/* 品类行情板数据层：把站内已有的四条日更管道重新编排成六大品类。
   只做筛选、排序与格式化，不新增任何行情事实：价格、涨跌、数据日、频率、来源、
   代理关系和过期状态逐行沿用上游字段，上游没有的一律留空并如实说明。 */

/* 六大类的顺序、折叠阈值与附加列；折叠阈值即首屏直接显示的行数。 */
export const BOARD_CATEGORIES = Object.freeze([
  { key: "commodity", label: "商品", labelEn: "Commodities", collapseAfter: 8, extraLabel: "口径" },
  { key: "index", label: "指数", labelEn: "Indices", collapseAfter: 8, extraLabel: "地区" },
  { key: "stock", label: "股票", labelEn: "Stocks", collapseAfter: 8, extraLabel: "市值" },
  { key: "fx", label: "外汇", labelEn: "FX", collapseAfter: 6, extraLabel: "口径" },
  { key: "crypto", label: "加密", labelEn: "Crypto", collapseAfter: 6, extraLabel: "市值" },
  { key: "bond", label: "债券", labelEn: "Bonds", collapseAfter: 6, extraLabel: "期限",
    directionLabels: { up: "上行", down: "下行" } }
]);

/* 股票取到公司榜里全部有行情的上市公司：每一行都要画得出迷你走势、也都要能打开
   自己的走势页。500 与管道里的 HISTORY_SYMBOLS 是同一个数——两处必须一致，否则
   后面几百行会显示「无序列」。契约里跨语言钉住了这一点。 */
export const STOCK_ROW_LIMIT = 500;

/* 指数所属地区只用于分组说明，不参与任何计算。 */
const INDEX_REGION = Object.freeze({
  "^GSPC": "美国", "^N225": "日本", "^GDAXI": "德国", "^HSI": "中国香港",
  "^STI": "新加坡", "000300.SS": "中国内地", "510300.SS": "中国内地",
  "^NZ50": "新西兰", "^BSESN": "印度", "^AXJO": "澳大利亚",
  "000905.SS": "中国内地", "510500.SS": "中国内地", "^STOXX": "欧洲",
  "^FTSE": "英国", "^FCHI": "法国", "^KS11": "韩国", "^BVSP": "巴西",
  "^IXIC": "美国", "^RUT": "美国", "^VIX": "美国·波动率", "^TWII": "中国台湾",
  "^GSPTSE": "加拿大", "^SSMI": "瑞士", "^IBEX": "西班牙", "FTSEMIB.MI": "意大利",
  "^MXX": "墨西哥", "^JKSE": "印尼", "^TA125.TA": "以色列", "^AEX": "荷兰",
  "^BFX": "比利时", "^OMX": "瑞典", "^ATX": "奥地利", "XU100.IS": "土耳其",
  "WIG20.WA": "波兰", "^SET.BK": "泰国", "^KLSE": "马来西亚", "PSEI.PS": "菲律宾",
  "^IPSA": "智利", "^MERV": "阿根廷", "^HSTECH": "中国香港",
  /* 代理代码同样要登记：主代码取不到时，落进快照的是代理那一行。只登记主代码，
     页面上「地区」就会空着——2026-08-29 发现波兰、智利、恒生科技三行正是如此。 */
  EPOL: "波兰", ECH: "智利", "3033.HK": "中国香港", THD: "泰国", EPHE: "菲律宾",
  EWJ: "日本", EWY: "韩国", "^KS200": "韩国", "^FTMIB": "意大利",
  /* 2026-08-29 扩容的 26 条，逐条探测确认过是真指数后才登记。 */
  "^STOXX50E": "欧元区", "^N100": "泛欧", "^MDAXI": "德国", "^SDAXI": "德国",
  "^TECDAX": "德国", "OSEBX.OL": "挪威", "^OMXC25": "丹麦", "^OMXH25": "芬兰",
  "^ISEQ": "爱尔兰", "GD.AT": "希腊", "PSI20.LS": "葡萄牙",
  "^OMXRGI": "拉脱维亚", "^OMXVGI": "立陶宛", "^OMXTGI": "爱沙尼亚",
  "^RUI": "美国", "^NYA": "美国", "^SP400": "美国", "^W5000": "美国",
  "000001.SS": "中国内地", "399001.SZ": "中国内地", "^NSEI": "印度",
  "^HSCE": "中国香港", "^TASI.SR": "沙特", "^AORD": "澳大利亚",
  "^AXKO": "澳大利亚", "^J203.JO": "南非"
});

