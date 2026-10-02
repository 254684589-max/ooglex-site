(() => {
'use strict';

const $ = s => document.querySelector(s);
const stage = $('#stage');
const globeEl = $('#globe');
const viewer = $('#viewer');
const playlist = $('#playlist');
const search = $('#search');
const count = $('#count');
const listCount = $('#listCount');
const status = $('#status');
const sourceLink = $('#openSource');
const attribution = $('#attribution');
const centerCoords = $('#centerCoords');
const playlistTabs = $('#playlistTabs');
const cfg = window.OOGLEX_GLOBAL_CAMS || {};
const WINDOW_CDN_BASE = String(cfg.windowCdnBase || '').replace(/\/$/, '');

const TOKYO = Object.freeze({ lat: 35.6762, lng: 139.6503, altitude: 1.45 });
let windows = [];
let filtered = [];
let selectedId = '';
let catalogSource = 'fallback';
let activeSort = 'featured';
let popularity = new Map();
let popularityLoaded = false;
let popularityPromise = null;
const reportedWindowPlays = new Set();

const globe = Globe()(globeEl)
  .width(stage.clientWidth)
  .height(stage.clientHeight)
  .globeImageUrl('../radio/vendor/earth-blue-marble.jpg')
  .backgroundColor('#05070f')
  .pointAltitude(0.015)
  .pointRadius(d => itemKey(d) === selectedId ? 0.29 : 0.20)
  .pointColor(d => itemKey(d) === selectedId ? '#ffd36b' : '#68a8ff')
  .pointLabel(d => '<b>' + escapeHtml(d.name || '沉浸窗口') + '</b><br>' + escapeHtml(itemSubLabel(d)))
  .onPointClick(d => showWindow(d, { focus: true, reveal: true }));

const controls = globe.controls();
controls.autoRotate = false;
controls.enableDamping = true;
controls.addEventListener('change', updateCenterReadout);
globe.pointOfView(TOKYO, 0);
updateCenterReadout();
void loadWindows();

async function loadWindows() {
  const candidates = [
    WINDOW_CDN_BASE ? { url: WINDOW_CDN_BASE + '/manifest.json', source: 'cdn' } : null,
    { url: './windows.json', source: 'fallback' }
  ].filter(Boolean);

  let lastError = null;
  for (const candidate of candidates) {
    try {
      const r = await fetch(candidate.url, { cache: 'no-store', headers: { Accept: 'application/json' } });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const data = await r.json();
      const normalized = (Array.isArray(data) ? data : [])
        .map(d => ({
          ...d,
          kind: 'window',
          lat: Number(d.lat),
          lng: Number(d.lng),
          video_url: resolveWindowVideoUrl(d)
        }))
        .filter(d => safeHttpUrl(d.video_url) && Number.isFinite(d.lat) && Number.isFinite(d.lng));

      if (!normalized.length) throw new Error('WINDOW 清单为空');
      windows = normalized;
      catalogSource = candidate.source;
      applySearch();
      void loadPopularity();
      setStatus(
        'WINDOW 窗口库已加载 · ' + windows.length + ' 个窗口' +
        (candidate.source === 'cdn' ? ' · Ooglex R2/CDN' : ' · 本地备用清单'),
        candidate.source === 'cdn' ? 'window' : 'warn'
      );
      return;
    } catch (err) {
      lastError = err;
    }
  }

  windows = [];
  filtered = [];
  render();
  setStatus('WINDOW 视频库加载失败：' + safeMessage(lastError), 'error');
}

function applySearch() {
  const q = String(search.value || '').trim().toLowerCase();
  const rows = !q ? windows.slice() : windows.filter(d => {
    const haystack = [
      d.name, d.name_zh, d.original_title, d.city_zh, d.city, d.country_zh, d.country, d.category, d.license, d.author
    ].map(v => String(v || '').toLowerCase()).join(' ');
    return haystack.includes(q);
  });
  filtered = sortWindows(rows);
  render();
}

function sortWindows(rows) {
  const out = rows.slice();
  if (activeSort === 'latest') {
    out.sort((a, b) =>
      catalogTimestamp(b) - catalogTimestamp(a) ||
      Number(b.quality_score || 0) - Number(a.quality_score || 0) ||
      String(a.name || '').localeCompare(String(b.name || ''))
    );
  } else if (activeSort === 'popular') {
    out.sort((a, b) => {
      const pa = popularityFor(a);
      const pb = popularityFor(b);
      return pb.plays - pa.plays ||
        pb.plays30d - pa.plays30d ||
        Number(b.quality_score || 0) - Number(a.quality_score || 0) ||
        String(a.name || '').localeCompare(String(b.name || ''));
    });
  }
  return out;
}

async function loadPopularity() {
  if (popularityLoaded || popularityPromise || !WINDOW_CDN_BASE) return popularityPromise;
  popularityPromise = (async () => {
    try {
      const r = await fetch(WINDOW_CDN_BASE + '/stats/popular?days=7&limit=500', {
        cache: 'no-store',
        headers: { Accept: 'application/json' }
      });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const data = await r.json();
      const rows = Array.isArray(data && data.items) ? data.items : [];
      popularity = new Map(rows.map(x => [String(x.id || ''), {
        plays: Number(x.plays || 0),
        plays30d: Number(x.plays30d || 0),
        total: Number(x.total || 0),
        lastPlayedAt: x.lastPlayedAt || null
      }]));
      popularityLoaded = true;
      if (activeSort === 'popular') applySearch();
    } catch (err) {
      popularityLoaded = false;
      if (activeSort === 'popular') {
        setStatus('热门统计暂不可用，当前仍可正常浏览精选 WINDOW。', 'warn');
      }
    } finally {
      popularityPromise = null;
    }
  })();
  return popularityPromise;
}

function popularityFor(d) {
  return popularity.get(String(d && d.id || '')) || { plays: 0, plays30d: 0, total: 0, lastPlayedAt: null };
}

function catalogTimestamp(d) {
  for (const value of [d && d.catalog_added_at, d && d.source_updated_at, d && d.source_published_at]) {
    const ts = Date.parse(String(value || ''));
    if (Number.isFinite(ts)) return ts;
  }
  return 0;
}

function listSubLabel(d) {
  const base = itemSubLabel(d);
  if (activeSort === 'popular') {
    const p = popularityFor(d);
    return (popularityLoaded ? '🔥 7天 ' + p.plays + ' 次 · ' : '') + base;
  }
  if (activeSort === 'latest') {
    const ts = catalogTimestamp(d);
    return (ts ? '新加入 ' + new Date(ts).toISOString().slice(0, 10) + ' · ' : '较早收录 · ') + base;
  }
  return base;
}

function render() {
  globe.pointsData(filtered);
  count.textContent = filtered.length + ' 个 WINDOW';
  listCount.textContent = filtered.length + ' 个窗口';

  playlist.replaceChildren();
  if (!filtered.length) {
    const empty = document.createElement('div');
    empty.className = 'empty-list';
    empty.textContent = windows.length ? '没有匹配的 WINDOW。' : '正在加载 WINDOW 窗口库…';
    playlist.appendChild(empty);
    return;
  }

  const frag = document.createDocumentFragment();
  for (const d of filtered) {
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'window-row' + (itemKey(d) === selectedId ? ' active' : '');
    row.setAttribute('role', 'option');
    row.setAttribute('aria-selected', itemKey(d) === selectedId ? 'true' : 'false');
    row.dataset.key = itemKey(d);

    const dot = document.createElement('span');
    dot.className = 'window-dot';

    const main = document.createElement('span');
    main.className = 'window-main';
    const name = document.createElement('span');
    name.className = 'window-name';
    name.textContent = d.name || '沉浸窗口';
    const sub = document.createElement('span');
    sub.className = 'window-sub';
    sub.textContent = listSubLabel(d);
    main.append(name, sub);
    row.append(dot, main);
    row.addEventListener('click', () => showWindow(d, { focus: true }));
    frag.appendChild(row);
  }
  playlist.appendChild(frag);
}

function showWindow(d, options = {}) {
  if (!d) return;
  selectedId = itemKey(d);

  $('#windowName').textContent = d.name || '沉浸窗口';
  $('#windowMeta').textContent = itemSubLabel(d);

  viewer.replaceChildren();
  const badge = document.createElement('div');
  badge.className = 'media-badge';
  badge.id = 'mediaBadge';
  badge.textContent = 'WINDOW';
  badge.dataset.empty = 'false';
  viewer.appendChild(badge);

  const video = document.createElement('video');
  video.src = d.video_url;
  video.autoplay = true;
  video.muted = true;
  video.loop = true;
  video.playsInline = true;
  video.controls = true;
  video.preload = 'metadata';
  video.addEventListener('error', () => {
    setStatus('该 WINDOW 暂时无法播放，可查看原始素材来源。', 'warn');
  });
  armPlayReport(video, d);
  viewer.appendChild(video);

  const source = safeHttpUrl(d.source_url);
  if (source) {
    sourceLink.href = source;
    sourceLink.removeAttribute('aria-disabled');
  } else {
    sourceLink.href = '#';
    sourceLink.setAttribute('aria-disabled', 'true');
  }

  const bits = [];
  if (d.author) bits.push('作者：' + stripHtml(d.author));
  if (d.license) bits.push('许可：' + d.license);
  bits.push(catalogSource === 'cdn' ? '播放：Ooglex R2/CDN' : '播放：备用源');
  attribution.textContent = bits.join(' · ');

  if (options.focus) {
    globe.pointOfView({
      lat: Number(d.lat),
      lng: Number(d.lng),
      altitude: Math.min(Number(globe.pointOfView().altitude) || 1.45, 1.15)
    }, prefersReducedMotion() ? 0 : 650);
  }

  render();
  if (options.reveal) {
    const row = playlist.querySelector('[data-key="' + cssEscape(selectedId) + '"]');
    if (row) row.scrollIntoView({ block: 'nearest', behavior: prefersReducedMotion() ? 'auto' : 'smooth' });
  }
}

function armPlayReport(video, d) {
  let fired = false;
  const check = () => {
    if (fired || Number(video.currentTime || 0) < 8) return;
    fired = true;
    void reportPlay(d);
  };
  video.addEventListener('timeupdate', check);
}

async function reportPlay(d) {
  const id = String(d && d.id || '');
  if (!WINDOW_CDN_BASE || catalogSource !== 'cdn' || !/^r2-(?:seed-)?[a-z0-9]{8,32}$/i.test(id)) return;
  const day = new Date().toISOString().slice(0, 10);
  const memoryKey = id + '|' + day;
  if (reportedWindowPlays.has(memoryKey)) return;
  reportedWindowPlays.add(memoryKey);

  const storageKey = 'ooglex-window-play-v1:' + memoryKey;
  try {
    if (localStorage.getItem(storageKey)) return;
    localStorage.setItem(storageKey, '1');
  } catch {}

  try {
    const r = await fetch(WINDOW_CDN_BASE + '/stats/play', {
      method: 'POST',
      mode: 'cors',
      keepalive: true,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id })
    });
    if (r.ok) {
      popularityLoaded = false;
      void loadPopularity();
    }
  } catch {}
}

