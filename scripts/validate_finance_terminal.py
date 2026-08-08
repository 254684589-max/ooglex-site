#!/usr/bin/env python3
"""Validate the Finance Terminal market overview without third-party dependencies."""

from __future__ import annotations

import importlib.util
import json
import re
import subprocess
import sys
import types
from datetime import date, datetime
from pathlib import Path

from market_data_quality import (
    fallback_data_meta,
    make_data_meta,
    summarize_data_quality,
    validate_data_quality,
)
from market_source_health import validate_source_health
from supporting_source_health import validate_health as validate_supporting_health


ROOT = Path(__file__).resolve().parents[1]
PAGE = ROOT / "apps" / "finance-terminal" / "index.html"
APP = ROOT / "apps" / "finance-terminal" / "app.js"
DATA = ROOT / "apps" / "finance-terminal" / "data.json"
MACRO_DATA = ROOT / "apps" / "macro-radar" / "data.json"
FEAR_GREED_DATA = ROOT / "apps" / "fear-greed" / "data.json"
FEAR_GREED_HEALTH = ROOT / "apps" / "fear-greed" / "health.json"
OFR_DATA = ROOT / "apps" / "ofr-monitor" / "data.json"
OFR_HEALTH = ROOT / "apps" / "ofr-monitor" / "health.json"
ASSET_TRACKER_DATA = ROOT / "apps" / "asset-tracker" / "data.json"
ASSET_TRACKER_HEALTH = ROOT / "apps" / "asset-tracker" / "health.json"
ASSET_RANKING_DATA = ROOT / "apps" / "asset-ranking" / "data.json"
ASSET_RANKING_HEALTH = ROOT / "apps" / "asset-ranking" / "health.json"
ASSET_RANKING_BUILD = ROOT / "scripts" / "asset-ranking" / "build_ranking.py"
COMPANIES_DATA = ROOT / "apps" / "companies" / "data.json"
COMPANIES_HEALTH = ROOT / "apps" / "companies" / "health.json"
COMPANIES_BUILD = ROOT / "scripts" / "companies" / "build_companies.py"
ECON_CALENDAR_DATA = ROOT / "apps" / "econ-calendar" / "data.json"
ECON_CALENDAR_HEALTH = ROOT / "apps" / "econ-calendar" / "health.json"
FINANCE_NEWS_DATA = ROOT / "apps" / "whats-latest" / "data.json"
FINANCE_NEWS_HEALTH = ROOT / "apps" / "whats-latest" / "health.json"
MACRO_BUILD = ROOT / "scripts" / "macro-radar" / "build_radar.py"
MACRO_HISTORY_BUILD = ROOT / "scripts" / "macro-radar" / "build_history.py"
MACRO_WORKFLOW = ROOT / ".github" / "workflows" / "macro_radar.yml"
FEAR_GREED_WORKFLOW = ROOT / ".github" / "workflows" / "fear_greed.yml"
OFR_WORKFLOW = ROOT / ".github" / "workflows" / "ofr_monitor.yml"
ASSET_TRACKER_WORKFLOW = ROOT / ".github" / "workflows" / "asset_tracker.yml"
ASSET_RANKING_WORKFLOW = ROOT / ".github" / "workflows" / "asset_ranking.yml"
COMPANIES_WORKFLOW = ROOT / ".github" / "workflows" / "companies.yml"
ECON_CALENDAR_WORKFLOW = ROOT / ".github" / "workflows" / "econ_calendar.yml"
FINANCE_NEWS_WORKFLOW = ROOT / ".github" / "workflows" / "whats_latest.yml"
SCHEDULER_WORKFLOW = ROOT / ".github" / "workflows" / "scheduler.yml"
QUALITY_WORKFLOW = ROOT / ".github" / "workflows" / "finance_terminal_quality.yml"
BROWSER_VALIDATOR = ROOT / "scripts" / "validate_finance_terminal_browser.mjs"
DATA_ISSUE_FORM = ROOT / ".github" / "ISSUE_TEMPLATE" / "finance-terminal-data.yml"
OPERATIONS_RUNBOOK = ROOT / "docs" / "FINANCE_TERMINAL_OPERATIONS_RUNBOOK.md"
SOURCE_HEALTH_VALIDATOR = ROOT / "scripts" / "validate_market_source_health.py"
SOURCE_HEALTH_DOC = ROOT / "docs" / "AGGREGATE_SOURCE_HEALTH.md"
SUPPORTING_HEALTH_VALIDATOR = ROOT / "scripts" / "validate_supporting_source_health.py"
SUPPORTING_HEALTH_DOC = ROOT / "docs" / "SUPPORTING_SOURCE_HEALTH.md"
HOME = ROOT / "index.html"