/* 股票品类下的二级分组：按行业。分组名直接用上游 data.json 里逐行的 sector，
   顺序按标普/GICS 的惯用次序固定写死——按当天的家数排会让标签位置天天变，
   读者刚记住「金融在第二个」，第二天就不是了。 */
export const STOCK_GROUPS = Object.freeze([
  { key: "科技", label: "科技", labelEn: "Technology" },
  { key: "金融", label: "金融", labelEn: "Financials" },
  { key: "工业", label: "工业", labelEn: "Industrials" },
  { key: "医疗健康", label: "医疗健康", labelEn: "Health Care" },
  { key: "可选消费", label: "可选消费", labelEn: "Consumer Discretionary" },
  { key: "必需消费", label: "必需消费", labelEn: "Consumer Staples" },
  { key: "通信服务", label: "通信服务", labelEn: "Communication Services" },
  { key: "能源", label: "能源", labelEn: "Energy" },
  { key: "公用事业", label: "公用事业", labelEn: "Utilities" },
  { key: "原材料", label: "原材料", labelEn: "Materials" },
  { key: "房地产", label: "房地产", labelEn: "Real Estate" },
  { key: "other", label: "其他", labelEn: "Other" }
]);

/* 指数品类下的二级分组：按地区。分区沿用参考站自己的划分（美洲/欧洲/亚洲/大洋洲/非洲），
   不另立「中东」——参考站把以色列、海湾各国都放在亚洲，自己再划一条线只会和它对不上。 */
export const INDEX_GROUPS = Object.freeze([
  { key: "americas", label: "美洲", labelEn: "Americas" },
  { key: "europe", label: "欧洲", labelEn: "Europe" },
  { key: "asia", label: "亚洲", labelEn: "Asia" },
  { key: "oceania", label: "大洋洲", labelEn: "Oceania" },
  { key: "africa", label: "非洲", labelEn: "Africa" },
  { key: "other", label: "其他", labelEn: "Other" }
]);

/* 逐代码登记，代理代码一并登记（理由同上面的地区表）。没登记的落进「其他」，
   不按代码后缀猜：.SS 是上海、.HK 是香港这类规则看着好用，遇到 ETF 代理就会分错，
   分错组比不分组更误导。 */
const INDEX_GROUP = Object.freeze({
  "^GSPC": "americas", "^IXIC": "americas", "^RUT": "americas", "^VIX": "americas",
  "^GSPTSE": "americas", "^BVSP": "americas", "^MXX": "americas",
  "^IPSA": "americas", ECH: "americas", "^MERV": "americas",
  "^STOXX": "europe", "^FTSE": "europe", "^GDAXI": "europe", "^FCHI": "europe",
  "^SSMI": "europe", "^IBEX": "europe", "FTSEMIB.MI": "europe", "^FTMIB": "europe",
  "^AEX": "europe", "^BFX": "europe", "^OMX": "europe", "^ATX": "europe",
  "XU100.IS": "europe", "WIG20.WA": "europe", EPOL: "europe",
  "^N225": "asia", EWJ: "asia", "^HSI": "asia", "^HSTECH": "asia", "3033.HK": "asia",
  "^STI": "asia", "000300.SS": "asia", "510300.SS": "asia",
  "000905.SS": "asia", "510500.SS": "asia", "^BSESN": "asia",
  "^KS11": "asia", "^KS200": "asia", EWY: "asia", "^TWII": "asia",
  "^JKSE": "asia", "^TA125.TA": "asia", "^SET.BK": "asia", THD: "asia",
  "^KLSE": "asia", "PSEI.PS": "asia", EPHE: "asia",
  "^AXJO": "oceania", "^NZ50": "oceania",
  /* 2026-08-29 扩容的 26 条。地区划分沿用参考站：沙特等海湾国家归亚洲，不另立中东。 */
  "^STOXX50E": "europe", "^N100": "europe", "^MDAXI": "europe", "^SDAXI": "europe",
  "^TECDAX": "europe", "OSEBX.OL": "europe", "^OMXC25": "europe", "^OMXH25": "europe",
  "^ISEQ": "europe", "GD.AT": "europe", "PSI20.LS": "europe",
  "^OMXRGI": "europe", "^OMXVGI": "europe", "^OMXTGI": "europe",
  "^RUI": "americas", "^NYA": "americas", "^SP400": "americas", "^W5000": "americas",
  "000001.SS": "asia", "399001.SZ": "asia", "^NSEI": "asia", "^HSCE": "asia",
  "^TASI.SR": "asia",
  "^AORD": "oceania", "^AXKO": "oceania",
  "^J203.JO": "africa"
});

