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
  var ATTRS = ["placeholder", "aria-label", "title"];

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
    "示例数据 · 待每日任务刷新": "Sample data · Awaiting daily refresh"
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
    "字节跳动": "ByteDance"
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
    "以色列": "Israel"
  };

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
    "站主工具": "Owner tools",
    "被举报且仍然公开的想法会列在这里。": "Thoughts that were reported and are still public are listed here.",
    "查看被举报的想法": "Review reported thoughts",
    "最新想法": "Latest thoughts",
    "加载中…": "Loading…",
    "加载更多": "Load more",
    "隐私政策": "Privacy Policy",
    "← 返回 Ooglex": "← Back to Ooglex",
    "想法流任何人都能看，但发布需要登录。": "Anyone can read the feed, but posting requires signing in.",
    "前往登录或注册 →": "Sign in or register →",
    /* 页脚这一条的文本节点末尾连着分隔符「·」（后面才是隐私政策链接），
       整个节点必须逐字节入典，只写句子是匹配不到的。 */
    "想法由发布者本人负责，不代表 Ooglex 立场。看到违规内容请点「举报」。\n    ·":
      "Posts are the responsibility of whoever wrote them and do not represent Ooglex. Use “Report” if you see something that breaks the rules.\n    ·"
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
    if ((m = /^实时数据 · 更新于 (.+)$/.exec(s))) return "Live data · Updated " + m[1];
    if ((m = /^更新于 (\d+) 分钟前$/.exec(s))) return "Updated " + m[1] + " min ago";
    if ((m = /^更新于 (\d+) 小时前$/.exec(s))) return "Updated " + m[1] + " hr ago";
    if ((m = /^更新于 (\d+) 天前$/.exec(s))) return "Updated " + m[1] + " d ago";
    // 来源行是「数据来源 <b>源名</b> · 数据日期 <b>日期</b> · 更新于 时间戳」，
    // <b> 把它切成好几个文本节点，整串的规则匹配不到，分隔符那两段要单独配。
    if (s === "· 数据日期") return "· Date";
    if ((m = /^· 更新于 (.+)$/.exec(s))) return "· Updated " + m[1];

    if (path.indexOf("/apps/asset-tracker/") === 0) {
      if ((m = /^(.+) · (\d+) 项$/.exec(s))) return (dict[m[1]] || m[1]) + " · " + m[2] + " assets";
      if ((m = /^▲ 领涨 (.+)$/.exec(s))) return "▲ Top gainer " + m[1];
      if ((m = /^▼ 领跌 (.+)$/.exec(s))) return "▼ Top decliner " + m[1];
    }
    if (path.indexOf("/apps/companies/") === 0) {
      if ((m = /^前 (\d+) 总市值$/.exec(s))) return "Top " + m[1] + " total market cap";
      if ((m = /^(\d+) 上市 · (\d+) 未上市$/.exec(s))) return m[1] + " public · " + m[2] + " private";
      if ((m = /^▲ 今日领涨 (.+)$/.exec(s))) return "▲ Top gainer today " + m[1];
      if ((m = /^▼ 今日领跌 (.+)$/.exec(s))) return "▼ Top decliner today " + m[1];
    }
    if (path.indexOf("/apps/ai-rankings/") === 0) {
      if ((m = /^综合 · 基于 (\d+) 榜$/.exec(s))) return "Composite · " + m[1] + " rankings";
      if ((m = /^覆盖 (\d+) 个模型$/.exec(s))) return "Coverage · " + m[1] + " models";
      if ((m = /^中国模型 (\d+) 个$/.exec(s))) return "China-based models · " + m[1];
      if ((m = /^上下文 (.+)$/.exec(s))) return "Context · " + m[1];
      if ((m = /^(\d+) 小时前$/.exec(s))) return m[1] + " hr ago";
    }
    if (path.indexOf("/apps/university-rankings/") === 0) {
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
      });
    }
    if (path.indexOf("/apps/university-rankings/") === 0) {
      document.querySelectorAll(".rowcard").forEach(function (card) {
        var nm = card.querySelector(".nm"), meta = card.querySelector(".meta");
        if (!nm || !meta) return;
        var parts = meta.textContent.split(" · ");
        if (parts.length < 2) return;
        var enName = parts[parts.length - 1].trim();
        if (!/[A-Za-z]/.test(enName)) return;
        rememberHtml(nm); rememberHtml(meta);
        nm.textContent = enName;
        var left = parts[0].trim();
        Object.keys(UNIVERSITY).forEach(function (zh) {
          if (left.indexOf(zh) >= 0 && UNIVERSITY[zh]) left = left.replace(zh, UNIVERSITY[zh]);
        });
        meta.textContent = left;
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
    var w = document.createTreeWalker(base, NodeFilter.SHOW_TEXT, null), n;
    while ((n = w.nextNode())) translateText(n);
    var els = base.querySelectorAll ? base.querySelectorAll("[placeholder],[aria-label],[title]") : [];
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

  var observer = null, pending = false;
  function watch() {
    if (observer || typeof MutationObserver === "undefined") return;
    observer = new MutationObserver(function (recs) {
      if (current !== "en" || pending) return;
      pending = true;
      requestAnimationFrame(function () {
        pending = false;
        recs.forEach(function (r) {
          if (r.type === "characterData") translateText(r.target);
          else Array.prototype.forEach.call(r.addedNodes || [], function (n) { walk(n); });
        });
        specialEnglish();
      });
    });
    observer.observe(document.documentElement, { subtree:true, childList:true, characterData:true });
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
