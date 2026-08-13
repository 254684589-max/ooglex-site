#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""金融终端四项免费代理行情的机器可读公开展示契约。"""

from __future__ import annotations

from datetime import date
from typing import Any
from urllib.parse import urlparse


TRADINGVIEW_HOSTS = {"www.tradingview.com", "www.tradingview-widget.com"}
WIDGET_SCRIPT_URL = "https://www.tradingview-widget.com/w/en/tv-mini-chart.js"
EXPECTED_ASSETS = {
    "sp500": {"originalSymbol": "SPX", "proxySymbol": "SPY", "widgetSymbol": "AMEX:SPY"},
    "nasdaq100": {"originalSymbol": "NDX", "proxySymbol": "QQQ", "widgetSymbol": "NASDAQ:QQQ"},
    "dow": {"originalSymbol": "DJIA", "proxySymbol": "DIA", "widgetSymbol": "AMEX:DIA"},
    "gold": {
        "originalSymbol": "LBMA-GOLD-PM-USD",
        "proxySymbol": "GLD",
        "widgetSymbol": "AMEX:GLD",
    },
}


def _is_https_url(value: Any, expected_hosts: set[str] | None = None) -> bool:
    if not isinstance(value, str):
        return False
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.path) and (
        expected_hosts is None or parsed.hostname in expected_hosts
    )


