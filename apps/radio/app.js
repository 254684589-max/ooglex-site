/* 环球电波 · 转动地球听世界
   真实卫星地球（自托管纹理）+ 中央圆圈"框选"收听 + 全球/中国电台（Radio Browser API，HTTPS 直连） */
(() => {
'use strict';
const $ = id => document.getElementById(id);
const audio = new Audio();
audio.preload = 'none';

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

/* ---------------- 电台数据工具 ---------------- */
const MIRRORS = [
  'https://de1.api.radio-browser.info',
  'https://nl1.api.radio-browser.info',
  'https://at1.api.radio-browser.info',
  'https://fi1.api.radio-browser.info',
];
async function api(path){
  const order = MIRRORS.slice().sort(() => Math.random() - 0.5);
  for (const m of order){
    try{
      const ctrl = new AbortController();
      const to = setTimeout(() => ctrl.abort(), 9000);
      const r = await fetch(m + path, { signal: ctrl.signal });
      clearTimeout(to);
      if (r.ok) return await r.json();
    }catch(e){ /* 换下一个镜像 */ }
  }
  return null;
}
function norm(s){
  return {
    name: (s.name || '未知电台').trim().slice(0, 60),
    country: s.country || '', state: s.state || '',
    lat: +s.geo_lat, lng: +s.geo_long,
    url: s.url_resolved || s.url || '', codec: s.codec || '',
    fav: s.favicon || '', votes: +s.votes || 0,
    cc: s.countrycode || '',
  };
}
function playable(s){
  return typeof s.url === 'string' && s.url.startsWith('https://')
    && !/\.m3u8(\?|$)/i.test(s.url)
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
const SNAP_KM = 900;   // 吸附半径：圆圈中心此范围内的最近电台会被"吸"到正中并播放
const broken = new Set();          // 本次会话中连不上的电台（自动跳过）
let selectPool = [], poolIdx = 0, watchdog = null;   // 失败自动跳到附近可用电台

function initGlobe(){
  world = Globe({ animateIn: true })($('globe'))
    .backgroundColor('rgba(0,0,0,0)')
    .width(innerWidth).height(innerHeight)
    .globeImageUrl('vendor/earth-blue-marble.jpg')
    .bumpImageUrl('vendor/earth-topology.png')
    .showAtmosphere(true).atmosphereColor('#9ec9ff').atmosphereAltitude(0.28)
    .pointsData([])
    .pointLat('lat').pointLng('lng')
    .pointColor(d => d === current ? '#fff3a0' : '#39ff14')
    .pointAltitude(d => d === current ? 0.02 : 0.01)
    .pointRadius(d => d === current ? 0.55 : 0.24)
    .pointResolution(6)
    .pointLabel(d => `<div style="background:rgba(8,12,26,.94);border:1px solid rgba(120,150,220,.35);
        padding:6px 10px;border-radius:8px;font-family:sans-serif;color:#e9f2ff;font-size:12px;max-width:220px">
        <b>${d.name}</b><br><span style="color:#93a4c8">${[d.country, d.state].filter(Boolean).join(' · ') || ''}</span></div>`)
    .onPointClick(d => { setRegion(d.lat, d.lng); showTab('region'); playAt(d, true); })
    .ringsData([])
    .ringColor(() => t => `rgba(61,255,158,${1 - t})`)
    .ringMaxRadius(3.4).ringPropagationSpeed(1.7).ringRepeatPeriod(620);

  enhanceGlobe(world);

  const c = world.controls();
  c.autoRotate = false; c.autoRotateSpeed = 0.34;
  c.enableDamping = false;          // 关掉松手后的惯性滑行，避免"滑过"信号源
  c.rotateSpeed = 0.85;
  c.minDistance = 180; c.maxDistance = 520;
  world.pointOfView({ lat: 30, lng: 110, altitude: 2.2 }, 0);

  // 拖动中：实时反馈圆圈是否已罩住电台（变绿 + 提示台名），不播放
  let liveThrottle = 0;
  c.addEventListener('change', () => {
    const now = performance.now();
    if (now - liveThrottle < 80 || !allStations.length) return;
    liveThrottle = now;
    const pov = world.pointOfView();
    const { st, d } = nearest(pov.lat, pov.lng);
    const ok = !!st && d <= SNAP_KM;
    setReticleLive(ok);
    $('rtip').textContent = ok ? '松手收听：' + st.name : '拖动地球，把电台转进圈内即可收听';
  });
  // 松手：自动吸附到最近电台（精准对准圆圈中心）并播放
  c.addEventListener('end', () => tuneCenter(true));

  addEventListener('resize', () => world.width(innerWidth).height(innerHeight));

  cinematicIntro();
}

/* 电影开场运镜：低轨贴地切入 → 低空掠过 → 平滑拉远到可操作的地球视角；拖动即可跳过。
   等日面贴图加载好再开拍，避免运镜时看到没上贴图的地球。 */
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
  if (player && regionList.length) player.style.display = 'flex';   // 运镜结束再亮出电台面板
  const el = $('intro'); if (!el) return;
  el.style.display = '';                                  // 恢复 CSS 默认布局
  el.style.opacity = '0';
  el.style.transition = 'opacity .7s ease';
  requestAnimationFrame(() => { el.style.opacity = '1'; });
}

/* 让地球更精细逼真：海洋镜面高光 + 夜面城市灯 + 更强地形起伏 + 各向异性高清过滤 + 电影级色调 + 昼夜立体感 */
function enhanceGlobe(world){
  const gm = world.globeMaterial();
  gm.bumpScale = 15;                                  // 更明显的山脉/地形起伏

  // 渲染器：各向异性过滤（斜看不糊）+ 电影级色调映射（色彩更通透）+ 视网膜清晰度
  let maxAniso = 8;
  try{
    const r = world.renderer();
    maxAniso = r.capabilities.getMaxAnisotropy() || 8;
    r.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    if ('toneMapping' in r){ r.toneMapping = 4 /* ACESFilmicToneMapping */; r.toneMappingExposure = 1.18; }
  }catch(e){}

  // 复用日面贴图已有的 Texture 构造器，再叠加高光/夜灯（无需单独引入 three）
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
    if (!gm.map){ return setTimeout(apply, 60); }                 // 等日面贴图就绪
    const Ctor = gm.map.constructor, cs = gm.map.colorSpace;
    gm.map.anisotropy = maxAniso; gm.map.needsUpdate = true;
    if (gm.bumpMap){ gm.bumpMap.anisotropy = maxAniso; gm.bumpMap.needsUpdate = true; }

    // 海洋镜面高光：水面反射阳光、陆地哑光
    texFromImg('vendor/earth-water.png', Ctor, null, t => {
      gm.specularMap = t;
      if (gm.specular && gm.specular.setHex) gm.specular.setHex(0x2b3f66);
      gm.shininess = 20; gm.needsUpdate = true;
    });
    // 夜面城市灯：夜半球点点灯火，呼应广播主题
    texFromImg('vendor/earth-night.jpg', Ctor, cs, t => {
      if ('emissiveMap' in gm){
        gm.emissiveMap = t;
        if (gm.emissive && gm.emissive.setHex) gm.emissive.setHex(0xffdd88);
        gm.emissiveIntensity = 1.0; gm.needsUpdate = true;
      }
    });
  })();

  // 光照：太阳跟随视角并略偏转——任何角度看正面都亮堂立体，边缘留一弯暮色 + 城市灯
  try{
    const lights = world.lights ? world.lights() : null;
    let sun = null;
    if (lights && lights.length){
      lights.forEach(l => {
        if (/Ambient|Hemisphere/i.test(l.type)) l.intensity = 1.0;     // 暮色侧不至于全黑，仍能看清绿点
        if (/Directional|Point/i.test(l.type)){ l.intensity = 1.45; sun = l; }
      });
      world.lights(lights);
    }
    if (sun && sun.position && world.camera){
      const cam = world.camera();
      const TH = 0.34, cosT = Math.cos(TH), sinT = Math.sin(TH);        // 阳光相对视角偏转 ~20°：正面大面积受光，边缘留一弯暮色
      (function follow(){
        const p = cam.position;
        sun.position.set(p.x * cosT - p.z * sinT, p.y * 1.05 + 25, p.x * sinT + p.z * cosT);
        requestAnimationFrame(follow);
      })();
    }
    console.log('[globe] sun-follow:', !!sun, '| aniso', maxAniso, '| mat', gm.type);
  }catch(e){ console.log('[globe] light err', e.message); }
}

