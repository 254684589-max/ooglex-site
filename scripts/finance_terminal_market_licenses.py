#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""金融终端四项待授权行情的机器可读上线契约。"""

from __future__ import annotations

from datetime import date
from typing import Any
from urllib.parse import urlparse


EXPECTED_ASSETS = {
    "sp500": {
        "targetSymbol": "SPX",
        "seriesId": "SP500",
        "providerHost": "fred.stlouisfed.org",
        "proxySymbol": "SPY",
    },
    "nasdaq100": {
        "targetSymbol": "NDX",
        "seriesId": "NASDAQ100",
        "providerHost": "fred.stlouisfed.org",
        "proxySymbol": "QQQ",
    },
    "dow": {
        "targetSymbol": "DJI",
        "seriesId": "DJIA",
        "providerHost": "fred.stlouisfed.org",
        "proxySymbol": "DIA",
    },
    "gold": {
        "targetSymbol": "XAU/USD",
        "seriesId": "LBMA-GOLD-PRICE",
        "providerHost": "www.lbma.org.uk",
        "proxySymbol": "GLD",
    },
}
AUTHORIZATION_STATUSES = {"blocked", "approved"}
BLOCKED_ACTION = "keep-demo"


def _is_https_url(value: Any, expected_host: str | None = None) -> bool:
    if not isinstance(value, str):
        return False
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.path) and (
        expected_host is None or parsed.hostname == expected_host
    )


def validate_market_source_readiness(readiness: dict[str, Any]) -> list[str]:
    """返回所有契约错误；不读取网络，也不把候选API视为展示许可。"""
    errors: list[str] = []
    if readiness.get("schemaVersion") != 1:
        errors.append("行情授权契约schemaVersion必须为1")
    try:
        date.fromisoformat(str(readiness.get("reviewedOn")))
    except ValueError:
        errors.append("行情授权契约reviewedOn必须是ISO日期")
    if readiness.get("displayScope") != "public-web":
        errors.append("行情授权契约必须明确覆盖public-web展示")
    if "精确原标的" not in str(readiness.get("policy", "")):
        errors.append("行情授权契约缺少精确原标的边界")

    assets = readiness.get("assets")
    if not isinstance(assets, list):
        return errors + ["行情授权契约assets必须是数组"]
    ids = [asset.get("id") for asset in assets if isinstance(asset, dict)]
    if len(assets) != 4 or len(ids) != 4 or set(ids) != set(EXPECTED_ASSETS):
        errors.append("行情授权契约必须恰好覆盖三大股指与黄金且ID唯一")

    blocked_count = 0
    for asset in assets:
        if not isinstance(asset, dict):
            errors.append("行情授权资产记录必须是对象")
            continue
        asset_id = asset.get("id")
        spec = EXPECTED_ASSETS.get(asset_id)
        if not spec:
            continue
        if asset.get("targetSymbol") != spec["targetSymbol"]:
            errors.append(f"{asset_id}目标代码与精确原标的不一致")
        candidate = asset.get("candidateSource")
        if not isinstance(candidate, dict):
            errors.append(f"{asset_id}缺少候选来源")
            candidate = {}
        if candidate.get("seriesId") != spec["seriesId"]:
            errors.append(f"{asset_id}候选序列与登记来源不一致")
        if not _is_https_url(candidate.get("url"), spec["providerHost"]):
            errors.append(f"{asset_id}候选来源必须使用登记的官方HTTPS页面")

        authorization = asset.get("authorization")
        if not isinstance(authorization, dict):
            errors.append(f"{asset_id}缺少授权结论")
            authorization = {}
        status = authorization.get("status")
        if status not in AUTHORIZATION_STATUSES:
            errors.append(f"{asset_id}授权状态必须为blocked或approved")
        if not _is_https_url(authorization.get("evidenceUrl"), spec["providerHost"]):
            errors.append(f"{asset_id}缺少官方授权依据链接")
        if not _is_https_url(authorization.get("termsUrl")):
            errors.append(f"{asset_id}缺少官方条款链接")
        if not str(authorization.get("licenseOwner", "")).strip():
            errors.append(f"{asset_id}缺少许可权利人")
        if status == "blocked":
            blocked_count += 1
            if authorization.get("publicDisplayAuthorized") is not False:
                errors.append(f"{asset_id}未获授权时不得标记公开展示已批准")
            if not str(authorization.get("reasonCode", "")).strip():
                errors.append(f"{asset_id}阻塞状态缺少原因代码")
            if asset.get("productionAction") != BLOCKED_ACTION:
                errors.append(f"{asset_id}授权阻塞时必须继续保留演示数据")
        elif status == "approved":
            if authorization.get("publicDisplayAuthorized") is not True:
                errors.append(f"{asset_id}approved状态必须明确公开展示已授权")
            if not str(authorization.get("approvalReference", "")).strip():
                errors.append(f"{asset_id}approved状态缺少可审计授权编号")
            if asset.get("productionAction") != "integrate-authorized-source":
                errors.append(f"{asset_id}获授权后必须进入授权来源接入流程")

        proxy = asset.get("proxyAlternative")
        if not isinstance(proxy, dict):
            errors.append(f"{asset_id}缺少显式代理候选")
            proxy = {}
        if proxy.get("symbol") != spec["proxySymbol"]:
            errors.append(f"{asset_id}代理候选代码与登记决策不一致")
        if proxy.get("instrumentType") != "etf-proxy" or proxy.get("isSameInstrument") is not False:
            errors.append(f"{asset_id}必须明确ETF不是同一原标的")
        if proxy.get("requiresProductApproval") is not True:
            errors.append(f"{asset_id}采用代理前必须经过产品决定")

    if readiness.get("blockedAssetCount") != blocked_count:
        errors.append("blockedAssetCount无法由逐项授权状态复算")
    return errors


def authorization_summary(readiness: dict[str, Any]) -> dict[str, Any]:
    """提取门禁可展示指标；调用方应先执行完整验证。"""
    assets = readiness.get("assets") or []
    statuses = {
        asset["id"]: asset["authorization"]["status"]
        for asset in assets
        if isinstance(asset, dict) and isinstance(asset.get("authorization"), dict)
    }
    return {
        "reviewedOn": readiness.get("reviewedOn"),
        "displayScope": readiness.get("displayScope"),
        "blockedAssets": sum(status == "blocked" for status in statuses.values()),
        "approvedAssets": sum(status == "approved" for status in statuses.values()),
        "authorizationStatuses": statuses,
    }
