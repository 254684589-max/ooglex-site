#!/usr/bin/env python3
"""Validate the Finance Terminal market overview without third-party dependencies."""

from __future__ import annotations

import importlib.util
import json
import math
import re
import subprocess
import sys
import types
from datetime import date, datetime
from pathlib import Path

from market_data_quality import (
    fallback_data_meta,
    make_data_meta,
    make_proxy_meta,
    summarize_data_quality,
    validate_data_quality,
    validate_proxy_meta,
)
from market_source_health import validate_source_health
from supporting_source_health import validate_health as validate_supporting_health
from finance_terminal_readiness_snapshot import validate_snapshot as validate_readiness_snapshot
from finance_terminal_market_licenses import validate_market_source_readiness


ROOT = Path(__file__).resolve().parents[1]
PAGE = ROOT / "apps" / "finance-terminal" / "index.html"
APP = ROOT / "apps" / "finance-terminal" / "app.js"
LOADER = ROOT / "apps" / "finance-terminal" / "finance-terminal-loader.mjs"
TERMINAL_VISUALS = ROOT / "apps" / "finance-terminal" / "finance-terminal-visuals.mjs"
RISK_RADAR_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-risk-radar.mjs"
WORLDMAP_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-worldmap.mjs"
SESSIONS_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-sessions.mjs"
WATCHLIST_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-watchlist.mjs"
HEALTH_ADAPTERS_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-health-adapters.mjs"
DETAIL_VIEW_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-detail-view.mjs"
BOARD_DATA_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-board-data.mjs"
BOARD_VIEW_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-board-view.mjs"
RADAR_VIEW_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-radar-view.mjs"
CURVE_VIEW_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-curve-view.mjs"
GLOBE_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-globe.mjs"
GLOBE_TEXTURE_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-globe-texture.mjs"
ORBIT_LINKS_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-orbit-links.mjs"
GATEWAY_PREVIEW_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-gateway-preview.mjs"
VISION_CSS = ROOT / "apps" / "finance-terminal" / "terminal-vision.css"
VISUAL_FIDELITY_CSS = ROOT / "apps" / "finance-terminal" / "terminal-visual-fidelity.css"
REFERENCE_FIDELITY_CSS = ROOT / "apps" / "finance-terminal" / "terminal-reference-fidelity.css"
AURORA_HOME_CSS = ROOT / "apps" / "finance-terminal" / "terminal-aurora-home.css"
REFERENCE_HOME_V2_CSS = ROOT / "apps" / "finance-terminal" / "terminal-reference-home-v2.css"
REFERENCE_HOME_V3_CSS = ROOT / "apps" / "finance-terminal" / "terminal-reference-home-v3.css"
REFERENCE_HOME_V4_CSS = ROOT / "apps" / "finance-terminal" / "terminal-reference-home-v4.css"
REFERENCE_HOME_V5_CSS = ROOT / "apps" / "finance-terminal" / "terminal-reference-home-v5.css"
COMMAND_CENTER_CSS = ROOT / "apps" / "finance-terminal" / "terminal-command-center.css"
COMMAND_CENTER_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-command-center.mjs"
AURORA_HOME_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-aurora-home.mjs"
REGRESSION_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-regression.mjs"
VISUALS_VALIDATOR = ROOT / "scripts" / "validate_finance_terminal_visuals.mjs"
RISK_VIEW_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-risk-view.mjs"
QUOTE_PAGE = ROOT / "apps" / "finance-terminal" / "quote.html"
BOARD_CSS = ROOT / "apps" / "finance-terminal" / "terminal-board.css"
LIVE_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-live.mjs"
MARKETS_PAGE = ROOT / "apps" / "markets" / "index.html"
MARKETS_MODULE = ROOT / "apps" / "markets" / "markets.mjs"
HOME_PAGE = ROOT / "index.html"
DATA_HUB_APP = ROOT / "apps" / "data-hub" / "app.js"
SITEMAP = ROOT / "sitemap.xml"
QUOTE_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-quote.mjs"
CHART_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-chart.mjs"
GEO_RISK_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-geo-risk.mjs"
RESEARCH_VIEW_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-research-view.mjs"
INFORMATION_VIEW_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-information-view.mjs"
OPERATIONS_VIEW_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-operations-view.mjs"
OPERATIONS_DATA_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-operations-data.mjs"
INFORMATION_DATA_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-information-data.mjs"
CORRELATION_VIEW_MODULE = ROOT / "apps" / "finance-terminal" / "finance-terminal-correlation-view.mjs"
TERMS_PAGE = ROOT / "apps" / "finance-terminal" / "terms.html"
PRIVACY_PAGE = ROOT / "apps" / "finance-terminal" / "privacy.html"
LEGAL_CSS = ROOT / "apps" / "finance-terminal" / "legal.css"
DATA = ROOT / "apps" / "finance-terminal" / "data.json"
READINESS_DATA = ROOT / "apps" / "finance-terminal" / "readiness.json"
MARKET_LICENSE_READINESS = ROOT / "apps" / "finance-terminal" / "market-source-readiness.json"
MACRO_DATA = ROOT / "apps" / "macro-radar" / "data.json"
FEAR_GREED_DATA = ROOT / "apps" / "fear-greed" / "data.json"
FEAR_GREED_HEALTH = ROOT / "apps" / "fear-greed" / "health.json"
OFR_DATA = ROOT / "apps" / "ofr-monitor" / "data.json"
OFR_HEALTH = ROOT / "apps" / "ofr-monitor" / "health.json"
ASSET_TRACKER_DATA = ROOT / "apps" / "asset-tracker" / "data.json"
ASSET_TRACKER_HEALTH = ROOT / "apps" / "asset-tracker" / "health.json"
ASSET_TRACKER_BUILD = ROOT / "scripts" / "asset-tracker" / "build_assets.py"
ASSET_RANKING_DATA = ROOT / "apps" / "asset-ranking" / "data.json"
ASSET_RANKING_HEALTH = ROOT / "apps" / "asset-ranking" / "health.json"
ASSET_RANKING_BUILD = ROOT / "scripts" / "asset-ranking" / "build_ranking.py"
COMPANIES_DATA = ROOT / "apps" / "companies" / "data.json"
COMPANIES_HEALTH = ROOT / "apps" / "companies" / "health.json"
COMPANIES_BUILD = ROOT / "scripts" / "companies" / "build_companies.py"
COMPANIES_HISTORY = ROOT / "apps" / "companies" / "history.json"
ASSET_RANKING_CRYPTO = ROOT / "apps" / "asset-ranking" / "crypto.json"
MARKET_HISTORY_MODULE = ROOT / "scripts" / "market_history.py"
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
BROWSER_EVIDENCE = ROOT / "scripts" / "finance_terminal_browser_evidence.mjs"
BROWSER_EVIDENCE_VALIDATOR = ROOT / "scripts" / "validate_finance_terminal_browser_evidence.mjs"
LOADER_VALIDATOR = ROOT / "scripts" / "validate_finance_terminal_loader.mjs"
BOARD_VALIDATOR = ROOT / "scripts" / "validate_finance_terminal_board.mjs"
PROXY_RUNTIME_HISTORY = ROOT / "scripts" / "finance_terminal_proxy_runtime_history.py"
PROXY_RUNTIME_HISTORY_VALIDATOR = ROOT / "scripts" / "validate_finance_terminal_proxy_runtime_history.py"
DATA_ISSUE_FORM = ROOT / ".github" / "ISSUE_TEMPLATE" / "finance-terminal-data.yml"
OPERATIONS_RUNBOOK = ROOT / "docs" / "FINANCE_TERMINAL_OPERATIONS_RUNBOOK.md"
SOURCE_HEALTH_VALIDATOR = ROOT / "scripts" / "validate_market_source_health.py"
SOURCE_HEALTH_DOC = ROOT / "docs" / "AGGREGATE_SOURCE_HEALTH.md"
SUPPORTING_HEALTH_VALIDATOR = ROOT / "scripts" / "validate_supporting_source_health.py"
SUPPORTING_HEALTH_DOC = ROOT / "docs" / "SUPPORTING_SOURCE_HEALTH.md"
HOME = ROOT / "index.html"

# 2026-08-25 所有者决定：标普500与纳斯达克100两张ETF代理卡撤下，核心资产收敛为
# 六项（两项免费嵌入代理 + 四项站内官方管道）；纳斯达克不再由其他标的顶替。
EXPECTED_SYMBOLS = {"DIA", "DGS10", "DTWEXBGS", "GLD", "WTI", "BTC/USD"}
EXPECTED_PROXIES = {
    "dow": ("DIA", "DJIA", "AMEX:DIA"),
    "gold": ("GLD", "LBMA-GOLD-PM-USD", "AMEX:GLD"),
}
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


def validate_official_observations(record: dict, label: str) -> list[dict]:
    """校验成功刷新后会从迁移点逐步扩展到8点的官方观测窗口。"""
    observations = record.get("observations")
    require(isinstance(observations, list) and 1 <= len(observations) <= 8,
            f"{label}观测窗口必须包含1至8个官方观测点")
    parsed_dates = []
    for index, observation in enumerate(observations):
        require(isinstance(observation, dict)
                and set(observation) == {"asOf", "value"},
                f"{label}第{index + 1}个观测点结构无效")
        try:
            observed_date = date.fromisoformat(observation["asOf"])
        except (TypeError, ValueError) as exc:
            raise AssertionError(f"{label}第{index + 1}个观测日期无效") from exc
        value = observation["value"]
        require(isinstance(value, (int, float)) and not isinstance(value, bool)
                and math.isfinite(value) and value > 0,
                f"{label}第{index + 1}个观测值必须是正有限数")
        parsed_dates.append(observed_date)
    require(all(previous < current for previous, current in zip(parsed_dates, parsed_dates[1:])),
            f"{label}观测日期必须严格递增且不可重复")
    require(observations[-1] == {"asOf": record.get("asOf"), "value": record.get("price")},
            f"{label}观测窗口末值必须与当前官方记录一致")
    if len(observations) >= 2:
        require(observations[-2] == {
            "asOf": record.get("previousAsOf"), "value": record.get("previousPrice")
        }, f"{label}观测窗口倒数第二项必须与前值记录一致")
    return observations


def run_official_observation_contract_tests() -> None:
    one_point = {
        "asOf": "2026-08-06", "price": 4.69,
        "previousAsOf": "2026-08-05", "previousPrice": 4.63,
        "observations": [{"asOf": "2026-08-06", "value": 4.69}],
    }
    require(len(validate_official_observations(one_point, "迁移序列")) == 1,
            "单点迁移窗口应保持有效")
    full_window = {
        "asOf": "2026-08-08", "price": 108.0,
        "previousAsOf": "2026-08-07", "previousPrice": 107.0,
        "observations": [
            {"asOf": f"2026-08-{day:02d}", "value": 100.0 + day}
            for day in range(1, 9)
        ],
    }
    require(len(validate_official_observations(full_window, "完整序列")) == 8,
            "八点完整窗口应保持有效")

    invalid_cases = []
    too_long = json.loads(json.dumps(full_window))
    too_long["observations"].insert(0, {"asOf": "2026-07-31", "value": 99.0})
    invalid_cases.append(too_long)
    reversed_window = json.loads(json.dumps(full_window))
    reversed_window["observations"].reverse()
    invalid_cases.append(reversed_window)
    duplicate_date = json.loads(json.dumps(full_window))
    duplicate_date["observations"][1]["asOf"] = duplicate_date["observations"][0]["asOf"]
    invalid_cases.append(duplicate_date)
    wrong_tail = json.loads(json.dumps(full_window))
    wrong_tail["observations"][-1]["value"] = 999.0
    invalid_cases.append(wrong_tail)
    wrong_previous = json.loads(json.dumps(full_window))
    wrong_previous["observations"][-2]["value"] = 999.0
    invalid_cases.append(wrong_previous)
    non_positive = json.loads(json.dumps(full_window))
    non_positive["observations"][0]["value"] = 0
    invalid_cases.append(non_positive)
    for invalid in invalid_cases:
        try:
            validate_official_observations(invalid, "异常序列")
        except AssertionError:
            continue
        raise AssertionError("无效官方观测窗口未被拒绝")


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
    proxy = make_proxy_meta(
        "etf", "000905.SS", "中证500ETF", "510500.SS",
        currency="CNY", return_basis="price", note="ETF收益率代理，可能存在跟踪误差。",
    )
    proxy_row = {"name": "中证500", "symbol": "510500.SS", "dataMeta": market, "proxy": proxy}
    require(not validate_proxy_meta(proxy_row), "有效ETF代理契约不应被拒绝")
    invalid_proxy_row = json.loads(json.dumps(proxy_row))
    invalid_proxy_row["proxy"]["instrumentSymbol"] = "000905.SS"
    require(validate_proxy_meta(invalid_proxy_row), "实际代码错配的代理契约必须被拒绝")
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

    class SeriesResponse:
        status_code = 200

        @staticmethod
        def json():
            return {"chart": {"result": [{
                "timestamp": [1785715200, 1785801600, 1785888000],
                "indicators": {"quote": [{"close": [10.0, None, 12.5]}]},
            }]}}

    class SeriesSession:
        @staticmethod
        def get(*_args, **_kwargs):
            return SeriesResponse()

    closes = module.yf_daily_closes(SeriesSession(), "TEST")
    require(closes == [("2026-08-03", 10.0), ("2026-08-05", 12.5)],
            "公司日线必须跳过无收盘的交易日，不做前向填充")

    class EmptySession:
        @staticmethod
        def get(*_args, **_kwargs):
            raise RuntimeError("network down")

    require(module.yf_daily_closes(EmptySession(), "TEST") == [],
            "取数失败必须返回空序列，由调用方保留上次历史")
    # 数值改动必须是有意的才该发生；「与行情板那一侧相等」由
    # _require_stock_row_limit_matches_history() 跨语言强制，不再靠两处各钉一个字面量。
    require(module.HISTORY_SYMBOLS == 500 and module.HISTORY_POINTS == 260,
            "公司日线覆盖标的数与滚动长度必须与行情板契约一致")
    require("history" in module.HISTORY_PATH and module.HISTORY_PATH.endswith(".json"),
            "公司日线必须写入独立的history.json，不混进data.json")
    print("Company per-record provenance builder: PASS")


def run_shared_history_contract_tests() -> None:
    """三条管道共用同一份滚动历史规则，且首次生成前的占位文件不得冒充有效数据。"""
    spec = importlib.util.spec_from_file_location("market_history", MARKET_HISTORY_MODULE)
    require(spec is not None and spec.loader is not None, "无法加载共享滚动历史模块")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    history, retained = module.build_rolling_history(
        {"A": [("2026-08-03", 1.0), ("2026-08-05", 3.0)]},
        {"dates": ["2026-08-03", "2026-08-04"], "series": {"B": [9.0, 9.5]}},
        "2026-08-25T00:00:00Z",
        source="TestSource",
        note="test",
    )
    require(history["dates"] == ["2026-08-03", "2026-08-04", "2026-08-05"],
            "共享日期轴必须按日升序合并")
    require(history["series"]["A"][1] is None, "缺观测日必须留空，不做前向填充")
    require(retained == ["B"] and history["series"]["B"][-1] is None,
            "本轮未取到的标的沿用上次序列且不补造新点")
    require(history["source"] == "TestSource" and history["frequency"] == "daily",
            "滚动历史必须标注调用方的真实来源")
    require(module.build_rolling_history({}, {}, "t", source="s", note="n")[0] is None,
            "无任何有效序列时必须返回空，由调用方保留上次文件")

    for path, keys in ((COMPANIES_HISTORY, ("dates", "series")),
                       (ASSET_RANKING_CRYPTO, ("assets", "history"))):
        payload = json.loads(path.read_text(encoding="utf-8"))
        require(payload.get("demo") is not True, f"{path.name}不得标记为演示数据")
        require(payload.get("source") and payload.get("note"),
                f"{path.name}必须写明来源与口径")
        for key in keys:
            require(key in payload, f"{path.name}缺少{key}字段")
        if payload.get("status") == "pending":
            require(not payload.get("dates") and not payload.get("assets"),
                    f"{path.name}标为pending时不得含有任何观测值")
    print("Shared rolling history and pending placeholders: PASS")


def _require_stock_row_limit_matches_history() -> None:
    """行情板的股票行数必须等于公司管道存日线的家数。

    这两个数分别写在 JS 与 Python 里。只改一处，页面上后面几十行就会显示「无序列」——
    页面不会报错，只是静静地少了走势，没人会立刻发现。同类的「常量抄了两份」在本仓库
    已经出过三次（健康记录数、加载器资源数、盘中桶数），所以这里不再各钉一个字面量，
    而是让两处必须相等。
    """
    board = BOARD_DATA_MODULE.read_text(encoding="utf-8")
    match = re.search(r"export const STOCK_ROW_LIMIT\s*=\s*(\d+)", board)
    require(match is not None, "行情板数据层里找不到 STOCK_ROW_LIMIT，同步校验会失效")
    builder = (ROOT / "scripts" / "companies" / "build_companies.py").read_text(encoding="utf-8")
    history = re.search(r"^HISTORY_SYMBOLS\s*=\s*(\d+)", builder, re.M)
    require(history is not None, "公司管道里找不到 HISTORY_SYMBOLS，同步校验会失效")
    require(int(match.group(1)) == int(history.group(1)),
            f"行情板股票行数({match.group(1)})与公司管道存日线的家数({history.group(1)})不一致："
            "多出来的那几行会显示「无序列」")

def _index_registry(name: str) -> set[str]:
    """从行情板数据层里读回某张登记表的代码集合。

    找不到这张表就直接失败，而不是当作空表放行——静默失效的校验比没有校验更糟：
    改名或重构会让它变成永远通过。
    """
    source = BOARD_DATA_MODULE.read_text(encoding="utf-8")
    marker = f"const {name} = Object.freeze({{"
    start = source.find(marker)
    require(start >= 0, f"行情板数据层里找不到登记表 {name}，指数登记校验会失效")
    end = source.find("});", start)
    require(end > start, f"登记表 {name} 的字面量没有正常闭合")
    body = source[start + len(marker):end]
    body = re.sub(r"/\*.*?\*/", " ", body, flags=re.S)      # 去掉块注释里的中文，免得被当成键
    # 键有两种写法：带引号的 "^GSPC" 与裸标识符 EPOL。裸标识符一行可以写好几个，
    # 因此按「前面是 { 或 ,」来断，不能按行首断——那样一行里只认得出第一个。
    normalized = "," + body
    return (set(re.findall(r'"([^"]+)"\s*:', normalized))
            | set(re.findall(r"[{,]\s*([A-Za-z_$][\w$]*)\s*:", normalized)))


def _require_index_registration(assets) -> None:
    """每一个可能落进快照的指数代码，都必须登记了地区与分组。

    「可能落进快照」包括候选列表里的每一个代码：主代码取不到时，落地的是回退或代理
    那一行，只登记主代码会让页面上的「地区」空着、分组掉进「其他」。
    """
    regions = _index_registry("INDEX_REGION")
    groups = _index_registry("INDEX_GROUP")
    candidates: list[str] = []
    for item in assets:
        if item.get("cat") != "equity":
            continue
        for entry in item.get("syms", []):
            candidates.append(entry if isinstance(entry, str) else entry.get("sym", ""))
    missing_region = sorted({s for s in candidates if s and s not in regions})
    missing_group = sorted({s for s in candidates if s and s not in groups})
    require(not missing_region,
            f"这些指数代码没有登记地区，页面上「地区」列会是空的：{missing_region}")
    require(not missing_group,
            f"这些指数代码没有登记分组，会掉进「其他」：{missing_group}")

def _first_symbol(item: dict) -> str:
    """取标的首选代码；候选可以是字符串或 {sym, note} 字典。"""
    candidate = item["syms"][0]
    return candidate["sym"] if isinstance(candidate, dict) else candidate