def validate_market_source_readiness(readiness: dict[str, Any]) -> list[str]:
    """验证免费嵌入代理边界；不把免费API访问误认为公开再分发权。"""
    errors: list[str] = []
    if readiness.get("schemaVersion") != 3:
        errors.append("免费代理行情契约schemaVersion必须为3")
    try:
        date.fromisoformat(str(readiness.get("reviewedOn")))
    except ValueError:
        errors.append("免费代理行情契约reviewedOn必须是ISO日期")
    if readiness.get("displayScope") != "public-web":
        errors.append("免费代理行情契约必须明确覆盖public-web展示")
    policy = str(readiness.get("policy", ""))
    if "显式ETF代理" not in policy or "不抓取、导出或再分发" not in policy:
        errors.append("免费代理行情契约缺少代理与禁止原始数据再分发边界")

    selection = readiness.get("selection")
    if not isinstance(selection, dict):
        errors.append("免费代理行情契约缺少产品选择")
        selection = {}
    if selection.get("strategy") != "free-embedded-proxy":
        errors.append("稳定V1必须使用免费官方嵌入代理策略")
    try:
        date.fromisoformat(str(selection.get("decidedOn")))
    except ValueError:
        errors.append("免费代理决定日期必须是ISO日期")
    if selection.get("decidedBy") != "project-owner":
        errors.append("免费代理决定必须由项目所有者确认")
    if selection.get("proxySubstitutionAllowed") is not True:
        errors.append("所有者选择免费代理后必须明确允许代理替换")
    if selection.get("exactBenchmarkProcurementPaused") is not True:
        errors.append("免费优先策略必须暂停精确基准采购")

    use_case = readiness.get("useCase")
    if not isinstance(use_case, dict):
        errors.append("免费代理行情契约缺少非商业使用范围")
        use_case = {}
    expected_use_case = {
        "operatorType": "individual-hobbyist",
        "commercial": False,
        "advertising": False,
        "subscriptions": False,
        "otherRevenue": False,
        "domain": "ooglex.com",
        "displayPurpose": "personal-financial-research",
        "publicApiRedistribution": False,
        "rawMarketDataStored": False,
        "tradingExecution": False,
        "investmentProduct": False,
        "costPolicy": "free-only",
    }
    for key, expected in expected_use_case.items():
        if use_case.get(key) != expected:
            errors.append(f"免费非商业使用范围{key}与所有者决定不一致")

    provider = readiness.get("provider")
    if not isinstance(provider, dict):
        errors.append("免费代理行情契约缺少嵌入提供方")
        provider = {}
    expected_provider = {
        "name": "TradingView",
        "delivery": "official-free-web-component",
        "widget": "tv-mini-chart",
        "scriptUrl": WIDGET_SCRIPT_URL,
        "cost": "free",
        "credentialsRequired": False,
        "attributionRequired": True,
        "exportAllowed": False,
        "providerControlsDelay": True,
    }
    for key, expected in expected_provider.items():
        if provider.get(key) != expected:
            errors.append(f"TradingView免费嵌入配置{key}无效")
    for key in ("documentationUrl", "marketAvailabilityUrl", "dataFaqUrl"):
        if not _is_https_url(provider.get(key), {"www.tradingview.com"}):
            errors.append(f"TradingView免费嵌入缺少官方{key}")
    runtime_verification = provider.get("runtimeVerification")
    expected_runtime_verification = {
        "registrationTag": "tv-mini-chart",
        "registrationTimeoutMs": 8000,
        "registrationEvidence": "custom-element-registered",
        "hostCheckDelayMs": 100,
        "successEvidence": "connected-defined-element-with-layout",
        "successDoesNotAssert": ["quote-rendered", "quote-freshness", "market-open"],
        "failureFallback": "official-symbol-link",
        "lateRegistrationRecovery": True,
    }
    if not isinstance(runtime_verification, dict):
        errors.append("TradingView免费嵌入缺少运行时验证边界")
    else:
        for key, expected in expected_runtime_verification.items():
            if runtime_verification.get(key) != expected:
                errors.append(f"TradingView运行时验证{key}无效")

    assets = readiness.get("assets")
    if not isinstance(assets, list):
        return errors + ["免费代理行情契约assets必须是数组"]
    ids = [asset.get("id") for asset in assets if isinstance(asset, dict)]
    if len(assets) != 4 or len(ids) != 4 or set(ids) != set(EXPECTED_ASSETS):
        errors.append("免费代理行情契约必须恰好覆盖三大股指与黄金且ID唯一")

    valid_count = 0
    for asset in assets:
        if not isinstance(asset, dict):
            errors.append("免费代理资产记录必须是对象")
            continue
        asset_id = asset.get("id")
        spec = EXPECTED_ASSETS.get(asset_id)
        if not spec:
            continue
        original = asset.get("original")
        proxy = asset.get("proxy")
        if not isinstance(original, dict) or original.get("symbol") != spec["originalSymbol"]:
            errors.append(f"{asset_id}缺少原标的披露")
        if not isinstance(proxy, dict):
            errors.append(f"{asset_id}缺少选定ETF代理")
            continue
        if proxy.get("symbol") != spec["proxySymbol"] or proxy.get("widgetSymbol") != spec["widgetSymbol"]:
            errors.append(f"{asset_id}代理代码或TradingView代码不一致")
        if proxy.get("instrumentType") != "etf-proxy" or proxy.get("isSameInstrument") is not False:
            errors.append(f"{asset_id}必须明确ETF代理不是原标的")
        if proxy.get("selected") is not True:
            errors.append(f"{asset_id}免费代理必须由所有者显式选定")
        if asset.get("productionAction") != "embed-provider-widget":
            errors.append(f"{asset_id}不得抓取或保存免费组件原始行情")
        else:
            valid_count += 1

    if readiness.get("proxyAssetCount") != valid_count:
        errors.append("proxyAssetCount无法由逐项代理状态复算")
    if readiness.get("freeDisplayAssetCount") != valid_count:
        errors.append("freeDisplayAssetCount无法由逐项免费展示状态复算")
    return errors


def authorization_summary(readiness: dict[str, Any]) -> dict[str, Any]:
    """保留旧调用名，输出免费嵌入代理门禁摘要。"""
    assets = readiness.get("assets") or []
    proxies = {
        asset["id"]: asset["proxy"]["symbol"]
        for asset in assets
        if isinstance(asset, dict) and isinstance(asset.get("proxy"), dict)
    }
    return {
        "reviewedOn": readiness.get("reviewedOn"),
        "displayScope": readiness.get("displayScope"),
        "strategy": (readiness.get("selection") or {}).get("strategy"),
        "blockedAssets": 0,
        "approvedAssets": 0,
        "preparedInquiries": 0,
        "proxyAssets": len(proxies),
        "freeDisplayAssets": readiness.get("freeDisplayAssetCount"),
        "proxySymbols": proxies,
        "provider": (readiness.get("provider") or {}).get("name"),
        "delivery": (readiness.get("provider") or {}).get("delivery"),
        "cost": (readiness.get("provider") or {}).get("cost"),
        "rawMarketDataStored": (readiness.get("useCase") or {}).get("rawMarketDataStored"),
        "runtimeVerification": (readiness.get("provider") or {}).get("runtimeVerification"),
    }
