import assert from "node:assert/strict";
import {
  derivePipelineSummary,
  deriveRegionalHeatmap
} from "../apps/finance-terminal/finance-terminal-visuals.mjs";
import { deriveRiskRadar } from "../apps/finance-terminal/finance-terminal-risk-radar.mjs";
import { textureCoordinate } from "../apps/finance-terminal/finance-terminal-globe.mjs";
import { regionAt } from "../apps/finance-terminal/finance-terminal-worldmap.mjs";
import { sessionState } from "../apps/finance-terminal/finance-terminal-sessions.mjs";
import { sanitizeSymbol, normalizeList, toggleSymbol, orderByWatchlist, describeFilter, createWatchlistStore }
  from "../apps/finance-terminal/finance-terminal-watchlist.mjs";
import { seriesPath, matchedKeyword }
  from "../apps/finance-terminal/finance-terminal-detail-view.mjs";
import { AXIS_LABELS, riskReading, pairAxes }
  from "../apps/finance-terminal/finance-terminal-radar-view.mjs";
import { RADAR_SIGNAL_KEYS } from "../apps/finance-terminal/finance-terminal-risk-radar.mjs";
import { logReturns, sessionAligned, pearson, buildMatrix, MIN_OVERLAP }
  from "../apps/finance-terminal/finance-terminal-correlation-view.mjs";
import { tenorX, valueY, curveSegments, describeShape }
  from "../apps/finance-terminal/finance-terminal-curve-view.mjs";
import { pickIndexRows, describeRows, formatChange }
  from "../apps/finance-terminal/finance-terminal-gateway-preview.mjs";

function asset(symbol, dailyReturn, options = {}) {
  return {
    symbol,
    returns: { d1: dailyReturn },
    stale: options.stale === true,
    suspect: options.suspect === true,
    proxy: options.proxy === true ? { type: "etf" } : null
  };
}

const regionalCard = {
  id: "cross-asset",
  status: "ok",
  assets: [
    asset("^GSPC", -1.2),
    asset("^BVSP", 0.4),
    asset("^STOXX", -0.4),
    asset("^FTSE", 0.2),
    asset("^GDAXI", 0.4),
    asset("^FCHI", -0.2),
    asset("510300.SS", -0.8, { proxy: true }),
    asset("^HSI", 0.2),
    asset("^N225", -0.3),
    asset("^BSESN", 0),
    asset("^AXJO", 0.5),
    asset("^NZ50", 0.3)
  ]
};

const regions = deriveRegionalHeatmap(regionalCard);
assert.equal(regions.length, 7, "热力图必须生成七组有真实代表指数的区域");
assert.equal(regions.find((region) => region.id === "north-america")?.value, -1.2);
assert.equal(regions.find((region) => region.id === "europe")?.value, 0);
assert.ok(Math.abs(regions.find((region) => region.id === "greater-china")?.value + 0.3) < 1e-12);
assert.equal(regions.find((region) => region.id === "greater-china")?.assets[0].proxy?.type, "etf");
assert.deepEqual(deriveRegionalHeatmap({ status: "error", assets: [] }), [],
  "区域数据错误时不得生成推断值");

const pipelineCards = [
  ["macro-radar", "healthy", 5],
  ["asset-tracker", "healthy", 6],
  ["companies", "degraded", 5],
  ["asset-ranking", "stale", 7]
].map(([id, status, cycles]) => ({
  id,
  status,
  readiness: { consecutiveSuccessfulCycles: cycles, reportStale: false }
}));

const progress = derivePipelineSummary(pipelineCards);
assert.deepEqual(progress, {
  minimumCycle: 5,
  evidenceStale: false,
  healthy: 2,
  degraded: 2,
  failed: 0
}, "稳定V1 HUD必须使用四管线最小连续周期且独立汇总健康状态");

