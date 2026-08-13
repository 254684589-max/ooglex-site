#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""四项免费嵌入代理行情的离线契约测试。"""

from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path

from finance_terminal_market_licenses import (
    EXPECTED_ASSETS,
    authorization_summary,
    validate_market_source_readiness,
)


ROOT = Path(__file__).resolve().parents[1]
READINESS_PATH = ROOT / "apps" / "finance-terminal" / "market-source-readiness.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    readiness = json.loads(READINESS_PATH.read_text(encoding="utf-8"))
    require(not validate_market_source_readiness(readiness), "仓库免费代理行情契约无效")
    summary = authorization_summary(readiness)
    require(summary["proxyAssets"] == 4 and summary["freeDisplayAssets"] == 4,
            "四项代理必须全部使用免费嵌入展示")
    require(summary["strategy"] == "free-embedded-proxy"
            and summary["provider"] == "TradingView"
            and summary["cost"] == "free",
            "免费代理策略、提供方或费用状态无效")
    require(summary["rawMarketDataStored"] is False,
            "官方组件路径不得保存或再分发原始行情")
    runtime_verification = summary["runtimeVerification"]
    require(runtime_verification["registrationTag"] == "tv-mini-chart"
            and runtime_verification["registrationTimeoutMs"] == 8000
            and runtime_verification["registrationEvidence"] == "custom-element-registered",
            "组件运行时登记验证契约无效")
    require(runtime_verification["hostCheckDelayMs"] == 100
            and runtime_verification["successEvidence"]
            == "connected-defined-element-with-layout",
            "组件宿主挂载验证契约无效")
    require(runtime_verification["successDoesNotAssert"]
            == ["quote-rendered", "quote-freshness", "market-open"]
            and runtime_verification["failureFallback"] == "official-symbol-link"
            and runtime_verification["lateRegistrationRecovery"] is True,
            "组件登记不得冒充行情渲染、新鲜度或开市状态")
    require(set(summary["proxySymbols"]) == set(EXPECTED_ASSETS),
            "代理状态没有完整覆盖三大股指与黄金")

    tampered = deepcopy(readiness)
    tampered["proxyAssetCount"] = 0
    require(any("proxyAssetCount" in error
                for error in validate_market_source_readiness(tampered)),
            "代理计数篡改未被拒绝")

    same_instrument = deepcopy(readiness)
    same_instrument["assets"][0]["proxy"]["isSameInstrument"] = True
    require(any("不是原标的" in error
                for error in validate_market_source_readiness(same_instrument)),
            "ETF代理静默冒充原指数未被拒绝")

    unselected = deepcopy(readiness)
    unselected["assets"][0]["proxy"]["selected"] = False
    require(any("显式选定" in error
                for error in validate_market_source_readiness(unselected)),
            "未由所有者选定的代理仍可通过")

    commercialized = deepcopy(readiness)
    commercialized["useCase"]["advertising"] = True
    require(any("advertising" in error
                for error in validate_market_source_readiness(commercialized)),
            "免费非商业范围被静默扩大")

    raw_storage = deepcopy(readiness)
    raw_storage["useCase"]["rawMarketDataStored"] = True
    require(any("rawMarketDataStored" in error
                for error in validate_market_source_readiness(raw_storage)),
            "免费组件原始行情可被静默保存")

    fake_api = deepcopy(readiness)
    fake_api["provider"]["delivery"] = "scraped-api"
    require(any("delivery" in error
                for error in validate_market_source_readiness(fake_api)),
            "未经授权的抓取接口冒充官方嵌入组件")

    paid = deepcopy(readiness)
    paid["provider"]["cost"] = "paid"
    require(any("cost" in error
                for error in validate_market_source_readiness(paid)),
            "付费来源可在免费优先策略下静默启用")

    false_freshness = deepcopy(readiness)
    false_freshness["provider"]["runtimeVerification"]["successDoesNotAssert"] = ["market-open"]
    require(any("successDoesNotAssert" in error
                for error in validate_market_source_readiness(false_freshness)),
            "组件登记可被静默误报为行情已渲染或新鲜")

    registration_only = deepcopy(readiness)
    registration_only["provider"]["runtimeVerification"]["successEvidence"] = "custom-element-registered"
    require(any("successEvidence" in error
                for error in validate_market_source_readiness(registration_only)),
            "组件只注册但没有挂载证据仍可通过")

    missing_layout_delay = deepcopy(readiness)
    del missing_layout_delay["provider"]["runtimeVerification"]["hostCheckDelayMs"]
    require(any("hostCheckDelayMs" in error
                for error in validate_market_source_readiness(missing_layout_delay)),
            "组件宿主挂载检查缺少稳定布局等待仍可通过")

    unsafe_fallback = deepcopy(readiness)
    unsafe_fallback["provider"]["runtimeVerification"]["failureFallback"] = "cached-quote"
    require(any("failureFallback" in error
                for error in validate_market_source_readiness(unsafe_fallback)),
            "组件失败后可用缓存行情冒充实时数据")

    print("Finance terminal free proxy readiness: PASS")
    print("- SPY / QQQ / DIA / GLD explicit ETF proxy boundary: PASS")
    print("- TradingView official free web-component delivery: PASS")
    print("- no API key / raw storage / scraping / paid source: PASS")
    print("- individual non-commercial public display scope: PASS")
    print("- registration + connected defined host layout / official-link fallback: PASS")


if __name__ == "__main__":
    main()
