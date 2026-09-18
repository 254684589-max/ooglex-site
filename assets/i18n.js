/* Ooglex shared subpage i18n layer.
   Reads the homepage preference from localStorage["ooglex.language"].
   This file intentionally translates only reviewed UI strings. Data-source names,
   legal attributions and unmapped research prose stay in their original language. */
(function () {
  "use strict";

  var KEY = "ooglex.language";
  var root = document.documentElement;
  var path = (location.pathname || "/").replace(/\/index\.html$/, "/");
  var current = "zh";

  function norm(v) { return v === "en" ? "en" : "zh"; }
  function read() {
    try { return norm(localStorage.getItem(KEY)); } catch (e) { return "zh"; }
  }
  function write(v) {
    try { localStorage.setItem(KEY, norm(v)); } catch (e) {}
  }

  var COMMON = {
    "← 返回首页": "← Back to Home",
    "← 返回": "← Back",
    "返回首页": "Back to Home",
    "数据来源": "Data Sources",
    "数据来源与许可": "Data Sources & Licenses",
    "关闭": "Close",
    "加载中": "Loading",
    "正在加载…": "Loading…",
    "重新加载": "Reload",
    "暂无数据": "No data",
    "标准": "Standard",
    "专业": "Pro",
    "搜索": "Search",
    "上一页": "Previous page",
    "下一页": "Next page",
    "跳至": "Go to",
    "邮箱": "Email",
    "密码": "Password",
    "昵称": "Display name",
    "状态": "Status",
    "会员": "Plan"
  };

  var BILLIONAIRES = {
    "🏆 福布斯亿万富翁实时排行榜": "🏆 Forbes Real-Time Billionaires",
    "全球全部亿万富豪 · 身价与当日变动 · 每日自动更新": "All global billionaires · Net worth and daily moves · Updated daily",
    "按身价": "Net Worth",
    "今日涨幅": "Top Gainers",
    "今日跌幅": "Top Decliners",
    "在全部亿万富豪中搜索姓名（中 / 英）…": "Search all billionaires by name…",
    "实时榜 · 每日自动更新": "Live ranking · Updated daily",
    "示例数据 · 待每日任务刷新": "Sample data · Waiting for daily refresh",
    "没有匹配的人物，换个关键词试试 🙂": "No matching people. Try another keyword 🙂",
    "分页导航": "Pagination",
    "关于本页数据": "About this data",
    "本页追踪全球全部亿万富豪（净值 ≥ 10 亿美元，当前约 3400 位）及其当日变动，数据来源 Forbes 实时富豪榜，每日自动更新，实际人数以页面顶部显示的当日数字为准。身价以美元计，主要随其持有的上市公司股价波动，因此「当日变动」更多反映市场行情，而非真实可动用现金。多数人物提供中文名对照，少数无法确认对应汉字的（多为中日韩越等汉字圈人物的罗马化拼写）保留福布斯英文原名，不做音译臆造。榜单仅供了解全球财富格局参考。": "This page tracks all global billionaires with net worth of at least US$1 billion (currently about 3,400 people) and their daily changes. Data comes from the Forbes real-time billionaire ranking and is updated daily; the live count shown above is authoritative for each update. Net worth is shown in US dollars and moves mainly with the market value of listed-company holdings, so daily changes reflect market pricing rather than immediately spendable cash. The ranking is provided for research on global wealth distribution."
  };

  var MACRO = {
    "黄河浮桥远航基金 · VOYAGER FUND": "VOYAGER FUND",
    "宏观风险监测": "MACRO RISK MONITOR",
    "制度信号": "Regime Signals",
    "Regime 时光机": "Regime Time Machine",
    "◂ 拖动时间轴 · 点击下方危机事件自动重放 ▸": "◂ Drag the timeline · click a crisis below to replay ▸",
    "历史机制为按当前方法学的周频回溯（滚动 2 年分位 · 同权重 · EMA 平滑），非当年实时发布值。数据每日自动重建、曲线右端随之延伸；未标注的连续压力段（读数 ≤35 持续两周以上）会自动画出 ⚠ 预警红区，用于监视未来危机。": "Historical regime readings are weekly backtests using the current methodology (rolling 2-year percentiles · equal weights · EMA smoothing), not values published in real time at the time. The series is rebuilt daily and extends automatically; unlabelled stress runs (score ≤35 for at least two weeks) are marked as warning zones for monitoring future crises.",
    "宏观管道": "Macro Plumbing",
    "市场异动": "Market Mutations",
    "数据更新 · —": "Updated · —",
    "数据源 ·": "Sources ·",
    "仅供研究，非投资建议": "For research only, not investment advice",
    "市场机制 · OVERALL REGIME": "Overall Regime",
    "◂ 收紧 · 风险": "◂ Tightening · Risk",
    "收紧 · 风险": "Tightening · Risk",
    "中性偏紧": "Neutral / Tight",
    "中性": "Neutral",
    "中性偏松": "Neutral / Easy",
    "宽松 · 支持": "Easing · Support",
    "宽松 · 支持 ▸": "Easing · Support ▸",
    "示例数据 · SAMPLE": "Sample Data · SAMPLE",
    "今日暂无显著异动。": "No significant market mutations today.",
    "流动性": "Liquidity",
    "波动率": "Volatility",
    "期限溢价": "Term Premium",
    "实际利率": "Real Rate",
    "信用利差": "Credit Spread",
    "增长动能": "Growth Momentum",
    "美元汇率": "US Dollar",
    "市场广度": "Market Breadth",
    "利率走廊": "Rate Corridor",
    "联储流动性": "Fed Liquidity",
    "实际利率与通胀预期": "Real Rates & Inflation Expectations",
    "期限结构与利差": "Term Structure & Spreads",
    "金融压力": "Financial Stress",
    "融资压力": "Funding Stress",
    "商品比率": "Commodity Ratios",
    "波动率全景": "Volatility Dashboard"
  };

  var TERMINAL = {
    "全球监控": "Global Monitor",
    "全球市场监控": "Global Market Monitor",
    "相关功能菜单 ⌄": "Related Functions ⌄",
    "⌗ 功能目录": "⌗ Function Directory",
    "输入 HELP 看用法": "Type HELP for commands",
    "输入助记符 / 代码后回车 —— 例：SPX 定位行、CRVE 曲线、DESC 证券描述、FDIR 功能目录（按 / 聚焦）": "Enter mnemonic / ticker and press Enter — e.g. SPX row, CRVE curve, DESC security, FDIR directory (press / to focus)",
    "全球股指 Global Equities": "Global Equities",
    "美债利率 US Rates": "US Rates",
    "外汇 FX": "FX",
    "报价": "Quotes",
    "交叉汇率": "Cross Rates",
    "商品 Commodities": "Commodities",
    "宏观风险监测 Macro / Risk Monitor": "Macro / Risk Monitor",
    "收益率曲线 Yield Curve": "Yield Curve",
    "当前形态": "Current Curve",
    "随时间": "Over Time",
    "期限价差历史": "Spread History",
    "主权利差 Sovereign Spreads": "Sovereign Spreads",
    "相对基准": "vs Benchmark",
    "利差历史": "Spread History",
    "基准国": "Benchmark Country",
    "国家": "Country",
    "收益率": "Yield",
    "利差": "Spread",
    "较前一观测": "vs Previous",
    "数据日": "Date",
    "分位/Z": "Percentile/Z",
    "地缘风险定价 Geopolitical Risk": "Geopolitical Risk",
    "功能快捷键": "Function shortcuts",
    "后退": "Back",
    "前进": "Forward",
    "外汇视图": "FX view",
    "曲线视图": "Curve view",
    "主权利差视图": "Sovereign spread view",
    "风险信号历史分位": "Risk signal historical percentile",
    "美债收益率曲线": "US Treasury yield curve",
    "主权利差历史": "Sovereign spread history"
  };

  var SUPPLY = {
    "全球产业链": "Global Supply Chain",
    "查公司：代码、中文名或英文名（如 TSM / 台积电 / Apple）": "Find a company: ticker or name (e.g. TSM / Apple)",
    "查找公司": "Find company",
    "页内区块导航": "Page sections",
    "数据范围声明": "Data coverage statement",
    "关于本页数据范围": "About Data Coverage",
    "本板块只收录有公开出处的信息，": "This section includes only information with public sources; it is ",
    "不是完整供应链": "not a complete supply chain",
    "按板块的覆盖情况": "Coverage by Sector",
    "为什么有的公司有数据、有的没有": "Why some companies have data and others do not",
    "细分产业链": "Industry Chains",
    "按 SEC 行业码（SIC）展开，宽度即家数 · 点一格只看该组公司": "Expanded by SEC SIC code; width represents company count · click a segment to filter",
    "按一级产业链筛选": "Filter by primary industry chain",
    "本链的上下游": "Upstream and downstream for this chain",
    "链外环节 · 不在实物流转链条上": "Enabling layers · outside the physical flow chain",
    "真实流向": "Observed Flows",
    "各环节的公司 → 全球冶炼厂所在国别 · 带子宽度是实测关系条数": "Companies by stage → countries hosting global smelters · band width represents observed relationship count",
    "关系流向": "Relationship flows",
    "上游集中度": "Upstream Concentration",
    "同一家冶炼厂被多少家申报人共同列入 · 全部来自申报名单，不含推断": "How many filers list the same smelter · based entirely on disclosed lists, with no inference"
  };

  var ACCOUNT = {
    "账户 · Ooglex": "Account · Ooglex",
    "登录你的研究终端": "Sign in to your research terminal",
    "支持邮箱注册、登录、找回密码，以及 Free / Pro 权限识别。": "Email sign-up, sign-in, password recovery, and Free / Pro access recognition.",
    "尚未连接": "Not connected",
    "账户前端已就位": "Account frontend is ready",
    "创建并连接 Supabase 项目后即可启用真实账户系统。": "Connect a Supabase project to enable the live account system.",
    "前端只允许放 Publishable Key，禁止放 service_role、数据库密码或邮件服务密钥。": "Only a Publishable Key may be used in the frontend. Never expose service_role, database passwords, or email-service secrets.",
    "登录": "Sign in",
    "注册": "Register",
    "忘记密码": "Forgot password",
    "昵称（可选）": "Display name (optional)",
    "设置新密码": "Set a new password",
    "新密码": "New password",
    "更新密码": "Update password",
    "已登录": "Signed in",
    "账户中心": "Account Center",
    "未设置": "Not set",
    "退出登录": "Sign out",
    "账户系统 Beta · Ooglex": "Account System Beta · Ooglex"
  };

  function copy(dst, src) {
    Object.keys(src).forEach(function (k) { dst[k] = src[k]; });
  }
  var dict = {};
  copy(dict, COMMON);
  if (path.indexOf("/apps/billionaires/") === 0) copy(dict, BILLIONAIRES);
  if (path.indexOf("/apps/macro-radar/") === 0) copy(dict, MACRO);
  if (path.indexOf("/apps/finance-terminal/") === 0) copy(dict, TERMINAL);
  if (path.indexOf("/apps/supply-chain/") === 0) copy(dict, SUPPLY);
  if (path.indexOf("/account/") === 0) copy(dict, ACCOUNT);

  var textOrig = new WeakMap(), textTouched = [];
  var attrOrig = new WeakMap(), attrTouched = [];
  var htmlOrig = new WeakMap(), htmlTouched = [];
  var ATTRS = ["placeholder", "aria-label", "title"];

  function regexTranslate(s) {
    var m;
    if (path.indexOf("/apps/billionaires/") === 0) {
      if ((m = /^(\d+)岁$/.exec(s))) return m[1] + " yrs";
      if ((m = /^第 ([\d,]+) – ([\d,]+) 条 · 共搜到 ([\d,]+) 人$/.exec(s))) return "Results " + m[1] + "–" + m[2] + " · " + m[3] + " people found";
      if ((m = /^第 ([\d,]+) – ([\d,]+) 名 · 共 ([\d,]+) 人$/.exec(s))) return "Ranks " + m[1] + "–" + m[2] + " · " + m[3] + " people";
      if ((m = /^第 ([\d,]+) 页$/.exec(s))) return "Page " + m[1];
      if ((m = /^([\d,]+) 位亿万富豪 总财富$/.exec(s))) return m[1] + " billionaires · Total wealth";
      if ((m = /^▲ 今日领涨 (.+)$/.exec(s))) return "▲ Top gainer today " + m[1];
      if ((m = /^▼ 今日领跌 (.+)$/.exec(s))) return "▼ Top decliner today " + m[1];
    }
    if (path.indexOf("/apps/macro-radar/") === 0) {
      if ((m = /^数据更新 · (.+)$/.exec(s))) return "Updated · " + m[1];
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
    var a = raw.indexOf(s);
    node.nodeValue = (a >= 0 ? raw.slice(0, a) : "") + out + (a >= 0 ? raw.slice(a + s.length) : "");
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

  function specialEnglish(scope) {
    if (path.indexOf("/apps/billionaires/") === 0) {
      var names = (scope.querySelectorAll ? scope : document).querySelectorAll(".nm");
      for (var i = 0; i < names.length; i++) {
        var nm = names[i], en = nm.querySelector(".en");
        if (!en || !en.textContent.trim()) continue;
        if (!htmlOrig.has(nm)) { htmlOrig.set(nm, nm.innerHTML); htmlTouched.push(nm); }
        nm.textContent = en.textContent.trim();
      }
    }
    if (path.indexOf("/apps/macro-radar/") === 0) {
      var cn = document.querySelector(".head h1 .cn"), enTitle = document.querySelector(".head h1 .en");
      if (cn) cn.style.display = "none";
      if (enTitle) { enTitle.style.marginLeft = "0"; enTitle.style.fontSize = "2.5rem"; enTitle.style.fontWeight = "800"; }
      var sigs = document.querySelectorAll(".sig");
      for (var j = 0; j < sigs.length; j++) {
        var se = sigs[j].querySelector(".r1 .en"), sh = sigs[j].querySelector("h3");
        if (se && sh && se.textContent.trim()) {
          if (!htmlOrig.has(sh)) { htmlOrig.set(sh, sh.innerHTML); htmlTouched.push(sh); }
          sh.textContent = se.textContent.trim();
          se.style.display = "none";
        }
      }
      var cats = document.querySelectorAll(".mcat .mhead");
      for (var k = 0; k < cats.length; k++) {
        var ce = cats[k].querySelector(".en"), cb = cats[k].querySelector("b");
        if (ce && cb && ce.textContent.trim()) {
          if (!htmlOrig.has(cb)) { htmlOrig.set(cb, cb.innerHTML); htmlTouched.push(cb); }
          cb.textContent = ce.textContent.trim();
          ce.style.display = "none";
        }
      }
    }
  }

  function walk(scope) {
    var base = scope && scope.nodeType ? scope : document.body;
    if (!base) return;
    if (base.nodeType === 3) { translateText(base); return; }
    if (base.nodeType === 1) translateAttrs(base);
    var w = document.createTreeWalker(base, NodeFilter.SHOW_TEXT, null);
    var n;
    while ((n = w.nextNode())) translateText(n);
    var els = base.querySelectorAll ? base.querySelectorAll("[placeholder],[aria-label],[title]") : [];
    for (var i = 0; i < els.length; i++) translateAttrs(els[i]);
    specialEnglish(base);
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
    if (path.indexOf("/apps/macro-radar/") === 0) {
      var cn = document.querySelector(".head h1 .cn"), enTitle = document.querySelector(".head h1 .en");
      if (cn) cn.style.display = "";
      if (enTitle) { enTitle.style.marginLeft = "10px"; enTitle.style.fontSize = "1.05rem"; enTitle.style.fontWeight = "600"; }
      document.querySelectorAll(".sig .r1 .en,.mcat .mhead .en").forEach(function (el) { el.style.display = ""; });
    }
  }

  var metaOriginal = null;
  function translateMeta() {
    if (!metaOriginal) {
      metaOriginal = {
        title: document.title,
        desc: (document.querySelector('meta[name="description"]') || {}).content || ""
      };
    }
    var titles = {
      "/apps/billionaires/": "Forbes Real-Time Billionaires · Live Net Worth Ranking",
      "/apps/macro-radar/": "Macro Risk Monitor · Daily Market Regime Dashboard",
      "/apps/finance-terminal/": "Ooglex Financial Terminal · Global Market Monitor",
      "/apps/supply-chain/": "Global Supply Chain · Industry Chain Map",
      "/account/": "Account · Ooglex"
    };
    if (titles[path]) document.title = titles[path];
  }
  function restoreMeta() { if (metaOriginal) document.title = metaOriginal.title; }

  var observer = null, pending = false;
  function watch() {
    if (observer || typeof MutationObserver === "undefined") return;
    observer = new MutationObserver(function (recs) {
      if (current !== "en" || pending) return;
      pending = true;
      requestAnimationFrame(function () {
        pending = false;
        for (var i = 0; i < recs.length; i++) {
          var r = recs[i];
          if (r.type === "characterData") translateText(r.target);
          else for (var j = 0; j < r.addedNodes.length; j++) walk(r.addedNodes[j]);
        }
        specialEnglish(document);
      });
    });
    observer.observe(document.documentElement, { subtree:true, childList:true, characterData:true });
  }

  function apply(lang, persist) {
    current = norm(lang);
    if (persist) write(current);
    root.setAttribute("data-lang", current);
    root.setAttribute("lang", current === "en" ? "en" : "zh-CN");
    if (current === "en") { walk(document.body); translateMeta(); watch(); }
    else { restore(); restoreMeta(); }
    try { document.dispatchEvent(new CustomEvent("ooglex:languagechange", { detail:{ language:current } })); } catch (e) {}
    return current;
  }

  window.OoglexI18n = {
    getLanguage: function () { return current; },
    setLanguage: function (lang) { return apply(lang, true); },
    toggle: function () { return apply(current === "en" ? "zh" : "en", true); },
    translateNow: function () { if (current === "en") walk(document.body); }
  };

  function boot() { apply(read(), false); }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();

  window.addEventListener("storage", function (e) {
    if (e.key === KEY) apply(e.newValue, false);
  });
})();
