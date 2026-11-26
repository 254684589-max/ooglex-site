import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {spawn,execFileSync} from 'node:child_process';
const root=path.resolve(process.argv[2]||'.');
const dir=path.join(root,'motion-studio');
const manifest=JSON.parse(fs.readFileSync(path.join(dir,'assets/research/retarget-batch/manifest.json')));
assert.equal(manifest.records.length,55);assert.equal(manifest.official_kinemiq_exports,0);assert.equal(manifest.visual_certified_count,0);
for(const r of manifest.records){assert.ok(fs.existsSync(path.join(dir,r.path)));assert.ok(fs.existsSync(path.join(dir,r.source.path)));assert.ok(!r.visual_certified&&!r.ik_certified&&!r.godot_certified);}
const browserProbe=String.raw`
const results=[];const check=(name,ok)=>{if(!ok)throw Error(name);results.push(name);};
const wait=async(fn)=>{for(let i=0;i<160;i++){if(fn())return;await new Promise(r=>setTimeout(r,100));}throw Error('等待超时 '+document.querySelector('#error')?.textContent);};
const $=id=>document.getElementById(id);
try{
const entries=await (await fetch('./assets/research/retarget-batch/manifest.json')).json();
await wait(()=>document.querySelectorAll('.clip').length===55);
check('55 experimental catalog cards',document.querySelectorAll('.clip').length===55);
check('canvas',!!document.querySelector('#viewer canvas'));
const indices=innerWidth>800?entries.records.map((_,i)=>i):[0,1,10,30,54];
for(const i of indices){const entry=entries.records[i];document.querySelectorAll('.clip')[i].click();
await wait(()=>!!$('error').textContent||(!$('play').disabled&&$('name').textContent===entry.source.name));
check(entry.source.id+' bound actual skin animation',!$('error').textContent&&$('details').textContent.includes('23 条实际动画轨道'));
check(entry.source.id+' diagnostics',$('diagnostics').textContent.includes(entry.frames+' 帧')&&$('diagnostics').textContent.includes('66 根蒙皮关节'));
await wait(()=>Number($('timeline').value)>0);$('play').click();check('pause',$('play').textContent==='播放');
$('timeline').value=String(Number($('timeline').max)/2);$('timeline').dispatchEvent(new Event('input'));check('seek',Number($('timeline').value)>0);
check('GLB and BVH download',!$('download').hidden&&$('download').href.endsWith('.glb')&&!$('modeldownload').hidden&&$('modeldownload').href.endsWith('.bvh'));
const credit=await (await fetch($('credit').href)).text();check('attribution',credit.includes('CC BY 3.0')&&credit.includes('ACCAD')&&credit.includes('experimental'));
}
$('search').value='SpinningBackKick';$('search').dispatchEvent(new Event('input'));check('search',document.querySelectorAll('.clip').length===1);
check('no script errors',!window.__retargetErrors.length);
check('responsive document',document.documentElement.scrollWidth<=innerWidth+2);
window.__retargetResult={ok:true,results,viewport:innerWidth};
}catch(e){window.__retargetResult={ok:false,results,error:String(e),errors:window.__retargetErrors};}
`;
const server=http.createServer((req,res)=>{
const p=decodeURIComponent(new URL(req.url,'http://127.0.0.1').pathname),file=path.resolve(root,'.'+p);
if(!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);res.end();return;}
let content=fs.readFileSync(file);if(p==='/motion-studio/retarget.html'){content=Buffer.from(content.toString().replace('<head>','<head><script>window.__retargetErrors=[];addEventListener("error",e=>{if(e.message)window.__retargetErrors.push(e.message)});addEventListener("unhandledrejection",e=>window.__retargetErrors.push(String(e.reason)));</script>').replace('</body>','<script type="module">'+browserProbe+'</script></body>'));}
res.writeHead(200,{'Content-Type':({'.html':'text/html; charset=utf-8','.js':'text/javascript','.json':'application/json','.svg':'image/svg+xml'})[path.extname(file)]||'application/octet-stream'});res.end(content);
});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
let chrome='';for(const x of ['google-chrome','chromium','chromium-browser']){try{chrome=execFileSync('which',[x],{encoding:'utf8'}).trim();if(chrome)break;}catch{}}
assert.ok(chrome,'Chrome/Chromium required; no silent skip');
await new Promise(r=>server.listen(0,'127.0.0.1',r));const port=server.address().port;
async function evalCDP(url,expression){return new Promise((resolve,reject)=>{const ws=new WebSocket(url);const timer=setTimeout(()=>{ws.close();reject(Error('CDP timeout'));},4000);ws.addEventListener('open',()=>ws.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{expression,returnByValue:true}})));ws.addEventListener('message',e=>{const m=JSON.parse(String(e.data));if(m.id!==1)return;clearTimeout(timer);ws.close();resolve(m.result?.result?.value);});ws.addEventListener('error',()=>{clearTimeout(timer);reject(Error('CDP failed'));});});}
try{for(const width of [500,1280]){const profile=fs.mkdtempSync(path.join(os.tmpdir(),'retarget-smoke-'));const c=spawn(chrome,['--headless=new','--no-sandbox','--disable-dev-shm-usage','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--remote-debugging-port=0','--remote-allow-origins=*','--user-data-dir='+profile,'--window-size='+width+',900','http://127.0.0.1:'+port+'/motion-studio/retarget.html'],{stdio:'ignore'});try{
let result;for(let i=0;i<1200;i++){await sleep(250);try{const debugPort=fs.readFileSync(path.join(profile,'DevToolsActivePort'),'utf8').split('\n')[0];const pages=await (await fetch('http://127.0.0.1:'+debugPort+'/json/list')).json();const page=pages.find(p=>p.type==='page'&&p.url.includes('retarget.html'));if(page){result=await evalCDP(page.webSocketDebuggerUrl,'window.__retargetResult');if(result)break;}}catch{}}
assert.ok(result?.ok,JSON.stringify(result||{error:'No browser result'}));assert.ok(width<800?result.viewport<=800:result.viewport>800,'Unexpected viewport');console.log('Retarget browser',width,JSON.stringify(result));}finally{c.kill('SIGKILL');await sleep(500);fs.rmSync(profile,{recursive:true,force:true,maxRetries:3});}}}finally{server.close();}
