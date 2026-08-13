#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""四项待授权核心行情的离线契约测试。"""

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
    require(not validate_market_source_readiness(readiness), "仓库行情授权契约无效")
    summary = authorization_summary(readiness)
    require(summary["blockedAssets"] == 4 and summary["approvedAssets"] == 0,
            "四项精确原标的必须继续保持授权阻塞")
    require(summary["strategy"] == "exact-original"
            and summary["preparedInquiries"] == 4,
            "四项精确原标的必须完成询价准备且不得切换代理")
    require(set(summary["authorizationStatuses"]) == set(EXPECTED_ASSETS),
            "授权状态没有完整覆盖三大股指与黄金")

    tampered = deepcopy(readiness)
    tampered["blockedAssetCount"] = 0
    require(any("blockedAssetCount" in error
                for error in validate_market_source_readiness(tampered)),
            "授权阻塞计数篡改未被拒绝")

    silently_proxied = deepcopy(readiness)
    silently_proxied["assets"][0]["proxyAlternative"]["isSameInstrument"] = True
    require(any("同一原标的" in error
                for error in validate_market_source_readiness(silently_proxied)),
            "ETF静默冒充指数未被拒绝")

    selected_proxy = deepcopy(readiness)
    selected_proxy["assets"][0]["proxyAlternative"]["selected"] = True
    require(any("不得选择ETF代理" in error
                for error in validate_market_source_readiness(selected_proxy)),
            "所有者选择精确原标的后仍可启用ETF代理")

    commercialized = deepcopy(readiness)
    commercialized["useCase"]["advertising"] = True
    require(any("advertising" in error
                for error in validate_market_source_readiness(commercialized)),
            "非商业询价范围被静默扩大")

    fake_submission = deepcopy(readiness)
    fake_submission["assets"][0]["procurement"]["status"] = "submitted"
    fake_submission["assets"][0]["procurement"]["submittedAt"] = "2026-08-13T08:00:00Z"
    require(any("可审计编号" in error
                for error in validate_market_source_readiness(fake_submission)),
            "无审计编号的已提交询价未被拒绝")

    fake_approval = deepcopy(readiness)
    fake_approval["assets"][0]["authorization"].update({
        "status": "approved",
        "publicDisplayAuthorized": True,
    })
    fake_approval["assets"][0]["productionAction"] = "integrate-authorized-source"
    fake_approval["blockedAssetCount"] = 3
    require(any("授权编号" in error
                for error in validate_market_source_readiness(fake_approval)),
            "无可审计授权编号的approved状态未被拒绝")

    print("Finance terminal market license readiness: PASS")
    print("- exact SPX / NDX / DJIA / LBMA Gold PM authorization boundary: PASS")
    print("- individual non-commercial delayed-display scope: PASS")
    print("- official inquiry routes and auditable submission states: PASS")
    print("- owner-selected no-proxy guard: PASS")


if __name__ == "__main__":
    main()
