# -*- coding: utf-8 -*-
"""公司榜的静态映射：行业/国别中文化、头部公司中文名+官网域名（用于 Clearbit 高清 logo）、
   并入榜单末尾的知名非上市公司。被 build_companies.py（每日）与首版生成脚本共用。"""

# FMP 行业（英文）-> 中文
SECTOR_ZH = {
    "Technology": "科技", "Financial Services": "金融", "Healthcare": "医疗健康",
    "Consumer Cyclical": "可选消费", "Consumer Defensive": "必需消费",
    "Communication Services": "通信服务", "Industrials": "工业", "Energy": "能源",
    "Basic Materials": "原材料", "Real Estate": "房地产", "Utilities": "公用事业",
}

# 国家 ISO2 -> 中文 / 国旗
COUNTRY_ZH = {
    "US": "美国", "CN": "中国", "TW": "台湾", "HK": "香港", "JP": "日本", "KR": "韩国",
    "IN": "印度", "SA": "沙特", "GB": "英国", "FR": "法国", "DE": "德国", "CH": "瑞士",
    "NL": "荷兰", "DK": "丹麦", "IE": "爱尔兰", "CA": "加拿大", "AU": "澳大利亚",
    "BR": "巴西", "ES": "西班牙", "IT": "意大利", "SE": "瑞典", "SG": "新加坡",
    "BE": "比利时", "BM": "百慕大", "FI": "芬兰", "IL": "以色列", "LU": "卢森堡",
    "NO": "挪威", "SV": "萨尔瓦多",
}
COUNTRY_FLAG = {
    "US": "🇺🇸", "CN": "🇨🇳", "TW": "🇹🇼", "HK": "🇭🇰", "JP": "🇯🇵", "KR": "🇰🇷",
    "IN": "🇮🇳", "SA": "🇸🇦", "GB": "🇬🇧", "FR": "🇫🇷", "DE": "🇩🇪", "CH": "🇨🇭",
    "NL": "🇳🇱", "DK": "🇩🇰", "IE": "🇮🇪", "CA": "🇨🇦", "AU": "🇦🇺", "BR": "🇧🇷",
    "ES": "🇪🇸", "IT": "🇮🇹", "SE": "🇸🇪", "SG": "🇸🇬", "BE": "🇧🇪", "BM": "🇧🇲",
    "FI": "🇫🇮", "IL": "🇮🇱", "LU": "🇱🇺", "NO": "🇳🇴", "SV": "🇸🇻",
}

