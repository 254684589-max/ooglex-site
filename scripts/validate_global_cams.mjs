import fs from 'node:fs';

const html = fs.readFileSync('apps/global-cams/index.html', 'utf8');
const app = fs.readFileSync('apps/global-cams/app.js', 'utf8');
const config = fs.readFileSync('apps/global-cams/config.js', 'utf8');
const windows = JSON.parse(fs.readFileSync('apps/global-cams/windows.json', 'utf8'));
const windowWorker = fs.readFileSync('workers/global-windows-cdn/worker.js', 'utf8');
const windowConfig = fs.readFileSync('workers/global-windows-cdn/wrangler.toml', 'utf8');
const windowLocations = JSON.parse(fs.readFileSync('data/global-windows/locations.json', 'utf8'));
const zhLabels = JSON.parse(fs.readFileSync('data/global-windows/zh_labels.json', 'utf8'));
const windowSync = fs.readFileSync('scripts/global-cams/sync_windows_to_r2.py', 'utf8');
const windowWorkflow = fs.readFileSync('.github/workflows/deploy-global-windows-cdn.yml', 'utf8');

const failures = [];
const ok = (cond, msg) => { if (!cond) failures.push(msg); };

try { new Function(app); } catch (e) { failures.push('app.js syntax: ' + e.message); }
const windowWorkerForParse = windowWorker
  .replace('export default', 'const __windowWorker =')
  .replace('export class WindowStats', 'class WindowStats');
try { new Function(windowWorkerForParse); } catch (e) { failures.push('global-windows worker syntax: ' + e.message); }

for (const id of [
  'stage','globe','playlist','viewer','windowName','windowMeta','openSource','expandViewer',
  'search','randomWindow','randomTop','zoomIn','zoomOut','resetGlobe','resetView',
  'fullscreen','status','count','listCount','centerCoords','sidebar','playlistTabs'
]) {
  ok(html.includes('id="' + id + '"'), 'missing HTML id #' + id);
}

