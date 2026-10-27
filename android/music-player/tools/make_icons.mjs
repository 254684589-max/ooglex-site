// 从 apps/music-player/icons/icon.svg（下载页上的那枚图标）生成安卓桌面图标 PNG。
// 用法（仓库根目录）：node android/music-player/tools/make_icons.mjs
// 需要 Playwright 的 Chromium（本地或 CI 已装即可，不是应用依赖）。图标 SVG 改了就重跑，把生成的 PNG 一起提交。
//
// 生成三类：
//   ic_launcher.png             传统图标（Android 5.1–7.1），圆角方块原样
//   ic_launcher_round.png       圆形图标
//   ic_launcher_background.png  自适应图标背景层（Android 8+），只有渐变底
//   ic_launcher_foreground.png  自适应图标前景层：光晕、音符、光弧
// 自适应图标的画布是 108dp，系统只露出中间 72dp，所以原图 512 方块整体缩放到中间 72dp。
import { readFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..", "..");
const res = join(here, "..", "app", "src", "main", "res");
const svg = readFileSync(join(repo, "apps", "music-player", "icons", "icon.svg"), "utf8");

const defs = svg.match(/<defs>[\s\S]*?<\/defs>/)[0];
const bgRect = svg.match(/<rect width="512" height="512"[^>]*\/>/)[0];
// 图标正文：圆角底和描边框之后的全部元素（光晕、音符、光弧）
const art = svg.slice(svg.lastIndexOf("stroke-width=\"4\"/>") + "stroke-width=\"4\"/>".length, svg.lastIndexOf("</svg>"));
const square = bgRect.replace(/ rx="\d+"/, "");
const fit = `translate(${(512 * 18) / 108} ${(512 * 18) / 108}) scale(${72 / 108})`;
const wrap = (body) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">${defs}${body}</svg>`;

const variants = {
  ic_launcher: { dp: 48, svg: svg },
  ic_launcher_round: {
    dp: 48,
    svg: wrap(`<clipPath id="c"><circle cx="256" cy="256" r="256"/></clipPath><g clip-path="url(#c)">${square}${art}</g>`),
  },
  // 外圈 18dp 只在视差动画时露出，用渐变的中间色铺满
  ic_launcher_background: { dp: 108, svg: wrap(`<rect width="512" height="512" fill="#1a1442"/><g transform="${fit}">${square}</g>`) },
  ic_launcher_foreground: { dp: 108, svg: wrap(`<g transform="${fit}">${art}</g>`) },
};
const densities = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };

const browser = await chromium.launch();
const page = await browser.newPage();
for (const [name, v] of Object.entries(variants)) {
  for (const [density, scale] of Object.entries(densities)) {
    const px = Math.round(v.dp * scale);
    await page.setViewportSize({ width: px, height: px });
    await page.setContent(`<html><body style="margin:0;background:transparent">${v.svg.replace('width="512" height="512"', `width="${px}" height="${px}"`)}</body></html>`);
    const dir = join(res, `mipmap-${density}`);
    mkdirSync(dir, { recursive: true });
    await page.screenshot({ path: join(dir, `${name}.png`), omitBackground: true, clip: { x: 0, y: 0, width: px, height: px } });
  }
}
await browser.close();
console.log("icons written to", res);
