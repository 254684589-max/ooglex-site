(() => {
'use strict';
const $ = s => document.querySelector(s);
const globeEl=$('#globe'), panel=$('#panel'), viewer=$('#viewer'), count=$('#count'), search=$('#search');
const status=$('#status'), loadBtn=$('#loadNearby'), attribution=$('#attribution');
const cfg=window.OOGLEX_GLOBAL_CAMS||{};
const API_BASE=String(cfg.apiBase||'').replace(/\/$/,'');
let all=[], filtered=[], mode='demo';

const globe = Globe()(globeEl)
  .globeImageUrl('../radio/vendor/earth-blue-marble.jpg')
  .backgroundColor('#05070f')
  .pointAltitude(0.015)
  .pointRadius(d=>d.playable?0.23:0.17)
  .pointColor(d=>d.playable?'#4ee7b7':'#d8e2f2')
  .pointLabel(d=>'<b>'+escapeHtml(d.name)+'</b><br>'+escapeHtml([d.city,d.country].filter(Boolean).join(' · ')))
  .onPointClick(showCamera);
globe.controls().autoRotate=true;
globe.controls().autoRotateSpeed=0.25;
globe.pointOfView({lat:22,lng:15,altitude:2.2},0);

loadDemo();

async function loadDemo(){
  try{
    const r=await fetch('./cameras.json',{cache:'no-store'});
    if(!r.ok)throw new Error('HTTP '+r.status);
    const data=await r.json();
    all=Array.isArray(data)?data:[];
    filtered=all;
    mode='demo';
    setStatus(API_BASE?'演示点位已载入。转动地球后点“加载当前区域”获取真实公开摄像头。':'演示点位。真实数据服务尚未配置；V0.2 后端代码已预留。','demo');
    render();
  }catch(err){
    all=[];filtered=[];
    setStatus('演示数据加载失败。','error');
    render();
    console.error(err);
  }
}

async function loadNearby(){
  if(!API_BASE){
    setStatus('真实数据服务尚未配置：需要先部署 Global Cams API Worker，并在 config.js 填入其域名。','demo');
    return;
  }
  const pov=globe.pointOfView();
  const lat=clamp(Number(pov.lat)||0,-90,90);
  const lng=clamp(Number(pov.lng)||0,-180,180);
  loadBtn.disabled=true;
  loadBtn.textContent='加载中…';
  setStatus('正在获取当前视角附近的公开摄像头…','live');
  try{
    const url=new URL(API_BASE+'/v1/webcams');
    url.searchParams.set('lat',lat.toFixed(4));
    url.searchParams.set('lng',lng.toFixed(4));
    url.searchParams.set('radius','250');
    url.searchParams.set('limit','50');
    url.searchParams.set('lang','zh');
    const r=await fetch(url.toString(),{headers:{Accept:'application/json'}});
    const payload=await r.json().catch(()=>({}));
    if(!r.ok)throw new Error(payload.error||('HTTP '+r.status));
    all=Array.isArray(payload.webcams)?payload.webcams:[];
    filtered=all;
    mode='live';
    search.value='';
    setStatus(all.length?'已载入 '+all.length+' 个真实公开摄像头 · 数据源 Windy Webcams API':'当前 250 公里范围内没有返回可用摄像头。','live');
    render();
  }catch(err){
    setStatus('真实摄像头加载失败：'+safeMessage(err),'error');
  }finally{
    loadBtn.disabled=false;
    loadBtn.textContent='加载当前区域';
  }
}

function render(){
  globe.pointsData(filtered);
  count.textContent=filtered.length+(mode==='demo'?' 个演示点位':' 个公开点位');
}

function showCamera(d){
  globe.controls().autoRotate=false;
  $('#camName').textContent=d.name||'公开摄像头';
  $('#camMeta').textContent=[d.city,d.country,d.category,d.source].filter(Boolean).join(' · ');
  const sourceUrl=safeHttpUrl(d.source_url);
  const sourceLink=$('#openSource');
  sourceLink.href=sourceUrl||'#';
  sourceLink.style.pointerEvents=sourceUrl?'auto':'none';
  sourceLink.setAttribute('aria-disabled',sourceUrl?'false':'true');
  viewer.replaceChildren();

  if(d.embed_url && safeHttpUrl(d.embed_url)){
    const f=document.createElement('iframe');
    f.src=d.embed_url;
    f.allow='autoplay; encrypted-media; picture-in-picture; fullscreen';
    f.allowFullscreen=true;
    f.referrerPolicy='strict-origin-when-cross-origin';
    viewer.appendChild(f);
  } else if(d.preview_url && safeHttpUrl(d.preview_url)){
    const img=document.createElement('img');
    img.src=d.preview_url;
    img.alt=d.name||'公开摄像头预览';
    img.referrerPolicy='no-referrer';
    if(sourceUrl){
      const a=document.createElement('a');
      a.href=sourceUrl;a.target='_blank';a.rel='noopener';
      a.appendChild(img);viewer.appendChild(a);
    }else viewer.appendChild(img);
  } else {
    const box=document.createElement('div');
    box.style.padding='24px';box.style.textAlign='center';
    box.textContent=d.demo?'演示点位：仅用于验证地球交互与页面布局。':'该摄像头当前没有可嵌入画面，请打开官方来源。';
    viewer.appendChild(box);
  }

  if(d.source==='Windy Webcams API'){
    attribution.innerHTML='Webcams provided by <a href="https://www.windy.com/" target="_blank" rel="noopener">windy.com</a> — <a href="https://www.windy.com/webcams/add" target="_blank" rel="noopener">add a webcam</a>';
  }else{
    attribution.textContent=d.demo?'演示数据，不代表当前真实直播状态。':'公开来源；画面版权与可用性归原始提供方。';
  }

  panel.classList.add('open');
  if(Number.isFinite(+d.lat)&&Number.isFinite(+d.lng)){
    globe.pointOfView({lat:+d.lat,lng:+d.lng,altitude:0.75},850);
  }
}

search.addEventListener('input',()=>{
  const q=search.value.trim().toLowerCase();
  filtered=!q?all:all.filter(d=>[d.name,d.city,d.country,d.category,d.source].join(' ').toLowerCase().includes(q));
  render();
});
loadBtn.addEventListener('click',loadNearby);
$('#closePanel').addEventListener('click',()=>panel.classList.remove('open'));
addEventListener('resize',()=>{globe.width(innerWidth).height(innerHeight)});

function setStatus(message,kind){status.textContent=message;status.dataset.kind=kind}
function clamp(v,min,max){return Math.min(max,Math.max(min,v))}
function safeMessage(err){return String(err&&err.message||err||'未知错误').slice(0,120)}
function safeHttpUrl(value){
  try{const u=new URL(String(value||''));return /^https?:$/.test(u.protocol)?u.href:''}catch{return''}
}
function escapeHtml(v=''){return String(v).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}
})();