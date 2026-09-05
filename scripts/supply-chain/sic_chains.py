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


# ── 链间上下游 ────────────────────────────────────────────────────────────
# 横轴回答「这家公司在哪条链上」，这张表回答「这条链的上游和下游是谁」。
#
# ## 这是框架，不是边
#
# 「半导体链的上游包含化工链」与「半导体属于零部件层」是同一类陈述：**产业结构
# 常识，是定义不是断言**，不指名任何两家公司，因此不需要逐条出处。它与 edges/
# 里那两万条**完全不同**——那些每一条都指名一家申报人与一家冶炼厂，都必须能点开
# 原始申报。两者在数据里分开存放（chainLinks vs edges）、在页面上分开显示、
# 在文案里分开说明，任何时候都不得混为一谈。
#
# ## 连线的两条规矩
#
# 一、**只连直接的一跳，且构成对方的主要投入。** 石油 → 化工 → 合成纤维 → 服装，
#     中间每一跳都连，但不从石油直接连到服装——那样连出来的是一张糊成一团的网，
#     读者反而看不出传导顺序。
# 二、**横跨全链的使能链不逐条连。** 金融、商业服务、物流、地产供给几乎所有链，
#     逐条连会画出 100 多条线且没有信息量。这几条标为 cross-cutting，页面上写明
#     「横跨全部产业链，未逐条连线」，而不是假装它们没有下游。
#
# 每条连线都要写清**流动的是什么**。只画一个箭头等于没说话：读者需要知道
# 化工给半导体的是电子气体与光刻胶，不是「某种化学品」。
CHAIN_LINKS: list[tuple[str, str, str]] = [
    # 采矿与金属：实物链的最上游，几乎所有制造业的起点
    ("mining-metals", "chemicals", "金属矿与冶炼产物是无机化工的原料"),
    ("mining-metals", "semiconductor", "高纯多晶硅、溅射靶材、稀有金属"),
    ("mining-metals", "electronics-components", "铜、金、锡——导电与焊接金属"),
    ("mining-metals", "construction-building", "钢材与建筑用金属制品"),
    ("mining-metals", "automotive", "车身钢板与铝合金"),
    ("mining-metals", "industrial-machinery", "结构件、传动件与刀具材料"),
    ("mining-metals", "packaging-paper", "金属罐用铝材与马口铁"),
    ("mining-metals", "aerospace-defense", "钛合金与高温合金"),
    # 石油与天然气
    ("oil-gas", "chemicals", "石脑油与天然气是石化的起点"),
    ("oil-gas", "utilities-power", "燃气与燃料油发电"),
    ("oil-gas", "logistics-transport", "运输燃料"),
    ("oil-gas", "construction-building", "沥青与建筑防水材料"),
    # 农业与食品
    ("agri-food", "consumer-goods", "食用油脂、糖、香料等日化与食品原料"),
    ("agri-food", "textiles-apparel", "棉、毛与皮革"),
    ("agri-food", "retail-distribution", "食品饮料进入商超与餐饮渠道"),
    # 化工与新材料：制造业的通用投入品
    ("chemicals", "semiconductor", "电子特气、光刻胶、CMP 抛光液、湿电子化学品"),
    ("chemicals", "electronics-components", "环氧树脂、覆铜板材料、导电胶"),
    ("chemicals", "pharma-biotech", "原料药中间体与试剂"),
    ("chemicals", "textiles-apparel", "涤纶、锦纶等合成纤维与染料"),
    ("chemicals", "packaging-paper", "聚乙烯、聚丙烯等包装用树脂"),
    ("chemicals", "construction-building", "涂料、粘合剂与混凝土外加剂"),
    ("chemicals", "automotive", "轮胎橡胶、内饰塑料与电池材料"),
    ("chemicals", "agri-food", "化肥与农药"),
    ("chemicals", "consumer-goods", "洗涤与化妆品配方原料"),
    # 电力与公用事业：不是所有链都逐条连，只连电力构成主要成本的那几条
    ("utilities-power", "semiconductor", "晶圆厂是连续运行的用电大户"),
    ("utilities-power", "computing-hardware", "数据中心的电力与冷却"),
    ("utilities-power", "mining-metals", "电解铝与电炉炼钢的电耗"),
    ("utilities-power", "chemicals", "电解与蒸汽供热"),
    # 建筑与建材
    ("construction-building", "real-estate", "建成的物业与基础设施"),
    ("construction-building", "utilities-power", "电厂、电网与输配电工程"),
    ("construction-building", "computing-hardware", "数据中心厂房与配电工程"),
    # 工业机械与自动化：各链的资本设备来源
    ("industrial-machinery", "semiconductor", "光刻、刻蚀、沉积、量测与封测设备"),
    ("industrial-machinery", "automotive", "冲压、焊装、涂装与总装产线"),
    ("industrial-machinery", "agri-food", "农业机械与食品加工设备"),
    ("industrial-machinery", "chemicals", "反应器、泵阀与分离设备"),
    ("industrial-machinery", "mining-metals", "采矿、破碎与冶炼设备"),
    ("industrial-machinery", "construction-building", "工程机械"),
    ("industrial-machinery", "packaging-paper", "造纸机与包装机械"),
    ("industrial-machinery", "pharma-biotech", "制药设备与洁净车间系统"),
    # 半导体：现代制造业的公共中间品
    ("semiconductor", "computing-hardware", "处理器、存储、加速卡"),
    ("semiconductor", "communications", "基带、射频与光通信芯片"),
    ("semiconductor", "automotive", "车规 MCU、功率器件与传感器"),
    ("semiconductor", "industrial-machinery", "工业控制与驱动芯片"),
    ("semiconductor", "medtech-health", "医学影像与监护设备的芯片"),
    ("semiconductor", "consumer-goods", "家电与消费电子芯片"),
    ("semiconductor", "aerospace-defense", "航天级与抗辐照器件"),
    # 电子元器件
    ("electronics-components", "computing-hardware", "电路板、连接器、被动元件"),
    ("electronics-components", "communications", "通信设备的元件与模块"),
    ("electronics-components", "automotive", "线束、连接器与电子模块"),
    ("electronics-components", "medtech-health", "医疗电子的元件"),
    ("electronics-components", "aerospace-defense", "机载与星载电子元件"),
    # 计算硬件与通信
    ("computing-hardware", "software-cloud", "服务器与存储是云与 AI 算力的载体"),
    ("computing-hardware", "communications", "网络设备与交换硬件"),
    ("communications", "software-cloud", "承载网络与带宽"),
    ("communications", "media-entertainment", "内容分发的传输通道"),
    ("software-cloud", "media-entertainment", "流媒体与内容平台的技术底座"),
    ("software-cloud", "financial-services", "支付、清算与风控系统"),
    # 制成品向终端
    ("automotive", "retail-distribution", "整车经销与售后配件"),
    ("automotive", "logistics-transport", "商用车构成公路运力"),
    ("aerospace-defense", "logistics-transport", "货机与航空货运运力"),
    ("aerospace-defense", "travel-leisure", "民航客机"),
    ("pharma-biotech", "medtech-health", "药品进入诊疗环节"),
    ("pharma-biotech", "retail-distribution", "药品批发与药店"),
    ("medtech-health", "retail-distribution", "器械与耗材的分销"),
    ("textiles-apparel", "retail-distribution", "成衣与鞋类进入零售"),
    ("consumer-goods", "retail-distribution", "日用品进入商超与电商"),
    ("packaging-paper", "agri-food", "食品饮料包装"),
    ("packaging-paper", "consumer-goods", "日用品包装"),
    ("packaging-paper", "pharma-biotech", "药品包装"),
    ("retail-distribution", "travel-leisure", "餐饮与门店消费"),
    # 逆向：SCOR 模型的 Return。缺这一段整个框架就是单向的，
    # 而实物链本来是**闭环**：消费后的废弃物回到冶炼与制浆，再变成新料。
    # 进环保链的几条（谁产生废弃物）与出环保链的几条（再生料去哪）都要有，
    # 只画一半就等于说回收出来的东西凭空产生。
    ("retail-distribution", "waste-circular", "消费后的包装与产品废弃物"),
    ("computing-hardware", "waste-circular", "退役服务器与电子废弃物"),
    ("automotive", "waste-circular", "报废汽车拆解"),
    ("construction-building", "waste-circular", "建筑与拆除垃圾"),
    ("waste-circular", "mining-metals", "再生金属回炉，与原生矿并行供料"),
    ("waste-circular", "chemicals", "再生塑料与化学回收原料"),
    ("waste-circular", "packaging-paper", "废纸回收再制浆"),
]

