#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""共享的逐条金融数据来源与新鲜度契约。

现有三个聚合行情任务继续保留原字段；本模块只追加 ``dataMeta`` 与
``dataQuality``，让前端和检查脚本能区分本轮行情、历史回退、慢变量估值、
旧快照未知状态和不可用项目。
"""

from collections import Counter
from datetime import datetime
import re
from typing import Any


CONTRACT_VERSION = 1
DATA_MODES = ("market", "fallback", "estimate", "unknown", "unavailable")
DATA_STATUSES = ("ok", "partial", "stale", "error")
FREQUENCIES = (
    "realtime",
    "delayed",
    "daily",
    "weekly",
    "monthly",
    "quarterly",
    "annual",
    "irregular",
)
PROXY_TYPES = ("etf", "futures", "index")
PROXY_RETURN_BASES = ("price", "total-return")


def _text(value: Any) -> str | None:
    return value.strip() if isinstance(value, str) and value.strip() else None


def make_data_meta(
    mode: str,
    source: str,
    *,
    as_of: str | None,
    updated_at: str | None,
    frequency: str,
    status: str | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    """生成稳定、可序列化的逐条元数据；不伪造缺失日期。"""
    if mode not in DATA_MODES:
        raise ValueError(f"不支持的数据模式：{mode}")
    if frequency not in FREQUENCIES:
        raise ValueError(f"不支持的更新频率：{frequency}")
    source_text = _text(source)
    if not source_text:
        raise ValueError("逐条数据来源不能为空")
    if status is None:
        status = {
            "market": "ok",
            "fallback": "stale",
            "estimate": "ok",
            "unknown": "partial",
            "unavailable": "error",
        }[mode]
    if status not in DATA_STATUSES:
        raise ValueError(f"不支持的数据状态：{status}")
    return {
        "mode": mode,
        "status": status,
        "source": source_text,
        "asOf": _text(as_of),
        "updatedAt": _text(updated_at),
        "frequency": frequency,
        **({"note": _text(note)} if _text(note) else {}),
    }


def make_proxy_meta(
    proxy_type: str,
    target_symbol: str,
    instrument_name: str,
    instrument_symbol: str,
    *,
    currency: str,
    return_basis: str,
    note: str,
) -> dict[str, str]:
    """生成显式代理契约，避免把ETF、期货或另一指数静默当成目标标的。"""
    values = {
        "targetSymbol": _text(target_symbol),
        "instrumentName": _text(instrument_name),
        "instrumentSymbol": _text(instrument_symbol),
        "currency": _text(currency),
        "note": _text(note),
    }
    if proxy_type not in PROXY_TYPES:
        raise ValueError(f"不支持的代理类型：{proxy_type}")
    if return_basis not in PROXY_RETURN_BASES:
        raise ValueError(f"不支持的代理回报口径：{return_basis}")
    if not all(values.values()):
        raise ValueError("代理契约的目标、实际工具、币种和说明不能为空")
    if values["targetSymbol"] == values["instrumentSymbol"]:
        raise ValueError("代理工具代码不能与目标标的代码相同")
    if not re.fullmatch(r"[A-Z]{3}", values["currency"] or ""):
        raise ValueError("代理工具币种必须为三位大写ISO代码")
    return {
        "type": proxy_type,
        "targetSymbol": values["targetSymbol"],
        "instrumentName": values["instrumentName"],
        "instrumentSymbol": values["instrumentSymbol"],
        "currency": values["currency"],
        "returnBasis": return_basis,
        "note": values["note"],
    }


def validate_proxy_meta(row: dict[str, Any]) -> list[str]:
    """校验可选代理契约；无代理字段的直接行情保持向后兼容。"""
    proxy = row.get("proxy") if isinstance(row, dict) else None
    if proxy is None:
        return []
    if not isinstance(proxy, dict):
        return ["proxy必须为对象"]
    required = {
        "type", "targetSymbol", "instrumentName", "instrumentSymbol",
        "currency", "returnBasis", "note",
    }
    errors = []
    if set(proxy) != required:
        errors.append("proxy字段不完整或含未登记字段")
    if proxy.get("type") not in PROXY_TYPES:
        errors.append("proxy.type无效")
    if proxy.get("returnBasis") not in PROXY_RETURN_BASES:
        errors.append("proxy.returnBasis无效")
    for key in ("targetSymbol", "instrumentName", "instrumentSymbol", "note"):
        if not _text(proxy.get(key)):
            errors.append(f"proxy.{key}缺失")
    if not re.fullmatch(r"[A-Z]{3}", _text(proxy.get("currency")) or ""):
        errors.append("proxy.currency无效")
    if _text(proxy.get("instrumentSymbol")) != _text(row.get("symbol")):
        errors.append("proxy.instrumentSymbol必须与实际行情代码一致")
    if _text(proxy.get("targetSymbol")) == _text(proxy.get("instrumentSymbol")):
        errors.append("代理工具代码不得冒充目标标的代码")
    return errors


def fallback_data_meta(
    previous_row: dict[str, Any] | None,
    *,
    source: str,
    frequency: str,
    legacy_updated_at: str | None = None,
) -> dict[str, Any]:
    """沿用旧值时保留旧数据日；旧快照无逐条时间时明确说明。"""
    previous_meta = (previous_row or {}).get("dataMeta")
    if isinstance(previous_meta, dict):
        previous_source = _text(previous_meta.get("source")) or source
        previous_as_of = _text(previous_meta.get("asOf"))
        previous_updated_at = _text(previous_meta.get("updatedAt"))
        previous_frequency = previous_meta.get("frequency")
        exact_previous_time = _parse_iso(previous_as_of) and _parse_iso(previous_updated_at)
        return make_data_meta(
            "fallback",
            previous_source,
            as_of=previous_as_of,
            updated_at=previous_updated_at,
            frequency=previous_frequency if previous_frequency in FREQUENCIES else frequency,
            status="stale" if exact_previous_time else "partial",
            note=("本轮请求失败，沿用上一份逐条有效值。" if exact_previous_time
                  else "本轮请求失败，沿用旧快照；上一份记录缺少可验证的精确逐条时间。"),
        )
    return make_data_meta(
        "fallback",
        source,
        as_of=None,
        updated_at=legacy_updated_at,
        frequency=frequency,
        status="partial",
        note="本轮请求失败，沿用旧版快照；旧文件未记录精确逐条时间。",
    )


def summarize_data_quality(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """按逐条元数据生成可复算的文件级覆盖摘要。"""
    mode_counts = Counter()
    source_counts = Counter()
    statuses = []
    for row in rows:
        meta = row.get("dataMeta") if isinstance(row, dict) else None
        if not isinstance(meta, dict) or meta.get("mode") not in DATA_MODES:
            mode_counts["unknown"] += 1
            statuses.append("partial")
            continue
        mode_counts[meta["mode"]] += 1
        statuses.append(meta.get("status"))
        source = _text(meta.get("source"))
        if source:
            source_counts[source] += 1

    if not rows or mode_counts["unavailable"] == len(rows):
        overall = "error"
    elif any(status in ("partial", "stale", "error") for status in statuses) \
            or mode_counts["fallback"] or mode_counts["unknown"] or mode_counts["unavailable"]:
        overall = "partial"
    else:
        overall = "ok"

    return {
        "contractVersion": CONTRACT_VERSION,
        "status": overall,
        "total": len(rows),
        "counts": {mode: mode_counts[mode] for mode in DATA_MODES},
        "sources": [
            {"name": name, "count": count}
            for name, count in sorted(source_counts.items(), key=lambda item: (-item[1], item[0]))
        ],
    }


def _parse_iso(value: str | None) -> bool:
    if not value:
        return False
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
        return True
    except (TypeError, ValueError):
        return False


def validate_data_quality(rows: list[dict[str, Any]], summary: dict[str, Any]) -> list[str]:
    """返回契约错误列表，供工作流在提交数据前阻断坏快照。"""
    errors = []
    if not isinstance(rows, list):
        return ["逐条数据必须为数组"]
    for index, row in enumerate(rows):
        meta = row.get("dataMeta") if isinstance(row, dict) else None
        label = row.get("name") if isinstance(row, dict) else None
        prefix = f"第{index + 1}条{f'（{label}）' if label else ''}"
        if not isinstance(meta, dict):
            errors.append(prefix + "缺少dataMeta")
            continue
        if meta.get("mode") not in DATA_MODES:
            errors.append(prefix + "mode无效")
        if meta.get("status") not in DATA_STATUSES:
            errors.append(prefix + "status无效")
        if meta.get("mode") == "fallback" and meta.get("status") not in ("stale", "partial"):
            errors.append(prefix + "fallback状态必须为stale或partial")
        if meta.get("mode") == "unknown" and meta.get("status") != "partial":
            errors.append(prefix + "unknown状态必须为partial")
        if meta.get("mode") == "unavailable" and meta.get("status") != "error":
            errors.append(prefix + "unavailable状态必须为error")
        if not _text(meta.get("source")):
            errors.append(prefix + "source缺失")
        if meta.get("frequency") not in FREQUENCIES:
            errors.append(prefix + "frequency无效")
        if meta.get("asOf") is not None and not _parse_iso(meta.get("asOf")):
            errors.append(prefix + "asOf格式无效")
        if meta.get("updatedAt") is not None and not _parse_iso(meta.get("updatedAt")):
            errors.append(prefix + "updatedAt格式无效")
        if meta.get("mode") == "market" and not _parse_iso(meta.get("asOf")):
            errors.append(prefix + "行情模式缺少有效asOf")
        if meta.get("mode") == "market" and not _parse_iso(meta.get("updatedAt")):
            errors.append(prefix + "行情模式缺少有效updatedAt")
        errors.extend(prefix + error for error in validate_proxy_meta(row))

    expected = summarize_data_quality(rows)
    if summary != expected:
        errors.append("dataQuality与逐条dataMeta不可复算一致")
    return errors
