/** 气泡图的几何层：纯函数，不碰 DOM，不读数据文件。
 *
 * 三条硬约束，和热力图那边同源：
 * 1. **面积严格正比于市值**——半径按 √市值 取，这是这张图对「大小」唯一的量化承诺；
 * 2. **纵向位置严格是收益率**，零线画出来，不做任何压缩或对数变换；
 * 3. **横向位置不携带信息**——它只是同一行业内部的避让，因此必须是**确定性**的：
 *    同一份输入永远排出同一个位置。盘中刷新时只有 y 会动，x 原地不动，
 *    这样气泡看上去是在「上下浮动」，而不是每半小时整列重新洗牌。
 */

/* 行业列的固定次序：与行情板的公司二级分组同一套（标普/GICS 惯用次序）。
   按当天家数或涨跌排会让列的位置天天变，读者刚记住「金融在第二列」，第二天就不是了。 */
export const SECTOR_ORDER = Object.freeze([
  "科技", "金融", "工业", "医疗健康", "可选消费", "必需消费",
  "通信服务", "能源", "公用事业", "原材料", "房地产"
]);

export function isNum(value) {
  return typeof value === "number" && Number.isFinite(value);
}

/* 纵轴范围：**按分位数取，不按极值取**。
   实测这一天 495 家里 96% 落在 −6.6%~+6.5%，但有一家 +22.4%。按极值定范围会把
   这一家撑开整根轴，其余四百多家挤成一条线——图上什么也读不出来。因此取 p2~p98，
   落在范围外的少数几家**贴边显示并描一圈虚线**，同时在说明里点出有几家越界：
   贴边是「它比这里更高/更低」，虚线与说明保证它不会被读成正好在边上。

   范围一定包含 0——零线是这张图的基准，把它挤出画面会让「涨还是跌」失去参照。
   刻度取整到好读的档位（1/2/5×10ⁿ）。 */
export function quantile(sorted, q) {
  if (!sorted.length) return 0;
  const at = (sorted.length - 1) * q;
  const lo = Math.floor(at);
  const hi = Math.ceil(at);
  return lo === hi ? sorted[lo] : sorted[lo] + (sorted[hi] - sorted[lo]) * (at - lo);
}

export function niceDomain(values, pad = 0.08) {
  const nums = (values || []).filter(isNum).sort((a, b) => a - b);
  if (!nums.length) return { min: -5, max: 5, step: 5 };
  let min = Math.min(0, nums.length > 20 ? quantile(nums, 0.02) : nums[0]);
  let max = Math.max(0, nums.length > 20 ? quantile(nums, 0.98) : nums[nums.length - 1]);
  if (min === max) { min -= 1; max += 1; }
  const span = max - min;
  min -= span * pad;
  max += span * pad;
  /* 刻度取 1/2/5×10ⁿ 里能给出 4~8 条线的那一档。 */
  const raw = (max - min) / 6;
  const mag = Math.pow(10, Math.floor(Math.log10(Math.max(raw, 1e-6))));
  const step = [1, 2, 5, 10].map((m) => m * mag).filter((s) => s >= raw)[0] || 10 * mag;
  return { min: Math.floor(min / step) * step, max: Math.ceil(max / step) * step, step };
}

export function ticksFor(domain) {
  const out = [];
  for (let v = domain.min; v <= domain.max + 1e-9; v += domain.step) {
    out.push(Math.round(v * 1e6) / 1e6);
  }
  return out;
}

/* 半径：面积严格正比于市值，因此 r = k·√cap，k 是**唯一一个**比例系数——
   动它只会整体放大缩小，不会破坏「面积比 = 市值比」。

   k 怎么定：按「全部气泡的总面积占画布的多少」来定，而不是钉死最大那颗的半径。
   市值最大与最小差 823 倍，开方后半径仍差 29 倍；若把最大那颗钉在列宽上，
   中位数那家就只剩 3px，一个字也写不下。改成按总墨迹定，筛到前 60 家时气泡自然变大、
   名字与股价就写得下了，而看全部 495 家时又不会糊成一团——同一个公式两头都成立。

   仍保留两个上限：任何一颗都不许超过 maxRadius（否则会横跨自己的列），
   任何一颗都不小于 minRadius（否则等于把这家公司从图上抹掉）。 */
export const INK_FRACTION = 0.32;      // 气泡总面积占绘图区的目标比例

export function radiusScale(caps, maxRadius, minRadius = 3, plotArea = 0) {
  const nums = (caps || []).filter((c) => isNum(c) && c > 0);
  if (!nums.length) return () => minRadius;
  const top = Math.sqrt(Math.max(...nums));
  /* 上限法：最大那颗正好等于 maxRadius。 */
  let k = maxRadius / top;
  if (plotArea > 0) {
    const sum = nums.reduce((total, cap) => total + cap, 0);
    /* 总墨迹法：Σπ(k√cap)² = kπ·Σcap = 目标面积。 */
    const byInk = Math.sqrt((INK_FRACTION * plotArea) / (Math.PI * sum));
    k = Math.min(byInk, k);            // 两者取小：先保证最大那颗不溢出列
  }
  return (cap) => (isNum(cap) && cap > 0
    ? Math.max(minRadius, Math.min(maxRadius, Math.sqrt(cap) * k))
    : minRadius);
}