function setStations(list){ world.pointsData(list); }
function refreshHighlight(){
  world.pointColor(d => d === current ? '#fff3a0' : '#39ff14')
       .pointRadius(d => d === current ? 0.55 : 0.24)
       .pointAltitude(d => d === current ? 0.02 : 0.01);
}
function setReticleLive(on){ $('reticle').classList.toggle('live', !!on); }

/* 把圆圈中心最近的电台设为当前（doPlay 为真则播放） */
function tuneCenter(doPlay){
  if (!allStations.length) return;
  const pov = world.pointOfView();
  const { st, d } = nearest(pov.lat, pov.lng);
  if (!st || d > SNAP_KM){ setReticleLive(false); return; }
  setReticleLive(true);
  if (doPlay){                                 // 吸附对准 + 播放（失败自动跳台），并在左下列出本区电台
    setRegion(st.lat, st.lng);
    showTab('region');
    playAt(st, true);
  } else {
    focus(st, { fly: !cinematic, play: false });   // 载入时仅吸附高亮，不出声（开场运镜中不抢镜头）
  }
}

/* 选中一个电台：高亮、涟漪、面板、（可选）飞过去、（可选）播放 */
function focus(st, opt){
  opt = opt || {};
  current = st;
  refreshHighlight();
  setReticleLive(true);
  if (opt.fly){
    const alt = world.pointOfView().altitude;
    world.pointOfView({ lat: st.lat, lng: st.lng, altitude: alt }, 450);   // 平滑吸附对准圆圈中心
  }
  if (opt.play){
    world.ringsData([st]);
    showPlayer(st);
    audio.src = st.url;
    audio.volume = $('pVol').value / 100;
    const p = audio.play();
    if (p && p.catch) p.catch(() => {});
  } else {
    world.ringsData([]);
    $('rtip').textContent = '松手 / 点击即可收听：' + st.name;
  }
  afterCurrentChanged();
}

