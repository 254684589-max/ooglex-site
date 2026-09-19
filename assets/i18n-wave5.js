/* Ooglex fifth-wave i18n layer.
   Final deep-page sweep for Finance Terminal, Calculators and AI Chat.
   Reads localStorage["ooglex.language"], translates reviewed UI/runtime strings,
   preserves the original Chinese DOM for lossless switching back, and deliberately
   does not translate user/assistant conversation content. */
(function () {
  "use strict";

  var KEY = "ooglex.language";
  var path = (location.pathname || "/").replace(/\/index\.html$/, "/");
  var current = "zh";
  var applying = false;
  var textOrig = new WeakMap(), textLast = new WeakMap(), textTouched = [];
  var attrOrig = new WeakMap(), attrLast = new WeakMap(), attrTouched = [];
  var ATTRS = ["placeholder", "aria-label", "title", "data-num-label"];

  function readLang() {
    try {
      if (window.OoglexI18n && window.OoglexI18n.getLanguage) {
        return window.OoglexI18n.getLanguage() === "en" ? "en" : "zh";
      }
      return localStorage.getItem(KEY) === "en" ? "en" : "zh";
    } catch (e) { return "zh"; }
  }

  function isTerminal() { return path.indexOf("/apps/finance-terminal/") === 0; }
  function isCalculator() { return path.indexOf("/apps/calculators/") === 0; }
  function isAiChat() { return path.indexOf("/apps/ai-chat/") === 0; }

  var COMMON = {
    "功能快捷键": "Function shortcuts",
    "后退": "Back",
    "前进": "Forward",
    "相关功能菜单 ⌄": "Related functions ⌄",
    "标准": "Standard",
    "专业": "Professional",
    "⌗ 功能目录": "⌗ Function Directory",
    "功能目录": "Function Directory",
    "⇱ 导出": "⇱ Export",
    "导出 CSV": "Export CSV",
    "口径说明": "Methodology",
    "口径与不可得字段": "Methodology & unavailable fields",
    "导出本页 CSV": "Export this page as CSV",
    "上一页": "Previous page",
    "下一页": "Next page",
    "命令行": "Command line",
    "HELP 看用法": "HELP for usage",
    "相关功能": "Related Functions",
    "全部功能": "All Functions",
    "读取中…": "Loading…",
    "无来源": "No source",
    "Pages": "Pages",
    "Quick Links": "Quick Links",
    "监控": "Monitor",
    "证券描述": "Security Description",
    "条件选股": "Equity Screener",
    "榜单与趋势": "Rankings & Trends",
    "多标的比较": "Multi-Asset Compare",
    "行情详情": "Quote Details",
    "旧版终端": "Legacy Terminal",
    "使用条款": "Terms of Use",
    "隐私政策": "Privacy Policy",
    "站点首页": "Site Home",
    "返回终端": "Back to Terminal",
    "返回全球市场总览": "Back to Global Market Overview",
    "数据仅供研究参考，不构成投资建议": "Data is for research and reference only; not investment advice",
    "仅供产品测试 · 非投资建议": "For product testing only · Not investment advice",
    "本站没有经纪或订单通道，因此这里没有买/卖键 —— 画一个就是假的。": "This site has no brokerage or order-routing channel, so there are no Buy/Sell buttons—adding them would be fake.",
    "公司": "Company",
    "板块": "Sector",
    "国别": "Country",
    "地区": "Region",
    "市值": "Market Cap",
    "标的": "Instrument",
    "期间": "Period",
    "变动": "Change",
    "口径": "Method",
    "有效点": "Valid Points",
    "当前视图": "Current View",
    "要闻": "News",
    "说明": "Notes"
  };

  var TERMINAL = {
    "汇总视图": "Summary view",
    "规划中：站内无任何账户数据；汇率需另接官方来源；风险指标依赖持仓协方差":
      "Planned: the site holds no account data; exchange rates would need a separate official source; risk metrics depend on a holdings covariance matrix",
    "规划中：无免费公开来源，现阶段这四组字段一律不显示，也不用占位数字冒充":
      "Planned: no free public source exists, so these four field groups are simply not shown — no placeholder numbers stand in for them",
    "规划中：站内债券数据是主权收益率序列，没有券级现金流（票息、付息频率、到期日）":
      "Planned: the site's bond data is sovereign yield series, with no bond-level cash flows (coupon, payment frequency, maturity)",
    "规划中：无来源": "Planned: no source",
    "规划中：无免费公开来源": "Planned: no free public source",
    "规划中：纯静态站无后端；浏览器本地只能在打开时评估":
      "Planned: a purely static site has no backend, and a browser can only evaluate it while the page is open",
    "规划中：需要先把数据口径做成可检索的结构，否则会答出站内没有的数字":
      "Planned: the data definitions must first be made searchable as structure, or it would answer with numbers the site does not hold",
    "行情报价":
      "Market Quotes",
    "宏观风险":
      "Macro Risk",
    "新闻事件":
      "News & Events",
    "分析研究":
      "Analysis & Research",
    "产业链":
      "Supply Chain",
    "榜单数据":
      "Rankings & Data",
    "工具计算":
      "Tools & Calculators",
    "系统":
      "System",
    "行情详情":
      "Quote Detail",
    "美债收益率曲线":
      "Treasury Yield Curve",
    "要闻":
      "News",
    "多标的比较":
      "Multi-Instrument Comparison",
    "榜单与趋势":
      "Rankings & Trends",
    "证券描述":
      "Security Description",
    "功能目录":
      "Function Catalog",
    "旧版终端":
      "Legacy Terminal",
    "六大品类逐项报价；盘中快照约 30 分钟刷新，非实时":
      "Per-instrument quotes across six categories; the intraday snapshot refreshes about every 30 minutes and is not real time",
    "133 个标的的日/周/月/年初至今收益，收盘口径":
      "Daily, weekly, monthly and year-to-date returns for 133 instruments, on a close basis",
    "500 家上市与非上市公司；非美元报价按上市地本币":
      "500 listed and private companies; non-USD quotes are in the local currency of the listing venue",
    "商品报价在全球市场行情页的六大品类里（品类切换是页内筛选，没有独立锚点）；apps/commodities/ 目前只有数据文件，还没有独立页面":
      "Commodity quotes live in the six categories of the Global Markets page (switching category filters within the page; there is no separate anchor). apps/commodities/ currently holds data files only, with no page of its own yet",
    "35 国 10 年期在全球市场行情页的债券品类里，按地区分组（美洲4/欧洲25/亚洲3/大洋洲2/非洲1），每行可点进自己的历史图；34 条月频、1 条日频，涨跌是「较前一观测」的基点变化不是当日。apps/bonds/ 目前只有数据文件，还没有独立页面 —— 品类切换是页内筛选，没有独立锚点。国与国之间的利差在监控页 SOVR 面板":
      "The 10-year yields of 35 countries sit in the Bonds category of the Global Markets page, grouped by region (Americas 4 / Europe 25 / Asia 3 / Oceania 2 / Africa 1), each row opening its own history chart; 34 series are monthly and 1 daily, and the change is the basis-point move versus the previous observation, not versus today. apps/bonds/ currently holds data files only, with no page of its own — switching category filters within the page and has no separate anchor. Country-to-country spreads are in the SOVR panel of the monitor page",
    "按板块与市值分块着色":
      "Tiled and coloured by sector and market cap",
    "单标的完整走势：日线 1 个月至全部区间，有小时观测的另有 4 小时线":
      "The full history of a single instrument: daily bars from one month to the entire range, plus 4-hour bars where hourly observations exist",
    "机制读数 + 七类信号 + 五组官方序列":
      "Regime reading + seven signal families + five groups of official series",
    "11 个期限共享日期轴；当日无观测即留空，不插值":
      "11 tenors on a shared date axis; a day with no observation is left blank, never interpolated",
    "OFR 五大监测":
      "The five OFR monitors",
    "CNN 七项情绪指标合成":
      "Composited from CNN's seven sentiment indicators",
    "各国经济状况概览":
      "An overview of each country's economic condition",
    "主要国家房价走势":
      "House price trends in major economies",
    "日内多次刷新":
      "Refreshed several times a day",
    "央行决议 / CPI / 非农；逐条标注是否已回填实际值":
      "Central-bank decisions / CPI / payrolls, each marked with whether the actual value has been backfilled",
    "六项比率（PE/PB/PS/ROE/净利率/负债率）筛选与排序，外加同业对比、板块分布与覆盖面。比率由本站按写明的公式从 SEC XBRL 报表项现算；逐条带报表期末与价格日期两个日期；分母非正不给比率，缺的字段是 null 不是 0":
      "Screen and sort on six ratios (PE, PB, PS, ROE, net margin, debt ratio), with peer comparison, sector distribution and coverage. The ratios are computed here from SEC XBRL statement items using the stated formulas; each row carries both the statement period end and the price date; a non-positive denominator yields no ratio, and a missing field is null, not 0",
    "与 SCRN 同一张表的另一种用法：筛选是加阈值，相对估值是和同业中位比。板块中位用中位数而非平均，样本不足 5 家不给中位。不另开一页重复同一份数据":
      "The same table as SCRN used a different way: screening applies thresholds, relative valuation compares against the peer median. Sector medians use the median rather than the mean, and no median is given below a sample of 5. No second page duplicates the same data",
    "证券描述页 15) 分页：该公司的报表原始项（营收/净利/EPS/权益/资产/负债）与六项比率，并与本板块中位对比。现金流表、信用评级、期权链仍无来源，菜单里保持置灰":
      "A sub-page of the Security Description page (15): the company's raw statement items (revenue, net income, EPS, equity, assets, liabilities) and the six ratios, compared with the sector median. Cash-flow statements, credit ratings and option chains still have no source and stay greyed out in the menu",
    "各国十年期相对任选基准国的利差（基点），外加当前利差最宽四国的月频利差历史（400 期）。只在与基准同一个数据日的国家之间算，跨期的逐条摘出；收益率是水平值，差值只报基点不报百分比":
      "Each country's 10-year yield spread against a benchmark country of your choosing (in basis points), plus the monthly spread history (400 periods) of the four countries with the widest current spreads. Spreads are computed only between countries sharing the benchmark's data date, with cross-period entries pulled out one by one; yields are levels, so differences are reported in basis points, never as percentages",
    "终端首页：一屏挂 13 个功能面板，跨品类总览":
      "The terminal's home page: 13 function panels on one screen, a cross-category overview",
    "单证券的发行人、证券、标识、收益、走势与口径分页":
      "Sub-pages for a single security: issuer, instrument, identifiers, returns, history and methodology",
    "按日期对齐、共同窗口内重基到 100 叠加比较；另给价差比值、回撤与区间总回报":
      "Aligned by date and rebased to 100 within a common window for overlay comparison, with the spread ratio, drawdown and total return over the range",
    "可切六个维度的排行表，编号行 + 相对强弧 + 迷你走势":
      "A ranking table switchable across six dimensions, with numbered rows, relative strength and sparklines",
    "可切六个维度的排行表，编号行 + 相对强弱 + 迷你走势":
      "A ranking table switchable across six dimensions, with numbered rows, relative strength and sparklines",
    "13F 与政治人物交易，周频":
      "13F filings and political trades, weekly",
    "12 个价值链环节 × 27 条产业链":
      "12 value-chain stages × 27 industry chains",
    "不限品类前 250":
      "Top 250 across all asset classes",
    "Forbes，日频":
      "Forbes, daily",
    "全部数据应用的聚合入口":
      "The aggregated entry point to every data app",
    "纯前端计算，不读数据":
      "Pure front-end computation; reads no data",
    "全市场知识图谱":
      "A knowledge graph of the whole market",
    "本注册表本身，列出已接入与规划中的全部功能":
      "The registry itself, listing every function that is live and every one that is planned",
    "键盘与命令行说明":
      "Keyboard and command-line reference",
    "改版前的终端页，保留可用；其品类看板与地缘风险模块尚未迁入新版":
      "The pre-redesign terminal page, kept usable; its category board and geopolitical-risk module have not yet moved to the new version",
    "CNN Business Fear & Greed Index · 日频":
      "CNN Business Fear & Greed Index · daily",
    "U.S. Office of Financial Research (OFR) · 日频":
      "U.S. Office of Financial Research (OFR) · daily",
    "Forex Factory 经济日历 · 周历 · 每日刷新":
      "Forex Factory economic calendar · weekly schedule · refreshed daily",
    "Google News · Yahoo Finance · 日内多次":
      "Google News · Yahoo Finance · several times a day",
    "CoinGecko · 日频 · 24h 口径":
      "CoinGecko · daily · 24-hour basis",
    "站内全部为公开来源的定时快照；任何一源失败只影响对应面板，不以零值静默覆盖":
      "Everything here is a scheduled snapshot of a public source; a failure in any one source affects only its own panel and never silently overwrites with zeros",
    "信用与加密 Credit & Crypto": "Credit & Crypto",
    "功能注册表 Function Registry": "Function Registry",
    "彩色功能键条、功能目录、命令行解析、建议功能条都从":
      "The colour function-key bar, the function catalog, command-line parsing and the suggested-function strip are all generated from ",
    "生成：加一个金融功能 = 加一条记录。划掉的是规划中，缺什么写在功能目录里。":
      ": adding a financial function means adding one record. Struck-through entries are planned; what is missing is stated in the catalog.",
    "Yahoo Finance · 约30分钟 · 非实时": "Yahoo Finance · about 30 minutes · not real time",
    "FRED · EIA · Yahoo Finance · 交易所行情 · 日频": "FRED · EIA · Yahoo Finance · exchange quotes · daily",
    "FRED / U.S. Treasury H.15 · 日频": "FRED / U.S. Treasury H.15 · daily",
    "来源 宏观风险监测的异动判定 · 阈值与口径见 MACR":
      "Source: the mutation detection of the Macro Risk Monitor · thresholds and definitions are under MACR",
    "以 德国10年期国债 为基准，单位基点（1bp = 0.01 个百分点）。只在与基准同一个数据日（2026-08-01）的国家之间算 —— 基准取这个月的观测、对手取另一个月的观测，两者之差不是利差，是两个时点的混合。数据日与基准不同、已摘出 4 条（智利10年期国债 2026-07-01、葡萄牙10年期国债 2026-07-01、波兰10年期国债 2026-07-01、欧元区AAA国债曲线10年 2026-09-16）。 收益率是水平值不是价格：差值只报基点，不报百分比。":
      "Benchmarked against the German 10-year government bond, in basis points (1bp = 0.01 percentage points). Spreads are computed only between countries sharing the benchmark's data date (2026-08-01) — taking the benchmark from one month and the counterpart from another does not give a spread, it gives a blend of two points in time. Four entries whose data date differs from the benchmark have been pulled out (Chile 10-year 2026-07-01, Portugal 10-year 2026-07-01, Poland 10-year 2026-07-01, Euro Area AAA government curve 10-year 2026-09-16). Yields are levels, not prices: differences are reported in basis points only, never as percentages.",
    "布油近1个月 +14.36% · WTI +19.17% · 按 −15% ~ +15% 线性映射，超出取端点":
      "Brent over the past month +14.36% · WTI +19.17% · mapped linearly over −15% to +15%, clipped at the endpoints",
    "黄金 -0.91% − 标普500 -0.70% = -0.21个百分点 · 按 −15 ~ +15 个百分点线性映射，超出取端点":
      "Gold −0.91% − S&P 500 −0.70% = −0.21 percentage points · mapped linearly over −15 to +15 percentage points, clipped at the endpoints",
    "宏观风险监测波动率信号 81/100（支持） · 风险方向 = 100 − 信号分，与首屏风险雷达同一取向":
      "Macro Risk Monitor volatility signal 81/100 (supportive) · risk direction = 100 − the signal score, the same orientation as the risk radar on the home screen",
    "OFR FSI -2.24，处于站内 261 个观测的第 65 百分位 · 百分位取自该文件自己保存的观测窗口，不设人为阈值":
      "OFR FSI −2.24, at the 65th percentile of the 261 observations held on site · the percentile comes from the observation window the file itself keeps; no threshold is imposed",
    "收益率曲线周环比 -12bp（走平）": "Yield curve, week over week −12bp (flattening)",
    "广度代理处于近两年 9% 分位，涨势集中":
      "The breadth proxy sits at the 9th percentile of the past two years, with gains concentrated",
    "高收益/投资级比价周环比 -0.6%，信用走弱":
      "High-yield vs. investment-grade ratio, week over week −0.6% — credit weakening",
    "跨资产强弱 Cross Asset · YTD":
      "Cross Asset · YTD",
    "股票 EQUITY":
      "Equity",
    "商品 COMMODITY":
      "Commodity",
    "债券 BOND":
      "Bond",
    "USD 申请失业金人数":
      "USD Initial Jobless Claims",
    "AUD 澳央行行长讲话":
      "AUD RBA Governor Speaks",
    "JPY 货币政策声明":
      "JPY Monetary Policy Statement",
    "JPY 央行利率决议":
      "JPY BoJ Policy Rate",
    "JPY 新闻发布会":
      "JPY Press Conference",
    "GBP 零售销售 环比":
      "GBP Retail Sales MoM",
    "EUR 欧央行行长讲话":
      "EUR ECB President Speaks",
    "来源 Yahoo Finance · AS OF 2026-09-17 · 日频收盘 · 状态 部分缺失 · LAST 为盘中快照（约 30 分钟刷新、非实时），1M/YTD 为收盘口径":
      "Source: Yahoo Finance · AS OF 2026-09-17 · daily close · status partially missing · LAST is an intraday snapshot (refreshed about every 30 minutes, not real time); 1M and YTD are on a close basis",
    "来源 FRED · EIA · Yahoo Finance · 交易所行情 · 判定阈值：分位 <35 STRESS / <48 RISK / <58 WATCH / ≥58 NORMAL；Z-Score |z|≥2 STRESS / ≥1.5 RISK / ≥1 WATCH（Z 由站内原始日序列现算，窗口见括号） · US10Y 与 DXY-FED 点进独立行情页（DGS10 / DTWEXBGS 两条逐日序列）；8 条合成信号点名称就地展开历史分位（周频回溯序列，没有单指标行情页，不做成假链接）；最后 9 条只有现值、站内无序列，因此不可点。完整指标页见宏观风险监测。":
      "Source: FRED · EIA · Yahoo Finance · exchange quotes · Thresholds: percentile <35 STRESS / <48 RISK / <58 WATCH / ≥58 NORMAL; Z-score |z|≥2 STRESS / ≥1.5 RISK / ≥1 WATCH (Z is computed live from the on-site raw daily series; the window is in parentheses) · US10Y and DXY-FED open their own quote pages (the DGS10 and DTWEXBGS daily series); the 8 composite signals expand their historical percentile in place when you click the name (weekly backtest series — there is no single-indicator quote page, and no fake link is offered); the last 9 have a current value only with no on-site series and are therefore not clickable. The full indicator page is the Macro Risk Monitor.",
    "十一个期限各取一条 FRED 官方序列、共享日期轴；某期限当日无观测即留空，不插值、不用相邻期限顶替。当前这两条利差都不倒挂。 30Y-5Y 由曲线现算，其余为数据源直接给出。":
      "Eleven tenors each take one official FRED series on a shared date axis; a tenor with no observation that day is left blank — never interpolated, never substituted with an adjacent tenor. Neither of these two spreads is currently inverted. 30Y−5Y is computed from the curve; the rest come straight from the source.",
    "来源 FRED (OECD Main Economic Indicators) / ECB Data Portal · 34 条月频 + 1 条日频，涨跌一律「较前一观测」不是当日 · 水平表在「全球市场行情」债券品类，这里只做利差":
      "Source: FRED (OECD Main Economic Indicators) / ECB Data Portal · 34 monthly series + 1 daily; changes are always “versus the previous observation”, not versus today · The level table lives in the Bonds category of Global Markets; this panel covers spreads only",
    "FRED (OECD Main Economic Indicators) / ECB Data Portal · 34条月频 + 1条日频":
      "FRED (OECD Main Economic Indicators) / ECB Data Portal · 34 monthly series + 1 daily",
    "FRED (OECD Main Economic Indicators) / ECB Data Portal · 月频 400 期":
      "FRED (OECD Main Economic Indicators) / ECB Data Portal · monthly, 400 periods",
    "本模型读的是市场为地缘风险付出的价格：能源溢价、避险需求、波动率制度、金融压力四条轴等权，全部由站内已在日更的公开管道逐日复算。它不统计、不解读地缘政治事件本身，也不使用任何 AI 生成的文本作为数据来源。":
      "This model reads the price the market pays for geopolitical risk: four equally weighted axes — energy premium, safe-haven demand, volatility regime and financial stress — all recomputed daily from public pipelines this site already refreshes every day. It neither counts nor interprets geopolitical events themselves, and it uses no AI-generated text as a data source.",
    "来源 Yahoo Finance · FRED · EIA · Yahoo Finance · 交易所行情 · U.S. Office of Financial Research (OFR) · AS OF 2026-09-15 · 四条轴各 25% 等权，任一条缺失即不给等级":
      "Source: Yahoo Finance · FRED · EIA · Yahoo Finance · exchange quotes · U.S. Office of Financial Research (OFR) · AS OF 2026-09-15 · The four axes are weighted 25% each; if any one is missing, no grade is given",
    "按跨资产管道的 category 字段汇总只数与涨跌宽度，完整的可搜索看板见 /apps/markets/ —— 这里不复制第二份看板。":
      "Counts and advance/decline breadth are aggregated from the cross-asset pipeline's category field. The full searchable board is at /apps/markets/ — no second copy of it is kept here.",
    "来源 Yahoo Finance · AS OF 2026-09-17 · 日频收盘 · 状态 部分缺失 · 只数与涨跌宽度按跨资产管道的 category 字段汇总 · 完整的可搜索看板见 /apps/markets/":
      "Source: Yahoo Finance · AS OF 2026-09-17 · daily close · status partially missing · Counts and breadth are aggregated from the cross-asset pipeline's category field · The full searchable board is at /apps/markets/",
    "来源 Forex Factory 经济日历 · AS OF 2026-09-17 · 周历 · 每日刷新 · 状态 — · A=实际 F=预测":
      "Source: Forex Factory economic calendar · AS OF 2026-09-17 · weekly schedule · refreshed daily · status — · A = actual, F = forecast",
    "来源 Google News · Yahoo Finance · AS OF 2026-09-18 · 日内多次 · 状态 —":
      "Source: Google News · Yahoo Finance · AS OF 2026-09-18 · several times a day · status —",
    "来源 Yahoo Finance · AS OF 2026-09-17 · 日频收盘 · 状态 部分缺失 · P = ETF 代理 · 加密为 24h 口径，与股票当日口径不同":
      "Source: Yahoo Finance · AS OF 2026-09-17 · daily close · status partially missing · P = ETF proxy · Crypto is on a 24-hour basis, which differs from the same-day basis used for equities",
    "来源 Yahoo Finance · 年初至今，各标的自身价格变动，未做汇率或再投资调整":
      "Source: Yahoo Finance · Year to date, each instrument's own price change, with no FX or reinvestment adjustment",
    "本终端不显示 BID / ASK / VOL / 日内高低 / 财务报表 / 评级 / 券级现金流 / 持仓：站内没有这些来源，也不用占位数字冒充。":
      "This terminal does not show BID / ASK / VOL / intraday high-low / financial statements / ratings / bond-level cash flows / holdings: the site has no source for them, and placeholder numbers are not used to stand in.",
    /* 主权债面板的国名 */
    "美国": "United States", "欧元区": "Euro Area", "德国": "Germany", "法国": "France",
    "意大利": "Italy", "西班牙": "Spain", "英国": "United Kingdom", "日本": "Japan",
    "加拿大": "Canada", "澳大利亚": "Australia", "新西兰": "New Zealand", "瑞士": "Switzerland",
    "瑞典": "Sweden", "挪威": "Norway", "丹麦": "Denmark", "芬兰": "Finland",
    "荷兰": "Netherlands", "比利时": "Belgium", "奥地利": "Austria", "爱尔兰": "Ireland",
    "葡萄牙": "Portugal", "希腊": "Greece", "卢森堡": "Luxembourg", "斯洛伐克": "Slovakia",
    "斯洛文尼亚": "Slovenia", "捷克": "Czechia", "波兰": "Poland", "匈牙利": "Hungary",
    "罗马尼亚": "Romania", "韩国": "South Korea", "以色列": "Israel", "墨西哥": "Mexico",
    "南非": "South Africa", "智利": "Chile", "哥伦比亚": "Colombia", "冰岛": "Iceland",
    "新建标签：打开功能目录": "New tab: open the function catalog",
    "打开功能目录，挑一个功能开新标签": "Open the function catalog and pick a function for a new tab",
    "全屏": "Fullscreen",
    "功能键条由 chrome/registry.js 生成：加一个功能就是加一条记录":
      "The function-key bar is generated by chrome/registry.js — adding a function means adding one record",
    "风险信号 · 0–100 相对分位（滚动 2 年）· 点名称看历史分位":
      "Risk signals · 0–100 relative percentile (rolling 2 years) · click a name for its history",
    "监测指标 · 仅现值与日变动（站内无历史序列，不给分位与判定）":
      "Monitored indicators · current value and daily change only (no on-site history, so no percentile or verdict)",
    "报价为数据源直接给出的对美元或对欧元的盘中快照（约 30 分钟刷新、非实时）。CNY 是在岸价，不是离岸 CNH。":
      "Quotes are intraday snapshots against the dollar or the euro exactly as the source gives them (refreshed about every 30 minutes, not real time). CNY is the onshore rate, not offshore CNH.",
    "来源 FRED / U.S. Treasury H.15 · 日频 · 某期限当日无观测即留空，不插值":
      "Source: FRED / U.S. Treasury H.15 · daily · a tenor with no observation that day is left blank, never interpolated",
    "来源 FRED / U.S. Treasury H.15 · 30Y-5Y 由曲线现算 · 历史窗口 260 个交易日":
      "Source: FRED / U.S. Treasury H.15 · 30Y−5Y computed from the curve · 260-session history window",
    "十一个期限各取一条 FRED 官方序列、共享日期轴；某期限当日无观测即留空，不插值、不用相邻期限顶替。当前这两条利差都不倒挂。 30Y-5Y 由曲线现算，其余读数直接取官方序列。":
      "Eleven tenors each take one official FRED series on a shared date axis; a tenor with no observation that day is left blank — never interpolated, never substituted with an adjacent tenor. Neither of these two spreads is currently inverted. 30Y−5Y is computed from the curve; every other reading is taken straight from the official series.",
    /* 指数、汇率、商品与信号名都是行业通行叫法（页面里本来就并排着 SPX / DXY / CL
       这类规范代码），按通行英文名写。国债与国名下面用锚定规则拼，不逐国入典。 */
    "终端监控": "Terminal Monitor",
    "宏观风险监测": "Macro Risk Monitor",
    "全球市场行情": "Global Markets",
    "全球监控 ·": "Global Monitor ·",
    "轴": "Axis",
    "分数": "Score",
    "读数": "Reading",
    "信号": "Signal",
    "品类": "Category",
    "指数贡献": "Index Contribution",
    "国别与板块": "Country & Sector",
    "只数": "Count",
    "涨": "Up",
    "跌": "Down",
    "无值": "No value",
    "中位当日": "Median daily",
    "前五 / 后五": "Top 5 / Bottom 5",
    "横截面汇总 Cross-Section": "Cross-Section",
    "经济日历 Event Calendar": "Event Calendar",
    "要闻 News": "News",
    "风险提示 Risk Alerts": "Risk Alerts",
    "数据来源 Data Sources": "Data Sources",
    "建议功能 Suggested": "Suggested",
    "来源 / 数据日期 / 状态": "Source / data date / status",
    "帮助": "Help",
    "待公布": "Pending",
    "© 2026 OOGLEX 金融终端": "© 2026 OOGLEX Finance Terminal",
    "标普500": "S&P 500",
    "纳斯达克综合": "Nasdaq Composite",
    "罗素2000": "Russell 2000",
    "欧元区斯托克50": "Euro Stoxx 50",
    "德国DAX": "DAX",
    "英国富时100": "FTSE 100",
    "日经225": "Nikkei 225",
    "恒生指数": "Hang Seng",
    "沪深300": "CSI 300",
    "标普500波动率": "VIX",
    "美元指数": "Dollar Index",
    "欧元兑美元": "EUR/USD",
    "美元兑日元": "USD/JPY",
    "英镑兑美元": "GBP/USD",
    "美元兑人民币": "USD/CNY",
    "WTI 原油": "WTI Crude",
    "布伦特原油": "Brent Crude",
    "黄金": "Gold",
    "白银": "Silver",
    "铜": "Copper",
    "天然气": "Natural Gas",
    "美国长期国债": "U.S. Long Treasuries",
    "投资级公司债": "Investment-Grade Corporates",
    "高收益债": "High Yield",
    "新兴市场美元主权债": "EM USD Sovereigns",
    "比特币（24h 口径）": "Bitcoin (24h basis)",
    "以太坊（24h 口径）": "Ethereum (24h basis)",
    "流动性": "Liquidity",
    "波动率": "Volatility",
    "期限溢价": "Term Premium",
    "实际利率": "Real Rates",
    "信用利差": "Credit Spreads",
    "增长动能": "Growth Momentum",
    "美元汇率": "Dollar",
    "市场广度": "Market Breadth",
    "能源溢价": "Energy Premium",
    "避险需求": "Safe-Haven Demand",
    "波动率制度": "Volatility Regime",
    "金融压力": "Financial Stress",
    "中性": "Neutral",
    "高": "High",
    "低": "Low",
    "偏高": "Elevated",
    "偏低": "Subdued",
    "10 年期美债收益率": "10-Year Treasury Yield",
    "美联储广义美元指数": "Nominal Broad U.S. Dollar Index",
    "债券波动率": "Bond Volatility",
    "股指波动率": "Equity Volatility",
    "高收益债 OAS": "High-Yield OAS",
    "投资级债 OAS": "Investment-Grade OAS",
    "担保隔夜融资利率": "SOFR",
    "财政部一般账户": "Treasury General Account",
    "隔夜逆回购用量": "Overnight Reverse Repo Volume",
    "芝加哥联储金融状况": "Chicago Fed Financial Conditions",
    "10Y−2Y 期限利差": "10Y−2Y Term Spread",
    "·计算": "· computed",
    "利率": "rates",
    "大类资产收益": "Asset-Class Returns",
    "全球公司股价": "Global Company Prices",
    "商品行情": "Commodities",
    "主权债收益率": "Sovereign Yields",
    "标普热力图": "S&P Heatmap",
    "金融风险监测": "Financial Risk Monitor",
    "恐慌与贪婪": "Fear & Greed",
    "全球经济图谱": "World Economy Map",
    "全球房价": "Global House Prices",
    "全球经济日历": "Global Economic Calendar",
    "相对估值": "Relative Valuation",
    "财务分析": "Financial Analysis",
    "主权利差": "Sovereign Spreads",
    "超级投资者持仓": "Superinvestor Holdings",
    "全球产业链": "Global Supply Chain",
    "全球市值排行": "Global Market-Cap Ranking",
    "福布斯亿万富翁实时排行榜": "Forbes Real-Time Billionaires",
    "数据中心": "Data Center",
    "金融计算器": "Financial Calculators",
    "金融知识架构": "Finance Knowledge Map",
    "组合与持仓": "Portfolios & Holdings",
    "逐笔报价与深度": "Tick Data & Depth",
    "资产互换分析": "Asset-Swap Analysis",
    "期权链与隐含波动": "Option Chains & Implied Vol",
    "资金流向": "Fund Flows",
    "条件告警": "Conditional Alerts",
    "终端问答": "Terminal Q&A",
    "行情（收盘）": "Quotes (close)",
    "行情（盘中快照）": "Quotes (intraday snapshot)",
    "Yahoo Finance · 日频收盘": "Yahoo Finance · daily close",
    "部分缺失": "Partially missing",
    "美债曲线": "Treasury Curve",
    "恐慌贪婪": "Fear & Greed",
    "OFR 金融风险": "OFR Financial Risk",
    "经济日历": "Economic Calendar",
    "加密（CoinGecko）": "Crypto (CoinGecko)",
    "公司（个股）": "Companies (single stocks)",
    "各国主权债收益率": "Sovereign Yields by Country",
    "主权债观测历史": "Sovereign Yield Observation History",
    "证券描述 · Ooglex金融终端": "Security Description · Ooglex Finance Terminal",
    "榜单与趋势 · Ooglex金融终端": "Rankings & Trends · Ooglex Finance Terminal",
    "多标的比较 · Ooglex金融终端": "Multi-Asset Compare · Ooglex Finance Terminal",
    "条件选股与相对估值 · Ooglex金融终端": "Equity Screener & Relative Valuation · Ooglex Finance Terminal",
    "行情详情 · Ooglex金融终端": "Quote Details · Ooglex Finance Terminal",
    "Ooglex金融终端 · 全球市场监控": "Ooglex Finance Terminal · Global Market Monitor",
    "Ooglex金融终端 · 全球市场总览": "Ooglex Finance Terminal · Global Market Overview",
    "选择证券": "Select security",
    "加入标的": "Add Instrument",
    "加入标的比较": "Add instrument to comparison",
    "共同窗口": "Common Window",
    "加入自选": "Add to Watchlist",
    "全区间走势 →": "Full-History Chart →",
    "基本信息": "Basic Information",
    "收益与同业": "Returns & Peers",
    "价格走势": "Price History",
    "标识与口径": "Identifiers & Methodology",
    "发行人与口径": "Issuer & Methodology",
    "财务报表": "Financial Statements",
    "信用评级": "Credit Rating",
    "现金流表": "Cash Flow Statement",
    "期权链": "Options Chain",
    "持股结构": "Ownership Structure",
    "发行人信息": "Issuer Information",
    "标识符": "Identifiers",
    "证券信息": "Security Information",
    "数据状态": "Data Status",
    "近 60 个交易日收盘": "Recent 60 Trading-Day Closes",
    "板块内位置": "Position Within Sector",
    "区间收益": "Period Return",
    "同业对比": "Peer Comparison",
    "收盘价走势": "Close-Price History",
    "全球公司": "Global Companies",
    "大类资产": "Asset Classes",
    "要闻主题": "News Themes",
    "排序口径": "Sort By",
    "涨幅最大": "Top Gainers",
    "跌幅最大": "Top Decliners",
    "变动最大（不论方向）": "Largest Absolute Moves",
    "筛选": "Filter",
    "行数": "Rows",
    "全部": "All",
    "站内没有的趋势维度": "Trend Metrics Not Available On-Site",
    "维度": "Metric",
    "为什么没有": "Why unavailable",
    "当日涨跌": "Daily Change",
    "近一周": "1 Week",
    "近一月": "1 Month",
    "年初至今": "Year to Date",
    "近一年": "1 Year",
    "要闻覆盖": "News Coverage",
    "叠加比较": "Overlay Compare",
    "区间总回报": "Total Return by Period",
    "价差与比值": "Spread & Ratio",
    "回撤": "Drawdown",
    "相关性矩阵": "Correlation Matrix",
    "贝塔与回归": "Beta & Regression",
    "季节性": "Seasonality",
    "自定义篮子": "Custom Basket",
    "清空重选": "Clear & Reselect",
    "归一化叠加 NORMALIZED OVERLAY": "Normalized Overlay",
    "共同窗口内重基到 100": "Rebased to 100 within the common window",
    "小倍数 SMALL MULTIPLES": "Small Multiples",
    "共用同一纵轴，逐个看清": "Shared y-axis for clean side-by-side reading",
    "选两个标的": "Select two instruments",
    "分子标的": "Numerator instrument",
    "分母标的": "Denominator instrument",
    "比值 A/B": "Ratio A/B",
    "归一化差 A−B（均重基 100）": "Normalized Spread A−B (both rebased to 100)",
    "距各自区间内前高的百分比": "Percent below each instrument's prior peak in the selected window",
    "最大回撤": "Max Drawdown",
    "谷底日": "Trough Date",
    "当前距前高": "Current vs. Peak",
    "日收益率，皮尔逊": "Daily returns, Pearson correlation",
    "对基准的最小二乘": "OLS versus benchmark",
    "基准标的": "Benchmark",
    "年化 Alpha": "Annualized Alpha",
    "日波动(年化)": "Daily Volatility (Annualized)",
    "重叠样本": "Overlapping Samples",
    "条件选股": "Equity Screener",
    "条件选股与相对估值": "Equity Screener & Relative Valuation",
    "命中": "Matches",
    "可算比率": "Ratios Available",
    "报表期末": "Statement End",
    "清空条件": "Clear Filters",
    "板块分布": "Sector Distribution",
    "覆盖面与口径": "Coverage & Methodology",
    "筛选条件 SCREEN CRITERIA": "Screen Criteria",
    "留空即不限": "Leave blank for no limit",
    "完整度": "Completeness",
    "任一比率可算即可": "At least one ratio available",
    "六项全齐": "All six ratios available",
    "命中结果 RESULTS": "Screen Results",
    "净利率%": "Net Margin %",
    "负债率%": "Debt / Assets %",
    "相对本板块中位": "Relative to sector median",
    "相对中位": "vs. Median",
    "板块分布 SECTOR MEDIANS": "Sector Medians",
    "逐板块的中位与样本数": "Median values and sample counts by sector",
    "家数": "Companies",
    "覆盖面 COVERAGE": "Coverage",
    "每一项能算多少家，以及为什么算不了": "How many companies support each metric and why others do not",
    "项": "Metric",
    "可算家数": "Companies Available",
    "占可用": "% Available",
    "口径 METHOD": "Methodology",
    "随数据一起给出，不是页面上另写的": "Delivered with the data, not separately invented by the page",
    "← 全球市场行情": "← Global Markets",
    "金融终端": "Finance Terminal",
    "正在读取站内日更管道中的该标的…": "Loading this instrument from the site's daily pipeline…",
    "此页面需要启用JavaScript才能读取站内日更管道中的行情与历史序列。": "JavaScript is required to load the site's daily quote and historical-series data.",
    "1个月": "1 Month",
    "3个月": "3 Months",
    "6个月": "6 Months",
    "1年": "1 Year",
    "5年": "5 Years",
    "10年": "10 Years",
    "25年": "25 Years",
    "3天": "3 Days",
    "1周": "1 Week",
    "2周": "2 Weeks",
    "指数": "Index",
    "商品": "Commodity",
    "外汇": "FX",
    "债券": "Bond",
    "较前一交易日收盘": "vs. previous trading-day close",
    "在 Yahoo Finance 打开原始行情页": "Open the original quote page on Yahoo Finance"
  };

  var LEGAL = {
    "使用条款 · Ooglex金融终端": "Terms of Use · Ooglex Finance Terminal",
    "隐私政策 · Ooglex金融终端": "Privacy Policy · Ooglex Finance Terminal",
    "生效及最近更新：2026-08-14": "Effective and last updated: 2026-08-14",
    "1. 产品性质与适用范围": "1. Product Nature and Scope",
    "2. 数据口径与可用性": "2. Data Methodology and Availability",
    "3. CoinGecko与其他第三方权利": "3. CoinGecko and Other Third-Party Rights",
    "4. 用户行为规则": "4. User Conduct",
    "5. 数字资产特别风险": "5. Digital-Asset Risks",
    "6. 责任与免责声明": "6. Liability and Disclaimer",
    "7. 外部链接与条款更新": "7. External Links and Terms Updates",
    "8. 问题反馈": "8. Issue Reporting",
    "1. 当前不主动收集的内容": "1. Information We Do Not Actively Collect",
    "2. 访问与技术信息": "2. Access and Technical Information",
    "3. 第三方数据与组件": "3. Third-Party Data and Components",
    "4. 使用目的与披露": "4. Purposes and Disclosure",
    "5. Cookie、本地存储与您的选择": "5. Cookies, Local Storage and Your Choices",
    "6. 保留、安全与跨境处理": "6. Retention, Security and Cross-Border Processing",
    "7. 儿童、更新与联系": "7. Children, Updates and Contact",
    "本产品是面向公众的跨资产研究信息页，不提供券商账户、交易执行、托管、个性化投资建议或收益保证。页面内容仅供一般信息与学习研究使用，不构成证券、数字资产或其他金融产品的要约、招揽、推荐或投资策略。": "This product is a public cross-asset research information page. It does not provide brokerage accounts, trade execution, custody, personalized investment advice, or return guarantees. Content is for general information, learning, and research only and does not constitute an offer, solicitation, recommendation, or investment strategy for securities, digital assets, or other financial products.",
    "页面会尽力显示来源、数据日、更新时间、频率以及正常、降级、过期、不可用或提供方代理状态。": "The page aims to show source, data date, update time, frequency, and whether a feed is normal, degraded, stale, unavailable, or represented by a provider proxy.",
    "数据可能延迟、缺失、不准确、中断或与其他来源存在差异；“更新健康”不等于行情实时或市场开市。": "Data may be delayed, missing, inaccurate, interrupted, or differ from other sources; an 'update healthy' status does not mean quotes are real-time or the market is open.",
    "用户应在作出任何金融决定前自行核对原始来源并承担全部决定与结果。": "Users should independently verify original sources before making any financial decision and remain responsible for their decisions and outcomes.",
    "您不得利用本产品或其第三方数据进行违法、欺诈、侵权、骚扰或歧视活动，也不得：": "You may not use this product or its third-party data for unlawful, fraudulent, infringing, harassing, or discriminatory activity, and you may not:",
    "出售、出租、转授权、再分发、联合供稿或提供对CoinGecko API或其他提供方数据的替代访问；": "sell, rent, sublicense, redistribute, syndicate, or provide substitute access to the CoinGecko API or other provider data;",
    "绕过访问限制、速率限制、安全措施或技术保护，干扰、探测或降低任何提供方服务性能；": "bypass access restrictions, rate limits, security measures, or technical protections, or interfere with, probe, or degrade any provider service;",
    "逆向工程、批量抓取、复制或保存超出本产品公开功能与第三方条款允许范围的数据；": "reverse engineer, bulk-scrape, copy, or store data beyond the scope allowed by the product's public functionality and applicable third-party terms;",
    "删除来源归属，或以任何方式暗示Ooglex由CoinGecko或其他提供方认可、赞助或关联。": "remove source attribution or imply that Ooglex is endorsed, sponsored, or affiliated with CoinGecko or another provider.",
    "加密资产价格高度波动，市场可能全天候快速变化。日度快照、24小时变化或历史回退都可能明显落后于当前市场。您不得仅依赖本产品或CoinGecko API数据作出交易、借贷、税务或投资决定。": "Crypto-asset prices are highly volatile and markets can move rapidly around the clock. Daily snapshots, 24-hour changes, or historical fallback data may materially lag the current market. Do not rely solely on this product or CoinGecko API data for trading, lending, tax, or investment decisions.",
    "外部网站由其各自运营者控制，并适用其自身条款与隐私政策。本条款可能随产品、法律或数据提供方要求更新；继续使用更新后的产品表示接受更新。重大变更会在本页更新日期。": "External websites are controlled by their respective operators and are subject to their own terms and privacy policies. These terms may be updated as the product, law, or provider requirements change; continued use after an update constitutes acceptance. Material changes will update the date on this page.",
    "本政策说明Ooglex金融终端（以下简称“本产品”）如何处理与访问有关的信息。使用本产品即表示您已阅读本政策；与第三方网站或组件的交互还适用其自身政策。": "This policy explains how Ooglex Finance Terminal (the 'Product') handles information related to access. By using the Product, you acknowledge that you have read this policy; interactions with third-party sites or components are also governed by their own policies.",
    "本产品当前是无需注册的静态Public Beta，不提供账户、支付、券商连接、投资组合录入、评论或消息功能。终端页面本身不要求您提交姓名、邮箱、电话、身份证明、API密钥、持仓或交易记录，也不把这些内容写入本产品数据库。": "The Product is currently a static Public Beta that requires no registration. It does not provide accounts, payments, brokerage connections, portfolio entry, comments, or messaging. The terminal itself does not ask you to submit your name, email, phone number, identity documents, API keys, holdings, or transaction records, and does not write such information to a Product database.",
    "网站托管、内容分发或安全服务可能按其运行需要处理IP地址、浏览器与设备类型、请求URL、时间、来源页、响应状态和安全事件日志，用于提供页面、诊断故障、防止滥用和维护安全。此类日志由相关服务商按其政策和保留规则处理。": "Hosting, content-delivery, or security providers may process IP addresses, browser and device type, requested URL, time, referrer, response status, and security-event logs as required to serve pages, diagnose failures, prevent abuse, and maintain security. Such logs are handled by those providers under their own policies and retention rules.",
    "本产品仅为提供静态页面、加载已披露的提供方组件、维护安全、排查错误和改进可靠性而处理必要的技术信息。Ooglex不会将终端页面主动收集的个人资料出售或用于自动化投资决策；因当前页面没有用户账户或输入表单，也不会把用户资料共享给CoinGecko。": "The Product processes only technical information necessary to serve static pages, load disclosed provider components, maintain security, troubleshoot errors, and improve reliability. Ooglex does not sell personal information actively collected by the terminal or use it for automated investment decisions; because the current terminal has no user accounts or input forms, it does not share user profile data with CoinGecko.",
    "终端应用代码当前不使用本地存储保存用户账户、持仓或偏好。浏览器、托管服务或TradingView等第三方仍可能使用缓存、Cookie或类似技术。您可以在浏览器中阻止或清除这些数据，也可以不加载组件、不点击外部链接或停止使用本产品；部分功能可能因此不可用。": "The terminal application currently does not use local storage to save user accounts or holdings. Browsers, hosting services, or third parties such as TradingView may still use caches, cookies, or similar technologies. You can block or clear such data in your browser, avoid loading components or external links, or stop using the Product; some functionality may then be unavailable.",
    "Ooglex不维护终端用户账户数据库。托管和第三方提供方可能在其运营地区处理并按自身规则保留安全或访问日志。我们采用最小权限、无前端密钥、公开来源白名单和机器校验降低风险，但任何互联网服务都无法保证绝对安全。": "Ooglex does not maintain a terminal-user account database. Hosting and third-party providers may process and retain security or access logs in their operating regions under their own rules. We reduce risk through least privilege, no front-end secrets, public-source allowlists, and automated validation, but no internet service can guarantee absolute security."
  };

  var CALC = {
    "金融理财": "Finance",
    "健康身体": "Health",
    "数学几何": "Math & Geometry",
    "单位换算": "Unit Conversion",
    "物理": "Physics",
    "化学": "Chemistry",
    "日常生活": "Daily Life",
    "实用工具": "Utilities",
    "计 算": "Calculate",
    "统 计": "Count",
    "← 算集首页": "← Calculator Home",
    "← 返回列表": "← Back to List",
    "没有匹配的计算器，换个关键词试试～": "No matching calculator. Try another keyword.",
    "请检查输入是否完整、有效": "Please check that all required inputs are complete and valid.",
    "房贷计算器": "Mortgage Calculator",
    "通用贷款计算器": "Loan Calculator",
    "复利计算器": "Compound Interest Calculator",
    "单利计算器": "Simple Interest Calculator",
    "个税估算器": "Income Tax Estimator",
    "储蓄目标计算器": "Savings Goal Calculator",
    "投资回报率 ROI": "Investment ROI",
    "通货膨胀计算器": "Inflation Calculator",
    "折扣计算器": "Discount Calculator",
    "小费计算器": "Tip Calculator",
    "含税价 / 税额": "Tax-Inclusive Price / Tax",
    "BMI 计算器": "BMI Calculator",
    "热量计算器": "Calorie Calculator",
    "体脂率估算": "Body Fat Estimator",
    "理想体重": "Ideal Weight",
    "每日饮水量": "Daily Water Intake",
    "目标心率区间": "Target Heart-Rate Zones",
    "最大心率": "Maximum Heart Rate",
    "预产期计算器": "Due Date Calculator",
    "排卵期计算器": "Ovulation Calculator",
    "酒精代谢估算": "Alcohol Metabolism Estimate",
    "每日蛋白质需求": "Daily Protein Needs",
    "配速计算器": "Pace Calculator",
    "百分比计算器": "Percentage Calculator",
    "平均数 / 统计": "Average / Statistics",
    "最大公约 / 最小公倍": "GCD / LCM",
    "一元二次方程": "Quadratic Equation",
    "三角形计算器": "Triangle Calculator",
    "圆的计算器": "Circle Calculator",
    "阶乘计算器": "Factorial Calculator",
    "排列组合": "Permutations & Combinations",
    "比例求解": "Ratio Solver",
    "质数判断": "Prime Number Test",
    "对数计算器": "Logarithm Calculator",
    "等差数列求和": "Arithmetic Sequence Sum",
    "温度换算": "Temperature Conversion",
    "速度 · 距离 · 时间": "Speed · Distance · Time",
    "牛顿第二定律": "Newton's Second Law",
    "动能计算器": "Kinetic Energy Calculator",
    "重力势能": "Gravitational Potential Energy",
    "欧姆定律": "Ohm's Law",
    "密度计算器": "Density Calculator",
    "压强计算器": "Pressure Calculator",
    "功率计算器": "Power Calculator",
    "自由落体": "Free Fall",
    "摩尔浓度": "Molar Concentration",
    "溶液稀释": "Solution Dilution",
    "理想气体定律": "Ideal Gas Law",
    "pH ↔ [H⁺]": "pH ↔ [H⁺]",
    "质量 ↔ 摩尔": "Mass ↔ Moles",
    "年龄计算器": "Age Calculator",
    "日期计算器": "Date Calculator",
    "倒数日 / 纪念日": "Countdown / Anniversary",
    "油费计算器": "Fuel Cost Calculator",
    "科学计算器": "Scientific Calculator",
    "密码生成器": "Password Generator",
    "随机决定器": "Random Decision Maker",
    "进制转换器": "Base Converter",
    "罗马数字转换": "Roman Numeral Converter",
    "文本字数统计": "Text / Word Count",
    "性别": "Sex",
    "男": "Male",
    "女": "Female",
    "年龄": "Age",
    "身高（厘米）": "Height (cm)",
    "体重（公斤）": "Weight (kg)",
    "模式": "Mode",
    "目标": "Goal",
    "数值": "Value",
    "原单位": "From Unit",
    "当前进制": "Current Base",
    "长度": "Length",
    "求解目标": "Solve For",
    "时间（秒）": "Time (seconds)",
    "距离（米）": "Distance (m)",
    "速度（米/秒）": "Speed (m/s)",
    "质量（千克）": "Mass (kg)",
    "加速度（米/秒²）": "Acceleration (m/s²)",
    "高度（米）": "Height (m)",
    "重力加速度 g": "Gravitational Acceleration g",
    "电压（伏特）": "Voltage (V)",
    "电流（安培）": "Current (A)",
    "电阻（欧姆）": "Resistance (Ω)",
    "体积（立方米）": "Volume (m³)",
    "压力（牛顿）": "Force (N)",
    "受力面积（平方米）": "Area (m²)",
    "做功 / 能量（焦耳）": "Work / Energy (J)",
    "下落时间（秒）": "Fall Time (seconds)",
    "溶质物质的量（摩尔）": "Amount of Solute (mol)",
    "溶液体积（升）": "Solution Volume (L)",
    "初始浓度 C₁": "Initial Concentration C₁",
    "初始体积 V₁（mL）": "Initial Volume V₁ (mL)",
    "目标浓度 C₂": "Target Concentration C₂",
    "压强（帕）": "Pressure (Pa)",
    "物质的量（摩尔）": "Amount of Substance (mol)",
    "出生日期": "Date of Birth",
    "起始日期": "Start Date",
    "目标日期": "Target Date",
    "行驶距离（公里）": "Distance (km)",
    "贷款总额（万元）": "Loan Amount (¥10k)",
    "贷款金额（元）": "Loan Amount (CNY)",
    "年利率（%）": "Annual Interest Rate (%)",
    "贷款年限": "Loan Term (Years)",
    "还款方式": "Repayment Method",
    "本金（元）": "Principal (CNY)",
    "年数": "Years",
    "投入成本（元）": "Initial Cost (CNY)",
    "最终回收（元）": "Final Value (CNY)",
    "投资年数（选填）": "Investment Years (Optional)",
    "金额（元）": "Amount (CNY)",
    "年通胀率（%）": "Annual Inflation Rate (%)",
    "原价（元）": "Original Price (CNY)",
    "账单金额（元）": "Bill Amount (CNY)",
    "小费比例（%）": "Tip (%)",
    "分账人数": "People Splitting Bill",
    "不含税金额（元）": "Pre-Tax Amount (CNY)",
    "税率（%）": "Tax Rate (%)"
  };

  var AI = {
    "新对话": "New chat",
    "🧠 大聪明（云端 · 免费 · 打开即用）": "🧠 Cloud AI (free · ready to use)",
    "🤖 小机灵（本机运行 · 免密钥 · 电脑用）": "🤖 Local AI (on-device · no key · desktop)",
    "离线小智（断网应急 · 小玩具）": "Offline Mini AI (offline fallback)",
    "自定义接口（高级 · 自带密钥）": "Custom Endpoint (advanced · bring your own key)",
    "内置规则引擎": "Built-in rule engine",
    "😀 离线小智 · 断网应急": "😀 Offline Mini AI · Offline fallback",
    "🧠 大聪明 · 云端免费 · 打开即用": "🧠 Cloud AI · Free · Ready to use",
    "大聪明暂未开通 —— 点 ⚙️ 设置换「小机灵」": "Cloud AI is not enabled yet — open ⚙️ Settings to switch to Local AI",
    "🤖 小机灵 · 本机运行": "🤖 Local AI · Running on this device",
    "· 已就绪": "· Ready",
    "· 首次使用需下载": "· First use requires a download",
    "🔧 自定义接口 ·": "🔧 Custom Endpoint ·",
    "未填模型": "No model specified",
    "尚未配置 —— 点右上角 ⚙️ 设置": "Not configured — open ⚙️ Settings in the top-right"
  };

  var TERM_PHRASES = [
    ["筛选：代码 / 名称 / 板块 / 国别", "Filter: ticker / name / sector / country"],
    ["输入助记符 / 编号 / 代码后回车", "Enter mnemonic / number / ticker, then press Enter"],
    ["输入助记符 / 代码后回车", "Enter mnemonic / ticker, then press Enter"],
    ["输入助记符 / 编号后回车", "Enter mnemonic / number, then press Enter"],
    ["基本信息", "Basic Information"], ["收益与同业", "Returns & Peers"],
    ["价格走势", "Price History"], ["标识与口径", "Identifiers & Methodology"],
    ["条件选股", "Equity Screener"], ["板块分布", "Sector Distribution"],
    ["覆盖面与口径", "Coverage & Methodology"], ["要闻覆盖", "News Coverage"],
    ["近一周", "1 Week"], ["近一月", "1 Month"], ["年初至今", "Year to Date"], ["近一年", "1 Year"],
    ["共同窗口", "Common Window"], ["有效点", "Valid Points"], ["读取中", "Loading"],
    ["页", "Page"]
  ];

  var CALC_PHRASES = [
    ["个计算器", "calculators"],
    ["搜索“", "Search results for “"], ["” 的结果", "”"],
    ["共 ", "Total "], [" 大类，点分类进入或直接搜索", " categories · choose a category or search directly"],
    ["每月月供：", "Monthly payment: "], ["支付利息总额：", "Total interest: "], ["还款总额：", "Total repayment: "],
    ["首月月供：", "First-month payment: "], ["末月月供：", "Last-month payment: "], ["每月递减约", "Monthly decrease approx."],
    ["每月还款：", "Monthly payment: "], ["总利息：", "Total interest: "], ["总还款", "Total repayment"],
    ["到期总额：", "Ending value: "], ["累计投入：", "Total contributions: "], ["利息收益：", "Interest gain: "],
    ["收益率", "Return"], ["利息：", "Interest: "], ["本息合计：", "Principal + interest: "],
    ["应纳税所得额（年）：", "Annual taxable income: "], ["全年个税约：", "Estimated annual tax: "], ["平均每月：", "Monthly average: "],
    ["税后月入约", "Estimated monthly after-tax income"], ["预计需要：", "Estimated time needed: "], ["净收益：", "Net gain: "],
    ["总回报率 ROI：", "Total ROI: "], ["年化收益率：", "Annualized return: "], ["现价：", "Discounted price: "], ["已省：", "You save: "],
    ["小费：", "Tip: "], ["合计：", "Total: "], ["每人", "Per person"], ["税额：", "Tax: "], ["含税价：", "Tax-inclusive price: "],
    ["基础代谢（BMR）：", "Basal metabolic rate (BMR): "], ["每日总消耗（TDEE）：", "Total daily energy expenditure (TDEE): "],
    ["体脂率（估算）：", "Estimated body fat: "], ["理想体重（Devine）：", "Ideal weight (Devine): "], ["建议每日饮水：", "Suggested daily water intake: "],
    ["预产期：", "Estimated due date: "], ["当前孕周：", "Current gestational age: "], ["排卵日：", "Estimated ovulation date: "],
    ["易孕期：", "Fertile window: "], ["血液酒精浓度（估算）：", "Estimated blood alcohol concentration: "], ["状态：", "Status: "],
    ["每日蛋白质建议：", "Suggested daily protein: "], ["配速：", "Pace: "], ["时速", "Speed"],
    ["平均数", "Mean"], ["中位数", "Median"], ["最大 / 最小", "Max / Min"], ["标准差（总体）", "Population standard deviation"],
    ["最大公约数 GCD：", "Greatest common divisor (GCD): "], ["最小公倍数 LCM：", "Least common multiple (LCM): "],
    ["周长", "Perimeter"], ["面积", "Area"], ["直径", "Diameter"], ["排列", "Permutation"], ["组合", "Combination"],
    ["判别式", "Discriminant"], ["是质数", "is prime"], ["不是质数", "is not prime"],
    ["摩尔浓度", "Molar concentration"], ["稀释后总体积", "Final diluted volume"], ["需加溶剂（水）", "Solvent (water) to add"],
    ["力 F", "Force F"], ["动能", "Kinetic energy"], ["重力势能", "Gravitational potential energy"], ["电压 V", "Voltage V"],
    ["电流 I", "Current I"], ["电阻 R", "Resistance R"], ["密度", "Density"], ["压强", "Pressure"], ["功率", "Power"],
    ["下落高度", "Fall distance"], ["落地速度", "Impact speed"]
  ];

  var AI_PHRASES = [
    ["大聪明", "Cloud AI"], ["小机灵", "Local AI"], ["离线小智", "Offline Mini AI"], ["自定义", "Custom"],
    [" · 已就绪", " · Ready"], [" · 首次使用需下载", " · First use requires a download"]
  ];

  function dictionary() {
    var out = {};
    Object.keys(COMMON).forEach(function (k) { out[k] = COMMON[k]; });
    if (isTerminal()) {
      Object.keys(TERMINAL).forEach(function (k) { out[k] = TERMINAL[k]; });
      Object.keys(LEGAL).forEach(function (k) { out[k] = LEGAL[k]; });
    }
    if (isCalculator()) Object.keys(CALC).forEach(function (k) { out[k] = CALC[k]; });
    if (isAiChat()) Object.keys(AI).forEach(function (k) { out[k] = AI[k]; });
    return out;
  }

  function phrases() {
    if (isTerminal()) return TERM_PHRASES;
    if (isCalculator()) return CALC_PHRASES;
    if (isAiChat()) return AI_PHRASES;
    return [];
  }

  /* 两端锚定的规则：整串进不了字典的拼接句（国债名、来源行、走势详情的 aria-label）。
     数字、日期与代码原样带回，国名查字典，查不到就保留原文。 */
  function termRegex(s, dict) {
    var m;
    if (!isTerminal()) return null;
    if ((m = /^(.+?)(\d+)年期国债$/.exec(s))) return (dict[m[1]] || m[1]) + " " + m[2] + "-Year Government Bond";
    if ((m = /^基准 (.+?)(\d+)年期国债（(.+?)）$/.exec(s))) {
      return "Benchmark: " + (dict[m[1]] || m[1]) + " " + m[2] + "-Year Government Bond (" + m[3] + ")";
    }
    if ((m = /^基准 欧元区AAA国债曲线(\d+)年（(.+?)）$/.exec(s))) {
      return "Benchmark: Euro Area AAA government curve, " + m[1] + "-year (" + m[2] + ")";
    }
    if ((m = /^欧元区AAA国债曲线(\d+)年$/.exec(s))) return "Euro Area AAA government curve, " + m[1] + "-year";
    if ((m = /^盘中 (.+)$/.exec(s))) return "Intraday " + m[1];
    if ((m = /^打开 (.+?) 的走势详情$/.exec(s))) return "Open the chart detail for " + (dict[m[1]] || m[1]);
    if ((m = /^打开 (.+?) 期美债收益率的走势详情$/.exec(s))) return "Open the chart detail for the " + m[1] + " Treasury yield";
    if ((m = /^(\d+) 条$/.exec(s))) return m[1] + " alerts";
    if ((m = /^已接入 (\d+) · 规划中 (\d+)$/.exec(s))) return m[1] + " live · " + m[2] + " planned";
    if ((m = /^(\d+) \/ 100 · (.+)$/.exec(s))) return m[1] + " / 100 · " + (dict[m[2]] || m[2]);
    if ((m = /^权重 (\d+%)$/.exec(s))) return "Weight " + m[1];
    if ((m = /^就地展开 (.+?) 的历史分位（([\d,]+) 点）$/.exec(s))) {
      return "Expand the historical percentile of " + (dict[m[1]] || m[1]) + " in place (" + m[2] + " points)";
    }
    /* 功能目录的两种写法：「CODE 名称 · 类别\n说明」与「名称 · 说明」。
       三段都查字典，任何一段查不到就整条放弃，不交出半中半英。 */
    if ((m = /^([A-Z]{2,5}) (.+?) · (.+?)\n([\s\S]+)$/.exec(s))) {
      if (dict[m[2]] && dict[m[3]] && dict[m[4]]) {
        return m[1] + " " + dict[m[2]] + " · " + dict[m[3]] + "\n" + dict[m[4]];
      }
    }
    if ((m = /^(.+?) · ([\s\S]+)$/.exec(s)) && dict[m[1]] && dict[m[2]]) {
      return dict[m[1]] + " · " + dict[m[2]];
    }
    if ((m = /^(.+?)(\d+)年期国债 收益率历史$/.exec(s))) {
      return (dict[m[1]] || m[1]) + " " + m[2] + "-Year Government Bond yield history";
    }
    if ((m = /^欧元区AAA国债曲线(\d+)年 收益率历史$/.exec(s))) {
      return "Euro Area AAA government curve, " + m[1] + "-year — yield history";
    }
    if ((m = /^([+\-−][\d.,]+bp) (高|低|中)$/.exec(s))) {
      return m[1] + " " + ({ "高": "high", "低": "low", "中": "mid" })[m[2]];
    }
    if ((m = /^综合 (\d+) \/ 100 · 等级「(.+?)」· 四条轴等权 · AS OF (.+)$/.exec(s))) {
      return "Composite " + m[1] + " / 100 · grade “" + (dict[m[2]] || m[2]) +
        "” · four equally weighted axes · AS OF " + m[3];
    }
    if ((m = /^合计 (\d+) 个标的 · 有当日值 (\d+) 个 · 涨 (\d+) \/ 跌 (\d+)$/.exec(s))) {
      return m[1] + " instruments in total · " + m[2] + " with a value today · " + m[3] + " up / " + m[4] + " down";
    }
    if ((m = /^(\S+) 短端利率周环比 (\S+)（(.+?)）$/.exec(s))) {
      return m[1] + " short-rate change, week over week " + m[2] +
        " (" + (m[3] === "加息定价升温、边际收紧" ? "more tightening priced in; marginally tighter"
              : m[3] === "降息定价升温、边际宽松" ? "more easing priced in; marginally looser" : m[3]) + ")";
    }
    if ((m = /^(\S+) 实际利率周环比 (\S+)（(.+?)）$/.exec(s))) {
      return m[1] + " real-rate change, week over week " + m[2] +
        " (" + (m[3] === "贴现率急升、压制久期资产" ? "discount rates jumping; pressure on long-duration assets"
              : m[3] === "贴现率回落、利好久期资产" ? "discount rates falling; supportive for long-duration assets" : m[3]) + ")";
    }
    if ((m = /^(\d+) 个标的 · (.+)$/.exec(s))) return m[1] + " instruments · " + m[2];
    if ((m = /^来源 (.+?) · AS OF (.+?) · 日频收盘 · 状态 (.+?)(?: · (.+))?$/.exec(s))) {
      var tail = m[4] ? " · " + m[4]
        .replace(/LAST 为盘中快照（约 30 分钟刷新、非实时）/, "LAST is an intraday snapshot (refreshed about every 30 minutes, not real time)")
        .replace(/\* 在岸 CNY，非离岸 CNH/, "* onshore CNY, not offshore CNH")
        .replace(/均为期货合约代理/, "all are futures-contract proxies") : "";
      if (!/[\u4e00-\u9fff]/.test(tail)) {
        return "Source: " + m[1] + " · AS OF " + m[2] + " · daily close · status " +
          (dict[m[3]] || m[3]) + tail;
      }
    }
    return null;
  }

  function translateRaw(raw) {
    if (raw == null) return raw;
    var dict = dictionary();
    if (Object.prototype.hasOwnProperty.call(dict, raw)) return dict[raw];
    var rx = termRegex(raw, dict);
    if (rx) return rx;
    var out = raw;
    phrases().forEach(function (pair) { if (out.indexOf(pair[0]) >= 0) out = out.split(pair[0]).join(pair[1]); });
    return out;
  }

  function translatePreserveSpace(raw) {
    var m = String(raw).match(/^(\s*)([\s\S]*?)(\s*)$/);
    if (!m || !m[2]) return raw;
    return m[1] + translateRaw(m[2]) + m[3];
  }

  function skipElement(el) {
    if (!el || el.nodeType !== 1) return false;
    if (el.matches("script,style,noscript,pre,code,textarea,[contenteditable='true'],[data-no-i18n]")) return true;
    if (isAiChat() && el.closest(".bubble, .conv .t")) return true;
    return false;
  }

  function translateText(node) {
    if (!node || node.nodeType !== 3 || !node.parentElement || skipElement(node.parentElement)) return;
    var live = node.data;
    if (!live || !live.trim()) return;
    var last = textLast.get(node);
    var orig = textOrig.get(node);
    if (current === "en") {
      if (last !== undefined && live === last) return;
      if (orig === undefined || (last !== undefined && live !== last)) {
        textOrig.set(node, live); orig = live;
        if (textTouched.indexOf(node) < 0) textTouched.push(node);
      }
      var tr = translatePreserveSpace(orig);
      if (tr !== live) node.data = tr;
      textLast.set(node, tr);
    } else if (orig !== undefined) {
      if (live === last || live === translatePreserveSpace(orig)) node.data = orig;
      textLast.delete(node);
    }
  }

  function translateAttrs(el) {
    if (!el || el.nodeType !== 1 || skipElement(el)) return;
    ATTRS.forEach(function (name) {
      if (!el.hasAttribute(name)) return;
      var live = el.getAttribute(name);
      var bag = attrOrig.get(el) || {};
      var lastBag = attrLast.get(el) || {};
      if (current === "en") {
        if (Object.prototype.hasOwnProperty.call(lastBag, name) && live === lastBag[name]) return;
        if (!Object.prototype.hasOwnProperty.call(bag, name) ||
            (Object.prototype.hasOwnProperty.call(lastBag, name) && live !== lastBag[name])) {
          bag[name] = live;
          attrOrig.set(el, bag);
          if (attrTouched.indexOf(el) < 0) attrTouched.push(el);
        }
        var tr = translateRaw(bag[name]);
        if (tr !== live) el.setAttribute(name, tr);
        lastBag[name] = tr;
        attrLast.set(el, lastBag);
      } else if (Object.prototype.hasOwnProperty.call(bag, name)) {
        if (!Object.prototype.hasOwnProperty.call(lastBag, name) || live === lastBag[name]) el.setAttribute(name, bag[name]);
        delete lastBag[name];
        attrLast.set(el, lastBag);
      }
    });
  }

  function walk(root) {
    if (!root) return;
    if (root.nodeType === 3) { translateText(root); return; }
    if (root.nodeType !== 1 && root.nodeType !== 9 && root.nodeType !== 11) return;
    if (root.nodeType === 1 && skipElement(root)) return;
    if (root.nodeType === 1) translateAttrs(root);
    var w = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT);
    var n;
    while ((n = w.nextNode())) {
      if (n.nodeType === 1) {
        if (skipElement(n)) { try { w.currentNode = n; } catch (e) {} continue; }
        translateAttrs(n);
      } else translateText(n);
    }
  }

  var SEO = {
    "/apps/finance-terminal/": ["Ooglex Finance Terminal · Global Market Monitor", "Ooglex Finance Terminal monitors global indices, U.S. Treasury yields and curve, FX, commodities, macro risk, cross-asset strength, economic events, news, credit and crypto with source and freshness labels."],
    "/apps/finance-terminal/security.html": ["Security Description · Ooglex Finance Terminal", "Security detail page with issuer and instrument information, identifiers, period returns, peer comparison and closing-price history, with source, date, frequency and status labels."],
    "/apps/finance-terminal/trends.html": ["Rankings & Trends · Ooglex Finance Terminal", "Rank global companies by daily, weekly, monthly and YTD change, market cap and on-site news coverage, with explicit disclosure for unavailable metrics."],
    "/apps/finance-terminal/compare.html": ["Multi-Asset Compare · Ooglex Finance Terminal", "Compare aligned closing-price series across companies and cross-asset instruments with normalized overlays, spreads/ratios, drawdowns, total returns, correlations and regressions."],
    "/apps/finance-terminal/screen.html": ["Equity Screener & Relative Valuation · Ooglex Finance Terminal", "Screen companies using PE, PB, PS, ROE, net margin and debt ratios calculated from disclosed SEC XBRL statement fields with explicit dates and missing-data treatment."],
    "/apps/finance-terminal/quote.html": ["Quote Details · Ooglex Finance Terminal", "Full-history detail page for a single instrument, with daily and available four-hour series, source, data date, update time and methodology."],
    "/apps/finance-terminal/terms.html": ["Terms of Use · Ooglex Finance Terminal", "Ooglex Finance Terminal Public Beta terms covering data sources, third-party rights, risk, liability and user conduct."],
    "/apps/finance-terminal/privacy.html": ["Privacy Policy · Ooglex Finance Terminal", "Ooglex Finance Terminal Public Beta privacy policy covering technical data processing, hosting logs, third-party components, external links and user choices."],
    "/apps/finance-terminal/legacy.html": ["Ooglex Finance Terminal · Global Market Overview", "A compact global market overview with market benchmarks, macro state, data methodology and update timestamps."],
    "/apps/calculators/": ["Ooglex Calculators · Finance, Health, Math & Utilities", "A browser-based collection of calculators for finance, health, math, unit conversion, physics, chemistry and everyday tasks."],
    "/apps/ai-chat/": ["Ooglex AI Chat", "A lightweight AI chat interface supporting cloud, on-device, offline fallback and custom OpenAI-compatible endpoints."]
  };

  var seoOrig = null;
  function meta(sel) { return document.querySelector(sel); }
  function captureSeo() {
    if (seoOrig) return;
    seoOrig = { title: document.title };
    ["description", "og:title", "og:description"].forEach(function (k) {
      var el = k.indexOf("og:") === 0 ? meta('meta[property="' + k + '"]') : meta('meta[name="' + k + '"]');
      seoOrig[k] = el ? el.getAttribute("content") : null;
    });
  }
  function applySeo() {
    captureSeo();
    var conf = SEO[path];
    if (current === "en" && conf) {
      document.title = conf[0];
      var desc = meta('meta[name="description"]'); if (desc) desc.setAttribute("content", conf[1]);
      var ogt = meta('meta[property="og:title"]'); if (ogt) ogt.setAttribute("content", conf[0]);
      var ogd = meta('meta[property="og:description"]'); if (ogd) ogd.setAttribute("content", conf[1]);
    } else if (seoOrig) {
      document.title = seoOrig.title;
      var d = meta('meta[name="description"]'); if (d && seoOrig.description != null) d.setAttribute("content", seoOrig.description);
      var t = meta('meta[property="og:title"]'); if (t && seoOrig["og:title"] != null) t.setAttribute("content", seoOrig["og:title"]);
      var o = meta('meta[property="og:description"]'); if (o && seoOrig["og:description"] != null) o.setAttribute("content", seoOrig["og:description"]);
    }
  }

  function apply(lang) {
    if (applying) return;
    applying = true;
    try {
      current = lang === "en" ? "en" : "zh";
      document.documentElement.lang = current === "en" ? "en" : "zh-CN";
      document.documentElement.setAttribute("data-lang", current);
      walk(document.body || document.documentElement);
      applySeo();
    } finally { applying = false; }
  }

  var observer = new MutationObserver(function (records) {
    if (applying || current !== "en") return;
    applying = true;
    try {
      records.forEach(function (r) {
        if (r.type === "characterData") translateText(r.target);
        else if (r.type === "attributes") translateAttrs(r.target);
        else Array.prototype.forEach.call(r.addedNodes || [], walk);
      });
    } finally { applying = false; }
  });

  function boot() {
    captureSeo();
    apply(readLang());
    observer.observe(document.documentElement, { subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ATTRS });
    document.addEventListener("ooglex:languagechange", function (e) {
      var lang = e && e.detail && e.detail.language;
      apply(lang === "en" ? "en" : readLang());
    });
    window.addEventListener("storage", function (e) { if (e.key === KEY) apply(readLang()); });
    window.addEventListener("pageshow", function () { apply(readLang()); });
  }

  window.OoglexI18nWave5 = { apply: apply, translate: translateRaw };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot, { once: true });
  else boot();
})();
