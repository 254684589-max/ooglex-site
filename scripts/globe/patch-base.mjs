#!/usr/bin/env node
/**
 * 把上游写死的根路径改写为部署基址，使产物能挂在站点子路径下。
 *
 * 上游（gods-eye-view）假定应用位于站点根目录，源码里有三类写死 `/` 开头的路径：
 *   1) public/ 根级静态文件（logo.svg / pin.svg / mic.svg ...），JS 与 HTML 模板都有引用
 *   2) /models/*.glb 飞机模型；这些字符串同时用作查表键（src/data/modelVisualAnchor.js），
 *      必须全局一致替换，否则模型锚点匹配不上
 *   3) /api/* 接口；静态部署下必然 404，前缀化只为把请求限制在应用自己的子树内，
 *      不污染站点根，也便于将来在同一子树接入真实后端
 *
 * 刻意不改入口 index.html：其中的 /src/main.js 与 /style.css 由 Vite 按 base 自行重写，
 * 手工替换会破坏构建。
 *
 * 用法：node patch-base.mjs <上游检出目录> <部署基址，如 /apps/globe/app/>
 */
import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const [srcDir, base] = process.argv.slice(2);
if (!srcDir || !base) {
  console.error('用法: node patch-base.mjs <上游目录> <基址(以 / 开头和结尾)>');
  process.exit(2);
}
if (!base.startsWith('/') || !base.endsWith('/')) {
  console.error(`基址必须以 / 开头和结尾，收到: ${base}`);
  process.exit(2);
}

/** 递归收集指定后缀的文件。 */
function collect(dir, exts, out = []) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) collect(p, exts, out);
    else if (exts.some((x) => e.name.endsWith(x))) out.push(p);
  }
  return out;
}

const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// 资产清单从 public/ 实际内容推导，上游新增文件时不会漏
const publicAssets = readdirSync(join(srcDir, 'public'), { withFileTypes: true })
  .filter((e) => e.isFile())
  .map((e) => e.name)
  .sort();

// 需要前缀化的根路径前缀：public 根级文件、模型目录、接口前缀
const targets = [...publicAssets.map((a) => `/${a}`), '/models/', '/api/'];

// 只在「引号或 = 后紧跟目标路径」时替换，避免误伤注释、正则和普通文本
const pattern = new RegExp(
  `(['"\`]|=")(${targets.map(escape).join('|')})`,
  'g',
);
const rewrite = (text) =>
  text.replace(pattern, (_m, lead, path) => `${lead}${base}${path.slice(1)}`);

const files = [
  ...collect(join(srcDir, 'src'), ['.js', '.html']),
  ...collect(join(srcDir, 'build'), ['.js']),
];

let changed = 0;
const byExt = { '.js': 0, '.html': 0 };
for (const f of files) {
  const before = readFileSync(f, 'utf8');
  const after = rewrite(before);
  if (after === before) continue;
  writeFileSync(f, after);
  changed += 1;
  byExt[f.endsWith('.html') ? '.html' : '.js'] += 1;
}
console.log(
  `[patch-base] 基址 ${base}｜资产 ${publicAssets.length} 个｜` +
    `改写 ${changed} 个文件（JS ${byExt['.js']}，HTML ${byExt['.html']}）`,
);

// 自检：src/ 与 build/ 下不应再有写死根路径的引用
const leftover = [];
for (const f of files) {
  const text = readFileSync(f, 'utf8');
  for (const [i, line] of text.split('\n').entries()) {
    if (pattern.test(line)) leftover.push(`${relative(srcDir, f)}:${i + 1}: ${line.trim().slice(0, 120)}`);
    pattern.lastIndex = 0;
  }
}
if (leftover.length) {
  console.error('[patch-base] 仍存在写死的根路径，产物会 404。上游可能新增了路径写法：');
  for (const l of leftover.slice(0, 10)) console.error('  ' + l);
  process.exit(1);
}
console.log('[patch-base] 自检通过：源码内已无写死根路径');
