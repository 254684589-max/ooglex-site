const TILT = .34;
const SIN_TILT = Math.sin(TILT);
const COS_TILT = Math.cos(TILT);
const RAD = Math.PI / 180;
const CACHE = new WeakMap();

function wrapLongitude(value) {
  return ((value + 180) % 360 + 360) % 360 - 180;
}

function angularDistance(a, b) {
  return Math.abs(wrapLongitude(a - b));
}

function makeCanvas(ctx, width, height) {
  const canvas = ctx.canvas?.ownerDocument?.createElement?.("canvas");
  if (!canvas) return null;
  canvas.width = width;
  canvas.height = height;
  return canvas;
}

function prepareSource(ctx, image) {
  const width = Math.min(1536, image.naturalWidth);
  const height = Math.round(width / 2);
  const canvas = makeCanvas(ctx, width, height);
  const source = canvas?.getContext?.("2d", { willReadFrequently: true });
  if (!source) return null;
  source.drawImage(image, 0, 0, width, height);
  try {
    return { width, height, pixels: source.getImageData(0, 0, width, height).data };
  } catch {
    return null;
  }
}

function prepareTarget(ctx, diameter) {
  const size = Math.max(320, Math.min(700, Math.round(diameter)));
  const canvas = makeCanvas(ctx, size, size);
  const target = canvas?.getContext?.("2d");
  if (!target) return null;
  return { size, canvas, target, imageData: target.createImageData(size, size) };
}

function renderOrthographic(state, centerLongitude) {
  const { source, target } = state;
  const { width: sourceWidth, height: sourceHeight, pixels } = source;
  const { size, imageData } = target;
  const output = imageData.data;
  const half = (size - 1) / 2;

  for (let y = 0; y < size; y += 1) {
    const screenY = (y - half) / half;
    for (let x = 0; x < size; x += 1) {
      const screenX = (x - half) / half;
      const radial = screenX * screenX + screenY * screenY;
      const out = (y * size + x) * 4;
      if (radial > 1) {
        output[out + 3] = 0;
        continue;
      }

      const depth = Math.sqrt(1 - radial);
      const worldY = Math.max(-1, Math.min(1, -COS_TILT * screenY + SIN_TILT * depth));
      const worldZ = SIN_TILT * screenY + COS_TILT * depth;
      const latitude = Math.asin(worldY) / RAD;
      const longitude = wrapLongitude(centerLongitude + Math.atan2(screenX, worldZ) / RAD);
      const sourceX = Math.min(sourceWidth - 1,
        Math.max(0, Math.round((longitude + 180) / 360 * (sourceWidth - 1))));
      const sourceY = Math.min(sourceHeight - 1,
        Math.max(0, Math.round((90 - latitude) / 180 * (sourceHeight - 1))));
      const input = (sourceY * sourceWidth + sourceX) * 4;
      const edgeShade = .34 + depth * .72;
      const northLight = Math.max(0, .29 - screenY * .16) * depth;
      const luminance = pixels[input] * .27 + pixels[input + 1] * .58 + pixels[input + 2] * .15;
      const leftX = Math.max(0, sourceX - 2);
      const rightX = Math.min(sourceWidth - 1, sourceX + 2);
      const upperY = Math.max(0, sourceY - 2);
      const lowerY = Math.min(sourceHeight - 1, sourceY + 2);
      const left = (sourceY * sourceWidth + leftX) * 4;
      const right = (sourceY * sourceWidth + rightX) * 4;
      const upper = (upperY * sourceWidth + sourceX) * 4;
      const lower = (lowerY * sourceWidth + sourceX) * 4;
      const localAverage = (
        pixels[left] * .27 + pixels[left + 1] * .58 + pixels[left + 2] * .15
        + pixels[right] * .27 + pixels[right + 1] * .58 + pixels[right + 2] * .15
        + pixels[upper] * .27 + pixels[upper + 1] * .58 + pixels[upper + 2] * .15
        + pixels[lower] * .27 + pixels[lower + 1] * .58 + pixels[lower + 2] * .15
      ) / 4;
      const sparkle = Math.max(0, luminance - localAverage - 1.4) ** 1.24;
      const warmLight = Math.max(0,
        Math.min(pixels[input], pixels[input + 1]) - pixels[input + 2] * .68 - 5) ** 1.15;
      const citySparkle = sparkle * Math.min(1, warmLight / 18);
      output[out] = Math.min(255,
        pixels[input] * edgeShade * .84 + northLight * 20 + warmLight * 3.8 + citySparkle * 4.6);
      output[out + 1] = Math.min(255,
        pixels[input + 1] * edgeShade * .88 + northLight * 35 + warmLight * 3.25 + citySparkle * 4.05);
      output[out + 2] = Math.min(255,
        pixels[input + 2] * (edgeShade + .03) * .96 + northLight * 64 + warmLight * 1.15 + citySparkle * 2.15);
      output[out + 3] = 255;
    }
  }
  target.target.putImageData(imageData, 0, 0);
  state.longitude = centerLongitude;
}

export function drawEarthTexture(ctx, image, cx, cy, radius, centerLongitude) {
  if (!image?.naturalWidth) return false;
  let state = CACHE.get(ctx);
  const diameter = radius * 2;
  const desiredSize = Math.max(320, Math.min(700, Math.round(diameter)));
  if (!state || state.image !== image || state.target.size !== desiredSize) {
    const source = prepareSource(ctx, image);
    const target = prepareTarget(ctx, diameter);
    if (!source || !target) return false;
    state = { image, source, target, longitude: Number.NaN };
    CACHE.set(ctx, state);
  }
  if (!Number.isFinite(state.longitude) || angularDistance(state.longitude, centerLongitude) >= .42) {
    renderOrthographic(state, centerLongitude);
  }

  ctx.save();
  ctx.beginPath();
  ctx.arc(cx, cy, radius, 0, Math.PI * 2);
  ctx.clip();
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(state.target.canvas, cx - radius, cy - radius, diameter, diameter);

  const atmosphere = ctx.createRadialGradient(
    cx - radius * .38, cy - radius * .42, radius * .04, cx, cy, radius * 1.06
  );
  atmosphere.addColorStop(0, "rgba(118,207,255,.18)");
  atmosphere.addColorStop(.43, "rgba(29,119,190,.055)");
  atmosphere.addColorStop(.78, "rgba(0,7,20,.06)");
  atmosphere.addColorStop(1, "rgba(0,2,10,.4)");
  ctx.fillStyle = atmosphere;
  ctx.fillRect(cx - radius, cy - radius, diameter, diameter);
  ctx.restore();
  return true;
}