/* 商品品类下的二级分组：一类三十多行，一条长列表看不出「这是能源还是金属」。
   分组是静态归类，只决定怎么摆，不参与计算，也不改动逐行的价格、涨跌、数据日与来源。 */
export const COMMODITY_GROUPS = Object.freeze([
  { key: "energy", label: "能源", labelEn: "Energy" },
  { key: "precious", label: "贵金属", labelEn: "Precious Metals" },
  { key: "base", label: "工业金属", labelEn: "Base Metals" },
  { key: "grain", label: "农产品", labelEn: "Grains & Oilseeds" },
  { key: "soft", label: "软商品", labelEn: "Softs" },
  { key: "livestock", label: "畜牧", labelEn: "Livestock" },
  { key: "index", label: "商品指数", labelEn: "Commodity Indices" },
  { key: "other", label: "其他", labelEn: "Other" }
]);

/* 逐代码登记。没登记的落进「其他」，不就近猜：分错组比不分组更误导。 */
const COMMODITY_GROUP = Object.freeze({
  "CL=F": "energy", "BZ=F": "energy", "NG=F": "energy", "HO=F": "energy",
  "RB=F": "energy", RWTC: "energy", "TTF=F": "energy",
  "GC=F": "precious", "SI=F": "precious", "PL=F": "precious", "PA=F": "precious",
  "HG=F": "base", "ALI=F": "base", DBB: "base", "HRC=F": "base",
  "ZW=F": "grain", "KE=F": "grain", "ZC=F": "grain", "ZS=F": "grain",
  "ZL=F": "grain", "ZM=F": "grain", "ZO=F": "grain", "ZR=F": "grain",
  "KC=F": "soft", "SB=F": "soft", "CC=F": "soft", "CT=F": "soft",
  "OJ=F": "soft", "LBR=F": "soft", "LBS=F": "soft",
  "LE=F": "livestock", "GF=F": "livestock", "HE=F": "livestock",
  "DC=F": "livestock", "CSC=F": "livestock",
  DBC: "index", GSG: "index", KRBN: "index"
});

/* 目前只有商品分了组；其余品类没有分组即不摆分组条。 */
/* 一张表登记「哪个品类有二级分组、分组表是哪份、逐代码登记表是哪份」。
   加第三个分组品类时只动这张表，不必再在 groupKeyOf 里加一条 if。 */
const GROUP_REGISTRY = Object.freeze({
  commodity: { groups: COMMODITY_GROUPS, bySymbol: COMMODITY_GROUP },
  index: { groups: INDEX_GROUPS, bySymbol: INDEX_GROUP },
  /* 股票没有逐代码登记表：行业由上游逐行声明（data.json 的 sector），
     声明的组名必须是上面登记过的，否则一律落进「其他」。 */
  stock: { groups: STOCK_GROUPS, bySymbol: {} }
});

export const GROUPS_BY_CATEGORY = Object.freeze({
  commodity: COMMODITY_GROUPS,
  index: INDEX_GROUPS,
  stock: STOCK_GROUPS
});

/* 分组来源有两处：期货那条管道按代码查登记表；商品现货管道自己就带 group 字段
   （它的品种在代码上看不出属于哪一组）。声明的组必须是已登记的组，否则一律落进
   「其他」——由上游随便写一个组名就能凭空造出一个分组，比不分组更糟。 */
export function groupKeyOf(categoryKey, symbol, declared) {
  const entry = GROUP_REGISTRY[categoryKey];
  if (!entry) return "";
  const named = String(declared || "");
  if (named && entry.groups.some((group) => group.key === named && group.key !== "other")) {
    return named;
  }
  return entry.bySymbol[String(symbol || "")] || "other";
}

/* 「口径」列按工具本身取值：=F 是期货，官方现货序列另标现货，其余是基金份额价格。
   三者不是同一种东西，不能都写成「期货」。 */
/* 非美元计价的商品逐个登记：价格格中会跟着写出币种，否则读者会默认它是美元。 */
const COMMODITY_CURRENCY = Object.freeze({ "TTF=F": "EUR" });

export function commodityBasis(symbol) {
  const text = String(symbol || "");
  if (!text) return "";
  return /=F$/.test(text) ? "期货" : "ETF代理";
}

