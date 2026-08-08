#!/usr/bin/env python3
"""四条金融终端辅助信息源共用的运行健康契约。

``data.json`` 继续保存最后一份可展示内容；``health.json`` 单独记录最近一次
自动任务是否真正刷新了来源。这样抓取失败时可以保留旧快照，同时让页面和质量
检查明确区分“内容仍可读”与“更新链正常”。
"""

from __future__ import annotations

from datetime import datetime
import json
import math
import os
from pathlib import Path
from typing import Any, Mapping


CONTRACT_VERSION = 1
DATASET_STATUSES = ("healthy", "degraded", "failed", "unknown")
HISTORY_STATUSES = ("tracked", "migrated")
ATTEMPT_STATUSES = ("success", "partial", "failed", "unknown")
COMPONENT_MODES = ("fresh", "fallback", "unavailable", "unknown")
COMPONENT_STATUSES = ("healthy", "degraded", "failed", "unknown")

FEED_SPECS: dict[str, dict[str, Any]] = {
    "fear-greed": {
        "source": "CNN Business Fear & Greed Index",
        "maxReportAgeHours": 72,
        "components": [
            {
                "id": "cnn-index",
                "name": "CNN Fear & Greed Index",
                "role": "primary",
                "frequency": "daily",
                "requiredForTerminal": True,
            },
        ],
        "recovery": [
            {"id": "same-source-retry", "kind": "retry", "label": "重试同一CNN公开接口"},
            {"id": "previous-snapshot", "kind": "previous-snapshot", "label": "失败时保留上一份完整指数快照"},
        ],
    },
    "ofr-monitor": {
        "source": "U.S. Office of Financial Research (OFR)",
        "maxReportAgeHours": 72,
        "components": [
            {"id": "fsi", "name": "OFR Financial Stress Index", "role": "primary", "frequency": "daily", "requiredForTerminal": True},
            {"id": "funding", "name": "OFR Short-term Funding", "role": "primary", "frequency": "daily", "requiredForTerminal": False},
            {"id": "mmf", "name": "OFR Money Market Funds", "role": "primary", "frequency": "monthly", "requiredForTerminal": False},
            {"id": "hedge", "name": "OFR Hedge Fund Monitor", "role": "primary", "frequency": "quarterly", "requiredForTerminal": False},
            {"id": "bank", "name": "Federal Reserve U.S. G-SIB Surcharges", "role": "reference", "frequency": "annual", "requiredForTerminal": False},
        ],
        "recovery": [
            {"id": "component-isolation", "kind": "partial-publish", "label": "五项组件独立刷新，单项失败不拖累其余组件"},
            {"id": "previous-component", "kind": "previous-record", "label": "单项失败时沿用上一份同组件有效值"},
            {"id": "previous-snapshot", "kind": "previous-snapshot", "label": "全部动态来源失败时保留完整旧快照"},
        ],
    },
    "econ-calendar": {
        "source": "Forex Factory 经济日历",
        "maxReportAgeHours": 36,
        "components": [
            {
                "id": "weekly-calendar",
                "name": "Forex Factory Weekly Calendar",
                "role": "primary",
                "frequency": "daily",
                "requiredForTerminal": True,
            },
        ],
        "recovery": [
            {"id": "same-source-retry", "kind": "retry", "label": "重试同一公开周历接口"},
            {"id": "previous-snapshot", "kind": "previous-snapshot", "label": "失败或空周历时保留上一份完整事件快照"},
        ],
    },
    "whats-latest": {
        "source": "Google News · Yahoo Finance",
        "maxReportAgeHours": 12,
        "components": [
            {"id": "markets-news", "name": "Google News 市场", "role": "primary", "frequency": "intraday", "requiredForTerminal": True},
            {"id": "tech-news", "name": "Google News 科技", "role": "secondary", "frequency": "intraday", "requiredForTerminal": False},
            {"id": "ent-news", "name": "Google News 娱乐", "role": "secondary", "frequency": "intraday", "requiredForTerminal": False},
            {"id": "sports-news", "name": "Google News 体育", "role": "secondary", "frequency": "intraday", "requiredForTerminal": False},
            {"id": "world-news", "name": "Google News 国际", "role": "secondary", "frequency": "intraday", "requiredForTerminal": False},
            {"id": "market-quotes", "name": "Yahoo Finance 市场快照", "role": "auxiliary", "frequency": "daily", "requiredForTerminal": False},
        ],
        "recovery": [
            {"id": "category-isolation", "kind": "partial-publish", "label": "新闻板块独立刷新，失败板块沿用上一份同板块内容"},
            {"id": "yahoo-mirror", "kind": "mirror", "label": "市场快照在Yahoo同提供方备用域名间重试"},
            {"id": "previous-snapshot", "kind": "previous-snapshot", "label": "全部新闻板块失败时保留完整旧快照"},
        ],
    },
}

