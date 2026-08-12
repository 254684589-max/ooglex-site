#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Ooglex金融终端Beta/稳定V1只读上线门禁。

门禁只读取仓库快照和GitHub Actions运行证据，不调用行情API，也不改写生产
数据。第一层检查四项真实核心行情、四项演示资产及页面必须展示的来源说明。
后续层在同一报告中追加聚合管道健康和远端日更周期证据。
"""

from __future__ import annotations

import argparse
from calendar import monthrange
from datetime import date, datetime, timedelta, timezone
import json
import math
import os
from pathlib import Path
import re
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from macro_source_health import validate_macro_health
from market_source_health import validate_source_health


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG_PATH = ROOT / "apps" / "finance-terminal" / "data.json"
DEFAULT_MACRO_PATH = ROOT / "apps" / "macro-radar" / "data.json"
DEFAULT_MACRO_HEALTH_PATH = ROOT / "apps" / "macro-radar" / "health.json"
DEFAULT_PAGE_PATH = ROOT / "apps" / "finance-terminal" / "index.html"
AGGREGATE_DATASETS = {
    "asset-tracker": {
        "data": ROOT / "apps" / "asset-tracker" / "data.json",
        "health": ROOT / "apps" / "asset-tracker" / "health.json",
        "rowsKey": "assets",
        "name": "跨资产强弱管道",
    },
    "companies": {
        "data": ROOT / "apps" / "companies" / "data.json",
        "health": ROOT / "apps" / "companies" / "health.json",
        "rowsKey": "companies",
        "name": "全球公司榜管道",
    },
    "asset-ranking": {
        "data": ROOT / "apps" / "asset-ranking" / "data.json",
        "health": ROOT / "apps" / "asset-ranking" / "health.json",
        "rowsKey": "assets",
        "name": "全球资产榜管道",
    },
}
AGGREGATE_HEALTH_MAX_AGE_HOURS = 72
MACRO_HEALTH_MAX_AGE_HOURS = 72
WORKFLOW_SPECS = {
    "macro-radar": {"file": "macro_radar.yml", "name": "宏观雷达日更"},
    "asset-tracker": {"file": "asset_tracker.yml", "name": "跨资产日更"},
    "companies": {"file": "companies.yml", "name": "公司榜日更"},
    "asset-ranking": {"file": "asset_ranking.yml", "name": "资产榜日更"},
}
BETA_REQUIRED_SUCCESSFUL_CYCLES = 3
STABLE_REQUIRED_SUCCESSFUL_CYCLES = 7
WORKFLOW_OBSERVATION_WINDOW_DAYS = 10
WORKFLOW_LATEST_MAX_AGE_HOURS = 48

REPORT_VERSION = 1
STATUSES = ("PASS", "WARN", "BLOCKED")
STATUS_WEIGHT = {status: index for index, status in enumerate(STATUSES)}
EXPECTED_ASSET_IDS = {
    "sp500", "nasdaq100", "dow", "us10y", "dxy", "gold", "wti", "bitcoin"
}
EXPECTED_OFFICIAL = {
    "us10y": {
        "symbol": "DGS10",
        "series": "DGS10",
        "maxBusinessDays": 3,
        "sourceKind": "FRED",
    },
    "dxy": {
        "symbol": "DTWEXBGS",
        "series": "DTWEXBGS",
        "maxBusinessDays": 3,
        "sourceKind": "FRED",
    },
    "wti": {
        "symbol": "WTI",
        "series": "RWTC",
        "maxBusinessDays": 4,
        "sourceKind": "EIA",
    },
    "bitcoin": {
        "symbol": "BTC/USD",
        "assetId": "bitcoin",
        "sourceKind": "CoinGecko",
    },
}
EXPECTED_DEMOS = {"sp500", "nasdaq100", "dow", "gold"}
BITCOIN_MAX_AGE_HOURS = 36
RWTC_ACCESS_METHODS = {"EIA API v2", "EIA public history page"}


class GateInputError(ValueError):
    """输入文件无法形成可信门禁报告。"""


def parse_datetime(value: Any) -> datetime:
    if not isinstance(value, str) or not value.strip():
        raise GateInputError("时间字段缺失")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise GateInputError(f"时间格式无效：{value}") from exc
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def parse_date(value: Any) -> date:
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        raise GateInputError(f"日期格式无效：{value}")
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise GateInputError(f"日期格式无效：{value}") from exc


def finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def observed_fixed_holiday(year: int, month: int, day: int) -> date:
    holiday = date(year, month, day)
    if holiday.weekday() == 5:
        return holiday - timedelta(days=1)
    if holiday.weekday() == 6:
        return holiday + timedelta(days=1)
    return holiday


def nth_weekday(year: int, month: int, weekday: int, nth: int) -> date:
    first = date(year, month, 1)
    offset = (weekday - first.weekday()) % 7
    return first + timedelta(days=offset + (nth - 1) * 7)


def last_weekday(year: int, month: int, weekday: int) -> date:
    last = date(year, month, monthrange(year, month)[1])
    return last - timedelta(days=(last.weekday() - weekday) % 7)


def us_federal_holidays(year: int) -> set[date]:
    # Python weekday: Monday=0. The list mirrors the browser adapter contract.
    return {
        observed_fixed_holiday(year, 1, 1),
        nth_weekday(year, 1, 0, 3),
        nth_weekday(year, 2, 0, 3),
        last_weekday(year, 5, 0),
        observed_fixed_holiday(year, 6, 19),
        observed_fixed_holiday(year, 7, 4),
        nth_weekday(year, 9, 0, 1),
        nth_weekday(year, 10, 0, 2),
        observed_fixed_holiday(year, 11, 11),
        nth_weekday(year, 11, 3, 4),
        observed_fixed_holiday(year, 12, 25),
    }


def is_us_business_day(value: date) -> bool:
    if value.weekday() >= 5:
        return False
    holidays = set()
    for year in (value.year - 1, value.year, value.year + 1):
        holidays.update(us_federal_holidays(year))
    return value not in holidays


def business_days_since(observed: date, now: datetime) -> int:
    current = now.astimezone(timezone.utc).date()
    if observed > current:
        raise GateInputError("观测日期晚于门禁时间")
    count = 0
    cursor = observed
    while cursor < current:
        cursor += timedelta(days=1)
        if is_us_business_day(cursor):
            count += 1
    return count


def hours_since(value: Any, now: datetime) -> float:
    observed = parse_datetime(value)
    current = now.astimezone(timezone.utc)
    if observed > current:
        raise GateInputError("健康报告时间晚于门禁时间")
    return (current - observed).total_seconds() / 3600


def make_check(
    check_id: str,
    name: str,
    status: str,
    summary: str,
    *,
    details: list[str] | None = None,
    metrics: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if status not in STATUSES:
        raise ValueError(f"不支持的门禁状态：{status}")
    return {
        "id": check_id,
        "name": name,
        "status": status,
        "summary": summary,
        "details": details or [],
        "metrics": metrics or {},
    }


def worst_status(checks: list[dict[str, Any]]) -> str:
    if not checks:
        return "BLOCKED"
    return max((check["status"] for check in checks), key=STATUS_WEIGHT.__getitem__)


def find_dgs10(macro: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    for category in macro.get("macro") or []:
        if not isinstance(category, dict):
            continue
        for row in category.get("rows") or []:
            if isinstance(row, dict) and row.get("id") == "DGS10":
                return category, row
    raise GateInputError("宏观雷达缺少DGS10记录")


def validate_config(config: dict[str, Any]) -> tuple[list[dict[str, Any]], list[str]]:
    errors: list[str] = []
    assets = config.get("assets")
    if not isinstance(assets, list):
        return [], ["终端配置assets不是数组"]
    ids = [asset.get("id") for asset in assets if isinstance(asset, dict)]
    if len(assets) != 8 or len(ids) != 8 or set(ids) != EXPECTED_ASSET_IDS:
        errors.append("核心资产必须恰为约定的8项且ID唯一")
    official = [asset for asset in assets if isinstance(asset, dict) and asset.get("demo") is False]
    demos = [asset for asset in assets if isinstance(asset, dict) and asset.get("demo") is True]
    if {asset.get("id") for asset in official} != set(EXPECTED_OFFICIAL):
        errors.append("真实数据配置必须且只能是DGS10、DTWEXBGS、RWTC与BTC/USD")
    if {asset.get("id") for asset in demos} != EXPECTED_DEMOS:
        errors.append("演示数据配置必须且只能是三大股指与黄金")
    for asset in demos:
        if asset.get("status") != "demo" or "演示" not in str((asset.get("source") or {}).get("name", "")):
            errors.append(f"{asset.get('id')}未同时以状态和来源标记为演示数据")
    for asset in official:
        spec = EXPECTED_OFFICIAL.get(asset.get("id")) or {}
        source = asset.get("source") or {}
        if asset.get("symbol") != spec.get("symbol"):
            errors.append(f"{asset.get('id')}代码与约定标的不一致")
        if asset.get("id") == "bitcoin":
            if source.get("assetId") != spec.get("assetId") or "CoinGecko" not in str(source.get("name", "")):
                errors.append("bitcoin来源资产与约定标的不一致")
            if asset.get("dataRef") != "../asset-ranking/data.json#assets[Bitcoin]":
                errors.append("bitcoin未复用全球资产榜逐条行情")
        elif source.get("seriesId") != spec.get("series"):
            errors.append(f"{asset.get('id')}来源序列与约定标的不一致")
        if asset.get("status") != "loading" or asset.get("price") is not None:
            errors.append(f"{asset.get('id')}静态配置必须等待上游适配且不得内置真实数值")
    return assets, errors


def evaluate_demo_policy(config: dict[str, Any], page_html: str) -> dict[str, Any]:
    assets, errors = validate_config(config)
    if config.get("demo") is not True or config.get("status") != "partial":
        errors.append("仍有演示资产时，文件级demo必须为true且status必须为partial")

    required_page_markers = (
        "当前为部分演示数据",
        "其余4项仍为演示数据",
        "FRED API使用条款",
        "本产品未获圣路易斯联储认可或认证",
        "EIA RWTC官方序列",
        "Powered by CoinGecko",
        "Yahoo BTC-USD",
        "非投资建议",
    )
    missing_markers = [marker for marker in required_page_markers if marker not in page_html]
    if missing_markers:
        errors.append("页面缺少必须公开的演示/来源说明：" + "、".join(missing_markers))

    demo_count = sum(1 for asset in assets if asset.get("demo") is True)
    if errors:
        return make_check(
            "market-demo-policy",
            "演示数据与公开说明",
            "BLOCKED",
            "演示/真实数据边界或公开说明不符合上线规则。",
            details=errors,
            metrics={"demoAssets": demo_count, "officialAssets": len(assets) - demo_count},
        )
    return make_check(
        "market-demo-policy",
        "演示数据与公开说明",
        "WARN" if demo_count else "PASS",
        (f"{demo_count}项资产仍为明确标注的演示数据；Beta可观察，稳定V1仍需替换。"
         if demo_count else "全部核心资产均为真实数据配置。"),
        details=["三大股指与黄金许可及正式接入尚未确认。"] if demo_count else [],
        metrics={"demoAssets": demo_count, "officialAssets": len(assets) - demo_count},
    )


def evaluate_dgs10(macro: dict[str, Any], now: datetime) -> dict[str, Any]:
    errors: list[str] = []
    age: int | None = None
    as_of: str | None = None
    pipeline_status: str | None = None
    try:
        category, row = find_dgs10(macro)
        as_of = row.get("asOf")
        pipeline_status = row.get("status") or "ok"
        if str(category.get("src", "")).upper() != "FRED":
            errors.append("DGS10来源不是FRED")
        source = row.get("source")
        if isinstance(source, dict) and (
            source.get("seriesId") != "DGS10" or "FRED" not in str(source.get("name", ""))
        ):
            errors.append("DGS10逐条来源不是FRED")
        if pipeline_status not in {"ok", "stale"}:
            errors.append("DGS10自动更新状态必须为ok或stale")
        value_match = re.fullmatch(r"(-?\d+(?:\.\d+)?)%", str(row.get("val", "")))
        change_match = re.fullmatch(r"([+-]?\d+(?:\.\d+)?)bp", str(row.get("chg", "")), re.I)
        if not value_match:
            errors.append("DGS10收益率数值或百分比单位无效")
        if not change_match:
            errors.append("DGS10变化值必须使用bp")
        if value_match and finite_number(row.get("price")) \
                and not math.isclose(row["price"], float(value_match.group(1)), rel_tol=0, abs_tol=1e-10):
            errors.append("DGS10数值字段不一致")
        if change_match and finite_number(row.get("changeBps")) \
                and not math.isclose(row["changeBps"], float(change_match.group(1)), rel_tol=0, abs_tol=1e-10):
            errors.append("DGS10变化字段不一致")
        if finite_number(row.get("price")) and finite_number(row.get("previousPrice")) \
                and finite_number(row.get("changeBps")):
            expected_bps = round((row["price"] - row["previousPrice"]) * 100)
            if not math.isclose(row["changeBps"], expected_bps, rel_tol=0, abs_tol=1e-10):
                errors.append("DGS10基点变化无法由当前值和前值复算")
        age = business_days_since(parse_date(as_of), now)
        parse_datetime(row.get("updatedAt") or macro.get("updatedAt"))
    except GateInputError as exc:
        errors.append(str(exc))
    if errors:
        return make_check(
            "official-dgs10", "FRED DGS10", "BLOCKED", "DGS10无法安全用于Beta。",
            details=errors, metrics={"asOf": as_of, "businessDaysOld": age, "maxBusinessDays": 3,
                                     "pipelineStatus": pipeline_status},
        )
    stale = pipeline_status == "stale" or (age is not None and age > 3)
    return make_check(
        "official-dgs10", "FRED DGS10", "WARN" if stale else "PASS",
        "DGS10观测或最近更新状态已过期，页面应继续标记STALE。" if stale else "DGS10来源、数值、单位和时效通过。",
        metrics={"asOf": as_of, "businessDaysOld": age, "maxBusinessDays": 3,
                 "pipelineStatus": pipeline_status},
    )


def evaluate_reference_series(
    macro: dict[str, Any],
    series_id: str,
    display_name: str,
    source_kind: str,
    max_business_days: int,
    now: datetime,
) -> dict[str, Any]:
    errors: list[str] = []
    age: int | None = None
    record = (macro.get("referenceSeries") or {}).get(series_id)
    if not isinstance(record, dict):
        return make_check(
            f"official-{series_id.lower()}", display_name, "BLOCKED",
            f"宏观雷达缺少{series_id}记录。",
        )
    source = record.get("source") or {}
    if record.get("id") != series_id or source.get("seriesId") != series_id:
        errors.append(f"{series_id}来源序列ID不一致")
    if record.get("demo") is not False:
        errors.append(f"{series_id}不得标记为演示数据")
    if record.get("status") not in {"ok", "stale"}:
        errors.append(f"{series_id}状态必须为ok或stale")
    if source_kind not in str(source.get("name", "")):
        errors.append(f"{series_id}来源不是{source_kind}")
    access_method = source.get("accessMethod") if series_id == "RWTC" else None
    if access_method is not None and access_method not in RWTC_ACCESS_METHODS:
        errors.append("RWTC实际访问路径无效")
    if not finite_number(record.get("price")) or not finite_number(record.get("previousPrice")):
        errors.append(f"{series_id}当前值或前值无效")
    try:
        observed = parse_date(record.get("asOf"))
        previous = parse_date(record.get("previousAsOf"))
        if previous >= observed:
            errors.append(f"{series_id}前值日期必须早于当前观测日期")
        age = business_days_since(observed, now)
        parse_datetime(record.get("updatedAt"))
        parse_datetime(record.get("lastAttemptAt"))
    except GateInputError as exc:
        errors.append(str(exc))
    if finite_number(record.get("price")) and finite_number(record.get("previousPrice")):
        expected_change = (record["price"] / record["previousPrice"] - 1) * 100
        if not finite_number(record.get("changePct")) or not math.isclose(
            record["changePct"], expected_change, rel_tol=0, abs_tol=1e-10
        ):
            errors.append(f"{series_id}涨跌幅无法由当前值和前值复算")
    if errors:
        return make_check(
            f"official-{series_id.lower()}", display_name, "BLOCKED",
            f"{series_id}无法安全用于Beta。", details=errors,
            metrics={"asOf": record.get("asOf"), "businessDaysOld": age,
                     "maxBusinessDays": max_business_days, "pipelineStatus": record.get("status"),
                     "accessMethod": access_method},
        )
    stale = record.get("status") == "stale" or (age is not None and age > max_business_days)
    return make_check(
        f"official-{series_id.lower()}", display_name, "WARN" if stale else "PASS",
        (f"{series_id}观测或最近更新状态已过期，页面应继续标记STALE。"
         if stale else f"{series_id}来源、数值、涨跌计算和时效通过。"),
        metrics={"asOf": record.get("asOf"), "businessDaysOld": age,
                 "maxBusinessDays": max_business_days, "pipelineStatus": record.get("status"),
                 "accessMethod": access_method},
    )


def evaluate_bitcoin_market(
    data: dict[str, Any], now: datetime, health: dict[str, Any] | None = None
) -> dict[str, Any]:
    """验证资产榜中可供终端发布的唯一BTC/USD逐条行情。"""
    errors: list[str] = []
    warnings: list[str] = []
    source_name: str | None = None
    mode: str | None = None
    status: str | None = None
    age_hours: float | None = None
    evidence_source: dict[str, Any] | None = None
    health_age_hours: float | None = None
    rows = data.get("assets")
    if not isinstance(rows, list):
        errors.append("全球资产榜缺少assets数组")
        matches: list[dict[str, Any]] = []
    else:
        matches = [row for row in rows if isinstance(row, dict)
                   and row.get("category") == "crypto" and row.get("symbol") == "BTC"
                   and (row.get("nameEn") == "Bitcoin" or row.get("name") == "比特币")]
    if len(matches) != 1:
        errors.append("全球资产榜必须且只能包含一条Bitcoin/BTC记录")
    top_source = data.get("source")
    if not isinstance(top_source, str) or "CoinGecko" not in top_source or "Yahoo Finance" not in top_source:
        errors.append("全球资产榜未同时声明CoinGecko主要来源与Yahoo Finance降级来源")
    if matches:
        row = matches[0]
        meta = row.get("dataMeta") if isinstance(row.get("dataMeta"), dict) else {}
        source_name = meta.get("source")
        mode = meta.get("mode")
        status = meta.get("status")
        if not finite_number(row.get("price")) or row["price"] <= 0:
            errors.append("BTC/USD价格必须为正有限数")
        if not finite_number(row.get("changePct")) or not -100 <= row["changePct"] <= 10000:
            errors.append("BTC/USD涨跌幅无效")
        if meta.get("frequency") != "daily":
            errors.append("BTC/USD逐条频率必须为daily")
        coin_gecko = mode == "market" and status == "ok" and source_name == "CoinGecko"
        yahoo = mode == "market" and status == "partial" \
            and source_name == "Yahoo Finance · 静态流通量基准"
        retained = mode == "fallback" and status in {"stale", "partial"} \
            and isinstance(source_name, str) and re.search(r"CoinGecko|Yahoo Finance", source_name)
        if not (coin_gecko or yahoo or retained):
            errors.append("BTC/USD不得使用估值、未知或不可用记录冒充行情")
        try:
            age_hours = hours_since(meta.get("asOf"), now)
            hours_since(meta.get("updatedAt"), now)
            hours_since(data.get("updatedAt"), now)
        except GateInputError as exc:
            errors.append(str(exc))
        if mode == "market" and meta.get("updatedAt") != data.get("updatedAt"):
            errors.append("BTC/USD逐条更新时间与资产榜快照不一致")
        if yahoo:
            warnings.append("CoinGecko本轮不可用，当前明确降级为Yahoo BTC-USD较前收盘口径。")
        if retained:
            warnings.append("CoinGecko与Yahoo本轮均未形成新值，当前保留同标的历史快照。")
        if row.get("stale") is True:
            warnings.append("资产榜已把BTC/USD逐条记录标记为过期。")
        if age_hours is not None and age_hours > BITCOIN_MAX_AGE_HOURS:
            warnings.append("BTC/USD逐条行情超过36小时。")
        if health is not None:
            health_errors = validate_source_health(
                health,
                dataset="asset-ranking",
                published_rows=rows if isinstance(rows, list) else [],
                published_snapshot_at=data.get("updatedAt"),
            )
            errors.extend(f"资产榜健康：{item}" for item in health_errors)
            try:
                health_age_hours = hours_since(health.get("lastAttemptAt"), now)
            except GateInputError as exc:
                errors.append(str(exc))
            source_id = "coingecko" if coin_gecko else "yahoo-finance" if yahoo else None
            candidates = [item for item in (health.get("sources") or []) if isinstance(item, dict)]
            if source_id:
                evidence_source = next((item for item in candidates if item.get("id") == source_id), None)
                if not evidence_source or (evidence_source.get("counts") or {}).get("market", 0) < 1:
                    errors.append("BTC/USD缺少对应市场来源的同批健康计数")
                elif evidence_source.get("lastSuccessAt") != meta.get("updatedAt"):
                    errors.append("BTC/USD逐条更新时间与来源最后成功时间不一致")
                elif coin_gecko and evidence_source.get("status") != "healthy":
                    errors.append("CoinGecko BTC/USD没有健康的同批来源证据")
                elif yahoo and evidence_source.get("status") not in {"healthy", "degraded"}:
                    errors.append("Yahoo BTC-USD降级来源健康状态无效")
            else:
                evidence_source = next((item for item in candidates
                                        if item.get("id") in {"coingecko", "yahoo-finance"}
                                        and (item.get("counts") or {}).get("fallback", 0) > 0), None)
                if evidence_source is None:
                    errors.append("BTC/USD历史回退缺少逐源健康证据")
            if health.get("status") == "failed":
                warnings.append("资产榜最近一次整批任务失败，BTC/USD仅保留可验证旧快照。")
            if health_age_hours is not None and health_age_hours > AGGREGATE_HEALTH_MAX_AGE_HOURS:
                warnings.append("资产榜健康证据超过72小时。")
    metrics = {
        "source": source_name,
        "mode": mode,
        "pipelineStatus": status,
        "ageHours": round(age_hours, 2) if age_hours is not None else None,
        "maxAgeHours": BITCOIN_MAX_AGE_HOURS,
        "healthEvidence": health is not None,
        "healthSource": evidence_source.get("id") if evidence_source else None,
        "healthSourceStatus": evidence_source.get("status") if evidence_source else None,
        "healthAgeHours": round(health_age_hours, 2) if health_age_hours is not None else None,
    }
    if errors:
        return make_check(
            "official-bitcoin", "CoinGecko BTC/USD", "BLOCKED",
            "BTC/USD无法安全用于Beta。", details=errors, metrics=metrics,
        )
    return make_check(
        "official-bitcoin", "CoinGecko BTC/USD", "WARN" if warnings else "PASS",
        ("BTC/USD来源契约通过，但当前处于明确降级或过期状态。"
         if warnings else "BTC/USD来源、数值、涨跌口径和时效通过。"),
        details=warnings, metrics=metrics,
    )


def evaluate_core_market(
    config: dict[str, Any], macro: dict[str, Any], page_html: str, now: datetime
) -> list[dict[str, Any]]:
    return [
        evaluate_demo_policy(config, page_html),
        evaluate_dgs10(macro, now),
        evaluate_reference_series(macro, "DTWEXBGS", "FRED DTWEXBGS", "FRED", 3, now),
        evaluate_reference_series(macro, "RWTC", "EIA RWTC", "EIA", 4, now),
    ]


def evaluate_macro_pipeline(
    macro: dict[str, Any], health: dict[str, Any], now: datetime
) -> dict[str, Any]:
    """核对三项官方值与最近真实取数尝试，旧值可用不等于更新链成功。"""
    errors = validate_macro_health(health, macro)
    age_hours: float | None = None
    try:
        age_hours = hours_since(health.get("lastAttemptAt"), now)
    except GateInputError as exc:
        errors.append(str(exc))
    coverage = health.get("coverage") if isinstance(health.get("coverage"), dict) else {}
    source_metrics = [{
        "id": source.get("id"),
        "status": source.get("status"),
        "mode": source.get("mode"),
        "asOf": source.get("asOf"),
        "lastAttemptAt": source.get("lastAttemptAt"),
        "lastSuccessfulAt": source.get("lastSuccessfulAt"),
        "consecutiveFailures": source.get("consecutiveFailures"),
        "snapshotPreserved": source.get("snapshotPreserved"),
    } for source in (health.get("sources") or []) if isinstance(source, dict)]
    metrics = {
        "pipelineStatus": health.get("status"),
        "historyStatus": health.get("historyStatus"),
        "attemptStatus": (health.get("attempt") or {}).get("status"),
        "lastAttemptAt": health.get("lastAttemptAt"),
        "lastSuccessfulAt": health.get("lastSuccessfulAt"),
        "reportAgeHours": round(age_hours, 2) if age_hours is not None else None,
        "maxAgeHours": MACRO_HEALTH_MAX_AGE_HOURS,
        "freshCoveragePct": coverage.get("freshCoveragePct"),
        "availableCoveragePct": coverage.get("availableCoveragePct"),
        "consecutiveFailures": health.get("consecutiveFailures"),
        "snapshotPreserved": health.get("snapshotPreserved"),
        "sources": source_metrics,
    }
    if errors:
        return make_check(
            "pipeline-macro-radar", "宏观雷达官方源管道", "BLOCKED",
            "macro-radar健康文件与三项官方发布记录不一致。",
            details=errors, metrics=metrics,
        )
    if health.get("status") == "failed":
        return make_check(
            "pipeline-macro-radar", "宏观雷达官方源管道", "BLOCKED",
            "DGS10、DTWEXBGS与RWTC最近一次均未刷新。",
            details=[str(health.get("failureReason") or "三项官方源最近尝试失败。")], metrics=metrics,
        )
    if age_hours is not None and age_hours > MACRO_HEALTH_MAX_AGE_HOURS:
        return make_check(
            "pipeline-macro-radar", "宏观雷达官方源管道", "BLOCKED",
            "宏观雷达逐源健康报告超过72小时，不能证明当前更新链可用。",
            details=["最后有效观测仍可按各卡片时效展示，但不满足Beta运行门槛。"], metrics=metrics,
        )
    warnings: list[str] = []
    if health.get("status") == "degraded":
        warnings.append("最近一次仅部分官方序列刷新，或仍处于迁移未知状态。")
    if health.get("historyStatus") != "tracked":
        warnings.append("逐源连续成功/失败历史尚未由真实远端运行建立。")
    if coverage.get("freshCoveragePct") != 100.0:
        warnings.append("最近一次任务未达到三项官方序列100%刷新覆盖。")
    return make_check(
        "pipeline-macro-radar", "宏观雷达官方源管道", "WARN" if warnings else "PASS",
        ("宏观雷达健康契约通过，但仍有逐源回退或历史待建立状态。"
         if warnings else "三项官方序列的快照、最近尝试和失败历史通过。"),
        details=warnings, metrics=metrics,
    )


def evaluate_aggregate_pipeline(
    dataset: str,
    data: dict[str, Any],
    health: dict[str, Any],
    now: datetime,
) -> dict[str, Any]:
    spec = AGGREGATE_DATASETS[dataset]
    rows = data.get(spec["rowsKey"])
    if not isinstance(rows, list):
        return make_check(
            f"pipeline-{dataset}", spec["name"], "BLOCKED",
            f"{dataset}发布快照缺少{spec['rowsKey']}数组。",
        )
    errors = validate_source_health(
        health,
        dataset=dataset,
        published_rows=rows,
        published_snapshot_at=data.get("updatedAt"),
    )
    age_hours: float | None = None
    try:
        age_hours = hours_since(health.get("lastAttemptAt"), now)
    except GateInputError as exc:
        errors.append(str(exc))

    coverage = health.get("coverage") if isinstance(health.get("coverage"), dict) else {}
    metrics = {
        "pipelineStatus": health.get("status"),
        "historyStatus": health.get("historyStatus"),
        "lastAttemptAt": health.get("lastAttemptAt"),
        "lastSuccessfulAt": health.get("lastSuccessfulAt"),
        "reportAgeHours": round(age_hours, 2) if age_hours is not None else None,
        "maxAgeHours": AGGREGATE_HEALTH_MAX_AGE_HOURS,
        "freshCoveragePct": coverage.get("freshCoveragePct"),
        "verifiedCoveragePct": coverage.get("verifiedCoveragePct"),
        "availableCoveragePct": coverage.get("availableCoveragePct"),
        "consecutiveFailures": health.get("consecutiveFailures"),
        "snapshotPreserved": health.get("snapshotPreserved"),
    }
    if errors:
        return make_check(
            f"pipeline-{dataset}", spec["name"], "BLOCKED",
            f"{dataset}健康文件与发布快照不一致。",
            details=errors, metrics=metrics,
        )
    if health.get("status") == "failed":
        return make_check(
            f"pipeline-{dataset}", spec["name"], "BLOCKED",
            f"{dataset}最近一次整批任务失败。",
            details=[str(health.get("failureReason") or "未提供失败原因")], metrics=metrics,
        )
    if age_hours is not None and age_hours > AGGREGATE_HEALTH_MAX_AGE_HOURS:
        return make_check(
            f"pipeline-{dataset}", spec["name"], "BLOCKED",
            f"{dataset}健康报告超过72小时，不能证明当前更新链可用。",
            details=["行情快照仍可展示为过期数据，但不满足Beta上线运行门槛。"], metrics=metrics,
        )

    warnings: list[str] = []
    if health.get("status") == "degraded":
        warnings.append("管道包含回退、估值、未知或部分数据。")
    if health.get("historyStatus") != "tracked":
        warnings.append("连续成功/失败历史尚未由真实远端运行建立。")
    if coverage.get("freshCoveragePct") == 0 and coverage.get("dynamicRecords", 0) > 0:
        warnings.append("最近任务行情覆盖为0%，不能把可用旧快照视为新鲜行情。")
    status = "WARN" if warnings else "PASS"
    summary = (
        f"{dataset}快照与健康契约通过，但仍有降级或历史待建立状态。"
        if warnings else f"{dataset}快照、来源健康和最近尝试时效通过。"
    )
    return make_check(
        f"pipeline-{dataset}", spec["name"], status, summary,
        details=warnings, metrics=metrics,
    )


def evaluate_aggregate_pipelines(
    aggregate_inputs: dict[str, dict[str, dict[str, Any]]], now: datetime
) -> list[dict[str, Any]]:
    checks = []
    for dataset in AGGREGATE_DATASETS:
        pair = aggregate_inputs.get(dataset) or {}
        data = pair.get("data")
        health = pair.get("health")
        if not isinstance(data, dict) or not isinstance(health, dict):
            checks.append(make_check(
                f"pipeline-{dataset}", AGGREGATE_DATASETS[dataset]["name"], "BLOCKED",
                f"{dataset}缺少数据或健康输入。",
            ))
        else:
            checks.append(evaluate_aggregate_pipeline(dataset, data, health, now))
    return checks


def workflow_cycle_date(created_at: datetime) -> str:
    """将21:00 UTC至次日窗口内的运行归入同一个调度日。"""
    return (created_at.astimezone(timezone.utc) - timedelta(hours=21)).date().isoformat()


def normalize_workflow_runs(
    payload: dict[str, Any], branch: str, now: datetime
) -> tuple[list[dict[str, Any]], list[str]]:
    raw_runs = payload.get("workflow_runs")
    if not isinstance(raw_runs, list):
        return [], ["GitHub Actions响应缺少workflow_runs数组"]
    errors: list[str] = []
    valid: list[dict[str, Any]] = []
    window_start = now.astimezone(timezone.utc) - timedelta(days=WORKFLOW_OBSERVATION_WINDOW_DAYS)
    for index, run in enumerate(raw_runs):
        if not isinstance(run, dict):
            errors.append(f"第{index + 1}条运行记录不是对象")
            continue
        if run.get("event") != "workflow_dispatch" or run.get("head_branch") != branch:
            continue
        if run.get("status") != "completed" or not isinstance(run.get("conclusion"), str):
            continue
        try:
            created = parse_datetime(run.get("created_at"))
            updated = parse_datetime(run.get("updated_at") or run.get("created_at"))
        except GateInputError:
            errors.append(f"第{index + 1}条运行记录时间无效")
            continue
        if created > now.astimezone(timezone.utc) or updated > now.astimezone(timezone.utc):
            errors.append(f"第{index + 1}条运行记录来自未来")
            continue
        if created < window_start:
            continue
        valid.append({
            "runId": run.get("id"),
            "runNumber": run.get("run_number"),
            "runAttempt": run.get("run_attempt"),
            "conclusion": run.get("conclusion"),
            "createdAt": created.isoformat().replace("+00:00", "Z"),
            "updatedAt": updated.isoformat().replace("+00:00", "Z"),
            "cycleDate": workflow_cycle_date(created),
            "headSha": run.get("head_sha"),
            "url": run.get("html_url"),
        })
    valid.sort(key=lambda item: item["createdAt"], reverse=True)
    return valid, errors


def evaluate_workflow_runs(
    workflow_id: str,
    payload: dict[str, Any],
    branch: str,
    now: datetime,
) -> dict[str, Any]:
    spec = WORKFLOW_SPECS[workflow_id]
    error_message = payload.get("error")
    if isinstance(error_message, str) and error_message:
        return make_check(
            f"workflow-{workflow_id}", spec["name"], "BLOCKED",
            f"无法取得{spec['file']}的远端运行证据。",
            details=[error_message],
            metrics={
                "workflow": spec["file"], "branch": branch,
                "requiredSuccessfulCycles": BETA_REQUIRED_SUCCESSFUL_CYCLES,
                "consecutiveSuccessfulCycles": 0,
            },
        )
    runs, errors = normalize_workflow_runs(payload, branch, now)
    by_cycle: dict[str, dict[str, Any]] = {}
    for run in runs:
        # runs already newest-first, so the first run is the final result for that scheduler cycle.
        by_cycle.setdefault(run["cycleDate"], run)
    cycles = sorted(by_cycle.values(), key=lambda item: item["cycleDate"], reverse=True)
    consecutive = 0
    for cycle in cycles:
        if cycle["conclusion"] != "success":
            break
        consecutive += 1
    latest = cycles[0] if cycles else None
    latest_age = None
    if latest:
        latest_age = hours_since(latest["createdAt"], now)
    metrics = {
        "workflow": spec["file"],
        "branch": branch,
        "observationWindowDays": WORKFLOW_OBSERVATION_WINDOW_DAYS,
        "requiredSuccessfulCycles": BETA_REQUIRED_SUCCESSFUL_CYCLES,
        "stableRequiredSuccessfulCycles": STABLE_REQUIRED_SUCCESSFUL_CYCLES,
        "observedCycles": len(cycles),
        "successfulCycles": sum(cycle["conclusion"] == "success" for cycle in cycles),
        "consecutiveSuccessfulCycles": consecutive,
        "latestConclusion": latest.get("conclusion") if latest else None,
        "latestCreatedAt": latest.get("createdAt") if latest else None,
        "latestAgeHours": round(latest_age, 2) if latest_age is not None else None,
        "cycleDates": [cycle["cycleDate"] for cycle in cycles],
        "runs": cycles,
    }
    if errors:
        return make_check(
            f"workflow-{workflow_id}", spec["name"], "BLOCKED",
            f"{spec['file']}运行证据包含无效时间或结构。",
            details=errors, metrics=metrics,
        )
    if not latest:
        return make_check(
            f"workflow-{workflow_id}", spec["name"], "BLOCKED",
            f"{branch}分支没有可验证的{spec['file']}日更周期。",
            metrics=metrics,
        )
    if latest["conclusion"] != "success":
        return make_check(
            f"workflow-{workflow_id}", spec["name"], "BLOCKED",
            f"{spec['file']}最近一个日更周期结论为{latest['conclusion']}。",
            metrics=metrics,
        )
    if latest_age is not None and latest_age > WORKFLOW_LATEST_MAX_AGE_HOURS:
        return make_check(
            f"workflow-{workflow_id}", spec["name"], "BLOCKED",
            f"{spec['file']}最近成功运行已超过48小时。",
            metrics=metrics,
        )
    if consecutive < BETA_REQUIRED_SUCCESSFUL_CYCLES:
        return make_check(
            f"workflow-{workflow_id}", spec["name"], "BLOCKED",
            f"{spec['file']}仅有{consecutive}个连续成功日更周期，Beta至少需要3个。",
            metrics=metrics,
        )
    return make_check(
        f"workflow-{workflow_id}", spec["name"], "PASS",
        f"{spec['file']}已有{consecutive}个连续成功日更周期。",
        metrics=metrics,
    )


def evaluate_workflow_evidence(evidence: dict[str, Any], now: datetime) -> list[dict[str, Any]]:
    branch = evidence.get("branch")
    workflows = evidence.get("workflows")
    if not isinstance(branch, str) or not branch.strip() or not isinstance(workflows, dict):
        return [
            make_check(
                f"workflow-{workflow_id}", spec["name"], "BLOCKED",
                "远端运行证据缺少目标分支或工作流结果。",
            )
            for workflow_id, spec in WORKFLOW_SPECS.items()
        ]
    checks = []
    for workflow_id, spec in WORKFLOW_SPECS.items():
        payload = workflows.get(spec["file"])
        if not isinstance(payload, dict):
            payload = {"error": f"缺少{spec['file']}运行证据"}
        checks.append(evaluate_workflow_runs(workflow_id, payload, branch, now))
    return checks


def stable_v1_status(checks: list[dict[str, Any]]) -> tuple[str, list[str]]:
    reasons: list[str] = []
    demo_check = next((check for check in checks if check["id"] == "market-demo-policy"), None)
    if demo_check and demo_check["metrics"].get("demoAssets", 0) > 0:
        reasons.append("稳定V1要求核心行情不含演示数据。")
    workflow_ids = {check["id"] for check in checks if check["id"].startswith("workflow-")}
    expected_workflow_ids = {f"workflow-{workflow_id}" for workflow_id in WORKFLOW_SPECS}
    for missing in sorted(expected_workflow_ids - workflow_ids):
        reasons.append(f"稳定V1缺少{missing}远端运行证据。")
    for check in checks:
        if check["status"] != "PASS" and not check["id"].startswith("workflow-"):
            reasons.append(f"{check['name']}尚未达到PASS。")
        if check["id"].startswith("workflow-"):
            cycles = check.get("metrics", {}).get("consecutiveSuccessfulCycles", 0)
            if not isinstance(cycles, int) or cycles < STABLE_REQUIRED_SUCCESSFUL_CYCLES:
                reasons.append(f"{check['name']}尚未连续成功7个日更周期。")
    return ("BLOCKED", reasons) if reasons else ("PASS", [])


def build_report(
    config: dict[str, Any],
    macro: dict[str, Any],
    page_html: str,
    now: datetime,
    aggregate_inputs: dict[str, dict[str, dict[str, Any]]] | None = None,
    workflow_evidence: dict[str, Any] | None = None,
    macro_health: dict[str, Any] | None = None,
) -> dict[str, Any]:
    checks = evaluate_core_market(config, macro, page_html, now)
    if macro_health is not None:
        checks.append(evaluate_macro_pipeline(macro, macro_health, now))
    if aggregate_inputs is not None:
        ranking_pair = aggregate_inputs.get("asset-ranking") or {}
        ranking_data = ranking_pair.get("data")
        ranking_health = ranking_pair.get("health")
        checks.append(evaluate_bitcoin_market(
            ranking_data if isinstance(ranking_data, dict) else {}, now,
            ranking_health if isinstance(ranking_health, dict) else None,
        ))
        checks.extend(evaluate_aggregate_pipelines(aggregate_inputs, now))
    if workflow_evidence is not None:
        checks.extend(evaluate_workflow_evidence(workflow_evidence, now))
    status = worst_status(checks)
    counts = {candidate: sum(1 for check in checks if check["status"] == candidate) for candidate in STATUSES}
    stable_status, stable_reasons = stable_v1_status(checks)
    return {
        "schemaVersion": REPORT_VERSION,
        "generatedAt": now.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
        "target": "beta",
        "status": status,
        "summary": counts,
        "checks": checks,
        "blockers": [check["summary"] for check in checks if check["status"] == "BLOCKED"],
        "warnings": [check["summary"] for check in checks if check["status"] == "WARN"],
        "targets": {
            "beta": {
                "status": status,
                "canLaunch": status != "BLOCKED",
                "requiredSuccessfulCycles": BETA_REQUIRED_SUCCESSFUL_CYCLES,
                "allowsExplicitDemoAssets": True,
            },
            "stableV1": {
                "status": stable_status,
                "canLaunch": stable_status == "PASS",
                "requiredSuccessfulCycles": STABLE_REQUIRED_SUCCESSFUL_CYCLES,
                "allowsExplicitDemoAssets": False,
                "blockers": stable_reasons,
            },
        },
        "scope": {
            "officialSeries": ["DGS10", "DTWEXBGS", "RWTC"],
            "marketAssets": ["BTC/USD"],
            "macroSourceHealth": macro_health is not None,
            "aggregatePipelines": list(AGGREGATE_DATASETS) if aggregate_inputs is not None else [],
            "remoteWorkflows": list(WORKFLOW_SPECS) if workflow_evidence is not None else [],
            "workflowEvidenceSource": workflow_evidence.get("source") if workflow_evidence else None,
            "repository": workflow_evidence.get("repository") if workflow_evidence else None,
            "branch": workflow_evidence.get("branch") if workflow_evidence else None,
            "doesNotCallMarketApis": True,
            "doesNotDeploy": True,
        },
    }


def render_markdown(report: dict[str, Any]) -> str:
    lines = [
        "# Ooglex金融终端上线准备报告",
        "",
        f"- Beta状态：**{report['status']}**",
        f"- 稳定V1状态：**{report['targets']['stableV1']['status']}**",
        f"- 生成时间：`{report['generatedAt']}`",
        f"- 汇总：PASS {report['summary']['PASS']} / WARN {report['summary']['WARN']} / BLOCKED {report['summary']['BLOCKED']}",
        "",
        "| 检查项 | 状态 | 结论 |",
        "|---|---|---|",
    ]
    for check in report["checks"]:
        lines.append(f"| {check['name']} | {check['status']} | {check['summary']} |")
    if report["blockers"]:
        lines.extend(["", "## 阻塞项", ""])
        lines.extend(f"- {item}" for item in report["blockers"])
    if report["warnings"]:
        lines.extend(["", "## 警告", ""])
        lines.extend(f"- {item}" for item in report["warnings"])
    stable_blockers = report.get("targets", {}).get("stableV1", {}).get("blockers") or []
    if stable_blockers:
        lines.extend(["", "## 稳定V1仍需", ""])
        lines.extend(f"- {item}" for item in stable_blockers)
    lines.extend([
        "",
        "> 本报告只读取仓库快照与运行证据，不调用行情API、不修改数据、不触发部署。",
        "",
    ])
    return "\n".join(lines)


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise GateInputError(f"无法读取JSON：{path}") from exc
    if not isinstance(value, dict):
        raise GateInputError(f"JSON根节点必须是对象：{path}")
    return value


def load_aggregate_inputs(paths: dict[str, dict[str, Path]] | None = None) -> dict[str, dict[str, dict[str, Any]]]:
    selected = paths or {
        dataset: {"data": spec["data"], "health": spec["health"]}
        for dataset, spec in AGGREGATE_DATASETS.items()
    }
    return {
        dataset: {
            "data": load_json(selected[dataset]["data"]),
            "health": load_json(selected[dataset]["health"]),
        }
        for dataset in AGGREGATE_DATASETS
    }


def fetch_workflow_runs(repository: str, workflow_file: str, branch: str, token: str) -> dict[str, Any]:
    query = urlencode({
        "branch": branch,
        "event": "workflow_dispatch",
        "status": "completed",
        "per_page": 100,
    })
    url = f"https://api.github.com/repos/{repository}/actions/workflows/{workflow_file}/runs?{query}"
    request = Request(url, headers={
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "ooglex-finance-terminal-release-gate",
    })
    try:
        with urlopen(request, timeout=15) as response:
            payload = json.load(response)
        if not isinstance(payload, dict) or not isinstance(payload.get("workflow_runs"), list):
            return {"error": "GitHub API响应结构无效"}
        return {"workflow_runs": payload["workflow_runs"]}
    except HTTPError as exc:
        return {"error": f"GitHub API HTTP {exc.code}"}
    except URLError as exc:
        return {"error": f"GitHub API网络错误：{type(exc.reason).__name__}"}
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return {"error": f"GitHub API响应读取失败：{type(exc).__name__}"}


def collect_workflow_evidence(
    repository: str | None,
    branch: str | None,
    token: str | None,
) -> dict[str, Any]:
    repository = repository.strip() if isinstance(repository, str) else ""
    branch = branch.strip() if isinstance(branch, str) else ""
    if not re.fullmatch(r"[^/\s]+/[^/\s]+", repository):
        error = "未提供有效的GitHub仓库owner/name"
    elif not branch:
        error = "未提供待观察分支"
    elif not token:
        error = "未提供只读GitHub Actions令牌"
    else:
        error = ""
    workflows = {}
    for spec in WORKFLOW_SPECS.values():
        workflows[spec["file"]] = (
            {"error": error} if error else fetch_workflow_runs(repository, spec["file"], branch, token)
        )
    return {
        "source": "github-api" if not error else "unavailable",
        "repository": repository or None,
        "branch": branch or None,
        "workflows": workflows,
    }


def load_workflow_evidence(path: Path) -> dict[str, Any]:
    evidence = load_json(path)
    if not isinstance(evidence.get("workflows"), dict):
        raise GateInputError("运行证据夹具缺少workflows对象")
    evidence = dict(evidence)
    evidence["source"] = "fixture"
    return evidence


def write_output(path: Path | None, content: str) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def parse_now(value: str | None) -> datetime:
    return parse_datetime(value) if value else datetime.now(timezone.utc)


def main() -> None:
    parser = argparse.ArgumentParser(description="生成金融终端只读上线准备报告")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG_PATH)
    parser.add_argument("--macro", type=Path, default=DEFAULT_MACRO_PATH)
    parser.add_argument("--macro-health", type=Path, default=DEFAULT_MACRO_HEALTH_PATH)
    parser.add_argument("--page", type=Path, default=DEFAULT_PAGE_PATH)
    parser.add_argument("--now", help="测试/复核用UTC ISO 8601时间")
    parser.add_argument("--report-json", type=Path)
    parser.add_argument("--report-md", type=Path)
    parser.add_argument("--skip-aggregate-health", action="store_true",
                        help="仅用于隔离测试三项宏观官方行情；正常门禁不得跳过")
    parser.add_argument("--repository", help="GitHub owner/name；默认读取GITHUB_REPOSITORY")
    parser.add_argument("--branch", help="待观察分支；默认读取READINESS_BRANCH或GitHub环境")
    parser.add_argument("--github-token-env", default="GITHUB_TOKEN",
                        help="只读Actions令牌所在环境变量名，不接收明文令牌参数")
    parser.add_argument("--workflow-evidence", type=Path, help="离线契约测试用运行证据JSON")
    parser.add_argument("--skip-remote-evidence", action="store_true",
                        help="仅用于隔离测试；正常Beta门禁不得跳过远端证据")
    parser.add_argument("--fail-on-blocked", action="store_true")
    args = parser.parse_args()

    try:
        repository = args.repository or os.environ.get("GITHUB_REPOSITORY")
        branch = (
            args.branch or os.environ.get("READINESS_BRANCH") or os.environ.get("GITHUB_HEAD_REF")
            or os.environ.get("GITHUB_REF_NAME")
        )
        if args.skip_remote_evidence:
            workflow_evidence = None
        elif args.workflow_evidence:
            workflow_evidence = load_workflow_evidence(args.workflow_evidence)
        else:
            workflow_evidence = collect_workflow_evidence(
                repository, branch, os.environ.get(args.github_token_env)
            )
        report = build_report(
            load_json(args.config),
            load_json(args.macro),
            args.page.read_text(encoding="utf-8"),
            parse_now(args.now),
            None if args.skip_aggregate_health else load_aggregate_inputs(),
            workflow_evidence,
            load_json(args.macro_health),
        )
    except (GateInputError, OSError) as exc:
        raise SystemExit(f"上线门禁输入无效：{exc}") from exc

    json_text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    markdown = render_markdown(report)
    write_output(args.report_json, json_text)
    write_output(args.report_md, markdown)
    print(json_text, end="")
    if args.fail_on_blocked and report["status"] == "BLOCKED":
        raise SystemExit(2)


if __name__ == "__main__":
    main()