/* 美债各期限的显示名；期限本身来自 curve.json，不在此处推算。 */
const TENOR_NAME = Object.freeze({
  DGS1MO: "美国1个月期国债收益率", DGS3MO: "美国3个月期国债收益率",
  DGS6MO: "美国6个月期国债收益率", DGS1: "美国1年期国债收益率",
  DGS2: "美国2年期国债收益率", DGS3: "美国3年期国债收益率",
  DGS5: "美国5年期国债收益率", DGS7: "美国7年期国债收益率",
  DGS10: "美国10年期国债收益率", DGS20: "美国20年期国债收益率",
  DGS30: "美国30年期国债收益率"
});

export function isFiniteNumber(value) {
  return typeof value === "number" && Number.isFinite(value);
}

/* 小数位：外汇按报价惯例，其余按数量级，避免把 1.1667 显示成 1.17。 */
export function priceDecimals(value, hint) {
  if (Number.isInteger(hint)) return hint;
  const abs = Math.abs(value);
  if (!Number.isFinite(abs) || abs === 0) return 2;
  if (abs >= 1) return 2;
  if (abs >= 0.01) return 4;
  return 6;
}

export function formatPrice(value, hint) {
  if (!isFiniteNumber(value)) return "—";
  const decimals = priceDecimals(value, hint);
  return value.toLocaleString("en-US", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals
  });
}

/* 涨跌显示：符号、箭头与文字同时给出，不把颜色当成唯一编码。 */
export function formatChange(value, unit) {
  if (!isFiniteNumber(value)) return { text: "—", direction: "unknown", arrow: "·" };
  const rounded = unit === "bp" ? Math.round(value) : Math.round(value * 100) / 100;
  const direction = rounded > 0 ? "up" : (rounded < 0 ? "down" : "flat");
  const arrow = direction === "up" ? "▲" : (direction === "down" ? "▼" : "▬");
  const sign = rounded > 0 ? "+" : "";
  const body = unit === "bp"
    ? `${sign}${rounded} bp`
    : `${sign}${rounded.toFixed(2)}%`;
  return { text: body, direction, arrow };
}

/* 亿美元：公司榜与资产榜的市值单位都是十亿美元。 */
/* 绝对变化：由已发布的最新价与涨跌幅现场复算（价 − 价 ÷ (1+涨跌%)），
   不引入第二个事实来源。涨跌缺失时不推算，留空。 */
export function absoluteChange(price, pct) {
  if (!isFiniteNumber(price) || !isFiniteNumber(pct) || pct === -100) return null;
  const previous = price / (1 + pct / 100);
  if (!Number.isFinite(previous)) return null;
  return price - previous;
}

export function formatAbsolute(value, hint) {
  if (!isFiniteNumber(value)) return "—";
  const sign = value > 0 ? "+" : "";
  return sign + formatPrice(value, hint);
}

/* 区间涨跌列（每周 / 月度 / 年初至今 / 同比）：上游已经算好的直接沿用，
   没算的留 null，由视图按站内历史现场补——两种来源都不允许推算或前向填充。 */
export function periodSet(returns) {
  const source = returns && typeof returns === "object" ? returns : {};
  const pick = (key) => (isFiniteNumber(source[key]) ? source[key] : null);
  return { w1: pick("w1"), m1: pick("m1"), ytd: pick("ytd"), y1: pick("y1") };
}

export function formatMarketCap(billions) {
  if (!isFiniteNumber(billions)) return "";
  const yi = billions * 10;
  if (yi >= 10000) return `${(yi / 10000).toFixed(2)}万亿美元`;
  return `${yi.toLocaleString("en-US", { maximumFractionDigits: 0 })}亿美元`;
}

/* 上游的数据日有的是日期、有的是完整时点；显示统一取日期部分，不改写原始字段。 */
export function formatAsOf(value) {
  const text = String(value || "");
  if (!text) return "";
  return /^\d{4}-\d{2}-\d{2}T/.test(text) ? text.slice(0, 10) : text;
}

function yahooUrl(symbol) {
  return `https://finance.yahoo.com/quote/${encodeURIComponent(String(symbol || ""))}`;
}

function statusOf(meta, stale) {
  if (stale === true) return "stale";
  const status = meta && typeof meta.status === "string" ? meta.status : "";
  if (status === "ok" || status === "partial" || status === "stale") return status;
  return "unknown";
}

