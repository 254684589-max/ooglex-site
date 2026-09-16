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
    "实时聚合 · 每日更新": "Live aggregate · Updated daily"
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
    "示例数据 · 待刷新": "Sample data · Awaiting refresh"
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
    "自选": "Watch"
  };

  var dict = {};
  copy(dict, COMMON);
  if (path.indexOf("/apps/asset-ranking/") === 0) copy(dict, ASSET_RANKING);
  if (path.indexOf("/apps/house-prices/") === 0) copy(dict, HOUSE);
  if (path.indexOf("/apps/world-economy/") === 0) copy(dict, WORLD);
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
    if ((m = /^单位 (.*)$/.exec(s))) return "Unit " + m[1];
    if ((m = /^截至 (.+)$/.exec(s))) return "As of " + m[1];
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

  var observer = null, pending = false;
  function watch() {
    if (observer || typeof MutationObserver === "undefined") return;
    observer = new MutationObserver(function (records) {
      if (current !== "en" || pending) return;
      pending = true;
      requestAnimationFrame(function () {
        pending = false;
        records.forEach(function (r) {
          if (r.type === "characterData") translateText(r.target);
          else Array.prototype.forEach.call(r.addedNodes || [], walk);
        });
      });
    });
    observer.observe(document.documentElement, { subtree:true, childList:true, characterData:true });
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