# 逆向边：与所在环的主流向相反的那一条。分层要有拓扑序，有环就没有拓扑序，
# 所以每个环都得剪开一刀——**剪哪一条是语义问题，不是图论问题**，在这里写死。
#
# 第一版让深度优先自己按遍历顺序找回边，它把「采矿 → 化工」剪了，于是采矿被排到
# 第 5 层、排在半导体下面，整条链倒过来。拓扑上没错，语义上荒唐。
# 谁供给谁我知道，就该由我写出来，并且写清为什么剪这一条。
#
# 剪完还有环就报错，不给层次——第一版正是靠「悄悄给个错的层次」算出 241 层的，
# 而下面第三条环（采矿→化工→建筑→电力→采矿）就是报错逼出来的：
# 四条边全是真的，我起初没看见它们首尾相接。
COUNTERFLOW: dict[tuple[str, str], str] = {
    # 回收环：SCOR 模型的 Return，再生料逆着物料流回到上游
    ("waste-circular", "mining-metals"): "再生金属返回冶炼，与原生矿并行",
    ("waste-circular", "chemicals"): "再生塑料返回化工",
    ("waste-circular", "packaging-paper"): "废纸返回制浆",
    # 设备环：设备厂供给半导体，半导体又供给设备厂的控制系统。主流向是设备在上游。
    ("semiconductor", "industrial-machinery"): "工业控制芯片回流到设备厂——与「设备→半导体」互为供给",
    # 资本形成环：采矿→化工→建筑→电力→采矿。电力是持续外供的投入品，
    # 而「建电厂电网」是一次性资本形成，方向与电力外供相反，剪这一条。
    ("construction-building", "utilities-power"): "建电厂与电网是资本形成，方向与电力持续外供相反",
    ("industrial-machinery", "mining-metals"): "采矿冶炼设备是资本投入，方向与矿料持续外供相反",
}

