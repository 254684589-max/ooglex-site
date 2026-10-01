(() => {
'use strict';

const $ = s => document.querySelector(s);
const stage = $('#stage');
const globeEl = $('#globe');
const viewer = $('#viewer');
const playlist = $('#playlist');
const count = $('#count');
const listCount = $('#listCount');
const search = $('#search');
const status = $('#status');
const loadBtn = $('#loadNearby');
const attribution = $('#attribution');
const sourceLink = $('#openSource');
const accumulate = $('#accumulate');
const centerCoords = $('#centerCoords');
const cfg = window.OOGLEX_GLOBAL_CAMS || {};
const API_BASE = String(cfg.apiBase || '').replace(/\/$/, '');

const TOKYO = Object.freeze({ lat: 35.6762, lng: 139.6503, altitude: 1.45 });
const PAGE_SIZE = 50;
const MAX_REGION_CAMERAS = 1000;

let all = [];
let filtered = [];
let selectedId = '';
let mode = API_BASE ? 'live' : 'demo';
let loading = false;
let rowsById = new Map();

const globe = Globe()(globeEl)
  .width(stage.clientWidth)
  .height(stage.clientHeight)
  .globeImageUrl('../radio/vendor/earth-blue-marble.jpg')
  .backgroundColor('#05070f')
  .pointAltitude(0.015)
  .pointRadius(d => cameraKey(d) === selectedId ? 0.29 : (d.playable ? 0.21 : 0.16))
  .pointColor(d => cameraKey(d) === selectedId ? '#ffd36b' : (d.playable ? '#4ee7b7' : '#d8e2f2'))
  .pointLabel(d => '<b>' + escapeHtml(d.name || '公开摄像头') + '</b><br>' + escapeHtml([cleanPlace(d.city), cleanPlace(d.country)].filter(Boolean).join(' · ')))
  .onPointClick(d => showCamera(d, { focus: true, reveal: true }));

const controls = globe.controls();
controls.autoRotate = false;
controls.enableDamping = true;
controls.addEventListener('change', updateCenterReadout);
globe.pointOfView(TOKYO, 0);
updateCenterReadout();

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
    all = Array.isArray(data) ? data : [];
    filtered = all.slice();
    mode = 'demo';
    setStatus('演示数据模式。真实 Global Cams API 尚未配置。', 'warn');
    render();
  } catch (err) {
    all = [];
    filtered = [];
    setStatus('演示数据加载失败。', 'error');
    render();
    console.error(err);
  }
}

async function loadNearby(options = {}) {
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
      setStatus(
        '正在加载当前区域：' + Math.min(offset, target) + ' / ' + target +
        (total > MAX_REGION_CAMERAS ? '（免费接口上限 ' + MAX_REGION_CAMERAS + '）' : ''),
        'live'
      );

      if (target === 0) break;
    }

    if (accumulate.checked && !options.initial) {
      all = mergeCameras(all, region);
    } else {
      all = region;
    }

    mode = 'live';
    applySearch();

    if (selectedId && !all.some(d => cameraKey(d) === selectedId)) clearSelection();

    const shown = region.length;
    const totalText = total == null ? shown : total;
    if (partialError) {
      setStatus('已加载 ' + shown + ' 个信号源，但后续分页失败：' + safeMessage(partialError), 'warn');
    } else if (!shown) {
      setStatus('当前查询中心 250 公里范围内没有返回可用摄像头。', 'warn');
    } else if (totalText > MAX_REGION_CAMERAS) {
      setStatus('区域共有 ' + totalText + ' 个摄像头；免费接口本次显示前 ' + MAX_REGION_CAMERAS + ' 个。数据源 Windy Webcams API。', 'warn');
    } else {
      setStatus(
        '当前区域已完整载入 ' + shown + ' / ' + totalText + ' 个公开摄像头' +
        (accumulate.checked && !options.initial ? ' · 已累计 ' + all.length + ' 个点位' : '') +
        ' · 数据源 Windy Webcams API' +
        (asOf ? ' · ' + formatTime(asOf) : ''),
        'live'
      );
    }
  } catch (err) {
    setStatus('真实摄像头加载失败：' + safeMessage(err), 'error');
  } finally {
    loading = false;
    loadBtn.disabled = false;
    loadBtn.textContent = '加载当前区域';
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
  filtered = !q ? all.slice() : all.filter(d => {
    const haystack = [d.name, d.city, d.country, d.category, d.source].filter(Boolean).join(' ').toLowerCase();
    return haystack.includes(q);
  });
  render();
}

