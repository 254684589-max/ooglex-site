const TEXTURE_URL = new URL("../tv/vendor/earth-night.jpg", import.meta.url).href;
const INITIAL_LONGITUDE = -34;
const ROTATION_DEGREES_PER_MS = .0025;

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}

export function textureCoordinate(centerLongitude, normalizedX) {
  const longitude = centerLongitude + Math.asin(clamp(normalizedX, -1, 1)) * 180 / Math.PI;
  return (((longitude + 180) % 360) + 360) % 360 / 360;
}

export function initMarketGlobe(dependencies = {}) {
  const document = dependencies.document || globalThis.document;
  const window = dependencies.window || globalThis.window;
  const host = document?.getElementById("market-globe");
  const canvas = document?.getElementById("market-globe-canvas");
  const context = canvas?.getContext?.("2d", { alpha: true });
  if (!host || !canvas || !context || !window) return Object.freeze({ destroy() {} });

  const figure = host.closest(".market-orbit");
  const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const image = new window.Image();
  let animationFrame = 0;
  let lastFrame = 0;
  let ready = false;
  let destroyed = false;
  let observer = null;

  function resize() {
    const bounds = host.getBoundingClientRect();
    const cssSize = Math.max(220, Math.round(Math.min(bounds.width || 340, bounds.height || 340)));
    const ratio = Math.min(1.6, window.devicePixelRatio || 1);
    const pixels = Math.round(cssSize * ratio);
    if (canvas.width !== pixels || canvas.height !== pixels) {
      canvas.width = pixels;
      canvas.height = pixels;
      canvas.style.width = `${cssSize}px`;
      canvas.style.height = `${cssSize}px`;
    }
    if (ready) draw(INITIAL_LONGITUDE);
  }

  function drawGraticule(cx, cy, radius) {
    context.save();
    context.strokeStyle = "rgba(101,220,255,.20)";
    context.lineWidth = Math.max(1, radius * .004);
    [-60, -30, 0, 30, 60].forEach((latitude) => {
      const radians = latitude * Math.PI / 180;
      context.beginPath();
      context.ellipse(cx, cy - Math.sin(radians) * radius,
        Math.cos(radians) * radius, Math.max(1, Math.cos(radians) * radius * .12), 0, 0, Math.PI * 2);
      context.stroke();
    });
    [.34, .68].forEach((scale) => {
      context.beginPath();
      context.ellipse(cx, cy, radius * scale, radius, 0, 0, Math.PI * 2);
      context.stroke();
    });
    context.restore();
  }

  function draw(longitude) {
    if (!ready || destroyed) return;
    const size = canvas.width;
    const cx = size / 2;
    const cy = size / 2;
    const radius = size * .445;
    const strip = Math.max(1, Math.round(size / 320));
    context.clearRect(0, 0, size, size);
    context.save();
    context.shadowColor = "rgba(54,203,255,.76)";
    context.shadowBlur = radius * .12;
    context.fillStyle = "#031323";
    context.beginPath();
    context.arc(cx, cy, radius, 0, Math.PI * 2);
    context.fill();
    context.clip();
    context.shadowBlur = 0;
    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = "high";

    for (let offset = -radius; offset < radius; offset += strip) {
      const normalized = clamp((offset + strip / 2) / radius, -1, 1);
      const vertical = Math.sqrt(Math.max(0, 1 - normalized * normalized));
      const sourceX = textureCoordinate(longitude, normalized) * image.naturalWidth;
      const sourceWidth = Math.max(1, image.naturalWidth / (radius * 4) * strip);
      const targetHeight = radius * 2 * vertical;
      context.drawImage(image, sourceX, 0,
        Math.min(sourceWidth, image.naturalWidth - sourceX), image.naturalHeight,
        cx + offset, cy - targetHeight / 2, strip + 1, targetHeight);
    }

    const daylight = context.createRadialGradient(cx - radius * .38, cy - radius * .42, 0,
      cx + radius * .08, cy + radius * .05, radius * 1.18);
    daylight.addColorStop(0, "rgba(135,232,255,.34)");
    daylight.addColorStop(.35, "rgba(30,156,220,.08)");
    daylight.addColorStop(.72, "rgba(0,12,29,.18)");
    daylight.addColorStop(1, "rgba(0,3,12,.9)");
    context.fillStyle = daylight;
    context.fillRect(cx - radius, cy - radius, radius * 2, radius * 2);
    drawGraticule(cx, cy, radius);
    context.restore();

    context.save();
    context.strokeStyle = "rgba(113,226,255,.8)";
    context.lineWidth = Math.max(1.4, radius * .006);
    context.shadowColor = "rgba(66,209,255,.92)";
    context.shadowBlur = radius * .08;
    context.beginPath();
    context.arc(cx, cy, radius, 0, Math.PI * 2);
    context.stroke();
    context.strokeStyle = "rgba(69,212,255,.2)";
    context.lineWidth = Math.max(4, radius * .035);
    context.beginPath();
    context.arc(cx, cy, radius * 1.025, 0, Math.PI * 2);
    context.stroke();
    context.restore();
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

  function handleVisibility() { start(); }
  function handleMotion() { start(); }

  image.decoding = "async";
  image.onload = () => {
    if (destroyed) return;
    ready = true;
    resize();
    draw(INITIAL_LONGITUDE);
    figure?.classList.add("globe-canvas-ready");
    start();
  };
  image.onerror = () => figure?.classList.add("globe-canvas-fallback");
  image.src = TEXTURE_URL;

  if (typeof window.ResizeObserver === "function") {
    observer = new window.ResizeObserver(resize);
    observer.observe(host);
  } else window.addEventListener("resize", resize, { passive: true });
  document.addEventListener("visibilitychange", handleVisibility);
  motion.addEventListener?.("change", handleMotion);
  resize();

  return Object.freeze({
    destroy() {
      destroyed = true;
      stop();
      observer?.disconnect();
      if (!observer) window.removeEventListener("resize", resize);
      document.removeEventListener("visibilitychange", handleVisibility);
      motion.removeEventListener?.("change", handleMotion);
    }
  });
}