# 横跨全部产业链的使能链：不逐条连，但要说明它横跨，而不是假装它没有下游。
CROSS_CUTTING: dict[str, str] = {
    "financial-services": "资金、保险与支付横跨全部产业链，不逐条连线",
    "real-estate": "厂房、仓储与办公物业横跨全部产业链，不逐条连线",
    "business-services": "咨询、人力、检测与认证横跨全部产业链，不逐条连线",
    "logistics-transport": "运输与仓储衔接每一段实物流转，不逐条连线",
}


def chain_links() -> list[dict]:
    """链间上下游，规范化成可直接写进 nodes.json 的形状。

    每条带 basis="framework"：这是**产业结构框架**，与 edges/ 里那两万条
    必须有原始申报的公司级关系不是一回事，任何时候都不得混在一起。
    """
    out = []
    for src, dst, flow in CHAIN_LINKS:
        if src not in CHAIN_INDEX or dst not in CHAIN_INDEX:
            continue                       # 写错 id 的连线直接丢掉，不让它变成幽灵节点
        out.append({"from": src, "to": dst, "flow": flow, "basis": "framework",
                    "direction": "counterflow" if (src, dst) in COUNTERFLOW else "forward",
                    "counterflowWhy": COUNTERFLOW.get((src, dst))})
    return out


