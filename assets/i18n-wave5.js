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

  function translateRaw(raw) {
    if (raw == null) return raw;
    var dict = dictionary();
    if (Object.prototype.hasOwnProperty.call(dict, raw)) return dict[raw];
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
