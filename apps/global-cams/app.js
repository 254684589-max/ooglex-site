(() => {
'use strict';

const $ = s => document.querySelector(s);
const sidebar = $('#sidebar');
const stage = $('#stage');
const globeEl = $('#globe');
const viewer = $('#viewer');
const playlist = $('#playlist');
const count = $('#count');
const listCount = $('#listCount');
const playlistTitle = $('#playlistTitle');
const search = $('#search');
const status = $('#status');
const loadBtn = $('#loadNearby');
const attribution = $('#attribution');
const sourceLink = $('#openSource');
const accumulate = $('#accumulate');
const centerCoords = $('#centerCoords');
const mediaFilters = $('#mediaFilters');
const legend = $('#legend');
const modeLive = $('#modeLive');
const modeWindow = $('#modeWindow');
const clearAllBtn = $('#clearAll');
const cfg = window.OOGLEX_GLOBAL_CAMS || {};
const API_BASE = String(cfg.apiBase || '').replace(/\/$/, '');

const TOKYO = Object.freeze({ lat: 35.6762, lng: 139.6503, altitude: 1.45 });
const PAGE_SIZE = 50;
const MAX_REGION_CAMERAS = 1000;

let liveCameras = [];
let windowLibrary = [];
let all = [];
let filtered = [];
let selectedId = '';
let activeMedia = 'all';
let activeLayer = 'live';
let mode = API_BASE ? 'live' : 'demo';
let loading = false;
let rowsById = new Map();
let windowsPromise = null;

const globe = Globe()(globeEl)
  .width(stage.clientWidth)
  .height(stage.clientHeight)
  .globeImageUrl('../radio/vendor/earth-blue-marble.jpg')
  .backgroundColor('#05070f')
  .pointAltitude(0.015)
  .pointRadius(d => itemKey(d) === selectedId ? 0.29 : (isWindow(d) ? 0.20 : (mediaType(d) === 'live' ? 0.23 : mediaType(d) === 'timelapse' ? 0.20 : 0.16)))
  .pointColor(d => itemKey(d) === selectedId ? '#ffd36b' : pointColorFor(d))
  .pointLabel(d => '<b>' + escapeHtml(d.name || itemFallbackName(d)) + '</b><br>' + escapeHtml(itemSubLabel(d)))
  .onPointClick(d => showItem(d, { focus: true, reveal: true }));

const controls = globe.controls();
controls.autoRotate = false;
controls.enableDamping = true;
controls.addEventListener('change', updateCenterReadout);
globe.pointOfView(TOKYO, 0);
updateCenterReadout();

void loadWindows({ silent: true });

if (API_BASE) {
  setStatus('真实摄像头服务已连接。正在加载东京当前区域的全部公开信号源…', 'live');
  requestAnimationFrame(() => loadNearby({ initial: true }));
} else {
  loadDemo();
}

async function loadDemo() {
  try {
    const r = await fetch('./cameras.json', { cache: 'no-store' });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const data = await r.json();
    liveCameras = Array.isArray(data) ? data : [];
    mode = 'demo';
    if (activeLayer === 'live') {
      all = liveCameras.slice();
      applySearch();
      setStatus('演示数据模式。真实 Global Cams API 尚未配置。', 'warn');
    }
  } catch (err) {
    liveCameras = [];
    if (activeLayer === 'live') {
      all = [];
      filtered = [];
      setStatus('演示数据加载失败。', 'error');
      render();
    }
    console.error(err);
  }
}

async function loadWindows(options = {}) {
  if (windowLibrary.length) return windowLibrary;
  if (windowsPromise) return windowsPromise;

  windowsPromise = (async () => {
    try {
      const r = await fetch('./windows.json', { cache: 'no-store' });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const data = await r.json();
      const rows = Array.isArray(data) ? data : [];
      windowLibrary = rows
        .filter(d => d && safeHttpUrl(d.video_url) && Number.isFinite(+d.lat) && Number.isFinite(+d.lng))
        .map(d => ({ ...d, kind: 'window' }));

      if (activeLayer === 'window') {
        all = windowLibrary.slice();
        applySearch();
        if (!options.silent) setStatus('沉浸窗口库已加载 ' + windowLibrary.length + ' 个许可视频。', 'window');
      }
      return windowLibrary;
    } catch (err) {
      if (activeLayer === 'window' && !options.silent) {
        setStatus('沉浸窗口库加载失败：' + safeMessage(err), 'error');
        all = [];
        filtered = [];
        render();
      }
      console.error(err);
      return [];
    } finally {
      windowsPromise = null;
    }
  })();

  return windowsPromise;
}

async function switchLayer(layer) {
  const next = layer === 'window' ? 'window' : 'live';
  if (activeLayer === next) return;

  activeLayer = next;
  selectedId = '';
  activeMedia = 'all';
  search.value = '';
  document.querySelectorAll('.filter-btn').forEach(btn => btn.classList.toggle('active', btn.dataset.filter === 'all'));
  modeLive.classList.toggle('active', next === 'live');
  modeWindow.classList.toggle('active', next === 'window');
  sidebar.classList.toggle('window-mode', next === 'window');
  mediaFilters.hidden = next === 'window';
  accumulate.closest('.toggle').classList.toggle('hidden', next === 'window');
  clearAllBtn.classList.toggle('hidden', next === 'window');

  if (next === 'window') {
    playlistTitle.textContent = '窗口列表';
    search.placeholder = '搜索国家、城市、窗口…';
    loadBtn.textContent = '随机窗口';
    legend.textContent = '🔵 WINDOW = 预录许可视频 · 默认静音循环播放 · 可放大 / 全屏 / 手动开声音';
    sourceLink.textContent = '查看素材来源';
    clearSelection();
    setStatus('正在加载沉浸窗口库…', 'window');
    const rows = await loadWindows();
    all = rows.slice();
    applySearch();
    if (rows.length) {
      showWindow(rows[0], { focus: false, reveal: true, autoplay: true });
      setStatus('沉浸窗口已启用 · ' + rows.length + ' 个许可视频 · 与实时摄像头分层展示。', 'window');
    } else {
      setStatus('当前窗口库暂无可播放视频。', 'warn');
    }
  } else {
    playlistTitle.textContent = '播放列表';
    search.placeholder = '搜索国家、城市、摄像头…';
    loadBtn.textContent = '加载当前区域';
    legend.textContent = '🔴 LIVE = 上游明确提供实时播放器　🟢 24H = 延时摄影　⚪ = 最新抓拍　· 中心准星 = 查询中心';
    sourceLink.textContent = '打开官方来源';
    clearSelection();
    all = liveCameras.slice();
    applySearch();
    if (mode === 'demo') {
      setStatus('演示数据模式。真实 Global Cams API 尚未配置。', 'warn');
    } else if (liveCameras.length) {
      const stats = mediaStats(liveCameras);
      setStatus('已恢复实时摄像头层 · ' + liveCameras.length + ' 个点位 · LIVE ' + stats.live + ' · 24H ' + stats.timelapse + ' · 抓拍 ' + stats.snapshot, 'live');
    } else {
      setStatus('转动地球后点击“加载当前区域”查询公开摄像头。', 'live');
    }
  }
}

async function loadNearby(options = {}) {
  if (activeLayer !== 'live') {
    randomWindow();
    return;
  }
  if (loading) return;
  if (!API_BASE) {
    setStatus('真实数据服务尚未配置。', 'warn');
    return;
  }

  const pov = globe.pointOfView();
  const lat = clamp(Number(pov.lat) || 0, -90, 90);
  const lng = clamp(Number(pov.lng) || 0, -180, 180);
  loading = true;
  loadBtn.disabled = true;
  loadBtn.textContent = '加载中…';
  setStatus('正在查询中心 ' + formatCoord(lat, lng) + ' 周围 250 公里的公开摄像头…', 'live');

  let region = [];
  let total = null;
  let partialError = null;
  let offset = 0;
  let asOf = '';

  try {
    while (total === null || offset < Math.min(total, MAX_REGION_CAMERAS)) {
      let payload;
      try {
        payload = await fetchRegionPage(lat, lng, offset);
      } catch (err) {
        if (offset === 0) throw err;
        partialError = err;
        break;
      }

      const webcams = Array.isArray(payload.webcams) ? payload.webcams : [];
      region = mergeCameras(region, webcams);
      total = Number.isFinite(Number(payload.total)) ? Number(payload.total) : region.length;
      asOf = String(payload.asOf || asOf || '');
      offset += PAGE_SIZE;

      const target = Math.min(total, MAX_REGION_CAMERAS);
      if (activeLayer === 'live') {
        setStatus(
          '正在加载当前区域：' + Math.min(offset, target) + ' / ' + target +
          (total > MAX_REGION_CAMERAS ? '（免费接口上限 ' + MAX_REGION_CAMERAS + '）' : ''),
          'live'
        );
      }

      if (target === 0) break;
    }

    if (accumulate.checked && !options.initial) {
      liveCameras = mergeCameras(liveCameras, region);
    } else {
      liveCameras = region;
    }

    mode = 'live';

    if (activeLayer === 'live') {
      all = liveCameras.slice();
      applySearch();

      if (selectedId && !all.some(d => itemKey(d) === selectedId)) clearSelection();

      const shown = region.length;
      const totalText = total == null ? shown : total;
      if (partialError) {
        setStatus('已加载 ' + shown + ' 个信号源，但后续分页失败：' + safeMessage(partialError), 'warn');
      } else if (!shown) {
        setStatus('当前查询中心 250 公里范围内没有返回可用摄像头。', 'warn');
      } else if (totalText > MAX_REGION_CAMERAS) {
        setStatus('区域共有 ' + totalText + ' 个摄像头；免费接口本次显示前 ' + MAX_REGION_CAMERAS + ' 个。数据源 Windy Webcams API。', 'warn');
      } else {
        const stats = mediaStats(region);
        setStatus(
          '当前区域已完整载入 ' + shown + ' / ' + totalText + ' 个公开摄像头' +
          ' · LIVE ' + stats.live + ' · 24H ' + stats.timelapse + ' · 抓拍 ' + stats.snapshot +
          (accumulate.checked && !options.initial ? ' · 已累计 ' + liveCameras.length + ' 个点位' : '') +
          ' · 数据源 Windy Webcams API' +
          (asOf ? ' · ' + formatTime(asOf) : ''),
          'live'
        );
      }
    }
  } catch (err) {
    if (activeLayer === 'live') setStatus('真实摄像头加载失败：' + safeMessage(err), 'error');
  } finally {
    loading = false;
    loadBtn.disabled = false;
    loadBtn.textContent = activeLayer === 'window' ? '随机窗口' : '加载当前区域';
  }
}

async function fetchRegionPage(lat, lng, offset) {
  const url = new URL(API_BASE + '/v1/webcams');
  url.searchParams.set('lat', lat.toFixed(4));
  url.searchParams.set('lng', lng.toFixed(4));
  url.searchParams.set('radius', '250');
  url.searchParams.set('limit', String(PAGE_SIZE));
  url.searchParams.set('offset', String(offset));
  url.searchParams.set('lang', 'zh');

  const r = await fetch(url.toString(), { headers: { Accept: 'application/json' } });
  const payload = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(payload.error || ('HTTP ' + r.status));
  return payload;
}

function applySearch() {
  const q = search.value.trim().toLowerCase();
  filtered = all.filter(d => {
    if (activeLayer === 'live') {
      const typeOk = activeMedia === 'all' || mediaType(d) === activeMedia;
      if (!typeOk) return false;
    }
    if (!q) return true;
    const haystack = isWindow(d)
      ? [d.name, d.city, d.country, d.category, d.author, d.license, 'window', '沉浸窗口'].filter(Boolean).join(' ').toLowerCase()
      : [d.name, d.city, d.country, d.category, d.source, mediaLabel(d)].filter(Boolean).join(' ').toLowerCase();
    return haystack.includes(q);
  });
  render();
}

function render() {
  globe.pointsData(filtered);

  if (activeLayer === 'window') {
    count.textContent = filtered.length === all.length && !search.value.trim()
      ? all.length + ' 个沉浸窗口'
      : filtered.length + ' / ' + all.length + ' 个窗口';
    listCount.textContent = filtered.length === all.length && !search.value.trim()
      ? all.length + ' 个窗口'
      : filtered.length + ' / ' + all.length + ' 个窗口';
  } else {
    count.textContent = filtered.length === all.length && activeMedia === 'all' && !search.value.trim()
      ? all.length + (mode === 'demo' ? ' 个演示点位' : ' 个公开点位')
      : filtered.length + ' / ' + all.length + ' 个点位';
    listCount.textContent = filtered.length === all.length && activeMedia === 'all' && !search.value.trim()
      ? all.length + ' 个信号源'
      : filtered.length + ' / ' + all.length + ' 个信号源';
    renderFilterCounts();
  }

  renderPlaylist();
}

function renderPlaylist() {
  playlist.replaceChildren();
  rowsById = new Map();

  if (!filtered.length) {
    const empty = document.createElement('div');
    empty.className = 'empty-list';
    if (activeLayer === 'window') {
      empty.textContent = all.length ? '没有匹配搜索条件的窗口。' : '当前没有可播放的沉浸窗口。';
    } else {
      empty.textContent = all.length
        ? '没有匹配搜索条件的摄像头。'
        : '当前没有已加载信号源。转动地球后点击“加载当前区域”。';
    }
    playlist.appendChild(empty);
    return;
  }

  const frag = document.createDocumentFragment();
  filtered.forEach(d => {
    const id = itemKey(d);
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'cam-row media-' + (isWindow(d) ? 'window' : mediaType(d)) + (id === selectedId ? ' active' : '');
    row.setAttribute('role', 'option');
    row.setAttribute('aria-selected', id === selectedId ? 'true' : 'false');
    row.dataset.camId = id;

    const dot = document.createElement('span');
    dot.className = 'cam-dot';
    dot.setAttribute('aria-hidden', 'true');

    const main = document.createElement('span');
    main.className = 'cam-main';
    const name = document.createElement('span');
    name.className = 'cam-name';
    name.textContent = d.name || itemFallbackName(d);
    const sub = document.createElement('span');
    sub.className = 'cam-sub';
    sub.textContent = itemSubLabel(d);

    main.append(name, sub);
    row.append(dot, main);
    row.addEventListener('click', () => showItem(d, { focus: true, reveal: false, autoplay: true }));
    rowsById.set(id, row);
    frag.appendChild(row);
  });

  playlist.appendChild(frag);
}

function showItem(d, options = {}) {
  if (isWindow(d)) showWindow(d, options);
  else showCamera(d, options);
}

function showCamera(d, options = {}) {
  selectedId = itemKey(d);
  const type = mediaType(d);
  $('#camName').textContent = d.name || '公开摄像头';
  $('#camMeta').textContent = [mediaLabel(d), cleanPlace(d.city), cleanPlace(d.country), d.category, d.source].filter(Boolean).join(' · ');
  sourceLink.textContent = '打开官方来源';

  const sourceUrl = safeHttpUrl(d.source_url);
  sourceLink.href = sourceUrl || '#';
  sourceLink.setAttribute('aria-disabled', sourceUrl ? 'false' : 'true');
  viewer.replaceChildren();
  appendMediaBadge(type);

  const liveUrl = type === 'live' ? safeHttpUrl(d.live_url || d.embed_url) : '';
  const timelapseUrl = type === 'timelapse' ? safeHttpUrl(d.timelapse_url || d.embed_url) : '';
  const previewUrl = safeHttpUrl(d.preview_url);

  if (liveUrl || timelapseUrl) {
    const frame = document.createElement('iframe');
    frame.src = liveUrl || timelapseUrl;
    frame.title = (d.name || '公开摄像头') + ' · ' + mediaLabel(d);
    frame.allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen';
    frame.allowFullscreen = true;
    frame.referrerPolicy = 'strict-origin-when-cross-origin';
    viewer.appendChild(frame);
  } else if (previewUrl) {
    const img = document.createElement('img');
    img.src = previewUrl;
    img.alt = (d.name || '公开摄像头') + ' · 最新抓拍';
    img.referrerPolicy = 'no-referrer';
    if (sourceUrl) {
      const a = document.createElement('a');
      a.href = sourceUrl;
      a.target = '_blank';
      a.rel = 'noopener';
      a.appendChild(img);
      viewer.appendChild(a);
    } else {
      viewer.appendChild(img);
    }
  } else {
    const box = document.createElement('div');
    box.className = 'viewer-empty';
    box.textContent = d.demo
      ? '演示点位：仅用于验证交互。'
      : '该摄像头当前没有实时、24H 延时摄影或最新抓拍，请打开官方来源。';
    viewer.appendChild(box);
  }

  if (d.source === 'Windy Webcams API') {
    attribution.innerHTML = 'Webcams provided by <a href="https://www.windy.com/" target="_blank" rel="noopener">windy.com</a> — <a href="https://www.windy.com/webcams/add" target="_blank" rel="noopener">add a webcam</a>';
  } else {
    attribution.textContent = d.demo
      ? '演示数据，不代表当前真实直播状态。'
      : '公开来源；画面版权与可用性归原始提供方。';
  }

  finishSelection(d, options);
}

function showWindow(d, options = {}) {
  selectedId = itemKey(d);
  $('#camName').textContent = d.name || '沉浸窗口';
  $('#camMeta').textContent = ['WINDOW 沉浸窗口', cleanPlace(d.city), cleanPlace(d.country), d.category, d.duration].filter(Boolean).join(' · ');
  sourceLink.textContent = '查看素材来源';

  const sourceUrl = safeHttpUrl(d.source_url);
  sourceLink.href = sourceUrl || '#';
  sourceLink.setAttribute('aria-disabled', sourceUrl ? 'false' : 'true');

  viewer.replaceChildren();
  appendMediaBadge('window');

  const videoUrl = safeHttpUrl(d.video_url);
  if (videoUrl) {
    const video = document.createElement('video');
    video.src = videoUrl;
    video.controls = true;
    video.autoplay = true;
    video.muted = true;
    video.loop = true;
    video.playsInline = true;
    video.preload = 'metadata';
    video.setAttribute('playsinline', '');
    video.setAttribute('aria-label', (d.name || '沉浸窗口') + ' 视频');
    video.addEventListener('error', () => {
      if (viewer.querySelector('.window-error')) return;
      const msg = document.createElement('div');
      msg.className = 'viewer-empty window-error';
      msg.textContent = '该窗口视频当前无法直接播放，可点击“查看素材来源”。';
      viewer.appendChild(msg);
    });
    viewer.appendChild(video);
    if (options.autoplay !== false) video.play().catch(() => {});
  } else {
    const box = document.createElement('div');
    box.className = 'viewer-empty';
    box.textContent = '该窗口暂未配置可播放视频。';
    viewer.appendChild(box);
  }

  renderWindowAttribution(d);
  finishSelection(d, options);
}

function renderWindowAttribution(d) {
  attribution.replaceChildren();
  const parts = [];
  if (d.author) parts.push('作者：' + d.author);
  if (d.license) parts.push(d.license);
  if (d.source) parts.push(d.source);

  const textNode = document.createTextNode((parts.join(' · ') || '许可视频素材') + (d.source_url ? ' · ' : ''));
  attribution.appendChild(textNode);

  const sourceUrl = safeHttpUrl(d.source_url);
  if (sourceUrl) {
    const a = document.createElement('a');
    a.href = sourceUrl;
    a.target = '_blank';
    a.rel = 'noopener';
    a.textContent = '查看许可与原始文件';
    attribution.appendChild(a);
  }
}

function finishSelection(d, options = {}) {
  render();

  if (options.reveal) {
    const row = rowsById.get(selectedId);
    if (row) row.scrollIntoView({ block: 'nearest', behavior: prefersReducedMotion() ? 'auto' : 'smooth' });
  }

  if (options.focus && Number.isFinite(+d.lat) && Number.isFinite(+d.lng)) {
    globe.pointOfView(
      { lat: +d.lat, lng: +d.lng, altitude: isWindow(d) ? 0.95 : 0.72 },
      prefersReducedMotion() ? 0 : 650
    );
  }
}

function randomWindow() {
  const pool = filtered.length ? filtered : windowLibrary;
  if (!pool.length) {
    setStatus('当前没有可随机播放的沉浸窗口。', 'warn');
    return;
  }
  const d = pool[Math.floor(Math.random() * pool.length)];
  showWindow(d, { focus: true, reveal: true, autoplay: true });
  setStatus('随机窗口 · ' + (d.name || '沉浸窗口') + ' · 预录许可视频，不代表实时画面。', 'window');
}

function renderFilterCounts() {
  const stats = mediaStats(liveCameras);
  $('#filterAllCount').textContent = String(liveCameras.length);
  $('#filterLiveCount').textContent = String(stats.live);
  $('#filterTimelapseCount').textContent = String(stats.timelapse);
  $('#filterSnapshotCount').textContent = String(stats.snapshot);
}

function mediaStats(items) {
  return items.reduce((acc, d) => {
    const type = mediaType(d);
    if (Object.prototype.hasOwnProperty.call(acc, type)) acc[type] += 1;
    return acc;
  }, { live: 0, timelapse: 0, snapshot: 0, source: 0 });
}

function mediaType(d) {
  const declared = String(d && d.stream_type || '');
  if (['live','timelapse','snapshot','source'].includes(declared)) return declared;
  if (d && (d.is_live === true || safeHttpUrl(d.live_url))) return 'live';
  if (d && safeHttpUrl(d.timelapse_url)) return 'timelapse';
  if (d && safeHttpUrl(d.preview_url)) return 'snapshot';
  // Backward compatibility: an unlabeled embed is never promoted to LIVE.
  if (d && safeHttpUrl(d.embed_url)) return 'timelapse';
  return 'source';
}

function mediaLabel(d) {
  const type = typeof d === 'string' ? d : mediaType(d);
  if (type === 'live') return 'LIVE 实时直播';
  if (type === 'timelapse') return '24H 延时摄影';
  if (type === 'snapshot') return '最新抓拍';
  if (type === 'window') return 'WINDOW 沉浸窗口';
  return '来源页';
}

function pointColorFor(d) {
  if (isWindow(d)) return '#68a8ff';
  const type = mediaType(d);
  if (type === 'live') return '#ff6262';
  if (type === 'timelapse') return '#4ee7b7';
  if (type === 'snapshot') return '#d8e2f2';
  return '#7f8ba2';
}

function appendMediaBadge(type) {
  const badge = document.createElement('div');
  badge.className = 'media-badge';
  badge.id = 'mediaBadge';
  badge.dataset.type = type || 'none';
  badge.textContent = type === 'none' ? '' : mediaLabel(type);
  viewer.appendChild(badge);
}

function clearSelection() {
  selectedId = '';
  const windowMode = activeLayer === 'window';
  $('#camName').textContent = windowMode ? '选择一个沉浸窗口' : '选择一个公开摄像头';
  $('#camMeta').textContent = windowMode
    ? '从窗口列表选择，或点击地球上的蓝色窗口点。'
    : '点地球上的信号点，或从下方播放列表选择。';
  sourceLink.href = '#';
  sourceLink.setAttribute('aria-disabled', 'true');
  sourceLink.textContent = windowMode ? '查看素材来源' : '打开官方来源';
  viewer.replaceChildren();
  appendMediaBadge('none');
  const empty = document.createElement('div');
  empty.className = 'viewer-empty';
  empty.textContent = windowMode ? '沉浸窗口视频将在这里播放' : '摄像头画面将在这里播放';
  viewer.appendChild(empty);
  attribution.textContent = windowMode
    ? 'WINDOW 为预录许可视频，和 LIVE 实时摄像头分层展示。'
    : '仅展示主动公开发布的户外摄像头；画面与版权归原始提供方。';
}

function clearAll() {
  if (activeLayer !== 'live') return;
  liveCameras = [];
  all = [];
  filtered = [];
  search.value = '';
  clearSelection();
  render();
  setStatus('已清空信号源。转动地球后可重新加载当前区域。', 'live');
}

function mergeCameras(base, incoming) {
  const map = new Map();
  base.forEach(d => map.set(cameraKey(d), d));
  incoming.forEach(d => map.set(cameraKey(d), d));
  return Array.from(map.values());
}

function itemKey(d) {
  if (isWindow(d)) {
    const id = String(d && d.id || '').trim();
    if (id) return 'window:' + id;
    return 'window:' + [Number(d && d.lat).toFixed(5), Number(d && d.lng).toFixed(5), String(d && d.name || '')].join('|');
  }
  return 'cam:' + cameraKey(d);
}

function cameraKey(d) {
  const id = String(d && d.id || '').trim();
  if (id) return id;
  return [Number(d && d.lat).toFixed(5), Number(d && d.lng).toFixed(5), String(d && d.name || '')].join('|');
}

function isWindow(d) {
  return !!(d && d.kind === 'window');
}

function itemFallbackName(d) {
  return isWindow(d) ? '沉浸窗口' : '公开摄像头';
}

function itemSubLabel(d) {
  if (isWindow(d)) {
    return [cleanPlace(d.city), cleanPlace(d.country), d.category, d.license].filter(Boolean).join(' · ') || 'WINDOW 沉浸窗口';
  }
  return [mediaLabel(d), cleanPlace(d.city), cleanPlace(d.country), d.category].filter(Boolean).join(' · ') || '公开来源';
}

function cleanPlace(value) {
  const s = String(value || '').trim();
  return !s || s.toLowerCase() === 'unknown' ? '' : s;
}

function updateCenterReadout() {
  const pov = globe.pointOfView();
  centerCoords.textContent = '查询中心 · ' + formatCoord(Number(pov.lat) || 0, Number(pov.lng) || 0);
}

function focusTokyo() {
  globe.pointOfView(TOKYO, prefersReducedMotion() ? 0 : 650);
}

function zoomBy(factor) {
  const pov = globe.pointOfView();
  globe.pointOfView({
    lat: Number(pov.lat) || 0,
    lng: Number(pov.lng) || 0,
    altitude: clamp((Number(pov.altitude) || 1.5) * factor, 0.28, 4.5)
  }, prefersReducedMotion() ? 0 : 260);
}

async function toggleFullscreen(target) {
  try {
    if (document.fullscreenElement) {
      await document.exitFullscreen();
    } else if (target && target.requestFullscreen) {
      await target.requestFullscreen();
    } else {
      setStatus('当前浏览器不支持全屏 API。', 'warn');
    }
  } catch (err) {
    setStatus('无法进入全屏：' + safeMessage(err), 'warn');
  }
}

search.addEventListener('input', applySearch);
document.querySelectorAll('.filter-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    if (activeLayer !== 'live') return;
    activeMedia = btn.dataset.filter || 'all';
    document.querySelectorAll('.filter-btn').forEach(x => x.classList.toggle('active', x === btn));
    applySearch();
  });
});
modeLive.addEventListener('click', () => void switchLayer('live'));
modeWindow.addEventListener('click', () => void switchLayer('window'));
loadBtn.addEventListener('click', () => activeLayer === 'window' ? randomWindow() : loadNearby());
clearAllBtn.addEventListener('click', clearAll);
$('#resetView').addEventListener('click', focusTokyo);
$('#resetGlobe').addEventListener('click', focusTokyo);
$('#zoomIn').addEventListener('click', () => zoomBy(0.72));
$('#zoomOut').addEventListener('click', () => zoomBy(1.38));
$('#fullscreen').addEventListener('click', () => toggleFullscreen(document.documentElement));
$('#expandViewer').addEventListener('click', () => toggleFullscreen(viewer));
addEventListener('resize', sizeGlobe);
document.addEventListener('fullscreenchange', sizeGlobe);

