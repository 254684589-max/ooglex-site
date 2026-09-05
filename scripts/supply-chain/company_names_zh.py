#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""在美上市外国私人发行人的中文名对照表。

## 只收「确有通用中文名」的，其余照旧显示英文原文

与 smelter_names_zh.py 同一条规矩：**给不出可靠译名的不进表**。
台积电、阿斯麦、诺和诺德这类在中文财经语境里有固定叫法，收；
Mayfair Gold、Trekor Metals 这类加拿大初级矿商没有通用中文名，
按字面直译出来的「梅费尔黄金」既不是它的注册名、也没人这么叫，
比直接显示英文原文更糟——它看着像个中文名，其实是编的。

**名字本身就是拉丁字母的也不收**（ARM、NICE、QIAGEN、Radware）：
它们在中文语境里就是这么写的，硬造一个音译反而不是它的名字。

## 为什么按 SEC 写的英文名做键

第一版按 CIK 做键，CIK 是我凭记忆写的——78 条里 46 条的编号是错的，
表里的英文名核对当场就把它们挡了下来（赛诺菲的编号写成了葛兰素史克的）。
**凭记忆写标识符就是在编数据**，哪怕看起来像个编号。

改成用 SEC 申报里的公司名做键：这 147 个字符串就在 foreign.json 里，
是照着数据抄的，不是想出来的。附带好处是公司改名（合并、重组）之后
键自动失配、退回显示英文原文——旧译名指认一家已经变了的公司，
同样是在说一件没有出处的事。
"""
from __future__ import annotations

# SEC 申报里写的公司名（原样） → 中文名
NAMES: dict[str, str] = {
    # ── 半导体与电子 ────────────────────────────────────────────────
    "TAIWAN SEMICONDUCTOR MANUFACTURING CO LTD": "台积电",
    "ASML HOLDING NV": "阿斯麦",
    "UNITED MICROELECTRONICS CORP": "联华电子",
    "ASE Technology Holding Co., Ltd.": "日月光投控",
    "STMicroelectronics N.V.": "意法半导体",
    "TOWER SEMICONDUCTOR LTD": "高塔半导体",
    "CHIPMOS TECHNOLOGIES INC": "南茂科技",
    "Himax Technologies, Inc.": "奇景光电",
    "Silicon Motion Technology CORP": "慧荣科技",
    "LG Display Co., Ltd.": "乐金显示",
    "KONINKLIJKE PHILIPS NV": "飞利浦",
    "Sony Group Corp": "索尼",

    # ── 通信 ────────────────────────────────────────────────────────
    "ERICSSON LM TELEPHONE CO": "爱立信",
    "NOKIA CORP": "诺基亚",
    "VODAFONE GROUP PUBLIC LTD CO": "沃达丰",
    "CHUNGHWA TELECOM CO LTD": "中华电信",

    # ── 汽车与机械 ──────────────────────────────────────────────────
    "HONDA MOTOR CO LTD": "本田",
    "TOYOTA MOTOR CORP/": "丰田",
    "Ferrari N.V.": "法拉利",
    "MAGNA INTERNATIONAL INC": "麦格纳",
    "EMBRAER S.A.": "巴西航空工业",

    # ── 医药与消费 ──────────────────────────────────────────────────
    "NOVO NORDISK A S": "诺和诺德",
    "GSK plc": "葛兰素史克",
    "Sanofi": "赛诺菲",
    "TAKEDA PHARMACEUTICAL CO LTD": "武田制药",
    "Fresenius Medical Care AG": "费森尤斯医疗",
    "SMITH & NEPHEW PLC": "施乐辉",
    "ALCON INC": "爱尔康",
    "British American Tobacco p.l.c.": "英美烟草",
    "Anheuser-Busch InBev SA/NV": "百威英博",
    "Alibaba Group Holding Ltd": "阿里巴巴",
    "Canada Goose Holdings Inc.": "加拿大鹅",
    "Birkenstock Holding plc": "勃肯",

    # ── 能源与化工 ──────────────────────────────────────────────────
    "BP PLC": "英国石油",
    "Shell plc": "壳牌",
    "TotalEnergies SE": "道达尔能源",
    "EQUINOR ASA": "挪威国家石油",
    "ENI SPA": "埃尼",
    "SASOL LTD": "萨索尔",
    "SUNCOR ENERGY INC": "森科能源",
    "CANADIAN NATURAL RESOURCES Ltd": "加拿大自然资源",

    # ── 采矿与金属 ──────────────────────────────────────────────────
    "RIO TINTO PLC": "力拓（英国）",
    "RIO TINTO LTD": "力拓（澳大利亚）",
    "BHP Group Ltd": "必和必拓",
    "BARRICK MINING CORP": "巴里克黄金",
    "AGNICO EAGLE MINES LTD": "艾格尼科鹰矿业",
    "AngloGold Ashanti PLC": "英美黄金阿散蒂",
    "HARMONY GOLD MINING CO LTD": "哈莫尼黄金",
    "PAN AMERICAN SILVER CORP": "泛美白银",
    "CAMECO CORP": "卡梅科",
    "TECK RESOURCES LTD": "泰克资源",
    "ArcelorMittal": "安赛乐米塔尔",
    "GERDAU S.A.": "盖尔道",
    "POSCO HOLDINGS INC.": "浦项控股",
    "TENARIS SA": "特纳瑞斯",
    "CEMEX SAB DE CV": "西麦斯",

    # ── 其他 ────────────────────────────────────────────────────────
    "ORIX CORP": "欧力士",
    "Canadian Solar Inc.": "阿特斯太阳能",
    "JinkoSolar Holding Co., Ltd.": "晶科能源",
    "CHINA YUCHAI INTERNATIONAL LTD": "中国玉柴",
    "ELBIT SYSTEMS LTD": "埃尔比特系统",
}


def name_for(english: str | None) -> str | None:
    """这家公司的中文名。表里没有就返回 None，页面照旧显示英文原文。"""
    if not english:
        return None
    return NAMES.get(english.strip()) or NAMES.get(english.strip().upper())