def run_asset_tracker_builder_contract_tests() -> None:
    spec = importlib.util.spec_from_file_location("asset_tracker_builder", ASSET_TRACKER_BUILD)
    require(spec is not None and spec.loader is not None, "无法加载跨资产构建脚本")
    module = importlib.util.module_from_spec(spec)
    inserted_stub = "requests" not in sys.modules
    if inserted_stub:
        requests_stub = types.ModuleType("requests")
        requests_stub.utils = types.SimpleNamespace(quote=lambda value: value)
        sys.modules["requests"] = requests_stub
    try:
        spec.loader.exec_module(module)
    finally:
        if inserted_stub:
            sys.modules.pop("requests", None)

    universe_names = [item["name"] for item in module.ASSETS]
    universe_symbols = [_first_symbol(item) for item in module.ASSETS]
    require(len(module.ASSETS) == 133, f"跨资产清单条数应为133，当前{len(module.ASSETS)}")
    require(len(set(universe_names)) == len(universe_names), "跨资产标的名称必须唯一")
    require(len(set(universe_symbols)) == len(universe_symbols), "跨资产首选代码必须唯一")
    categories = {}
    for item in module.ASSETS:
        categories[item["cat"]] = categories.get(item["cat"], 0) + 1
    require(categories == {"equity": 64, "commodity": 36, "fx": 22, "bond": 11},
            f"跨资产四类条数与登记不一致：{categories}")
    _require_index_registration(module.ASSETS)
    _require_stock_row_limit_matches_history()
    # 2026-08-25 所有者决定：撤下QQQ代理卡后纳斯达克改由综合指数^IXIC进入指数类；
    # 道指仍由DIA免费组件展示，纳斯达克100（NDX）不再进入本站，两者都不得混进清单。
    require("^IXIC" in universe_symbols,
            "纳斯达克综合指数应在跨资产清单的指数类中")
    require("^DJI" not in universe_symbols and "^NDX" not in universe_symbols,
            "道指仍以免费ETF组件展示、纳斯达克100不再展示，两者都不进入跨资产清单")
    tracker_rows = json.loads(ASSET_TRACKER_DATA.read_text(encoding="utf-8"))["assets"]
    require(all(row.get("name") in set(universe_names) for row in tracker_rows),
            "data.json 里出现了清单外的标的")
    require(len(tracker_rows) <= len(module.ASSETS),
            "已发布条数不得超过清单条数")

    asset = next(item for item in module.ASSETS if item["name"] == "中证500")
    require(asset["syms"][0] == "000905.SS", "中证500必须优先尝试原指数代码")
    proxy_candidate = asset["syms"][1]
    require(proxy_candidate.get("sym") == "510500.SS", "中证500ETF代理代码无效")
    attempts = []

    def fake_fetch(symbol):
        attempts.append(symbol)
        if symbol == "000905.SS":
            raise ValueError("行情数据点不足")
        return [("2025-08-11", 100.0), ("2026-08-10", 110.0), ("2026-08-11", 111.0)]

    chosen, suspect = module.select_candidate(asset, fake_fetch)
    require(attempts == ["000905.SS", "510500.SS"], "中证500候选回退顺序无效")
    require(suspect is None and chosen and chosen[0] == "510500.SS", "中证500ETF代理未被选中")
    require(chosen[2]["targetSymbol"] == "000905.SS"
            and chosen[2]["instrumentSymbol"] == "510500.SS"
            and chosen[2]["currency"] == "CNY"
            and chosen[2]["returnBasis"] == "price",
            "中证500ETF代理契约无效")
    print("Asset tracker CSI 500 fallback: PASS")

    def day(number):
        return f"2026-08-{number:02d}"

    fresh, _ = module.build_history({
        "^GSPC": [(day(18), 100.0), (day(19), 101.0), (day(20), 102.5)],
        "^N225": [(day(18), 200.0), (day(20), 204.0)],
    }, {}, "2026-08-22T00:00:00Z")
    require(fresh["dates"] == [day(18), day(19), day(20)], "历史共享日期轴必须按日升序合并")
    require(fresh["series"]["^N225"][1] is None, "缺报价日必须留空，不得前向填充")
    require(fresh["asOf"] == day(20) and fresh["points"] == 3, "历史 asOf 与点数必须由日期轴复算")
    require(fresh["source"] == "Yahoo Finance" and fresh["frequency"] == "daily",
            "历史必须标注与data.json一致的来源与频率")

    capped, _ = module.build_history(
        {"^GSPC": [(day(18), 1.0), (day(19), 2.0), (day(20), 3.0)]}, {}, "t", limit=2)
    require(capped["dates"] == [day(19), day(20)], "历史必须滚动截断到最近N个交易日")

    previous = {"dates": [day(18), day(19)],
                "series": {"^GSPC": [100.0, 101.0], "^FTSE": [50.0, 51.0]}}
    merged, retained = module.build_history(
        {"^GSPC": [(day(19), 101.0), (day(20), 102.0)]}, previous, "t")
    require(retained == ["^FTSE"], "本轮取数失败的标的必须沿用上次序列")
    require(merged["series"]["^FTSE"][-1] is None, "沿用的序列不得为新日期补造点位")

    require(module.build_history({}, {}, "t")[0] is None,
            "无任何有效序列时必须返回空，让调用方保留上次history.json")
    dirty, _ = module.build_history(
        {"^X": [(day(18), float("nan")), (day(19), 5.0), (day(20), None)]}, {}, "t")
    require(dirty["dates"] == [day(19)], "NaN与缺失值不得写入历史")
    print("Asset tracker rolling history: PASS")

    macro_spec = importlib.util.spec_from_file_location(
        "macro_radar_series", ROOT / "scripts" / "macro-radar" / "build_radar.py")
    macro_module = importlib.util.module_from_spec(macro_spec)
    macro_inserted = "requests" not in sys.modules
    if macro_inserted:
        macro_stub = types.ModuleType("requests")
        macro_stub.utils = types.SimpleNamespace(quote=lambda value: value)
        sys.modules["requests"] = macro_stub
    try:
        macro_spec.loader.exec_module(macro_module)
    finally:
        if macro_inserted:
            sys.modules.pop("requests", None)

    official, _ = macro_module.build_official_series({
        "DGS10": [(day(18), 4.61), (day(19), 4.65), (day(20), 4.69)],
        "DTWEXBGS": [(day(18), 118.9), (day(19), 119.1)],
        "RWTC": [(day(18), 86.0), (day(20), 86.48)],
    }, {}, "2026-08-22T00:00:00Z")
    require(official["source"] == "FRED · EIA" and official["frequency"] == "daily",
            "官方长序列必须标注来源与频率")
    require(official["series"]["DGS10"]["dates"] == [day(18), day(19), day(20)],
            "官方长序列必须按日升序")
    capped_macro, _ = macro_module.build_official_series(
        {"DGS10": [(day(18), 1.0), (day(19), 2.0), (day(20), 3.0)]}, {}, "t", limit=2)
    require(capped_macro["series"]["DGS10"]["dates"] == [day(19), day(20)],
            "官方长序列必须滚动截断")
    kept_macro, kept_ids = macro_module.build_official_series(
        {"DGS10": [(day(19), 4.6)]},
        {"series": {"RWTC": {"dates": [day(17)], "values": [85.0]}}}, "t")
    require(kept_ids == ["RWTC"] and kept_macro["series"]["RWTC"]["values"] == [85.0],
            "本轮缺失的官方序列必须沿用上次且不补造新点")
    require(macro_module.build_official_series({}, {}, "t")[0] is None,
            "无任何有效官方序列时必须返回空，保留上次series.json")
    dirty_macro, _ = macro_module.build_official_series(
        {"DGS10": [("bad", 1.0), (day(19), -5.0), (day(20), 4.7)]}, {}, "t")
    require(dirty_macro["series"]["DGS10"]["dates"] == [day(20)],
            "非法日期与非正值不得写入官方长序列")
    published = json.loads((ROOT / "apps" / "finance-terminal" / "data.json").read_text(encoding="utf-8"))
    for record in published["assets"]:
        if record["symbol"] in {"DGS10", "DTWEXBGS", "WTI"}:
            require(record.get("dataRef", "").startswith("../macro-radar/data.json"),
                    "三项官方行情仍必须读取data.json中的受契约8点窗口")
    print("Macro official long series: PASS")
    print("- FRED cache reuse / single EIA request / rolling cap: PASS")
    print("- retention on failure / no fabricated points / contracted 8-point window untouched: PASS")

    print("- shared date axis / no forward fill / rolling cap: PASS")
    print("- per-symbol retention on failure / no fabricated points / dirty value rejection: PASS")


    csi300 = next(item for item in module.ASSETS if item["name"] == "沪深300")
    require(csi300["syms"][0] == "000300.SS", "沪深300必须优先尝试原指数代码")
    require(csi300["syms"][1].get("sym") == "510300.SS", "沪深300ETF代理代码无效")
    csi300_attempts = []

    def fake_csi300_fetch(symbol):
        csi300_attempts.append(symbol)
        if symbol == "000300.SS":
            raise ValueError("模拟原指数失败")
        return [("2025-08-11", 100.0), ("2026-08-10", 105.0), ("2026-08-11", 106.0)]

    csi300_chosen, csi300_suspect = module.select_candidate(csi300, fake_csi300_fetch)
    require(csi300_attempts == ["000300.SS", "510300.SS"], "沪深300候选回退顺序无效")
    require(csi300_suspect is None and csi300_chosen and csi300_chosen[0] == "510300.SS",
            "沪深300ETF代理未被选中")
    require(csi300_chosen[2]["targetSymbol"] == "000300.SS"
            and csi300_chosen[2]["instrumentSymbol"] == "510300.SS"
            and csi300_chosen[2]["currency"] == "CNY"
            and csi300_chosen[2]["returnBasis"] == "price",
            "沪深300ETF代理契约无效")
    print("Asset tracker CSI 300 fallback: PASS")


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

    class ChartResponse:
        status_code = 200

        @staticmethod
        def json():
            return {"prices": [[1785715200000, 100.0], [1785758400000, 105.0],
                               [1785801600000, 110.0], [1785888000000, None]]}

    class ChartSession:
        @staticmethod
        def get(*_args, **_kwargs):
            return ChartResponse()

    crypto_closes = module.coingecko_daily_closes(ChartSession(), "bitcoin")
    require(crypto_closes == [("2026-08-03", 105.0), ("2026-08-04", 110.0)],
            "加密日线必须按UTC日期归并、同日取最后一个点，且丢弃缺价点")

    class BrokenSession:
        @staticmethod
        def get(*_args, **_kwargs):
            raise RuntimeError("rate limited")

    require(module.coingecko_daily_closes(BrokenSession(), "bitcoin") == [],
            "加密日线取数失败必须返回空序列，不得补造点位")
    require(module.build_crypto_board(ChartSession(), {}, "2026-08-25T00:00:00Z") is None,
            "CoinGecko市值快照不可用时必须保留上次crypto.json，不写空数据")
    require(module.CRYPTO_BOARD_COUNT == 20 and module.CRYPTO_BOARD_POINTS == 260,
            "加密品类板条数与滚动长度必须与行情板契约一致")
    require(module.CRYPTO_NAME_ZH.get("BTC") == "比特币",
            "常见币种必须有中文名，未收录的沿用英文名")

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
    observations = [
        ("2026-07-21", 120.5210), ("2026-07-22", 120.6500),
        ("2026-07-23", 120.9075), ("2026-07-24", 120.7105),
    ]
    fresh = builder.build_dtwexbgs_reference({}, attempt, lambda _series_id, _limit: observations)
    require(fresh["status"] == "ok", "DTWEXBGS成功更新必须标记ok")
    require(fresh["price"] == 120.7105 and fresh["previousPrice"] == 120.9075, "DTWEXBGS观测值映射错误")
    require(fresh["asOf"] == "2026-07-24" and fresh["previousAsOf"] == "2026-07-23", "DTWEXBGS日期映射错误")
    expected_change = (120.7105 / 120.9075 - 1) * 100
    require(abs(fresh["changePct"] - expected_change) < 1e-12, "DTWEXBGS涨跌幅计算错误")
    require(fresh["updatedAt"] == attempt and fresh["lastAttemptAt"] == attempt, "DTWEXBGS成功更新时间错误")
    require(fresh["observations"] == [
        {"asOf": observed, "value": value} for observed, value in observations
    ], "DTWEXBGS最近观测窗口映射错误")
    require(builder.valid_dtwexbgs_reference(fresh), "成功记录未通过结构校验")

    old = {"referenceSeries": {"DTWEXBGS": fresh}}
    failed_at = "2026-08-04T12:00:00Z"
    fallback = builder.build_dtwexbgs_reference(old, failed_at, lambda _series_id, _limit: [])
    require(fallback["status"] == "stale", "更新失败且有历史值时必须标记stale")
    require(fallback["price"] == fresh["price"] and fallback["asOf"] == fresh["asOf"], "更新失败不得覆盖历史有效值")
    require(fallback["updatedAt"] == fresh["updatedAt"], "失败时不得伪造成功更新时间")
    require(fallback["lastAttemptAt"] == failed_at, "失败尝试时间必须单独记录")
    require(fallback["observations"] == fresh["observations"], "失败回退必须完整保留DTWEXBGS观测窗口")
    require(fresh["status"] == "ok", "失败回退不得原地修改上一份记录")

    unavailable = builder.build_dtwexbgs_reference({}, failed_at, lambda _series_id, _limit: [])
    require(unavailable["status"] == "error", "无新值也无历史值时必须标记error")
    require(unavailable["price"] is None and unavailable["updatedAt"] is None, "失败时不得写入默认数值或伪更新时间")
    require(unavailable["observations"] == [], "无历史DTWEXBGS时观测窗口必须为空")

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

    history_page = """
    <html><body><table>
      <tr><th colspan="6">Cushing, OK WTI Spot Price FOB (Dollars per Barrel)</th></tr>
      <tr><th>Week Of</th><th>Mon</th><th>Tue</th><th>Wed</th><th>Thu</th><th>Fri</th></tr>
      <tr><td>2025 Dec-29 to Jan- 2</td><td>57.89</td><td>57.79</td><td>57.26</td><td></td><td>57.21</td></tr>
      <tr><td>2026 Jul-27 to Jul-31</td><td>84.25</td><td>80.91</td><td>86.08</td><td>85.15</td><td>86.16</td></tr>
      <tr><td>2026 Aug- 3 to Aug- 7</td><td>81.96</td><td></td><td></td><td></td><td></td></tr>
    </table></body></html>
    """
    expected_history = [
        ("2026-07-29", 86.08), ("2026-07-30", 85.15),
        ("2026-07-31", 86.16), ("2026-08-03", 81.96),
    ]
    require(builder.parse_eia_rwtc_history_html(history_page, 4) == expected_history,
            "EIA公开历史页日期、空值或跨周解析错误")
    require(builder.parse_eia_rwtc_history_html("<table><tr><td>2026 Aug- 3 to Aug- 7</td>"
                                                "<td>81.96</td></tr></table>") == [],
            "EIA公开历史页必须验证标题与单位")

    history_captured = {}

    class FakeHistoryResponse:
        text = history_page

        @staticmethod
        def raise_for_status():
            return None

    def history_requester(url, **kwargs):
        history_captured["url"] = url
        history_captured["params"] = kwargs.get("params")
        return FakeHistoryResponse()

    history_observations = builder.eia_rwtc_history(4, requester=history_requester)
    require(history_captured["url"] == builder.EIA_HISTORY_URL,
            "RWTC无密钥回退必须使用EIA官方日频历史页")
    require(history_captured["params"] is None, "EIA公开历史页不得拼接或传递API密钥")
    require(history_observations == expected_history, "EIA公开历史页请求结果映射错误")

    original_api = builder.eia_rwtc_api
    original_history = builder.eia_rwtc_history
    try:
        builder.eia_rwtc_api = lambda _limit: []
        builder.eia_rwtc_history = lambda _limit: history_observations
        history_fresh = builder.build_rwtc_reference({}, attempt)
    finally:
        builder.eia_rwtc_api = original_api
        builder.eia_rwtc_history = original_history
    require(history_fresh["status"] == "ok" and history_fresh["asOf"] == "2026-08-03",
            "EIA API不可用时官方历史页应恢复RWTC")
    require(history_fresh["source"].get("accessMethod") == "EIA public history page",
            "RWTC必须披露实际官方访问路径")
    require(builder.valid_rwtc_reference(history_fresh), "带访问路径的RWTC记录必须通过结构校验")
    invalid_access = dict(history_fresh)
    invalid_access["source"] = dict(history_fresh["source"], accessMethod="unregistered mirror")
    require(not builder.valid_rwtc_reference(invalid_access), "未登记RWTC访问路径必须被拒绝")

    fresh = builder.build_rwtc_reference({}, attempt, lambda _limit: observations)
    require(fresh["status"] == "ok", "RWTC成功更新必须标记ok")
    require(fresh["price"] == 84.25 and fresh["previousPrice"] == 91.74, "RWTC观测值映射错误")
    require(fresh["asOf"] == "2026-07-27" and fresh["previousAsOf"] == "2026-07-24", "RWTC日期映射错误")
    expected_change = (84.25 / 91.74 - 1) * 100
    require(abs(fresh["changePct"] - expected_change) < 1e-12, "RWTC涨跌幅计算错误")
    require(fresh["updatedAt"] == attempt and fresh["lastAttemptAt"] == attempt, "RWTC成功更新时间错误")
    require(fresh["observations"] == [
        {"asOf": observed, "value": value} for observed, value in observations
    ], "RWTC最近观测窗口映射错误")
    require(builder.valid_rwtc_reference(fresh), "RWTC成功记录未通过结构校验")

    old = {"referenceSeries": {"RWTC": fresh}}
    failed_at = "2026-08-04T12:00:00Z"
    fallback = builder.build_rwtc_reference(old, failed_at, lambda _limit: [])
    require(fallback["status"] == "stale", "RWTC更新失败且有历史值时必须标记stale")
    require(fallback["price"] == fresh["price"] and fallback["asOf"] == fresh["asOf"], "RWTC失败不得覆盖历史有效值")
    require(fallback["updatedAt"] == fresh["updatedAt"], "RWTC失败时不得伪造成功更新时间")
    require(fallback["lastAttemptAt"] == failed_at, "RWTC失败尝试时间必须单独记录")
    require(fallback["observations"] == fresh["observations"], "RWTC失败回退必须完整保留观测窗口")
    require(fresh["status"] == "ok", "RWTC失败回退不得原地修改上一份记录")

    unavailable = builder.build_rwtc_reference({}, failed_at, lambda _limit: [])
    require(unavailable["status"] == "error", "RWTC无新值也无历史值时必须标记error")
    require(unavailable["price"] is None and unavailable["updatedAt"] is None, "RWTC失败时不得写入默认数值")
    require(unavailable["observations"] == [], "无历史RWTC时观测窗口必须为空")

    invalid = builder.build_rwtc_reference(
        old,
        failed_at,
        lambda _limit: [("2026-07-27", 84.25), ("2026-07-24", 91.74)],
    )
    require(invalid["status"] == "stale" and invalid["price"] == fresh["price"], "RWTC日期倒序必须回退历史值")
    print("RWTC EIA pipeline states: PASS")
    print("- API contract / official history fallback / success / retained snapshot / invalid observation: PASS")


