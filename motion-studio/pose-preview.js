import * as T from 'three';
/* Draw only decoded source poses. No stock images or fabricated animation. */
export function bvhSegments(m,sampleFrame){
 const group=new T.Group(),nodes=[],frame=Math.min(m.frames-1,Math.max(0,sampleFrame??Math.floor(m.frames*.42)));
 for(const n of m.nodes){const o=new T.Object3D();o.position.fromArray(n.offset);
 for(let i=0;i<n.channels.length;i++){const c=n.channels[i],v=m.values[frame*m.channels+n.start+i],axis=c[0].toLowerCase();
 if(c.endsWith('position'))o.position[axis]+=v;else o.quaternion.multiply(new T.Quaternion().setFromAxisAngle(new T.Vector3(axis==='x'?1:0,axis==='y'?1:0,axis==='z'?1:0),v*Math.PI/180));}
 (n.parent<0?group:nodes[n.parent]).add(o);nodes.push(o);}
 group.updateMatrixWorld(true);return m.nodes.flatMap((n,i)=>n.parent<0?[]:[[nodes[n.parent].getWorldPosition(new T.Vector3()),nodes[i].getWorldPosition(new T.Vector3())]]);
}
export function hierarchyLinks(root,clip){
 const bones=[],tracked=new Set(clip.tracks.map(t=>T.PropertyBinding.parseTrackName(t.name).nodeName));
 root.traverse(o=>{if(o.isBone)bones.push(o);});
 const set=new Set(bones.length>1?bones:[]);if(set.size<2)root.traverse(o=>{if(tracked.has(o.name))set.add(o);});
 if(set.size<2)root.traverse(o=>{if(o!==root&&!o.isMesh)set.add(o);});
 const links=[];for(const o of set){let p=o.parent;while(p&&p!==root&&!set.has(p))p=p.parent;if(p&&set.has(p))links.push([p,o]);}
 if(!links.length)throw Error('没有可显示的骨架层级');return links;
}
export function glbSegments(root,clip){
 const mixer=new T.AnimationMixer(root);const action=mixer.clipAction(clip);action.play();mixer.setTime(Math.min(clip.duration*.42,Math.max(0,clip.duration-.001)));root.updateMatrixWorld(true);
 const segments=hierarchyLinks(root,clip).map(([a,b])=>[a.getWorldPosition(new T.Vector3()),b.getWorldPosition(new T.Vector3())]);
 mixer.stopAllAction();mixer.uncacheRoot(root);return segments;
}
export function poseImage(segments){
 if(!segments.length)throw Error('没有有效姿态');
 const project=v=>[v.x*.88-v.z*.47,-v.y*.97+(v.x*.47+v.z*.88)*.19];
 const lines=segments.map(pair=>pair.map(project)).filter(pair=>pair.flat().every(Number.isFinite));
 if(!lines.length)throw Error('姿态数值无效');const pts=lines.flat(),xs=pts.map(p=>p[0]),ys=pts.map(p=>p[1]);
 const minX=Math.min(...xs),maxX=Math.max(...xs),minY=Math.min(...ys),maxY=Math.max(...ys),span=Math.max(maxX-minX,maxY-minY);
 if(!(span>1e-8))throw Error('姿态尺寸无效');const scale=190/span;
 const p=([x,y])=>[(x-(minX+maxX)/2)*scale+120,(y-(minY+maxY)/2)*scale+120];
 const c=document.createElement('canvas');c.width=c.height=240;const ctx=c.getContext('2d');ctx.fillStyle='#25303c';ctx.fillRect(0,0,240,240);ctx.strokeStyle='#ffd16c';ctx.fillStyle='#ffe5a4';ctx.lineWidth=4;ctx.lineCap='round';
 for(const [a,b] of lines){const u=p(a),v=p(b);ctx.beginPath();ctx.moveTo(...u);ctx.lineTo(...v);ctx.stroke();}
 for(const q of pts){ctx.beginPath();ctx.arc(...p(q),2.9,0,Math.PI*2);ctx.fill();}
 return c.toDataURL('image/png');
}