# 代码 -> (中文名, 官网域名)。域名用于 Clearbit 高清 logo；未列出的公司用英文名 + FMP 图/字母牌。
ZH_OVERLAY = {
    "NVDA": ("英伟达", "nvidia.com"), "AAPL": ("苹果", "apple.com"), "MSFT": ("微软", "microsoft.com"),
    "GOOGL": ("谷歌", "google.com"), "AMZN": ("亚马逊", "amazon.com"), "META": ("Meta", "meta.com"),
    "AVGO": ("博通", "broadcom.com"), "TSLA": ("特斯拉", "tesla.com"), "BRK-B": ("伯克希尔", "berkshirehathaway.com"),
    "JPM": ("摩根大通", "jpmorganchase.com"), "WMT": ("沃尔玛", "walmart.com"), "LLY": ("礼来", "lilly.com"),
    "V": ("Visa", "visa.com"), "MA": ("万事达", "mastercard.com"), "ORCL": ("甲骨文", "oracle.com"),
    "COST": ("好市多", "costco.com"), "NFLX": ("奈飞", "netflix.com"), "XOM": ("埃克森美孚", "exxonmobil.com"),
    "JNJ": ("强生", "jnj.com"), "HD": ("家得宝", "homedepot.com"), "PG": ("宝洁", "pg.com"),
    "BAC": ("美国银行", "bankofamerica.com"), "ABBV": ("艾伯维", "abbvie.com"), "CVX": ("雪佛龙", "chevron.com"),
    "KO": ("可口可乐", "coca-colacompany.com"), "AMD": ("AMD", "amd.com"), "CRM": ("Salesforce", "salesforce.com"),
    "PM": ("菲利普莫里斯", "pmi.com"), "WFC": ("富国银行", "wellsfargo.com"), "TMUS": ("T-Mobile", "t-mobile.com"),
    "CSCO": ("思科", "cisco.com"), "IBM": ("IBM", "ibm.com"), "MCD": ("麦当劳", "mcdonalds.com"),
    "ABT": ("雅培", "abbott.com"), "GE": ("GE航空航天", "geaerospace.com"), "LIN": ("林德", "linde.com"),
    "ADBE": ("Adobe", "adobe.com"), "PEP": ("百事", "pepsico.com"), "DIS": ("迪士尼", "disney.com"),
    "MRK": ("默克", "merck.com"), "NOW": ("ServiceNow", "servicenow.com"), "ACN": ("埃森哲", "accenture.com"),
    "TXN": ("德州仪器", "ti.com"), "QCOM": ("高通", "qualcomm.com"), "INTU": ("Intuit", "intuit.com"),
    "AXP": ("美国运通", "americanexpress.com"), "ISRG": ("直觉外科", "intuitive.com"), "AMGN": ("安进", "amgen.com"),
    "GS": ("高盛", "goldmansachs.com"), "MS": ("摩根士丹利", "morganstanley.com"), "PFE": ("辉瑞", "pfizer.com"),
    "CAT": ("卡特彼勒", "caterpillar.com"), "RTX": ("雷神技术", "rtx.com"), "INTC": ("英特尔", "intel.com"),
    "T": ("AT&T", "att.com"), "VZ": ("威瑞森", "verizon.com"), "LOW": ("劳氏", "lowes.com"),
    "UNH": ("联合健康", "unitedhealthgroup.com"), "HON": ("霍尼韦尔", "honeywell.com"), "BKNG": ("Booking", "booking.com"),
    "NKE": ("耐克", "nike.com"), "SBUX": ("星巴克", "starbucks.com"), "BA": ("波音", "boeing.com"),
    "UPS": ("UPS", "ups.com"), "SPGI": ("标普全球", "spglobal.com"), "BLK": ("贝莱德", "blackrock.com"),
    "C": ("花旗", "citigroup.com"), "BX": ("黑石", "blackstone.com"), "PLTR": ("Palantir", "palantir.com"),
    "UBER": ("Uber", "uber.com"), "COIN": ("Coinbase", "coinbase.com"), "PYPL": ("PayPal", "paypal.com"),
    "ABNB": ("爱彼迎", "airbnb.com"), "MU": ("美光", "micron.com"), "DELL": ("戴尔", "dell.com"),
    "GM": ("通用汽车", "gm.com"), "F": ("福特", "ford.com"), "MO": ("奥驰亚", "altria.com"),
    "DHR": ("丹纳赫", "danaher.com"), "TMO": ("赛默飞", "thermofisher.com"), "WDAY": ("Workday", "workday.com"),
    "PANW": ("Palo Alto", "paloaltonetworks.com"), "CRWD": ("CrowdStrike", "crowdstrike.com"), "SHW": ("宣伟", "sherwin-williams.com"),
    "SPCX": ("SpaceX", "spacex.com"),
    # —— 海外 ——
    "TSM": ("台积电", "tsmc.com"), "005930.KS": ("三星电子", "samsung.com"), "BABA": ("阿里巴巴", "alibabagroup.com"),
    "ASML": ("阿斯麦", "asml.com"), "SAP": ("SAP", "sap.com"), "TM": ("丰田", "toyota.com"), "AZN": ("阿斯利康", "astrazeneca.com"),
    "NVO": ("诺和诺德", "novonordisk.com"), "NVS": ("诺华", "novartis.com"), "SHEL": ("壳牌", "shell.com"),
    "HSBC": ("汇丰", "hsbc.com"), "BHP": ("必和必拓", "bhp.com"), "TTE": ("道达尔能源", "totalenergies.com"),
    "SONY": ("索尼", "sony.com"), "BUD": ("百威英博", "ab-inbev.com"), "UL": ("联合利华", "unilever.com"),
    "RY": ("加拿大皇家银行", "rbc.com"), "TD": ("道明银行", "td.com"), "PDD": ("拼多多", "pinduoduo.com"),
    "JD": ("京东", "jd.com"), "NTES": ("网易", "netease.com"), "BIDU": ("百度", "baidu.com"),
    "SE": ("Sea", "sea.com"), "RIO": ("力拓", "riotinto.com"), "GSK": ("葛兰素史克", "gsk.com"),
    "DEO": ("帝亚吉欧", "diageo.com"), "BP": ("BP", "bp.com"), "SNY": ("赛诺菲", "sanofi.com"),
    "ARM": ("Arm", "arm.com"), "SPOT": ("Spotify", "spotify.com"), "BTI": ("英美烟草", "bat.com"),
    "TCEHY": ("腾讯", "tencent.com"), "LVMUY": ("路威酩轩", "lvmh.com"), "NSRGY": ("雀巢", "nestle.com"),
    "RHHBY": ("罗氏", "roche.com"), "INFY": ("印孚瑟斯", "infosys.com"), "IBN": ("ICICI银行", "icicibank.com"),
    "HDB": ("HDFC银行", "hdfcbank.com"), "SAN": ("桑坦德银行", "santander.com"), "UBS": ("瑞银", "ubs.com"),
    "STLA": ("Stellantis", "stellantis.com"), "SIEGY": ("西门子", "siemens.com"), "VWAGY": ("大众汽车", "volkswagen.com"),
    "MBGYY": ("梅赛德斯-奔驰", "mercedes-benz.com"), "2222.SR": ("沙特阿美", "aramco.com"), "TRI": ("汤森路透", "thomsonreuters.com"),
    "ENB": ("Enbridge", "enbridge.com"), "CNI": ("加拿大国家铁路", "cn.ca"), "MUFG": ("三菱日联", "mufg.jp"),
    "RELX": ("RELX", "relx.com"), "PHG": ("飞利浦", "philips.com"),
}

