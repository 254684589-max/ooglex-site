import fs from 'node:fs';

const html = fs.readFileSync('apps/global-cams/index.html', 'utf8');
const app = fs.readFileSync('apps/global-cams/app.js', 'utf8');
const worker = fs.readFileSync('workers/global-cams-api/worker.js', 'utf8');
const windows = JSON.parse(fs.readFileSync('apps/global-cams/windows.json', 'utf8'));
const windowWorker = fs.readFileSync('workers/global-windows-cdn/worker.js', 'utf8');
const windowConfig = fs.readFileSync('workers/global-windows-cdn/wrangler.toml', 'utf8');
const windowLocations = JSON.parse(fs.readFileSync('data/global-windows/locations.json', 'utf8'));
const windowSync = fs.readFileSync('scripts/global-cams/sync_windows_to_r2.py', 'utf8');

const failures = [];
const ok = (cond, msg) => { if (!cond) failures.push(msg); };

try { new Function(app); } catch (e) { failures.push('app.js syntax: ' + e.message); }

const workerForParse = worker
  .replace('export default', 'const __worker =')
  .replace('export function normalizeWebcam', 'function normalizeWebcam');
try { new Function(workerForParse); } catch (e) { failures.push('worker.js syntax: ' + e.message); }
const windowWorkerForParse = windowWorker.replace('export default', 'const __windowWorker =');
try { new Function(windowWorkerForParse); } catch (e) { failures.push('global-windows worker syntax: ' + e.message); }

for (const id of [
  'stage','globe','playlist','viewer','camName','camMeta','openSource','expandViewer',
  'search','loadNearby','accumulate','clearAll','zoomIn','zoomOut','resetGlobe',
  'resetView','fullscreen','status','count','listCount','centerCoords','mediaFilters',
  'filterAllCount','filterLiveCount','filterTimelapseCount','filterSnapshotCount',
  'sidebar','modeLive','modeWindow','playlistTitle','legend'
]) {
  ok(html.includes('id="' + id + '"'), 'missing HTML id #' + id);
}

ok(html.includes('环球实景 <span>V0.7</span>'), 'V0.7 label missing');
ok(html.includes('播放列表'), 'playlist label missing');
ok(html.includes('@media(max-width:820px)'), '820px responsive rule missing');
ok(app.includes('controls.autoRotate = false'), 'globe auto-rotation is not disabled');
ok(app.includes("activeLayer = 'live'"), 'dual-layer state missing');
ok(app.includes("switchLayer('window')"), 'WINDOW mode switch missing');
ok(app.includes("WINDOW_CDN_BASE + '/manifest.json'"), 'WINDOW CDN manifest fetch missing');
ok(app.includes("{ url: './windows.json', source: 'fallback' }"), 'WINDOW local fallback missing');
ok(app.includes('resolveWindowVideoUrl'), 'WINDOW R2 media URL resolver missing');
ok(app.includes("video.autoplay = true"), 'WINDOW autoplay missing');
ok(app.includes("video.muted = true"), 'WINDOW muted autoplay guard missing');
ok(app.includes("video.loop = true"), 'WINDOW loop missing');
ok(app.includes("mediaLabel(type)"), 'media label helper missing');
ok(!app.includes('controls.autoRotate = true'), 'auto-rotation true remains in app');
ok(app.includes('const PAGE_SIZE = 50'), 'page size guard missing');
ok(app.includes('const MAX_REGION_CAMERAS = 1000'), 'free-tier region cap missing');
ok(app.includes("url.searchParams.set('offset', String(offset))"), 'frontend offset pagination missing');
ok(app.includes('mergeCameras(liveCameras, region)'), 'accumulated-region merge missing');
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

ok(Array.isArray(windows) && windows.length >= 5, 'WINDOW seed library must contain at least 5 entries');
ok(windowConfig.includes('bucket_name = "ooglex-global-windows"'), 'WINDOW R2 bucket binding missing');
ok(windowConfig.includes('windows-cdn.ooglex.com'), 'WINDOW CDN custom domain missing');
ok(windowWorker.includes('env.WINDOW_MEDIA.get'), 'WINDOW worker R2 read missing');
ok(windowWorker.includes('Range'), 'WINDOW worker byte-range support missing');
ok(windowWorker.includes('caches.default'), 'WINDOW CDN cache layer missing');
ok(windowWorker.includes('manifest/windows.json'), 'WINDOW CDN manifest key missing');
ok(Array.isArray(windowLocations.locations) && windowLocations.locations.length >= 50, 'WINDOW scenic discovery locations too small');
ok(Number(windowLocations.target) >= 100 && Number(windowLocations.target) <= 300, 'WINDOW target must be within 100-300 clips');
ok(Number(windowLocations.min_catalog) >= 100, 'WINDOW minimum production catalog must be 100+');
ok(Number(windowLocations.min_quality_score) >= 5, 'WINDOW minimum quality score too low');
ok(windowSync.includes('HARD_REJECT'), 'WINDOW hard-reject quality gate missing');
ok(windowSync.includes('SCENIC_WEIGHTS'), 'WINDOW scenic scoring missing');
ok(windowSync.includes('haversine_km'), 'WINDOW geographic validation missing');
ok(windowSync.includes('quality_score'), 'WINDOW quality score output missing');
ok(windowSync.includes('seed_items'), 'WINDOW curated seed ingestion missing');
ok(windowSync.includes('image_infos'), 'WINDOW batched metadata lookup missing');
ok(windowSync.includes('category_titles'), 'WINDOW place-category harvesting missing');
ok(windowSync.includes('semantic_title_key'), 'WINDOW semantic duplicate guard missing');
ok(windowSync.includes('trusted_category'), 'WINDOW trusted category evidence missing');
ok(windowSync.includes('_DOWNLOAD_LAST'), 'WINDOW media download pacing missing');
ok(windowSync.includes('media HTTP'), 'WINDOW media 429 retry/backoff missing');
ok(windowSync.includes('ingest_existing'), 'WINDOW existing R2 reuse missing');
ok(windowSync.includes('global_scenic_titles'), 'WINDOW global scenic fill missing');
ok(windowSync.includes('match_global_location'), 'WINDOW global scenic geolocation missing');
ok(windowSync.includes('media_coords'), 'WINDOW page-coordinate support missing');
ok(Array.isArray(windowLocations.global_scenic_queries) && windowLocations.global_scenic_queries.length >= 15, 'WINDOW global scenic query pool too small');
ok(Number(windowLocations.global_max_candidates) >= 500, 'WINDOW global scenic candidate pool too small');
ok(Number(windowLocations.request_interval_seconds) >= 0.5, 'WINDOW Wikimedia request pacing too aggressive');
ok(String(windowLocations.existing_manifest_url || '').includes('windows-cdn.ooglex.com/manifest.json'), 'WINDOW existing CDN manifest reuse URL missing');
for (const w of windows) {
  ok(w.kind === 'window', 'WINDOW item missing kind=window');
  ok(/^https:\/\/upload\.wikimedia\.org\//.test(String(w.video_url || '')), 'WINDOW video must use approved Wikimedia media URL');
  ok(/^https:\/\/commons\.wikimedia\.org\//.test(String(w.source_url || '')), 'WINDOW source page missing');
  ok(/^CC /.test(String(w.license || '')), 'WINDOW license missing');
  ok(Number.isFinite(Number(w.lat)) && Number.isFinite(Number(w.lng)), 'WINDOW coordinates missing');
}

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
  console.error('Global Cams V0.7 validation failed:');
  failures.forEach(x => console.error(' - ' + x));
  process.exit(1);
}
console.log('Global Cams V0.7 validation passed.');
