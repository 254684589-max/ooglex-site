/** 方块图（treemap）布局：纯函数，不碰 DOM，可离线逐条校验。
 *
 * 用的是 squarified 算法（Bruls/Huizing/van Wijk 2000）：按面积排布矩形，
 * 同时尽量把每块的长宽比压向 1。为什么不按简单的「切片」排——切片会把小市值
 * 公司压成一条几乎没有宽度的细线，读者既点不中也读不出标签。
 *
 * 面积严格正比于数值：这是方块图唯一的量化承诺，不能为了好看去改。
 * 因此本文件只做几何，配色、文字与交互都在别处，互不干扰。
 */

/* 纯函数：把一组 {key, value} 按面积铺进矩形，返回逐块的 {x, y, w, h}。
   value 必须为正；非正与非数一律先由调用方剔除，这里不替调用方猜。 */
export function squarify(items, rect) {
  const clean = (items || []).filter(
    (item) => item && Number.isFinite(item.value) && item.value > 0);
  if (!clean.length || !(rect.w > 0) || !(rect.h > 0)) return [];
  const total = clean.reduce((sum, item) => sum + item.value, 0);
  const scale = (rect.w * rect.h) / total;
  const queue = clean.slice().sort((a, b) => b.value - a.value)
    .map((item) => ({ item, area: item.value * scale }));

  const out = [];
  let box = { x: rect.x, y: rect.y, w: rect.w, h: rect.h };
  let row = [];
  while (queue.length) {
    const next = queue[0];
    const side = Math.min(box.w, box.h);
    if (!row.length || worstRatio(row.concat(next), side) <= worstRatio(row, side)) {
      row.push(queue.shift());
      continue;
    }
    box = placeRow(row, box, out);
    row = [];
  }
  if (row.length) placeRow(row, box, out);
  return out;
}

/* 一行里最差的长宽比：squarified 就是靠让这个值单调不增来决定何时换行。 */
function worstRatio(row, side) {
  if (!row.length || !(side > 0)) return Infinity;
  const sum = row.reduce((acc, entry) => acc + entry.area, 0);
  if (!(sum > 0)) return Infinity;
  const max = Math.max(...row.map((entry) => entry.area));
  const min = Math.min(...row.map((entry) => entry.area));
  const side2 = side * side;
  const sum2 = sum * sum;
  return Math.max((side2 * max) / sum2, sum2 / (side2 * min));
}

/* 把一行铺到当前矩形的短边上，并返回剩下的矩形。 */
function placeRow(row, box, out) {
  const sum = row.reduce((acc, entry) => acc + entry.area, 0);
  const vertical = box.w >= box.h;          // 短边是高 → 沿左侧竖着铺一列
  const thickness = sum / (vertical ? box.h : box.w);
  let cursor = vertical ? box.y : box.x;
  row.forEach((entry) => {
    const length = entry.area / (thickness || 1);
    out.push(vertical
      ? { item: entry.item, x: box.x, y: cursor, w: thickness, h: length }
      : { item: entry.item, x: cursor, y: box.y, w: length, h: thickness });
    cursor += length;
  });
  return vertical
    ? { x: box.x + thickness, y: box.y, w: box.w - thickness, h: box.h }
    : { x: box.x, y: box.y + thickness, w: box.w, h: box.h - thickness };
}

/* 两层布局：先按行业分块，再在每块里排公司。行业块留出标题条的高度，
   标题条不占公司的面积——否则公司之间的面积比就不再等于市值比了。 */
export function layoutSectors(sectors, rect, options = {}) {
  const headHeight = Number.isFinite(options.headHeight) ? options.headHeight : 18;
  const gap = Number.isFinite(options.gap) ? options.gap : 2;
  const blocks = squarify(
    sectors.map((sector) => ({ key: sector.key, value: sector.value, sector })), rect);
  return blocks.map((block) => {
    const inner = {
      x: block.x + gap,
      y: block.y + headHeight,
      w: Math.max(0, block.w - gap * 2),
      h: Math.max(0, block.h - headHeight - gap)
    };
    return {
      sector: block.item.sector,
      x: block.x, y: block.y, w: block.w, h: block.h,
      headHeight,
      tiles: squarify(block.item.sector.children, inner)
    };
  });
}