# 并入榜单末尾的知名「非上市公司」（来源：multiples.vc「最有价值私营公司」榜，最新一轮公开估值，
# 单位：十亿美元；非实时）。标记 private=True，前端置于榜单末段并标「未上市」。
PRIVATE = [
    {"nameEn": "Anthropic", "name": "Anthropic", "marketCap": 965.0, "country": "美国", "flag": "🇺🇸", "sector": "人工智能", "domain": "anthropic.com"},
    {"nameEn": "OpenAI", "name": "OpenAI", "marketCap": 852.0, "country": "美国", "flag": "🇺🇸", "sector": "人工智能", "domain": "openai.com"},
    {"nameEn": "Tether", "name": "Tether", "marketCap": 500.0, "country": "萨尔瓦多", "flag": "🇸🇻", "sector": "加密货币", "domain": "tether.to"},
    {"nameEn": "ByteDance", "name": "字节跳动", "marketCap": 480.0, "country": "中国", "flag": "🇨🇳", "sector": "互联网", "domain": "bytedance.com"},
    {"nameEn": "Stripe", "name": "Stripe", "marketCap": 159.0, "country": "美国", "flag": "🇺🇸", "sector": "支付", "domain": "stripe.com"},
    {"nameEn": "Ant Group", "name": "蚂蚁集团", "marketCap": 150.0, "country": "中国", "flag": "🇨🇳", "sector": "金融科技", "domain": "antgroup.com"},
    {"nameEn": "Databricks", "name": "Databricks", "marketCap": 134.0, "country": "美国", "flag": "🇺🇸", "sector": "数据与AI", "domain": "databricks.com"},
    {"nameEn": "Waymo", "name": "Waymo", "marketCap": 126.0, "country": "美国", "flag": "🇺🇸", "sector": "自动驾驶", "domain": "waymo.com"},
    {"nameEn": "Reliance Retail", "name": "信实零售", "marketCap": 101.0, "country": "印度", "flag": "🇮🇳", "sector": "零售", "domain": "relianceretail.com"},
    {"nameEn": "Revolut", "name": "Revolut", "marketCap": 75.0, "country": "英国", "flag": "🇬🇧", "sector": "金融科技", "domain": "revolut.com"},
    {"nameEn": "Shein", "name": "希音", "marketCap": 66.0, "country": "新加坡", "flag": "🇸🇬", "sector": "电商", "domain": "shein.com"},
    {"nameEn": "Anduril", "name": "Anduril", "marketCap": 61.0, "country": "美国", "flag": "🇺🇸", "sector": "国防科技", "domain": "anduril.com"},
    {"nameEn": "Reliance Jio", "name": "信实 Jio", "marketCap": 58.5, "country": "印度", "flag": "🇮🇳", "sector": "电信", "domain": "jio.com"},
    {"nameEn": "DeepSeek", "name": "深度求索", "marketCap": 50.0, "country": "中国", "flag": "🇨🇳", "sector": "人工智能", "domain": "deepseek.com"},
    {"nameEn": "Adani New Industries", "name": "阿达尼新能源", "marketCap": 50.0, "country": "印度", "flag": "🇮🇳", "sector": "新能源", "domain": "adani.com"},
    {"nameEn": "TenneT Germany", "name": "TenneT", "marketCap": 45.8, "country": "德国", "flag": "🇩🇪", "sector": "公用事业", "domain": "tennet.eu"},
    {"nameEn": "Ramp", "name": "Ramp", "marketCap": 44.0, "country": "美国", "flag": "🇺🇸", "sector": "金融科技", "domain": "ramp.com"},
    {"nameEn": "Canva", "name": "Canva", "marketCap": 42.0, "country": "澳大利亚", "flag": "🇦🇺", "sector": "软件", "domain": "canva.com"},
    {"nameEn": "Prometheus", "name": "Prometheus", "marketCap": 41.0, "country": "美国", "flag": "🇺🇸", "sector": "数据中心", "domain": "prometheushyperscale.com"},
    {"nameEn": "Ripple", "name": "Ripple", "marketCap": 40.0, "country": "美国", "flag": "🇺🇸", "sector": "加密货币", "domain": "ripple.com"},
    {"nameEn": "Figure", "name": "Figure", "marketCap": 39.0, "country": "美国", "flag": "🇺🇸", "sector": "机器人", "domain": "figure.ai"},
    {"nameEn": "JUUL", "name": "JUUL", "marketCap": 38.0, "country": "美国", "flag": "🇺🇸", "sector": "消费品", "domain": "juul.com"},
    {"nameEn": "Safe Superintelligence", "name": "Safe Superintelligence", "marketCap": 32.0, "country": "美国", "flag": "🇺🇸", "sector": "人工智能", "domain": "ssi.inc"},
    {"nameEn": "Fanatics", "name": "Fanatics", "marketCap": 31.0, "country": "美国", "flag": "🇺🇸", "sector": "电商", "domain": "fanatics.com"},
    {"nameEn": "Groot Systems", "name": "Groot Systems", "marketCap": 30.0, "country": "纳米比亚", "flag": "🇳🇦", "sector": "科技", "domain": None},
    {"nameEn": "VAST Data", "name": "VAST Data", "marketCap": 30.0, "country": "美国", "flag": "🇺🇸", "sector": "数据存储", "domain": "vastdata.com"},
    # —— 27–50 名（来源 multiples.vc「最有价值私营公司」榜，最近一轮公开估值）——
    {"nameEn": "HUB International", "name": "HUB International", "marketCap": 29.0, "country": "美国", "flag": "🇺🇸", "sector": "保险经纪", "domain": "hubinternational.com"},
    {"nameEn": "Scale AI", "name": "Scale AI", "marketCap": 29.0, "country": "美国", "flag": "🇺🇸", "sector": "AI数据", "domain": "scale.com"},
    {"nameEn": "LaLiga", "name": "西甲联盟", "marketCap": 27.9, "country": "西班牙", "flag": "🇪🇸", "sector": "体育", "domain": "laliga.com"},
    {"nameEn": "Cognition", "name": "Cognition", "marketCap": 26.0, "country": "美国", "flag": "🇺🇸", "sector": "人工智能", "domain": "cognition.ai"},
    {"nameEn": "OKX", "name": "OKX", "marketCap": 25.0, "country": "塞舌尔", "flag": "🇸🇨", "sector": "加密货币", "domain": "okx.com"},
    {"nameEn": "Yangtze Memory (YMTC)", "name": "长江存储", "marketCap": 22.5, "country": "中国", "flag": "🇨🇳", "sector": "半导体", "domain": "ymtc.com"},
    {"nameEn": "Epic Games", "name": "Epic Games", "marketCap": 22.5, "country": "美国", "flag": "🇺🇸", "sector": "游戏", "domain": "epicgames.com"},
    {"nameEn": "Kalshi", "name": "Kalshi", "marketCap": 22.0, "country": "美国", "flag": "🇺🇸", "sector": "金融", "domain": "kalshi.com"},
    {"nameEn": "BYJU'S", "name": "BYJU'S", "marketCap": 22.0, "country": "印度", "flag": "🇮🇳", "sector": "教育科技", "domain": "byjus.com"},
    {"nameEn": "FiberCop", "name": "FiberCop", "marketCap": 21.6, "country": "意大利", "flag": "🇮🇹", "sector": "电信", "domain": "fibercop.it"},
    {"nameEn": "WestConnex", "name": "WestConnex", "marketCap": 21.4, "country": "澳大利亚", "flag": "🇦🇺", "sector": "基建", "domain": "westconnex.com.au"},
    {"nameEn": "Chobani", "name": "Chobani", "marketCap": 20.0, "country": "美国", "flag": "🇺🇸", "sector": "食品", "domain": "chobani.com"},
    {"nameEn": "Authentic Brands Group", "name": "Authentic Brands", "marketCap": 20.0, "country": "美国", "flag": "🇺🇸", "sector": "品牌授权", "domain": "authenticbrands.com"},
    {"nameEn": "Perplexity", "name": "Perplexity", "marketCap": 20.0, "country": "美国", "flag": "🇺🇸", "sector": "人工智能", "domain": "perplexity.ai"},
    {"nameEn": "Xiaohongshu", "name": "小红书", "marketCap": 20.0, "country": "中国", "flag": "🇨🇳", "sector": "互联网", "domain": "xiaohongshu.com"},
    {"nameEn": "Moonshot AI", "name": "月之暗面", "marketCap": 20.0, "country": "中国", "flag": "🇨🇳", "sector": "人工智能", "domain": "moonshot.ai"},
    {"nameEn": "KNDS", "name": "KNDS", "marketCap": 20.0, "country": "荷兰", "flag": "🇳🇱", "sector": "国防", "domain": "knds.com"},
    {"nameEn": "ChangXin Memory (CXMT)", "name": "长鑫存储", "marketCap": 19.4, "country": "中国", "flag": "🇨🇳", "sector": "半导体", "domain": "cxmt.com"},
    {"nameEn": "Repsol Upstream", "name": "Repsol Upstream", "marketCap": 19.0, "country": "西班牙", "flag": "🇪🇸", "sector": "能源", "domain": "repsol.com"},
    {"nameEn": "ViiV Healthcare", "name": "ViiV Healthcare", "marketCap": 18.2, "country": "英国", "flag": "🇬🇧", "sector": "医疗健康", "domain": "viivhealthcare.com"},
    {"nameEn": "JD Digits", "name": "京东科技", "marketCap": 17.9, "country": "中国", "flag": "🇨🇳", "sector": "金融科技", "domain": "jd.com"},
    {"nameEn": "Miro", "name": "Miro", "marketCap": 17.5, "country": "美国", "flag": "🇺🇸", "sector": "软件", "domain": "miro.com"},
    {"nameEn": "Deel", "name": "Deel", "marketCap": 17.3, "country": "美国", "flag": "🇺🇸", "sector": "软件", "domain": "deel.com"},
    {"nameEn": "Froneri", "name": "Froneri", "marketCap": 17.3, "country": "英国", "flag": "🇬🇧", "sector": "食品", "domain": "froneri.com"},
]