const ready = derivePipelineSummary(pipelineCards.map((card) => ({
  ...card,
  status: "healthy",
  readiness: { consecutiveSuccessfulCycles: 7, reportStale: false }
})));
assert.equal(ready.minimumCycle, 7, "四管线全部7/7时必须可复算为完整资格");
assert.equal(ready.healthy, 4);

const staleEvidence = derivePipelineSummary(pipelineCards.map((card) => ({
  ...card,
  readiness: { ...card.readiness, reportStale: card.id === "macro-radar" }
})));
assert.equal(staleEvidence.minimumCycle, 5, "证据过期不得清空已有周期");
assert.equal(staleEvidence.evidenceStale, true, "任一资格证据过期必须向HUD传播");

assert.equal(derivePipelineSummary(pipelineCards.slice(0, 3)).minimumCycle, null,
  "缺少任一核心管线时不得显示伪造的总资格进度");

const radarProbe = deriveRiskRadar([{ regimeSignals: [
  { key: "realrate", score: 11 }, { key: "term", score: 55 }, { key: "usd", score: 68 },
  { key: "volatility", score: 87 }, { key: "credit", score: 74 }, { key: "liquidity", score: 31 }
] }]);
assert.equal(radarProbe.values.length, 6, "风险雷达必须输出六个维度");
assert.ok(radarProbe.values.every((value) => value >= 0 && value <= 100));
assert.ok(radarProbe.score >= 0 && radarProbe.score <= 10);
assert.equal(deriveRiskRadar([{ regimeSignals: [{ key: "realrate", score: 11 }] }]), null,
  "制度信号不完整时风险雷达不得生成推断分数");

assert.equal(textureCoordinate(0, 0), .5, "地球中央经线必须映射到纹理中央");
assert.equal(textureCoordinate(0, 1), .75, "地球右侧边缘必须映射到东经90度");
assert.equal(textureCoordinate(0, -1), .25, "地球左侧边缘必须映射到西经90度");


/* 交易时段：纯日历推导，覆盖盘中、午休、盘前、收盘、周末与未知时区。 */
const at = (iso, zone) => sessionState(zone, new Date(iso));
assert.equal(at("2026-08-19T18:00:00Z", "America/New_York").state, "open",
  "周三纽约14:00应处于常规交易时段");
assert.equal(at("2026-08-20T00:00:00Z", "America/New_York").state, "closed",
  "纽约收盘后不得仍标记为开盘");
assert.equal(at("2026-08-19T12:00:00Z", "America/New_York").state, "pre",
  "纽约盘前应标记为待开盘");
assert.equal(at("2026-08-19T11:00:00Z", "Europe/London").state, "open",
  "周三伦敦12:00应处于常规交易时段");
assert.equal(at("2026-08-19T04:00:00Z", "Asia/Shanghai").state, "lunch",
  "上海12:00应识别为午间休市而非收盘");
assert.equal(at("2026-08-19T03:00:00Z", "Asia/Tokyo").state, "lunch",
  "东京12:00应识别为午间休市而非收盘");
assert.ok(at("2026-08-19T02:30:00Z", "Asia/Shanghai").detail.includes("午休"),
  "上半场剩余时间应指向午休而非收盘");
assert.ok(at("2026-08-19T06:00:00Z", "Asia/Shanghai").detail.includes("收盘"),
  "下半场剩余时间应指向收盘");
assert.equal(at("2026-08-22T18:00:00Z", "America/New_York").state, "weekend",
  "周六必须标记为周末休市");
assert.equal(at("2026-08-19T18:00:00Z", "Mars/Olympus").state, "unknown",
  "无法解析的时区必须返回未知而不是猜测开盘");


