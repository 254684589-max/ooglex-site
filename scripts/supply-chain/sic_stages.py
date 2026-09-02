#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""SIC 行业码 → 价值链阶段的映射规则。

## 为什么需要它

第 0 层只有 GICS 一级板块（11 类）可用，粒度不足以定位产业链位置：同属「科技」的
英伟达（芯片，中间制造）、苹果（终端品牌）与微软（软件平台）位置完全不同，因此
313/495 个节点只能给候选集、不能给结论。

SEC 的 SIC 码（4 位）恰好能分开它们——实测取到的真实代码：

    AAPL 3571 Electronic Computers          → 品牌整合
    NVDA 3674 Semiconductors                → 中间制造
    MSFT 7372 Prepackaged Software          → 平台服务

## 规则形态

按「先精确后范围」匹配：4 位精确覆盖 → 4 位区间 → 2 位大类。每条规则都写明依据，
不是拍脑袋——SIC 的大类结构本身是公开标准（01-09 农林渔、10-14 采矿、20-39 制造、
40-49 运输公用、50-59 批零、60-67 金融地产、70-89 服务）。

## 边界

SEC 的 SIC 分配本身有不一致：应用材料（半导体设备）被分到 3674 半导体，泛林（同样是
设备）被分到 3559 专用机械。两者阶段相同（都是中间制造），所以不影响结论，但**这说明
SIC 是「比板块细」而不是「精确」**——节点仍标 `stageBasis: sic-refined`，与真实上下游边
反推出的 `edge-derived` 区分开。
"""
from __future__ import annotations

STAGE_UPSTREAM = "upstream-resource"
STAGE_INTERMEDIATE = "intermediate-manufacturing"
STAGE_BRAND = "brand-integration"
STAGE_DISTRIBUTION = "distribution-service"
STAGE_PLATFORM = "platform-service"
STAGE_SUPPORTING = "supporting"

# ── 4 位精确覆盖：同一大类里阶段确实不同的那些 ──────────────────────────────
EXACT: dict[int, tuple[str, str]] = {
    # 35xx 机械与计算机：整机是品牌整合，零部件与设备是中间制造
    3571: (STAGE_BRAND, "电子计算机整机，设计与品牌为主（苹果、戴尔、惠普）"),
    3572: (STAGE_INTERMEDIATE, "计算机存储设备，是整机的零部件"),
    3576: (STAGE_INTERMEDIATE, "计算机通信设备"),
    3577: (STAGE_INTERMEDIATE, "计算机外围设备"),
    3578: (STAGE_INTERMEDIATE, "计算与记账机器"),
    # 37xx 运输设备：整车整机是品牌整合，零部件是中间制造
    3711: (STAGE_BRAND, "整车制造"),
    3713: (STAGE_BRAND, "卡车与客车车身"),
    3714: (STAGE_INTERMEDIATE, "机动车零部件"),
    3721: (STAGE_BRAND, "飞机整机"),
    3724: (STAGE_INTERMEDIATE, "飞机发动机与零件"),
    3728: (STAGE_INTERMEDIATE, "飞机零部件"),
    # 283x 医药：成药与生物制品是面向终端的成品，诊断试剂是中间投入
    2834: (STAGE_BRAND, "成药制剂，面向终端市场的成品"),
    2836: (STAGE_BRAND, "生物制品"),
    2835: (STAGE_INTERMEDIATE, "体外诊断试剂，是医疗服务的投入品"),
}

# ── 4 位区间：比大类细、但不必逐码列举的段落 ────────────────────────────────
RANGES: list[tuple[int, int, str, str]] = [
    (100, 999, STAGE_UPSTREAM, "农林牧渔，初级产品"),
    (1000, 1499, STAGE_UPSTREAM, "采矿与油气开采"),
    (1500, 1799, STAGE_BRAND, "建筑与住宅开发，交付终端成品"),
    (2000, 2199, STAGE_BRAND, "食品饮料与烟草，面向终端消费"),
    (2200, 2299, STAGE_INTERMEDIATE, "纺织，是服装的投入品"),
    (2300, 2399, STAGE_BRAND, "服装成衣"),
    (2400, 2499, STAGE_UPSTREAM, "木材采伐与初加工"),
    (2500, 2599, STAGE_BRAND, "家具"),
    (2600, 2699, STAGE_INTERMEDIATE, "造纸，是包装与印刷的投入品"),
    (2700, 2799, STAGE_PLATFORM, "出版与印刷，以内容为主"),
    (2800, 2899, STAGE_INTERMEDIATE, "化工，多为下游行业的投入品"),
    (2900, 2999, STAGE_UPSTREAM, "石油炼制与煤制品"),
    (3000, 3099, STAGE_INTERMEDIATE, "橡胶与塑料制品"),
    (3100, 3199, STAGE_BRAND, "皮革制品与鞋类"),
    (3200, 3299, STAGE_INTERMEDIATE, "石料、陶土与玻璃制品"),
    # 33xx 必须拆开：331x-334x 是高炉、轧钢与有色冶炼精炼（真上游）；
    # 335x-339x 是把金属加工成线材、板材、铸件（给下游用的投入品，属中间制造）。
    # 不拆的话康宁（SIC 3357 有色线材拉制）会被误判成上游资源——它做的是
    # 玻璃基板与光纤，是不折不扣的中间投入（实测用例）。
    (3300, 3349, STAGE_UPSTREAM, "钢铁与有色金属冶炼精炼"),
    (3350, 3399, STAGE_INTERMEDIATE, "金属轧制、拉制与铸造，供下游装配"),
    (3400, 3499, STAGE_INTERMEDIATE, "金属制品"),
    (3500, 3599, STAGE_INTERMEDIATE, "工业机械与设备"),
    (3600, 3699, STAGE_INTERMEDIATE, "电子与电气设备，含半导体"),
    (3700, 3799, STAGE_INTERMEDIATE, "运输设备零部件"),
    (3800, 3899, STAGE_INTERMEDIATE, "仪器仪表与医疗器械"),
    (3900, 3999, STAGE_BRAND, "其他制造业，多为终端产品"),
    (4000, 4799, STAGE_DISTRIBUTION, "运输与物流服务"),
    (4800, 4899, STAGE_DISTRIBUTION, "通信服务，网络承载与分发"),
    (4900, 4999, STAGE_SUPPORTING, "公用事业"),
    (5000, 5199, STAGE_DISTRIBUTION, "批发贸易"),
    (5200, 5999, STAGE_DISTRIBUTION, "零售贸易"),
    (6000, 6799, STAGE_SUPPORTING, "金融、保险与房地产"),
    (7000, 7299, STAGE_DISTRIBUTION, "住宿与个人服务"),
    (7300, 7399, STAGE_PLATFORM, "商业服务，含软件与数据处理"),
    (7400, 7999, STAGE_PLATFORM, "其他服务、娱乐与传媒"),
    (8000, 8099, STAGE_DISTRIBUTION, "医疗服务，面向终端患者"),
    (8100, 8999, STAGE_SUPPORTING, "法律、工程、管理等专业服务"),
]


def resolve(sic: int | str | None) -> dict | None:
    """把 SIC 码解析成价值链阶段。无法解析时返回 None，不猜。"""
    if sic is None or sic == "":
        return None
    try:
        code = int(sic)
    except (TypeError, ValueError):
        return None
    if code <= 0:
        return None
    if code in EXACT:
        stage, reason = EXACT[code]
        return {"stage": stage, "basis": "sic-exact", "sic": code, "reason": reason}
    for low, high, stage, reason in RANGES:
        if low <= code <= high:
            return {"stage": stage, "basis": "sic-range", "sic": code, "reason": reason}
    return None
