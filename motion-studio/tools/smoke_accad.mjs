import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {spawn,execFileSync} from 'node:child_process';
const root=path.resolve(process.argv[2]||'.');
const dir=path.join(root,'motion-studio');
const manifest=JSON.parse(fs.readFileSync(path.join(dir,'assets/accad/manifest.json')));
const quality=JSON.parse(fs.readFileSync(path.join(dir,'assets/accad/quality.json')));
assert.equal(manifest.records.length,299);assert.equal(quality.count,299);
for(const r of manifest.records){assert.ok(fs.existsSync(path.join(dir,r.path)));assert.ok(fs.existsSync(path.join(dir,'assets/accad/thumbs',r.id+'.svg')));}
for(const page of ['index.html','kaykit.html'])assert.match(fs.readFileSync(path.join(dir,page),'utf8'),/href="\.\/accad\.html"/);
const kick=manifest.records.find(x=>x.name.includes('SpinningBackKick'));assert.ok(kick);
const browserProbe=String.raw`
const results=[];const check=(name,ok)=>{if(!ok)throw Error(name);results.push(name);};
const wait=async(fn)=>{for(let i=0;i<160;i++){if(fn())return;await new Promise(r=>setTimeout(r,100));}throw Error('等待超时 '+document.querySelector('#error')?.textContent);};
const $=id=>document.getElementById(id);
try{
await wait(()=>document.querySelectorAll('.clip').length===299);
check('299 catalog cards',document.querySelectorAll('.clip img').length===299);
check('canvas',!!document.querySelector('#viewer canvas'));
$('search').value='SpinningBackKick';$('search').dispatchEvent(new Event('input'));
check('search filter',document.querySelectorAll('.clip').length===1);
document.querySelector('.clip').click();await wait(()=>!$('play').disabled&&$('name').textContent.includes('SpinningBackKick'));
check('real BVH selected',$('details').textContent.includes('83 帧')&&!$('error').textContent);
await wait(()=>Number($('timeline').value)>1);$('play').click();
check('pause',$('play').textContent==='播放');
$('timeline').value='20';$('timeline').dispatchEvent(new Event('input'));await wait(()=>Number($('timeline').value)===20);
check('seek',Number($('timeline').value)===20);
$('display').value='bones';$('display').dispatchEvent(new Event('change'));$('display').value='human';$('display').dispatchEvent(new Event('change'));check('view switching',!$('error').textContent);
$('maprig').click();check('rig mapping',$('mapping').textContent.includes('22/22'));
$('quality').click();check('quality metadata',$('qualityout').textContent.includes('83 帧'));
check('BVH link',!$('download').hidden&&$('download').href.endsWith('.bvh'));
const blob=await (await fetch($('credit').href)).text();check('credit',blob.includes('CC BY 3.0')&&blob.includes('ACCAD'));
let exportHref='',exportName='';const oldClick=HTMLAnchorElement.prototype.click;try{HTMLAnchorElement.prototype.click=function(){exportHref=this.href;exportName=this.download;};$('glb').click();}finally{HTMLAnchorElement.prototype.click=oldClick;}
check('GLB export link',exportName.endsWith('.glb')&&exportHref.startsWith('blob:'));
const glb=await (await fetch(exportHref)).arrayBuffer();const view=new DataView(glb);check('GLB magic and size',view.getUint32(0,true)===0x46546c67&&view.getUint32(8,true)===glb.byteLength);const gltf=JSON.parse(new TextDecoder().decode(new Uint8Array(glb,20,view.getUint32(12,true))));check('GLB animation and license',gltf.animations[0].channels.length===23&&gltf.asset.extras.license==='CC BY 3.0');
for(const [name,frames] of [['Female1_A01_Stand',91],['Male1_A10_LieToCrouch',196]]){$('search').value=name;$('search').dispatchEvent(new Event('input'));const button=[...document.querySelectorAll('.clip')].find(el=>el.textContent.startsWith(name));check(name+' found',!!button);button.click();await wait(()=>$('name').textContent===name);check(name+' parsed',$('details').textContent.includes(frames+' 帧')&&!$('error').textContent);}
check('no script errors',!window.__accadErrors.length);
check('responsive document',document.documentElement.scrollWidth<=innerWidth+2);
window.__accadResult={ok:true,results,viewport:innerWidth};
}catch(e){window.__accadResult={ok:false,results,error:String(e),errors:window.__accadErrors};}
`;
const server=http.createServer((req,res)=>{
const p=decodeURIComponent(new URL(req.url,'http://127.0.0.1').pathname),file=path.resolve(root,'.'+p);
if(!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);res.end();return;}
let content=fs.readFileSync(file);if(p==='/motion-studio/accad.html'){content=Buffer.from(content.toString().replace('<head>','<head><script>window.__accadErrors=[];addEventListener("error",e=>{if(e.message)window.__accadErrors.push(e.message)});addEventListener("unhandledrejection",e=>window.__accadErrors.push(String(e.reason)));</script>').replace('</body>','<script type="module">'+browserProbe+'</script></body>'));}
res.writeHead(200,{'Content-Type':({'.html':'text/html; charset=utf-8','.js':'text/javascript','.json':'application/json','.svg':'image/svg+xml'})[path.extname(file)]||'application/octet-stream'});res.end(content);
});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
let chrome='';for(const x of ['google-chrome','chromium','chromium-browser']){try{chrome=execFileSync('which',[x],{encoding:'utf8'}).trim();if(chrome)break;}catch{}}
assert.ok(chrome,'Chrome/Chromium required; no silent skip');
await new Promise(r=>server.listen(0,'127.0.0.1',r));const port=server.address().port;
async function evalCDP(url,expression){return new Promise((resolve,reject)=>{const ws=new WebSocket(url);const timer=setTimeout(()=>{ws.close();reject(Error('CDP timeout'));},4000);ws.addEventListener('open',()=>ws.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{expression,returnByValue:true}})));ws.addEventListener('message',e=>{const m=JSON.parse(String(e.data));if(m.id!==1)return;clearTimeout(timer);ws.close();resolve(m.result?.result?.value);});ws.addEventListener('error',()=>{clearTimeout(timer);reject(Error('CDP failed'));});});}
try{for(const width of [500,1280]){const profile=fs.mkdtempSync(path.join(os.tmpdir(),'accad-smoke-'));const c=spawn(chrome,['--headless=new','--no-sandbox','--disable-dev-shm-usage','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--remote-debugging-port=0','--remote-allow-origins=*','--user-data-dir='+profile,'--window-size='+width+',900','http://127.0.0.1:'+port+'/motion-studio/accad.html'],{stdio:'ignore'});try{
let result;for(let i=0;i<160;i++){await sleep(250);try{const debugPort=fs.readFileSync(path.join(profile,'DevToolsActivePort'),'utf8').split('\n')[0];const pages=await (await fetch('http://127.0.0.1:'+debugPort+'/json/list')).json();const page=pages.find(p=>p.type==='page'&&p.url.includes('accad.html'));if(page){result=await evalCDP(page.webSocketDebuggerUrl,'window.__accadResult');if(result)break;}}catch{}}
assert.ok(result?.ok,JSON.stringify(result||{error:'No browser result'}));assert.ok(width<800?result.viewport<=800:result.viewport>800,'Unexpected viewport');console.log('ACCAD browser',width,JSON.stringify(result));}finally{c.kill('SIGKILL');await sleep(500);fs.rmSync(profile,{recursive:true,force:true,maxRetries:3});}}}finally{server.close();}
