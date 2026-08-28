/* 品类行情板数据层：把站内已有的四条日更管道重新编排成六大品类。
   只做筛选、排序与格式化，不新增任何行情事实：价格、涨跌、数据日、频率、来源、
   代理关系和过期状态逐行沿用上游字段，上游没有的一律留空并如实说明。 */

/* 六大类的顺序、折叠阈值与附加列；折叠阈值即首屏直接显示的行数。 */
export const BOARD_CATEGORIES = Object.freeze([
  { key: "commodity", label: "商品", labelEn: "Commodities", collapseAfter: 8, extraLabel: "口径" },
  { key: "index", label: "指数", labelEn: "Indices", collapseAfter: 6, extraLabel: "地区" },
  { key: "stock", label: "股票", labelEn: "Stocks", collapseAfter: 8, extraLabel: "市值" },
  { key: "fx", label: "外汇", labelEn: "FX", collapseAfter: 6, extraLabel: "口径" },
  { key: "crypto", label: "加密", labelEn: "Crypto", collapseAfter: 6, extraLabel: "市值" },
  { key: "bond", label: "债券", labelEn: "Bonds", collapseAfter: 6, extraLabel: "期限",
    directionLabels: { up: "上行", down: "下行" } }
]);

/* 股票只取市值最高的一段：与公司榜日线历史覆盖的标的数一致，让每一行都能画走势；
   全部500家仍在全球公司榜页面完整展示。 */
export const STOCK_ROW_LIMIT = 40;

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
  "^IPSA": "智利", "^MERV": "阿根廷", "^HSTECH": "中国香港"
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
  "RB=F": "energy", "B0=F": "energy", RWTC: "energy",
  "GC=F": "precious", "SI=F": "precious", "PL=F": "precious", "PA=F": "precious",
  "HG=F": "base", "ALI=F": "base", DBB: "base",
  "ZW=F": "grain", "KE=F": "grain", "ZC=F": "grain", "ZS=F": "grain",
  "ZL=F": "grain", "ZM=F": "grain", "ZO=F": "grain", "ZR=F": "grain",
  "KC=F": "soft", "SB=F": "soft", "CC=F": "soft", "CT=F": "soft",
  "OJ=F": "soft", "LBR=F": "soft", "LBS=F": "soft",
  "LE=F": "livestock", "GF=F": "livestock", "HE=F": "livestock",
  DBC: "index", GSG: "index", KRBN: "index"
});

/* 目前只有商品分了组；其余品类没有分组即不摆分组条。 */
export const GROUPS_BY_CATEGORY = Object.freeze({ commodity: COMMODITY_GROUPS });

export function groupKeyOf(categoryKey, symbol) {
  if (categoryKey !== "commodity") return "";
  return COMMODITY_GROUP[String(symbol || "")] || "other";
}

/* 「口径」列按工具本身取值：=F 是期货，官方现货序列另标现货，其余是基金份额价格。
   三者不是同一种东西，不能都写成「期货」。 */
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
  return {
    total: rows.length,
    up,
    down,
    stale,
    asOf: dates.length ? dates[dates.length - 1] : "",
    text: rows.length
      ? `${rows.length}项 · ${upLabel}${up} · ${downLabel}${down}${stale ? ` · 过期${stale}` : ""}`
      : "本类暂无可用数据"
  };
}

/* 贴分组并按登记组序重排；同组内保持上游顺序。没有分组的品类原样返回。 */
export function withGroups(rows, categoryKey) {
  const groups = GROUPS_BY_CATEGORY[categoryKey];
  if (!groups) return rows;
  const order = groups.map((group) => group.key);
  return rows
    .map((row, index) => ({ row, index, key: groupKeyOf(categoryKey, row.symbol) }))
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
      extraText: commodityBasis(asset.symbol)
    }));
    const spot = macro && macro.referenceSeries ? macro.referenceSeries.RWTC : null;
    const spotRow = referenceRow(spot, "commodity", { extraText: "现货" });
    return withGroups(spotRow ? rows.concat([spotRow]) : rows, "commodity");
  }
  if (key === "index") {
    return trackerAssets(assetTracker, "equity").map((asset) => trackerRow(asset, "index", {
      extraText: INDEX_REGION[asset.symbol] || ""
    }));
  }
  if (key === "stock") return stockRows(companies);
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
    cryptoBoard: pickOptional("assetRankingCrypto")
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