NEWS_COMPONENT_KEYS = {
    "markets-news": "markets",
    "tech-news": "tech",
    "ent-news": "ent",
    "sports-news": "sports",
    "world-news": "world",
}


class HealthContractError(ValueError):
    """健康快照与数据或契约不一致。"""


def _text(value: Any) -> str | None:
    return value.strip() if isinstance(value, str) and value.strip() else None


def _finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def valid_iso(value: Any) -> bool:
    if not _text(value):
        return False
    try:
        datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return True
    except (TypeError, ValueError):
        return False


def _percent(numerator: int, denominator: int) -> float:
    return round(numerator / denominator * 100, 2) if denominator else 0.0


def component_ids(dataset: str) -> list[str]:
    if dataset not in FEED_SPECS:
        raise HealthContractError(f"未知辅助来源：{dataset}")
    return [component["id"] for component in FEED_SPECS[dataset]["components"]]


def _news_category(data: Mapping[str, Any], key: str) -> dict[str, Any] | None:
    matches = [
        category for category in data.get("categories", [])
        if isinstance(category, dict) and category.get("key") == key
    ] if isinstance(data.get("categories"), list) else []
    return matches[0] if len(matches) == 1 else None


def component_present(dataset: str, component_id: str, data: Mapping[str, Any]) -> bool:
    """只确认当前快照是否含可展示组件，不推断它是否来自本轮刷新。"""
    if not isinstance(data, Mapping):
        return False
    if dataset == "fear-greed":
        now_ref = data.get("refs", {}).get("now") if isinstance(data.get("refs"), dict) else None
        return (
            component_id == "cnn-index"
            and _finite(data.get("score"))
            and isinstance(now_ref, dict)
            and now_ref.get("score") == data.get("score")
        )
    if dataset == "ofr-monitor":
        value = data.get(component_id)
        if component_id == "fsi":
            return isinstance(value, dict) and _finite(value.get("value")) and bool(_text(value.get("asOf")))
        if component_id == "funding":
            return isinstance(value, dict) and bool(value.get("sofr") or value.get("effr")) and bool(_text(value.get("asOf")))
        if component_id == "mmf":
            return isinstance(value, dict) and _finite(value.get("total")) and bool(_text(value.get("asOf")))
        if component_id == "hedge":
            return isinstance(value, dict) and bool(value.get("gav") or value.get("nav") or value.get("url"))
        if component_id == "bank":
            return isinstance(value, dict) and isinstance(value.get("gsibs"), list) and bool(value["gsibs"])
        return False
    if dataset == "econ-calendar":
        return (
            component_id == "weekly-calendar"
            and isinstance(data.get("events"), list)
            and bool(data["events"])
            and data.get("count") == len(data["events"])
        )
    if dataset == "whats-latest":
        if component_id == "market-quotes":
            return isinstance(data.get("markets"), list) and bool(data["markets"])
        category_key = NEWS_COMPONENT_KEYS.get(component_id)
        category = _news_category(data, category_key) if category_key else None
        return isinstance(category, dict) and isinstance(category.get("items"), list) and bool(category["items"])
    return False


def _component_status(mode: str) -> str:
    return {
        "fresh": "healthy",
        "fallback": "degraded",
        "unavailable": "failed",
        "unknown": "unknown",
    }[mode]


def _ordered_for_mode(dataset: str, modes: Mapping[str, str], mode: str) -> list[str]:
    return [component_id for component_id in component_ids(dataset) if modes.get(component_id) == mode]


def _published_components(dataset: str, data: Mapping[str, Any]) -> list[str]:
    return [component_id for component_id in component_ids(dataset) if component_present(dataset, component_id, data)]


def _previous_component_success(previous: Mapping[str, Any] | None, component_id: str) -> str | None:
    if not isinstance(previous, Mapping):
        return None
    for component in previous.get("components", []):
        if isinstance(component, dict) and component.get("id") == component_id:
            return _text(component.get("lastSuccessAt"))
    return None


