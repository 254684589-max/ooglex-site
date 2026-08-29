import { drawEarthTexture } from "./finance-terminal-globe-texture.mjs";

const MASK_URL = new URL("../tv/vendor/earth-water.jpg", import.meta.url).href;
const TEX_URL = new URL("../tv/vendor/earth-night.jpg", import.meta.url);
const INITIAL_LONGITUDE = -5;
const ROTATION = .00004;
const SIN_TILT = Math.sin(.34);
const COS_TILT = Math.cos(.34);
const RAD = Math.PI / 180;

/* The network is decorative context, not a second market-data layer. Coordinates are real global
   financial hubs; the figure caption already discloses that connections are illustrative. */
const HUBS = Object.freeze([
  [40.7128, -74.006, 1], [51.5072, -.1276, 1], [50.1109, 8.6821, .72],
  [25.2048, 55.2708, .7], [19.076, 72.8777, .58], [1.3521, 103.8198, .82],
  [31.2304, 121.4737, 1], [35.6762, 139.6503, .92]
]);
const ROUTES = Object.freeze([[0, 1], [0, 2], [1, 3], [1, 6], [2, 5], [3, 6], [5, 7]]);

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

export function greatCirclePoint(start, end, amount) {
  const t = Math.max(0, Math.min(1, amount));
  const vector = ([latitude, longitude]) => {
    const phi = latitude * RAD, lambda = longitude * RAD, cos = Math.cos(phi);
    return [cos * Math.cos(lambda), cos * Math.sin(lambda), Math.sin(phi)];
  };
  const a = vector(start), b = vector(end);
  const angle = Math.acos(Math.max(-1, Math.min(1, a[0] * b[0] + a[1] * b[1] + a[2] * b[2])));
  const sine = Math.sin(angle);
  const weights = sine < 1e-7 ? [1 - t, t] : [Math.sin((1 - t) * angle) / sine, Math.sin(t * angle) / sine];
  const x = a[0] * weights[0] + b[0] * weights[1];
  const y = a[1] * weights[0] + b[1] * weights[1];
  const z = a[2] * weights[0] + b[2] * weights[1];
  return { latitude: Math.atan2(z, Math.hypot(x, y)) / RAD, longitude: Math.atan2(y, x) / RAD };
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

  function drawSpace(cx, cy, r, phase) {
    ctx.save();
    for (let index = 0; index < 86; index += 1) {
      const x = ((index * 137 + 43) % 997) / 997 * canvas.width;
      const y = ((index * 223 + 71) % 991) / 991 * canvas.height;
      if (Math.hypot(x - cx, y - cy) < r * 1.01) continue;
      const pulse = .34 + .32 * Math.sin(phase * .0016 + index * 1.71);
      const dot = Math.max(.55, r * (index % 13 === 0 ? .006 : .0028));
      ctx.globalAlpha = Math.max(.12, pulse);
      ctx.fillStyle = index % 11 === 0 ? "#b98cff" : index % 5 === 0 ? "#dff7ff" : "#68cfff";
      ctx.fillRect(x, y, dot, dot);
    }
    ctx.globalAlpha = 1;
    ctx.restore();
  }

  function drawAurora(cx, cy, r) {
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    const haze = ctx.createRadialGradient(cx + r * .08, cy - r * .94, 0, cx, cy - r * .84, r * .9);
    haze.addColorStop(0, "rgba(181,103,255,.25)");
    haze.addColorStop(.38, "rgba(75,168,255,.16)");
    haze.addColorStop(1, "rgba(30,188,255,0)");
    ctx.fillStyle = haze;
    ctx.fillRect(cx - r, cy - r * 1.36, r * 2, r * .7);

    for (let index = 0; index < 31; index += 1) {
      const unit = - .84 + index / 30 * 1.68;
      const offset = unit * r;
      const rim = cy - Math.sqrt(Math.max(0, r * r - offset * offset));
      const wave = .12 + .13 * (.5 + .5 * Math.sin(index * 1.83));
      const plume = r * wave * (1 - Math.abs(unit) * .45);
      const gradient = ctx.createLinearGradient(0, rim + 3, 0, rim - plume);
      const violet = index > 12 && index < 24;
      gradient.addColorStop(0, violet ? "rgba(155,92,255,.48)" : "rgba(73,211,255,.5)");
      gradient.addColorStop(.42, violet ? "rgba(187,112,255,.22)" : "rgba(92,218,255,.2)");
      gradient.addColorStop(1, "rgba(98,172,255,0)");
      ctx.strokeStyle = gradient;
      ctx.lineWidth = Math.max(.8, r * (.003 + (index % 5 === 0 ? .004 : 0)));
      ctx.beginPath();
      ctx.moveTo(cx + offset, rim + r * .025);
      ctx.bezierCurveTo(cx + offset - r * .015, rim - plume * .24,
        cx + offset + r * .018, rim - plume * .72, cx + offset + r * .03, rim - plume);
      ctx.stroke();
    }
    ctx.restore();
  }

  function drawOrbitStage(cx, cy, r, phase, foreground) {
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    ctx.lineWidth = Math.max(.7, r * .0032);
    ctx.strokeStyle = foreground ? "rgba(95,211,255,.38)" : "rgba(63,154,238,.2)";
    ctx.shadowColor = "rgba(73,183,255,.46)";
    ctx.shadowBlur = foreground ? r * .035 : 0;
    ctx.beginPath();
    ctx.ellipse(cx, cy + r * .08, r * 1.24, r * .29, -.08, foreground ? 0 : Math.PI, foreground ? Math.PI : Math.PI * 2);
    ctx.stroke();
    ctx.strokeStyle = foreground ? "rgba(148,109,255,.22)" : "rgba(87,87,255,.15)";
    ctx.beginPath();
    ctx.ellipse(cx, cy - r * .02, r * 1.08, r * .43, .19, foreground ? 0 : Math.PI, foreground ? Math.PI : Math.PI * 2);
    ctx.stroke();
    if (foreground) {
      const angle = phase * .00034;
      [[1.24, .29, -.08, angle], [1.08, .43, .19, angle * .73 + 2.2]].forEach(([rx, ry, rotation, value], index) => {
        const cos = Math.cos(rotation), sin = Math.sin(rotation);
        const px = Math.cos(value) * r * rx, py = Math.sin(value) * r * ry;
        const x = cx + px * cos - py * sin, y = cy + px * sin + py * cos + (index ? -r * .02 : r * .08);
        ctx.fillStyle = index ? "#bd91ff" : "#bff6ff";
        ctx.shadowColor = ctx.fillStyle;
        ctx.shadowBlur = r * .055;
        ctx.beginPath();
        ctx.arc(x, y, Math.max(1.2, r * .007), 0, Math.PI * 2);
        ctx.fill();
      });
    }
    ctx.restore();
  }

  function drawRouteLayer(cx, cy, r, foreground) {
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    ctx.lineCap = "round";
    ROUTES.forEach(([from, to], routeIndex) => {
      let drawing = false;
      const gradient = ctx.createLinearGradient(cx - r, cy, cx + r, cy);
      gradient.addColorStop(0, "rgba(83,181,255,.22)");
      gradient.addColorStop(.55, routeIndex % 3 === 0 ? "rgba(192,143,255,.82)" : "rgba(123,222,255,.75)");
      gradient.addColorStop(1, "rgba(95,174,255,.24)");
      ctx.strokeStyle = gradient;
      ctx.lineWidth = Math.max(.7, r * (foreground ? .0041 : .0026));
      ctx.shadowColor = routeIndex % 3 === 0 ? "rgba(178,109,255,.7)" : "rgba(79,205,255,.72)";
      ctx.shadowBlur = foreground ? r * .025 : 0;
      ctx.beginPath();
      for (let step = 0; step <= 40; step += 1) {
        const amount = step / 40;
        const geo = greatCirclePoint(HUBS[from], HUBS[to], amount);
        const point = projectPoint(geo.latitude, geo.longitude, spun);
        const visible = foreground ? point.depth > -.015 : point.depth <= .035;
        if (!visible) { drawing = false; continue; }
        const altitude = 1 + Math.sin(Math.PI * amount) * .105;
        const x = cx + point.x * r * altitude, y = cy + point.y * r * altitude;
        ctx[drawing ? "lineTo" : "moveTo"](x, y);
        drawing = true;
      }
      ctx.stroke();
    });
    ctx.restore();
  }

  function drawHubs(cx, cy, r) {
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    HUBS.forEach(([latitude, longitude, weight], index) => {
      const point = projectPoint(latitude, longitude, spun);
      if (point.depth <= .02) return;
      const x = cx + point.x * r, y = cy + point.y * r;
      const radius = Math.max(1.2, r * .009 * weight);
      ctx.fillStyle = index % 4 === 2 ? "#c494ff" : "#dcf9ff";
      ctx.shadowColor = index % 4 === 2 ? "#a56cff" : "#55d8ff";
      ctx.shadowBlur = r * .07;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = "rgba(109,220,255,.52)";
      ctx.lineWidth = Math.max(.6, r * .0025);
      ctx.beginPath();
      ctx.arc(x, y, radius * 2.65, 0, Math.PI * 2);
      ctx.stroke();
    });
    ctx.restore();
  }

  function drawSphere(cx, cy, r) {
    if (textureReady) drawEarthTexture(ctx, textureImage, cx, cy, r, spun);
    ctx.strokeStyle = "rgba(99,216,255,.052)";
    ctx.lineWidth = Math.max(.45, r * .0024);
    ctx.beginPath();
    [-45, 0, 45].forEach((latitude) => trace(cx, cy, r, latitude, true));
    for (let longitude = -180; longitude < 180; longitude += 45) trace(cx, cy, r, longitude, false);
    ctx.stroke();

    const dot = Math.max(.55, r * (textureReady ? .0037 : .0065));
    ctx.fillStyle = textureReady ? "rgba(145,231,255,.24)" : "rgba(154,242,255,.96)";
    for (let index = 0; index < land.length; index += 2) {
      const point = projectPoint(land[index], land[index + 1], spun);
      if (point.depth <= .04) continue;
      ctx.globalAlpha = Math.min(textureReady ? .13 : 1, point.depth * (textureReady ? .19 : 1.55));
      ctx.fillRect(cx + point.x * r - dot / 2, cy + point.y * r - dot / 2, dot, dot);
    }
    ctx.globalAlpha = 1;
  }

  function draw(longitude, phase = 0) {
    if (!ready || destroyed) return;
    spun = longitude;
    const size = canvas.width;
    const cx = size / 2;
    const cy = cx;
    const r = size * .385;
    ctx.clearRect(0, 0, size, size);

    drawSpace(cx, cy, r, phase);
    drawOrbitStage(cx, cy, r, phase, false);
    drawAurora(cx, cy, r);
    drawRouteLayer(cx, cy, r, false);

    const body = ctx.createRadialGradient(cx - r * .35, cy - r * .4, r * .05, cx, cy, r * 1.05);
    body.addColorStop(0, "rgba(30,102,150,.97)");
    body.addColorStop(1, "rgba(3,18,34,.99)");
    ctx.save();
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.fillStyle = body;
    ctx.fill();
    ctx.clip();
    drawSphere(cx, cy, r);
    ctx.restore();

    drawRouteLayer(cx, cy, r, true);
    drawHubs(cx, cy, r);
    drawOrbitStage(cx, cy, r, phase, true);

    /* 参考稿的边缘光不是均匀一圈：左上缘最亮，绕到右下逐渐熄灭。 */
    const limb = ctx.createLinearGradient(cx - r, cy - r, cx + r * .7, cy + r);
    limb.addColorStop(0, "rgba(196,246,255,.95)");
    limb.addColorStop(.32, "rgba(108,222,255,.7)");
    limb.addColorStop(.68, "rgba(58,150,220,.22)");
    limb.addColorStop(1, "rgba(30,84,150,.08)");
    ctx.strokeStyle = limb;
    ctx.lineWidth = Math.max(1.2, r * .0105);
    ctx.shadowColor = "rgba(96,214,255,.7)";
    ctx.shadowBlur = r * .1;
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.shadowBlur = 0;

    ctx.strokeStyle = "rgba(127,223,255,.18)";
    ctx.lineWidth = Math.max(.6, r * .0025);
    ctx.beginPath();
    ctx.arc(cx, cy, r * 1.025, Math.PI * 1.08, Math.PI * 1.92);
    ctx.stroke();
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
      draw(INITIAL_LONGITUDE + timestamp * ROTATION, timestamp);
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
