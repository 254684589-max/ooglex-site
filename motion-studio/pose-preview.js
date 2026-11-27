import * as T from 'three';
/* Draw only decoded source poses. No stock images or fabricated animation. */
export function bvhSegments(m){
 const group=new T.Group(),nodes=[],frame=Math.min(m.frames-1,Math.floor(m.frames*.42));
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
export function createThumbnails(load){
 const results=new Map(),pending=new Map(),queue=[];let busy=false;
 const observer=new IntersectionObserver(entries=>{for(const e of entries){if(!e.isIntersecting)continue;observer.unobserve(e.target);const item=pending.get(e.target);pending.delete(e.target);if(item)queue.push(item);}pump();},{rootMargin:'150px'});
 async function pump(){if(busy)return;busy=true;try{while(queue.length){const {record,box}=queue.shift();if(!box.isConnected)continue;try{let src=results.get(record.id);if(!src){src=await load(record);results.set(record.id,src);}if(box.isConnected)show(box,src,record.name);}catch(e){if(box.isConnected){box.textContent='取帧失败 · 点击播放';box.title=e.message;}}await new Promise(r=>requestAnimationFrame(r));}}finally{busy=false;}}
 function show(box,src,name){const img=document.createElement('img');img.alt=name+' 真实动作取帧';img.src=src;box.replaceChildren(img);}
 return {reset(){observer.disconnect();pending.clear();queue.length=0;},add(record,box,staticSrc){if(results.has(record.id)){show(box,results.get(record.id),record.name);return;}if(staticSrc){const img=document.createElement('img');img.loading='lazy';img.alt=record.name+' 真实骨架取帧';img.src=staticSrc;img.onerror=()=>{box.textContent='读取真实姿态…';pending.set(box,{record,box});observer.observe(box);};box.replaceChildren(img);return;}pending.set(box,{record,box});observer.observe(box);}};
}
export function fitCamera(camera,controls,box){
 if(box.isEmpty())throw Error('无法计算可见骨架边界');const center=box.getCenter(new T.Vector3()),size=box.getSize(new T.Vector3()),extent=Math.max(size.x,size.y,size.z);
 if(!Number.isFinite(extent)||extent<=0)throw Error('骨架尺寸无效');const direction=new T.Vector3(.75,.30,1.9).normalize(),angle=T.MathUtils.degToRad(camera.fov/2),horizontal=Math.atan(Math.tan(angle)*Math.max(camera.aspect,.3)),dist=extent*.85/Math.tan(Math.min(angle,horizontal));
 camera.near=Math.max(.0001,extent*.002);camera.far=Math.max(100,extent*30);camera.position.copy(center).addScaledVector(direction,dist);camera.updateProjectionMatrix();controls.target.copy(center);controls.update();
}