def _validate_data_identity(dataset: str, data: Mapping[str, Any]) -> None:
    if dataset not in FEED_SPECS:
        raise HealthContractError(f"未知辅助来源：{dataset}")
    if not isinstance(data, Mapping):
        raise HealthContractError(f"{dataset} data.json不是对象")
    if data.get("source") != FEED_SPECS[dataset]["source"]:
        raise HealthContractError(f"{dataset}数据来源与登记口径不一致")
    if not valid_iso(data.get("updatedAt")):
        raise HealthContractError(f"{dataset}数据更新时间无效")


def _build_health(
    dataset: str,
    *,
    data: Mapping[str, Any],
    generated_at: str,
    modes: Mapping[str, str],
    published: bool | None,
    previous_health: Mapping[str, Any] | None,
    failure_reason: str | None,
    migrated: bool,
) -> dict[str, Any]:
    _validate_data_identity(dataset, data)
    if not valid_iso(generated_at):
        raise HealthContractError("generated_at必须是ISO 8601时间")
    ids = component_ids(dataset)
    if set(modes) != set(ids) or any(mode not in COMPONENT_MODES for mode in modes.values()):
        raise HealthContractError(f"{dataset}必须为全部组件提供合法模式")
    if migrated:
        if published is not None or failure_reason is not None or any(mode != "unknown" for mode in modes.values()):
            raise HealthContractError("迁移健康不得伪造尝试结果")
    else:
        if not isinstance(published, bool):
            raise HealthContractError("真实运行必须明确是否发布")
        if not published and not _text(failure_reason):
            raise HealthContractError("未发布运行必须包含失败原因")
        if published and failure_reason is not None:
            raise HealthContractError("成功发布不得包含顶层失败原因")

    snapshot_at = str(data["updatedAt"])
    present = _published_components(dataset, data)
    fresh = _ordered_for_mode(dataset, modes, "fresh")
    fallback = _ordered_for_mode(dataset, modes, "fallback")
    unavailable = _ordered_for_mode(dataset, modes, "unavailable")
    unknown = _ordered_for_mode(dataset, modes, "unknown")
    if not migrated and published and any(component_id in fresh + fallback and component_id not in present for component_id in ids):
        raise HealthContractError("已刷新或回退组件必须存在于发布快照")

    if migrated:
        status = "unknown"
        history_status = "migrated"
        attempt_status = "unknown"
        consecutive_failures = None
        last_attempt_at = None
        last_successful_at = snapshot_at
        snapshot_preserved = None
    else:
        history_status = "tracked"
        last_attempt_at = generated_at
        attempt_status = "success" if published and len(fresh) == len(ids) else "partial" if published else "failed"
        status = "healthy" if attempt_status == "success" else "degraded" if published else "failed"
        previous_failures = previous_health.get("consecutiveFailures") if isinstance(previous_health, Mapping) else None
        consecutive_failures = 0 if published else previous_failures + 1 if isinstance(previous_failures, int) else 1
        last_successful_at = snapshot_at if published else (
            _text(previous_health.get("lastSuccessfulAt")) if isinstance(previous_health, Mapping) else None
        ) or snapshot_at
        snapshot_preserved = bool(not published and present)

    components = []
    for spec in FEED_SPECS[dataset]["components"]:
        component_id = spec["id"]
        mode = modes[component_id]
        previous_success = _previous_component_success(previous_health, component_id)
        last_success_at = generated_at if mode == "fresh" else previous_success
        if last_success_at is None and component_id in present:
            last_success_at = snapshot_at
        components.append({
            "id": component_id,
            "name": spec["name"],
            "role": spec["role"],
            "frequency": spec["frequency"],
            "requiredForTerminal": spec["requiredForTerminal"],
            "status": _component_status(mode),
            "mode": mode,
            "published": component_id in present,
            "lastAttemptAt": None if migrated else generated_at,
            "lastSuccessAt": last_success_at,
        })

    expected = len(ids)
    coverage = {
        "expectedComponents": expected,
        "publishedComponents": len(present),
        "refreshedComponents": len(fresh),
        "fallbackComponents": len(fallback),
        "unavailableComponents": len(unavailable),
        "unknownComponents": len(unknown),
        "publishedCoveragePct": _percent(len(present), expected),
        "freshCoveragePct": _percent(len(fresh), expected),
    }
    return {
        "contractVersion": CONTRACT_VERSION,
        "dataset": dataset,
        "generatedAt": generated_at,
        "status": status,
        "historyStatus": history_status,
        "lastAttemptAt": last_attempt_at,
        "lastSuccessfulAt": last_successful_at,
        "consecutiveFailures": consecutive_failures,
        "publishedSnapshotAt": snapshot_at,
        "snapshotPreserved": snapshot_preserved,
        "failureReason": _text(failure_reason),
        "coverage": coverage,
        "attempt": {
            "status": attempt_status,
            "published": published,
            "refreshedComponents": fresh,
            "fallbackComponents": fallback,
            "unavailableComponents": unavailable,
            "unknownComponents": unknown,
        },
        "components": components,
        "policy": {
            "maxReportAgeHours": FEED_SPECS[dataset]["maxReportAgeHours"],
            "terminalRequiredComponents": [
                component["id"] for component in FEED_SPECS[dataset]["components"]
                if component["requiredForTerminal"]
            ],
        },
        "recovery": {
            "preservesLastValidSnapshot": True,
            "steps": [dict(step) for step in FEED_SPECS[dataset]["recovery"]],
        },
    }