/* 跨资产管道行 → 行情行。d1 就是该管道已算好的当日价格变动，不再二次加工。 */
function trackerRow(asset, categoryKey, options = {}) {
  const meta = asset && asset.dataMeta ? asset.dataMeta : {};
  const change = formatChange(asset && asset.returns ? asset.returns.d1 : null, "pct");
  return {
    id: `${categoryKey}:${asset.symbol}`,
    name: asset.name,
    nameEn: "",
    symbol: asset.symbol,
    priceText: formatPrice(asset.price, options.decimals),
    price: isFiniteNumber(asset.price) ? asset.price : null,
    change,
    changeAbs: absoluteChange(asset.price, asset && asset.returns ? asset.returns.d1 : null),
    periods: periodSet(asset && asset.returns),
    changeBasis: "较前一交易日收盘",
    extraText: options.extraText || "",
    asOf: formatAsOf(meta.asOf),
    updatedAt: meta.updatedAt || "",
    frequency: meta.frequency || "",
    sourceName: meta.source || "",
    sourceUrl: yahooUrl(asset.symbol),
    status: statusOf(meta, asset.stale),
    note: asset.note || (meta.note || ""),
    proxyOf: asset.proxy && asset.proxy.targetSymbol ? asset.proxy.targetSymbol : "",
    currency: options.currency || "",
    unit: options.unit || "",
    series: { kind: "tracker", key: asset.symbol }
  };
}

/* ICE美元指数（DX-Y.NYB）是专有基准，金融终端的许可决定是改用美联储广义美元指数
   DTWEXBGS 并准确改名，因此行情板不在本页重新发布它的点位。跨资产强弱卡沿用原有
   口径只比较各标的自身收益率，不受此处影响。 */
const BOARD_EXCLUDED_SYMBOLS = Object.freeze(["DX-Y.NYB"]);

/* 上游明确标为 unavailable 且连价格都没有的标的不进列表：那种行只有一串「—」，
   既不是行情也不是过期数据。管线本身的失败另有 #board-failures 与运行证据分区如实报告。 */
function trackerAssets(assetTracker, category) {
  const assets = assetTracker && Array.isArray(assetTracker.assets) ? assetTracker.assets : [];
  return assets.filter((asset) => asset && asset.category === category && asset.symbol
    && !BOARD_EXCLUDED_SYMBOLS.includes(asset.symbol)
    && !(asset.price === null && asset.dataMeta && asset.dataMeta.mode === "unavailable"));
}

/* 宏观雷达参考序列（FRED 广义美元指数、EIA 库欣WTI现货）→ 行情行。 */
function referenceRow(series, categoryKey, options = {}) {
  if (!series || !series.id) return null;
  const change = formatChange(series.changePct, "pct");
  return {
    id: `${categoryKey}:${series.id}`,
    name: series.name || series.id,
    nameEn: series.nameEn || "",
    symbol: series.id,
    priceText: formatPrice(series.price, options.decimals),
    price: isFiniteNumber(series.price) ? series.price : null,
    change,
    changeAbs: absoluteChange(series.price, series.changePct),
    periods: periodSet(series.returns),
    changeBasis: `较前一观测 ${series.previousAsOf || "—"}`,
    extraText: options.extraText || "",
    asOf: formatAsOf(series.asOf),
    updatedAt: series.updatedAt || "",
    frequency: series.frequency || "",
    sourceName: series.source && series.source.name ? series.source.name : "",
    sourceUrl: series.source && series.source.url ? series.source.url : "",
    status: series.status === "ok" ? "ok" : (series.status || "unknown"),
    note: series.note || "",
    proxyOf: "",
    currency: "",
    unit: options.unit || "",
    series: { kind: "macro", key: series.id }
  };
}

/* 美债曲线：值来自 curve.json 当期观测，当日变动由同一份历史的最后两个观测算出
   （bp = (今日 − 上一观测) × 100），公式可从文件字段直接复现。 */
export function tenorChangeBp(history, tenorId) {
  const values = history && history.values ? history.values[tenorId] : null;
  if (!Array.isArray(values)) return null;
  const points = values.filter(isFiniteNumber);
  if (points.length < 2) return null;
  return (points[points.length - 1] - points[points.length - 2]) * 100;
}