/* 播放某电台，并围绕它建一个"就近备选池"：连不上时自动跳到附近可用电台 */
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
  watchdog = setTimeout(() => { if (audio.paused || audio.readyState < 3) hop('连接超时'); }, 7000);
}
function hop(reason){
  clearTimeout(watchdog);
  const failed = selectPool[poolIdx];
  if (failed) broken.add(failed.url);
  poolIdx++;
  while (poolIdx < selectPool.length && broken.has(selectPool[poolIdx].url)) poolIdx++;
  if (poolIdx < selectPool.length){
    const st = selectPool[poolIdx];
    focus(st, { fly: false, play: true });
    setState('load', (reason ? reason + ' · ' : '') + '自动跳到附近可用电台…');
    armWatchdog();
  } else {
    setState('err', '附近电台在当前网络下都连不上，换个地区或稍后再试');
    world.ringsData([]);
  }
}
function stopAudio(){
  audio.pause();
  world.ringsData([]);
  setState('load', '已暂停');
  toggleBtn('▶ 播放');
}
audio.addEventListener('playing', () => { clearTimeout(watchdog); setState('ok', '♪ 正在收听'); toggleBtn('⏸ 暂停'); if (current) world.ringsData([current]); setPlaybackState('playing'); });
audio.addEventListener('pause', () => setPlaybackState('paused'));
audio.addEventListener('waiting', () => setState('load', '缓冲中…'));
audio.addEventListener('stalled', () => setState('load', '缓冲中…'));
audio.addEventListener('error', () => hop('该台无法播放'));

