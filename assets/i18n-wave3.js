/* Ooglex third-wave i18n layer.
   Covers remaining public data pages. It translates reviewed UI chrome only;
   source/news/research prose stays in its original language. */
(function () {
  "use strict";

  var KEY = "ooglex.language";
  var path = (location.pathname || "/").replace(/\/index\.html$/, "/");
  var current = "zh";
  var textOrig = new WeakMap(), textTouched = [];
  var attrOrig = new WeakMap(), attrTouched = [];
  var htmlOrig = new WeakMap(), htmlTouched = [];
  /* 加进 alt：榜单头像/图标的 alt 存的是中文名，读屏用户此前一直读到中文。 */
  var ATTRS = ["placeholder", "aria-label", "title", "alt"];

  function readLang() {
    try {
      if (window.OoglexI18n && window.OoglexI18n.getLanguage) {
        return window.OoglexI18n.getLanguage() === "en" ? "en" : "zh";
      }
      return localStorage.getItem(KEY) === "en" ? "en" : "zh";
    } catch (e) { return "zh"; }
  }

  function copy(dst, src) { Object.keys(src).forEach(function (k) { dst[k] = src[k]; }); }

  var COMMON = {
    "← 返回 Ooglex": "← Back to Ooglex",
    "关于本页数据": "About This Data",
    "数据来源": "Data Source",
    "数据日期": "Date",
    "更新于": "Updated",
    "全部": "All",
    "暂无数据": "No data",
    "加载中…": "Loading…",
    "加载失败": "Load failed",
    "实时榜 · 每日自动更新": "Live ranking · Updated daily",
    "示例数据 · 待每日任务刷新": "Sample data · Awaiting daily refresh",
    "实时聚合 · 每日更新": "Live aggregate · Updated daily",
    "实时聚合 · 自动更新": "Live aggregate · Auto-updated",
    "示例数据 · 待刷新": "Sample data · Awaiting refresh",
    "今日涨幅": "Top Gainers",
    "今日跌幅": "Top Decliners",
    "来源": "Source",
    "不可用": "Unavailable"
  };

  var ASSET_RANKING = {
    /* 资产名、品类名与计量口径全部逐条取自 apps/asset-ranking/data.json 的
       `nameEn` / `en` / `unit` 字段（数据里本来就中英双写），生成而非手译，
       不会和数据源分叉。既有词条在后面覆盖同名键，保持原有措辞优先。 */
    "全球房地产": "Real Estate",
    "石油": "Crude Oil",
    "煤炭": "Coal",
    "政府债券": "Government Bonds",
    "人民币": "Chinese Yuan (M2)",
    "天然气": "Natural Gas",
    "黄金": "Gold",
    "美元": "US Dollar (M2)",
    "铝": "Aluminum",
    "铁矿石": "Iron Ore",
    "铜": "Copper",
    "欧元": "Euro (M3)",
    "日元": "Japanese Yen (M2)",
    "英伟达": "Nvidia",
    "苹果": "Apple Inc.",
    "谷歌": "Alphabet Inc. (Class A)",
    "英镑": "British Pound (M2)",
    "微软": "Microsoft",
    "白银": "Silver",
    "亚马逊": "Amazon",
    "台积电": "Taiwan Semiconductor Manufacturing",
    "Meta": "Meta Platforms",
    "博通": "Broadcom",
    "沙特阿美": "Saudi Aramco",
    "比特币": "Bitcoin",
    "特斯拉": "Tesla, Inc.",
    "三星电子": "Samsung Electronics",
    "美光": "Micron Technology",
    "伯克希尔": "Berkshire Hathaway",
    "礼来": "Lilly (Eli)",
    "摩根大通": "JPMorgan Chase",
    "AMD": "Advanced Micro Devices",
    "沃尔玛": "Walmart",
    "Visa": "Visa Inc.",
    "埃克森美孚": "ExxonMobil",
    "强生": "Johnson & Johnson",
    "阿斯麦": "ASML Holding",
    "英特尔": "Intel",
    "万事达": "Mastercard",
    "腾讯": "Tencent Holdings",
    "字节跳动": "ByteDance",
    "艾伯维": "AbbVie",
    "思科": "Cisco",
    "甲骨文": "Oracle Corporation",
    "雪佛龙": "Chevron Corporation",
    "美国银行": "Bank of America",
    "Palantir": "Palantir Technologies",
    "好市多": "Costco",
    "戴尔": "Dell Technologies",
    "可口可乐": "Coca-Cola Company (The)",
    "卡特彼勒": "Caterpillar Inc.",
    "默克": "Merck & Co.",
    "汇丰": "HSBC Holdings",
    "罗氏": "Roche Holding",
    "宝洁": "Procter & Gamble",
    "联合健康": "UnitedHealth Group",
    "泛林集团": "Lam Research",
    "应用材料": "Applied Materials",
    "GE航空航天": "GE Aerospace",
    "摩根士丹利": "Morgan Stanley",
    "奈飞": "Netflix",
    "家得宝": "Home Depot (The)",
    "以太坊": "Ethereum",
    "菲利普莫里斯": "Philip Morris International",
    "加拿大皇家银行": "Royal Bank of Canada",
    "Arm": "Arm Holdings",
    "高盛": "Goldman Sachs",
    "诺华": "Novartis",
    "壳牌": "Shell",
    "富国银行": "Wells Fargo",
    "三菱日联": "Mitsubishi UFJ Financial",
    "雷神技术": "RTX Corporation",
    "阿里巴巴": "Alibaba Group",
    "阿斯利康": "AstraZeneca",
    "Palo Alto": "Palo Alto Networks",
    "SAP": "SAP SE",
    "GE 维尔诺瓦": "GE Vernova",
    "赛默飞": "Thermo Fisher Scientific",
    "雀巢": "Nestle",
    "闪迪": "Sandisk Corporation",
    "西门子": "Siemens",
    "德州仪器": "Texas Instruments",
    "路威酩轩": "LVMH",
    "丰田": "Toyota Motor",
    "花旗": "Citigroup",
    "科磊": "KLA Corporation",
    "必和必拓": "BHP Group",
    "桑坦德银行": "Banco Santander",
    "美国运通": "American Express",
    "林德": "Linde plc",
    "美满电子": "Marvell Technology, Inc.",
    "道明银行": "Toronto-Dominion Bank",
    "安进": "Amgen",
    "道达尔能源": "TotalEnergies",
    "威瑞森": "Verizon",
    "高通": "Qualcomm",
    "诺和诺德": "Novo Nordisk",
    "吉利德": "Gilead Sciences",
    "迪尔": "Deere & Company",
    "泰达币": "Tether",
    "迪士尼": "Walt Disney Company (The)",
    "百事": "PepsiCo",
    "嘉信理财": "Charles Schwab Corporation",
    "T-Mobile": "T-Mobile US",
    "希捷": "Seagate Technology",
    "雅培": "Abbott Laboratories",
    "亚德诺": "Analog Devices",
    "麦当劳": "McDonald's",
    "新纪元能源": "NextEra Energy",
    "联合太平洋": "Union Pacific Corporation",
    "瑞银": "UBS Group",
    "贝莱德": "BlackRock",
    "康菲石油": "ConocoPhillips",
    "西班牙对外银行": "Banco Bilbao Vizcaya",
    "力拓": "Rio Tinto",
    "伊顿": "Eaton Corporation",
    "辉瑞": "Pfizer",
    "波音": "Boeing",
    "百威英博": "Anheuser-Busch InBev",
    "盈透证券": "Interactive Brokers Group",
    "黑石": "Blackstone Inc.",
    "丹纳赫": "Danaher Corporation",
    "蚂蚁集团": "Ant Group",
    "西部数据": "Western Digital",
    "索尼": "Sony Group",
    "直觉外科": "Intuitive Surgical",
    "瑞穗金融": "Mizuho Financial",
    "联合利华": "Unilever",
    "纽蒙特": "Newmont",
    "安达保险": "Chubb Limited",
    "Booking": "Booking Holdings",
    "福泰制药": "Vertex Pharmaceuticals",
    "霍尼韦尔": "Honeywell",
    "百时美施贵宝": "Bristol Myers Squibb",
    "康宁": "Corning Inc.",
    "飞塔": "Fortinet",
    "前进保险": "Progressive Corporation",
    "普洛斯": "Prologis",
    "第一资本": "Capital One",
    "洛克希德·马丁": "Lockheed Martin",
    "马拉松石油": "Marathon Petroleum",
    "瓦莱罗能源": "Valero Energy",
    "英美烟草": "British American Tobacco",
    "标普全球": "S&P Global",
    "美敦力": "Medtronic",
    "派克汉尼汾": "Parker Hannifin",
    "埃森哲": "Accenture",
    "奥驰亚": "Altria",
    "HDFC银行": "HDFC Bank",
    "拼多多": "PDD Holdings",
    "星巴克": "Starbucks",
    "菲利普斯66": "Phillips 66",
    "劳氏": "Lowe's",
    "Spotify": "Spotify Technology",
    "史赛克": "Stryker Corporation",
    "ING 集团": "ING Groep",
    "纽约梅隆银行": "Bank of New York Mellon Corp",
    "赛诺菲": "Sanofi",
    "三井住友金融": "Sumitomo Mitsui Financial",
    "麦克森": "McKesson Corporation",
    "葛兰素史克": "GSK",
    "自由港麦克莫兰": "Freeport-McMoRan",
    "ICICI银行": "ICICI Bank",
    "信实零售": "Reliance Retail",
    "Adobe": "Adobe Inc.",
    "罗宾汉": "Robinhood Markets, Inc.",
    "爱彼迎": "Airbnb",
    "币安币": "BNB",
    "芝商所": "CME Group",
    "南方公司": "Southern Company",
    "安费诺": "Amphenol",
    "通用动力": "General Dynamics",
    "HCA 医疗": "HCA Healthcare",
    "星座能源": "Constellation Energy",
    "特灵科技": "Trane Technologies",
    "美国合众银行": "U.S. Bancorp",
    "PNC 金融服务": "PNC Financial Services",
    "维谛技术": "Vertiv Holdings Co",
    "杜克能源": "Duke Energy",
    "豪梅特航空": "Howmet Aerospace",
    "CSX 运输": "CSX Corporation",
    "万豪国际": "Marriott International",
    "威廉姆斯公司": "Williams Companies",
    "洲际交易所": "Intercontinental Exchange",
    "巴克莱": "Barclays",
    "劳埃德银行": "Lloyds Banking",
    "江森自控": "Johnson Controls",
    "废物管理公司": "Waste Management",
    "UPS": "United Parcel Service",
    "威达信集团": "Marsh & McLennan Companies, Inc.",
    "艾默生": "Emerson Electric",
    "美国电塔": "American Tower",
    "康卡斯特": "Comcast",
    "瑞波币": "XRP",
    "再生元": "Regeneron Pharmaceuticals",
    "埃尼": "Eni",
    "慧与": "Hewlett Packard Enterprise",
    "旅行者保险": "Travelers Companies (The)",
    "穆迪": "Moody's Corporation",
    "亿滋国际": "Mondelez International",
    "宣伟": "Sherwin-Williams",
    "通用汽车": "General Motors",
    "斯伦贝谢": "Schlumberger",
    "EOG 能源": "EOG Resources",
    "楷登电子": "Cadence Design Systems",
    "英国国家电网": "National Grid",
    "伊利诺伊工具": "Illinois Tool Works",
    "艺康": "Ecolab",
    "摩托罗拉系统": "Motorola Solutions",
    "网易": "NetEase",
    "诺斯罗普·格鲁曼": "Northrop Grumman",
    "USDC": "USD Coin",
    "罗斯百货": "Ross Stores",
    "宏利金融": "Manulife Financial",
    "新思科技": "Synopsys",
    "联邦快递": "FedEx",
    "信诺": "Cigna",
    "加拿大国家铁路": "Canadian National Railway",
    "房地产": "Real Estate",
    "大宗商品": "Commodities",
    "贵金属": "Precious Metals",
    "货币": "Currencies",
    "债券": "Bonds",
    "公司": "Companies",
    "加密货币": "Crypto",
    "住宅+商业+农地": "residential + commercial + farmland",
    "桶（探明储量）": "barrels (proven reserves)",
    "吨（探明储量）": "tonnes (proven reserves)",
    "全球公共债务余额": "global public debt outstanding",
    "元（广义货币 M2）": "CNY (broad money M2)",
    "探明储量估值": "valuation of proven reserves",
    "盎司（地面存量）": "ounces (above-ground stock)",
    "美元（广义货币 M2）": "USD (broad money M2)",
    "吨（储量）": "tonnes (reserves)",
    "磅（储量）": "pounds (reserves)",
    "欧元（广义货币 M3）": "EUR (broad money M3)",
    "日元（广义货币 M2）": "JPY (broad money M2)",
    "英镑（广义货币 M2）": "GBP (broad money M2)",
    "🌐 全球资产市值排行榜": "🌐 Global Assets by Market Cap",
    "不限品类 · 只看市值 · 房地产 / 国债 / 商品 / 货币 / 黄金 / 公司 / 加密货币 同台前 250": "All asset classes · Ranked only by market cap · Property / sovereign debt / commodities / currencies / gold / companies / crypto · Top 250",
    "市值排名": "Market Cap Rank",
    "搜索资产 / 代码（中 · 英）…": "Search asset / ticker…",
    "搜索资产 / 代码…": "Search asset / ticker…",
    "萨尔瓦多": "El Salvador",
    "关于本榜": "About this ranking",
    "Yahoo Finance · CoinGecko · 公开估算（世界黄金协会 / IMF / Savills 等）":
      "Yahoo Finance · CoinGecko · public estimates (World Gold Council, IMF, Savills and others)",
    "全球资产不限品类按市值排名（前 250）。商品/贵金属以储量或地面存量×日频行情、货币以广义货币 M2×日频汇率、公司/加密货币以最新市值快照计；房地产、政府债务、煤炭、天然气为权威机构存量估值（慢变量，静态基准）。每日自动更新，仅供参考，不构成投资建议。":
      "Global assets ranked by market cap across every class (top 250). Commodities and precious metals are valued as reserves or above-ground stock × daily prices; currencies as broad money M2 × daily exchange rates; companies and crypto from the latest market-cap snapshot. Real estate, government debt, coal and natural gas use stock valuations from established institutions (slow-moving variables held as a static baseline). Refreshed daily; for reference only, not investment advice.",
    "这是一张「不限品类、只看市值」的全球资产排行榜：把房地产、政府债券、煤炭、石油、天然气、铁矿石、铝、铜、黄金、白银、各国货币（广义货币 M2）、上市公司、加密货币放进同一张榜按美元市值从高到低排名，取前 250。计算方法与主流资产市值站一致——商品/贵金属按「储量或地面存量 × 实时行情」、货币按「广义货币 × 实时汇率」、公司与加密货币按实时市值；房地产、政府债务等慢变量采用权威机构存量估值。数据每日自动更新，来源 Yahoo Finance、CoinGecko 及世界黄金协会 / IMF / Savills 等公开估算，仅供参考，不构成任何投资建议。":
      "This is a ranking of global assets by market cap alone, with no restriction on asset class: real estate, government bonds, coal, oil, natural gas, iron ore, aluminium, copper, gold, silver, national currencies (broad money M2), listed companies and cryptocurrencies all sit in one table, ordered by USD market cap, top 250. The method matches the mainstream asset-valuation sites: commodities and precious metals as reserves or above-ground stock × live prices, currencies as broad money × live exchange rates, and companies and crypto at live market cap; slow-moving variables such as real estate and government debt use stock valuations from established institutions. Data refreshes daily from Yahoo Finance, CoinGecko and public estimates by the World Gold Council, the IMF, Savills and others. For reference only; not investment advice.",
    "没有匹配的资产，换个关键词或分类试试 🙂": "No matching assets. Try another keyword or category 🙂",
    "存量估值": "Stock valuation",
    "沿用上次": "Previous value retained",
    "加密货币": "Crypto",
    "房地产": "Real Estate",
    "国债": "Sovereign Debt",
    "商品": "Commodities",
    "货币": "Currencies",
    "黄金": "Gold",
    "公司": "Companies",
    "未上市": "Private",
    "上轮融资": "Last round",
    "🏆 榜首": "🏆 #1"
  };

  var HOUSE = {
    "实时榜 · OECD/BIS 每周自动更新": "Live ranking · OECD/BIS, refreshed weekly",
    "覆盖": "Coverage",
    "国/地区": "countries/regions",
    "👆 点击国家看近 20 年走势": "👆 Click a country for the past 20 years",
    "北美": "North America",
    "欧洲": "Europe",
    "亚太": "Asia-Pacific",
    "新兴/其他": "Emerging / Other",
    "哥斯达黎加": "Costa Rica",
    "搜索国家 / 地区…": "Search country / region…",
    "OECD 分析性房价指数 · 各国官方统计（中国国家统计局 70 城 / 香港差饷署 等）· BIS（每周自动刷新）":
      "OECD analytical house price indices · national official statistics (China NBS 70-city, Hong Kong Rating and Valuation Department, and others) · BIS (refreshed weekly)",
    "全球主要国家住宅房价指数（名义/实际同比、环比与近 20 年季度走势）。多数国家采用 OECD 分析性房价指数（跨国可比、口径一致）；OECD 未收录或口径差异较大的经济体改用其官方指数——中国用国家统计局 70 城新建商品住宅价格指数、香港用差饷物业估价署售价指数、新加坡用 URA 指数等。每周自动刷新，名义为当地货币现价、实际为经通胀调整，基期统一 2015=100。各国统计口径仍略有差异，仅供参考，不构成投资建议。":
      "Residential house price indices for major economies (nominal and real year-over-year, quarter-over-quarter, and roughly 20 years of quarterly history). Most countries use the OECD analytical house price index, which is consistent and comparable across borders; economies the OECD does not cover, or where definitions differ materially, use their official index instead — China uses the NBS 70-city new-build residential price index, Hong Kong the Rating and Valuation Department sale price index, Singapore the URA index, and so on. Refreshed weekly. Nominal is in current local currency and real is inflation-adjusted, all rebased to 2015=100. National definitions still differ slightly; for reference only, not investment advice.",
    "本页把全球主要国家的住宅房价放在同一张表横向对比：名义同比（当地货币现价涨跌）、实际同比（经通胀调整后的真实涨跌）、最近一季环比，以及近几年的季度走势迷你图，帮你快速看清「哪些国家房价在涨、哪些在跌」。点击任一国家可展开近 20 年（视各国可获取历史而定）的房价指数走势折线图，历史涨跌一目了然。数据来源 OECD 分析性房价指数与 BIS 住宅物业价格长序列，每周自动刷新；房价为季度数据，页面会自动接住各国最新已发布季度。各国统计口径与基期（2015=100）略有差异，且房价历史表现不代表未来，本页仅供参考，不构成任何投资建议。":
      "This page puts residential house prices for major economies into one comparable table: nominal year-over-year (current local-currency change), real year-over-year (the inflation-adjusted change), the most recent quarter-over-quarter move, and a sparkline of recent quarters — so you can see at a glance which countries are rising and which are falling. Click any country to expand a line chart of roughly 20 years of index history (as far back as each country publishes). Data comes from the OECD analytical house price indices and the BIS long series on residential property prices, refreshed weekly; house prices are quarterly, and the page automatically picks up each country's latest published quarter. Definitions and the 2015=100 base differ slightly by country, and past price behaviour does not predict future behaviour. For reference only; not investment advice.",
    "🏘️ 全球主要国家房价走势": "🏘️ Global Home Price Trends",
    "名义 / 实际同比 · 环比 · 点击国家看近 20 年走势 · 每周更新": "Nominal / real YoY · QoQ · Click a country for up to 20 years of history · Updated weekly",
    "名义同比": "Nominal YoY",
    "实际同比": "Real YoY",
    "环比": "QoQ",
    "搜索国家 / 地区（中 · 英）…": "Search country / region…",
    "暂无足够历史数据可展示": "Not enough historical data to display",
    "没有匹配的国家/地区，换个关键词或区域试试 🙂": "No matching country/region. Try another keyword or region 🙂",
    "指数": "Index",
    "截至": "As of",
    "近似": "Approx.",
    "沿用上次": "Previous value retained",
    "区间": "Period",
    "全期累计": "Total change",
    "峰值": "Peak",
    "较峰值": "vs. Peak",
    "实际": "Real",
    "名义房价指数": "Nominal home-price index",
    "当地货币": "local currency",
    "悬停查看各季读数": "Hover for quarterly readings",
    "近似序列": "Approximate series"
  };

  /* 国家/地区名在这些页面上是界面标签（地图图例、榜单表头、筛选条），不是数据正文，
     所以翻；名称一律用各国通行英文名，不音译。 */
  /* 板块/行业名同样是界面标注（行卡的第二行、筛选条），翻；公司名走数据里的 nameEn。 */
  var SECTOR = {
    "科技": "Technology", "互联网": "Internet", "人工智能": "Artificial Intelligence",
    "数据与AI": "Data & AI", "自动驾驶": "Autonomous Driving", "通信服务": "Communication Services",
    "金融": "Financials", "金融科技": "Fintech", "支付": "Payments", "医疗健康": "Healthcare",
    "可选消费": "Consumer Discretionary", "必需消费": "Consumer Staples", "零售": "Retail",
    "工业": "Industrials", "能源": "Energy", "原材料": "Materials", "公用事业": "Utilities",
    "房地产": "Real Estate", "加密货币": "Crypto"
  };

  var COUNTRY = {
    "美国": "United States", "中国": "China", "日本": "Japan", "德国": "Germany",
    "英国": "United Kingdom", "法国": "France", "印度": "India", "意大利": "Italy",
    "加拿大": "Canada", "韩国": "South Korea", "俄罗斯": "Russia", "巴西": "Brazil",
    "澳大利亚": "Australia", "西班牙": "Spain", "墨西哥": "Mexico", "印度尼西亚": "Indonesia",
    "荷兰": "Netherlands", "沙特阿拉伯": "Saudi Arabia", "沙特": "Saudi Arabia",
    "土耳其": "Türkiye", "瑞士": "Switzerland", "波兰": "Poland", "阿根廷": "Argentina",
    "比利时": "Belgium", "瑞典": "Sweden", "爱尔兰": "Ireland", "泰国": "Thailand",
    "以色列": "Israel", "奥地利": "Austria", "挪威": "Norway", "阿联酋": "United Arab Emirates",
    "尼日利亚": "Nigeria", "埃及": "Egypt", "南非": "South Africa", "丹麦": "Denmark",
    "新加坡": "Singapore", "马来西亚": "Malaysia", "菲律宾": "Philippines", "越南": "Vietnam",
    "孟加拉国": "Bangladesh", "巴基斯坦": "Pakistan", "智利": "Chile", "哥伦比亚": "Colombia",
    "秘鲁": "Peru", "罗马尼亚": "Romania", "捷克": "Czechia", "新西兰": "New Zealand",
    "芬兰": "Finland", "葡萄牙": "Portugal", "希腊": "Greece", "匈牙利": "Hungary",
    "斯洛伐克": "Slovakia", "斯洛文尼亚": "Slovenia", "立陶宛": "Lithuania",
    "拉脱维亚": "Latvia", "爱沙尼亚": "Estonia", "卢森堡": "Luxembourg",
    "塞浦路斯": "Cyprus", "马耳他": "Malta", "克罗地亚": "Croatia",
    "冰岛": "Iceland", "保加利亚": "Bulgaria", "乌克兰": "Ukraine",
    "香港": "Hong Kong SAR", "中国香港": "Hong Kong SAR",
    "台湾": "Taiwan", "中国台湾": "Taiwan", "澳门": "Macao SAR",
    "欧元区": "Euro Area", "全球": "Global", "经合组织": "OECD"
  };

  var WORLD = {
    "🌐 全球经济图谱": "🌐 World Economy Map",
    "各国经济状况概览 · 央行利率 · 通胀 · 失业 · 增长 · 债务 · 每日更新": "Country economic overview · Policy rates · Inflation · Unemployment · Growth · Debt · Updated daily",
    "背景音乐": "Background music",
    "切换地图 / 榜单": "Switch map / ranking",
    "悬停查看 · 滚轮缩放": "Hover for values · Scroll to zoom",
    "完整榜单": "Full Ranking",
    "暂无数据": "No data",
    "国家 / 地区": "Country / Region",
    "美元": "USD",
    "数据：": "Data: ",
    "单位": "Unit",
    "实时聚合 · 每日更新": "Live aggregate · Updated daily",
    "央行基准利率": "Policy Rate",
    "通胀率": "Inflation Rate",
    "失业率": "Unemployment Rate",
    "GDP增长": "GDP Growth",
    "政府债务/GDP": "Government Debt / GDP",
    "人均GDP": "GDP per Capita",
    "经常账户/GDP": "Current Account / GDP",
    "预期寿命": "Life Expectancy",
    "城镇化率": "Urbanization Rate",
    "出口/GDP": "Exports / GDP",
    "人口增长": "Population Growth",
    "储蓄率/GDP": "Savings Rate / GDP",
    "央行基准利率 · Policy Rate": "Policy Rate",
    "央行基准利率（%） ↓": "Policy Rate (%) ↓",
    "主要经济体央行政策利率（整理自公开资料）":
      "Central bank policy rates for major economies (compiled from public sources)",
    "World Bank Open Data · 央行基准利率：整理自公开资料":
      "World Bank Open Data · Policy rates compiled from public sources",
    "宏观指标来自世界银行公开数据（年度，取各国最新可得值，故年份可能不一）；央行基准利率为整理自公开资料的主要经济体政策利率，定期更新。仅供参考，不构成建议。":
      "Macro indicators come from World Bank Open Data (annual, taking each country's latest available value, so reference years can differ). Policy rates for major economies are compiled from public sources and refreshed periodically. For reference only; not advice.",
    "本页以世界地图形态展示各国关键经济指标——央行基准利率、通胀率、失业率、GDP 增长、政府债务等，便于横向对比各国经济状况，数据每日更新。各国统计口径与公布频率不同，跨国对比时请注意可比性，本页仅供宏观了解参考。":
      "This page lays key economic indicators — policy rate, inflation, unemployment, GDP growth, government debt and more — onto a world map so countries can be compared side by side, refreshed daily. Statistical definitions and release schedules differ by country, so take care when comparing across borders; this page is for general macro orientation only."
  };

  var SUPER = {
    /* 投资人、机构与持仓标的的中英对照全部逐条取自 apps/superinvestors/data.json
       （`zh`/`en`、`firmZh`/`firm`、持仓的 `zh`/`name`），生成而非手译。 */
    " ": " Vaneck ETF Trust（看跌期权）",
    " GE医疗": " Ge Healthcare Technologies Inc.",
    " GE维诺瓦(能源)": " Ge Vernova Inc",
    " KKR": " Kkr & Co Inc",
    " Nu控股": " Nu Holdings Ltd.",
    " Rivian": " Rivian Automotive Inc",
    " ServiceNow": " Servicenow Inc",
    " T-Mobile美国": " T-Mobile Us Inc",
    " Vistra能源": " Vistra Corp",
    " 先锋ETF": " Vanguard Scottsdale Fds Lg Ter",
    " 前进保险": " Progressive Corp",
    " 华纳兄弟探索": " Warner Bros Discovery Inc",
    " 可口可乐FEMSA": " Coca-Cola Femsa Sab De Cv",
    " 埃克森美孚": " Exxon Mobil Corp",
    " 声田": " Spotify Technology SA",
    " 威瑞信": " Verisign Inc",
    " 安硕ETF": " Ishares Tr",
    " 安硕ETF（看涨期权）": " Ishares Inc（看涨期权）",
    " 安硕ETF（看跌期权）": " Ishares Iboxx High Yield Corporate Bond ETF - Us E（看跌期权）",
    " 安谋": " Arm Holdings PLC",
    " 安达保险": " Chubb Limited",
    " 布鲁克菲尔德": " Brookfield Corp",
    " 希捷": " Seagate Technology Hldngs Pl",
    " 帕兰提尔": " Palantir Technologies Inc",
    " 帕兰提尔（看跌期权）": " Palantir Technologies Inc（看跌期权）",
    " 德维特": " Davita Inc",
    " 怡安": " Aon PLC",
    " 摩根士丹利": " Morgan Stanley ETF Trust",
    " 新闻集团": " News Corp",
    " 林德": " Linde PLC",
    " 法拉利": " Ferrari N V",
    " 派拓网络": " Palo Alto Networks Inc",
    " 海港娱乐": " Seaport Entmt Group Inc",
    " 福克斯": " Fox Corporation",
    " 罗宾侠": " Robinhood Markets Inc",
    " 联邦快递": " Fedex Fght Hldg Co Inc",
    " 西部数据": " Western Digital Corp",
    " 贝莱德": " Blackrock Inc",
    " 财捷": " Intuit Inc.",
    " 辉瑞": " Pfizer Inc",
    " 辉瑞（看涨期权）": " Pfizer Inc（看涨期权）",
    " 道富（看跌期权）": " State Street Energy Select Sector Spdr ETF - Us Et（看跌期权）",
    " 酷澎": " Coupang",
    " 阿里斯塔网络": " Arista Networks Inc",
    " 雪花公司": " Snowflake Inc",
    " 霍华德·休斯": " Howard Hughes Holdings Inc",
    " 餐饮品牌国际": " Restaurant Brands Intl Inc",
    "AAPL 苹果": "AAPL Apple Inc",
    "AAPL 苹果（看跌期权）": "AAPL Apple Inc（看跌期权）",
    "AB ": "AB AllianceBernstein Holding L.P. Units",
    "ABBV 艾伯维": "ABBV Abbvie Inc",
    "ABNB 爱彼迎": "ABNB Airbnb Inc",
    "ABT 雅培": "ABT Abbott Laboratories",
    "ACIW ": "ACIW ACI Worldwide Inc",
    "ADBE 奥多比": "ADBE Adobe Inc",
    "ADI ": "ADI Analog Devices Inc",
    "ADP ": "ADP Automatic Data Processing Inc",
    "AER ": "AER AerCap Holdings NV",
    "AIT ": "AIT Applied Industrial Technologies Inc",
    "AKAM 阿卡迈": "AKAM AKAMAI TECHNOLOGIES Inc",
    "ALLY ": "ALLY Ally Financial Inc",
    "AMAT 应用材料": "AMAT Applied Matls Inc",
    "AMD 超威半导体": "AMD Advanced Micro Devices Inc",
    "AMD 超威半导体（看跌期权）": "AMD Advanced Micro Devices Inc（看跌期权）",
    "AMGN 安进": "AMGN Amgen Inc",
    "AMRZ ": "AMRZ AMRIZE LTD",
    "AMZN 亚马逊": "AMZN Amazon Inc",
    "ANET 阿里斯塔网络": "ANET Arista Networks Inc",
    "APD 空气产品": "APD Air Products And Chemicals I",
    "AQR资本": "AQR Capital",
    "AQR资本 AQR Capital": "AQR Capital",
    "ARQT ": "ARQT ARCUTIS BIOTHERAPEUTICS INC",
    "ASML 阿斯麦": "ASML Asml Hldg Nv Nys",
    "AVB ": "AVB AvalonBay Communities Inc",
    "AVGO 博通": "AVGO Broadcom Inc",
    "AXON 艾克森企业": "AXON Axon Enterprise Inc",
    "AXP 美国运通": "AXP American Express Co",
    "AXTA ": "AXTA Axalta Coating Systems Ltd",
    "AZN 阿斯利康": "AZN Astrazeneca PLC",
    "AZO ": "AZO AutoZone Inc",
    "BA 波音": "BA Boeing Co",
    "BABA 阿里巴巴": "BABA Alibaba Group Hldg Ltd",
    "BAC 美国银行": "BAC Bank Of Amer Corp",
    "BBAI ": "BBAI BIGBEAR.AI HOLDINGS INC",
    "BK 纽约梅隆银行": "BK Bank Of York Mellon Corp",
    "BMY 百时美施贵宝": "BMY Bristol-Myers Squibb Co",
    "BRK.B 伯克希尔·哈撒韦": "BRK.B Berkshire Hathaway Inc",
    "BSX ": "BSX Boston Scientific Corp",
    "BX 黑石": "BX Blackstone Group Inc",
    "C 花旗集团": "C Citigroup Inc",
    "CAH ": "CAH Cardinal Health Inc",
    "CAT 卡特彼勒": "CAT Caterpillar Inc",
    "CHTR 特许通讯": "CHTR Charter Communications Inc",
    "CLF 克利夫兰-克利夫斯": "CLF Cloudflare Inc",
    "CMCSA 康卡斯特": "CMCSA Comcast Corp",
    "CME 芝商所": "CME Cme Group Inc",
    "CNI 加拿大国家铁路": "CNI Canadian Natl Ry Co",
    "COHR ": "COHR Coherent Corp",
    "COO ": "COO The Cooper Cos Inc",
    "COP 康菲石油": "COP Conocophillips",
    "COST 开市客": "COST Costco Wholesale",
    "CP 加拿大太平洋堪萨斯城": "CP Canadian Pacific Kansas City",
    "CRM 赛富时": "CRM Salesforce Inc",
    "CROX 卡骆驰": "CROX Crowdstrike Hldgs Inc",
    "CSCO 思科": "CSCO Cisco Sys Inc",
    "CSX CSX运输": "CSX Csx Corp",
    "CSX运输": "Csx Corp",
    "CVS CVS健康": "CVS Cvs Health Corp",
    "CVS健康": "Cvs Health Corp",
    "CVX 雪佛龙": "CVX Chevron Corporation",
    "D1资本": "D1 Capital",
    "D1资本 D1 Capital": "D1 Capital",
    "DAL 达美航空": "DAL Delta Air Lines Inc",
    "DE 迪尔": "DE Deere & Co",
    "DELL 戴尔": "DELL Dell Technologies Inc",
    "DHR 丹纳赫": "DHR Danaher Corp",
    "DIS 迪士尼": "DIS Disney Walt Company Holding Co",
    "EA 艺电": "EA Electronic Arts Inc",
    "ECL 艺康集团": "ECL Ecolab Inc",
    "EWBC 华美银行": "EWBC East West Bancorp Inc",
    "FAS ": "FAS Direxion Financial Bull 3X Shares",
    "FDX 联邦快递": "FDX Fedex Corp",
    "FIHBX ": "FIHBX FEDERATED HERMES HIGH YIELD BOND FUND",
    "FTNT ": "FTNT Fortinet Inc",
    "GE 通用电气": "GE Ge Aerospace",
    "GEV GE维诺瓦(能源)": "GEV GE VERNOVA INC",
    "GE医疗": "Ge Healthcare Technologies Inc.",
    "GE维诺瓦(能源)": "Ge Vernova Inc",
    "GLD 黄金ETF（看涨期权）": "GLD Spdr Gold Shares - Us Etp（看涨期权）",
    "GOOG 谷歌": "GOOG Alphabet Inc A类",
    "GOOGL 谷歌": "GOOGL Alphabet Inc. - Class A Common Stock",
    "GS 高盛": "GS Goldman Sachs Group Inc",
    "HAL 哈里伯顿（看涨期权）": "HAL Halliburton Co（看涨期权）",
    "HD 家得宝": "HD Home Depot Inc",
    "HLT 希尔顿": "HLT Hilton Worldwide Hldgs Inc",
    "HUM 哈门那": "HUM Humana Inc",
    "IBIT 安硕ETF": "IBIT ISHARES BITCOIN TRUST ETF",
    "ICE 洲际交易所": "ICE Intercontinental Exchange In",
    "INTC 英特尔": "INTC Intel Corp",
    "INTU 财捷": "INTU Intuit Inc",
    "IVV 安硕ETF": "IVV Ishares Tr",
    "IVV 安硕ETF（看涨期权）": "IVV Ishares Tr（看涨期权）",
    "IVV 安硕ETF（看跌期权）": "IVV Ishares Tr（看跌期权）",
    "JD·万斯": "J.D. Vance",
    "JNJ 强生": "JNJ Johnson & Johnson",
    "JPM 摩根大通": "JPM Jpmorgan Chase & Co",
    "KHC 卡夫亨氏": "KHC Kraft Heinz Co",
    "KKR": "Kkr & Co Inc",
    "KO 可口可乐": "KO Coca Cola Co",
    "KR 克罗格": "KR Kroger Co",
    "LH ": "LH Laboratory Corp of America Holdings",
    "LITE ": "LITE Lumentum Holdings Inc",
    "LLY 礼来": "LLY Eli Lilly & Co",
    "LRCX 泛林集团": "LRCX Lam Research Corp",
    "LULU 露露乐蒙": "LULU Lululemon Athletica Inc",
    "LULU 露露乐蒙（看涨期权）": "LULU Lululemon Athletica Inc（看涨期权）",
    "LUV 西南航空": "LUV Southwest Airls Co",
    "MA 万事达": "MA Mastercard Incorporated",
    "MAR 万豪": "MAR Marriott Intl Inc",
    "MCK ": "MCK McKesson Corp",
    "MCO 穆迪": "MCO Moodys Corp",
    "MELI 美客多": "MELI Mercadolibre Inc",
    "META Meta平台": "META Meta Platforms Inc",
    "META Meta平台（看涨期权）": "META Meta Platforms Inc（看涨期权）",
    "MPWR ": "MPWR Monolithic Power Systems Inc",
    "MRK 默沙东": "MRK Merck Co Inc",
    "MSCI MSCI明晟": "MSCI Msci Inc",
    "MSCI明晟": "Msci Inc",
    "MSFT 微软": "MSFT Microsoft Corp",
    "MTZ ": "MTZ MasTec Inc",
    "MU 美光科技": "MU Micron Technology Inc",
    "MU 美光科技（看涨期权）": "MU Micron Technology Inc（看涨期权）",
    "MU 美光科技（看跌期权）": "MU Micron Technology Inc（看跌期权）",
    "Meta平台": "Meta Platforms Inc",
    "Meta平台（看涨期权）": "Meta Platforms Inc（看涨期权）",
    "NFLX 奈飞": "NFLX Netflix Inc",
    "NSC 诺福克南方": "NSC Norfolk Southn Corp",
    "NUE 纽柯钢铁": "NUE Nucor Corp",
    "NVDA 英伟达": "NVDA Nvidia Corp",
    "NVDA 英伟达（看跌期权）": "NVDA Nvidia Corporation（看跌期权）",
    "NXPI ": "NXPI NXP Semiconductors NV",
    "Nu控股": "Nu Holdings Ltd.",
    "ORCL 甲骨文": "ORCL Oracle Corp",
    "ORLY 奥莱利汽配": "ORLY Organon & Co",
    "OXY 西方石油": "OXY Occidental Pete Corp",
    "PAYX ": "PAYX Paychex Inc",
    "PDD 拼多多": "PDD Pdd Holdings Inc",
    "PEP 百事": "PEP Pepsico, Inc.",
    "PG 宝洁": "PG Procter & Gamble Co",
    "PM 菲利普莫里斯": "PM Philip Morris International In",
    "PSX 菲利普斯66": "PSX Phillips 66",
    "PTON ": "PTON Peloton Interactive Inc",
    "PYPL 贝宝": "PYPL Paypal Hldgs Inc",
    "Point72资产管理": "Point72",
    "Point72资产管理 Point72": "Point72",
    "QCOM 高通": "QCOM Qualcomm Inc",
    "QQQ 纳指100 ETF（看涨期权）": "QQQ Invesco Qqq Tr（看涨期权）",
    "QQQ 纳指100 ETF（看跌期权）": "QQQ Invesco Qqq Tr（看跌期权）",
    "RBLX ": "RBLX Roblox Corp",
    "REGN 再生元": "REGN Regeneron Pharmaceuticals",
    "REGN 再生元（看涨期权）": "REGN Regeneron Pharmaceuticals（看涨期权）",
    "Rivian": "Rivian Automotive Inc",
    "SBUX 星巴克": "SBUX Starbucks Corp",
    "SCHW 嘉信理财": "SCHW Schwab Charles Corp",
    "SE 冬海集团": "SE Sea Ltd ADR",
    "SFTBY ": "SFTBY Softbank Group Corp",
    "SHOP Shopify": "SHOP Shopify 'A'",
    "SHW 宣伟": "SHW Sherwin Williams Co",
    "SPGI 标普全球": "SPGI S&P Global Inc",
    "SPY 标普500 ETF": "SPY State Str Spdr S&P 500 ETF T",
    "SPY 标普500 ETF（看涨期权）": "SPY State Str Spdr S&P 500 ETF T（看涨期权）",
    "SPY 标普500 ETF（看跌期权）": "SPY State Str Spdr S&P 500 ETF T（看跌期权）",
    "SQ ": "SQ Block Inc",
    "STZ 星座品牌": "STZ Stryker Corporation",
    "ServiceNow": "Servicenow Inc",
    "Shopify": "Shopify 'A'",
    "T-Mobile美国": "T-Mobile Us Inc",
    "TCBI ": "TCBI Texas Capital Bancshares Inc",
    "TEL ": "TEL TE Connectivity Ltd",
    "TEM ": "TEM Tempus AI, Inc. - Class A Common",
    "TER ": "TER Teradyne Inc",
    "TJX TJX折扣百货": "TJX Tyson Foods Inc",
    "TJX折扣百货": "Tyson Foods Inc",
    "TME 腾讯音乐": "TME Tencent Music Entertainm",
    "TMO 赛默飞世尔": "TMO Thermo Fisher Scientific Inc",
    "TPH ": "TPH Tri Pointe Homes Inc",
    "TSLA 特斯拉": "TSLA Tesla Inc",
    "TSLA 特斯拉（看涨期权）": "TSLA Tesla Inc（看涨期权）",
    "TSM 台积电": "TSM Taiwan Semiconductor Manuf ADR",
    "TSM 台积电（看跌期权）": "TSM Taiwan Semiconductor Manufacturing Co Ltd - Us ADR（看跌期权）",
    "TTWO ": "TTWO Take-Two Interactive Software Inc",
    "TXN 德州仪器": "TXN Texas Instruments Ord",
    "UBER 优步": "UBER Uber Technologies Inc",
    "UNH 联合健康": "UNH Unitedhealth Group Inc",
    "UNH 联合健康（看涨期权）": "UNH Unitedhealth Group Inc（看涨期权）",
    "UNP 联合太平洋": "UNP Union Pac Corp",
    "UPS 联合包裹": "UPS United Parcel Svcs Inc",
    "USB 美国合众银行": "USB Us Bancorp",
    "USO ": "USO United States Oil Fund",
    "V 维萨": "V Visa Inc",
    "VMC ": "VMC Vulcan Materials Co",
    "VOO 先锋标普500 ETF": "VOO Vanguard Index Fds",
    "VSNT ": "VSNT Versant Media Group, Inc. - Class A Common Stock",
    "VST Vistra能源": "VST Vistra Corp. Common Stock",
    "Vistra能源": "Vistra Corp",
    "WDAY ": "WDAY Workday Inc",
    "WFC 富国银行": "WFC Wells Fargo & Co",
    "WM 废物管理": "WM Waste Mgmt Inc",
    "WMT 沃尔玛": "WMT Walmart Inc",
    "WRB ": "WRB Berkley (W.R.) Corp",
    "WYNN 永利度假村": "WYNN Wynn Resorts, Limited",
    "XLP ": "XLP SPDR Select Sector Fund - Consumer Staples",
    "XLU ": "XLU The Utilities Select Sector SPDR Fund",
    "XLV ": "XLV The Health Care Select Sector SPDR Fund",
    "XOM 埃克森美孚": "XOM Exxon Mobil Corp",
    "万事达": "Mastercard Incorporated",
    "万豪": "Marriott Intl Inc",
    "东南资产管理": "Southeastern AM (Longleaf)",
    "东南资产管理 Southeastern AM (Longleaf)": "Southeastern AM (Longleaf)",
    "中投公司": "China CIC",
    "丹·克伦肖": "Dan Crenshaw",
    "丹·桑德海姆": "Dan Sundheim",
    "丹尼尔·勒布": "Daniel Loeb",
    "丹纳赫": "Danaher Corp",
    "丽莎·麦克莱恩": "Lisa McClain",
    "乔什·戈特海默": "Josh Gottheimer",
    "乔尔·格林布拉特": "Joel Greenblatt",
    "亚马逊": "Amazon Inc",
    "价值行动资本": "ValueAct Capital",
    "价值行动资本 ValueAct Capital": "ValueAct Capital",
    "伊兹·英格兰德": "Izzy Englander",
    "伊坎资本": "Icahn Capital",
    "伊坎资本 Icahn Capital": "Icahn Capital",
    "伊朗国家发展基金": "Iran NDF",
    "优步": "Uber Technologies Inc",
    "伯克希尔·哈撒韦": "Berkshire Hathaway",
    "伯克希尔·哈撒韦 Berkshire Hathaway": "Berkshire Hathaway",
    "俄罗斯国家财富基金": "Russia NWF",
    "保尔森公司": "Paulson & Co",
    "保尔森公司 Paulson & Co": "Paulson & Co",
    "保罗·辛格": "Paul Singer",
    "保罗·都铎·琼斯": "Paul Tudor Jones",
    "先锋ETF": "Vanguard Scottsdale Fds Lg Ter",
    "先锋标普500 ETF": "Vanguard Index Fds",
    "克利夫兰-克利夫斯": "Cloudflare Inc",
    "克罗格": "Kroger Co",
    "克莱奥·菲尔兹": "Cleo Fields",
    "克里夫·阿斯内斯": "Cliff Asness",
    "克里斯·霍恩": "Chris Hohn",
    "再生元": "Regeneron Pharmaceuticals",
    "再生元（看涨期权）": "Regeneron Pharmaceuticals（看涨期权）",
    "冬海集团": "Sea Ltd ADR",
    "凯茜·伍德": "Cathie Wood",
    "前进保险": "Progressive Corp",
    "加德纳·鲁索": "Gardner Russo & Quinn",
    "加德纳·鲁索 Gardner Russo & Quinn": "Gardner Russo & Quinn",
    "加拿大养老基金": "CPP Investments",
    "加拿大养老基金 CPP Investments": "CPP Investments",
    "加拿大国家铁路": "Canadian Natl Ry Co",
    "加拿大太平洋堪萨斯城": "Canadian Pacific Kansas City",
    "包普斯特集团": "Baupost Group",
    "包普斯特集团 Baupost Group": "Baupost Group",
    "千禧管理": "Millennium Management",
    "千禧管理 Millennium Management": "Millennium Management",
    "华纳兄弟探索": "Warner Bros Discovery Inc",
    "华美银行": "East West Bancorp Inc",
    "华莱士·魏茨": "Wally Weitz",
    "南希·佩洛西": "Nancy Pelosi",
    "博通": "Broadcom Inc",
    "卡塔尔投资局": "Qatar QIA",
    "卡夫亨氏": "Kraft Heinz Co",
    "卡尔·伊坎": "Carl Icahn",
    "卡恩兄弟": "Kahn Brothers",
    "卡恩兄弟集团": "Kahn Brothers Group",
    "卡恩兄弟集团 Kahn Brothers Group": "Kahn Brothers Group",
    "卡特彼勒": "Caterpillar Inc",
    "卡骆驰": "Crowdstrike Hldgs Inc",
    "双西格玛": "Two Sigma",
    "双西格玛投资": "Two Sigma Investments",
    "双西格玛投资 Two Sigma Investments": "Two Sigma Investments",
    "可口可乐": "Coca Cola Co",
    "可口可乐FEMSA": "Coca-Cola Femsa Sab De Cv",
    "台积电": "Taiwan Semiconductor Manuf ADR",
    "台积电（看跌期权）": "Taiwan Semiconductor Manufacturing Co Ltd - Us ADR（看跌期权）",
    "史蒂夫·科恩": "Steve Cohen",
    "吉姆·班克斯": "Jim Banks",
    "吉尔伯特·西斯内罗斯": "Gilbert Cisneros",
    "哈里伯顿（看涨期权）": "Halliburton Co（看涨期权）",
    "哈里斯联合": "Harris Associates (Oakmark)",
    "哈里斯联合 Harris Associates (Oakmark)": "Harris Associates (Oakmark)",
    "哈里斯联合(奥克马克)": "Harris Associates",
    "哈门那": "Humana Inc",
    "喜马拉雅资本": "Himalaya Capital",
    "喜马拉雅资本 Himalaya Capital": "Himalaya Capital",
    "嘉信理财": "Schwab Charles Corp",
    "土耳其财富基金": "Turkey TWF",
    "埃克森美孚": "Exxon Mobil Corp",
    "埃利奥特投资管理": "Elliott Management",
    "埃利奥特投资管理 Elliott Management": "Elliott Management",
    "城堡投资": "Citadel Advisors",
    "城堡投资 Citadel Advisors": "Citadel Advisors",
    "塞恩资产管理": "Scion Asset Management",
    "塞恩资产管理 Scion Asset Management": "Scion Asset Management",
    "声田": "Spotify Technology SA",
    "大卫·泰珀": "David Tepper",
    "大卫·艾布拉姆斯": "David Abrams",
    "奈飞": "Netflix Inc",
    "奥多比": "Adobe Inc",
    "奥莱利汽配": "Organon & Co",
    "威瑞信": "Verisign Inc",
    "孤松资本": "Lone Pine Capital",
    "孤松资本 Lone Pine Capital": "Lone Pine Capital",
    "安德烈亚斯·哈尔沃森": "Andreas Halvorsen",
    "安硕ETF": "Ishares Tr",
    "安硕ETF（看涨期权）": "Ishares Tr（看涨期权）",
    "安硕ETF（看跌期权）": "Ishares Tr（看跌期权）",
    "安谋": "Arm Holdings PLC",
    "安达保险": "Chubb Limited",
    "安进": "Amgen Inc",
    "宝洁": "Procter & Gamble Co",
    "宣伟": "Sherwin Williams Co",
    "家得宝": "Home Depot Inc",
    "富国银行": "Wells Fargo & Co",
    "布拉德·格斯特纳": "Brad Gerstner",
    "布鲁克菲尔德": "Brookfield Corp",
    "布鲁斯·伯考维茨": "Bruce Berkowitz",
    "希尔顿": "Hilton Worldwide Hldgs Inc",
    "希捷": "Seagate Technology Hldngs Pl",
    "帕兰提尔": "Palantir Technologies Inc",
    "帕兰提尔（看跌期权）": "Palantir Technologies Inc（看跌期权）",
    "应用材料": "Applied Matls Inc",
    "废物管理": "Waste Mgmt Inc",
    "康卡斯特": "Comcast Corp",
    "康菲石油": "Conocophillips",
    "开市客": "Costco Wholesale",
    "强生": "Johnson & Johnson",
    "微软": "Microsoft Corp",
    "德劭基金": "D.E. Shaw",
    "德劭集团": "D.E. Shaw & Co",
    "德劭集团 D.E. Shaw & Co": "D.E. Shaw & Co",
    "德州仪器": "Texas Instruments Ord",
    "德州永久学校基金": "Texas Permanent School",
    "德州永久学校基金 Texas Permanent School": "Texas Permanent School",
    "德维特": "Davita Inc",
    "思科": "Cisco Sys Inc",
    "怡安": "Aon PLC",
    "戴夫·麦考密克": "Dave McCormick",
    "戴尔": "Dell Technologies Inc",
    "打孔卡资本管理": "Punch Card Management",
    "打孔卡资本管理 Punch Card Management": "Punch Card Management",
    "托尼·维德": "Tony Wied",
    "拼多多": "Pdd Holdings Inc",
    "挪威主权基金": "Norges Bank",
    "挪威主权基金 Norges Bank": "Norges Bank",
    "摩根士丹利": "Morgan Stanley ETF Trust",
    "摩根大通": "Jpmorgan Chase & Co",
    "文艺复兴科技": "Renaissance Tech",
    "文艺复兴科技(西蒙斯)": "Renaissance Technologies",
    "文艺复兴科技(西蒙斯) Renaissance Technologies": "Renaissance Technologies",
    "斯坦利·德鲁肯米勒": "Stanley Druckenmiller",
    "斯蒂芬·曼德尔": "Stephen Mandel",
    "新加坡 GIC": "Singapore GIC",
    "新西兰超级基金": "NZ Super Fund",
    "新闻集团": "News Corp",
    "方舟投资": "ARK Invest",
    "方舟投资 ARK Invest": "ARK Invest",
    "星巴克": "Starbucks Corp",
    "星座品牌": "Stryker Corporation",
    "星板价值": "Starboard Value",
    "星板价值 Starboard Value": "Starboard Value",
    "普泽纳投资管理": "Pzena Investment",
    "普泽纳投资管理 Pzena Investment": "Pzena Investment",
    "普雷姆·瓦特萨": "Prem Watsa",
    "李录": "Li Lu",
    "杜肯家族办公室": "Duquesne Family Office",
    "杜肯家族办公室 Duquesne Family Office": "Duquesne Family Office",
    "杰夫·史密斯": "Jeff Smith",
    "林德": "Linde PLC",
    "枫信金融": "Fairfax Financial",
    "枫信金融 Fairfax Financial": "Fairfax Financial",
    "柏基投资": "Baillie Gifford",
    "柏基投资 Baillie Gifford & Co": "Baillie Gifford & Co",
    "查克·阿克瑞": "Chuck Akre",
    "标普500 ETF": "State Str Spdr S&P 500 ETF T",
    "标普500 ETF（看涨期权）": "State Str Spdr S&P 500 ETF T（看涨期权）",
    "标普500 ETF（看跌期权）": "State Str Spdr S&P 500 ETF T（看跌期权）",
    "标普全球": "S&P Global Inc",
    "桥水基金": "Bridgewater Associates",
    "桥水基金 Bridgewater Associates": "Bridgewater Associates",
    "梅森·莫菲特": "Mason Morfit",
    "梅森·霍金斯": "Mason Hawkins",
    "橡树资本": "Oaktree Capital",
    "橡树资本 Oaktree Capital": "Oaktree Capital",
    "每日期刊(芒格遗产)": "Daily Journal",
    "每日期刊公司": "Daily Journal Corp",
    "每日期刊公司 Daily Journal Corp": "Daily Journal Corp",
    "比尔·米勒": "Bill Miller",
    "比尔·阿克曼": "Bill Ackman",
    "永利度假村": "Wynn Resorts, Limited",
    "汤姆·盖纳": "Tom Gayner",
    "汤姆·鲁索": "Tom Russo",
    "汤米·塔伯维尔": "Tommy Tuberville",
    "沃伦·巴菲特": "Warren Buffett",
    "沃尔玛": "Walmart Inc",
    "沙特公共投资基金": "Saudi PIF",
    "沙特公共投资基金 Saudi PIF": "Saudi PIF",
    "法拉利": "Ferrari N V",
    "法拉龙资本": "Farallon Capital",
    "法拉龙资本 Farallon Capital": "Farallon Capital",
    "泛林集团": "Lam Research Corp",
    "波伦资本": "Polen Capital",
    "波伦资本 Polen Capital": "Polen Capital",
    "波音": "Boeing Co",
    "洲际交易所": "Intercontinental Exchange In",
    "派拓网络": "Palo Alto Networks Inc",
    "海港娱乐": "Seaport Entmt Group Inc",
    "淡马锡": "Temasek Holdings",
    "淡马锡 Temasek Holdings": "Temasek Holdings",
    "潘兴广场资本": "Pershing Square",
    "潘兴广场资本 Pershing Square": "Pershing Square",
    "澳大利亚未来基金": "Australia Future Fund",
    "爱彼迎": "Airbnb Inc",
    "爱瑞尔投资": "Ariel Investments",
    "爱瑞尔投资 Ariel Investments": "Ariel Investments",
    "特威迪·布朗": "Tweedy Browne",
    "特威迪·布朗 Tweedy, Browne Co": "Tweedy, Browne Co",
    "特斯拉": "Tesla Inc",
    "特斯拉（看涨期权）": "Tesla Inc（看涨期权）",
    "特许通讯": "Charter Communications Inc",
    "特里·史密斯": "Terry Smith",
    "特里安基金": "Trian Fund Management",
    "特里安基金 Trian Fund Management": "Trian Fund Management",
    "玛乔丽·泰勒·格林": "Marjorie Taylor Greene",
    "理查德·普泽纳": "Richard Pzena",
    "瑞·达利欧": "Ray Dalio",
    "甲骨文": "Oracle Corp",
    "百事": "Pepsico, Inc.",
    "百时美施贵宝": "Bristol-Myers Squibb Co",
    "盖茨基金会信托": "Gates Foundation",
    "盖茨基金会信托 B&M Gates Foundation Trust": "B&M Gates Foundation Trust",
    "礼来": "Eli Lilly & Co",
    "福克斯": "Fox Corporation",
    "科威特投资局": "Kuwait KIA",
    "穆巴达拉": "Mubadala",
    "穆巴达拉 Mubadala": "Mubadala",
    "穆迪": "Moodys Corp",
    "空气产品": "Air Products And Chemicals I",
    "第三点资本": "Third Point",
    "第三点资本 Third Point": "Third Point",
    "米勒价值合伙": "Miller Value Partners",
    "米勒价值合伙 Miller Value Partners": "Miller Value Partners",
    "索罗斯基金管理": "Soros Fund Management",
    "索罗斯基金管理 Soros Fund Management": "Soros Fund Management",
    "索罗斯家族办公室": "George Soros",
    "约翰·保尔森": "John Paulson",
    "约翰·罗杰斯": "John Rogers",
    "纳尔逊·佩尔茨": "Nelson Peltz",
    "纳指100 ETF（看涨期权）": "Invesco Qqq Tr（看涨期权）",
    "纳指100 ETF（看跌期权）": "Invesco Qqq Tr（看跌期权）",
    "纽柯钢铁": "Nucor Corp",
    "纽约梅隆银行": "Bank Of York Mellon Corp",
    "维京环球": "Viking Global",
    "维京环球 Viking Global": "Viking Global",
    "维萨": "Visa Inc",
    "罗·卡纳": "Ro Khanna",
    "罗宾侠": "Robinhood Markets Inc",
    "美光科技": "Micron Technology Inc",
    "美光科技（看涨期权）": "Micron Technology Inc（看涨期权）",
    "美光科技（看跌期权）": "Micron Technology Inc（看跌期权）",
    "美国合众银行": "Us Bancorp",
    "美国运通": "American Express Co",
    "美国银行": "Bank Of Amer Corp",
    "美客多": "Mercadolibre Inc",
    "老虎环球基金": "Tiger Global",
    "老虎环球基金 Tiger Global": "Tiger Global",
    "联合健康": "Unitedhealth Group Inc",
    "联合健康（看涨期权）": "Unitedhealth Group Inc（看涨期权）",
    "联合包裹": "United Parcel Svcs Inc",
    "联合太平洋": "Union Pac Corp",
    "联邦快递": "Fedex Corp",
    "肯·格里芬": "Ken Griffin",
    "肯·费雪": "Ken Fisher",
    "腾讯音乐": "Tencent Music Entertainm",
    "艺康集团": "Ecolab Inc",
    "艺电": "Electronic Arts Inc",
    "艾伯维": "Abbvie Inc",
    "艾克森企业": "Axon Enterprise Inc",
    "艾布拉姆斯资本": "Abrams Capital",
    "艾布拉姆斯资本 Abrams Capital": "Abrams Capital",
    "芝商所": "Cme Group Inc",
    "芬德史密斯": "Fundsmith",
    "芬德史密斯 Fundsmith": "Fundsmith",
    "花旗集团": "Citigroup Inc",
    "苏珊·德尔贝内": "Suzan DelBene",
    "英伟达": "Nvidia Corp",
    "英伟达（看跌期权）": "Nvidia Corporation（看跌期权）",
    "英国儿童投资基金": "TCI Fund Management",
    "英国儿童投资基金 TCI Fund Management": "TCI Fund Management",
    "英特尔": "Intel Corp",
    "苹果": "Apple Inc",
    "苹果（看跌期权）": "Apple Inc（看跌期权）",
    "莫尼什·帕伯莱": "Mohnish Pabrai",
    "菲利普·拉丰": "Philippe Laffont",
    "菲利普斯66": "Phillips 66",
    "菲利普莫里斯": "Philip Morris International In",
    "蔡斯·科尔曼": "Chase Coleman",
    "蔻图资本": "Coatue Management",
    "蔻图资本 Coatue Management": "Coatue Management",
    "西南航空": "Southwest Airls Co",
    "西方石油": "Occidental Pete Corp",
    "西部数据": "Western Digital Corp",
    "诺伯特·卢": "Norbert Lou",
    "诺福克南方": "Norfolk Southn Corp",
    "谷歌": "Alphabet Inc A类",
    "贝宝": "Paypal Hldgs Inc",
    "贝莱德": "Blackrock Inc",
    "财捷": "Intuit Inc.",
    "费尔霍姆资本": "Fairholme Capital",
    "费尔霍姆资本 Fairholme Capital": "Fairholme Capital",
    "费雪投资": "Fisher Investments",
    "费雪投资 Fisher Investments": "Fisher Investments",
    "赛富时": "Salesforce Inc",
    "赛斯·卡拉曼": "Seth Klarman",
    "赛默飞世尔": "Thermo Fisher Scientific Inc",
    "超威半导体": "Advanced Micro Devices Inc",
    "超威半导体（看跌期权）": "Advanced Micro Devices Inc（看跌期权）",
    "辉瑞": "Pfizer Inc",
    "辉瑞（看涨期权）": "Pfizer Inc（看涨期权）",
    "达拉尔街": "Dalal Street",
    "达拉尔街 Dalal Street": "Dalal Street",
    "达美航空": "Delta Air Lines Inc",
    "迈克尔·伯里": "Michael Burry",
    "迈克尔·麦考尔": "Michael McCaul",
    "迪士尼": "Disney Walt Company Holding Co",
    "迪尔": "Deere & Co",
    "通用电气": "Ge Aerospace",
    "道富（看跌期权）": "State Street Energy Select Sector Spdr ETF - Us Et（看跌期权）",
    "都铎投资": "Tudor Investment",
    "都铎投资 Tudor Investment": "Tudor Investment",
    "酷澎": "Coupang",
    "里克·斯科特": "Rick Scott",
    "阿克瑞资本": "Akre Capital",
    "阿克瑞资本 Akre Capital": "Akre Capital",
    "阿卡迈": "AKAMAI TECHNOLOGIES Inc",
    "阿尔提米特资本": "Altimeter Capital",
    "阿尔提米特资本 Altimeter Capital": "Altimeter Capital",
    "阿布扎比 ADQ": "Abu Dhabi ADQ",
    "阿布扎比投资局": "Abu Dhabi ADIA",
    "阿布扎比穆巴达拉": "Mubadala",
    "阿帕卢萨管理": "Appaloosa",
    "阿帕卢萨管理 Appaloosa": "Appaloosa",
    "阿拉斯加永久基金": "Alaska Permanent",
    "阿斯利康": "Astrazeneca PLC",
    "阿斯麦": "Asml Hldg Nv Nys",
    "阿里巴巴": "Alibaba Group Hldg Ltd",
    "阿里斯塔网络": "Arista Networks Inc",
    "雅克曼资产管理": "Yacktman AM",
    "雅克曼资产管理 Yacktman Asset Management": "Yacktman Asset Management",
    "雅培": "Abbott Laboratories",
    "雪佛龙": "Chevron Corporation",
    "雪花公司": "Snowflake Inc",
    "霍华德·休斯": "Howard Hughes Holdings Inc",
    "霍华德·马克斯": "Howard Marks",
    "露露乐蒙": "Lululemon Athletica Inc",
    "露露乐蒙（看涨期权）": "Lululemon Athletica Inc（看涨期权）",
    "韩国投资公司": "Korea Investment Corp",
    "韩国投资公司 Korea Investment Corp": "Korea Investment Corp",
    "餐饮品牌国际": "Restaurant Brands Intl Inc",
    "香港金管局": "Hong Kong HKMA",
    "马克尔集团": "Markel Group",
    "马克尔集团 Markel Group": "Markel Group",
    "马克韦恩·穆林": "Markwayne Mullin",
    "马歇尔·韦斯": "Marshall Wace",
    "马歇尔·韦斯 Marshall Wace": "Marshall Wace",
    "高盛": "Goldman Sachs Group Inc",
    "高谭资产管理": "Gotham Asset Management",
    "高谭资产管理 Gotham Asset Management": "Gotham Asset Management",
    "高通": "Qualcomm Inc",
    "魏茨投资管理": "Weitz Investment",
    "魏茨投资管理 Weitz Investment": "Weitz Investment",
    "黄金ETF（看涨期权）": "Spdr Gold Shares - Us Etp（看涨期权）",
    "黑石": "Blackstone Group Inc",
    "默沙东": "Merck Co Inc",
    "💼 超级投资者 · 持仓与情绪": "💼 Superinvestors · Holdings & Sentiment",
    "约 60 位大佬 13F 持仓 · 佩洛西等政治人物交易 · 中英对照 · AAII 情绪 · 每周自动更新":
      "13F holdings from about 60 well-known investors · Congressional trades including Pelosi · AAII sentiment · Updated weekly",
    "🏦 大佬持仓": "🏦 Investor Holdings",
    "🌐 主权基金": "🌐 Sovereign Funds",
    "🏛 政治人物": "🏛 Politicians",
    "🌡 AAII 情绪": "🌡 AAII Sentiment",
    "🌐 主权财富基金 · 前十大持仓": "🌐 Sovereign Wealth Funds · Top 10 Holdings",
    "SEC 提交 13F 的主权基金 · 点击展开": "Sovereign funds that file 13Fs with the SEC · click to expand",
    "🏆 全球前 20 大主权财富基金（按规模）": "🏆 Top 20 Sovereign Wealth Funds by Size",
    "✅ 披露 13F 美股持仓（上方可展开） · ⛔ 不披露/经外部管理人持有":
      "✅ Discloses U.S. holdings via 13F (expandable above) · ⛔ Does not disclose, or holds through external managers",
    "✅ 有持仓": "✅ Holdings disclosed",
    "⛔ 不披露": "⛔ Not disclosed",
    /* 政治人物板块：党派、议院与州名 */
    "民主党": "Democrat", "共和党": "Republican", "无党派": "Independent",
    "众议院": "House", "参议院": "Senate", "副总统(前参议员)": "Vice President (former Senator)",
    "加利福尼亚": "California", "佛罗里达": "Florida", "宾夕法尼亚": "Pennsylvania",
    "华盛顿州": "Washington", "俄亥俄": "Ohio", "新泽西": "New Jersey",
    "路易斯安那": "Louisiana", "俄克拉荷马": "Oklahoma", "阿拉巴马": "Alabama",
    "威斯康星": "Wisconsin", "得克萨斯": "Texas", "佐治亚": "Georgia",
    "密歇根": "Michigan", "印第安纳": "Indiana", "纽约": "New York",
    "伊利诺伊": "Illinois", "北卡罗来纳": "North Carolina", "弗吉尼亚": "Virginia",
    "马里兰": "Maryland", "马萨诸塞": "Massachusetts", "田纳西": "Tennessee",
    "亚利桑那": "Arizona", "科罗拉多": "Colorado", "明尼苏达": "Minnesota",
    "密苏里": "Missouri", "南卡罗来纳": "South Carolina", "肯塔基": "Kentucky",
    "阿布扎比": "Abu Dhabi",
    "🌡 AAII 投资者情绪调查": "🌡 AAII Investor Sentiment Survey",
    "美国个人投资者协会 · 每周四发布 · 未来六个月股市看法":
      "American Association of Individual Investors · published every Thursday · outlook for stocks over the next six months",
    "历史平均": "Historical average",
    "本周": "This week",
    "12 周 · 新在上": "12 weeks · newest first",
    "数据来源：": "Sources: ",
    "（机构与主权基金季度持仓）·": " (quarterly holdings of institutions and sovereign funds) · ",
    "STOCK Act 披露": "STOCK Act disclosures",
    "（议员交易）·": " (congressional trades) · ",
    "（每周四发布）": " (published every Thursday)",
    "个百分点 · 52 周看涨最高 49.5%（2026-01-15） · 最低 28.8%（2026-09-17）。情绪极端时常被用作反向参考。":
      " percentage points · 52-week bullish high 49.5% (2026-01-15), low 28.8% (2026-09-17). Sentiment extremes are often read as a contrarian cue.",
    "规模为近似值（约 7 家披露 13F）。ADIA、沙特 PIF、中投、科威特、卡塔尔等不向 SEC 申报，免费公开渠道无美股持仓明细。":
      "Sizes are approximate (about seven funds file 13Fs). ADIA, Saudi PIF, CIC, Kuwait, Qatar and others do not file with the SEC, so no U.S. holdings detail is available through free public channels.",
    "13F 为机构按季度向 SEC 披露的美股多头持仓，最长滞后 45 天，且不含空头、债券与海外持仓；主权财富基金仅收录向 SEC 提交 13F 者（挪威、新加坡、加拿大等），ADIA、沙特 PIF、中投等不申报或经外部管理人持有，无公开美股持仓明细；国会议员交易来自 STOCK Act 披露（金额为区间估算，披露最长滞后 45 天）；AAII 情绪调查每周四发布。公司中文名为常用译名，以英文原名为准。人物头像来自维基百科与美国国会官方照片库。仅供参考，不构成投资建议。":
      "A 13F is the quarterly disclosure institutions file with the SEC covering long U.S. equity positions, lagging by up to 45 days and excluding shorts, bonds and overseas holdings. Only sovereign wealth funds that file 13Fs are listed (Norway, Singapore, Canada and others); ADIA, Saudi PIF, CIC and others either do not file or hold through external managers, so no public U.S. holdings detail exists. Congressional trades come from STOCK Act disclosures (amounts are range estimates, disclosed up to 45 days late). The AAII sentiment survey is published every Thursday. Chinese company names are common translations; the English original governs. Portraits come from Wikipedia and the official U.S. Congress photo library. For reference only; not investment advice.",
    "本页追踪巴菲特、达利欧、索罗斯、李录、伯里等约 60 位超级投资者与顶级机构（含桥水、城堡、文艺复兴、挪威主权基金等）向 SEC 提交的 13F 季度持仓报告，公司与机构名称均为中英对照：组合市值、前十大重仓与集中度、当季新建/加仓/减持/清仓动向，并聚合出\"大佬共识\"榜；新增「华盛顿·政治人物股票交易」板块：追踪佩洛西、万斯（参议员任期）等十余位美国政治人物按 STOCK Act 披露的股票买卖（金额为披露区间估算，滞后最长 45 天；总统等行政分支不在国会披露体系内）；同页附美国个人投资者协会（AAII）每周四发布的投资者情绪调查。人物头像来自维基百科自由许可图片与美国国会官方照片库。13F 只披露美股多头持仓且最长滞后 45 天，不含做空、债券与海外仓位；情绪调查为散户样本。以上均为公开信息整理，每周自动更新，仅供参考，不构成投资建议。":
      "This page tracks the quarterly 13F filings of about 60 superinvestors and top institutions — Buffett, Dalio, Soros, Li Lu, Burry and firms including Bridgewater, Citadel, Renaissance and Norway's sovereign fund — with company and firm names shown in both Chinese and English: portfolio value, the top ten positions and concentration, and the quarter's new, added, trimmed and exited moves, aggregated into a consensus board. A “Washington · Political Stock Trades” section tracks the stock purchases and sales disclosed under the STOCK Act by more than a dozen U.S. politicians including Pelosi and Vance (during his Senate term); amounts are estimated from disclosure ranges and lag by up to 45 days, and the executive branch is outside the congressional disclosure system. The page also carries the AAII investor sentiment survey, published every Thursday. Portraits come from freely licensed Wikipedia images and the official U.S. Congress photo library. A 13F covers only long U.S. equity positions and lags by up to 45 days, excluding shorts, bonds and overseas holdings; the sentiment survey samples retail investors. All of it is compiled from public information and refreshed weekly. For reference only; not investment advice.",
    "🏛 超级投资者组合": "🏛 Superinvestor Portfolios",
    "🔍 搜索投资者 / 机构（中英文均可）…": "🔍 Search investor / firm…",
    "超级投资者持仓": "Superinvestor Holdings",
    "组合市值": "Portfolio Value",
    "新建": "New",
    "加仓": "Added",
    "减持": "Trimmed",
    "清仓": "Exited",
    "前十大持仓 · 占组合比例": "Top 10 holdings · Portfolio weight",
    "本季主要动向（vs 上季 13F）": "Major moves this quarter (vs. prior 13F)",
    "报告期": "Reporting period",
    "提交于": "Filed",
    "手动快照·部分近似": "Manual snapshot · Partly approximate",
    "SEC 原文 ↗": "SEC filing ↗",
    "🤝 大佬共识": "🤝 Investor Consensus",
    "剔除期权 · 按持有人数与仓位规模": "Options excluded · Ranked by holder count and position size",
    "👑 最多大佬共同持有": "👑 Most widely held",
    "💰 最大单一重仓": "💰 Largest single positions",
    "买入": "Buy",
    "卖出": "Sell",
    "其他": "Other",
    "近期规模(估)": "Recent volume (est.)",
    "最近披露的交易（按交易日期）": "Recent disclosed trades (by trade date)",
    "披露于": "Filed",
    "金额为披露区间估算 · 披露最长滞后 45 天": "Amounts are estimated from disclosed ranges · Disclosures may lag by up to 45 days",
    "🏛 华盛顿 · 政治人物股票交易": "🏛 Washington · Political Stock Trades",
    "搜索投资者 / 机构…": "Search investor / firm…",
    "看涨": "Bullish",
    "中性": "Neutral",
    "看跌": "Bearish"
  };

  var MAJORS = {
    /* 91 个专业名直接取自 apps/major-rankings/data.json 的 `en` 字段（数据里本来就有
       中英双写），逐条生成，不是手译，也不会和数据源分叉。 */
    "人工智能与机器学习": "Artificial Intelligence & Machine Learning",
    "数据科学": "Data Science",
    "计算机科学": "Computer Science",
    "软件工程": "Software Engineering",
    "网络安全": "Cybersecurity",
    "机器人工程": "Robotics",
    "云计算": "Cloud Computing",
    "商业分析": "Business Analytics",
    "信息管理系统": "Information Systems (MIS)",
    "人机交互": "Human-Computer Interaction",
    "石油工程": "Petroleum Engineering",
    "计算机工程": "Computer Engineering",
    "电气工程": "Electrical Engineering",
    "化学工程": "Chemical Engineering",
    "航空航天工程": "Aerospace Engineering",
    "核工程": "Nuclear Engineering",
    "机电一体化": "Mechatronics",
    "机械工程": "Mechanical Engineering",
    "可再生能源工程": "Renewable Energy Engineering",
    "生物医学工程": "Biomedical Engineering",
    "工业工程": "Industrial Engineering",
    "材料科学与工程": "Materials Science & Engineering",
    "土木工程": "Civil Engineering",
    "环境工程": "Environmental Engineering",
    "航空飞行": "Aviation & Piloting",
    "建筑管理": "Construction Management",
    "医学": "Medicine (pre-med)",
    "口腔医学": "Dentistry (pre-dental)",
    "药学": "Pharmacy (PharmD)",
    "医师助理": "Physician Assistant Studies",
    "兽医学": "Veterinary Medicine",
    "物理治疗": "Physical Therapy (DPT)",
    "护理学": "Nursing (BSN)",
    "医学影像": "Radiologic & Imaging Sciences",
    "职业治疗": "Occupational Therapy",
    "言语病理": "Speech-Language Pathology",
    "公共卫生": "Public Health",
    "营养与膳食": "Nutrition & Dietetics",
    "精算学": "Actuarial Science",
    "物理学": "Physics",
    "统计学": "Statistics",
    "数学": "Mathematics",
    "生物技术与生物信息": "Biotechnology & Bioinformatics",
    "遗传与基因组学": "Genetics & Genomics",
    "天文与天体物理": "Astronomy & Astrophysics",
    "地球科学与地质": "Earth Science & Geology",
    "神经科学": "Neuroscience",
    "化学": "Chemistry",
    "食品科学": "Food Science",
    "环境科学": "Environmental Science",
    "生物学": "Biology",
    "农业科学": "Agricultural Science",
    "金融工程 / 量化金融": "Quantitative Finance",
    "经济学": "Economics",
    "金融学": "Finance",
    "创业学": "Entrepreneurship",
    "房地产": "Real Estate",
    "管理学": "Management",
    "供应链管理": "Supply Chain Management",
    "会计学": "Accounting",
    "国际商务": "International Business",
    "市场营销": "Marketing",
    "人力资源": "Human Resources",
    "酒店管理": "Hospitality Management",
    "政治学": "Political Science",
    "国际关系": "International Relations",
    "哲学": "Philosophy",
    "传播学": "Communications",
    "语言学": "Linguistics",
    "地理学": "Geography",
    "历史学": "History",
    "心理学": "Psychology",
    "英语与文学": "English & Literature",
    "新闻学": "Journalism",
    "社会学": "Sociology",
    "人类学": "Anthropology",
    "城市规划": "Urban Planning",
    "法学": "Law (pre-law / legal studies)",
    "公共管理": "Public Administration",
    "刑事司法": "Criminal Justice",
    "图书情报": "Library & Information Science",
    "教育与师范": "Education & Teaching",
    "社会工作": "Social Work",
    "建筑学": "Architecture",
    "游戏设计": "Game Design",
    "工业设计": "Industrial & Product Design",
    "影视制作": "Film & Media Production",
    "平面设计": "Graphic Design",
    "服装设计": "Fashion Design",
    "音乐与表演": "Music & Performing Arts",
    "美术": "Fine Arts",
    /* 学科大类标签与筛选条 */
    "计算机·AI": "Computing & AI",
    "工程": "Engineering",
    "医学·健康": "Medicine & Health",
    "自然科学": "Natural Sciences",
    "商科·经济": "Business & Economics",
    "社科·人文": "Social Sciences & Humanities",
    "教育·法律": "Education & Law",
    "艺术·设计": "Arts & Design",
    "专业薪资 · 就业率 · 毕业起薪 · AI 时代未来 10 年最有前景专业 —— 四榜合一，权威数据整理":
      "Pay · employment rate · starting salary · the most promising majors for the next decade of AI — four rankings in one, compiled from authoritative data",
    "年度权威数据整理 · 2024–2025": "Annual compilation of authoritative data · 2024–2025",
    "覆盖": "Coverage",
    "个专业": "majors",
    "按专业统计的应届起薪与职业中期薪资（美国）":
      "Starting and mid-career pay by major (United States)",
    "NACE 起薪调查 & 毕业生去向 ↗": "NACE Salary Survey & First-Destination ↗",
    "美国全国高校与雇主协会的应届起薪 / First-Destination 就业率":
      "Starting salaries and First-Destination employment rates from the U.S. National Association of Colleges and Employers",
    "U.S. BLS 职业展望手册 ↗": "U.S. BLS Occupational Outlook Handbook ↗",
    "美国劳工统计局 2023–2033 各职业工资与十年就业增长预测":
      "Bureau of Labor Statistics 2023–2033 projections for occupational pay and ten-year employment growth",
    "WEF《未来就业报告 2025》 ↗": "WEF Future of Jobs Report 2025 ↗",
    "世界经济论坛：AI 时代增长最快 / 萎缩最快的岗位与技能":
      "World Economic Forum: the fastest-growing and fastest-shrinking jobs and skills of the AI era",
    "英国 HESA Graduate Outcomes ↗": "UK HESA Graduate Outcomes ↗",
    "英国官方毕业生去向与就业率调查":
      "The UK's official graduate destinations and employment survey",
    "QS 毕业生就业力排名 ↗": "QS Graduate Employability Rankings ↗",
    "以雇主声誉与毕业生就业成果为核心的国际参考":
      "An international reference built on employer reputation and graduate employment outcomes",
    "本榜为": "This table is an ",
    "（非每日实时）：薪资取自 PayScale 薪资报告与 NACE 起薪调查，就业率综合各国毕业生去向调查，":
      " (not refreshed daily): pay comes from the PayScale salary report and the NACE starting-salary survey, employment rates combine national graduate-destination surveys, ",
    "未来 10 年就业增长取自美国 BLS 职业展望，AI 时代前景参考 WEF《未来就业报告 2025》；":
      "ten-year employment growth comes from the U.S. BLS Occupational Outlook, and the AI-era outlook draws on the WEF Future of Jobs Report 2025;",
    "「AI 前景分」= 40%×十年增长 + 35%×AI 需求放大度 + 25%×(100−AI 替代度)。薪资以美元/年、美国市场为基准，仅供参考，不构成升学或就业建议。":
      "the AI outlook score = 40% × ten-year growth + 35% × how much AI amplifies demand + 25% × (100 − exposure to AI substitution). Pay is in USD per year against the U.S. market. For reference only; not admissions or career advice.",
    "关于全球专业与就业前景榜": "About the Majors & Career Outlook rankings",
    "本页用一份专业数据集支撑四张榜单：": "One dataset of majors drives four rankings here: ",
    "专业薪资 Top 100": "Top 100 by pay",
    "（职业中期年薪）、": " (mid-career annual salary), ",
    "毕业起薪 Top 100": "Top 100 by starting salary",
    "（应届起薪）、": " (first-job salary), ",
    "就业率 Top 100": "Top 100 by employment rate",
    "（毕业生就业率），以及": " (graduate employment rate), and ",
    "AI 时代未来 10 年最有前景专业排名": "the most promising majors for the next decade of AI",
    "。薪资来自 PayScale 薪资报告与 NACE 起薪调查，就业率综合美国 NACE First-Destination、英国 HESA Graduate Outcomes 与 QS 毕业生就业力等各国毕业生去向调查，未来十年就业增长取自美国劳工统计局（BLS）职业展望，AI 时代前景参考世界经济论坛《未来就业报告 2025》。":
      ". Pay comes from the PayScale salary report and the NACE starting-salary survey; employment rates combine graduate-destination surveys including NACE First-Destination in the U.S., HESA Graduate Outcomes in the UK and QS Graduate Employability; ten-year employment growth comes from the U.S. Bureau of Labor Statistics Occupational Outlook; and the AI-era outlook draws on the World Economic Forum's Future of Jobs Report 2025.",
    "「AI 前景分」由三项加权合成：40% 看未来十年岗位增长、35% 看 AI 浪潮对该专业需求的放大度、25% 看其抗 AI 替代能力，因此人工智能、数据科学、网络安全、机器人、生物技术、可再生能源等既乘 AI 而上、又高增长的专业排名靠前。可按学科大类筛选、中英文搜索。数据为年度整理值、以美国市场为基准，仅供参考，不构成升学或就业建议。":
      "The AI outlook score is a weighted blend of three things: 40% ten-year job growth, 35% how much the AI wave amplifies demand for the major, and 25% how well it resists AI substitution. That is why artificial intelligence, data science, cybersecurity, robotics, biotechnology and renewable energy — majors that both ride AI and grow fast — rank near the top. You can filter by field and search in Chinese or English. The figures are an annual compilation benchmarked to the U.S. market. For reference only; not admissions or career advice.",
    "全球专业与就业前景榜": "Majors & Career Outlook",
    "搜索专业 / 学科（中英皆可）…": "Search major / field…",
    "💰 专业薪资": "💰 Mid-Career Pay",
    "🎓 毕业起薪": "🎓 Starting Salary",
    "📈 就业率": "📈 Employment Rate",
    "🚀 AI 时代前景": "🚀 AI-Era Outlook",
    "中期年薪": "Mid-career salary",
    "应届起薪": "Starting salary",
    "毕业生就业率": "Graduate employment rate",
    "10 年前景分": "10-year outlook score",
    "起薪": "Start",
    "薪资": "Pay",
    "就业": "Employment",
    "前景": "Outlook",
    "AI 受益": "AI Tailwind",
    "受 AI 冲击": "AI Exposure",
    "AI 中性": "AI Neutral",
    "没有匹配的专业": "No matching majors",
    "年度权威数据整理": "Annual curated data",
    "薪资第一": "Highest pay",
    "就业率第一": "Highest employment rate",
    "AI 前景第一": "Top AI-era outlook",
    "数据来源与延伸阅读": "Data Sources & Further Reading",
    "🎓 全球大学排名 300 强 →": "🎓 Global University Rankings →"
  };

  var LATEST = {
    "最新消息是什么？": "What's Latest?",
    "新闻 · 市场 · 情报": "News · Markets · Intelligence",
    "📊 市场快照": "📊 Market Snapshot",
    "今日重点": "Top Story",
    "点击阅读原文 →": "Read original →",
    "来源未知": "Unknown source",
    "该板块暂无内容": "No items in this section",
    "暂无新闻": "No news",
    "● 实时": "● Live",
    "暂无行情": "No market data",
    "实时聚合 · 自动更新": "Live aggregate · Auto-updated",
    "示例数据 · 待刷新": "Sample data · Awaiting refresh",
    /* 板块标签与快照标的名属界面；新闻标题、媒体名按既有口径保持原文。 */
    "市场": "Markets",
    "人工智能·科技": "AI & Tech",
    "娱乐": "Entertainment",
    "体育": "Sports",
    "国际": "World",
    "标普500": "S&P 500",
    "纳斯达克": "Nasdaq",
    "布伦特原油": "Brent Crude",
    "WTI原油": "WTI Crude",
    "黄金": "Gold",
    "美元指数": "Dollar Index",
    "新闻聚合自 Google News 收录的权威媒体，每条均链接回原文，仅作信息聚合，不代表本站观点；市场快照来自 Yahoo Finance。仅供参考。":
      "News is aggregated from established outlets indexed by Google News; every item links back to the original. This is aggregation only and does not represent the views of this site. The market snapshot comes from Yahoo Finance. For reference only.",
    "本页聚合多家权威媒体的实时要闻与市场快照，分板块呈现，每日多次自动更新，点击标题可直达原文。聚合仅做标题与摘要的归集，完整内容与版权归原媒体所有；重要信息请点进原文核实。":
      "This page aggregates live headlines from established outlets alongside a market snapshot, grouped by section and refreshed several times a day; click a headline to go straight to the original. Only headlines and summaries are collected here — the full text and copyright belong to the original outlets, so verify anything important at the source."
  };

  var MARKETS = {
    "数据中心": "Data Center",
    "标普500热力图": "S&P 500 Heatmap",
    "金融终端": "Financial Terminal",
    "大类资产收益率": "Asset Returns",
    "全球公司榜": "Global Companies",
    "全球市场行情": "Global Markets",
    "商品、指数、公司、外汇、加密、债券六大品类逐项报价。每行带近60个交易日的迷你走势，点开即是该标的自己的完整行情页——1个月到全部区间、区间统计与逐项来源。": "Quotes across six categories: commodities, indices, companies, FX, crypto and bonds. Each row includes a roughly 60-session sparkline and links to a full quote page with range statistics and source details.",
    "标的总数": "Instruments",
    "品类": "Categories",
    "二级分组": "Subgroups",
    "数据日": "Data Date",
    "今日涨跌": "Today",
    "数据源": "Sources",
    "品类行情": "Market by Category",
    "按名称或代码搜索标的": "Search by name or ticker",
    "搜索名称或代码，例如 黄金 / GC=F": "Search name or ticker, e.g. Gold / GC=F",
    "只看自选": "Watchlist only",
    "行情品类": "Market categories",
    "品类分组": "Category groups",
    "行情列表": "Market list",
    "正在按品类整理站内日更行情…": "Organizing daily market data by category…",
    "Ooglex · 全球市场行情": "Ooglex · Global Markets",
    "数据每日自动更新 · 仅供参考，非投资建议": "Updated daily · For reference only, not investment advice",
    "使用条款": "Terms",
    "隐私政策": "Privacy",
    "此页面需要启用JavaScript才能读取站内日更管道中的行情与历史序列。": "JavaScript is required to load the site's daily market snapshots and history.",
    "商品": "Commodities",
    "指数": "Indices",
    "公司": "Companies",
    "外汇": "FX",
    "加密": "Crypto",
    "加密货币": "Crypto",
    "债券": "Bonds",
    "能源": "Energy",
    "贵金属": "Precious Metals",
    "工业金属": "Industrial Metals",
    "农产品": "Agriculture",
    "软商品": "Softs",
    "北美": "North America",
    "欧洲": "Europe",
    "亚洲": "Asia",
    "其他": "Other",
    "标的": "Instrument",
    "最新价": "Last",
    "涨跌": "Change",
    "涨跌额": "Change",
    "来源": "Source",
    "自选": "Watch",
    "畜牧": "Livestock",
    "商品指数": "Commodity Indices",
    "期货": "Futures",
    "现货": "Spot",
    "近60日": "Last 60 sessions",
    "变": "Chg",
    "每周": "Weekly",
    "月度": "Monthly",
    "年初至今": "YTD",
    "同比": "YoY",
    "口径": "Basis",
    "盘中快照已过期 · 显示日更收盘值": "Intraday snapshot is stale · showing the daily close",
    "自选仅保存在本机浏览器，不会上传": "Your watchlist stays in this browser and is never uploaded",
    "商品分组": "Commodity groups",
    "商品行情列表": "Commodity market list",
    "由站内历史序列现场算出：最近观测对该区间锚点日之前的最后一个观测":
      "Computed on the fly from this site's history: the latest observation against the last observation before the range's anchor date",
    "站内历史序列不够长，算不出这一档区间变化；此处不做推算":
      "The on-site history is not long enough to compute this range; no estimate is made",
    "产品法律与隐私": "Product legal & privacy"
  };

  var dict = {};
  copy(dict, COMMON);
  if (path.indexOf("/apps/asset-ranking/") === 0) { copy(dict, COUNTRY); copy(dict, SECTOR); copy(dict, ASSET_RANKING); }
  if (path.indexOf("/apps/house-prices/") === 0) { copy(dict, COUNTRY); copy(dict, HOUSE); }
  if (path.indexOf("/apps/world-economy/") === 0) { copy(dict, COUNTRY); copy(dict, WORLD); }
  if (path.indexOf("/apps/superinvestors/") === 0) { copy(dict, COUNTRY); copy(dict, SUPER); }
  if (path.indexOf("/apps/major-rankings/") === 0) copy(dict, MAJORS);
  if (path.indexOf("/apps/whats-latest/") === 0) copy(dict, LATEST);
  if (path.indexOf("/apps/markets/") === 0) copy(dict, MARKETS);

  function regexTranslate(s) {
    var m;
    if ((m = /^(\d+) 分钟前$/.exec(s))) return m[1] + " min ago";
    if ((m = /^(\d+)分钟前$/.exec(s))) return m[1] + " min ago";
    if ((m = /^(\d+) 小时前$/.exec(s))) return m[1] + " hr ago";
    if ((m = /^(\d+)小时前$/.exec(s))) return m[1] + " hr ago";
    if ((m = /^(\d+) 天前$/.exec(s))) return m[1] + " days ago";
    if ((m = /^(\d+)天前$/.exec(s))) return m[1] + " days ago";
    if (s === "刚刚") return "Just now";
    if ((m = /^第 (\d+) 高$/.exec(s))) return "#" + m[1] + " highest";
    if ((m = /^(\d+) 个国家\/地区$/.exec(s))) return m[1] + " countries/regions";
    if ((m = /^(\d+) 组$/.exec(s))) return m[1] + " groups";
    if ((m = /^(\d+) 家$/.exec(s))) return m[1] + " sources";
    if ((m = /^覆盖 (\d+) 个专业$/.exec(s))) return m[1] + " majors covered";
    if ((m = /^前 (\d+) 总市值$/.exec(s))) return "Top " + m[1] + " total market cap";
    if ((m = /^(\d+) 位持有$/.exec(s))) return "Held by " + m[1];
    if ((m = /^近期 (\d+) 笔披露 · 最近交易 (.+)$/.exec(s))) return m[1] + " recent disclosures · Last trade " + m[2];
    if ((m = /^10年 ([+−-]?\d+(?:\.\d+)?)%$/.exec(s))) return "10Y " + m[1] + "%";
    if ((m = /^数据：(.*)$/.exec(s))) return "Data: " + m[1];
    // 「数据：」已翻成 "Data: " 后，尾巴里的中文口径说明是独立一段，单独配
    if ((m = /^Data: (\d{4})年末整理 · 单位 (.+)$/.exec(s))) return "Data: compiled as of end-" + m[1] + " · unit " + m[2];
    if ((m = /^(\d{4})年末整理 · 单位 (.+)$/.exec(s))) return "compiled as of end-" + m[1] + " · unit " + m[2];
    if ((m = /^单位 (.*)$/.exec(s))) return "Unit " + m[1];
    if ((m = /^截至 (.+)$/.exec(s))) return "As of " + m[1];
    if (path.indexOf("/apps/superinvestors/") === 0) {
      /* 标的名上有几种构建脚本加的中文零件：期权方向「（看涨期权）」、股份类别
         「A类」，以及 aria-label 里「中文名 英文名 · 金额 · 占比」的中文前半。
         统一先把这些零件换掉、再把整串里能查到的中文名换成英文，最后只有当
         结果里一个汉字都不剩时才采用——剩汉字说明还有没认出来的成分，
         那就原样留着，不交出一个半中半英的串。 */
      var fixed = s
        .replace(/（看涨期权）/g, " (calls)")
        .replace(/（看跌期权）/g, " (puts)")
        .replace(/([A-Za-z0-9)\-])\s*([A-C])类/g, "$1 Class $2")
        .replace(/^([^·]*?[\u4e00-\u9fff][^·]*?) ([A-Za-z].* · .+)$/, "$2")
        .replace(/看涨 /g, "Bullish ").replace(/看跌 /g, "Bearish ").replace(/中性 /g, "Neutral ");
      if (fixed !== s) {
        var zhLeft = fixed.match(/[\u4e00-\u9fff][\u4e00-\u9fff()（）\w]*/g) || [];
        for (var zi = 0; zi < zhLeft.length; zi++) {
          if (dict[zhLeft[zi]]) fixed = fixed.split(zhLeft[zi]).join(dict[zhLeft[zi]]);
        }
        if (!/[\u4e00-\u9fff]/.test(fixed)) return fixed;
      }
      if ((m = /^(.+?)\s*([A-C])类(.*)$/.exec(s)) && dict[m[1]]) return dict[m[1]] + " Class " + m[2] + m[3];
      // 「挪威 · Norges Bank」「民主党 · 众议院 · 加利福尼亚」这类分段串：逐段查表。
      if (s.indexOf(" · ") > 0 && /[\u4e00-\u9fff]/.test(s)) {
        var sg = s.split(" · "), sh = false;
        var sj = sg.map(function (seg) {
          if (dict[seg]) { sh = true; return dict[seg]; }
          var fm2 = /^([^\u4e00-\u9fffA-Za-z0-9]+)(.+)$/.exec(seg);
          if (fm2 && dict[fm2[2]]) { sh = true; return fm2[1] + dict[fm2[2]]; }
          var tw = /^([^\u4e00-\u9fff]*)([\u4e00-\u9fff]+)(.*)$/.exec(seg);
          if (tw && dict[tw[2]]) { sh = true; return tw[1] + dict[tw[2]] + tw[3]; }
          return seg;
        }).join(" · ");
        if (sh) return sj;
      }
      if ((m = /^(\d+) 位 · 国会 STOCK Act 披露 · 点击展开近期交易$/.exec(s))) {
        return m[1] + " politicians · congressional STOCK Act disclosures · click to expand recent trades";
      }
      if ((m = /^(\S+) vs 上周$/.exec(s))) return m[1] + " vs. last week";
      if ((m = /^牛熊差 (\S+)$/.exec(s))) return "Bull−bear spread " + m[1];
      if ((m = /^共 (\d+) 位 · 点击展开前十大持仓与季度动向$/.exec(s))) {
        return m[1] + " investors · click to expand top-10 holdings and quarterly moves";
      }
      if ((m = /^(\d{4}) Q(\d) · ([\d,]+) 只持仓 · 前十占 (\S+)$/.exec(s))) {
        return m[1] + " Q" + m[2] + " · " + m[3] + " holdings · top 10 = " + m[4];
      }
      if ((m = /^报告期 (\S+) · 提交于 (\S+) ·$/.exec(s))) return "Period " + m[1] + " · filed " + m[2] + " ·";
      if ((m = /^(加仓|减持|新建|清仓) (\S+)$/.exec(s))) {
        return ({ "加仓": "Added", "减持": "Trimmed", "新建": "New", "清仓": "Exited" })[m[1]] + " " + m[2];
      }
      // 「城堡投资 Citadel Advisors」：中英拼在一起，英文下只留英文那一半。
      if ((m = /^([\u4e00-\u9fff\u00B7A-Za-z0-9]*[\u4e00-\u9fff]) ([A-Za-z0-9].*)$/.exec(s)) && !dict[s]) return m[2];
    }
    if (path.indexOf("/apps/asset-ranking/") === 0) {
      // 「1.73 万亿桶（探明储量）」：数量与量级词照翻，计量口径查字典。
      if ((m = /^([\d.,]+)\s*(万亿|亿|万|千)?(.+)$/.exec(s)) && dict[m[3]]) {
        var mag = { "万亿": " trillion ", "亿": " hundred million ", "万": " ten thousand ", "千": " thousand " };
        return m[1] + (m[2] ? mag[m[2]] : " ") + dict[m[3]];
      }
      /* 行卡第二行是「国旗国名 · 板块 · 代码/状态」这类用 · 拼起来的短语，
         段数和成分都不固定（有的没国旗、有的第三段是「上轮融资 May 2026」）。
         逐段查表：查得到就换，查不到原样留下——不做整串猜测。 */
      if (s.indexOf(" · ") > 0 && /[\u4e00-\u9fff]/.test(s)) {
        var segs = s.split(" · "), hit = false;
        var out = segs.map(function (seg) {
          var flag = "", body = seg;
          var fm = /^([^\u4e00-\u9fffA-Za-z0-9]+)(.+)$/.exec(seg);
          if (fm) { flag = fm[1]; body = fm[2]; }
          if (dict[body]) { hit = true; return flag + dict[body]; }
          var lm = /^上轮融资 (.+)$/.exec(body);
          if (lm) { hit = true; return flag + "Last round " + lm[1]; }
          if (body === "未上市") { hit = true; return flag + "Private"; }
          return seg;
        }).join(" · ");
        if (hit) return out;
      }
      if ((m = /^▲ 今日领涨 (.+?) (\S+)$/.exec(s))) return "▲ Top gainer today " + (dict[m[1]] || m[1]) + " " + m[2];
      if ((m = /^▼ 今日领跌 (.+?) (\S+)$/.exec(s))) return "▼ Top decliner today " + (dict[m[1]] || m[1]) + " " + m[2];
    }
    if (path.indexOf("/apps/major-rankings/") === 0) {
      if ((m = /^(\S+)\s+([^\s\d]+)(?:\s+(\d+))?$/.exec(s)) && dict[m[2]]) {
        return m[1] + " " + dict[m[2]] + (m[3] ? " " + m[3] : "");
      }
    }
    if ((m = /^指数 (\S+) · (\S+) · 截至 (.+)$/.exec(s))) return "Index " + m[1] + " · " + m[2] + " · as of " + m[3];
    if ((m = /^▲ 涨幅居首 (.+?) (\S+)$/.exec(s))) return "▲ Biggest gain " + (dict[m[1]] || m[1]) + " " + m[2];
    if ((m = /^▼ 跌幅居首 (.+?) (\S+)$/.exec(s))) return "▼ Biggest decline " + (dict[m[1]] || m[1]) + " " + m[2];
    // 「🇹🇷 土耳其」「🇺🇸 美国 50」这类：国旗与数字原样带回，只查国名。
    if ((m = /^(\S+)\s+([^\s\d]+)(?:\s+(\S+))?$/.exec(s)) && dict[m[2]]) {
      return m[1] + " " + dict[m[2]] + (m[3] ? " " + m[3] : "");
    }
    if (path.indexOf("/apps/markets/") === 0) {
      // 行情板的组合串：标的名、代码与数字原样带回，只翻固定部分。
      if ((m = /^(.+?) · (\d+)项 · 上涨(\d+) · 下跌(\d+) · 数据日 (.+?) ~ (.+)$/.exec(s))) {
        return (dict[m[1]] || m[1]) + " · " + m[2] + " instruments · " + m[3] + " up · " + m[4] +
          " down · data " + m[5] + " ~ " + m[6];
      }
      if ((m = /^(\d+)项$/.exec(s))) return m[1] + " items";
      if ((m = /^展开全部 (\d+) 项$/.exec(s))) return "Show all " + m[1];
      if ((m = /^加入自选 (.+)$/.exec(s))) return "Add " + m[1] + " to watchlist";
      if ((m = /^移出自选 (.+)$/.exec(s))) return "Remove " + m[1] + " from watchlist";
      if ((m = /^当前显示 (\d+) 项：上涨 (\d+) 项，下跌 (\d+) 项，持平或暂无观测 (\d+) 项$/.exec(s))) {
        return "Showing " + m[1] + " instruments: " + m[2] + " up, " + m[3] + " down, " + m[4] + " flat or unobserved";
      }
      if ((m = /^(.+?)，最新价 (\S+?)，(\S+?)，打开完整行情页$/.exec(s))) {
        return m[1] + ", last " + m[2] + ", " + m[3] + ", open the full quote page";
      }
      if ((m = /^(.+?) 最近(\d+)个交易日站内走势，区间变化 (\S+)$/.exec(s))) {
        return m[1] + " — on-site trend over the last " + m[2] + " sessions, range change " + m[3];
      }
    }
    if ((m = /^数据日期 (.+)$/.exec(s))) return "As of " + m[1];
    if ((m = /^更新于 (.+)$/.exec(s))) return "Updated " + m[1];
    // 「· 6小时前」这类分隔符开头的相对时间是独立文本节点（前面是媒体名的 <b>）
    if ((m = /^· ?(\d+)\s*分钟前$/.exec(s))) return "· " + m[1] + " min ago";
    if ((m = /^· ?(\d+)\s*小时前$/.exec(s))) return "· " + m[1] + " hr ago";
    if ((m = /^· ?(\d+)\s*天前$/.exec(s))) return "· " + m[1] + " days ago";
    if (path.indexOf("/apps/whats-latest/") === 0) {
      if ((m = /^今日重点 · (.+)$/.exec(s))) return "Top story · " + (dict[m[1]] || m[1]);
      // 「首都医科大学 · 6小时前 · 点击阅读原文 →」：媒体名原样带回，只翻时间与动作
      if ((m = /^(.+?) · (\d+)\s*分钟前 · 点击阅读原文 →$/.exec(s))) return m[1] + " · " + m[2] + " min ago · Read original →";
      if ((m = /^(.+?) · (\d+)\s*小时前 · 点击阅读原文 →$/.exec(s))) return m[1] + " · " + m[2] + " hr ago · Read original →";
      if ((m = /^(.+?) · (\d+)\s*天前 · 点击阅读原文 →$/.exec(s))) return m[1] + " · " + m[2] + " days ago · Read original →";
    }
    return null;
  }

  function translateValue(s) {
    if (Object.prototype.hasOwnProperty.call(dict, s)) return dict[s];
    return regexTranslate(s);
  }

  function skipText(node) {
    var p = node && node.parentElement;
    return !p || /^(SCRIPT|STYLE|NOSCRIPT|CODE|PRE)$/.test(p.tagName);
  }

  function translateText(node) {
    if (!node || node.nodeType !== 3 || skipText(node)) return;
    var raw = node.nodeValue || "", s = raw.trim();
    if (!s) return;
    var out = translateValue(s);
    if (!out || out === s) return;
    if (!textOrig.has(node)) { textOrig.set(node, raw); textTouched.push(node); }
    var p = raw.indexOf(s);
    node.nodeValue = (p >= 0 ? raw.slice(0, p) : "") + out + (p >= 0 ? raw.slice(p + s.length) : "");
  }

  function translateAttrs(el) {
    if (!el || el.nodeType !== 1) return;
    var saved = attrOrig.get(el) || {}, changed = false;
    ATTRS.forEach(function (a) {
      if (!el.hasAttribute(a)) return;
      var v = el.getAttribute(a), out = translateValue(v);
      if (!out || out === v) return;
      if (!(a in saved)) saved[a] = v;
      el.setAttribute(a, out); changed = true;
    });
    if (changed && !attrOrig.has(el)) { attrOrig.set(el, saved); attrTouched.push(el); }
  }

  function rememberHtml(el) {
    if (!el || htmlOrig.has(el)) return;
    htmlOrig.set(el, el.innerHTML); htmlTouched.push(el);
  }

  /* 超级投资者的持仓行本来就是中英并排：
     <span class="tk">SPY</span>标普500 ETF（看涨期权） <small class="enm">State Str …</small>
     英文下把中间那个中文文本节点去掉，只留 .enm；期权方向的括号后缀单独翻。
     .enm 里没有英文名的行不动——宁可留中文，也不把一只标的显示成另一只。 */
  function superHoldings() {
    if (path.indexOf("/apps/superinvestors/") !== 0) return;
    document.querySelectorAll(".hname").forEach(function (el) {
      var enm = el.querySelector(".enm");
      if (!enm || !enm.textContent.trim()) return;
      var zhNode = null;
      for (var i = 0; i < el.childNodes.length; i++) {
        var c = el.childNodes[i];
        if (c.nodeType === 3 && /[\u4e00-\u9fff]/.test(c.nodeValue || "")) { zhNode = c; break; }
      }
      if (!zhNode) return;
      rememberHtml(el);
      zhNode.nodeValue = " ";
    });
  }

  /* 头像圆圈里是投资人中文名的首字（「肯」「沃」）。名字已经翻成英文，
     首字也得跟着换成英文首字母；同一张卡里找得到中文名才换，找不到不动。 */
  function superInitials() {
    if (path.indexOf("/apps/superinvestors/") !== 0) return;
    document.querySelectorAll(".invhead .avatar").forEach(function (el) {
      var node = el.firstChild;
      if (!node || node.nodeType !== 3) return;
      var t = (node.nodeValue || "").trim();
      if (t.length !== 1 || !/[\u4e00-\u9fff]/.test(t)) return;
      /* 同一个 .invhead 里的 .nm 此时已被翻成英文名，直接取它的首字母。
         取不到英文名就不动这个圆圈——宁可留中文，也不写一个对不上人的字母。 */
      var head = el.closest && el.closest(".invhead");
      var nmEl = head && head.querySelector(".nm");
      var en = nmEl ? nmEl.textContent.trim() : "";
      if (!en || /[\u4e00-\u9fff]/.test(en.charAt(0))) return;
      if (!textOrig.has(node)) { textOrig.set(node, node.nodeValue); textTouched.push(node); }
      node.nodeValue = en.charAt(0).toUpperCase();
    });
  }

  function specialEnglish() {
    superHoldings();
  }

  function walk(scope) {
    var base = scope && scope.nodeType ? scope : document.body;
    if (!base) return;
    if (base.nodeType === 3) { translateText(base); return; }
    if (base.nodeType === 1) translateAttrs(base);
    /* 和其他层同理：specialEnglish 对整块做 innerHTML 备份，必须跑在逐节点翻译之前。 */
    specialEnglish();
    var w = document.createTreeWalker(base, NodeFilter.SHOW_TEXT, null), n;
    while ((n = w.nextNode())) translateText(n);
    var els = base.querySelectorAll ? base.querySelectorAll("[placeholder],[aria-label],[title],[alt]") : [];
    for (var i = 0; i < els.length; i++) translateAttrs(els[i]);
    superInitials();   // 要读翻好的英文名，必须排在文本翻译之后
  }

  function restore() {
    for (var i = 0; i < textTouched.length; i++) {
      var n = textTouched[i]; if (n && textOrig.has(n)) n.nodeValue = textOrig.get(n);
    }
    for (var j = 0; j < attrTouched.length; j++) {
      var el = attrTouched[j], saved = attrOrig.get(el); if (!el || !saved) continue;
      Object.keys(saved).forEach(function (a) { el.setAttribute(a, saved[a]); });
    }
    for (var k = 0; k < htmlTouched.length; k++) {
      var h = htmlTouched[k]; if (h && htmlOrig.has(h)) h.innerHTML = htmlOrig.get(h);
    }
    textTouched = []; attrTouched = []; htmlTouched = [];
    textOrig = new WeakMap(); attrOrig = new WeakMap(); htmlOrig = new WeakMap();
  }

  var titleOrig = null;
  var TITLES = {
    "/apps/asset-ranking/": "Global Assets by Market Cap · Top 250",
    "/apps/house-prices/": "Global Home Prices · Ooglex",
    "/apps/world-economy/": "World Economy Map · Ooglex",
    "/apps/superinvestors/": "Superinvestors · 13F & AAII · Ooglex",
    "/apps/major-rankings/": "Majors & Career Outlook · Ooglex",
    "/apps/whats-latest/": "What's Latest · News & Markets · Ooglex",
    "/apps/markets/": "Global Markets · Ooglex"
  };
  function translateTitle() {
    if (titleOrig === null) titleOrig = document.title;
    if (TITLES[path]) document.title = TITLES[path];
  }
  function restoreTitle() { if (titleOrig !== null) document.title = titleOrig; }
  /* pending 原本是「本帧已排过队就直接 return」——但 return 掉的那一批 records
     **就此丢了**，不会被后面的 rAF 处理。数据枢纽这类一屏拉十几个 data.json、
     逐卡渲染的页面，一帧里能来好几批 mutation，于是「领涨」「今日上涨」这些
     字典里明明有的词条永远翻不到。改成先把 records 攒起来再统一处理：
     既保留按帧合并的原意，又一条都不丢。 */

  var observer = null, pending = false, queued = [];
  function watch() {
    if (observer || typeof MutationObserver === "undefined") return;
    observer = new MutationObserver(function (records) {
      if (current !== "en") return;

      queued = queued.concat(Array.prototype.slice.call(records));

      if (pending) return;
      pending = true;
      requestAnimationFrame(function () {
        pending = false;
        /* rAF 排队期间用户可能已经切回中文：那时 restore() 已经跑完，
           这一帧再去翻译（尤其是末尾无条件调用的 specialEnglish）会把刚还原的
           标题、样式又改回英文态——宏观风险监测的中文大标题就是这么丢的。 */
        if (current !== "en") { queued = []; return; }
        var batch = queued; queued = [];
        batch.forEach(function (r) {
          if (r.type === "attributes") translateAttrs(r.target);
          else if (r.type === "characterData") translateText(r.target);
          else Array.prototype.forEach.call(r.addedNodes || [], walk);
        });
      });
    });
    /* 也盯 ATTRS 里那几个属性：原先只盯 childList/characterData，
       于是「就地改写已有元素的 aria-label/title」这类更新永远翻不到
       （行情板的「当前显示 73 项：上涨 25…」就是这么漏的）。
       改写属性本身会再触发一次 mutation，但英文串查不到词条，第二轮是空转，不会循环。 */
    observer.observe(document.documentElement, { subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ATTRS });
  }

  function apply(lang) {
    current = lang === "en" ? "en" : "zh";
    if (current === "en") { walk(document.body); translateTitle(); watch(); }
    else { restore(); restoreTitle(); }
  }

  function boot() { apply(readLang()); }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();

  document.addEventListener("ooglex:languagechange", function (e) {
    var lang = e && e.detail && e.detail.language;
    apply(lang === "en" ? "en" : "zh");
  });
  window.addEventListener("storage", function (e) {
    if (e.key === KEY) apply(e.newValue === "en" ? "en" : "zh");
  });
})();