EXPECTED_SYMBOLS = {"SPX", "NDX", "DJI", "DGS10", "DTWEXBGS", "XAU/USD", "WTI", "BTC/USD"}
COMMON_ASSET_FIELDS = {
    "id", "name", "nameEn", "symbol", "category", "demo", "status", "frequency",
    "delayLabel", "price", "asOf", "updatedAt", "source", "spark",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def parse_iso(value: str) -> None:
    datetime.fromisoformat(value.replace("Z", "+00:00"))


def parse_date(value: str) -> None:
    date.fromisoformat(value)


def css_hex_variable(styles: str, name: str) -> str:
    match = re.search(rf"--{re.escape(name)}:\s*(#[0-9a-fA-F]{{6}})\s*;", styles)
    require(match is not None, f"CSS变量--{name}缺失或不是六位十六进制颜色")
    return match.group(1)


def relative_luminance(color: str) -> float:
    channels = [int(color[index:index + 2], 16) / 255 for index in (1, 3, 5)]
    linear = [channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4
              for channel in channels]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast_ratio(foreground: str, background: str) -> float:
    lighter, darker = sorted((relative_luminance(foreground), relative_luminance(background)), reverse=True)
    return (lighter + 0.05) / (darker + 0.05)


def run_market_data_quality_contract_tests() -> None:
    updated = "2026-08-03T12:00:00Z"
    market = make_data_meta(
        "market", "Yahoo Finance", as_of="2026-08-01", updated_at=updated, frequency="daily"
    )
    previous = {"dataMeta": market}
    fallback = fallback_data_meta(previous, source="Yahoo Finance", frequency="daily")
    require(fallback["mode"] == "fallback" and fallback["status"] == "stale", "逐条回退状态无效")
    require(fallback["asOf"] == market["asOf"] and fallback["updatedAt"] == market["updatedAt"],
            "逐条回退必须保留上一份真实时间")
    legacy = fallback_data_meta(
        {}, source="Yahoo Finance", frequency="daily", legacy_updated_at="2026-08-01T23:48:35Z"
    )
    require(legacy["mode"] == "fallback" and legacy["status"] == "partial", "旧快照回退必须标记partial")
    require(legacy["asOf"] is None, "旧快照不得用文件日期冒充逐条数据日")
    unknown_previous = {"dataMeta": make_data_meta(
        "unknown", "Yahoo Finance", as_of=None, updated_at=updated, frequency="daily"
    )}
    unknown_fallback = fallback_data_meta(unknown_previous, source="Yahoo Finance", frequency="daily")
    require(unknown_fallback["status"] == "partial" and unknown_fallback["asOf"] is None,
            "缺少可验证逐条时间的旧记录不得升级为精确STALE回退")
    rows = [{"name": "A", "dataMeta": market}, {"name": "B", "dataMeta": fallback}]
    summary = summarize_data_quality(rows)
    require(summary["counts"]["market"] == 1 and summary["counts"]["fallback"] == 1,
            "逐条数据质量计数错误")
    require(summary["status"] == "partial" and not validate_data_quality(rows, summary),
            "逐条数据质量摘要或结构校验错误")
    print("Market data per-record contract: PASS")


def run_company_builder_contract_tests() -> None:
    spec = importlib.util.spec_from_file_location("companies_builder", COMPANIES_BUILD)
    require(spec is not None and spec.loader is not None, "无法加载公司榜构建脚本")
    module = importlib.util.module_from_spec(spec)
    inserted_stub = "requests" not in sys.modules
    if inserted_stub:
        requests_stub = types.ModuleType("requests")
        requests_stub.utils = types.SimpleNamespace(quote=lambda value: value)
        requests_stub.Session = object
        sys.modules["requests"] = requests_stub
    try:
        spec.loader.exec_module(module)
    finally:
        if inserted_stub:
            sys.modules.pop("requests", None)

    class Response:
        status_code = 200

        @staticmethod
        def json():
            return {"chart": {"result": [{"meta": {
                "regularMarketPrice": 125.5,
                "chartPreviousClose": 120.0,
                "regularMarketTime": 1785715200,
            }}]}}

    class Session:
        @staticmethod
        def get(*_args, **_kwargs):
            return Response()

    quote = module.yf_chart(Session(), "TEST")
    require(quote == (125.5, 120.0, "2026-08-03T00:00:00Z"), "公司行情值或行情时点映射错误")
    require(module.last_round_as_of("May 2026") == "2026-05-01", "融资月份规范化错误")
    require(module.last_round_as_of(None) is None, "缺失融资月份不得生成默认日期")
    print("Company per-record provenance builder: PASS")


def run_asset_ranking_builder_contract_tests() -> None:
    spec = importlib.util.spec_from_file_location("asset_ranking_builder", ASSET_RANKING_BUILD)
    require(spec is not None and spec.loader is not None, "无法加载全球资产榜构建脚本")
    module = importlib.util.module_from_spec(spec)
    inserted_stub = "requests" not in sys.modules
    if inserted_stub:
        requests_stub = types.ModuleType("requests")
        requests_stub.utils = types.SimpleNamespace(quote=lambda value: value)
        requests_stub.Session = object
        sys.modules["requests"] = requests_stub
    try:
        spec.loader.exec_module(module)
    finally:
        if inserted_stub:
            sys.modules.pop("requests", None)

    class Response:
        status_code = 200

        @staticmethod
        def json():
            return {"chart": {"result": [{"meta": {
                "regularMarketPrice": 75.25,
                "chartPreviousClose": 73.5,
                "regularMarketTime": 1785715200,
            }}]}}

    class Session:
        headers = {}

        @staticmethod
        def get(*_args, **_kwargs):
            return Response()

    quote = module.yf_price(Session(), "TEST")
    require(quote == (75.25, 73.5, "2026-08-03T00:00:00Z"), "资产排行行情值或行情时点映射错误")
    require(module.baseline_provenance({"name": "全球房地产"}) == {"source": "Savills", "asOf": None},
            "全球房地产静态基准来源映射错误")

    rows = module.build_aggregates(Session(), {}, "2026-08-03T01:00:00Z")
    real_estate = next(row for row in rows if row["name"] == "全球房地产")
    oil = next(row for row in rows if row["name"] == "石油")
    require(real_estate["dataMeta"]["mode"] == "estimate"
            and real_estate["dataMeta"]["source"] == "Savills"
            and real_estate["dataMeta"]["asOf"] is None,
            "慢变量估值不得伪造报告日期")
    require(oil["dataMeta"]["mode"] == "market"
            and oil["dataMeta"]["asOf"] == "2026-08-03T00:00:00Z"
            and oil["dataMeta"]["status"] == "partial",
            "数量基准日期缺失时，行情价格记录必须保留行情时点并降级为partial")
    print("Asset ranking per-record provenance builder: PASS")


def find_dgs10(macro: dict) -> tuple[dict, dict]:
    matches = []
    for category in macro.get("macro", []):
        for row in category.get("rows", []):
            if row.get("id") == "DGS10":
                matches.append((category, row))
    require(len(matches) == 1, "宏观雷达必须且只能包含一条DGS10记录")
    return matches[0]


def load_macro_builder():
    spec = importlib.util.spec_from_file_location("macro_radar_builder", MACRO_BUILD)
    require(spec is not None and spec.loader is not None, "无法加载宏观雷达构建脚本")
    module = importlib.util.module_from_spec(spec)
    inserted_stub = "requests" not in sys.modules
    if inserted_stub:
        requests_stub = types.ModuleType("requests")
        requests_stub.get = lambda *_args, **_kwargs: None
        sys.modules["requests"] = requests_stub
    try:
        spec.loader.exec_module(module)
    finally:
        if inserted_stub:
            sys.modules.pop("requests", None)
    return module


def run_dtwexbgs_pipeline_tests() -> None:
    builder = load_macro_builder()
    attempt = "2026-08-03T12:00:00Z"
    observations = [("2026-07-23", 120.9075), ("2026-07-24", 120.7105)]
    fresh = builder.build_dtwexbgs_reference({}, attempt, lambda _series_id, _limit: observations)
    require(fresh["status"] == "ok", "DTWEXBGS成功更新必须标记ok")
    require(fresh["price"] == 120.7105 and fresh["previousPrice"] == 120.9075, "DTWEXBGS观测值映射错误")
    require(fresh["asOf"] == "2026-07-24" and fresh["previousAsOf"] == "2026-07-23", "DTWEXBGS日期映射错误")
    expected_change = (120.7105 / 120.9075 - 1) * 100
    require(abs(fresh["changePct"] - expected_change) < 1e-12, "DTWEXBGS涨跌幅计算错误")
    require(fresh["updatedAt"] == attempt and fresh["lastAttemptAt"] == attempt, "DTWEXBGS成功更新时间错误")
    require(builder.valid_dtwexbgs_reference(fresh), "成功记录未通过结构校验")

    old = {"referenceSeries": {"DTWEXBGS": fresh}}
    failed_at = "2026-08-04T12:00:00Z"
    fallback = builder.build_dtwexbgs_reference(old, failed_at, lambda _series_id, _limit: [])
    require(fallback["status"] == "stale", "更新失败且有历史值时必须标记stale")
    require(fallback["price"] == fresh["price"] and fallback["asOf"] == fresh["asOf"], "更新失败不得覆盖历史有效值")
    require(fallback["updatedAt"] == fresh["updatedAt"], "失败时不得伪造成功更新时间")
    require(fallback["lastAttemptAt"] == failed_at, "失败尝试时间必须单独记录")
    require(fresh["status"] == "ok", "失败回退不得原地修改上一份记录")

    unavailable = builder.build_dtwexbgs_reference({}, failed_at, lambda _series_id, _limit: [])
    require(unavailable["status"] == "error", "无新值也无历史值时必须标记error")
    require(unavailable["price"] is None and unavailable["updatedAt"] is None, "失败时不得写入默认数值或伪更新时间")

    invalid = builder.build_dtwexbgs_reference(
        old,
        failed_at,
        lambda _series_id, _limit: [("2026-07-24", 120.7), ("2026-07-23", 120.9)],
    )
    require(invalid["status"] == "stale" and invalid["price"] == fresh["price"], "日期倒序的新数据必须回退历史有效值")
    print("DTWEXBGS FRED pipeline states: PASS")
    print("- success / failed-refresh fallback / no-history error / invalid-observation: PASS")


def run_rwtc_pipeline_tests() -> None:
    builder = load_macro_builder()
    attempt = "2026-08-03T12:00:00Z"
    payload = {
        "response": {
            "frequency": "daily",
            "data": [
                {
                    "period": "2026-07-27",
                    "series": "RWTC",
                    "value": "84.25",
                    "value-units": "dollars per barrel",
                },
                {
                    "period": "2026-07-24",
                    "series": "RWTC",
                    "value": "91.74",
                    "value-units": "dollars per barrel",
                },
                {
                    "period": "2026-07-23",
                    "series": "RBRTE",
                    "value": "99.99",
                    "value-units": "dollars per barrel",
                },
            ],
        }
    }
    captured = {}

    class FakeResponse:
        status_code = 200

        @staticmethod
        def raise_for_status():
            return None

        @staticmethod
        def json():
            return payload

    def requester(url, **kwargs):
        captured["url"] = url
        captured["params"] = kwargs.get("params")
        return FakeResponse()

    observations = builder.eia_rwtc_api(2, requester=requester, api_key="test-key")
    require(captured["url"] == builder.EIA_API_URL, "RWTC必须使用已核对的EIA API v2路由")
    require("test-key" not in captured["url"], "EIA密钥不得拼入或记录在请求URL中")
    require(captured["params"]["api_key"] == "test-key", "EIA密钥必须通过参数对象传递")
    require(captured["params"]["frequency"] == "daily", "RWTC API请求必须为日频")
    require(captured["params"]["data[0]"] == "value", "RWTC API请求字段必须为value")
    require(captured["params"]["facets[series][]"] == "RWTC", "RWTC API请求序列筛选错误")
    require(observations == [("2026-07-24", 91.74), ("2026-07-27", 84.25)], "EIA返回值解析或排序错误")

    fresh = builder.build_rwtc_reference({}, attempt, lambda _limit: observations)
    require(fresh["status"] == "ok", "RWTC成功更新必须标记ok")
    require(fresh["price"] == 84.25 and fresh["previousPrice"] == 91.74, "RWTC观测值映射错误")
    require(fresh["asOf"] == "2026-07-27" and fresh["previousAsOf"] == "2026-07-24", "RWTC日期映射错误")
    expected_change = (84.25 / 91.74 - 1) * 100
    require(abs(fresh["changePct"] - expected_change) < 1e-12, "RWTC涨跌幅计算错误")
    require(fresh["updatedAt"] == attempt and fresh["lastAttemptAt"] == attempt, "RWTC成功更新时间错误")
    require(builder.valid_rwtc_reference(fresh), "RWTC成功记录未通过结构校验")

    old = {"referenceSeries": {"RWTC": fresh}}
    failed_at = "2026-08-04T12:00:00Z"
    fallback = builder.build_rwtc_reference(old, failed_at, lambda _limit: [])
    require(fallback["status"] == "stale", "RWTC更新失败且有历史值时必须标记stale")
    require(fallback["price"] == fresh["price"] and fallback["asOf"] == fresh["asOf"], "RWTC失败不得覆盖历史有效值")
    require(fallback["updatedAt"] == fresh["updatedAt"], "RWTC失败时不得伪造成功更新时间")
    require(fallback["lastAttemptAt"] == failed_at, "RWTC失败尝试时间必须单独记录")
    require(fresh["status"] == "ok", "RWTC失败回退不得原地修改上一份记录")

    unavailable = builder.build_rwtc_reference({}, failed_at, lambda _limit: [])
    require(unavailable["status"] == "error", "RWTC无新值也无历史值时必须标记error")
    require(unavailable["price"] is None and unavailable["updatedAt"] is None, "RWTC失败时不得写入默认数值")

    invalid = builder.build_rwtc_reference(
        old,
        failed_at,
        lambda _limit: [("2026-07-27", 84.25), ("2026-07-24", 91.74)],
    )
    require(invalid["status"] == "stale" and invalid["price"] == fresh["price"], "RWTC日期倒序必须回退历史值")
    print("RWTC EIA pipeline states: PASS")
    print("- API contract / success / failed-refresh fallback / no-history error / invalid-observation: PASS")


def run_js_adapter_tests() -> None:
    script = r"""
const assert = require("assert");
const fs = require("fs");
const adapter = require("./apps/finance-terminal/app.js");
const config = JSON.parse(fs.readFileSync("./apps/finance-terminal/data.json", "utf8"));
const macro = JSON.parse(fs.readFileSync("./apps/macro-radar/data.json", "utf8"));
const macroHealth = JSON.parse(fs.readFileSync("./apps/macro-radar/health.json", "utf8"));
const fearGreed = JSON.parse(fs.readFileSync("./apps/fear-greed/data.json", "utf8"));
const fearGreedHealth = JSON.parse(fs.readFileSync("./apps/fear-greed/health.json", "utf8"));
const ofr = JSON.parse(fs.readFileSync("./apps/ofr-monitor/data.json", "utf8"));
const ofrHealth = JSON.parse(fs.readFileSync("./apps/ofr-monitor/health.json", "utf8"));
const assetTracker = JSON.parse(fs.readFileSync("./apps/asset-tracker/data.json", "utf8"));
const assetTrackerHealth = JSON.parse(fs.readFileSync("./apps/asset-tracker/health.json", "utf8"));
const assetRanking = JSON.parse(fs.readFileSync("./apps/asset-ranking/data.json", "utf8"));
const assetRankingHealth = JSON.parse(fs.readFileSync("./apps/asset-ranking/health.json", "utf8"));
const companies = JSON.parse(fs.readFileSync("./apps/companies/data.json", "utf8"));
const companiesHealth = JSON.parse(fs.readFileSync("./apps/companies/health.json", "utf8"));
const econCalendar = JSON.parse(fs.readFileSync("./apps/econ-calendar/data.json", "utf8"));
const econCalendarHealth = JSON.parse(fs.readFileSync("./apps/econ-calendar/health.json", "utf8"));
const financeNews = JSON.parse(fs.readFileSync("./apps/whats-latest/data.json", "utf8"));
const financeNewsHealth = JSON.parse(fs.readFileSync("./apps/whats-latest/health.json", "utf8"));

const match = adapter.findDgs10Row(macro);
assert(match && match.row.id === "DGS10");
const reference = adapter.findDtwexbgsReference(macro);
assert(reference && reference.id === "DTWEXBGS");
const oilReference = adapter.findRwtcReference(macro);
assert(oilReference && oilReference.id === "RWTC");
const dollarConfig = config.assets.find((asset) => asset.id === "dxy");
const oilConfig = config.assets.find((asset) => asset.id === "wti");
const currentNow = new Date("2026-08-08T23:59:59Z");
const supportingNow = new Date("2026-08-08T12:00:00Z");
const expiredOfficialHealthNow = new Date("2026-08-12T23:59:59Z");
function qualityDeclaration(rows) {
  const metas = rows.map((row) => adapter.normalizeDataMeta(row.dataMeta, null));
  const quality = adapter.summarizeRowQuality(metas, null);
  return {
    contractVersion: 1,
    status: !rows.length || quality.counts.unavailable === rows.length ? "error" : quality.degraded ? "partial" : "ok",
    total: quality.total,
    counts: quality.counts,
    sources: quality.sources
  };
}
[
  ["fear-greed", fearGreed, fearGreedHealth],
  ["ofr-monitor", ofr, ofrHealth],
  ["econ-calendar", econCalendar, econCalendarHealth],
  ["whats-latest", financeNews, financeNewsHealth]
].forEach(([dataset, sourceData, sourceHealth]) => {
  const state = adapter.adaptSupportingSourceHealth(sourceHealth, dataset, sourceData, supportingNow);
  assert.strictEqual(state.dataset, dataset);
  assert.strictEqual(state.status, "unknown");
  assert.strictEqual(state.historyKnown, false);
  assert.strictEqual(state.freshCoveragePct, 0);
  assert.strictEqual(state.publishedCoveragePct, 100);
  const tampered = JSON.parse(JSON.stringify(sourceHealth));
  tampered.coverage.refreshedComponents += 1;
  assert.throws(() => adapter.adaptSupportingSourceHealth(tampered, dataset, sourceData, supportingNow));
});
function trackedSupportingHealth(sourceHealth, attemptedAt, overrides = {}, published = true) {
  const tracked = JSON.parse(JSON.stringify(sourceHealth));
  const statusForMode = { fresh: "healthy", fallback: "degraded", unavailable: "failed", unknown: "unknown" };
  const grouped = { fresh: [], fallback: [], unavailable: [], unknown: [] };
  tracked.historyStatus = "tracked";
  tracked.generatedAt = attemptedAt;
  tracked.lastAttemptAt = attemptedAt;
  tracked.consecutiveFailures = published ? 0 : 1;
  tracked.snapshotPreserved = !published;
  tracked.failureReason = published ? null : "测试失败";
  tracked.components.forEach((component) => {
    const mode = overrides[component.id] || "fresh";
    component.mode = mode;
    component.status = statusForMode[mode];
    component.lastAttemptAt = attemptedAt;
    if (mode === "fresh") component.lastSuccessAt = attemptedAt;
    grouped[mode].push(component.id);
  });
  tracked.coverage.refreshedComponents = grouped.fresh.length;
  tracked.coverage.fallbackComponents = grouped.fallback.length;
  tracked.coverage.unavailableComponents = grouped.unavailable.length;
  tracked.coverage.unknownComponents = grouped.unknown.length;
  tracked.coverage.freshCoveragePct = Math.round(grouped.fresh.length / tracked.components.length * 10000) / 100;
  tracked.attempt = {
    status: published && grouped.fresh.length === tracked.components.length ? "success" : published ? "partial" : "failed",
    published,
    refreshedComponents: grouped.fresh,
    fallbackComponents: grouped.fallback,
    unavailableComponents: grouped.unavailable,
    unknownComponents: grouped.unknown
  };
  tracked.status = tracked.attempt.status === "success" ? "healthy" : published ? "degraded" : "failed";
  return tracked;
}
const trackedFear = trackedSupportingHealth(fearGreedHealth, "2026-08-08T11:00:00Z");
assert.strictEqual(adapter.adaptSupportingSourceHealth(trackedFear, "fear-greed", fearGreed, supportingNow).status, "healthy");
const fallbackFear = trackedSupportingHealth(fearGreedHealth, "2026-08-08T11:00:00Z", { "cnn-index": "fallback" });
const fallbackFearState = adapter.adaptSupportingSourceHealth(fallbackFear, "fear-greed", fearGreed, supportingNow);
assert.strictEqual(fallbackFearState.status, "degraded");
assert.strictEqual(fallbackFearState.terminalStatus, "degraded");
const failedFear = trackedSupportingHealth(fearGreedHealth, "2026-08-08T11:00:00Z", { "cnn-index": "fallback" }, false);
assert.strictEqual(adapter.adaptSupportingSourceHealth(failedFear, "fear-greed", fearGreed, supportingNow).status, "failed");
const staleFearHealth = trackedSupportingHealth(fearGreedHealth, "2026-08-01T11:00:00Z");
assert.strictEqual(adapter.adaptSupportingSourceHealth(staleFearHealth, "fear-greed", fearGreed, supportingNow).status, "stale");
const supportingRiskCards = adapter.buildRiskCards({
  macro: { data: macro, error: null },
  fearGreed: { data: fearGreed, error: null },
  fearGreedHealth: { data: fearGreedHealth, error: null },
  ofr: { data: ofr, error: null },
  ofrHealth: { data: ofrHealth, error: null }
}, supportingNow);
assert.strictEqual(supportingRiskCards[1].sourceHealth.status, "unknown");
assert.strictEqual(supportingRiskCards[2].sourceHealth.status, "unknown");
const supportingInformationCards = adapter.buildInformationCards({
  calendar: { data: econCalendar, error: null },
  calendarHealth: { data: econCalendarHealth, error: null },
  news: { data: financeNews, error: null },
  newsHealth: { data: financeNewsHealth, error: null }
}, supportingNow);
assert.strictEqual(supportingInformationCards[0].sourceHealth.status, "unknown");
assert.strictEqual(supportingInformationCards[1].sourceHealth.status, "unknown");
const success = adapter.buildPageData(config, macro, currentNow);
const dgs10 = success.assets.find((asset) => asset.id === "us10y");
const dollar = success.assets.find((asset) => asset.id === "dxy");
const oil = success.assets.find((asset) => asset.id === "wti");
assert.strictEqual(dgs10.demo, false);
assert.strictEqual(dgs10.status, match.row.status === "ok" ? "ok" : "stale");
assert.strictEqual(dgs10.symbol, "DGS10");
assert.strictEqual(dgs10.changeUnit, "bp");
assert(Number.isFinite(dgs10.price));
assert(Number.isFinite(dgs10.change));
assert.strictEqual(dgs10.price, Number(match.row.val.replace("%", "")));
assert.strictEqual(dgs10.change, Number(match.row.chg.toLowerCase().replace("bp", "")));
assert.strictEqual(dgs10.asOf, match.row.asOf);
assert.strictEqual(dgs10.updatedAt, macro.updatedAt);
assert.strictEqual(dgs10.source.seriesId, "DGS10");
const dgs10Health = adapter.adaptOfficialSourceHealth(macroHealth, macro, dgs10, "DGS10", currentNow);
assert.strictEqual(dgs10Health.seriesId, "DGS10");
assert.strictEqual(dgs10Health.status, "unknown");
assert.strictEqual(dgs10Health.historyKnown, false);
assert.strictEqual(dgs10Health.refreshLabel, "历史待建立");
const dgs10WithStaleHealth = adapter.buildPageData(
  config, macro, expiredOfficialHealthNow, null, { data: macroHealth, error: null }
).assets.find((asset) => asset.id === "us10y");
assert.strictEqual(dgs10WithStaleHealth.updateHealth.status, "stale");
assert.strictEqual(dgs10WithStaleHealth.updateHealth.seriesId, "DGS10");
assert(dgs10WithStaleHealth.updateHealth.note.includes("超过72小时"));
const tamperedDgs10Health = JSON.parse(JSON.stringify(macroHealth));
tamperedDgs10Health.sources.find((source) => source.id === "DGS10").asOf = "2026-07-29";
assert.throws(() => adapter.adaptOfficialSourceHealth(
  tamperedDgs10Health, macro, dgs10, "DGS10", currentNow
));
const dgs10WithMissingHealth = adapter.buildPageData(
  config, macro, currentNow, null, { data: null, error: new Error("HTTP 503") }
).assets.find((asset) => asset.id === "us10y");
assert.strictEqual(dgs10WithMissingHealth.status, dgs10.status);
assert.strictEqual(dgs10WithMissingHealth.price, dgs10.price);
assert.strictEqual(dgs10WithMissingHealth.updateHealth.status, "unknown");
assert.strictEqual(dollar.demo, false);
assert.strictEqual(dollar.status, "stale");
assert.strictEqual(dollar.symbol, "DTWEXBGS");
assert.strictEqual(dollar.price, reference.price);
assert.strictEqual(dollar.previousPrice, reference.previousPrice);
assert.strictEqual(dollar.asOf, reference.asOf);
assert.strictEqual(dollar.updatedAt, reference.updatedAt);
assert.strictEqual(dollar.source.seriesId, "DTWEXBGS");
assert(Math.abs(dollar.changePct - ((reference.price / reference.previousPrice - 1) * 100)) < 1e-12);
const dollarHealth = adapter.adaptOfficialSourceHealth(
  macroHealth, macro, dollar, "DTWEXBGS", currentNow
);
assert.strictEqual(dollarHealth.status, "stale");
assert.strictEqual(dollarHealth.historyKnown, false);
assert.strictEqual(dollarHealth.refreshLabel, "历史待建立");
const dollarWithStaleHealth = adapter.buildPageData(
  config, macro, expiredOfficialHealthNow, null, { data: macroHealth, error: null }
).assets.find((asset) => asset.id === "dxy");
assert.strictEqual(dollarWithStaleHealth.updateHealth.status, "stale");
assert.strictEqual(dollarWithStaleHealth.updateHealth.seriesId, "DTWEXBGS");
const tamperedDollarHealth = JSON.parse(JSON.stringify(macroHealth));
tamperedDollarHealth.sources.find((source) => source.id === "DTWEXBGS").publishedUpdatedAt = "2026-07-28T20:23:00Z";
const isolatedDollarHealth = adapter.buildPageData(
  config, macro, expiredOfficialHealthNow, null, { data: tamperedDollarHealth, error: null }
);
assert.strictEqual(isolatedDollarHealth.assets.find((asset) => asset.id === "dxy").updateHealth.status, "unknown");
assert.strictEqual(isolatedDollarHealth.assets.find((asset) => asset.id === "dxy").price, dollar.price);
assert.strictEqual(isolatedDollarHealth.assets.find((asset) => asset.id === "us10y").updateHealth.status, "stale");
assert.strictEqual(oil.demo, false);
assert.strictEqual(oil.status, "stale");
assert.strictEqual(oil.symbol, "WTI");
assert.strictEqual(oil.price, oilReference.price);
assert.strictEqual(oil.previousPrice, oilReference.previousPrice);
assert.strictEqual(oil.asOf, oilReference.asOf);
assert.strictEqual(oil.updatedAt, oilReference.updatedAt);
assert.strictEqual(oil.source.seriesId, "RWTC");
assert(Math.abs(oil.changePct - ((oilReference.price / oilReference.previousPrice - 1) * 100)) < 1e-12);
const oilHealth = adapter.adaptOfficialSourceHealth(macroHealth, macro, oil, "RWTC", currentNow);
assert.strictEqual(oilHealth.status, "stale");
assert.strictEqual(oilHealth.historyKnown, false);
assert.strictEqual(oilHealth.refreshLabel, "历史待建立");
const oilWithStaleHealth = adapter.buildPageData(
  config, macro, expiredOfficialHealthNow, null, { data: macroHealth, error: null }
).assets.find((asset) => asset.id === "wti");
assert.strictEqual(oilWithStaleHealth.updateHealth.status, "stale");
assert.strictEqual(oilWithStaleHealth.updateHealth.seriesId, "RWTC");
const allOfficialHealth = adapter.buildPageData(
  config, macro, expiredOfficialHealthNow, null, { data: macroHealth, error: null }
).assets.filter((asset) => asset.demo === false);
assert.deepStrictEqual(allOfficialHealth.map((asset) => asset.updateHealth.seriesId), ["DGS10", "DTWEXBGS", "RWTC"]);
assert.strictEqual(allOfficialHealth.filter((asset) => asset.updateHealth.status === "stale").length, 3);

function trackedOfficialHealth(base, seriesId, attemptedAt, mode) {
  const tracked = JSON.parse(JSON.stringify(base));
  tracked.historyStatus = "tracked";
  tracked.generatedAt = attemptedAt;
  tracked.lastAttemptAt = attemptedAt;
  const source = tracked.sources.find((item) => item.id === seriesId);
  source.historyStatus = "tracked";
  source.lastAttemptAt = attemptedAt;
  source.mode = mode;
  source.status = { market: "healthy", fallback: "degraded", unavailable: "failed" }[mode];
  source.consecutiveFailures = mode === "market" ? 0 : 1;
  source.snapshotPreserved = mode === "fallback";
  source.failureReason = mode === "market" ? null : "测试更新失败";
  if (mode === "market") source.lastSuccessfulAt = attemptedAt;
  return tracked;
}
const healthyDgsHealth = trackedOfficialHealth(macroHealth, "DGS10", "2026-08-08T12:00:00Z", "market");
const healthyDgsMacro = JSON.parse(JSON.stringify(macro));
adapter.findDgs10Row(healthyDgsMacro).row.status = "ok";
const healthyDgsAsset = adapter.buildPageData(config, healthyDgsMacro, currentNow)
  .assets.find((asset) => asset.id === "us10y");
assert.strictEqual(adapter.adaptOfficialSourceHealth(
  healthyDgsHealth, healthyDgsMacro, healthyDgsAsset, "DGS10", currentNow
).status, "healthy");

const fallbackDollarMacro = JSON.parse(JSON.stringify(macro));
fallbackDollarMacro.referenceSeries.DTWEXBGS.status = "stale";
const fallbackDollarAsset = adapter.adaptDtwexbgs(dollarConfig, fallbackDollarMacro, currentNow);
const trackedDollarFallback = trackedOfficialHealth(
  macroHealth, "DTWEXBGS", "2026-08-08T12:00:00Z", "fallback"
);
assert.strictEqual(adapter.adaptOfficialSourceHealth(
  trackedDollarFallback, fallbackDollarMacro, fallbackDollarAsset, "DTWEXBGS", currentNow
).status, "degraded");

const unavailableOilMacro = JSON.parse(JSON.stringify(macro));
unavailableOilMacro.referenceSeries.RWTC.status = "error";
const unavailableOilAsset = Object.assign({}, oilConfig, {
  price: null, previousPrice: null, changePct: null, asOf: null, updatedAt: null, demo: false, status: "error"
});
const trackedOilFailure = trackedOfficialHealth(
  macroHealth, "RWTC", "2026-08-08T12:00:00Z", "unavailable"
);
const trackedOilSource = trackedOilFailure.sources.find((source) => source.id === "RWTC");
trackedOilSource.published = false;
trackedOilSource.asOf = null;
trackedOilSource.publishedUpdatedAt = null;
assert.strictEqual(adapter.adaptOfficialSourceHealth(
  trackedOilFailure, unavailableOilMacro, unavailableOilAsset, "RWTC", currentNow
).status, "failed");
assert.strictEqual(success.assets.filter((asset) => asset.demo === false).length, 3);
assert.strictEqual(success.assets.filter((asset) => asset.demo === true).length, 5);
assert.strictEqual(success.status, "stale");

const trackedDgsMacro = JSON.parse(JSON.stringify(macro));
const trackedDgs = adapter.findDgs10Row(trackedDgsMacro).row;
trackedDgs.status = "stale";
trackedDgs.price = Number(trackedDgs.val.replace("%", ""));
trackedDgs.changeBps = Number(trackedDgs.chg.toLowerCase().replace("bp", ""));
trackedDgs.previousPrice = trackedDgs.price - trackedDgs.changeBps / 100;
trackedDgs.updatedAt = "2026-08-02T21:00:00Z";
trackedDgs.lastAttemptAt = "2026-08-03T21:00:00Z";
trackedDgs.source = { name: "FRED / Federal Reserve H.15", seriesId: "DGS10" };
const retainedDgs = adapter.buildPageData(config, trackedDgsMacro, currentNow).assets.find((asset) => asset.id === "us10y");
assert.strictEqual(retainedDgs.status, "stale");
assert.strictEqual(retainedDgs.updatedAt, trackedDgs.updatedAt);
assert(retainedDgs.note.includes("自动更新失败"));

trackedDgs.status = "ok";
trackedDgs.asOf = "2026-08-07";
trackedDgs.updatedAt = "2026-08-07T21:00:00Z";
trackedDgs.lastAttemptAt = trackedDgs.updatedAt;
const independentlyFreshDgs = adapter.buildPageData(config, trackedDgsMacro, currentNow).assets.find((asset) => asset.id === "us10y");
assert.strictEqual(independentlyFreshDgs.status, "ok");
assert.strictEqual(independentlyFreshDgs.updatedAt, trackedDgs.updatedAt);

const freshDollar = adapter.adaptDtwexbgs(dollarConfig, macro, new Date("2026-07-27T23:59:59Z"));
assert.strictEqual(freshDollar.status, "ok");
assert.strictEqual(freshDollar.demo, false);
assert.strictEqual(freshDollar.delayLabel, "日频 · 自动更新");

const freshOilMacro = JSON.parse(JSON.stringify(macro));
freshOilMacro.referenceSeries.RWTC.status = "ok";
const freshOil = adapter.adaptRwtc(oilConfig, freshOilMacro, new Date("2026-07-31T23:59:59Z"));
assert.strictEqual(freshOil.status, "ok");
assert.strictEqual(freshOil.demo, false);
assert.strictEqual(freshOil.delayLabel, "日频现货 · 自动更新");

const staleMacro = JSON.parse(JSON.stringify(macro));
const staleMatch = adapter.findDgs10Row(staleMacro);
staleMatch.row.asOf = "2026-07-20";
staleMacro.referenceSeries.DTWEXBGS.asOf = "2026-07-20";
staleMacro.referenceSeries.DTWEXBGS.previousAsOf = "2026-07-17";
staleMacro.referenceSeries.RWTC.status = "ok";
staleMacro.referenceSeries.RWTC.asOf = "2026-07-20";
staleMacro.referenceSeries.RWTC.previousAsOf = "2026-07-17";
const stale = adapter.buildPageData(config, staleMacro, new Date("2026-07-27T23:59:59Z"));
assert.strictEqual(stale.assets.find((asset) => asset.id === "us10y").status, "stale");
assert.strictEqual(stale.assets.find((asset) => asset.id === "dxy").status, "stale");
assert.strictEqual(stale.assets.find((asset) => asset.id === "wti").status, "stale");
assert.strictEqual(stale.status, "stale");

const missingMacro = JSON.parse(JSON.stringify(macro));
missingMacro.macro.forEach((category) => {
  category.rows = (category.rows || []).filter((row) => row.id !== "DGS10");
});
const missing = adapter.buildPageData(config, missingMacro, currentNow);
assert.strictEqual(missing.assets.find((asset) => asset.id === "us10y").status, "error");
assert.strictEqual(missing.assets.find((asset) => asset.id === "dxy").status, "stale");
assert.strictEqual(missing.assets.find((asset) => asset.id === "wti").status, "stale");

const invalidMacro = JSON.parse(JSON.stringify(macro));
adapter.findDgs10Row(invalidMacro).row.chg = "+1%";
adapter.findDgs10Row(invalidMacro).row.changeBps = null;
const invalidDgs10 = adapter.buildPageData(config, invalidMacro, currentNow);
assert.strictEqual(invalidDgs10.assets.find((asset) => asset.id === "us10y").status, "error");

const invalidDollarMacro = JSON.parse(JSON.stringify(macro));
invalidDollarMacro.referenceSeries.DTWEXBGS.price = null;
const invalidDollar = adapter.buildPageData(config, invalidDollarMacro, currentNow);
assert.strictEqual(invalidDollar.assets.find((asset) => asset.id === "dxy").status, "error");
assert.strictEqual(invalidDollar.assets.find((asset) => asset.id === "dxy").price, null);

const wrongSourceMacro = JSON.parse(JSON.stringify(macro));
wrongSourceMacro.referenceSeries.DTWEXBGS.source.seriesId = "DXY";
const wrongSource = adapter.buildPageData(config, wrongSourceMacro, currentNow);
assert.strictEqual(wrongSource.assets.find((asset) => asset.id === "dxy").status, "error");

const invalidOilMacro = JSON.parse(JSON.stringify(macro));
invalidOilMacro.referenceSeries.RWTC.previousPrice = null;
const invalidOil = adapter.buildPageData(config, invalidOilMacro, currentNow);
assert.strictEqual(invalidOil.assets.find((asset) => asset.id === "wti").status, "error");
assert.strictEqual(invalidOil.assets.find((asset) => asset.id === "wti").price, null);

const wrongOilSourceMacro = JSON.parse(JSON.stringify(macro));
wrongOilSourceMacro.referenceSeries.RWTC.source.seriesId = "CL=F";
const wrongOilSource = adapter.buildPageData(config, wrongOilSourceMacro, currentNow);
assert.strictEqual(wrongOilSource.assets.find((asset) => asset.id === "wti").status, "error");

const fallbackMacro = JSON.parse(JSON.stringify(macro));
fallbackMacro.referenceSeries.DTWEXBGS.status = "stale";
fallbackMacro.referenceSeries.DTWEXBGS.asOf = "2026-08-03";
fallbackMacro.referenceSeries.DTWEXBGS.previousAsOf = "2026-07-31";
const fallback = adapter.buildPageData(config, fallbackMacro, currentNow);
const fallbackDollar = fallback.assets.find((asset) => asset.id === "dxy");
assert.strictEqual(fallbackDollar.status, "stale");
assert(fallbackDollar.note.includes("自动更新失败"));

const oilFallbackMacro = JSON.parse(JSON.stringify(macro));
oilFallbackMacro.referenceSeries.RWTC.status = "stale";
oilFallbackMacro.referenceSeries.RWTC.asOf = "2026-08-03";
oilFallbackMacro.referenceSeries.RWTC.previousAsOf = "2026-07-31";
const oilFallback = adapter.buildPageData(config, oilFallbackMacro, currentNow).assets.find((asset) => asset.id === "wti");
assert.strictEqual(oilFallback.status, "stale");
assert(oilFallback.note.includes("自动更新未成功"));

const failed = adapter.buildPageDataWithMacroError(config, new Error("HTTP 503"), currentNow);
const unavailableYield = failed.assets.find((asset) => asset.id === "us10y");
const unavailableDollar = failed.assets.find((asset) => asset.id === "dxy");
const unavailableOil = failed.assets.find((asset) => asset.id === "wti");
assert.strictEqual(unavailableYield.status, "error");
assert.strictEqual(unavailableYield.demo, false);
assert.strictEqual(unavailableYield.price, null);
assert.strictEqual(unavailableYield.change, null);
assert.strictEqual(unavailableDollar.status, "error");
assert.strictEqual(unavailableDollar.price, null);
assert.strictEqual(unavailableOil.status, "error");
assert.strictEqual(unavailableOil.price, null);
assert.strictEqual(adapter.businessDaysSince("2026-07-30", new Date("2026-08-03T23:00:00Z")), 2);
assert.strictEqual(adapter.businessDaysSince("2026-07-02", new Date("2026-07-06T23:00:00Z")), 1);

const macroRisk = adapter.adaptMacroRegime(macro, currentNow);
assert.strictEqual(macroRisk.id, "macro-regime");
assert.strictEqual(macroRisk.value, macro.regime.score);
assert.strictEqual(macroRisk.assessment, macro.regime.labelZh + " · " + macro.regime.labelEn);
assert.strictEqual(macroRisk.status, "ok");
assert.strictEqual(macroRisk.asOf, macro.asOf);
assert.strictEqual(macroRisk.updatedAt, macro.updatedAt);
assert.strictEqual(macroRisk.source.name, macro.source);
assert.deepStrictEqual(macroRisk.meterLabels, ["承压", "中性", "支持"]);

const staleRiskMacro = JSON.parse(JSON.stringify(macro));
staleRiskMacro.asOf = "2026-07-27";
const staleMacroRisk = adapter.adaptMacroRegime(staleRiskMacro, currentNow);
assert.strictEqual(staleMacroRisk.status, "stale");
assert(staleMacroRisk.note.includes("超过2个美国工作日"));

const fallbackRiskMacro = JSON.parse(JSON.stringify(macro));
fallbackRiskMacro.live = false;
const fallbackMacroRisk = adapter.adaptMacroRegime(fallbackRiskMacro, currentNow);
assert.strictEqual(fallbackMacroRisk.status, "stale");
assert(fallbackMacroRisk.note.includes("命中不足"));

const invalidRiskMacro = JSON.parse(JSON.stringify(macro));
invalidRiskMacro.regime.score = 101;
const invalidMacroRisk = adapter.buildRiskCards({ macro: { data: invalidRiskMacro, error: null } }, currentNow)[0];
assert.strictEqual(invalidMacroRisk.status, "error");
assert.strictEqual(invalidMacroRisk.value, null);

const failedMacroRisk = adapter.buildRiskCards({ macro: { data: null, error: new Error("HTTP 503") } }, currentNow)[0];
assert.strictEqual(failedMacroRisk.status, "error");
assert.strictEqual(failedMacroRisk.value, null);

const fearGreedRisk = adapter.adaptFearGreed(fearGreed, currentNow);
assert.strictEqual(fearGreedRisk.id, "fear-greed");
assert.strictEqual(fearGreedRisk.value, fearGreed.score);
assert.strictEqual(fearGreedRisk.assessment, fearGreed.ratingZh);
assert.strictEqual(fearGreedRisk.status, "ok");
assert.strictEqual(fearGreedRisk.asOf, fearGreed.asOf);
assert.strictEqual(fearGreedRisk.updatedAt, fearGreed.updatedAt);
assert(fearGreedRisk.changeText.includes("较上一收盘"));
assert.deepStrictEqual(fearGreedRisk.meterLabels, ["极度恐惧", "中性", "极度贪婪"]);

const staleFearGreed = JSON.parse(JSON.stringify(fearGreed));
staleFearGreed.asOf = "2026-07-27";
const staleFearGreedRisk = adapter.adaptFearGreed(staleFearGreed, currentNow);
assert.strictEqual(staleFearGreedRisk.status, "stale");
assert(staleFearGreedRisk.note.includes("超过2个美国工作日"));

const invalidFearGreed = JSON.parse(JSON.stringify(fearGreed));
invalidFearGreed.refs.now.score = invalidFearGreed.score - 1;
const riskCardsWithInvalidFear = adapter.buildRiskCards({
  macro: { data: macro, error: null },
  fearGreed: { data: invalidFearGreed, error: null },
  ofr: { data: ofr, error: null }
}, currentNow);
assert.strictEqual(riskCardsWithInvalidFear.length, 3);
assert.strictEqual(riskCardsWithInvalidFear[0].status, "ok");
assert.strictEqual(riskCardsWithInvalidFear[1].status, "error");
assert.strictEqual(riskCardsWithInvalidFear[1].value, null);
assert.strictEqual(riskCardsWithInvalidFear[2].status, "ok");

const riskCardsWithFearFailure = adapter.buildRiskCards({
  macro: { data: macro, error: null },
  fearGreed: { data: null, error: new Error("HTTP 503") },
  ofr: { data: ofr, error: null }
}, currentNow);
assert.strictEqual(riskCardsWithFearFailure[0].status, "ok");
assert.strictEqual(riskCardsWithFearFailure[1].status, "error");
assert.strictEqual(riskCardsWithFearFailure[2].status, "ok");

const ofrRisk = adapter.adaptOfrFsi(ofr, currentNow);
assert.strictEqual(ofrRisk.id, "ofr-fsi");
assert.strictEqual(ofrRisk.value, ofr.fsi.value);
assert.strictEqual(ofrRisk.assessment, "低于历史平均压力");
assert.strictEqual(ofrRisk.status, "ok");
assert.strictEqual(ofrRisk.asOf, ofr.fsi.asOf);
assert.strictEqual(ofrRisk.updatedAt, ofr.updatedAt);
assert(ofrRisk.changeText.includes((ofr.fsi.change > 0 ? "+" : ofr.fsi.change < 0 ? "−" : "")
  + Math.abs(ofr.fsi.change).toFixed(2)));
assert(ofrRisk.changeText.includes(ofr.fsi.change > 0 ? "压力上升" : ofr.fsi.change < 0 ? "压力下降" : "压力持平"));

const partialOfr = JSON.parse(JSON.stringify(ofr));
partialOfr.fsi.change = null;
const partialOfrRisk = adapter.adaptOfrFsi(partialOfr, currentNow);
assert.strictEqual(partialOfrRisk.status, "partial");
assert.strictEqual(partialOfrRisk.value, ofr.fsi.value);
assert(partialOfrRisk.note.includes("变化字段缺失"));

const staleOfr = JSON.parse(JSON.stringify(ofr));
staleOfr.fsi.asOf = "2026-07-23";
const staleOfrRisk = adapter.adaptOfrFsi(staleOfr, currentNow);
assert.strictEqual(staleOfrRisk.status, "stale");
assert(staleOfrRisk.note.includes("超过5个美国工作日"));

const invalidOfr = JSON.parse(JSON.stringify(ofr));
invalidOfr.fsi.url = "https://example.com/fsi";
const riskCardsWithInvalidOfr = adapter.buildRiskCards({
  macro: { data: macro, error: null },
  fearGreed: { data: fearGreed, error: null },
  ofr: { data: invalidOfr, error: null }
}, currentNow);
assert.strictEqual(riskCardsWithInvalidOfr[0].status, "ok");
assert.strictEqual(riskCardsWithInvalidOfr[1].status, "ok");
assert.strictEqual(riskCardsWithInvalidOfr[2].status, "error");
assert.strictEqual(riskCardsWithInvalidOfr[2].value, null);

const riskCardsWithOfrFailure = adapter.buildRiskCards({
  macro: { data: macro, error: null },
  fearGreed: { data: fearGreed, error: null },
  ofr: { data: null, error: new Error("HTTP 503") }
}, currentNow);
assert.strictEqual(riskCardsWithOfrFailure[0].status, "ok");
assert.strictEqual(riskCardsWithOfrFailure[1].status, "ok");
assert.strictEqual(riskCardsWithOfrFailure[2].status, "error");

const macroOperationHealth = adapter.adaptMacroSourceHealth(macroHealth, macro, currentNow);
assert.strictEqual(macroOperationHealth.dataset, "macro-radar");
assert.strictEqual(macroOperationHealth.status, "degraded");
assert.strictEqual(macroOperationHealth.pipelineStatus, "degraded");
assert.strictEqual(macroOperationHealth.availableCoveragePct, 100);
assert.strictEqual(macroOperationHealth.freshCoveragePct, 0);
assert.strictEqual(macroOperationHealth.historyKnown, false);
assert.strictEqual(macroOperationHealth.consecutiveFailures, null);
assert.strictEqual(macroOperationHealth.reportStale, false);

const operationSources = {
  macro: { data: macro, error: null },
  macroHealth: { data: macroHealth, error: null },
  assetTracker: { data: assetTracker, error: null },
  assetTrackerHealth: { data: assetTrackerHealth, error: null },
  companies: { data: companies, error: null },
  companiesHealth: { data: companiesHealth, error: null },
  assetRanking: { data: assetRanking, error: null },
  assetRankingHealth: { data: assetRankingHealth, error: null }
};
const operationCards = adapter.buildOperationsCards(operationSources, currentNow);
assert.strictEqual(operationCards.length, 4);
assert.deepStrictEqual(operationCards.map((card) => card.id), [
  "macro-radar", "asset-tracker", "companies", "asset-ranking"
]);
assert(operationCards.every((card) => card.status === "degraded"));
assert.deepStrictEqual(operationCards.map((card) => card.publishedRecords), [3, 28, 500, 250]);
assert.deepStrictEqual(operationCards.map((card) => card.expectedRecords), [3, 28, 500, 250]);
assert.deepStrictEqual(operationCards.map((card) => card.availableCoveragePct), [100, 100, 100, 100]);
assert.deepStrictEqual(operationCards.map((card) => card.freshCoveragePct), [
  macroHealth.coverage.freshCoveragePct,
  assetTrackerHealth.coverage.freshCoveragePct,
  companiesHealth.coverage.freshCoveragePct,
  assetRankingHealth.coverage.freshCoveragePct
]);
assert(operationCards.every((card) => card.historyKnown === false));

const staleOperationCards = adapter.buildOperationsCards(operationSources, expiredOfficialHealthNow);
assert(staleOperationCards.every((card) => card.status === "stale"));
assert(staleOperationCards.every((card) => card.reportStale === true));
assert(staleOperationCards[0].note.includes("不代表当前任务仍在正常运行"));

const tamperedMacroHealth = JSON.parse(JSON.stringify(macroHealth));
tamperedMacroHealth.coverage.freshCoveragePct = 100;
assert.throws(() => adapter.adaptMacroSourceHealth(tamperedMacroHealth, macro, currentNow), /覆盖率/);
const tamperedOperationSources = Object.assign({}, operationSources, {
  macroHealth: { data: tamperedMacroHealth, error: null }
});
const tamperedOperationCards = adapter.buildOperationsCards(tamperedOperationSources, currentNow);
assert.strictEqual(tamperedOperationCards[0].status, "unknown");
assert.strictEqual(tamperedOperationCards[0].contractKnown, false);
assert(tamperedOperationCards.slice(1).every((card) => card.status === "degraded"));

const mismatchedMacroSnapshot = JSON.parse(JSON.stringify(macro));
mismatchedMacroSnapshot.updatedAt = "2026-08-03T22:00:00Z";
assert.throws(() => adapter.adaptMacroSourceHealth(macroHealth, mismatchedMacroSnapshot, currentNow), /快照时间不一致/);
const failedOperationSources = Object.assign({}, operationSources, {
  companiesHealth: { data: null, error: new Error("HTTP 503") }
});
const failedOperationCards = adapter.buildOperationsCards(failedOperationSources, currentNow);
assert.strictEqual(failedOperationCards[2].status, "unknown");
assert.strictEqual(failedOperationCards[2].publishedRecords, null);
assert(failedOperationCards[2].note.includes("HTTP 503"));
assert.strictEqual(failedOperationCards[0].status, "degraded");

const crossAsset = adapter.adaptCrossAsset(assetTracker, currentNow, assetTrackerHealth);
assert.strictEqual(crossAsset.id, "cross-asset");
assert.strictEqual(crossAsset.status, "partial");
assert.strictEqual(crossAsset.asOf, assetTracker.asOf);
assert.strictEqual(crossAsset.updatedAt, assetTracker.updatedAt);
assert.strictEqual(crossAsset.source.name, "Yahoo Finance");
assert.strictEqual(crossAsset.periods.length, 5);
assert.strictEqual(crossAsset.assets.length, assetTracker.assets.length);
assert.deepStrictEqual(crossAsset.quality.counts, assetTracker.dataQuality.counts);
assert.strictEqual(crossAsset.quality.declaredValid, true);
assert.strictEqual(crossAsset.quality.contractKnown, true);
assert.strictEqual(crossAsset.sourceHealth.status, "degraded");
assert.strictEqual(crossAsset.sourceHealth.freshCoveragePct, assetTrackerHealth.coverage.freshCoveragePct);
assert.strictEqual(crossAsset.sourceHealth.historyKnown, false);
assert.strictEqual(crossAsset.sourceHealth.consecutiveFailures, null);
assert.strictEqual(crossAsset.sourceHealth.reportStale, false);
const expiredTrackerHealth = adapter.adaptSourceHealth(
  assetTrackerHealth, "asset-tracker", assetTracker, expiredOfficialHealthNow
);
assert.strictEqual(expiredTrackerHealth.status, "stale");
assert.strictEqual(expiredTrackerHealth.pipelineStatus, "degraded");
assert.strictEqual(expiredTrackerHealth.reportStale, true);
assert(expiredTrackerHealth.note.includes("不代表当前行情新鲜度"));
const failedTrackerHealth = JSON.parse(JSON.stringify(assetTrackerHealth));
Object.assign(failedTrackerHealth, {
  generatedAt: "2026-08-08T20:00:00Z",
  lastAttemptAt: "2026-08-08T20:00:00Z",
  status: "failed",
  historyStatus: "tracked",
  consecutiveFailures: 1,
  snapshotPreserved: true,
  failureReason: "测试整源失败，保留旧快照。"
});
failedTrackerHealth.attempt = {
  status: "failed", published: false, producedRecords: 28,
  counts: { market: 0, fallback: 0, estimate: 0, unknown: 0, unavailable: 28 }
};
const retainedCrossAsset = adapter.adaptCrossAsset(assetTracker, currentNow, failedTrackerHealth);
assert.strictEqual(retainedCrossAsset.sourceHealth.status, "failed");
assert.strictEqual(retainedCrossAsset.sourceHealth.snapshotPreserved, true);
assert.strictEqual(retainedCrossAsset.sourceHealth.consecutiveFailures, 1);
assert(retainedCrossAsset.sourceHealth.note.includes("最后有效快照"));
const mismatchedTrackerHealth = JSON.parse(JSON.stringify(assetTrackerHealth));
mismatchedTrackerHealth.publishedSnapshotAt = "2026-07-31T00:00:00Z";
const unverifiedTrackerHealth = adapter.adaptCrossAsset(assetTracker, currentNow, mismatchedTrackerHealth).sourceHealth;
assert.strictEqual(unverifiedTrackerHealth.status, "unknown");
assert.strictEqual(unverifiedTrackerHealth.contractKnown, false);
const fallbackAsset = crossAsset.assets.find((asset) => asset.dataMeta.mode === "fallback");
assert(fallbackAsset && fallbackAsset.dataMeta.asOf === null);
assert(fallbackAsset.dataLabel.includes("历史回退"));
const ytdRanking = adapter.rankCrossAssetPeriod(crossAsset, "ytd");
const expectedYtd = assetTracker.assets
  .filter((asset) => !asset.stale && !asset.suspect && Number.isFinite(asset.returns.ytd))
  .sort((a, b) => a.returns.ytd - b.returns.ytd);
assert.strictEqual(ytdRanking.coverage, expectedYtd.length);
assert.strictEqual(ytdRanking.total, assetTracker.assets.length);
assert.deepStrictEqual(ytdRanking.leaders.map((asset) => asset.symbol), expectedYtd.slice(-3).reverse().map((asset) => asset.symbol));
assert.deepStrictEqual(ytdRanking.laggards.map((asset) => asset.symbol), expectedYtd.slice(0, 3).map((asset) => asset.symbol));
assert(ytdRanking.leaders.concat(ytdRanking.laggards).every((asset) => !asset.stale && !asset.suspect));
assert.strictEqual(adapter.periodTabTargetIndex(0, "ArrowRight", 5), 1);
assert.strictEqual(adapter.periodTabTargetIndex(4, "ArrowRight", 5), 0);
assert.strictEqual(adapter.periodTabTargetIndex(0, "ArrowLeft", 5), 4);
assert.strictEqual(adapter.periodTabTargetIndex(2, "Home", 5), 0);
assert.strictEqual(adapter.periodTabTargetIndex(2, "End", 5), 4);
assert.strictEqual(adapter.periodTabTargetIndex(2, "Enter", 5), 2);

const freshAssetTracker = JSON.parse(JSON.stringify(assetTracker));
freshAssetTracker.updatedAt = "2026-08-08T20:00:00Z";
freshAssetTracker.asOf = "2026-08-08";
freshAssetTracker.status = "ok";
freshAssetTracker.assets.forEach((asset) => {
  asset.stale = false;
  asset.suspect = false;
  asset.dataMeta = {
    mode: "market", status: "ok", source: "Yahoo Finance", asOf: freshAssetTracker.asOf,
    updatedAt: freshAssetTracker.updatedAt, frequency: "daily"
  };
});
freshAssetTracker.dataQuality = {
  contractVersion: 1, status: "ok", total: freshAssetTracker.assets.length,
  counts: { market: freshAssetTracker.assets.length, fallback: 0, estimate: 0, unknown: 0, unavailable: 0 },
  sources: [{ name: "Yahoo Finance", count: freshAssetTracker.assets.length }]
};
const freshCrossAsset = adapter.adaptCrossAsset(freshAssetTracker, currentNow);
assert.strictEqual(freshCrossAsset.status, "ok");
assert.strictEqual(freshCrossAsset.quality.counts.market, 28);

const mismatchedTrackerQuality = JSON.parse(JSON.stringify(freshAssetTracker));
mismatchedTrackerQuality.dataQuality.counts.market -= 1;
assert.strictEqual(adapter.adaptCrossAsset(mismatchedTrackerQuality, currentNow).status, "partial");

const legacyAssetTracker = JSON.parse(JSON.stringify(freshAssetTracker));
delete legacyAssetTracker.dataQuality;
legacyAssetTracker.assets.forEach((asset) => { delete asset.dataMeta; });
const legacyCrossAsset = adapter.adaptCrossAsset(legacyAssetTracker, currentNow);
assert.strictEqual(legacyCrossAsset.status, "partial");
assert.strictEqual(legacyCrossAsset.quality.contractKnown, false);

const staleAssetTracker = JSON.parse(JSON.stringify(freshAssetTracker));
staleAssetTracker.updatedAt = "2026-07-30T20:00:00Z";
staleAssetTracker.asOf = "2026-07-30";
const staleCrossAsset = adapter.adaptCrossAsset(staleAssetTracker, currentNow);
assert.strictEqual(staleCrossAsset.status, "stale");
assert.strictEqual(adapter.rankCrossAssetPeriod(staleCrossAsset, "d1").paused, true);
assert.strictEqual(adapter.rankCrossAssetPeriod(staleCrossAsset, "ytd").paused, false);

const invalidAssetTracker = JSON.parse(JSON.stringify(assetTracker));
invalidAssetTracker.source = "Unknown feed";
const invalidResearch = adapter.buildResearchCards({
  assetTracker: { data: invalidAssetTracker, error: null },
  assetRanking: { data: assetRanking, error: null },
  companies: { data: companies, error: null }
}, currentNow);
assert.strictEqual(invalidResearch.length, 3);
assert.strictEqual(invalidResearch[0].status, "error");
assert.strictEqual(invalidResearch[0].assets.length, 0);
assert.strictEqual(invalidResearch[1].status, "partial");
assert.strictEqual(invalidResearch[2].status, "partial");

const failedResearch = adapter.buildResearchCards({
  assetTracker: { data: null, error: new Error("HTTP 503") },
  assetRanking: { data: assetRanking, error: null },
  companies: { data: companies, error: null }
}, currentNow);
assert.strictEqual(failedResearch.length, 3);
assert.strictEqual(failedResearch[0].status, "error");
assert.strictEqual(failedResearch[0].assets.length, 0);
assert.strictEqual(failedResearch[1].status, "partial");
assert.strictEqual(failedResearch[2].status, "partial");

const globalAssets = adapter.adaptAssetRanking(assetRanking, currentNow, assetRankingHealth);
assert.strictEqual(globalAssets.id, "asset-ranking");
assert.strictEqual(globalAssets.status, "partial");
assert.strictEqual(globalAssets.count, assetRanking.count);
assert.strictEqual(globalAssets.totalMarketCap, assetRanking.totalMarketCap);
assert.strictEqual(globalAssets.asOf, assetRanking.asOf);
assert.strictEqual(globalAssets.updatedAt, assetRanking.updatedAt);
assert.strictEqual(globalAssets.assets.length, 5);
assert.deepStrictEqual(globalAssets.assets.map((asset) => asset.name), assetRanking.assets.slice(0, 5).map((asset) => asset.name));
assert.deepStrictEqual(globalAssets.assets.map((asset) => asset.marketCap), assetRanking.assets.slice(0, 5).map((asset) => asset.marketCap));
assert(globalAssets.assets.some((asset) => asset.static));
assert(globalAssets.assets.some((asset) => !asset.static));
assert.deepStrictEqual(globalAssets.quality.counts, assetRanking.dataQuality.counts);
assert.strictEqual(globalAssets.quality.declaredValid, true);
assert.strictEqual(globalAssets.sourceHealth.status, "degraded");
assert.strictEqual(globalAssets.sourceHealth.freshCoveragePct,
  Math.round(assetRanking.dataQuality.counts.market / assetRanking.count * 10000) / 100);
assert.strictEqual(globalAssets.sourceHealth.verifiedCoveragePct,
  Math.round((assetRanking.dataQuality.counts.market + assetRanking.dataQuality.counts.fallback
    + assetRanking.dataQuality.counts.estimate) / assetRanking.count * 10000) / 100);
assert(globalAssets.assets[0].dataLabel.includes("静态估算") && globalAssets.assets[0].dataLabel.includes("Savills"));
globalAssets.assets.forEach((asset, index) => {
  const mode = assetRanking.assets[index].dataMeta.mode;
  if (mode === "estimate") assert(asset.dataLabel.includes("静态估算"));
  if (mode === "fallback") assert(asset.dataLabel.includes("历史回退"));
  if (mode === "unknown") assert.strictEqual(asset.dataLabel, "来源待确认");
});
assert(globalAssets.note.includes(assetRanking.dataQuality.counts.unknown + "项旧快照"));

const freshAssetRanking = JSON.parse(JSON.stringify(assetRanking));
freshAssetRanking.updatedAt = "2026-08-08T20:00:00Z";
freshAssetRanking.asOf = "2026-08-08";
freshAssetRanking.status = "ok";
freshAssetRanking.assets.forEach((asset) => {
  asset.stale = false;
  const estimate = asset.static === true || asset.private === true;
  asset.dataMeta = {
    mode: estimate ? "estimate" : "market",
    status: "ok",
    source: asset.dataMeta.source,
    asOf: estimate ? "2026-08-01" : "2026-08-08T20:00:00Z",
    updatedAt: freshAssetRanking.updatedAt,
    frequency: estimate ? "irregular" : "daily"
  };
});
freshAssetRanking.dataQuality = qualityDeclaration(freshAssetRanking.assets);
const freshGlobalAssets = adapter.adaptAssetRanking(freshAssetRanking, currentNow);
assert.strictEqual(freshGlobalAssets.status, "ok");
const expectedFreshRankingEstimates = freshAssetRanking.assets
  .filter((asset) => asset.static === true || asset.private === true).length;
assert.strictEqual(freshGlobalAssets.quality.counts.market,
  freshAssetRanking.assets.length - expectedFreshRankingEstimates);
assert.strictEqual(freshGlobalAssets.quality.counts.estimate, expectedFreshRankingEstimates);

const fallbackAssetRanking = JSON.parse(JSON.stringify(freshAssetRanking));
const fallbackRankingRow = fallbackAssetRanking.assets.find((asset) => asset.dataMeta.mode === "market");
fallbackRankingRow.stale = true;
fallbackRankingRow.dataMeta = {
  mode: "fallback", status: "stale", source: fallbackRankingRow.dataMeta.source,
  asOf: "2026-08-02T20:00:00Z", updatedAt: "2026-08-02T20:10:00Z", frequency: "daily"
};
fallbackAssetRanking.dataQuality = qualityDeclaration(fallbackAssetRanking.assets);
const fallbackGlobalAssets = adapter.adaptAssetRanking(fallbackAssetRanking, currentNow);
assert.strictEqual(fallbackGlobalAssets.status, "partial");
assert.strictEqual(fallbackGlobalAssets.quality.counts.fallback, 1);

const mismatchedRankingQuality = JSON.parse(JSON.stringify(freshAssetRanking));
mismatchedRankingQuality.dataQuality.counts.market -= 1;
assert.strictEqual(adapter.adaptAssetRanking(mismatchedRankingQuality, currentNow).status, "partial");

const legacyAssetRanking = JSON.parse(JSON.stringify(freshAssetRanking));
delete legacyAssetRanking.dataQuality;
legacyAssetRanking.assets.forEach((asset) => { delete asset.dataMeta; });
const legacyGlobalAssets = adapter.adaptAssetRanking(legacyAssetRanking, currentNow);
assert.strictEqual(legacyGlobalAssets.status, "partial");
assert.strictEqual(legacyGlobalAssets.quality.contractKnown, false);

const staleAssetRanking = JSON.parse(JSON.stringify(freshAssetRanking));
staleAssetRanking.updatedAt = "2026-07-30T20:00:00Z";
staleAssetRanking.asOf = "2026-07-30";
assert.strictEqual(adapter.adaptAssetRanking(staleAssetRanking, currentNow).status, "stale");

const invalidAssetRanking = JSON.parse(JSON.stringify(assetRanking));
invalidAssetRanking.source = "Yahoo Finance";
const invalidRankingResearch = adapter.buildResearchCards({
  assetTracker: { data: assetTracker, error: null },
  assetRanking: { data: invalidAssetRanking, error: null },
  companies: { data: companies, error: null }
}, currentNow);
assert.strictEqual(invalidRankingResearch[0].status, "partial");
assert.strictEqual(invalidRankingResearch[1].status, "error");
assert.strictEqual(invalidRankingResearch[1].totalMarketCap, null);

const brokenTopRanking = JSON.parse(JSON.stringify(assetRanking));
brokenTopRanking.assets[0].marketCap = null;
const brokenTopResearch = adapter.buildResearchCards({
  assetTracker: { data: assetTracker, error: null },
  assetRanking: { data: brokenTopRanking, error: null },
  companies: { data: companies, error: null }
}, currentNow);
assert.strictEqual(brokenTopResearch[0].status, "partial");
assert.strictEqual(brokenTopResearch[1].status, "error");

const failedRankingResearch = adapter.buildResearchCards({
  assetTracker: { data: assetTracker, error: null },
  assetRanking: { data: null, error: new Error("HTTP 503") },
  companies: { data: companies, error: null }
}, currentNow);
assert.strictEqual(failedRankingResearch[0].status, "partial");
assert.strictEqual(failedRankingResearch[1].status, "error");

const companyLeaders = adapter.adaptCompanies(companies, currentNow, companiesHealth);
const listedCompanies = companies.companies.filter((company) => !company.private);
assert.strictEqual(companyLeaders.id, "company-leaders");
assert.strictEqual(companyLeaders.status, "partial");
assert.strictEqual(companyLeaders.listedCount, companies.listedCount);
assert.strictEqual(companyLeaders.privateCount, companies.privateCount);
assert.strictEqual(companyLeaders.asOf, companies.asOf);
assert.strictEqual(companyLeaders.updatedAt, companies.updatedAt);
assert(companyLeaders.source.name.includes("Yahoo Finance") && companyLeaders.source.name.includes("multiples.vc"));
assert.deepStrictEqual(companyLeaders.topCompanies.map((company) => company.symbol), listedCompanies.slice(0, 3).map((company) => company.symbol));
assert.strictEqual(companyLeaders.gainer, null);
assert.strictEqual(companyLeaders.laggard, null);
assert.strictEqual(companyLeaders.moverCoverage, 0);
assert.strictEqual(companyLeaders.quality.counts.market, 0);
assert.strictEqual(companyLeaders.quality.counts.estimate, 50);
assert.strictEqual(companyLeaders.quality.counts.unknown, 450);
assert.strictEqual(companyLeaders.quality.declaredValid, true);
assert.strictEqual(companyLeaders.sourceHealth.status, "degraded");
assert.strictEqual(companyLeaders.sourceHealth.freshCoveragePct, 0);
assert.strictEqual(companyLeaders.sourceHealth.verifiedCoveragePct, 10);
assert(companyLeaders.note.includes("暂停当日领涨与领跌"));
assert(companyLeaders.topCompanies.every((company) => company.dataLabel === "来源待确认"));
assert(Math.abs(companyLeaders.listedMarketCap - listedCompanies.reduce((sum, company) => sum + company.marketCap, 0)) < 1e-9);
const monitoredResearch = adapter.buildResearchCards({
  assetTracker: { data: assetTracker, error: null },
  assetTrackerHealth: { data: assetTrackerHealth, error: null },
  assetRanking: { data: assetRanking, error: null },
  assetRankingHealth: { data: assetRankingHealth, error: null },
  companies: { data: companies, error: null },
  companiesHealth: { data: companiesHealth, error: null }
}, currentNow);
assert.strictEqual(monitoredResearch.length, 3);
assert(monitoredResearch.every((card) => card.sourceHealth.contractKnown));

const freshCompanies = JSON.parse(JSON.stringify(companies));
freshCompanies.updatedAt = "2026-08-08T20:00:00Z";
freshCompanies.asOf = "2026-08-08";
freshCompanies.companies.forEach((company) => {
  if (!company.private) {
    if (!Number.isFinite(company.changePct)) company.changePct = 0;
    company.stale = false;
    company.dataMeta = {
      mode: "market", status: "ok", source: "Yahoo Finance", asOf: "2026-08-08T20:00:00Z",
      updatedAt: freshCompanies.updatedAt, frequency: "daily"
    };
  }
});
freshCompanies.dataQuality = qualityDeclaration(freshCompanies.companies);
freshCompanies.status = freshCompanies.dataQuality.status;
const freshCompanyLeaders = adapter.adaptCompanies(freshCompanies, currentNow);
const freshListedCompanies = freshCompanies.companies.filter((company) => !company.private);
const freshExpectedMovers = freshListedCompanies.slice().sort((a, b) => a.changePct - b.changePct);
assert.strictEqual(freshCompanyLeaders.status, "ok");
assert.strictEqual(freshCompanyLeaders.moverCoverage, freshCompanies.listedCount);
assert.strictEqual(freshCompanyLeaders.gainer.symbol, freshExpectedMovers[freshExpectedMovers.length - 1].symbol);
assert.strictEqual(freshCompanyLeaders.laggard.symbol, freshExpectedMovers[0].symbol);
assert.strictEqual(freshCompanyLeaders.gainer.private, false);
assert.strictEqual(freshCompanyLeaders.laggard.private, false);

const fallbackCompanies = JSON.parse(JSON.stringify(freshCompanies));
fallbackCompanies.companies[0].stale = true;
fallbackCompanies.companies[0].dataMeta.mode = "fallback";
fallbackCompanies.companies[0].dataMeta.status = "stale";
fallbackCompanies.dataQuality = qualityDeclaration(fallbackCompanies.companies);
fallbackCompanies.status = fallbackCompanies.dataQuality.status;
const fallbackCompanyLeaders = adapter.adaptCompanies(fallbackCompanies, currentNow);
assert.strictEqual(fallbackCompanyLeaders.status, "partial");
assert.strictEqual(fallbackCompanyLeaders.quality.counts.fallback, 1);
assert.strictEqual(fallbackCompanyLeaders.moverCoverage, freshCompanies.listedCount - 1);
assert.notStrictEqual(fallbackCompanyLeaders.gainer.symbol, fallbackCompanies.companies[0].symbol);

const staleCompanies = JSON.parse(JSON.stringify(freshCompanies));
staleCompanies.updatedAt = "2026-07-30T20:00:00Z";
staleCompanies.asOf = "2026-07-30";
assert.strictEqual(adapter.adaptCompanies(staleCompanies, currentNow).status, "stale");

const invalidCompanies = JSON.parse(JSON.stringify(companies));
invalidCompanies.source = "Unknown feed";
const invalidCompanyResearch = adapter.buildResearchCards({
  assetTracker: { data: assetTracker, error: null },
  assetRanking: { data: assetRanking, error: null },
  companies: { data: invalidCompanies, error: null }
}, currentNow);
assert.strictEqual(invalidCompanyResearch[0].status, "partial");
assert.strictEqual(invalidCompanyResearch[1].status, "partial");
assert.strictEqual(invalidCompanyResearch[2].status, "error");
assert.strictEqual(invalidCompanyResearch[2].listedMarketCap, null);

const brokenCompanyTotal = JSON.parse(JSON.stringify(freshCompanies));
brokenCompanyTotal.totalMarketCap += 100;
const brokenCompanyResearch = adapter.buildResearchCards({
  assetTracker: { data: assetTracker, error: null },
  assetRanking: { data: assetRanking, error: null },
  companies: { data: brokenCompanyTotal, error: null }
}, currentNow);
assert.strictEqual(brokenCompanyResearch[2].status, "error");

const failedCompanyResearch = adapter.buildResearchCards({
  assetTracker: { data: assetTracker, error: null },
  assetRanking: { data: assetRanking, error: null },
  companies: { data: null, error: new Error("HTTP 503") }
}, currentNow);
assert.strictEqual(failedCompanyResearch[0].status, "partial");
assert.strictEqual(failedCompanyResearch[1].status, "partial");
assert.strictEqual(failedCompanyResearch[2].status, "error");

const calendar = adapter.adaptEconomicCalendar(econCalendar, currentNow);
assert.strictEqual(calendar.id, "economic-calendar");
assert.strictEqual(calendar.status, "ok");
assert.strictEqual(calendar.count, econCalendar.events.length);
assert.strictEqual(calendar.highCount, econCalendar.events.filter((event) => event.impact === "high").length);
assert.strictEqual(calendar.asOf, econCalendar.asOf);
assert.strictEqual(calendar.updatedAt, econCalendar.updatedAt);
assert.strictEqual(calendar.source.name, "Forex Factory 经济日历");
assert(calendar.events.length > 0 && calendar.events.length <= 4);
assert(calendar.events.every((event) => ["high", "medium"].includes(event.impact)));
if (calendar.selectionLabel === "接下来重要事件") {
  assert(calendar.events.every((event) => Date.parse(event.ts) >= currentNow.getTime()));
  assert(calendar.events.every((event, index) => index === 0
    || event.timestamp >= calendar.events[index - 1].timestamp));
} else {
  assert.strictEqual(calendar.selectionLabel, "最近重要事件");
  assert(calendar.events.every((event) => Date.parse(event.ts) < currentNow.getTime()));
  assert(calendar.events.every((event, index) => index === 0
    || event.timestamp <= calendar.events[index - 1].timestamp));
}

const partialCalendar = JSON.parse(JSON.stringify(econCalendar));
partialCalendar.count += 1;
assert.strictEqual(adapter.adaptEconomicCalendar(partialCalendar, currentNow).status, "partial");

const staleCalendar = JSON.parse(JSON.stringify(econCalendar));
staleCalendar.updatedAt = "2026-07-31T12:00:00Z";
assert.strictEqual(adapter.adaptEconomicCalendar(staleCalendar, currentNow).status, "stale");

const invalidCalendar = JSON.parse(JSON.stringify(econCalendar));
invalidCalendar.source = "Unknown calendar";
const invalidInformation = adapter.buildInformationCards({
  calendar: { data: invalidCalendar, error: null }
}, currentNow);
assert.strictEqual(invalidInformation.length, 1);
assert.strictEqual(invalidInformation[0].status, "error");
assert.strictEqual(invalidInformation[0].events.length, 0);

const failedInformation = adapter.buildInformationCards({
  calendar: { data: null, error: new Error("HTTP 503") }
}, currentNow);
assert.strictEqual(failedInformation.length, 1);
assert.strictEqual(failedInformation[0].status, "error");
assert.strictEqual(failedInformation[0].events.length, 0);

const newsNow = new Date(Date.parse(financeNews.updatedAt) + 60 * 60 * 1000);
const news = adapter.adaptFinanceNews(financeNews, newsNow);
const marketItems = financeNews.categories.find((category) => category.key === "markets").items;
const expectedNews = marketItems.slice().sort((a, b) => b.published - a.published).slice(0, 5);
assert.strictEqual(news.id, "finance-news");
assert.strictEqual(news.status, "ok");
assert.strictEqual(news.count, marketItems.length);
assert.strictEqual(news.articles.length, 5);
assert.strictEqual(news.asOf, financeNews.asOf);
assert.strictEqual(news.updatedAt, financeNews.updatedAt);
assert.strictEqual(news.source.name, "Google News RSS · 原媒体");
assert.deepStrictEqual(news.articles.map((item) => item.title), expectedNews.map((item) => item.title));
assert(news.articles.every((item) => adapter.isSafeGoogleNewsUrl(item.link)));
assert(news.articles.every((item, index) => index === 0 || item.published <= news.articles[index - 1].published));
assert(news.articles.every((item) => !Object.prototype.hasOwnProperty.call(item, "price")));

const partialNews = JSON.parse(JSON.stringify(financeNews));
partialNews.categories.find((category) => category.key === "markets").items[0].link = "https://example.com/unsafe";
assert.strictEqual(adapter.adaptFinanceNews(partialNews, newsNow).status, "partial");

assert.strictEqual(adapter.adaptFinanceNews(financeNews, currentNow).status, "stale");

const invalidNews = JSON.parse(JSON.stringify(financeNews));
invalidNews.source = "Yahoo Finance";
const invalidNewsInformation = adapter.buildInformationCards({
  news: { data: invalidNews, error: null }
}, newsNow);
assert.strictEqual(invalidNewsInformation.length, 1);
assert.strictEqual(invalidNewsInformation[0].status, "error");
assert.strictEqual(invalidNewsInformation[0].articles.length, 0);

const failedNewsInformation = adapter.buildInformationCards({
  news: { data: null, error: new Error("HTTP 503") }
}, newsNow);
assert.strictEqual(failedNewsInformation.length, 1);
assert.strictEqual(failedNewsInformation[0].status, "error");
assert.strictEqual(failedNewsInformation[0].articles.length, 0);

const combinedInformation = adapter.buildInformationCards({
  calendar: { data: econCalendar, error: null },
  news: { data: financeNews, error: null }
}, newsNow);
assert.strictEqual(combinedInformation.length, 2);
assert.strictEqual(combinedInformation[0].id, "economic-calendar");
assert.strictEqual(combinedInformation[1].id, "finance-news");

console.log("DGS10 + DTWEXBGS + RWTC JavaScript adapter states: PASS");
console.log("- official / automatic / stale / missing / invalid / request-error: PASS");
console.log("Macro regime adapter states: PASS");
console.log("- active / stale / retained fallback / invalid / request-error: PASS");
console.log("CNN Fear & Greed adapter states: PASS");
console.log("- active / stale / invalid / independent request-error: PASS");
console.log("OFR Financial Stress adapter states: PASS");
console.log("- active / partial / stale / invalid-source / independent request-error: PASS");
console.log("Cross-asset performance adapter states: PASS");
console.log("- period ranking / excluded stale rows / partial / stale / invalid-source / request-error: PASS");
console.log("Global asset ranking adapter states: PASS");
console.log("- total / top-five order / static-vs-market / partial / stale / invalid-source / request-error: PASS");
console.log("Global company leaders adapter states: PASS");
console.log("- listed top-three / movers / private exclusion / total / partial / stale / invalid-source / request-error: PASS");
console.log("Aggregate source health adapter states: PASS");
console.log("- migrated history / coverage / failed-attempt retention / snapshot mismatch / independent health request: PASS");
console.log("Economic calendar adapter states: PASS");
console.log("- event counts / impact filter / local-time input / partial / stale / invalid-source / request-error: PASS");
console.log("Finance news adapter states: PASS");
console.log("- market-only / latest-five / safe links / partial / stale / invalid-source / request-error: PASS");
"""
    result = subprocess.run(
        ["node", "-e", script],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    require(result.returncode == 0, f"DGS10、DTWEXBGS与RWTC JavaScript适配测试失败：\n{result.stdout}{result.stderr}")
    print(result.stdout.strip())


def main() -> None:
    for path in (
        PAGE, APP, DATA, MACRO_DATA, FEAR_GREED_DATA, FEAR_GREED_HEALTH, OFR_DATA, OFR_HEALTH,
        ASSET_TRACKER_DATA, ASSET_TRACKER_HEALTH, ASSET_RANKING_DATA, ASSET_RANKING_HEALTH,
        COMPANIES_DATA, COMPANIES_HEALTH,
        ECON_CALENDAR_DATA, ECON_CALENDAR_HEALTH, FINANCE_NEWS_DATA, FINANCE_NEWS_HEALTH,
        MACRO_BUILD, MACRO_WORKFLOW, FEAR_GREED_WORKFLOW, OFR_WORKFLOW, ASSET_TRACKER_WORKFLOW,
        ASSET_RANKING_WORKFLOW, COMPANIES_WORKFLOW, ECON_CALENDAR_WORKFLOW, FINANCE_NEWS_WORKFLOW,
        SCHEDULER_WORKFLOW, SOURCE_HEALTH_VALIDATOR, SOURCE_HEALTH_DOC,
        SUPPORTING_HEALTH_VALIDATOR, SUPPORTING_HEALTH_DOC, HOME,
    ):
        require(path.is_file(), f"缺少文件：{path.relative_to(ROOT)}")

    data = json.loads(DATA.read_text(encoding="utf-8"))
    macro = json.loads(MACRO_DATA.read_text(encoding="utf-8"))
    fear_greed = json.loads(FEAR_GREED_DATA.read_text(encoding="utf-8"))
    fear_greed_health = json.loads(FEAR_GREED_HEALTH.read_text(encoding="utf-8"))
    ofr = json.loads(OFR_DATA.read_text(encoding="utf-8"))
    ofr_health = json.loads(OFR_HEALTH.read_text(encoding="utf-8"))
    asset_tracker = json.loads(ASSET_TRACKER_DATA.read_text(encoding="utf-8"))
    asset_tracker_health = json.loads(ASSET_TRACKER_HEALTH.read_text(encoding="utf-8"))
    asset_ranking = json.loads(ASSET_RANKING_DATA.read_text(encoding="utf-8"))
    asset_ranking_health = json.loads(ASSET_RANKING_HEALTH.read_text(encoding="utf-8"))
    companies = json.loads(COMPANIES_DATA.read_text(encoding="utf-8"))
    companies_health = json.loads(COMPANIES_HEALTH.read_text(encoding="utf-8"))
    econ_calendar = json.loads(ECON_CALENDAR_DATA.read_text(encoding="utf-8"))
    econ_calendar_health = json.loads(ECON_CALENDAR_HEALTH.read_text(encoding="utf-8"))
    finance_news = json.loads(FINANCE_NEWS_DATA.read_text(encoding="utf-8"))
    finance_news_health = json.loads(FINANCE_NEWS_HEALTH.read_text(encoding="utf-8"))
    for dataset_name, dataset, health, rows_key in (
        ("asset-tracker", asset_tracker, asset_tracker_health, "assets"),
        ("asset-ranking", asset_ranking, asset_ranking_health, "assets"),
        ("companies", companies, companies_health, "companies"),
    ):
        health_errors = validate_source_health(
            health,
            dataset=dataset_name,
            published_rows=dataset.get(rows_key, []),
            published_snapshot_at=dataset.get("updatedAt"),
        )
        require(not health_errors, dataset_name + "来源健康无效：" + "；".join(health_errors))
    for dataset_name, dataset, health in (
        ("fear-greed", fear_greed, fear_greed_health),
        ("ofr-monitor", ofr, ofr_health),
        ("econ-calendar", econ_calendar, econ_calendar_health),
        ("whats-latest", finance_news, finance_news_health),
    ):
        validate_supporting_health(dataset_name, dataset, health)
    require(data.get("schemaVersion") == 2, "data.json schemaVersion必须为2")
    require(data.get("demo") is True, "仍含演示资产时，data.json必须包含demo: true")
    require(data.get("status") == "partial", "混合数据配置状态必须为partial")
    require(
        "DGS10" in data.get("source", "") and "DTWEXBGS" in data.get("source", "")
        and "RWTC" in data.get("source", "") and "演示" in data.get("source", ""),
        "总来源必须同时标注DGS10、DTWEXBGS、RWTC与演示数据",
    )
    parse_iso(data["updatedAt"])

    assets = data.get("assets")
    require(isinstance(assets, list) and len(assets) == 8, "必须且只能包含8项核心资产")
    require({asset.get("symbol") for asset in assets} == EXPECTED_SYMBOLS, "资产代码与需求不一致")
    require(len({asset.get("id") for asset in assets}) == 8, "资产ID必须唯一")

    demo_assets = [asset for asset in assets if asset.get("demo") is True]
    real_configs = [asset for asset in assets if asset.get("demo") is False]
    require(len(demo_assets) == 5, "除DGS10、DTWEXBGS与RWTC外必须恰有5项演示资产")
    require({asset.get("id") for asset in real_configs} == {"us10y", "dxy", "wti"}, "真实数据配置必须是us10y、dxy与wti")

    for asset in assets:
        missing = COMMON_ASSET_FIELDS - asset.keys()
        require(not missing, f"{asset.get('symbol', 'unknown')} 缺少字段：{sorted(missing)}")
        require(isinstance(asset["source"], dict) and asset["source"].get("name"), f"{asset['symbol']} 缺少结构化数据来源")
        if asset["demo"] is True:
            require(asset["status"] == "demo", f"{asset['symbol']} 演示状态必须为demo")
            require(isinstance(asset["price"], (int, float)), f"{asset['symbol']} price必须为数值")
            require(isinstance(asset.get("changePct"), (int, float)), f"{asset['symbol']} changePct必须为数值")
            require(isinstance(asset["spark"], list) and len(asset["spark"]) >= 2, f"{asset['symbol']} 缺少演示走势")
            require("演示" in asset["source"]["name"], f"{asset['symbol']} 来源必须明确标注为演示")
            parse_date(asset["asOf"])
            parse_iso(asset["updatedAt"])

    real_by_id = {asset["id"]: asset for asset in real_configs}
    dgs10_config = real_by_id["us10y"]
    require(dgs10_config["symbol"] == "DGS10", "美债卡片代码必须为DGS10")
    require(dgs10_config["status"] == "loading", "DGS10静态配置必须以loading状态等待适配")
    require(dgs10_config["price"] is None and dgs10_config.get("change") is None, "不得把模拟DGS10数值留在静态配置中")
    require(dgs10_config.get("changeUnit") == "bp", "DGS10变化单位必须为bp")
    require(dgs10_config["source"].get("seriesId") == "DGS10", "DGS10来源序列ID不一致")
    require(dgs10_config.get("dataRef") == "../macro-radar/data.json#DGS10", "DGS10必须复用宏观雷达数据")

    dollar_config = real_by_id["dxy"]
    require(dollar_config["name"] == "美联储广义美元指数", "DTWEXBGS页面名称不准确")
    require(dollar_config["symbol"] == "DTWEXBGS", "广义美元卡片不得继续显示为DXY")
    require(dollar_config["status"] == "loading", "DTWEXBGS配置必须以loading状态等待适配")
    require("snapshot" not in dollar_config, "DTWEXBGS自动更新后不得继续标记为静态快照")
    require(dollar_config.get("changePct") is None, "DTWEXBGS涨跌幅必须由当前值和前值计算")
    require(dollar_config.get("price") is None and dollar_config.get("previousPrice") is None, "DTWEXBGS价格不得继续存放在终端配置中")
    require(dollar_config.get("asOf") is None and dollar_config.get("updatedAt") is None, "DTWEXBGS时间不得继续存放在终端配置中")
    require(dollar_config["source"].get("seriesId") == "DTWEXBGS", "DTWEXBGS来源序列ID不一致")
    require(dollar_config["source"].get("url") == "https://fred.stlouisfed.org/series/DTWEXBGS", "DTWEXBGS来源链接不准确")
    require(
        dollar_config.get("dataRef") == "../macro-radar/data.json#referenceSeries.DTWEXBGS",
        "DTWEXBGS必须指向宏观雷达自动更新记录",
    )

    wti_config = real_by_id["wti"]
    require(wti_config["name"] == "库欣WTI原油现货", "WTI页面名称必须明确为库欣现货")
    require(wti_config["symbol"] == "WTI", "WTI现货卡片代码不准确")
    require(wti_config["status"] == "loading", "RWTC配置必须以loading状态等待适配")
    require(wti_config.get("changePct") is None, "RWTC涨跌幅必须由当前值和前值计算")
    require(wti_config.get("price") is None and wti_config.get("previousPrice") is None, "RWTC价格不得留在终端配置中")
    require(wti_config.get("asOf") is None and wti_config.get("updatedAt") is None, "RWTC时间不得留在终端配置中")
    require(wti_config["source"].get("seriesId") == "RWTC", "WTI来源必须是EIA RWTC")
    require(wti_config["source"].get("url") == "https://www.eia.gov/dnav/pet/hist/rwtcd.htm", "RWTC来源链接不准确")
    require(
        wti_config.get("dataRef") == "../macro-radar/data.json#referenceSeries.RWTC",
        "RWTC必须指向宏观雷达自动更新记录",
    )

    category, row = find_dgs10(macro)
    require(category.get("src") == "FRED", "宏观雷达DGS10来源必须为FRED")
    require(re.fullmatch(r"-?\d+(?:\.\d+)?%", row.get("val", "")) is not None, "DGS10收益率格式无效")
    require(re.fullmatch(r"[+-]?\d+(?:\.\d+)?bp", row.get("chg", ""), flags=re.I) is not None, "DGS10变化必须使用bp")
    parse_date(row["asOf"])
    parse_iso(macro["updatedAt"])

    dollar_reference = (macro.get("referenceSeries") or {}).get("DTWEXBGS")
    require(isinstance(dollar_reference, dict), "宏观雷达缺少DTWEXBGS参考序列")
    require(dollar_reference.get("id") == "DTWEXBGS", "DTWEXBGS参考序列ID无效")
    require(dollar_reference.get("demo") is False, "DTWEXBGS参考序列不得标记为演示数据")
    require(dollar_reference.get("status") in {"ok", "stale"}, "DTWEXBGS参考序列状态无效")
    require(isinstance(dollar_reference.get("price"), (int, float)), "DTWEXBGS自动更新当前值无效")
    require(isinstance(dollar_reference.get("previousPrice"), (int, float)), "DTWEXBGS自动更新前值无效")
    dollar_as_of = date.fromisoformat(dollar_reference["asOf"])
    dollar_previous_as_of = date.fromisoformat(dollar_reference["previousAsOf"])
    require(dollar_previous_as_of < dollar_as_of, "DTWEXBGS自动更新前值日期必须早于当前观测日期")
    parse_iso(dollar_reference["updatedAt"])
    parse_iso(dollar_reference["lastAttemptAt"])
    require(dollar_reference["source"].get("seriesId") == "DTWEXBGS", "DTWEXBGS自动更新来源不准确")
    expected_change = (dollar_reference["price"] / dollar_reference["previousPrice"] - 1) * 100
    require(abs(dollar_reference["changePct"] - expected_change) < 1e-12, "DTWEXBGS自动更新涨跌幅不可复现")

    wti_reference = (macro.get("referenceSeries") or {}).get("RWTC")
    require(isinstance(wti_reference, dict), "宏观雷达缺少RWTC参考序列")
    require(wti_reference.get("id") == "RWTC", "RWTC参考序列ID无效")
    require(wti_reference.get("demo") is False, "RWTC参考序列不得标记为演示数据")
    require(wti_reference.get("status") in {"ok", "stale"}, "RWTC参考序列状态无效")
    require(isinstance(wti_reference.get("price"), (int, float)), "RWTC自动更新当前值无效")
    require(isinstance(wti_reference.get("previousPrice"), (int, float)), "RWTC自动更新前值无效")
    wti_as_of = date.fromisoformat(wti_reference["asOf"])
    wti_previous_as_of = date.fromisoformat(wti_reference["previousAsOf"])
    require(wti_previous_as_of < wti_as_of, "RWTC自动更新前值日期必须早于当前观测日期")
    parse_iso(wti_reference["updatedAt"])
    parse_iso(wti_reference["lastAttemptAt"])
    require(wti_reference["source"].get("seriesId") == "RWTC", "RWTC自动更新来源不准确")
    expected_wti_change = (wti_reference["price"] / wti_reference["previousPrice"] - 1) * 100
    require(abs(wti_reference["changePct"] - expected_wti_change) < 1e-12, "RWTC自动更新涨跌幅不可复现")

    require(fear_greed.get("source") == "CNN Business Fear & Greed Index", "恐慌与贪婪来源不准确")
    require(isinstance(fear_greed.get("score"), (int, float)) and 0 <= fear_greed["score"] <= 100, "恐慌与贪婪读数必须在0至100之间")
    require(isinstance(fear_greed.get("rating"), str) and fear_greed["rating"], "恐慌与贪婪英文评级缺失")
    require(isinstance(fear_greed.get("ratingZh"), str) and fear_greed["ratingZh"], "恐慌与贪婪中文评级缺失")
    require((fear_greed.get("refs") or {}).get("now", {}).get("score") == fear_greed["score"], "恐慌与贪婪当前参考值不一致")
    close_score = (fear_greed.get("refs") or {}).get("close", {}).get("score")
    require(isinstance(close_score, (int, float)) and 0 <= close_score <= 100, "恐慌与贪婪上一收盘参考值无效")
    parse_date(fear_greed["asOf"])
    parse_iso(fear_greed["updatedAt"])

    require(ofr.get("source") == "U.S. Office of Financial Research (OFR)", "OFR数据来源不准确")
    require(isinstance(ofr.get("fsi"), dict), "OFR数据缺少金融压力指数")
    require(isinstance(ofr["fsi"].get("value"), (int, float)), "OFR金融压力读数无效")
    require(isinstance(ofr["fsi"].get("change"), (int, float)), "OFR金融压力日变化无效")
    require(
        ofr["fsi"].get("url") == "https://www.financialresearch.gov/financial-stress-index/",
        "OFR金融压力来源链接不准确",
    )
    parse_date(ofr["fsi"]["asOf"])
    parse_iso(ofr["updatedAt"])

    require(asset_tracker.get("source") == "Yahoo Finance", "跨资产数据来源必须明确为Yahoo Finance")
    require(asset_tracker.get("defaultPeriod") == "ytd", "跨资产默认周期必须为年初至今")
    require(
        {period.get("key") for period in asset_tracker.get("periods", [])} == {"d1", "w1", "m1", "ytd", "y1"},
        "跨资产数据必须包含5个约定周期",
    )
    tracker_assets = asset_tracker.get("assets")
    require(isinstance(tracker_assets, list) and len(tracker_assets) >= 8, "跨资产数据样本不足")
    require(
        all(isinstance(asset.get("name"), str) and isinstance(asset.get("symbol"), str) for asset in tracker_assets),
        "跨资产数据缺少名称或代码",
    )
    require(
        sum(isinstance((asset.get("returns") or {}).get("ytd"), (int, float)) for asset in tracker_assets) >= 8,
        "跨资产年初至今回报有效样本不足",
    )
    require(asset_tracker.get("frequency") == "daily", "跨资产文件级frequency必须为daily")
    tracker_quality_errors = validate_data_quality(tracker_assets, asset_tracker.get("dataQuality"))
    require(not tracker_quality_errors, "跨资产逐条数据契约无效：" + "；".join(tracker_quality_errors))
    tracker_counts = asset_tracker["dataQuality"]["counts"]
    require(asset_tracker.get("status") == asset_tracker["dataQuality"]["status"],
            "跨资产文件级status必须与逐条质量汇总一致")
    require(sum(tracker_counts.values()) == len(tracker_assets)
            and tracker_counts["estimate"] == 0 and tracker_counts["unavailable"] == 0,
            "跨资产逐条状态计数必须完整且不得混入估值或不可用记录")
    tracker_fallbacks = [asset for asset in tracker_assets if asset["dataMeta"]["mode"] == "fallback"]
    tracker_stale_rows = [asset for asset in tracker_assets if asset.get("stale") is True]
    require(len(tracker_fallbacks) == len(tracker_stale_rows) == tracker_counts["fallback"],
            "跨资产回退模式必须与逐条stale字段一致")
    require(all(asset["dataMeta"]["asOf"] is not None
                or "旧" in asset["dataMeta"].get("note", "")
                for asset in tracker_fallbacks),
            "缺少精确数据日的跨资产回退必须披露旧快照限制")
    require(all(asset["dataMeta"]["source"] == "Yahoo Finance" for asset in tracker_assets),
            "跨资产逐条来源必须明确为Yahoo Finance")
    require("ETF" in asset_tracker.get("note", "") and "期货代理" in asset_tracker.get("note", ""), "跨资产数据未披露代理标的口径")
    parse_date(asset_tracker["asOf"])
    parse_iso(asset_tracker["updatedAt"])

    ranking_source = asset_ranking.get("source", "")
    require(
        all(name in ranking_source for name in ("Yahoo Finance", "CoinGecko", "公开估算")),
        "全球资产市值来源必须披露行情、加密货币和公开估算",
    )
    ranking_assets = asset_ranking.get("assets")
    require(
        isinstance(ranking_assets, list) and len(ranking_assets) == asset_ranking.get("count") == 250,
        "全球资产市值榜必须包含250项",
    )
    require(
        all(isinstance(asset.get("marketCap"), (int, float)) and asset["marketCap"] > 0 for asset in ranking_assets),
        "全球资产市值分项必须为正数",
    )
    require(
        all(asset.get("rank") == index for index, asset in enumerate(ranking_assets, 1)),
        "全球资产市值排名必须连续",
    )
    require(
        all(ranking_assets[index - 1]["marketCap"] >= ranking_assets[index]["marketCap"] for index in range(1, len(ranking_assets))),
        "全球资产市值必须按市值降序排列",
    )
    ranking_total = sum(asset["marketCap"] for asset in ranking_assets)
    require(abs(ranking_total - asset_ranking.get("totalMarketCap", 0)) <= 1, "全球资产总市值不可由分项复现")
    require(any(asset.get("static") is True for asset in ranking_assets[:5]), "榜首样本必须覆盖慢变量估算标签")
    require(any(asset.get("static") is False for asset in ranking_assets[:5]), "榜首样本必须覆盖随行情更新标签")
    require(asset_ranking.get("frequency") == "daily", "全球资产榜文件级frequency必须为daily")
    ranking_quality_errors = validate_data_quality(ranking_assets, asset_ranking.get("dataQuality"))
    require(not ranking_quality_errors, "全球资产榜逐条数据契约无效：" + "；".join(ranking_quality_errors))
    ranking_counts = asset_ranking["dataQuality"]["counts"]
    require(asset_ranking.get("status") == asset_ranking["dataQuality"]["status"],
            "全球资产榜文件级status必须与逐条质量汇总一致")
    require(sum(ranking_counts.values()) == len(ranking_assets) and ranking_counts["unavailable"] == 0,
            "全球资产榜逐条状态计数必须完整且当前快照不得含不可用记录")
    static_ranking_rows = [asset for asset in ranking_assets if asset.get("static") is True]
    private_ranking_rows = [asset for asset in ranking_assets if asset.get("private") is True]
    require(len(static_ranking_rows) == 6
            and all(asset["dataMeta"]["mode"] == "estimate" for asset in static_ranking_rows),
            "全球资产榜慢变量必须明确标记为静态估值")
    require(private_ranking_rows
            and all(asset["dataMeta"]["mode"] == "estimate" for asset in private_ranking_rows),
            "全球资产榜中的未上市公司必须透传静态估值状态")
    require(ranking_counts["estimate"] >= len(static_ranking_rows) + len(private_ranking_rows),
            "全球资产榜估值计数不得少于慢变量与未上市公司之和")
    require(all(asset["dataMeta"]["asOf"] is None
                for asset in ranking_assets if asset["dataMeta"]["mode"] == "unknown"),
            "旧全球资产行情快照不得以文件日期冒充逐条行情日期")
    require(all(asset["dataMeta"]["asOf"] is None for asset in static_ranking_rows),
            "未保存原报告日期的慢变量不得以文件日期冒充估值日期")
    expected_missing_private_dates = sum(not isinstance(asset.get("lastRound"), str)
                                         or not asset["lastRound"].strip()
                                         for asset in private_ranking_rows)
    require(sum(asset["dataMeta"]["asOf"] is None for asset in private_ranking_rows)
            == expected_missing_private_dates,
            "全球资产榜必须按未上市公司融资月份透传估值日期缺失状态")
    ranking_fallbacks = [asset for asset in ranking_assets if asset["dataMeta"]["mode"] == "fallback"]
    require("慢变量" in asset_ranking.get("note", "")
            and all("沿用" in asset["dataMeta"].get("note", "")
                    or "旧" in asset["dataMeta"].get("note", "") for asset in ranking_fallbacks),
            "全球资产市值数据未披露慢变量或回退快照限制")
    parse_date(asset_ranking["asOf"])
    parse_iso(asset_ranking["updatedAt"])

    require(companies.get("source") == "Yahoo Finance", "公司榜来源必须明确为Yahoo Finance")
    company_rows = companies.get("companies")
    require(
        isinstance(company_rows, list) and len(company_rows) == companies.get("count") == 500,
        "公司榜必须包含500项",
    )
    listed_rows = [company for company in company_rows if company.get("private") is not True]
    private_rows = [company for company in company_rows if company.get("private") is True]
    require(len(listed_rows) == companies.get("listedCount") == 450, "公司榜上市公司数量不一致")
    require(len(private_rows) == companies.get("privateCount") == 50, "公司榜未上市公司数量不一致")
    require(
        all(isinstance(company.get("marketCap"), (int, float)) and company["marketCap"] > 0 for company in company_rows),
        "公司榜市值必须为正数",
    )
    require(
        all(company.get("rank") == index for index, company in enumerate(company_rows, 1)),
        "公司榜排名必须连续",
    )
    require(
        all(listed_rows[index - 1]["marketCap"] >= listed_rows[index]["marketCap"] for index in range(1, len(listed_rows))),
        "上市公司必须按市值降序排列",
    )
    company_total = sum(company["marketCap"] for company in company_rows)
    require(abs(company_total - companies.get("totalMarketCap", 0)) <= 1, "公司榜总市值不可由分项复现")
    valid_company_changes = [
        company for company in listed_rows
        if isinstance(company.get("changePct"), (int, float)) and -100 <= company["changePct"] <= 1000
    ]
    require(len(valid_company_changes) >= 20, "上市公司当日涨跌有效样本不足")
    require(all(company.get("private") is not True for company in valid_company_changes), "未上市公司不得进入当日涨跌样本")
    require(companies.get("frequency") == "daily", "公司榜文件级frequency必须为daily")
    company_quality_errors = validate_data_quality(company_rows, companies.get("dataQuality"))
    require(not company_quality_errors, "公司榜逐条数据契约无效：" + "；".join(company_quality_errors))
    company_counts = companies["dataQuality"]["counts"]
    require(companies.get("status") == companies["dataQuality"]["status"],
            "公司榜文件级status必须与逐条质量汇总一致")
    require(sum(company_counts.values()) == len(company_rows)
            and company_counts["estimate"] == len(private_rows) and company_counts["unavailable"] == 0,
            "公司榜逐条状态计数必须覆盖全部记录，并与未上市估值数量一致")
    require(all(company["dataMeta"]["mode"] in {"market", "fallback", "unknown"}
                and (company.get("stale") is True) == (company["dataMeta"]["mode"] == "fallback")
                for company in listed_rows),
            "上市公司行情、回退和待确认模式必须与stale字段一致")
    require(all(company["dataMeta"]["mode"] == "estimate" and company["dataMeta"]["frequency"] == "irregular"
                for company in private_rows), "未上市公司必须标记为不定期静态估值")
    expected_missing_company_dates = sum(not isinstance(company.get("lastRound"), str)
                                         or not company["lastRound"].strip() for company in private_rows)
    require(sum(company["dataMeta"]["asOf"] is None for company in private_rows)
            == expected_missing_company_dates,
            "未上市估值日期缺失必须与融资月份字段一致")
    for company in private_rows:
        if company["dataMeta"]["asOf"]:
            parse_date(company["dataMeta"]["asOf"])
    require("未上市" in companies.get("note", "") and "非实时" in companies.get("note", ""), "公司榜未披露未上市估值口径")
    parse_date(companies["asOf"])
    parse_iso(companies["updatedAt"])

    require(econ_calendar.get("source") == "Forex Factory 经济日历", "经济日历来源必须明确为Forex Factory")
    calendar_events = econ_calendar.get("events")
    require(
        isinstance(calendar_events, list) and len(calendar_events) == econ_calendar.get("count") and len(calendar_events) > 0,
        "经济日历事件数必须与count一致且非空",
    )
    require(
        all(event.get("impact") in {"high", "medium", "low", "holiday"} for event in calendar_events),
        "经济日历影响级别无效",
    )
    require(
        all(
            isinstance(event.get("title"), str) and event["title"]
            and isinstance(event.get("country"), str) and event["country"]
            and isinstance(event.get("ccy"), str) and event["ccy"]
            for event in calendar_events
        ),
        "经济日历事件缺少标题、国家或货币代码",
    )
    require(
        all(event.get(field) is None or isinstance(event.get(field), str)
            for event in calendar_events for field in ("actual", "forecast", "previous")),
        "经济日历实际、预测或前值必须是字符串或空值",
    )
    calendar_times = [datetime.fromisoformat(event["ts"].replace("Z", "+00:00")) for event in calendar_events]
    require(calendar_times == sorted(calendar_times), "经济日历事件必须按时间升序排列")
    require(
        sum(event.get("impact") == "high" for event in calendar_events) == econ_calendar.get("highCount"),
        "经济日历高影响事件数不可由分项复现",
    )
    require(re.fullmatch(r"\d{4}-\d{2}-\d{2}\s*~\s*\d{4}-\d{2}-\d{2}", econ_calendar.get("weekOf", "")) is not None,
            "经济日历周范围格式无效")
    require("实际值" in econ_calendar.get("note", ""), "经济日历说明未披露实际值回填")
    parse_date(econ_calendar["asOf"])
    parse_iso(econ_calendar["updatedAt"])

    require("Google News" in finance_news.get("source", ""), "财经新闻总来源必须包含Google News")
    news_categories = finance_news.get("categories")
    require(isinstance(news_categories, list), "财经新闻缺少板块列表")
    market_categories = [category for category in news_categories if category.get("key") == "markets"]
    require(len(market_categories) == 1 and market_categories[0].get("name") == "市场", "财经新闻必须且只能包含一个市场板块")
    market_news = market_categories[0].get("items")
    require(isinstance(market_news, list) and len(market_news) >= 3, "财经新闻市场板块有效样本不足")
    require(
        all(
            isinstance(item.get("title"), str) and item["title"]
            and isinstance(item.get("source"), str) and item["source"]
            and isinstance(item.get("published"), (int, float)) and item["published"] > 0
            for item in market_news
        ),
        "财经新闻缺少标题、原媒体或发布时间",
    )
    require(
        all(re.fullmatch(r"https://news\.google\.com/rss/articles/[A-Za-z0-9_-]+(?:\?[^\s]*)?", item.get("link", ""))
            for item in market_news),
        "财经新闻链接必须是Google News RSS文章链接",
    )
    require(len({item["link"] for item in market_news}) == len(market_news), "财经新闻市场板块不得包含重复链接")
    require("每条均链接回原文" in finance_news.get("note", ""), "财经新闻说明未披露原文链接口径")
    parse_date(finance_news["asOf"])
    parse_iso(finance_news["updatedAt"])

    page = PAGE.read_text(encoding="utf-8")
    app = APP.read_text(encoding="utf-8")
    home = HOME.read_text(encoding="utf-8")
    require("当前为部分演示数据" in page, "页面首屏缺少部分演示数据提示")
    require("FRED API使用条款" in page and "未获圣路易斯联储认可或认证" in page, "页面缺少FRED说明与条款入口")
    require("DTWEXBGS" in page and "不是ICE DXY" in page and "自动更新失败" in page, "页面未准确解释广义美元指数与回退规则")
    require("RWTC" in page and "不是 <code>CL=F</code>" in page and "EIA API文档" in page, "页面未准确解释WTI现货来源与口径")
    require("官方静态快照" not in page, "页面不得继续把DTWEXBGS描述为静态快照")
    require("其余5项" in page, "页面演示资产数量说明不准确")
    require('id="data-banner"' in page and 'id="market-grid"' in page, "页面缺少数据状态或卡片容器")
    require('id="risk-grid"' in page and 'id="risk-summary"' in page and "市场状态" in page, "页面缺少市场状态模块")
    require('id="research-grid"' in page and 'id="research-summary"' in page and "市场强弱与领袖" in page, "页面缺少市场研究模块")
    require('id="information-grid"' in page and 'id="information-summary"' in page and "今日事件与资讯" in page,
            "页面缺少事件资讯模块")
    require('id="operations-grid"' in page and 'id="operations-summary"' in page and "Beta数据运行状态" in page,
            "页面缺少四管道Beta运行状态模块")
    require("健康快照不等于上线门禁通过" in page and "连续成功至少3个日更周期" in page,
            "页面未区分仓库健康快照与远端Beta门禁证据")
    require("finance_terminal_beta_gate.yml" in page and "finance-terminal-data.yml" in page
            and "报告数据问题" in page, "页面缺少远端门禁或结构化数据反馈入口")
    require('class="skip-link" href="#main-content"' in page and 'id="main-content" tabindex="-1"' in page,
            "页面缺少跳到主要内容的键盘入口")
    require('id="page-announcer" role="status" aria-live="polite" aria-atomic="true"' in page,
            "页面缺少原子化加载状态播报")
    require('id="data-banner" role="region"' in page and 'aria-labelledby="banner-title"' in page,
            "数据横幅必须使用有名称的静态区域，避免重复播报")
    require(page.count('aria-live="polite"') == 1, "页面只能保留一个礼貌级实时播报区")
    require(page.count('role="list"') >= 5, "五个动态卡片容器必须使用列表语义")
    require("跨资产强弱" in page and "今日、近一周、近一月、年初至今和近一年" in page, "页面未说明跨资产排行周期")
    require("ETF或期货代理" in page and "超过72小时" in page, "页面未披露跨资产代理口径或过期规则")
    require("全球资产市值" in page and "data.json" in page
            and "无法逐条证明本轮行情路径的记录保持`PARTIAL`" in page
            and "不会用文件更新时间代替" in page, "页面未说明全球资产市值逐条来源限制")
    require("全球公司领袖" in page and "未上市估值不参与涨跌排序" in page, "页面未说明公司领袖的上市范围")
    require("无法逐只证明450家上市公司是本轮成功还是历史回退" in page
            and "暂停“今日领涨/领跌”" in page, "页面未披露公司数据逐项新鲜度限制")
    require("CNN恐慌与贪婪分数" in page and "0–100" in page, "页面未说明CNN恐慌与贪婪指标口径")
    require("OFR金融压力指数以0为历史平均" in page and "正值高于平均压力" in page, "页面未说明OFR金融压力口径")
    require("经济日历复用Forex Factory公开周历" in page and "超过36小时" in page and "设备本地时区" in page,
            "页面未说明经济日历来源、时区或过期规则")
    require("财经新闻只读取“最新消息”数据中的" in page and "Yahoo行情快照不参与终端行情" in page,
            "页面未说明财经新闻板块范围或行情排除规则")
    require("新闻文件超过12小时" in page and "最新文章超过36小时" in page and "Google News跳转原媒体" in page,
            "页面未说明财经新闻时效或跳转来源")
    require("UPDATE HEALTH" in app and "首次迁移无法追溯旧任务" in page
            and "四个辅助来源健康" in page,
            "页面未展示或解释四个辅助来源更新链健康")
    require("official-update-health" in app and "adaptOfficialSourceHealth" in app
            and "三张官方行情卡片" in page and "逐源健康快照" in page,
            "页面未展示或解释三项官方行情逐源更新链健康")
    require('src="app.js"' in page, "页面未加载本地app.js")
    compact_page = re.sub(r"\s+", "", page)
    require(contrast_ratio(css_hex_variable(page, "faint"), css_hex_variable(page, "panel")) >= 4.5,
            "最弱正文色与卡片背景对比度必须达到WCAG AA 4.5:1")
    require('content="width=device-width,initial-scale=1.0"' in compact_page, "页面缺少移动端viewport")
    require(
        ".market-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr))" in compact_page,
        "桌面端必须显示四列市场卡片",
    )
    require(
        ".risk-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr))" in compact_page,
        "桌面端市场状态模块必须支持三列信号卡片",
    )
    require(
        ".research-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr))" in compact_page,
        "桌面端市场研究模块必须支持三列卡片",
    )
    require(
        ".information-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr))" in compact_page,
        "桌面端事件资讯模块必须支持双列卡片",
    )
    require(
        ".operations-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr))" in compact_page,
        "桌面端运行状态模块必须支持四列管道卡片",
    )
    require(
        "@media(max-width:1040px)" in compact_page
        and ".market-grid{grid-template-columns:repeat(2,minmax(0,1fr))" in compact_page,
        "平板端必须显示两列市场卡片",
    )
    require(".hero>*{min-width:0" in compact_page
            and ".hero{grid-template-columns:minmax(0,1fr);gap:30px" in compact_page,
            "窄屏Hero网格必须允许包含不换行元数据的子项收缩")
    require(".meta-grid{grid-template-columns:minmax(0,1fr)" in compact_page,
            "360像素元数据网格必须允许长来源字段收缩并省略")
    require(
        "@media(max-width:1040px)" in compact_page
        and ".risk-grid{grid-template-columns:repeat(2,minmax(0,1fr))" in compact_page,
        "平板端市场状态模块必须使用两列布局",
    )
    require(
        "@media(max-width:1040px)" in compact_page
        and ".research-grid{grid-template-columns:repeat(2,minmax(0,1fr))" in compact_page,
        "平板端市场研究模块必须使用两列布局",
    )
    require(
        "@media(max-width:1040px)" in compact_page
        and ".information-grid{grid-template-columns:1fr" in compact_page,
        "768像素事件资讯模块必须使用单列布局",
    )
    require(
        "@media(max-width:1040px)" in compact_page
        and ".operations-grid{grid-template-columns:repeat(2,minmax(0,1fr))" in compact_page,
        "768像素运行状态模块必须使用两列布局",
    )
    require(
        "@media(max-width:620px)" in compact_page
        and ".market-grid{grid-template-columns:1fr" in compact_page,
        "手机端必须显示单列市场卡片",
    )
    require(
        "@media(max-width:620px)" in compact_page
        and ".risk-grid{grid-template-columns:1fr" in compact_page,
        "手机端市场状态模块必须使用单列布局",
    )
    require(
        "@media(max-width:620px)" in compact_page
        and ".research-grid{grid-template-columns:1fr" in compact_page,
        "手机端市场研究模块必须使用单列布局",
    )
    require(
        "@media(max-width:620px)" in compact_page
        and ".operations-grid{grid-template-columns:1fr" in compact_page,
        "手机端运行状态模块必须使用单列布局",
    )
    require(
        "@media(max-width:620px)" in compact_page
        and ".event-row{grid-template-columns:48pxminmax(0,1fr)" in compact_page,
        "360像素经济事件行必须使用紧凑布局",
    )
    require(
        ".brand,.back-link,.period-tab,.source-link,.detail-link{display:inline-flex;min-height:44px" in compact_page,
        "360像素主要交互控件必须提供至少44像素触控高度",
    )
    require("touch-action:manipulation" in compact_page and ".event-values{display:flex;flex-wrap:wrap;white-space:normal" in compact_page,
            "手机端缺少触控优化或经济数据换行保护")
    require("@media(prefers-reduced-motion:reduce)" in compact_page
            and "animation-duration:0.01ms!important" in compact_page,
            "页面未完整尊重减少动画偏好")
    require("@media(prefers-contrast:more)" in compact_page and "@media(forced-colors:active)" in compact_page,
            "页面缺少高对比偏好或系统强制颜色支持")
    require('MACRO_DATA_URL="../macro-radar/data.json"' in re.sub(r"\s+", "", app), "app.js未读取现有宏观雷达数据")
    require('MACRO_HEALTH_URL="../macro-radar/health.json"' in re.sub(r"\s+", "", app),
            "app.js未读取宏观雷达逐源健康快照")
    require("businessDaysSince" in app and "DGS10_MAX_BUSINESS_DAYS" in app and '"stale"' in app, "app.js未实现DGS10过期判断")
    require("DTWEXBGS_MAX_BUSINESS_DAYS" in app and "findDtwexbgsReference" in app, "app.js未读取DTWEXBGS自动更新记录")
    require("record.price / record.previousPrice" in app and "refreshFailed" in app, "DTWEXBGS涨跌幅或失败回退不可复现")
    require("RWTC_MAX_BUSINESS_DAYS" in app and "findRwtcReference" in app and "adaptRwtc" in app, "app.js未读取RWTC自动更新记录")
    require("MACRO_REGIME_MAX_BUSINESS_DAYS" in app and "adaptMacroRegime" in app and "buildRiskCards" in app, "app.js未接入宏观状态适配层")
    require("FEAR_GREED_DATA_URL" in app and "FEAR_GREED_MAX_BUSINESS_DAYS" in app and "adaptFearGreed" in app, "app.js未接入CNN恐慌与贪婪数据")
    require("OFR_DATA_URL" in app and "OFR_FSI_MAX_BUSINESS_DAYS" in app and "adaptOfrFsi" in app, "app.js未接入OFR金融压力数据")
    require("ASSET_TRACKER_DATA_URL" in app and "ASSET_TRACKER_MAX_AGE_HOURS" in app, "app.js未读取现有跨资产数据")
    require("ASSET_TRACKER_HEALTH_URL" in app and "ASSET_RANKING_HEALTH_URL" in app
            and "COMPANIES_HEALTH_URL" in app, "app.js未读取三条聚合管道健康文件")
    require("adaptSourceHealth" in app and "safeSourceHealth" in app and "appendSourceHealth" in app,
            "app.js未校验或展示来源健康状态")
    require("adaptMacroSourceHealth" in app and "buildOperationsCards" in app
            and "renderOperationsCards" in app and "makeOperationCard" in app,
            "app.js未校验或渲染四管道Beta运行状态")
    require("可用覆盖" in app and "本轮新鲜" in app and "已验证覆盖" in app
            and "失败回退" in app, "运行状态卡片缺少覆盖率、时效或回退说明")
    require("pipeline-health" in page and "本轮行情" in app and "连续失败" in app
            and "最近尝试" in app and "最后成功" in app and "健康报告已超过" in app,
            "页面缺少管道状态、本轮覆盖、尝试时间、过期提示或最后成功信息")
    require("adaptCrossAsset" in app and "rankCrossAssetPeriod" in app and "buildResearchCards" in app, "app.js未实现跨资产适配和排行")
    require("asset.stale" in app and "asset.suspect" in app and "paused" in app, "跨资产排行未排除异常行或暂停过期今日排行")
    require("normalizeDataMeta" in app and "summarizeRowQuality" in app and "appendQualitySummary" in app,
            "跨资产卡片未读取或展示逐条数据状态")
    require("quality-strip" in page and "quality.counts.fallback" in app and "历史回退" in app,
            "页面缺少行情、回退、估算与待确认覆盖信息")
    require("ASSET_RANKING_DATA_URL" in app and "ASSET_RANKING_MAX_AGE_HOURS" in app, "app.js未读取现有全球资产市值数据")
    require("adaptAssetRanking" in app and "formatMarketCapBillions" in app
            and "asset.dataLabel" in app and "summarizeRowQuality(rowMetas, data.dataQuality)" in app,
            "app.js未实现全球资产市值逐条来源适配或口径标签")
    require("COMPANIES_DATA_URL" in app and "COMPANIES_MAX_AGE_HOURS" in app, "app.js未读取现有公司榜数据")
    require("adaptCompanies" in app and "company.private" in app and "freshnessKnown" in app, "app.js未实现上市公司筛选或逐项新鲜度状态")
    require("gainer" in app and "laggard" in app and "listedMarketCap" in app, "app.js未生成公司领涨、领跌和上市市值")
    require("moverCoverage" in app and "暂停当日领涨与领跌" in app and "company.dataLabel" in app,
            "公司榜未按逐条状态暂停或恢复每日涨跌排行")
    require("ECON_CALENDAR_DATA_URL" in app and "ECON_CALENDAR_MAX_AGE_HOURS" in app, "app.js未读取现有经济日历数据")
    require("adaptEconomicCalendar" in app and "buildInformationCards" in app and "normalizeCalendarEvent" in app,
            "app.js未实现经济日历适配、校验或独立状态")
    require("FINANCE_NEWS_DATA_URL" in app and "FINANCE_NEWS_MAX_AGE_HOURS" in app
            and "FINANCE_NEWS_ITEM_MAX_AGE_HOURS" in app, "app.js未读取现有财经新闻或缺少新鲜度规则")
    require("adaptFinanceNews" in app and "isSafeGoogleNewsUrl" in app and "makeFinanceNewsCard" in app,
            "app.js未实现财经新闻适配、安全链接或渲染")
    require('setAttribute("role", "listitem")' in app, "动态卡片缺少列表项语义")
    require("card.tabIndex = 0" not in app and "article.tabIndex = 0" not in app,
            "非交互卡片不得进入键盘Tab顺序")
    require("announceExperience" in app and "pageAnnouncer.textContent" in app,
            "页面未集中播报异步加载结果")
    require('setAttribute("role", "tablist")' in app and 'setAttribute("role", "tab")' in app
            and 'setAttribute("role", "tabpanel")' in app, "跨资产周期未使用标准标签页语义")
    require("periodTabTargetIndex" in app and 'event.key' in app and 'nextButton.focus()' in app,
            "跨资产周期未支持方向键、Home和End键盘导航")
    require('setAttribute("aria-selected"' in app and 'setAttribute("aria-controls"' in app,
            "跨资产周期标签页状态或面板关联缺失")
    require('setAttribute("aria-pressed"' not in app, "标签页不得混用aria-pressed按钮模式")
    require("runBrowserRegressionProbe" in app and "finance-terminal-regression-result" in app
            and "supportingHealthResources" in app and "supportingHealthPanelCount" in app
            and "officialHealthResources" in app and "officialHealthPanelCount" in app,
            "页面缺少浏览器、官方逐源或辅助来源资源回归探针")
    require("noHorizontalOverflow" in app and "responsiveColumns" in app and "targetSizes" in app
            and "keyboardTabs" in app, "浏览器回归探针未覆盖溢出、布局、触控与键盘交互")
    require('document.querySelectorAll(".operation-card").length === 4' in app
            and "renderedGridColumns(operationsGrid)" in app,
            "浏览器回归探针未覆盖四张运行状态卡片或其响应式列数")
    require("undersizedTargets" in app, "浏览器回归结果必须列出尺寸不足的触控目标")
    require(".operation-action" in app, "浏览器回归探针未检查Beta运行与反馈触控目标")
    require("data.markets" not in app and ".markets" not in app, "终端财经新闻不得读取同文件的Yahoo行情快照")
    require('card.status === "partial"' in app and 'text: "PARTIAL"' in app, "市场状态卡片未区分部分数据")
    require("buildPageDataWithMacroError" in app and "unavailableDtwexbgs" in app and "unavailableRwtc" in app and 'status: "error"' in app, "app.js未覆盖官方数据文件失败状态")
    require("changeUnit" in app and '"bp"' in app, "app.js未按bp显示收益率变化")
    require("apps/finance-terminal/" in home, "首页缺少金融终端入口")

    external_scripts = re.findall(r'<script[^>]+src=["\']https?://', page, flags=re.I)
    require(not external_scripts, "金融终端页面不得引入外部脚本依赖")
    build_script = MACRO_BUILD.read_text(encoding="utf-8")
    history_build_script = MACRO_HISTORY_BUILD.read_text(encoding="utf-8")
    workflow = MACRO_WORKFLOW.read_text(encoding="utf-8")
    fear_greed_workflow = FEAR_GREED_WORKFLOW.read_text(encoding="utf-8")
    ofr_workflow = OFR_WORKFLOW.read_text(encoding="utf-8")
    asset_tracker_workflow = ASSET_TRACKER_WORKFLOW.read_text(encoding="utf-8")
    asset_ranking_workflow = ASSET_RANKING_WORKFLOW.read_text(encoding="utf-8")
    companies_workflow = COMPANIES_WORKFLOW.read_text(encoding="utf-8")
    econ_calendar_workflow = ECON_CALENDAR_WORKFLOW.read_text(encoding="utf-8")
    finance_news_workflow = FINANCE_NEWS_WORKFLOW.read_text(encoding="utf-8")
    scheduler = SCHEDULER_WORKFLOW.read_text(encoding="utf-8")
    require(BROWSER_VALIDATOR.exists(), "缺少金融终端真实浏览器回归脚本")
    browser_validator = BROWSER_VALIDATOR.read_text(encoding="utf-8")
    require("[360, 768, 1280]" in browser_validator and "Page.captureScreenshot" in browser_validator
            and "Runtime.evaluate" in browser_validator, "浏览器回归脚本未覆盖三档宽度、渲染DOM和截图")
    require(QUALITY_WORKFLOW.exists(), "缺少金融终端只读质量工作流")
    quality_workflow = QUALITY_WORKFLOW.read_text(encoding="utf-8")
    require("permissions:\n  contents: read" in quality_workflow, "金融终端质量工作流权限必须只读")
    require(".github/ISSUE_TEMPLATE/finance-terminal-data.yml" in quality_workflow,
            "金融终端质量工作流未覆盖数据反馈表单变更")
    require("docs/FINANCE_TERMINAL_OPERATIONS_RUNBOOK.md" in quality_workflow,
            "金融终端质量工作流未覆盖四管道运行手册变更")
    require("validate_finance_terminal_browser.mjs" in quality_workflow and "validate_finance_terminal.py" in quality_workflow,
            "金融终端质量工作流未运行静态与浏览器回归")
    require("validate_market_data_quality.py --dataset all" in quality_workflow,
            "金融终端质量工作流未统一校验三条逐项来源契约")
    require("validate_market_source_health.py --dataset all --report" in quality_workflow
            and "validate_macro_source_health.py --report" in quality_workflow
            and "finance-terminal-source-health" in quality_workflow
            and "retention-days: 14" in quality_workflow,
            "金融终端质量工作流未生成或保留四管道健康诊断")
    require("validate_market_workflow_governance.py --dataset all" in quality_workflow,
            "金融终端质量工作流未统一校验生产与辅助任务治理契约")
    require("validate_supporting_source_health.py --dataset all --report" in quality_workflow
            and "validate_supporting_source_builders.py" in quality_workflow,
            "金融终端质量工作流未校验四个辅助来源健康与离线回退")
    require("deploy" not in quality_workflow.lower() and "secrets." not in quality_workflow,
            "金融终端质量工作流不得部署或读取Secrets")
    require(DATA_ISSUE_FORM.exists(), "缺少金融终端数据问题反馈表单")
    issue_form = DATA_ISSUE_FORM.read_text(encoding="utf-8")
    require(issue_form.count("- type:") == 9 and "id: pipeline" in issue_form
            and "id: problem_type" in issue_form and "id: observed_at" in issue_form,
            "数据反馈表单字段数量或关键ID无效")
    for pipeline_label in ("DGS10 / DTWEXBGS / RWTC", "asset-tracker", "companies", "asset-ranking"):
        require(pipeline_label in issue_form, f"数据反馈表单缺少管道选项：{pipeline_label}")
    require("API密钥" in issue_form and "访问令牌" in issue_form and "持仓" in issue_form
            and issue_form.count("required: true") >= 8,
            "数据反馈表单缺少敏感信息警告或必填约束")
    require(OPERATIONS_RUNBOOK.exists(), "缺少金融终端四管道运行与故障恢复手册")
    runbook = OPERATIONS_RUNBOOK.read_text(encoding="utf-8")
    for required_text in (
        "macro-radar", "asset-tracker", "companies", "asset-ranking",
        "data.json", "health.json", "Beta门禁Artifact", "超过72小时",
        "连续成功至少3个日更周期", "稳定V1至少观察7个周期",
        "不得手工只修其中一个文件", "不得重置或强推共享分支",
    ):
        require(required_text in runbook, f"四管道运行手册缺少关键规则：{required_text}")
    require(runbook.index("运行`Companies Tracker`") < runbook.index("运行`Asset Ranking`"),
            "四管道运行手册必须明确公司榜先于资产榜")
    for command in (
        "validate_finance_terminal.py", "validate_market_data_quality.py --dataset all",
        "validate_market_source_health.py --dataset all", "validate_macro_source_health.py",
        "validate_market_workflow_governance.py --dataset all",
        "validate_finance_terminal_release_gate.py",
    ):
        require(command in runbook, f"四管道运行手册缺少本地检查：{command}")
    require("build_dtwexbgs_reference" in build_script and '"referenceSeries": reference_series' in build_script, "宏观雷达脚本未生成DTWEXBGS参考序列")
    require("build_rwtc_reference" in build_script and '"facets[series][]": RWTC_ID' in build_script, "宏观雷达脚本未按EIA RWTC口径生成参考序列")
    require("requests.get(url, params=params" in build_script, "FRED请求必须把密钥放在参数对象而非日志字符串中")
    require("response = get(EIA_API_URL, params=params" in build_script, "EIA请求必须把密钥放在参数对象而非URL字符串中")
    require("repr(e)" not in build_script and "repr(exc)" not in build_script, "异常日志不得输出可能含密钥的完整请求URL")
    require("requests.get(url, params=params" in history_build_script
            and "&api_key=" not in history_build_script
            and "repr(e)" not in history_build_script and "repr(error)" not in history_build_script,
            "宏观历史任务不得把FRED密钥拼入URL或异常日志")
    require("FRED_API_KEY: ${{ secrets.FRED_API_KEY }}" in workflow, "宏观雷达工作流未通过Secret提供FRED密钥")
    require("EIA_API_KEY: ${{ secrets.EIA_API_KEY }}" in workflow, "宏观雷达工作流未通过Secret引用EIA密钥")
    require("market_workflow_governance.py stage --dataset macro-radar" in workflow
            and "validate_macro_source_health.py --report" in workflow,
            "宏观雷达工作流未使用逐源健康校验与精确路径守卫")
    require("macro_radar.yml" in scheduler, "每日调度器未触发宏观雷达工作流")
    require("python scripts/fear-greed/build_fear_greed.py" in fear_greed_workflow, "恐慌与贪婪工作流未运行既有取数脚本")
    require("validate_supporting_source_health.py --dataset fear-greed" in fear_greed_workflow
            and "market_workflow_governance.py stage --dataset fear-greed" in fear_greed_workflow,
            "恐慌与贪婪工作流未校验健康或使用精确路径守卫")
    require("market-data-fear-greed-${{ github.ref }}" in fear_greed_workflow
            and "retention-days: 14" in fear_greed_workflow,
            "恐慌与贪婪工作流缺少独立并发或短期诊断")
    require("fear_greed.yml" in scheduler, "每日调度器未触发恐慌与贪婪工作流")
    require("python scripts/ofr-monitor/build_ofr.py" in ofr_workflow, "OFR工作流未运行既有取数脚本")
    require("validate_supporting_source_health.py --dataset ofr-monitor" in ofr_workflow
            and "market_workflow_governance.py stage --dataset ofr-monitor" in ofr_workflow,
            "OFR工作流未校验健康或使用精确路径守卫")
    require("market-data-ofr-monitor-${{ github.ref }}" in ofr_workflow
            and "retention-days: 14" in ofr_workflow,
            "OFR工作流缺少独立并发或短期诊断")
    require("ofr_monitor.yml" in scheduler, "每日调度器未触发OFR工作流")
    require("python scripts/asset-tracker/build_assets.py" in asset_tracker_workflow, "跨资产工作流未运行既有取数脚本")
    require("validate_market_data_quality.py --dataset asset-tracker" in asset_tracker_workflow,
            "跨资产工作流未在提交前校验逐条来源契约")
    require("validate_market_source_health.py --dataset asset-tracker" in asset_tracker_workflow,
            "跨资产工作流未在提交前校验来源健康")
    require("market_workflow_governance.py stage --dataset asset-tracker" in asset_tracker_workflow,
            "跨资产工作流未使用路径所有权守卫暂存数据与健康文件")
    require("market-data-asset-tracker-${{ github.ref }}" in asset_tracker_workflow
            and "Sync target branch before generation" in asset_tracker_workflow,
            "跨资产工作流缺少独立并发锁或生成前同步")
    require("asset-tracker-workflow-${{ github.run_attempt }}" in asset_tracker_workflow
            and "retention-days: 14" in asset_tracker_workflow,
            "跨资产工作流未把运行诊断保留为短期Artifact")
    require("asset_tracker.yml" in scheduler, "每日调度器未触发跨资产工作流")
    require("python scripts/asset-ranking/build_ranking.py" in asset_ranking_workflow, "全球资产市值工作流未运行既有取数脚本")
    require("validate_market_data_quality.py --dataset asset-ranking" in asset_ranking_workflow,
            "全球资产市值工作流未在提交前校验逐条来源契约")
    require("validate_market_source_health.py --dataset asset-ranking" in asset_ranking_workflow,
            "全球资产市值工作流未在提交前校验来源健康")
    require("market_workflow_governance.py stage --dataset asset-ranking" in asset_ranking_workflow,
            "全球资产市值工作流未使用路径所有权守卫暂存数据与健康文件")
    require("market-data-asset-ranking-${{ github.ref }}" in asset_ranking_workflow
            and "Sync target branch before generation" in asset_ranking_workflow,
            "全球资产市值工作流缺少独立并发锁或生成前同步")
    require("asset-ranking-workflow-${{ github.run_attempt }}" in asset_ranking_workflow
            and "retention-days: 14" in asset_ranking_workflow,
            "全球资产市值工作流未把运行诊断保留为短期Artifact")
    require("asset_ranking.yml" in scheduler and "companies.yml" in scheduler, "调度器未按公司数据后置触发全球资产市值工作流")
    require("python scripts/companies/build_companies.py" in companies_workflow, "公司榜工作流未运行既有取数脚本")
    require("validate_market_data_quality.py --dataset companies" in companies_workflow,
            "公司榜工作流未在提交前校验逐条来源契约")
    require("validate_market_source_health.py --dataset companies" in companies_workflow,
            "公司榜工作流未在提交前校验来源健康")
    require("market_workflow_governance.py stage --dataset companies" in companies_workflow,
            "公司榜工作流未使用精确路径守卫提交数据、健康状态与本地Logo")
    require("market-data-companies-${{ github.ref }}" in companies_workflow
            and "Sync target branch before generation" in companies_workflow,
            "公司榜工作流缺少独立并发锁或生成前同步")
    require("companies-workflow-${{ github.run_attempt }}" in companies_workflow
            and "retention-days: 14" in companies_workflow,
            "公司榜工作流未把运行诊断保留为短期Artifact")
    require("git add -A apps/companies" not in companies_workflow,
            "公司榜工作流不得宽范围暂存整个应用目录")
    require("companies.yml" in scheduler, "每日调度器未触发公司榜工作流")
    require("python scripts/econ-calendar/build_calendar.py" in econ_calendar_workflow, "经济日历工作流未运行既有取数脚本")
    require("validate_supporting_source_health.py --dataset econ-calendar" in econ_calendar_workflow
            and "market_workflow_governance.py stage --dataset econ-calendar" in econ_calendar_workflow,
            "经济日历工作流未校验健康或使用精确路径守卫")
    require("market-data-econ-calendar-${{ github.ref }}" in econ_calendar_workflow
            and "retention-days: 14" in econ_calendar_workflow,
            "经济日历工作流缺少独立并发或短期诊断")
    require("econ_calendar.yml" in scheduler, "每日调度器未触发经济日历工作流")
    require("python scripts/whats-latest/build_news.py" in finance_news_workflow, "财经新闻工作流未运行既有取数脚本")
    require("validate_supporting_source_health.py --dataset whats-latest" in finance_news_workflow
            and "market_workflow_governance.py stage --dataset whats-latest" in finance_news_workflow,
            "财经新闻工作流未校验健康或使用精确路径守卫")
    require("market-data-whats-latest-${{ github.ref }}" in finance_news_workflow
            and "retention-days: 14" in finance_news_workflow,
            "财经新闻工作流缺少独立并发或短期诊断")
    require("cron: '15 */6 * * *'" in finance_news_workflow, "财经新闻工作流必须保持每6小时更新")
    run_market_data_quality_contract_tests()
    run_company_builder_contract_tests()
    run_asset_ranking_builder_contract_tests()
    run_dtwexbgs_pipeline_tests()
    run_rwtc_pipeline_tests()
    run_js_adapter_tests()

    print("Finance Terminal DGS10 + DTWEXBGS + RWTC validation: PASS")
    print("- two FRED-backed cards, one EIA-backed card and five explicit demo cards: PASS")
    print("- yield percent / change bp / broad-dollar and WTI spot change percent: PASS")
    print("- FRED and EIA refresh success / retained fallback / no-history error: PASS")
    print("- source / as-of / updated-at / stale / unavailable states: PASS")
    print("- homepage route and local data dependency: PASS")
    print("- 360 / 768 / 1280 responsive rules: PASS")
    print("- macro regime value / source / freshness / fallback states: PASS")
    print("- CNN fear & greed score / rating / close delta / freshness / failure states: PASS")
    print("- OFR FSI value / daily change / zero baseline / freshness / partial / failure states: PASS")
    print("- cross-asset five-period ranking / per-row provenance / fallback / freshness / failure states: PASS")
    print("- global asset top-five / total / per-record provenance / mixed-frequency / failure states: PASS")
    print("- company per-row market/fallback/estimate / mover gating / private exclusion / failure states: PASS")
    print("- aggregate source health / coverage / consecutive failure / retained snapshot / diagnostics: PASS")
    print("- four-pipeline Beta operations / macro cross-check / stale snapshot isolation: PASS")
    print("- Beta gate link / structured data feedback / sensitive-input warning: PASS")
    print("- economic calendar counts / impact / local-time input / freshness / independent failure states: PASS")
    print("- finance news market-only / latest-five / safe links / freshness / independent failure states: PASS")
    print("- four supporting feeds / migrated health / partial fallback / retained snapshot / workflow governance: PASS")
    print("- three official card update chains / single-source isolation / stale evidence: PASS")
    print("- no external script dependencies: PASS")
    print("- browser regression probe / read-only CI contract: PASS")


if __name__ == "__main__":
    main()