/* 自选清单：代码清洗、纯函数切换、稳定排序与存储不可用降级。 */
assert.equal(sanitizeSymbol("BTC/USD"), "BTC/USD", "合法标的代码必须原样保留");
assert.equal(sanitizeSymbol("<script>"), null, "含尖括号的输入不得写入本地存储");
assert.equal(sanitizeSymbol("x".repeat(50)), null, "超长输入必须拒绝");
assert.equal(normalizeList(["A", "A", "B"]).join(), "A,B", "自选必须去重");
assert.equal(normalizeList(Array.from({ length: 80 }, (_, i) => `S${i}`)).length, 40,
  "自选条数必须有上限");

const baseList = ["SPY"];
assert.equal(toggleSymbol("QQQ", baseList).join(), "SPY,QQQ", "切换必须能新增");
assert.equal(baseList.join(), "SPY", "切换不得修改入参数组");
assert.equal(toggleSymbol("SPY", ["SPY", "QQQ"]).join(), "QQQ", "再次切换必须移除");

const ordered = orderByWatchlist(
  [{ s: "A" }, { s: "B" }, { s: "C" }, { s: "D" }], ["C", "A"], (item) => item.s);
assert.equal(ordered.map((item) => item.s).join(""), "ACBD",
  "自选须前置且两组内部各自保持原有相对顺序");

assert.equal(describeFilter(0, false, true).hidden, true, "无自选时筛选入口必须隐藏");
assert.equal(describeFilter(2, true, true).label, "显示全部", "筛选开启时入口应提供退出");
assert.ok(describeFilter(2, false, false).title.includes("仅在本次会话有效"),
  "存储不可用时必须如实说明不跨会话保留");

const blocked = { getItem() { throw new Error("blocked"); }, setItem() { throw new Error("blocked"); } };
const degraded = createWatchlistStore(blocked);
degraded.toggle("SPY");
assert.ok(degraded.has("SPY"), "存储被拦时自选仍应在本次会话内生效");
assert.equal(degraded.persisted(), false, "存储被拦时不得声称已保存");

assert.equal(seriesPath([1], 100, 50, 5), "", "不足两点时不得画出任何折线");
assert.equal(seriesPath([], 100, 50, 5), "", "空序列不得画出任何折线");
assert.equal(seriesPath([1, "x", null, 3], 100, 50, 5), seriesPath([1, 3], 100, 50, 5),
  "非有限值必须整点剔除而非当作零");
const flat = seriesPath([2, 2, 2], 100, 50, 5);
assert.ok(flat.startsWith("M5.0 ") && !flat.includes("NaN"),
  "全平序列不得因零跨度产生 NaN 坐标");
const shaped = seriesPath([0, 10], 100, 50, 5);
assert.equal(shaped, "M5.0 45.0 L95.0 5.0",
  "最低点须落在下边距、最高点须落在上边距，且首尾贴合内框");

assert.equal(matchedKeyword("美联储维持利率不变", ["利率", "黄金"]), "利率",
  "必须返回实际命中的关键词以便如实标注匹配依据");
assert.equal(matchedKeyword("美联储维持利率不变", ["黄金"]), null, "未命中必须返回 null");
assert.equal(matchedKeyword(null, ["利率"]), null, "标题缺失不得抛错或误判命中");
assert.equal(matchedKeyword("SPY 创新高", []), null, "无关键词时不得声称命中");

