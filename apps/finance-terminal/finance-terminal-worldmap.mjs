/* 全球风险热力图点阵：站内海陆遮罩生成大陆点阵，按区域代表指数当日回报着色。
   只把既有回报值映射为颜色，不产生任何新的行情事实，也不请求外部服务。 */
const MASK_URL = new URL("../tv/vendor/earth-water.jpg", import.meta.url).href;

/* 区域代表指数的地理锚点，仅用于把已有回报值定位到地图上。 */
const ANCHORS = Object.freeze({
  "north-america": [-100, 45],
  "south-america": [-58, -15],
  europe: [15, 50],
  "greater-china": [110, 33],
  japan: [138, 37],
  "south-asia": [79, 22],
  oceania: [145, -27]
});
const REACH = 46;

/* 当日回报 → 点阵配色：跌幅越深压力越高（琥珀转橙红），上涨为冷青，无数据为暗蓝。 */
export function pressureTone(value) {
  if (!Number.isFinite(value)) return [84, 126, 156, .34];
  if (value > .25) return [96, 226, 255, .8];
  if (value > -.25) return [126, 194, 226, .62];
  const heat = Math.min(1, (-value - .25) / 1.75);
  return [244 + heat * 11, 182 - heat * 62, 75 - heat * 22, .74 + heat * .26];
}

/* 找出覆盖该经纬度的区域（取最近锚点，超出 REACH 视为未覆盖）。 */
export function nearestRegion(longitude, latitude, regions) {
  let best = null;
  let bestDistance = REACH;
  regions.forEach((region) => {
    const anchor = ANCHORS[region.id];
    if (!anchor) return;
    const dx = (longitude - anchor[0]) * Math.cos((latitude + anchor[1]) / 2 * Math.PI / 180);
    const distance = Math.hypot(dx, latitude - anchor[1]);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = region;
    }
  });
  return best;
}

export function renderWorldHeatmap(canvas, regions, options = {}) {
  const doc = options.document || canvas?.ownerDocument;
  const view = options.window || globalThis.window;
  const ctx = canvas?.getContext?.("2d");
  if (!canvas || !ctx || !doc || !view) return Object.freeze({ destroy() {} });

  const rows = 118;
  const columns = 236;
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

    /* 先铺压力辉光，再画点阵，形成参考图的热区扩散感。 */
    regions.forEach((region) => {
      const anchor = ANCHORS[region.id];
      if (!anchor || !Number.isFinite(region.value) || region.value > -.25) return;
      const [r, g, b] = pressureTone(region.value);
      const cx = (anchor[0] + 180) / 360 * width;
      const cy = (TOP_LATITUDE - anchor[1]) / (TOP_LATITUDE - BOTTOM_LATITUDE) * height;
      const bloom = ctx.createRadialGradient(cx, cy, 0, cx, cy, width * .12);
      bloom.addColorStop(0, `rgba(${r | 0},${g | 0},${b | 0},.26)`);
      bloom.addColorStop(1, "rgba(0,0,0,0)");
      ctx.fillStyle = bloom;
      ctx.fillRect(0, 0, width, height);
    });

    for (let row = 0; row < rows; row += 1) {
      const latitude = rowLatitude(row);
      for (let column = 0; column < columns; column += 1) {
        if (pixels[(row * columns + column) * 4] > 118) continue;
        const longitude = (column + .5) / columns * 360 - 180;
        const region = nearestRegion(longitude, latitude, regions);
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
    const buffer = doc.createElement("canvas");
    buffer.width = columns;
    buffer.height = rows;
    const target = buffer.getContext("2d", { willReadFrequently: true });
    if (!target) return;
    const sourceTop = (90 - TOP_LATITUDE) / 180 * image.naturalHeight;
    const sourceHeight = (TOP_LATITUDE - BOTTOM_LATITUDE) / 180 * image.naturalHeight;
    target.drawImage(image, 0, sourceTop, image.naturalWidth, sourceHeight, 0, 0, columns, rows);
    try {
      paint(target.getImageData(0, 0, columns, rows).data);
    } catch { return; }
    canvas.closest(".risk-map-figure")?.classList.add("risk-map-canvas-ready");
  };
  image.src = MASK_URL;

  return Object.freeze({ destroy() { destroyed = true; } });
}
