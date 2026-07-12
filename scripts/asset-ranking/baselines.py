# -*- coding: utf-8 -*-
"""
「全球资产市值排行榜」的静态基准数据（不限品类，只看市值）。

方法论（与 assetmarketcap / 8marketcap 等站一致，可每日实时更新）：
    某类资产市值 = 数量(储量/地面存量/广义货币M2) × 单位价格(实时行情/汇率)

因此绝大多数大类资产的市值会随金价、油价、铜价、汇率每日浮动；只有房地产、煤炭、
政府债务、天然气这类「慢变量」用权威机构的存量估值作静态基准（附来源，定期人工校准）。

字段说明（AGGREGATES 每一项）：
    name/nameEn  中英文名           cat 分类键（见 CATEGORIES）
    qty          数量（以 price 的计价单位计）  unit 数量单位（展示用）
    symbol       Yahoo 实时价代码（有则市值随行情浮动；无则 basePrice 视为固定基准）
    basePrice    离线/兜底单位价格（美元）      invert 汇率是否取倒数（USD/本币 → 本币/USD）
    note         口径与来源说明（展示在条目备注里）
数量 × 价格 得到美元市值；本模块统一以「十亿美元」为单位输出，与公司榜口径一致。
"""

# —— 分类：键 / 中文 / 英文 / emoji / 颜色 ——（红涨绿跌沿用全站习惯，颜色仅用于分类标签）
CATEGORIES = [
    {"key": "real-estate", "label": "房地产",   "en": "Real Estate", "emoji": "🏠", "color": "#e0894e"},
    {"key": "commodity",   "label": "大宗商品", "en": "Commodities", "emoji": "🛢️", "color": "#8b95a5"},
    {"key": "metal",       "label": "贵金属",   "en": "Precious Metals", "emoji": "🪙", "color": "#f3c969"},
    {"key": "currency",    "label": "货币",     "en": "Currencies",  "emoji": "💵", "color": "#5fd07a"},
    {"key": "bond",        "label": "债券",     "en": "Bonds",       "emoji": "📜", "color": "#38bdf8"},
    {"key": "company",     "label": "公司",     "en": "Companies",   "emoji": "🏢", "color": "#6c8cff"},
    {"key": "crypto",      "label": "加密货币", "en": "Crypto",      "emoji": "₿",  "color": "#f7931a"},
]

