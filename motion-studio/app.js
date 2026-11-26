import * as THREE from 'three';
import {GLTFLoader} from './vendor/examples/jsm/loaders/GLTFLoader.js';
import {OrbitControls} from './vendor/examples/jsm/controls/OrbitControls.js';

const $ = id => document.getElementById(id);
const view = $('viewer');
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x141b24);

const camera = new THREE.PerspectiveCamera(42,1,0.01,500);
const renderer = new THREE.WebGLRenderer({antialias:true});
renderer.setPixelRatio(Math.min(devicePixelRatio,1.5));
view.appendChild(renderer.domElement);

const controls = new OrbitControls(camera,renderer.domElement);
controls.enableDamping = true;

scene.add(new THREE.HemisphereLight(0xffffff,0x526070,2.5));

const light = new THREE.DirectionalLight(0xffffff,3);
light.position.set(4,6,5);
scene.add(light);

const fill = new THREE.DirectionalLight(0xb7d9ff,1.5);
fill.position.set(-4,3,-3);
scene.add(fill);

scene.add(new THREE.GridHelper(12,24,0x526375,0x303b49));

const loader = new GLTFLoader();
const clock = new THREE.Clock();

let model,mixer,action,animations=[];
let playing=true;
let request=0;

function resize(){
 const w=view.clientWidth,h=view.clientHeight;
 renderer.setSize(w,h,false);
 camera.aspect=w/Math.max(h,1);
 camera.updateProjectionMatrix();
}
new ResizeObserver(resize).observe(view);
resize();

function fit(){
 if(!model)return;
 const box=new THREE.Box3().setFromObject(model);
 const center=box.getCenter(new THREE.Vector3());
 const size=box.getSize(new THREE.Vector3());
 const d=Math.max(size.x,size.y,size.z,0.5);
 controls.target.copy(center);
 camera.position.copy(center).add(new THREE.Vector3(d*1.3,d*0.6,d*2.0));
 controls.update();
}

function disposeModel(){
 if(!model)return;
 if(mixer){
   mixer.stopAllAction();
   mixer.uncacheRoot(model);
 }
 scene.remove(model);
 model.traverse(o=>{
   if(o.geometry)o.geometry.dispose();
   for(const m of [].concat(o.material||[])){
     for(const v of Object.values(m))
       if(v?.isTexture)v.dispose();
     m.dispose();
   }
 });
 model=null;mixer=null;action=null;
}

function chooseClip(i){
 if(!mixer||!animations[i])return;
 mixer.stopAllAction();
 action=mixer.clipAction(animations[i]);
 action.reset().play();
 action.timeScale=Number($('speed').value);
 playing=true;
}

async function load(url,name){
 const token=++request;
 $('status').textContent='正在加载：'+name;
 try{
   const g=await loader.loadAsync(url);
   if(token!==request)return;
   disposeModel();
   model=g.scene;
   scene.add(model);
   animations=g.animations;
   mixer=new THREE.AnimationMixer(model);
   $('clips').replaceChildren();
   animations.forEach((clip,i)=>{
     const opt=document.createElement('option');
     opt.value=i;opt.textContent=clip.name||('动作 '+(i+1));
     $('clips').append(opt);
   });
   if(animations.length)chooseClip(0);
   fit();
   $('status').textContent=name+' · '+animations.length+' 个动画片段';
 }catch(e){
   $('status').textContent='加载失败：'+e.message;
 }
}

async function loadLocal(file){
 const b=await file.arrayBuffer();
 const dv=new DataView(b);
 if(b.byteLength<20||dv.getUint32(0,true)!==0x46546c67){
   $('status').textContent='不是有效GLB文件';return;
 }
 const n=dv.getUint32(12,true);
 const d=JSON.parse(new TextDecoder().decode(b.slice(20,20+n)));
 if([...d.buffers||[],...d.images||[]].some(
   x=>x.uri&&!x.uri.startsWith('data:')
 )){
   $('status').textContent='仅接受自包含GLB文件';return;
 }
 const u=URL.createObjectURL(new Blob([b],{type:'model/gltf-binary'}));
 try{await load(u,file.name)}
 finally{URL.revokeObjectURL(u)}
}

function listFiles(files){
 const items=[...files].filter(f=>f.name.toLowerCase().endsWith('.glb'));
 $('files').replaceChildren();
 $('count').textContent='本地GLB：'+items.length;
 for(const f of items){
   const btn=document.createElement('button');
   btn.textContent=f.webkitRelativePath||f.name;
   btn.onclick=()=>loadLocal(f).catch(e=>{
     $('status').textContent=e.message;
   });
   $('files').append(btn);
 }
}

$('upload').onchange=e=>listFiles(e.target.files);
$('directory').onchange=e=>listFiles(e.target.files);
$('play').onclick=()=>playing=!playing;
$('reset').onclick=fit;
$('clips').onchange=e=>chooseClip(Number(e.target.value));
$('speed').onchange=e=>{if(action)action.timeScale=Number(e.target.value)};
$('timeline').oninput=e=>{
 if(action&&mixer){
   playing=false;
   mixer.setTime(Number(e.target.value)/1000*action.getClip().duration/Math.max(action.timeScale,0.001));
 }
};

renderer.setAnimationLoop(()=>{
 const dt=Math.min(clock.getDelta(),0.1);
 if(mixer&&playing)mixer.update(dt);
 if(action&&action.getClip().duration)
   $('timeline').value=1000*action.time/action.getClip().duration;
 controls.update();
 renderer.render(scene,camera);
});


async function openPublicLibrary(){

 await load(
   './assets/public/library.glb',
   'Quaternius · CC0'
 );

 if(!model || !animations.length){
   $('publicCount').textContent='公开动作库加载失败';
   return;
 }

 const initial = animations.findIndex(
   a => /idle/i.test(a.name)
 );

 const first = initial >= 0 ? initial : 0;

 chooseClip(first);
 $('clips').value = first;

 function renderActions(){

   const q = $('actionSearch').value.toLowerCase();
   const list = $('publicActions');

   list.replaceChildren();

   animations.forEach((clip,i)=>{

     if(!clip.name.toLowerCase().includes(q))return;

     const btn = document.createElement('button');

     btn.textContent =
       clip.name + ' · ' + clip.duration.toFixed(2) + 's';

     btn.classList.toggle(
       'active', Number($('clips').value)===i
     );

     btn.onclick=()=>{
       chooseClip(i);
       $('clips').value=i;
       $('status').textContent=
         clip.name+' · CC0 · '+clip.duration.toFixed(2)+'秒';
       renderActions();
     };

     list.append(btn);
   });

   $('publicCount').textContent=
     '公开动作：'+animations.length+
     ' · 当前显示：'+list.children.length;
 }

 $('actionSearch').oninput=renderActions;

 $('clips').onchange=()=>{
   chooseClip(Number($('clips').value));
   renderActions();
 };

 renderActions();
}

openPublicLibrary().catch(e=>{
 $('status').textContent='加载失败：'+e.message;
});