/* 雷达六轴现在各读一个真实制度信号，风险 = 100 − 分数。 */
{
  const SIGNALS = [
    { key: "liquidity", label: "流动性", score: 31 }, { key: "volatility", label: "波动率", score: 87 },
    { key: "term", label: "期限溢价", score: 55 }, { key: "realrate", label: "实际利率", score: 11 },
    { key: "credit", label: "信用利差", score: 74 }, { key: "growth", label: "增长动能", score: 61 },
    { key: "usd", label: "美元汇率", score: 68 }, { key: "breadth", label: "市场广度", score: 66 }
  ];
  const cards = [{ id: "macro-regime", regimeSignals: SIGNALS }];
  const radar = deriveRiskRadar(cards);
  assert.ok(radar, "八个信号齐备时雷达必须出值");
  assert.equal(RADAR_SIGNAL_KEYS.length, 6, "雷达必须是六个轴");
  assert.equal(AXIS_LABELS.length, 6, "轴名数量必须与轴数一致");

  /* 抽屉与雷达是两份独立读取，任何一方改了映射这里立刻失败。 */
  const paired = pairAxes(SIGNALS);
  paired.forEach((axis, index) => {
    assert.equal(axis.key, RADAR_SIGNAL_KEYS[index], `第${index + 1}轴的信号键必须与雷达一致`);
    assert.ok(Math.abs(axis.reading * 10 - radar.values[index]) < 1e-9,
      `第${index + 1}轴「${axis.label}」抽屉读数与雷达不一致`);
  });

  /* 方向必须正确：信号越高（越宽松）风险越低。 */
  assert.equal(riskReading(87), 1.3, "波动率信号 87 对应风险 1.3");
  assert.equal(riskReading(11), 8.9, "实际利率信号 11 对应风险 8.9");
  assert.equal(riskReading(null), null, "分数缺失必须返回 null 而非猜测");
  const volatility = paired.find((axis) => axis.key === "volatility");
  const realrate = paired.find((axis) => axis.key === "realrate");
  assert.ok(volatility.reading < realrate.reading,
    "波动率信号高于实际利率信号时，其风险读数必须更低——方向写反会让整张雷达读反");

  /* 真实信号必须体现离散度；此前六轴由一个分数重组，全挤在中段。 */
  const spread = Math.max(...radar.values) - Math.min(...radar.values);
  assert.ok(spread > 50, `六轴应反映真实差异，当前跨度 ${spread.toFixed(1)}`);

  /* 缺任一信号即整体空态，不用其他轴顶替。 */
  RADAR_SIGNAL_KEYS.forEach((key) => {
    const partial = SIGNALS.filter((signal) => signal.key !== key);
    assert.equal(deriveRiskRadar([{ regimeSignals: partial }]), null,
      `缺 ${key} 信号时雷达必须整体空态`);
    const gap = pairAxes(partial).find((axis) => axis.key === key);
    assert.equal(gap.reading, null, `缺 ${key} 时抽屉对应轴必须留空`);
    assert.equal(gap.signal, null, `缺 ${key} 时不得用其他信号顶替`);
  });
  assert.equal(deriveRiskRadar([{ id: "x" }]), null, "没有宏观卡时必须空态");
  assert.equal(deriveRiskRadar([]), null, "空输入必须空态");
}


/* 地图不得替没有代表指数的地区着色：这些地点站内没有任何指数，必须留白。 */
{
  const REGIONS = ["north-america", "south-america", "europe", "greater-china",
    "japan", "south-asia", "oceania"].map((id) => ({ id }));
  const mustCover = [["纽约", -74, 40.7, "north-america"], ["圣保罗", -46.6, -23.5, "south-america"],
    ["伦敦", -0.1, 51.5, "europe"], ["里斯本", -9.1, 38.7, "europe"], ["雅典", 23.7, 38, "europe"],
    ["上海", 121.5, 31.2, "greater-china"], ["乌鲁木齐", 87.6, 43.8, "greater-china"],
    ["东京", 139.7, 35.7, "japan"], ["新德里", 77.2, 28.6, "south-asia"],
    ["孟买", 72.8, 19, "south-asia"], ["悉尼", 151.2, -33.9, "oceania"]];
  const mustStayBlank = [["拉各斯", 3.4, 6.5], ["开罗", 31.2, 30], ["约翰内斯堡", 28, -26.2],
    ["内罗毕", 36.8, -1.3], ["利雅得", 46.7, 24.7], ["德黑兰", 51.4, 35.7],
    ["莫斯科", 37.6, 55.8], ["伊斯坦布尔", 29, 41], ["首尔", 127, 37.5],
    ["雅加达", 106.8, -6.2], ["曼谷", 100.5, 13.8]];
  mustCover.forEach(([name, lon, lat, expected]) => {
    const hit = regionAt(lon, lat, REGIONS);
    assert.equal(hit && hit.id, expected, `${name}应归入${expected}`);
  });
  mustStayBlank.forEach(([name, lon, lat]) => {
    assert.equal(regionAt(lon, lat, REGIONS), null,
      `${name}所在国家站内没有代表指数，地图不得借邻近区域的涨跌为其着色`);
  });
}