def run_js_adapter_tests() -> None:
    script = r"""
(async () => {
const assert = require("assert");
const fs = require("fs");
const adapter = require("./apps/finance-terminal/app.js");
const informationData = (await import("./apps/finance-terminal/finance-terminal-information-data.mjs"))
  .createInformationData(adapter.sectionDataHelpers());
const operationsData = (await import("./apps/finance-terminal/finance-terminal-operations-data.mjs"))
  .createOperationsData(adapter.sectionDataHelpers());
const { createSupportingHealthAdapter } = await import("./apps/finance-terminal/finance-terminal-health-adapters.mjs");
const supportingAdapter = createSupportingHealthAdapter(adapter.supportingHealthHelpers());
adapter.installSupportingHealthAdapter(supportingAdapter);
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
const readiness = JSON.parse(fs.readFileSync("./apps/finance-terminal/readiness.json", "utf8"));
const marketLicenseReadiness = JSON.parse(fs.readFileSync("./apps/finance-terminal/market-source-readiness.json", "utf8"));

const match = adapter.findDgs10Row(macro);
assert(match && match.row.id === "DGS10");
const reference = adapter.findDtwexbgsReference(macro);
assert(reference && reference.id === "DTWEXBGS");
const oilReference = adapter.findRwtcReference(macro);
assert(oilReference && oilReference.id === "RWTC");
const dollarConfig = config.assets.find((asset) => asset.id === "dxy");
const oilConfig = config.assets.find((asset) => asset.id === "wti");
const bitcoinConfig = config.assets.find((asset) => asset.id === "bitcoin");
const bitcoinRow = assetRanking.assets.find((asset) => asset.symbol === "BTC");
const rankingSource = { data: assetRanking, error: null };
const rankingHealthSource = { data: assetRankingHealth, error: null };
const currentLatestMs = Math.max(...[
  macro.updatedAt,
  fearGreed.updatedAt,
  ofr.updatedAt,
  assetTracker.updatedAt,
  assetRanking.updatedAt,
  companies.updatedAt
].map(Date.parse));
assert(Number.isFinite(currentLatestMs));
const currentNow = new Date(currentLatestMs + 6 * 60 * 60 * 1000);
const marketLicenseState = adapter.adaptMarketLicenseReadiness(marketLicenseReadiness);
assert.strictEqual(marketLicenseState.status, "free");
assert.strictEqual(marketLicenseState.strategy, "free-embedded-proxy");
assert.strictEqual(marketLicenseState.proxyAssets, marketLicenseReadiness.assets.length);
assert.strictEqual(marketLicenseState.provider, "TradingView");
assert.strictEqual(marketLicenseState.cost, "free");
assert.strictEqual(marketLicenseState.rawMarketDataStored, false);
assert.deepStrictEqual(marketLicenseState.targets, ["DIA", "GLD"]);
const disguisedMarketProxy = JSON.parse(JSON.stringify(marketLicenseReadiness));
disguisedMarketProxy.assets[0].proxy.isSameInstrument = true;
assert.throws(() => adapter.adaptMarketLicenseReadiness(disguisedMarketProxy), /冒充原标的/);
const scrapedMarketProxy = JSON.parse(JSON.stringify(marketLicenseReadiness));
scrapedMarketProxy.provider.delivery = "scraped-api";
assert.throws(() => adapter.adaptMarketLicenseReadiness(scrapedMarketProxy), /免费嵌入配置无效/);
const currentAttemptAt = new Date(currentNow.getTime() - 60 * 60 * 1000).toISOString();
const currentAttemptDate = currentAttemptAt.slice(0, 10);
const supportingSnapshots = [
  [fearGreed, fearGreedHealth],
  [ofr, ofrHealth],
  [econCalendar, econCalendarHealth],
  [financeNews, financeNewsHealth]
];
const supportingLatestMs = Math.max(...supportingSnapshots.flatMap(([data, health]) => [
  Date.parse(data.updatedAt), Date.parse(health.generatedAt)
]));
assert(Number.isFinite(supportingLatestMs));
const supportingNow = new Date(supportingLatestMs + 60 * 60 * 1000);
const expiredOfficialHealthNow = new Date(Date.parse(macroHealth.generatedAt) + 96 * 60 * 60 * 1000);
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
  const state = supportingAdapter.adaptSupportingSourceHealth(sourceHealth, dataset, sourceData, supportingNow);
  const reportAgeHours = (supportingNow.getTime() - Date.parse(sourceHealth.generatedAt)) / (60 * 60 * 1000);
  const expectedStatus = sourceHealth.historyStatus !== "migrated"
    && reportAgeHours > sourceHealth.policy.maxReportAgeHours
    && sourceHealth.status !== "failed" ? "stale" : sourceHealth.status;
  assert.strictEqual(state.dataset, dataset);
  assert.strictEqual(state.status, expectedStatus);
  assert.strictEqual(state.historyKnown, sourceHealth.historyStatus === "tracked");
  assert.strictEqual(state.freshCoveragePct, sourceHealth.coverage.freshCoveragePct);
  assert.strictEqual(state.publishedCoveragePct, sourceHealth.coverage.publishedCoveragePct);
  const tampered = JSON.parse(JSON.stringify(sourceHealth));
  tampered.coverage.refreshedComponents += 1;
  assert.throws(() => supportingAdapter.adaptSupportingSourceHealth(tampered, dataset, sourceData, supportingNow));
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
const supportingAttemptAt = new Date(supportingNow.getTime() - 60 * 60 * 1000).toISOString();
const supportingStaleAt = new Date(supportingNow.getTime() - 96 * 60 * 60 * 1000).toISOString();
const trackedFear = trackedSupportingHealth(fearGreedHealth, supportingAttemptAt);
assert.strictEqual(supportingAdapter.adaptSupportingSourceHealth(trackedFear, "fear-greed", fearGreed, supportingNow).status, "healthy");
const fallbackFear = trackedSupportingHealth(fearGreedHealth, supportingAttemptAt, { "cnn-index": "fallback" });
const fallbackFearState = supportingAdapter.adaptSupportingSourceHealth(fallbackFear, "fear-greed", fearGreed, supportingNow);
assert.strictEqual(fallbackFearState.status, "degraded");
assert.strictEqual(fallbackFearState.terminalStatus, "degraded");
const failedFear = trackedSupportingHealth(fearGreedHealth, supportingAttemptAt, { "cnn-index": "fallback" }, false);
assert.strictEqual(supportingAdapter.adaptSupportingSourceHealth(failedFear, "fear-greed", fearGreed, supportingNow).status, "failed");
const staleFearHealth = trackedSupportingHealth(fearGreedHealth, supportingStaleAt);
assert.strictEqual(supportingAdapter.adaptSupportingSourceHealth(staleFearHealth, "fear-greed", fearGreed, supportingNow).status, "stale");
const supportingRiskCards = adapter.buildRiskCards({
  macro: { data: macro, error: null },
  fearGreed: { data: fearGreed, error: null },
  fearGreedHealth: { data: fearGreedHealth, error: null },
  ofr: { data: ofr, error: null },
  ofrHealth: { data: ofrHealth, error: null }
}, supportingNow);
assert.strictEqual(supportingRiskCards[1].sourceHealth.status,
  supportingAdapter.adaptSupportingSourceHealth(fearGreedHealth, "fear-greed", fearGreed, supportingNow).status);
assert.strictEqual(supportingRiskCards[2].sourceHealth.status,
  supportingAdapter.adaptSupportingSourceHealth(ofrHealth, "ofr-monitor", ofr, supportingNow).status);
const supportingInformationCards = informationData.buildInformationCards({
  calendar: { data: econCalendar, error: null },
  calendarHealth: { data: econCalendarHealth, error: null },
  news: { data: financeNews, error: null },
  newsHealth: { data: financeNewsHealth, error: null }
}, supportingNow);
assert.strictEqual(supportingInformationCards[0].sourceHealth.status,
  supportingAdapter.adaptSupportingSourceHealth(econCalendarHealth, "econ-calendar", econCalendar, supportingNow).status);
assert.strictEqual(supportingInformationCards[1].sourceHealth.status,
  supportingAdapter.adaptSupportingSourceHealth(financeNewsHealth, "whats-latest", financeNews, supportingNow).status);
const success = adapter.buildPageData(
  config, macro, currentNow, null, null, rankingSource, rankingHealthSource
);
const dgs10 = success.assets.find((asset) => asset.id === "us10y");
const dollar = success.assets.find((asset) => asset.id === "dxy");
const oil = success.assets.find((asset) => asset.id === "wti");
const bitcoin = success.assets.find((asset) => asset.id === "bitcoin");
assert.strictEqual(dgs10.demo, false);
assert.strictEqual(dgs10.status, match.row.status === "ok"
  && adapter.businessDaysSince(match.row.asOf, currentNow) <= 3 ? "ok" : "stale");
assert.strictEqual(dgs10.symbol, "DGS10");
assert.strictEqual(dgs10.changeUnit, "bp");
assert(Number.isFinite(dgs10.price));
assert(Number.isFinite(dgs10.change));
assert.strictEqual(dgs10.price, Number(match.row.val.replace("%", "")));
assert.strictEqual(dgs10.change, Number(match.row.chg.toLowerCase().replace("bp", "")));
assert.strictEqual(dgs10.asOf, match.row.asOf);
assert.strictEqual(dgs10.updatedAt, macro.updatedAt);
assert.strictEqual(dgs10.source.seriesId, "DGS10");
assert.strictEqual(dgs10.observationTrend.count, match.row.observations.length);
assert.strictEqual(dgs10.observationTrend.targetCount, 8);
assert.deepStrictEqual(dgs10.observationTrend.values, match.row.observations.map((item) => item.value));
assert.strictEqual(dgs10.observationTrend.changeUnit, "bp");
assert.strictEqual(dgs10.observationTrend.change, match.row.observations.length < 2 ? null
  : Math.round((match.row.observations[match.row.observations.length - 1].value
    - match.row.observations[0].value) * 10000) / 100);
const dgsWindow = JSON.parse(JSON.stringify(macro));
const dgsWindowRow = adapter.findDgs10Row(dgsWindow).row;
const dgsWindowPrice = Number(dgsWindowRow.val.replace("%", ""));
dgsWindowRow.price = dgsWindowPrice;
dgsWindowRow.previousPrice = Math.round((dgsWindowPrice - 0.06) * 100) / 100;
dgsWindowRow.changeBps = 6;
dgsWindowRow.chg = "6bp";
dgsWindowRow.observations = [
  { asOf: dgsWindowRow.previousAsOf, value: dgsWindowRow.previousPrice },
  { asOf: dgsWindowRow.asOf, value: dgsWindowPrice }
];
const dgsWindowAsset = adapter.adaptDgs10(
  config.assets.find((asset) => asset.id === "us10y"), dgsWindow, currentNow
);
assert.strictEqual(dgsWindowAsset.observationTrend.count, 2);
assert.strictEqual(dgsWindowAsset.observationTrend.change, 6);
const tamperedDgsWindow = JSON.parse(JSON.stringify(dgsWindow));
adapter.findDgs10Row(tamperedDgsWindow).row.observations[1].value =
  Math.round((dgsWindowPrice + 0.01) * 100) / 100;
assert.throws(() => adapter.adaptDgs10(
  config.assets.find((asset) => asset.id === "us10y"), tamperedDgsWindow, currentNow
));
const dgs10Health = adapter.adaptOfficialSourceHealth(macroHealth, macro, dgs10, "DGS10", currentNow);
const dgs10HealthRecord = macroHealth.sources.find((source) => source.id === "DGS10");
assert.strictEqual(dgs10Health.seriesId, "DGS10");
assert.strictEqual(dgs10Health.status, dgs10HealthRecord.status);
assert.strictEqual(dgs10Health.historyKnown, macroHealth.historyStatus === "tracked");
assert.strictEqual(dgs10Health.refreshLabel, {
  market: "已刷新", fallback: "保留旧值", unavailable: "不可用", unknown: "历史待建立"
}[dgs10HealthRecord.mode]);
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
/* 阈值读自被测代码本身，避免测试与源码各写一个数字而悄悄漂移。 */
assert.strictEqual(dollar.status, reference.status === "ok"
  && adapter.businessDaysSince(reference.asOf, currentNow)
     <= adapter.DTWEXBGS_MAX_BUSINESS_DAYS ? "ok" : "stale");
assert.equal(adapter.DTWEXBGS_MAX_BUSINESS_DAYS, 8,
  "H.10 按周成批发布，正常滞后可达 5 个工作日；阈值需容纳一周批次并仍能发现缺批");
assert.strictEqual(dollar.symbol, "DTWEXBGS");
assert.strictEqual(dollar.price, reference.price);
assert.strictEqual(dollar.previousPrice, reference.previousPrice);
assert.strictEqual(dollar.asOf, reference.asOf);
assert.strictEqual(dollar.updatedAt, reference.updatedAt);
assert.strictEqual(dollar.source.seriesId, "DTWEXBGS");
assert(Math.abs(dollar.changePct - ((reference.price / reference.previousPrice - 1) * 100)) < 1e-12);
assert.strictEqual(dollar.observationTrend.count, reference.observations.length);
assert.deepStrictEqual(dollar.observationTrend.values, reference.observations.map((item) => item.value));
assert.strictEqual(dollar.observationTrend.startAsOf, reference.observations[0].asOf);
assert.strictEqual(dollar.observationTrend.endAsOf, reference.asOf);
assert(Math.abs(dollar.observationTrend.change
  - ((reference.price / reference.observations[0].value - 1) * 100)) < 1e-12);
const tamperedDollarWindow = JSON.parse(JSON.stringify(macro));
tamperedDollarWindow.referenceSeries.DTWEXBGS.observations[
  tamperedDollarWindow.referenceSeries.DTWEXBGS.observations.length - 1
].value += 1;
assert.throws(() => adapter.adaptDtwexbgs(dollarConfig, tamperedDollarWindow, currentNow));
const dollarHealth = adapter.adaptOfficialSourceHealth(
  macroHealth, macro, dollar, "DTWEXBGS", currentNow
);
const dollarHealthRecord = macroHealth.sources.find((source) => source.id === "DTWEXBGS");
assert.strictEqual(dollarHealth.status, dollarHealthRecord.status);
assert.strictEqual(dollarHealth.historyKnown, macroHealth.historyStatus === "tracked");
assert.strictEqual(dollarHealth.refreshLabel, {
  market: "已刷新", fallback: "保留旧值", unavailable: "不可用", unknown: "历史待建立"
}[dollarHealthRecord.mode]);
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
assert.strictEqual(oil.status, oilReference.status === "ok"
  && adapter.businessDaysSince(oilReference.asOf, currentNow) <= 4 ? "ok" : "stale");
assert.strictEqual(oil.symbol, "WTI");
assert.strictEqual(oil.price, oilReference.price);
assert.strictEqual(oil.previousPrice, oilReference.previousPrice);
assert.strictEqual(oil.asOf, oilReference.asOf);
assert.strictEqual(oil.updatedAt, oilReference.updatedAt);
assert.strictEqual(oil.source.seriesId, "RWTC");
assert(Math.abs(oil.changePct - ((oilReference.price / oilReference.previousPrice - 1) * 100)) < 1e-12);
assert.strictEqual(oil.observationTrend.count, oilReference.observations.length);
assert.deepStrictEqual(oil.observationTrend.values, oilReference.observations.map((item) => item.value));
assert.strictEqual(oil.observationTrend.startAsOf, oilReference.observations[0].asOf);
assert.strictEqual(oil.observationTrend.endAsOf, oilReference.asOf);
assert(Math.abs(oil.observationTrend.change
  - ((oilReference.price / oilReference.observations[0].value - 1) * 100)) < 1e-12);
const tamperedOilWindow = JSON.parse(JSON.stringify(macro));
tamperedOilWindow.referenceSeries.RWTC.observations.reverse();
assert.throws(() => adapter.adaptRwtc(oilConfig, tamperedOilWindow, currentNow));
const oilHealth = adapter.adaptOfficialSourceHealth(macroHealth, macro, oil, "RWTC", currentNow);
const oilHealthRecord = macroHealth.sources.find((source) => source.id === "RWTC");
assert.strictEqual(oilHealth.status, oilHealthRecord.status);
assert.strictEqual(oilHealth.historyKnown, macroHealth.historyStatus === "tracked");
assert.strictEqual(oilHealth.refreshLabel, {
  market: "已刷新", fallback: "保留旧值", unavailable: "不可用", unknown: "历史待建立"
}[oilHealthRecord.mode]);
const oilWithStaleHealth = adapter.buildPageData(
  config, macro, expiredOfficialHealthNow, null, { data: macroHealth, error: null }
).assets.find((asset) => asset.id === "wti");
assert.strictEqual(oilWithStaleHealth.updateHealth.status, "stale");
assert.strictEqual(oilWithStaleHealth.updateHealth.seriesId, "RWTC");
const allOfficialHealth = adapter.buildPageData(
  config, macro, expiredOfficialHealthNow, null, { data: macroHealth, error: null }
).assets.filter((asset) => asset.updateHealth);
assert.deepStrictEqual(allOfficialHealth.map((asset) => asset.updateHealth.seriesId), [
  "DGS10", "DTWEXBGS", "RWTC", "BTC/USD"
]);
assert.strictEqual(allOfficialHealth.filter((asset) => asset.updateHealth.status === "stale").length, 3);
assert.strictEqual(allOfficialHealth.filter((asset) => asset.updateHealth.status === "unknown").length, 1);

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
const healthyDgsHealth = trackedOfficialHealth(macroHealth, "DGS10", currentAttemptAt, "market");
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
  macroHealth, "DTWEXBGS", currentAttemptAt, "fallback"
);
assert.strictEqual(adapter.adaptOfficialSourceHealth(
  trackedDollarFallback, fallbackDollarMacro, fallbackDollarAsset, "DTWEXBGS", currentNow
).status, "degraded");

const unavailableOilMacro = JSON.parse(JSON.stringify(macro));
unavailableOilMacro.referenceSeries.RWTC.status = "error";
const unavailableOilAsset = Object.assign({}, oilConfig, {
  price: null, previousPrice: null, changePct: null, asOf: null, updatedAt: null, demo: false, status: "error",
  source: Object.assign({}, oilConfig.source, { accessMethod: oilReference.source.accessMethod })
});
const trackedOilFailure = trackedOfficialHealth(
  macroHealth, "RWTC", currentAttemptAt, "unavailable"
);
const trackedOilSource = trackedOilFailure.sources.find((source) => source.id === "RWTC");
trackedOilSource.published = false;
trackedOilSource.asOf = null;
trackedOilSource.publishedUpdatedAt = null;
assert.strictEqual(adapter.adaptOfficialSourceHealth(
  trackedOilFailure, unavailableOilMacro, unavailableOilAsset, "RWTC", currentNow
).status, "failed");
assert.strictEqual(bitcoin.demo, false);
assert.strictEqual(bitcoin.status, "ok");
assert.strictEqual(bitcoin.price, bitcoinRow.price);
assert.strictEqual(bitcoin.changePct, bitcoinRow.changePct);
assert.strictEqual(bitcoin.asOf, bitcoinRow.dataMeta.asOf);
assert.strictEqual(bitcoin.updatedAt, bitcoinRow.dataMeta.updatedAt);
assert.strictEqual(bitcoin.source.name, "Powered by CoinGecko");
assert.strictEqual(bitcoin.changePeriod, "24_hours");
assert(bitcoin.note.includes("不宣称实时"));
assert.strictEqual(bitcoin.updateHealth.status, "healthy");
assert.strictEqual(bitcoin.updateHealth.accessMethodLabel, "CoinGecko");
assert.strictEqual(bitcoin.updateHealth.lastSuccessfulAt, bitcoin.updatedAt);
const tamperedBitcoinHealth = JSON.parse(JSON.stringify(assetRankingHealth));
tamperedBitcoinHealth.sources.find((source) => source.id === "coingecko").lastSuccessAt = "2026-08-01T00:00:00Z";
assert.throws(() => adapter.adaptBitcoinSourceHealth(
  tamperedBitcoinHealth, assetRanking, bitcoin, currentNow
), /同批/);
const yahooRanking = JSON.parse(JSON.stringify(assetRanking));
const yahooBitcoin = adapter.findBitcoinAsset(yahooRanking);
yahooBitcoin.dataMeta.mode = "market";
yahooBitcoin.dataMeta.status = "partial";
yahooBitcoin.dataMeta.source = "Yahoo Finance · 静态流通量基准";
const yahooBitcoinCard = adapter.adaptBitcoin(bitcoinConfig, yahooRanking, currentNow);
assert.strictEqual(yahooBitcoinCard.status, "partial");
assert.strictEqual(yahooBitcoinCard.changePeriod, "previous_close");
assert.strictEqual(adapter.adaptBitcoinSourceHealth(
  assetRankingHealth, yahooRanking, yahooBitcoinCard, currentNow
).accessMethodLabel, "Yahoo BTC-USD");
const retainedRanking = JSON.parse(JSON.stringify(assetRanking));
const retainedBitcoin = adapter.findBitcoinAsset(retainedRanking);
retainedBitcoin.dataMeta.mode = "fallback";
retainedBitcoin.dataMeta.status = "stale";
retainedBitcoin.dataMeta.source = "CoinGecko · Yahoo Finance";
assert.strictEqual(adapter.adaptBitcoin(bitcoinConfig, retainedRanking, currentNow).status, "stale");
const estimatedRanking = JSON.parse(JSON.stringify(assetRanking));
const estimatedBitcoin = adapter.findBitcoinAsset(estimatedRanking);
estimatedBitcoin.dataMeta.mode = "estimate";
estimatedBitcoin.dataMeta.status = "partial";
assert.throws(() => adapter.adaptBitcoin(bitcoinConfig, estimatedRanking, currentNow), /不得使用估值/);
const duplicateBitcoin = JSON.parse(JSON.stringify(assetRanking));
duplicateBitcoin.assets.push(JSON.parse(JSON.stringify(bitcoinRow)));
assert.throws(() => adapter.findBitcoinAsset(duplicateBitcoin), /只能包含一条/);
const missingBitcoin = JSON.parse(JSON.stringify(assetRanking));
missingBitcoin.assets = missingBitcoin.assets.filter((asset) => asset.symbol !== "BTC");
assert.throws(() => adapter.findBitcoinAsset(missingBitcoin), /只能包含一条/);
const unavailableBitcoinPage = adapter.buildPageData(
  config, macro, currentNow, null, null, { data: null, error: new Error("HTTP 503") }
);
assert.strictEqual(unavailableBitcoinPage.assets.find((asset) => asset.id === "bitcoin").status, "error");
assert.strictEqual(unavailableBitcoinPage.assets.find((asset) => asset.id === "us10y").price, dgs10.price);
assert.strictEqual(success.assets.filter((asset) => asset.demo === false).length, config.assets.length);
assert.strictEqual(success.assets.filter((asset) => asset.externalDisplay).length,
  config.assets.filter((asset) => asset.externalDisplay).length);
assert.strictEqual(success.assets.filter((asset) => asset.demo === true).length, 0);
/* 页面状态是各卡状态的汇总，不能写死某个值——那会随当天真实数据变化，
   此前它之所以恒为 stale，正是因为 DTWEXBGS 被日频阈值误判。
   这里锁不变式；「确实能汇总出过期」由下方 staleMacro 夹具专门覆盖。 */
const staleAssets = success.assets.filter((asset) => asset.status === "stale");
assert.strictEqual(success.status, staleAssets.length ? "stale" : "ok",
  "页面状态应汇总各卡，过期卡=" + JSON.stringify(staleAssets.map((a) => a.symbol)));

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
trackedDgs.asOf = currentAttemptDate;
trackedDgs.updatedAt = currentAttemptAt;
trackedDgs.lastAttemptAt = trackedDgs.updatedAt;
trackedDgs.observations = [{ asOf: trackedDgs.asOf, value: trackedDgs.price }];
const independentlyFreshDgs = adapter.buildPageData(config, trackedDgsMacro, currentNow).assets.find((asset) => asset.id === "us10y");
assert.strictEqual(independentlyFreshDgs.status, "ok");
assert.strictEqual(independentlyFreshDgs.updatedAt, trackedDgs.updatedAt);

const freshDollar = adapter.adaptDtwexbgs(
  dollarConfig, macro, new Date(reference.asOf + "T23:59:59Z")
);
assert.strictEqual(freshDollar.status, "ok");
assert.strictEqual(freshDollar.demo, false);
/* 频率标签必须说清 H.10 的发布节奏：观测是日度的，发布是按周成批的。 */
assert.strictEqual(freshDollar.delayLabel, "日度观测 · 每周成批发布");

const freshOilMacro = JSON.parse(JSON.stringify(macro));
freshOilMacro.referenceSeries.RWTC.status = "ok";
freshOilMacro.referenceSeries.RWTC.source.accessMethod = "EIA public history page";
const freshOil = adapter.adaptRwtc(
  oilConfig, freshOilMacro, new Date(oilReference.asOf + "T23:59:59Z")
);
assert.strictEqual(freshOil.status, "ok");
assert.strictEqual(freshOil.demo, false);
assert.strictEqual(freshOil.delayLabel, "日频现货 · 自动更新");
assert.strictEqual(freshOil.source.accessMethod, "EIA public history page");
const pathAwareHealth = trackedOfficialHealth(macroHealth, "RWTC", currentAttemptAt, "market");
pathAwareHealth.sources.find((source) => source.id === "RWTC").source.accessMethod = "EIA public history page";
const pathAwareState = adapter.adaptOfficialSourceHealth(
  pathAwareHealth, freshOilMacro, freshOil, "RWTC", currentNow
);
assert.strictEqual(pathAwareState.accessMethodLabel, "官方历史页");
const tamperedPathHealth = JSON.parse(JSON.stringify(pathAwareHealth));
tamperedPathHealth.sources.find((source) => source.id === "RWTC").source.accessMethod = "EIA API v2";
assert.throws(() => adapter.adaptOfficialSourceHealth(
  tamperedPathHealth, freshOilMacro, freshOil, "RWTC", currentNow
), /访问路径/);

const staleMacro = JSON.parse(JSON.stringify(macro));
const staleMatch = adapter.findDgs10Row(staleMacro);
staleMatch.row.asOf = "2026-07-20";
staleMatch.row.observations = [{ asOf: staleMatch.row.asOf, value: staleMatch.row.price }];
/* DTWEXBGS 的阈值按 H.10 每周成批发布定为 8 个工作日，因此这里要把夹具推到
   10 个工作日之前，才真正落在过期区间内——原来的 07-20 距 07-27 只有 5 个
   工作日，属于该序列的正常滞后，不该被判过期。 */
staleMacro.referenceSeries.DTWEXBGS.asOf = "2026-07-13";
staleMacro.referenceSeries.DTWEXBGS.previousAsOf = "2026-07-10";
staleMacro.referenceSeries.DTWEXBGS.observations = [
  { asOf: "2026-07-10", value: staleMacro.referenceSeries.DTWEXBGS.previousPrice },
  { asOf: "2026-07-13", value: staleMacro.referenceSeries.DTWEXBGS.price }
];
staleMacro.referenceSeries.RWTC.status = "ok";
staleMacro.referenceSeries.RWTC.asOf = "2026-07-20";
staleMacro.referenceSeries.RWTC.previousAsOf = "2026-07-17";
staleMacro.referenceSeries.RWTC.observations = [
  { asOf: "2026-07-17", value: staleMacro.referenceSeries.RWTC.previousPrice },
  { asOf: "2026-07-20", value: staleMacro.referenceSeries.RWTC.price }
];
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
assert.strictEqual(missing.assets.find((asset) => asset.id === "dxy").status, dollar.status);
assert.strictEqual(missing.assets.find((asset) => asset.id === "wti").status, oil.status);

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
fallbackMacro.referenceSeries.DTWEXBGS.observations = [
  { asOf: "2026-07-31", value: fallbackMacro.referenceSeries.DTWEXBGS.previousPrice },
  { asOf: "2026-08-03", value: fallbackMacro.referenceSeries.DTWEXBGS.price }
];
const fallback = adapter.buildPageData(config, fallbackMacro, currentNow);
const fallbackDollar = fallback.assets.find((asset) => asset.id === "dxy");
assert.strictEqual(fallbackDollar.status, "stale");
assert(fallbackDollar.note.includes("自动更新失败"));

const oilFallbackMacro = JSON.parse(JSON.stringify(macro));
oilFallbackMacro.referenceSeries.RWTC.status = "stale";
oilFallbackMacro.referenceSeries.RWTC.asOf = "2026-08-03";
oilFallbackMacro.referenceSeries.RWTC.previousAsOf = "2026-07-31";
oilFallbackMacro.referenceSeries.RWTC.observations = [
  { asOf: "2026-07-31", value: oilFallbackMacro.referenceSeries.RWTC.previousPrice },
  { asOf: "2026-08-03", value: oilFallbackMacro.referenceSeries.RWTC.price }
];
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

const macroOperationHealth = operationsData.adaptMacroSourceHealth(macroHealth, macro, currentNow);
assert.strictEqual(macroOperationHealth.dataset, "macro-radar");
assert.strictEqual(macroOperationHealth.status, macroHealth.status);
assert.strictEqual(macroOperationHealth.pipelineStatus, macroHealth.status);
assert.strictEqual(macroOperationHealth.availableCoveragePct, 100);
assert.strictEqual(macroOperationHealth.freshCoveragePct, macroHealth.coverage.freshCoveragePct);
assert.strictEqual(macroOperationHealth.historyKnown, macroHealth.historyStatus === "tracked");
assert.strictEqual(macroOperationHealth.consecutiveFailures, macroHealth.consecutiveFailures);
assert.strictEqual(macroOperationHealth.reportStale, false);

const operationSources = {
  macro: { data: macro, error: null },
  macroHealth: { data: macroHealth, error: null },
  assetTracker: { data: assetTracker, error: null },
  assetTrackerHealth: { data: assetTrackerHealth, error: null },
  companies: { data: companies, error: null },
  companiesHealth: { data: companiesHealth, error: null },
  assetRanking: { data: assetRanking, error: null },
  assetRankingHealth: { data: assetRankingHealth, error: null },
  readiness: { data: readiness, error: null }
};
const operationCards = operationsData.buildOperationsCards(operationSources, currentNow);
assert.strictEqual(operationCards.length, 4);
assert.deepStrictEqual(operationCards.map((card) => card.id), [
  "macro-radar", "asset-tracker", "companies", "asset-ranking"
]);
assert.deepStrictEqual(operationCards.map((card) => card.status), [
  macroHealth.status,
  adapter.adaptSourceHealth(assetTrackerHealth, "asset-tracker", assetTracker, currentNow).status,
  adapter.adaptSourceHealth(companiesHealth, "companies", companies, currentNow).status,
  adapter.adaptSourceHealth(assetRankingHealth, "asset-ranking", assetRanking, currentNow).status
]);
assert.strictEqual(operationCards[3].reportedPipelineStatus, assetRankingHealth.status);
/* 条数以各自健康文件声明的为准：跨资产清单扩容时这里不该跟着改成新的魔法数字。 */
assert.deepStrictEqual(operationCards.map((card) => card.publishedRecords), [
  macroHealth.coverage.publishedSeries,
  assetTracker.assets.length,
  companies.companies.length,
  assetRanking.assets.length
]);
assert.deepStrictEqual(operationCards.map((card) => card.expectedRecords), [
  3,
  assetTrackerHealth.coverage.expectedRecords,
  companiesHealth.coverage.expectedRecords,
  assetRankingHealth.coverage.expectedRecords
]);
assert.strictEqual(operationCards[1].symbol, `${assetTracker.assets.length} ASSETS`);
assert.deepStrictEqual(operationCards.map((card) => card.availableCoveragePct), [100, 100, 100, 100]);
assert.deepStrictEqual(operationCards.map((card) => card.freshCoveragePct), [
  macroHealth.coverage.freshCoveragePct,
  assetTrackerHealth.coverage.freshCoveragePct,
  companiesHealth.coverage.freshCoveragePct,
  assetRankingHealth.coverage.freshCoveragePct
]);
assert.deepStrictEqual(operationCards.map((card) => card.historyKnown), [
  macroHealth, assetTrackerHealth, companiesHealth, assetRankingHealth
].map((health) => health.historyStatus === "tracked"));
const readinessState = operationsData.adaptReadinessSnapshot(readiness, currentNow);
const expectedReadinessById = Object.fromEntries(readiness.pipelines.map((pipeline) => [pipeline.id, pipeline]));
operationCards.forEach((card) => {
  const expected = expectedReadinessById[card.id];
  assert(expected);
  assert.strictEqual(card.readiness.consecutiveSuccessfulCycles, expected.consecutiveSuccessfulCycles);
  assert.strictEqual(card.readiness.latestCycleDate, expected.cycleDates.slice().sort().at(-1));
  assert.strictEqual(card.readiness.status, readinessState.pipelines[card.id].status);
});
const staleReadiness = operationsData.adaptReadinessSnapshot(
  readiness, new Date(Date.parse(readiness.generatedAt) + 73 * 60 * 60 * 1000)
);
assert(Object.values(staleReadiness.pipelines).every((pipeline) => pipeline.status === "stale"));
const tamperedReadiness = JSON.parse(JSON.stringify(readiness));
tamperedReadiness.summary.minimumConsecutiveSuccessfulCycles += 1;
assert.throws(() => operationsData.adaptReadinessSnapshot(tamperedReadiness, currentNow), /不可复算/);

const staleOperationCards = operationsData.buildOperationsCards(operationSources, expiredOfficialHealthNow);
assert(staleOperationCards.every((card) => card.status === "stale"));
assert(staleOperationCards.every((card) => card.reportStale === true));
assert(staleOperationCards[0].note.includes("不代表当前任务仍在正常运行"));

const tamperedMacroHealth = JSON.parse(JSON.stringify(macroHealth));
tamperedMacroHealth.coverage.freshCoveragePct = macroHealth.coverage.freshCoveragePct === 100 ? 99 : 100;
assert.throws(() => operationsData.adaptMacroSourceHealth(tamperedMacroHealth, macro, currentNow), /覆盖率/);
const tamperedOperationSources = Object.assign({}, operationSources, {
  macroHealth: { data: tamperedMacroHealth, error: null }
});
const tamperedOperationCards = operationsData.buildOperationsCards(tamperedOperationSources, currentNow);
assert.strictEqual(tamperedOperationCards[0].status, "unknown");
assert.strictEqual(tamperedOperationCards[0].contractKnown, false);
assert.deepStrictEqual(tamperedOperationCards.slice(1).map((card) => card.status), [
  adapter.adaptSourceHealth(assetTrackerHealth, "asset-tracker", assetTracker, currentNow).status,
  adapter.adaptSourceHealth(companiesHealth, "companies", companies, currentNow).status,
  adapter.adaptSourceHealth(assetRankingHealth, "asset-ranking", assetRanking, currentNow).status
]);

const mismatchedMacroSnapshot = JSON.parse(JSON.stringify(macro));
mismatchedMacroSnapshot.updatedAt = "2026-08-03T22:00:00Z";
assert.throws(() => operationsData.adaptMacroSourceHealth(macroHealth, mismatchedMacroSnapshot, currentNow), /快照时间不一致/);
const failedOperationSources = Object.assign({}, operationSources, {
  companiesHealth: { data: null, error: new Error("HTTP 503") }
});
const failedOperationCards = operationsData.buildOperationsCards(failedOperationSources, currentNow);
assert.strictEqual(failedOperationCards[2].status, "unknown");
assert.strictEqual(failedOperationCards[2].publishedRecords, null);
assert(failedOperationCards[2].note.includes("HTTP 503"));
assert.strictEqual(failedOperationCards[0].status, macroHealth.status);

const crossAsset = adapter.adaptCrossAsset(assetTracker, currentNow, assetTrackerHealth);
assert.strictEqual(crossAsset.id, "cross-asset");
assert.strictEqual(crossAsset.status, assetTracker.status);
assert.strictEqual(crossAsset.asOf, assetTracker.asOf);
assert.strictEqual(crossAsset.updatedAt, assetTracker.updatedAt);
assert.strictEqual(crossAsset.source.name, "Yahoo Finance");
assert.strictEqual(crossAsset.periods.length, 5);
assert.strictEqual(crossAsset.assets.length, assetTracker.assets.length);
assert.deepStrictEqual(crossAsset.quality.counts, assetTracker.dataQuality.counts);
assert.strictEqual(crossAsset.quality.declaredValid, true);
assert.strictEqual(crossAsset.quality.contractKnown, true);
assert.strictEqual(crossAsset.sourceHealth.status, assetTrackerHealth.status);
assert.strictEqual(crossAsset.sourceHealth.freshCoveragePct, assetTrackerHealth.coverage.freshCoveragePct);
assert.strictEqual(crossAsset.sourceHealth.historyKnown, assetTrackerHealth.historyStatus === "tracked");
assert.strictEqual(crossAsset.sourceHealth.consecutiveFailures, assetTrackerHealth.consecutiveFailures);
assert.strictEqual(crossAsset.sourceHealth.reportStale, false);
const expiredTrackerHealth = adapter.adaptSourceHealth(
  assetTrackerHealth, "asset-tracker", assetTracker, expiredOfficialHealthNow
);
assert.strictEqual(expiredTrackerHealth.status, "stale");
assert.strictEqual(expiredTrackerHealth.pipelineStatus, assetTrackerHealth.status);
assert.strictEqual(expiredTrackerHealth.reportStale, true);
assert(expiredTrackerHealth.note.includes("不代表当前行情新鲜度"));
const failedTrackerHealth = JSON.parse(JSON.stringify(assetTrackerHealth));
Object.assign(failedTrackerHealth, {
  generatedAt: currentAttemptAt,
  lastAttemptAt: currentAttemptAt,
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
const fallbackTracker = JSON.parse(JSON.stringify(assetTracker));
const fallbackRow = fallbackTracker.assets[0];
fallbackRow.stale = true;
fallbackRow.suspect = false;
fallbackRow.dataMeta = {
  mode: "fallback", status: "partial", source: "Yahoo Finance", asOf: null,
  updatedAt: fallbackTracker.updatedAt, frequency: "daily",
  note: "测试夹具：本轮请求失败，沿用上一份逐条有效值。"
};
fallbackTracker.status = "partial";
fallbackTracker.dataQuality = qualityDeclaration(fallbackTracker.assets);
const fallbackCrossAsset = adapter.adaptCrossAsset(fallbackTracker, currentNow);
assert.strictEqual(fallbackCrossAsset.status, "partial");
const fallbackAsset = fallbackCrossAsset.assets.find((asset) => asset.dataMeta.mode === "fallback");
assert(fallbackAsset && fallbackAsset.dataMeta.asOf === null);
assert(fallbackAsset.dataLabel.includes("历史回退"));
const proxyTracker = JSON.parse(JSON.stringify(assetTracker));
const proxyRow = proxyTracker.assets.find((asset) => asset.name === "中证500");
proxyRow.symbol = "510500.SS";
proxyRow.proxy = {
  type: "etf", targetSymbol: "000905.SS", instrumentName: "中证500ETF",
  instrumentSymbol: "510500.SS", currency: "CNY", returnBasis: "price",
  note: "ETF收益率代理，可能存在跟踪误差。"
};
const proxyCrossAsset = adapter.adaptCrossAsset(proxyTracker, currentNow, assetTrackerHealth);
const adaptedProxy = proxyCrossAsset.assets.find((asset) => asset.name === "中证500");
assert(adaptedProxy.proxy && adaptedProxy.proxy.instrumentSymbol === "510500.SS");
assert(adaptedProxy.dataLabel.startsWith("PROXY · "));
const invalidProxyTracker = JSON.parse(JSON.stringify(proxyTracker));
invalidProxyTracker.assets.find((asset) => asset.name === "中证500").proxy.currency = "人民币";
assert.throws(() => adapter.adaptCrossAsset(invalidProxyTracker, currentNow), /代理标的契约无效/);
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
freshAssetTracker.updatedAt = currentAttemptAt;
freshAssetTracker.asOf = currentAttemptDate;
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
assert.strictEqual(freshCrossAsset.quality.counts.market, freshAssetTracker.assets.length);

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

const baselineResearch = adapter.buildResearchCards({
  assetTracker: { data: assetTracker, error: null },
  assetRanking: { data: assetRanking, error: null },
  companies: { data: companies, error: null }
}, currentNow);
assert.strictEqual(baselineResearch.length, 3);

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
assert.strictEqual(invalidResearch[1].status, baselineResearch[1].status);
assert.strictEqual(invalidResearch[2].status, baselineResearch[2].status);

const failedResearch = adapter.buildResearchCards({
  assetTracker: { data: null, error: new Error("HTTP 503") },
  assetRanking: { data: assetRanking, error: null },
  companies: { data: companies, error: null }
}, currentNow);
assert.strictEqual(failedResearch.length, 3);
assert.strictEqual(failedResearch[0].status, "error");
assert.strictEqual(failedResearch[0].assets.length, 0);
assert.strictEqual(failedResearch[1].status, baselineResearch[1].status);
assert.strictEqual(failedResearch[2].status, baselineResearch[2].status);

const globalAssets = adapter.adaptAssetRanking(assetRanking, currentNow, assetRankingHealth);
assert.strictEqual(globalAssets.id, "asset-ranking");
assert.strictEqual(globalAssets.status, assetRanking.status);
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
assert.strictEqual(globalAssets.sourceHealth.status,
  adapter.adaptSourceHealth(assetRankingHealth, "asset-ranking", assetRanking, currentNow).status);
assert.strictEqual(globalAssets.sourceHealth.reportedPipelineStatus, assetRankingHealth.status);
assert.strictEqual(globalAssets.sourceHealth.freshCoveragePct,
  assetRankingHealth.coverage.freshCoveragePct);
assert.strictEqual(globalAssets.sourceHealth.verifiedCoveragePct,
  assetRankingHealth.coverage.verifiedCoveragePct);
assert.strictEqual(globalAssets.sourceHealth.slowEstimateRecords, assetRanking.dataQuality.counts.estimate);
assert.strictEqual(globalAssets.sourceHealth.dynamicIssueRecords, 0);
assert(globalAssets.assets[0].dataLabel.includes("静态估算") && globalAssets.assets[0].dataLabel.includes("Savills"));
globalAssets.assets.forEach((asset, index) => {
  const mode = assetRanking.assets[index].dataMeta.mode;
  if (mode === "estimate") assert(asset.dataLabel.includes("静态估算"));
  if (mode === "fallback") assert(asset.dataLabel.includes("历史回退"));
  if (mode === "unknown") assert.strictEqual(asset.dataLabel, "来源待确认");
});
if (assetRanking.dataQuality.counts.unknown > 0) {
  assert(globalAssets.note.includes(assetRanking.dataQuality.counts.unknown + "项旧快照"));
}

const freshAssetRanking = JSON.parse(JSON.stringify(assetRanking));
freshAssetRanking.updatedAt = currentAttemptAt;
freshAssetRanking.asOf = currentAttemptDate;
freshAssetRanking.status = "ok";
freshAssetRanking.assets.forEach((asset) => {
  asset.stale = false;
  const estimate = asset.static === true || asset.private === true;
  asset.dataMeta = {
    mode: estimate ? "estimate" : "market",
    status: "ok",
    source: asset.dataMeta.source,
    asOf: estimate ? "2026-08-01" : currentAttemptAt,
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
assert.strictEqual(invalidRankingResearch[0].status, baselineResearch[0].status);
assert.strictEqual(invalidRankingResearch[1].status, "error");
assert.strictEqual(invalidRankingResearch[1].totalMarketCap, null);

const brokenTopRanking = JSON.parse(JSON.stringify(assetRanking));
brokenTopRanking.assets[0].marketCap = null;
const brokenTopResearch = adapter.buildResearchCards({
  assetTracker: { data: assetTracker, error: null },
  assetRanking: { data: brokenTopRanking, error: null },
  companies: { data: companies, error: null }
}, currentNow);
assert.strictEqual(brokenTopResearch[0].status, baselineResearch[0].status);
assert.strictEqual(brokenTopResearch[1].status, "error");

const failedRankingResearch = adapter.buildResearchCards({
  assetTracker: { data: assetTracker, error: null },
  assetRanking: { data: null, error: new Error("HTTP 503") },
  companies: { data: companies, error: null }
}, currentNow);
assert.strictEqual(failedRankingResearch[0].status, baselineResearch[0].status);
assert.strictEqual(failedRankingResearch[1].status, "error");

const companyLeaders = adapter.adaptCompanies(companies, currentNow, companiesHealth);
const listedCompanies = companies.companies.filter((company) => !company.private);
const eligibleCompanyMovers = listedCompanies.filter((company) => company.stale !== true
  && company.dataMeta && company.dataMeta.mode === "market" && company.dataMeta.status === "ok"
  && Number.isFinite(company.changePct) && company.changePct >= -100 && company.changePct <= 1000)
  .slice().sort((a, b) => a.changePct - b.changePct);
assert.strictEqual(companyLeaders.id, "company-leaders");
assert.strictEqual(companyLeaders.status, companies.status);
assert.strictEqual(companyLeaders.listedCount, companies.listedCount);
assert.strictEqual(companyLeaders.privateCount, companies.privateCount);
assert.strictEqual(companyLeaders.asOf, companies.asOf);
assert.strictEqual(companyLeaders.updatedAt, companies.updatedAt);
assert(companyLeaders.source.name.includes("Yahoo Finance") && companyLeaders.source.name.includes("multiples.vc"));
assert.deepStrictEqual(companyLeaders.topCompanies.map((company) => company.symbol), listedCompanies.slice(0, 3).map((company) => company.symbol));
assert.strictEqual(companyLeaders.gainer && companyLeaders.gainer.symbol,
  eligibleCompanyMovers.length >= 20 ? eligibleCompanyMovers[eligibleCompanyMovers.length - 1].symbol : null);
assert.strictEqual(companyLeaders.laggard && companyLeaders.laggard.symbol,
  eligibleCompanyMovers.length >= 20 ? eligibleCompanyMovers[0].symbol : null);
assert.strictEqual(companyLeaders.moverCoverage, eligibleCompanyMovers.length);
assert.deepStrictEqual(companyLeaders.quality.counts, companies.dataQuality.counts);
assert.strictEqual(companyLeaders.quality.declaredValid, true);
assert.strictEqual(companyLeaders.sourceHealth.status, companiesHealth.status);
assert.strictEqual(companyLeaders.sourceHealth.freshCoveragePct,
  companiesHealth.coverage.freshCoveragePct);
assert.strictEqual(companyLeaders.sourceHealth.verifiedCoveragePct,
  companiesHealth.coverage.verifiedCoveragePct);
assert.strictEqual(companyLeaders.sourceHealth.slowEstimateRecords, companies.dataQuality.counts.estimate);
const expectedCompanyDynamicIssues = companies.companies.filter((company) => company.private !== true
  && (!company.dataMeta || company.dataMeta.mode !== "market" || company.dataMeta.status !== "ok")).length;
assert.strictEqual(companyLeaders.sourceHealth.dynamicIssueRecords, expectedCompanyDynamicIssues);
if (companies.dataQuality.counts.unknown + companies.dataQuality.counts.unavailable > 0) {
  assert(companyLeaders.note.includes("暂停当日领涨与领跌"));
}
companyLeaders.topCompanies.forEach((company, index) => {
  const mode = listedCompanies[index].dataMeta.mode;
  if (mode === "market") assert(company.dataLabel.includes("行情"));
  if (mode === "fallback") assert(company.dataLabel.includes("历史回退"));
  if (mode === "unknown") assert.strictEqual(company.dataLabel, "来源待确认");
});
assert(Math.abs(companyLeaders.listedMarketCap - listedCompanies.reduce((sum, company) => sum + company.marketCap, 0)) < 1e-9);
const dynamicFallbackCompanies = JSON.parse(JSON.stringify(companies));
dynamicFallbackCompanies.companies.find((company) => !company.private).dataMeta = {
  mode: "fallback", status: "stale", source: "Yahoo Finance",
  asOf: "2026-08-01T00:00:00Z", updatedAt: "2026-08-01T00:00:00Z", frequency: "daily"
};
dynamicFallbackCompanies.dataQuality = qualityDeclaration(dynamicFallbackCompanies.companies);
const dynamicFallbackHealth = JSON.parse(JSON.stringify(companiesHealth));
dynamicFallbackHealth.status = "degraded";
dynamicFallbackHealth.coverage.counts = dynamicFallbackCompanies.dataQuality.counts;
dynamicFallbackHealth.coverage.freshCoveragePct = Math.round(
  dynamicFallbackCompanies.dataQuality.counts.market / companies.listedCount * 10000
) / 100;
dynamicFallbackHealth.coverage.verifiedCoveragePct = 100;
dynamicFallbackHealth.attempt.counts = dynamicFallbackCompanies.dataQuality.counts;
assert.strictEqual(adapter.adaptSourceHealth(
  dynamicFallbackHealth, "companies", dynamicFallbackCompanies, currentNow
).status, "degraded");
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
freshCompanies.updatedAt = currentAttemptAt;
freshCompanies.asOf = currentAttemptDate;
freshCompanies.companies.forEach((company) => {
  if (!company.private) {
    if (!Number.isFinite(company.changePct)) company.changePct = 0;
    company.stale = false;
    company.dataMeta = {
      mode: "market", status: "ok", source: "Yahoo Finance", asOf: currentAttemptAt,
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
assert.strictEqual(invalidCompanyResearch[0].status, baselineResearch[0].status);
assert.strictEqual(invalidCompanyResearch[1].status, baselineResearch[1].status);
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
assert.strictEqual(failedCompanyResearch[0].status, baselineResearch[0].status);
assert.strictEqual(failedCompanyResearch[1].status, baselineResearch[1].status);
assert.strictEqual(failedCompanyResearch[2].status, "error");

const calendarNow = new Date(Date.parse(econCalendar.updatedAt) + 60 * 60 * 1000);
const calendar = informationData.adaptEconomicCalendar(econCalendar, calendarNow);
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
  assert(calendar.events.every((event) => Date.parse(event.ts) >= calendarNow.getTime()));
  assert(calendar.events.every((event, index) => index === 0
    || event.timestamp >= calendar.events[index - 1].timestamp));
} else {
  assert.strictEqual(calendar.selectionLabel, "最近重要事件");
  assert(calendar.events.every((event) => Date.parse(event.ts) < calendarNow.getTime()));
  assert(calendar.events.every((event, index) => index === 0
    || event.timestamp <= calendar.events[index - 1].timestamp));
}

/* 回归：周末没有经济数据发布，周范围常在周五结束；周六跑出的文件不得被误判为过期。
   固定构造一份周日~周五的周历，分别在周六、下周日两个时点求值。 */
const weekendCalendar = JSON.parse(JSON.stringify(econCalendar));
weekendCalendar.weekOf = "2026-08-16 ~ 2026-08-21";
weekendCalendar.asOf = "2026-08-22";
weekendCalendar.updatedAt = "2026-08-22T21:30:00Z";
const saturdayNow = new Date(Date.parse("2026-08-22T22:30:00Z"));
assert.notStrictEqual(informationData.adaptEconomicCalendar(weekendCalendar, saturdayNow).status, "stale",
  "周六（本周内、无发布日）不得因周范围止于周五而被判为过期");
const nextSundayCalendar = JSON.parse(JSON.stringify(weekendCalendar));
nextSundayCalendar.asOf = "2026-08-23";
nextSundayCalendar.updatedAt = "2026-08-23T10:00:00Z";
assert.strictEqual(
  informationData.adaptEconomicCalendar(nextSundayCalendar, new Date(Date.parse("2026-08-23T11:00:00Z"))).status,
  "stale", "文件已进入下一周仍必须判为过期——放宽整周不得掩盖真正的跨周陈旧");
const agedCalendar = JSON.parse(JSON.stringify(weekendCalendar));
assert.strictEqual(
  informationData.adaptEconomicCalendar(agedCalendar, new Date(Date.parse("2026-08-24T21:30:00Z"))).status,
  "stale", "超过36小时未更新仍必须判为过期");

const partialCalendar = JSON.parse(JSON.stringify(econCalendar));
partialCalendar.count += 1;
assert.strictEqual(informationData.adaptEconomicCalendar(partialCalendar, calendarNow).status, "partial");

const staleCalendar = JSON.parse(JSON.stringify(econCalendar));
staleCalendar.updatedAt = "2026-07-31T12:00:00Z";
assert.strictEqual(informationData.adaptEconomicCalendar(staleCalendar, calendarNow).status, "stale");

const invalidCalendar = JSON.parse(JSON.stringify(econCalendar));
invalidCalendar.source = "Unknown calendar";
const invalidInformation = informationData.buildInformationCards({
  calendar: { data: invalidCalendar, error: null }
}, calendarNow);
assert.strictEqual(invalidInformation.length, 1);
assert.strictEqual(invalidInformation[0].status, "error");
assert.strictEqual(invalidInformation[0].events.length, 0);

const failedInformation = informationData.buildInformationCards({
  calendar: { data: null, error: new Error("HTTP 503") }
}, calendarNow);
assert.strictEqual(failedInformation.length, 1);
assert.strictEqual(failedInformation[0].status, "error");
assert.strictEqual(failedInformation[0].events.length, 0);

const newsNow = new Date(Date.parse(financeNews.updatedAt) + 60 * 60 * 1000);
const news = informationData.adaptFinanceNews(financeNews, newsNow);
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
assert(news.articles.every((item) => informationData.isSafeGoogleNewsUrl(item.link)));
assert(news.articles.every((item, index) => index === 0 || item.published <= news.articles[index - 1].published));
assert(news.articles.every((item) => !Object.prototype.hasOwnProperty.call(item, "price")));

const partialNews = JSON.parse(JSON.stringify(financeNews));
partialNews.categories.find((category) => category.key === "markets").items[0].link = "https://example.com/unsafe";
assert.strictEqual(informationData.adaptFinanceNews(partialNews, newsNow).status, "partial");

const staleNewsNow = new Date(Date.parse(financeNews.updatedAt) + 13 * 60 * 60 * 1000);
assert.strictEqual(informationData.adaptFinanceNews(financeNews, staleNewsNow).status, "stale");

const invalidNews = JSON.parse(JSON.stringify(financeNews));
invalidNews.source = "Yahoo Finance";
const invalidNewsInformation = informationData.buildInformationCards({
  news: { data: invalidNews, error: null }
}, newsNow);
assert.strictEqual(invalidNewsInformation.length, 1);
assert.strictEqual(invalidNewsInformation[0].status, "error");
assert.strictEqual(invalidNewsInformation[0].articles.length, 0);

const failedNewsInformation = informationData.buildInformationCards({
  news: { data: null, error: new Error("HTTP 503") }
}, newsNow);
assert.strictEqual(failedNewsInformation.length, 1);
assert.strictEqual(failedNewsInformation[0].status, "error");
assert.strictEqual(failedNewsInformation[0].articles.length, 0);

const combinedInformation = informationData.buildInformationCards({
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
console.log("- BTC market/fallback + market-only / latest-five / safe links / failure isolation: PASS");
})().catch((error) => { console.error(error); process.exit(1); });
"""
    result = subprocess.run(
        ["node", "-e", script],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    require(result.returncode == 0, f"DGS10、DTWEXBGS、RWTC与BTC/USD JavaScript适配测试失败：\n{result.stdout}{result.stderr}")
    print(result.stdout.strip())


def run_provider_widget_runtime_tests() -> None:
    script = r"""
const assert = require("assert");
const adapter = require("./apps/finance-terminal/app.js");

(async () => {
  const missing = await adapter.waitForProviderWidgetRegistration(null, "tv-mini-chart", 5);
  assert.deepStrictEqual(missing, {
    status: "unavailable", reason: "custom-elements-unavailable"
  });

  const alreadyRegistered = await adapter.waitForProviderWidgetRegistration({
    get: (tag) => tag === "tv-mini-chart" ? function Widget() {} : undefined,
    whenDefined: () => Promise.resolve()
  }, "tv-mini-chart", 5);
  assert.deepStrictEqual(alreadyRegistered, {
    status: "registered", reason: "custom-element-registered"
  });

  let resolveRegistration;
  const registration = new Promise((resolve) => { resolveRegistration = resolve; });
  setTimeout(resolveRegistration, 0);
  const delayed = await adapter.waitForProviderWidgetRegistration({
    get: () => undefined,
    whenDefined: () => registration
  }, "tv-mini-chart", 50);
  assert.deepStrictEqual(delayed, {
    status: "registered", reason: "custom-element-registered"
  });

  const timedOut = await adapter.waitForProviderWidgetRegistration({
    get: () => undefined,
    whenDefined: () => new Promise(() => {})
  }, "tv-mini-chart", 5);
  assert.deepStrictEqual(timedOut, {
    status: "unavailable", reason: "registration-timeout"
  });

  const mountedHost = {
    localName: "tv-mini-chart",
    isConnected: true,
    matches: (selector) => selector === ":defined",
    getBoundingClientRect: () => ({ width: 320, height: 176 })
  };
  assert.deepStrictEqual(adapter.inspectProviderWidgetHost(
    mountedHost, "tv-mini-chart", "connected-defined-element-with-layout"
  ), {
    status: "mounted", reason: "connected-defined-element-with-layout"
  });
  assert.deepStrictEqual(adapter.inspectProviderWidgetHost({
    ...mountedHost, isConnected: false
  }, "tv-mini-chart", "connected-defined-element-with-layout"), {
    status: "unavailable", reason: "component-host-disconnected"
  });
  assert.deepStrictEqual(adapter.inspectProviderWidgetHost({
    ...mountedHost, matches: () => false
  }, "tv-mini-chart", "connected-defined-element-with-layout"), {
    status: "unavailable", reason: "component-host-not-defined"
  });
  assert.deepStrictEqual(adapter.inspectProviderWidgetHost({
    ...mountedHost, getBoundingClientRect: () => ({ width: 0, height: 176 })
  }, "tv-mini-chart", "connected-defined-element-with-layout"), {
    status: "unavailable", reason: "component-host-empty-layout"
  });

  console.log("TradingView proxy runtime registration and host states: PASS");
  console.log("- missing / pre-registered / delayed / timeout fallback: PASS");
  console.log("- connected / defined / non-empty host layout boundary: PASS");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
"""
    result = subprocess.run(
        ["node", "-e", script],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    require(result.returncode == 0,
            f"TradingView代理运行时状态测试失败：\n{result.stdout}{result.stderr}")
    print(result.stdout.strip())


def main() -> None:
    for path in (
        PAGE, APP, LOADER, TERMINAL_VISUALS, VISION_CSS, DATA, READINESS_DATA, MARKET_LICENSE_READINESS,
        MACRO_DATA, FEAR_GREED_DATA, FEAR_GREED_HEALTH, OFR_DATA, OFR_HEALTH,
        ASSET_TRACKER_DATA, ASSET_TRACKER_HEALTH, ASSET_RANKING_DATA, ASSET_RANKING_HEALTH,
        COMPANIES_DATA, COMPANIES_HEALTH,
        ECON_CALENDAR_DATA, ECON_CALENDAR_HEALTH, FINANCE_NEWS_DATA, FINANCE_NEWS_HEALTH,
        MACRO_BUILD, MACRO_WORKFLOW, FEAR_GREED_WORKFLOW, OFR_WORKFLOW, ASSET_TRACKER_WORKFLOW,
        ASSET_RANKING_WORKFLOW, COMPANIES_WORKFLOW, ECON_CALENDAR_WORKFLOW, FINANCE_NEWS_WORKFLOW,
        COMPANIES_HISTORY, ASSET_RANKING_CRYPTO, MARKET_HISTORY_MODULE,
        SCHEDULER_WORKFLOW, SOURCE_HEALTH_VALIDATOR, SOURCE_HEALTH_DOC,
        SUPPORTING_HEALTH_VALIDATOR, SUPPORTING_HEALTH_DOC,
        BROWSER_VALIDATOR, BROWSER_EVIDENCE, BROWSER_EVIDENCE_VALIDATOR, VISUALS_VALIDATOR,
        PROXY_RUNTIME_HISTORY, PROXY_RUNTIME_HISTORY_VALIDATOR, HOME,
    ):
        require(path.is_file(), f"缺少文件：{path.relative_to(ROOT)}")

    data = json.loads(DATA.read_text(encoding="utf-8"))
    readiness = json.loads(READINESS_DATA.read_text(encoding="utf-8"))
    validate_readiness_snapshot(readiness)
    market_license_readiness = json.loads(MARKET_LICENSE_READINESS.read_text(encoding="utf-8"))
    market_source_errors = validate_market_source_readiness(market_license_readiness)
    require(not market_source_errors,
            "免费代理行情契约无效：" + "；".join(market_source_errors))
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
    require(data.get("schemaVersion") == 3, "data.json schemaVersion必须为3")
    require(data.get("demo") is False, "免费代理策略下data.json必须包含demo: false")
    require(data.get("status") == "ok", "无演示值的混合展示配置状态必须为ok")
    require(
        "DGS10" in data.get("source", "") and "DTWEXBGS" in data.get("source", "")
        and "RWTC" in data.get("source", "") and "CoinGecko" in data.get("source", "")
        and "Yahoo Finance" in data.get("source", "") and "TradingView" in data.get("source", "")
        and "DIA" in data.get("source", "") and "GLD" in data.get("source", ""),
        "总来源必须同时标注四项站内行情与TradingView免费代理",
    )
    parse_iso(data["updatedAt"])

    assets = data.get("assets")
    require(isinstance(assets, list) and len(assets) == 6, "必须且只能包含6项核心资产")
    require({asset.get("symbol") for asset in assets} == EXPECTED_SYMBOLS, "资产代码与需求不一致")
    require(len({asset.get("id") for asset in assets}) == len(assets), "资产ID必须唯一")

    demo_assets = [asset for asset in assets if asset.get("demo") is True]
    require(not demo_assets, "免费代理接入后不得保留演示资产")
    proxy_configs = [asset for asset in assets if asset.get("id") in EXPECTED_PROXIES]
    real_configs = [asset for asset in assets if asset.get("id") in {"us10y", "dxy", "wti", "bitcoin"}]
    require(len(proxy_configs) == len(EXPECTED_PROXIES),
            "免费ETF代理项数必须与已登记的代理契约一致")
    require(len(real_configs) == 4, "站内真实数据配置必须是us10y、dxy、wti与bitcoin")

    for asset in assets:
        missing = COMMON_ASSET_FIELDS - asset.keys()
        require(not missing, f"{asset.get('symbol', 'unknown')} 缺少字段：{sorted(missing)}")
        require(isinstance(asset["source"], dict) and asset["source"].get("name"), f"{asset['symbol']} 缺少结构化数据来源")
    for asset in proxy_configs:
        expected_symbol, expected_original, expected_widget = EXPECTED_PROXIES[asset["id"]]
        external = asset.get("externalDisplay") or {}
        proxy_for = asset.get("proxyFor") or {}
        require(asset["symbol"] == expected_symbol and asset.get("instrument") == "etf-proxy",
                f"{asset['id']}免费ETF代理代码或类型无效")
        require(asset["status"] == "provider" and asset["frequency"] == "provider-managed",
                f"{asset['id']}必须由TradingView管理行情状态和频率")
        require(asset.get("price") is None and asset.get("changePct") is None
                and asset.get("asOf") is None and asset.get("updatedAt") is None,
                f"{asset['id']}不得保存免费组件中的行情值或时间戳")
        require(external == {
            "provider": "TradingView", "widget": "tv-mini-chart",
            "widgetSymbol": expected_widget, "rawDataStored": False,
        }, f"{asset['id']}TradingView组件配置无效")
        require(proxy_for.get("symbol") == expected_original
                and proxy_for.get("isSameInstrument") is False,
                f"{asset['id']}必须明确代理不是原标的")
        require("TradingView" in asset["source"]["name"]
                and asset["source"]["url"].startswith("https://www.tradingview.com/symbols/"),
                f"{asset['id']}缺少TradingView官方来源")
        require(isinstance(asset["spark"], list) and not asset["spark"],
                f"{asset['id']}不得使用本地演示走势")

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

    bitcoin_config = real_by_id["bitcoin"]
    require(bitcoin_config["symbol"] == "BTC/USD", "比特币卡片代码必须为BTC/USD")
    require(bitcoin_config["status"] == "loading", "BTC/USD配置必须以loading状态等待适配")
    require(bitcoin_config.get("price") is None and bitcoin_config.get("changePct") is None,
            "BTC/USD价格与涨跌不得留在终端配置中")
    require(bitcoin_config.get("asOf") is None and bitcoin_config.get("updatedAt") is None,
            "BTC/USD时间不得留在终端配置中")
    require(bitcoin_config["source"].get("assetId") == "bitcoin"
            and "CoinGecko" in bitcoin_config["source"].get("name", ""),
            "BTC/USD来源必须指向CoinGecko资产记录")
    require(bitcoin_config["source"].get("url") == "https://www.coingecko.com/",
            "BTC/USD主要来源链接不准确")
    require(bitcoin_config.get("dataRef") == "../asset-ranking/data.json#assets[Bitcoin]",
            "BTC/USD必须复用全球资产榜逐条行情")

    category, row = find_dgs10(macro)
    require(category.get("src") == "FRED", "宏观雷达DGS10来源必须为FRED")
    validate_official_observations(row, "DGS10")
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
    validate_official_observations(dollar_reference, "DTWEXBGS")
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
    validate_official_observations(wti_reference, "RWTC")
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
    loader = LOADER.read_text(encoding="utf-8")
    terminal_visuals = TERMINAL_VISUALS.read_text(encoding="utf-8")
    risk_radar_module = RISK_RADAR_MODULE.read_text(encoding="utf-8")
    worldmap_module = WORLDMAP_MODULE.read_text(encoding="utf-8")
    sessions_module = SESSIONS_MODULE.read_text(encoding="utf-8")
    watchlist_module = WATCHLIST_MODULE.read_text(encoding="utf-8")
    health_adapters_module = HEALTH_ADAPTERS_MODULE.read_text(encoding="utf-8")
    detail_view_module = DETAIL_VIEW_MODULE.read_text(encoding="utf-8")
    radar_view_module = RADAR_VIEW_MODULE.read_text(encoding="utf-8")
    curve_view_module = CURVE_VIEW_MODULE.read_text(encoding="utf-8")
    globe_module = GLOBE_MODULE.read_text(encoding="utf-8")
    globe_texture_module = GLOBE_TEXTURE_MODULE.read_text(encoding="utf-8")
    gateway_preview_module = GATEWAY_PREVIEW_MODULE.read_text(encoding="utf-8")
    orbit_links_module = ORBIT_LINKS_MODULE.read_text(encoding="utf-8")
    reference_home_v3_css = REFERENCE_HOME_V3_CSS.read_text(encoding="utf-8")
    reference_home_v4_css = REFERENCE_HOME_V4_CSS.read_text(encoding="utf-8")
    reference_home_v5_css = REFERENCE_HOME_V5_CSS.read_text(encoding="utf-8")
    vision_css = VISION_CSS.read_text(encoding="utf-8")
    command_center_css = COMMAND_CENTER_CSS.read_text(encoding="utf-8")
    reference_fidelity_css = REFERENCE_FIDELITY_CSS.read_text(encoding="utf-8")
    aurora_home_css = AURORA_HOME_CSS.read_text(encoding="utf-8")
    command_center_module = COMMAND_CENTER_MODULE.read_text(encoding="utf-8")
    aurora_home_module = AURORA_HOME_MODULE.read_text(encoding="utf-8")
    regression_module = REGRESSION_MODULE.read_text(encoding="utf-8")
    risk_view_module = RISK_VIEW_MODULE.read_text(encoding="utf-8")
    research_view_module = RESEARCH_VIEW_MODULE.read_text(encoding="utf-8")
    information_view_module = INFORMATION_VIEW_MODULE.read_text(encoding="utf-8")
    information_data_module = INFORMATION_DATA_MODULE.read_text(encoding="utf-8")
    operations_data_module = OPERATIONS_DATA_MODULE.read_text(encoding="utf-8")
    operations_view_module = OPERATIONS_VIEW_MODULE.read_text(encoding="utf-8")
    board_data_module = BOARD_DATA_MODULE.read_text(encoding="utf-8")
    board_view_module = BOARD_VIEW_MODULE.read_text(encoding="utf-8")
    geo_risk_module = GEO_RISK_MODULE.read_text(encoding="utf-8")
    terminal_views = (app + "\n" + risk_view_module + "\n" + research_view_module
                      + "\n" + information_view_module + "\n" + operations_view_module)
    compact_loader = re.sub(r"\s+", "", loader)
    require(APP.stat().st_size <= 220_000, "金融终端生产入口脚本超过220KB性能预算")
    # 14,000 是按「一个分区一个触发元素、进入视野即加载」那版观察器设的。改为
    # 「掠过不算、停留才算」并允许一个分区挂多个触发元素后，这段不可压缩地变大；
    # 同时 app.js 里那个各行其是的雷达观察器被删掉，常规加载合计反而比之前小。
    # 15,600 是在原15KB基础上给「品类行情板」留出的增量：新增一份美债收益率曲线
    # 资源与一个只复用已有资源键的board资源组，加载器本身多出约210字节；常规加载
    # 合计仍受下方230KB预算约束。
    # 15,800：风险分区多读一份跨资产快照（地缘风险定价的能源与避险两条轴），
    # 该资源键在品类行情与市场研究两组里已存在，加载器按键去重，请求数不变。
    # 16,300：加载器的快照多带一个「已登记上游资源数」，让探针不必各处硬编码计数。
    require(LOADER.stat().st_size <= 16_300, "金融终端分区加载模块超过16.3KB性能预算")
    require(TERMINAL_VISUALS.stat().st_size <= 16_000, "金融终端视觉数据模块超过16KB性能预算")
    # 3,000 是按旧版「把宏观状态一个分数加权重组出六个轴」那一行设定的。六个轴改读
    # 六个具名真实制度信号后，查表逻辑不可压缩地更大；该模块不计入 230KB 常规加载
    # 合计，增量约占首屏 JS 的 0.2%，换来雷达从推算值变为真实测量。
    require(RISK_RADAR_MODULE.stat().st_size <= 3_400, "金融终端风险雷达模块超过3.4KB性能预算")
    require(WORLDMAP_MODULE.stat().st_size <= 5_000, "金融终端点阵世界地图模块超过5KB性能预算")
    require(SESSIONS_MODULE.stat().st_size <= 3_500, "金融终端交易时段模块超过3.5KB性能预算")
    # 7,600：自选清单改为整页共用一份状态并支持分区各自的筛选入口后必要的增量。
    require(WATCHLIST_MODULE.stat().st_size <= 7_600, "金融终端自选清单模块超过7.6KB性能预算")
    require(HEALTH_ADAPTERS_MODULE.stat().st_size <= 11_000, "金融终端辅助来源健康适配层超过11KB性能预算")
    require(DETAIL_VIEW_MODULE.stat().st_size <= 13_000, "金融终端资产详情抽屉模块超过13KB性能预算")
    require(RADAR_VIEW_MODULE.stat().st_size <= 6_000, "金融终端雷达构成抽屉模块超过6KB性能预算")
    require(CURVE_VIEW_MODULE.stat().st_size <= 9_000, "金融终端收益率曲线抽屉模块超过9KB性能预算")
    require(CORRELATION_VIEW_MODULE.stat().st_size <= 15_000,
            "金融终端相关性矩阵抽屉模块超过15KB性能预算")
    require(GLOBE_MODULE.stat().st_size <= 8_000, "金融终端地球动画模块超过8KB性能预算")
    # 正射纹理以520px为上限并缓存旋转结果；四邻域对比只增强原图真实城市灯光。
    require(GLOBE_TEXTURE_MODULE.stat().st_size <= 5_800,
            "金融终端正射地球纹理模块超过5.8KB性能预算")
    require(ORBIT_LINKS_MODULE.stat().st_size <= 4_000, "金融终端市场连线模块超过4KB性能预算")
    # 三张入口卡现共同镜像跨资产、宏观与经济日历快照；多出的解析只在risk组就绪后按需加载。
    require(GATEWAY_PREVIEW_MODULE.stat().st_size <= 14_000, "金融终端三工作区预览模块超过14KB性能预算")
    require(VISION_CSS.stat().st_size <= 28_000, "金融终端科幻视觉样式超过28KB性能预算")
    # 20,000 是在分区内容还没被发现遭裁切时定的。补上「分区内那一层也要能缩」与
    # 遥测面板第三行两处修复、连同解释它们为何存在的注释后需要 20.7KB；换回的是
    # OFR 卡片与运行证据面板不再被裁掉 137px 与 201px，收益率曲线入口不再缺 6px。
    # 27,000：一屏总览把核心资产上移到第二行、原ETF代理那一格改放地缘风险定价
    # 表盘，两块各自的紧凑化规则（含四条轴在窄格里的两行排布）都在这里。
    # 24,600：总览里的行情板多出一列迷你走势与一条脉冲条的紧凑化规则。
    require(COMMAND_CENTER_CSS.stat().st_size <= 27_000, "金融终端单屏指挥中心样式超过27KB性能预算")
    require(VISUAL_FIDELITY_CSS.stat().st_size <= 6_000, "金融终端高保真视觉层超过6KB性能预算")
    require(REFERENCE_FIDELITY_CSS.stat().st_size <= 12_900, "金融终端参考图精修层超过12.9KB性能预算")
    require(AURORA_HOME_CSS.stat().st_size <= 26_000, "金融终端极光首页样式超过26KB性能预算")
    require(REFERENCE_HOME_V2_CSS.stat().st_size <= 27_000, "金融终端参考首页第二版样式超过27KB性能预算")
    # 22,000 是第一轮参考对齐时定的。第二轮把行情带改成椭圆弧带、证据条与六个标的换成
    # 图形徽章、曲线补节点与图例、影响强度改三段式、页脚每组补图标块，另加解释这些取值
    # 由来的注释后需要 27.2KB；换回的是首屏与参考稿在弧带、图标、连线与页脚四处对齐。
    # 28,800：第三轮把总览读数从等宽体换成无衬线＋表格数字（参考稿的读数是比例字体，
    # 等宽把字距拉宽、气质偏终端），这一层连同说明注释再占 1.5KB。
    # 30,200：第四轮入口卡指数预览显示真实当日涨跌，逐行两列排布、涨跌配色与
    # 表头那两行来源披露（不截断）在这里。
    require(REFERENCE_HOME_V3_CSS.stat().st_size <= 30_200, "金融终端参考首页第三版样式超过30.2KB性能预算")
    # v4仅在桌面总览上校正1672×941参考图的坐标、比例和光效；移动端继续由v3负责。
    require(REFERENCE_HOME_V4_CSS.stat().st_size <= 15_500,
            "金融终端1672像素参考锁定样式超过15.5KB性能预算")
    # v5补回入口卡真实表格、曲线、事件与异动密度，并封住宽屏装饰造成的根横向滚动。
    require(REFERENCE_HOME_V5_CSS.stat().st_size <= 20_500,
            "金融终端参考丰富度样式超过20.5KB性能预算")
    require(COMMAND_CENTER_MODULE.stat().st_size <= 4_000, "金融终端视图切换模块超过4KB性能预算")
    # HUD只把既有已校验状态压缩为中文短标签与等价覆盖率百分比，不引入第二套数据。
    require(AURORA_HOME_MODULE.stat().st_size <= 4_200, "金融终端极光首页同步模块超过4.2KB性能预算")
    require(APP.stat().st_size + LOADER.stat().st_size + TERMINAL_VISUALS.stat().st_size
            + COMMAND_CENTER_MODULE.stat().st_size + GLOBE_MODULE.stat().st_size
            + GLOBE_TEXTURE_MODULE.stat().st_size
            + ORBIT_LINKS_MODULE.stat().st_size
            + AURORA_HOME_MODULE.stat().st_size <= 230_000,
            "金融终端常规加载JavaScript超过230KB性能预算")
    # 23,000 是加入品类行情板与分区折叠检查后的预算：探针要逐「标签组」校验键盘与
    # 语义（页面现在有跨资产周期与品类行情板两组），核对六个品类标签、当前品类的
    # 价格/涨跌列、折叠按钮默认收起、搜索框与逐行自选开关，并在量尺寸前记下两个
    # 工程/运营向分区折叠壳的默认状态。该模块只在 regression=1 时加载。
    # 25,400：探针额外核对每行的迷你走势位、品类脉冲条，以及地缘风险定价的
    # 四条轴与五档等级梯（缺轴时改为核对「不可用」态而不是分数）。
    # 25.8KB包含资产主值盒的诊断尺寸；仅失败时写入证据，不进入常规加载路径。
    # 26,200：分阶段加载的资源计数改为按加载器登记表推导，不再抄硬编码数字。
    require(REGRESSION_MODULE.stat().st_size <= 26_200,
            "仅回归模式加载的浏览器探针超过26.2KB性能预算")
    # 25,500：在 22.5KB 基础上再给「商品现货与官方指数」那条管道留出的增量——它把 FRED
    # 的 EIA 日频现货与 IMF 月频初级商品价并进商品品类，逐条按自己的频率标口径与涨跌基准。
    # 分组与并流都只是重新编排已经取到的行，不新增任何行情事实。
    # 27,500：再加上「变 / 每周 / 月度 / 年初至今 / 同比」五列所需的逐行字段——
    # 绝对变化由已发布的价与涨跌幅现场复算，区间涨跌沿用上游已算好的值。
    # 27,500 是商品分七组时定的。指数扩到 64 条、并在品类下按地区再分一层后，多出的是
    # 两张逐代码登记表（地区 + 分组，含代理代码）与解释它们为何要逐条登记的注释：
    # 按代码后缀猜地区遇到 ETF 代理就会分错，分错组比不分组更误导。
    # 34,000：股票品类也分了二级组（按行业），多出一张行业登记表与解释它为何按
    # GICS 惯用次序写死（而不是按当天家数排）的注释。
    require(BOARD_DATA_MODULE.stat().st_size <= 34_000,
            "按需加载的品类行情板数据层超过34KB性能预算")
    # 23,000：在原18KB基础上给「逐行迷你走势 + 品类脉冲条」留出的增量。走势本身
    # 不新增任何请求：它复用抽屉那套历史文件与同一份带缓存的读取，一个品类最多
    # 触发一次历史文件读取；拿不到序列的行如实留白，不画推断曲线。
    # 24,000：再加上分组筛选条（aria-pressed 芯片）、列表里的分组小标题，以及现货管道
    # 那条按「日频/月频」分桶取历史的分支。走势说明按各行自己的频率措辞，不把月频说成日频。
    # 30,000：新增五列的渲染，以及「上游没算的区间涨跌由站内历史现场补」那一段。
    # 它复用迷你走势那一次历史读取，一个品类仍然最多触发一次历史文件请求。
    # 31,500：股票品类的分组条末尾多了一个「专属视图入口」（目前是标普500热力图），
    # 连同那张入口登记表——加第二个品类的专属视图时只动表、不改渲染逻辑。
    require(BOARD_VIEW_MODULE.stat().st_size <= 31_500,
            "按需加载的品类行情板视图超过31.5KB性能预算")
    # 行情详情页是独立网址的完整页面：品类行情逐行是真链接（<a href>，可新标签页
    # 打开、可分享），不再是就地弹层。页面只读站内已在日更的公开管道，缺哪一档
    # 区间就说没有；走势图渲染器与详情页各自独立于首屏，不进常规加载预算。
    quote_page = QUOTE_PAGE.read_text(encoding="utf-8")
    quote_module = QUOTE_MODULE.read_text(encoding="utf-8")
    chart_module = CHART_MODULE.read_text(encoding="utf-8")
    # 28,000：详情页新增商品现货这一类标的的读取器与月频历史轴转换。
    # 28,000 是只有日线与月线两套区间时定的。补上 4 小时线这一层——粒度切换、按天数
    # 裁剪的区间集合、以及说明「本站聚合、非交易所原生 K 线、时间为 UTC、来源可能与
    # 本页报价不同」的那段逐条披露——连同解释这些取值由来的注释后需要 35KB。
    # 37,000：公司完整历史改为按名次分片后，多出片号解析与两处取数改写。
    require(QUOTE_MODULE.stat().st_size <= 37_000, "行情详情页脚本超过37KB性能预算")
    # 盘中活更新模块：两页共用一份，只重取那份几KB的盘中快照并在数值真的变了时闪一下。
    live_module = LIVE_MODULE.read_text(encoding="utf-8")
    require(LIVE_MODULE.stat().st_size <= 10_000, "盘中活更新模块超过10KB性能预算")
    require("realtime !== false" in live_module and "MAX_AGE_MINUTES" in live_module
            and "newerThan" in live_module and "非实时" in live_module,
            "盘中活更新必须校验快照自报的非实时标记与新鲜度，并只在报价确实更新时覆盖")
    require('id="board-live"' in page and 'id="board-live"' in MARKETS_PAGE.read_text(encoding="utf-8"),
            "两页都必须给盘中状态留出如实标注的位置")
    require(CHART_MODULE.stat().st_size <= 12_000, "走势图渲染模块超过12KB性能预算")
    require(QUOTE_PAGE.stat().st_size <= 14_000, "行情详情页超过14KB性能预算")
    require('src="finance-terminal-quote.mjs"' in quote_page
            and 'href="../markets/"' in quote_page
            and 'href="index.html#board-section"' in quote_page
            and "terms.html" in quote_page and "privacy.html" in quote_page,
            "行情详情页必须挂载自己的脚本，并同时保留「全球市场行情」与金融终端两个返回入口")
    # 「全球市场行情」是同一块行情板的独立页面：数据层与视图都复用金融终端那一份，
    # 六份数据文件的相对深度也相同，因此不需要第二套取数逻辑，也不会出现两套口径。
    markets_page = MARKETS_PAGE.read_text(encoding="utf-8")
    markets_module = MARKETS_MODULE.read_text(encoding="utf-8")
    require(MARKETS_PAGE.stat().st_size <= 14_000 and MARKETS_MODULE.stat().st_size <= 5_000,
            "「全球市场行情」页面或脚本超过体积预算")
    require('data-quote-base="../finance-terminal/quote.html"' in markets_page
            and 'href="../finance-terminal/terminal-board.css"' in markets_page
            and 'id="board-panel"' in markets_page and 'id="board-search"' in markets_page
            and 'id="board-pulse"' in markets_page and 'id="board-tabs"' in markets_page,
            "「全球市场行情」必须复用共享的行情板样式与同一套挂载点")
    require("finance-terminal-board-data.mjs" in markets_module
            and "finance-terminal-board-view.mjs" in markets_module
            and "buildBoard" in markets_module and "createBoardView" in markets_module
            and "assetRankingCrypto" in markets_module,
            "「全球市场行情」必须直接复用品类行情的数据层与视图，不得另写一套取数")
    require('href="apps/markets/"' in HOME_PAGE.read_text(encoding="utf-8")
            and 'folder: "markets"' in DATA_HUB_APP.read_text(encoding="utf-8")
            and "apps/markets/" in SITEMAP.read_text(encoding="utf-8"),
            "「全球市场行情」必须同时出现在首页、数据中心与站点地图里")
    require("quoteHref" in board_view_module and 'text(line, "a", "board-open")' in board_view_module
            and "openPanel" not in board_view_module,
            "品类行情逐行必须是指向独立行情页的真链接，不再就地弹层")
    require("QUOTE_RANGES" in quote_module and '"25y"' in quote_module and '"all"' in quote_module
            and "history-monthly.json" in quote_module and "curve-monthly.json" in quote_module,
            "行情详情页必须提供 5年/10年/25年/全部 区间并读取月线长历史")
    require("不插值" in quote_module and "cache: \"no-store\"" in quote_module,
            "行情详情页必须写明缺观测不插值，并按不缓存读取站内快照")
    require("renderChart" in chart_module and "quote-cursor" in chart_module
            and "非交易" not in chart_module,
            "走势图渲染器必须提供读数游标")
    # 行情板样式已抽成 terminal-board.css，供金融终端与独立的「全球市场行情」页共用：
    # 同一份数据的同一种呈现不该因为换页面就变成两套样子。
    board_css = BOARD_CSS.read_text(encoding="utf-8")
    require("board-cell-spark" in board_view_module and "sparkDirection" in board_view_module
            and "SPARK_POINTS" in board_view_module and "distribution" in board_view_module
            and 'id="board-pulse"' in page and ".board-spark-line" in board_css,
            "品类行情板必须逐行画站内序列的迷你走势并给出涨跌分布脉冲条")
    require('<link rel="stylesheet" href="terminal-board.css">' in page
            and ".board-tab" in board_css and ".board-pulse-bar" in board_css
            and BOARD_CSS.stat().st_size <= 14_000,
            "行情板样式必须是两页共用的独立样式表，并保持在14KB以内")
    # 品类之下的二级分组：目前只有商品分了组。分组条是筛选芯片（aria-pressed）而不是
    # 第二组标签页——面板仍是同一个品类的 tabpanel；列表里的分组小标题不带 .board-row，
    # 因此不参与逐行的自选、迷你走势与盘中覆盖。两页共用同一个挂载点与同一份样式。
    require('id="board-groups"' in page and 'id="board-groups"' in markets_page,
            "两页都必须给品类下的二级分组条留出挂载点")
    require("COMMODITY_GROUPS" in board_data_module and "groupSummary" in board_data_module
            and "commodityBasis" in board_data_module
            and "board-group-chip" in board_view_module
            and "board-group-head" in board_view_module
            and 'aria-pressed' in board_view_module
            and ".board-group-chip" in board_css and ".board-group-head" in board_css,
            "商品品类必须在品类之下再分组，并且分组条是筛选芯片而不是第二组标签页")
    require("能源" in board_data_module and "贵金属" in board_data_module
            and "工业金属" in board_data_module and "农产品" in board_data_module
            and "软商品" in board_data_module and "畜牧" in board_data_module
            and "商品指数" in board_data_module,
            "商品二级分组必须覆盖能源、贵金属、工业金属、农产品、软商品、畜牧与商品指数")
    require('import("./finance-terminal-board-view.mjs")' in app
            and 'import("./finance-terminal-board-data.mjs")' in app
            and "createBoardView" in board_view_module
            and "buildBoard" in board_data_module
            and "finance-terminal-board-view.mjs" not in page
            and "finance-terminal-board-data.mjs" not in page,
            "品类行情板的数据层与视图必须保持按需导入且不得在首屏预加载")
    require(RISK_VIEW_MODULE.stat().st_size <= 6_600,
            "按需加载的市场状态视图超过6.6KB性能预算")
    # 地缘风险定价：四条轴各自读站内已在日更的公开管道，逐轴给出原值、映射口径、
    # 来源与数据日；缺任何一条即不给等级。它与同分区那三张「不合成为总分」的官方
    # 信号卡分开渲染，也不参与它们的状态计数。
    require(GEO_RISK_MODULE.stat().st_size <= 16_500,
            "按需加载的地缘风险定价模型超过16.5KB性能预算")
    require("buildGeoRisk" in risk_view_module and "renderGeoRisk" in risk_view_module
            and "GEO_AXES" in geo_risk_module and "percentileScore" in geo_risk_module
            and "不统计" in geo_risk_module and 'id="geo-risk"' in page
            and "finance-terminal-geo-risk.mjs" not in page,
            "地缘风险定价必须随市场状态视图按需加载，并写明它读的是定价而非事件本身")
    require('import("./finance-terminal-risk-view.mjs")' in app
            and "createRiskView" in risk_view_module
            and "finance-terminal-risk-view.mjs" not in page,
            "市场状态视图必须保持按需导入且不得在首屏预加载")
    require(RESEARCH_VIEW_MODULE.stat().st_size <= 14_000,
            "按需加载的市场研究视图超过14KB性能预算")
    require('import("./finance-terminal-research-view.mjs")' in app
            and "createResearchView" in research_view_module
            and "finance-terminal-research-view.mjs" not in page,
            "市场研究视图必须保持按需导入且不得在首屏预加载")
    require(INFORMATION_VIEW_MODULE.stat().st_size <= 10_000,
            "按需加载的事件资讯视图超过10KB性能预算")
    require('import("./finance-terminal-information-view.mjs")' in app
            and "createInformationView" in information_view_module
            and "finance-terminal-information-view.mjs" not in page,
            "事件资讯视图必须保持按需导入且不得在首屏预加载")
    require(OPERATIONS_VIEW_MODULE.stat().st_size <= 9_000,
            "按需加载的稳定V1运行证据视图超过9KB性能预算")
    require('import("./finance-terminal-operations-view.mjs")' in app
            and "createOperationsView" in operations_view_module
            and "finance-terminal-operations-view.mjs" not in page,
            "稳定V1运行证据视图必须保持按需导入且不得在首屏预加载")
    require('<link rel="stylesheet" href="terminal-reference-home-v2.css">' in page
            and '<link rel="stylesheet" href="terminal-reference-home-v3.css">' in page
            and '<link rel="stylesheet" href="terminal-reference-home-v4.css">' in page
            and '<link rel="stylesheet" href="terminal-reference-home-v5.css">' in page
            and 'body[data-terminal-view="overview"] .market-globe-shell' in reference_home_v4_css
            and 'html[data-finance-terminal-page]' in reference_home_v5_css
            and 'overflow-x: clip' in reference_home_v5_css
            and '@media (max-width: 620px)' in reference_home_v3_css
            and 'aria-hidden' in page,
            "参考首页精修层缺少样式引用、单屏地球定位或独立窄屏规则")
    require('<link rel="stylesheet" href="terminal-vision.css">' in page
            and '<link rel="stylesheet" href="terminal-command-center.css">' in page
            and '<link rel="stylesheet" href="terminal-visual-fidelity.css">' in page
            and '<link rel="stylesheet" href="terminal-reference-fidelity.css">' in page
            and '<link rel="stylesheet" href="terminal-aurora-home.css">' in page
            and 'src="finance-terminal-command-center.mjs"' in page
            and 'import("./finance-terminal-visuals.mjs")' in app
            and "createTerminalVisuals" in terminal_visuals,
            "科幻终端视觉层缺少本地样式或数据模块")
    require('from "./finance-terminal-aurora-home.mjs"' in command_center_module
            and "initAuroraHome" in command_center_module
            and "MutationObserver" in aurora_home_module
            and "innerHTML" not in aurora_home_module
            and 'id="aurora-gateways"' in page
            and 'class="terminal-mode-switch"' in page
            and ".aurora-gateway-grid" in aurora_home_css
            and "@media (max-width: 620px)" in aurora_home_css,
            "极光首页缺少模式切换、三工作流入口、已校验读数同步或独立移动端布局")
    require('import("./finance-terminal-gateway-preview.mjs")' in app
            and "pickIndexRows" in gateway_preview_module
            and "pickMoverRows" in gateway_preview_module
            and "pickMacroSnapshot" in gateway_preview_module
            and "pickCalendarRows" in gateway_preview_module
            and "curveGeometry" in gateway_preview_module
            and "describeRows" in gateway_preview_module
            and "!asset.proxy" in gateway_preview_module
            and 'asset.dataMeta.mode === "market"' in gateway_preview_module
            and 'asset.dataMeta.status === "ok"' in gateway_preview_module
            and "asset.stale !== true" in gateway_preview_module
            and "innerHTML" not in gateway_preview_module
            and 'id="gateway-index-table"' in page
            and 'id="gateway-mover-table"' in page
            and 'id="gateway-yield-chart"' in page
            and 'id="gateway-event-list"' in page
            and 'id="gateway-impact-table"' in page
            and 'aria-busy="true"' in page
            and "finance-terminal-gateway-preview.mjs" not in page,
            "入口卡预览必须镜像已校验的指数、异动、宏观与日历快照，排除代理和过期条目")
    require('from "./finance-terminal-orbit-links.mjs"' in command_center_module
            and "initOrbitLinks" in orbit_links_module
            and "anchorPoint" in orbit_links_module
            and "arcPath" in orbit_links_module
            and "ResizeObserver" in orbit_links_module
            and "innerHTML" not in orbit_links_module
            and 'class="orbit-links"' in page
            and 'id="orbit-link-a"' in page
            and ".orbit-link" in reference_home_v3_css,
            "市场连线层必须按城市标记实测坐标绘制、随尺寸重算且不使用innerHTML")
    require('from "./finance-terminal-globe.mjs"' in command_center_module
            and "initMarketGlobe" in globe_module
            and "textureCoordinate" in globe_module
            and "earth-night.jpg" in globe_module
            and "renderOrthographic" in globe_texture_module
            and "getImageData" in globe_texture_module
            and "CACHE = new WeakMap" in globe_texture_module
            and "prefers-reduced-motion" in globe_module
            and "visibilitychange" in globe_module
            and "innerHTML" not in globe_module
            and 'id="market-globe-canvas"' in page
            and ".market-globe-shell" in reference_fidelity_css,
            "高保真地球必须使用本地纹理、真实自转、节能与减少动画降级")
    compact_reference_home = re.sub(r"\s+", "", reference_home_v4_css)
    require("grid-template-rows:20.93vw6.7vw22.36vw" in compact_reference_home
            and "grid-template-columns:1.12fr1fr1.11fr" in compact_reference_home
            and "width:76.3%" in compact_reference_home
            and "margin-left:6.8%" in compact_reference_home
            and "top:50%" in compact_reference_home
            and "left:50%" in compact_reference_home
            and "width:52%" in compact_reference_home
            and "grid-template-columns:minmax(0,1fr)16.2vw" in compact_reference_home,
            "1672×941参考锁定层缺少目标纵向网格、资产弧带或三工作区比例")
    require('body[data-terminal-view="overview"] #main-content' in command_center_css
            and 'grid-template-columns: repeat(16, minmax(0, 1fr))' in command_center_css
            and 'body[data-terminal-view="overview"] #information-section' in command_center_css
            and 'body[data-terminal-view="overview"] .global-risk-map' in command_center_css
            and 'body[data-terminal-view="overview"] .pipeline-command' in command_center_css
            and "VIEW_BY_ID" in command_center_module
            and "aria-current" in command_center_module
            and "innerHTML" not in command_center_module,
            "单屏指挥中心缺少桌面网格、地图、管线或可访问导航契约")
    require("innerHTML" not in terminal_visuals
            and "REGION_SPECS" in terminal_visuals
            and "Yahoo Finance" in terminal_visuals
            and "renderGlobalRiskHeatmap" in terminal_visuals
            and "renderPipelineOverview" in terminal_visuals,
            "终端视觉数据模块缺少安全文本渲染、区域代理或资格进度逻辑")
    require("innerHTML" not in risk_radar_module
            and 'from "./finance-terminal-risk-radar.mjs"' in terminal_visuals
            and "deriveRiskRadar" in risk_radar_module
            and "renderRiskRadar" in risk_radar_module,
            "高保真风险雷达必须使用独立受预算约束的真实信号视觉层")
    require("innerHTML" not in health_adapters_module
            and 'import("./finance-terminal-health-adapters.mjs")' in app
            and "finance-terminal-health-adapters.mjs" not in page
            and "createSupportingHealthAdapter" in health_adapters_module
            and "installSupportingHealthAdapter" in app
            and "function adaptSupportingSourceHealth" not in app
            and "function adaptSupportingSourceHealth" in health_adapters_module
            and "辅助来源健康适配层尚未加载" in app,
            "辅助来源健康适配层必须按需加载、不进首屏，且未安装时明确报未就绪而非臆造状态")
    require("innerHTML" not in curve_view_module
            and 'import("./finance-terminal-curve-view.mjs")' in app
            and "finance-terminal-curve-view.mjs" not in page
            and "openCurve" in curve_view_module
            and "curveSegments" in curve_view_module
            and 'from "./finance-terminal-detail-view.mjs"' in curve_view_module
            and "不插值、不用相邻期限顶替" in curve_view_module
            and "在此之前不显示推断值" in curve_view_module
            and "不构成对后市的预测" in curve_view_module
            and 'id="yield-curve-entry"' in page
            and 'id="yield-curve-entry-risk"' in page
            and "aria-modal" not in curve_view_module,
            "收益率曲线抽屉必须按需导入、不进首屏、缺档断线不插值，且不得另建对话框语义")
    risk_radar_module = RISK_RADAR_MODULE.read_text(encoding="utf-8")
    require("innerHTML" not in radar_view_module
            and 'import("./finance-terminal-radar-view.mjs")' in app
            and "finance-terminal-radar-view.mjs" not in page
            and "openRadar" in radar_view_module
            and "pairAxes" in radar_view_module
            and 'from "./finance-terminal-detail-view.mjs"' in radar_view_module
            and 'from "./finance-terminal-risk-radar.mjs"' in radar_view_module
            and "缺任一信号时雷达整体保持空态" in radar_view_module
            and "不是对后市的预测" in radar_view_module
            and 'id="risk-radar-detail"' in page,
            "雷达构成抽屉必须按需导入、不进首屏，且与雷达共用同一份信号键")
    require("RADAR_SIGNAL_KEYS" in risk_radar_module
            and "regimeSignals" in risk_radar_module
            and "extractRegimeSignals" in app
            and "regimeSignals: extractRegimeSignals(macroData)" in app
            and "实际利率" in page and "期限溢价" in page and "信用利差" in page
            and "利率风险" not in page and "通胀风险" not in page
            and "波动率来自VIX" in page,
            "风险雷达六轴必须各读一个真实制度信号，不得再用单一分数加权重组，"
            "且轴名不得沿用没有对应测量的旧标签")
    require('risk: [document.getElementById("risk-section")' in app
            and 'document.querySelector(".risk-radar-panel")' in app
            and "observeRadarPanel" not in app,
            "首屏之外但先于 #risk-section 出现的风险雷达必须登记为 risk 分区的触发元素，"
            "否则窄屏下它会一直停在 LOADING 直到访客滚到数千像素之下的分区；"
            "触发逻辑只能有一份，不得在 app.js 里另起一个观察器")
    require("dwellMs" in loader
            and "clearTimeout(dwellTimers" in loader
            and "掠过" in loader,
            "延迟分区必须区分「滚过」与「看过」：分区导航是一次上万像素的平滑滚动，"
            "掠过即加载会把整页请求一并拉起，延迟加载形同虚设")
    correlation_view_module = CORRELATION_VIEW_MODULE.read_text(encoding="utf-8")
    require("innerHTML" not in correlation_view_module
            and 'import("./finance-terminal-correlation-view.mjs")' in app
            and "finance-terminal-correlation-view.mjs" not in page
            and "openCorrelation" in correlation_view_module
            and "buildMatrix" in correlation_view_module
            and 'from "./finance-terminal-detail-view.mjs"' in correlation_view_module
            and "aria-modal" not in correlation_view_module
            and 'id="correlation-entry"' in page,
            "相关性矩阵抽屉必须按需导入、不进首屏，且不得另建对话框语义")
    # 三条口径必须留在代码里：用收益率不用价位、日历错位整列剔除、重叠不足不给数。
    require("logReturns" in correlation_view_module
            and "价位序列本身带趋势" in correlation_view_module
            and "sessionAligned" in correlation_view_module
            and "交易日历对不齐的标的整个不进矩阵" in correlation_view_module
            and "MIN_OVERLAP" in correlation_view_module
            and "不是对后市的预测" in correlation_view_module,
            "相关性矩阵必须用日对数收益率、剔除日历错位标的、重叠不足时留空，"
            "并声明其为历史统计而非预测")
    require("../asset-tracker/history.json" in correlation_view_module,
            "相关性矩阵必须读取站内已发布的滚动历史，不得另立数据源")
    require("openPanel" in detail_view_module and "isPanelOpen" in detail_view_module
            and "aria-modal" in detail_view_module
            and "aria-modal" not in radar_view_module,
            "抽屉外壳必须只有一份实现，雷达抽屉不得另建一套对话框语义")
    require("innerHTML" not in detail_view_module
            and 'import("./finance-terminal-detail-view.mjs")' in app
            and "finance-terminal-detail-view.mjs" not in page
            and "openAsset" in detail_view_module
            and "seriesPath" in detail_view_module
            and "matchedKeyword" in detail_view_module
            and "按其使用条款不得抓取、保存或再分发组件行情" in detail_view_module
            and "在此之前不显示推断值" in detail_view_module
            and "不代表其与本标的存在因果关系" in detail_view_module
            and "命中不等于与本标的相关" in detail_view_module
            and 'aria-modal' in detail_view_module
            and 'class="detail-open"' not in page
            and ".detail-open" in vision_css
            and ".detail-open" not in detail_view_module,
            "资产详情抽屉必须按需导入、不进首屏，无序列时如实说明而非展示推断值，"
            "且首屏可见的触发按钮样式不得随抽屉延后加载")
    require("innerHTML" not in watchlist_module
            and 'import("./finance-terminal-watchlist.mjs")' in app
            and "finance-terminal-watchlist.mjs" not in page
            and "mountWatchlist" in watchlist_module
            and "sanitizeSymbol" in watchlist_module
            and "safeStorage" in watchlist_module
            and "仅保存在本机浏览器，不会上传" in watchlist_module
            and 'id="watch-filter"' in page
            and ".watch-toggle" in vision_css
            and 'aria-pressed' in watchlist_module,
            "自选清单必须按需导入、清洗代码、容忍存储不可用并声明只存本机")
    require("innerHTML" not in sessions_module
            and 'from "./finance-terminal-sessions.mjs"' in terminal_visuals
            and "sessionState" in sessions_module
            and "localClock" in sessions_module
            and "未计入交易所假日" in page
            and ".orbit-session" in vision_css
            and "session-open" in vision_css,
            "交易时段状态必须为纯日历计算、披露未计假日并提供非颜色区分")
    require("innerHTML" not in worldmap_module
            and 'from "./finance-terminal-worldmap.mjs"' in terminal_visuals
            and "renderWorldHeatmap" in worldmap_module
            and "pressureTone" in worldmap_module
            and "earth-water.jpg" in worldmap_module
            and 'id="risk-map-canvas"' in page
            and ".risk-map-canvas-ready" in reference_fidelity_css,
            "点阵世界地图必须使用同源遮罩、既有回报着色并保留SVG降级")
    require('@media (max-width: 1040px)' in vision_css
            and '@media (max-width: 780px)' in vision_css
            and '@media (max-width: 620px)' in vision_css
            and "prefers-reduced-motion" in vision_css
            and "forced-colors" in vision_css,
            "科幻视觉层缺少桌面、平板、手机、减少动画或强制颜色规则")
    require(".section-nav a { min-width: 44px; min-height: 44px; justify-content: center; }" in vision_css
            and ".global-risk-map-layout > *" in vision_css
            and ".pipeline-command > *" in vision_css
            and vision_css.count("grid-template-columns: minmax(0, 1fr);") >= 2
            and ".hero-telemetry .meta-item" in vision_css,
            "科幻视觉层缺少360px触控目标或复杂网格安全收缩边界")
    terms_page = TERMS_PAGE.read_text(encoding="utf-8")
    privacy_page = PRIVACY_PAGE.read_text(encoding="utf-8")
    legal_css = LEGAL_CSS.read_text(encoding="utf-8")
    home = HOME.read_text(encoding="utf-8")
    require("4项站内真实数据与2项TradingView免费ETF代理" in page,
            "页面首屏缺少免费数据覆盖提示")
    require("FRED API使用条款" in page
            and "未获圣路易斯联储、EIA或TradingView认可或认证" in page,
            "页面缺少来源说明与条款入口")
    require("DTWEXBGS" in page and "不是ICE DXY" in page and "自动更新失败" in page, "页面未准确解释广义美元指数与回退规则")
    require("RWTC" in page and "不是 <code>CL=F</code>" in page and "EIA API文档" in page, "页面未准确解释WTI现货来源与口径")
    require("官方静态快照" not in page, "页面不得继续把DTWEXBGS描述为静态快照")
    require("0 DEMO" in page, "页面未明确披露零演示行情")
    require("Powered by CoinGecko" in page and "Yahoo BTC-USD" in page,
            "页面未披露BTC/USD主要来源、署名或降级口径")
    require('if (source.name === "Powered by CoinGecko") link.classList.add("coingecko-attribution")' in app
            and ".coingecko-attribution" in page and "font-size: 11px" in page,
            "CoinGecko署名必须使用可机器识别且不小于10px的醒目样式")
    require('href="terms.html"' in page and 'href="privacy.html"' in page
            and 'class="legal-links"' in page,
            "金融终端页脚缺少易访问的使用条款或隐私政策")
    require("CoinGecko API及相关数据、品牌和知识产权属于Gecko Labs" in terms_page
            and "出售、出租、转授权、再分发" in terms_page
            and "CoinGecko不负责本产品" in terms_page
            and "加密资产价格高度波动" in terms_page
            and "https://www.coingecko.com/en/api_terms" in terms_page,
            "用户条款缺少CoinGecko所有权、保护性限制、责任排除或加密资产风险披露")
    require("无需注册的静态Public Beta" in privacy_page
            and "TradingView官方组件" in privacy_page
            and "终端应用代码当前不使用本地存储" in privacy_page
            and "https://www.coingecko.com/en/privacy" in privacy_page,
            "隐私政策缺少当前收集范围、第三方组件、本地存储或CoinGecko隐私入口")
    require("font-size: 16px" in legal_css and "min-width: 320px" in legal_css
            and "<script" not in terms_page and "<script" not in privacy_page,
            "法律页面必须保持移动端可读且不得新增追踪脚本")
    for legal_page in (terms_page, privacy_page):
        require(all('rel="noopener noreferrer"' in tag
                    for tag in re.findall(r'<a[^>]+target="_blank"[^>]*>', legal_page)),
                "法律页面外链必须隔离新窗口上下文")
    require("DIA与GLD分别仅作为DJIA与LBMA Gold Price PM的免费ETF代理" in page
            and "不是同一原标的" in page
            and "不抓取、不导出、不保存" in page,
            "页面未披露免费ETF代理与原标的边界")
    require('id="data-banner"' in page and 'id="market-grid"' in page, "页面缺少数据状态或卡片容器")
    require('id="license-notice" role="region"' in page
            and 'aria-labelledby="license-title"' in page
            and "免费代理行情策略" in page,
            "页面缺少免费代理行情策略区域")
    require('id="risk-grid"' in page and 'id="risk-summary"' in page and "市场状态" in page, "页面缺少市场状态模块")
    require('id="research-grid"' in page and 'id="research-summary"' in page and "市场强弱与领袖" in page, "页面缺少市场研究模块")
    require('id="information-grid"' in page and 'id="information-summary"' in page and "市场洞察与动态" in page
            and 'id="market-insight-title"' in page and 'id="market-insight-copy"' in page
            and "RULE-BASED · VERIFIED SIGNALS" in page,
            "页面缺少事件资讯模块")
    require('id="operations-grid"' in page and 'id="operations-summary"' in page and "稳定V1运行证据" in page,
            "页面缺少四管道稳定V1运行证据模块")
    require('id="market-tape"' in page and 'class="market-orbit-svg"' in page
            and page.count('data-market-time=') == 4
            and "非资金流向图" in page,
            "页面缺少核心资产行情带、全息地球时区或非资金流向说明")
    require('id="global-risk-map"' in page and page.count('data-risk-region=') == 8
            and "区域代表性股票指数的当日价格跌幅作为市场压力代理" in page
            and "不是国家风险评分" in page,
            "全球风险热力图缺少区域路径、压力代理口径或风险边界说明")
    require('id="stable-v1-ring" role="progressbar"' in page
            and 'aria-valuemax="7"' in page and 'id="pipeline-nodes"' in page,
            "页面缺少稳定V1 7周期HUD或四管线节点")
    require("健康快照与连续周期证据是两套独立信号" in page
            and "Beta需四条管道各满3个周期" in page,
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
    require("全球资产市值" in page
            and "已披露市值代理" in page and "不会用文件更新时间代替" in page
            and "未登记`PARTIAL`路径仍会明确降级" in page,
            "页面未说明全球资产市值逐条来源限制")
    require("全球公司领袖" in page and "未上市估值不参与涨跌排序" in page, "页面未说明公司领袖的上市范围")
    require("动态行情和慢频估值分层" in page and "不会单独被当作更新失败" in page,
            "页面未披露公司数据逐项新鲜度限制")
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
    require("official-trend" in page and "buildOfficialObservationTrend" in app
            and "normalizeOfficialObservations" in app and "RECENT OBSERVATIONS" in app
            and "最多8项" in page and "不以演示走势填充" in page,
            "页面未校验或展示三项官方行情最近观测趋势")
    require('src="app.js"' in page, "页面未加载本地app.js")
    require('rel="modulepreload" href="finance-terminal-loader.mjs"' in page
            and 'import("./finance-terminal-loader.mjs")' in app,
            "页面未预加载或动态导入原生分区加载模块")
    require('critical:Object.freeze(["macro","macroHealth","assetRanking","assetRankingHealth","marketLicense"])'
            in compact_loader and "criticalSourceCount:RESOURCE_GROUPS.critical.length" in compact_loader,
            "首屏资源契约必须固定为宏观、资产榜及许可5份资源")
    require("requests=newMap()" in compact_loader and "if(!requests.has(key))" in compact_loader
            and "createDeferredSectionScheduler" in loader and "IntersectionObserver" in loader
            and "navigationLinks" in loader,
            "分区加载器缺少共享请求缓存、视口观察或导航触发契约")
    require('loader.loadGroup("critical")' in loader and "data-critical-data-state" in loader
            and "data-deferred-data-state" in loader and "criticalSourceRequestCount" in loader
            and "criticalPaintBarrier" in loader and "requestedKeysAtSchedulerStart" in loader
            and "networkRequestCount" in loader and "duplicateNetworkRequestCount" in loader
            and "sectionTransitions" in loader and "stagedDataLoading" in regression_module,
            "页面未区分首屏与延迟分区加载状态")
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
    require('macro:"../macro-radar/data.json"' in compact_loader, "分区加载器未读取现有宏观雷达数据")
    require('macroHealth:"../macro-radar/health.json"' in compact_loader,
            "分区加载器未读取宏观雷达逐源健康快照")
    require("businessDaysSince" in app and "DGS10_MAX_BUSINESS_DAYS" in app and '"stale"' in app, "app.js未实现DGS10过期判断")
    require("DTWEXBGS_MAX_BUSINESS_DAYS" in app and "findDtwexbgsReference" in app, "app.js未读取DTWEXBGS自动更新记录")
    require("var DTWEXBGS_MAX_BUSINESS_DAYS = 8;" in app
            and "H.10按周成批发布" in app
            and "日度观测 · 每周成批发布" in app,
            "DTWEXBGS 新鲜度阈值必须匹配 H.10 每周成批发布的真实节奏："
            "日频假设下的 3 个工作日会让它每周有一半时间误报过期")
    require("record.price / record.previousPrice" in app and "refreshFailed" in app, "DTWEXBGS涨跌幅或失败回退不可复现")
    require("RWTC_MAX_BUSINESS_DAYS" in app and "findRwtcReference" in app and "adaptRwtc" in app, "app.js未读取RWTC自动更新记录")
    require("MACRO_REGIME_MAX_BUSINESS_DAYS" in app and "adaptMacroRegime" in app and "buildRiskCards" in app, "app.js未接入宏观状态适配层")
    require('fearGreed:"../fear-greed/data.json"' in compact_loader
            and "FEAR_GREED_MAX_BUSINESS_DAYS" in app and "adaptFearGreed" in app,
            "金融终端未接入CNN恐慌与贪婪数据")
    require('ofr:"../ofr-monitor/data.json"' in compact_loader
            and "OFR_FSI_MAX_BUSINESS_DAYS" in app and "adaptOfrFsi" in app,
            "金融终端未接入OFR金融压力数据")
    require('assetTracker:"../asset-tracker/data.json"' in compact_loader
            and "ASSET_TRACKER_MAX_AGE_HOURS" in app, "金融终端未读取现有跨资产数据")
    require('assetTrackerHealth:"../asset-tracker/health.json"' in compact_loader
            and 'assetRankingHealth:"../asset-ranking/health.json"' in compact_loader
            and 'companiesHealth:"../companies/health.json"' in compact_loader,
            "分区加载器未读取三条聚合管道健康文件")
    require("adaptSourceHealth" in app and "safeSourceHealth" in app and "appendSourceHealth" in app,
            "app.js未校验或展示来源健康状态")
    require("adaptMacroSourceHealth" in operations_data_module
            and "buildOperationsCards" in operations_data_module
            and "renderOperationsCards" in app and "makeOperationCard" in operations_view_module,
            "运行证据数据层未校验或渲染四管道Beta运行状态")
    require('readiness:"readiness.json"' in compact_loader
            and "adaptReadinessSnapshot" in operations_data_module
            and "READINESS_MAX_AGE_HOURS" in operations_data_module
            and "operation-readiness" in operations_view_module
            and "STABLE V1 EVIDENCE" in operations_view_module,
            "金融终端未读取、校验或渲染稳定V1连续周期证据")
    # 运行证据的适配只有该分区用得上，不该进首屏。
    require('import("./finance-terminal-operations-data.mjs")' in app
            and "createOperationsData" in operations_data_module
            and "adaptMacroSourceHealth" not in app
            and "adaptReadinessSnapshot" not in app,
            "运行证据数据层必须按需加载，且其适配函数不得留在首屏脚本里")
    require(OPERATIONS_DATA_MODULE.stat().st_size <= 23_000,
            "金融终端运行证据数据层超过23KB性能预算")
    require('marketLicense:"market-source-readiness.json"' in compact_loader
            and "adaptMarketLicenseReadiness" in app
            and "renderMarketLicenseNotice" in app and "FREE DATA" in app,
            "金融终端未读取、校验或渲染免费代理行情状态")
    require("稳定V1运行证据" in page and "同一日更周期重跑不会重复累计" in page,
            "页面未区分健康快照与稳定V1周期门禁")
    require("可用覆盖" in operations_view_module and "本轮新鲜" in operations_view_module
            and "已验证覆盖" in operations_view_module and "失败回退" in operations_view_module,
            "运行状态卡片缺少覆盖率、时效或回退说明")
    require("pipeline-health" in page and "本轮行情" in app and "连续失败" in operations_view_module
            and "最近尝试" in operations_view_module and "最后成功" in operations_view_module
            and "健康报告已超过" in app,
            "页面缺少管道状态、本轮覆盖、尝试时间、过期提示或最后成功信息")
    require("adaptCrossAsset" in app and "rankCrossAssetPeriod" in app and "buildResearchCards" in app, "app.js未实现跨资产适配和排行")
    require("asset.stale" in app and "asset.suspect" in app and "paused" in app, "跨资产排行未排除异常行或暂停过期今日排行")
    require("normalizeDataMeta" in app and "summarizeRowQuality" in app and "appendQualitySummary" in app,
            "跨资产卡片未读取或展示逐条数据状态")
    require("normalizeAssetProxy" in app and "proxy-badge" in page and "PROXY" in app,
            "跨资产页面未校验或显式展示代理标的")
    require("quality-strip" in page and "quality.counts.fallback" in app and "历史回退" in app,
            "页面缺少行情、回退、估算与待确认覆盖信息")
    require('assetRanking:"../asset-ranking/data.json"' in compact_loader
            and "ASSET_RANKING_MAX_AGE_HOURS" in app, "金融终端未读取现有全球资产市值数据")
    require("adaptAssetRanking" in app and "formatMarketCapBillions" in terminal_views
            and "asset.dataLabel" in terminal_views and "summarizeRowQuality(rowMetas, data.dataQuality)" in app,
            "app.js未实现全球资产市值逐条来源适配或口径标签")
    require('companies:"../companies/data.json"' in compact_loader
            and "COMPANIES_MAX_AGE_HOURS" in app, "金融终端未读取现有公司榜数据")
    require("adaptCompanies" in app and "company.private" in app and "freshnessKnown" in app, "app.js未实现上市公司筛选或逐项新鲜度状态")
    require("gainer" in app and "laggard" in app and "listedMarketCap" in app, "app.js未生成公司领涨、领跌和上市市值")
    require("moverCoverage" in app and "暂停当日领涨与领跌" in app and "company.dataLabel" in terminal_views,
            "公司榜未按逐条状态暂停或恢复每日涨跌排行")
    require('calendar:"../econ-calendar/data.json"' in compact_loader
            and "ECON_CALENDAR_MAX_AGE_HOURS" in information_data_module,
            "金融终端未读取现有经济日历数据")
    require("adaptEconomicCalendar" in information_data_module
            and "buildInformationCards" in information_data_module
            and "normalizeCalendarEvent" in information_data_module,
            "事件资讯数据层未实现经济日历适配、校验或独立状态")
    require('news:"../whats-latest/data.json"' in compact_loader
            and "FINANCE_NEWS_MAX_AGE_HOURS" in information_data_module
            and "FINANCE_NEWS_ITEM_MAX_AGE_HOURS" in information_data_module,
            "事件资讯数据层未读取现有财经新闻或缺少新鲜度规则")
    require("adaptFinanceNews" in information_data_module
            and "isSafeGoogleNewsUrl" in information_data_module
            and "makeFinanceNewsCard" in terminal_views,
            "事件资讯数据层未实现财经新闻适配、安全链接或渲染")
    # 事件资讯的适配只有该分区用得上，不该进首屏。数据层必须按需导入、不得回流 app.js。
    require('import("./finance-terminal-information-data.mjs")' in app
            and "createInformationData" in information_data_module
            and "adaptEconomicCalendar" not in app
            and "adaptFinanceNews" not in app,
            "事件资讯数据层必须按需加载，且其适配函数不得留在首屏脚本里")
    require(INFORMATION_DATA_MODULE.stat().st_size <= 15_000,
            "金融终端事件资讯数据层超过15KB性能预算")
    require('setAttribute("role", "listitem")' in terminal_views, "动态卡片缺少列表项语义")
    require("card.tabIndex = 0" not in terminal_views and "article.tabIndex = 0" not in terminal_views,
            "非交互卡片不得进入键盘Tab顺序")
    require("announceExperience" in app and "pageAnnouncer.textContent" in app,
            "页面未集中播报异步加载结果")
    require('setAttribute("role", "tablist")' in terminal_views and 'setAttribute("role", "tab")' in terminal_views
            and 'setAttribute("role", "tabpanel")' in terminal_views, "跨资产周期未使用标准标签页语义")
    require("periodTabTargetIndex" in app and 'event.key' in terminal_views and 'nextButton.focus()' in terminal_views,
            "跨资产周期未支持方向键、Home和End键盘导航")
    require('setAttribute("aria-selected"' in terminal_views and 'setAttribute("aria-controls"' in terminal_views,
            "跨资产周期标签页状态或面板关联缺失")
    require('setAttribute("aria-pressed"' not in terminal_views, "标签页不得混用aria-pressed按钮模式")
    require('import("./finance-terminal-regression.mjs")' in app
            and "runBrowserRegressionProbe" in regression_module
            and "finance-terminal-regression-result" in regression_module
            and "stagedDataLoading" in regression_module
            and "supportingHealthResources" in regression_module and "supportingHealthPanelCount" in regression_module
            and "officialHealthResources" in regression_module and "officialHealthPanelCount" in regression_module
            and "officialObservationTrends" in regression_module and "officialObservationTrendCount" in regression_module
            and "overviewCardLegibility" in regression_module
            and "scrollHeight <= n.clientHeight" in regression_module,
            "页面缺少浏览器、分区加载、官方逐源或辅助来源资源回归探针")
    require("marketLicenseReadiness" in regression_module and "providerWidgetCount" in regression_module,
            "浏览器回归探针未覆盖免费代理状态或四项提供方组件")
    require("orbitalTerminalVisuals" in regression_module
            and "riskHudVisuals" in regression_module
            and "globalRiskHeatmap" in regression_module
            and "stableV1Hud" in regression_module
            and "minimumReadinessCycle" in regression_module,
            "浏览器回归探针未覆盖行情带、时区地球、风险HUD、区域热力图或动态V1资格")
    require("providerAttribution" in regression_module and "poweredByCoinGeckoLinks" in regression_module,
            "浏览器回归探针未核对CoinGecko署名文本、样式或最小字号")
    require("waitForProviderWidgetRegistration" in app and "inspectProviderWidgetHost" in app
            and "verifyProviderWidgetHosts" in app and "monitorProviderWidgets" in app
            and "providerWidgetRuntime" in regression_module and "providerWidgetRuntimeStates" in regression_module
            and "providerWidgetRuntimeEvidence" in regression_module,
            "页面未验证或回归免费组件的注册与宿主挂载状态")
    require('data-provider-state", "loading"' in app
            and "组件已注册 · 正在验证宿主" in app
            and "组件宿主已挂载 · 报价状态见组件" in app
            and "组件未加载 · 使用来源链接" in app,
            "免费组件缺少加载、注册、宿主挂载或官方链接回退状态")
    require("providerWidgetUnavailableCopy" in app
            and "组件加载超时 · 使用来源链接" in app
            and "组件注册失败 · 使用来源链接" in app
            and "组件验证不可用 · 使用来源链接" in app
            and "组件挂载异常 · 使用来源链接" in app,
            "免费代理卡未按注册超时、注册失败、验证不可用和宿主异常显示分层回退原因")
    require('params.get("runtimeEvidence") === "1"' in app
            and "useProductionEvidenceWindow" in app,
            "机器浏览器证据没有使用与生产页面一致的完整组件等待窗口")
    require('.provider-widget-shell[data-provider-state="mounted"]' in page
            and "visibility: hidden" in page and ".provider-runtime-status" in page,
            "免费组件宿主未挂载时没有隐藏空组件或保留可见状态")
    require("noHorizontalOverflow" in regression_module and "responsiveColumns" in regression_module
            and "targetSizes" in regression_module and "keyboardTabs" in regression_module,
            "浏览器回归探针未覆盖溢出、布局、触控与键盘交互")
    require('class="section-nav"' in page and page.count('class="section-nav"') == 1
            and "sectionNavigation" in regression_module
            and 'document.querySelector("details.method > summary")' in regression_module,
            "页面缺少分区导航、锚点契约或可折叠数据说明")
    require("STALE DATA" not in app and "compactStatus.join(\"／\")" in app,
            "顶部状态必须显示逐类数量，不能以全局STALE DATA误导用户")
    require("Prototype" not in page and "Ooglex Finance Terminal · Public Beta" in page,
            "金融终端页脚版本名称必须统一为Public Beta")
    require("Dense metadata remains readable" in page and "footer { font-size: 11px; }" in page,
            "金融终端辅助文字缺少11px正常缩放可读性下限")
    require(".section-nav a { min-width: 44px; min-height: 44px;" in page
            and ".legal-links a { min-width: 44px; min-height: 44px;" in page,
            "移动端分区导航与法律链接必须同时满足44px宽高触控下限")
    require('document.querySelectorAll(".operation-card").length === 4' in regression_module
            and "renderedGridColumns(operationsGrid)" in regression_module,
            "浏览器回归探针未覆盖四张运行状态卡片或其响应式列数")
    require("undersizedTargets" in regression_module, "浏览器回归结果必须列出尺寸不足的触控目标")
    require(".operation-action" in regression_module, "浏览器回归探针未检查Beta运行与反馈触控目标")
    require("data.markets" not in app and ".markets" not in app, "终端财经新闻不得读取同文件的Yahoo行情快照")
    require('card.status === "partial"' in app and 'text: "PARTIAL"' in app, "市场状态卡片未区分部分数据")
    require("buildPageDataWithMacroError" in app and "unavailableDtwexbgs" in app and "unavailableRwtc" in app and 'status: "error"' in app, "app.js未覆盖官方数据文件失败状态")
    require("changeUnit" in app and '"bp"' in app, "app.js未按bp显示收益率变化")
    require("apps/finance-terminal/" in home, "首页缺少金融终端入口")
    require("金融终端 Public Beta" in home
            and "4项站内真实数据、2项免费ETF代理、0项演示" in home
            and "Finance Terminal Public Beta" in home
            and "4 first-party data cards, 2 free ETF proxies, 0 demo" in home,
            "首页金融终端入口未同步Public Beta真实数据与免费代理口径")
    require("金融终端（演示）" not in home
            and "4项演示数据" not in home
            and "Finance Terminal (Demo)" not in home
            and "4 real, 4 demo" not in home,
            "首页仍残留金融终端演示版文案")

    external_scripts = re.findall(r'<script[^>]+src=["\'](https?://[^"\']+)', page, flags=re.I)
    require(external_scripts == ["https://widgets.tradingview-widget.com/w/en/tv-mini-chart.js"],
            "金融终端只能引入已登记的TradingView免费组件脚本")
    require("www.tradingview-widget.com" not in page and "www.tradingview-widget.com" not in app,
            "金融终端不得回退到会拒绝组件请求的旧www脚本主机")
    require('type="module"' in page and page.index("tv-mini-chart.js") < page.index('src="app.js"'),
            "TradingView组件必须以模块脚本在本地应用前加载")
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
    browser_validator = BROWSER_VALIDATOR.read_text(encoding="utf-8")
    require("[360, 768, 1280, 1672, 2048]" in browser_validator and "Page.captureScreenshot" in browser_validator
            and '\".mjs\": \"text/javascript; charset=utf-8\"' in browser_validator
            and "Runtime.evaluate" in browser_validator and "officialObservationTrendCount" in browser_validator
            and "readinessEvidencePanelCount" in browser_validator
            and "validateDeferredLoading" in browser_validator
            and "criticalSourceRequestCount" in browser_validator
            and "informationSourceRequestCount" in browser_validator
            and "operationsSourceRequestCount" in browser_validator
            and "groupLoadSequence" in browser_validator
            and "duplicateNetworkRequestCount" in browser_validator
            and "informationTransitions" in browser_validator
            and "operationsTransitions" in browser_validator
            and "finance-terminal-browser-evidence.json" in browser_validator
            and "buildBrowserEvidence" in browser_validator
            and "runtimeEvidence=1" in browser_validator,
            "浏览器回归脚本未覆盖五档宽度、官方趋势、稳定V1证据、渲染DOM和截图")
    browser_evidence = BROWSER_EVIDENCE.read_text(encoding="utf-8")
    require("EXPECTED_WIDTHS = [360, 768, 1280, 1672, 2048]" in browser_evidence
            and 'EXPECTED_SYMBOLS = ["DIA", "GLD"]' in browser_evidence
            and "EXPECTED_PROVIDER_SCRIPT" in browser_evidence
            and "providerScriptLoadedViewports" in browser_evidence
            and "providerScriptFailedViewports" in browser_evidence
            and "buildViewportDiagnosis" in browser_evidence
            and "renderBrowserEvidenceSummary" in browser_evidence
            and "diagnosisCounts" in browser_evidence
            and "doesNotReadOrStoreQuotes" in browser_evidence
            and "connected-defined-element-with-layout" in browser_evidence,
            "浏览器证据未覆盖两项代理、五档视口或禁止行情读取边界")
    require('client.send("Network.enable")' in browser_validator
            and "trackProviderScriptTransport" in browser_validator
            and 'client.subscribe("Network.requestWillBeSent"' in browser_validator
            and 'client.subscribe("Network.responseReceived"' in browser_validator
            and 'client.subscribe("Network.loadingFailed"' in browser_validator,
            "浏览器回归未记录白名单提供方脚本的请求、响应和受控失败状态")
    proxy_history = PROXY_RUNTIME_HISTORY.read_text(encoding="utf-8")
    require("MAX_CYCLES = 7" in proxy_history
            and "ARTIFACT_LOOKBACK_DAYS = 14" in proxy_history
            and "EXPECTED_VIEWPORTS = 5" in proxy_history
            and "COMPATIBLE_VIEWPORT_COUNTS = {4, EXPECTED_VIEWPORTS}" in proxy_history
            and 'cycleBoundaryUtc": "21:00"' in proxy_history
            and "finance-terminal-proxy-runtime-" in proxy_history
            and "doesNotReadOrStoreQuotes" in proxy_history
            and "token-unavailable" in proxy_history
            and "api-unavailable" in proxy_history,
            "代理运行趋势未限制7周期、21:00 UTC边界、14天Artifact或诚实降级")
    require(QUALITY_WORKFLOW.exists(), "缺少金融终端只读质量工作流")
    require(LOADER_VALIDATOR.exists(), "缺少金融终端分区加载器独立契约测试")
    require(BOARD_VALIDATOR.exists(), "缺少品类行情板独立契约测试")
    quality_workflow = QUALITY_WORKFLOW.read_text(encoding="utf-8")
    require("permissions:\n  actions: read\n  contents: read" in quality_workflow,
            "金融终端质量工作流权限必须限制为Actions与内容只读")
    require(".github/ISSUE_TEMPLATE/finance-terminal-data.yml" in quality_workflow,
            "金融终端质量工作流未覆盖数据反馈表单变更")
    require("docs/FINANCE_TERMINAL_OPERATIONS_RUNBOOK.md" in quality_workflow,
            "金融终端质量工作流未覆盖四管道运行手册变更")
    require("validate_finance_terminal_browser.mjs" in quality_workflow
            and "validate_finance_terminal_visuals.mjs" in quality_workflow
            and "validate_finance_terminal_browser_evidence.mjs" in quality_workflow
            and "fonts-noto-cjk" in quality_workflow
            and "finance-terminal-browser-evidence.json" in quality_workflow
            and "finance-terminal-browser-evidence.md" in quality_workflow
            and "validate_finance_terminal_proxy_runtime_history.py" in quality_workflow
            and "finance_terminal_proxy_runtime_history.py" in quality_workflow
            and "finance-terminal-proxy-runtime-history.json" in quality_workflow
            and "finance-terminal-proxy-runtime-history.md" in quality_workflow
            and "GITHUB_TOKEN: ${{ github.token }}" in quality_workflow
            and "finance-terminal-proxy-runtime" in quality_workflow
            and "validate_finance_terminal.py" in quality_workflow
            and "node scripts/validate_finance_terminal_loader.mjs" in quality_workflow
            and "node scripts/validate_finance_terminal_board.mjs" in quality_workflow,
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
    require("validate_finance_terminal_readiness_snapshot.py" in quality_workflow,
            "金融终端质量工作流未校验稳定V1静态证据")
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
    require("parse_eia_rwtc_history_html" in build_script and "EIA_HISTORY_URL" in build_script,
            "宏观雷达脚本缺少EIA官方历史页无密钥回退")
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
    require('-f event=workflow_dispatch -f "branch=$GITHUB_REF_NAME" -f per_page=1' in scheduler,
            "每日调度器必须按当前分支查询最近运行，不能让开发分支资格运行抑制main生产调度")
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
    run_shared_history_contract_tests()
    run_asset_tracker_builder_contract_tests()
    run_company_builder_contract_tests()
    run_asset_ranking_builder_contract_tests()
    run_official_observation_contract_tests()
    run_dtwexbgs_pipeline_tests()
    run_rwtc_pipeline_tests()
    run_js_adapter_tests()
    run_provider_widget_runtime_tests()
    board_contracts = subprocess.run(
        ["node", str(BOARD_VALIDATOR)],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    require(board_contracts.returncode == 0,
            f"品类行情板契约失败：\n{board_contracts.stdout}{board_contracts.stderr}")
    print(board_contracts.stdout.strip())
    visual_contracts = subprocess.run(
        ["node", str(VISUALS_VALIDATOR)],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    require(visual_contracts.returncode == 0,
            f"科幻终端视觉数据契约失败：\n{visual_contracts.stdout}{visual_contracts.stderr}")
    print(visual_contracts.stdout.strip())

    print("Finance Terminal DGS10 + DTWEXBGS + RWTC + BTC/USD validation: PASS")
    print("- four local data cards plus two explicit free TradingView ETF proxies / zero demos: PASS")
    print("- yield bp / broad-dollar and WTI percent / BTC 24h or previous-close change: PASS")
    print("- FRED and EIA refresh success / retained fallback / no-history error: PASS")
    print("- source / as-of / updated-at / stale / unavailable states: PASS")
    print("- homepage route and local data dependency: PASS")
    print("- 360 / 768 / 1280 / 1672 / 2048 responsive rules: PASS")
    print("- macro regime value / source / freshness / fallback states: PASS")
    print("- CNN fear & greed score / rating / close delta / freshness / failure states: PASS")
    print("- OFR FSI value / daily change / zero baseline / freshness / partial / failure states: PASS")
    print("- cross-asset five-period ranking / per-row provenance / fallback / freshness / failure states: PASS")
    print("- global asset top-five / total / per-record provenance / mixed-frequency / failure states: PASS")
    print("- company per-row market/fallback/estimate / mover gating / private exclusion / failure states: PASS")
    print("- aggregate source health / coverage / consecutive failure / retained snapshot / diagnostics: PASS")
    print("- four-pipeline stable V1 evidence / macro cross-check / stale snapshot isolation: PASS")
    print("- Beta gate link / structured data feedback / sensitive-input warning: PASS")
    print("- economic calendar counts / impact / local-time input / freshness / independent failure states: PASS")
    print("- finance news market-only / latest-five / safe links / freshness / independent failure states: PASS")
    print("- four supporting feeds / migrated health / partial fallback / retained snapshot / workflow governance: PASS")
    print("- four real-asset update chains / single-source isolation / stale evidence: PASS")
    print("- one allowlisted TradingView free widget dependency / explicit proxy fallback: PASS")
    print("- proxy widget registration / host mount / timeout / late-recovery contract: PASS")
    print("- browser regression probe / read-only CI contract: PASS")


if __name__ == "__main__":
    main()
