function textureX(centerLongitude, normalizedX) {
  const longitude = centerLongitude + Math.asin(Math.max(-1, Math.min(1, normalizedX))) * 180 / Math.PI;
  return (((longitude + 180) % 360) + 360) % 360 / 360;
}

export function drawEarthTexture(ctx, image, cx, cy, radius, centerLongitude) {
  if (!image?.naturalWidth) return false;
  const sourceWidth = image.naturalWidth;
  const sourceHeight = image.naturalHeight;
  const step = Math.max(2, Math.round(radius / 190));
  ctx.save();
  ctx.beginPath();
  ctx.arc(cx, cy, radius, 0, Math.PI * 2);
  ctx.clip();
  ctx.globalAlpha = .96;
  for (let offset = -radius; offset < radius; offset += step) {
    const normalized = Math.max(-.999, Math.min(.999, (offset + step / 2) / radius));
    const sourceX = Math.floor(textureX(centerLongitude, normalized) * sourceWidth);
    const span = Math.max(1, Math.round(sourceWidth * step / (4 * radius)));
    ctx.drawImage(image, Math.min(sourceWidth - span, Math.max(0, sourceX)), 0, span, sourceHeight,
      cx + offset, cy - radius, step + 1, radius * 2);
  }
  const light = ctx.createRadialGradient(cx - radius * .42, cy - radius * .4, radius * .02,
    cx, cy, radius * 1.08);
  light.addColorStop(0, "rgba(115,210,255,.22)");
  light.addColorStop(.42, "rgba(20,109,168,.06)");
  light.addColorStop(.78, "rgba(0,8,22,.24)");
  light.addColorStop(1, "rgba(0,3,12,.82)");
  ctx.fillStyle = light;
  ctx.fillRect(cx - radius, cy - radius, radius * 2, radius * 2);
  ctx.restore();
  return true;
}
