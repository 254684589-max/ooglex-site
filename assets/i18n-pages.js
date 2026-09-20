/* Ooglex second-wave page i18n layer.
   Extends /assets/i18n.js for data-heavy pages while preserving original Chinese text.
   Only reviewed UI strings are translated; source names and unmapped research prose stay untouched. */
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
      if (window.OoglexI18n && window.OoglexI18n.getLanguage) return window.OoglexI18n.getLanguage() === "en" ? "en" : "zh";
      return localStorage.getItem(KEY) === "en" ? "en" : "zh";
    } catch (e) { return "zh"; }
  }

  var COMMON = {
    "← 返回 Ooglex": "← Back to Ooglex",
    "← 返回首页": "← Back to Home",
    "关于本页数据": "About This Data",
    "数据来源与延伸阅读": "Data Sources & Further Reading",
    "加载中…": "Loading…",
    "加载失败": "Load failed",
    "暂无数据": "No data",
    "实时 · 每日自动更新": "Live · Updated daily",
    "实时榜 · 每日自动更新": "Live ranking · Updated daily",
    "示例数据 · 待刷新": "Sample data · Awaiting refresh",
    "示例数据 · 待每日任务刷新": "Sample data · Awaiting daily refresh",
    "数据来源": "Data Source",
    "数据日期": "Date",
    "更新于": "Updated",
    "今日涨幅": "Top Gainers",
    "今日跌幅": "Top Decliners",
    "综合第一": "Overall #1",
    "开源第一": "Open-source #1",
    "全部": "All",
    "今天": "Today",
    "实际": "Actual",
    "预测": "Forecast",
    "前值": "Previous"
  };

  var ASSET = {
    "🌍 全球大类资产收益率": "🌍 Global Asset Returns",
    "一图看尽 股市 · 商品 · 外汇 · 债券 的收益率表现": "One view of returns across equities · commodities · FX · bonds",
    "图表": "Chart",
    "📊 图表": "📊 Chart",
    "📋 数据表": "📋 Table",
    "数据来自 Yahoo Finance 公开行情，每日自动更新；涨跌幅为各标的自身价格变动。LME 金属以全球期货代理、债券以国债 ETF 代理（详见各条备注）。仅供参考，非投资建议。":
      "Data comes from Yahoo Finance public quotes and refreshes daily; the percentage is each instrument's own price change. LME metals are proxied by global futures and bonds by Treasury ETFs (see each instrument's note). For reference only; not investment advice.",
    "本页把全球主要大类资产——股票指数、商品、外汇、债券——的近期收益率放在同一张表里横向对比，帮你快速看清「最近什么在涨、什么在跌」。数值为区间涨跌幅，绿涨红跌；数据来源 Yahoo Finance，每日自动刷新。提示：历史收益率不代表未来表现，本页仅供参考，不构成任何投资建议。":
      "This page puts recent returns for the major asset classes — equity indices, commodities, FX and bonds — into one comparable table, so you can see at a glance what has been rising and what has been falling. Values are the change over the period, green for up and red for down; data comes from Yahoo Finance and refreshes daily. Past returns do not predict future performance; for reference only, not investment advice.",
    "表格": "Table",
    "日频行情 · 每日自动更新": "Daily market data · Updated daily",
    "示例数据 · 合并后转真实行情": "Sample data · Live source after merge",
    "资产": "Asset",
    "该周期暂无足够数据": "Not enough data for this period",
    "该周期暂无数据，换个周期或品类试试 🙂": "No data for this period. Try another period or category 🙂",
    "代理标的": "Proxy instrument",
    "部分周期数据异常，已隐藏": "Some period data is anomalous and has been hidden",
    "代理说明：": "Proxy notes:",
    "今日": "Today",
    "近一周": "1W",
    "近一月": "1M",
    "年初至今": "YTD",
    "近一年": "1Y",
    "股市": "Equities",
    "商品": "Commodities",
    "外汇": "FX",
    "债券": "Bonds"
  };

  var COMPANIES = {
    /* 国名与板块是行卡的标注维度，属界面；公司名走 specialEnglish 拿数据里的 nameEn。
       两张表逐条对着 apps/companies/data.json 的实际取值补齐，实测无遗漏。 */
    "美国": "United States",
    "中国": "China",
    "日本": "Japan",
    "德国": "Germany",
    "英国": "United Kingdom",
    "法国": "France",
    "印度": "India",
    "意大利": "Italy",
    "加拿大": "Canada",
    "韩国": "South Korea",
    "台湾": "Taiwan",
    "荷兰": "Netherlands",
    "瑞士": "Switzerland",
    "瑞典": "Sweden",
    "丹麦": "Denmark",
    "爱尔兰": "Ireland",
    "比利时": "Belgium",
    "西班牙": "Spain",
    "澳大利亚": "Australia",
    "新加坡": "Singapore",
    "沙特": "Saudi Arabia",
    "萨尔瓦多": "El Salvador",
    "百慕大": "Bermuda",
    "塞舌尔": "Seychelles",
    "纳米比亚": "Namibia",
    "科技": "Technology",
    "软件": "Software",
    "半导体": "Semiconductors",
    "互联网": "Internet",
    "人工智能": "Artificial Intelligence",
    "AI数据": "AI Data",
    "数据与AI": "Data & AI",
    "数据中心": "Data Centers",
    "数据存储": "Data Storage",
    "机器人": "Robotics",
    "自动驾驶": "Autonomous Driving",
    "电商": "E-commerce",
    "游戏": "Gaming",
    "教育科技": "Education Technology",
    "通信服务": "Communication Services",
    "电信": "Telecom",
    "金融": "Financials",
    "金融科技": "Fintech",
    "支付": "Payments",
    "保险经纪": "Insurance Brokerage",
    "加密货币": "Crypto",
    "医疗健康": "Healthcare",
    "可选消费": "Consumer Discretionary",
    "必需消费": "Consumer Staples",
    "消费品": "Consumer Goods",
    "食品": "Food",
    "零售": "Retail",
    "品牌授权": "Brand Licensing",
    "体育": "Sports",
    "工业": "Industrials",
    "基建": "Infrastructure",
    "国防": "Defense",
    "国防科技": "Defense Technology",
    "能源": "Energy",
    "新能源": "Clean Energy",
    "原材料": "Materials",
    "公用事业": "Utilities",
    "房地产": "Real Estate",
    "上市公司市值/股价/当日涨跌每日自动更新（来源 Yahoo Finance，本币市值按汇率折美元）；末段为知名非上市公司（标「未上市」，最近一轮公开估值、非实时）。仅供参考，不构成投资建议。":
      "Market cap, share price and the daily move for listed companies refresh daily (source: Yahoo Finance; local-currency market caps are converted to USD at the prevailing rate). The tail of the list is well-known private companies, marked “Private”, carrying their most recent publicly reported valuation rather than a live figure. For reference only; not investment advice.",
    "🏢 全球公司市值榜": "🏢 Global Companies by Market Cap",
    "全球市值前 500 强 · 上市与非上市 · 实时股价与当日涨跌 · 每日自动更新": "Global top 500 · Public and private companies · Prices and daily moves · Updated daily",
    "标普500热力图 →": "S&P 500 Heatmap →",
    "按市值": "Market Cap",
    "搜索公司 / 代码（中 · 英）…": "Search company / ticker…",
    "没有匹配的公司，换个关键词试试 🙂": "No matching companies. Try another keyword 🙂",
    "🌐 全球最有价值私营公司 · 未上市 / 待上市 · 最新估值（非实时）": "🌐 World's most valuable private companies · Latest valuations (not real-time)",
    "未上市": "Private",
    "最新估值": "Latest valuation",
    "上轮融资": "Last round",
    "示例数据 · 待每日任务刷新": "Sample data · Awaiting daily refresh",
    "本页按市值排列全球前 500 大公司（含部分知名非上市公司），展示实时股价、当日涨跌与市值，数据来源 Financial Modeling Prep，每日自动更新。市值 = 股价 × 总股本，会随股价变化；非上市公司市值为估值参考。本页仅供研究参考，不构成投资建议。":
      "This page ranks the world's 500 largest companies by market cap, including a number of well-known private ones, showing live share price, the daily move and market cap. Data comes from Financial Modeling Prep and refreshes daily. Market cap = share price × shares outstanding, so it moves with the price; for private companies the figure is a reference valuation. For research reference only; not investment advice."
  };

  var AI = {
    "全球大模型评测榜": "Global AI Model Rankings",
    "LMArena 竞技场 Elo · LiveBench 客观评测 · Artificial Analysis 智能指数 —— 三榜合一，每日自动更新": "LMArena Elo · LiveBench · Artificial Analysis Intelligence Index — combined ranking, updated daily",
    "搜索模型 / 厂商（中英皆可）…": "Search model / provider…",
    "🏆 综合": "🏆 Overall",
    "⚔️ 竞技场 Elo": "⚔️ Arena Elo",
    "🧪 LiveBench": "🧪 LiveBench",
    "📊 智能指数": "📊 Intelligence Index",
    "🔓 开源模型": "🔓 Open-source Models",
    "智能": "Intel.",
    "LiveBench 均分": "LiveBench Avg.",
    "智能指数": "Intelligence Index",
    "综合参考分": "Composite Score",
    "没有匹配的模型": "No matching models",
    "开源": "Open",
    "闭源": "Closed",
    "上下文": "Context",
    "上线快照（近似值）· 合并后每日自动更新": "Launch snapshot (approx.) · Updated daily after live merge",
    "数据来源与延伸阅读": "Data Sources & Further Reading",
    "谷歌": "Google",
    "阿里巴巴": "Alibaba",
    "月之暗面": "Moonshot AI",
    "智谱AI": "Zhipu AI",
    "字节跳动": "ByteDance",
    "深度求索": "DeepSeek",
    "智谱": "Zhipu AI",
    /* KPI 行被 <b> 拆开：「覆盖 <b>N</b> 个模型」「中国模型 <b>N</b> 个」 */
    "覆盖": "Coverage",
    "个模型": "models",
    "中国模型": "China-based models",
    "个": "models",
    "LMArena（竞技场 Elo） ↗": "LMArena (Arena Elo) ↗",
    "数百万用户匿名对战投票的 Elo 排名": "Elo ranking from millions of anonymous head-to-head votes",
    "定期换题的客观评测：数学 · 推理 · 编程 · 数据分析 · 指令遵循":
      "Objective benchmarks with rotating questions: maths · reasoning · coding · data analysis · instruction following",
    "Artificial Analysis 智能指数 ↗": "Artificial Analysis Intelligence Index ↗",
    "综合多项基准的智能指数，兼看速度与价格":
      "An intelligence index across several benchmarks, alongside speed and price",
    "每小时更新的模型热度与采用率趋势": "Hourly model popularity and adoption trends",
    "开源模型评测榜（已归档，供参考）": "Open-source model leaderboard (archived, for reference)",
    "HELM（斯坦福） ↗": "HELM (Stanford) ↗",
    "强调公平可重复的学术评测平台": "An academic evaluation platform built for fairness and reproducibility",
    "数据每日自动更新一次（北京时间 07:00 前抓取 LMArena / LiveBench 最新榜单）；":
      "Data refreshes once a day (the latest LMArena and LiveBench boards are fetched before 07:00 Beijing time);",
    "各榜单口径不同（Elo 为相对对战胜率、LiveBench 为客观题得分、智能指数为综合基准），跨榜绝对值不可直接比较；":
      "the rankings measure different things (Elo is a relative head-to-head win rate, LiveBench is an objective test score, and the Intelligence Index is a composite benchmark), so absolute values are not comparable across them;",
    "「综合」列为本站将三榜归一化后的加权参考分，仅用于粗略排序。数据仅供参考，不构成任何建议。":
      "the “Overall” column is this site's weighted reference score after normalising the three rankings, and is only meant for rough ordering. For reference only; not advice."
  };

  var UNIVERSITY = {
    "全球大学排名 300 强": "Global University Rankings · Top 300",
    "QS · THE 泰晤士 · ARWU 软科 · U.S. News —— 四大权威榜单合一，按各校平均位次综合排序": "QS · THE · ARWU · U.S. News — combined by each university's average rank",
    "🚀 全球专业与就业前景榜 →": "🚀 Majors & Career Outlook →",
    "搜索大学 / 国家（中英皆可）…": "Search university / country…",
    "🏆 综合": "🏆 Overall",
    "📊 THE 泰晤士": "📊 THE",
    "🔬 ARWU 软科": "🔬 ARWU",
    "四榜均位": "Average of 4 rankings",
    "QS 位次": "QS Rank",
    "THE 位次": "THE Rank",
    "ARWU 位次": "ARWU Rank",
    "U.S. News 位次": "U.S. News Rank",
    "没有匹配的学校": "No matching universities",
    "数据来源与延伸阅读": "Data Sources & Further Reading",
    "美国": "United States",
    "英国": "United Kingdom",
    "中国": "China",
    "中国香港": "Hong Kong SAR",
    "中国台湾": "Taiwan",
    "新加坡": "Singapore",
    "日本": "Japan",
    "韩国": "South Korea",
    "瑞士": "Switzerland",
    "德国": "Germany",
    "法国": "France",
    "荷兰": "Netherlands",
    "加拿大": "Canada",
    "澳大利亚": "Australia",
    "瑞典": "Sweden",
    "比利时": "Belgium",
    "丹麦": "Denmark",
    "意大利": "Italy",
    "西班牙": "Spain",
    "芬兰": "Finland",
    "挪威": "Norway",
    "奥地利": "Austria",
    "爱尔兰": "Ireland",
    "新西兰": "New Zealand",
    "印度": "India",
    "巴西": "Brazil",
    "以色列": "Israel",
    "沙特": "Saudi Arabia",
    "南非": "South Africa",
    "俄罗斯": "Russia",
    "葡萄牙": "Portugal",
    "马来西亚": "Malaysia",
    "捷克": "Czech Republic",
    "波兰": "Poland",
    "阿根廷": "Argentina",
    "墨西哥": "Mexico",
    "希腊": "Greece",
    "智利": "Chile",
    "卡塔尔": "Qatar",
    "阿联酋": "United Arab Emirates",
    "泰国": "Thailand",
    /* KPI 行是「覆盖 <b>300</b> 所」这种，<b> 把它拆成两个文本节点，整串进不了字典 */
    "覆盖": "Coverage",
    "所": "universities",
    "上榜": "Listed in",
    "个国家/地区": "countries/regions",
    "中国高校": "China-based universities",
    "QS 世界大学排名 ↗": "QS World University Rankings ↗",
    "QS 世界大学排名": "QS World University Rankings",
    "Quacquarelli Symonds，侧重学术声誉、雇主声誉与国际化":
      "Quacquarelli Symonds — weighted toward academic reputation, employer reputation and internationalisation",
    "THE 泰晤士高等教育世界大学排名 ↗": "THE Times Higher Education World University Rankings ↗",
    "THE 泰晤士高等教育世界大学排名": "THE Times Higher Education World University Rankings",
    "18 项指标，覆盖教学、研究、引用、产业与国际展望":
      "18 indicators spanning teaching, research, citations, industry and international outlook",
    "ARWU 软科世界大学学术排名 ↗": "ARWU Academic Ranking of World Universities ↗",
    "ARWU 软科世界大学学术排名": "ARWU Academic Ranking of World Universities",
    "上海交大发起，重科研产出与顶级奖项（诺奖/菲尔兹/高被引）":
      "Started by Shanghai Jiao Tong University — weighted toward research output and top prizes (Nobel, Fields, highly cited researchers)",
    "上海交大发起，重科研产出与顶级奖项":
      "Started by Shanghai Jiao Tong University — weighted toward research output and top prizes",
    "U.S. News 全球最佳大学 ↗": "U.S. News Best Global Universities ↗",
    "U.S. News 全球最佳大学": "U.S. News Best Global Universities",
    "以全球研究声誉与文献计量表现为主": "Driven mainly by global research reputation and bibliometrics",
    "本榜为": "This table is an ",
    "年度权威数据整理": "annual compilation of authoritative data",
    "：综合 QS / THE / ARWU / U.S. News 四大权威世界大学排名近一期公开位次；":
      ": it combines the most recent published positions from QS, THE, ARWU and U.S. News;",
    "「综合」列为各校在四大榜单位次的平均值（ARTU 式聚合排名，至少命中两个榜才计入），位次越小越靠前；":
      "the “Overall” column is each university's average position across the four rankings (an ARTU-style aggregate, counted only when a university appears in at least two), and a lower number ranks higher;",
    "各榜评价口径不同（声誉、科研产出、引用、国际化侧重各异），跨榜绝对位次不可直接比较，数据以各榜官方公布为准，仅供参考。":
      "each ranking measures different things (reputation, research output, citations and internationalisation carry different weights), so absolute positions are not directly comparable across them. The publishers' official releases govern; this table is for reference only.",
    "关于全球大学排名 300 强": "About the Global University Rankings Top 300",
    "本榜把四大权威世界大学排名合为一张表：": "This table merges four authoritative world university rankings: ",
    "（侧重学术声誉、雇主声誉与国际化）、": " (academic reputation, employer reputation and internationalisation), ",
    "（18 项指标覆盖教学/研究/引用/产业/国际展望）、":
      " (18 indicators across teaching, research, citations, industry and international outlook), ",
    "（上海交大发起，重科研产出与顶级奖项）、":
      " (started by Shanghai Jiao Tong University, weighted toward research output and top prizes), and ",
    "（以全球研究声誉与文献计量为主）。": " (driven mainly by global research reputation and bibliometrics).",
    "「综合」排名采用 ARTU 式聚合法，取每所大学在各榜位次的平均值排序（至少命中两个榜才计入综合），可切换查看任一单榜，并按国家/地区筛选、中英文搜索。本榜为四大榜单近一期公开位次的年度权威整理，数据以各榜官方公布为准，仅供参考，不构成升学建议。":
      "The “Overall” ranking uses an ARTU-style aggregate: each university's positions are averaged across the rankings it appears in (at least two are required). You can switch to any single ranking, filter by country or region, and search in Chinese or English. The table is an annual compilation of the most recent published positions; the publishers' official releases govern. For reference only; not admissions advice."
  };

  /* 长键在前：供上面的子串替换使用，避免短键截胡长键（见 specialEnglish 里的注释）。 */
  var UNIVERSITY_KEYS_BY_LENGTH = Object.keys(UNIVERSITY).sort(function (a, b) { return b.length - a.length; });

  var CALENDAR = {
    /* 国别是筛选标签，属界面；事件名与数值不翻 */
    "全球": "Global",
    "美国": "United States",
    "欧元区": "Euro Area",
    "英国": "United Kingdom",
    "日本": "Japan",
    "中国": "China",
    "加拿大": "Canada",
    "澳大利亚": "Australia",
    "新西兰": "New Zealand",
    "瑞士": "Switzerland",
    "Forex Factory 经济日历": "Forex Factory Economic Calendar",
    "经济日历来自 Forex Factory 公开周历（免登录），含央行利率决议、CPI、非农、PMI、GDP 等重要事件的预测值与前值；时间为 UTC，事件公布后会回填实际值。仅供参考，不构成投资建议。":
      "The calendar comes from Forex Factory's public weekly schedule (no login required) and carries forecasts and previous readings for central-bank rate decisions, CPI, non-farm payrolls, PMI, GDP and other major events. Times are UTC, and actual values are backfilled once released. For reference only; not investment advice.",
    "本页汇总本周全球重要经济事件——央行利率决议、CPI、非农就业、PMI、GDP 等，并列出市场预测值与前值，按你所在时区显示，数据来源 Forex Factory，每日自动更新。实际公布值与预测之间的差异，往往是行情波动的触发点。事件时间偶有调整，请以官方公布为准。":
      "This page collects the week's major global economic events — central-bank rate decisions, CPI, non-farm payrolls, PMI, GDP and more — with market forecasts and previous readings, shown in your own time zone. Data comes from Forex Factory and is updated daily. The gap between the released figure and the forecast is often what moves the market. Event times are occasionally revised; the official announcement governs.",
    "全球经济日历": "Global Economic Calendar",
    "央行利率决议 · CPI · 非农 · PMI · GDP —— 含预测值与前值，按你的本地时区显示": "Central-bank decisions · CPI · payrolls · PMI · GDP — forecasts and previous values, shown in your local time zone",
    "高影响": "High impact",
    "中影响": "Medium impact",
    "低影响": "Low impact",
    "假日": "Holiday",
    "绿色 = 已公布实际值": "Green = released actual value",
    "🔴 高影响": "🔴 High impact",
    "🟠 中": "🟠 Medium",
    "⚪ 低": "⚪ Low",
    "本周该筛选下暂无事件 🙂": "No events match this filter this week 🙂",
    "⏭ 接下来": "⏭ Next",
    "即将公布": "Due shortly",
    "事件时间已自动换算为你的本地时区显示。": "Event times are automatically converted to your local time zone.",
    "周日": "Sun",
    "周一": "Mon",
    "周二": "Tue",
    "周三": "Wed",
    "周四": "Thu",
    "周五": "Fri",
    "周六": "Sat"
  };

  var FEAR = {
    "🧭 市场恐慌与贪婪指数": "🧭 Market Fear & Greed Index",
    "CNN Fear & Greed · 0 = 极度恐惧 · 100 = 极度贪婪 · 每日自动更新": "CNN Fear & Greed · 0 = Extreme Fear · 100 = Extreme Greed · Updated daily",
    "📈 近一年走势": "📈 1-Year Trend",
    "7 个驱动指标": "7 Drivers",
    "极度恐惧": "Extreme Fear",
    "恐惧": "Fear",
    "中性": "Neutral",
    "贪婪": "Greed",
    "极度贪婪": "Extreme Greed",
    "上一收盘": "Previous Close",
    "一周前": "1 Week Ago",
    "一月前": "1 Month Ago",
    "一年前": "1 Year Ago",
    "暂无指标数据": "No indicator data",
    /* 主读数是「中文 · ENGLISH」并列，英文下并列就成了 Fear · FEAR 的重复，只留一个 */
    "极度恐惧 · EXTREME FEAR": "Extreme Fear",
    "恐惧 · FEAR": "Fear",
    "中性 · NEUTRAL": "Neutral",
    "贪婪 · GREED": "Greed",
    "极度贪婪 · EXTREME GREED": "Extreme Greed",
    "数据来自 CNN 恐慌与贪婪指数：0 = 极度恐惧，100 = 极度贪婪，由 7 个市场情绪指标综合而成，每日自动更新。仅供参考，不构成建议。":
      "Data comes from the CNN Fear & Greed Index: 0 = extreme fear, 100 = extreme greed, composited from seven market-sentiment indicators and updated daily. For reference only; not advice.",
    "本页追踪 CNN 市场恐慌与贪婪指数（Fear & Greed Index），用 0–100 衡量市场情绪：越低越恐慌、越高越贪婪，并拆解 7 个驱动指标与历史曲线，每日自动更新。它是情绪参考而非买卖信号——极端恐慌或贪婪常被当作反向观察线索，但不应单独作为决策依据。":
      "This page tracks the CNN Fear & Greed Index, which scores market sentiment from 0 to 100 — lower is more fearful, higher is more greedy — and breaks out its seven drivers plus the historical curve, updated daily. It is a sentiment reference, not a buy or sell signal: extreme fear or greed is often read as a contrarian cue, but should never be the sole basis for a decision.",
    "市场动能": "Market Momentum",
    "标普500 相对125日均线": "S&P 500 vs. 125-day moving average",
    "股价强度": "Stock Price Strength",
    "创52周新高 vs 新低个股": "52-week highs vs. lows",
    "股价广度": "Stock Price Breadth",
    "麦克莱伦成交量总和指数": "McClellan Volume Summation Index",
    "看跌/看涨期权": "Put/Call Options",
    "5日 Put/Call 比率": "5-day Put/Call ratio",
    "市场波动": "Market Volatility",
    "VIX 及其50日均线": "VIX and its 50-day moving average",
    "避险需求": "Safe-Haven Demand",
    "股票 vs 国债 20日收益差": "20-day stock vs. Treasury return spread",
    "垃圾债需求": "Junk Bond Demand",
    "投资级 vs 垃圾债收益利差": "Investment-grade vs. junk-bond yield spread"
  };

  var HUB = {
    "数据中心 · The Data Center": "THE DATA CENTER",
    "今日": "Today's",
    "市场": "Markets",
    "，一页读尽": ", at a glance",
    "15 个自动更新的实时数据应用 ·": "15 auto-updating data apps ·",
    "宏观风险监测": "Macro Risk Monitor",
    "市场机制 · 7 大制度信号 · 跨资产": "Market regime · 7 signals · Cross-asset",
    "标普500热力图": "S&P 500 Heatmap",
    "按行业分块 · 按市值定面积 · 按当日涨跌上色": "Sector blocks · Sized by market cap · Colored by daily move",
    "全球市场行情": "Global Markets",
    "商品 · 指数 · 公司 · 外汇 · 加密 · 债券 · 逐项完整走势": "Commodities · indices · companies · FX · crypto · bonds",
    "全球大类资产收益率": "Global Asset Returns",
    "股市 · 商品 · 外汇 · 债券": "Equities · commodities · FX · bonds",
    "全球资产市值榜": "Global Assets by Market Cap",
    "不限品类 · 前 250 · 房产/国债/黄金/公司/加密": "All asset classes · Top 250 · property/Treasuries/gold/companies/crypto",
    "全球房价走势": "Global Home Prices",
    "主要国家 · 名义/实际同比 · 季度走势": "Major economies · Nominal/real YoY · Quarterly trends",
    "福布斯亿万富翁实时排行榜": "Forbes Real-Time Billionaires",
    "亿万富豪全榜 · 身价": "All billionaires · Net worth",
    "全球公司市值榜": "Global Companies by Market Cap",
    "全球 500 强 · 市值 · 股价": "Global top 500 · Market cap · Prices",
    "恐慌与贪婪指数": "Fear & Greed Index",
    "CNN Fear & Greed · 近一年走势": "CNN Fear & Greed · 1-year trend",
    "全球经济图谱": "World Economy Map",
    "各国经济指标地图": "Economic indicators by country",
    "超级投资者持仓": "Superinvestor Holdings",
    "13F · 60 位大佬 · 政治人物交易 · AAII": "13F · 60 investors · Political trades · AAII",
    "全球大模型评测榜": "Global AI Model Rankings",
    "LMArena Elo · LiveBench · 智能指数": "LMArena Elo · LiveBench · Intelligence Index",
    "全球大学排名 300 强": "Global University Rankings · Top 300",
    "QS · THE · ARWU · U.S. News 四榜合一": "QS · THE · ARWU · U.S. News combined",
    "全球专业与就业前景榜": "Majors & Career Outlook",
    "薪资 · 就业率 · 起薪 · AI 时代前景": "Pay · employment · starting salary · AI-era outlook",
    "全球经济日历": "Global Economic Calendar",
    "央行决议 · CPI · 非农": "Central banks · CPI · payrolls",
    "偏弱信号": "Weakest signals",
    /* 首屏导语被 <b> 拆成若干节点；标的名、人名、公司名按既有口径保持原文。 */
    "市场情绪 · Fear & Greed": "Market sentiment · Fear & Greed",
    "市场处于": "The market is in ",
    "恐惧": "Fear",
    "极度恐惧": "Extreme Fear",
    "中性": "Neutral",
    "贪婪": "Greed",
    "极度贪婪": "Extreme Greed",
    "区间。年初至今": " territory. Year to date, ",
    "领涨全球，": " leads globally and ",
    "领跌。": " lags.",
    "全球首富": "Richest person",
    "市值 #1": "Largest by market cap",
    "资产总市值": "Total asset market cap",
    "前 250 · 含房产/国债/黄金": "Top 250 · incl. property, sovereign debt and gold",
    "家成分股（共 503 个成分代码）": "constituents (503 tickers in total)",
    "项跨资产标的（另有公司榜、加密与美债曲线）":
      "cross-asset instruments (plus the company board, crypto and the Treasury curve)",
    "前 250 总市值": "Top 250 total market cap",
    "涨幅居首": "Biggest gain",
    "跌幅居首": "Biggest decline",
    "前 500 总市值": "Top 500 total market cap",
    "12 项指标 · 约 180 国/地区": "12 indicators · about 180 countries/regions",
    "央行基准利率": "Central bank policy rate",
    "AAII 情绪": "AAII sentiment",
    "综合第一": "Overall #1",
    "开源第一": "Top open-source",
    "QS/THE/ARWU/USN 平均位次": "Average rank across QS/THE/ARWU/USN",
    "薪资第一": "Highest pay",
    "AI 前景第一": "Best AI-era outlook",
    "人工智能与机器学习": "Artificial intelligence & machine learning",
    "美国金融风险监测": "U.S. Financial Risk Monitor",
    "金融压力 · 低于平均压力": "Financial stress · below average",
    "金融压力 · 高于平均压力": "Financial stress · above average",
    "金融压力 · 接近平均水平": "Financial stress · near average",
    "SOFR 隔夜利率": "SOFR overnight rate",
    "货币基金规模": "Money market fund assets",
    "各应用数据每日自动更新（来源 Yahoo Finance · CoinGecko · OECD · BIS · OFR · Forbes · CNN · Google News · World Bank · Forex Factory · QS · THE · ARWU · U.S. News · PayScale · NACE · BLS · WEF）。仅供参考，不构成建议。":
      "Every app refreshes daily (sources: Yahoo Finance · CoinGecko · OECD · BIS · OFR · Forbes · CNN · Google News · World Bank · Forex Factory · QS · THE · ARWU · U.S. News · PayScale · NACE · BLS · WEF). For reference only; not advice.",
    "数据中心是 Ooglex 所有实时数据应用的统一入口，把全球市场行情、大类资产收益率、福布斯亿万富翁实时排行榜、恐慌贪婪指数、全球经济图谱、经济日历等聚合在一页，每张卡片带实时小预览，数据每日自动更新，点击任意卡片进入完整页面。所有数据均来自公开第三方来源，仅供参考，不构成投资建议。":
      "The Data Center is the single entry point to every live-data app on Ooglex, gathering global markets, asset-class returns, the Forbes real-time billionaire ranking, the Fear & Greed Index, the world economy map and the economic calendar onto one page. Each card carries a live mini preview, the data refreshes daily, and clicking a card opens the full page. All data comes from public third-party sources and is for reference only; it is not investment advice.",
    "今日上涨": "Advancing today",
    "领涨": "Top gainer",
    "年初至今领涨": "YTD leader",
    "领跌": "Top decliner",
    "覆盖": "Coverage",
    "央行基准利率": "Policy rates",
    "薪资第一": "Highest pay",
    "AAII 情绪": "AAII sentiment",
    "看涨": "Bullish",
    "看跌": "Bearish",
    "等待首次数据更新": "Waiting for first data update"
  };

  var IDEAS = {
    "你的想法": "Your Thoughts",
    "登录后随时发布，发出即公开。任何人都能浏览。":
      "Post any time once signed in. Everything posted is public, and anyone can read it.",
    "正在确认登录状态…": "Checking your sign-in status…",
    "这个账户已被停用，无法发布。": "This account is suspended and cannot post.",
    "此刻在想什么？最多 500 字。": "What are you thinking? 500 characters max.",
    "想法正文": "Thought text",
    "发布": "Post",
    "最新想法": "Latest thoughts",
    "加载中…": "Loading…",
    "加载更多": "Load more",
    "隐私政策": "Privacy Policy",
    "← 返回 Ooglex": "← Back to Ooglex",
    "想法流任何人都能看，但发布需要登录。": "Anyone can read the feed, but posting requires signing in.",
    "前往登录或注册 →": "Sign in or register →"
  };

  function add(dst, src) { Object.keys(src).forEach(function (k) { dst[k] = src[k]; }); }
  var dict = {};
  add(dict, COMMON);
  if (path.indexOf("/apps/asset-tracker/") === 0) add(dict, ASSET);
  if (path.indexOf("/apps/companies/") === 0) add(dict, COMPANIES);
  if (path.indexOf("/apps/ai-rankings/") === 0) add(dict, AI);
  if (path.indexOf("/apps/university-rankings/") === 0) add(dict, UNIVERSITY);
  if (path.indexOf("/apps/econ-calendar/") === 0) add(dict, CALENDAR);
  if (path.indexOf("/apps/fear-greed/") === 0) add(dict, FEAR);
  if (path.indexOf("/apps/data-hub/") === 0) add(dict, HUB);
  if (path.indexOf("/apps/ideas/") === 0) add(dict, IDEAS);

  function regexTranslate(s) {
    var m;
    if ((m = /^数据加载失败：(.+)$/.exec(s))) return "Failed to load data: " + m[1];
    /* 尾巴上的相对时间也要一起翻。原先只翻前半截、把「12 小时前」原样带回，
       结果下一层（wave3）会再翻一次这个半成品，并把半成品记成它的「原文」——
       切回中文时 wave3 后还原，就把页面又改回了 "Live data · Updated 12 小时前"。 */
    if ((m = /^实时数据 · 更新于 (.+)$/.exec(s))) {
      var rel = m[1], rm;
      if ((rm = /^(\d+) 分钟前$/.exec(rel))) rel = rm[1] + " min ago";
      else if ((rm = /^(\d+) 小时前$/.exec(rel))) rel = rm[1] + " hr ago";
      else if ((rm = /^(\d+) 天前$/.exec(rel))) rel = rm[1] + " d ago";
      else if (rel === "刚刚") rel = "just now";
      return "Live data · Updated " + rel;
    }
    if ((m = /^更新于 (\d+) 分钟前$/.exec(s))) return "Updated " + m[1] + " min ago";
    if ((m = /^更新于 (\d+) 小时前$/.exec(s))) return "Updated " + m[1] + " hr ago";
    if ((m = /^更新于 (\d+) 天前$/.exec(s))) return "Updated " + m[1] + " d ago";
    // 来源行是「数据来源 <b>源名</b> · 数据日期 <b>日期</b> · 更新于 时间戳」，
    // <b> 把它切成好几个文本节点，整串的规则匹配不到，分隔符那两段要单独配。
    if (s === "· 数据日期") return "· Date";
    if ((m = /^· 更新于 (.+)$/.exec(s))) return "· Updated " + m[1];

    if (path.indexOf("/apps/asset-tracker/") === 0) {
      // 标的名在数据里只有中文（无 nameEn），按既有口径不翻，只翻包住它的固定部分。
      if ((m = /^(.+) · 现价 (\S+)$/.exec(s))) return m[1] + " · last " + m[2];
      if ((m = /^▲ Top gainer (.+)$/.exec(s))) return "▲ Top gainer " + m[1];
      if ((m = /^(.+) · (\d+) 项$/.exec(s))) return (dict[m[1]] || m[1]) + " · " + m[2] + " assets";
      if ((m = /^▲ 领涨 (.+)$/.exec(s))) return "▲ Top gainer " + m[1];
      if ((m = /^▼ 领跌 (.+)$/.exec(s))) return "▼ Top decliner " + m[1];
    }
    if (path.indexOf("/apps/companies/") === 0) {
      /* 行卡第二行是「🇺🇸美国 · 科技 · NVDA」这类 · 拼串，段数不定（非上市公司
         第三段是「上轮融资 May 2026」）。逐段查表，查不到原样留下。 */
      if (s.indexOf(" · ") > 0 && /[\u4e00-\u9fff]/.test(s)) {
        var segs = s.split(" · "), hit = false;
        var joined = segs.map(function (seg) {
          var flag = "", body = seg;
          var fm = /^([^\u4e00-\u9fffA-Za-z0-9]+)(.+)$/.exec(seg);
          if (fm) { flag = fm[1]; body = fm[2]; }
          if (dict[body]) { hit = true; return flag + dict[body]; }
          var lm = /^上轮融资 (.+)$/.exec(body);
          if (lm) { hit = true; return flag + "Last round " + lm[1]; }
          return seg;
        }).join(" · ");
        if (hit) return joined;
      }
      if ((m = /^前 (\d+) 总市值$/.exec(s))) return "Top " + m[1] + " total market cap";
      if ((m = /^(\d+) 上市 · (\d+) 未上市$/.exec(s))) return m[1] + " public · " + m[2] + " private";
      if ((m = /^▲ 今日领涨 (.+)$/.exec(s))) return "▲ Top gainer today " + m[1];
      if ((m = /^▼ 今日领跌 (.+)$/.exec(s))) return "▼ Top decliner today " + m[1];
    }
    if (path.indexOf("/apps/ai-rankings/") === 0) {
      // 厂商行是「🇨🇳 月之暗面 · 上下文 1M」：国旗与上下文长度原样带回，只查厂商名。
      if ((m = /^(\S+)\s+(.+?) · 上下文 (\S+)$/.exec(s))) {
        return m[1] + " " + (dict[m[2]] || m[2]) + " · Context " + m[3];
      }
      if ((m = /^Live data · Updated (\d+) 小时前$/.exec(s))) return "Live data · Updated " + m[1] + " hr ago";
      if ((m = /^Live data · Updated (\d+) 分钟前$/.exec(s))) return "Live data · Updated " + m[1] + " min ago";
      if ((m = /^Live data · Updated (\d+) 天前$/.exec(s))) return "Live data · Updated " + m[1] + " d ago";
      if ((m = /^综合 · 基于 (\d+) 榜$/.exec(s))) return "Composite · " + m[1] + " rankings";
      if ((m = /^覆盖 (\d+) 个模型$/.exec(s))) return "Coverage · " + m[1] + " models";
      if ((m = /^中国模型 (\d+) 个$/.exec(s))) return "China-based models · " + m[1];
      if ((m = /^上下文 (.+)$/.exec(s))) return "Context · " + m[1];
      if ((m = /^(\d+) 小时前$/.exec(s))) return m[1] + " hr ago";
    }
    if (path.indexOf("/apps/university-rankings/") === 0) {
      // 国家/地区快捷筛选条：「🇺🇸 美国 50」。国旗与计数原样带回，只查国名。
      if ((m = /^(\S+)\s+([^\s\d]+)(?:\s+(\d+))?$/.exec(s)) && dict[m[2]]) {
        return m[1] + " " + dict[m[2]] + (m[3] ? " " + m[3] : "");
      }
      if ((m = /^均位 · (\d+) 榜$/.exec(s))) return "Average · " + m[1] + " rankings";
      if ((m = /^四大榜单权威整理 · (\d{4}) 版$/.exec(s))) return "Four-source ranking · " + m[1] + " edition";
      if ((m = /^覆盖 (\d+) 所$/.exec(s))) return "Coverage · " + m[1] + " universities";
      if ((m = /^上榜 (\d+) 个国家\/地区$/.exec(s))) return "Countries/regions · " + m[1];
      if ((m = /^中国高校 (\d+) 所$/.exec(s))) return "China-based universities · " + m[1];
    }
    if (path.indexOf("/apps/econ-calendar/") === 0) {
      if ((m = /^全部 · (\d+)$/.exec(s))) return "All · " + m[1];
      if ((m = /^🔴 高影响 · (\d+)$/.exec(s))) return "🔴 High · " + m[1];
      if ((m = /^🟠 中 · (\d+)$/.exec(s))) return "🟠 Medium · " + m[1];
      if ((m = /^⚪ 低 · (\d+)$/.exec(s))) return "⚪ Low · " + m[1];
      if ((m = /^本周 (.+)（UTC） · 共 (\d+) 项$/.exec(s))) return "Week of " + m[1] + " (UTC) · " + m[2] + " events";
      if ((m = /^(\d+) 分钟后$/.exec(s))) return "in " + m[1] + " min";
      if ((m = /^(\d+) 小时后$/.exec(s))) return "in " + m[1] + " hr";
      if ((m = /^(\d+) 天后$/.exec(s))) return "in " + m[1] + " d";
      if ((m = /^(\d+)月(\d+)日 (周[日一二三四五六])( · 今天)?$/.exec(s))) return m[1] + "/" + m[2] + " " + (dict[m[3]] || m[3]) + (m[4] ? " · Today" : "");
      if ((m = /^(高|中|低|假日)影响$/.exec(s))) return ({"高":"High impact","中":"Medium impact","低":"Low impact","假日":"Holiday"})[m[1]];
    }
    if (path.indexOf("/apps/data-hub/") === 0) {
      // 预览卡里的组合串：人名/公司名/标的名与数字原样带回，只翻固定部分。
      if ((m = /^(\d+) 位富豪总财富$/.exec(s))) return "Combined wealth of " + m[1] + " billionaires";
      if ((m = /^综合前 (\d+)$/.exec(s))) return "Overall top " + m[1];
      if ((m = /^看涨 (\S+)$/.exec(s))) return "Bullish " + m[1];
      if ((m = /^(\S+) · (\d+) 只持仓$/.exec(s))) return m[1] + " \u00B7 " + m[2] + " holdings";
      if ((m = /^看跌 (\S+)$/.exec(s))) return "Bearish " + m[1];
      if ((m = /^实际利率 (\S+) · 市场广度 (\S+)$/.exec(s))) return "Real rates " + m[1] + " \u00B7 Breadth " + m[2];
      if ((m = /^预测 (\S+) · 前值 (\S+) · 本周 (\d+) 项$/.exec(s))) {
        return "Forecast " + m[1] + " \u00B7 Previous " + m[2] + " \u00B7 " + m[3] + " events this week";
      }
      if ((m = /^(.+) 环比$/.exec(s))) return m[1] + " MoM";
      if ((m = /^(.+) 同比$/.exec(s))) return m[1] + " YoY";
    }
    if (path.indexOf("/apps/fear-greed/") === 0) {
      if ((m = /^综合读数（0–100）· 数据日期 (.+)$/.exec(s))) return "Composite reading (0–100) · Date " + m[1];
      if ((m = /^(\d+) · (极度恐惧|恐惧|中性|贪婪|极度贪婪)$/.exec(s))) return m[1] + " · " + (dict[m[2]] || m[2]);
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

  function specialEnglish() {
    if (path.indexOf("/apps/companies/") === 0) {
      document.querySelectorAll(".rowcard .nm").forEach(function (nm) {
        var en = nm.querySelector(".en"), pri = nm.querySelector(".pri");
        if (!en || !en.textContent.trim()) return;
        rememberHtml(nm);
        var label = en.textContent.trim();
        nm.textContent = label;
        if (pri) { var b = pri.cloneNode(true); b.textContent = "Private"; nm.appendChild(b); }
        /* logo 的 alt 存的是公司中文名，读屏用户此前读到的还是中文。英文名在 .en 里
           现成有，一并换掉；走 attrOrig 记账，切回中文时和其他属性一起还原。 */
        var card = nm.closest && nm.closest(".rowcard");
        var img = card && card.querySelector("img");
        if (img && img.getAttribute("alt") && img.getAttribute("alt") !== label) {
          var saved = attrOrig.get(img);
          if (!saved) { saved = {}; attrOrig.set(img, saved); attrTouched.push(img); }
          if (!("alt" in saved)) saved.alt = img.getAttribute("alt");
          img.setAttribute("alt", label);
        }
      });
    }
    if (path.indexOf("/apps/university-rankings/") === 0) {
      var zhToEnName = {};
      document.querySelectorAll(".rowcard").forEach(function (card) {
        var nm = card.querySelector(".nm"), meta = card.querySelector(".meta");
        if (!nm || !meta) return;
        var parts = meta.textContent.split(" · ");
        if (parts.length < 2) return;
        var enName = parts[parts.length - 1].trim();
        if (!/[A-Za-z]/.test(enName)) return;
        rememberHtml(nm); rememberHtml(meta);
        zhToEnName[nm.textContent.trim()] = enName;
        nm.textContent = enName;
        var left = parts[0].trim();
        /* 这里是子串替换，必须长键优先：按插入序走的话「中国」会先命中「中国香港」，
           替出「China香港」这种半中半英的地名（实测过）。长键先替就不会被短键截胡。 */
        UNIVERSITY_KEYS_BY_LENGTH.forEach(function (zh) {
          if (left.indexOf(zh) >= 0 && UNIVERSITY[zh]) left = left.replace(zh, UNIVERSITY[zh]);
        });
        meta.textContent = left;
      });
      /* 「综合第一」KPI 里只有学校中文名，没有英文兄弟节点；借上面行卡片建的
         中→英映射把它换掉，换不到就保持原文，不臆造校名。 */
      document.querySelectorAll("#summary b").forEach(function (b) {
        var en = zhToEnName[b.textContent.trim()];
        if (!en) return;
        rememberHtml(b);
        b.textContent = en;
      });
    }
    if (path.indexOf("/apps/econ-calendar/") === 0) {
      document.querySelectorAll(".ev .nm").forEach(function (box) {
        var zh = box.querySelector(".t"), en = box.querySelector(".en");
        if (!zh || !en || !en.textContent.trim()) return;
        rememberHtml(box);
        box.innerHTML = "<div class='t'>" + en.textContent.trim().replace(/[&<>]/g, function (c) { return ({"&":"&amp;","<":"&lt;",">":"&gt;"})[c]; }) + "</div>";
      });
    }
  }

  function walk(scope) {
    var base = scope && scope.nodeType ? scope : document.body;
    if (!base) return;
    if (base.nodeType === 3) { translateText(base); return; }
    if (base.nodeType === 1) translateAttrs(base);
    /* 和 i18n.js 同理：specialEnglish 对整块元素做 innerHTML 备份，必须跑在逐节点
       翻译**之前**，否则它备下来的「原文」已经是英文。公司榜的「未上市」徽标就在
       .nm 里，先翻后备份的话，切回中文时它会停在 "Private"。 */
    specialEnglish();
    var w = document.createTreeWalker(base, NodeFilter.SHOW_TEXT, null), n;
    while ((n = w.nextNode())) translateText(n);
    var els = base.querySelectorAll ? base.querySelectorAll("[placeholder],[aria-label],[title],[alt]") : [];
    for (var i = 0; i < els.length; i++) translateAttrs(els[i]);
  }

  function restore() {
    textTouched.forEach(function (n) { if (n && textOrig.has(n)) n.nodeValue = textOrig.get(n); });
    attrTouched.forEach(function (el) {
      var saved = attrOrig.get(el); if (!el || !saved) return;
      Object.keys(saved).forEach(function (a) { el.setAttribute(a, saved[a]); });
    });
    htmlTouched.forEach(function (el) { if (el && htmlOrig.has(el)) el.innerHTML = htmlOrig.get(el); });
    textTouched = []; attrTouched = []; htmlTouched = [];
    textOrig = new WeakMap(); attrOrig = new WeakMap(); htmlOrig = new WeakMap();
  }

  var titleOrig = document.title;
  var TITLES = {
    "/apps/asset-tracker/": "Global Asset Returns · Daily Tracker",
    "/apps/companies/": "Global Companies by Market Cap",
    "/apps/ai-rankings/": "Global AI Model Rankings",
    "/apps/university-rankings/": "Global University Rankings · Top 300",
    "/apps/econ-calendar/": "Global Economic Calendar",
    "/apps/fear-greed/": "Market Fear & Greed Index",
    "/apps/data-hub/": "Data Center · Live Data Apps"
  };
  /* pending 原本是「本帧已排过队就直接 return」——但 return 掉的那一批 records
     **就此丢了**，不会被后面的 rAF 处理。数据枢纽这类一屏拉十几个 data.json、
     逐卡渲染的页面，一帧里能来好几批 mutation，于是「领涨」「今日上涨」这些
     字典里明明有的词条永远翻不到。改成先把 records 攒起来再统一处理：
     既保留按帧合并的原意，又一条都不丢。 */

  var observer = null, pending = false, queued = [];
  function watch() {
    if (observer || typeof MutationObserver === "undefined") return;
    observer = new MutationObserver(function (recs) {
      if (current !== "en") return;

      queued = queued.concat(Array.prototype.slice.call(recs));

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
    if (current === "en") {
      walk(document.body);
      if (TITLES[path]) document.title = TITLES[path];
      watch();
    } else {
      restore();
      document.title = titleOrig;
    }
  }

  function boot() { apply(readLang()); }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();

  document.addEventListener("ooglex:languagechange", function (e) {
    apply(e && e.detail && e.detail.language === "en" ? "en" : "zh");
  });

  window.addEventListener("storage", function (e) {
    if (e.key !== KEY || window.OoglexI18n) return;
    apply(e.newValue === "en" ? "en" : "zh");
  });
})();
