(() => {
'use strict';
const $ = s => document.querySelector(s);
const globeEl=$('#globe'), panel=$('#panel'), viewer=$('#viewer'), count=$('#count'), search=$('#search');
let all=[], filtered=[];
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

fetch('./cameras.json',{cache:'no-store'})
  .then(r=>{if(!r.ok)throw new Error('HTTP '+r.status);return r.json()})
  .then(data=>{all=Array.isArray(data)?data:[]; filtered=all; render();})
  .catch(err=>{count.textContent='数据加载失败'; console.error(err)});

function render(){
  globe.pointsData(filtered);
  count.textContent=filtered.length+' 个公开点位';
}
function showCamera(d){
  globe.controls().autoRotate=false;
  $('#camName').textContent=d.name;
  $('#camMeta').textContent=[d.city,d.country,d.category,d.source].filter(Boolean).join(' · ');
  $('#openSource').href=d.source_url||'#';
  viewer.innerHTML='';
  if(d.embed_url){
    const f=document.createElement('iframe');
    f.src=d.embed_url; f.allow='autoplay; encrypted-media; picture-in-picture; fullscreen'; f.allowFullscreen=true;
    viewer.appendChild(f);
  } else if(d.preview_url){
    const img=document.createElement('img'); img.src=d.preview_url; img.alt=d.name; viewer.appendChild(img);
  } else {
    const box=document.createElement('div'); box.style.padding='24px'; box.style.textAlign='center';
    box.innerHTML='此点位已登记公开来源。<br><small>下一阶段接入可嵌入直播/实时图片源。</small>';
    viewer.appendChild(box);
  }
  panel.classList.add('open');
  globe.pointOfView({lat:d.lat,lng:d.lng,altitude:0.75},850);
}
search.addEventListener('input',()=>{
  const q=search.value.trim().toLowerCase();
  filtered=!q?all:all.filter(d=>[d.name,d.city,d.country,d.category,d.source].join(' ').toLowerCase().includes(q));
  render();
});
$('#closePanel').addEventListener('click',()=>panel.classList.remove('open'));
addEventListener('resize',()=>{globe.width(innerWidth).height(innerHeight)});
function escapeHtml(v=''){return String(v).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}
})();