def make_migrated_health(dataset: str, *, data: Mapping[str, Any], generated_at: str) -> dict[str, Any]:
    """为既有快照建立未知历史，绝不把文件存在推断为最近任务成功。"""
    return _build_health(
        dataset,
        data=data,
        generated_at=generated_at,
        modes={component_id: "unknown" for component_id in component_ids(dataset)},
        published=None,
        previous_health=None,
        failure_reason=None,
        migrated=True,
    )


def make_health(
    dataset: str,
    *,
    data: Mapping[str, Any],
    attempted_at: str,
    component_modes: Mapping[str, str],
    published: bool,
    previous_health: Mapping[str, Any] | None = None,
    failure_reason: str | None = None,
) -> dict[str, Any]:
    return _build_health(
        dataset,
        data=data,
        generated_at=attempted_at,
        modes=component_modes,
        published=published,
        previous_health=previous_health,
        failure_reason=failure_reason,
        migrated=False,
    )


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise HealthContractError(message)


def validate_health(dataset: str, data: Mapping[str, Any], health: Mapping[str, Any]) -> None:
    """交叉校验数据与健康快照，并阻断覆盖率或状态篡改。"""
    _validate_data_identity(dataset, data)
    _require(isinstance(health, Mapping), f"{dataset} health.json不是对象")
    _require(health.get("contractVersion") == CONTRACT_VERSION, f"{dataset}健康契约版本错误")
    _require(health.get("dataset") == dataset, f"{dataset}健康文件数据集错配")
    _require(health.get("status") in DATASET_STATUSES, f"{dataset}健康状态无效")
    _require(health.get("historyStatus") in HISTORY_STATUSES, f"{dataset}历史状态无效")
    _require(valid_iso(health.get("generatedAt")), f"{dataset}健康生成时间无效")
    _require(health.get("publishedSnapshotAt") == data.get("updatedAt"), f"{dataset}健康与数据快照时间错配")
    if health.get("lastSuccessfulAt") is not None:
        _require(valid_iso(health.get("lastSuccessfulAt")), f"{dataset}最后成功时间无效")

    ids = component_ids(dataset)
    components = health.get("components")
    _require(isinstance(components, list) and [item.get("id") for item in components if isinstance(item, dict)] == ids,
             f"{dataset}组件顺序或集合错误")
    modes: dict[str, str] = {}
    for spec, component in zip(FEED_SPECS[dataset]["components"], components):
        _require(isinstance(component, dict), f"{dataset}组件结构无效")
        for key in ("name", "role", "frequency", "requiredForTerminal"):
            _require(component.get(key) == spec[key], f"{dataset}/{spec['id']}登记字段{key}错配")
        mode = component.get("mode")
        _require(mode in COMPONENT_MODES and component.get("status") == _component_status(mode),
                 f"{dataset}/{spec['id']}模式与状态错配")
        _require(component.get("published") == component_present(dataset, spec["id"], data),
                 f"{dataset}/{spec['id']}发布状态无法由data.json复算")
        if component.get("lastAttemptAt") is not None:
            _require(valid_iso(component.get("lastAttemptAt")), f"{dataset}/{spec['id']}尝试时间无效")
        if component.get("lastSuccessAt") is not None:
            _require(valid_iso(component.get("lastSuccessAt")), f"{dataset}/{spec['id']}成功时间无效")
        modes[spec["id"]] = mode

    present = _published_components(dataset, data)
    fresh = _ordered_for_mode(dataset, modes, "fresh")
    fallback = _ordered_for_mode(dataset, modes, "fallback")
    unavailable = _ordered_for_mode(dataset, modes, "unavailable")
    unknown = _ordered_for_mode(dataset, modes, "unknown")
    expected_coverage = {
        "expectedComponents": len(ids),
        "publishedComponents": len(present),
        "refreshedComponents": len(fresh),
        "fallbackComponents": len(fallback),
        "unavailableComponents": len(unavailable),
        "unknownComponents": len(unknown),
        "publishedCoveragePct": _percent(len(present), len(ids)),
        "freshCoveragePct": _percent(len(fresh), len(ids)),
    }
    _require(health.get("coverage") == expected_coverage, f"{dataset}健康覆盖率不可复算")

    attempt = health.get("attempt")
    _require(isinstance(attempt, dict), f"{dataset}尝试汇总缺失")
    _require(attempt.get("refreshedComponents") == fresh
             and attempt.get("fallbackComponents") == fallback
             and attempt.get("unavailableComponents") == unavailable
             and attempt.get("unknownComponents") == unknown,
             f"{dataset}尝试组件汇总错配")
    _require(attempt.get("status") in ATTEMPT_STATUSES, f"{dataset}尝试状态无效")

    migrated = health.get("historyStatus") == "migrated"
    if migrated:
        _require(health.get("status") == "unknown" and health.get("lastAttemptAt") is None,
                 f"{dataset}迁移状态不得声称已运行")
        _require(health.get("consecutiveFailures") is None and health.get("snapshotPreserved") is None,
                 f"{dataset}迁移状态不得推断失败历史")
        _require(health.get("failureReason") is None and attempt.get("status") == "unknown"
                 and attempt.get("published") is None and all(mode == "unknown" for mode in modes.values()),
                 f"{dataset}迁移尝试字段不诚实")
        _require(all(component.get("lastAttemptAt") is None for component in components),
                 f"{dataset}迁移组件不得包含尝试时间")
    else:
        published = attempt.get("published")
        _require(isinstance(published, bool), f"{dataset}真实尝试必须明确发布状态")
        expected_attempt = "success" if published and len(fresh) == len(ids) else "partial" if published else "failed"
        expected_status = "healthy" if expected_attempt == "success" else "degraded" if published else "failed"
        _require(attempt.get("status") == expected_attempt and health.get("status") == expected_status,
                 f"{dataset}顶层状态无法由尝试结果复算")
        _require(health.get("lastAttemptAt") == health.get("generatedAt")
                 and all(component.get("lastAttemptAt") == health.get("generatedAt") for component in components),
                 f"{dataset}真实尝试时间不一致")
        _require(isinstance(health.get("consecutiveFailures"), int) and health.get("consecutiveFailures") >= 0,
                 f"{dataset}连续失败次数无效")
        _require(health.get("consecutiveFailures") == 0 if published else health.get("consecutiveFailures") >= 1,
                 f"{dataset}连续失败次数与发布状态错配")
        _require(health.get("snapshotPreserved") == bool(not published and present),
                 f"{dataset}旧快照保留状态错误")
        _require(health.get("failureReason") is None if published else bool(_text(health.get("failureReason"))),
                 f"{dataset}失败原因与发布状态错配")
        _require(not published or all(component_id in present for component_id in fresh + fallback),
                 f"{dataset}健康声称刷新了未发布组件")

    policy = health.get("policy")
    _require(isinstance(policy, dict)
             and policy.get("maxReportAgeHours") == FEED_SPECS[dataset]["maxReportAgeHours"]
             and policy.get("terminalRequiredComponents") == [
                 component["id"] for component in FEED_SPECS[dataset]["components"]
                 if component["requiredForTerminal"]
             ], f"{dataset}时效或终端必需组件策略错配")
    recovery = health.get("recovery")
    _require(isinstance(recovery, dict) and recovery.get("preservesLastValidSnapshot") is True
             and recovery.get("steps") == FEED_SPECS[dataset]["recovery"],
             f"{dataset}恢复顺序错配")


def load_json(path: str | os.PathLike[str]) -> dict[str, Any]:
    try:
        with Path(path).open(encoding="utf-8") as stream:
            value = json.load(stream)
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def write_json_atomic(path: str | os.PathLike[str], value: Mapping[str, Any]) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, target)


def write_health(path: str | os.PathLike[str], value: Mapping[str, Any]) -> None:
    write_json_atomic(path, value)