/* 同一行业列内的横向避让：确定性贪心。
   先按半径从大到小排，最大的占住列心（和参考图一样，大公司在中间），
   其余依次向两侧试探第一个不与已放置气泡相交的位置。
   完全放不下时贴边并允许重叠——重叠比把一家公司从图上删掉诚实。 */
export function packColumn(items, centerX, halfWidth, gap = 1) {
  const placed = [];
  const order = items.slice().sort((a, b) => b.r - a.r || String(a.key).localeCompare(String(b.key)));
  order.forEach((item) => {
    const limit = Math.max(0, halfWidth - item.r);
    const stride = Math.max(2, item.r * 0.7);
    let chosen = 0;
    for (let step = 0; step <= Math.ceil(limit / stride) + 1; step += 1) {
      const candidates = step === 0 ? [0] : [step * stride, -step * stride];
      const fit = candidates
        .map((offset) => Math.max(-limit, Math.min(limit, offset)))
        .filter((offset) => placed.every((other) => {
          const dx = (centerX + offset) - other.x;
          const dy = item.y - other.y;
          const need = item.r + other.r + gap;
          return dx * dx + dy * dy >= need * need;
        }))[0];
      if (fit !== undefined) { chosen = fit; break; }
      chosen = Math.max(-limit, Math.min(limit, (step % 2 ? 1 : -1) * step * stride));
    }
    placed.push({ ...item, x: centerX + chosen });
  });
  return placed;
}

/* 整张图的布局。返回逐行业的列与逐公司的圆，另带纵轴刻度。
   metricOf 决定纵向位置读哪一档收益（当日 / 每周 / 月度 / 年初至今），
   几何本身对读的是哪一档没有意见——换档只是换一次输入。 */
export function layoutBubbles(rows, box, options = {}) {
  /* 刻意不叫 valueOf：那是 Object.prototype 上的方法名，`options.valueOf` 对任何对象
     都为真，默认值永远轮不到——这个坑写完第一版就踩到了，改名比记住它便宜。 */
  const metricOf = options.metricOf || ((row) => row.changePct);
  const order = options.order || SECTOR_ORDER;
  const padTop = options.padTop || 14;
  const padBottom = options.padBottom || 46;   // 容得下行业名 + 家数两行
  const padLeft = options.padLeft || 46;
  const padRight = options.padRight || 12;

  const usable = (rows || []).filter((row) => row && isNum(row.marketCap) && row.marketCap > 0);
  const plotW = Math.max(40, box.w - padLeft - padRight);
  const plotH = Math.max(40, box.h - padTop - padBottom);

  const present = order.filter((name) => usable.some((row) => (row.sector || "未分类") === name));
  const extras = Array.from(new Set(usable.map((row) => row.sector || "未分类")))
    .filter((name) => !order.includes(name)).sort();
  const columns = present.concat(extras);
  if (!columns.length) return { columns: [], circles: [], domain: niceDomain([]), ticks: [], plot: null };

  const domain = options.domain || niceDomain(usable.map((row) => metricOf(row)));
  const colW = plotW / columns.length;
  /* 半径上限同时受列宽与图高约束：列很窄时不能让一颗气泡横跨整列。
     最大的那家是最小那家的八百多倍市值（√后仍有 29 倍半径差），上限放宽一点点，
     整根列就会被一颗气泡糊住——0.30/0.11 是实测下来两者都读得清的一档。 */
  const maxR = Math.max(6, Math.min(colW * 0.46, plotH * 0.17));
  const radiusOf = radiusScale(usable.map((row) => row.marketCap), maxR, 3, plotW * plotH);
  const yOf = (value) => padTop + plotH
    * (1 - (value - domain.min) / Math.max(1e-9, domain.max - domain.min));

  const circles = [];
  const columnBoxes = columns.map((name, index) => {
    const centerX = padLeft + colW * (index + 0.5);
    const members = usable.filter((row) => (row.sector || "未分类") === name);
    const items = members.map((row) => {
      const value = metricOf(row);
      /* 缺这一档收益的公司不参与纵向定位：放到零线上会被读成「没涨没跌」，
         那是伪造。它们在图上不画，改由下方的缺口说明与数据表交代。 */
      if (!isNum(value)) return { key: row.symbol, row, r: 0, y: null };
      const clamped = Math.max(domain.min, Math.min(domain.max, value));
      return {
        key: row.symbol,
        row,
        r: radiusOf(row.marketCap),
        y: yOf(clamped),
        outside: clamped !== value      // 真实值在范围外，画成贴边并描虚线
      };
    }).filter((item) => item.y !== null);
    packColumn(items, centerX, colW * 0.5 - 2).forEach((item) => circles.push({
      ...item, sector: name, value: metricOf(item.row)
    }));
    return { key: name, label: name, x: padLeft + colW * index, w: colW, centerX,
             count: members.length, drawn: items.length,
             outside: items.filter((item) => item.outside).length };
  });

  return {
    columns: columnBoxes,
    circles,
    domain,
    ticks: ticksFor(domain),
    plot: { x: padLeft, y: padTop, w: plotW, h: plotH, zeroY: yOf(0) },
    yOf
  };
}
