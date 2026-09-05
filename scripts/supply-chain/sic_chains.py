#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""SIC 码 → 一级产业链。给这张图补上**横轴**。

## 为什么需要横轴

现在只有一根轴：12 个环节（原料 → 材料加工 → 零部件 → 资本设备 → 成品 →
物流 → 分销 → 终端服务，加四个使能层）。那根轴回答「这家公司在链上的哪一层」，
回答不了「它在**哪条链**上」。

结果是半导体设备和农机都落在「资本设备」这一格里，看上去像同一层的邻居，
其实一辈子不发生关系。**纵向分层而不分链，等于把所有产业揉成一条链。**

加上横轴之后是个二维模型：

        纵轴（12 环节）   这家公司在链上的哪一层    ← 已有
        横轴（27 条链）   它属于哪条产业链          ← 本模块
        细分（SIC 4 位码） 链内的具体环节            ← 已有，来自申报

ASML 既是「资本设备」层，又是「半导体」链——两个坐标都要有才定位得了。

## 这条线在哪

仓库的规矩是「无证据不上图」。分清两件事：

    公司之间的**关系**（谁供给谁）—— 必须有可核验的原始出处，一条都不能编
    公司的**分类**（属于哪条链）  —— 是定义，不是断言

本模块只做后者，而且只用一个输入：**公司向 SEC 申报的 SIC 码**。逐家可核验、
规则公开、任何人拿同一份码跑出同一个结果。

**不按公司名分派**。「我知道这家做 AI」不是依据——那是编。此前吃过一次亏：
按名字以为应用材料是半导体设备（资本设备层），它申报的 SIC 是 3674 半导体，
最后按申报码走。这里同一条规矩：表里只有码，没有公司。

一家公司可以在多条链上，这不是含糊，是事实：SIC 3533 油气田机械既在油气链
也在工业机械链，SIC 6324 医疗保险计划既在医疗链也在金融链。硬压成一条才是
失真。

## 这张表**不**声称什么