/* ---------------- 上一台 / 下一台（屏幕按钮与方向盘 / 蓝牙按键共用） ---------------- */
function stepPool(){
  if (activeTab === 'fav' && favs.length > 1) return favs;   // 收藏页里就在收藏间切换
  if (regionList.length > 1) return regionList;              // 否则在本区 / 搜索结果里切换
  return null;                                               // 列表太小 → 全球随机
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

/* ---------------- 媒体会话：车机蓝牙(AVRCP) / 方向盘 / 耳机线控 ----------------
   把上一曲 / 下一曲映射为上一台 / 下一台，车机屏幕同时显示台名与地区 */
function updateMediaMeta(st){
  if (!('mediaSession' in navigator)) return;
  try{
    const artwork = [
      { src: 'icons/icon-192.png', sizes: '192x192', type: 'image/png' },
      { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png' },
    ];
    if (st.fav && st.fav.startsWith('https://')) artwork.unshift({ src: st.fav, sizes: '96x96' });
    navigator.mediaSession.metadata = new MediaMetadata({
      title: st.name,
      artist: [st.country, st.state].filter(Boolean).join(' · ') || '环球电波',
      album: '环球电波 · 转动地球听世界',
      artwork,
    });
  }catch(e){}
}
function setPlaybackState(s){
  if ('mediaSession' in navigator){ try{ navigator.mediaSession.playbackState = s; }catch(e){} }
}
if ('mediaSession' in navigator){
  const bind = (action, fn) => { try{ navigator.mediaSession.setActionHandler(action, fn); }catch(e){} };
  bind('play', () => { if (current){ const p = audio.play(); if (p && p.catch) p.catch(() => {}); } });
  bind('pause', () => stopAudio());
  bind('stop', () => stopAudio());
  bind('previoustrack', () => stepStation(-1));
  bind('nexttrack', () => stepStation(1));
}

/* ---------------- 面板 ---------------- */
function showPlayer(st){
  $('player').style.display = 'flex';
  $('pName').textContent = st.name;
  $('pLoc').textContent = [st.country, st.state].filter(Boolean).join(' · ') || '—';
  const fav = $('pFav');
  if (st.fav) fav.innerHTML = `<img src="${st.fav}" style="width:100%;height:100%;border-radius:12px;object-fit:cover" onerror="this.parentNode.textContent='📻'">`;
  else fav.textContent = '📻';
  setState('load', '连接中…');
  updateMediaMeta(st);
}
function setState(cls, txt){ const e = $('pState'); e.className = 'state ' + cls; e.textContent = txt; }
function toggleBtn(txt){ $('pToggle').textContent = txt; }

$('pToggle').onclick = () => {
  if (!current) return;
  if (audio.paused){ const p = audio.play(); if (p && p.catch) p.catch(() => {}); }
  else stopAudio();
};
$('pVol').oninput = () => { audio.volume = $('pVol').value / 100; };
$('pPrev').onclick = () => stepStation(-1);
$('pNext').onclick = () => stepStation(1);

/* ---------------- 收藏夹 + 本区电台列表 ---------------- */
const FAV_KEY = 'ooglex_radio_favs';
const REGION_KM = 230;                 // "本区"半径：圆圈中心此范围内的电台都列出来
let favs = loadFavs();
let regionList = [], regionLabel = '', activeTab = 'region';

function loadFavs(){ try { return JSON.parse(localStorage.getItem(FAV_KEY)) || []; } catch (e) { return []; } }
function saveFavs(){ try { localStorage.setItem(FAV_KEY, JSON.stringify(favs)); } catch (e) {} }
function isFav(st){ return !!st && favs.some(f => f.url === st.url); }
function toggleFav(st){
  if (!st) return;
  const i = favs.findIndex(f => f.url === st.url);
  if (i >= 0) favs.splice(i, 1);
  else favs.unshift({ name: st.name, country: st.country, state: st.state, lat: st.lat, lng: st.lng, url: st.url, cc: st.cc });
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
      (activeTab === 'fav' ? '还没有收藏～ 点电台右侧的 ☆ 就能收藏。' : '这一带暂时没有电台，换个地方试试。') + '</div>';
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
function setMin(on){ $('player').classList.toggle('min', !!on); $('pChev').textContent = on ? '▴ 展开列表' : '▾ 收起'; }
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
$('q').addEventListener('input', () => { clearTimeout(searchTimer); searchTimer = setTimeout(doSearch, 350); });
async function doSearch(){
  const term = $('q').value.trim();
  if (!term){ setStations(allStations); hideStatus(); return; }
  const t = term.toLowerCase();
  // 先用本站 5000+ 电台库即时搜索（国内/手机/微信秒出，不等外网）
  const local = allStations.filter(s => (s.name + ' ' + s.country + ' ' + s.state).toLowerCase().includes(t));
  if (local.length){
    hideStatus();
    setStations(local);
    regionList = local; regionLabel = '搜索“' + term + '” · ' + local.length + ' 台';
    ensurePanel(); updateCounts(); showTab('region');
    playAt(local[0], true);
  } else {
    status('本地未找到，联网搜索中…', true);
  }
  // 再用在线目录锦上添花（能连上就补充；连不上就用本地结果）
  try{
    const raw = await api('/json/stations/search?hidebroken=true&has_geo_info=true&order=votes&reverse=true&limit=400&name=' + encodeURIComponent(term));
    if (raw && raw.length){
      const merged = dedupe(local.concat(raw.map(norm).filter(playable)));
      setStations(merged);
      regionList = merged; regionLabel = '搜索“' + term + '” · ' + merged.length + ' 台';
      ensurePanel(); updateCounts();
      if (!local.length && merged.length){ showTab('region'); playAt(merged[0], true); }
      else renderList();
      hideStatus();
    } else if (!local.length){
      status('没有找到匹配的电台，换个词试试～', false, 2600);
    }
  }catch(e){ if (!local.length) status('没有找到匹配的电台～', false, 2600); }
}

/* ---------------- 载入电台 ---------------- */
// stations.json 里的紧凑数组 [name,lat,lng,url,country,state,cc] → 电台对象
function rowToStation(r){
  return { name: (r[0] || '').slice(0, 60), lat: +r[1], lng: +r[2], url: r[3] || '',
           country: r[4] || '', state: r[5] || '', cc: r[6] || '', codec: '', fav: '', votes: 0 };
}
async function loadStations(){
  status('正在载入电台…', true);
  let list = [];
  // 1) 本站自带电台库（同源托管 → 国内 / 手机 / 微信都能直达，不依赖外网 API）
  try{
    const data = await (await fetch('stations.json?t=' + Date.now())).json();
    if (Array.isArray(data)) list = data.map(rowToStation).filter(playable);
  }catch(e){ /* 还没生成就走兜底 */ }
  // 2) 兜底：内置精选电台
  if (!list.length){
    try{
      const fb = await (await fetch('stations-fallback.json')).json();
      list = fb.filter(playable);
      status('⚠ 电台库尚未生成，已载入内置精选电台。', false, 4000);
    }catch(e){ status('电台库加载失败，请检查网络后刷新。', false); return; }
  }
  allStations = dedupe(list);
  setStations(allStations);
  if (allStations.length > 50){
    const cnCount = allStations.filter(s => s.cc === 'CN').length;
    status(`已就绪 · ${allStations.length} 个电台（含中国 ${cnCount} 个）`, false, 3000);
  }
  tuneCenter(false);   // 高亮圆圈中心最近的电台（不自动出声，等你拖动/点击）
  const pov = world.pointOfView();
  const near = nearest(pov.lat, pov.lng).st;   // 以最近的电台为中心列出这一带
  if (near) setRegion(near.lat, near.lng);
  showTab('region');
  trySupplement();     // 后台顺带尝试在线目录，能连上就补更多（连不上也无所谓）
}
async function trySupplement(){
  try{
    const g = await api('/json/stations/search?hidebroken=true&has_geo_info=true&order=clickcount&reverse=true&limit=1500');
    if (!g || !g.length) return;
    const merged = dedupe(allStations.concat(g.map(norm).filter(playable)));
    if (merged.length > allStations.length){ allStations = merged; setStations(allStations); }
  }catch(e){ /* 连不上就算了，本地库已够用 */ }
}

/* ---------------- 启动 ---------------- */
$('introGo').onclick = () => { $('intro').style.display = 'none'; };
if (innerWidth <= 640) setMin(true);   // 手机默认收起列表，避免遮挡地球
initGlobe();
loadStations();
})();