# 各非上市公司「上一轮融资时间」（来源 multiples.vc 的 Last Round 列；Tether 暂无公开轮次）
LAST_ROUND = {
    "Anthropic": "May 2026", "OpenAI": "Apr 2026", "Tether": None, "ByteDance": "Nov 2025", "Stripe": "Feb 2026",
    "Ant Group": "Jun 2018", "Databricks": "Dec 2025", "Waymo": "Feb 2026", "Reliance Retail": "Oct 2023", "Revolut": "Nov 2025",
    "Shein": "May 2023", "Anduril": "May 2026", "Reliance Jio": "Jul 2020", "DeepSeek": "Jun 2026", "Adani New Industries": "Jun 2022",
    "TenneT Germany": "Feb 2026", "Ramp": "Jun 2026", "Canva": "Aug 2025", "Prometheus": "Jun 2026", "Ripple": "Nov 2025",
    "Figure": "Sep 2025", "JUUL": "Dec 2018", "Safe Superintelligence": "Apr 2025", "Fanatics": "Dec 2022", "VAST Data": "Mar 2026",
    "Groot Systems": "Oct 2019", "HUB International": "May 2025", "Scale AI": "Jun 2025", "LaLiga": "Aug 2021", "Cognition": "May 2026",
    "OKX": "Mar 2026", "Yangtze Memory (YMTC)": "Dec 2023", "Epic Games": "Feb 2024", "Kalshi": "Mar 2026", "BYJU'S": "Oct 2022",
    "FiberCop": "Jun 2024", "WestConnex": "Sep 2021", "Chobani": "Oct 2025", "Authentic Brands Group": "Jun 2023", "Perplexity": "Dec 2025",
    "Xiaohongshu": "Nov 2021", "Moonshot AI": "May 2026", "KNDS": "Jun 2026", "ChangXin Memory (CXMT)": "Mar 2024", "Repsol Upstream": "Sep 2022",
    "ViiV Healthcare": "Jan 2026", "JD Digits": "Jul 2018", "Miro": "Jan 2022", "Deel": "Oct 2025", "Froneri": "Oct 2025",
}


