/* 环球TV · 转动地球看世界
   真实卫星地球（自托管纹理）+ 中央圆圈"框选"观看 + 全球/中国电视台（iptv-org 公开直播源，HTTPS 直连，HLS 播放）
   与「环球电波」同构：同源托管频道库 → 国内 / 手机 / 微信直达，不依赖外网 API。 */
(() => {
'use strict';
const $ = id => document.getElementById(id);
const video = $('video');
video.playsInline = true;
video.setAttribute('playsinline', '');
video.setAttribute('webkit-playsinline', '');

/* ---------------- 星空背景 ---------------- */
(function stars(){
  const cv = $('stars'), cx = cv.getContext('2d');
  function draw(){
    cv.width = innerWidth; cv.height = innerHeight;
    const n = Math.min(240, (innerWidth * innerHeight) / 9000 | 0);
    cx.clearRect(0, 0, cv.width, cv.height);
    for (let i = 0; i < n; i++){
      const x = Math.random() * cv.width, y = Math.random() * cv.height, r = Math.random() * 1.3;
      cx.fillStyle = `rgba(255,255,255,${0.15 + Math.random() * 0.6})`;
      cx.beginPath(); cx.arc(x, y, r, 0, 6.29); cx.fill();
    }
  }
  draw();
  addEventListener('resize', draw);
})();

/* ---------------- 状态提示 ---------------- */
const statusEl = $('status');
let statusTimer;
function status(msg, spin, autohide){
  clearTimeout(statusTimer);
  statusEl.style.display = 'block';
  statusEl.innerHTML = (spin ? '<span class="spin"></span>' : '') + msg;
  if (autohide) statusTimer = setTimeout(hideStatus, autohide);
}
function hideStatus(){ statusEl.style.display = 'none'; }

if (typeof Globe !== 'function'){
  status('地球组件加载失败，请刷新页面重试。', false);
  return;
}

/* ---------------- 频道数据工具 ---------------- */
function playableUrl(u){
  return typeof u === 'string' && u.startsWith('https://')
    && /\.(m3u8|mp4)(\?|$)/i.test(u);
}
function playable(s){
  return playableUrl(s.url)
    && isFinite(s.lat) && isFinite(s.lng)
    && Math.abs(s.lat) <= 90 && Math.abs(s.lng) <= 180
    && !(s.lat === 0 && s.lng === 0);
}
function dedupe(list){
  const seen = new Set(), out = [];
  for (const s of list){ if (!seen.has(s.url)){ seen.add(s.url); out.push(s); } }
  return out;
}
function dist(aLat, aLng, bLat, bLng){
  const toR = x => x * Math.PI / 180, R = 6371;
  const dLat = toR(bLat - aLat), dLng = toR(bLng - aLng);
  const s = Math.sin(dLat / 2) ** 2 + Math.cos(toR(aLat)) * Math.cos(toR(bLat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}
function nearest(lat, lng){
  let best = null, bd = Infinity;
  for (const s of allStations){ const d = dist(lat, lng, s.lat, s.lng); if (d < bd){ bd = d; best = s; } }
  return { st: best, d: bd };
}

/* ---------------- 地球 ---------------- */
let world, current = null, allStations = [], rotating = false, cinematic = false;
let HLS_PROXY = '';   // 站长部署 HLS 代理后填入 apps/tv/proxy.json；用于 Chrome/安卓 hls.js 补 CORS（Safari 原生播放不走代理）
let proxying = false; // 当前台是否已切到代理（避免重复切、并用于状态标识）
const SNAP_KM = 900;   // 吸附半径：圆圈中心此范围内的最近频道会被"吸"到正中并播放
const broken = new Set();          // 本次会话中连不上的频道（自动跳过）
let selectPool = [], poolIdx = 0, watchdog = null;   // 失败自动跳到附近可用频道

function initGlobe(){
  // waitForGlobeReady:false —— 不等贴图下载完就先显示地球（深蓝占位球 + 蓝点），慢网络下不再黑屏
  world = Globe({ animateIn: true, waitForGlobeReady: false })($('globe'))
    .backgroundColor('rgba(0,0,0,0)')
    .width(innerWidth).height(innerHeight)
    .globeImageUrl('vendor/earth-blue-marble.jpg')
    .bumpImageUrl('vendor/earth-topology.jpg')
    .showAtmosphere(true).atmosphereColor('#9ec9ff').atmosphereAltitude(0.28)
    .pointsData([])
    .pointLat('lat').pointLng('lng')
    .pointColor(d => d === current ? '#fff3a0' : '#4dc3ff')
    .pointAltitude(d => d === current ? 0.02 : 0.01)
    .pointRadius(d => d === current ? 0.55 : 0.24)
    .pointResolution(6)
    .pointLabel(d => `<div style="background:rgba(8,12,26,.94);border:1px solid rgba(120,150,220,.35);
        padding:6px 10px;border-radius:8px;font-family:sans-serif;color:#e9f2ff;font-size:12px;max-width:220px">
        <b>${d.name}</b><br><span style="color:#93a4c8">${[d.country, d.state].filter(Boolean).join(' · ') || ''}</span></div>`)
    .onPointClick(d => { setRegion(d.lat, d.lng); showTab('region'); playAt(d, true); })
    .ringsData([])
    .ringColor(() => t => `rgba(77,195,255,${1 - t})`)
    .ringMaxRadius(3.4).ringPropagationSpeed(1.7).ringRepeatPeriod(620);

  enhanceGlobe(world);

  // 贴图下载完之前先给地球一个深海蓝底色：慢网络下也能立刻看到地球轮廓，而不是黑屏
  try{
    const gm = world.globeMaterial();
    if (gm && gm.color && gm.color.setHex){
      gm.color.setHex(0x14386b);
      (function unveil(){
        const ok = gm.map && gm.map.image && (gm.map.image.complete || gm.map.image.naturalWidth > 0);
        if (ok){ if (gm.color && gm.color.setHex) gm.color.setHex(0xffffff); gm.needsUpdate = true; }
        else setTimeout(unveil, 120);
      })();
    }
  }catch(e){}

  const c = world.controls();
  c.autoRotate = false; c.autoRotateSpeed = 0.34;
  c.enableDamping = false;          // 关掉松手后的惯性滑行，避免"滑过"信号源
  c.rotateSpeed = 0.85;
  c.minDistance = 180; c.maxDistance = 520;
  world.pointOfView({ lat: 30, lng: 110, altitude: 2.2 }, 0);

  // 拖动中：实时反馈圆圈是否已罩住频道（变亮 + 提示台名），不播放
  let liveThrottle = 0;
  c.addEventListener('change', () => {
    const now = performance.now();
    if (now - liveThrottle < 80 || !allStations.length) return;
    liveThrottle = now;
    const pov = world.pointOfView();
    const { st, d } = nearest(pov.lat, pov.lng);
    const ok = !!st && d <= SNAP_KM;
    setReticleLive(ok);
    $('rtip').textContent = ok ? '松手观看：' + st.name : '拖动地球，把电视台转进圈内即可观看';
  });
  // 松手：自动吸附到最近频道（精准对准圆圈中心）并播放
  c.addEventListener('end', () => tuneCenter(true));

  addEventListener('resize', () => world.width(innerWidth).height(innerHeight));

  cinematicIntro();
}

/* 电影开场运镜：低轨贴地切入 → 低空掠过 → 平滑拉远到可操作的地球视角；拖动即可跳过。 */
function cinematicIntro(){
  try{
    const c = world.controls();
    const gm = world.globeMaterial();
    const savedMin = c.minDistance;
    cinematic = true;
    c.minDistance = 104;                                  // 临时放开，允许贴近地表的低轨镜头
    const intro = $('intro'), player = $('player');
    if (intro) intro.style.display = 'none';
    if (player) player.style.display = 'none';
    world.pointOfView({ lat: 8, lng: 88, altitude: 0.42 }, 0);   // 先就位低轨，静候贴图

    function run(){
      world.pointOfView({ lat: 20, lng: 103, altitude: 0.62 }, 1600);                     // 低空掠过
      const t2 = setTimeout(() => world.pointOfView({ lat: 30, lng: 110, altitude: 2.2 }, 2600), 1600); // 拉远到全球
      function done(){
        if (!cinematic) return;
        cinematic = false;
        c.minDistance = savedMin;
        c.removeEventListener('start', done);
        clearTimeout(t2); clearTimeout(timer);
        revealIntro();
      }
      const timer = setTimeout(done, 4400);
      c.addEventListener('start', done);                  // 用户一拖动就跳过运镜
    }

    let waited = 0;                                        // 等日面贴图（最多兜底 4s）
    (function waitTex(){
      const ready = gm.map && gm.map.image && (gm.map.image.complete || gm.map.image.naturalWidth > 0);
      if (ready || waited >= 4000) run();
      else { waited += 90; setTimeout(waitTex, 90); }
    })();
  }catch(e){ cinematic = false; revealIntro(); }
}
function revealIntro(){
  const player = $('player');
  if (player && regionList.length) player.style.display = 'flex';   // 运镜结束再亮出频道面板
  const el = $('intro'); if (!el) return;
  el.style.display = '';                                  // 恢复 CSS 默认布局
  el.style.opacity = '0';
  el.style.transition = 'opacity .7s ease';
  requestAnimationFrame(() => { el.style.opacity = '1'; });
}

/* 让地球更精细逼真：海洋镜面高光 + 夜面城市灯 + 更强地形起伏 + 各向异性高清过滤 + 电影级色调 */
function enhanceGlobe(world){
  const gm = world.globeMaterial();
  gm.bumpScale = 15;

  let maxAniso = 8;
  try{
    const r = world.renderer();
    maxAniso = r.capabilities.getMaxAnisotropy() || 8;
    r.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    if ('toneMapping' in r){ r.toneMapping = 4 /* ACESFilmicToneMapping */; r.toneMappingExposure = 1.18; }
  }catch(e){}

  function texFromImg(url, Ctor, colorSpace, cb){
    const img = new Image();
    img.onload = () => { try{
      const t = new Ctor(img);
      if (colorSpace) t.colorSpace = colorSpace;
      t.anisotropy = maxAniso; t.needsUpdate = true; cb(t);
    }catch(e){} };
    img.src = url;
  }

  (function apply(){
    if (!gm.map){ return setTimeout(apply, 60); }
    const Ctor = gm.map.constructor, cs = gm.map.colorSpace;
    gm.map.anisotropy = maxAniso; gm.map.needsUpdate = true;
    if (gm.bumpMap){ gm.bumpMap.anisotropy = maxAniso; gm.bumpMap.needsUpdate = true; }

    texFromImg('vendor/earth-water.jpg', Ctor, null, t => {
      gm.specularMap = t;
      if (gm.specular && gm.specular.setHex) gm.specular.setHex(0x2b3f66);
      gm.shininess = 20; gm.needsUpdate = true;
    });
    texFromImg('vendor/earth-night.jpg', Ctor, cs, t => {
      if ('emissiveMap' in gm){
        gm.emissiveMap = t;
        if (gm.emissive && gm.emissive.setHex) gm.emissive.setHex(0xffdd88);
        gm.emissiveIntensity = 1.0; gm.needsUpdate = true;
      }
    });
  })();

  try{
    const lights = world.lights ? world.lights() : null;
    let sun = null;
    if (lights && lights.length){
      lights.forEach(l => {
        if (/Ambient|Hemisphere/i.test(l.type)) l.intensity = 1.0;
        if (/Directional|Point/i.test(l.type)){ l.intensity = 1.45; sun = l; }
      });
      world.lights(lights);
    }
    if (sun && sun.position && world.camera){
      const cam = world.camera();
      const TH = 0.34, cosT = Math.cos(TH), sinT = Math.sin(TH);
      (function follow(){
        const p = cam.position;
        sun.position.set(p.x * cosT - p.z * sinT, p.y * 1.05 + 25, p.x * sinT + p.z * cosT);
        requestAnimationFrame(follow);
      })();
    }
  }catch(e){}
}

function setStations(list){ world.pointsData(list); }
function refreshHighlight(){
  world.pointColor(d => d === current ? '#fff3a0' : '#4dc3ff')
       .pointRadius(d => d === current ? 0.55 : 0.24)
       .pointAltitude(d => d === current ? 0.02 : 0.01);
}
function setReticleLive(on){ $('reticle').classList.toggle('live', !!on); }

/* 把圆圈中心最近的频道设为当前（doPlay 为真则播放） */
function tuneCenter(doPlay){
  if (!allStations.length) return;
  const pov = world.pointOfView();
  const { st, d } = nearest(pov.lat, pov.lng);
  if (!st || d > SNAP_KM){ setReticleLive(false); return; }
  setReticleLive(true);
  if (doPlay){
    setRegion(st.lat, st.lng);
    showTab('region');
    playAt(st, true);
  } else {
    focus(st, { fly: !cinematic, play: false });
  }
}

/* ---------------- HLS / 视频播放 ---------------- */
let hls = null;
function detachHls(){
  if (hls){ try{ hls.destroy(); }catch(e){} hls = null; }
  try{ video.removeAttribute('src'); video.load(); }catch(e){}   // 彻底复位，避免切台时残留旧源触发误报
}
function attachStream(url){
  detachHls();
  try{ video.pause(); }catch(e){}
  proxying = false;                    // 新台从直连开始
  const isHls = /\.m3u8(\?|$)/i.test(url);
  const nativeHls = video.canPlayType('application/vnd.apple.mpegurl');
  if (isHls && !nativeHls && window.Hls && Hls.isSupported()){
    startHls(url, false);              // 先直连（快，跟最开始一样）；连不上再走代理
  } else {
    video.src = url;                   // Safari 原生 HLS，或 mp4 直链
    const p = video.play(); if (p && p.catch) p.catch(() => {});
  }
}
// 切到代理重试当前台（供 hls 错误 和 看门狗超时 共用）；返回是否成功发起
function switchToProxy(url){
  if (!HLS_PROXY || proxying) return false;
  proxying = true;
  setState('load', '直连不通，改走代理…');
  startHls(url, true);
  armWatchdog();
  return true;
}
/* 直连优先、代理兜底：
   viaProxy=false 先直连——能直连的台不绕境外代理，保持原本的速度；
   直连报网络/CORS 致命错误且配了代理 → 自动改走代理再试一次（多半是跨域被拦）；
   代理也不行才跳台。真正的死台靠 error 事件快速跳走，不靠硬掐超时。 */
function startHls(url, viaProxy){
  detachHls();
  const src = (viaProxy && HLS_PROXY) ? (HLS_PROXY + '/?url=' + encodeURIComponent(url)) : url;
  hls = new Hls({ maxBufferLength: 12, liveSyncDurationCount: 3,
    manifestLoadingTimeOut: 10000, manifestLoadingMaxRetry: 1,
    levelLoadingTimeOut: 10000, levelLoadingMaxRetry: 2,
    fragLoadingTimeOut: 14000, fragLoadingMaxRetry: 2 });
  let netRetry = 0;
  hls.loadSource(src);
  hls.attachMedia(video);
  hls.on(Hls.Events.ERROR, (evt, data) => {
    if (!data || !data.fatal) return;
    if (data.type === Hls.ErrorTypes.NETWORK_ERROR){
      if (!viaProxy && switchToProxy(url)) return;   // 直连不通 → 改走代理救一下
      if (netRetry++ < 1){ try{ hls.startLoad(); }catch(e){ hop('信号中断'); } }
      else hop('连不上（源已失效或无跨域许可）');
    }
    else if (data.type === Hls.ErrorTypes.MEDIA_ERROR){ try{ hls.recoverMediaError(); }catch(e){ hop('解码失败'); } }
    else hop('该台无法播放');
  });
  const p = video.play();
  if (p && p.catch) p.catch(() => {});
}

/* 选中一个频道：高亮、涟漪、面板、（可选）飞过去、（可选）播放 */
function focus(st, opt){
  opt = opt || {};
  current = st;
  refreshHighlight();
  setReticleLive(true);
  if (opt.fly){
    const alt = world.pointOfView().altitude;
    world.pointOfView({ lat: st.lat, lng: st.lng, altitude: alt }, 450);
  }
  if (opt.play){
    world.ringsData([st]);
    showPlayer(st);
    attachStream(st.url);
  } else {
    world.ringsData([]);
    $('rtip').textContent = '松手 / 点击即可观看：' + st.name;
  }
  afterCurrentChanged();
}

/* 播放某频道，并围绕它建一个"就近备选池"：连不上时自动跳到附近可用频道 */
function playAt(st, fly){
  selectPool = allStations
    .map(s => ({ s, d: dist(st.lat, st.lng, s.lat, s.lng) }))
    .filter(x => !broken.has(x.s.url))
    .sort((a, b) => a.d - b.d)
    .slice(0, 14)
    .map(x => x.s);
  selectPool = [st].concat(selectPool.filter(s => s !== st));
  poolIdx = 0;
  focus(st, { fly: fly, play: true });
  armWatchdog();
}
function armWatchdog(){
  clearTimeout(watchdog);
  // 直连超时（境外台常见）：先别急着跳台——若有代理没试过，改走代理再等；否则才跳台
  watchdog = setTimeout(() => {
    if (!(video.paused || video.readyState < 2)) return;   // 已在播，无需处理
    if (current && switchToProxy(current.url)) return;      // 直连超时 → 转代理
    hop('连接超时');
  }, proxying ? 12000 : 9000);   // 直连阶段 9s 就转代理；代理阶段给足 12s
}
const MAX_HOPS = 5;   // 自动跳台上限：这一带都连不上时尽快收手给提示，而不是在十几个死台间反复横跳
function hop(reason){
  clearTimeout(watchdog);
  const failed = selectPool[poolIdx];
  if (failed) broken.add(failed.url);
  poolIdx++;
  while (poolIdx < selectPool.length && broken.has(selectPool[poolIdx].url)) poolIdx++;
  if (poolIdx < selectPool.length && poolIdx <= MAX_HOPS){
    const st = selectPool[poolIdx];
    focus(st, { fly: false, play: true });
    setState('load', (reason ? reason + ' · ' : '') + '自动跳到附近可用频道…');
    armWatchdog();
  } else {
    setState('err', '这一带在当前网络下都连不上，试试 🏠 回中国上空，或换个地区');
    world.ringsData([]);
  }
}
function stopVideo(){
  try{ video.pause(); }catch(e){}
  world.ringsData([]);
  setState('load', '已暂停');
  toggleBtn('▶ 播放');
}
video.addEventListener('playing', () => { clearTimeout(watchdog); setState('ok', '● 正在直播' + (proxying ? '（经代理）' : '')); toggleBtn('⏸ 暂停'); if (current) world.ringsData([current]); setPlaybackState('playing'); });
video.addEventListener('pause', () => setPlaybackState('paused'));
video.addEventListener('waiting', () => setState('load', '缓冲中…'));
video.addEventListener('stalled', () => setState('load', '缓冲中…'));
// 仅在确有 MediaError（真正无法播放）时跳台；切台/复位过程中的 emptied/abort 不误触发
video.addEventListener('error', () => { if (video.error) hop('该台无法播放'); });

/* ---------------- 上一台 / 下一台 ---------------- */
function stepPool(){
  if (activeTab === 'fav' && favs.length > 1) return favs;
  if (regionList.length > 1) return regionList;
  return null;
}
function stepStation(dir){
  if (!allStations.length) return;
  const list = stepPool();
  let st = null;
  if (list){
    const idx = current ? list.findIndex(s => s.url === current.url) : -1;
    st = idx >= 0 ? list[(idx + dir + list.length) % list.length]
                  : list[dir > 0 ? 0 : list.length - 1];
  } else {
    st = allStations[Math.floor(Math.random() * allStations.length)];
    if (st && (!current || st.url !== current.url)) setRegion(st.lat, st.lng);
  }
  if (!st || (current && st.url === current.url)) return;
  playAt(st, true);
}

/* ---------------- 媒体会话：遥控 / 蓝牙 / 耳机线控 ---------------- */
function updateMediaMeta(st){
  if (!('mediaSession' in navigator)) return;
  try{
    const artwork = [
      { src: 'icons/icon-192.png', sizes: '192x192', type: 'image/png' },
      { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png' },
    ];
    if (st.logo && st.logo.startsWith('https://')) artwork.unshift({ src: st.logo, sizes: '96x96' });
    navigator.mediaSession.metadata = new MediaMetadata({
      title: st.name,
      artist: [st.country, st.state].filter(Boolean).join(' · ') || '环球TV',
      album: '环球TV · 转动地球看世界',
      artwork,
    });
  }catch(e){}
}
function setPlaybackState(s){
  if ('mediaSession' in navigator){ try{ navigator.mediaSession.playbackState = s; }catch(e){} }
}
if ('mediaSession' in navigator){
  const bind = (action, fn) => { try{ navigator.mediaSession.setActionHandler(action, fn); }catch(e){} };
  bind('play', () => { const p = video.play(); if (p && p.catch) p.catch(() => {}); });
  bind('pause', () => stopVideo());
  bind('stop', () => stopVideo());
  bind('previoustrack', () => stepStation(-1));
  bind('nexttrack', () => stepStation(1));
}

/* ---------------- 面板 ---------------- */
function showPlayer(st){
  $('player').style.display = 'flex';
  $('pName').textContent = st.name;
  $('pLoc').textContent = [st.country, st.state].filter(Boolean).join(' · ') || '—';
  const logo = $('pLogo');
  if (st.logo) logo.innerHTML = `<img src="${st.logo}" alt="" onerror="this.parentNode.textContent='📺'">`;
  else logo.textContent = '📺';
  setState('load', '连接中…');
  updateMediaMeta(st);
}
function setState(cls, txt){ const e = $('pState'); e.className = 'state ' + cls; e.textContent = txt; }
function toggleBtn(txt){ $('pToggle').textContent = txt; }

$('pToggle').onclick = () => {
  if (!current) return;
  if (video.paused){ const p = video.play(); if (p && p.catch) p.catch(() => {}); }
  else stopVideo();
};
$('pMute').onclick = () => {
  video.muted = !video.muted;
  $('pMute').textContent = video.muted ? '🔇' : '🔊';
  $('pMute').classList.toggle('on', !video.muted);
};
$('pVol').oninput = () => { video.volume = $('pVol').value / 100; if (video.volume > 0) video.muted = false; };
$('pFull').onclick = () => {
  const stage = $('stage');
  if (document.fullscreenElement){ document.exitFullscreen().catch(() => {}); return; }
  const el = stage.requestFullscreen ? stage : video;
  const req = el.requestFullscreen || el.webkitRequestFullscreen || video.webkitEnterFullscreen;
  if (req){ try{ req.call(el); }catch(e){ try{ video.webkitEnterFullscreen(); }catch(_){} } }
};
$('pPrev').onclick = () => stepStation(-1);
$('pNext').onclick = () => stepStation(1);
$('stage').addEventListener('dblclick', () => $('pFull').click());

/* ---------------- 收藏夹 + 本区频道列表 ---------------- */
const FAV_KEY = 'ooglex_tv_favs';
const REGION_KM = 300;
let favs = loadFavs();
let regionList = [], regionLabel = '', activeTab = 'region';

function loadFavs(){ try { return JSON.parse(localStorage.getItem(FAV_KEY)) || []; } catch (e) { return []; } }
function saveFavs(){ try { localStorage.setItem(FAV_KEY, JSON.stringify(favs)); } catch (e) {} }
function isFav(st){ return !!st && favs.some(f => f.url === st.url); }
function toggleFav(st){
  if (!st) return;
  const i = favs.findIndex(f => f.url === st.url);
  if (i >= 0) favs.splice(i, 1);
  else favs.unshift({ name: st.name, country: st.country, state: st.state, lat: st.lat, lng: st.lng, url: st.url, cc: st.cc, logo: st.logo });
  saveFavs(); updateCounts(); renderList(); updateStar();
}
function esc(s){ return (s || '').replace(/[&<>"]/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;' }[c])); }

function regionAround(lat, lng){
  return allStations.map(s => ({ s, d: dist(lat, lng, s.lat, s.lng) }))
    .filter(x => x.d <= REGION_KM).sort((a, b) => a.d - b.d).slice(0, 90).map(x => x.s);
}
function setRegion(lat, lng, label){
  regionList = regionAround(lat, lng);
  if (label) regionLabel = label;
  else { const n = regionList[0]; regionLabel = (n ? (n.state || n.country || '这一带') : '这一带') + ' · ' + regionList.length + ' 台'; }
  ensurePanel(); updateCounts();
}
function ensurePanel(){ if (!cinematic) $('player').style.display = 'flex'; }
function updateCounts(){ $('cntRegion').textContent = regionList.length; $('cntFav').textContent = favs.length; }
function showTab(t){
  activeTab = t;
  $('tabRegion').classList.toggle('on', t === 'region');
  $('tabFav').classList.toggle('on', t === 'fav');
  renderList();
}
function updateStar(){ const on = isFav(current); const b = $('pStar'); b.textContent = on ? '★' : '☆'; b.classList.toggle('is', on); }
function afterCurrentChanged(){ updateStar(); renderList(); }
function renderList(){
  const list = activeTab === 'fav' ? favs : regionList;
  $('plabel').textContent = activeTab === 'fav' ? ('我的收藏 · ' + favs.length + ' 台') : (regionLabel || '');
  if (!list.length){
    $('plist').innerHTML = '<div class="pempty">' +
      (activeTab === 'fav' ? '还没有收藏～ 点频道右侧的 ☆ 就能收藏。' : '这一带暂时没有电视台，换个地方试试。') + '</div>';
    return;
  }
  $('plist').innerHTML = list.map((s, i) => {
    const on = current && current.url === s.url;
    const fv = isFav(s);
    return '<div class="prow' + (on ? ' on' : '') + '" data-i="' + i + '">' +
      '<div class="pr-main"><div class="pr-nm">' + esc(s.name) + '</div>' +
      '<div class="pr-sub">' + esc([s.country, s.state].filter(Boolean).join(' · ')) + '</div></div>' +
      '<button class="pr-star' + (fv ? ' is' : '') + '" data-star="' + i + '" title="收藏 / 取消收藏">' + (fv ? '★' : '☆') + '</button></div>';
  }).join('');
}
function setMin(on){ $('player').classList.toggle('min', !!on); $('pChev').textContent = on ? '▴ 展开' : '▾ 收起'; }
$('pHandle').onclick = () => setMin(!$('player').classList.contains('min'));
$('tabRegion').onclick = () => { setMin(false); showTab('region'); };
$('tabFav').onclick = () => { setMin(false); showTab('fav'); };
$('pStar').onclick = () => toggleFav(current);
$('plist').addEventListener('click', e => {
  const list = activeTab === 'fav' ? favs : regionList;
  const star = e.target.closest('.pr-star');
  if (star){ toggleFav(list[+star.dataset.star]); return; }
  const row = e.target.closest('.prow');
  if (row){ const s = list[+row.dataset.i]; if (s) playAt(s, true); }
});

/* ---------------- 全屏沉浸模式（隐藏浏览器地址栏） ---------------- */
(function immersive(){
  const btn = $('tFull');
  if (!btn) return;
  const isApp = matchMedia('(display-mode: standalone)').matches || navigator.standalone;
  if (!document.fullscreenEnabled || isApp){ btn.style.display = 'none'; return; }
  const FS_KEY = 'ooglex_tv_fs';
  const fsOn = () => !!document.fullscreenElement;
  function enterFs(){
    const p = document.documentElement.requestFullscreen({ navigationUI: 'hide' });
    if (p && p.catch) p.catch(() => {});
  }
  btn.onclick = () => {
    if (fsOn()){
      document.exitFullscreen().catch(() => {});
      try{ localStorage.removeItem(FS_KEY); }catch(e){}
    } else {
      enterFs();
      try{ localStorage.setItem(FS_KEY, '1'); }catch(e){}
    }
  };
  document.addEventListener('fullscreenchange', () => {
    btn.classList.toggle('on', fsOn());
    btn.title = fsOn() ? '退出全屏' : '全屏沉浸模式：隐藏浏览器地址栏';
  });
  let wants = false;
  try{ wants = localStorage.getItem(FS_KEY) === '1'; }catch(e){}
  if (wants){
    const once = () => { enterFs(); removeEventListener('pointerdown', once, true); };
    addEventListener('pointerdown', once, true);
  }
})();

/* ---------------- 工具按钮 ---------------- */
$('tRandom').onclick = () => {
  if (!allStations.length) return;
  const s = allStations[Math.floor(Math.random() * allStations.length)];
  setRegion(s.lat, s.lng); showTab('region'); playAt(s, true);
};
$('tHome').onclick = () => world.pointOfView({ lat: 30, lng: 110, altitude: 2.2 }, 900);
$('tRotate').onclick = () => {
  rotating = !rotating;
  world.controls().autoRotate = rotating;
  $('tRotate').textContent = rotating ? '⏸' : '↻';
};

/* ---------------- 搜索 ---------------- */
let searchTimer;
$('q').addEventListener('input', () => { clearTimeout(searchTimer); searchTimer = setTimeout(doSearch, 300); });
function doSearch(){
  const term = $('q').value.trim();
  if (!term){ setStations(allStations); hideStatus(); return; }
  const t = term.toLowerCase();
  const local = allStations.filter(s => (s.name + ' ' + s.country + ' ' + s.state).toLowerCase().includes(t));
  if (local.length){
    hideStatus();
    setStations(local);
    regionList = local; regionLabel = '搜索“' + term + '” · ' + local.length + ' 台';
    ensurePanel(); updateCounts(); showTab('region');
    playAt(local[0], true);
  } else {
    status('没有找到匹配的电视台，换个词试试～', false, 2400);
  }
}

/* ---------------- 载入频道 ---------------- */
// channels.json 里的紧凑数组 [name,lat,lng,url,country,state,cc,logo?] → 频道对象
function rowToStation(r){
  return { name: (r[0] || '').slice(0, 60), lat: +r[1], lng: +r[2], url: r[3] || '',
           country: r[4] || '', state: r[5] || '', cc: r[6] || '', logo: r[7] || '' };
}
async function loadStations(){
  status('正在载入电视台…', true);
  // 读取 HLS 代理配置（站长部署后在 proxy.json 里填 URL；留空则直连）
  try{
    const pj = await (await fetch('proxy.json?t=' + Date.now())).json();
    if (pj && typeof pj.hls === 'string') HLS_PROXY = pj.hls.trim().replace(/\/+$/, '');
  }catch(e){ /* 没有就直连 */ }
  let list = [];
  // 1) 本站自带频道库（同源托管 → 国内 / 手机 / 微信都能直达，不依赖外网 API）
  try{
    const data = await (await fetch('channels.json?t=' + Date.now())).json();
    if (Array.isArray(data)) list = data.map(rowToStation).filter(playable);
  }catch(e){ /* 还没生成就走兜底 */ }
  // 2) 兜底：内置精选频道
  if (!list.length){
    try{
      const fb = await (await fetch('channels-fallback.json')).json();
      list = fb.map(rowToStation).filter(playable);
      status('⚠ 频道库尚未生成，已载入内置精选频道。', false, 4000);
    }catch(e){ status('频道库加载失败，请检查网络后刷新。', false); return; }
  }
  allStations = dedupe(list);
  setStations(allStations);
  if (allStations.length > 20){
    const cnCount = allStations.filter(s => s.cc === 'CN' || s.cc === 'HK' || s.cc === 'TW' || s.cc === 'MO').length;
    status(`已就绪 · ${allStations.length} 个频道（含华语区 ${cnCount} 个）`, false, 3000);
  }
  tuneCenter(false);
  const pov = world.pointOfView();
  const near = nearest(pov.lat, pov.lng).st;
  if (near) setRegion(near.lat, near.lng);
  showTab('region');
}

/* ---------------- 启动 ---------------- */
$('introGo').onclick = () => { $('intro').style.display = 'none'; };
if (innerWidth <= 640) setMin(true);   // 手机默认收起列表，避免遮挡地球
video.volume = 1;
initGlobe();
loadStations();
})();
