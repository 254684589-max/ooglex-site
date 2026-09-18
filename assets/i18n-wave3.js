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
  var ATTRS = ["placeholder", "aria-label", "title"];

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
    "🌐 全球资产市值排行榜": "🌐 Global Assets by Market Cap",
    "不限品类 · 只看市值 · 房地产 / 国债 / 商品 / 货币 / 黄金 / 公司 / 加密货币 同台前 250": "All asset classes · Ranked only by market cap · Property / sovereign debt / commodities / currencies / gold / companies / crypto · Top 250",
    "市值排名": "Market Cap Rank",
    "搜索资产 / 代码（中 · 英）…": "Search asset / ticker…",
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
  if (path.indexOf("/apps/asset-ranking/") === 0) copy(dict, ASSET_RANKING);
  if (path.indexOf("/apps/house-prices/") === 0) { copy(dict, COUNTRY); copy(dict, HOUSE); }
  if (path.indexOf("/apps/world-economy/") === 0) { copy(dict, COUNTRY); copy(dict, WORLD); }
  if (path.indexOf("/apps/superinvestors/") === 0) copy(dict, SUPER);
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

  function walk(scope) {
    var base = scope && scope.nodeType ? scope : document.body;
    if (!base) return;
    if (base.nodeType === 3) { translateText(base); return; }
    if (base.nodeType === 1) translateAttrs(base);
    var w = document.createTreeWalker(base, NodeFilter.SHOW_TEXT, null), n;
    while ((n = w.nextNode())) translateText(n);
    var els = base.querySelectorAll ? base.querySelectorAll("[placeholder],[aria-label],[title]") : [];
    for (var i = 0; i < els.length; i++) translateAttrs(els[i]);
  }

  function restore() {
    for (var i = 0; i < textTouched.length; i++) {
      var n = textTouched[i]; if (n && textOrig.has(n)) n.nodeValue = textOrig.get(n);
    }
    for (var j = 0; j < attrTouched.length; j++) {
      var el = attrTouched[j], saved = attrOrig.get(el); if (!el || !saved) continue;
      Object.keys(saved).forEach(function (a) { el.setAttribute(a, saved[a]); });
    }
    textTouched = []; attrTouched = [];
    textOrig = new WeakMap(); attrOrig = new WeakMap();
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