function curveRows(curve) {
  const tenors = curve && Array.isArray(curve.tenors) ? curve.tenors : [];
  return tenors.filter((tenor) => tenor && tenor.id).map((tenor) => {
    const change = formatChange(tenorChangeBp(curve.history, tenor.id), "bp");
    return {
      id: `bond:${tenor.id}`,
      name: TENOR_NAME[tenor.id] || `美国国债收益率 ${tenor.label}`,
      nameEn: "",
      symbol: tenor.id,
      priceText: isFiniteNumber(tenor.value) ? `${tenor.value.toFixed(2)}%` : "—",
      price: isFiniteNumber(tenor.value) ? tenor.value : null,
      change,
      changeAbs: null,
      periods: periodSet(null),
      changeBasis: "较前一观测（基点）",
      extraText: tenor.label || "",
      asOf: formatAsOf(tenor.asOf || curve.asOf),
      updatedAt: curve.updatedAt || "",
      frequency: curve.frequency || "",
      sourceName: curve.source || "",
      sourceUrl: `https://fred.stlouisfed.org/series/${encodeURIComponent(tenor.id)}`,
      status: tenor.current === true ? "ok" : "stale",
      note: tenor.current === true ? "" : "该期限在最新交易日没有官方观测，显示的是最近一次有观测的数值。",
      proxyOf: "",
      currency: "",
      unit: "年化收益率",
      series: { kind: "curve", key: tenor.id }
    };
  });
}

/* 公司榜 → 股票行。只取有真实行情的上市公司，未上市估值不进入行情板。 */
function stockRows(companies) {
  const list = companies && Array.isArray(companies.companies) ? companies.companies : [];
  return list
    .filter((item) => item && item.dataMeta && item.dataMeta.mode === "market" && isFiniteNumber(item.price))
    .slice(0, STOCK_ROW_LIMIT)
    .map((item) => {
      const meta = item.dataMeta || {};
      const change = formatChange(item.changePct, "pct");
      return {
        id: `stock:${item.symbol}`,
        name: item.name,
        nameEn: item.nameEn || "",
        symbol: item.symbol,
        priceText: formatPrice(item.price),
        price: item.price,
        change,
        changeAbs: absoluteChange(item.price, item.changePct),
        periods: periodSet(item.returns),
        changeBasis: "当日价格变动",
        extraText: formatMarketCap(item.marketCap),
        asOf: formatAsOf(meta.asOf),
        updatedAt: meta.updatedAt || "",
        frequency: meta.frequency || "",
        sourceName: meta.source || "",
        sourceUrl: yahooUrl(item.symbol),
        status: statusOf(meta, item.stale),
        note: item.sector ? `${item.country || ""} · ${item.sector}`.trim() : "",
        proxyOf: "",
        currency: item.priceCur || "",
        unit: item.priceCur || "",
        group: item.sector || "",
        series: { kind: "company", key: item.symbol }
      };
    });
}

/* 加密品类板 → 加密行。行情与日线来自同一次 CoinGecko 取数，涨跌是24小时口径。 */
function cryptoBoardRows(board) {
  const list = board && Array.isArray(board.assets) ? board.assets : [];
  return list
    .filter((item) => item && isFiniteNumber(item.price) && item.symbol)
    .map((item) => {
      const meta = item.dataMeta || {};
      return {
        id: `crypto:${item.symbol}`,
        name: item.name,
        nameEn: item.nameEn || "",
        symbol: item.symbol,
        priceText: formatPrice(item.price),
        price: item.price,
        change: formatChange(item.changePct, "pct"),
        changeAbs: absoluteChange(item.price, item.changePct),
        periods: periodSet(item.returns),
        changeBasis: "过去24小时",
        extraText: formatMarketCap(item.marketCap),
        asOf: formatAsOf(meta.asOf || board.asOf),
        updatedAt: meta.updatedAt || board.updatedAt || "",
        frequency: meta.frequency || board.frequency || "",
        sourceName: meta.source || board.source || "CoinGecko",
        sourceUrl: item.id
          ? `https://www.coingecko.com/en/coins/${encodeURIComponent(item.id)}`
          : "https://www.coingecko.com/",
        status: statusOf(meta, item.stale),
        note: "",
        proxyOf: "",
        currency: "USD",
        unit: "USD",
        series: { kind: "cryptoBoard", key: item.symbol }
      };
    });
}

/* 资产榜 → 加密行（加密品类板尚未生成时的回退）。同样是24小时口径，但没有日线。 */
function cryptoRows(assetRanking) {
  const list = assetRanking && Array.isArray(assetRanking.assets) ? assetRanking.assets : [];
  return list
    .filter((item) => item && item.category === "crypto" && isFiniteNumber(item.price))
    .map((item) => {
      const meta = item.dataMeta || {};
      const change = formatChange(item.changePct, "pct");
      return {
        id: `crypto:${item.symbol || item.name}`,
        name: item.name,
        nameEn: item.nameEn || "",
        symbol: item.symbol || "",
        priceText: formatPrice(item.price),
        price: item.price,
        change,
        changeAbs: absoluteChange(item.price, item.changePct),
        periods: periodSet(item.returns),
        changeBasis: "过去24小时",
        extraText: formatMarketCap(item.marketCap),
        asOf: formatAsOf(meta.asOf),
        updatedAt: meta.updatedAt || "",
        frequency: meta.frequency || "",
        sourceName: meta.source || "",
        sourceUrl: "https://www.coingecko.com/",
        status: statusOf(meta, item.stale),
        note: "",
        proxyOf: "",
        currency: "USD",
        unit: "USD",
        series: null
      };
    });
}

