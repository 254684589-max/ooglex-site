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
  const width = Math.min(1024, image.naturalWidth);
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
  const size = Math.max(280, Math.min(520, Math.round(diameter)));
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
      const edgeShade = .45 + depth * .55;
      const northLight = Math.max(0, .18 - screenY * .09);
      output[out] = Math.min(255, pixels[input] * edgeShade + northLight * 8);
      output[out + 1] = Math.min(255, pixels[input + 1] * edgeShade + northLight * 18);
      output[out + 2] = Math.min(255, pixels[input + 2] * (edgeShade + .06) + northLight * 34);
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
  const desiredSize = Math.max(280, Math.min(520, Math.round(diameter)));
  if (!state || state.image !== image || state.target.size !== desiredSize) {
    const source = prepareSource(ctx, image);
    const target = prepareTarget(ctx, diameter);
    if (!source || !target) return false;
    state = { image, source, target, longitude: Number.NaN };
    CACHE.set(ctx, state);
  }
  if (!Number.isFinite(state.longitude) || angularDistance(state.longitude, centerLongitude) >= .32) {
    renderOrthographic(state, centerLongitude);
  }

  ctx.save();
  ctx.beginPath();
  ctx.arc(cx, cy, radius, 0, Math.PI * 2);
  ctx.clip();
  ctx.drawImage(state.target.canvas, cx - radius, cy - radius, diameter, diameter);

  const atmosphere = ctx.createRadialGradient(
    cx - radius * .38, cy - radius * .42, radius * .04, cx, cy, radius * 1.06
  );
  atmosphere.addColorStop(0, "rgba(80,177,238,.11)");
  atmosphere.addColorStop(.46, "rgba(15,89,151,.035)");
  atmosphere.addColorStop(.78, "rgba(0,7,20,.16)");
  atmosphere.addColorStop(1, "rgba(0,2,10,.7)");
  ctx.fillStyle = atmosphere;
  ctx.fillRect(cx - radius, cy - radius, diameter, diameter);
  ctx.restore();
  return true;
}