ok(html.includes('环球实景 <span>V1.0</span>'), 'V1.0 label missing');
ok((html.match(/class="sort-btn/g) || []).length === 3, 'featured/latest/popular tabs missing');
ok(html.includes('data-sort="featured"') && html.includes('data-sort="latest"') && html.includes('data-sort="popular"'), 'sort modes incomplete');
ok(html.includes('WINDOW ONLY'), 'WINDOW-only badge missing');
ok(html.includes('WINDOW 播放列表'), 'WINDOW playlist label missing');
ok(html.includes('@media(max-width:820px)'), '820px responsive rule missing');

ok(!html.includes('LIVE 实时'), 'LIVE mode still present in HTML');
ok(!html.includes('公开摄像头'), 'camera copy still present in HTML');
ok(!html.includes('modeLive'), 'LIVE mode control still present');
ok(!html.includes('mediaFilters'), 'camera media filters still present');
ok(!html.includes('loadNearby'), 'camera region loader still present');
ok(!html.includes('accumulate'), 'camera accumulate control still present');

ok(!app.includes('API_BASE'), 'camera API base still present in app');
ok(!app.includes('/v1/webcams'), 'camera API request still present in app');
ok(!app.includes('liveCameras'), 'camera runtime collection still present');
ok(!app.includes('loadNearby'), 'camera loader still present in app');
ok(!app.includes('cameras.json'), 'camera demo fallback still present');
ok(!config.includes('apiBase'), 'camera API config still present');

ok(app.includes('controls.autoRotate = false'), 'globe auto-rotation is not disabled');
ok(!app.includes('controls.autoRotate = true'), 'auto-rotation true remains in app');
ok(app.includes("WINDOW_CDN_BASE + '/manifest.json'"), 'WINDOW CDN manifest fetch missing');
ok(app.includes("{ url: './windows.json', source: 'fallback' }"), 'WINDOW local fallback missing');
ok(app.includes('resolveWindowVideoUrl'), 'WINDOW R2 media URL resolver missing');
ok(app.includes('video.autoplay = true'), 'WINDOW autoplay missing');
ok(app.includes('video.muted = true'), 'WINDOW muted autoplay guard missing');
ok(app.includes('video.loop = true'), 'WINDOW loop missing');
ok(app.includes('video.playsInline = true'), 'WINDOW mobile inline playback missing');
ok(app.includes('randomWindow'), 'WINDOW random picker missing');
ok(app.includes('showWindow'), 'WINDOW selection renderer missing');
ok(app.includes("'/stats/popular?days=7&limit=500'") || app.includes("'/stats/popular?days=7&limit=500"), 'popular stats fetch missing');
ok(app.includes("'/stats/play'") || app.includes("'/stats/play"), 'play stats POST missing');
ok(app.includes("currentTime || 0) < 8"), '8-second play qualification missing');
ok(app.includes('ooglex-window-play-v1:'), 'once-per-day browser dedupe missing');
ok(app.includes("activeSort === 'latest'"), 'latest sorting missing');
ok(app.includes("activeSort === 'popular'"), 'popular sorting missing');
ok(app.includes('technicalLabel'), 'duration/resolution display helper missing');
ok(app.includes('d.city_zh || d.city'), 'Chinese place label display missing');
ok(app.includes('d.original_title'), 'original-title search support missing');
ok(String(config).includes('https://windows-cdn.ooglex.com'), 'WINDOW CDN config missing');

ok(Array.isArray(windows) && windows.length >= 5, 'WINDOW seed library must contain at least 5 entries');
for (const w of windows) {
  ok(w.kind === 'window', 'WINDOW item missing kind=window');
  ok(/^https:\/\/upload\.wikimedia\.org\//.test(String(w.video_url || '')), 'WINDOW seed must use approved Wikimedia media URL');
  ok(/^https:\/\/commons\.wikimedia\.org\//.test(String(w.source_url || '')), 'WINDOW source page missing');
  ok(/^CC /.test(String(w.license || '')), 'WINDOW license missing');
  ok(Number.isFinite(Number(w.lat)) && Number.isFinite(Number(w.lng)), 'WINDOW coordinates missing');
  ok(Number(w.duration_seconds) >= 30 && Number(w.duration_seconds) <= 300, 'WINDOW fallback duration violates V1 gate');
  ok(Number(w.width) >= 1280 && Number(w.height) >= 720, 'WINDOW fallback resolution below 720p');
  ok(Number(w.width) > Number(w.height), 'WINDOW fallback must be landscape');
  ok(Boolean(w.name_zh) && /[\u3400-\u9fff]/.test(String(w.name_zh)), 'WINDOW fallback Chinese name missing');
  ok(Boolean(w.original_title), 'WINDOW fallback original title missing');
}

ok(windowConfig.includes('bucket_name = "ooglex-global-windows"'), 'WINDOW R2 bucket binding missing');
ok(windowConfig.includes('windows-cdn.ooglex.com'), 'WINDOW CDN custom domain missing');
ok(windowWorker.includes('env.WINDOW_MEDIA.get'), 'WINDOW worker R2 read missing');
ok(windowWorker.includes('Range'), 'WINDOW worker byte-range support missing');
ok(windowWorker.includes('caches.default'), 'WINDOW media cache helper missing');
ok(windowWorker.includes('no-cache, max-age=0, must-revalidate'), 'WINDOW manifest freshness policy missing');
ok(windowWorker.includes('manifest/windows.json'), 'WINDOW CDN manifest key missing');
ok(windowWorker.includes('export class WindowStats'), 'WINDOW popularity Durable Object missing');
ok(windowWorker.includes('"/stats/play"'), 'WINDOW play endpoint missing');
ok(windowWorker.includes('"/stats/popular"'), 'WINDOW popular endpoint missing');
ok(windowWorker.includes('isAllowedWriteOrigin'), 'stats write-origin guard missing');
ok(windowWorker.includes('payload_too_large'), 'stats payload size guard missing');
ok(windowWorker.includes('recentClients'), 'stats transient rate limit missing');
ok(windowConfig.includes('name = "WINDOW_STATS"'), 'WINDOW_STATS Durable Object binding missing');
ok(windowConfig.includes('new_sqlite_classes = ["WindowStats"]'), 'WINDOW_STATS migration missing');

ok(Array.isArray(windowLocations.locations) && windowLocations.locations.length >= 50, 'WINDOW scenic discovery locations too small');
ok(Number(windowLocations.target) === 150, 'WINDOW V1.0 target must be 150');
ok(Number(windowLocations.existing_keep_limit) >= 130 && Number(windowLocations.existing_keep_limit) < Number(windowLocations.target), 'WINDOW rotating keep limit invalid');
ok(String(windowLocations.popularity_url || '').includes('/stats/popular'), 'WINDOW popularity ranking URL missing');
ok(Number(windowLocations.min_catalog) >= 100, 'WINDOW minimum production catalog must be 100+');
ok(Number(windowLocations.min_quality_score) >= 60, 'WINDOW V1.0 100-point quality floor too low');
ok(Number(windowLocations.min_semantic_score) >= 5, 'WINDOW scenic semantic floor too low');
ok(Number(windowLocations.min_duration_seconds) >= 30, 'WINDOW minimum duration must be at least 30s');
ok(Number(windowLocations.max_duration_seconds) <= 300, 'WINDOW maximum duration must be at most 300s');
ok(Number(windowLocations.preferred_duration_min_seconds) >= 60, 'WINDOW preferred duration lower bound missing');
ok(Number(windowLocations.preferred_duration_max_seconds) <= 180, 'WINDOW preferred duration upper bound missing');
ok(Number(windowLocations.min_width) >= 1280 && Number(windowLocations.min_height) >= 720, 'WINDOW minimum resolution must be 720p');
ok(windowLocations.require_landscape === true, 'WINDOW must reject portrait video');
ok(Number(windowLocations.max_file_mb) <= 80 && Number(windowLocations.max_file_mb) >= 60, 'WINDOW file-size ceiling must support high-quality video');
ok(windowSync.includes('"prop": "videoinfo|coordinates"'), 'Wikimedia videoinfo batch metadata missing');
ok(windowSync.includes('"viprop": "url|mime|size|dimensions|mediatype|derivatives|timestamp|extmetadata"'), 'Wikimedia derivative metadata request missing');
ok(windowSync.includes('preferred_height = int(cfg.get("preferred_height") or 1080)'), '1080p delivery preference missing');
ok(windowSync.includes('if mime not in VIDEO_MIMES'), 'browser-safe transcode MIME gate missing');
ok(Number(windowLocations.max_catalog_gb) <= 8, 'WINDOW catalog storage budget must stay within 8GB');
ok(Number(windowLocations.quality_schema_version) === 1, 'WINDOW quality schema version missing');
ok(String(windowLocations.zh_labels || '').endsWith('zh_labels.json'), 'WINDOW Chinese label map missing');
ok(Object.keys(zhLabels.cities || {}).length >= 170, 'WINDOW Chinese city labels incomplete');
ok(Number(windowLocations.request_interval_seconds) >= 0.8, 'WINDOW Wikimedia request pacing too aggressive');
ok(Number(windowLocations.global_match_distance_km) <= 150, 'WINDOW global geolocation radius too broad');
ok(Number(windowLocations.local_location_scan_limit) >= 30 && Number(windowLocations.local_location_scan_limit) <= 200, 'WINDOW local scan limit out of range');
ok(Array.isArray(windowLocations.global_scenic_queries) && windowLocations.global_scenic_queries.length >= 35, 'WINDOW global scenic query pool too small');
ok(Array.isArray(windowLocations.global_scenic_categories) && windowLocations.global_scenic_categories.length >= 12, 'WINDOW scenic category pool too small');

for (const token of [
  'HARD_REJECT','STRICT_DESC_REJECT','SCENIC_WEIGHTS','haversine_km','quality_score',
  'seed_items','image_infos','ingest_existing','global_scenic_titles','match_global_location',
  'media_coords','category_titles','scene_fingerprint','text_has_alias','_MEDIA_LAST','title_score < 3',
  'catalog_added_at','source_updated_at','fetch_popularity','existing_keep_limit',
  'rest_media_profile','technical_gate','v1_quality_score','duration_seconds',
  'original_title','name_zh','quality_breakdown','max_catalog_gb','audit-existing',
  'videoinfo','derivatives','select_delivery_variant','delivery_variant_url',
  'delivery_kind','transcode_key','no-720p-under-80mb-variant','manifest-only'
]) {
  ok(windowSync.includes(token), 'WINDOW curator guard missing: ' + token);
}
ok(windowWorkflow.includes("cron: '25 19 * * *'"), 'daily WINDOW refresh schedule missing');
ok(windowWorkflow.includes('manifest/gc-pending.json'), 'persistent R2 cleanup queue missing');
ok(windowWorkflow.includes('queue[:20]'), 'R2 cleanup per-run cap missing');
ok(windowWorkflow.includes('exceeds hard cap 500'), 'R2 cleanup queue safety cap missing');
ok(windowWorkflow.includes('r2 object delete "$BUCKET/$key" --remote --force'), 'stale R2 cleanup command missing');
ok(windowWorkflow.includes("'data/global-windows/zh_labels.json'"), 'Chinese label workflow trigger missing');
ok(!/WINDY_WEBCAMS_API_KEY\s*=\s*['"][A-Za-z0-9]{20,}/.test(html + app + config), 'camera API key literal detected');

if (failures.length) {
  console.error('Global WINDOW V1.0 validation failed:');
  failures.forEach(x => console.error(' - ' + x));
  process.exit(1);
}
console.log('Global WINDOW V1.0 validation passed.');