/* 汇总：只统计本类真实存在的涨跌方向，缺值不计入任何一边。 */
export function summarize(rows, labels) {
  const upLabel = (labels && labels.up) || "上涨";
  const downLabel = (labels && labels.down) || "下跌";
  const up = rows.filter((row) => row.change.direction === "up").length;
  const down = rows.filter((row) => row.change.direction === "down").length;
  const stale = rows.filter((row) => row.status === "stale").length;
  const dates = rows.map((row) => row.asOf).filter(Boolean).sort();
  const oldest = dates[0] || "";
  const newest = dates[dates.length - 1] || "";
  return {
    total: rows.length,
    up,
    down,
    stale,
    asOf: newest,
    /* 一类里混着不同频率时（商品同时有日频期货与月频现货），只写最新那天会把整类
       说得比实际更新。数据日不一致就给区间，一致才写单日。 */
    asOfRange: newest && oldest !== newest ? `${oldest} ~ ${newest}` : newest,
    text: rows.length
      ? `${rows.length}项 · ${upLabel}${up} · ${downLabel}${down}${stale ? ` · 过期${stale}` : ""}`
      : "本类暂无可用数据"
  };
}

/* 商品现货管道的「口径」列：它和期货不是一回事，频率也不是日频，逐条按自己的频率写明。 */
export function spotBasis(row) {
  const frequency = String(row && row.frequency || "");
  if (row && row.group === "index") return frequency === "monthly" ? "月度指数" : "官方指数";
  if (frequency === "monthly") return "月度现货";
  if (frequency === "weekly") return "周度均价";
  return "现货";
}

/* 商品现货与官方指数（FRED：EIA 日频现货 + IMF 月频初级商品价）→ 行情行。
   涨跌一律相对该序列自己的上一观测，绝不写成「当日涨跌」——它多数是月频。 */
function spotRows(commodities) {
  const list = commodities && Array.isArray(commodities.series) ? commodities.series : [];
  return list
    .filter((item) => item && item.id && isFiniteNumber(item.price))
    .map((item) => {
      const meta = item.dataMeta || {};
      const frequency = item.frequency || meta.frequency || "";
      return {
        id: `commodity:${item.id}`,
        name: item.name,
        nameEn: "",
        symbol: item.id,
        priceText: formatPrice(item.price),
        price: item.price,
        change: formatChange(item.changePct, "pct"),
        changeAbs: absoluteChange(item.price, item.changePct),
        periods: periodSet(item.returns),
        changeBasis: `较前一观测 ${item.previousAsOf || "—"}`,
        extraText: spotBasis(item),
        group: item.group || "",
        asOf: formatAsOf(meta.asOf),
        updatedAt: meta.updatedAt || commodities.updatedAt || "",
        frequency,
        sourceName: meta.source || commodities.source || "",
        sourceUrl: `https://fred.stlouisfed.org/series/${encodeURIComponent(item.id)}`,
        status: statusOf(meta, item.stale),
        note: item.note || meta.note || "",
        proxyOf: "",
        currency: "",
        unit: item.unit || "",
        series: { kind: "commodity", key: item.id, grain: frequency === "monthly" ? "monthly" : "daily" }
      };
    });
}

/* 贴分组并按登记组序重排；同组内保持上游顺序。没有分组的品类原样返回。 */
export function withGroups(rows, categoryKey) {
  const groups = GROUPS_BY_CATEGORY[categoryKey];
  if (!groups) return rows;
  const order = groups.map((group) => group.key);
  return rows
    .map((row, index) => ({ row, index, key: groupKeyOf(categoryKey, row.symbol, row.group) }))
    .sort((a, b) => (order.indexOf(a.key) - order.indexOf(b.key)) || (a.index - b.index))
    .map((entry) => Object.assign({}, entry.row, {
      group: entry.key,
      groupLabel: (groups.filter((group) => group.key === entry.key)[0] || {}).label || ""
    }));
}

/* 分组条只列出当前确实有行的组：一条都没有的组不摆空标签占位。 */
export function groupSummary(categoryKey, rows) {
  const groups = GROUPS_BY_CATEGORY[categoryKey];
  if (!groups) return [];
  return groups
    .map((group) => ({
      key: group.key,
      label: group.label,
      labelEn: group.labelEn,
      count: rows.filter((row) => row.group === group.key).length
    }))
    .filter((group) => group.count > 0);
}

