/* Ooglex fourth-wave i18n layer.
   Covers public tools/content/entertainment pages that were not in the first
   three rollout waves. Reads localStorage["ooglex.language"] and keeps the
   original Chinese DOM so switching back is lossless. */
(function () {
  "use strict";

  var KEY = "ooglex.language";
  var path = (location.pathname || "/").replace(/\/index\.html$/, "/");
  var current = "zh";
  var textOrig = new WeakMap(), textTouched = [];
  var attrOrig = new WeakMap(), attrTouched = [];
  var htmlOrig = new WeakMap(), htmlTouched = [];
  var styleOrig = new WeakMap(), styleTouched = [];
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
  function add(dst, src) { Object.keys(src).forEach(function (k) { dst[k] = src[k]; }); }

  var COMMON = {
    "← 返回": "← Back",
    "← 返回主页": "← Back to Home",
    "← 返回首页": "← Back to Home",
    "返回主页": "Back to Home",
    "返回首页": "Back to Home",
    "关闭": "Close",
    "取消": "Cancel",
    "保存": "Save",
    "搜索": "Search",
    "加载中…": "Loading…",
    "加载中": "Loading",
    "正在加载…": "Loading…",
    "重新加载": "Reload",
    "暂无数据": "No data",
    "准备就绪": "Ready",
    "知道了 ✕": "Got it ✕",
    "数据来源": "Data Sources",
    "数据来源与许可": "Data Sources & Licenses",
    "关于本页数据": "About This Data",
    "关于本页数据与播放": "About This Data & Playback",
    "仅供参考，不构成投资建议": "For reference only; not investment advice",
    "仅供研究，非投资建议": "For research only; not investment advice"
  };

  var HEATMAP = {
    /* 成分股中文名与板块名逐条取自 apps/companies/sp500.json 的 `nameEn` / `sectorEn`
       （数据里本就中英双写）。少数行的 sector 与 sectorEn 对不上（上游分类漂移），
       板块按多数票取，得到的正好是 GICS 十一大板块。 */
    "英伟达": "Nvidia",
    "苹果": "Apple Inc.",
    "谷歌": "Alphabet Inc. (Class A)",
    "微软": "Microsoft",
    "亚马逊": "Amazon",
    "Meta": "Meta Platforms",
    "博通": "Broadcom",
    "特斯拉": "Tesla, Inc.",
    "美光": "Micron Technology",
    "伯克希尔": "Berkshire Hathaway",
    "礼来": "Lilly (Eli)",
    "摩根大通": "JPMorgan Chase",
    "AMD": "Advanced Micro Devices",
    "沃尔玛": "Walmart",
    "Visa": "Visa Inc.",
    "埃克森美孚": "ExxonMobil",
    "强生": "Johnson & Johnson",
    "英特尔": "Intel",
    "万事达": "Mastercard",
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
    "宝洁": "Procter & Gamble",
    "联合健康": "UnitedHealth Group",
    "泛林集团": "Lam Research",
    "应用材料": "Applied Materials",
    "GE航空航天": "GE Aerospace",
    "摩根士丹利": "Morgan Stanley",
    "奈飞": "Netflix",
    "家得宝": "Home Depot (The)",
    "菲利普莫里斯": "Philip Morris International",
    "高盛": "Goldman Sachs",
    "富国银行": "Wells Fargo",
    "雷神技术": "RTX Corporation",
    "Palo Alto": "Palo Alto Networks",
    "GE 维尔诺瓦": "GE Vernova",
    "赛默飞": "Thermo Fisher Scientific",
    "闪迪": "Sandisk Corporation",
    "德州仪器": "Texas Instruments",
    "花旗": "Citigroup",
    "科磊": "KLA Corporation",
    "美国运通": "American Express",
    "林德": "Linde plc",
    "美满电子": "Marvell Technology, Inc.",
    "安进": "Amgen",
    "威瑞森": "Verizon",
    "高通": "Qualcomm",
    "吉利德": "Gilead Sciences",
    "迪尔": "Deere & Company",
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
    "贝莱德": "BlackRock",
    "康菲石油": "ConocoPhillips",
    "伊顿": "Eaton Corporation",
    "辉瑞": "Pfizer",
    "波音": "Boeing",
    "盈透证券": "Interactive Brokers Group",
    "黑石": "Blackstone Inc.",
    "丹纳赫": "Danaher Corporation",
    "西部数据": "Western Digital",
    "直觉外科": "Intuitive Surgical",
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
    "标普全球": "S&P Global",
    "美敦力": "Medtronic",
    "派克汉尼汾": "Parker Hannifin",
    "埃森哲": "Accenture",
    "奥驰亚": "Altria",
    "星巴克": "Starbucks",
    "菲利普斯66": "Phillips 66",
    "劳氏": "Lowe's",
    "史赛克": "Stryker Corporation",
    "纽约梅隆银行": "Bank of New York Mellon Corp",
    "麦克森": "McKesson Corporation",
    "自由港麦克莫兰": "Freeport-McMoRan",
    "Adobe": "Adobe Inc.",
    "罗宾汉": "Robinhood Markets, Inc.",
    "爱彼迎": "Airbnb",
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
    "江森自控": "Johnson Controls",
    "废物管理公司": "Waste Management",
    "UPS": "United Parcel Service",
    "威达信集团": "Marsh & McLennan Companies, Inc.",
    "艾默生": "Emerson Electric",
    "美国电塔": "American Tower",
    "康卡斯特": "Comcast",
    "再生元": "Regeneron Pharmaceuticals",
    "慧与": "Hewlett Packard Enterprise",
    "旅行者保险": "Travelers Companies (The)",
    "穆迪": "Moody's Corporation",
    "亿滋国际": "Mondelez International",
    "宣伟": "Sherwin-Williams",
    "通用汽车": "General Motors",
    "斯伦贝谢": "Schlumberger",
    "EOG 能源": "EOG Resources",
    "楷登电子": "Cadence Design Systems",
    "伊利诺伊工具": "Illinois Tool Works",
    "艺康": "Ecolab",
    "摩托罗拉系统": "Motorola Solutions",
    "诺斯罗普·格鲁曼": "Northrop Grumman",
    "罗斯百货": "Ross Stores",
    "新思科技": "Synopsys",
    "联邦快递": "FedEx",
    "信诺": "Cigna",
    "阿波罗全球管理": "Apollo Global Management",
    "塔吉特": "Target Corporation",
    "康明斯": "Cummins",
    "诺福克南方铁路": "Norfolk Southern Railway",
    "华纳兄弟探索": "Warner Bros. Discovery",
    "奥莱利汽配": "O'Reilly Auto Parts",
    "高露洁": "Colgate-Palmolive",
    "金德摩根": "Kinder Morgan",
    "希尔顿": "Hilton Worldwide",
    "共和服务": "Republic Services",
    "皇家加勒比": "Royal Caribbean Group",
    "西蒙地产": "Simon Property Group",
    "美国电力": "American Electric Power",
    "碧迪医疗": "Becton Dickinson",
    "好事达": "Allstate",
    "波士顿科学": "Boston Scientific",
    "空气化工产品": "Air Products",
    "怡安": "Aon",
    "联合租赁": "United Rentals",
    "莫德纳": "Moderna",
    "大都会人寿": "MetLife",
    "帕卡": "Paccar",
    "纽柯钢铁": "Nucor",
    "泰科电子": "TE Connectivity",
    "固安捷": "W. W. Grainger",
    "美国家庭人寿": "Aflac",
    "西方石油": "Occidental Petroleum",
    "CRH 集团": "CRH plc",
    "恩智浦": "NXP Semiconductors",
    "芯源系统": "Monolithic Power Systems",
    "是德科技": "Keysight Technologies",
    "道明尼能源": "Dominion Energy",
    "贝克休斯": "Baker Hughes",
    "响尾蛇能源": "Diamondback Energy",
    "泰瑞达": "Teradyne",
    "科迪华": "Corteva",
    "耐克": "Nike, Inc.",
    "桑普拉能源": "Sempra",
    "阿美特克": "Ametek",
    "福特": "Ford Motor Company",
    "佳明": "Garmin",
    "康德乐": "Cardinal Health",
    "公共存储": "Public Storage",
    "Workday": "Workday, Inc.",
    "达美航空": "Delta Air Lines",
    "纳斯达克": "Nasdaq, Inc.",
    "爱德华兹生命科学": "Edwards Lifesciences",
    "道富银行": "State Street Corporation",
    "第五三银行": "Fifth Third Bancorp",
    "安特吉": "Entergy",
    "相干公司": "Coherent, Inc.",
    "哈门那": "Humana",
    "欧特克": "Autodesk",
    "Coinbase": "Coinbase Global",
    "罗克韦尔自动化": "Rockwell Automation",
    "开利": "Carrier Global",
    "艾昆纬": "IQVIA",
    "安捷伦": "Agilent Technologies",
    "怪物饮料": "Monster Beverage",
    "墨式烧烤": "Chipotle Mexican Grill",
    "ADM": "Archer Daniels Midland",
    "阿瑞斯资本": "Ares Management Corporation",
    "保德信金融": "Prudential Financial",
    "世邦魏理仕": "CBRE Group",
    "美国国际集团": "American International Group",
    "明晟": "MSCI",
    "爱德士": "Idexx Laboratories",
    "伟创力": "Flex Ltd.",
    "霍顿房屋": "D. R. Horton",
    "联合爱迪生": "Consolidated Edison",
    "微芯科技": "Microchip Technology",
    "罗珀科技": "Roper Technologies",
    "西斯科": "Sysco",
    "克罗格": "Kroger",
    "百胜餐饮": "Yum! Brands",
    "哈特福德金融": "Hartford (The)",
    "钢铁动力": "Steel Dynamics",
    "联合航空": "United Airlines Holdings",
    "好时": "Hershey Company (The)",
    "德康医疗": "Dexcom",
    "雅诗兰黛": "Estée Lauder Companies (The)",
    "瑞思迈": "ResMed",
    "M&T 银行": "M&T Bank",
    "北方信托": "Northern Trust",
    "亿客行": "Expedia Group",
    "金佰利": "Kimberly-Clark",
    "渤健": "Biogen",
    "冠城国际": "Crown Castle",
    "雷蒙詹姆斯": "Raymond James Financial",
    "捷普": "Jabil",
    "硕腾": "Zoetis",
    "嘉年华邮轮": "Carnival",
    "戴文能源": "Devon Energy",
    "马丁玛丽埃塔": "Martin Marietta Materials",
    "太平洋煤气电力": "PG&E Corporation",
    "韦莱韬悦": "Willis Towers Watson",
    "GE 医疗": "GE HealthCare",
    "卡夫亨氏": "Kraft Heinz",
    "福克斯": "Fox Corporation (Class A)",
    "梅特勒-托利多": "Mettler Toledo",
    "英格索兰": "Ingersoll Rand",
    "哈里伯顿": "Halliburton",
    "沃特世": "Waters Corporation",
    "特利丹": "Teledyne Technologies",
    "芝加哥期权交易所": "Cboe Global Markets",
    "威瑞信": "Verisign",
    "美国水务": "American Water Works",
    "拉斯维加斯金沙": "Las Vegas Sands",
    "安森美半导体": "ON Semiconductor",
    "奥的斯": "Otis Worldwide",
    "赛莱默": "Xylem Inc.",
    "多佛": "Dover Corporation",
    "PPG 工业": "PPG Industries",
    "泰佩思琦": "Tapestry, Inc.",
    "邦吉": "Bunge Global",
    "宏盟集团": "Omnicom Group",
    "普信集团": "T. Rowe Price",
    "美元树": "Dollar Tree",
    "第一太阳能": "First Solar",
    "爱迪生国际": "Edison International",
    "星座品牌": "Constellation Brands",
    "拉夫劳伦": "Ralph Lauren Corporation",
    "莱纳房屋": "Lennar",
    "西南航空": "Southwest Airlines",
    "泰森食品": "Tyson Foods",
    "公用事业": "Utilities",
    "医疗健康": "Health Care",
    "原材料": "Materials",
    "可选消费": "Consumer Discretionary",
    "工业": "Industrials",
    "必需消费": "Consumer Staples",
    "房地产": "Real Estate",
    "科技": "Information Technology",
    "能源": "Energy",
    "通信服务": "Communication Services",
    "金融": "Financials",
    /* 下面两段整段本来就在字典里，但 DOM 里 <b> 把它们切开了，
       文本节点是以「：」开头的后半段，整段那条永远匹配不到。 */
    "：放大不是把同一张图糊着放大，而是在更大的画布上重新排一次版，小市值公司的格子因此变大，名字、代码与股价才真的显示得出来。到了最大或最小档还继续滚，页面照常滚动，不会把你困在图里；也可以用下方按钮或 + − 0 键。":
      ": zooming re-lays out the map on a larger canvas rather than scaling pixels, so smaller companies gain enough room to show names, tickers and prices. At the zoom limits the page resumes normal scrolling; the buttons below and the +, − and 0 keys work too.",
    "：站内任务每约30分钟重取一次全部成分股的最新价，页面每20秒重读这份站内静态文件（不在浏览器里调用任何外部行情接口），只有确实更新时才覆盖。":
      ": a scheduled job on this site re-fetches every constituent's latest price about every 30 minutes, and the page re-reads that static file every 20 seconds (no external quote API is ever called from your browser), overwriting only when the data has actually changed.",
    "全部": "All",
    "当日涨跌": "Daily change",
    "当日涨跌缺失": "Daily change unavailable",
    "跌超3%": "Down >3%",
    "跌1–3%": "Down 1–3%",
    "跌1%内": "Down <1%",
    "基本持平": "Roughly flat",
    "涨1%内": "Up <1%",
    "涨1–3%": "Up 1–3%",
    "涨超3%": "Up >3%",
    "标的": "Instrument",
    "代码": "Ticker",
    "行业": "Sector",
    "股价": "Price",
    "市值": "Market cap",
    "当日": "Today",
    "每周": "Weekly",
    "月度": "Monthly",
    "年初至今": "YTD",
    "气泡颜色 = 当日涨跌": "Bubble colour = daily change",
    "使用条款": "Terms",
    "Ooglex · 标普500热力图 · 数据每日自动更新，非实时行情 · 仅供参考，非投资建议 ·":
      "Ooglex · S&P 500 Heatmap · Refreshed daily, not live quotes · For reference only, not investment advice ·",
    "全球市场行情": "Global Markets",
    "全球公司榜": "Global Companies",
    "金融终端": "Finance Terminal",
    "标普500热力图": "S&P 500 Heatmap",
    "按行业分块，每块的面积正比于该公司的市值，颜色是它当日的涨跌。方格以中文公司名标注，放得下的大格再补上交易代码与股价。每块瓦片上同时写出带 ▲▼ 的涨跌数字，另有图例与完整数据表——颜色不是唯一的编码方式。点开任一块即是该公司的完整行情页。": "Grouped by sector; tile area is proportional to market capitalization and color shows the day's move. Larger tiles also show ticker and price. Every tile includes an explicit ▲▼ percentage, plus a legend and a full data table, so color is not the only encoding. Click any tile to open that company's full quote page.",
    "滚轮可以缩放": "Use the wheel to zoom",
    "放大不是把同一张图糊着放大，而是在更大的画布上重新排一次版，小市值公司的格子因此变大，名字、代码与股价才真的显示得出来。到了最大或最小档还继续滚，页面照常滚动，不会把你困在图里；也可以用下方按钮或 + − 0 键。": "Zooming re-lays out the map on a larger canvas rather than simply scaling pixels, so smaller companies gain enough space to show names, tickers and prices. At the zoom limits, the page resumes normal scrolling. You can also use the controls below or the +, − and 0 keys.",
    "美股开盘后会跟着动": "Updates during U.S. market hours",
    "站内任务每约30分钟重取一次全部成分股的最新价，页面每20秒重读这份站内静态文件（不在浏览器里调用任何外部行情接口），只有确实更新时才覆盖。": "A site task refreshes constituent prices about every 30 minutes. The page re-reads the site's static snapshot every 20 seconds and only replaces values when the snapshot actually changes; the browser does not call an external quote API.",
    "这不是实时行情": "This is not real-time market data",
    "——刷新周期约30分钟，交易所自身还有延迟（美股常见15分钟），标题下方会写明覆盖了多少家与更新于多久前。": "—the refresh cycle is roughly 30 minutes and exchange feeds may themselves be delayed (often 15 minutes for U.S. equities). Coverage and freshness are shown below the title.",
    "覆盖成分股": "Constituents Covered",
    "合计市值": "Total Market Cap",
    "数据日": "Data Date",
    "今日涨跌": "Breadth Today",
    "未覆盖": "Not Covered",
    "正在读取站内标普500快照…": "Loading the site's S&P 500 snapshot…",
    "正在读取站内每日管道生成的标普500快照…": "Loading the S&P 500 snapshot generated by the site's daily pipeline…",
    "显示家数": "Number of companies shown",
    "热力图画布，可用滚轮或下方按钮缩放，放大后可拖动查看": "Heatmap canvas. Use the wheel or controls below to zoom; drag to pan after zooming.",
    "标普500成分股按行业分块的市值与当日涨跌热力图": "S&P 500 sector heatmap sized by market cap and colored by today's move",
    "滚轮缩放 · 按住左键拖动平移 · 也可用 + − 0 键": "Wheel to zoom · drag to pan · or use + − 0",
    "缩放": "Zoom",
    "缩小": "Zoom out",
    "放大": "Zoom in",
    "重置": "Reset",
    "以数据表查看": "View as data table",
    "标普500气泡图": "S&P 500 Bubble Chart",
    "纵轴区间": "Y-axis range",
    "同一批成分股换一种看法：横向按行业分列，纵向是这一档的涨跌，气泡面积正比于市值。\n        颜色与热力图同一套色阶——两张图摆在一页上，不该为了看第二张重新学一遍颜色。\n        行业身份由列的位置与列标题承担，不另派十一种颜色：气泡这类任意两点都可能相邻的图形，\n        分类色最多撑得住三种，十一种在色觉差异下必然有几对分不开。放得下的气泡上直接标出公司名与股价。": "The same constituents shown another way: sectors run across the x-axis, the y-axis shows the selected return range, and bubble area is proportional to market cap. The color scale matches the heatmap. Sector identity is carried by column position and labels rather than eleven extra category colors; bubbles with enough space show company name and price.",
    "气泡图画布，可用滚轮或下方按钮缩放，放大后可拖动查看": "Bubble-chart canvas. Use the wheel or controls below to zoom; drag to pan after zooming.",
    "滚轮缩放 · 按住左键拖动平移 · 放大后小气泡也写得出公司名与股价 · 也可用 + − 0 键": "Wheel to zoom · drag to pan · zoom in to reveal names and prices on smaller bubbles · or use + − 0",
    "气泡图缩放": "Bubble-chart zoom"
  };

  var OFR = {
    /* 五个子指标标签、G-SIB 银行名与页尾说明；说明段在 DOM 里被 <b> 拆开，按节点各配一条。
       银行名用各行官方英文名，不音译。 */
    "信用": "Credit",
    "股票估值": "Equity valuation",
    "融资": "Funding",
    "避险资产": "Safe assets",
    "波动率": "Volatility",
    "银行系统性风险": "Systemic banking risk",
    "家美国 G-SIB · 系统性资本附加": "U.S. G-SIBs · systemic capital surcharge",
    "摩根大通": "JPMorgan Chase",
    "花旗集团": "Citigroup",
    "高盛": "Goldman Sachs",
    "美国银行": "Bank of America",
    "摩根士丹利": "Morgan Stanley",
    "富国银行": "Wells Fargo",
    "纽约梅隆银行": "BNY Mellon",
    "道富银行": "State Street",
    "适用 2025 年 · 美联储据 2023 年末数据核定":
      "Applies to 2025 · Set by the Federal Reserve from year-end 2023 data",
    "数据来源：": "Source: ",
    "· 金融研究办公室，美国财政部下属机构 · 公开数据，仅供参考，不构成投资建议。":
      " · Office of Financial Research, an agency of the U.S. Treasury · Public data, for reference only; not investment advice.",
    "本页汇集美国财政部下属「金融研究办公室」（Office of Financial Research，OFR）的五大监测工具：":
      "This page collects the five monitors published by the Office of Financial Research (OFR), an agency of the U.S. Treasury: ",
    "（每日，0 为历史平均压力，正值高于平均、负值低于平均）、":
      " (daily; 0 is the historical average level of stress, positive is above average and negative below), ",
    "（每日，SOFR/EFFR 等隔夜利率与成交量）、":
      " (daily; overnight rates and volumes such as SOFR and EFFR), ",
    "货币市场基金规模": "money market fund assets",
    "（每月）、": " (monthly), ",
    "（每季度，SEC Form PF 汇总的总资产/净资产/杠杆）与":
      " (quarterly; gross assets, net assets and leverage aggregated from SEC Form PF), and ",
    "（美国 8 家 G-SIB 系统性资本附加，美联储约年度核定，反映各行系统重要性）。数据来源为 OFR 公开数据接口（金融压力指数 CSV、短期融资监测 STFM API、对冲基金监测 HFM API）及美联储 G-SIB 附加资本核定，在服务端定时抓取后静态托管。所有数据仅供参考，不构成投资建议。":
      " (the systemic capital surcharge for the eight U.S. G-SIBs, set by the Federal Reserve roughly annually and reflecting each bank's systemic importance). Data comes from the OFR's public interfaces (the Financial Stress Index CSV, the STFM short-term funding API and the HFM hedge fund API) plus the Federal Reserve's G-SIB surcharge determinations, fetched on a schedule server-side and hosted statically. All data is for reference only and is not investment advice.",
    "🏛️ 美国金融风险监测": "🏛️ U.S. Financial Risk Monitor",
    "OFR 五大监测 · 金融压力 · 短期融资 · 货币基金 · 对冲基金 · 银行系统性风险": "Five OFR monitors · Financial stress · Short-term funding · Money market funds · Hedge funds · Systemic banking risk",
    "四类细分市场监测": "Four Market Monitors",
    "金融压力指数暂无数据": "Financial Stress Index data unavailable",
    "高于平均压力": "Above-average stress",
    "低于平均压力": "Below-average stress",
    "接近平均水平": "Near historical average",
    "较前值": "vs. prior",
    "🇺🇸 美国": "🇺🇸 United States",
    "其他发达": "Other Advanced",
    "新兴市场": "Emerging Markets",
    "按地区贡献": "Contribution by Region",
    "按类别贡献": "Contribution by Category",
    "金融压力指数": "Financial Stress Index",
    "OFR 原表 →": "OFR source →",
    "近一年": "Past year",
    "0 = 历史平均压力": "0 = historical average stress",
    "前往 OFR →": "Open OFR →",
    "短期融资监测": "Short-Term Funding Monitor",
    "EFFR 联邦基金利率": "EFFR federal funds rate",
    "SOFR 成交量": "SOFR volume",
    "隔夜担保融资利率（SOFR）、联邦基金利率与回购成交量。": "Secured Overnight Financing Rate (SOFR), federal funds rate and repo volume.",
    "货币市场基金": "Money Market Funds",
    "较上月": "vs. prior month",
    "万亿 · 总规模": "trillion · total assets",
    "美国货币市场基金总规模及资产结构。": "Total U.S. money-market-fund assets and asset composition.",
    "对冲基金监测": "Hedge Fund Monitor",
    "万亿 · 总资产 GAV": "trillion · gross assets (GAV)",
    "万亿 · 净资产 NAV": "trillion · net assets (NAV)",
    "净资产 NAV": "Net assets (NAV)",
    "总杠杆 GAV/NAV": "Gross leverage GAV/NAV",
    "季度更新": "Quarterly update",
    "季度": "Quarterly",
    "银行系统性风险监测": "Systemic Banking Risk Monitor",
    "关于本页数据": "About This Data"
  };

  var FINANCE = {
    /* 首屏导语、八层标签与页脚：这几条此前漏在外面，英文下整页只有标题是英文 */
    "一套自下而上、层层递进的金融认知地图——从数学基础到专业纵深与监管合规，覆盖华尔街前台 / 中台 / 后台、危机机制与认知元层的完整知识体系。":
      "A bottom-up, layer-by-layer map of financial knowledge — from mathematical foundations through specialist depth to regulation and compliance, covering Wall Street's front, middle and back office, crisis mechanics and the meta layer of cognition.",
    "本框架从数学基础出发，逐层构建至专业纵深与监管合规，覆盖华尔街从业者所需的完整知识体系——前台 / 中台 / 后台、危机机制、认知元层与专业纵深无所不包。八个层级层层依赖：L1 数理工具 → L2 市场机制 → L3 衍生品定价 → L4 组合与风险 → L5 另类与结构化 → L6 宏观与行为 → L7 专业纵深 → L8 监管与合规。校验坐标：CFA × FRM × SOA 精算 × 顶级商学院 × Bloomberg × ISDA/BIS/IOSCO × 投行培训 × Pozsar / Mehrling / Brunnermeier / Gatheral 学术与实务。":
      "The framework starts from mathematical foundations and builds layer by layer to specialist depth, regulation and compliance, covering what a Wall Street practitioner needs across front, middle and back office, crisis mechanics, the meta layer of cognition and vertical specialisms. The eight layers build on one another: L1 Mathematical Tools → L2 Market Mechanics → L3 Derivatives Pricing → L4 Portfolio & Risk → L5 Alternatives & Structured Products → L6 Macro & Behaviour → L7 Specialist Depth → L8 Regulation & Compliance. Calibrated against CFA, FRM, SOA actuarial, top business-school curricula, Bloomberg, ISDA/BIS/IOSCO, investment-bank training programmes, and the academic and practitioner work of Pozsar, Mehrling, Brunnermeier and Gatheral.",
    "金融工程的数学根基——从线性代数到随机微积分，涵盖定价与风控所需的全部数学工具。":
      "The mathematical bedrock of financial engineering — from linear algebra to stochastic calculus, covering every mathematical tool pricing and risk management needs.",
    "展开 →": "Expand →",
    "从订单簿到暗池——理解价格如何形成、流动性如何流转、交易如何执行与清算。":
      "From the order book to dark pools — how prices form, how liquidity moves, and how trades are executed and cleared.",
    "从 Black-Scholes 到粗糙波动率——覆盖全谱系衍生品定价理论与数值方法。":
      "From Black-Scholes to rough volatility — the full spectrum of derivatives pricing theory and numerical methods.",
    "从 Markowitz 到气候 VaR——资产配置、因子投资、风险度量与绩效归因的全面框架。":
      "From Markowitz to climate VaR — a complete framework for asset allocation, factor investing, risk measurement and performance attribution.",
    "从 CLO 到私募信贷——另类投资、结构化产品与大宗商品的完整知识图谱。":
      "From CLOs to private credit — a full knowledge graph of alternatives, structured products and commodities.",
    "从 Eurodollar 体系到行为偏差——理解驱动市场的宏观力量与人类认知局限。":
      "From the Eurodollar system to behavioural bias — the macro forces that drive markets and the limits of human cognition.",
    "保险精算、贸易融资、ESG、房地产、主权债务、量化架构与金融科技——垂直领域的专业深度。":
      "Actuarial science, trade finance, ESG, real estate, sovereign debt, quantitative architecture and fintech — depth in the vertical specialisms.",
    "全新层级——从 Basel III/IV 到反洗钱，覆盖全球金融监管体系与合规科技。":
      "A new layer — from Basel III/IV to anti-money-laundering, covering global financial regulation and compliance technology.",
    "· 内容长期更新中": "· Continuously updated",
    "校验坐标：CFA × FRM × SOA 精算 × 商学院 × Bloomberg × ISDA/BIS/IOSCO":
      "Calibrated against: CFA × FRM × SOA actuarial × business-school curricula × Bloomberg × ISDA/BIS/IOSCO",
    "© 2026 ooglex.com · 仅供学习交流，不构成任何投资建议":
      "© 2026 ooglex.com · For study and discussion only; not investment advice",
    "金融专栏 · 终极架构": "Finance Column · Ultimate Architecture",
    "金融知识终极架构": "Ultimate Financial Knowledge Architecture",
    "层级 Layers": "Layers",
    "模块 Modules": "Modules",
    "术语 Terms": "Terms",
    "双语": "Bilingual",
    "中英对照": "Chinese / English",
    "🔍 检索 560+ 术语（中文 / English / 缩写，如 VaR、波动率、CLO、Basel…）": "🔍 Search 560+ terms (English / Chinese / abbreviations, e.g. VaR, volatility, CLO, Basel…)",
    "概念因果推导图谱": "Causal Concept Maps",
    "用箭头把一个体系内的概念按因果关系串起来——利率、流动性、国债、美元、杠杆…": "Connect concepts within a financial system by causal links—rates, liquidity, Treasuries, the dollar, leverage and more.",
    "进入图谱 →": "Open Maps →",
    "架构总览": "Architecture Overview",
    "金融知识终极架构 · 内容长期更新中": "Ultimate Financial Knowledge Architecture · Continuously updated",
    "仅供学习交流，不构成任何投资建议": "For learning and discussion only; not investment advice",
    "← 架构总览": "← Architecture Overview",
    "主页": "Home",
    "金融架构": "Financial Architecture",
    "正在加载…": "Loading…",
    "v4.0 新增": "NEW in v4.0",
    "← 上一层": "← Previous Layer",
    "下一层 →": "Next Layer →",
    "因果推导图谱": "Causal Maps",
    "张图谱": "maps",
    "原生": "Native",
    "可缩放矢量": "Scalable vector",
    "持续": "Ongoing",
    "更新中": "Updating",
    "点击放大": "Click to enlarge",
    "因果链 ·": "Causal chain ·",
    "金融知识终极架构 · 概念因果推导图谱（网页原生矢量绘制）· 内容长期更新中": "Ultimate Financial Knowledge Architecture · Causal concept maps (native web vectors) · Continuously updated"
  };

  var MOVIES = {
    /* 片名换成 apps/movies/data.json 里的原名（TMDB `orig`）。另有 36 条原名本身是
       中日韩文（如《千与千寻》的原名是「千と千尋の神隠し」），换过去对英文读者
       没有帮助，那些保留中文片名，不硬凑。 */
    "肖申克的救赎": "The Shawshank Redemption",
    "教父": "The Godfather",
    "辛德勒的名单": "Schindler's List",
    "蝙蝠侠：黑暗骑士": "The Dark Knight",
    "教父2": "The Godfather Part II",
    "星际穿越": "Interstellar",
    "指环王3：王者无敌": "The Lord of the Rings: The Return of the King",
    "十二怒汉": "12 Angry Men",
    "绿里奇迹": "The Green Mile",
    "低俗小说": "Pulp Fiction",
    "挽救计划": "Project Hail Mary",
    "阿甘正传": "Forrest Gump",
    "搏击俱乐部": "Fight Club",
    "迈克尔·杰克逊：巨星之路": "Michael",
    "好家伙": "GoodFellas",
    "奇幻变身大冒险": "Swapped",
    "指环王1：护戒使者": "The Lord of the Rings: The Fellowship of the Ring",
    "美丽人生": "La vita è bella",
    "黄金三镖客": "Il buono, il brutto, il cattivo",
    "指环王2：双塔奇兵": "The Lord of the Rings: The Two Towers",
    "盗梦空间": "Inception",
    "蜘蛛侠：平行宇宙": "Spider-Man: Into the Spider-Verse",
    "星球大战5：帝国反击战": "The Empire Strikes Back",
    "七宗罪": "Se7en",
    "飞越疯人院": "One Flew Over the Cuckoo's Nest",
    "爆裂鼓手": "Whiplash",
    "安昂传奇：最后的气宗": "Avatar Aang: The Last Airbender",
    "惊魂记": "Psycho",
    "勇夺芳心": "दिलवाले दुल्हनिया ले जायेंगे",
    "沉默的羔羊": "The Silence of the Lambs",
    "上帝之城": "Cidade de Deus",
    "钢琴家": "The Pianist",
    "回到未来": "Back to the Future",
    "蜘蛛侠：纵横宇宙": "Spider-Man: Across the Spider-Verse",
    "美国X档案": "American History X",
    "这个杀手不太冷": "Léon",
    "美国往事": "Once Upon a Time in America",
    "天堂电影院": "Nuovo Cinema Paradiso",
    "死亡诗社": "Dead Poets Society",
    "触不可及": "Intouchables",
    "黑客帝国": "The Matrix",
    "复仇者联盟3：无限战争": "Avengers: Infinity War",
    "复仇者联盟4：终局之战": "Avengers: Endgame",
    "狮子王": "The Lion King",
    "后窗": "Rear Window",
    "荒野机器人": "The Wild Robot",
    "角斗士": "Gladiator",
    "拯救大兵瑞恩": "Saving Private Ryan",
    "现代启示录": "Apocalypse Now",
    "无耻混蛋": "Inglourious Basterds",
    "生活多美好": "It's a Wonderful Life",
    "西部往事": "C'era una volta il West",
    "星球大战4：新希望": "Star Wars",
    "绿皮书": "Green Book",
    "致命魔术": "The Prestige",
    "禁闭岛": "Shutter Island",
    "楚门的世界": "The Truman Show",
    "被解救的姜戈": "Django Unchained",
    "加百列的地狱": "Gabriel's Inferno",
    "闪灵": "The Shining",
    "寻梦环游记": "Coco",
    "异形": "Alien",
    "终结者2：审判日": "Terminator 2: Judgment Day",
    "摩登时代": "Modern Times",
    "穿靴子的猫2": "Puss in Boots: The Last Wish",
    "未麻的部屋": "PERFECT BLUE",
    "大独裁者": "The Great Dictator",
    "血战钢锯岭": "Hacksaw Ridge",
    "相助": "The Help",
    "七号房的礼物": "7. Koğuştaki Mucize",
    "玩具总动员5": "Toy Story 5",
    "记忆碎片": "Memento",
    "五尺天涯": "Five Feet Apart",
    "发条橙": "A Clockwork Orange",
    "日落大道": "Sunset Boulevard",
    "心灵捕手": "Good Will Hunting",
    "克劳斯：圣诞节的秘密": "Klaus",
    "无间道风云": "The Departed",
    "非常嫌疑犯": "The Usual Suspects",
    "痴迷": "Obsession",
    "超级马力欧银河大电影": "The Super Mario Galaxy Movie",
    "蛊惑兄弟": "O Auto da Compadecida",
    "疤面煞星": "Scarface",
    "加百列的地狱：第二部": "Gabriel's Inferno: Part II",
    "惩罚者：最后一击": "The Punisher: One Last Kill",
    "城市之光": "City Lights",
    "机器人总动员": "WALL·E",
    "光荣之路": "Paths of Glory",
    "小丑": "Joker",
    "沙丘2": "Dune: Part Two",
    "桃色公寓": "The Apartment",
    "妈咪": "Mommy",
    "卡萨布兰卡": "Casablanca",
    "一年中的生活": "Life in a Year",
    "海上钢琴师": "La leggenda del pianista sull'oceano",
    "落水狗": "Reservoir Dogs",
    "加百列的地狱：第三部": "Gabriel's Inferno: Part III",
    "囚徒": "Prisoners",
    "暖暖内含光": "Eternal Sunshine of the Spotless Mind",
    "奇爱博士": "Dr. Strangelove or: How I Learned to Stop Worrying and Love the Bomb",
    "出租车司机": "Taxi Driver",
    "自己去看": "Иди и смотри",
    "黑帮悍将": "Bound by Honor",
    "全金属外壳": "Full Metal Jacket",
    "偷自行车的人": "Ladri di biciclette",
    "控方证人": "Witness for the Prosecution",
    "第七封印": "Det sjunde inseglet",
    "怪形": "The Thing",
    "奇迹男孩": "Wonder",
    "黑暗正义联盟：天启星战争": "Justice League Dark: Apokolips War",
    "心灵奇旅": "Soul",
    "哈利·波特与死亡圣器（下）": "Harry Potter and the Deathly Hallows: Part 2",
    "河狸变身计划": "Hoppers",
    "复仇者联盟": "The Avengers",
    "迷魂记": "Vertigo",
    "云上情歌": "Clouds",
    "两杆大烟枪": "Lock, Stock and Two Smoking Barrels",
    "请以你的名字呼唤我": "Call Me by Your Name",
    "寻子遇仙记": "The Kid",
    "多哥": "Togo",
    "何以为家": "کفرناحوم",
    "怒火青春": "La Haine",
    "狩猎": "Jagten",
    "我在雨中等你": "The Art of Racing in the Rain",
    "狼行者": "Wolfwalkers",
    "扎克·施奈德版正义联盟": "Zack Snyder's Justice League",
    "假面": "Persona",
    "焦土之城": "Incendies",
    "雨中曲": "Singin' in the Rain",
    "困在时间里的父亲": "The Father",
    "燃烧女子的肖像": "Portrait de la jeune fille en feu",
    "鹬": "Piper",
    "看不见的客人": "Contratiempo",
    "热情如火": "Some Like It Hot",
    "血色将至": "There Will Be Blood",
    "大都会": "Metropolis",
    "潜行者": "Сталкер",
    "三块广告牌": "Three Billboards Outside Ebbing, Missouri",
    "从海底出击": "Das Boot",
    "傲慢与偏见": "Pride & Prejudice",
    "八部半": "8½",
    "双重赔偿": "Double Indemnity",
    "隐藏人物": "Hidden Figures",
    "2001太空漫游": "2001: A Space Odyssey",
    "杀死比尔：血色全传": "Kill Bill: The Whole Bloody Affair",
    "猫猫的奇幻漂流": "Straume",
    "真人快打传奇：蝎子的复仇": "Mortal Kombat Legends: Scorpion's Revenge",
    "德州巴黎": "Paris, Texas",
    "精英部队": "Tropa de Elite",
    "你给的仇恨": "The Hate U Give",
    "象人": "The Elephant Man",
    "野草莓": "Smultronstället",
    "奇迹少女 纽约篇": "Miraculous World : New York, les héros unis",
    "M就是凶手": "M - Eine Stadt sucht einen Mörder",
    "彗星美人": "All About Eve",
    "中央车站": "Central do Brasil",
    "雄狮": "Lion",
    "还有明天": "C'è ancora domani",
    "紫心之恋": "Purple Hearts",
    "窃听风暴": "Das Leben der Anderen",
    "华尔街之狼": "The Wolf of Wall Street",
    "布达佩斯大饭店": "The Grand Budapest Hotel",
    "一条狗的使命2": "A Dog's Journey",
    "奇迹梦之队": "GOAT",
    "黄昏双镖客": "Per qualche dollaro in più",
    "莫扎特传": "Amadeus",
    "甜蜜的生活": "La dolce vita",
    "驯龙高手：重回家园": "How to Train Your Dragon: Homecoming",
    "怦然心动": "Flipped",
    "哈利·波特与阿兹卡班的囚徒": "Harry Potter and the Prisoner of Azkaban",
    "骗中骗": "The Sting",
    "奥德赛": "The Odyssey",
    "切肤之痛": "Sulla mia pelle",
    "三傻大闹宝莱坞": "3 Idiots",
    "梦之安魂曲": "Requiem for a Dream",
    "极速车王": "Ford v Ferrari",
    "恐惧的代价": "Le Salaire de la peur",
    "心跳瞬间": "In a Heartbeat",
    "福尔摩斯二世": "Sherlock Jr.",
    "我的名字叫可汗": "My Name Is Khan",
    "变形金刚：起源": "Transformers One",
    "电话谋杀案": "Dial M for Murder",
    "忠犬八公的故事": "Hachi: A Dog's Tale",
    "K-Pop 猎魔女团": "KPop Demon Hunters",
    "巴里·林登": "Barry Lyndon",
    "地球上的星星": "तारे ज़मीन पर",
    "阿拉伯的劳伦斯": "Lawrence of Arabia",
    "赌城风云": "Casino",
    "四百击": "Les Quatre Cents Coups",
    "奥本海默": "Oppenheimer",
    "吉尔莫·德尔·托罗的匹诺曹": "Guillermo del Toro's Pinocchio",
    "美国丽人": "American Beauty",
    "海洋之歌": "Song of the Sea",
    "纸人": "Paperman",
    "天才少女": "Gifted",
    "至爱梵高·星空之谜": "Loving Vincent",
    "圣女贞德蒙难记": "La Passion de Jeanne d'Arc",
    "杀死一只知更鸟": "To Kill a Mockingbird",
    "老爷车": "Gran Torino",
    "房间": "Room",
    "玩具总动员": "Toy Story",
    "淘金记": "The Gold Rush",
    "谜一样的双眼": "El secreto de sus ojos",
    "镜子": "Зеркало",
    "碧血金沙": "The Treasure of the Sierra Madre",
    "三个男人一只脚": "Tre uomini e una gamba",
    "迷墙": "Pink Floyd: The Wall",
    "绝境盟约": "La sociedad de la nieve",
    "爱，简单": "Hoje Eu Quero Voltar Sozinho",
    "爱在黎明破晓前": "Before Sunrise",
    "绵羊侦探团": "The Sheep Detectives",
    "歪心狼对阵ACME": "Coyote vs. Acme",
    "逃出绝命街": "The End of Oak Street",
    "怒之杀": "Mutiny",
    "生化危机：爆发夜": "Resident Evil",
    "击中爱情": "விஸ்வநாத் & சன்ஸ்",
    "汪汪队立大功大电影3：勇闯恐龙岛": "PAW Patrol: The Dino Movie",
    "魔法情缘": "Practical Magic 2",
    "罪火焦点": "Hot Spot",
    "坠落2：死点": "Fall 2: Deadpoint",
    "护肝人": "Runner",
    "养蜂人的对手": "The Rivals of Amziah King",
    "潜伏6：血域": "Insidious: Out of the Further",
    "末世行者": "The Dog Stars",
    "毒：成人童话": "ಟಾಕ್ಸಿಕ್",
    "托尼": "Tony",
    "诈死游戏": "Just Play Dead",
    "赛车总动员": "Cars",
    "起义": "The Uprising",
    "逃出布迪秀": "Buddy",
    "不择手段": "By Any Means",
    "爱乐之城": "La La Land",
    "寻找艾米丽": "Finding Emily",
    "阿基拉": "AKIRA",
    "耶稣受难记": "The Passion of the Christ",
    "坠河的女孩": "The Girl in the River",
    "新年狂欢": "Nimrods",
    "脑波猎场": "The Wrong Girls",
    "月光男孩": "Moonlight",
    "猛攻": "Onslaught",
    "我们未曾有过的": "Todo lo que nunca fuimos",
    "逃无止境": "It Ends",
    "监狱雄心": "The Weight",
    "鳄鱼脸": "Gator Face",
    "瘴气营地的青春性事与死亡": "Teenage Sex and Death at Camp Miasma",
    "伊鲁穆迪": "ఇరుముడి",
    "水疗周末": "Spa Weekend",
    "小羊肖恩3：青苔农场的怪兽": "Shaun the Sheep: The Beast of Mossy Bottom",
    "远方的魔法树": "The Magic Faraway Tree",
    "核战边缘": "The Brink of War",
    "害群之马": "Bad Apples",
    "变形金刚大电影": "The Transformers: The Movie",
    "校园大逃杀2：篝火行动": "Run Hide Fight: Infidels",
    "肥佬教授": "The Nutty Professor",
    "蝙蝠侠大战幻影人": "Batman: Mask of the Phantasm",
    "诺斯费拉图": "Nosferatu",
    "卡里加里博士的小屋": "The Cabinet of Dr. Caligari",
    "活死人之夜": "Night of the Living Dead",
    "将军号": "The General",
    "谜中谜": "Charade",
    "战舰波将金号": "Battleship Potemkin",
    "西线无战事": "All Quiet on the Western Front",
    "持摄影机的人": "Man with a Movie Camera",
    "女友礼拜五": "His Girl Friday",
    "安全至下": "Safety Last!",
    "陌生人": "The Stranger",
    "摄影师": "The Cameraman",
    "血红街道": "Scarlet Street",
    "女巫": "Häxan",
    "猛鬼屋": "House on Haunted Hill",
    "船长二世": "Steamboat Bill, Jr.",
    "我的戈弗雷": "My Man Godfrey",
    "灵魂狂欢节": "Carnival of Souls",
    "幽灵马车": "The Phantom Carriage",
    "绕道": "Detour",
    "歌剧魅影": "The Phantom of the Opera",
    "七次机会": "Seven Chances",
    "地球最后一人": "The Last Man on Earth",
    "待客之道": "Our Hospitality",
    "房客": "The Lodger",
    "恐怖小店": "The Little Shop of Horrors",
    "北方的纳努克": "Nanook of the North",
    "黄金时代": "L'Age d'Or",
    "约翰·多伊": "Meet John Doe",
    "最危险的游戏": "The Most Dangerous Game",
    "航海家": "The Navigator",
    "拿破仑": "Napoleon",
    "玩家马布斯博士": "Dr. Mabuse, the Gambler",
    "动物饼干": "Animal Crackers",
    "一个明星的诞生": "A Star Is Born",
    "笑面人": "The Man Who Laughs",
    "奥赛罗": "Othello",
    "泥人哥连出世记": "The Golem: How He Came into the World",
    "独眼龙": "One-Eyed Jacks",
    "残花泪": "Broken Blossoms",
    "讹诈": "Blackmail",
    "群众": "The Crowd",
    "铁汉雌虎": "McLintock!",
    "贪婪": "Greed",
    "十月": "October (Ten Days that Shook the World)",
    "月宫宝盒": "The Thief of Bagdad",
    "白魔鬼": "White Zombie",
    "搭便车的人": "The Hitch-Hiker",
    "奇爱疑云": "The Strange Love of Martha Ivers",
    "死亡漩涡": "D.O.A.",
    "尼伯龙根：西格弗里德之死": "Die Nibelungen: Siegfried",
    "爵士歌手": "The Jazz Singer",
    "疯狂的一页": "A Page of Madness",
    "阿卡丁先生": "Mr. Arkadin",
    "巴黎一妇人": "A Woman of Paris",
    "大爵士乐队": "The Big Combo",
    "外太空计划9": "Plan 9 from Outer Space",
    "失落的世界": "The Lost World",
    "朝圣者": "The Pilgrim",
    "卡比利亚": "Cabiria",
    "劳莱与哈台之飞天两条友": "The Flying Deuces",
    "西行": "Go West",
    "血流成河": "A Bucket of Blood",
    "战地之花": "The Big Parade",
    "边城蒙面侠": "Kansas City Confidential",
    "柏林：城市交响曲": "Berlin: Symphony of a Great City",
    "摩洛哥": "Morocco",
    "恐怖之夜": "Terror by Night",
    "绿衣女子": "The Woman in Green",
    "战胜恶魔": "Beat the Devil",
    "三个时代": "Three Ages",
    "迷失少女日记": "Diary of a Lost Girl",
    "剃刀边缘": "Dressed to Kill",
    "新生": "The Freshman",
    "爱情事件": "Love Affair",
    "告别武器": "A Farewell to Arms",
    "痴呆症": "Dementia 13",
    "第七天堂": "7th Heaven",
    "福尔摩斯与秘密武器": "Sherlock Holmes and the Secret Weapon",
    "大追踪": "The Big Trail",
    "钟楼怪人": "The Hunchback of Notre Dame",
    "人生的枷锁": "Of Human Bondage",
    "月里嫦娥": "Woman in the Moon",
    "挨了耳光的男人": "He Who Gets Slapped",
    "宾虚": "Ben-Hur: A Tale of the Christ",
    "大学": "College",
    "星期天的人们": "People on Sunday",
    "纽约船坞": "The Docks of New York",
    "小人国": "Gulliver's Travels",
    "都市女郎": "City Girl",
    "一路向东": "Way Down East",
    "小公主": "The Little Princess",
    "秋缠断肠记": "Penny Serenade",
    "天使与魔鬼": "Angel and the Badman",
    "追踪天涯": "Woman on the Run",
    "蝙蝠": "The Bat",
    "恐怖古堡": "The Terror",
    "重婚者": "The Bigamist",
    "突然": "Suddenly",
    "不公平的遭遇": "Raw Deal",
    "百老汇旋律": "The Broadway Melody",
    "社会中坚": "Salt of the Earth",
    "小兄弟": "The Kid Brother",
    "王室的婚礼": "Royal Wedding",
    "战将巴特勒": "Battling Butler",
    "黑狱杀人王": "He Walked by Night",
    "地狱天使": "Hell's Angels",
    "暴风雨中的孤儿": "Orphans of the Storm",
    "最后命令": "The Last Command",
    "毫不神圣": "Nothing Sacred",
    "地下世界": "Underworld",
    "悔之已晚": "Too Late for Tears",
    "夜潮": "Night Tide",
    "欲海奇鸳": "The Prowler",
    "T人": "T-Men",
    "猫和金丝雀": "The Cat and the Canary",
    "十诫": "The Ten Commandments",
    "乞力马扎罗的雪": "The Snows of Kilimanjaro",
    "佐罗的标记": "The Mark of Zorro",
    "犯罪的都市": "The Front Page",
    "铁骑": "The Iron Horse",
    "不死之脑": "The Brain That Wouldn't Die",
    "红屋情魔": "The Red House",
    "大鼻子情圣": "Cyrano de Bergerac",
    "不法之徒": "The Outlaw",
    "孟克斯人": "The Manxman",
    "真情难诉": "Girl Shy",
    "巴厘岛之路": "Road to Bali",
    "大麻烟疯潮": "Reefer Madness",
    "天伦乐": "Life with Father",
    "玉女弄璋": "Father's Little Dividend",
    "火星女王艾莉塔": "Aelita: Queen of Mars",
    "农家妇": "The Farmer's Wife",
    "上海风光": "The Shanghai Gesture",
    "一屋之主": "Master of the House",
    "大地之光": "The Southerner",
    "黄蜂女": "The Wasp Woman",
    "蜡人馆": "Waxworks",
    "迷梦追踪": "The Chase",
    "万王之王": "The King of Kings",
    "蝠魔": "The Devil Bat",
    "春天的女神": "The Goddess",
    "亚洲风暴": "Storm Over Asia",
    "厄舍古厦的倒塌": "The Fall of the House of Usher",
    "水性杨花": "Easy Virtue",
    "斯文加利": "Svengali",
    "黑海盗": "The Black Pirate",
    "美艳亲王": "My Favorite Brunette",
    "惩罚": "The Penalty",
    "机械怪兽": "Robot Monster",
    "启示录四骑士": "The Four Horsemen of the Apocalypse",
    "吸血蝙蝠": "The Vampire Bat",
    "礼帽回归": "Topper Returns",
    "钦差大臣": "The Inspector General",
    "我最后一次看见巴黎": "The Last Time I Saw Paris",
    "罗宾汉": "Robin Hood",
    "非洲滑稽人": "Africa Screams",
    "杀人鼩": "The Killer Shrews",
    "心字已成灰": "Hollow Triumph",
    "圣非小路": "Santa Fe Trail",
    "虐待狂": "The Sadist",
    "鹰": "The Eagle",
    "沙漠情酋": "The Sheik",
    "狗房谋杀案": "The Kennel Murder Case",
    "夫妇之道": "That Uncertain Feeling",
    "生而为彼": "Made for Each Other",
    "杰克与仙豆": "Jack and the Beanstalk",
    "圣诞老人征服火星人": "Santa Claus Conquers the Martians",
    "祖母的孩子": "Grandma's Boy",
    "了不起的X先生": "The Amazing Mr. X",
    "虎踞龙盘": "Vengeance Valley",
    "麻雀": "Sparrows",
    "着什么急？": "Why Worry?",
    "巨蛭之祸": "Attack of the Giant Leeches",
    "消失的尸体": "The Corpse Vanishes",
    "战争与敌人": "At War with the Army",
    "无形幽灵": "Invisible Ghost",
    "超越时间障碍": "Beyond the Time Barrier",
    "蓝胡子": "Bluebeard",
    "圣彼得堡的末日": "The End of St. Petersburg",
    "绿野仙踪": "The Wizard of Oz",
    "僵尸之王": "King of the Zombies",
    "陌生女人": "The Strange Woman",
    "哈利路亚": "Hallelujah",
    "火箭飞船X-M": "Rocketship X-M",
    "除了明天": "Beyond Tomorrow",
    "梨花泪": "Cause for Alarm!",
    "地球上最后一个女人": "Last Woman on Earth",
    "青草：一个民族的生活之战": "Grass: A Nation's Battle for Life",
    "爵士之王": "King of Jazz",
    "太阳之血": "Blood on the Sun",
    "尖叫的头骨": "The Screaming Skull",
    "流沙": "Quicksand",
    "虫先生进城记": "Mr. Bug Goes to Town",
    "正邪之间": "Shield for Murder",
    "外层空间少年": "Teenagers from Outer Space",
    "萨乐美": "Salomé",
    "蝙蝠祟": "The Bat Whispers",
    "金发冰美人": "Blonde Ice",
    "神奇的透明人": "The Amazing Transparent Man",
    "伏都教徒": "Voodoo Man",
    "第二合唱队": "Second Chorus",
    "杰克医生": "Dr. Jack",
    "不灭人魔": "Indestructible Man",
    "毒蜥蜴": "The Giant Gila Monster",
    "山艾树小径": "Sagebrush Trail",
    "林肯传": "Abraham Lincoln",
    "铁面人": "The Iron Mask",
    "帕吕峰的白色地狱": "The White Hell of Pitz Palu",
    "滚烫热水": "Hot Water",
    "科斯塔·柏林的故事": "The Saga of Gösta Berling",
    "大红树": "The Big Trees",
    "大弗拉马里翁": "The Great Flamarion",
    "雷霆之怒": "The Fast and the Furious",
    "酋长的儿子": "The Son of the Sheik",
    "魔星袭地球": "Killers from Space",
    "蓝钢": "Blue Steel",
    "下套": "Trapped",
    "陷害": "Railroaded!",
    "恶魔之手": "The Devil's Hand",
    "月球猫女": "Cat-Women of the Moon",
    "威斯特先生苏联历险记": "The Extraordinary Adventures of Mr. West in the Land of the Bolsheviks",
    "黎明之怒": "Rage at Dawn",
    "夜色骇人": "Fear in the Night",
    "亚利桑那天空下": "'Neath the Arizona Skies",
    "夜半歌声": "Song at Midnight",
    "执星者": "The Star Packer",
    "鬼海怪物": "Creature from the Haunted Sea",
    "血字的研究": "A Study in Scarlet",
    "兰迪独行": "Randy Rides Alone",
    "乱云飞渡": "Till the Clouds Roll By",
    "象：一部荒野戏剧": "Chang: A Drama of the Wilderness",
    "黄先生探案": "Mr. Wong, Detective",
    "德州暴徒": "Texas Terror",
    "请你杀了我": "Please Murder Me",
    "午夜鲍厄里": "Bowery at Midnight",
    "步步登高": "Feet First",
    "冷酷": "Ruthless",
    "命运的主宰者": "Riders of Destiny",
    "新巴比伦": "The New Babylon",
    "我可爱的秘书": "My Dear Secretary",
    "浮华世界": "Becky Sharp",
    "幸运德州人": "The Lucky Texan",
    "黎明骑士": "The Dawn Rider",
    "非法边境线": "The Lawless Frontier",
    "金壶": "Pot o' Gold",
    "陈查理之猩红的线索": "The Scarlet Clue",
    "小安妮·鲁尼": "Little Annie Rooney",
    "工合": "Gung Ho!",
    "内心圣所": "Inner Sanctum",
    "来自犹他州的人": "The Man from Utah",
    "边城豪侠": "Abilene Town",
    "未知的世界": "Unknown World",
    "怪物制造者": "The Monster Maker",
    "黄先生的秘密": "The Mystery of Mr. Wong",
    "沙漠小径": "The Desert Trail",
    "保留丈夫": "Kept Husbands",
    "吓死人": "Scared to Death",
    "大好人": "Great Guy",
    "摸不透的踪迹": "The Trail Beyond",
    "牛奶之路": "The Milky Way",
    "死人行走": "Dead Men Walk",
    "致命时刻": "The Fatal Hour",
    "风滚草": "Tumbleweeds",
    "黄先生在唐人街": "Mr. Wong in Chinatown",
    "奇怪的错觉": "Strange Illusion",
    "舞台门俱乐部": "Stage Door Canteen",
    "鬼魅行走": "The Ghost Walks",
    "雾岛": "Fog Island",
    "黑龙": "Black Dragons",
    "彩虹谷": "Rainbow Valley",
    "歌唱幸福": "Something to Sing About",
    "疯狂怪物": "The Mad Monster",
    "红粉干戈": "Whistle Stop",
    "天堂峡谷": "Paradise Canyon",
    "米莉": "Millie",
    "月宫毒仙子": "Missile to the Moon",
    "篷车队": "The Covered Wagon",
    "画山": "The Painted Hills",
    "血债血偿": "Jigsaw",
    "邪恶女人": "Wicked Woman",
    "大路": "The Big Road",
    "纽约港": "Port of New York",
    "堪萨斯太平洋": "Kansas Pacific",
    "日魔": "The Hideous Sun Demon",
    "唐璜": "Don Juan",
    "他的私人秘书": "His Private Secretary",
    "夜半尖叫": "A Shriek in the Night",
    "铁扇公主": "Princess Iron Fan",
    "僵尸的反叛": "Revolt of the Zombies",
    "一个惊恐之夜": "One Frightened Night",
    "多尔西兄弟": "The Fabulous Dorseys",
    "月球基地计划": "Project Moonbase",
    "判处活命": "Condemned to Live",
    "无畏泰山": "Tarzan the Fearless",
    "泰山与绿色女神": "Tarzan and the Green Goddess",
    "体育皇后": "Queen of Sports",
    "简爱": "Jane Eyre",
    "假释公司": "Parole, Inc.",
    "金钱疯狂": "Money Madness",
    "泰山的复仇": "Tarzan's Revenge",
    "神秘之屋": "House of Mystery",
    "恋爱与义务": "Love and Duty",
    "无赖酒馆": "The Rogues Tavern",
    "渔光曲": "Song of the Fishermen",
    "公开的秘密": "Open Secret",
    "帕鲁卡": "Palooka",
    "姊妹花": "Twin Sisters",
    "月球旅行记": "A Trip to the Moon",
    "爱丽丝梦游仙境": "Alice in Wonderland",
    "党同伐异": "Intolerance",
    "化身博士": "Dr. Jekyll and Mr. Hyde",
    "三剑客": "The Three Musketeers",
    "茶花女": "Camille",
    "命运": "Destiny",
    "最后一笑": "The Last Laugh",
    "浮士德": "Faust",
    "潘多拉的魔盒": "Pandora's Box",
    "蓝天使": "The Blue Angel",
    "新女性": "New Women",
    "马路天使": "Street Angel",
    "十字街头": "Crossroads",
    "雨": "Rain",
    "冲击": "Impact",
    "全球电影榜": "Global Movie Rankings",
    "高分电影 Top 250": "Top 250 by Rating",
    "全球最新上映": "Now Playing Worldwide",
    "公版经典 · 免费正片": "Public Domain Classics · Full films, free",
    "公有领域": "the public domain",
    "数据来自 TMDB（The Movie Database）公开 API：高分电影 Top 250（按票数加权排序、经典优先）与全球最新上映，含海报与中文片名，每日自动更新。点击海报可在线看官方预告片（YouTube），「公版经典」为已进入公有领域的经典电影（含华语老片）、正片由 Internet Archive 提供；观看渠道数据来自 TMDB × JustWatch。评分为 TMDB 用户评分，仅供参考。":
      "Data comes from the public TMDB (The Movie Database) API: the Top 250 by rating (weighted by vote count, favouring classics) and what is now playing worldwide, with posters and localized titles, refreshed daily. Click a poster to watch the official trailer (YouTube). “Public Domain Classics” are films that have entered the public domain (including older Chinese-language titles), with full films hosted by the Internet Archive; where-to-watch data comes from TMDB × JustWatch. Ratings are TMDB user scores and are for reference only.",
    "本页汇总高分电影 Top 250 与全球最新上映，含排名、评分与海报，数据来源 TMDB，每日自动更新。点击海报可在弹窗内播放":
      "This page gathers the Top 250 by rating and what is now playing worldwide, with ranks, scores and posters. Data comes from TMDB and refreshes daily. Click a poster to play the ",
    "（来自 YouTube），并附各地区": " (from YouTube) in a dialog, alongside regional ",
    "（数据来自 TMDB × JustWatch）；「公版经典」榜单为已进入":
      " (data from TMDB × JustWatch). The “Public Domain Classics” list covers films that have entered ",
    "的经典电影，完整正片由 Internet Archive 公益托管、可直接观看。本站不存储、不提供任何受版权保护影片的正片资源。评分为 TMDB 用户综合评分，会随投票动态变化；海报与资料版权归 TMDB 及片方所有。":
      ", with complete films hosted for free by the Internet Archive and watchable directly. This site stores and serves no full copies of any copyrighted film. Ratings are aggregate TMDB user scores and move with the votes; posters and metadata remain the copyright of TMDB and the rights holders.",
    "背景音乐": "Background music",
    "TOP全球电影榜": "TOP Global Movie Rankings",
    "高分电影 Top 250 · 全球最新上映 · 公版经典正片 · 点海报看预告片 · 每日自动更新": "Top-rated 250 · New worldwide releases · Public-domain classics · Click a poster for a trailer · Updated daily",
    "该榜单暂无数据，实时任务上线后展示 🙂": "No data in this list yet. It will appear after the live job refreshes 🙂",
    "正片": "Full film",
    "暂无可内嵌播放的预告片": "No embeddable trailer is currently available",
    "数据每日更新，也可用下方链接搜索观看": "Data updates daily; use the links below to search for viewing options",
    "公有领域 · 免费正片": "Public domain · Full film free",
    "官方预告片": "Official trailer",
    "📼 在 Internet Archive 打开": "📼 Open in Internet Archive",
    "▶ 在 YouTube 打开": "▶ Open in YouTube",
    "🔍 YouTube 搜预告片": "🔍 Search trailer on YouTube",
    "TMDB 详情 ↗": "TMDB details ↗",
    "该片已进入公有领域，正片由 Internet Archive 公益托管，可放心观看。": "This film is in the public domain and the full feature is hosted by Internet Archive.",
    "正版观看渠道": "Official Streaming Options",
    "渠道数据来自 TMDB × JustWatch，以各平台实际上架为准。": "Availability data comes from TMDB × JustWatch and may vary by platform and region.",
    "暂无该片的流媒体上架数据，可到 TMDB 详情页查看更多信息。": "No streaming availability is listed for this title. See TMDB for more information.",
    "实时 · 每日自动更新": "Live · Updated daily",
    "示例数据 · 待刷新": "Sample data · Awaiting refresh",
    "平均评分": "Average rating",
    "数据来源": "Data source",
    "高分 Top 250": "Top Rated 250",
    "最新上映": "New Releases",
    "公版经典": "Public-Domain Classics",
    "中国大陆": "Mainland China",
    "香港": "Hong Kong",
    "台湾": "Taiwan",
    "美国": "United States",
    "新加坡": "Singapore",
    "英国": "United Kingdom",
    "日本": "Japan"
  };

  var AI_CHAT = {
    /* 首屏欢迎语与提示条整段入过典，但 DOM 里被 <b> 拆成短节点，整段永远匹配不到。
       模型代号沿用 wave5 已定的译名：大聪明 = Cloud AI、离线小智 = Offline Mini AI。 */
    "（云端）走海外线路，网络环境受限时可能连不上，可换用 WiFi/电脑，或直接改用下方国内模型；":
      " (cloud) routes overseas and may not connect on a restricted network — try Wi-Fi or a computer, or switch to one of the mainland models below;",
    "（本机模型）需": " (on-device) needs ",
    "电脑版 Chrome / Edge": "desktop Chrome or Edge",
    "，手机用不了，下载模型请在 ⚙️ 设置把「下载源」切成镜像；\n    断网可用":
      ", does not work on phones, and to download the model open ⚙️ Settings and switch the download source to the mirror;\n    it works offline",
    "。有 API 密钥可在设置选「自定义接口」填智谱 / DeepSeek 等国内模型，":
      ". With an API key you can pick “Custom endpoint” in Settings and plug in Zhipu, DeepSeek or another mainland model for a ",
    "连接更稳定": "more stable connection",
    "你好呀，我是万象智聊 ✨": "Hi, I'm Ooglex AI Chat ✨",
    "默认用": "By default it runs ",
    "大聪明": "Cloud AI",
    "小机灵": "Local AI",
    "（云端模型），打开就能聊。": " (a cloud model) — just open it and start talking.",
    "⚠️ 提示：大聪明走海外线路，": "⚠️ Note: Cloud AI routes overseas, so it ",
    "网络环境受限时可能连不上": "may not connect on a restricted network",
    "，可换用 WiFi / 电脑，或直接改用下方国内模型；断网可用":
      ". Try Wi-Fi or a computer, or switch to one of the mainland models below; offline, use ",
    "离线小智": "Offline Mini AI",
    "；有 API 密钥可在 ⚙️ 设置选「自定义接口」填智谱 / DeepSeek，":
      ". With an API key, open ⚙️ Settings, choose “Custom endpoint” and plug in Zhipu or DeepSeek,",
    "有什么想聊的，直接说 😄": "Whatever you want to talk about, just say it 😄",
    "⧉ 复制": "⧉ Copy",
    "新对话": "New chat",
    "默认「大聪明」云端模型，": "Runs the “Cloud AI” model by default — ",
    "打开就能聊，不用填任何东西": "open it and start talking, nothing to fill in",
    "。想更私密可换「小机灵」（模型跑在你电脑上）。":
      ". For more privacy, switch to “Local AI”, which runs the model on your own computer.",
    "知道了": "Got it",
    "删除对话": "Delete chat",
    "✨ 万象智聊": "✨ Ooglex AI Chat",
    "💬 对话": "💬 Chats",
    "⚙️ 设置": "⚙️ Settings",
    "📢 使用提示": "📢 Usage tips",
    "知道了 ✕": "Got it ✕",
    "输入你的问题…（Enter 发送，Shift+Enter 换行）": "Ask anything… (Enter to send, Shift+Enter for a new line)",
    "发送": "Send",
    "＋ 新对话": "+ New chat",
    "⚙️ 选择 AI": "⚙️ Choose AI",
    "选择 AI": "Choose AI",
    "接口地址（Base URL）": "Endpoint (Base URL)",
    "模型名称": "Model name",
    "模型下载源（国内网络请选镜像）": "Model download source",
    "官方 HuggingFace（需海外网络）": "Official Hugging Face",
    "国内镜像 hf-mirror.com": "Mirror · hf-mirror.com",
    "API 密钥（仅保存在你自己的浏览器里）": "API key (stored only in your browser)",
    "AI 人设（系统提示词，可自由修改）": "AI persona (system prompt; editable)",
    "取消": "Cancel",
    "保存并开聊": "Save & Start Chatting",
    "复制": "Copy",
    "重新生成": "Regenerate",
    "删除": "Delete",
    "停止": "Stop",
    "连接中…": "Connecting…",
    "思考中…": "Thinking…",
    "生成中…": "Generating…",
    "已连接": "Connected",
    "离线": "Offline"
  };

  var CALC = {
    "万 象 算 集": "OOGLEX CALCULATORS",
    "生活之数 · 尽在掌中": "Everyday numbers · One practical toolkit",
    "🔍 搜索计算器……（如 房贷、BMI、圆、汇率、进制）": "🔍 Search calculators… (mortgage, BMI, circle, FX, number base…)",
    "万象算集 · 计算器大全 · 结果仅供参考 · 托管于 GitHub Pages": "Ooglex Calculators · Results for reference only · Hosted on GitHub Pages",
    "金融理财": "Finance",
    "健康身体": "Health",
    "数学几何": "Math & Geometry",
    "单位换算": "Unit Conversion",
    "物理": "Physics",
    "化学": "Chemistry",
    "日常生活": "Everyday Life",
    "实用工具": "Utilities",
    "计 算": "CALCULATE",
    "没有匹配的计算器，换个关键词试试～": "No matching calculator. Try another keyword.",
    "← 算集首页": "← Calculator Home",
    "← 返回列表": "← Back to List",
    "请检查输入是否完整、有效": "Please check that all inputs are complete and valid",
    "房贷计算器": "Mortgage Calculator",
    "通用贷款计算器": "Loan Calculator",
    "复利计算器": "Compound Interest Calculator",
    "单利计算器": "Simple Interest Calculator",
    "BMI 计算器": "BMI Calculator",
    "体脂率计算器": "Body Fat Calculator",
    "基础代谢率 BMR": "Basal Metabolic Rate (BMR)",
    "科学计算器": "Scientific Calculator",
    "百分比计算器": "Percentage Calculator",
    "汇率换算": "FX Converter",
    "日期计算器": "Date Calculator"
  };

  var RADIO = {
    /* 安装引导与提示条整段都写过，但 DOM 里被 <b> 拆成了一串短节点，
       整段那几条永远匹配不到。下面按拆开后的节点各配一条。 */
    "在浏览器打开": "Open in browser",
    "🤖 安卓（Chrome / Edge / 三星等浏览器）": "🤖 Android (Chrome / Edge / Samsung Internet)",
    "点浏览器右上角菜单": "Open the browser menu at the top right",
    "选择": "choose ",
    "「安装应用」": "“Install app”",
    "或": " or ",
    "「添加到主屏幕」": "“Add to Home screen”",
    "🍎 iPhone / iPad（用 Safari 打开）": "🍎 iPhone / iPad (open in Safari)",
    "点底部的": "Tap the ",
    "分享按钮 ⬆️": "Share button ⬆️",
    "向下滑动，选择": "Scroll down and choose ",
    "点右上角": "Tap ",
    "「添加」": "“Add”",
    "，主屏即出现 App 图标": " at the top right and the app icon appears on your Home screen",
    "💬 微信 / QQ / 其它内置浏览器": "💬 WeChat / QQ / other in-app browsers",
    "内置浏览器": "In-app browsers ",
    "「在浏览器打开」": "“Open in browser”",
    "（或用系统 Safari / Chrome 打开本页）": " (or open this page in Safari or Chrome directly)",
    "再按上面对应系统的步骤安装": "then follow the steps for your platform above",
    "拖动地球": "Drag the globe",
    "中间的圆圈": "the circle in the middle",
    "🔍 顶部": "🔍 The search box at the top takes a ",
    "🎲 随机一台 · 🏠 回到中国上空 · ↻ 自转": "🎲 Random station · 🏠 Back over China · ↻ Auto-rotate",
    "收藏 / 取消收藏": "Add to or remove from favourites",
    "确认后，桌面会出现「环球电波」图标": "Once confirmed, a “Global Radio” icon appears on your home screen",
    "或 ⬇️ 直接下载 APK 安装（无需商店）": "or ⬇️ download the APK directly (no app store needed)",
    "无法直接安装": "cannot install it directly — use ",
    "转动地球，绿点是一座座正在广播的电台。点亮任意一个，就能实时收听当地的声音。":
      "Spin the globe: each green dot is a station on air. Light one up and you hear that place live.",
    "，把想听的地方转进": ", bring the place you want into ",
    "，松手即自动收听": ", and let go to start listening",
    "🟢 也可直接": "🟢 Or just ",
    "点击任意绿点": "click any green dot",
    "收听该台": " to listen to that station",
    "城市 / 国家 / 电台名": "city, country or station name",
    "说明：仅收录 HTTPS 直连电台，国内及多数亚洲电台可直接收听。":
      "Note: only stations reachable over direct HTTPS are listed, so mainland-China and most Asian stations play directly.",
    "连不上的台会自动跳到附近可用电台": "A station that will not connect is skipped for a working one nearby",
    "；部分欧美电台服务器在墙外，国内需代理才行，属正常现象。":
      "; some European and American servers sit outside the mainland-China network and need a proxy there, which is expected.",
    "环球电波": "Global Radio",
    "RADIO · 转动地球听世界": "RADIO · Spin the globe, hear the world",
    "拖动地球，把电台转进圈内即可收听": "Drag the globe and move a station into the reticle to listen",
    "搜索电台 / 城市 / 国家（如 北京、jazz、BBC）": "Search station / city / country (e.g. Beijing, jazz, BBC)",
    "展开或收起面板": "Expand or collapse panel",
    "▾ 收起": "▾ Collapse",
    "选一座城市开始收听": "Choose a city to start listening",
    "拖动地球把电台转进圆圈，或点下方列表": "Move a station into the reticle, or select one from the list below",
    "收藏当前电台": "Favorite current station",
    "上一台（也可用方向盘 / 蓝牙上一曲键）": "Previous station",
    "下一台（也可用方向盘 / 蓝牙下一曲键）": "Next station",
    "上一台": "Previous station",
    "下一台": "Next station",
    "▶ 播放": "▶ Play",
    "⏸ 暂停": "⏸ Pause",
    "音量": "Volume",
    "本区": "Nearby",
    "⭐ 收藏": "⭐ Favorites",
    "全屏沉浸模式：隐藏浏览器地址栏": "Immersive fullscreen",
    "安装到手机": "Install on phone",
    "随机一台": "Random station",
    "回到中国上空": "Return over China",
    "开始/停止自转": "Start/stop rotation",
    "📲 安装到手机": "📲 Install on Your Phone",
    "把「环球电波」装到主屏，像 App 一样全屏打开、离线也能启动，无需应用商店。": "Add Global Radio to your home screen. It opens fullscreen like an app and can launch offline, with no app store required.",
    "⬇️ 立即安装到本机": "⬇️ Install Now",
    "🌍 环球电波": "🌍 Global Radio",
    "国内直连优先 · 无需登录": "Direct connections prioritized · No sign-in required",
    "进入 · 开始收听": "Enter · Start Listening",
    "📲 安装到手机 · 查看安装方法": "📲 Install on phone · View instructions",
    "正在连接…": "Connecting…",
    "正在播放": "Playing",
    "播放中": "Playing",
    "连接失败": "Connection failed",
    "暂无收藏": "No favorites yet",
    "附近电台": "Nearby stations",
    "搜索结果": "Search results"
  };

  var TV = {
    /* 安装引导与提示条整段都写过，但 DOM 里被 <b> 拆成了一串短节点，
       整段那几条永远匹配不到。下面按拆开后的节点各配一条。 */
    "在浏览器打开": "Open in browser",
    "🤖 安卓（Chrome / Edge / 三星等浏览器）": "🤖 Android (Chrome / Edge / Samsung Internet)",
    "点浏览器右上角菜单": "Open the browser menu at the top right",
    "选择": "choose ",
    "「安装应用」": "“Install app”",
    "或": " or ",
    "「添加到主屏幕」": "“Add to Home screen”",
    "🍎 iPhone / iPad（用 Safari 打开）": "🍎 iPhone / iPad (open in Safari)",
    "点底部的": "Tap the ",
    "分享按钮 ⬆️": "Share button ⬆️",
    "向下滑动，选择": "Scroll down and choose ",
    "点右上角": "Tap ",
    "「添加」": "“Add”",
    "，主屏即出现 App 图标": " at the top right and the app icon appears on your Home screen",
    "💬 微信 / QQ / 其它内置浏览器": "💬 WeChat / QQ / other in-app browsers",
    "内置浏览器": "In-app browsers ",
    "「在浏览器打开」": "“Open in browser”",
    "（或用系统 Safari / Chrome 打开本页）": " (or open this page in Safari or Chrome directly)",
    "再按上面对应系统的步骤安装": "then follow the steps for your platform above",
    "拖动地球": "Drag the globe",
    "中间的圆圈": "the circle in the middle",
    "🔍 顶部": "🔍 The search box at the top takes a ",
    "🎲 随机一台 · 🏠 回到中国上空 · ↻ 自转": "🎲 Random station · 🏠 Back over China · ↻ Auto-rotate",
    "收藏 / 取消收藏": "Add to or remove from favourites",
    "确认后，桌面会出现「环球TV」图标": "Once confirmed, a “Global TV” icon appears on your home screen",
    "把「环球TV」装到主屏，像 App 一样全屏打开，无需应用商店。":
      "Install Global TV to your home screen and it opens full-screen like a native app — no app store required.",
    "可能无法播放视频": "may not be able to play video — use ",
    "📺 环球TV": "📺 Global TV",
    "华语频道直连优先 · 无需登录": "Chinese-language channels prioritised for direct connection · No sign-in",
    "转动地球，蓝点是一座座正在直播的电视台。点亮任意一个，就能实时观看当地的画面。":
      "Spin the globe: each blue dot is a channel broadcasting live. Light one up and you watch that place in real time.",
    "，把想看的地方转进": ", bring the place you want into ",
    "，松手即自动观看": ", and let go to start watching",
    "🔵 也可直接": "🔵 Or just ",
    "点击任意蓝点": "click any blue dot",
    "观看该台": " to watch that channel",
    "城市 / 国家 / 频道名": "city, country or channel name",
    "说明：仅收录 HTTPS 直连的公开直播源，华语区及多数亚洲频道可直接观看。":
      "Note: only public live streams reachable over direct HTTPS are listed, so Chinese-language and most Asian channels play directly.",
    "连不上的台会自动跳到附近可用频道": "A channel that will not connect is skipped for a working one nearby",
    "；部分欧美频道服务器在墙外，国内需代理才行，属正常现象。":
      "; some European and American servers sit outside the mainland-China network and need a proxy there, which is expected.",
    "进入 · 开始观看": "Enter · Start watching",
    "📲 安装到手机 · 查看安装方法": "📲 Install on your phone · See how",
    "▾ 收起": "▾ Collapse",
    "展开或收起面板": "Expand or collapse the panel",
    "上一台": "Previous channel",
    "下一台": "Next channel",
    "音量": "Volume",
    "全屏沉浸模式：隐藏浏览器地址栏": "Immersive fullscreen: hides the browser address bar",
    "安装到手机": "Install on your phone",
    "回到中国上空": "Back over China",
    "开始/停止自转": "Start or stop auto-rotation",
    "无权访问": "Access Restricted",
    "因相关法律法规等原因，您暂无权访问本页面。": "Access to this page is restricted for legal or regulatory reasons.",
    "如已获授权，请输入访问密码后进入。": "If you are authorized, enter the access password to continue.",
    "请输入访问密码": "Enter access password",
    "进　入": "ENTER",
    "密码错误，请重试": "Incorrect password. Please try again.",
    "环球TV": "Global TV",
    "GLOBAL TV · 转动地球看世界": "GLOBAL TV · Spin the globe, watch the world",
    "拖动地球，把电视台转进圈内即可观看": "Drag the globe and move a TV station into the reticle to watch",
    "搜索频道 / 城市 / 国家（如 CGTN、NHK、凤凰）": "Search channel / city / country (e.g. CGTN, NHK)",
    "选一座城市开始观看": "Choose a city to start watching",
    "拖动地球把电视台转进圆圈，或点下方列表": "Move a TV station into the reticle, or select one from the list below",
    "收藏当前频道": "Favorite current channel",
    "静音": "Mute",
    "全屏观看": "Fullscreen video",
    "随机一台": "Random channel",
    "📲 安装到手机": "📲 Install on Your Phone",
    "正在连接…": "Connecting…",
    "正在播放": "Playing",
    "播放中": "Playing",
    "连接失败": "Connection failed",
    "暂无收藏": "No favorites yet",
    "本区": "Nearby",
    "⭐ 收藏": "⭐ Favorites",
    "▶ 播放": "▶ Play",
    "⏸ 暂停": "⏸ Pause"
  };

  var GLOBE = {
    "全球态势地球": "Global Situational Globe",
    "切换界面语言（应用内文案）": "Switch interface language",
    "数据来源": "Data Sources",
    "准备加载基础地球": "Ready to load Basic Earth",
    "全球视角": "Global View",
    "切换高清影像": "Switch to HD Imagery",
    "返回基础地球": "Back to Basic Earth",
    "三维地球 · 公开地理数据叠加": "3D Globe · Public Geospatial Data",
    "进入地球": "Enter Globe",
    "首次加载需下载三维引擎和基础底图，需要支持 WebGL 的浏览器 · 个人学习用途，非商业使用": "The first load downloads the 3D engine and base map. A WebGL-capable browser is required · Personal learning use · Non-commercial",
    "数据来源与许可": "Data Sources & Licenses",
    "本站可用": "Available on This Site",
    "本站不可用（需服务端代理）": "Unavailable Here (Server Proxy Required)",
    "默认": "Default",
    "可选": "Optional",
    "可用": "Available",
    "非商业": "Non-commercial",
    "不可用": "Unavailable",
    "Natural Earth 基础地球": "Natural Earth Basic Globe",
    "USGS 全球地震目录": "USGS Global Earthquake Catalog",
    "数据中心（约 4300 处）· 大坝（704 座）": "Data centers (~4,300) · Dams (704)",
    "Natural Earth 命名地理区域": "Natural Earth Named Geographic Regions",
    "CelesTrak 卫星星历（约 840 颗，六个分组）": "CelesTrak satellite ephemerides (~840 satellites, six groups)",
    "航天任务（近 30 天发射记录）": "Space missions (launches in the past 30 days)",
    "实时航班 · 船舶（AIS）· 活跃火点": "Live flights · Ships (AIS) · Active fires",
    "交通流 · 公共自行车 · 交通摄像头 · 网络电台 · 区域新闻": "Traffic · Public bikes · Traffic cameras · Internet radio · Regional news",
    "Google 真实感三维瓦片 · 地点搜索 · 语音控制": "Google photorealistic 3D tiles · Place search · Voice control",
    "正在加载三维引擎和基础底图，首次访问可能需要稍候。": "Loading the 3D engine and basic globe. The first visit may take a moment.",
    "正在加载基础地球…": "Loading Basic Earth…",
    "当前浏览器无法运行三维地球": "This browser cannot run the 3D globe",
    "未能创建 WebGL 画布。请使用支持 WebGL 的浏览器，并确认已开启硬件加速。": "A WebGL canvas could not be created. Use a WebGL-capable browser and make sure hardware acceleration is enabled.",
    "地球加载超时": "Globe load timed out",
    "站内资源未能完成加载，请检查网络后重试。": "Site resources did not finish loading. Check your network and try again.",
    "地球未能完成加载": "Globe failed to load",
    "正在连接影像服务…": "Connecting to imagery service…",
    "影像不可用 · 已返回基础地球": "Imagery unavailable · Returned to Basic Earth",
    "基础地球 · 低分辨率底图": "Basic Earth · Low-resolution base map",
    "OpenStreetMap 底图": "OpenStreetMap base map",
    "Esri 高清影像": "Esri HD imagery",
    "三维地球 · 公开地理数据叠加": "3D Globe · Public Geospatial Data Overlays",
    "在浏览器里转动一颗真实卫星影像的地球，叠加公开地理数据：全球地震、\n        4300 处数据中心、704 座大坝、海底电缆与命名地理区域。\n        全部数据源与许可在「数据来源」里逐条列出。": "Spin a satellite-imagery globe in your browser with public geospatial data layered on top: global earthquakes,\n        about 4,300 data centres, 704 dams, submarine cables and named geographic regions.\n        Every source and its licence is listed item by item under “Data Sources”.",
    "这是一个纯静态部署，": "This is a purely static deployment with ",
    "没有服务端": "no server side",
    "。卫星与航天任务通过每日定时生成的\n        同源静态快照供数据（星点位置由前端实时推算）；而实时航班、船舶、交通摄像头、\n        电台等图层依赖后端代理，在本站不可用，打开后会显示为不可用状态，\n        这是预期行为而非故障。具体哪些可用见「数据来源」。": ". Satellites and space missions are fed by same-origin static snapshots rebuilt daily\n        (the points themselves are propagated live in the browser); layers such as live flights, ships,\n        traffic cameras and radio need a backend proxy and are therefore unavailable here — they open\n        in an unavailable state, which is expected behaviour, not a fault. See “Data Sources” for what works.",
    "应用界面已做中文化（顶栏「中 / EN」可切回英文原版）。": "The embedded app ships a Chinese localisation layer; the 中 / EN button in the top bar switches it back to the English original.",
    "数据来源署名按许可要求保留原文": "Source attributions stay in their original wording as the licences require",
    "，地图上的坐标、呼号、机型等读数同样不翻译。": ", and readouts on the map such as coordinates, call signs and aircraft types are left untranslated too.",
    "首屏约需下载 2.2 MB（三维引擎），需要支持 WebGL 的浏览器 · 个人学习用途，非商业使用": "The first screen downloads about 2.2 MB (the 3D engine) and needs a WebGL-capable browser · Personal learning use, non-commercial",
    "界面程序来自开源项目": "The interface code comes from the open-source project ",
    "（MIT 许可，仅覆盖代码）。\n    下列数据各自独立授权，与该许可无关。本站按个人学习用途部署，不作商业使用。": " (MIT licence, which covers the code only).\n    The datasets below are licensed independently of it. This site is deployed for personal learning use, not commercially.",
    "随应用一起分发的三维模型": "3D Models Shipped With the App",
    "署名": "Attribution",
    "Natural Earth II 基础底图（默认）": "Natural Earth II base map (default)",
    "随 Cesium 一同发布的本地瓦片，": "Local tiles shipped with Cesium — ",
    "不请求外网": "no outbound requests",
    "，因此不开 VPN 也能直接显示 ·\n    公有领域 · Made with Natural Earth · 层级上限 2，": " — so it renders without a VPN ·\n    Public domain · Made with Natural Earth · Zoom capped at level 2, so it ",
    "放大后会发糊": "blurs when zoomed in",
    "，\n    这是数据分辨率所限，需要细节请在应用内底图菜单切到高清影像": ".\n    That is the resolution of the data; for detail, switch to HD imagery in the app’s base-map menu",
    "Esri World Imagery 高清影像": "Esri World Imagery (HD)",
    "在应用内底图菜单切换 · Powered by Esri — Source: Esri, Maxar, Earthstar Geographics 及 GIS 用户社区 ·\n    该服务在中国大陆不一定可达，取不到时自动退回基础底图": "Switch to it in the app’s base-map menu · Powered by Esri — Source: Esri, Maxar, Earthstar Geographics and the GIS User Community ·\n    The service is not always reachable from mainland China; when it fails the globe falls back to the basic base map",
    "OpenStreetMap 底图": "OpenStreetMap base map",
    "同样在底图菜单切换 · ODbL 1.0 · © OpenStreetMap contributors": "Also switchable in the base-map menu · ODbL 1.0 · © OpenStreetMap contributors",
    "近 24 小时地震摘要 · 美国地质调查局，公有领域 · 由浏览器直接请求，刷新频率取决于该源": "Past-24-hour earthquake summary · U.S. Geological Survey, public domain · Requested directly by the browser; refresh rate follows the source",
    "ODbL 1.0 · © OpenStreetMap contributors，另据 Open Infrastructure Map · 署名与相同方式共享": "ODbL 1.0 · © OpenStreetMap contributors, also via Open Infrastructure Map · Attribution and share-alike required",
    "1046 处陆地 + 292 处海域名称 · 公有领域 · Made with Natural Earth": "1,046 land features + 292 marine names · Public domain · Made with Natural Earth",
    "美国政府来源数据，无许可限制，请求署名 · CelesTrak (celestrak.org), Dr. T.S. Kelso ·\n    每日抓取 TLE 存为同源静态快照；": "U.S. government source data, no licence restrictions, attribution requested · CelesTrak (celestrak.org), Dr. T.S. Kelso ·\n    TLEs are fetched daily into a same-origin static snapshot; ",
    "轨道位置由前端按 SGP4 实时推算": "orbital positions are propagated live in the browser with SGP4",
    "，所以星点是实时移动的": ", so the points really do move in real time",
    "Launch Library 2 — The Space Devs · 数据可任意形式使用与分享 · 每日刷新\n    · 提供发射事件与时间，不含连续上升段遥测或实时在轨状态": "Launch Library 2 — The Space Devs · Free to use and share in any form · Refreshed daily\n    · Provides launch events and times, not continuous ascent telemetry or live on-orbit status",
    "TeleGeography 海底电缆（712 条 + 1917 个登陆点）": "TeleGeography submarine cables (712 cables + 1,917 landing points)",
    "CC BY-NC-SA 3.0 · © TeleGeography — submarinecablemap.com · 仅限非商业用途；本站若转作商业用途必须移除该数据集": "CC BY-NC-SA 3.0 · © TeleGeography — submarinecablemap.com · Non-commercial use only; this dataset must be removed if the site ever turns commercial",
    "航班与船舶是秒级实时位置，无法用定时静态快照替代；船舶还需常驻 WebSocket 与私有密钥，\n    火点需要 NASA FIRMS 密钥。三者都需要一个与应用同源的后端": "Flights and ships are second-by-second live positions that a scheduled static snapshot cannot stand in for; ships also need a persistent WebSocket and a private key,\n    and fire hotspots need a NASA FIRMS key. All three require a backend on the same origin as the app",
    "同上；其中部分上游还要求密钥，而密钥不会写入前端": "Same as above; some of these upstreams also require keys, and keys are never written into the front end",
    "需要按量计费的第三方密钥，本站未配置": "Requires a metered third-party key, which this site does not configure",
    "飞机 / 直升机 / 无人机 / 货轮 三维模型": "Aircraft / helicopter / drone / cargo-ship 3D models",
    "位于": "Located under ",
    "，非本仓库 MIT 源码的一部分，各自采用": ", not part of this repository’s MIT-licensed source; each carries its own licence. ",
    "均已修改": "All have been modified",
    "：上游 God's Eye View 做过几何与材质精简、贴图缩小到 256px WebP，\n    并把朝向与比例烘焙进网格（glTF +Y 朝上、机头朝 −X、包围盒中心归零）。": ": upstream God's Eye View simplified the geometry and materials and shrank textures to 256px WebP,\n    then baked orientation and scale into the mesh (glTF +Y up, nose toward −X, bounding box centred on zero).",
    "署名按 CC BY 4.0 保留，不代表原作者对本站的认可。": "Attribution is retained under CC BY 4.0 and does not imply the original authors endorse this site.",
    "当前为中文界面，点击切回英文原版": "App is in Chinese · Click to switch back to the English original",
    "当前为英文原版，点击切回中文": "App is in the English original · Click to switch back to Chinese",
    "全球态势地球（三维）": "Global Situational Globe (3D)",
    "未能创建 WebGL 画布。请改用较新版本的 Chrome、Edge、Firefox 或 Safari，并确认未关闭硬件加速；部分浏览器的省电模式也会禁用 WebGL。": "A WebGL canvas could not be created. Use a recent version of Chrome, Edge, Firefox or Safari and make sure hardware acceleration is on; some browsers also disable WebGL in battery-saver mode.",
    "检测到省流量模式或较慢网络。首屏约需下载 2.2 MB（三维引擎），确认后再加载 · 个人学习用途，非商业使用": "Data-saver mode or a slow network was detected. The first screen downloads about 2.2 MB (the 3D engine) — confirm before loading · Personal learning use, non-commercial",
    "更新时间：读取中…": "Updated: loading…",
    "更新时间：静态数据快照尚未生成（定时任务首次运行后写入），此前这两个图层没有数据": "Updated: the static snapshot has not been generated yet (written after the scheduled job first runs); until then these two layers have no data",
    "更新时间：读取失败（status.json 不可用，数据快照可能尚未生成）": "Updated: read failed (status.json unavailable; the snapshot may not exist yet)",
  };

  var FORTUNE = {
    "🎵 奏乐": "🎵 Music",
    "知 命 阁": "NAME & FORTUNE",
    "一名一世界 · 一字一乾坤": "A traditional name-and-fortune reading · For entertainment only",
    "📜 报上名来": "📜 Enter Your Name",
    "中文姓名（必填）": "Chinese name (required)",
    "例如：张三丰": "e.g. 张三丰",
    "出生日期（选填，填写后可排生辰八字）": "Birth date (optional; enables BaZi calculation)",
    "出生时辰（选填）": "Birth hour (optional)",
    "不清楚": "Unknown",
    "子时 23:00–01:00": "Zi (Rat) 23:00–01:00",
    "丑时 01:00–03:00": "Chou (Ox) 01:00–03:00",
    "寅时 03:00–05:00": "Yin (Tiger) 03:00–05:00",
    "卯时 05:00–07:00": "Mao (Rabbit) 05:00–07:00",
    "辰时 07:00–09:00": "Chen (Dragon) 07:00–09:00",
    "巳时 09:00–11:00": "Si (Snake) 09:00–11:00",
    "午时 11:00–13:00": "Wu (Horse) 11:00–13:00",
    "未时 13:00–15:00": "Wei (Goat) 13:00–15:00",
    "申时 15:00–17:00": "Shen (Monkey) 15:00–17:00",
    "酉时 17:00–19:00": "You (Rooster) 17:00–19:00",
    "戌时 19:00–21:00": "Xu (Dog) 19:00–21:00",
    "亥时 21:00–23:00": "Hai (Pig) 21:00–23:00",
    "开 始 测 算": "START READING",
    "推演天干地支…": "Calculating the Heavenly Stems and Earthly Branches…",
    "✦ 本页面内容由程序生成，仅供娱乐，不构成任何现实建议 ✦": "✦ Program-generated content for entertainment only; not real-world advice ✦",
    "知命阁 · 托管于 GitHub Pages": "Name & Fortune · Hosted on GitHub Pages",
    "年柱": "Year Pillar",
    "月柱": "Month Pillar",
    "日柱": "Day Pillar",
    "时柱": "Hour Pillar",
    "五行": "Five Elements",
    "财运": "Wealth",
    "事业": "Career",
    "爱情": "Relationships",
    "健康": "Health",
    "幸运色": "Lucky color",
    "幸运数字": "Lucky number"
  };

  var GAMES = {
    "🎮 游戏中心": "🎮 Game Center",
    "网页小游戏 · 电脑手机都能玩 · 点击开玩": "Browser games · Play on desktop or mobile · Click to start",
    "GTA Vice City · 网页版": "GTA Vice City · Browser Edition",
    "浏览器直接畅玩罪恶都市：无需下载安装，支持全屏与强制横屏模式，内置作弊菜单（游戏内按 F3 开启）。首次加载需耐心等待。": "Play Vice City directly in your browser—no installation required. Supports fullscreen and forced landscape mode, with an in-game cheat menu via F3. The first load may take a while.",
    "红色警戒 2 · 网页版": "Red Alert 2 · Browser Edition",
    "经典 RTS 浏览器在线玩：单人战役、遭遇战、多人联机、天梯排位，内置共和国之辉 MOD。无需下载安装，电脑体验最佳，手机建议横屏。": "Classic RTS in the browser: campaigns, skirmishes, multiplayer and ranked play, with the Republic's Glory mod. No installation required; desktop is recommended and landscape works best on mobile.",
    "🎮 开始游戏 →": "🎮 Play →",
    "网页小游戏 · 纯前端，无需安装": "Browser games · Frontend only · No installation required",
    "正在加载 GTA Vice City": "Loading GTA Vice City",
    "首次加载可能需要几分钟，请耐心等待": "The first load may take a few minutes",
    "⬌ 强制横屏模式": "⬌ Forced landscape mode",
    "返回游戏中心": "Back to Game Center",
    "设置": "Settings",
    "全屏": "Fullscreen",
    "游戏设置": "Game Settings",
    "🔄 强制横屏": "🔄 Force Landscape",
    "将整个网页旋转为横屏并填满画面": "Rotate the page into landscape and fill the screen",
    "💡 显示操作提示": "💡 Show Tips",
    "游戏内按 F3 显示/隐藏作弊菜单": "Press F3 in-game to show/hide the cheat menu",
    "🧹 清除缓存": "🧹 Clear Cache",
    "清除游戏缓存并重新加载": "Clear game cache and reload",
    "执行": "Run",
    "💡 提示：按 F3 显示/隐藏作弊菜单": "💡 Tip: press F3 to show/hide the cheat menu",
    /* 下面几条是「整串已入典、但 DOM 里被 <kbd>/<span>/<b> 拆开」的补丁：
       整串那条永远匹配不到，必须按拆开后的节点各配一条。 */
    "💡 提示：按": "💡 Tip: press",
    "显示/隐藏作弊菜单": "to show/hide the cheat menu",
    "⚙️ 设置": "⚙️ Settings",
    "黑底页面、不用害怕——直接点中间的红色按钮": "A black page is nothing to worry about — just click the red button in the middle,",
    "点此自动导入": "Click here to auto-import",
    "，游戏素材会自动下载导入，别的什么都不用填。": ", and the game assets download and import themselves. Nothing else to fill in.",
    "资源包几百 MB，建议连 Wi-Fi。只有第一次需要，之后素材缓存在浏览器里，打开秒进。":
      "The asset pack is a few hundred MB, so Wi-Fi is recommended. Only the first run needs it — after that the assets are cached in the browser and it opens instantly.",
    "单人战役 / 遭遇战 / 多人联机随便选。手机请": "Campaign, skirmish or multiplayer — take your pick. On a phone, switch to ",
    "横屏": "landscape",
    "并点右上角 ⛶ 全屏，电脑体验最佳。": " and tap ⛶ at the top right for fullscreen. Desktop gives the best experience.",
    "我知道了，开始加载 →": "Got it — start loading →",
    "跳过引导": "Skip the guide",
    "🎖️ 首次进入请在导入页点「点此自动导入」· 支持战役/联机/共辉 MOD":
      "🎖️ On first entry, click “Click here to auto-import” on the import page · Campaign, multiplayer and the Republic's Glory mod are supported",
    "🔄 刷新": "🔄 Refresh",
    "💡 提示": "💡 Tips",
    "正在加载 红色警戒 2 网页版": "Loading Red Alert 2 Browser Edition",
    "首次加载需下载游戏资源，可能需要 1–3 分钟": "The first load downloads game assets and may take 1–3 minutes",
    "电脑体验最佳 · 手机建议横屏": "Best on desktop · Landscape recommended on mobile",
    "加载较慢或没有反应？": "Loading slowly or not responding?",
    "新窗口直接打开 ↗": "Open directly in a new window ↗",
    "切换游戏源": "Switch Game Source",
    "新窗口打开": "Open in New Window",
    "🔁 切换游戏源": "🔁 Switch Game Source",
    "不同源加载速度可能不同，哪个快用哪个": "Load speed varies by source. Use whichever is faster.",
    "🚩 第一次玩？30 秒看懂": "🚩 First time? Learn it in 30 seconds",
    "红警 2 网页版 · 免下载安装 · 以后打开直接进游戏": "Red Alert 2 in the browser · No install · Future visits open directly into the game",
    "游戏会先弹出「资源导入」页": "The game first opens a resource-import page",
    "等进度条走完（约 1–3 分钟）": "Wait for the progress bar (about 1–3 minutes)",
    "进入主菜单，开打！": "Enter the main menu and play!"
  };

  var PRIVACY = {
    "隐私政策": "Privacy Policy",
    "适用于 Ooglex（ooglex.com） · 最近更新：2026-09-18": "Applies to Ooglex (ooglex.com) · Last updated: 2026-09-18",
    "感谢你使用 Ooglex（以下简称\"本站\"）。本政策说明本站如何处理与你相关的信息，以及第三方广告与 Cookie 的使用情况。使用本站即表示你已阅读并理解本政策。": "Thank you for using Ooglex (the “Site”). This policy explains how the Site handles information related to you, including third-party advertising and cookies. By using the Site, you acknowledge that you have read and understood this policy.",
    "1. 本站的性质": "1. Nature of the Site",
    "本站是一个托管于 GitHub Pages 的静态网站，聚合实时金融数据、实用工具与网页小游戏。本站不设注册或账户系统，通常不会主动向你索取姓名、电话等个人身份信息。": "The Site is a static website hosted on GitHub Pages that aggregates financial data, utilities and browser games. The Site generally does not proactively request personal identity information such as your name or phone number.",
    "2. 我们收集与使用的信息": "2. Information We Collect and Use",
    "本地保存的数据：": "Locally stored data:",
    "访问日志与分析：": "Access logs and analytics:",
    "第三方数据展示：": "Third-party data display:",
    "X 第三方嵌入：": "X third-party embeds:",
    "科技领袖头像：": "Tech-leader avatars:",
    "「科技领袖实时动态流」使用 X 官方网页嵌入组件直接展示公开时间线。加载该组件时，X 可能接收你访问的网页、IP 地址、浏览器类型、操作系统及 Cookie 等信息；相关处理受 X 自身隐私政策与 X for Websites 规则约束。若当前网络无法连接 X，本页会降级为原主页跳转入口。": "Tech Leaders Live Feed uses X's official web embed to display public timelines directly. When the component loads, X may receive the page you visited, IP address, browser type, operating system and cookie information. That processing is governed by X's own privacy policy and X for Websites rules. If X is unreachable on the current network, the page falls back to a direct profile link.",
    "「科技领袖实时动态流」可能通过 Unavatar 获取公开 X 头像。加载头像时，该第三方服务可能接收必要的网络请求信息（如 IP 地址、浏览器请求头和所请求的公开账号标识）。头像服务不可用时，本站会回退为本地生成的姓名首字母头像。": "Tech Leaders Live Feed may fetch public X avatars through Unavatar. When an avatar loads, that third-party service may receive the network request information it needs (such as IP address, browser request headers and the requested public account identifier). If the avatar service is unavailable, the site falls back to locally generated initials avatars.",
    "3. 广告与 Cookie（Google AdSense）": "3. Advertising and Cookies (Google AdSense)",
    /* 整段那几条只在段里没有 <strong>/<a> 时成立；实际 DOM 是拆开的，按节点各配一条。 */
    "本站是一个托管于 GitHub Pages 的静态网站，聚合实时金融数据、实用工具与网页小游戏。本站":
      "The Site is a static website hosted on GitHub Pages that aggregates real-time financial data, utilities and browser games. It ",
    "不设注册或账户系统": "has no registration or account system",
    "，通常不会主动向你索取姓名、电话等个人身份信息。":
      " and generally does not proactively ask you for personal identity information such as your name or phone number.",
    "部分工具（如 AI 对话、计算器、设置项）会将你输入的内容或偏好（例如你自带的 API 密钥）":
      "Some tools (AI chat, calculators, preference settings) keep what you enter or prefer — your own API key, for example — ",
    "仅保存在你本地浏览器（localStorage）中": "only in your local browser storage (localStorage)",
    "，不会上传到本站服务器。清除浏览器数据即可删除。":
      ". Nothing is uploaded to the Site's servers, and clearing your browser data deletes it.",
    "本站可能使用 Google Analytics、Google Search Console 等工具，以汇总、匿名的方式了解访问量与使用情况，用于改进网站。":
      "The Site may use Google Analytics, Google Search Console and similar tools to understand traffic and usage in aggregate, anonymous form, in order to improve the site.",
    "本站展示来自 Yahoo Finance、Forbes、TMDB、CNN、Financial Modeling Prep、Forex Factory 等公开来源的数据，相关版权归原始来源所有，本站仅作聚合呈现。":
      "The Site displays data from public sources including Yahoo Finance, Forbes, TMDB, CNN, Financial Modeling Prep and Forex Factory. Copyright remains with the original sources; the Site only aggregates and presents it.",
    "本站使用": "The Site uses ",
    "等第三方广告服务来展示广告。": " and other third-party advertising services to display ads.",
    "第三方供应商（包括 Google）会使用": "Third-party vendors, including Google, use ",
    "，根据你过去对本站及其他网站的访问情况来投放广告。":
      " to serve ads based on your prior visits to this site and other sites.",
    "Google 使用广告 Cookie，使其及其合作伙伴能够基于你的访问情况向你投放广告。":
      "Google uses advertising cookies so that it and its partners can serve you ads based on your visits.",
    "你可以前往": "You can visit ",
    "Google 广告设置": "Google Ads Settings",
    "停用个性化广告；也可访问": " to turn off personalized advertising, or visit ",
    "停用部分第三方供应商的 Cookie。": " to opt out of some third-party vendors' cookies.",
    "更多关于 Google 如何使用数据的信息，请见": "For more on how Google uses data, see ",
    "Google 合作伙伴网站隐私说明": "How Google uses information from partner sites",
    "4. 你的选择": "4. Your Choices",
    "你可以通过浏览器设置管理或清除 Cookie 与本地存储，也可以使用上述链接停用个性化广告。停用后你仍会看到广告，但其相关性可能降低。": "You can manage or clear cookies and local storage through your browser settings, and you can use the links above to disable personalized advertising. You may still see ads afterward, but they may be less relevant.",
    "5. 儿童隐私": "5. Children's Privacy",
    "本站不面向 13 岁以下儿童，也不会有意收集其个人信息。": "The Site is not directed to children under 13 and does not knowingly collect their personal information.",
    "6. 政策更新": "6. Policy Updates",
    "本政策可能不时更新，更新后将在本页公布并更新顶部的\"最近更新\"日期。": "This policy may be updated from time to time. Changes will be posted on this page and the “Last updated” date above will be revised.",
    "7. 联系我们": "7. Contact Us",
    "如对本隐私政策有任何疑问，请联系：": "For questions about this privacy policy, contact:"
  };

  var dict = {};
  add(dict, COMMON);
  if (path.indexOf("/apps/heatmap/") === 0) add(dict, HEATMAP);
  if (path.indexOf("/apps/ofr-monitor/") === 0) add(dict, OFR);
  if (path.indexOf("/apps/finance-column/") === 0) add(dict, FINANCE);
  if (path.indexOf("/apps/movies/") === 0) add(dict, MOVIES);
  if (path.indexOf("/apps/ai-chat/") === 0) add(dict, AI_CHAT);
  if (path.indexOf("/apps/calculators/") === 0) add(dict, CALC);
  if (path.indexOf("/apps/radio/") === 0) add(dict, RADIO);
  if (path.indexOf("/apps/tv/") === 0) add(dict, TV);
  if (path.indexOf("/apps/globe/") === 0) add(dict, GLOBE);
  if (path.indexOf("/apps/name-fortune/") === 0) add(dict, FORTUNE);
  if (path.indexOf("/games/") === 0) add(dict, GAMES);
  if (path.indexOf("/privacy/") === 0) add(dict, PRIVACY);

  function regexTranslate(s) {
    var m;
    if ((m = /^更新于 (\d+) 分钟前$/.exec(s))) return "Updated " + m[1] + " min ago";
    if ((m = /^更新于 (\d+) 小时前$/.exec(s))) return "Updated " + m[1] + " hr ago";
    if ((m = /^更新于 (\d+) 天前$/.exec(s))) return "Updated " + m[1] + " d ago";
    if ((m = /^截至 (.+)$/.exec(s))) return "As of " + m[1];
    if ((m = /^(\d+) 个计算器 →$/.exec(s))) return m[1] + " calculators →";
    if ((m = /^共 (\d+) 个计算器 · 分为 (\d+) 大类，点分类进入或直接搜索$/.exec(s))) return m[1] + " calculators across " + m[2] + " categories · choose a category or search directly";
    // 上面那条只在整串没被标签拆开时成立；实际 DOM 里 <b> 把它切成「共」「70」「个计算器…」三段。
    if (s === "共") return "Total";
    if ((m = /^个计算器 · 分为 (\d+) 大类，点分类进入或直接搜索$/.exec(s))) return "calculators across " + m[1] + " categories · choose a category or search directly";
    if ((m = /^搜索“(.+)” 的结果$/.exec(s))) return "Results for “" + m[1] + "”";
    if ((m = /^(\d+)票$/.exec(s))) return m[1] + " votes";
    if ((m = /^命中 (\d+) 条，显示前 40 条$/.exec(s))) return m[1] + " matches · showing first 40";
    if ((m = /^命中 (\d+) 条$/.exec(s))) return m[1] + " matches";
    if ((m = /^未找到「(.+)」相关术语$/.exec(s))) return "No terms found for “" + m[1] + "”";
    if ((m = /^(\d+) 模块 · (\d+) 术语$/.exec(s))) return m[1] + " modules · " + m[2] + " terms";
    if ((m = /^(\d+) 模块$/.exec(s))) return m[1] + " modules";
    if ((m = /^(\d+) 术语$/.exec(s))) return m[1] + " terms";
    if ((m = /^(\d+) 项$/.exec(s))) return m[1] + " items";
    if ((m = /^第 (\d+) 页$/.exec(s))) return "Page " + m[1];
    // 态势地球的数据快照状态行是拼出来的（更新时间 + 刷新频率 + 状态），整串进不了字典；
    // 两端锚定只翻固定部分，时间戳原样保留。
    if ((m = /^更新时间：(.+?) · 每日刷新 · (.+)$/.exec(s))) {
      var note = { "正常": "OK", "无记录": "no records",
        "抓取失败，显示的是上一份有效数据": "fetch failed — showing the last valid data" }[m[2]];
      if (!note) {
        var part = /^部分失败（(\d+)\/(\d+)），其余为上一份有效数据$/.exec(m[2]);
        note = part ? "partial failure (" + part[1] + "/" + part[2] + "); the rest is the last valid data" : m[2];
      }
      return "Updated: " + m[1] + " · refreshed daily · " + note;
    }
    // 环球电波 / 环球TV 的运行时状态串：台名与国名原样带回，只翻固定部分。
    if ((m = /^松手收听：(.+)$/.exec(s))) return "Release to listen: " + m[1];
    if ((m = /^松手观看：(.+)$/.exec(s))) return "Release to watch: " + m[1];
    if ((m = /^(.+) · (\d+) 台$/.exec(s))) return m[1] + " · " + m[2] + (m[2] === "1" ? " station" : " stations");
    if ((m = /^已就绪 · (\d+) 个频道（含华语区 (\d+) 个）$/.exec(s))) {
      return "Ready · " + m[1] + " channels (" + m[2] + " Chinese-language)";
    }
    if ((m = /^已就绪 · (\d+) 个电台（含中国 (\d+) 个）$/.exec(s))) {
      return "Ready · " + m[1] + " stations (" + m[2] + " in China)";
    }
    if ((m = /^已就绪 · (\d+) 个电台（含华语区 (\d+) 个）$/.exec(s))) {
      return "Ready · " + m[1] + " stations (" + m[2] + " Chinese-language)";
    }
    // 美国金融风险监测的状态行与频率角标：数字与日期原样带回。
    if ((m = /^更新于 (\d+) 小时前 · 截至 (.+)$/.exec(s))) return "Updated " + m[1] + " hr ago · as of " + m[2];
    if ((m = /^更新于 (\d+) 天前 · 截至 (.+)$/.exec(s))) return "Updated " + m[1] + " d ago · as of " + m[2];
    if ((m = /^更新于 (\d+) 分钟前 · 截至 (.+)$/.exec(s))) return "Updated " + m[1] + " min ago · as of " + m[2];
    if ((m = /^(.+) · 每日$/.exec(s))) return m[1] + " · daily";
    if ((m = /^(.+) · 每月$/.exec(s))) return m[1] + " · monthly";
    if ((m = /^(.+) · 季度$/.exec(s))) return m[1] + " · quarterly";
    if ((m = /^(.+) · 年度$/.exec(s))) return m[1] + " · annual";
    if ((m = /^([▲▼]) (\S+) 较前值$/.exec(s))) return m[1] + " " + m[2] + " vs. prior";
    if ((m = /^近一年 · 一年前 (\S+)$/.exec(s))) return "Past year · one year ago " + m[1];
    if ((m = /^([+\-−]?[\d.,]+) 万亿$/.exec(s))) return m[1] + "T";
    // 标普500热力图的组合串：数字原样带回，中文单位与量级词照翻。
    if (path.indexOf("/apps/heatmap/") === 0) {
      if ((m = /^([\d,]+) 家$/.exec(s))) return m[1] + " companies";
      if ((m = /^([\d,]+)家 · ([▲▼].+)$/.exec(s))) return m[1] + " · " + m[2];
      if ((m = /^([\d,]+)家$/.exec(s))) return m[1] + " companies";
      if ((m = /^显示市值前 ([\d,]+) 家（共 ([\d,]+) 家）$/.exec(s))) {
        return "Showing the top " + m[1] + " by market cap (of " + m[2] + ")";
      }
      if ((m = /^([\d.,]+)(万亿|亿|万)美元$/.exec(s))) {
        return "$" + m[1] + ({ "万亿": "T", "亿": "00M", "万": "0K" })[m[2]];
      }
      if ((m = /^盘中快照未覆盖当前读数（更新于 (.+?)），显示的是收盘口径的日更读数。$/.exec(s))) {
        return "The intraday snapshot does not cover the current reading (updated " +
          (regexTranslate("更新于 " + m[1]) || m[1]).replace(/^Updated /, "") +
          "); what is shown is the daily close.";
      }
      /* 瓦片与气泡的 aria-label 有两种写法，差在中间多不多一段「股价 $X」：
         「英伟达（NVDA），科技，市值 5.31万亿美元，当日 ▲0.45%」
         「英伟达（NVDA），科技，股价 $219.34，市值 …，当日 …」 */
      if ((m = /^(.+?)（(.+?)），([^，]+?)，(?:股价 ([^，]+)，)?市值 ([\d.,]+)(万亿|亿|万)美元，当日 (.+)$/.exec(s))) {
        var unit = { "万亿": "T", "亿": "00M", "万": "0K" }[m[6]];
        return (dict[m[1]] || m[1]) + " (" + m[2] + "), " + (dict[m[3]] || m[3]) +
          (m[4] ? ", price " + m[4] : "") + ", market cap $" + m[5] + unit + ", today " + m[7];
      }
      /* 方法学长句结尾的成分代码数、取到行情的家数与未覆盖名单每天都会变，同样改成规则；
         代码表原样带回（只把顿号换成英文逗号），不改动任何一个代码。 */
      if ((m = /^标普500成分股的当日市值与涨跌，与全球公司榜同一次取数、同一来源。成分名单取自 datahub 公开数据集，站内按 Yahoo 的代码写法归一化后匹配；名单里站内没有行情的成分股逐个列在 missing 里，不用别的公司顶替、也不静默丢弃。市值为「最新价 × 流通股数」，与指数公司自己按自由流通量加权的口径不同，因此这里只用于相对大小的可视化，不是指数权重。名单共 ([\d,]+) 个成分代码，站内当日取到行情的 ([\d,]+) 家；未覆盖 ([\d,]+) 家：(.+?)。$/.exec(s))) {
        return "Market cap and the daily move for S&P 500 constituents, from the same fetch and the same source as the Global Companies board. " +
          "The constituent list comes from a public datahub dataset and is matched after normalising tickers to Yahoo's spelling; " +
          "constituents with no on-site quote are listed individually under \u201cmissing\u201d rather than substituted with another company or silently dropped. " +
          "Market cap here is latest price \u00d7 shares outstanding, which differs from the index provider's own free-float weighting, " +
          "so it is used only to size the tiles and is not an index weight. The list holds " + m[1] + " tickers; " + m[2] +
          " had quotes on the day and " + m[3] + " did not: " + m[4].replace(/\u3001/g, ", ") + ".";
      }
      /* 气泡图说明里的家数、百分位区间与越界家数每天取数都会变，死词条一夜就失效，
         改成两端锚定的规则：数字原样带回，任何一段对不上就整句放弃、保留中文。 */
      if ((m = /^纵向是当日涨跌，横向按行业分列，气泡面积正比于市值；共画出 ([\d,]+) 家。纵轴按第2–98百分位取范围（(.+?)）而不是按极值——按极值定范围会被个别极端值撑开，其余几百家挤成一条线。有 ([\d,]+) 家的真实涨跌在这个范围之外，贴边显示并描了虚线圈，真实数值见悬浮读数与数据表。$/.exec(s))) {
        return "The vertical axis is the daily change, the horizontal axis splits by sector, and bubble area is proportional to market cap; " +
          m[1] + " companies are drawn. The vertical range is the 2nd–98th percentile (" + m[2].replace(/-/g, "\u2212") +
          ") rather than the extremes — using the extremes lets a couple of outliers stretch the axis and squash the other few hundred into a line. " +
          m[3] + " companies fall outside that range; they are pinned to the edge with a dashed outline, and their true values are in the hover readout and the data table.";
      }
      if (s === "标普500成分股气泡图：横向按行业分列，纵向是当日，气泡面积正比于市值，共 300 家。完整读数见下方数据表。") {
        return "Bubble chart of S&P 500 constituents: split by sector horizontally, daily change vertically, bubble area proportional to market cap, 300 companies in all. Full readings are in the data table below.";
      }
      if ((m = /^标普500成分股气泡图：横向按行业分列，纵向是当日，气泡面积正比于市值，共 ([\d,]+) 家。完整读数见下方数据表。$/.exec(s))) {
        return "Bubble chart of S&P 500 constituents: split by sector horizontally, daily change vertically, bubble area proportional to market cap, " + m[1] + " companies in all. Full readings are in the data table below.";
      }
      /* 瓦片放不下时公司名会被截成「摩根士…」，截断后的字面进不了字典。
         先按前缀在字典里找唯一匹配；前缀撞车时（如「菲利…」同时命中两家）
         由下面 specialEnglish 里的 heatmapTiles() 借瓦片自己的 aria-label 定位，
         两条路都走不通就原样留着，绝不猜成另一家公司。 */
      if (/…$/.test(s)) {
        var head = s.slice(0, -1), found = null, keys = Object.keys(dict);
        for (var qi = 0; qi < keys.length; qi++) {
          if (keys[qi].indexOf(head) === 0) {
            if (found) { found = null; break; }
            found = dict[keys[qi]];
          }
        }
        if (found) return found.length > head.length + 3 ? found.slice(0, head.length + 3) + "…" : found;
      }
    }
    if (path.indexOf("/apps/movies/") === 0) {
      // 「高分电影 Top 250 · 250」「1994 · 3.1万票」：数字原样带回，中文量级词照翻。
      if ((m = /^(.+?) · (\d+)$/.exec(s)) && dict[m[1]]) return dict[m[1]] + " · " + m[2];
      if ((m = /^(\d{4}) · ([\d.]+)万票$/.exec(s))) return m[1] + " · " + m[2] + "0k votes";
      if ((m = /^(\d{4}) · ([\d,]+)票$/.exec(s))) return m[1] + " · " + m[2] + " votes";
      if ((m = /^· 更新于 (.+)$/.exec(s))) return "· Updated " + m[1];
    }
    if (s === "刚刚") return "Just now";
    return null;
  }

  function translateValue(s) {
    if (Object.prototype.hasOwnProperty.call(dict, s)) return dict[s];
    return regexTranslate(s);
  }

  function skipText(node) {
    var p = node && node.parentElement;
    if (!p || /^(SCRIPT|STYLE|NOSCRIPT|CODE|PRE)$/.test(p.tagName)) return true;
    if (p.closest && p.closest("[data-i18n-skip]")) return true;
    return false;
  }

  function translateText(node) {
    if (!node || node.nodeType !== 3 || skipText(node)) return;
    var raw = node.nodeValue || "", s = raw.trim();
    if (!s) return;
    var out = translateValue(s);
    if (!out || out === s) return;
    if (!textOrig.has(node)) { textOrig.set(node, raw); textTouched.push(node); }
    var i = raw.indexOf(s);
    node.nodeValue = (i >= 0 ? raw.slice(0, i) : "") + out + (i >= 0 ? raw.slice(i + s.length) : "");
  }

  function translateAttrs(el) {
    if (!el || el.nodeType !== 1) return;
    var saved = attrOrig.get(el) || {}, touched = false;
    ATTRS.forEach(function (a) {
      if (!el.hasAttribute(a)) return;
      var v = el.getAttribute(a), out = translateValue(v);
      if (!out || out === v) return;
      if (!(a in saved)) saved[a] = v;
      el.setAttribute(a, out); touched = true;
    });
    if (touched && !attrOrig.has(el)) { attrOrig.set(el, saved); attrTouched.push(el); }
  }

  function rememberHtml(el) {
    if (!el || htmlOrig.has(el)) return;
    htmlOrig.set(el, el.innerHTML); htmlTouched.push(el);
  }
  function rememberStyle(el) {
    if (!el || styleOrig.has(el)) return;
    styleOrig.set(el, el.getAttribute("style")); styleTouched.push(el);
  }

  function financeSpecial() {
    if (path === "/apps/finance-column/" && window.ARCH) {
      document.querySelectorAll(".layer-card").forEach(function (card) {
        var id = (card.querySelector(".lc-id") || {}).textContent || "";
        var layer = window.ARCH.findLayer ? window.ARCH.findLayer(id.trim()) : null;
        if (!layer) return;
        var h = card.querySelector("h3"), en = card.querySelector(".lc-en");
        if (h && en) { rememberHtml(h); h.textContent = layer.en || en.textContent; }
        card.querySelectorAll(".mchip").forEach(function (chip, i) {
          if (!layer.modules[i]) return;
          rememberHtml(chip); chip.textContent = (layer.modules[i].en || layer.modules[i].cn) + (layer.modules[i].isNew ? " ★" : "");
        });
      });
    }
    if (path.indexOf("/apps/finance-column/layer") === 0 && window.ARCH) {
      document.querySelectorAll("#lnav .lpill").forEach(function (pill) {
        var id = (pill.querySelector("b") || {}).textContent || "";
        var layer = window.ARCH.findLayer ? window.ARCH.findLayer(id.trim()) : null;
        var span = pill.querySelector("span");
        if (layer && span) { rememberHtml(span); span.textContent = layer.en || layer.cn; }
      });
      var idp = new URLSearchParams(location.search).get("id") || "L1";
      var lay = window.ARCH.findLayer ? window.ARCH.findLayer(idp) : null;
      if (lay) {
        var hh = document.querySelector(".layer-hero h1"), he = document.querySelector(".layer-hero .lh-en");
        if (hh) { rememberHtml(hh); hh.textContent = lay.en || lay.cn; }
        if (he) { rememberHtml(he); he.textContent = lay.cn; }
        document.querySelectorAll(".mod-sec").forEach(function (sec, i) {
          var mod = lay.modules[i]; if (!mod) return;
          var h3 = sec.querySelector("h3"), me = sec.querySelector(".ms-en");
          if (h3) { rememberHtml(h3); h3.textContent = mod.en || mod.cn; }
          if (me) { rememberHtml(me); me.textContent = mod.cn; }
          sec.querySelectorAll(".term").forEach(function (term, ti) {
            var row = mod.terms[ti]; if (!row) return;
            var cn = term.querySelector(".t-cn"), en = term.querySelector(".t-en");
            if (cn && en) { rememberHtml(cn); rememberHtml(en); cn.textContent = row[1] || row[0]; en.textContent = row[0]; }
          });
        });
      }
    }
    if (path.indexOf("/apps/finance-column/diagrams") === 0) {
      document.querySelectorAll(".dg-group").forEach(function (g) {
        var h2 = g.querySelector(".sec-title h2"), ge = g.querySelector(".sec-title .en");
        if (h2 && ge && ge.textContent.trim()) { rememberHtml(h2); var old = h2.textContent; h2.textContent = ge.textContent.trim(); rememberHtml(ge); ge.textContent = old; }
        g.querySelectorAll(".dg-card").forEach(function (c) {
          var h3 = c.querySelector("h3"), de = c.querySelector(".dg-en");
          if (h3 && de && de.textContent.trim()) { rememberHtml(h3); var oldh = h3.textContent; h3.textContent = de.textContent.trim(); rememberHtml(de); de.textContent = oldh; }
        });
      });
    }
  }

  /* 前缀撞车的截断瓦片：它外层的链接带 aria-label，此时已经被翻成
     「Phillips 66 (PSX), Energy, …」，从中取出公司名再按同样长度截断。
     取不到就不动——宁可留中文，也不把一家公司显示成另一家。 */
  function heatmapTiles() {
    if (path.indexOf("/apps/heatmap/") !== 0) return;
    document.querySelectorAll(".heat-tile-name").forEach(function (el) {
      var t = (el.textContent || "").trim();
      if (!/…$/.test(t) || !/[\u4e00-\u9fff]/.test(t)) return;
      var host = el.closest && el.closest("[aria-label]");
      var lab = host && host.getAttribute("aria-label");
      var mm = lab && /^(.+?) \(/.exec(lab);
      if (!mm || /[\u4e00-\u9fff]/.test(mm[1])) return;
      var head = t.slice(0, -1), en = mm[1];
      var node = el.firstChild;
      if (!node || node.nodeType !== 3) return;
      if (!textOrig.has(node)) { textOrig.set(node, node.nodeValue); textTouched.push(node); }
      node.nodeValue = en.length > head.length + 3 ? en.slice(0, head.length + 3) + "…" : en;
    });
  }

  function specialEnglish() {
    financeSpecial();
    heatmapTiles();
    /* 这里原本硬把态势地球的 #btn-lang 写成「EN / 中」并置 aria-pressed=true。
       那个按钮说的是「应用内」的语言，不是站内语言，硬改会让按钮对不上实际状态，
       而且切回中文时不还原。页面自己的 paintLang() 已经跟随站内语言，这段去掉。 */
  }

  function walk(scope) {
    var base = scope && scope.nodeType ? scope : document.body;
    if (!base) return;
    if (base.nodeType === 3) { translateText(base); return; }
    if (base.nodeType === 1) translateAttrs(base);
    var w = document.createTreeWalker(base, NodeFilter.SHOW_TEXT, null), n;
    while ((n = w.nextNode())) translateText(n);
    var els = base.querySelectorAll ? base.querySelectorAll("[placeholder],[aria-label],[title],[alt]") : [];
    for (var i = 0; i < els.length; i++) translateAttrs(els[i]);
    specialEnglish();
  }

  function restore() {
    textTouched.forEach(function (n) { if (n && textOrig.has(n)) n.nodeValue = textOrig.get(n); });
    attrTouched.forEach(function (el) {
      var saved = attrOrig.get(el); if (!el || !saved) return;
      Object.keys(saved).forEach(function (a) { el.setAttribute(a, saved[a]); });
    });
    htmlTouched.forEach(function (el) { if (el && htmlOrig.has(el)) el.innerHTML = htmlOrig.get(el); });
    styleTouched.forEach(function (el) {
      if (!el || !styleOrig.has(el)) return;
      var v = styleOrig.get(el); if (v == null) el.removeAttribute("style"); else el.setAttribute("style", v);
    });
    textTouched = []; attrTouched = []; htmlTouched = []; styleTouched = [];
    textOrig = new WeakMap(); attrOrig = new WeakMap(); htmlOrig = new WeakMap(); styleOrig = new WeakMap();
  }

  var metaOrig = null;
  var META = {
    "/apps/heatmap/": ["S&P 500 Heatmap · Ooglex", "S&P 500 constituents grouped by sector, sized by market cap and colored by daily move, with explicit percentages and a full data table."],
    "/apps/ofr-monitor/": ["U.S. Financial Risk Monitor · OFR", "Five OFR monitors covering financial stress, short-term funding, money market funds, hedge funds and systemic banking risk."],
    "/apps/finance-column/": ["Ultimate Financial Knowledge Architecture · Ooglex", "A structured Wall Street knowledge map spanning 8 layers, 48 modules and 560+ bilingual financial terms."],
    "/apps/finance-column/layer.html": ["Financial Knowledge Architecture · Layer", "Layer detail from the Ooglex financial knowledge architecture."],
    "/apps/finance-column/diagrams.html": ["Causal Concept Maps · Financial Knowledge Architecture", "Native web vector maps connecting financial concepts through causal relationships."],
    "/apps/movies/": ["Global Movie Rankings · Top 250 & New Releases", "Top-rated movies, new worldwide releases, official trailers and public-domain classics, updated daily from TMDB."],
    "/apps/ai-chat/": ["Ooglex AI Chat", "Lightweight multi-model AI chat with local settings, streaming responses and optional user-provided API keys."],
    "/apps/calculators/": ["Ooglex Calculators · Finance, Health, Math & More", "70+ browser calculators across finance, health, math, conversions, physics, chemistry and everyday utilities."],
    "/apps/radio/": ["Global Radio · Spin the Globe and Listen", "Spin a 3D globe and listen to radio stations around the world."],
    "/apps/tv/": ["Global TV · Spin the Globe and Watch", "Spin a 3D globe and explore live television channels around the world."],
    "/apps/globe/": ["Global Situational Globe · 3D Geospatial Data", "A browser-based 3D globe with public geospatial layers including earthquakes, data centers, dams, submarine cables and satellites."],
    "/apps/name-fortune/": ["Name & Fortune · Entertainment Reading", "A traditional Chinese name, BaZi and five-elements reading for entertainment only."],
    "/games/hub/": ["Game Center · Browser Games · Ooglex", "Browser games including GTA Vice City and Red Alert 2, with no installation required."],
    "/games/gta-vice-city/": ["GTA Vice City · Browser Edition", "Play GTA Vice City in the browser with fullscreen and landscape controls."],
    "/games/red-alert/": ["Red Alert 2 · Browser Edition", "Play Red Alert 2 in the browser with campaigns, skirmishes and multiplayer."],
    "/privacy/": ["Privacy Policy · Ooglex", "Ooglex privacy policy covering local storage, analytics, advertising, cookies and user choices."]
  };
  function metaKey() {
    if (META[path]) return path;
    if (path.indexOf("/apps/finance-column/layer") === 0) return "/apps/finance-column/layer.html";
    if (path.indexOf("/apps/finance-column/diagrams") === 0) return "/apps/finance-column/diagrams.html";
    return null;
  }
  function translateMeta() {
    if (!metaOrig) {
      var d = document.querySelector('meta[name="description"]');
      var ot = document.querySelector('meta[property="og:title"]');
      var od = document.querySelector('meta[property="og:description"]');
      metaOrig = { title: document.title, desc: d && d.content, ogTitle: ot && ot.content, ogDesc: od && od.content };
    }
    var k = metaKey(), m = k && META[k]; if (!m) return;
    document.title = m[0];
    var desc = document.querySelector('meta[name="description"]'); if (desc) desc.content = m[1];
    var ogt = document.querySelector('meta[property="og:title"]'); if (ogt) ogt.content = m[0];
    var ogd = document.querySelector('meta[property="og:description"]'); if (ogd) ogd.content = m[1];
  }
  function restoreMeta() {
    if (!metaOrig) return;
    document.title = metaOrig.title;
    var desc = document.querySelector('meta[name="description"]'); if (desc && metaOrig.desc != null) desc.content = metaOrig.desc;
    var ogt = document.querySelector('meta[property="og:title"]'); if (ogt && metaOrig.ogTitle != null) ogt.content = metaOrig.ogTitle;
    var ogd = document.querySelector('meta[property="og:description"]'); if (ogd && metaOrig.ogDesc != null) ogd.content = metaOrig.ogDesc;
  }
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
          else Array.prototype.forEach.call(r.addedNodes || [], function (n) { walk(n); });
        });
        specialEnglish();
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
    document.documentElement.setAttribute("data-lang", current);
    document.documentElement.setAttribute("lang", current === "en" ? "en" : "zh-CN");
    if (current === "en") { walk(document.body); translateMeta(); watch(); }
    else { restore(); restoreMeta(); }
  }

  function boot() {
    apply(readLang());
    if (path.indexOf("/apps/globe/") === 0) {
      var btn = document.getElementById("btn-lang");
      if (btn) btn.addEventListener("click", function () { setTimeout(function () { apply(readLang()); }, 0); });
    }
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();

  document.addEventListener("ooglex:languagechange", function (e) {
    apply(e && e.detail && e.detail.language === "en" ? "en" : "zh");
  });
  window.addEventListener("storage", function (e) {
    if (e.key === KEY) apply(e.newValue === "en" ? "en" : "zh");
  });
})();