# —— 大类资产（房地产 / 大宗商品 / 贵金属 / 货币 / 债券）——
# 数量取自公开权威估算（探明储量、地面存量、广义货币 M2/M3），价格尽量接实时行情。
AGGREGATES = [
    # 房地产：全球住宅+商业+土地总值，慢变量，静态基准（Savills 全球房地产总值估算）
    {"name": "全球房地产", "nameEn": "Real Estate", "cat": "real-estate", "emoji": "🏠",
     "qty": None, "unit": "住宅+商业+农地", "symbol": None, "basePrice": None, "baseCap": 380000.0,
     "note": "全球房地产总值，来源 Savills 估算（约 380 万亿美元，慢变量，定期校准）"},

    # 债券：全球政府债务余额，静态基准（IMF 全球公共债务）
    {"name": "政府债券", "nameEn": "Government Bonds", "cat": "bond", "emoji": "📜",
     "qty": None, "unit": "全球公共债务余额", "symbol": None, "basePrice": None, "baseCap": 97000.0,
     "note": "全球政府债务余额，来源 IMF《财政监测》（约 97 万亿美元，慢变量）"},

    # 大宗商品：储量 × 价格（能取到实时价的用 Yahoo 期货代理，取不到则静态）
    {"name": "煤炭", "nameEn": "Coal", "cat": "commodity", "emoji": "🪨",
     "qty": 1.166e12, "unit": "吨（探明储量）", "symbol": None, "basePrice": 130.0,
     "note": "全球煤炭探明储量 × 均价（储量约 1.17 万亿吨，静态基准）"},
    {"name": "石油", "nameEn": "Crude Oil", "cat": "commodity", "emoji": "🛢️",
     "qty": 1.73e12, "unit": "桶（探明储量）", "symbol": "CL=F", "basePrice": 68.0,
     "note": "全球石油探明储量 × WTI 油价（储量约 1.73 万亿桶，价格实时）"},
    {"name": "天然气", "nameEn": "Natural Gas", "cat": "commodity", "emoji": "💨",
     "qty": None, "unit": "探明储量估值", "symbol": None, "basePrice": None, "baseCap": 40000.0,
     "note": "全球天然气探明储量估值（约 40 万亿美元，静态基准）"},
    {"name": "铁矿石", "nameEn": "Iron Ore", "cat": "commodity", "emoji": "⛏️",
     "qty": 2.0e11, "unit": "吨（储量）", "symbol": None, "basePrice": 98.5,
     "note": "全球铁矿石储量 × 到岸价（储量约 2000 亿吨，静态基准）"},
    {"name": "铝", "nameEn": "Aluminum", "cat": "commodity", "emoji": "🔩",
     "qty": 5.8e9, "unit": "吨（储量）", "symbol": "ALI=F", "basePrice": 2500.0,
     "note": "全球铝储量 × 期货铝价（以 LME/COMEX 期货代理，价格实时）"},
    {"name": "铜", "nameEn": "Copper", "cat": "commodity", "emoji": "🟤",
     "qty": 2.86e12, "unit": "磅（储量）", "symbol": "HG=F", "basePrice": 4.4,
     "note": "全球铜储量 × COMEX 铜价（储量约 13 亿吨，价格实时）"},

    # 贵金属：地面存量 × 现货价（价格实时）
    {"name": "黄金", "nameEn": "Gold", "cat": "metal", "emoji": "🥇",
     "qty": 6.72e9, "unit": "盎司（地面存量）", "symbol": "GC=F", "basePrice": 3000.0,
     "note": "全球地面黄金存量 × 金价（约 6.72 亿盎司/21.6 万吨，来源世界黄金协会，价格实时）"},
    {"name": "白银", "nameEn": "Silver", "cat": "metal", "emoji": "🥈",
     "qty": 5.0e10, "unit": "盎司（地面存量）", "symbol": "SI=F", "basePrice": 33.0,
     "note": "全球地面白银存量 × 银价（约 500 亿盎司，价格实时）"},

    # 货币：广义货币 M2/M3 × 汇率（qty 为本币金额，symbol 为 Yahoo 汇率代码）
    {"name": "人民币", "nameEn": "Chinese Yuan (M2)", "cat": "currency", "emoji": "🇨🇳",
     "qty": 353.67e12, "unit": "元（广义货币 M2）", "symbol": "CNY=X", "invert": True, "basePrice": 0.140,
     "note": "中国广义货币 M2（约 353 万亿元）× 美元汇率，汇率实时"},
    {"name": "美元", "nameEn": "US Dollar (M2)", "cat": "currency", "emoji": "🇺🇸",
     "qty": 22.80e12, "unit": "美元（广义货币 M2）", "symbol": None, "basePrice": 1.0,
     "note": "美国广义货币 M2（约 22.8 万亿美元）"},
    {"name": "欧元", "nameEn": "Euro (M3)", "cat": "currency", "emoji": "🇪🇺",
     "qty": 16.38e12, "unit": "欧元（广义货币 M3）", "symbol": "EURUSD=X", "invert": False, "basePrice": 1.15,
     "note": "欧元区广义货币 M3（约 16.4 万亿欧元）× 美元汇率，汇率实时"},
    {"name": "日元", "nameEn": "Japanese Yen (M2)", "cat": "currency", "emoji": "🇯🇵",
     "qty": 1250e12, "unit": "日元（广义货币 M2）", "symbol": "JPY=X", "invert": True, "basePrice": 0.0064,
     "note": "日本广义货币 M2（约 1250 万亿日元）× 美元汇率，汇率实时"},
    {"name": "英镑", "nameEn": "British Pound (M2)", "cat": "currency", "emoji": "🇬🇧",
     "qty": 3.0e12, "unit": "英镑（广义货币 M2）", "symbol": "GBPUSD=X", "invert": False, "basePrice": 1.28,
     "note": "英国广义货币 M2（约 3 万亿英镑）× 美元汇率，汇率实时"},
]

# —— 主要加密货币（个体计入排行；实时市值来自 CoinGecko，取不到则用此基准 + BTC/ETH 现价推算）——
# id 为 CoinGecko 币种 id；yf 为 Yahoo 代码（价格兜底）；baseCap 十亿美元。
CRYPTO = [
    {"name": "比特币",   "nameEn": "Bitcoin",   "id": "bitcoin",     "yf": "BTC-USD", "supply": 19_900_000,      "baseCap": 2000.0, "symbol": "BTC"},
    {"name": "以太坊",   "nameEn": "Ethereum",  "id": "ethereum",    "yf": "ETH-USD", "supply": 120_700_000,     "baseCap": 450.0,  "symbol": "ETH"},
    {"name": "泰达币",   "nameEn": "Tether",    "id": "tether",      "yf": None,      "supply": None,            "baseCap": 145.0,  "symbol": "USDT"},
    {"name": "瑞波币",   "nameEn": "XRP",       "id": "ripple",      "yf": "XRP-USD", "supply": 59_000_000_000,  "baseCap": 130.0,  "symbol": "XRP"},
    {"name": "币安币",   "nameEn": "BNB",       "id": "binancecoin", "yf": "BNB-USD", "supply": 145_000_000,     "baseCap": 95.0,   "symbol": "BNB"},
    {"name": "Solana",   "nameEn": "Solana",    "id": "solana",      "yf": "SOL-USD", "supply": 530_000_000,     "baseCap": 85.0,   "symbol": "SOL"},
    {"name": "USDC",     "nameEn": "USD Coin",  "id": "usd-coin",    "yf": None,      "supply": None,            "baseCap": 60.0,   "symbol": "USDC"},
    {"name": "狗狗币",   "nameEn": "Dogecoin",  "id": "dogecoin",    "yf": "DOGE-USD","supply": 148_000_000_000, "baseCap": 30.0,   "symbol": "DOGE"},
    {"name": "艾达币",   "nameEn": "Cardano",   "id": "cardano",     "yf": "ADA-USD", "supply": 35_800_000_000,  "baseCap": 25.0,   "symbol": "ADA"},
    {"name": "波场",     "nameEn": "TRON",      "id": "tron",        "yf": "TRX-USD", "supply": 94_600_000_000,  "baseCap": 24.0,   "symbol": "TRX"},
]