/* 收益率曲线：缺档必须断线，绝不插值跨过空洞。 */
{
  const pts = (vals) => vals.map((v, i) => (v === null ? null : { value: v, months: i + 1 }));
  assert.equal(curveSegments(pts([1, 2, 3])).length, 1, "无缺档应为一整段");
  assert.equal(curveSegments(pts([1, 2, null, 4, 5])).length, 2,
    "中间缺档必须断成两段，不得插值跨过");
  assert.equal(curveSegments(pts([1, null, 3])).length, 0,
    "两侧各只剩一点时无法成线，不得画出任何线段");
  assert.equal(curveSegments(pts([null, null])).length, 0, "全缺档不画线");
  assert.equal(curveSegments([]).length, 0, "空输入不画线");

  /* 对数横轴：短端不得挤在一起，且首尾贴合内边距。 */
  assert.equal(tenorX(1, 1, 360).toFixed(1), "26.0", "最短期限落在左内边距");
  assert.equal(tenorX(360, 1, 360).toFixed(1), "494.0", "最长期限落在右内边距");
  assert.ok(tenorX(12, 1, 360) > tenorX(3, 1, 360), "期限越长横坐标越大");
  const shortGap = tenorX(3, 1, 360) - tenorX(1, 1, 360);
  const longGap = tenorX(360, 1, 360) - tenorX(120, 1, 360);
  assert.ok(shortGap > longGap * 0.5,
    "对数轴下短端间距不应被长端压缩到难以分辨");
  assert.equal(tenorX(0, 1, 360), 26, "非法月数回退到左内边距而非产生 NaN");

  assert.equal(valueY(5, 5, 5).toFixed(1), "144.0", "全平序列不得因零跨度产生 NaN");
  assert.ok(valueY(5, 3, 5) < valueY(3, 3, 5), "读数越高纵坐标越靠上");

  const t = (label, value, months) => ({ label, value, months });
  assert.equal(describeShape([t("1M", 5.4, 1), t("2Y", 4.6, 24), t("10Y", 4.1, 120)]),
    "整体倒挂 · 短端高于长端");
  assert.equal(describeShape([t("1M", 4.0, 1), t("2Y", 4.3, 24), t("10Y", 4.8, 120)]),
    "正常上行 · 长端明显高于短端");
  assert.equal(describeShape([t("1M", 4.3, 1), t("10Y", 4.5, 120)]),
    "读数不足，不判断形态", "少于三个可用读数时不得给出形态结论");
  assert.equal(describeShape([t("1M", null, 1), t("2Y", null, 24), t("10Y", 4.1, 120)]),
    "读数不足，不判断形态", "缺读数的档位不得计入形态判断");
}

