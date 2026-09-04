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

# ── 价值链环节 ────────────────────────────────────────────────────────────
# 八段实物链 + 四层使能层。相比早先的六段，补上了四处专业框架里本该分开、
# 而当时被并掉的东西：
#
#   物流与运输   原来并进「分销服务」。物流是链的**连接组织**，不是渠道；
#                华尔街单独跟踪运价（BDI、集装箱、空运），并掉就没法看。
#   资本设备     原来和零部件同属「中间制造」。应用材料、泛林、卡特彼勒是
#                **供给制造商的设备商**，与德州仪器、英伟达这类元器件供应商
#                在链上位置不同，混在一层等于说不出「谁供给谁」。
#   能源与公用事业 原来算「支持性行业」。电力和天然气是制造业的**投入品**，
#                不是像银行那样的外围服务。
#   循环与废弃物   SCOR 模型里的 Return（逆向供应链）。冲突矿产本身就涉及
#                回收金属，缺这一层框架就是单向的。
STAGE_RAW = "raw-material"
STAGE_MATERIAL = "material-processing"
STAGE_COMPONENT = "component"
STAGE_EQUIPMENT = "capital-equipment"
STAGE_FINISHED = "finished-goods"
STAGE_LOGISTICS = "logistics"
STAGE_DISTRIBUTION = "distribution"
STAGE_END_SERVICE = "end-service"
STAGE_ENERGY = "energy-utility"
STAGE_TECHNOLOGY = "technology"
STAGE_FINANCIAL = "financial"
STAGE_CIRCULAR = "circular"


# ── 4 位精确码：同一个大类里位置不同的，必须逐码拆 ──────────────────────────
# 这张表的每一条都对应一个真实会判错的公司。两位码做不到的精度在这里补。
EXACT: dict[int, tuple[str, str]] = {
    # 35xx 机械与计算机：整机是终端品牌，零部件是元器件，设备是资本品
    3571: (STAGE_FINISHED, "电子计算机整机，设计与品牌为主（苹果、戴尔、惠普）"),
    3570: (STAGE_EQUIPMENT, "计算机与办公设备，面向企业的资本支出（IBM、慧与）"),
    3572: (STAGE_COMPONENT, "计算机存储设备，是整机的零部件"),
    3576: (STAGE_COMPONENT, "计算机通信设备"),
    3577: (STAGE_COMPONENT, "计算机外围设备"),
    3578: (STAGE_COMPONENT, "计算与记账机器"),
    # 37xx 运输设备：整车整机是终端品牌，零部件是元器件
    3711: (STAGE_FINISHED, "整车制造"),
    3713: (STAGE_FINISHED, "卡车与客车车身"),
    3714: (STAGE_COMPONENT, "机动车零部件"),
    3721: (STAGE_FINISHED, "飞机整机"),
    3724: (STAGE_COMPONENT, "飞机发动机与零件"),
    3728: (STAGE_COMPONENT, "飞机零部件"),
    3730: (STAGE_FINISHED, "船舶制造"),
    3760: (STAGE_FINISHED, "导弹与航天器整机"),
    # 283x/284x 化工：成药与日化面向终端，诊断试剂是医疗服务的投入
    2834: (STAGE_FINISHED, "成药制剂，面向终端市场的成品"),
    2836: (STAGE_FINISHED, "生物制品"),
    2835: (STAGE_COMPONENT, "体外诊断试剂，是医疗服务的投入品"),
    # 44xx / 45xx 运输：**载客的不是物流**。水上运输在标普里全是邮轮公司，
    # 4512 是客运航空，4700 是在线旅游平台（Booking、亿客行）——
    # 按两位码把 40–47 整段归物流，会把邮轮和客运航空当成货运。
    4512: (STAGE_END_SERVICE, "客运航空，面向消费者的服务"),
    4513: (STAGE_LOGISTICS, "航空快递与货运（联邦快递）"),
    4700: (STAGE_END_SERVICE, "在线旅游平台"),
    4731: (STAGE_LOGISTICS, "货运代理与安排"),
}