def upstream_of(chain_id: str) -> list[dict]:
    """谁供给这条链。"""
    return [l for l in chain_links() if l["to"] == chain_id]


def downstream_of(chain_id: str) -> list[dict]:
    """这条链供给谁。"""
    return [l for l in chain_links() if l["from"] == chain_id]


# ── 链的层次：从连线里算出来，不手工指定 ──────────────────────────────────
# 要的是「一进页面就看得出谁在上游、谁在下游」。层次**不手工排**——手排的话
# 我一改连线，层次就和连线对不上，而且没人看得出对不上。改为从 CHAIN_LINKS 算。
#
# ## 第一版是错的，靠打印结果发现
#
# 第一版直接对全图做最长路径松弛，结果是 **241 层、30 条边被判成回流**：
# 实物链有回路（采矿 → 化工 → … → 环保 → 采矿），松弛在环里一圈圈往上顶，
# 顶到迭代上限为止。层数比链数还多十倍，一眼就知道不对。
#
# ## 正确的做法：先断环，再分层
#
# 深度优先遍历，指向**当前还在栈上**的节点的边就是回边（back edge）——
# 那正是环的入口。把回边拿掉，剩下的是有向无环图，再做最长路径就收敛了。
# 回边不是错误，是实物链本来的形态：SCOR 模型的 Return 段，回收料返回上游。
#
# 遍历顺序固定（先入度为 0 的源头，再按链表顺序），所以同一份连线永远算出
# 同一个结果——层次是数据的函数，不是运行顺序的函数。
def _has_cycle(flow: list[tuple[str, str]], order: list[str]) -> list[str] | None:
    """剪掉回流边之后还有没有环。有就说明连线表自相矛盾，要人来看，不能糊过去。

    返回环上的节点序列（供报错时打印），没有环返回 None。
    """
    adj: dict[str, list[str]] = {}
    for src, dst in flow:
        adj.setdefault(src, []).append(dst)
    state: dict[str, int] = {}
    stack: list[str] = []

    def visit(node: str) -> list[str] | None:
        state[node] = 1
        stack.append(node)
        for nxt in adj.get(node, ()):
            if state.get(nxt) == 1:
                return stack[stack.index(nxt):] + [nxt]
            if nxt not in state:
                found = visit(nxt)
                if found:
                    return found
        state[node] = 2
        stack.pop()
        return None

    for node in order:
        if node not in state:
            found = visit(node)
            if found:
                return found
    return None


def chain_layers() -> dict:
    """算出每条链的层次，并带上回流边。

    返回 {"layer": {链: 层号}, "back": [[from, to], ...], "depth": 层数}。
    横跨全链的使能链不参与分层——它们没有固定位置，硬塞进某一层是假的。
    """
    order = [cid for cid, _, _ in CHAINS if cid not in CROSS_CUTTING]
    flow = [(s, d) for s, d, _ in CHAIN_LINKS
            if s not in CROSS_CUTTING and d not in CROSS_CUTTING]
    back = [(s, d) for s, d in flow if (s, d) in COUNTERFLOW]
    dag = [(s, d) for s, d in flow if (s, d) not in COUNTERFLOW]

    cycle = _has_cycle(dag, order)
    if cycle:
        # 悄悄给个错的层次比报错糟得多：第一版就是这么算出 241 层的。
        raise RuntimeError("剪掉逆向边后仍有环，层次算不出来（把这个环里方向与主流向"
                           "相反的那条加进 COUNTERFLOW，并写清为什么）："
                           + " → ".join(CHAIN_ZH.get(c, c) for c in cycle))

    layer = {cid: 0 for cid in order}
    for _ in range(len(order) + 1):
        moved = False
        for src, dst in dag:
            if layer[dst] < layer[src] + 1:
                layer[dst] = layer[src] + 1
                moved = True
        if not moved:
            break

    return {"layer": layer,
            "back": sorted([list(e) for e in back]),
            "depth": (max(layer.values()) + 1) if layer else 0}
