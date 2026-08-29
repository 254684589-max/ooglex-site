/** 热力图的数据层：纯函数，不碰 DOM。
 *
 * 只做三件事：把成分股按行业归并、把当日涨跌映射到色阶、把数字格式化。
 * 面积由 heatmap-layout.mjs 单独负责——几何与配色分开，改一个不会带坏另一个。
 */

/* 发散色阶。两条分支各自由站内既有的涨跌色出发，按 OKLCH 保持同一色相、
   亮度单调、步距可见地生成，并逐档校验过与面板底色的对比度；中点是中性灰，
   读作「基本没动」。每档另带 ink：瓦片上的字用浅色还是深色由这一档决定，
   最差一档也有 4.45:1，不会出现「颜色好看但字看不清」。 */
export const SCALE = Object.freeze([
  { key: "down3", max: -3, color: "#cb4052", ink: "light", label: "跌超3%" },
  { key: "down2", max: -1, color: "#d37176", ink: "dark", label: "跌1–3%" },
  { key: "down1", max: -0.1, color: "#d4999a", ink: "dark", label: "跌1%内" },
  { key: "flat", max: 0.1, color: "#484f4b", ink: "light", label: "基本持平" },
  { key: "up1", max: 1, color: "#87b89d", ink: "dark", label: "涨1%内" },
  { key: "up2", max: 3, color: "#48a77b", ink: "dark", label: "涨1–3%" },
  { key: "up3", max: Infinity, color: "#009457", ink: "dark", label: "涨超3%" }
]);

/* 缺当日涨跌的公司不上色：留空比涂成「持平」诚实——没取到不等于没变化。 */
export const NO_CHANGE = Object.freeze({
  key: "unknown", color: "#1b2330", ink: "light", label: "当日涨跌缺失"
});

/* 档位边界按「看的是哪一档区间」缩放。

   色阶的 ±0.1/±1/±3 是给**当日**涨跌定的。同一套边界拿去看年初至今，几乎每一家都
   越过 +3%，整张图会全绿——颜色不再区分任何东西，等于白占一个通道。因此每一档区间
   自带一个倍数，边界随之放大，图例也按放大后的真实数字重写。

   倍数不是拍脑袋：按各档区间大致的波动幅度取整（周约 2 倍日、月约 4 倍、
   年初至今约 10 倍），够让分布铺开在七档上，又不必每天重算一遍而让颜色含义天天变。 */
export const BAND_SCALE = Object.freeze({ d1: 1, w1: 2, m1: 4, ytd: 10 });

export function stepFor(changePct, factor = 1) {
  if (!Number.isFinite(changePct)) return NO_CHANGE;
  const k = Number.isFinite(factor) && factor > 0 ? factor : 1;
  return SCALE.filter((step) => changePct < step.max * k)[0] || SCALE[SCALE.length - 1];
}

/* 图例文字：按当前倍数写出这一档的真实边界，而不是永远印着「跌超3%」。 */
export function bandLabel(step, factor = 1) {
  const k = Number.isFinite(factor) && factor > 0 ? factor : 1;
  if (k === 1) return step.label;
  const edges = SCALE.map((entry) => entry.max * k);
  const index = SCALE.indexOf(step);
  const round = (value) => (Math.abs(value) >= 10 ? Math.round(value) : Number(value.toFixed(1)));
  /* 最外两档是开区间：下界用它自己的边，不是相邻那一档的。 */
  if (index === 0) return `跌超${round(Math.abs(edges[0]))}%`;
  if (index === SCALE.length - 1) return `涨超${round(edges[SCALE.length - 2])}%`;
  if (step.key === "flat") return "基本持平";
  if (index < 3) return `跌${round(Math.abs(edges[index]))}–${round(Math.abs(edges[index - 1]))}%`;
  return `涨${round(edges[index - 1])}–${round(edges[index])}%`;
}

/* 上游的 marketCap 单位是「十亿美元」，中文里没有这个量级词：
   一万亿以上写「万亿」，以下写「亿」（1 十亿 = 10 亿）。直接把数字后面缀个
   「十亿美元」既不是中文习惯，也容易被读成「十·亿」。 */
export function formatCap(billions) {
  if (!Number.isFinite(billions)) return "—";
  if (billions >= 1000) return `${(billions / 1000).toFixed(2)}万亿美元`;
  return `${Math.round(billions * 10).toLocaleString("en-US")}亿美元`;
}

export function formatPct(value) {
  if (!Number.isFinite(value)) return "—";
  const arrow = value > 0 ? "▲" : (value < 0 ? "▼" : "—");
  return `${arrow}${Math.abs(value).toFixed(2)}%`;
}

/* 按行业归并。行业块的面积用成分股市值之和，块内再按各自市值排布。
   行业的「当日涨跌」按市值加权——把大小公司等权平均会让一家小公司的暴涨
   看起来像整个行业在涨。缺涨跌的公司不参与加权，但仍计入面积。 */
export function groupBySector(members, limit) {
  const rows = (members || [])
    .filter((row) => row && Number.isFinite(row.marketCap) && row.marketCap > 0)
    .sort((a, b) => b.marketCap - a.marketCap);
  const shown = limit && limit > 0 ? rows.slice(0, limit) : rows;
  const buckets = new Map();
  shown.forEach((row) => {
    const key = row.sector || "未分类";
    if (!buckets.has(key)) buckets.set(key, []);
    buckets.get(key).push(row);
  });
  return Array.from(buckets.entries())
    .map(([key, children]) => {
      const value = children.reduce((sum, row) => sum + row.marketCap, 0);
      const weighted = children.filter((row) => Number.isFinite(row.changePct));
      const weightSum = weighted.reduce((sum, row) => sum + row.marketCap, 0);
      return {
        key,
        label: key,
        value,
        count: children.length,
        changePct: weightSum > 0
          ? weighted.reduce((sum, row) => sum + row.changePct * row.marketCap, 0) / weightSum
          : null,
        children: children.map((row) => ({ key: row.symbol, value: row.marketCap, row }))
      };
    })
    .sort((a, b) => b.value - a.value);
}

/* 顶部读数：覆盖家数、总市值、涨跌家数。都由传进来的行现场算，不另存一份。 */
export function summarize(members) {
  const rows = (members || []).filter((row) => row && Number.isFinite(row.marketCap));
  const withChange = rows.filter((row) => Number.isFinite(row.changePct));
  return {
    count: rows.length,
    totalCap: rows.reduce((sum, row) => sum + row.marketCap, 0),
    up: withChange.filter((row) => row.changePct > 0).length,
    down: withChange.filter((row) => row.changePct < 0).length,
    flat: withChange.filter((row) => row.changePct === 0).length,
    unknown: rows.length - withChange.length
  };
}