function randomWindow() {
  const pool = filtered.length ? filtered : windows;
  if (!pool.length) return;
  const d = pool[Math.floor(Math.random() * pool.length)];
  showWindow(d, { focus: true, reveal: true });
}

function resolveWindowVideoUrl(d) {
  const direct = safeHttpUrl(d && d.video_url);
  if (direct) return direct;

  const key = String(d && d.r2_key || '').replace(/^\/+/, '');
  if (!WINDOW_CDN_BASE || !/^media\/[a-z0-9][a-z0-9._-]{2,160}$/i.test(key)) return '';
  return WINDOW_CDN_BASE + '/' + key;
}

function itemKey(d) {
  const id = String(d && d.id || '').trim();
  if (id) return 'window:' + id;
  return 'window:' + [
    Number(d && d.lat).toFixed(5),
    Number(d && d.lng).toFixed(5),
    String(d && d.name || '')
  ].join('|');
}

function itemSubLabel(d) {
  return [
    cleanPlace(d.city_zh || d.city),
    cleanPlace(d.country_zh || d.country),
    d.category,
    technicalLabel(d),
    d.license
  ].filter(Boolean).join(' · ') || 'WINDOW 沉浸窗口';
}

function technicalLabel(d) {
  const width = Number(d && d.width || 0);
  const height = Number(d && d.height || 0);
  const duration = Number(d && d.duration_seconds || 0);
  const parts = [];
  if (width >= 3840 && height >= 2160) parts.push('4K');
  else if (width >= 1920 && height >= 1080) parts.push('1080p');
  else if (width >= 1280 && height >= 720) parts.push('720p');
  else if (width && height) parts.push(width + '×' + height);
  if (duration > 0) {
    const total = Math.round(duration);
    const mm = Math.floor(total / 60);
    const ss = String(total % 60).padStart(2, '0');
    parts.push(mm ? mm + ':' + ss : total + '秒');
  }
  return parts.join(' · ');
}