# ── 4 位区间：比大类细、但不必逐码列举的段落 ────────────────────────────────
RANGES: list[tuple[int, int, str, str]] = [
    (100, 999, STAGE_RAW, "农林牧渔，初级产品"),
    (1000, 1499, STAGE_RAW, "采矿与油气开采"),
    (1500, 1799, STAGE_FINISHED, "建筑与住宅开发，交付终端成品"),
    (2000, 2199, STAGE_FINISHED, "食品饮料与烟草，面向终端消费"),
    (2200, 2299, STAGE_MATERIAL, "纺织，是服装的投入品"),
    (2300, 2399, STAGE_FINISHED, "服装成衣"),
    (2400, 2499, STAGE_MATERIAL, "木材采伐与初加工"),
    (2500, 2599, STAGE_FINISHED, "家具"),
    (2600, 2699, STAGE_MATERIAL, "造纸，是包装与印刷的投入品"),
    (2700, 2799, STAGE_TECHNOLOGY, "出版与内容，以内容为主"),
    # 28xx 化工要分开：工业化学品是投入品，日化与药品是终端成品（见 EXACT）
    (2800, 2839, STAGE_MATERIAL, "工业化学品，多为下游行业的投入品"),
    (2840, 2849, STAGE_FINISHED, "肥皂洗涤与化妆品，面向终端消费"),
    (2850, 2899, STAGE_MATERIAL, "涂料、农药与其他化学品"),
    (2900, 2999, STAGE_MATERIAL, "石油炼制与煤制品"),
    (3000, 3099, STAGE_MATERIAL, "橡胶与塑料制品"),
    (3100, 3199, STAGE_FINISHED, "皮革制品与鞋类"),
    (3200, 3299, STAGE_MATERIAL, "石料、陶土与玻璃制品"),
    # 33xx 必须拆开：331x-334x 是高炉、轧钢与有色冶炼精炼（材料加工）；
    # 335x-339x 是把金属加工成线材、板材、铸件（给下游装配用的元器件）。
    # 不拆的话康宁（SIC 3357 有色线材拉制）会被误判成资源开采——它做的是
    # 玻璃基板与光纤，是不折不扣的中间投入（实测用例）。
    (3300, 3349, STAGE_MATERIAL, "钢铁与有色金属冶炼精炼"),
    (3350, 3399, STAGE_COMPONENT, "金属轧制、拉制与铸造，供下游装配"),
    (3400, 3499, STAGE_COMPONENT, "金属制品"),
    # 35xx 主体是资本设备：工程机械、半导体设备、工业机械。
    # 整机与零部件已在 EXACT 里逐码拆出去。
    (3500, 3569, STAGE_EQUIPMENT, "工业机械与专用设备，下游的资本支出"),
    (3579, 3599, STAGE_EQUIPMENT, "办公与通用工业设备"),
    (3600, 3699, STAGE_COMPONENT, "电子与电气元器件，含半导体"),
    (3700, 3799, STAGE_COMPONENT, "运输设备零部件"),
    (3800, 3899, STAGE_FINISHED, "仪器仪表与医疗器械，多为可直接交付的成品"),
    (3900, 3999, STAGE_FINISHED, "其他制造业，多为终端产品"),
    (4000, 4299, STAGE_LOGISTICS, "铁路、公路货运与仓储"),
    (4300, 4399, STAGE_LOGISTICS, "邮政与快递"),
    (4400, 4499, STAGE_END_SERVICE, "水上运输，标普成分股中为邮轮与客运"),
    (4500, 4599, STAGE_LOGISTICS, "航空运输（客运见 EXACT 4512）"),
    (4600, 4699, STAGE_LOGISTICS, "管道运输"),
    (4700, 4799, STAGE_LOGISTICS, "运输服务与货代"),
    (4800, 4899, STAGE_TECHNOLOGY, "电信与网络承载"),
    # 49xx 拆开：电力燃气是投入品，废物处理是逆向供应链
    (4900, 4949, STAGE_ENERGY, "电力、燃气与水务，制造业的投入品"),
    (4950, 4959, STAGE_CIRCULAR, "废弃物处理与回收，逆向供应链"),
    (4960, 4999, STAGE_ENERGY, "综合公用事业"),
    (5000, 5199, STAGE_DISTRIBUTION, "批发贸易"),
    (5200, 5999, STAGE_DISTRIBUTION, "零售贸易"),
    (6000, 6799, STAGE_FINANCIAL, "金融、保险与房地产"),
    (7000, 7299, STAGE_END_SERVICE, "住宿与个人服务"),
    (7300, 7399, STAGE_TECHNOLOGY, "商业服务，含软件与数据处理"),
    (7400, 7499, STAGE_FINANCIAL, "商业与管理服务"),
    (7500, 7599, STAGE_END_SERVICE, "汽车修理与租赁"),
    (7600, 7799, STAGE_END_SERVICE, "维修服务"),
    (7800, 7899, STAGE_TECHNOLOGY, "影视与流媒体"),
    (7900, 7999, STAGE_END_SERVICE, "娱乐与休闲服务"),
    (8000, 8099, STAGE_END_SERVICE, "医疗服务，面向终端患者"),
    (8100, 8999, STAGE_FINANCIAL, "法律、工程、会计等专业服务"),
]


