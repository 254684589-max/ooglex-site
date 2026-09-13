/* ===========================================================================
   OOGLEX 功能注册表 · Function Registry
   ---------------------------------------------------------------------------
   这是「把终端当成长期工程」的骨架：加一个金融功能 = 在 FUNCTIONS 里加一条记录。
   彩色功能键条、功能目录页、命令行解析、相关功能菜单，全部从这张表生成，
   没有任何一处把功能名写死在 HTML 里。

   每条记录的字段
   --------------
   mn      助记符（OOGLEX 自己的，不用彭博的 DES/GP/TREN 这类商标性助记符）
   zh/en   中英文名称
   cat     分类，决定它在功能键条上的颜色（见 CATEGORIES）
   href    站内地址；status 为 planned 时为 null
   status  live   = 站内已有页面，可点
           draft  = 本目录下的草案页，可点，但标注草案
           planned= 还没建，只在功能目录里列出，不做成可点按钮，也不假装能用
   data    它读的站内数据文件（planned 的写「需新增」）
   note    口径或限制，逐条写清
   =========================================================================== */
(function (global) {
  "use strict";

  /* 分类 → 颜色。颜色只承载「功能属于哪一类」，和涨跌红绿是两套语义，
     所以功能键条不参与数据配色的严格控色规则 —— 它是导航，不是数据。 */
  var CATEGORIES = {
    quote:  { zh: "行情报价", en: "Quotes",     bg: "#b5a01c", ink: "#0a0a0a" },
    macro:  { zh: "宏观风险", en: "Macro/Risk", bg: "#a32638", ink: "#ffffff" },
    anly:   { zh: "分析研究", en: "Analytics",  bg: "#1d7a3c", ink: "#ffffff" },
    news:   { zh: "新闻事件", en: "News/Events",bg: "#b8651e", ink: "#0a0a0a" },
    rank:   { zh: "榜单数据", en: "Rankings",   bg: "#1d5fa6", ink: "#ffffff" },
    tool:   { zh: "工具计算", en: "Tools",      bg: "#9c2a86", ink: "#ffffff" },
    chain:  { zh: "产业链",   en: "Value Chain",bg: "#1a7d6e", ink: "#ffffff" },
    sys:    { zh: "系统",     en: "System",     bg: "#4a4a4a", ink: "#e8e8e8" }
  };

  var FUNCTIONS = [
    /* ── 行情报价 ──────────────────────────────────────────────────────── */
    { mn:"GMKT", zh:"全球市场行情", en:"Global Markets", cat:"quote", status:"live",
      href:"../apps/markets/", data:["asset-tracker/data.json","asset-tracker/intraday.json"],
      note:"六大品类逐项报价；盘中快照约 30 分钟刷新，非实时" },
    { mn:"WRET", zh:"大类资产收益", en:"World Returns", cat:"quote", status:"live",
      href:"../apps/asset-tracker/", data:["asset-tracker/data.json"],
      note:"133 个标的的日/周/月/年初至今收益，收盘口径" },
    { mn:"EQTY", zh:"全球公司股价", en:"Equities", cat:"quote", status:"live",
      href:"../apps/companies/", data:["companies/data.json","companies/intraday.json"],
      note:"500 家上市与非上市公司；非美元报价按上市地本币" },
    { mn:"CMDT", zh:"商品行情", en:"Commodities", cat:"quote", status:"live",
      href:"../apps/commodities/", data:["commodities/data.json"],
      note:"现货与期货代理并列，代理关系逐条标注" },
    { mn:"BOND", zh:"主权债收益率", en:"Sovereign Yields", cat:"quote", status:"live",
      href:"../apps/bonds/", data:["bonds/data.json"],
      note:"35 国 10 年期；OECD 月频，与站内日频曲线是同一资产的两个口径" },
    { mn:"HEAT", zh:"标普热力图", en:"S&P Heatmap", cat:"quote", status:"live",
      href:"../apps/heatmap/", data:["companies/sp500.json"], note:"按板块与市值分块着色" },

    /* ── 宏观风险 ──────────────────────────────────────────────────────── */
    { mn:"MACR", zh:"宏观雷达", en:"Macro Radar", cat:"macro", status:"live",
      href:"../apps/macro-radar/", data:["macro-radar/data.json","macro-radar/series.json"],
      note:"机制读数 + 七类信号 + 五组官方序列" },
    { mn:"CRVE", zh:"美债收益率曲线", en:"Treasury Curve", cat:"macro", status:"live",
      href:"../apps/macro-radar/", data:["macro-radar/curve.json"],
      note:"11 个期限共享日期轴；当日无观测即留空，不插值" },
    { mn:"RISK", zh:"金融风险监测", en:"Financial Risk", cat:"macro", status:"live",
      href:"../apps/ofr-monitor/", data:["ofr-monitor/data.json"], note:"OFR 五大监测" },
    { mn:"FEAR", zh:"恐慌与贪婪", en:"Fear & Greed", cat:"macro", status:"live",
      href:"../apps/fear-greed/", data:["fear-greed/data.json"], note:"CNN 七项情绪指标合成" },
    { mn:"WECO", zh:"全球经济图谱", en:"World Economy", cat:"macro", status:"live",
      href:"../apps/world-economy/", data:["world-economy/data.json"], note:"各国经济状况概览" },
    { mn:"HPRC", zh:"全球房价", en:"House Prices", cat:"macro", status:"live",
      href:"../apps/house-prices/", data:["house-prices/data.json"], note:"主要国家房价走势" },

    /* ── 新闻事件 ──────────────────────────────────────────────────────── */
    { mn:"NEWS", zh:"要闻", en:"News", cat:"news", status:"live",
      href:"../apps/whats-latest/", data:["whats-latest/data.json"], note:"日内多次刷新" },
    { mn:"ECAL", zh:"全球经济日历", en:"Econ Calendar", cat:"news", status:"live",
      href:"../apps/econ-calendar/", data:["econ-calendar/data.json"],
      note:"央行决议 / CPI / 非农；逐条标注是否已回填实际值" },

    /* ── 分析研究 ──────────────────────────────────────────────────────── */
    { mn:"DESC", zh:"证券描述", en:"Security Description", cat:"anly", status:"draft",
      href:"g-des.html", data:["companies/data.json","companies/history.json","companies/intraday.json"],
      note:"方案G 草案：单证券的发行人、证券、标识、收益与口径分页" },
    { mn:"TRND", zh:"榜单与趋势", en:"Trends", cat:"anly", status:"draft",
      href:"h-tren.html", data:["companies/data.json","whats-latest/data.json"],
      note:"方案H 草案：可切维度的排行表，编号行 + 迷你走势" },
    { mn:"MON",  zh:"多功能监控", en:"Monitor", cat:"anly", status:"draft",
      href:"i-mon.html", data:["多个站内 JSON"], note:"方案I 草案：一屏挂多个功能面板" },
    { mn:"SUPI", zh:"超级投资者持仓", en:"Superinvestors", cat:"anly", status:"live",
      href:"../apps/superinvestors/", data:["superinvestors/data.json"],
      note:"13F 与政治人物交易，周频" },

    /* ── 产业链 ────────────────────────────────────────────────────────── */
    { mn:"SCHN", zh:"全球产业链", en:"Value Chains", cat:"chain", status:"live",
      href:"../apps/supply-chain/", data:["supply-chain/*.json"],
      note:"12 个价值链环节 × 27 条产业链" },

    /* ── 榜单数据 ──────────────────────────────────────────────────────── */
    { mn:"MCAP", zh:"全球市值排行", en:"Market Cap Rank", cat:"rank", status:"live",
      href:"../apps/asset-ranking/", data:["asset-ranking/data.json","asset-ranking/crypto.json"],
      note:"不限品类前 250" },
    { mn:"BILL", zh:"全球富豪榜", en:"Billionaires", cat:"rank", status:"live",
      href:"../apps/billionaires/", data:["billionaires/data.json"], note:"Forbes，日频" },
    { mn:"DHUB", zh:"数据中心", en:"Data Hub", cat:"rank", status:"live",
      href:"../apps/data-hub/", data:["站内各应用"], note:"全部数据应用的聚合入口" },

    /* ── 工具 ──────────────────────────────────────────────────────────── */
    { mn:"CALC", zh:"金融计算器", en:"Calculators", cat:"tool", status:"live",
      href:"../apps/calculators/", data:[], note:"纯前端计算，不读数据" },
    { mn:"EDU",  zh:"金融知识架构", en:"Finance Knowledge", cat:"tool", status:"live",
      href:"../apps/finance-column/", data:[], note:"全市场知识图谱" },

    /* ── 系统 ──────────────────────────────────────────────────────────── */
    { mn:"FDIR", zh:"功能目录", en:"Function Directory", cat:"sys", status:"draft",
      href:"#fdir", data:[], note:"本注册表本身，列出已接入与规划中的全部功能" },
    { mn:"HELP", zh:"帮助", en:"Help", cat:"sys", status:"draft",
      href:"#help", data:[], note:"键盘与命令行说明" }
  ];

  /* 规划中的功能：只在功能目录里列出，不做成可点按钮。
     写清「缺什么」比先画个空壳诚实 —— 缺数据源的就写缺哪一条。 */
  var PLANNED = [
    { mn:"PORT", zh:"组合与持仓", en:"Portfolio", cat:"anly",
      need:"账户/持仓来源：positions[] = { symbol, qty, avgCost, currency, asOf }",
      blocked:"站内无任何账户数据；汇率需另接官方来源；风险指标依赖持仓协方差" },
    { mn:"QUOT", zh:"逐笔报价与深度", en:"Level 1/2 Quotes", cat:"quote",
      need:"付费行情源（BID / ASK / VOL / 日内高低）",
      blocked:"无免费公开来源，现阶段这四组字段一律不显示，也不用占位数字冒充" },
    { mn:"SWAP", zh:"资产互换分析", en:"Asset Swap", cat:"anly",
      need:"单券现金流表 + 互换曲线 + 日历规则",
      blocked:"站内债券数据是主权收益率序列，没有券级现金流（票息、付息频率、到期日）" },
    { mn:"OPTN", zh:"期权链与隐含波动", en:"Option Chain", cat:"anly",
      need:"期权链快照（行权价、到期、隐含波动率）", blocked:"无来源" },
    { mn:"FLOW", zh:"资金流向", en:"Fund Flows", cat:"macro",
      need:"基金流向周报（EPFR/ICI 一类）", blocked:"无免费公开来源" },
    { mn:"SCRN", zh:"条件选股", en:"Screener", cat:"anly",
      need:"基本面字段（PE / PB / ROE / 营收增速）",
      blocked:"站内公司数据只有价格、市值与收益率，没有财务报表字段" },
    { mn:"ALRT", zh:"条件告警", en:"Alerts", cat:"tool",
      need:"一处可写存储 + 定时评估", blocked:"纯静态站无后端；浏览器本地只能在打开时评估" },
    { mn:"CHAT", zh:"终端问答", en:"Terminal Q&A", cat:"tool",
      need:"接站内 ai-chat 的问答能力并限定在站内数据上",
      blocked:"需要先把数据口径做成可检索的结构，否则会答出站内没有的数字" }
  ];

  /* PLANNED 里不再逐条写 status —— 在这里统一打标，避免漏写导致被当成可跳转的功能 */
  PLANNED.forEach(function (f) { f.status = "planned"; f.href = null; });

  function byMn(mn) {
    mn = String(mn || "").toUpperCase();
    return FUNCTIONS.filter(function (f) { return f.mn === mn; })[0] ||
           PLANNED.filter(function (f) { return f.mn === mn; })[0] || null;
  }
  function live()    { return FUNCTIONS.filter(function (f) { return f.status !== "planned"; }); }
  function byCat(c)  { return FUNCTIONS.filter(function (f) { return f.cat === c; }); }
  function catOf(f)  { return CATEGORIES[f.cat] || CATEGORIES.sys; }

  /* 功能键条：默认顺序按分类分组，和彭博一样「同色相邻」，扫视更快 */
  var BAR_ORDER = ["quote", "macro", "news", "anly", "chain", "rank", "tool", "sys"];
  function shortcuts() {
    var out = [];
    BAR_ORDER.forEach(function (c) {
      byCat(c).forEach(function (f) { if (f.status !== "planned") out.push(f); });
    });
    return out;
  }

  global.OOGLEX_FN = {
    CATEGORIES: CATEGORIES, FUNCTIONS: FUNCTIONS, PLANNED: PLANNED,
    byMn: byMn, byCat: byCat, catOf: catOf, live: live, shortcuts: shortcuts,
    BAR_ORDER: BAR_ORDER
  };
})(window);
