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
  'resetView','fullscreen','status','count','listCount','centerCoords','mediaFilters',
  'filterAllCount','filterLiveCount','filterTimelapseCount','filterSnapshotCount'
]) {
  ok(html.includes('id="' + id + '"'), 'missing HTML id #' + id);
}

ok(html.includes('环球实景 <span>V0.4</span>'), 'V0.4 label missing');
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
ok(worker.includes("stream_type: streamType"), 'worker media type field missing');
ok(worker.includes("is_live: Boolean(live)"), 'worker explicit live flag missing');
ok(worker.includes("live_url: live || ''"), 'worker live URL field missing');
ok(worker.includes("timelapse_url: timelapse || ''"), 'worker timelapse URL field missing');
ok(!worker.includes('firstString(player.live, player.day)'), 'worker still conflates live and day player');
ok(app.includes("activeMedia = 'all'"), 'media filter state missing');
ok(app.includes("LIVE 实时直播"), 'LIVE semantic label missing');
ok(app.includes("24H 延时摄影"), 'timelapse semantic label missing');
ok(app.includes("an unlabeled embed is never promoted to LIVE"), 'conservative backward-compatibility rule missing');
ok(!/JoerI87|WINDY_WEBCAMS_API_KEY\s*=\s*['"][A-Za-z0-9]{20,}/.test(html + app + worker), 'possible API key literal detected');

const normalizeWebcam = new Function(workerForParse + '; return normalizeWebcam;')();
const baseFixture = {
  webcamId: 1,
  title: 'Fixture',
  status: 'active',
  location: { latitude: 35.6, longitude: 139.7, country: 'Japan', city: 'Tokyo' },
  categories: [],
  urls: { detail: 'https://www.windy.com/webcams/1' },
  lastUpdatedOn: '2026-10-01T00:00:00Z'
};
const liveFixture = normalizeWebcam({
  ...baseFixture,
  player: { live: 'https://example.com/live', day: 'https://example.com/day' },
  images: { current: { preview: 'https://example.com/preview.jpg' } }
});
ok(liveFixture.stream_type === 'live', 'live fixture not classified LIVE');
ok(liveFixture.is_live === true, 'live fixture missing is_live=true');
ok(liveFixture.embed_url === 'https://example.com/live', 'live fixture must prefer live player');
ok(liveFixture.timelapse_url === 'https://example.com/day', 'live fixture must retain day player separately');

const timelapseFixture = normalizeWebcam({
  ...baseFixture,
  player: { day: 'https://example.com/day' },
  images: { current: { preview: 'https://example.com/preview.jpg' } }
});
ok(timelapseFixture.stream_type === 'timelapse', 'day-only fixture not classified timelapse');
ok(timelapseFixture.is_live === false, 'day-only fixture incorrectly marked live');
ok(timelapseFixture.embed_url === 'https://example.com/day', 'timelapse fixture embed mismatch');

const snapshotFixture = normalizeWebcam({
  ...baseFixture,
  player: {},
  images: { current: { preview: 'https://example.com/preview.jpg' } }
});
ok(snapshotFixture.stream_type === 'snapshot', 'preview-only fixture not classified snapshot');
ok(snapshotFixture.embed_url === '', 'snapshot fixture must not expose an embed player');

const sourceFixture = normalizeWebcam({
  ...baseFixture,
  player: {},
  images: { current: {} }
});
ok(sourceFixture.stream_type === 'source', 'source-only fixture not classified source');
ok(sourceFixture.playable === false, 'source-only fixture incorrectly marked playable');

if (failures.length) {
  console.error('Global Cams V0.4 validation failed:');
  failures.forEach(x => console.error(' - ' + x));
  process.exit(1);
}
console.log('Global Cams V0.4 validation passed.');