/* Sample real motion at 12 fps. Long recordings use a 4-second excerpt. */
export function sampleTimes(duration){
 if(!Number.isFinite(duration)||duration<=0)throw Error('动作时长无效');
 const span=Math.min(duration,4),start=duration>4?(duration-span)*.42:0,count=Math.max(2,Math.ceil(span*12));
 return {times:Array.from({length:count},(_,i)=>start+i*span/count),span};
}
export function bvhMotion(m){
 const {times,span}=sampleTimes(m.duration);return packMotion(times.map(t=>bvhSegments(m,Math.round(t/m.dt))),span);
}
export function glbMotion(root,clip){
 const {times,span}=sampleTimes(clip.duration),links=hierarchyLinks(root,clip),mixer=new T.AnimationMixer(root),action=mixer.clipAction(clip);action.play();
 try{return packMotion(times.map(t=>{mixer.setTime(t);root.updateMatrixWorld(true);return links.map(([a,b])=>[a.getWorldPosition(new T.Vector3()),b.getWorldPosition(new T.Vector3())]);}),span);}
 finally{mixer.stopAllAction();mixer.uncacheRoot(root);}
}
/* A consistent camera scale across frames, root translation centered per frame. */
export function packMotion(poses,span){
 const project=v=>[v.x*.88-v.z*.47,-v.y*.97+(v.x*.47+v.z*.88)*.19];
 let extent=0;
 const centered=poses.map(segments=>{
  const raw=segments.map(pair=>pair.map(project)).filter(pair=>pair.flat().every(Number.isFinite));
  if(!raw.length)throw Error('姿态无有效骨骼');
  const pts=raw.flat(),xs=pts.map(p=>p[0]),ys=pts.map(p=>p[1]),minX=Math.min(...xs),maxX=Math.max(...xs),minY=Math.min(...ys),maxY=Math.max(...ys);
  extent=Math.max(extent,maxX-minX,maxY-minY);const cx=(minX+maxX)/2,cy=(minY+maxY)/2;
  return raw.flat(2).map((v,i)=>v-(i%2?cy:cx));
 });
 if(!(extent>1e-8))throw Error('姿态尺寸无效');
 return {span,frames:centered.map(values=>Float32Array.from(values,(v,i)=>v*178/extent+110))};
}
export function drawFrame(canvas,frame){
 const ctx=canvas.getContext('2d');ctx.fillStyle='#25303c';ctx.fillRect(0,0,220,220);
 ctx.lineCap='round';ctx.lineJoin='round';ctx.strokeStyle='#af7b26';ctx.lineWidth=7;
 const path=()=>{ctx.beginPath();for(let i=0;i<frame.length;i+=4){ctx.moveTo(frame[i],frame[i+1]);ctx.lineTo(frame[i+2],frame[i+3]);}ctx.stroke();};
 path();ctx.strokeStyle='#ffd16c';ctx.lineWidth=4.5;path();ctx.fillStyle='#ffe5a4';
 for(let i=0;i<frame.length;i+=2){ctx.beginPath();ctx.arc(frame[i],frame[i+1],2.9,0,Math.PI*2);ctx.fill();}
}

/* One shared offscreen WebGL renderer; cards play cached 2D sprite frames. */
let modelRenderer;
async function renderModelFrames(times,span,pose,bounds,root){
 const size=144,columns=Math.min(6,times.length),rows=Math.ceil(times.length/columns);
 const atlas=document.createElement('canvas');atlas.width=columns*size;atlas.height=rows*size;const ctx=atlas.getContext('2d');
 if(!modelRenderer){modelRenderer=new T.WebGLRenderer({antialias:true,alpha:false,preserveDrawingBuffer:true});modelRenderer.setPixelRatio(1);modelRenderer.setSize(size,size,false);}
 const scene=new T.Scene();scene.background=new T.Color(0x25303c);scene.add(root,new T.HemisphereLight(0xffffff,0x556070,2));
 const light=new T.DirectionalLight(0xffffff,2);light.position.set(3,5,4);scene.add(light);
 const camera=new T.PerspectiveCamera(42,1,.001,100),direction=new T.Vector3(.75,.30,1.9).normalize();
 let extent=0;const centers=[];
 for(const t of times){pose(t);root.updateMatrixWorld(true);const b=bounds();if(b.isEmpty())throw Error('模型边界无效');const v=b.getSize(new T.Vector3());extent=Math.max(extent,v.x,v.y,v.z);centers.push(b.getCenter(new T.Vector3()));}
 if(!(extent>0&&Number.isFinite(extent)))throw Error('模型尺寸无效');
 const dist=extent*.75/Math.tan(T.MathUtils.degToRad(camera.fov/2));camera.near=Math.max(.0001,extent*.002);camera.far=Math.max(100,extent*30);camera.updateProjectionMatrix();
 try{for(let i=0;i<times.length;i++){pose(times[i]);root.updateMatrixWorld(true);camera.position.copy(centers[i]).addScaledVector(direction,dist);camera.lookAt(centers[i]);modelRenderer.render(scene,camera);ctx.drawImage(modelRenderer.domElement,(i%columns)*size,Math.floor(i/columns)*size);if(i%4===3)await new Promise(r=>requestAnimationFrame(r));}}
 finally{scene.remove(root);}
 return {span,atlas,size,columns,frames:Array.from({length:times.length},(_,i)=>i)};
}
export async function skinnedMotion(root,clip){
 const {times,span}=sampleTimes(clip.duration),mixer=new T.AnimationMixer(root),action=mixer.clipAction(clip);action.play();
 const bones=[];root.traverse(o=>{if(o.isBone)bones.push(o);});
 const bounds=()=>{const box=new T.Box3();for(const b of bones)box.expandByPoint(b.getWorldPosition(new T.Vector3()));return box.isEmpty()?new T.Box3().setFromObject(root):box;};
 try{return await renderModelFrames(times,span,t=>mixer.setTime(t),bounds,root);}
 finally{mixer.stopAllAction();mixer.uncacheRoot(root);}
}
function paintMotion(canvas,motion,index){
 if(!motion.atlas){drawFrame(canvas,motion.frames[index]);return;}
 const ctx=canvas.getContext('2d'),{size,columns,atlas}=motion;ctx.drawImage(atlas,(index%columns)*size,Math.floor(index/columns)*size,size,size,0,0,220,220);
}

