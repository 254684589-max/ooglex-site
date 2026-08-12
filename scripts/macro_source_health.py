#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""宏观雷达三项官方序列的逐源运行健康契约。

``data.json`` 保存页面需要的最后有效观测，``health.json`` 单独保存最近一次
任务是否真正刷新了 DGS10、DTWEXBGS 与 RWTC。这样来源失败时可以继续展示
明确标记的旧值，同时不会把保留快照误认为本轮成功。
"""

from __future__ import annotations

from collections import Counter
from datetime import datetime
import json
import math
import os
from pathlib import Path
import re
from typing import Any


CONTRACT_VERSION = 1
DATASET = "macro-radar"
PIPELINE_STATUSES = ("healthy", "degraded", "failed")
ATTEMPT_STATUSES = ("success", "partial", "failed", "unknown")
SOURCE_STATUSES = ("healthy", "degraded", "failed", "unknown")
RWTC_ACCESS_METHODS = ("EIA API v2", "EIA public history page")
SOURCE_MODES = ("market", "fallback", "unavailable", "unknown")
HISTORY_STATUSES = ("tracked", "migrated")

SERIES_SPECS: dict[str, dict[str, Any]] = {
    "DGS10": {
        "name": "FRED DGS10",
        "provider": "FRED / Federal Reserve H.15",
        "url": "https://fred.stlouisfed.org/series/DGS10",
        "frequency": "daily",
        "maxBusinessDays": 3,
        "changeUnit": "bp",
    },
    "DTWEXBGS": {
        "name": "FRED DTWEXBGS",
        "provider": "FRED / Federal Reserve H.10",
        "url": "https://fred.stlouisfed.org/series/DTWEXBGS",
        "frequency": "daily",
        "maxBusinessDays": 3,
        "changeUnit": "percent",
    },
    "RWTC": {
        "name": "EIA RWTC",
        "provider": "U.S. EIA / Cushing WTI Spot",
        "url": "https://www.eia.gov/dnav/pet/hist/rwtcd.htm",
        "frequency": "daily",
        "maxBusinessDays": 4,
        "changeUnit": "percent",
    },
}

RECOVERY_STEPS = [
    {"id": "request-retry", "kind": "same-source-retry", "label": "各官方接口独立重试，不以另一标的替代"},
    {"id": "previous-observation", "kind": "previous-record", "label": "单一序列失败时保留其最后有效观测并标记回退"},
    {"id": "independent-health", "kind": "health-snapshot", "label": "数据快照与健康快照分开更新，持续记录真实失败"},
]


def _text(value: Any) -> str | None:
    return value.strip() if isinstance(value, str) and value.strip() else None


def _finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _valid_iso(value: Any) -> bool:
    if not _text(value):
        return False
    try:
        datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return True
    except (TypeError, ValueError):
        return False


def _valid_date(value: Any) -> bool:
    if not _text(value):
        return False
    try:
        datetime.strptime(str(value), "%Y-%m-%d")
        return True
    except (TypeError, ValueError):
        return False


def _parse_unit(value: Any, unit: str) -> float | None:
    match = re.fullmatch(r"\s*([+-]?\d+(?:\.\d+)?)\s*" + re.escape(unit) + r"\s*", str(value or ""), re.I)
    return float(match.group(1)) if match else None


def _find_dgs10(data: dict[str, Any]) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    for category in data.get("macro") or []:
        if not isinstance(category, dict):
            continue
        for row in category.get("rows") or []:
            if isinstance(row, dict) and row.get("id") == "DGS10":
                return category, row
    return None, None


def _published_dgs10(data: dict[str, Any]) -> dict[str, Any]:
    spec = SERIES_SPECS["DGS10"]
    category, row = _find_dgs10(data)
    errors: list[str] = []
    if not isinstance(category, dict) or not isinstance(row, dict):
        return {"id": "DGS10", "published": False, "recordStatus": "error", "errors": ["缺少DGS10记录"]}
    if str(category.get("src", "")).upper() != "FRED":
        errors.append("DGS10分类来源不是FRED")
    price = row.get("price") if _finite(row.get("price")) else _parse_unit(row.get("val"), "%")
    change = row.get("changeBps") if _finite(row.get("changeBps")) else _parse_unit(row.get("chg"), "bp")
    if not _finite(price) or price <= 0:
        errors.append("DGS10收益率无效")
    if not _finite(change):
        errors.append("DGS10基点变化无效")
    if not _valid_date(row.get("asOf")):
        errors.append("DGS10观测日期无效")
    updated_at = row.get("updatedAt") or data.get("updatedAt")
    if not _valid_iso(updated_at):
        errors.append("DGS10更新时间无效")
    source = row.get("source")
    if isinstance(source, dict) and (
        source.get("seriesId") != "DGS10" or "FRED" not in str(source.get("name", ""))
    ):
        errors.append("DGS10逐条来源无效")
    record_status = row.get("status") or "ok"
    if record_status not in ("ok", "stale", "error"):
        errors.append("DGS10状态无效")
    if record_status == "error":
        return {
            "id": "DGS10", "published": False, "recordStatus": "error",
            "asOf": None, "updatedAt": None, "lastAttemptAt": row.get("lastAttemptAt"),
            "errors": errors,
        }
    return {
        "id": "DGS10",
        "published": not errors,
        "recordStatus": record_status,
        "asOf": row.get("asOf"),
        "updatedAt": updated_at,
        "lastAttemptAt": row.get("lastAttemptAt") or updated_at,
        "price": price,
        "change": change,
        "errors": errors,
        "source": {"name": spec["provider"], "url": spec["url"], "seriesId": "DGS10"},
    }


def _published_reference(data: dict[str, Any], series_id: str) -> dict[str, Any]:
    spec = SERIES_SPECS[series_id]
    record = (data.get("referenceSeries") or {}).get(series_id)
    if not isinstance(record, dict):
        return {"id": series_id, "published": False, "recordStatus": "error", "errors": [f"缺少{series_id}记录"]}
    errors: list[str] = []
    source = record.get("source") or {}
    expected_provider = "FRED" if series_id == "DTWEXBGS" else "EIA"
    if record.get("id") != series_id or source.get("seriesId") != series_id:
        errors.append(f"{series_id}序列ID无效")
    if expected_provider not in str(source.get("name", "")):
        errors.append(f"{series_id}提供方无效")
    access_method = source.get("accessMethod") if series_id == "RWTC" else None
    if access_method is not None and access_method not in RWTC_ACCESS_METHODS:
        errors.append("RWTC实际访问路径无效")
    status = record.get("status")
    if status not in ("ok", "stale", "error"):
        errors.append(f"{series_id}状态无效")
    if status == "error":
        return {
            "id": series_id, "published": False, "recordStatus": "error",
            "asOf": None, "updatedAt": None, "lastAttemptAt": record.get("lastAttemptAt"),
            "errors": errors,
        }
    if not _finite(record.get("price")) or record.get("price") <= 0:
        errors.append(f"{series_id}当前值无效")
    if not _finite(record.get("previousPrice")) or record.get("previousPrice") <= 0:
        errors.append(f"{series_id}前值无效")
    if not _valid_date(record.get("asOf")) or not _valid_date(record.get("previousAsOf")):
        errors.append(f"{series_id}观测日期无效")
    elif record["previousAsOf"] >= record["asOf"]:
        errors.append(f"{series_id}前值日期必须早于当前日期")
    if not _valid_iso(record.get("updatedAt")) or not _valid_iso(record.get("lastAttemptAt")):
        errors.append(f"{series_id}尝试或成功时间无效")
    if _finite(record.get("price")) and _finite(record.get("previousPrice")):
        expected_change = (record["price"] / record["previousPrice"] - 1) * 100
        if not _finite(record.get("changePct")) or not math.isclose(
            record["changePct"], expected_change, rel_tol=0, abs_tol=1e-10
        ):
            errors.append(f"{series_id}涨跌幅不可复算")
    return {
        "id": series_id,
        "published": not errors,
        "recordStatus": status,
        "asOf": record.get("asOf"),
        "updatedAt": record.get("updatedAt"),
        "lastAttemptAt": record.get("lastAttemptAt"),
        "price": record.get("price"),
        "change": record.get("changePct"),
        "accessMethod": access_method,
        "errors": errors,
        "source": {"name": spec["provider"], "url": spec["url"], "seriesId": series_id},
    }


def published_series(data: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """把页面现有两种结构适配成三条可交叉校验的官方序列记录。"""
    if not isinstance(data, dict):
        return {series_id: {"id": series_id, "published": False, "recordStatus": "error", "errors": ["data.json必须为对象"]}
                for series_id in SERIES_SPECS}
    return {
        "DGS10": _published_dgs10(data),
        "DTWEXBGS": _published_reference(data, "DTWEXBGS"),
        "RWTC": _published_reference(data, "RWTC"),
    }


def _previous_source(previous_health: dict[str, Any] | None, series_id: str) -> dict[str, Any]:
    return next((source for source in (previous_health or {}).get("sources", [])
                 if isinstance(source, dict) and source.get("id") == series_id), {})


def _coverage(sources: list[dict[str, Any]]) -> dict[str, Any]:
    counts = Counter(source.get("mode") for source in sources if source.get("mode") in SOURCE_MODES)
    published = sum(source.get("published") is True for source in sources)
    expected = len(SERIES_SPECS)
    return {
        "expectedSeries": expected,
        "publishedSeries": published,
        "counts": {mode: counts[mode] for mode in SOURCE_MODES},
        "freshCoveragePct": round(counts["market"] / expected * 100, 2),
        "availableCoveragePct": round(published / expected * 100, 2),
    }


def make_macro_health(
    data: dict[str, Any],
    *,
    attempted_at: str,
    previous_health: dict[str, Any] | None = None,
    migrated: bool = False,
) -> dict[str, Any]:
    """从发布快照生成逐源健康；迁移模式不臆测此前任务结果。"""
    if not _valid_iso(attempted_at):
        raise ValueError("attempted_at必须是ISO 8601时间")
    observations = published_series(data)
    sources = []
    refreshed: list[str] = []
    failed: list[str] = []
    unknown: list[str] = []

    for series_id, spec in SERIES_SPECS.items():
        record = observations[series_id]
        previous = _previous_source(previous_health, series_id)
        if migrated:
            mode = "unknown"
            source_status = "unknown"
            consecutive = None
            snapshot_preserved = None
            failure_reason = None
            history_status = "migrated"
            last_attempt_at = record.get("lastAttemptAt") if _valid_iso(record.get("lastAttemptAt")) else attempted_at
            unknown.append(series_id)
        else:
            success = record.get("published") is True and record.get("recordStatus") == "ok" \
                and record.get("lastAttemptAt") == attempted_at
            if success:
                mode = "market"
                source_status = "healthy"
                consecutive = 0
                snapshot_preserved = False
                failure_reason = None
                refreshed.append(series_id)
            else:
                mode = "fallback" if record.get("published") is True else "unavailable"
                source_status = "degraded" if mode == "fallback" else "failed"
                previous_failures = previous.get("consecutiveFailures")
                consecutive = previous_failures + 1 if isinstance(previous_failures, int) else 1
                snapshot_preserved = mode == "fallback"
                detail = "; ".join(record.get("errors") or [])
                failure_reason = detail or f"{series_id}本轮官方接口未返回可发布的新观测。"
                failed.append(series_id)
            history_status = "tracked"
            last_attempt_at = attempted_at

        if mode == "market":
            last_successful_at = record.get("updatedAt") or attempted_at
        else:
            last_successful_at = previous.get("lastSuccessfulAt") or record.get("updatedAt")
        source_registration = {"name": spec["provider"], "url": spec["url"], "seriesId": series_id}
        if series_id == "RWTC" and record.get("accessMethod") in RWTC_ACCESS_METHODS:
            source_registration["accessMethod"] = record["accessMethod"]
        sources.append({
            "id": series_id,
            "name": spec["name"],
            "provider": spec["provider"],
            "role": "primary",
            "status": source_status,
            "mode": mode,
            "historyStatus": history_status,
            "frequency": spec["frequency"],
            "maxBusinessDays": spec["maxBusinessDays"],
            "changeUnit": spec["changeUnit"],
            "published": record.get("published") is True,
            "asOf": record.get("asOf") if record.get("published") else None,
            "publishedUpdatedAt": record.get("updatedAt") if record.get("published") else None,
            "lastAttemptAt": last_attempt_at,
            "lastSuccessfulAt": last_successful_at,
            "consecutiveFailures": consecutive,
            "snapshotPreserved": snapshot_preserved,
            "failureReason": failure_reason,
            "source": source_registration,
        })

    coverage = _coverage(sources)
    if migrated:
        attempt_status = "unknown"
        pipeline_status = "degraded"
        history_status = "migrated"
        consecutive_failures = None
        snapshot_preserved = None
        failure_reason = None
    else:
        attempt_status = "success" if len(refreshed) == len(SERIES_SPECS) else "partial" if refreshed else "failed"
        pipeline_status = "healthy" if attempt_status == "success" else "degraded" if refreshed else "failed"
        history_status = "tracked"
        previous_failures = (previous_health or {}).get("consecutiveFailures")
        consecutive_failures = 0 if refreshed else (previous_failures + 1 if isinstance(previous_failures, int) else 1)
        snapshot_preserved = bool(not refreshed and coverage["publishedSeries"])
        failure_reason = "三项官方序列本轮均未刷新，已按逐源规则保留可验证旧值。" if not refreshed else None

    known_successes = [source.get("lastSuccessfulAt") for source in sources if _valid_iso(source.get("lastSuccessfulAt"))]
    previous_success = (previous_health or {}).get("lastSuccessfulAt")
    if refreshed:
        last_successful_at = attempted_at
    elif _valid_iso(previous_success):
        last_successful_at = previous_success
    else:
        last_successful_at = max(known_successes) if known_successes else None

    return {
        "contractVersion": CONTRACT_VERSION,
        "dataset": DATASET,
        "generatedAt": attempted_at,
        "status": pipeline_status,
        "historyStatus": history_status,
        "lastAttemptAt": attempted_at,
        "lastSuccessfulAt": last_successful_at,
        "consecutiveFailures": consecutive_failures,
        "publishedSnapshotAt": data.get("updatedAt"),
        "snapshotPreserved": snapshot_preserved,
        "failureReason": failure_reason,
        "coverage": coverage,
        "attempt": {
            "status": attempt_status,
            "refreshedSeries": refreshed,
            "failedSeries": failed,
            "unknownSeries": unknown,
        },
        "sources": sources,
        "recovery": {
            "preservesLastValidSnapshot": True,
            "steps": [dict(step) for step in RECOVERY_STEPS],
        },
    }


def validate_macro_health(health: dict[str, Any], data: dict[str, Any]) -> list[str]:
    """交叉复算健康文件与宏观雷达当前发布快照。"""
    errors: list[str] = []
    if not isinstance(health, dict):
        return ["健康文件必须为JSON对象"]
    if health.get("contractVersion") != CONTRACT_VERSION:
        errors.append("contractVersion无效")
    if health.get("dataset") != DATASET:
        errors.append("dataset无效")
    if health.get("status") not in PIPELINE_STATUSES:
        errors.append("status无效")
    if health.get("historyStatus") not in HISTORY_STATUSES:
        errors.append("historyStatus无效")
    for key in ("generatedAt", "lastAttemptAt"):
        if not _valid_iso(health.get(key)):
            errors.append(f"{key}格式无效")
    if health.get("generatedAt") != health.get("lastAttemptAt"):
        errors.append("generatedAt必须等于最近尝试时间")
    if health.get("lastSuccessfulAt") is not None and not _valid_iso(health.get("lastSuccessfulAt")):
        errors.append("lastSuccessfulAt格式无效")
    if health.get("publishedSnapshotAt") != data.get("updatedAt"):
        errors.append("publishedSnapshotAt与data.json更新时间不一致")

    observations = published_series(data)
    for series_id, record in observations.items():
        if record.get("errors"):
            errors.extend(record["errors"])

    sources = health.get("sources")
    expected_ids = list(SERIES_SPECS)
    if not isinstance(sources, list) or [source.get("id") for source in sources if isinstance(source, dict)] != expected_ids:
        errors.append("sources缺失、顺序错误或ID无效")
        sources = []
    else:
        for source in sources:
            series_id = source["id"]
            spec = SERIES_SPECS[series_id]
            record = observations[series_id]
            if source.get("provider") != spec["provider"] or source.get("role") != "primary":
                errors.append(f"{series_id}提供方或角色无效")
            if source.get("status") not in SOURCE_STATUSES or source.get("mode") not in SOURCE_MODES:
                errors.append(f"{series_id}状态或模式无效")
            if source.get("historyStatus") not in HISTORY_STATUSES:
                errors.append(f"{series_id}历史状态无效")
            if source.get("frequency") != spec["frequency"] or source.get("maxBusinessDays") != spec["maxBusinessDays"]:
                errors.append(f"{series_id}频率或过期阈值无效")
            if source.get("changeUnit") != spec["changeUnit"]:
                errors.append(f"{series_id}变化单位无效")
            expected_source = {"name": spec["provider"], "url": spec["url"], "seriesId": series_id}
            if series_id == "RWTC" and record.get("accessMethod") in RWTC_ACCESS_METHODS:
                expected_source["accessMethod"] = record["accessMethod"]
            if source.get("source") != expected_source:
                errors.append(f"{series_id}来源登记无效")
            if source.get("published") is not (record.get("published") is True):
                errors.append(f"{series_id}发布状态与data.json不一致")
            expected_as_of = record.get("asOf") if record.get("published") else None
            expected_updated = record.get("updatedAt") if record.get("published") else None
            if source.get("asOf") != expected_as_of or source.get("publishedUpdatedAt") != expected_updated:
                errors.append(f"{series_id}观测或更新时间与data.json不一致")
            if not _valid_iso(source.get("lastAttemptAt")):
                errors.append(f"{series_id}最后尝试时间无效")
            if source.get("lastSuccessfulAt") is not None and not _valid_iso(source.get("lastSuccessfulAt")):
                errors.append(f"{series_id}最后成功时间无效")

            if health.get("historyStatus") == "migrated":
                if source.get("historyStatus") != "migrated" or source.get("mode") != "unknown" \
                        or source.get("status") != "unknown" or source.get("consecutiveFailures") is not None \
                        or source.get("snapshotPreserved") is not None or source.get("failureReason") is not None:
                    errors.append(f"{series_id}迁移状态不得推断历史任务结果")
            else:
                if source.get("historyStatus") != "tracked":
                    errors.append(f"{series_id}真实运行后必须标记tracked")
                if source.get("lastAttemptAt") != health.get("lastAttemptAt"):
                    errors.append(f"{series_id}最近尝试时间与管道不一致")
                failures = source.get("consecutiveFailures")
                if not isinstance(failures, int) or failures < 0:
                    errors.append(f"{series_id}连续失败次数无效")
                if source.get("mode") == "market":
                    if source.get("status") != "healthy" or failures != 0 \
                            or source.get("snapshotPreserved") is not False or source.get("failureReason") is not None \
                            or record.get("recordStatus") != "ok":
                        errors.append(f"{series_id}本轮成功语义不一致")
                elif source.get("mode") == "fallback":
                    if source.get("status") != "degraded" or not isinstance(failures, int) or failures < 1 \
                            or source.get("snapshotPreserved") is not True or not _text(source.get("failureReason")) \
                            or record.get("published") is not True:
                        errors.append(f"{series_id}回退语义不一致")
                elif source.get("mode") == "unavailable":
                    if source.get("status") != "failed" or not isinstance(failures, int) or failures < 1 \
                            or source.get("snapshotPreserved") is not False or not _text(source.get("failureReason")) \
                            or record.get("published") is True:
                        errors.append(f"{series_id}不可用语义不一致")
                else:
                    errors.append(f"{series_id}tracked状态不得使用unknown模式")

    if sources and health.get("coverage") != _coverage(sources):
        errors.append("coverage不可由逐源状态复算")
    attempt = health.get("attempt")
    if not isinstance(attempt, dict) or attempt.get("status") not in ATTEMPT_STATUSES:
        errors.append("attempt无效")
    elif sources:
        refreshed = [source["id"] for source in sources if source.get("mode") == "market"]
        failed = [source["id"] for source in sources if source.get("mode") in ("fallback", "unavailable")]
        unknown = [source["id"] for source in sources if source.get("mode") == "unknown"]
        expected_status = "unknown" if unknown else "success" if len(refreshed) == len(SERIES_SPECS) \
            else "partial" if refreshed else "failed"
        if attempt != {"status": expected_status, "refreshedSeries": refreshed,
                       "failedSeries": failed, "unknownSeries": unknown}:
            errors.append("attempt不可由逐源模式复算")

        expected_pipeline = "degraded" if unknown else "healthy" if len(refreshed) == len(SERIES_SPECS) \
            else "degraded" if refreshed else "failed"
        if health.get("status") != expected_pipeline:
            errors.append("管道状态不可由逐源模式复算")
        if health.get("historyStatus") == "migrated":
            if health.get("consecutiveFailures") is not None or health.get("snapshotPreserved") is not None \
                    or health.get("failureReason") is not None:
                errors.append("迁移快照不得推断整批失败历史")
        else:
            failures = health.get("consecutiveFailures")
            if not isinstance(failures, int) or failures < 0:
                errors.append("管道连续失败次数无效")
            if refreshed and (failures != 0 or health.get("snapshotPreserved") is not False):
                errors.append("部分或全部成功时管道失败状态未归零")
            if not refreshed and (not isinstance(failures, int) or failures < 1
                                  or health.get("snapshotPreserved") is not bool(health["coverage"]["publishedSeries"])
                                  or not _text(health.get("failureReason"))):
                errors.append("整批失败语义不一致")

    recovery = health.get("recovery")
    if not isinstance(recovery, dict) or recovery.get("preservesLastValidSnapshot") is not True \
            or recovery.get("steps") != RECOVERY_STEPS:
        errors.append("recovery与登记顺序不一致")
    return errors


def load_json(path: str | os.PathLike[str]) -> dict[str, Any] | None:
    try:
        with open(path, encoding="utf-8") as file:
            value = json.load(file)
        return value if isinstance(value, dict) else None
    except (OSError, ValueError):
        return None


def write_macro_health(path: str | os.PathLike[str], health: dict[str, Any]) -> None:
    """原子替换健康文件，避免任务中断留下半份JSON。"""
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".tmp")
    temporary.write_text(json.dumps(health, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, target)
