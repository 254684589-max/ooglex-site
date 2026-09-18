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
    /* 宏观管道的指标名（FRED 系列，data.json 里只有中文名和 series id，没有 nameEn），
       一律用各系列的通行英文名，不自创译法。 */
    "联邦基金有效利率": "Effective Federal Funds Rate",
    "SOFR 担保隔夜融资利率": "SOFR (Secured Overnight Financing Rate)",
    "准备金利率 (IORB)": "Interest on Reserve Balances (IORB)",
    "联邦基金目标上限": "Fed Funds Target Range · Upper Limit",
    "联邦基金目标下限": "Fed Funds Target Range · Lower Limit",
    "贴现窗口一级信贷利率": "Discount Window Primary Credit Rate",
    "美联储总资产": "Federal Reserve Total Assets",
    "准备金余额": "Reserve Balances",
    "财政部一般账户 (TGA)": "Treasury General Account (TGA)",
    "隔夜逆回购用量 (RRP)": "Overnight Reverse Repo Volume (RRP)",
    "10 年期美债收益率": "10-Year Treasury Yield",
    "5 年期 TIPS 实际收益率": "5-Year TIPS Real Yield",
    "10 年期 TIPS 实际收益率": "10-Year TIPS Real Yield",
    "10 年盈亏平衡通胀预期": "10-Year Breakeven Inflation Rate",
    "5 年盈亏平衡通胀预期": "5-Year Breakeven Inflation Rate",
    "5 年 5 年远期通胀预期": "5-Year, 5-Year Forward Inflation Expectation Rate",
    "2 年期美债收益率": "2-Year Treasury Yield",
    "30 年期美债收益率": "30-Year Treasury Yield",
    "10Y−2Y 期限利差": "10Y−2Y Term Spread",
    "10Y−3M 期限利差": "10Y−3M Term Spread",
    "10Y 期限溢价 (ACM/KW)": "10Y Term Premium (ACM/KW)",
    "芝加哥联储金融状况指数": "Chicago Fed National Financial Conditions Index",
    "调整后金融状况指数": "Adjusted National Financial Conditions Index",
    "圣路易斯联储金融压力指数": "St. Louis Fed Financial Stress Index",
    "高收益债 OAS": "High-Yield OAS",
    "BBB 级公司债 OAS": "BBB Corporate OAS",
    "投资级债 OAS": "Investment-Grade OAS",
    "Baa 公司债–10Y 利差": "Baa Corporate − 10Y Spread",
    "铜/金 ×1000 (工业 vs 避险)": "Copper/Gold ×1000 (industrial vs. safe haven)",
    "金/银": "Gold/Silver",
    "油/铜": "Oil/Copper",
    "油/金 ×100": "Oil/Gold ×100",
    "MOVE 债券波动率": "MOVE Bond Volatility",
    "SKEW 偏度": "SKEW Index",
    "VVIX 波动之波动": "VVIX (volatility of volatility)",
    /* 时光机上的危机事件标签 */
    "2008 全球金融危机": "2008 Global Financial Crisis",
    "2011 欧债·美债降级": "2011 Euro Debt Crisis · U.S. Downgrade",
    "2013 缩减恐慌": "2013 Taper Tantrum",
    "2015 人民币冲击": "2015 Renminbi Shock",
    "2018 联储双紧": "2018 Fed Double Tightening",
    "2019 回购危机": "2019 Repo Crisis",
    "2020 新冠崩盘": "2020 COVID Crash",
    "2022 通胀紧缩": "2022 Inflation Tightening",
    "2023 硅谷银行": "2023 Silicon Valley Bank",
    "2024 套息平仓": "2024 Carry-Trade Unwind",
    /* 信号卡的状态词与指标说明 */
    "支持": "Supportive",
    "承压": "Under pressure",
    "VIX 水平与期限结构": "VIX level and term structure",
    "增长动能综合：铜金比 · 半导体/大盘(SOX) · 周期/防御(XLY/XLP)":
      "Growth momentum composite: copper/gold · semis vs. market (SOX) · cyclicals vs. defensives (XLY/XLP)",
    "等权/市值加权广度：存量近两年 9% 分位，近 13 周更集中":
      "Equal- vs. cap-weighted breadth: at the 9th percentile of the past two years, and more concentrated over the last 13 weeks",
    "FRED · EIA · Yahoo Finance · 交易所行情": "FRED · EIA · Yahoo Finance · exchange quotes",
    "· 仅供研究，非投资建议": "· For research only, not investment advice",
    "收益率曲线周环比": "Yield curve, week over week",
    "（走平）": " (flattening)",
    "（陡峭化）": " (steepening)",
    "利率": "rates",
    "（加息定价升温、边际收紧）": " (more tightening priced in; marginally tighter)",
    "（降息定价升温、边际宽松）": " (more easing priced in; marginally looser)",
    "（贴现率急升、压制久期资产）": " (discount rates jumping; pressure on long-duration assets)",
    "（贴现率回落、利好久期资产）": " (discount rates falling; supportive for long-duration assets)",
    "广度代理处于近两年": "The breadth proxy sits at the ",
    "分位，涨势集中": " percentile of the past two years, with gains concentrated",
    "高收益/投资级比价周环比": "High-yield vs. investment-grade ratio, week over week",
    "，信用走弱": " — credit weakening",
    "，信用改善": " — credit improving",
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
    "账户系统 Beta · Ooglex": "Account System Beta · Ooglex",
    /* 2026-09-18 新增的昵称编辑区，当时没跟着补英文 */
    "修改昵称": "Change display name",
    "保存昵称": "Save display name",
    "留空则显示为「匿名用户」": "Leave empty to appear as “Anonymous”",
    "昵称会显示在": "Your display name appears in ",
    "想法流": "Your Thoughts",
    "里，并决定你的头像首字与配色；改了之后你已发布的想法会一起更新.":
      " and decides the initial and colour of your avatar. Changing it also updates the posts you have already published.",
    "里，并决定你的头像首字与配色；改了之后你已发布的想法会一起更新。":
      " and decides the initial and colour of your avatar. Changing it also updates the posts you have already published.",
    "返回首页": "Back to Home"
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
      /* 信号卡的判语是 scripts/macro-radar/build_radar.py 按模板拼出来的，
         整串永远进不了字典。下面逐个模板写两端锚定的规则，数字与单位原样带回；
         拼进去的词（信号名、松紧判断）统一走 SIGNAL/TONE 两张小表，
         查不到就回退原文，绝不臆造。 */
      var SIGNAL = { "流动性": "Liquidity", "波动率": "Volatility", "期限溢价": "Term premium",
        "实际利率": "Real rates", "信用": "Credit", "美元": "Dollar", "广度": "Breadth",
        "市场广度": "Market breadth", "信用利差": "Credit spreads" };
      var TONE = { "回升": "rebounding", "收缩": "contracting", "充裕": "ample", "趋紧": "tightening",
        "政策偏松": "policy leaning easy", "政策偏紧": "policy leaning tight",
        "牛陡偏松": "bull steepening, easier", "熊陡偏紧": "bear steepening, tighter",
        "曲线陡峭": "curve steep", "曲线倒挂": "curve inverted",
        "紧缩驱动": "tightening-driven", "增长驱动": "growth-driven",
        "利差温和": "spreads contained", "利差走阔": "spreads widening",
        "风险偏好回升": "risk appetite recovering", "信用边际走弱": "credit weakening at the margin",
        "走强偏紧": "stronger, tighter", "走弱偏松": "weaker, easier",
        "抬升": "rising", "回落": "easing",
        "倒挂 (backwardation)": "backwardation", "正向 (contango)": "contango",
        "尚未进入系统性压力区": "not yet in systemic stress territory",
        "已进入压力区": "already in stress territory",
        "风险偏好占优、结构偏支持": "risk appetite dominates and the structure is supportive",
        "避险情绪升温、结构偏承压": "risk-off is building and the structure is under pressure",
        "多空交织、结构中性分化": "mixed, with a neutral and divided structure",
        "收紧 · 风险": "Tight · Risk", "中性偏紧": "Neutral-tight", "中性": "Neutral",
        "中性偏松": "Neutral-easy", "宽松 · 支持": "Supportive" };
      function sig(x) { return x.split("、").map(function (k) { return SIGNAL[k] || k; }).join(" and "); }
      function tone(x) { return TONE[x] || x; }

      if ((m = /^净流动性 (\S+?)T，近 13 周 (\S+?)B（(.+?)）(?:；SOFR−IORB (\S+?)bp（(.+?)）)?$/.exec(s))) {
        return "Net liquidity " + m[1] + "T, " + m[2] + "B over 13 weeks (" + tone(m[3]) + ")" +
          (m[4] ? "; SOFR−IORB " + m[4] + "bp (" + tone(m[5]) + ")" : "");
      }
      if ((m = /^3M 短端利率 (\S+?)%，(.+)$/.exec(s))) return "3M short rate " + m[1] + "%, " + tone(m[2]);
      if ((m = /^VIX (抬升|回落)，期限结构(.+)$/.exec(s))) return "VIX " + tone(m[1]) + ", term structure in " + tone(m[2]);
      if ((m = /^10Y−3M (\S+?)bp，期限溢价 (\S+?)%（(.+?)）$/.exec(s))) {
        return "10Y−3M " + m[1] + "bp, term premium " + m[2] + "% (" + tone(m[3]) + ")";
      }
      if ((m = /^收益率曲线 10Y−3M (\S+?)bp，(.+)$/.exec(s))) return "Yield curve 10Y−3M " + m[1] + "bp, " + tone(m[2]);
      if ((m = /^5Y 实际利率 (\S+?)%，近 13 周 (\S+?)bp(?:（(.+?)）)?$/.exec(s))) {
        return "5Y real rate " + m[1] + "%, " + m[2] + "bp over 13 weeks" + (m[3] ? " (" + tone(m[3]) + ")" : "");
      }
      if ((m = /^高收益债 OAS (\S+?)bp，(.+)$/.exec(s))) return "High-yield OAS " + m[1] + "bp, " + tone(m[2]);
      if ((m = /^高收益\/投资级比价 \(HYG÷LQD\)，(.+)$/.exec(s))) return "High-yield vs. investment-grade (HYG÷LQD), " + tone(m[1]);
      if ((m = /^美元指数 (\S+?)（(.+?)）(?:，离岸-在岸基差 (\S+?)pips)?$/.exec(s))) {
        return "Dollar index " + m[1] + " (" + tone(m[2]) + ")" +
          (m[3] ? ", CNH−CNY basis " + m[3] + " pips" : "");
      }
      if ((m = /^等权\/市值加权广度：存量近两年 (\S+?)% 分位，近 13 周(.+)$/.exec(s))) {
        return "Equal- vs. cap-weighted breadth: " + m[1] + "th percentile of the past two years, " + m[2] + " over 13 weeks";
      }
      if ((m = /^(.+?)走弱压制风险偏好；(.+?)相对稳健，(.+?)。$/.exec(s))) {
        return sig(m[1]) + " weakening weighs on risk appetite, while " + sig(m[2]) +
          " hold up; " + tone(m[3]) + ".";
      }
      if (s === "多资产制度信号综合读数。") return "Composite reading across multi-asset regime signals.";
      if (s === "今日无显著市场异动，跨资产结构平稳。") return "No notable market moves today; the cross-asset structure is stable.";
      if ((m = /^今日 (\d+) 条市场异动，(.+?)；与机制读数 (\d+)（(.+?)）方向一致。$/.exec(s))) {
        return m[1] + " notable market moves today: " + tone(m[2]) + "; consistent with the regime reading of " +
          m[3] + " (" + tone(m[4]) + ").";
      }
      // 「3M 短端利率周环比」这类被 <b> 切成了「3」「M 短端利率周环比」两段
      if ((m = /^M 短端利率周环比$/.exec(s))) return "M short-rate change, week over week";
      if ((m = /^Y 实际利率周环比$/.exec(s))) return "Y real-rate change, week over week";
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
    /* specialEnglish 必须跑在逐节点翻译**之前**。它对整块元素做 innerHTML 备份
       （富豪榜的 .nm、宏观风险监测的 .sig h3 / .mcat b），如果先让 translateText
       把里面的文本翻成英文，它备份下来的「原文」就已经是英文了，切回中文时
       h3 会停在 "Liquidity" 而不是「流动性」。它接管的那几块本来就由它整体改写，
       提前跑不会漏翻。 */
    specialEnglish(base);
    var w = document.createTreeWalker(base, NodeFilter.SHOW_TEXT, null);
    var n;
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
        for (var i = 0; i < batch.length; i++) {
          var r = batch[i];
          if (r.type === "attributes") translateAttrs(r.target);
          else if (r.type === "characterData") translateText(r.target);
          else for (var j = 0; j < r.addedNodes.length; j++) walk(r.addedNodes[j]);
        }
        specialEnglish(document);
      });
    });
    /* 也盯 ATTRS 里那几个属性：原先只盯 childList/characterData，
       于是「就地改写已有元素的 aria-label/title」这类更新永远翻不到
       （行情板的「当前显示 73 项：上涨 25…」就是这么漏的）。
       改写属性本身会再触发一次 mutation，但英文串查不到词条，第二轮是空转，不会循环。 */
    observer.observe(document.documentElement, { subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ATTRS });
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
