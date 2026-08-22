/* 全息线框地球：站内海陆遮罩点阵大陆 + 倾斜经纬网 + 前后分层轨道环。
   贴图仅取同源静态图，不含任何行情数值。 */
const MASK_URL = new URL("../tv/vendor/earth-water.jpg", import.meta.url).href;
const FALLBACK_URL = new URL("../tv/vendor/earth-night.jpg", import.meta.url).href;
const INITIAL_LONGITUDE = -34;
const ROTATION_DEGREES_PER_MS = .0025;
const SIN_TILT = Math.sin(.34);
const COS_TILT = Math.cos(.34);
const RAD = Math.PI / 180;
const ORBITS = [[1.2, .3, -.36, "244,182,75"], [1.34, .19, .28, "69,212,255"], [1.09, .46, .62, "88,206,255"]];

export function textureCoordinate(centerLongitude, normalizedX) {
  const longitude = centerLongitude + Math.asin(Math.max(-1, Math.min(1, normalizedX))) * 180 / Math.PI;
  return (((longitude + 180) % 360) + 360) % 360 / 360;
}

/* 倾斜正交投影，depth>0 为朝向观察者的半球。 */
export function projectPoint(latitude, longitude, centerLongitude) {
  const phi = latitude * RAD;
  const delta = (longitude - centerLongitude) * RAD;
  const cos = Math.cos(phi);
  const y = Math.sin(phi);
  const z = cos * Math.cos(delta);
  return { x: cos * Math.sin(delta), y: -(y * COS_TILT - z * SIN_TILT), depth: y * SIN_TILT + z * COS_TILT };
}