/* 相关性矩阵的三条口径必须钉住：用收益率不用价位、错位日历整列剔除、
   重叠样本不足不给数。任何一条松掉，页面就会显示看起来专业却是错的系数。 */
{
  assert.deepEqual(logReturns([]).length, 0);
  assert.equal(logReturns([100, 110])[0], null, "第一个交易日没有前一日，收益率必须留空");
  assert.ok(Math.abs(logReturns([100, 110])[1] - Math.log(1.1)) < 1e-12);
  assert.equal(logReturns([100, null, 110])[2], null, "缺报价处不得跨日拼出收益率");
  assert.equal(logReturns([100, null, 110])[1], null);
  assert.equal(logReturns([0, 10])[1], null, "非正价位不得进入对数收益率");

  const weekdays = ["2026-08-17", "2026-08-18", "2026-08-19"];
  const withWeekend = ["2026-08-16", "2026-08-17", "2026-08-18"];
  assert.equal(sessionAligned(weekdays, [1, 2, 3]), true);
  assert.equal(sessionAligned(withWeekend, [1, 2, 3]), false, "周日出现观测即判定日历错位");
  assert.equal(sessionAligned(withWeekend, [null, 2, 3]), true, "周末留空不算错位");

  /* 完全同向与完全反向的两条序列，系数必须是 ±1；样本不足则一律不给数。 */
  const up = [];
  const down = [];
  for (let index = 0; index < MIN_OVERLAP + 5; index += 1) {
    up.push((index % 7) - 3);
    down.push(3 - (index % 7));
  }
  assert.ok(Math.abs(pearson(up, up).value - 1) < 1e-12);
  assert.ok(Math.abs(pearson(up, down).value + 1) < 1e-12);
  assert.equal(pearson(up.slice(0, MIN_OVERLAP - 1), down.slice(0, MIN_OVERLAP - 1)).value, null,
    `重叠样本少于 ${MIN_OVERLAP} 天必须留空，不得给出不稳定的系数`);
  assert.equal(pearson(up, up.map(() => 5)).value, null, "常数序列没有相关性可言，不得返回数字");

  const dates = [];
  const rising = [];
  const falling = [];
  const misaligned = [];
  let cursor = Date.UTC(2026, 0, 5);
  while (dates.length < MIN_OVERLAP + 6) {
    const day = new Date(cursor);
    if (day.getUTCDay() !== 0 && day.getUTCDay() !== 6) {
      dates.push(day.toISOString().slice(0, 10));
      /* 两条价位路径的对数收益率互为相反数，相关系数因此正好是 −1。
         直接用镜像价位是不行的：log 是非线性的，镜像价位并不给出镜像收益率。 */
      const step = ((dates.length % 5) - 2) / 100;
      const previousUp = rising.length ? rising[rising.length - 1] : 100;
      const previousDown = falling.length ? falling[falling.length - 1] : 300;
      rising.push(rising.length ? previousUp * Math.exp(step) : previousUp);
      falling.push(falling.length ? previousDown * Math.exp(-step) : previousDown);
      misaligned.push(50 + dates.length);
    }
    cursor += 86400000;
  }
  /* 把一个周末观测塞进第三条序列：它必须整列出局，另外两条照常入表。 */
  dates.push("2026-04-05");
  rising.push(null);
  falling.push(null);
  misaligned.push(77);
  const matrix = buildMatrix(
    { dates, series: { RISE: rising, FALL: falling, SKEW: misaligned } },
    [{ symbol: "RISE", name: "上行", category: "equity" },
      { symbol: "FALL", name: "下行", category: "equity" },
      { symbol: "SKEW", name: "错位", category: "fx" }]
  );
  assert.deepEqual(matrix.symbols, ["FALL", "RISE"], "日历错位的标的不得进入矩阵");
  assert.equal(matrix.excluded.length, 1);
  assert.equal(matrix.excluded[0].symbol, "SKEW");
  assert.equal(matrix.excluded[0].weekend, 1, "被剔除的标的必须如实记录周末观测数");
  assert.equal(matrix.cells.length, 1, "两个标的只应产生一组配对，不重复计对角线两侧");
  assert.ok(Math.abs(matrix.cells[0].value + 1) < 1e-12, "构造的完全反向序列必须给出 −1");
  assert.ok(matrix.cells[0].n >= MIN_OVERLAP);
}

