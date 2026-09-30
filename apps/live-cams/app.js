(() => {
'use strict';
const $ = id => document.getElementById(id);
const state = { all: [], filtered: [], current: null, meta: null };
let world = null;

function esc(v){
  return String(v == null ? '' : v).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}
function showStatus(msg){
  const el = $('status');
  el.textContent = msg;
  el.classList.add('show');
}
function hideStatus(){ $('status').classList.remove('show'); }

(function stars(){
  const cv = $('stars'), cx = cv.getContext('2d');
  function draw(){
    cv.width = innerWidth; cv.height = innerHeight;
    cx.clearRect(0,0,cv.width,cv.height);
    const n = Math.min(220, Math.floor(innerWidth * innerHeight / 9500));
    for(let i=0;i<n;i++){
      cx.fillStyle = 'rgba(255,255,255,' + (0.14 + Math.random() * 0.55).toFixed(2) + ')';
      cx.beginPath(); cx.arc(Math.random()*cv.width,Math.random()*cv.height,Math.random()*1.2,0,Math.PI*2); cx.fill();
    }
  }
  draw(); addEventListener('resize', draw);
})();

function validCam(c){
  return c && c.id && c.name && Number.isFinite(+c.lat) && Number.isFinite(+c.lng) &&
    Math.abs(+c.lat) <= 90 && Math.abs(+c.lng) <= 180 &&
    typeof c.embed === 'string' && /^https:\/\//.test(c.embed) &&
    (c.mode === 'live' || c.mode === 'timelapse');
}

function initGlobe(){
  if (typeof Globe !== 'function') throw new Error('3D 地球组件加载失败');
  world = Globe({animateIn:true, waitForGlobeReady:false})($('globe'))
    .backgroundColor('rgba(0,0,0,0)')
    .width(innerWidth).height(innerHeight)
    .globeImageUrl('/apps/radio/vendor/earth-blue-marble.jpg')
    .bumpImageUrl('/apps/radio/vendor/earth-topology.jpg')
    .showAtmosphere(true).atmosphereColor('#8fc5ff').atmosphereAltitude(.24)
    .pointLat('lat').pointLng('lng')
    .pointColor(d => d === state.current ? '#ffd166' : (d.mode === 'live' ? '#3dff9e' : '#5b8cff'))
    .pointRadius(d => d === state.current ? .52 : .30)
    .pointAltitude(d => d === state.current ? .025 : .012)
    .pointResolution(8)
    .pointLabel(d => '<div style="background:rgba(8,13,28,.96);border:1px solid rgba(130,160,225,.32);padding:7px 10px;border-radius:9px;color:#eef5ff;font:12px -apple-system,BlinkMacSystemFont,Segoe UI,sans-serif"><b>' +
      esc(d.name) + '</b><br><span style="color:#93a4c8">' + esc([d.city,d.country].filter(Boolean).join(' · ')) + ' · ' + (d.mode === 'live' ? '直播' : '延时/最新画面') + '</span></div>')
    .onPointClick(d => selectCam(d, true));

  try{
    const ctl = world.controls();
    ctl.enableDamping = true;
    ctl.dampingFactor = .08;
    if (!matchMedia('(prefers-reduced-motion: reduce)').matches){
      ctl.autoRotate = true;
      ctl.autoRotateSpeed = .22;
    }
  }catch(e){}

  world.pointOfView({lat:18,lng:15,altitude:2.15},0);
  addEventListener('resize', () => world && world.width(innerWidth).height(innerHeight));
}

function refreshPoints(){
  if (!world) return;
  world.pointsData(state.filtered);
  refreshPointStyle();
}
function refreshPointStyle(){
  if (!world) return;
  world.pointColor(d => d === state.current ? '#ffd166' : (d.mode === 'live' ? '#3dff9e' : '#5b8cff'))
    .pointRadius(d => d === state.current ? .52 : .30)
    .pointAltitude(d => d === state.current ? .025 : .012);
}

function renderStats(){
  $('allN').textContent = String(state.all.length);
  $('liveN').textContent = String(state.all.filter(c => c.mode === 'live').length);
  $('tlN').textContent = String(state.all.filter(c => c.mode === 'timelapse').length);
  $('listCount').textContent = state.filtered.length + ' / ' + state.all.length;
}

function renderList(){
  const body = $('listBody');
  body.replaceChildren();
  if (!state.filtered.length){
    const p = document.createElement('p');
    p.textContent = '没有匹配的公开摄像头。';
    p.style.cssText = 'padding:16px;color:#93a4c8;font-size:.82rem;text-align:center';
    body.appendChild(p);
    return;
  }
  for (const c of state.filtered){
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'cam-row' + (state.current && state.current.id === c.id ? ' on' : '');
    b.setAttribute('aria-label', c.name + '，' + (c.mode === 'live' ? '直播' : '延时或最新画面'));
    const dot = document.createElement('span'); dot.className = 'dot ' + c.mode;
    const main = document.createElement('span'); main.className = 'cam-main';
    const nm = document.createElement('span'); nm.className = 'cam-name'; nm.textContent = c.name;
    const loc = document.createElement('span'); loc.className = 'cam-loc'; loc.textContent = [c.city,c.country].filter(Boolean).join(' · ');
    const type = document.createElement('span'); type.className = 'cam-type'; type.textContent = c.mode === 'live' ? 'LIVE' : 'TIMELAPSE';
    main.append(nm,loc); b.append(dot,main,type);
    b.addEventListener('click', () => selectCam(c, true));
    body.appendChild(b);
  }
}

function filter(){
  const q = $('q').value.trim().toLowerCase();
  const mode = $('mode').value;
  state.filtered = state.all.filter(c => {
    const text = [c.name,c.city,c.country,c.provider].join(' ').toLowerCase();
    return (!q || text.includes(q)) && (mode === 'all' || c.mode === mode);
  });
  if (state.current && !state.filtered.some(c => c.id === state.current.id)){
    closeViewer();
  }
  refreshPoints();
  renderStats();
  renderList();
}

function selectCam(c, fly){
  state.current = c;
  refreshPointStyle();
  renderList();
  if (fly && world){
    try{ world.controls().autoRotate = false; }catch(e){}
    world.pointOfView({lat:+c.lat,lng:+c.lng,altitude:1.15},650);
  }
  $('camTitle').textContent = c.name;
  $('camLoc').textContent = [c.city,c.country].filter(Boolean).join(' · ') + (c.locationPrecision === 'locality' ? ' · 地点级定位' : '');
  const badge = $('camBadge');
  badge.className = 'badge ' + c.mode;
  badge.textContent = c.mode === 'live' ? '● LIVE' : '延时 / 最新画面';
  $('camProvider').textContent = c.provider || 'Public webcam';
  $('camSource').href = c.sourceUrl || c.embed;
  $('camFrame').src = c.embed;
  $('viewer').classList.add('show');
}
function closeViewer(){
  state.current = null;
  refreshPointStyle();
  renderList();
  $('viewer').classList.remove('show');
  $('camFrame').src = 'about:blank';
}

function randomCam(){
  const pool = state.filtered.length ? state.filtered : state.all;
  if (!pool.length) return;
  selectCam(pool[Math.floor(Math.random()*pool.length)], true);
}
function resetAll(){
  $('q').value = '';
  $('mode').value = 'all';
  closeViewer();
  state.filtered = state.all.slice();
  refreshPoints(); renderStats(); renderList();
  if (world) world.pointOfView({lat:18,lng:15,altitude:2.15},650);
}

async function boot(){
  showStatus('正在加载全球公开摄像头…');
  try{
    initGlobe();
    const r = await fetch('cameras.json?v=1',{cache:'no-store'});
    if (!r.ok) throw new Error('摄像头数据 HTTP ' + r.status);
    const data = await r.json();
    state.meta = data.meta || {};
    state.all = Array.isArray(data.cameras) ? data.cameras.filter(validCam) : [];
    state.filtered = state.all.slice();
    if (!state.all.length) throw new Error('公开摄像头列表为空');
    refreshPoints(); renderStats(); renderList(); hideStatus();
  }catch(err){
    console.error(err);
    showStatus('加载失败：' + (err && err.message ? err.message : '未知错误'));
  }
}

$('q').addEventListener('input', filter);
$('mode').addEventListener('change', filter);
$('randomBtn').addEventListener('click', randomCam);
$('resetBtn').addEventListener('click', resetAll);
$('closeViewer').addEventListener('click', closeViewer);
addEventListener('keydown', e => { if (e.key === 'Escape') closeViewer(); });

boot();
})();