# 代码 -> 中文名（仅补名，不改 logo/域名）。纯英文品牌不列入，保留原文。
NAME_ZH_EXTRA = {'AMAT': '应用材料', 'LRCX': '泛林集团', 'KLAC': '科磊', 'SNDK': '闪迪', 'GEV': 'GE 维尔诺瓦', 'MRVL': '美满电子', 'WDC': '西部数据', 'GLW': '康宁', 'STX': '希捷', 'APH': '安费诺', 'ADI': '亚德诺', 'NEE': '新纪元能源', 'DE': '迪尔', 'UNP': '联合太平洋', 'ETN': '伊顿', 'SCHW': '嘉信理财', 'GILD': '吉利德', 'UBER': '优步', 'IBKR': '盈透证券', 'BBVA': '西班牙对外银行', 'CB': '安达保险', 'PLD': '普洛斯', 'PGR': '前进保险', 'COP': '康菲石油', 'VRTX': '福泰制药', 'SYK': '史赛克', 'COF': '第一资本', 'PH': '派克汉尼汾', 'ENB': '安桥', 'BMY': '百时美施贵宝', 'VRT': '维谛技术', 'MFG': '瑞穗金融', 'LMT': '洛克希德·马丁', 'FTNT': '飞塔', 'SO': '南方公司', 'HWM': '豪梅特航空', 'TT': '特灵科技', 'MDT': '美敦力', 'CDNS': '楷登电子', 'NEM': '纽蒙特', 'DUK': '杜克能源', 'PNC': 'PNC 金融服务', 'MAR': '万豪国际', 'BNY': '纽约梅隆银行', 'MNST': '怪物饮料', 'CMI': '康明斯', 'USB': '美国合众银行', 'GD': '通用动力', 'CEG': '星座能源', 'SMFG': '三井住友金融', 'WMB': '威廉姆斯公司', 'HOOD': '罗宾汉', 'BCS': '巴克莱', 'WM': '废物管理公司', 'ING': 'ING 集团', 'CSX': 'CSX 运输', 'FCX': '自由港麦克莫兰', 'MCK': '麦克森', 'HCA': 'HCA 医疗', 'CMCSA': '康卡斯特', 'RCL': '皇家加勒比', 'JCI': '江森自控', 'SNPS': '新思科技', 'LYG': '劳埃德银行', 'NGG': '英国国家电网', 'MRSH': '威达信集团', 'EMR': '艾默生', 'CME': '芝商所', 'VLO': '瓦莱罗能源', 'MCO': '穆迪', 'AMT': '美国电塔', 'ECL': '艺康', 'FDX': '联邦快递', 'MDLZ': '亿滋国际', 'ITW': '伊利诺伊工具', 'HLT': '希尔顿', 'MPC': '马拉松石油', 'AEP': '美国电力', 'ORLY': '奥莱利汽配', 'CL': '高露洁', 'SPG': '西蒙地产', 'CI': '信诺', 'CRH': 'CRH 集团', 'TER': '泰瑞达', 'KMI': '金德摩根', 'NSC': '诺福克南方铁路', 'TRV': '旅行者保险', 'NOC': '诺斯罗普·格鲁曼', 'NXPI': '恩智浦', 'URI': '联合租赁', 'EOG': 'EOG 能源', 'AON': '怡安', 'PSX': '菲利普斯66', 'ICE': '洲际交易所', 'SLB': '斯伦贝谢', 'MSI': '摩托罗拉系统', 'E': '埃尼', 'WBD': '华纳兄弟探索', 'MFC': '宏利金融', 'ROST': '罗斯百货', 'APO': '阿波罗全球管理', 'RSG': '共和服务', 'REGN': '再生元', 'BSX': '波士顿科学', 'MPWR': '芯源系统', 'GWW': '固安捷', 'PCAR': '帕卡', 'ALL': '好事达', 'COHR': '相干公司', 'SRE': '桑普拉能源', 'DAL': '达美航空', 'AFL': '美国家庭人寿', 'CARR': '开利', 'D': '道明尼能源', 'TGT': '塔吉特', 'APD': '空气化工产品', 'HPE': '慧与', 'FLEX': '伟创力', 'KEYS': '是德科技', 'TEL': '泰科电子', 'PSA': '公共存储', 'BDX': '碧迪医疗', 'BKR': '贝克休斯', 'CTVA': '科迪华', 'MET': '大都会人寿', 'CAH': '康德乐', 'RELX': '励讯集团', 'ROK': '罗克韦尔自动化', 'ETR': '安特吉', 'EW': '爱德华兹生命科学', 'NUE': '纽柯钢铁', 'FITB': '第五三银行', 'EA': '艺电', 'OXY': '西方石油', 'MCHP': '微芯科技', 'BASFY': '巴斯夫', 'STT': '道富银行', 'HUM': '哈门那', 'DHI': '霍顿房屋', 'GRMN': '佳明', 'UAL': '联合航空', 'YUM': '百胜餐饮', 'NDAQ': '纳斯达克', 'IDXX': '爱德士', 'ED': '联合爱迪生', 'ADSK': '欧特克', 'MSCI': '明晟', 'CCL': '嘉年华邮轮', 'SYY': '西斯科', 'CBRE': '世邦魏理仕', 'AIG': '美国国际集团', 'JBL': '捷普', 'PCG': '太平洋煤气电力', 'PRU': '保德信金融', 'A': '安捷伦', 'HSY': '好时', 'HIG': '哈特福德金融', 'KMB': '金佰利', 'ARES': '阿瑞斯资本', 'MTB': 'M&T 银行', 'MLM': '马丁玛丽埃塔', 'ON': '安森美半导体', 'KR': '克罗格', 'CCI': '冠城国际', 'STLD': '钢铁动力', 'ROP': '罗珀科技', 'NTRS': '北方信托', 'IQV': '艾昆纬', 'BIIB': '渤健', 'IR': '英格索兰', 'LVS': '拉斯维加斯金沙', 'ZTS': '硕腾', 'EXPE': '亿客行', 'DOV': '多佛', 'TDY': '特利丹', 'GEHC': 'GE 医疗', 'TPR': '泰佩思琦', 'RJF': '雷蒙詹姆斯', 'EIX': '爱迪生国际', 'RMD': '瑞思迈', 'KHC': '卡夫亨氏', 'EL': '雅诗兰黛', 'HAL': '哈里伯顿', 'OTIS': '奥的斯', 'MRNA': '莫德纳', 'XYL': '赛莱默', 'DXCM': '德康医疗', 'PPG': 'PPG 工业', 'DVN': '戴文能源', 'AWK': '美国水务', 'MTD': '梅特勒-托利多', 'LUV': '西南航空', 'FSLR': '第一太阳能', 'WTW': '韦莱韬悦', 'TROW': '普信集团', 'RL': '拉夫劳伦', 'CBOE': '芝加哥期权交易所', 'STZ': '星座品牌', 'WAT': '沃特世', 'DLTR': '美元树', 'VRSN': '威瑞信', 'LEN': '莱纳房屋', 'FOXA': '福克斯', 'BG': '邦吉', 'OMC': '宏盟集团', 'TSN': '泰森食品', 'AME': '阿美特克', 'FANG': '响尾蛇能源', 'CMG': '墨式烧烤', 'ADM': 'ADM'}

# 非上市公司 英文名 -> 中文名
NAME_ZH_EXTRA_PRIV = {'Ripple': '瑞波', 'OKX': '欧易', 'Repsol Upstream': '雷普索尔'}