function sizeGlobe() {
  globe.width(stage.clientWidth).height(stage.clientHeight);
  updateCenterReadout();
}

function setStatus(message, kind) {
  status.textContent = message;
  status.dataset.kind = kind || 'live';
}

function formatCoord(lat, lng) {
  const ns = lat >= 0 ? 'N' : 'S';
  const ew = lng >= 0 ? 'E' : 'W';
  return Math.abs(lat).toFixed(2) + '°' + ns + ' · ' + Math.abs(lng).toFixed(2) + '°' + ew;
}

function formatTime(value) {
  try {
    return new Intl.DateTimeFormat('zh-CN', {
      month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
      hour12: false
    }).format(new Date(value));
  } catch {
    return '';
  }
}

function prefersReducedMotion() {
  return !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
}

function clamp(v, min, max) {
  return Math.min(max, Math.max(min, v));
}

function safeMessage(err) {
  return String(err && err.message || err || '未知错误').slice(0, 160);
}

function safeHttpUrl(value) {
  try {
    const u = new URL(String(value || ''));
    return /^https?:$/.test(u.protocol) ? u.href : '';
  } catch {
    return '';
  }
}

function escapeHtml(v = '') {
  return String(v).replace(/[&<>"']/g, m => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;'
  }[m]));
}
})();