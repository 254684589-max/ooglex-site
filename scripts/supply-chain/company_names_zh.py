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

    # ── 在美上市的中国内地／港澳台公司 ─────────────────────────────────
    # 这一批**不是翻译，是公司自己的注册中文名**。SEC 只存英文法定名称
    # （2026-09-06 探针实测：25 家抽样 0 家元数据带中文），所以只能逐家人工
    # 核对进表。收的标准与全表一致：中文财经语境里有固定叫法的才收，
    # 拿不准的一律不收、照旧显示英文原文。
    #
    # 键照抄 nodes.json 里的 SEC 名称串，不是凭记忆写的。
    "Baidu, Inc.": "百度",
    "Bilibili Inc.": "哔哩哔哩",
    "JD.com, Inc.": "京东",
    "NetEase, Inc.": "网易",
    "iQIYI, Inc.": "爱奇艺",
    "WEIBO Corp": "微博",
    "Tencent Music Entertainment Group": "腾讯音乐",
    "KE Holdings Inc.": "贝壳",
    "Autohome Inc.": "汽车之家",
    "NIO Inc.": "蔚来",
    "Li Auto Inc.": "理想汽车",
    "XPENG INC.": "小鹏汽车",
    "ZTO Express (Cayman) Inc.": "中通快递",
    "TAL Education Group": "好未来",
    "Vipshop Holdings Ltd": "唯品会",
    "Sohu.com Ltd": "搜狐",
    "Hello Group Inc.": "挚文集团",
    "HUYA Inc.": "虎牙",
    "DouYu International Holdings Ltd": "斗鱼",
    "Luckin Coffee Inc.": "瑞幸咖啡",
    "H World Group Ltd": "华住集团",
    "GDS Holdings Ltd": "万国数据",
    "Futu Holdings Ltd": "富途控股",
    "UP Fintech Holding Ltd": "老虎证券",
    "Lufax Holding Ltd": "陆金所",
    "NOAH HOLDINGS LTD": "诺亚控股",
    "Qfin Holdings, Inc.": "奇富科技",
    "FinVolution Group": "信也科技",
    "LexinFintech Holdings Ltd.": "乐信",
    "Yiren Digital Ltd.": "宜人智科",
    "Jiayin Group Inc.": "嘉银科技",
    "MINISO Group Holding Ltd": "名创优品",
    "Yatsen Holding Ltd": "逸仙电商",
    "RLX Technology Inc.": "雾芯科技",
    "Zhihu Inc.": "知乎",
    "36Kr Holdings Inc.": "36氪",
    "Kanzhun Ltd": "看准科技",
    "Youdao, Inc.": "网易有道",
    "Gaotu Techedu Inc.": "高途",
    "Sunlands Technology Group": "尚德机构",
    "17 Education & Technology Group Inc.": "一起教育科技",
    "iHuman Inc.": "洪恩教育",
    "Baozun Inc.": "宝尊电商",
    "Tuniu Corp": "途牛",
    "Full Truck Alliance Co. Ltd.": "满帮集团",
    "DiDi Global Inc.": "滴滴",
    "Kingsoft Cloud Holdings Ltd": "金山云",
    "VNET Group, Inc.": "世纪互联",
    "Xunlei Ltd": "迅雷",
    "Cheetah Mobile Inc.": "猎豹移动",
    "Tuya Inc.": "涂鸦智能",
    "Hesai Group": "禾赛科技",
    "Pony AI Inc.": "小马智行",
    "WeRide Inc.": "文远知行",
    "EHang Holdings Ltd": "亿航智能",
    "Niu Technologies": "小牛电动",
    "DAQO NEW ENERGY CORP.": "大全新能源",
    "Zepp Health Corp": "华米科技",
    "So-Young International Inc.": "新氧",
    "Waterdrop Inc.": "水滴公司",
    "Huize Holding Ltd": "慧择",
    "Uxin Ltd": "优信",
    "ATRenew Inc.": "万物新生",
    "QUHUO Ltd": "趣活",
    "Yunji Inc.": "云集",
    "MOGU Inc.": "蘑菇街",
    "Fangdd Network Group Ltd.": "房多多",
    "Phoenix New Media Ltd": "凤凰新媒体",
    "The9 LTD": "第九城市",
    "Atour Lifestyle Holdings Ltd": "亚朵",
    "GreenTree Hospitality Group Ltd.": "格林酒店集团",
    "Chagee Holdings Ltd.": "霸王茶姬",
    "Lotus Technology Inc.": "路特斯科技",
    "ZKH Group Ltd": "震坤行",
    "NaaS Technology Inc.": "能链智电",
    "ECARX Holdings Inc.": "亿咖通科技",
    "Cheche Group Inc.": "车车科技",
    "uCloudlink Group Inc.": "优克联",
    "Viomi Technology Co., Ltd": "云米科技",
    "WiMi Hologram Cloud Inc.": "微美全息",
    "Intchains Group Ltd": "芯动科技",
    "YXT.COM GROUP HOLDING Ltd": "云学堂",
    "CLPS Inc": "华钦科技",
    "Lanvin Group Holdings Ltd": "复朗集团",
    "HUTCHMED (China) Ltd": "和黄医药",
    "Melco Resorts & Entertainment LTD": "新濠博亚娱乐",
    "STUDIO CITY INTERNATIONAL HOLDINGS Ltd": "新濠影汇",
    "111, Inc.": "1药网",
    "ASIA PACIFIC WIRE & CABLE CORP LTD": "亚太电线电缆",
    "Perfect Corp.": "玩美移动",
    "Gogoro Inc.": "睿能创意",
    "Adagene Inc.": "天演药业",
    "ASCENTAGE PHARMA GROUP INTERNATIONAL": "亚盛医药",
    "ATA Creativity Global": "全美在线",
    "Burning Rock Biotech Ltd": "燃石医学",
    "Jianpu Technology Inc.": "简普科技",

    # ── 标普成分股里确有通用中文名的 ────────────────────────────────────
    # 只有极少数够格：IBM、AT&T、eBay、PayPal 在中文语境里就是写原文的，
    # 按全表规矩不收——硬造一个音译反而不是它的名字。
    "Uber": "优步",
    "Kenvue": "科赴",
}


def name_for(english: str | None) -> str | None:
    """这家公司的中文名。表里没有就返回 None，页面照旧显示英文原文。"""
    if not english:
        return None
    return NAMES.get(english.strip()) or NAMES.get(english.strip().upper())
