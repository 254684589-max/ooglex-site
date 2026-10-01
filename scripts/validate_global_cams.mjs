import fs from 'node:fs';

const html = fs.readFileSync('apps/global-cams/index.html', 'utf8');
const app = fs.readFileSync('apps/global-cams/app.js', 'utf8');
const worker = fs.readFileSync('workers/global-cams-api/worker.js', 'utf8');

const failures = [];
const ok = (cond, msg) => { if (!cond) failures.push(msg); };

try { new Function(app); } catch (e) { failures.push('app.js syntax: ' + e.message); }

const workerForParse = worker
  .replace('export default', 'const __worker =')
  .replace('export function normalizeWebcam', 'function normalizeWebcam');
try { new Function(workerForParse); } catch (e) { failures.push('worker.js syntax: ' + e.message); }

for (const id of [
  'stage','globe','playlist','viewer','camName','camMeta','openSource','expandViewer',
  'search','loadNearby','accumulate','clearAll','zoomIn','zoomOut','resetGlobe',
  'resetView','fullscreen','status','count','listCount','centerCoords'
]) {
  ok(html.includes('id="' + id + '"'), 'missing HTML id #' + id);
}

ok(html.includes('环球实景 <span>V0.3</span>'), 'V0.3 label missing');
ok(html.includes('播放列表'), 'playlist label missing');
ok(html.includes('@media(max-width:820px)'), '820px responsive rule missing');
ok(app.includes('controls.autoRotate = false'), 'globe auto-rotation is not disabled');
ok(!app.includes('controls.autoRotate = true'), 'auto-rotation true remains in app');
ok(app.includes('const PAGE_SIZE = 50'), 'page size guard missing');
ok(app.includes('const MAX_REGION_CAMERAS = 1000'), 'free-tier region cap missing');
ok(app.includes("url.searchParams.set('offset', String(offset))"), 'frontend offset pagination missing');
ok(app.includes('mergeCameras(all, region)'), 'accumulated-region merge missing');
ok(app.includes("requestAnimationFrame(() => loadNearby({ initial: true }))"), 'Tokyo initial auto-load missing');
ok(worker.includes("integerParam(url.searchParams.get('offset') || '0', 0, 1000)"), 'worker offset guard missing');
ok(worker.includes("upstream.searchParams.set('offset', String(offset))"), 'worker offset passthrough missing');
ok(worker.includes('env.WINDY_WEBCAMS_API_KEY'), 'worker secret binding missing');
ok(!/JoerI87|WINDY_WEBCAMS_API_KEY\s*=\s*['"][A-Za-z0-9]{20,}/.test(html + app + worker), 'possible API key literal detected');

if (failures.length) {
  console.error('Global Cams V0.3 validation failed:');
  failures.forEach(x => console.error(' - ' + x));
  process.exit(1);
}
console.log('Global Cams V0.3 validation passed.');