console.log("Finance Terminal visual data contracts: PASS");
console.log("- seven-region daily return pressure proxy / error isolation: PASS");
console.log("- dynamic 5/7 to 7/7 minimum-cycle continuity / stale evidence preservation: PASS");
console.log("- three-source normalized six-axis risk radar / incomplete-source isolation: PASS");
/* 入口卡的指数预览：只收已校验的当日涨跌，代理标的与降级/过期条目一律不进表；
   数据日不一致时表头必须给区间，不能只写最新那天。 */
const trackerFixture = {
  assets: [
    { name: "标普500", category: "equity", stale: false, returns: { d1: -0.02 },
      dataMeta: { mode: "market", status: "ok", source: "Yahoo Finance", asOf: "2026-08-26" } },
    { name: "日经225", category: "equity", stale: false, returns: { d1: 1.25 },
      dataMeta: { mode: "market", status: "ok", source: "Yahoo Finance", asOf: "2026-08-27" } },
    { name: "沪深300", category: "equity", stale: false, returns: { d1: -0.24 },
      proxy: { type: "etf", targetSymbol: "000300.SS" },
      dataMeta: { mode: "market", status: "ok", source: "Yahoo Finance", asOf: "2026-08-25" } },
    { name: "过期指数", category: "equity", stale: true, returns: { d1: 0.4 },
      dataMeta: { mode: "market", status: "ok", source: "Yahoo Finance", asOf: "2026-08-20" } },
    { name: "估算指数", category: "equity", stale: false, returns: { d1: 0.4 },
      dataMeta: { mode: "estimate", status: "ok", source: "Yahoo Finance", asOf: "2026-08-27" } },
    { name: "降级指数", category: "equity", stale: false, returns: { d1: 0.4 },
      dataMeta: { mode: "market", status: "partial", source: "Yahoo Finance", asOf: "2026-08-27" } },
    { name: "缺涨跌指数", category: "equity", stale: false, returns: {},
      dataMeta: { mode: "market", status: "ok", source: "Yahoo Finance", asOf: "2026-08-27" } },
    { name: "布伦特原油", category: "commodity", stale: false, returns: { d1: 0.9 },
      dataMeta: { mode: "market", status: "ok", source: "Yahoo Finance", asOf: "2026-08-27" } }
  ]
};
const indexRows = pickIndexRows(trackerFixture, 6);
assert.deepStrictEqual(indexRows.map((row) => row.name), ["标普500", "日经225"]);
assert.deepStrictEqual(pickIndexRows({ assets: [] }, 6), []);
assert.deepStrictEqual(pickIndexRows(null, 6), []);
assert.strictEqual(describeRows(indexRows).label, "Yahoo Finance · 数据日 08-26~08-27");
assert.strictEqual(describeRows([indexRows[0]]).label, "Yahoo Finance · 数据日 08-26");
assert.strictEqual(describeRows([]).ready, false);
assert.strictEqual(describeRows([]).label, "暂无可用指数");
/* 颜色之外必须有正负号，涨跌不能只靠颜色表达。 */
assert.strictEqual(formatChange(1.234), "+1.23%");
assert.strictEqual(formatChange(-1.234), "−1.23%");
assert.strictEqual(formatChange(0), "0.00%");

console.log("- rotating globe longitude projection / texture wrap contract: PASS");
console.log("- calendar-only trading sessions / lunch break / weekend / unknown zone: PASS");
console.log("- watchlist sanitization / pure toggle / stable ordering / storage degradation: PASS");
console.log("- detail drawer series geometry / literal keyword-hit labelling: PASS");
console.log("- radar six axes read real regime signals / direction / gap isolation: PASS");
console.log("- heatmap paints only regions with a representative index: PASS");
console.log("- yield curve breaks at missing tenors / log tenor axis / honest shape call: PASS");
console.log("- correlation on log returns / misaligned-calendar exclusion / thin-overlap blanking: PASS");
console.log("- gateway index preview drops proxy/stale/degraded rows and dates its own span: PASS");
