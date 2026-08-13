#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""金融终端四项待授权行情的机器可读上线契约。"""

from __future__ import annotations

from datetime import date, datetime
from typing import Any
from urllib.parse import urlparse


EXPECTED_ASSETS = {
    "sp500": {
        "targetSymbol": "SPX",
        "seriesId": "SPX",
        "providerHosts": {"www.spglobal.com"},
        "evidenceHosts": {"www.spglobal.com"},
        "proxySymbol": "SPY",
        "requestGroup": "sp-dji-index-display",
        "contact": "index_services@spglobal.com",
        "contactHosts": {"www.spglobal.com"},
    },
    "nasdaq100": {
        "targetSymbol": "NDX",
        "seriesId": "NDX",
        "providerHosts": {"www.nasdaq.com"},
        "evidenceHosts": {"www.nasdaq.com"},
        "proxySymbol": "QQQ",
        "requestGroup": "nasdaq-index-display",
        "contact": "datasales@nasdaq.com",
        "contactHosts": {"www.nasdaqtrader.com"},
    },
    "dow": {
        "targetSymbol": "DJIA",
        "seriesId": "DJIA",
        "providerHosts": {"www.spglobal.com"},
        "evidenceHosts": {"www.spglobal.com"},
        "proxySymbol": "DIA",
        "requestGroup": "sp-dji-index-display",
        "contact": "index_services@spglobal.com",
        "contactHosts": {"www.spglobal.com"},
    },
    "gold": {
        "targetSymbol": "LBMA-GOLD-PM-USD",
        "seriesId": "LBMA-GOLD-PRICE-PM-USD",
        "providerHosts": {"www.ice.com"},
        "evidenceHosts": {"www.lbma.org.uk"},
        "proxySymbol": "GLD",
        "requestGroup": "iba-lbma-gold-display",
        "contact": "iba-licensing@theice.com",
        "contactHosts": {"www.ice.com"},
    },
}
AUTHORIZATION_STATUSES = {"blocked", "approved"}
PROCUREMENT_STATUSES = {"prepared", "submitted", "quoted", "licensed"}
BLOCKED_ACTION = "keep-demo"


def _is_https_url(value: Any, expected_hosts: set[str] | None = None) -> bool:
    if not isinstance(value, str):
        return False
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.path) and (
        expected_hosts is None or parsed.hostname in expected_hosts
    )