function render() {
  globe.pointsData(filtered);
  count.textContent = filtered.length === all.length
    ? all.length + (mode === 'demo' ? ' 个演示点位' : ' 个公开点位')
    : filtered.length + ' / ' + all.length + ' 个点位';
  listCount.textContent = filtered.length === all.length
    ? all.length + ' 个信号源'
    : filtered.length + ' / ' + all.length + ' 个信号源';
  renderPlaylist();
}

function renderPlaylist() {
  playlist.replaceChildren();
  rowsById = new Map();

  if (!filtered.length) {
    const empty = document.createElement('div');
    empty.className = 'empty-list';
    empty.textContent = all.length
      ? '没有匹配搜索条件的摄像头。'
      : '当前没有已加载信号源。转动地球后点击“加载当前区域”。';
    playlist.appendChild(empty);
    return;
  }

  const frag = document.createDocumentFragment();
  filtered.forEach(d => {
    const id = cameraKey(d);
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'cam-row' + (d.playable ? ' playable' : '') + (id === selectedId ? ' active' : '');
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
    name.textContent = d.name || '公开摄像头';
    const sub = document.createElement('span');
    sub.className = 'cam-sub';
    sub.textContent = [cleanPlace(d.city), cleanPlace(d.country), d.category].filter(Boolean).join(' · ') || '公开来源';

    main.append(name, sub);
    row.append(dot, main);
    row.addEventListener('click', () => showCamera(d, { focus: true, reveal: false }));
    rowsById.set(id, row);
    frag.appendChild(row);
  });

  playlist.appendChild(frag);
}

function showCamera(d, options = {}) {
  selectedId = cameraKey(d);
  $('#camName').textContent = d.name || '公开摄像头';
  $('#camMeta').textContent = [cleanPlace(d.city), cleanPlace(d.country), d.category, d.source].filter(Boolean).join(' · ');

  const sourceUrl = safeHttpUrl(d.source_url);
  sourceLink.href = sourceUrl || '#';
  sourceLink.setAttribute('aria-disabled', sourceUrl ? 'false' : 'true');
  viewer.replaceChildren();

  if (d.embed_url && safeHttpUrl(d.embed_url)) {
    const frame = document.createElement('iframe');
    frame.src = d.embed_url;
    frame.title = d.name || '公开摄像头播放器';
    frame.allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen';
    frame.allowFullscreen = true;
    frame.referrerPolicy = 'strict-origin-when-cross-origin';
    viewer.appendChild(frame);
  } else if (d.preview_url && safeHttpUrl(d.preview_url)) {
    const img = document.createElement('img');
    img.src = d.preview_url;
    img.alt = d.name || '公开摄像头预览';
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
      : '该摄像头当前没有可嵌入画面，请打开官方来源。';
    viewer.appendChild(box);
  }

  if (d.source === 'Windy Webcams API') {
    attribution.innerHTML = 'Webcams provided by <a href="https://www.windy.com/" target="_blank" rel="noopener">windy.com</a> — <a href="https://www.windy.com/webcams/add" target="_blank" rel="noopener">add a webcam</a>';
  } else {
    attribution.textContent = d.demo
      ? '演示数据，不代表当前真实直播状态。'
      : '公开来源；画面版权与可用性归原始提供方。';
  }

  render();
  if (options.reveal) {
    const row = rowsById.get(selectedId);
    if (row) row.scrollIntoView({ block: 'nearest', behavior: prefersReducedMotion() ? 'auto' : 'smooth' });
  }

  if (options.focus && Number.isFinite(+d.lat) && Number.isFinite(+d.lng)) {
    globe.pointOfView(
      { lat: +d.lat, lng: +d.lng, altitude: 0.72 },
      prefersReducedMotion() ? 0 : 650
    );
  }
}

function clearSelection() {
  selectedId = '';
  $('#camName').textContent = '选择一个公开摄像头';
  $('#camMeta').textContent = '点地球上的信号点，或从下方播放列表选择。';
  sourceLink.href = '#';
  sourceLink.setAttribute('aria-disabled', 'true');
  viewer.replaceChildren();
  const empty = document.createElement('div');
  empty.className = 'viewer-empty';
  empty.textContent = '摄像头画面将在这里播放';
  viewer.appendChild(empty);
  attribution.textContent = '仅展示主动公开发布的户外摄像头；画面与版权归原始提供方。';
}

function clearAll() {
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

function cameraKey(d) {
  const id = String(d && d.id || '').trim();
  if (id) return id;
  return [Number(d && d.lat).toFixed(5), Number(d && d.lng).toFixed(5), String(d && d.name || '')].join('|');
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
loadBtn.addEventListener('click', () => loadNearby());
$('#clearAll').addEventListener('click', clearAll);
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