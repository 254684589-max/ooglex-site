import { drawEarthTexture } from "./finance-terminal-globe-texture.mjs";

const MASK_URL = new URL("../tv/vendor/earth-water.jpg", import.meta.url).href;
const TEX_URL = new URL("../tv/vendor/earth-night.jpg", import.meta.url);
const INITIAL_LONGITUDE = -15;
const ROTATION = .00004;
const SIN_TILT = Math.sin(.34);
const COS_TILT = Math.cos(.34);
const RAD = Math.PI / 180;

export function textureCoordinate(centerLongitude, normalizedX) {
  const longitude = centerLongitude + Math.asin(Math.max(-1, Math.min(1, normalizedX))) * 180 / Math.PI;
  return (((longitude + 180) % 360) + 360) % 360 / 360;
}

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
  const maskImage = new window.Image();
  const textureImage = new window.Image();
  let animationFrame = 0, lastFrame = 0, observer = null, land = [], spun = INITIAL_LONGITUDE;
  let ready = false, textureReady = false, destroyed = false;

  function sampleLand() {
    const columns = 208, rows = 104;
    const buffer = document.createElement("canvas");
    buffer.width = columns;
    buffer.height = rows;
    const target = buffer.getContext("2d", { willReadFrequently: true });
    if (!target) return;
    target.drawImage(maskImage, 0, 0, columns, rows);
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
    if (textureReady) drawEarthTexture(ctx, textureImage, cx, cy, r, spun);
    ctx.strokeStyle = "rgba(99,216,255,.12)";
    ctx.lineWidth = Math.max(.6, r * .0035);
    ctx.beginPath();
    [-60, -30, 0, 30, 60].forEach((latitude) => trace(cx, cy, r, latitude, true));
    for (let longitude = -180; longitude < 180; longitude += 30) trace(cx, cy, r, longitude, false);
    ctx.stroke();

    if (!textureReady) {
      const dot = Math.max(.8, r * .0065);
      ctx.fillStyle = "rgba(154,242,255,.96)";
      for (let index = 0; index < land.length; index += 2) {
        const point = projectPoint(land[index], land[index + 1], spun);
        if (point.depth <= .04) continue;
        ctx.globalAlpha = Math.min(1, point.depth * 1.55);
        ctx.fillRect(cx + point.x * r - dot / 2, cy + point.y * r - dot / 2, dot, dot);
      }
      ctx.globalAlpha = 1;
    }
  }

  function drawConnections(cx, cy, r) {
    const links = [
      [-.82, -.06, -.34, -.54, .02, -.34],
      [-.8, -.05, -.08, -.55, .72, -.05],
      [-.08, -.36, .34, -.44, .78, .17],
      [-.76, -.02, .12, -.29, .82, .2]
    ];
    ctx.save();
    ctx.beginPath();
    ctx.arc(cx, cy, r * .995, 0, Math.PI * 2);
    ctx.clip();
    ctx.lineWidth = Math.max(.8, r * .0042);
    ctx.strokeStyle = "rgba(116,190,255,.82)";
    ctx.shadowColor = "rgba(85,174,255,.82)";
    ctx.shadowBlur = r * .026;
    links.forEach(([x1, y1, qx, qy, x2, y2], index) => {
      ctx.globalAlpha = index === 3 ? .54 : .82;
      ctx.beginPath();
      ctx.moveTo(cx + x1 * r, cy + y1 * r);
      ctx.quadraticCurveTo(cx + qx * r, cy + qy * r, cx + x2 * r, cy + y2 * r);
      ctx.stroke();
    });
    ctx.restore();
    ctx.globalAlpha = 1;
  }

  function draw(longitude) {
    if (!ready || destroyed) return;
    spun = longitude;
    const size = canvas.width;
    const cx = size / 2;
    const cy = cx;
    const r = size * .385;
    ctx.clearRect(0, 0, size, size);

    const body = ctx.createRadialGradient(cx - r * .35, cy - r * .4, r * .05, cx, cy, r * 1.05);
    body.addColorStop(0, "rgba(19,72,116,.97)");
    body.addColorStop(1, "rgba(3,18,34,.99)");
    ctx.save();
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.fillStyle = body;
    ctx.fill();
    ctx.clip();
    drawSphere(cx, cy, r);
    ctx.restore();
    drawConnections(cx, cy, r);

    ctx.strokeStyle = "rgba(126,220,255,.72)";
    ctx.lineWidth = Math.max(1, r * .0062);
    ctx.shadowColor = "rgba(66,190,255,.82)";
    ctx.shadowBlur = r * .105;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.shadowBlur = 0;

  }

  function stop() {
    if (animationFrame) window.cancelAnimationFrame(animationFrame);
    animationFrame = 0;
  }

  function frame(timestamp) {
    animationFrame = 0;
    if (destroyed || motion.matches || document.hidden) return;
    if (!lastFrame || timestamp - lastFrame >= 220) {
      lastFrame = timestamp;
      draw(INITIAL_LONGITUDE + timestamp * ROTATION);
    }
    animationFrame = window.requestAnimationFrame(frame);
  }

  function start() {
    stop();
    if (ready && !motion.matches && !document.hidden) animationFrame = window.requestAnimationFrame(frame);
    else if (ready) draw(INITIAL_LONGITUDE);
  }

  function activate() {
    if (destroyed || ready) return;
    ready = true;
    resize();
    draw(INITIAL_LONGITUDE);
    figure?.classList.add("globe-canvas-ready");
    start();
  }

  maskImage.onload = () => {
    if (destroyed) return;
    sampleLand();
    if (ready) draw(spun);
    else activate();
  };
  maskImage.onerror = activate;
  textureImage.onload = () => {
    if (destroyed) return;
    textureReady = true;
    if (ready) draw(spun);
    else activate();
  };
  textureImage.onerror = activate;
  maskImage.src = MASK_URL;
  textureImage.src = TEX_URL;

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
