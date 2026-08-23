/* 全球风险热力图点阵：站内海陆遮罩生成大陆点阵，按区域代表指数当日回报着色。
   只把既有回报值映射为颜色，不产生任何新的行情事实，也不请求外部服务。 */
const MASK_URL = new URL("../tv/vendor/earth-water.jpg", import.meta.url).href;

/* 各区域代表指数覆盖的经纬度范围 [西,南,东,北]。此前是单一锚点加 46 度圆半径，
   欧洲的圆盖到尼日利亚与埃及，等于替没有数据的地区断言市场状态。 */
const BOUNDS = Object.freeze({
  "north-america": [-168, 15, -52, 72],
  "south-america": [-82, -56, -34, 13],
  europe: [-11, 35, 28, 71],
  "greater-china": [73, 18, 123, 54],
  japan: [129, 30, 146, 46],
  "south-asia": [68, 6, 90, 36],
  oceania: [112, -48, 179, -10]
});

/* 当日回报 → 点阵配色：跌幅越深压力越高（琥珀转橙红），上涨为冷青，无数据为暗蓝。 */
export function pressureTone(value) {
  if (!Number.isFinite(value)) return [84, 126, 156, .34];
  if (value > .25) return [96, 226, 255, .8];
  if (value > -.25) return [126, 194, 226, .62];
  const heat = Math.min(1, (-value - .25) / 1.75);
  return [244 + heat * 11, 182 - heat * 62, 75 - heat * 22, .74 + heat * .26];
}

/* 都不含则返回 null——没有代表指数的地区宁可留白，不借邻近数值。
   两框重叠处（喜马拉雅一带）取面积更小者。 */
export function regionAt(longitude, latitude, regions) {
  let best = null;
  let bestArea = Infinity;
  regions.forEach((region) => {
    const b = BOUNDS[region.id];
    if (!b || longitude < b[0] || longitude > b[2] || latitude < b[1] || latitude > b[3]) return;
    const area = (b[2] - b[0]) * (b[3] - b[1]);
    if (area < bestArea) { bestArea = area; best = region; }
  });
  return best;
}

export function renderWorldHeatmap(canvas, regions, options = {}) {
  const doc = options.document || canvas?.ownerDocument;
  const view = options.window || globalThis.window;
  const ctx = canvas?.getContext?.("2d");
  if (!canvas || !ctx || !doc || !view) return Object.freeze({ destroy() {} });

  let rows = 118;
  let columns = 236;
  /* 裁掉南极空白带，只保留有陆地与代表指数的纬度区间。 */
  const TOP_LATITUDE = 84;
  const BOTTOM_LATITUDE = -58;
  const image = new view.Image();
  let destroyed = false;

  function rowLatitude(row) {
    return TOP_LATITUDE - (row + .5) / rows * (TOP_LATITUDE - BOTTOM_LATITUDE);
  }

  function paint(pixels) {
    const width = canvas.width;
    const height = canvas.height;
    const stepX = width / columns;
    const stepY = height / rows;
    const dot = Math.max(.85, Math.min(stepX, stepY) * .34);
    ctx.clearRect(0, 0, width, height);

    /* 不铺热区辉光：那会把 -0.3% 这种寻常波动放大成一片橙色。 */

    for (let row = 0; row < rows; row += 1) {
      const latitude = rowLatitude(row);
      for (let column = 0; column < columns; column += 1) {
        if (pixels[(row * columns + column) * 4] > 118) continue;
        const longitude = (column + .5) / columns * 360 - 180;
        const region = regionAt(longitude, latitude, regions);
        const [r, g, b, alpha] = pressureTone(region ? region.value : NaN);
        ctx.fillStyle = `rgba(${r | 0},${g | 0},${b | 0},${alpha})`;
        ctx.beginPath();
        ctx.arc((column + .5) * stepX, (row + .5) * stepY, dot, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }

  image.decoding = "async";
  image.onload = () => {
    if (destroyed) return;
    /* 背衬按实际显示尺寸乘设备像素比设定，避免被 CSS 拉伸压扁点阵。
       canvas 在 ready 前是 display:none 量不到，故先显形再量，失败则撤回。 */
    const figure = canvas.closest(".risk-map-figure");
    figure?.classList.add("risk-map-canvas-ready");
    const box = canvas.getBoundingClientRect();
    const ratio = Math.min(view.devicePixelRatio || 1, 2);
    if (box.width > 1 && box.height > 1) {
      canvas.width = Math.round(box.width * ratio);
      canvas.height = Math.round(box.height * ratio);
      columns = Math.max(200, Math.round(canvas.width / (4.4 * ratio)));
      rows = Math.max(90, Math.round(canvas.height / (4.4 * ratio)));
    }
    const buffer = doc.createElement("canvas");
    buffer.width = columns;
    buffer.height = rows;
    const target = buffer.getContext("2d", { willReadFrequently: true });
    if (!target) { figure?.classList.remove("risk-map-canvas-ready"); return; }
    const sourceTop = (90 - TOP_LATITUDE) / 180 * image.naturalHeight;
    const sourceHeight = (TOP_LATITUDE - BOTTOM_LATITUDE) / 180 * image.naturalHeight;
    target.drawImage(image, 0, sourceTop, image.naturalWidth, sourceHeight, 0, 0, columns, rows);
    try {
      paint(target.getImageData(0, 0, columns, rows).data);
    } catch { figure?.classList.remove("risk-map-canvas-ready"); }
  };
  image.src = MASK_URL;

  return Object.freeze({ destroy() { destroyed = true; } });
}
