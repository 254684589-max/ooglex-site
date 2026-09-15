export function patchBundle(input) {
  let code = input;
  function once(code, pattern, replacement, label) {
    const matches = [...code.matchAll(new RegExp(pattern.source, 'g'))];
    if (matches.length !== 1) throw new Error(label + ': expected one upstream anchor, got ' + matches.length);
    return code.replace(pattern, replacement);
  }
  if (!code.includes('window.OoglexGlobeNetwork.registry(')) {
  code = once(code, /return\{defaultId:[\s\S]*?sources:[\s\S]*?\}\)\}\}/,
    (match) => 'return window.OoglexGlobeNetwork.registry(' + match.slice(6, -1) + ')}', 'map registry');
  code = once(code, /initialStack:(\w+)\?"photoreal":"esri-imagery"/,
    'initialStack:$1?"photoreal":"local-earth"', 'initial map');
  code = once(code, /\.setStack\((\w+)\?"photoreal":"esri-imagery",/,
    '.setStack($1?"photoreal":"local-earth",', 'startup map');
  // Existing ordered UI list and the data-layer globe-regime allowlist.
  const lists = code.match(/"esri-imagery","osm"\]/g) || [];
  if (lists.length !== 2) throw new Error('Map allowlists changed upstream');
  code = code.replaceAll('"esri-imagery","osm"]', '"esri-imagery","osm","local-earth"]');
  code = once(code, /(\w+)\.start\(\)\.catch\((\w+)=>\{console\.error\("God's Eye View initialization failed:"/,
    'window.OoglexGlobeNetwork.start($1).catch($2=>{console.error("God\'s Eye View initialization failed:"',
    'application ready bridge');
  }
  if (!code.includes('window.OoglexGlobeNetwork.initialView(')) {
    code = once(code,
      /function (\w+)\((\w+)\)\{\2\.camera\.setView\(\{destination:Cesium\.Cartesian3\.fromDegrees\(-97\.7431,30\.2672,25e3\)[\s\S]*?return\(\)=>\{clearTimeout\(\w+\),\2\.isDestroyed\(\)\|\|\2\.camera\.cancelFlight\(\)\}\}/,
      'function $1($2){return window.OoglexGlobeNetwork.initialView($2)}', 'default overview camera');
  }
  return code;
}
export function patchHtml(input, base) {
  let html = input.replace(/\s*<link\b[^>]*href="https:\/\/fonts\.(?:googleapis|gstatic)\.com[^"]*"[^>]*>/g, '');
  if (/fonts\.(googleapis|gstatic)\.com/.test(html)) throw new Error('External Google font dependency remains');
  if (!html.includes('network-policy.js')) {
    const anchor = /<script src="[^"]*cesium\/Cesium\.js"><\/script>/;
    if (!anchor.test(html)) throw new Error('Cesium script anchor missing');
    html = html.replace(anchor, (tag) => tag + '\n  <script src="' + base + 'network-policy.js?v=1"></script>');
  }
  if (!html.includes('network.css')) {
    html = html.replace('</head>', '  <link rel="stylesheet" href="' + base + 'network.css?v=1">\n</head>');
  }
  html = html.replace(/network-policy\.js\?v=\d+/g, 'network-policy.js?v=2');
  html = html.replace(/(assets\/index-[^"?]+\.js)(?:\?[^"]*)?"/, '$1?network=2"');
  return html;
}

import { readFileSync, writeFileSync, cpSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const here = dirname(fileURLToPath(import.meta.url));
  const output = resolve(process.argv[2] || 'apps/globe/app');
  const base = process.argv[3] || '/apps/globe/app/';
  if (!base.startsWith('/') || !base.endsWith('/')) throw new Error('base must start/end with /');
  const htmlPath = resolve(output, 'index.html');
  const originalHtml = readFileSync(htmlPath, 'utf8');
  const match = originalHtml.match(/src="[^"]*\/assets\/(index-[^"?]+\.js)(?:\?[^"]*)?"/);
  if (!match) throw new Error('Built entry module missing');
  const entry = resolve(output, 'assets', match[1]);
  const code = patchBundle(readFileSync(entry, 'utf8'));
  const html = patchHtml(originalHtml, base);
  for (const name of ['network-policy.js', 'network.css', 'fonts', 'icons']) {
    if (!existsSync(resolve(here, name))) throw new Error('Missing local asset: ' + name);
    cpSync(resolve(here, name), resolve(output, name), { recursive: true });
  }
  writeFileSync(entry, code);
  writeFileSync(htmlPath, html);
  console.log('Globe network policy applied: local fonts, local map, bounded remote imagery.');
}
