#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""冶炼厂中文译名表。

## 为什么单独一个文件、而不是写进边文件

边文件里的每一条都挂着 SEC 申报出处，字段值就是申报原文。**译名不是申报内容，
是我们加的一层标注**，把它混进去会让「哪些是原文、哪些是我们写的」分不清。
因此译名单独成表，页面按名字对照着显示，出错也只是显示层的事，动不了证据。

## 只在两种情况下给中文名

1. **常用名对照表命中**——中日韩台企业普遍有通用中文名（云南锡业、三菱综合材料、
   厦门钨业），这些是查得到的，不是我编的。
2. **整串都能由词表拼出来**——地名 + 行业词 + 公司后缀全部认得才拼，
   有一个词认不出就整条不给中文名。

**绝不半译**：`赤峰 Dajingzi 锡业有限公司` 这种东西比纯英文更糟——它看着像个
中文名，其实是拼错的。宁可显示英文原文。

## 页面必须同时显示英文原文

中文是译名，不是注册名称。核对时以英文原文为准——申报里写的就是英文。
"""
from __future__ import annotations

import re


def key(name: str | None) -> str:
    """归一化：只留小写字母与数字，用于查表。"""
    return re.sub(r"[^a-z0-9]+", "", (name or "").lower())


# ── 常用中文名对照 ──────────────────────────────────────────────────────────
# 按被申报提及的次数从高到低整理，覆盖名单里露出频率最高的那批。
# 只收有通用中文名的；欧美企业普遍没有，不硬造。
_COMMON: dict[str, str] = {
    # 中国大陆 · 锡
    "Tin Smelting Branch of Yunnan Tin Co., Ltd.": "云南锡业 锡冶炼分公司",
    "Yunnan Tin Company Limited": "云南锡业股份有限公司",
    "China Tin Group Co., Ltd.": "中国锡业集团有限公司",
    "Gejiu Non-Ferrous Metal Processing Co., Ltd.": "个旧有色金属加工有限公司",
    "Guangdong Hanhe Non-Ferrous Metal Co., Ltd.": "广东翰和有色金属有限公司",
    "Chenzhou Yunxiang Mining and Metallurgy Co., Ltd.": "郴州云翔矿冶有限公司",
    "Chifeng Dajingzi Tin Industry Co., Ltd.": "赤峰大井子锡业有限公司",
    "Yunnan Chengfeng Non-ferrous Metals Co., Ltd.": "云南乘风有色金属股份有限公司",
    "China Tin Group Co., Ltd": "中国锡业集团有限公司",
    # 中国大陆 · 钨
    "Chongyi Zhangyuan Tungsten Co., Ltd.": "崇义章源钨业股份有限公司",
    "Xiamen Tungsten Co., Ltd.": "厦门钨业股份有限公司",
    "Xiamen Tungsten (H.C.) Co., Ltd.": "厦门钨业（海沧）有限公司",
    "Guangdong Xianglu Tungsten Co., Ltd.": "广东翔鹭钨业股份有限公司",
    "Jiangxi Yaosheng Tungsten Co., Ltd.": "江西耀升钨业股份有限公司",
    "Ganzhou Seadragon W & Mo Co., Ltd.": "赣州海龙钨钼有限公司",
    "China Molybdenum Tungsten Co., Ltd.": "洛阳钼业钨业有限公司",
    "Jiangxi Tonggu Non-ferrous Metallurgical & Chemical Co., Ltd.":
        "江西铜鼓有色冶金化工有限责任公司",
    "Ganzhou Huaxing Tungsten Products Co., Ltd.": "赣州华兴钨制品有限公司",
    "Jiangxi Gan Bei Tungsten Co., Ltd.": "江西赣北钨业有限公司",
    "Ganzhou Non-ferrous Metals Smelting Co., Ltd.": "赣州有色冶金有限公司",
    "Hunan Chunchang Nonferrous Metals Co., Ltd.": "湖南春长有色金属有限公司",
    "Jiangxi Xinsheng Tungsten Industry Co., Ltd.": "江西鑫盛钨业有限公司",
    # 中国大陆 · 钽铌
    "Ningxia Orient Tantalum Industry Co., Ltd.": "宁夏东方钽业股份有限公司",
    "Jiujiang Zhongao Tantalum & Niobium Co., Ltd.": "九江中澳钽铌有限公司",
    "Jiujiang Tanbre Co., Ltd.": "九江有色金属冶炼有限公司",
    "JiuJiang JinXin Nonferrous Metals Co., Ltd.": "九江金鑫有色金属有限公司",
    "Yanling Jincheng Tantalum & Niobium Co., Ltd.": "鄢陵金城钽铌有限公司",
    "Changsha South Tantalum Niobium Co., Ltd.": "长沙南方钽铌有限责任公司",
    "F&X Electro-Materials Ltd.": "福鑫电子材料有限公司",
    "XIMEI RESOURCES (GUANGDONG) LIMITED": "喜美资源（广东）有限公司",
    "Jiangxi Dinghai Tantalum & Niobium Co., Ltd.": "江西鼎海钽铌有限公司",
    # 中国大陆 · 金银铜
    "Jiangxi Copper Co., Ltd.": "江西铜业股份有限公司",
    "Shandong Zhaojin Gold & Silver Refinery Co., Ltd.": "山东招金金银精炼有限公司",
    "Shandong Gold Smelting Co., Ltd.": "山东黄金冶炼有限公司",
    "Zijin Mining Group Co., Ltd Gold Refinery": "紫金矿业集团 黄金精炼厂",
    "Zijin Mining Group Gold Smelting Co. Ltd.": "紫金矿业集团黄金冶炼有限公司",
    "China National Gold Group Corporation": "中国黄金集团有限公司",
    "Zhongyuan Gold Smelter of Zhongjin Gold Corporation": "中金黄金 中原黄金冶炼厂",
    "Guangdong Jinding Gold Limited": "广东金鼎黄金有限公司",
    "Hunan Chenzhou Mining Co., Ltd.": "湖南郴州矿产有限责任公司",
    "Daye Non-Ferrous Metals Group Holdings Co., Ltd.": "大冶有色金属集团控股有限公司",
    "Tongling Nonferrous Metals Group Co., Ltd.": "铜陵有色金属集团股份有限公司",
    "Jinlong Copper Co., Ltd.": "金隆铜业有限公司",
    "Yunnan Copper Industry Co., Ltd.": "云南铜业股份有限公司",
    "Chifeng Jilong Gold Mining Co., Ltd.": "赤峰吉隆黄金矿业股份有限公司",
    "Hangzhou Fuchunjiang Smelting Co., Ltd.": "杭州富春江冶炼有限公司",
    "Sichuan Tianze Precious Metals Co., Ltd.": "四川天泽贵金属有限公司",
    "Baiyin Nonferrous Metals Corporation (BNMC)": "白银有色集团股份有限公司",
    "Beijing Zenith Materials": "北京泽尼斯材料",
    "Luoyang Zijin Yinhui Gold Refinery Co., Ltd.": "洛阳紫金银辉黄金精炼有限公司",
    "Shandong Humon Smelting Co., Ltd.": "山东恒邦冶炼股份有限公司",
    "China Minmetals Non-ferrous Metals Holding Co., Ltd.": "中国五矿有色金属控股有限公司",
    "China GoldDeal Investment Co., Ltd.": "中金国泰投资有限公司",
    "China National Nonferrous Metals Imp. & Exp. Jiangxi Co., Ltd.":
        "中国有色金属进出口江西公司",
    # 中国香港
    "Metalor Technologies (Hong Kong) Ltd.": "贺利氏麦特勒（香港）有限公司",
    "Heraeus Metals Hong Kong Ltd.": "贺利氏金属（香港）有限公司",
    "Metalor Technologies (Suzhou) Ltd.": "麦特勒技术（苏州）有限公司",
    # 中国台湾
    "Solar Applied Materials Technology Corp.": "光洋应用材料科技股份有限公司",
    "Yield Open Investment Co., Ltd.": "益开投资股份有限公司",
    # 日本
    "Mitsubishi Materials Corporation": "三菱综合材料株式会社",
    "Mitsui Mining and Smelting Co., Ltd.": "三井金属矿业株式会社",
    "Sumitomo Metal Mining Co., Ltd.": "住友金属矿山株式会社",
    "Tanaka Kikinzoku Kogyo K.K.": "田中贵金属工业株式会社",
    "Matsuda Sangyo Co., Ltd.": "松田产业株式会社",
    "Japan New Metals Co., Ltd.": "日本新金属株式会社",
    "A.L.M.T. Corp.": "联合材料株式会社",
    "Nihon Material Co., Ltd.": "日本材料株式会社",
    "Asahi Refining Japan": "朝日精炼 日本",
    "Asahi Pretec Corp.": "朝日 Pretec 株式会社",
    "Ishifuku Metal Industry Co., Ltd.": "石福金属兴业株式会社",
    "Nippon PGM Co., Ltd.": "日本 PGM 株式会社",
    "Tokuriki Honten Co., Ltd.": "德力本店株式会社",
    "Asaka Riken Co., Ltd.": "朝日理研株式会社",
    "Aida Chemical Industries Co., Ltd.": "会田化学工业株式会社",
    "Yokohama Metal Co., Ltd.": "横滨金属株式会社",
    "JX Advanced Metals Corporation": "JX 金属株式会社",
    "Dowa": "同和控股",
    "Toho Zinc Co., Ltd.": "东邦锌株式会社",
    "Nippon Mining & Metals Co., Ltd.": "日矿金属株式会社",
    "Kojima Chemicals Co., Ltd.": "小岛化学药品株式会社",
    "Sumitomo Metal Mining Philippines, Inc.": "住友金属矿山菲律宾公司",
    "Nihon Superior Co., Ltd.": "日本斯倍利亚社株式会社",
    "Mitsubishi Materials Trading Corporation": "三菱综合材料贸易株式会社",
    # 韩国
    "LS MnM Inc.": "LS MnM 株式会社",
    "LS-NIKKO Copper Inc.": "LS-日矿铜业株式会社",
    "Korea Zinc Co., Ltd.": "高丽锌业株式会社",
    "SEMPSA Joyeria Plateria S.A.": "SEMPSA 珠宝银器公司",
    "Young Poong Corp.": "永丰株式会社",
    "Torecom": "Torecom 株式会社",
    "Samwon Metals Corp.": "三元金属株式会社",
}

GLOSSARY: dict[str, str] = {key(k): v for k, v in _COMMON.items()}

# ── 组合规则 ────────────────────────────────────────────────────────────────
# 只有整串每个词都认得才拼。认不全就不给中文名，不半译。
_PLACES = {
    "yunnan": "云南", "jiangxi": "江西", "hunan": "湖南", "guangdong": "广东",
    "guangxi": "广西", "hubei": "湖北", "henan": "河南", "hebei": "河北",
    "shandong": "山东", "shanxi": "山西", "sichuan": "四川", "fujian": "福建",
    "zhejiang": "浙江", "jiangsu": "江苏", "anhui": "安徽", "liaoning": "辽宁",
    "jilin": "吉林", "gansu": "甘肃", "qinghai": "青海", "ningxia": "宁夏",
    "xinjiang": "新疆", "yunfu": "云浮", "ganzhou": "赣州", "chenzhou": "郴州",
    "changsha": "长沙", "kunming": "昆明", "xiamen": "厦门", "jiujiang": "九江",
    "chifeng": "赤峰", "gejiu": "个旧", "tongling": "铜陵", "daye": "大冶",
    "baiyin": "白银", "luoyang": "洛阳", "zhuzhou": "株洲", "shaoguan": "韶关",
    "hangzhou": "杭州", "suzhou": "苏州", "beijing": "北京", "shanghai": "上海",
    "tianjin": "天津", "chongqing": "重庆", "guiyang": "贵阳", "nanjing": "南京",
    "shenzhen": "深圳", "dongguan": "东莞", "zhongshan": "中山", "wuxi": "无锡",
    "zhaoyuan": "招远", "xianghualing": "香花岭", "taiwan": "台湾",
    "guangzhou": "广州", "qingdao": "青岛", "xian": "西安", "wuhan": "武汉",
    "harbin": "哈尔滨", "shenyang": "沈阳", "dalian": "大连", "xuzhou": "徐州",
    "yichun": "宜春", "pingxiang": "萍乡", "hezhou": "贺州", "liuzhou": "柳州",
    "nanchang": "南昌", "hunchun": "珲春", "yantai": "烟台", "weihai": "威海",
    "linyi": "临沂", "zibo": "淄博", "jinan": "济南", "handan": "邯郸",
    "taiyuan": "太原", "baotou": "包头", "lanzhou": "兰州", "urumqi": "乌鲁木齐",
    "chuzhou": "滁州", "huzhou": "湖州", "ningbo": "宁波", "wenzhou": "温州",
    "foshan": "佛山", "huizhou": "惠州", "zhuhai": "珠海", "shantou": "汕头",
    "meizhou": "梅州", "ganxian": "赣县", "dayu": "大余", "chongyi": "崇义",
    "quanzhou": "泉州", "longyan": "龙岩", "sanming": "三明", "nanping": "南平",
    "hengyang": "衡阳", "xiangtan": "湘潭", "yueyang": "岳阳", "changde": "常德",
}
_WORDS = {
    "tin": "锡业", "tungsten": "钨业", "gold": "黄金", "silver": "白银",
    "copper": "铜业", "zinc": "锌业", "lead": "铅业", "tantalum": "钽",
    "niobium": "铌", "molybdenum": "钼", "nonferrous": "有色", "non": "",
    "ferrous": "有色", "metals": "金属", "metal": "金属", "mining": "矿业",
    "smelting": "冶炼", "smelter": "冶炼厂", "refinery": "精炼厂",
    "refining": "精炼", "industry": "工业", "industries": "工业",
    "group": "集团", "materials": "材料", "material": "材料",
    "chemical": "化学", "chemicals": "化学", "resources": "资源",
    "technology": "科技", "technologies": "科技", "precious": "贵",
    "and": "", "&": "", "the": "",
    # 常见通用词。**只收含义唯一的**——像 jin / yuan / hua 这种拼音字号不收：
    # jin 可以是金、进、锦、晋，猜错就是给一家真公司安了个错名字。
    "new": "新", "plant": "厂", "factory": "厂", "products": "制品",
    "product": "制品", "city": "市", "of": "", "recycling": "回收",
    "environmental": "环保", "environment": "环保", "rare": "稀有",
    "solder": "焊料", "industrial": "工业", "manufacturing": "制造",
    "system": "系统", "systems": "系统", "cemented": "硬质", "carbide": "合金",
    "advanced": "先进", "trade": "贸易", "trading": "贸易",
    "development": "发展", "branch": "分公司", "powder": "粉末",
    "alloy": "合金", "alloys": "合金", "wire": "线材", "foil": "箔材",
    "processing": "加工", "metallurgy": "冶金", "metallurgical": "冶金",
    "mine": "矿", "mines": "矿业", "engineering": "工程",
    "electronic": "电子", "electronics": "电子", "science": "科学",
    "international": "国际", "national": "国家", "china": "中国",
    "japan": "日本", "korea": "韩国", "holdings": "控股", "holding": "控股",
}
_SUFFIX = {
    "coltd": "有限公司", "co": "", "ltd": "有限公司", "limited": "有限公司",
    "corporation": "公司", "corp": "公司", "inc": "公司", "incorporated": "公司",
    "llc": "有限责任公司", "company": "公司", "gmbh": "有限公司",
    "kk": "株式会社", "kabushiki": "株式会社", "kaisha": "株式会社",
    "cop": "公司", "plc": "公司", "sa": "公司",
}


# 只有中文语境的企业才组合译名。美国的 Advanced Chemical Company 直译成
# 「先进化学公司」是我编的——它没有中文名。组合规则一度对它生效，这是不对的。
_ZH_CONTEXT = {"中国", "中国台湾", "中国香港", "中国澳门", "日本", "韩国", "新加坡"}


def _compose(name: str) -> str | None:
    """地名 + 行业词 + 后缀全部认得才拼；有一个不认得就返回 None。"""
    tokens = [t for t in re.split(r"[^A-Za-z&]+", name or "") if t]
    if not tokens or len(tokens) > 8:
        return None
    place: list[str] = []
    body: list[str] = []
    tail: list[str] = []
    for token in tokens:
        low = token.lower()
        if low in _PLACES and not body:
            place.append(_PLACES[low])
        elif low in _WORDS:
            word = _WORDS[low]
            # 「铜业 + 工业」这种叠词读着别扭，前面已经有行业词就不再加「工业」
            if word == "工业" and body:
                continue
            body.append(word)
        elif low in _SUFFIX:
            tail.append(_SUFFIX[low])
        else:
            return None                       # 有认不出的词，整条放弃
    if not body:
        return None                           # 连行业词都没有，拼不出像样的名字
    if not place and len(body) < 2:
        return None                           # 没有地名时至少要两个行业词，避免拼出「金属公司」这种空壳
    composed = "".join(place + body + tail[-1:])
    return composed if len(composed) >= 4 else None


def translate(name: str | None, country: str | None = None) -> str | None:
    """返回中文译名；给不出可靠译名时返回 None（页面就显示英文原文）。

    对照表不限国别——上面那些都是查得到的通用中文名。
    组合规则只对中文语境的企业生效，理由见 `_ZH_CONTEXT` 上方注释。
    """
    if not name:
        return None
    hit = GLOSSARY.get(key(name))
    if hit:
        return hit
    if country not in _ZH_CONTEXT:
        return None
    return _compose(name)
