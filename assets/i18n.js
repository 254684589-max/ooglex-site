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
    /* 国名与行业是榜单的筛选/标注维度，属界面，翻；人名与公司名是数据，不翻。
       两张表逐条对着 apps/billionaires/data.json 的实际取值补齐，实测无遗漏。 */
    "美国": "United States",
    "中国": "China",
    "印度": "India",
    "德国": "Germany",
    "俄罗斯": "Russia",
    "香港": "Hong Kong SAR",
    "台湾": "Taiwan",
    "意大利": "Italy",
    "巴西": "Brazil",
    "加拿大": "Canada",
    "法国": "France",
    "英国": "United Kingdom",
    "澳大利亚": "Australia",
    "瑞士": "Switzerland",
    "瑞典": "Sweden",
    "日本": "Japan",
    "韩国": "South Korea",
    "新加坡": "Singapore",
    "西班牙": "Spain",
    "以色列": "Israel",
    "印度尼西亚": "Indonesia",
    "土耳其": "Türkiye",
    "泰国": "Thailand",
    "墨西哥": "Mexico",
    "荷兰": "Netherlands",
    "挪威": "Norway",
    "丹麦": "Denmark",
    "芬兰": "Finland",
    "奥地利": "Austria",
    "比利时": "Belgium",
    "爱尔兰": "Ireland",
    "波兰": "Poland",
    "捷克": "Czechia",
    "匈牙利": "Hungary",
    "希腊": "Greece",
    "葡萄牙": "Portugal",
    "罗马尼亚": "Romania",
    "保加利亚": "Bulgaria",
    "克罗地亚": "Croatia",
    "斯洛伐克": "Slovakia",
    "爱沙尼亚": "Estonia",
    "冰岛": "Iceland",
    "卢森堡": "Luxembourg",
    "摩纳哥": "Monaco",
    "列支敦士登": "Liechtenstein",
    "塞浦路斯": "Cyprus",
    "马来西亚": "Malaysia",
    "菲律宾": "Philippines",
    "越南": "Vietnam",
    "哈萨克斯坦": "Kazakhstan",
    "乌克兰": "Ukraine",
    "格鲁吉亚": "Georgia",
    "亚美尼亚": "Armenia",
    "阿联酋": "United Arab Emirates",
    "沙特阿拉伯": "Saudi Arabia",
    "卡塔尔": "Qatar",
    "阿曼": "Oman",
    "黎巴嫩": "Lebanon",
    "埃及": "Egypt",
    "摩洛哥": "Morocco",
    "阿尔及利亚": "Algeria",
    "尼日利亚": "Nigeria",
    "南非": "South Africa",
    "津巴布韦": "Zimbabwe",
    "坦桑尼亚": "Tanzania",
    "斯威士兰": "Eswatini",
    "智利": "Chile",
    "阿根廷": "Argentina",
    "秘鲁": "Peru",
    "哥伦比亚": "Colombia",
    "委内瑞拉": "Venezuela",
    "乌拉圭": "Uruguay",
    "巴巴多斯": "Barbados",
    "伯利兹": "Belize",
    "圣基茨和尼维斯": "Saint Kitts and Nevis",
    "新西兰": "New Zealand",
    "巴基斯坦": "Pakistan",
    "尼泊尔": "Nepal",
    "阿富汗": "Afghanistan",
    "阿尔巴尼亚": "Albania",
    "根西": "Guernsey",
    "科技": "Technology",
    "金融投资": "Finance & Investments",
    "时尚零售": "Fashion & Retail",
    "制造业": "Manufacturing",
    "多元化": "Diversified",
    "食品饮料": "Food & Beverage",
    "医疗健康": "Healthcare",
    "房地产": "Real Estate",
    "能源": "Energy",
    "汽车": "Automotive",
    "传媒娱乐": "Media & Entertainment",
    "电信": "Telecom",
    "金属矿业": "Metals & Mining",
    "物流": "Logistics",
    "博彩": "Gambling & Casinos",
    "体育": "Sports",
    "服务业": "Services",
    "建筑工程": "Construction & Engineering",
    "页": "Page",
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
    "跳转到指定页": "Jump to page",
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
    /* 波动率全景新增的期限结构行（build_radar.py 的 VOL_SYMBOLS 与 VIX/VIX3M 比值） */
    "VIX 9 日": "VIX 9-Day",
    "VIX 3 月": "VIX 3-Month",
    "VIX 6 月": "VIX 6-Month",
    "VIX/VIX3M 期限结构": "VIX/VIX3M term structure",
    "倒挂": "Inverted",
    "正向": "Normal",
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
    /* 页头 KPI、面板标签与方法学小节的标题。
       「冶炼厂关系」的语义按板块规则逐字照搬：申报里说的是「该冶炼厂出现在
       申报人的供应链中」，英文写 "appears in … supply chain"，
       **不得写成 supplier / supplies** —— 那是替申报人下结论。 */
    "公司": "Companies",
    "标普500成分股 495 家 + 在美上市外国私人发行人 1,194 家 + 报 10-K 的美国本土发行人 4,223 家，按 12 个价值链环节 × 27 条一级产业链两维定位 · Global Supply Chain":
      "495 S&P 500 constituents + 1,194 foreign private issuers listed in the U.S. + 4,223 U.S. domestic issuers filing a 10-K, placed on two axes: 12 value-chain stages × 27 first-level industry chains · Global Supply Chain",
    "已收录 86220 条带出处的关系（扫了 5898 家：369 家有名单、670 家有申报但正文未列名单、4698 家无申报），全部来自 Form SD 冲突矿产申报，语义是「该冶炼厂出现在申报人的供应链中」——间接、不含份额，不是直接供货关系。一级与二级供应商 0 条：七种办法已逐条实测否决——SEC 四条（客户集中度、全文反查、附件 21 子公司、附件 10 材料合同）加联邦采购分包、FCC 设备认证、政府召回公告，这不是还没做。点公司表里的「冶炼厂」列进入单家视图逐条核验。":
      "86,220 sourced relationships recorded (5,898 companies scanned: 369 with a list, 670 that filed without a list in the text, 4,698 with no filing), all from Form SD conflict-minerals filings. The semantics are “this smelter appears in the filer's supply chain” — indirect, with no share and no tier; it is not a direct supply relationship. Tier-1 and tier-2 suppliers: 0. Seven approaches were tested and rejected one by one — four SEC routes (customer concentration, full-text reverse lookup, Exhibit 21 subsidiaries, Exhibit 10 material contracts) plus federal procurement subcontracts, FCC equipment authorisations and government recall notices. This is not work left undone. Click the “Smelters” column in the company table to open a single-company view and verify each entry.",
    "下面各面板的关系边按申报年份分布：2026 年 81,251 条，另有 3,752 条（4%）来自 2025 年以前的申报、分布在 18 家公司，最老一份是 2016 年。抽取器取的是每家最近一份能解出名单的申报——公司停报 Form SD 之后，最后那份就一直留着。留着是对的（它是可核验的原始申报），**但它参与了下面每一个读数的计算**，所以在这里说明。":
      "Relationship edges across the panels below, by filing year: 81,251 from 2026, plus 3,752 (4%) from filings before 2025, spread across 18 companies, the oldest from 2016. The extractor takes each company's most recent filing from which a list can be parsed — once a company stops filing Form SD, its last one stays. Keeping it is right (it is a verifiable original filing), **but it feeds every reading below**, which is why it is stated here.",
    "当前唯一的关系数据源是 SEC 的 Form SD 冲突矿产申报，它只适用于产品中含钽锡钨金的发行人。因此各板块的覆盖率差别很大，而且有些板块的空白不会随时间填上——银行和 REIT 没有实体产品，本来就不需要申报。下面按板块把「有名单」和「为什么没有」分开列出。":
      "The only relationship data source at present is the SEC's Form SD conflict-minerals filing, which applies only to issuers whose products contain tantalum, tin, tungsten or gold. Coverage therefore varies widely by sector, and some sectoral blanks will never fill in — banks and REITs have no physical product and were never required to file. The breakdown below separates “has a list” from “why not”.",
    "另有在美上市的外国私人发行人 1194 家（报 20-F／40-F 的全体，不限于报 Form SD 的）。它们没有站内板块分类，下面按经营地拆——注意这一栏的口径是地理，不是板块。口径是经营地，不是注册地：715 家用 SEC 备案的注册地，479 家注册在开曼、英属维尔京、马绍尔、百慕大这类只做登记的法域，改用备案的营业地址——它们的注册地回答不了「这家公司在哪做生意」。其中 56 家的营业地址本身也在离岸法域，照实保留：SEC 手上只有那个地址，猜一个国家才是编造。另有 9 家备案里没有可用的地区字段，列为未归类。":
      "A further 1,194 foreign private issuers listed in the U.S. (all those filing a 20-F or 40-F, not only Form SD filers). They carry no on-site sector classification, so the breakdown below is by place of business — note that this column is geographic, not sectoral. Place of business, not place of incorporation: 715 use the jurisdiction of incorporation from their SEC filing, while 479 are incorporated in the Cayman Islands, the British Virgin Islands, the Marshall Islands, Bermuda and similar registration-only jurisdictions, for which the filed business address is used instead — their place of incorporation cannot answer “where does this company do business”. For 56 of those, the business address is itself in an offshore jurisdiction and is kept as filed: that address is all the SEC holds, and guessing a country would be fabrication. A further 9 filings carry no usable region field and are listed as ungrouped.",
    "另有报 10-K 的美国本土发行人 4223 家（标普成分股之外的那些）。站内公司榜只收标普成分股，所以这一池没有市值与板块分类——是口径如此，不是取数失败；它们又几乎全在美国，按国别拆只会得到一行。下面按 SEC 行业码的大类拆——注意这一栏的口径是行业大类，不是 GICS 板块。":
      "A further 4,223 U.S. domestic issuers filing a 10-K (those outside the S&P constituents). The on-site company board covers only S&P constituents, so this pool has no market cap or sector classification — that is the scope, not a failed fetch. They are also almost all in the United States, so a country breakdown would return a single row. The breakdown below is by SEC industry-code major group — note that this column is industry group, not GICS sector.",
    "全池 5,912 家按规模：其中 2,313 家是大型加速申报人（SEC 按公众持股量 ≥ 7 亿美元划的档）。用这条轴而不是市值，是因为站内行情只覆盖标普成分股 495 家（8%），而 SEC 的分档覆盖 5,300 家（90%）、三个池同一把尺子。余下 612 家分两种：新上市公司的档位要到财年末才评（记「未标注档位」），以及本轮没取到这一栏的（记「未分类」）。注意它按公众持股量分档、一年只重定一次，不是市值区间；「小型申报公司」「新兴成长公司」是另外两种身份，不占这条轴。":
      "The whole pool of 5,912 by size: 2,313 of them are large accelerated filers (the SEC's band for public float of at least US$700 million). This axis is used rather than market cap because on-site quotes cover only the 495 S&P constituents (8%), while the SEC's bands cover 5,300 (90%) and apply the same yardstick to all three pools. The remaining 612 split two ways: newly listed companies whose band is only assessed at fiscal year end (recorded as “filer status not stated”), and those for which this field was not retrieved this round (recorded as “unclassified”). Note that the band is set by public float and reset only once a year — it is not a market-cap bracket; “smaller reporting company” and “emerging growth company” are two separate statuses and do not occupy this axis.",
    "「无申报」不等于「这家公司没有供应链」，只表示它没有提交 Form SD——多数是因为规则对它不适用。「有申报未列名单」是规则允许的：Form SD 强制申报、不强制列出冶炼厂名单。这两类占多数，所以覆盖率永远到不了 100%，这是披露制度本身的上限。":
      "“No filing” does not mean “this company has no supply chain” — only that it has not submitted a Form SD, usually because the rule does not apply to it. “Filed without a list” is permitted by the rule: Form SD mandates the filing, not the disclosure of a smelter list. These two categories are the majority, which is why coverage can never reach 100%. That ceiling belongs to the disclosure regime itself.",
    "下面按上下游层次排：越靠上越上游，共 10 层，由 77 条连线算出，不是手工排的":
      "Ordered below by upstream–downstream position: higher is more upstream, 10 layers in all, computed from the 77 links rather than arranged by hand",
    "有 7 个 SIC 大类横跨多个环节，因此同一个名字会在不同环节里各出现一次——这不是重复：化工里既有工业气体（材料加工）也有成药（整机与品牌），四位行业码才分得开，逐家依据见展开后表格的「判定依据」列。":
      "Seven SIC major groups span more than one stage, so the same name appears once in each stage it spans — this is not duplication: chemicals covers both industrial gases (materials processing) and finished drugs (finished goods and brands), and only the four-digit code separates them. The basis for each company is in the “Basis” column of the expanded table.",
    "面向终端市场的整机、成药与消费品牌":
      "Finished goods, drugs and consumer brands aimed at the end market",
    "铁路、货运、空运与货代，链条的连接组织":
      "Rail, freight, air cargo and forwarding — the connective tissue of the chain",
    "医疗、住宿、客运与售后等面向消费者的服务":
      "Healthcare, lodging, passenger transport, after-sales and other consumer-facing services",
    "电力、燃气与水务——是制造业的投入品，不是外围服务":
      "Power, gas and water — inputs to manufacturing, not peripheral services",
    "银行、保险、地产与工程会计等专业服务":
      "Banking, insurance, property, and engineering and accounting professional services",
    "废弃物处理与材料回收，逆向供应链":
      "Waste treatment and materials recovery — the reverse supply chain",
    "当前口径：全池，未筛选产业链。 共 86220 条关系，指向 81 个国家或地区的冶炼厂。带子宽度是实测条数，不是示意。":
      "Current scope: whole pool, no chain filter. 86,220 relationships in total, pointing to smelters in 81 countries or regions. Ribbon width is the measured count, not an illustration.",
    "语义：该冶炼厂出现在申报人的供应链中（间接、不含份额、不含层级）。":
      "Semantics: this smelter appears in the filer's supply chain (indirect, with no share and no tier).",
    "灰色 = 无出处。另有 5543 家公司没有冶炼厂名单，未出现在本图中":
      "Grey = no source. A further 5,543 companies have no smelter list and do not appear in this chart",
    "列出关系数最多的 8 个国别，长尾并入「其他」，合计仍等于总条数":
      "The 8 countries with the most relationships are listed; the long tail is folded into “Other”, and the total still equals the overall count",
    "当前口径：全池，未筛选产业链。 被最多申报人共同列入的 30 家冶炼厂。分母是有名单的 369 家公司（不是全部 5912 家）；本口径下共 1693 家被两家以上共同申报，下面列前 30 家（另有 1663 家未列出）。":
      "Current scope: whole pool, no chain filter. The 30 smelters co-listed by the most filers. The denominator is the 369 companies that disclosed a list (not all 5,912); under this scope 1,693 smelters are co-filed by two or more companies, and the top 30 are listed below (1,663 others are not shown).",
    "条的长度是「占有名单公司的比例」，分母 369 家。「被 N 家共同列入」只说明这 N 家的申报名单里都有它，不说明它们与这家冶炼厂之间有直接采购关系——冶炼厂在供应链的第三层，申报的原义是「出现在本公司供应链中」。榜单上有 4 个名字出现两次：同一家厂一部分申报人给了 RMI 编号、一部分只给名字，登记表刻意不做同义合并（宁可一家重复出现，不可两家被错并成一家），因此这几家的真实共同申报数比任一行都高。整体上这个数只会少算不会多算。":
      "Bar length is the share of companies that disclosed a list, against a denominator of 369. “Co-listed by N filers” says only that the smelter appears in all N of their filed lists; it does not say those companies have a direct purchasing relationship with it — smelters sit at the third tier of the supply chain, and the filing's own wording is “appears in this company's supply chain”. Four names appear twice in the table: for the same smelter, some filers supplied an RMI identifier and others only a name, and the registry deliberately does not merge synonyms (better one smelter listed twice than two merged into one by mistake), so the true co-filing count for those is higher than any single row. Overall this figure can only undercount, never overcount.",
    "读这份榜单前先知道一件事：这些名单彼此高度雷同。297 家名单不少于 30 条的公司里，与自己最相似的那一家的重合度（Jaccard）中位数是 0.92，有 158 家 ≥0.90，40 家与另一家完全相同；中位公司名单里每一家冶炼厂都被别的申报人也列了（独有比例 0%）。原因是这些名单在很大程度上是同一份 RMI 合规冶炼厂名录的再现——它们是合规产物，不是各家自己的供应画像。所以重叠大是常态，不是信号；真正值得看第二眼的是独有比例高的那几家，例如 ECHO 96%、SLGN 58%、AP 17%。":
      "One thing to know before reading this table: these lists are highly similar to one another. Among the 297 companies whose list has at least 30 entries, the median overlap (Jaccard) with their single most similar peer is 0.92; 158 are at or above 0.90, and 40 are identical to another company's list. For the median company, every smelter on the list is also listed by some other filer (0% unique). The reason is that these lists largely reproduce the same RMI conformant-smelter directory — they are a compliance artifact, not each company's own picture of its supply base. Heavy overlap is therefore the norm, not a signal; the ones worth a second look are those with a high unique share, such as ECHO at 96%, SLGN at 58% and AP at 17%.",
    "Form SD 一年一报，EDGAR 留着历年申报。回溯 4 年后能看出每家今年新进了哪座冶炼厂、砍掉了哪座——存量名单只说明现状，变动才说明方向。可比公司 169 家（有名单的共 369 家）· 年度对比 444 组 · 变动率中位 15%、90 分位 52%（中位与分位只统计真正相邻的两年，共 440 组）。下面按最近一个可比年度的变动率排。":
      "Form SD is filed once a year and EDGAR keeps the historical filings. Looking back four years shows which smelters each company added this year and which it dropped — a standing list describes the present, while the changes describe the direction. 169 companies are comparable (369 disclosed a list) · 444 year-on-year pairs · median turnover 15%, 90th percentile 52% (the median and percentile count only genuinely adjacent years, 440 pairs). Ordered below by turnover in the most recent comparable year.",
    "跨年身份只认 RMI 编号：编号是冶炼厂设施的全球唯一标识，换一年仍是同一座厂。只有名字的条目不计入变动——一个拼写差异就会同时造出一条假新增和一条假消失。本轮追得动的条目占 96%，所以上面的变动率说的是**这部分**的换厂情况，不是整份名单。某一年没有带编号条目、或两年的编号覆盖率相差太远（低于 50%）的年度标为不可比，不按 0 计入——实测有申报人中途才开始写编号，那会得出「新增 306 座」，而它只是编号覆盖率变了。另有 12 组是一边整批进出、另一边几乎没动静（例如某家从 316 条变成 13 条、一条新增都没有）：申报人真的大改名单，与那一年只解析到部分文档，在数据上分不开，**已标为不可比并移出上表**——这是说清楚判不了，不是判它错。另有 8 家最近一个可比年度的带编号条目不足 10 条，比例失真（两三条时加一座就是几十个百分点），不参与上面的排名，数据里照留。":
      "Cross-year identity relies on the RMI identifier alone: the identifier is the global unique ID for a smelter facility and stays the same from year to year. Name-only entries are excluded from the change count — a single spelling difference would manufacture both a false addition and a false disappearance. 96% of entries could be tracked this round, so the turnover figures above describe **that portion**, not the whole list. A year with no identified entries, or where identifier coverage between the two years differs too much (below 50%), is marked not comparable rather than counted as zero — in testing, some filers only began writing identifiers partway through, which would yield “306 added” when all that changed was identifier coverage. A further 12 pairs show a wholesale move on one side and almost nothing on the other (one company went from 316 entries to 13 with not a single addition): a filer genuinely rewriting its list and only part of the documents being parsed that year are indistinguishable in the data, so those are **marked not comparable and removed from the table above** — that is stating the judgement cannot be made, not judging it wrong. Another 8 companies have fewer than 10 identified entries in their most recent comparable year, where the ratio distorts (with two or three entries, adding one smelter moves it tens of percentage points); they are excluded from the ranking above and kept in the data.",
    "多德-弗兰克 §1502 管的就是钽、锡、钨、金四种（业内叫 3TG）。四种矿的上游结构差得很远，合在一起看会读错：按国别排是「中国最大」，按矿种才看得出钨和钽的中国集中度是金的三倍，而受涵盖国家的暴露反而主要走锡和金。集中度用 HHI，分档取美国司法部／联邦贸易委员会《横向合并指引》的口径。":
      "Dodd-Frank §1502 covers exactly four minerals — tantalum, tin, tungsten and gold, known in the industry as 3TG. Their upstream structures differ sharply, and reading them together misleads: by country the headline is “China is largest”, but only a per-mineral view shows that Chinese concentration in tungsten and tantalum is three times that of gold, while exposure to the covered countries runs mainly through tin and gold. Concentration uses the HHI, with the bands taken from the U.S. Department of Justice / Federal Trade Commission Horizontal Merger Guidelines.",
    "HHI 按已披露冶炼厂条目的国别分布计算，不是采购量——Form SD 不要求申报采购量，一条关系只说明「这座厂出现在申报人的供应链中」。所以「钨 HHI 2135」要读成「已披露的钨冶炼厂里四成在中国」，不能读成「四成的钨来自中国」。另有 610 条关系没写明矿种，未列为一档——那是缺字段，不是第五种矿。":
      "The HHI is computed from the country distribution of disclosed smelter entries, not from purchase volumes — Form SD does not require volumes to be reported, and a relationship says only that “this smelter appears in the filer's supply chain”. So “tungsten HHI 2135” should be read as “40% of disclosed tungsten smelters are in China”, not as “40% of tungsten comes from China”. A further 610 relationships name no mineral and are not shown as a fifth band — that is a missing field, not a fifth mineral.",
    "当前口径：全池，未筛选产业链。 按冶炼厂所在国别看暴露面：左边是有多少家申报人的名单里出现过该国的厂，右边是关系条数。分母是有名单的 369 家公司（不是全部 5912 家）。共 81 个国别，下面列前 20 个。":
      "Current scope: whole pool, no chain filter. Exposure by the country a smelter sits in: the left side is how many filers' lists have contained a smelter in that country, the right side is the relationship count. The denominator is the 369 companies that disclosed a list.",
    "注意两列排名不同：按暴露家数第一的是「印度尼西亚」（340 家），按关系条数第一的是「中国」（21,762 条）。条数说的是图谱里有多少分量落在那里，家数说的是暴露面有多宽，两者不是一回事。本屏与上游集中度同源，都是从申报名单里数出来的，不含推断。「某国的冶炼厂出现在这些公司的名单里」不说明它们与那些冶炼厂之间有直接采购关系——冶炼厂在供应链的第三层，申报的原义是「出现在本公司供应链中」。":
      "Note that the two columns rank differently: first by number of exposed companies is Indonesia (340), first by relationship count is China (21,762). The count says how much of the graph lands there; the company count says how many filers are touched. Neither is a purchase volume.",
    "本板块的关系数据全部来自 Form SD 冲突矿产申报，而这套申报制度的立法依据是多德-弗兰克法案 §1502 / SEC Rule 13p-1 界定的受涵盖国家：刚果（金）及九个接壤国。公司之所以要逐家列出冶炼厂，正是为了说明自己的钽、锡、钨、金有没有为这一地区的武装冲突提供资金。法定 10 国里，本轮数据中出现了 10 国：登记表里有 55 家冶炼厂，被 292 家申报人（共 369 家有名单）列入，合计 1,575 条。":
      "All relationship data in this section comes from Form SD conflict-minerals filings, and that regime rests on Dodd-Frank §1502 / SEC Rule 13p-1, which names ten covered countries: the Democratic Republic of the Congo and the nine states adjoining it.",
    "出现在名单里不等于该公司使用了冲突矿产，恰恰相反：Form SD 要求的是尽责调查，一座厂被列出来，说明这家公司的调查覆盖到了它——那是制度在运转。受涵盖国家里同样有通过 RMI 合规认证的冶炼厂。本屏只回答「这十个国家在这批申报里出现了多少」，不评价任何一家公司。":
      "Appearing in a list does not mean the company used conflict minerals — quite the opposite: Form SD requires due diligence, and a smelter being listed shows the company's diligence reached it. That is the regime working.",
    "标普500成分股清单来自站内公司榜（datahub / s-and-p-500-companies），每日更新，本页不另建取数管道。":
      "The S&P 500 constituent list comes from the on-site company board (datahub / s-and-p-500-companies), updated daily; this page builds no separate fetch pipeline.",
    "由 SEC EDGAR 的官方 SIC 行业码判定。GICS 一级板块粒度不足——苹果、英伟达与微软同属「科技」但产业链位置完全不同；SIC 分别为 3571 电子计算机整机、3674 半导体、7372 预装软件，可以分开。每家公司的 SIC 与判定依据见各环节表格，并附可点开的原始申报链接。":
      "Assigned from the official SIC industry code in SEC EDGAR. GICS top-level sectors are not granular enough — Apple, Nvidia and Microsoft all sit in “Information Technology” yet occupy entirely different positions in the chain; their SIC codes are 3571, 3674 and 7372 respectively.",
    "同一套 SIC 码的第二个用途。纵向的 12 个环节说的是「在链上的哪一层」，横向的 27 条一级产业链说的是「在哪条链上」——只分层不分链的话，半导体设备与农机会落在同一格里，看着像邻居，其实一辈子不发生关系。归属由行业码按公开规则映射，不按公司名分派；一家可以同时在多条链上（全池 683 家如此），因为 SIC 3533 油气田机械本来就既在油气链也在工业机械链。链是分类，不是关系：同一条链上的两家公司之间有没有供应关系，只有申报文件说了算。":
      "The second use of the same SIC codes. The 12 stages on the vertical axis say which layer of the chain a company sits in; the 27 first-level industry chains on the horizontal axis say which chain it sits on — layering alone cannot tell a semiconductor company from a pharmaceutical one at the same stage. A company may belong to more than one chain.",
    "两个池。标普 500 成分股 495 家来自站内公司榜，有市值与当日涨跌；在美上市的外国私人发行人 1194 家来自 SEC EDGAR（报 20-F／40-F 且同时报 Form SD 的那一批），站内没有它们的报价——市值合计与环节涨跌都不含这批公司，带 * 的市值即为此。收这一批而不是全部一千余家外国发行人，是因为报 Form SD 才可能带来冶炼厂名单，也就是加进来同时带节点和边；只增加孤立节点的扩池没有意义。指数商的成分股名单（MSCI ACWI、S&P Global 1200）是专有数据，再分发要授权，因此没有采用。":
      "Two pools. The 495 S&P 500 constituents come from the on-site company board and carry market cap and the daily move; the 1,194 foreign private issuers listed in the U.S. come from SEC EDGAR (20-F / 40-F filers) and have neither.",
    "按价值链环节汇总当日涨跌；等权与市值加权并列给出，不互相冒充。行情值沿用站内成分股文件，未重算。":
      "The daily move is aggregated by value-chain stage; equal-weighted and cap-weighted figures are given side by side and neither stands in for the other. Quote values are taken from the on-site constituent file and are not recomputed.",
    "阶段未判定 0 家不摊入任何环节；报价过期 0 家不计入均值；无报价 0 家单独计。":
      "0 companies with no stage assigned are spread into any stage; 0 with stale quotes are excluded from the averages; 0 with no quote are counted separately.",
    "SIC 是「比板块细」而不是「精确」——SEC 对同类公司的分配本身存在不一致（半导体设备厂商有的归 3674 半导体、有的归 3559 专用机械）。因此本页阶段是行业码层面的判定，不等于对单家公司业务结构的完整刻画。":
      "SIC is “finer than sector”, not “precise” — the SEC's own assignment of comparable companies is inconsistent (some semiconductor equipment makers sit under 3674 semiconductors and others under 3559 special industry machinery). This page uses it because it is official, verifiable and covers all three pools, not because it is flawless.",
    /* §1502 点名的四种矿，以及制度界定的十个受涵盖国家 */
    "金": "Gold", "锡": "Tin", "钨": "Tungsten", "钽": "Tantalum",
    "刚果（金）": "DR Congo", "刚果（布）": "Republic of the Congo",
    "安哥拉": "Angola", "布隆迪": "Burundi", "中非": "Central African Republic",
    "卢旺达": "Rwanda", "南苏丹": "South Sudan", "坦桑尼亚": "Tanzania",
    "乌干达": "Uganda", "赞比亚": "Zambia",
    "钽 · 锡 · 钨 · 金 —— §1502 点名的四种矿，结构各不相同":
      "Tantalum · tin · tungsten · gold — the four minerals named by §1502, each with a different structure",
    "多德-弗兰克 §1502 界定的十国 · 这份披露制度就是为它们立的":
      "The ten countries defined by Dodd-Frank §1502 · the disclosure regime was written for them",
    "今年新进了哪座厂、砍掉了哪座 · 跨年只认 RMI 编号":
      "Which smelters were added this year and which were dropped · cross-year identity relies on the RMI identifier only",
    "同一个国别被多少家申报人的名单碰到 · 与「条数」是两个不同的读数":
      "How many filers' lists touch a given country · a different reading from the relationship count",
    "数据仅供研究参考，不构成投资建议。": "For research reference only; not investment advice.",
    "大型申报人": "Large filers",
    "关系": "Relationships",
    "申报人": "Filers",
    "冶炼厂": "Smelters",
    "数据日": "Data date",
    "更新": "Updated",
    "频率": "Frequency",
    "关系一年一次": "Relationships once a year",
    "· 行情每日": "· quotes daily",
    "数据范围": "Scope",
    "覆盖缺口": "Gaps",
    "名单变动": "Changes",
    "名单变动（历年）": "List changes (by year)",
    "按矿种": "By mineral",
    "国别暴露": "By country",
    "受涵盖国": "Covered country",
    "受涵盖国家": "§1502 states",
    "全池": "Whole pool",
    "有名单": "List disclosed",
    "有申报未列名单": "Filed, no list in the text",
    "申报资源开采付款": "Filed resource-extraction payments",
    "无申报": "No filing",
    "无逐家记录": "No per-company record",
    "大型加速申报人": "Large accelerated filer",
    "加速申报人": "Accelerated filer",
    "非加速申报人": "Non-accelerated filer",
    "未标注档位": "Filer status not stated",
    "未分类": "Unclassified",
    "未归类": "Ungrouped",
    "全部产业链": "All industry chains",
    "最上游": "Most upstream",
    "最终端": "Most downstream",
    "使能": "Enabling",
    "横跨全链": "Spans the whole chain",
    "有出处": "Sourced",
    "等权": "Equal-weighted",
    "市值加权": "Cap-weighted",
    "中位": "Median",
    "其他": "Other",
    "看是哪几家": "See which companies",
    "同名另有一条": "Another entry shares this name",
    "新增": "Added",
    "消失": "Dropped",
    "变动": "Change",
    "· 均不在池内": "· none in pool",
    "数据方法与来源": "Method & Sources",
    "节点来源：": "Node source: ",
    "阶段判定：": "Stage assignment: ",
    "产业链归属：": "Chain assignment: ",
    "公司池：": "Company pool: ",
    "环节涨跌：": "Stage moves: ",
    "剔除口径：": "Exclusions: ",
    "阶段划分说明：": "How the stages are defined: ",
    "局限：": "Limitations: ",
    "隐私政策": "Privacy Policy",
    "。每一条信息都能点开核验来源。": ". Every item can be opened to verify its source.",
    "阶段判定口径：SEC 官方 SIC 行业码判定 5912 家。逐家依据见下方各环节表格的「判定依据」列。":
      "How stages are assigned: 5,912 companies assigned from official SEC SIC industry codes. The basis for each one is in the “Basis” column of the stage tables below.",
    "实物链 8 段 + 使能层 4 段，按 SEC 行业码（SIC）展开，宽度即家数 · 点一格只看该组公司":
      "8 physical-chain stages + 4 enabling layers, expanded by SEC SIC code; width is the number of companies · click a cell to filter to that group",
    "矿产、油气与农林原料的开采": "Extraction of minerals, oil and gas, and agricultural and forestry raw materials",
    "半导体、电子元件与金属结构件": "Semiconductors, electronic components and fabricated metal parts",
    "供给制造环节的机械与专用设备": "Machinery and specialised equipment supplied to manufacturing",
    "批发与零售渠道": "Wholesale and retail channels",
    "软件、电信承载与内容平台": "Software, telecom carriage and content platforms",
    "冶炼、化工、炼油与造纸，产出下游的投入品":
      "Smelting, chemicals, refining and paper — producing the inputs used downstream",
    /* 价值链环节、产业链、SIC 行业组、板块与公司名的中英对照，逐条取自
       apps/supply-chain/*.json 里成对的 `label`/`labelEn`、`name`/`nameEn`、
       `sicMajorLabel`/`sicMajorLabelEn` 等字段——数据里本来就双写，生成而非手译。
       口径按板块规则：环节与分类是「定义」，可以直译；公司之间的关系语义
       （冶炼厂出现在申报人的供应链中）在下面的长句里逐字照搬，
       **一律不得写成 supplier / supplies**。 */
    "1药网": "111, Inc.",
    "36氪": "36Kr Holdings Inc.",
    "ADM": "Archer Daniels Midland",
    "AMD": "Advanced Micro Devices",
    "Adobe": "Adobe Inc.",
    "Booking": "Booking Holdings",
    "CRH 集团": "CRH plc",
    "CSX 运输": "CSX Corporation",
    "Coinbase": "Coinbase Global",
    "EOG 能源": "EOG Resources",
    "GE 医疗": "GE HealthCare",
    "GE 维尔诺瓦": "GE Vernova",
    "GE航空航天": "GE Aerospace",
    "HCA 医疗": "HCA Healthcare",
    "M&T 银行": "M&T Bank",
    "Meta": "Meta Platforms",
    "PNC 金融服务": "PNC Financial Services",
    "PPG 工业": "PPG Industries",
    "Palantir": "Palantir Technologies",
    "Palo Alto": "Palo Alto Networks",
    "T-Mobile": "T-Mobile US",
    "UPS": "United Parcel Service",
    "Visa": "Visa Inc.",
    "Workday": "Workday, Inc.",
    "一起教育科技": "17 Education & Technology Group Inc.",
    "万事达": "Mastercard",
    "万国数据": "GDS Holdings Ltd",
    "万物新生": "ATRenew Inc.",
    "万豪国际": "Marriott International",
    "世纪互联": "VNET Group, Inc.",
    "世邦魏理仕": "CBRE Group",
    "个人服务": "Personal Services",
    "中华电信": "CHUNGHWA TELECOM CO LTD",
    "中国": "China",
    "中国台湾": "Taiwan",
    "中国澳门": "Macau",
    "中国玉柴": "CHINA YUCHAI INTERNATIONAL LTD",
    "中国香港": "Hong Kong",
    "中通快递": "ZTO Express (Cayman) Inc.",
    "中非": "central african republic",
    "丰田": "TOYOTA MOTOR CORP/",
    "丹纳赫": "Danaher Corporation",
    "丹麦": "Denmark",
    "乌兹别克斯坦": "Uzbekistan",
    "乌干达": "uganda",
    "乌拉圭": "Uruguay",
    "乐信": "LexinFintech Holdings Ltd.",
    "乐金显示": "LG Display Co., Ltd.",
    "云学堂": "YXT.COM GROUP HOLDING Ltd",
    "云米科技": "Viomi Technology Co., Ltd",
    "云集": "Yunji Inc.",
    "亚太电线电缆": "ASIA PACIFIC WIRE & CABLE CORP LTD",
    "亚德诺": "Analog Devices",
    "亚朵": "Atour Lifestyle Holdings Ltd",
    "亚盛医药": "ASCENTAGE PHARMA GROUP INTERNATIONAL",
    "亚美尼亚": "Armenia",
    "亚马逊": "Amazon",
    "京东": "JD.com, Inc.",
    "亿咖通科技": "ECARX Holdings Inc.",
    "亿客行": "Expedia Group",
    "亿滋国际": "Mondelez International",
    "亿航智能": "EHang Holdings Ltd",
    "以色列": "Israel",
    "仪器仪表与医疗器械": "Instruments & Related Products",
    "伊利诺伊工具": "Illinois Tool Works",
    "伊顿": "Eaton Corporation",
    "优信": "Uxin Ltd",
    "优克联": "uCloudlink Group Inc.",
    "优步": "Uber",
    "伟创力": "Flex Ltd.",
    "传媒与娱乐": "Media & Entertainment",
    "伯克希尔": "Berkshire Hathaway",
    "住宿": "Hotels & Lodging",
    "佳明": "Garmin",
    "俄罗斯": "russian federation",
    "保德信金融": "Prudential Financial",
    "保险代理与经纪": "Insurance Agents & Brokers",
    "保险公司": "Insurance Carriers",
    "信也科技": "FinVolution Group",
    "信诺": "Cigna",
    "克罗格": "Kroger",
    "全美在线": "ATA Creativity Global",
    "公共交通": "Local & Suburban Transit",
    "公共存储": "Public Storage",
    "公用事业": "Industrials",
    "公路货运与仓储": "Motor Freight & Warehousing",
    "共和服务": "Republic Services",
    "其他制造业": "Miscellaneous Manufacturing",
    "其他零售": "Miscellaneous Retail",
    "再生元": "Regeneron Pharmaceuticals",
    "农业与食品": "Agriculture & Food",
    "农业服务": "Agricultural Services",
    "冠城国际": "Crown Castle",
    "凤凰新媒体": "Phoenix New Media Ltd",
    "分销与零售": "Distribution & Retail",
    "刚果（布）": "congo",
    "刚果（金）": "congo democratic republic of the",
    "前进保险": "Progressive Corporation",
    "力拓（澳大利亚）": "RIO TINTO LTD",
    "力拓（英国）": "RIO TINTO PLC",
    "加拿大": "Canada",
    "加拿大自然资源": "CANADIAN NATURAL RESOURCES Ltd",
    "加拿大鹅": "Canada Goose Holdings Inc.",
    "加纳": "ghana",
    "劳氏": "Lowe's",
    "勃肯": "Birkenstock Holding plc",
    "包装与纸业": "Packaging & Paper",
    "化工与制药": "Chemicals & Allied Products",
    "化工与新材料": "Chemicals & Materials",
    "北方信托": "Northern Trust",
    "北马其顿": "north macedonia",
    "医疗健康": "Health Care",
    "医疗器械与医疗服务": "Medtech & Health Services",
    "医疗服务": "Health Services",
    "医药与生物科技": "Pharma & Biotech",
    "半导体": "Semiconductors",
    "华住集团": "H World Group Ltd",
    "华米科技": "Zepp Health Corp",
    "华纳兄弟探索": "Warner Bros. Discovery",
    "华钦科技": "CLPS Inc",
    "南方公司": "Southern Company",
    "南苏丹": "south sudan",
    "南茂科技": "CHIPMOS TECHNOLOGIES INC",
    "南非": "South Africa",
    "博通": "Broadcom",
    "卡夫亨氏": "Kraft Heinz",
    "卡梅科": "CAMECO CORP",
    "卡特彼勒": "Caterpillar Inc.",
    "卢旺达": "rwanda",
    "卢森堡": "Luxembourg",
    "印刷与出版": "Printing & Publishing",
    "印度": "India",
    "印度尼西亚": "Indonesia",
    "原材料": "Materials",
    "可口可乐": "Coca-Cola Company (The)",
    "可选消费": "Consumer Discretionary",
    "台积电": "TAIWAN SEMICONDUCTOR MANUFACTURING CO LTD",
    "史赛克": "Stryker Corporation",
    "吉利德": "Gilead Sciences",
    "吉尔吉斯斯坦": "kyrgyzstan",
    "名创优品": "MINISO Group Holding Ltd",
    "和黄医药": "HUTCHMED (China) Ltd",
    "哈特福德金融": "Hartford (The)",
    "哈莫尼黄金": "HARMONY GOLD MINING CO LTD",
    "哈萨克斯坦": "Kazakhstan",
    "哈里伯顿": "Halliburton",
    "哈门那": "Humana",
    "响尾蛇能源": "Diamondback Energy",
    "哔哩哔哩": "Bilibili Inc.",
    "哥伦比亚": "Colombia",
    "唯品会": "Vipshop Holdings Ltd",
    "商业与专业服务": "Business & Professional Services",
    "商业服务": "Business Services",
    "嘉信理财": "Charles Schwab Corporation",
    "嘉年华邮轮": "Carnival",
    "嘉银科技": "Jiayin Group Inc.",
    "固安捷": "W. W. Grainger",
    "土耳其": "Turkey",
    "坦桑尼亚": "tanzania united republic of",
    "埃克森美孚": "ExxonMobil",
    "埃塞俄比亚": "ethiopia",
    "埃尔比特系统": "ELBIT SYSTEMS LTD",
    "埃尼": "ENI SPA",
    "埃森哲": "Accenture",
    "塔吉特": "Target Corporation",
    "塞浦路斯": "Cyprus",
    "墨式烧烤": "Chipotle Mexican Grill",
    "墨西哥": "Mexico",
    "壳牌": "Shell plc",
    "复朗集团": "Lanvin Group Holdings Ltd",
    "多佛": "Dover Corporation",
    "多米尼加": "Dominican Republic",
    "大全新能源": "DAQO NEW ENERGY CORP.",
    "大都会人寿": "MetLife",
    "天演药业": "Adagene Inc.",
    "太平洋煤气电力": "PG&E Corporation",
    "奇富科技": "Qfin Holdings, Inc.",
    "奇景光电": "Himax Technologies, Inc.",
    "奈飞": "Netflix",
    "奥地利": "austria",
    "奥的斯": "Otis Worldwide",
    "奥莱利汽配": "O'Reilly Auto Parts",
    "奥驰亚": "Altria",
    "好事达": "Allstate",
    "好市多": "Costco",
    "好时": "Hershey Company (The)",
    "好未来": "TAL Education Group",
    "委内瑞拉": "Venezuela",
    "威廉姆斯公司": "Williams Companies",
    "威瑞信": "Verisign",
    "威瑞森": "Verizon",
    "威达信集团": "Marsh & McLennan Companies, Inc.",
    "娱乐与休闲服务": "Amusement & Recreation Services",
    "孟加拉国": "bangladesh",
    "安捷伦": "Agilent Technologies",
    "安提瓜和巴布达": "Antigua and Barbuda",
    "安森美半导体": "ON Semiconductor",
    "安特吉": "Entergy",
    "安费诺": "Amphenol",
    "安赛乐米塔尔": "ArcelorMittal",
    "安达保险": "Chubb Limited",
    "安进": "Amgen",
    "安道尔": "andorra",
    "宏盟集团": "Omnicom Group",
    "宜人智科": "Yiren Digital Ltd.",
    "宝尊电商": "Baozun Inc.",
    "宝洁": "Procter & Gamble",
    "宣伟": "Sherwin-Williams",
    "家具": "Furniture & Fixtures",
    "家居零售": "Home Furniture & Furnishings Stores",
    "家得宝": "Home Depot (The)",
    "富国银行": "Wells Fargo",
    "富途控股": "Futu Holdings Ltd",
    "小牛电动": "Niu Technologies",
    "小马智行": "Pony AI Inc.",
    "小鹏汽车": "XPENG INC.",
    "尚德机构": "Sunlands Technology Group",
    "尼日利亚": "Nigeria",
    "工业": "Industrials",
    "工业机械与自动化": "Industrial Machinery",
    "工程、会计与研究服务": "Engineering & Management Services",
    "巴哈马": "Bahamas",
    "巴拿马": "Panama",
    "巴西": "Brazil",
    "巴西航空工业": "EMBRAER S.A.",
    "巴里克黄金": "BARRICK MINING CORP",
    "布隆迪": "burundi",
    "希尔顿": "Hilton Worldwide",
    "希捷": "Seagate Technology",
    "希腊": "Greece",
    "帕卡": "Paccar",
    "应用材料": "Applied Materials",
    "废物管理公司": "Waste Management",
    "康卡斯特": "Comcast",
    "康宁": "Corning Inc.",
    "康德乐": "Cardinal Health",
    "康明斯": "Cummins",
    "康菲石油": "ConocoPhillips",
    "建材与家居零售": "Building Materials & Garden Supply",
    "建筑与建材": "Construction & Building",
    "建筑专业承包": "Special Trade Contractors",
    "开利": "Carrier Global",
    "开曼群岛": "Cayman Islands",
    "强生": "Johnson & Johnson",
    "影视": "Motion Pictures",
    "循环与废弃物": "Circular & Waste",
    "微博": "WEIBO Corp",
    "微美全息": "WiMi Hologram Cloud Inc.",
    "微芯科技": "Microchip Technology",
    "微软": "Microsoft",
    "德国": "Germany",
    "德州仪器": "Texas Instruments",
    "德康医疗": "Dexcom",
    "必和必拓": "BHP Group Ltd",
    "必需消费": "Consumer Staples",
    "思科": "Cisco",
    "怡安": "Aon",
    "怪物饮料": "Monster Beverage",
    "恩智浦": "NXP Semiconductors",
    "意大利": "Italy",
    "意法半导体": "STMicroelectronics N.V.",
    "慧与": "Hewlett Packard Enterprise",
    "慧择": "Huize Holding Ltd",
    "慧荣科技": "Silicon Motion Technology CORP",
    "戴尔": "Dell Technologies",
    "戴文能源": "Devon Energy",
    "房地产": "Real Estate",
    "房多多": "Fangdd Network Group Ltd.",
    "房屋建筑承包": "Building Construction",
    "批发·耐用品": "Wholesale Trade - Durable Goods",
    "批发·非耐用品": "Wholesale Trade - Nondurable Goods",
    "技术与平台": "Technology & Platforms",
    "拉夫劳伦": "Ralph Lauren Corporation",
    "拉斯维加斯金沙": "Las Vegas Sands",
    "挚文集团": "Hello Group Inc.",
    "挪威": "Norway",
    "挪威国家石油": "EQUINOR ASA",
    "捷克": "czechia",
    "捷普": "Jabil",
    "控股与投资机构": "Holding & Other Investment Offices",
    "搜狐": "Sohu.com Ltd",
    "摩托罗拉系统": "Motorola Solutions",
    "摩根士丹利": "Morgan Stanley",
    "摩根大通": "JPMorgan Chase",
    "摩纳哥": "Monaco",
    "教育服务": "Educational Services",
    "整机与品牌": "Finished Goods & Brands",
    "文远知行": "WeRide Inc.",
    "斗鱼": "DouYu International Holdings Ltd",
    "斯伦贝谢": "Schlumberger",
    "斯洛伐克": "slovakia",
    "新加坡": "Singapore",
    "新思科技": "Synopsys",
    "新氧": "So-Young International Inc.",
    "新濠博亚娱乐": "Melco Resorts & Entertainment LTD",
    "新濠影汇": "STUDIO CITY INTERNATIONAL HOLDINGS Ltd",
    "新纪元能源": "NextEra Energy",
    "新西兰": "New Zealand",
    "施乐辉": "SMITH & NEPHEW PLC",
    "旅游休闲与餐饮": "Travel, Leisure & Dining",
    "旅行者保险": "Travelers Companies (The)",
    "日月光投控": "ASE Technology Holding Co., Ltd.",
    "日本": "Japan",
    "日用消费品": "Consumer Goods",
    "明晟": "MSCI",
    "星巴克": "Starbucks",
    "星座品牌": "Constellation Brands",
    "星座能源": "Constellation Energy",
    "是德科技": "Keysight Technologies",
    "普信集团": "T. Rowe Price",
    "普洛斯": "Prologis",
    "晶科能源": "JinkoSolar Holding Co., Ltd.",
    "智利": "Chile",
    "服装成衣": "Apparel",
    "服装零售": "Apparel & Accessory Stores",
    "木材与木制品": "Lumber & Wood Products",
    "本田": "HONDA MOTOR CO LTD",
    "机械与计算机设备": "Machinery & Computer Equipment",
    "材料加工": "Materials Processing",
    "杜克能源": "Duke Energy",
    "林德": "Linde plc",
    "柬埔寨": "Cambodia",
    "标普全球": "S&P Global",
    "根西岛": "Guernsey",
    "格林酒店集团": "GreenTree Hospitality Group Ltd.",
    "格鲁吉亚": "georgia",
    "桑普拉能源": "Sempra",
    "梅特勒-托利多": "Mettler Toledo",
    "森科能源": "SUNCOR ENERGY INC",
    "楷登电子": "Cadence Design Systems",
    "橡胶与塑料制品": "Rubber & Plastics",
    "欧力士": "ORIX CORP",
    "欧特克": "Autodesk",
    "武田制药": "TAKEDA PHARMACEUTICAL CO LTD",
    "比利时": "Belgium",
    "毛里塔尼亚": "mauritania",
    "毛里求斯": "Mauritius",
    "水上运输": "Water Transportation",
    "水滴公司": "Waterdrop Inc.",
    "江森自控": "Johnson Controls",
    "汽车": "Automotive",
    "汽车之家": "Autohome Inc.",
    "汽车修理与租赁": "Auto Repair & Services",
    "汽车经销与加油站": "Auto Dealers & Service Stations",
    "沃尔玛": "Walmart",
    "沃特世": "Waters Corporation",
    "沃达丰": "VODAFONE GROUP PUBLIC LTD CO",
    "沙特阿拉伯": "saudi arabia",
    "法国": "France",
    "法拉利": "Ferrari N.V.",
    "泛林集团": "Lam Research",
    "泛美白银": "PAN AMERICAN SILVER CORP",
    "波兰": "poland",
    "波士顿科学": "Boston Scientific",
    "波音": "Boeing",
    "泰佩思琦": "Tapestry, Inc.",
    "泰克资源": "TECK RESOURCES LTD",
    "泰国": "thailand",
    "泰森食品": "Tyson Foods",
    "泰瑞达": "Teradyne",
    "泰科电子": "TE Connectivity",
    "泽西岛": "Jersey",
    "洛克希德·马丁": "Lockheed Martin",
    "津巴布韦": "zimbabwe",
    "洪恩教育": "iHuman Inc.",
    "洲际交易所": "Intercontinental Exchange",
    "派克汉尼汾": "Parker Hannifin",
    "浦项控股": "POSCO HOLDINGS INC.",
    "涂鸦智能": "Tuya Inc.",
    "渔猎": "Fishing, Hunting & Trapping",
    "渤健": "Biogen",
    "满帮集团": "Full Truck Alliance Co. Ltd.",
    "滴滴": "DiDi Global Inc.",
    "澳大利亚": "Australia",
    "烟草制品": "Tobacco Products",
    "燃石医学": "Burning Rock Biotech Ltd",
    "爱奇艺": "iQIYI, Inc.",
    "爱尔兰": "Ireland",
    "爱尔康": "ALCON INC",
    "爱彼迎": "Airbnb",
    "爱德华兹生命科学": "Edwards Lifesciences",
    "爱德士": "Idexx Laboratories",
    "爱沙尼亚": "estonia",
    "爱立信": "ERICSSON LM TELEPHONE CO",
    "爱迪生国际": "Edison International",
    "物流与运输": "Logistics & Transport",
    "特利丹": "Teledyne Technologies",
    "特斯拉": "Tesla, Inc.",
    "特灵科技": "Trane Technologies",
    "特纳瑞斯": "TENARIS SA",
    "猎豹移动": "Cheetah Mobile Inc.",
    "玩美移动": "Perfect Corp.",
    "环保与循环经济": "Environmental & Circular",
    "玻利维亚": "bolivia plurinational state of",
    "理想汽车": "Li Auto Inc.",
    "瑞典": "Sweden",
    "瑞士": "Switzerland",
    "瑞幸咖啡": "Luckin Coffee Inc.",
    "瑞思迈": "ResMed",
    "瓦莱罗能源": "Valero Energy",
    "甲骨文": "Oracle Corporation",
    "电力与公用事业": "Power & Utilities",
    "电力燃气与水务": "Electric, Gas & Sanitary Services",
    "电子与电气设备": "Electronic & Electrical Equipment",
    "电子元器件": "Electronic Components",
    "畜牧业": "Agricultural Production - Livestock",
    "百事": "PepsiCo",
    "百威英博": "Anheuser-Busch InBev SA/NV",
    "百度": "Baidu, Inc.",
    "百慕大": "Bermuda",
    "百时美施贵宝": "Bristol Myers Squibb",
    "百胜餐饮": "Yum! Brands",
    "皇家加勒比": "Royal Caribbean Group",
    "皮革制品": "Leather Products",
    "盈透证券": "Interactive Brokers Group",
    "盖尔道": "GERDAU S.A.",
    "直布罗陀": "Gibraltar",
    "直觉外科": "Intuitive Surgical",
    "相干公司": "Coherent, Inc.",
    "看准科技": "Kanzhun Ltd",
    "睿能创意": "Gogoro Inc.",
    "知乎": "Zhihu Inc.",
    "石油与天然气": "Oil & Gas",
    "石油与天然气开采": "Oil & Gas Extraction",
    "石油炼制": "Petroleum Refining",
    "硕腾": "Zoetis",
    "碧迪医疗": "Becton Dickinson",
    "礼来": "Lilly (Eli)",
    "社会服务": "Social Services",
    "福克斯": "Fox Corporation (Class A)",
    "福泰制药": "Vertex Pharmaceuticals",
    "福特": "Ford Motor Company",
    "禾赛科技": "Hesai Group",
    "种植业": "Agricultural Production - Crops",
    "科技": "Information Technology",
    "科磊": "KLA Corporation",
    "科赴": "Kenvue",
    "科迪华": "Corteva",
    "秘鲁": "Peru",
    "穆迪": "Moody's Corporation",
    "空气化工产品": "Air Products",
    "立陶宛": "Lithuania",
    "第一太阳能": "First Solar",
    "第一资本": "Capital One",
    "第九城市": "The9 LTD",
    "第五三银行": "Fifth Third Bancorp",
    "简普科技": "Jianpu Technology Inc.",
    "管道运输": "Pipelines",
    "索尼": "Sony Group Corp",
    "纳斯达克": "Nasdaq, Inc.",
    "纺织": "Textile Mill Products",
    "纺织服装与鞋类": "Textiles & Apparel",
    "纽柯钢铁": "Nucor",
    "纽约梅隆银行": "Bank of New York Mellon Corp",
    "纽蒙特": "Newmont",
    "终端服务": "End Services",
    "维谛技术": "Vertiv Holdings Co",
    "综合零售": "General Merchandise Stores",
    "缅甸": "myanmar",
    "网易": "NetEase, Inc.",
    "网易有道": "Youdao, Inc.",
    "罗克韦尔自动化": "Rockwell Automation",
    "罗宾汉": "Robinhood Markets, Inc.",
    "罗斯百货": "Ross Stores",
    "罗珀科技": "Roper Technologies",
    "美元树": "Dollar Tree",
    "美光": "Micron Technology",
    "美国": "United States",
    "美国合众银行": "U.S. Bancorp",
    "美国国际集团": "American International Group",
    "美国家庭人寿": "Aflac",
    "美国水务": "American Water Works",
    "美国电力": "American Electric Power",
    "美国电塔": "American Tower",
    "美国运通": "American Express",
    "美国银行": "Bank of America",
    "美敦力": "Medtronic",
    "美满电子": "Marvell Technology, Inc.",
    "老挝": "lao people s democratic republic",
    "老虎证券": "UP Fintech Holding Ltd",
    "耐克": "Nike, Inc.",
    "联华电子": "UNITED MICROELECTRONICS CORP",
    "联合健康": "UnitedHealth Group",
    "联合太平洋": "Union Pacific Corporation",
    "联合爱迪生": "Consolidated Edison",
    "联合租赁": "United Rentals",
    "联合航空": "United Airlines Holdings",
    "联邦快递": "FedEx",
    "肯尼亚": "Kenya",
    "能源": "Energy",
    "能源与公用事业": "Energy & Utilities",
    "能链智电": "NaaS Technology Inc.",
    "腾讯音乐": "Tencent Music Entertainment Group",
    "自由港麦克莫兰": "Freeport-McMoRan",
    "航空航天与国防": "Aerospace & Defense",
    "航空运输": "Transportation by Air",
    "艺康": "Ecolab",
    "艾伯维": "AbbVie",
    "艾昆纬": "IQVIA",
    "艾格尼科鹰矿业": "AGNICO EAGLE MINES LTD",
    "艾默生": "Emerson Electric",
    "芝加哥期权交易所": "Cboe Global Markets",
    "芝商所": "CME Group",
    "芬兰": "Finland",
    "芯动科技": "Intchains Group Ltd",
    "芯源系统": "Monolithic Power Systems",
    "花旗": "Citigroup",
    "苏丹": "sudan",
    "英伟达": "Nvidia",
    "英国": "United Kingdom",
    "英国石油": "BP PLC",
    "英属维尔京群岛": "Virgin Islands, British",
    "英格索兰": "Ingersoll Rand",
    "英特尔": "Intel",
    "英美烟草": "British American Tobacco p.l.c.",
    "英美黄金阿散蒂": "AngloGold Ashanti PLC",
    "苹果": "Apple Inc.",
    "荷兰": "Netherlands",
    "莫德纳": "Moderna",
    "莱纳房屋": "Lennar",
    "菲利普斯66": "Phillips 66",
    "菲利普莫里斯": "Philip Morris International",
    "菲律宾": "Philippines",
    "萨索尔": "SASOL LTD",
    "葛兰素史克": "GSK plc",
    "葡萄牙": "portugal",
    "蒙古": "mongolia",
    "蔚来": "NIO Inc.",
    "蘑菇街": "MOGU Inc.",
    "虎牙": "HUYA Inc.",
    "西南航空": "Southwest Airlines",
    "西斯科": "Sysco",
    "西方石油": "Occidental Petroleum",
    "西班牙": "Spain",
    "西蒙地产": "Simon Property Group",
    "西部数据": "Western Digital",
    "西麦斯": "CEMEX SAB DE CV",
    "计算与数据中心硬件": "Computing & Datacenter Hardware",
    "证券与商品经纪": "Security & Commodity Brokers",
    "诺亚控股": "NOAH HOLDINGS LTD",
    "诺和诺德": "NOVO NORDISK A S",
    "诺基亚": "NOKIA CORP",
    "诺斯罗普·格鲁曼": "Northrop Grumman",
    "诺福克南方铁路": "Norfolk Southern Railway",
    "谷歌": "Alphabet Inc. (Class A)",
    "豪梅特航空": "Howmet Aerospace",
    "贝克休斯": "Baker Hughes",
    "贝壳": "KE Holdings Inc.",
    "贝莱德": "BlackRock",
    "费森尤斯医疗": "Fresenius Medical Care AG",
    "资本设备": "Capital Equipment",
    "资源开采": "Raw Materials",
    "赛莱默": "Xylem Inc.",
    "赛诺菲": "Sanofi",
    "赛默飞": "Thermo Fisher Scientific",
    "赞比亚": "zambia",
    "越南": "vietnam",
    "趣活": "QUHUO Ltd",
    "路特斯科技": "Lotus Technology Inc.",
    "车车科技": "Cheche Group Inc.",
    "软件与云服务": "Software & Cloud",
    "辉瑞": "Pfizer",
    "达美航空": "Delta Air Lines",
    "迅雷": "Xunlei Ltd",
    "运输服务": "Transportation Services",
    "运输设备": "Transportation Equipment",
    "迪士尼": "Walt Disney Company (The)",
    "迪尔": "Deere & Company",
    "途牛": "Tuniu Corp",
    "通信": "Communications",
    "通信与网络": "Communications & Networking",
    "通信服务": "Communication Services",
    "通用动力": "General Dynamics",
    "通用汽车": "General Motors",
    "造纸与纸制品": "Paper & Allied Products",
    "逸仙电商": "Yatsen Holding Ltd",
    "道富银行": "State Street Corporation",
    "道明尼能源": "Dominion Energy",
    "道达尔能源": "TotalEnergies SE",
    "邦吉": "Bunge Global",
    "采矿与金属": "Mining & Metals",
    "重型工程建筑": "Heavy Construction",
    "金佰利": "Kimberly-Clark",
    "金属冶炼与压延": "Primary Metal Industries",
    "金属制品": "Fabricated Metal Products",
    "金属矿采选": "Metal Mining",
    "金山云": "Kingsoft Cloud Holdings Ltd",
    "金德摩根": "Kinder Morgan",
    "金融": "Financials",
    "金融与专业服务": "Financial & Professional",
    "金融服务": "Financial Services",
    "钢铁动力": "Steel Dynamics",
    "铁路运输": "Railroad Transportation",
    "银行与存款机构": "Depository Institutions",
    "闪迪": "Sandisk Corporation",
    "阿斯麦": "ASML HOLDING NV",
    "阿根廷": "Argentina",
    "阿波罗全球管理": "Apollo Global Management",
    "阿特斯太阳能": "Canadian Solar Inc.",
    "阿瑞斯资本": "Ares Management Corporation",
    "阿美特克": "Ametek",
    "阿联酋": "United Arab Emirates",
    "阿里巴巴": "Alibaba Group Holding Ltd",
    "陆金所": "Lufax Holding Ltd",
    "雅培": "Abbott Laboratories",
    "雅诗兰黛": "Estée Lauder Companies (The)",
    "雪佛龙": "Chevron Corporation",
    "零售与分销": "Retail & Distribution",
    "零部件与元器件": "Components",
    "雷神技术": "RTX Corporation",
    "雷蒙詹姆斯": "Raymond James Financial",
    "雾芯科技": "RLX Technology Inc.",
    "震坤行": "ZKH Group Ltd",
    "霍尼韦尔": "Honeywell",
    "霍顿房屋": "D. R. Horton",
    "霸王茶姬": "Chagee Holdings Ltd.",
    "非存款信贷机构": "Nondepository Credit Institutions",
    "非金属矿物制品": "Stone, Clay & Glass",
    "非金属矿采选": "Nonmetallic Minerals Mining",
    "韦莱韬悦": "Willis Towers Watson",
    "韩国": "Korea, Republic of",
    "飞利浦": "KONINKLIJKE PHILIPS NV",
    "飞塔": "Fortinet",
    "食品与饮料": "Food & Kindred Products",
    "食品零售": "Food Stores",
    "餐饮": "Eating & Drinking Places",
    "马丁玛丽埃塔": "Martin Marietta Materials",
    "马恩岛": "Isle of Man",
    "马拉松石油": "Marathon Petroleum",
    "马来西亚": "Malaysia",
    "马绍尔群岛": "Marshall Islands",
    "马达加斯加": "madagascar",
    "马里": "mali",
    "高塔半导体": "TOWER SEMICONDUCTOR LTD",
    "高盛": "Goldman Sachs",
    "高途": "Gaotu Techedu Inc.",
    "高通": "Qualcomm",
    "高露洁": "Colgate-Palmolive",
    "麦克森": "McKesson Corporation",
    "麦当劳": "McDonald's",
    "麦格纳": "MAGNA INTERNATIONAL INC",
    "黑山": "Montenegro",
    "黑石": "Blackstone Inc.",
    "默克": "Merck & Co.",
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
  /* 加进 alt：榜单头像/图标的 alt 存的是中文名，读屏用户此前一直读到中文。 */
  var ATTRS = ["placeholder", "aria-label", "title", "alt"];

  function regexTranslate(s) {
    var m;
    if (path.indexOf("/apps/billionaires/") === 0) {
      if ((m = /^(\d+)岁$/.exec(s))) return m[1] + " yrs";
      if ((m = /^第 ([\d,]+) – ([\d,]+) 条 · 共搜到 ([\d,]+) 人$/.exec(s))) return "Results " + m[1] + "–" + m[2] + " · " + m[3] + " people found";
      if ((m = /^第 ([\d,]+) – ([\d,]+) 名 · 共 ([\d,]+) 人$/.exec(s))) return "Ranks " + m[1] + "–" + m[2] + " · " + m[3] + " people";
      if ((m = /^第 ([\d,]+) 页$/.exec(s))) return "Page " + m[1];
      if ((m = /^([\d,]+) 位亿万富豪 总财富$/.exec(s))) return m[1] + " billionaires · Total wealth";
      /* 「其中 2887 人有中文名对照」里的人数随每日取数变化，死词条会一夜失效，
         改成两端锚定的规则，数字原样带回（补上千分位）。 */
      if ((m = /^数据来自 Forbes 实时富豪榜，每日自动更新；身价单位为十亿美元（B），当日变动为较上一参考时点的估算。榜单覆盖全部亿万富豪（净值 ≥ 10 亿美元），其中 (\d+) 人有中文名对照，其余显示福布斯英文原名。仅供参考，不构成任何建议。$/.exec(s))) {
        return "Data comes from the Forbes real-time billionaire ranking and refreshes daily. Net worth is in billions of U.S. dollars (B), and the daily change is an estimate against the previous reference point. The ranking covers every billionaire (net worth of at least US$1 billion); " +
          m[1].replace(/\B(?=(\d{3})+$)/g, ",") + " of them have a verified Chinese name, and the rest display the Forbes original. For reference only; not advice.";
      }
      if ((m = /^▲ 今日领涨 (.+)$/.exec(s))) return "▲ Top gainer today " + m[1];
      if ((m = /^▼ 今日领跌 (.+)$/.exec(s))) return "▼ Top decliner today " + m[1];
      // 「🇺🇸美国 · Tesla, SpaceX · 科技 · 55岁」：国旗、公司名与年龄原样带回，
      // 只查国名与行业；查不到就保留原文，不臆造。
      if ((m = /^(\S*?)([\u4e00-\u9fff]+) · (.+?) · ([\u4e00-\u9fff]+) · (\d+)岁$/.exec(s))) {
        return m[1] + (dict[m[2]] || m[2]) + " · " + m[3] + " · " + (dict[m[4]] || m[4]) + " · " + m[5] + " yrs";
      }
      if ((m = /^(\S*?)([\u4e00-\u9fff]+) · (.+?) · ([\u4e00-\u9fff]+)$/.exec(s))) {
        return m[1] + (dict[m[2]] || m[2]) + " · " + m[3] + " · " + (dict[m[4]] || m[4]);
      }
      if (s === "· 数据日期") return "· Date";
      if ((m = /^· 更新于 (.+)$/.exec(s))) return "· Updated " + m[1];
    }
    if (path.indexOf("/apps/supply-chain/") === 0) {
      /* 页面里绝大多数长句是按模板拼的（家数、条数、百分比会变），整串进不了字典。
         下面逐个模板写两端锚定的规则，数字原样带回。
         语义按板块规则照搬申报原义：冶炼厂关系写 "appears in the supply chain of"，
         **不写 supplier / supplies**。 */
      if ((m = /^([\d,]+) 家$/.exec(s))) return m[1] + " companies";
      if ((m = /^([\d,]+) 条$/.exec(s))) return m[1] + " relationships";
      if ((m = /^([\d,]+) 厂$/.exec(s))) return m[1] + " smelters";
      if ((m = /^([\d,]+)家$/.exec(s))) return m[1] + " companies";
      if ((m = /^([\d,]+)条$/.exec(s))) return m[1] + " relationships";
      if ((m = /^([\d,]+)厂$/.exec(s))) return m[1] + " smelters";
      if (s === "家") return "companies";
      if (s === "条") return "relationships";
      if (s === "家厂") return "smelters";
      if (s === "家申报人") return "filers";
      if (s === "条受涵盖国") return "covered countries";
      if ((m = /^([\d,]+) 条关系$/.exec(s))) return m[1] + " relationships";
      if ((m = /^([\d.,]+) 亿$/.exec(s))) return m[1] + "00M";
      if ((m = /^([\d.,]+) 万亿$/.exec(s))) return m[1] + "T";
      if ((m = /^家 · 有出处关系$/.exec(s))) return "companies · with sourced relationships";
      if ((m = /^家（占全池 ([\d.]+%)$/.exec(s))) return "companies (" + m[1] + " of the whole pool";
      if ((m = /^，占报过 Form SD 的 ([\d,]+) 家的 ([\d.]+%)$/.exec(s))) {
        return ", and " + m[2] + " of the " + m[1] + " that have filed a Form SD";
      }
      if (s === "）· 点开看各板块与国别为什么差这么多") return ") · open to see why sectors and countries differ so much";
      if ((m = /^家 ([\d.]+%)$/.exec(s))) return "companies, " + m[1];
      if ((m = /^其他 (\d+) 个国别／地区$/.exec(s))) return m[1] + " other countries/regions";
      if ((m = /^SIC (\d+) · ([\d,]+) 家$/.exec(s))) return "SIC " + m[1] + " · " + m[2] + " companies";
      if ((m = /^· (\d+) 家可点开$/.exec(s))) return "· " + m[1] + " openable";
      if ((m = /^([\d,]+) 条 · ([\d,]+) 厂$/.exec(s))) return m[1] + " relationships · " + m[2] + " smelters";
      if ((m = /^条 · ([\d,]+) 厂$/.exec(s))) return "relationships · " + m[1] + " smelters";
      if ((m = /^(\d+) 条 · 无出处$/.exec(s))) return m[1] + " relationships · no source";
      if ((m = /^(未集中|中度集中|高度集中) · (.+?)([\d.]+%)$/.exec(s))) {
        var conc = { "未集中": "Not concentrated", "中度集中": "Moderately concentrated",
          "高度集中": "Highly concentrated" }[m[1]];
        return conc + " · " + (dict[m[2]] || m[2]) + " " + m[3];
      }
      if ((m = /^(.+?) → (.+?)　([\d,]+) 条$/.exec(s))) {
        return (dict[m[1]] || m[1]) + " → " + (dict[m[2]] || m[2]) + "\u3000" + m[3] + " relationships";
      }
      if ((m = /^另有 (\d+) 家分散在 (\d+) 个更小的行业码里，未单列。$/.exec(s))) {
        return "A further " + m[1] + " companies sit in " + m[2] + " smaller industry codes and are not listed separately.";
      }
      /* 共同列入的免责句：语义必须停在「共同出现在名单里」，
         不得写成 supplier/supplies，也不得暗示这几家公司之间有关系。 */
      if ((m = /^这 ([\d,]+) 家申报人的 Form SD 名单里都出现了「(.+)」。只是共同列入，不表示它们与这家冶炼厂之间有采购关系，也不表示这几家公司之间有关系。$/.exec(s))) {
        return "“" + m[2] + "” appears in the Form SD list of all " + m[1] +
          " of these filers. That is co-listing only: it does not imply a purchasing relationship with this smelter, nor any relationship among these companies.";
      }
      if ((m = /^这 ([\d,]+) 家申报人的 Form SD 名单里都出现了「(.+)」。(.+)$/.exec(s))) {
        return "“" + m[2] + "” appears in the Form SD list of all " + m[1] +
          " of these filers. Co-listing only — it implies no purchasing relationship.";
      }
      /* 覆盖构成：「科技：共 84 家，有名单 34 家、有申报未列名单 26 家、无申报 24 家」
         以及被拆出来的单段「有名单 34 家」。分段翻，段名查表。 */
      var STATUS = { "有名单": "list disclosed", "有申报未列名单": "filed without a list",
        "申报资源开采付款": "filed resource-extraction payments", "无申报": "no filing",
        "无逐家记录": "no per-company record", "未分类": "unclassified" };
      if ((m = /^(.+?)：共 ([\d,]+) 家，(.+)$/.exec(s))) {
        var parts = m[3].replace(/。$/, "").split("、").map(function (x) {
          var pm = /^(.+?) ([\d,]+) 家$/.exec(x);
          return pm && STATUS[pm[1]] ? pm[2] + " " + STATUS[pm[1]] : x;
        });
        if (!/[\u4e00-\u9fff]/.test(parts.join(""))) {
          return (dict[m[1]] || m[1]) + ": " + m[2] + " companies — " + parts.join(", ");
        }
      }
      if ((m = /^(.+?) ([\d,]+) 家$/.exec(s)) && STATUS[m[1]]) return m[2] + " " + STATUS[m[1]];
      // 「金属矿采选（Metal Mining） 160 家」：括号里本来就是英文，去掉中文那一半。
      if ((m = /^(.+?)（(.+?)） ([\d,]+) 家$/.exec(s))) return m[2] + " " + m[3] + " companies";
      if ((m = /^(其他 \d+ 个国别／地区): ([\s\S]+)$/.exec(s))) {
        var om = /^其他 (\d+) 个国别／地区$/.exec(m[1]);
        return om[1] + " other countries/regions: " + m[2];
      }
      if (s === "等权涨跌") return "Equal-weighted move";
      if (s === "市值加权涨跌") return "Cap-weighted move";
      if ((m = /^市值合计只含 (\d+)\/([\d,]+) 家有站内报价的公司，不是本环节的总市值（其余是外国私人发行人，站内无行情）。$/.exec(s))) {
        return "The market-cap total covers only the " + m[1] + " of " + m[2] +
          " companies with an on-site quote — not the stage's full market cap (the rest are foreign private issuers, which this site carries no quotes for).";
      }
      /* 各环节的覆盖构成长句：分号分段、每段一个模板，逐段翻；
         只要还剩汉字就整串放弃、保留原文，不交出半中半英的句子。 */
      if ((m = /^本环节 ([\d,]+) 家：([\s\S]+)$/.exec(s))) {
        var body = m[2]
          .replace(/有名单 ([\d,]+) 家/g, "$1 with a list")
          .replace(/有申报但正文未列名单 ([\d,]+) 家/g, "$1 filed but with no list in the text")
          .replace(/申报的是 13q-1 资源开采付款 ([\d,]+) 家（那套披露里没有冶炼厂这个概念）/g,
            "$1 filed a 13q-1 resource-extraction payment report instead (that regime has no notion of a smelter)")
          .replace(/无 Form SD 申报 ([\d,]+) 家（规则只管产品含钽锡钨金的发行人，多数不适用）/g,
            "$1 filed no Form SD (the rule covers only issuers whose products contain tantalum, tin, tungsten or gold, so it does not apply to most)")
          .replace(/尚无逐家申报状态 ([\d,]+) 家/g, "$1 with no per-company filing status yet")
          .replace(/「无申报」不等于这些公司没有供应链。?/g,
            "“No filing” does not mean these companies have no supply chain.")
          .replace(/无申报不等于这些公司没有供应链。?/g,
            "“No filing” does not mean these companies have no supply chain.")
          .replace(/；/g, "; ").replace(/。/g, ". ").replace(/，/g, ", ");
        if (!/[\u4e00-\u9fff]/.test(body)) return "This stage has " + m[1] + " companies: " + body.trim();
      }
      if ((m = /^(未归类|未分类) ([\d,]+) 家$/.exec(s))) return m[2] + " ungrouped";
      if ((m = /^各价值链环节的公司与其申报冶炼厂所在国别之间的关系条数流向图，共 ([\d,]+) 条$/.exec(s))) {
        return "Flow of relationship counts between companies at each value-chain stage and the countries their filed smelters sit in — " + m[1] + " in all";
      }
      if (s === "历年名单变动") return "List changes by year";
      if (s === "按矿种的上游结构") return "Upstream structure by mineral";
      if (s === "按国别的上游暴露") return "Upstream exposure by country";
      if ((m = /^(.+?)：([\d,]+) 条关系、([\d,]+) 家冶炼厂、([\d,]+) 家申报人，分布在 ([\d,]+) 个国别。最大来源国 (.+?) 占 ([\d.]+%)，国别 HHI ([\d,]+)（(.+?)）。其中 ([\d,]+) 条落在 §1502 受涵盖国家。(?:另有 ([\d,]+) 条国别未写明，不计入集中度。)?$/.exec(s))) {
        var conc2 = { "未集中": "not concentrated", "中度集中": "moderately concentrated",
          "高度集中": "highly concentrated" }[m[9]] || m[9];
        return (dict[m[1]] || m[1]) + ": " + m[2] + " relationships, " + m[3] + " smelters, " + m[4] +
          " filers, across " + m[5] + " countries. Largest source country " + (dict[m[6]] || m[6]) +
          " at " + m[7] + "; country HHI " + m[8] + " (" + conc2 + "). Of these, " + m[10] +
          " fall in §1502 covered countries." +
          (m[11] ? " A further " + m[11] + " do not state a country and are excluded from the concentration measure." : "");
      }
      if ((m = /^(.+?)：登记表里 ([\d,]+) 家冶炼厂；([\d,]+) 家申报人的名单里出现过，合计 ([\d,]+) 条。「厂」数来自冶炼厂登记表，「条」数来自各家申报名单，两者分母不同。$/.exec(s))) {
        return (dict[m[1]] || m[1]) + ": " + m[2] + " smelters in the registry; they appear in the lists of " +
          m[3] + " filers, " + m[4] + " relationships in total. The smelter count comes from the smelter registry and the relationship count from the filed lists — the two have different denominators.";
      }
      if (s === "受涵盖国家暴露") return "Covered-country exposure";
      if ((m = /^(.+)：$/.exec(s)) && dict[m[1]]) return dict[m[1]] + ": ";
      if ((m = /^(\d+) 天前$/.exec(s))) return m[1] + " d ago";
      if ((m = /^(\d+) 小时前$/.exec(s))) return m[1] + " hr ago";
      if ((m = /^(\d+) 分钟前$/.exec(s))) return m[1] + " min ago";
      if (s === "多德-弗兰克 §1502 界定的受涵盖国家——这套申报制度就是为这十国立的。出现在名单里不等于用了冲突矿产。") {
        return "The covered countries defined by Dodd-Frank §1502 — the disclosure regime was written for these ten. Appearing in a list does not mean conflict minerals were used.";
      }
      if ((m = /^(.+?)：([\d,]+) 家有名单的公司（共 ([\d,]+) 家）的申报名单里出现过该国的冶炼厂，占 ([\d.]+%)；关系 ([\d,]+) 条，占全部 ([\d,]+) 条的 ([\d.]+%)。「出现在名单里」不等于采购关系。?$/.exec(s))) {
        return (dict[m[1]] || m[1]) + ": smelters in this country appear in the filed lists of " + m[2] +
          " of the " + m[3] + " companies that disclosed a list (" + m[4] + "); " + m[5] +
          " relationships, " + m[7] + " of all " + m[6] +
          ". Appearing in a list does not mean a purchasing relationship.";
      }
      if (s === "这家厂在登记表里有两条：一部分申报人给了 RMI 编号、一部分只给名字。登记表不做同义合并，所以它的真实共同申报数比这一行更高。") {
        return "This smelter has two entries in the registry: some filers gave an RMI identifier and some gave only a name. The registry does not merge synonyms, so its true co-filing count is higher than this row shows.";
      }
      if ((m = /^(.+?)：(\d{4}) → (\d{4}) 新增 ([\d,]+) 座、消失 ([\d,]+) 座，分母是该年带 RMI 编号的 ([\d,]+) 条。只比带编号的条目——只有名字的跨年追不了。?$/.exec(s))) {
        return (dict[m[1]] || m[1]) + ": " + m[2] + " → " + m[3] + ", " + m[4] + " added and " + m[5] +
          " dropped, against the " + m[6] + " entries carrying an RMI identifier that year. Only identified entries are compared — name-only entries cannot be tracked across years.";
      }
      if (s === "Form SD 每年 5 月 31 日前申报，冶炼厂关系一年只变一次；市值与涨跌来自站内行情，每日更新。") {
        return "Form SD is filed by 31 May each year, so smelter relationships change only once a year; market cap and the daily move come from on-site quotes and refresh daily.";
      }
      if ((m = /^未覆盖的 ([\d,]+) 家：(.+)$/.exec(s))) {
        var tail = m[2]
          .replace(/有申报未列名单 ([\d,]+) 家/g, "filed without a list in the text: $1")
          .replace(/申报的是 13q-1 资源开采付款 ([\d,]+) 家/g, "filed a 13q-1 resource-extraction payment report: $1")
          .replace(/未报 Form SD、规则不适用 ([\d,]+) 家/g, "no Form SD filed, the rule does not apply: $1")
          .replace(/尚无逐家申报状态 ([\d,]+) 家/g, "per-company filing status not yet known: $1")
          .replace(/未报申报不等于这些公司没有供应链，只表示公开渠道没有逐家名单。/g,
            "Not having filed does not mean these companies have no supply chain — only that no per-company list exists in public channels.")
          .replace(/未报申报不等于这些公司没有供应链。/g,
            "Not having filed does not mean these companies have no supply chain.")
          .replace(/市值合计只含 ([\d,]+)\/([\d,]+) 家有站内报价的公司，不是本环节的总市值（其余是外国私人发行人，站内无行情）。/g,
            "The market-cap total covers only the $1 of $2 companies with an on-site quote — not the stage's full market cap (the rest are foreign private issuers, which this site carries no quotes for).")
          .replace(/市值合计只含 ([\d,]+)\/([\d,]+) 家有站内报价的公司，不是该环节全部。/g,
            "The market-cap total covers only the $1 of $2 companies that have an on-site quote, not the whole stage.")
          .replace(/ 尚无逐家申报状态 ([\d,]+) 家/g, " · per-company filing status not yet known: $1");
        if (!/[\u4e00-\u9fff]/.test(tail)) return m[1] + " not covered: " + tail;
      }
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
        /* 尾巴只有「走扩」「更集中」两种取值（build_radar.py），认不出就整句不翻，
           不把中文原样塞进英文句子里。 */
        var brd = { "走扩": "broadening", "更集中": "more concentrated" }[m[2]];
        if (!brd) return null;
        return "Equal- vs. cap-weighted breadth: " + m[1] + "th percentile of the past two years, " + brd + " over 13 weeks";
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
        var enName = en.textContent.trim();
        nm.textContent = enName;
        /* 头像的 alt 存的是中文名，屏幕阅读器读到的还是中文。名字在 .en 里现成有，
           顺手一并换掉；走 attrOrig 记账，切回中文时和其他属性一起还原。 */
        var card = nm.closest && nm.closest(".rowcard");
        var img = card && card.querySelector(".ava img");
        if (img && img.getAttribute("alt") && img.getAttribute("alt") !== enName) {
          var saved = attrOrig.get(img);
          if (!saved) { saved = {}; attrOrig.set(img, saved); attrTouched.push(img); }
          if (!("alt" in saved)) saved.alt = img.getAttribute("alt");
          img.setAttribute("alt", enName);
        }
      }
    }
    if (path.indexOf("/apps/billionaires/") === 0) {
      /* 「▲ 今日领涨 埃隆·马斯克 +$23.32B」里只有中文名。榜单行里本来就有中英对照，
         借它建一张映射把 KPI 也换成英文名；映射里没有的（福布斯本就只给英文名、
         或该人不在当前页）一律保留原文，不音译、不臆造。 */
      var zhToEn = {};
      document.querySelectorAll(".rowcard .nm").forEach(function (nmEl) {
        var src = htmlOrig.has(nmEl) ? htmlOrig.get(nmEl) : nmEl.innerHTML;
        var tmp = document.createElement("div");
        tmp.innerHTML = src;
        var te = tmp.querySelector(".en");
        var zh = tmp.firstChild && tmp.firstChild.nodeType === 3 ? tmp.firstChild.nodeValue.trim() : "";
        if (zh && te && te.textContent.trim()) zhToEn[zh] = te.textContent.trim();
      });
      document.querySelectorAll(".lead").forEach(function (el) {
        var mm = /^([\u25B2\u25BC] .+?) ([\u4e00-\u9fff\u00B7]+) (.+)$/.exec(el.textContent.trim());
        if (!mm) return;
        /* 领涨/领跌的人常常不在当前这一页的榜单行里（榜单按身价排，KPI 按当日变动排），
           所以优先读 app.js 从 data.json 带过来的 data-en，取不到再退回本页的中英对照。 */
        var en = el.getAttribute("data-en") || zhToEn[mm[2]];
        if (!en) return;
        if (!htmlOrig.has(el)) { htmlOrig.set(el, el.innerHTML); htmlTouched.push(el); }
        el.textContent = mm[1] + " " + en + " " + mm[3];
      });
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
    var els = base.querySelectorAll ? base.querySelectorAll("[placeholder],[aria-label],[title],[alt]") : [];
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
