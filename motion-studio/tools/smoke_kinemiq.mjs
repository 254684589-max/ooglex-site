import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {spawn,execFileSync} from 'node:child_process';
const root=path.resolve(process.argv[2]||'.');
const dir=path.join(root,'motion-studio');
const bake=process.argv.includes('--bake');
const manifest=JSON.parse(fs.readFileSync(path.join(dir,'assets/kinemiq/manifest.json')));
assert.equal(manifest.records.length,35);assert.equal(manifest.unique_motion_credit,0);
assert.ok(manifest.models.length);for(const r of [...manifest.records,...manifest.models]){assert.ok(fs.existsSync(path.join(dir,r.path)));}
for(const page of ['index.html','kaykit.html','accad.html'])assert.match(fs.readFileSync(path.join(dir,page),'utf8'),/href="\.\/kinemiq\.html"/);
const browserProbe=String.raw`
const results=[];const check=(name,ok)=>{if(!ok)throw Error(name);results.push(name);};
const wait=async(fn)=>{for(let i=0;i<1200;i++){if(fn())return;await new Promise(r=>setTimeout(r,100));}throw Error('等待超时 '+document.querySelector('#error')?.textContent);};
const $=id=>document.getElementById(id);
try{
await wait(()=>document.querySelectorAll('.clip').length===35);
check('35 real catalog cards',document.querySelectorAll('.clip').length===35);
check('canvas',!!document.querySelector('#viewer canvas'));
check('three-column layout template',!!document.querySelector('.librarynav')&&!!document.querySelector('.library')&&!!document.querySelector('.preview'));
await wait(()=>window.__kinemiqThumbReady===true);
const thumbs=[...document.querySelectorAll('.motion-card .thumb img')];
await Promise.all(thumbs.map(img=>img.decode()));
check('all 35 actual 256px thumbnails',thumbs.length===35&&thumbs.every(img=>img.naturalWidth===256&&img.naturalHeight===256));
const canvas=document.createElement('canvas');canvas.width=256;canvas.height=256;const ctx=canvas.getContext('2d',{willReadFrequently:true});const hashes=[];
for(const img of thumbs){ctx.drawImage(img,0,0);const p=ctx.getImageData(0,0,256,256).data;let n=0;for(let i=0;i<p.length;i+=4){if(Math.abs(p[i]-37)+Math.abs(p[i+1]-48)+Math.abs(p[i+2]-60)>30)n++;}check('rendered foreground '+img.alt,n>500&&n<62000);hashes.push(await crypto.subtle.digest('SHA-256',p).then(b=>Array.from(new Uint8Array(b),x=>x.toString(16).padStart(2,'0')).join('')));}
check('distinct animation pose images',new Set(hashes).size>=30);
window.__kinemiqBaked=Object.fromEntries(thumbs.map(img=>[img.closest('.clip').dataset.id,img.src]));
const entries=await (await fetch('./assets/kinemiq/manifest.json')).json();
for(const [i,entry] of entries.records.entries()){
const cards=[...document.querySelectorAll('.clip')];cards[i].click();
await wait(()=>!!$('error').textContent||(!$('play').disabled&&$('name').textContent===entry.name));
check(entry.id+' real GLB playback',!$('error').textContent&&$('details').textContent.includes('实际动画轨道'));
check(entry.id+' source download',!$('download').hidden&&$('download').href.endsWith('.glb'));
if(i===0){await wait(()=>Number($('timeline').value)>0);$('play').click();check('pause',$('play').textContent==='播放');$('timeline').value=String(Number($('timeline').max)/2);$('timeline').dispatchEvent(new Event('input'));check('seek',Number($('timeline').value)>0);check('model download',!$('modeldownload').hidden);check('66 mannequin bones',Number($('factbones').textContent)===66);check('Chinese label',!!$('cnname').textContent);$('bones').click();$('reset').click();}
}
$('search').value=entries.records[0].name;$('search').dispatchEvent(new Event('input'));check('search',document.querySelectorAll('.clip').length>0&&document.querySelectorAll('.clip').length<35);
check('no script errors',!window.__kinemiqErrors.length);
check('responsive document',document.documentElement.scrollWidth<=innerWidth+2);
window.__kinemiqResult={ok:true,results,viewport:innerWidth};
}catch(e){window.__kinemiqResult={ok:false,results,error:String(e),errors:window.__kinemiqErrors};}
`;
const server=http.createServer((req,res)=>{
const p=decodeURIComponent(new URL(req.url,'http://127.0.0.1').pathname),file=path.resolve(root,'.'+p);
if(!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);res.end();return;}
let content=fs.readFileSync(file);if(p==='/motion-studio/kinemiq.html'){content=Buffer.from(content.toString().replace('<head>','<head><script>window.__kinemiqErrors=[];addEventListener("error",e=>{if(e.message)window.__kinemiqErrors.push(e.message)});addEventListener("unhandledrejection",e=>window.__kinemiqErrors.push(String(e.reason)));</script>').replace('</body>','<script type="module">'+browserProbe+'</script></body>'));}
res.writeHead(200,{'Content-Type':({'.html':'text/html; charset=utf-8','.js':'text/javascript','.json':'application/json','.svg':'image/svg+xml'})[path.extname(file)]||'application/octet-stream'});res.end(content);
});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
let chrome='';for(const x of ['google-chrome','chromium','chromium-browser']){try{chrome=execFileSync('which',[x],{encoding:'utf8'}).trim();if(chrome)break;}catch{}}
assert.ok(chrome,'Chrome/Chromium required; no silent skip');
await new Promise(r=>server.listen(0,'127.0.0.1',r));const port=server.address().port;
async function evalCDP(url,expression){return new Promise((resolve,reject)=>{const ws=new WebSocket(url);const timer=setTimeout(()=>{ws.close();reject(Error('CDP timeout'));},4000);ws.addEventListener('open',()=>ws.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{expression,returnByValue:true}})));ws.addEventListener('message',e=>{const m=JSON.parse(String(e.data));if(m.id!==1)return;clearTimeout(timer);ws.close();resolve(m.result?.result?.value);});ws.addEventListener('error',()=>{clearTimeout(timer);reject(Error('CDP failed'));});});}
try{for(const width of [500,1280]){const profile=fs.mkdtempSync(path.join(os.tmpdir(),'kinemiq-smoke-'));const c=spawn(chrome,['--headless=new','--no-sandbox','--disable-dev-shm-usage','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--remote-debugging-port=0','--remote-allow-origins=*','--user-data-dir='+profile,'--window-size='+width+',900','http://127.0.0.1:'+port+'/motion-studio/kinemiq.html'],{stdio:'ignore'});try{
let result;for(let i=0;i<1600;i++){await sleep(250);try{const debugPort=fs.readFileSync(path.join(profile,'DevToolsActivePort'),'utf8').split('\n')[0];const pages=await (await fetch('http://127.0.0.1:'+debugPort+'/json/list')).json();const page=pages.find(p=>p.type==='page'&&p.url.includes('kinemiq.html'));if(page){result=await evalCDP(page.webSocketDebuggerUrl,'window.__kinemiqResult');if(result)break;}}catch{}}
assert.ok(result?.ok,JSON.stringify(result||{error:'No browser result'}));assert.ok(width<800?result.viewport<=800:result.viewport>800,'Unexpected viewport');console.log('KinemIQ browser',width,JSON.stringify(result));
if(bake&&width===500){const debugPort=fs.readFileSync(path.join(profile,'DevToolsActivePort'),'utf8').split('\n')[0];const pages=await(await fetch('http://127.0.0.1:'+debugPort+'/json/list')).json();const page=pages.find(p=>p.type==='page'&&p.url.includes('kinemiq.html'));const out=path.join(dir,'assets/kinemiq/thumbs');fs.mkdirSync(out,{recursive:true});const rows=[];for(const x of manifest.records){const value=await evalCDP(page.webSocketDebuggerUrl,'window.__kinemiqBaked['+JSON.stringify(x.id)+']');const filename=x.id+'.png';if(value?.startsWith('data:image/png;base64,')){const bytes=Buffer.from(value.split(',')[1],'base64');assert.equal(bytes.subarray(0,8).toString('hex'),'89504e470d0a1a0a');assert.equal(bytes.readUInt32BE(16),256);assert.equal(bytes.readUInt32BE(20),256);fs.writeFileSync(path.join(out,filename),bytes);}else assert.ok(fs.existsSync(path.join(out,filename)),'missing actual generated PNG');const source=x.hasSkinnedMesh?x:manifest.models.find(m=>/mannequin/i.test(m.original))||manifest.models[0];rows.push({id:x.id,path:'assets/kinemiq/thumbs/'+filename,source_sha256:x.sha256,model_sha256:source.sha256});}fs.writeFileSync(path.join(dir,'assets/kinemiq/thumbs.json'),JSON.stringify({schema:'ooglex.kinemiq.thumbs.v1',records:rows},null,2)+'\n');console.log('Baked',rows.length,'actual GLB pose PNG thumbnails');}
}finally{c.kill('SIGKILL');await sleep(500);fs.rmSync(profile,{recursive:true,force:true,maxRetries:3});}}}finally{server.close();}