export function initMarketGlobe(options = {}) {
  const { document = globalThis.document, window = globalThis.window } = options;
  const host = document?.getElementById("market-globe");
  const canvas = document?.getElementById("market-globe-canvas");
  const ctx = canvas?.getContext?.("2d", { alpha: true });
  if (!host || !canvas || !ctx || !window) return Object.freeze({ destroy() {} });

  const figure = host.closest(".market-orbit");
  const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const image = new window.Image();
  let animationFrame = 0, lastFrame = 0, observer = null, land = [], spun = INITIAL_LONGITUDE;
  let ready = false, destroyed = false;

  /* 遮罩一次性采样成陆地点阵，之后每帧只投影。 */
  function sampleLand() {
    const columns = 132, rows = 66;
    const buffer = document.createElement("canvas");
    buffer.width = columns;
    buffer.height = rows;
    const target = buffer.getContext("2d", { willReadFrequently: true });
    if (!target) return;
    target.drawImage(image, 0, 0, columns, rows);
    let pixels;
    try {
      pixels = target.getImageData(0, 0, columns, rows).data;
    } catch { return; }
    const points = [];
    for (let row = 1; row < rows - 1; row += 1) {
      const latitude = 90 - (row + .5) / rows * 180;
      const step = Math.max(1, Math.round(1 / Math.max(.18, Math.cos(latitude * RAD))));
      for (let column = 0; column < columns; column += step) {
        if (pixels[(row * columns + column) * 4] <= 118) points.push(latitude, (column + .5) / columns * 360 - 180);
      }
    }
    land = points;
  }

  function resize() {
    const bounds = host.getBoundingClientRect();
    const cssSize = Math.max(220, Math.round(Math.min(bounds.width || 340, bounds.height || 340)));
    const ratio = Math.min(1.6, window.devicePixelRatio || 1);
    const pixels = Math.round(cssSize * ratio);
    if (canvas.width !== pixels || canvas.height !== pixels) {
      canvas.width = pixels;
      canvas.height = pixels;
      canvas.style.width = canvas.style.height = `${cssSize}px`;
    }
    if (ready) draw(spun);
  }

  /* parallel：定纬扫经；否则定经扫纬。 */
  function trace(cx, cy, r, fixed, parallel) {
    let drawing = false;
    for (let value = 0; value <= (parallel ? 360 : 180); value += 4) {
      const point = parallel ? projectPoint(fixed, value, spun) : projectPoint(value - 90, fixed, spun);
      if (point.depth <= 0) { drawing = false; continue; }
      const px = cx + point.x * r;
      const py = cy + point.y * r;
      ctx[drawing ? "lineTo" : "moveTo"](px, py);
      drawing = true;
    }
  }

  function drawSphere(cx, cy, r) {
    ctx.strokeStyle = "rgba(88,206,255,.22)";
    ctx.lineWidth = Math.max(.6, r * .0035);
    ctx.beginPath();
    [-60, -30, 0, 30, 60].forEach((latitude) => trace(cx, cy, r, latitude, true));
    for (let longitude = -180; longitude < 180; longitude += 30) trace(cx, cy, r, longitude, false);
    ctx.stroke();

    const dot = Math.max(.9, r * .0125);
    ctx.fillStyle = "rgba(120,232,255,.92)";
    for (let index = 0; index < land.length; index += 2) {
      const point = projectPoint(land[index], land[index + 1], spun);
      if (point.depth <= .04) continue;
      ctx.globalAlpha = Math.min(.95, point.depth * 1.25);
      ctx.beginPath();
      ctx.arc(cx + point.x * r, cy + point.y * r, dot, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  /* 后半段先画、前半段后画，形成环绕关系。 */
  function drawOrbits(cx, cy, r, front) {
    ORBITS.forEach(([scale, flatten, rotation, color]) => {
      ctx.save();
      ctx.translate(cx, cy);
      ctx.rotate(rotation);
      ctx.strokeStyle = `rgba(${color},${front ? .72 : .2})`;
      ctx.lineWidth = Math.max(1, r * (front ? .006 : .004));
      if (front) {
        ctx.shadowColor = `rgba(${color},.55)`;
        ctx.shadowBlur = r * .05;
      }
      ctx.beginPath();
      ctx.ellipse(0, 0, r * scale, r * scale * flatten, 0, front ? Math.PI : 0, front ? Math.PI * 2 : Math.PI);
      ctx.stroke();
      ctx.restore();
    });
  }

  function draw(longitude) {
    if (!ready || destroyed) return;
    spun = longitude;
    const size = canvas.width;
    const cx = size / 2;
    const cy = cx;
    const r = size * .35;
    ctx.clearRect(0, 0, size, size);
    drawOrbits(cx, cy, r, false);

    const body = ctx.createRadialGradient(cx - r * .35, cy - r * .4, r * .05, cx, cy, r * 1.05);
    body.addColorStop(0, "rgba(19,71,108,.95)");
    body.addColorStop(1, "rgba(2,12,23,.98)");
    ctx.save();
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.fillStyle = body;
    ctx.fill();
    ctx.clip();
    drawSphere(cx, cy, r);
    ctx.restore();

    ctx.strokeStyle = "rgba(126,232,255,.85)";
    ctx.lineWidth = Math.max(1, r * .0075);
    ctx.shadowColor = "rgba(66,209,255,.9)";
    ctx.shadowBlur = r * .13;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.shadowBlur = 0;

    drawOrbits(cx, cy, r, true);
  }

  function stop() {
    if (animationFrame) window.cancelAnimationFrame(animationFrame);
    animationFrame = 0;
  }

  function frame(timestamp) {
    animationFrame = 0;
    if (destroyed || motion.matches || document.hidden) return;
    if (!lastFrame || timestamp - lastFrame >= 42) {
      lastFrame = timestamp;
      draw(INITIAL_LONGITUDE + timestamp * ROTATION_DEGREES_PER_MS);
    }
    animationFrame = window.requestAnimationFrame(frame);
  }

  function start() {
    stop();
    if (ready && !motion.matches && !document.hidden) animationFrame = window.requestAnimationFrame(frame);
    else if (ready) draw(INITIAL_LONGITUDE);
  }

  image.decoding = "async";
  image.onload = () => {
    if (destroyed) return;
    sampleLand();
    ready = true;
    resize();
    draw(INITIAL_LONGITUDE);
    figure?.classList.add("globe-canvas-ready");
    start();
  };
  image.onerror = () => {
    if (image.src === MASK_URL) image.src = FALLBACK_URL;
    else figure?.classList.add("globe-canvas-fallback");
  };
  image.src = MASK_URL;

  if (typeof window.ResizeObserver === "function") {
    observer = new window.ResizeObserver(resize);
    observer.observe(host);
  } else window.addEventListener("resize", resize, { passive: true });
  document.addEventListener("visibilitychange", start);
  motion.addEventListener?.("change", start);
  resize();

  return Object.freeze({
    destroy() {
      destroyed = true;
      stop();
      observer?.disconnect();
      if (!observer) window.removeEventListener("resize", resize);
      document.removeEventListener("visibilitychange", start);
      motion.removeEventListener?.("change", start);
    }
  });
}