不声称链与链之间有传导关系，不声称同一条链上的两家公司之间有供应关系。
链是**筛子**，不是边。边只能来自申报文件。
"""
from __future__ import annotations

# ── 一级产业链 ────────────────────────────────────────────────────────────
# 按「从地下到终端」大致排序，便于页面上从左到右读。顺序不含任何传导含义。
CHAINS: list[tuple[str, str, str]] = [
    ("agri-food", "农业与食品", "Agriculture & Food"),
    ("mining-metals", "采矿与金属", "Mining & Metals"),
    ("oil-gas", "石油与天然气", "Oil & Gas"),
    ("utilities-power", "电力与公用事业", "Power & Utilities"),
    ("chemicals", "化工与新材料", "Chemicals & Materials"),
    ("packaging-paper", "包装与纸业", "Packaging & Paper"),
    ("construction-building", "建筑与建材", "Construction & Building"),
    ("semiconductor", "半导体", "Semiconductors"),
    ("electronics-components", "电子元器件", "Electronic Components"),
    ("computing-hardware", "计算与数据中心硬件", "Computing & Datacenter Hardware"),
    ("communications", "通信与网络", "Communications & Networking"),
    ("software-cloud", "软件与云服务", "Software & Cloud"),
    ("industrial-machinery", "工业机械与自动化", "Industrial Machinery"),
    ("automotive", "汽车", "Automotive"),
    ("aerospace-defense", "航空航天与国防", "Aerospace & Defense"),
    ("pharma-biotech", "医药与生物科技", "Pharma & Biotech"),
    ("medtech-health", "医疗器械与医疗服务", "Medtech & Health Services"),
    ("textiles-apparel", "纺织服装与鞋类", "Textiles & Apparel"),
    ("consumer-goods", "日用消费品", "Consumer Goods"),
    ("retail-distribution", "零售与分销", "Retail & Distribution"),
    ("logistics-transport", "物流与运输", "Logistics & Transportation"),
    ("travel-leisure", "旅游休闲与餐饮", "Travel, Leisure & Dining"),
    ("media-entertainment", "传媒与娱乐", "Media & Entertainment"),
    ("financial-services", "金融服务", "Financial Services"),
    ("real-estate", "房地产", "Real Estate"),
    ("business-services", "商业与专业服务", "Business & Professional Services"),
    ("waste-circular", "环保与循环经济", "Environmental & Circular"),
]

CHAIN_INDEX: dict[str, int] = {cid: i for i, (cid, _, _) in enumerate(CHAINS)}
CHAIN_ZH: dict[str, str] = {cid: zh for cid, zh, _ in CHAINS}
CHAIN_EN: dict[str, str] = {cid: en for cid, _, en in CHAINS}


# ── 4 位精确码 ────────────────────────────────────────────────────────────
# 只列**区间给不出正确答案**的码：要么区间会判错，要么这一码天然跨多条链。
# 精确码命中时**取代**区间结果（区间是兜底，精确是修正），不与区间求并。
EXACT: dict[int, tuple[tuple[str, ...], str]] = {
    # 化工里分出来的：日化面向终端消费，与工业化学品不是一条链
    2840: (("consumer-goods", "chemicals"), "肥皂洗涤与化妆品：配方来自化工，卖给消费者"),
    2842: (("consumer-goods", "chemicals"), "专用清洁用品"),
    2844: (("consumer-goods", "chemicals"), "香水与化妆品"),
    2870: (("chemicals", "agri-food"), "农用化学品：化肥农药是农业的投入品"),
    2111: (("consumer-goods",), "烟草制品按终端消费品处理，不并入食品链"),
    # 药与诊断
    2834: (("pharma-biotech",), "成药制剂"),
    2836: (("pharma-biotech",), "生物制品"),
    2835: (("medtech-health", "pharma-biotech"), "体外诊断试剂：既是药企产品也是医疗服务投入"),
    3826: (("medtech-health", "pharma-biotech"), "实验室分析仪器：药企与医院共同的上游"),
    8731: (("pharma-biotech", "business-services"), "商业化研究外包，主体是药物研发"),
    # 金属与建材
    1400: (("construction-building", "mining-metals"), "非金属矿采：砂石骨料主要供建筑"),
    3312: (("mining-metals", "construction-building"), "钢铁冶炼：建筑与制造共同的上游"),
    3357: (("communications", "electronics-components"),
           "绝缘导线与光纤拉制：光纤是通信骨干，不是采矿"),
    3411: (("packaging-paper",), "金属罐是包装，不是金属加工的终点"),
    # 机械里跨链的几码
    3523: (("industrial-machinery", "agri-food"), "农业机械"),
    3533: (("industrial-machinery", "oil-gas"), "油气田机械"),
    3559: (("semiconductor", "industrial-machinery"),
           "专用工业机械 NEC：半导体前道设备申报在这一码下"),
    3585: (("industrial-machinery", "construction-building"), "暖通空调与商用制冷"),
    3510: (("utilities-power", "industrial-machinery"), "发动机与涡轮：发电设备"),
    3621: (("utilities-power", "industrial-machinery"), "电机与发电机"),
    3743: (("logistics-transport", "industrial-machinery"), "铁路装备"),
    3730: (("logistics-transport", "aerospace-defense"),
           "船舶建造：民用船属运输装备，军船属国防，SIC 分不开，两条都挂"),
    3822: (("construction-building", "industrial-machinery"), "楼宇自控"),
    3825: (("electronics-components", "industrial-machinery"), "电学测量仪器"),
    3827: (("semiconductor", "communications"), "光学仪器与镜头：光刻与光通信共用"),
    3851: (("medtech-health", "consumer-goods"), "眼科用品"),
    # 电子与计算：整机、元件、通信设备在同一大类下，必须逐码分
    3576: (("computing-hardware", "communications"), "计算机通信设备"),
    3661: (("communications", "electronics-components"), "电话电报设备"),
    3663: (("communications", "electronics-components"), "广播电视与通信设备"),
    3669: (("communications", "electronics-components"), "通信设备 NEC"),
    3672: (("electronics-components", "semiconductor"), "印制电路板"),
    3674: (("semiconductor",), "半导体与相关器件"),
    # 公用事业与油气的重叠段
    4922: (("oil-gas", "utilities-power"), "天然气长输管道"),
    4923: (("oil-gas", "utilities-power"), "天然气输配"),
    4924: (("utilities-power", "oil-gas"), "天然气配售，直接面对终端"),
    4932: (("utilities-power", "oil-gas"), "燃气与综合公用事业"),
    4941: (("utilities-power",), "水务：与电力同属公用事业"),
    4991: (("utilities-power",), "热电联产与小型发电"),
    4953: (("waste-circular",), "废弃物处理"),
    1731: (("construction-building", "utilities-power"),
           "电气工程施工：电网与数据中心的建设方"),
    # 传媒、通信与娱乐
    4812: (("communications",), "无线通信"),
    4813: (("communications",), "固网通信"),
    4833: (("media-entertainment", "communications"), "电视广播"),
    4841: (("media-entertainment", "communications"), "有线电视"),
    7841: (("media-entertainment",), "影音租赁：流媒体申报在这一码下"),
    7311: (("business-services", "media-entertainment"), "广告代理"),
    # 交通：载客与载货不是一条链（此前踩过的坑，这里同样要分）
    4400: (("travel-leisure",), "水上运输：标普成分股中为邮轮"),
    4512: (("travel-leisure", "logistics-transport"), "定期航空：客运为主，腹舱带货"),
    4513: (("logistics-transport",), "航空快递"),
    4700: (("travel-leisure",), "旅行服务与在线旅游平台"),
    4731: (("logistics-transport",), "货运代理"),
    # 批发：既是分销，也属所供应的那条链
    5013: (("automotive", "retail-distribution"), "汽车配件批发"),
    5047: (("medtech-health", "retail-distribution"), "医疗器械批发"),
    5065: (("electronics-components", "retail-distribution"), "电子元件批发"),
    5122: (("pharma-biotech", "retail-distribution"), "药品批发"),
    5140: (("agri-food", "retail-distribution"), "食品批发"),
    5500: (("automotive", "retail-distribution"), "汽车经销与加油站"),
    5531: (("automotive", "retail-distribution"), "汽车用品零售"),
    5810: (("travel-leisure", "retail-distribution"), "餐饮"),
    5812: (("travel-leisure", "retail-distribution"), "餐饮"),
    5912: (("medtech-health", "retail-distribution"), "药店"),
    # 金融里跨链的
    6324: (("medtech-health", "financial-services"), "医疗保险计划：医疗支付方"),
    6792: (("oil-gas", "real-estate"), "油气矿区权益"),
    # REIT 同时落在「投资与控股」和「房地产投资信托」两条区间上，求并会让 26 家
    # REIT 既算金融又算地产。它是持有物业的载体，归地产——用精确码取代区间。
    6798: (("real-estate",), "房地产投资信托：持有物业的载体，归地产不归泛金融"),
    7320: (("financial-services", "business-services"), "征信与信用报告"),
    7359: (("industrial-machinery", "business-services"), "设备租赁"),
    # 服务大类里的软件
    7370: (("software-cloud",), "计算机编程与数据处理"),
    7371: (("software-cloud",), "软件开发服务"),
    7372: (("software-cloud",), "预打包软件"),
    7373: (("software-cloud",), "系统集成"),
    7374: (("software-cloud",), "数据处理与托管"),
    7389: (("business-services",), "商业服务 NEC：这一码本身就是杂项，不硬派链"),
}


# ── 4 位区间：兜底，保证每个码都有归属 ─────────────────────────────────────
# 区间可以重叠，命中多条就**求并**——一个码同时落在两条链上是常态。
RANGES: list[tuple[int, int, tuple[str, ...], str]] = [
    (100, 999, ("agri-food",), "农林牧渔"),
    (1000, 1099, ("mining-metals",), "金属矿开采"),
    (1200, 1299, ("mining-metals", "utilities-power"), "煤炭开采"),
    (1300, 1399, ("oil-gas",), "油气开采与油服"),
    (1400, 1499, ("mining-metals", "construction-building"), "非金属矿采"),
    (1500, 1799, ("construction-building",), "建筑施工与住宅开发"),
    (2000, 2199, ("agri-food",), "食品饮料"),
    (2200, 2299, ("textiles-apparel",), "纺织"),
    (2300, 2399, ("textiles-apparel",), "服装"),
    (2400, 2499, ("construction-building",), "木材加工"),
    (2500, 2599, ("consumer-goods",), "家具"),
    (2600, 2699, ("packaging-paper",), "造纸与纸制品"),
    (2700, 2799, ("media-entertainment",), "出版印刷"),
    (2800, 2899, ("chemicals",), "化学工业"),
    (2900, 2999, ("oil-gas", "chemicals"), "石油炼制与煤制品：炼化一体，两条链都在"),
    (3000, 3099, ("chemicals",), "橡胶与塑料制品"),
    (3100, 3199, ("textiles-apparel",), "皮革与鞋类"),
    (3200, 3299, ("construction-building",), "石料、陶土与玻璃"),
    (3300, 3399, ("mining-metals",), "金属冶炼与加工"),
    (3400, 3499, ("industrial-machinery",), "金属制品"),
    (3480, 3489, ("aerospace-defense",), "军械"),
    (3500, 3599, ("industrial-machinery",), "工业机械与设备"),
    (3570, 3579, ("computing-hardware",), "计算机与外围设备"),
    (3600, 3629, ("electronics-components",), "电气设备与元件"),
    (3630, 3639, ("consumer-goods",), "家用电器"),
    (3640, 3669, ("electronics-components",), "照明与通信设备"),
    (3670, 3699, ("electronics-components",), "电子元器件"),
    (3700, 3719, ("automotive",), "汽车整车"),
    (3714, 3716, ("automotive",), "汽车零部件"),
    (3720, 3729, ("aerospace-defense",), "航空器与发动机"),
    (3730, 3739, ("logistics-transport",), "船舶"),
    (3740, 3749, ("logistics-transport",), "铁路装备"),
    (3760, 3769, ("aerospace-defense",), "导弹与航天器"),
    (3790, 3799, ("consumer-goods",), "其他运输工具"),
    (3800, 3819, ("industrial-machinery",), "仪器仪表"),
    (3810, 3819, ("aerospace-defense",), "搜索、导航与航空系统"),
    (3820, 3839, ("industrial-machinery",), "测量与控制仪器"),
    (3840, 3849, ("medtech-health",), "医疗与外科器械"),
    (3850, 3859, ("medtech-health",), "眼科用品"),
    (3860, 3899, ("consumer-goods",), "摄影与钟表"),
    (3900, 3999, ("consumer-goods",), "其他制造业"),
    (4000, 4299, ("logistics-transport",), "铁路、公路货运与仓储"),
    (4300, 4399, ("logistics-transport",), "邮政快递"),
    (4400, 4499, ("logistics-transport",), "水上运输"),
    (4500, 4599, ("logistics-transport",), "航空运输"),
    (4600, 4699, ("oil-gas", "logistics-transport"), "管道运输"),
    (4700, 4799, ("logistics-transport",), "运输服务"),
    (4800, 4899, ("communications",), "通信业"),
    (4900, 4949, ("utilities-power",), "电力燃气水务"),
    (4950, 4959, ("waste-circular",), "废弃物处理"),
    (4960, 4999, ("utilities-power",), "综合公用事业"),
    (5000, 5199, ("retail-distribution",), "批发贸易"),
    (5200, 5999, ("retail-distribution",), "零售贸易"),
    (5800, 5819, ("travel-leisure",), "餐饮"),
    (6000, 6499, ("financial-services",), "银行、券商与保险"),
    (6500, 6599, ("real-estate",), "房地产经营"),
    (6600, 6799, ("financial-services",), "投资与控股"),
    (7000, 7099, ("travel-leisure",), "住宿"),
    (7200, 7299, ("consumer-goods",), "个人服务"),
    (7300, 7399, ("business-services",), "商业服务"),
    (7370, 7379, ("software-cloud",), "计算机服务"),
    (7400, 7599, ("business-services",), "商业与设备服务"),
    (7600, 7799, ("business-services",), "维修服务"),
    (7800, 7899, ("media-entertainment",), "影视"),
    (7900, 7999, ("travel-leisure",), "娱乐与休闲"),
    (8000, 8099, ("medtech-health",), "医疗服务"),
    (8100, 8199, ("business-services",), "法律服务"),
    (8200, 8299, ("business-services",), "教育服务"),
    (8300, 8399, ("business-services",), "社会服务"),
    (8400, 8699, ("travel-leisure",), "博物馆与团体组织"),
    (8700, 8799, ("business-services",), "工程、会计与管理服务"),
    (8800, 8999, ("business-services",), "其他服务"),
]


def _ordered(ids) -> list[str]:
    """按 CHAINS 的顺序去重排序，保证同一输入永远得到同一输出。"""
    seen = {c for c in ids if c in CHAIN_INDEX}
    return sorted(seen, key=lambda c: CHAIN_INDEX[c])


def resolve_chains(sic: int | str | None) -> dict | None:
    """SIC 码 → 一级产业链。认不出返回 None，**不硬塞一条链**。"""
    if sic is None or sic == "":
        return None
    try:
        code = int(str(sic).strip())
    except (TypeError, ValueError):
        return None
    if code in EXACT:
        ids, why = EXACT[code]
        return {"chains": _ordered(ids), "basis": "sic-exact", "note": why}
    hits: list[str] = []
    reasons: list[str] = []
    for low, high, ids, why in RANGES:
        if low <= code <= high:
            hits.extend(ids)
            reasons.append(why)
    if not hits:
        return None
    return {"chains": _ordered(hits), "basis": "sic-range", "note": "；".join(reasons)}