# ── SIC 两位大类 ──────────────────────────────────────────────────────
# SEC 自己的行业大类（Major Group）。用途是把一个价值链环节拆成看得见的构成：
# 「中间制造 142 家」说不出这 142 家是什么，拆开就是仪器仪表 39、半导体 31、
# 计算机与工业机械 32、化工制药 34。
#
# 这里只做**翻译**，不做归并、不新建分类——每家公司的 SIC 码来自 SEC 申报，
# 逐家可核验；把两位码换成中文名不改变任何归属。认不出的码返回 None，
# 页面显示原始码，不硬塞一个名字。
SIC_MAJOR: dict[str, tuple[str, str]] = {
    "01": ("种植业", "Agricultural Production - Crops"),
    "02": ("畜牧业", "Agricultural Production - Livestock"),
    "07": ("农业服务", "Agricultural Services"),
    "08": ("林业", "Forestry"),
    "09": ("渔猎", "Fishing, Hunting & Trapping"),
    "10": ("金属矿采选", "Metal Mining"),
    "13": ("石油与天然气开采", "Oil & Gas Extraction"),
    "14": ("非金属矿采选", "Nonmetallic Minerals Mining"),
    "15": ("房屋建筑承包", "Building Construction"),
    "16": ("重型工程建筑", "Heavy Construction"),
    "17": ("建筑专业承包", "Special Trade Contractors"),
    "20": ("食品与饮料", "Food & Kindred Products"),
    "21": ("烟草制品", "Tobacco Products"),
    "22": ("纺织", "Textile Mill Products"),
    "23": ("服装成衣", "Apparel"),
    "24": ("木材与木制品", "Lumber & Wood Products"),
    "25": ("家具", "Furniture & Fixtures"),
    "26": ("造纸与纸制品", "Paper & Allied Products"),
    "27": ("印刷与出版", "Printing & Publishing"),
    "28": ("化工与制药", "Chemicals & Allied Products"),
    "29": ("石油炼制", "Petroleum Refining"),
    "30": ("橡胶与塑料制品", "Rubber & Plastics"),
    "31": ("皮革制品", "Leather Products"),
    "32": ("非金属矿物制品", "Stone, Clay & Glass"),
    "33": ("金属冶炼与压延", "Primary Metal Industries"),
    "34": ("金属制品", "Fabricated Metal Products"),
    "35": ("机械与计算机设备", "Machinery & Computer Equipment"),
    "36": ("电子与电气设备", "Electronic & Electrical Equipment"),
    "37": ("运输设备", "Transportation Equipment"),
    "38": ("仪器仪表与医疗器械", "Instruments & Related Products"),
    "39": ("其他制造业", "Miscellaneous Manufacturing"),
    "40": ("铁路运输", "Railroad Transportation"),
    "41": ("公共交通", "Local & Suburban Transit"),
    "42": ("公路货运与仓储", "Motor Freight & Warehousing"),
    "44": ("水上运输", "Water Transportation"),
    "45": ("航空运输", "Transportation by Air"),
    "46": ("管道运输", "Pipelines"),
    "47": ("运输服务", "Transportation Services"),
    "48": ("通信", "Communications"),
    "49": ("电力燃气与水务", "Electric, Gas & Sanitary Services"),
    "50": ("批发·耐用品", "Wholesale Trade - Durable Goods"),
    "51": ("批发·非耐用品", "Wholesale Trade - Nondurable Goods"),
    "52": ("建材与家居零售", "Building Materials & Garden Supply"),
    "53": ("综合零售", "General Merchandise Stores"),
    "54": ("食品零售", "Food Stores"),
    "55": ("汽车经销与加油站", "Auto Dealers & Service Stations"),
    "56": ("服装零售", "Apparel & Accessory Stores"),
    "57": ("家居零售", "Home Furniture & Furnishings Stores"),
    "58": ("餐饮", "Eating & Drinking Places"),
    "59": ("其他零售", "Miscellaneous Retail"),
    "60": ("银行与存款机构", "Depository Institutions"),
    "61": ("非存款信贷机构", "Nondepository Credit Institutions"),
    "62": ("证券与商品经纪", "Security & Commodity Brokers"),
    "63": ("保险公司", "Insurance Carriers"),
    "64": ("保险代理与经纪", "Insurance Agents & Brokers"),
    "65": ("房地产", "Real Estate"),
    "67": ("控股与投资机构", "Holding & Other Investment Offices"),
    "70": ("住宿", "Hotels & Lodging"),
    "72": ("个人服务", "Personal Services"),
    "73": ("商业服务", "Business Services"),
    "75": ("汽车修理与租赁", "Auto Repair & Services"),
    "78": ("影视", "Motion Pictures"),
    "79": ("娱乐与休闲服务", "Amusement & Recreation Services"),
    "80": ("医疗服务", "Health Services"),
    "82": ("教育服务", "Educational Services"),
    "83": ("社会服务", "Social Services"),
    "87": ("工程、会计与研究服务", "Engineering & Management Services"),
    "99": ("未分类", "Nonclassifiable Establishments"),
}


def major_group(sic: int | str | None) -> dict | None:
    """两位大类。认不出就返回 None——页面显示原始码，不猜一个名字出来。"""
    if sic is None:
        return None
    text = str(sic).strip()
    if not text.isdigit():
        return None
    key = text.zfill(4)[:2]
    hit = SIC_MAJOR.get(key)
    if not hit:
        return None
    return {"code": key, "label": hit[0], "labelEn": hit[1]}


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