function categoryRows(key, sources) {
  const { assetTracker, companies, assetRanking, macro, curve } = sources;
  if (key === "commodity") {
    const rows = trackerAssets(assetTracker, "commodity").map((asset) => trackerRow(asset, "commodity", {
      extraText: commodityBasis(asset.symbol),
      currency: COMMODITY_CURRENCY[asset.symbol] || ""
    }));
    const spot = macro && macro.referenceSeries ? macro.referenceSeries.RWTC : null;
    const spotRow = referenceRow(spot, "commodity", { extraText: "现货" });
    const withSpot = spotRow ? rows.concat([spotRow]) : rows;
    return withGroups(withSpot.concat(spotRows(sources.commodities)), "commodity");
  }
  if (key === "index") {
    return withGroups(trackerAssets(assetTracker, "equity").map((asset) => trackerRow(asset, "index", {
      extraText: INDEX_REGION[asset.symbol] || ""
    })), "index");
  }
  if (key === "stock") return withGroups(stockRows(companies), "stock");
  if (key === "fx") {
    const rows = trackerAssets(assetTracker, "fx").map((asset) => trackerRow(asset, "fx", {
      decimals: Math.abs(Number(asset.price)) >= 100 ? 3 : 4,
      extraText: "即期汇率"
    }));
    const broad = macro && macro.referenceSeries ? macro.referenceSeries.DTWEXBGS : null;
    const broadRow = referenceRow(broad, "fx", { decimals: 4, extraText: "贸易加权指数" });
    return broadRow ? rows.concat([broadRow]) : rows;
  }
  if (key === "crypto") {
    const fromBoard = cryptoBoardRows(sources.cryptoBoard);
    return fromBoard.length ? fromBoard : cryptoRows(assetRanking);
  }
  if (key === "bond") {
    return curveRows(curve).concat(
      trackerAssets(assetTracker, "bond").map((asset) => trackerRow(asset, "bond", { extraText: "ETF代理" }))
    );
  }
  return [];
}

/* 分区入口：任一上游失败只让对应品类为空并给出原因，其余品类照常显示。 */
export function buildBoard(group = {}) {
  const failures = [];
  function pick(key, label) {
    const entry = group[key];
    if (!entry) return null;
    if (entry.error) {
      failures.push(`${label}：${entry.error.message || "读取失败"}`);
      return null;
    }
    return entry.data;
  }
  /* 加密品类板是后补的可选文件：首次日更任务跑完之前它可能不存在，
     那不是管线故障，只回退到资产榜里已有的加密条目，不写进失败清单。 */
  function pickOptional(key) {
    const entry = group[key];
    return entry && !entry.error ? entry.data : null;
  }
  const sources = {
    assetTracker: pick("assetTracker", "跨资产管道"),
    companies: pick("companies", "公司榜"),
    assetRanking: pick("assetRanking", "资产榜"),
    macro: pick("macro", "宏观雷达"),
    curve: pick("macroCurve", "美债收益率曲线"),
    cryptoBoard: pickOptional("assetRankingCrypto"),
    /* 商品现货管道是后补的可选文件：首轮日更跑完前它可能不存在，
       那不是管线故障——期货那半边照常显示，缺的只是现货与官方指数那半边。 */
    commodities: pickOptional("commodities")
  };
  const categories = BOARD_CATEGORIES.map((category) => {
    const rows = categoryRows(category.key, sources);
    return {
      key: category.key,
      label: category.label,
      labelEn: category.labelEn,
      collapseAfter: category.collapseAfter,
      extraLabel: category.extraLabel,
      rows,
      groups: groupSummary(category.key, rows),
      summary: summarize(rows, category.directionLabels)
    };
  });
  const withRows = categories.filter((category) => category.rows.length);
  const total = categories.reduce((sum, category) => sum + category.rows.length, 0);
  return {
    categories,
    total,
    status: withRows.length === categories.length ? "ok" : (withRows.length ? "partial" : "error"),
    failures,
    curveHistory: sources.curve && sources.curve.history ? sources.curve.history : null,
    cryptoHistory: sources.cryptoBoard && sources.cryptoBoard.history
      ? sources.cryptoBoard.history : null,
    summaryText: total
      ? `${withRows.length}/${categories.length}类 · ${total}项标的`
      : "品类行情暂不可用"
  };
}
