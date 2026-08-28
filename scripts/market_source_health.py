#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""三条聚合行情管道共用的来源健康与恢复契约。

健康文件与 ``data.json`` 分开保存：取数整批失败时，最后有效数据快照保持不变，
但 ``health.json`` 仍会记录本轮失败、连续失败次数和实际恢复顺序。这样前端不会
把保留快照误认为本轮成功，质量工作流也能在不调用外部接口的情况下复核状态。
"""

from __future__ import annotations

from collections import Counter
from datetime import datetime
import json
import os
from pathlib import Path
from typing import Any

from market_data_quality import DATA_MODES, summarize_data_quality


HEALTH_CONTRACT_VERSION = 1
PIPELINE_STATUSES = ("healthy", "degraded", "failed")
ATTEMPT_STATUSES = ("success", "failed", "unknown")
HISTORY_STATUSES = ("tracked", "migrated")
SOURCE_ROLES = ("primary", "secondary", "reference", "upstream")
SOURCE_STATUSES = ("healthy", "degraded", "failed", "unknown")

DATASET_SPECS: dict[str, dict[str, Any]] = {
    "asset-tracker": {
        # 与 scripts/asset-tracker/build_assets.py 的 ASSETS 清单条数保持一致：写入健康文件时
        # 始终用这个现行值。清单扩容当天仓库里还留着上一次任务按旧条数写的健康文件，
        # 因此校验时额外接受 expectedRecordOptions 里已登记的历史值；扩容后的第一份
        # 健康文件发布后即可把该列表收回单值。
        "expectedRecords": 103,
        "expectedRecordOptions": (56, 98, 103, 104),
        "sources": [
            {
                "id": "yahoo-finance",
                "name": "Yahoo Finance",
                "role": "primary",
                "matches": ["Yahoo Finance"],
                "recordModes": ["market", "fallback", "unknown", "unavailable"],
                "successModes": ["market"],
            },
        ],
        "recovery": [
            {"id": "yahoo-mirror", "kind": "mirror", "label": "切换Yahoo Finance备用域名query2"},
            {"id": "alternate-symbol", "kind": "alternate-symbol", "label": "按标的使用已登记候选代码或明确代理"},
            {"id": "previous-record", "kind": "previous-record", "label": "单项失败时沿用上一份逐条有效值"},
            {"id": "previous-snapshot", "kind": "previous-snapshot", "label": "整源失败时保留上一份完整data.json"},
        ],
    },
    "companies": {
        "expectedRecords": 500,
        "sources": [
            {
                "id": "yahoo-finance",
                "name": "Yahoo Finance",
                "role": "primary",
                "matches": ["Yahoo Finance"],
                "recordModes": ["market", "fallback", "unknown", "unavailable"],
                "successModes": ["market"],
            },
            {
                "id": "multiples-vc",
                "name": "multiples.vc公开融资估值汇总",
                "role": "reference",
                "matches": ["multiples.vc"],
                "recordModes": ["estimate"],
                "successModes": ["estimate"],
                "successStatuses": ["ok", "partial"],
            },
        ],
        "recovery": [
            {"id": "yahoo-mirror", "kind": "mirror", "label": "切换Yahoo Finance备用域名query2"},
            {"id": "static-fx", "kind": "static-baseline", "label": "KRW换汇失败时使用已披露静态汇率并降级"},
            {"id": "previous-record", "kind": "previous-record", "label": "单家公司失败时沿用上一份逐条有效值"},
            {"id": "previous-snapshot", "kind": "previous-snapshot", "label": "有效报价低于50%或体检失败时保留完整旧快照"},
        ],
    },
    "asset-ranking": {
        "expectedRecords": 250,
        "sources": [
            {
                "id": "yahoo-finance",
                "name": "Yahoo Finance",
                "role": "primary",
                "matches": ["Yahoo Finance"],
                "recordModes": ["market", "fallback", "unknown", "unavailable"],
                "successModes": ["market"],
                "partialSuccessMatches": ["公开存量基准", "世界黄金协会"],
            },
            {
                "id": "coingecko",
                "name": "CoinGecko",
                "role": "primary",
                "matches": ["CoinGecko"],
                "recordModes": ["market", "fallback", "unknown", "unavailable"],
                "successModes": ["market"],
            },
            {
                "id": "companies-upstream",
                "name": "companies/data.json上游快照",
                "role": "upstream",
                "categories": ["company"],
                "successModes": ["market", "estimate"],
                "successStatuses": ["ok", "partial"],
            },
            {
                "id": "public-estimates",
                "name": "公开存量与融资估值",
                "role": "reference",
                "matches": ["Savills", "IMF", "世界黄金协会", "公开存量基准", "multiples.vc", "静态加密市值基准"],
                "recordModes": ["estimate"],
                "successModes": ["estimate"],
                "successStatuses": ["ok", "partial"],
            },
        ],
        "recovery": [
            {"id": "yahoo-mirror", "kind": "mirror", "label": "Yahoo行情切换备用域名query2"},
            {"id": "crypto-yahoo", "kind": "secondary-source", "label": "CoinGecko失败时以Yahoo价格×已披露静态流通量兜底"},
            {"id": "upstream-company", "kind": "upstream-snapshot", "label": "公司条目复用已校验的companies快照与健康状态"},
            {"id": "previous-or-baseline", "kind": "previous-snapshot", "label": "单项沿用旧值或静态基准；整榜体检失败时保留旧快照"},
        ],
    },
}


def _text(value: Any) -> str | None:
    return value.strip() if isinstance(value, str) and value.strip() else None


def _valid_iso(value: Any) -> bool:
    if not isinstance(value, str) or not value:
        return False
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
        return True
    except (TypeError, ValueError):
        return False


def _percent(numerator: int, denominator: int) -> float:
    return round(numerator / denominator * 100, 2) if denominator > 0 else 0.0


def _dynamic_records(dataset: str, rows: list[dict[str, Any]]) -> int:
    if dataset == "asset-tracker":
        return len(rows)
    if dataset == "companies":
        return sum(row.get("private") is not True for row in rows if isinstance(row, dict))
    if dataset == "asset-ranking":
        return sum(
            row.get("static") is not True and row.get("private") is not True
            for row in rows
            if isinstance(row, dict)
        )
    raise ValueError(f"未知数据集：{dataset}")


def _row_is_dynamic(dataset: str, row: dict[str, Any]) -> bool:
    if dataset == "asset-tracker":
        return True
    if dataset == "companies":
        return row.get("private") is not True
    if dataset == "asset-ranking":
        return row.get("static") is not True and row.get("private") is not True
    raise ValueError(f"未知数据集：{dataset}")


def _dynamic_market_success(dataset: str, meta: dict[str, Any]) -> bool:
    if meta.get("mode") != "market":
        return False
    if meta.get("status") == "ok":
        return True
    source = str(meta.get("source") or "")
    return bool(
        dataset == "asset-ranking" and meta.get("status") == "partial"
        and any(token in source for token in ("公开存量基准", "世界黄金协会"))
    )


def _snapshot_is_healthy(dataset: str, rows: list[dict[str, Any]]) -> bool:
    """区分动态行情失败与已披露慢频估值，不把两者混成同一种降级。"""
    if len(rows) != DATASET_SPECS[dataset]["expectedRecords"]:
        return False
    slow_frequencies = {"weekly", "monthly", "quarterly", "annual", "irregular"}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("dataMeta"), dict):
            return False
        meta = row["dataMeta"]
        if _row_is_dynamic(dataset, row):
            if not _dynamic_market_success(dataset, meta):
                return False
        elif meta.get("mode") != "estimate" or meta.get("status") not in {"ok", "partial"} \
                or meta.get("frequency") not in slow_frequencies:
            return False
    return True


def _coverage(dataset: str, rows: list[dict[str, Any]],
              expected: int | None = None) -> dict[str, Any]:
    if expected is None:
        expected = DATASET_SPECS[dataset]["expectedRecords"]
    quality = summarize_data_quality(rows)
    counts = quality["counts"]
    dynamic = _dynamic_records(dataset, rows)
    verified = counts["market"] + counts["fallback"] + counts["estimate"]
    available = len(rows) - counts["unavailable"]
    return {
        "expectedRecords": expected,
        "publishedRecords": len(rows),
        "dynamicRecords": dynamic,
        "counts": dict(counts),
        "publishedCoveragePct": _percent(len(rows), expected),
        "freshCoveragePct": _percent(counts["market"], dynamic),
        "verifiedCoveragePct": _percent(verified, expected),
        "availableCoveragePct": _percent(available, expected),
    }


def _source_observations(dataset: str, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    observations = []
    for source in DATASET_SPECS[dataset]["sources"]:
        matched = []
        for row in rows:
            meta = row.get("dataMeta") if isinstance(row, dict) else None
            source_name = _text((meta or {}).get("source")) if isinstance(meta, dict) else None
            category_match = not source.get("categories") or row.get("category") in source["categories"]
            source_match = not source.get("matches") or (
                source_name and any(token in source_name for token in source["matches"])
            )
            mode_match = not source.get("recordModes") or (meta or {}).get("mode") in source["recordModes"]
            if isinstance(meta, dict) and category_match and source_match and mode_match:
                matched.append(meta)
        counts = Counter(meta.get("mode") for meta in matched if meta.get("mode") in DATA_MODES)
        last_successes = [
            meta.get("updatedAt") for meta in matched
            if meta.get("mode") in source["successModes"] and _valid_iso(meta.get("updatedAt"))
        ]
        if not matched or all(meta.get("mode") == "unknown" for meta in matched):
            status = "unknown"
        elif all(meta.get("mode") == "unavailable" for meta in matched):
            status = "failed"
        elif any(
            meta.get("mode") not in source["successModes"]
            or (
                meta.get("status") not in source.get("successStatuses", ["ok"])
                and not (
                    meta.get("status") == "partial"
                    and any(token in str(meta.get("source") or "")
                            for token in source.get("partialSuccessMatches", []))
                )
            )
            for meta in matched
        ):
            status = "degraded"
        else:
            status = "healthy"
        observations.append({
            "id": source["id"],
            "name": source["name"],
            "role": source["role"],
            "status": status,
            "records": len(matched),
            "counts": {mode: counts[mode] for mode in DATA_MODES},
            "lastSuccessAt": max(last_successes) if last_successes else None,
        })
    return observations


def make_source_health(
    dataset: str,
    *,
    published_rows: list[dict[str, Any]],
    attempted_rows: list[dict[str, Any]],
    attempted_at: str,
    published_snapshot_at: str | None,
    published: bool,
    previous_health: dict[str, Any] | None = None,
    failure_reason: str | None = None,
    migrated: bool = False,
) -> dict[str, Any]:
    """生成健康快照；失败时覆盖的是健康文件，不是最后有效行情文件。"""
    if dataset not in DATASET_SPECS:
        raise ValueError(f"未知数据集：{dataset}")
    if not _valid_iso(attempted_at):
        raise ValueError("attempted_at必须是ISO 8601时间")
    if published_snapshot_at is not None and not _valid_iso(published_snapshot_at):
        raise ValueError("published_snapshot_at必须是ISO 8601时间或None")
    if published and failure_reason:
        raise ValueError("成功发布不得包含failure_reason")
    if not published and not _text(failure_reason):
        raise ValueError("未发布健康报告必须包含failure_reason")

    coverage = _coverage(dataset, published_rows)
    attempt_quality = summarize_data_quality(attempted_rows)
    if migrated:
        attempt_status = "unknown"
        consecutive_failures = None
        history_status = "migrated"
    else:
        attempt_status = "success" if published else "failed"
        previous_failures = (previous_health or {}).get("consecutiveFailures")
        consecutive_failures = 0 if published else (previous_failures + 1 if isinstance(previous_failures, int) else 1)
        history_status = "tracked"

    if published:
        last_successful_at = published_snapshot_at or attempted_at
    else:
        last_successful_at = _text((previous_health or {}).get("lastSuccessfulAt")) or published_snapshot_at

    if not published:
        pipeline_status = "failed"
    elif _snapshot_is_healthy(dataset, published_rows):
        pipeline_status = "healthy"
    else:
        pipeline_status = "degraded"

    snapshot_preserved = bool(
        not published
        and published_rows
        and published_snapshot_at is not None
    )

    return {
        "contractVersion": HEALTH_CONTRACT_VERSION,
        "dataset": dataset,
        "generatedAt": attempted_at,
        "status": pipeline_status,
        "historyStatus": history_status,
        "lastAttemptAt": attempted_at,
        "lastSuccessfulAt": last_successful_at,
        "consecutiveFailures": consecutive_failures,
        "publishedSnapshotAt": published_snapshot_at,
        "snapshotPreserved": snapshot_preserved,
        "failureReason": _text(failure_reason),
        "coverage": coverage,
        "attempt": {
            "status": attempt_status,
            "published": published,
            "producedRecords": len(attempted_rows),
            "counts": dict(attempt_quality["counts"]),
        },
        "sources": _source_observations(dataset, attempted_rows),
        "recovery": {
            "preservesLastValidSnapshot": True,
            "steps": [dict(step) for step in DATASET_SPECS[dataset]["recovery"]],
        },
    }


def attach_upstream_health(
    health: dict[str, Any],
    *,
    source_id: str,
    upstream_dataset: str,
    upstream_health: dict[str, Any] | None,
    upstream_snapshot_at: str | None,
) -> dict[str, Any]:
    """把依赖管道的最近尝试状态附到来源观察，不改写其逐条覆盖计数。"""
    source = next((item for item in health.get("sources", []) if item.get("id") == source_id), None)
    if source is None:
        raise ValueError(f"未登记上游来源：{source_id}")
    contract_known = bool(
        isinstance(upstream_health, dict)
        and upstream_health.get("contractVersion") == HEALTH_CONTRACT_VERSION
        and upstream_health.get("dataset") == upstream_dataset
        and upstream_health.get("status") in PIPELINE_STATUSES
        and upstream_health.get("publishedSnapshotAt") == upstream_snapshot_at
    )
    upstream_status = upstream_health.get("status") if contract_known else "unknown"
    source["upstream"] = {
        "dataset": upstream_dataset,
        "contractKnown": contract_known,
        "status": upstream_status,
        "lastAttemptAt": upstream_health.get("lastAttemptAt") if contract_known else None,
        "lastSuccessfulAt": upstream_health.get("lastSuccessfulAt") if contract_known else None,
        "consecutiveFailures": upstream_health.get("consecutiveFailures") if contract_known else None,
        "snapshotPreserved": upstream_health.get("snapshotPreserved") if contract_known else None,
        "snapshotAligned": contract_known,
    }
    severity = {"healthy": 0, "unknown": 1, "degraded": 1, "failed": 2}
    if severity[upstream_status] > severity[source["status"]]:
        source["status"] = upstream_status
    if contract_known and _valid_iso(upstream_health.get("lastSuccessfulAt")):
        source["lastSuccessAt"] = upstream_health["lastSuccessfulAt"]
    if health.get("status") == "healthy" and source["status"] != "healthy":
        health["status"] = "degraded"
    return health


def validate_source_health(
    health: dict[str, Any],
    *,
    dataset: str,
    published_rows: list[dict[str, Any]],
    published_snapshot_at: str | None,
) -> list[str]:
    """校验健康文件与当前发布快照的交叉一致性。"""
    errors: list[str] = []
    if not isinstance(health, dict):
        return ["健康文件必须是JSON对象"]
    if dataset not in DATASET_SPECS:
        return [f"未知数据集：{dataset}"]
    if health.get("contractVersion") != HEALTH_CONTRACT_VERSION:
        errors.append("contractVersion无效")
    if health.get("dataset") != dataset:
        errors.append("dataset与文件路径不一致")
    if health.get("status") not in PIPELINE_STATUSES:
        errors.append("status无效")
    if health.get("historyStatus") not in HISTORY_STATUSES:
        errors.append("historyStatus无效")
    for key in ("generatedAt", "lastAttemptAt"):
        if not _valid_iso(health.get(key)):
            errors.append(f"{key}格式无效")
    if health.get("lastSuccessfulAt") is not None and not _valid_iso(health.get("lastSuccessfulAt")):
        errors.append("lastSuccessfulAt格式无效")
    if health.get("publishedSnapshotAt") != published_snapshot_at:
        errors.append("publishedSnapshotAt与data.json更新时间不一致")
    expected_snapshot_preserved = bool(
        health.get("status") == "failed"
        and published_rows
        and published_snapshot_at is not None
    )
    if health.get("snapshotPreserved") is not expected_snapshot_preserved:
        errors.append("snapshotPreserved与管道状态不一致")
    if health.get("status") == "failed" and not _text(health.get("failureReason")):
        errors.append("失败状态缺少failureReason")
    if health.get("status") != "failed" and health.get("failureReason") is not None:
        errors.append("非失败状态不得包含failureReason")

    consecutive = health.get("consecutiveFailures")
    if health.get("historyStatus") == "migrated":
        if consecutive is not None:
            errors.append("迁移快照的历史连续失败次数必须为null")
    elif not isinstance(consecutive, int) or consecutive < 0:
        errors.append("tracked快照的consecutiveFailures必须为非负整数")
    if health.get("status") == "failed" and isinstance(consecutive, int) and consecutive < 1:
        errors.append("失败状态的连续失败次数必须至少为1")

    declared_expected = (health.get("coverage") or {}).get("expectedRecords")
    accepted_expected = DATASET_SPECS[dataset].get(
        "expectedRecordOptions", (DATASET_SPECS[dataset]["expectedRecords"],))
    expected_coverage = _coverage(
        dataset, published_rows,
        declared_expected if declared_expected in accepted_expected else None)
    if health.get("coverage") != expected_coverage:
        errors.append("coverage不可由当前data.json逐条状态复算")

    attempt = health.get("attempt")
    if not isinstance(attempt, dict):
        errors.append("缺少attempt")
    else:
        if attempt.get("status") not in ATTEMPT_STATUSES:
            errors.append("attempt.status无效")
        if not isinstance(attempt.get("published"), bool):
            errors.append("attempt.published必须为布尔值")
        if not isinstance(attempt.get("producedRecords"), int) or attempt.get("producedRecords") < 0:
            errors.append("attempt.producedRecords无效")
        counts = attempt.get("counts")
        if not isinstance(counts, dict) or set(counts) != set(DATA_MODES) \
                or any(not isinstance(counts.get(mode), int) or counts[mode] < 0 for mode in DATA_MODES):
            errors.append("attempt.counts无效")
        elif sum(counts.values()) != attempt.get("producedRecords"):
            errors.append("attempt.counts合计与producedRecords不一致")
        if attempt.get("published") is not (health.get("status") != "failed"):
            errors.append("attempt.published与管道状态不一致")
        if health.get("historyStatus") == "migrated" and attempt.get("status") != "unknown":
            errors.append("迁移快照的attempt.status必须为unknown")
        if health.get("historyStatus") == "tracked" \
                and attempt.get("status") != ("failed" if health.get("status") == "failed" else "success"):
            errors.append("tracked快照的attempt.status与管道状态不一致")

    sources = health.get("sources")
    source_specs = DATASET_SPECS[dataset]["sources"]
    if not isinstance(sources, list) or [item.get("id") for item in sources if isinstance(item, dict)] \
            != [item["id"] for item in source_specs]:
        errors.append("sources缺失、顺序错误或ID未登记")
    else:
        for source in sources:
            if source.get("role") not in SOURCE_ROLES or source.get("status") not in SOURCE_STATUSES:
                errors.append(f"来源{source.get('id')}的role或status无效")
            counts = source.get("counts")
            if not isinstance(source.get("records"), int) or source["records"] < 0:
                errors.append(f"来源{source.get('id')}的records无效")
            if not isinstance(counts, dict) or set(counts) != set(DATA_MODES) \
                    or sum(counts.values()) != source.get("records"):
                errors.append(f"来源{source.get('id')}的counts无效")
            if source.get("lastSuccessAt") is not None and not _valid_iso(source.get("lastSuccessAt")):
                errors.append(f"来源{source.get('id')}的lastSuccessAt无效")
            upstream = source.get("upstream")
            if upstream is not None:
                if not isinstance(upstream, dict) or upstream.get("dataset") not in DATASET_SPECS \
                        or upstream.get("status") not in (*PIPELINE_STATUSES, "unknown") \
                        or not isinstance(upstream.get("contractKnown"), bool) \
                        or not isinstance(upstream.get("snapshotAligned"), bool):
                    errors.append(f"来源{source.get('id')}的upstream无效")
                elif upstream.get("contractKnown"):
                    if upstream.get("snapshotAligned") is not True:
                        errors.append(f"来源{source.get('id')}的上游快照未对齐")
                    if not _valid_iso(upstream.get("lastAttemptAt")):
                        errors.append(f"来源{source.get('id')}的上游尝试时间无效")
                    if upstream.get("lastSuccessfulAt") is not None \
                            and not _valid_iso(upstream.get("lastSuccessfulAt")):
                        errors.append(f"来源{source.get('id')}的上游成功时间无效")
                    failures = upstream.get("consecutiveFailures")
                    if failures is not None and (not isinstance(failures, int) or failures < 0):
                        errors.append(f"来源{source.get('id')}的上游连续失败次数无效")
                    if not isinstance(upstream.get("snapshotPreserved"), bool):
                        errors.append(f"来源{source.get('id')}的上游快照状态无效")
    if dataset == "asset-ranking":
        upstream_source = next((item for item in (sources or []) if item.get("id") == "companies-upstream"), {})
        if not isinstance(upstream_source.get("upstream"), dict):
            errors.append("asset-ranking缺少companies健康透传")
    if health.get("status") == "healthy" and any(
        source.get("role") in ("primary", "upstream") and source.get("status") != "healthy"
        for source in (sources or []) if isinstance(source, dict)
    ):
        errors.append("主要或上游来源异常时管道不得标记healthy")

    recovery = health.get("recovery")
    expected_steps = DATASET_SPECS[dataset]["recovery"]
    if not isinstance(recovery, dict) or recovery.get("preservesLastValidSnapshot") is not True \
            or recovery.get("steps") != expected_steps:
        errors.append("recovery与已登记恢复顺序不一致")
    return errors


def load_json(path: str | os.PathLike[str]) -> dict[str, Any] | None:
    try:
        with open(path, encoding="utf-8") as file:
            data = json.load(file)
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def write_health(path: str | os.PathLike[str], health: dict[str, Any]) -> None:
    """原子替换健康文件，避免任务中断留下半份JSON。"""
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".tmp")
    temporary.write_text(json.dumps(health, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, target)