function cleanPlace(value) {
  const s = String(value || '').trim();
  return !s || s.toLowerCase() === 'unknown' ? '' : s;
}

function updateCenterReadout() {
  const pov = globe.pointOfView();
  centerCoords.textContent = '视图中心 · ' + formatCoord(Number(pov.lat) || 0, Number(pov.lng) || 0);
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

function sizeGlobe() {
  globe.width(stage.clientWidth).height(stage.clientHeight);
  updateCenterReadout();
}

function setStatus(message, kind) {
  status.textContent = message;
  status.dataset.kind = kind || 'window';
}

function formatCoord(lat, lng) {
  const ns = lat >= 0 ? 'N' : 'S';
  const ew = lng >= 0 ? 'E' : 'W';
  return Math.abs(lat).toFixed(2) + '°' + ns + ' · ' + Math.abs(lng).toFixed(2) + '°' + ew;
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

function stripHtml(value) {
  const el = document.createElement('div');
  el.innerHTML = String(value || '');
  return (el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 240);
}

function escapeHtml(v = '') {
  return String(v).replace(/[&<>"']/g, m => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;'
  }[m]));
}

function cssEscape(value) {
  if (window.CSS && typeof window.CSS.escape === 'function') return window.CSS.escape(value);
  return String(value).replace(/["\\]/g, '\\$&');
}

search.addEventListener('input', applySearch);
playlistTabs.addEventListener('click', event => {
  const btn = event.target.closest('.sort-btn');
  if (!btn) return;
  activeSort = btn.dataset.sort || 'featured';
  playlistTabs.querySelectorAll('.sort-btn').forEach(x => x.classList.toggle('active', x === btn));
  if (activeSort === 'popular') void loadPopularity();
  applySearch();
});
$('#randomWindow').addEventListener('click', randomWindow);
$('#randomTop').addEventListener('click', randomWindow);
$('#resetView').addEventListener('click', focusTokyo);
$('#resetGlobe').addEventListener('click', focusTokyo);
$('#zoomIn').addEventListener('click', () => zoomBy(0.72));
$('#zoomOut').addEventListener('click', () => zoomBy(1.38));
$('#fullscreen').addEventListener('click', () => toggleFullscreen(document.documentElement));
$('#expandViewer').addEventListener('click', () => toggleFullscreen(viewer));
addEventListener('resize', sizeGlobe);
document.addEventListener('fullscreenchange', sizeGlobe);
})();