def _is_iso_datetime(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return parsed.tzinfo is not None


def validate_market_source_readiness(readiness: dict[str, Any]) -> list[str]:
    """返回所有契约错误；不读取网络，也不把候选API视为展示许可。"""
    errors: list[str] = []
    if readiness.get("schemaVersion") != 2:
        errors.append("行情授权契约schemaVersion必须为2")
    try:
        date.fromisoformat(str(readiness.get("reviewedOn")))
    except ValueError:
        errors.append("行情授权契约reviewedOn必须是ISO日期")
    if readiness.get("displayScope") != "public-web":
        errors.append("行情授权契约必须明确覆盖public-web展示")
    if "精确原标的" not in str(readiness.get("policy", "")):
        errors.append("行情授权契约缺少精确原标的边界")

    selection = readiness.get("selection")
    if not isinstance(selection, dict):
        errors.append("行情授权契约缺少产品选择")
        selection = {}
    if selection.get("strategy") != "exact-original":
        errors.append("稳定V1必须锁定精确原标的策略")
    try:
        date.fromisoformat(str(selection.get("decidedOn")))
    except ValueError:
        errors.append("精确原标的决定日期必须是ISO日期")
    if selection.get("decidedBy") != "project-owner":
        errors.append("精确原标的决定必须由项目所有者确认")
    if selection.get("proxySubstitutionAllowed") is not False:
        errors.append("精确原标的策略不得静默允许代理替换")

    use_case = readiness.get("useCase")
    if not isinstance(use_case, dict):
        errors.append("行情授权契约缺少非商业使用范围")
        use_case = {}
    expected_use_case = {
        "operatorType": "individual-hobbyist",
        "commercial": False,
        "advertising": False,
        "subscriptions": False,
        "otherRevenue": False,
        "domain": "ooglex.com",
        "displayLatency": "daily-delayed",
        "displayPurpose": "personal-financial-research",
        "publicApiRedistribution": False,
        "tradingExecution": False,
        "investmentProduct": False,
        "quoteAcceptance": "owner-confirmation-required",
    }
    for key, expected in expected_use_case.items():
        if use_case.get(key) != expected:
            errors.append(f"非商业使用范围{key}与所有者决定不一致")

    assets = readiness.get("assets")
    if not isinstance(assets, list):
        return errors + ["行情授权契约assets必须是数组"]
    ids = [asset.get("id") for asset in assets if isinstance(asset, dict)]
    if len(assets) != 4 or len(ids) != 4 or set(ids) != set(EXPECTED_ASSETS):
        errors.append("行情授权契约必须恰好覆盖三大股指与黄金且ID唯一")

    blocked_count = 0
    inquiry_ready_count = 0
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
        if not _is_https_url(candidate.get("url"), spec["providerHosts"]):
            errors.append(f"{asset_id}候选来源必须使用登记的官方HTTPS页面")

        authorization = asset.get("authorization")
        if not isinstance(authorization, dict):
            errors.append(f"{asset_id}缺少授权结论")
            authorization = {}
        status = authorization.get("status")
        if status not in AUTHORIZATION_STATUSES:
            errors.append(f"{asset_id}授权状态必须为blocked或approved")
        if not _is_https_url(authorization.get("evidenceUrl"), spec["evidenceHosts"]):
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

        procurement = asset.get("procurement")
        if not isinstance(procurement, dict):
            errors.append(f"{asset_id}缺少询价准备记录")
            procurement = {}
        procurement_status = procurement.get("status")
        if procurement_status not in PROCUREMENT_STATUSES:
            errors.append(f"{asset_id}询价状态无效")
        else:
            inquiry_ready_count += 1
        if procurement.get("requestGroup") != spec["requestGroup"]:
            errors.append(f"{asset_id}询价分组与权利人不一致")
        if str(procurement.get("contact", "")).lower() != spec["contact"]:
            errors.append(f"{asset_id}询价联系方式与官方登记不一致")
        if not _is_https_url(procurement.get("contactUrl"), spec["contactHosts"]):
            errors.append(f"{asset_id}缺少官方询价入口")
        requested_license = str(procurement.get("requestedLicense", "")).lower()
        if "public website display" not in requested_license or not (
            "daily" in requested_license or "delayed" in requested_license
        ):
            errors.append(f"{asset_id}询价范围必须限制为日频或延迟公开网页展示")
        if not str(procurement.get("delivery", "")).strip():
            errors.append(f"{asset_id}缺少授权后数据交付路径")
        if procurement_status == "prepared":
            if procurement.get("submittedAt") is not None:
                errors.append(f"{asset_id}尚未提交询价时不得伪造提交时间")
            if procurement.get("inquiryReference"):
                errors.append(f"{asset_id}尚未提交询价时不得登记询价编号")
        elif procurement_status in {"submitted", "quoted"}:
            if not _is_iso_datetime(procurement.get("submittedAt")):
                errors.append(f"{asset_id}已提交询价必须记录带时区的提交时间")
            if not str(procurement.get("inquiryReference", "")).strip():
                errors.append(f"{asset_id}已提交询价必须记录可审计编号")
        elif procurement_status == "licensed":
            if status != "approved":
                errors.append(f"{asset_id}只有公开展示授权批准后才能标记licensed")
        if status == "approved" and procurement_status != "licensed":
            errors.append(f"{asset_id}授权批准与采购状态不一致")

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
        if proxy.get("selected") is not False:
            errors.append(f"{asset_id}精确原标的策略下不得选择ETF代理")

    if readiness.get("blockedAssetCount") != blocked_count:
        errors.append("blockedAssetCount无法由逐项授权状态复算")
    if readiness.get("inquiryReadyAssetCount") != inquiry_ready_count:
        errors.append("inquiryReadyAssetCount无法由逐项询价状态复算")
    return errors


def authorization_summary(readiness: dict[str, Any]) -> dict[str, Any]:
    """提取门禁可展示指标；调用方应先执行完整验证。"""
    assets = readiness.get("assets") or []
    statuses = {
        asset["id"]: asset["authorization"]["status"]
        for asset in assets
        if isinstance(asset, dict) and isinstance(asset.get("authorization"), dict)
    }
    procurement_statuses = {
        asset["id"]: asset["procurement"]["status"]
        for asset in assets
        if isinstance(asset, dict) and isinstance(asset.get("procurement"), dict)
    }
    return {
        "reviewedOn": readiness.get("reviewedOn"),
        "displayScope": readiness.get("displayScope"),
        "strategy": (readiness.get("selection") or {}).get("strategy"),
        "blockedAssets": sum(status == "blocked" for status in statuses.values()),
        "approvedAssets": sum(status == "approved" for status in statuses.values()),
        "preparedInquiries": sum(
            status == "prepared" for status in procurement_statuses.values()
        ),
        "authorizationStatuses": statuses,
        "procurementStatuses": procurement_statuses,
    }