export function createThumbnails(load){
 const cache=new Map(),entries=new Map(),queue=[];let busy=false,last=0,raf=0;
 const observer=new IntersectionObserver(changes=>{
  for(const e of changes){const item=entries.get(e.target);if(!item)continue;item.visible=e.isIntersecting;
   if(item.visible&&!item.queued&&!item.motion){item.queued=true;queue.push(item);}
  }pump();schedule();
 },{rootMargin:'80px'});
 function schedule(){if(!raf&&[...entries.values()].some(x=>x.visible&&x.motion&&x.box.isConnected))raf=requestAnimationFrame(tick);}
 function tick(now){raf=0;if(now-last>=80){last=now;for(const item of entries.values()){
  if(!item.visible||!item.motion||!item.box.isConnected)continue;
  const {frames,span}=item.motion,index=Math.floor(((now-item.started)/1000%span)/span*frames.length)%frames.length;
  if(index!==item.index){paintMotion(item.canvas,item.motion,index);item.index=index;}
 }}schedule();}
 function show(item,motion){if(!item.box.isConnected||entries.get(item.box)!==item)return;item.motion=motion;item.started=performance.now();item.index=0;const canvas=document.createElement('canvas');canvas.width=canvas.height=220;canvas.setAttribute('role','img');canvas.setAttribute('aria-label',item.record.name+' 真实动作循环预览');item.canvas=canvas;paintMotion(canvas,motion,0);item.box.replaceChildren(canvas);item.box.dataset.preview='animated';schedule();}
 async function pump(){if(busy)return;busy=true;try{while(queue.length){const item=queue.shift();if(!item.box.isConnected||entries.get(item.box)!==item||!item.visible){item.queued=false;continue;}
  try{let motion=cache.get(item.record.id);if(!motion){motion=await load(item.record);cache.set(item.record.id,motion);if(cache.size>100)cache.delete(cache.keys().next().value);}show(item,motion);}
  catch(e){if(item.box.isConnected&&entries.get(item.box)===item){item.box.dataset.preview='error';item.box.title=e.message;if(!item.box.querySelector('img'))item.box.textContent='缩略动画加载失败 · 点击查看';}}
  finally{item.queued=false;}await new Promise(r=>requestAnimationFrame(r));
 }}finally{busy=false;}}
 return {reset(){observer.disconnect();entries.clear();queue.length=0;if(raf)cancelAnimationFrame(raf);raf=0;},add(record,box,staticSrc){
  const item={record,box,visible:false,queued:false,motion:null};entries.set(box,item);
  if(staticSrc){const img=document.createElement('img');img.loading='lazy';img.alt=record.name+' 真实姿态';img.src=staticSrc;img.onerror=()=>{if(!item.motion)box.textContent='读取真实动作…';};box.replaceChildren(img);}
  const cached=cache.get(record.id);if(cached){const canvas=document.createElement('canvas');canvas.width=canvas.height=220;canvas.setAttribute('aria-label',record.name+' 真实动作循环预览');canvas.setAttribute('role','img');item.canvas=canvas;item.motion=cached;item.started=performance.now();item.index=0;paintMotion(canvas,cached,0);box.replaceChildren(canvas);box.dataset.preview='animated';}
  observer.observe(box);
 }};
}
export function fitCamera(camera,controls,box){
 if(box.isEmpty())throw Error('无法计算可见骨架边界');const center=box.getCenter(new T.Vector3()),size=box.getSize(new T.Vector3()),extent=Math.max(size.x,size.y,size.z);
 if(!Number.isFinite(extent)||extent<=0)throw Error('骨架尺寸无效');const direction=new T.Vector3(.75,.30,1.9).normalize(),angle=T.MathUtils.degToRad(camera.fov/2),horizontal=Math.atan(Math.tan(angle)*Math.max(camera.aspect,.3)),dist=extent*.85/Math.tan(Math.min(angle,horizontal));
 camera.near=Math.max(.0001,extent*.002);camera.far=Math.max(100,extent*30);camera.position.copy(center).addScaledVector(direction,dist);camera.updateProjectionMatrix();controls.target.copy(center);controls.update();
}
