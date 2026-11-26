// Ooglex public animation asset tools. No upload, server processing or third-party dependencies.
const $ = id => document.getElementById(id);
const enc = new TextEncoder(), dec = new TextDecoder();
const finite = a => Array.prototype.every.call(a, Number.isFinite);
const rounded = n => Number(n.toFixed(6));
function parseGLB(buffer) {
  const v=new DataView(buffer);
  if(v.byteLength<20 || v.getUint32(0,true)!==0x46546c67 || v.getUint32(4,true)!==2 || v.getUint32(8,true)!==v.byteLength) throw Error('无效 GLB 2.0');
  let doc, bin; const chunks=[];
  for(let p=12;p<v.byteLength;) {
    if(p+8>v.byteLength) throw Error('GLB 数据块头不完整');
    const n=v.getUint32(p,true), t=v.getUint32(p+4,true);
    if(n%4 || p+8+n>v.byteLength) throw Error('GLB 数据块长度异常');
    const b=new Uint8Array(buffer,p+8,n);
    if(t===0x4e4f534a) doc=JSON.parse(dec.decode(b));
    else {chunks.push({type:t,bytes:b});if(t===0x004e4942)bin=b;}
    p+=8+n;
  }
  if(!doc || !bin) throw Error('缺少 JSON 或 BIN 数据块');
  return {doc,bin,chunks};
}
function scalarTimes(gl,index) {
  const a=gl.doc.accessors?.[index];
  if(!a || a.type!=='SCALAR' || a.componentType!==5126 || a.sparse || !Number.isInteger(a.count) || a.count<1) return null;
  const bv=gl.doc.bufferViews?.[a.bufferView];
  if(!bv || bv.buffer!==0)return null;
  const offset=(bv.byteOffset||0)+(a.byteOffset||0), stride=bv.byteStride||4;
  if(stride<4 || offset<0 || offset+(a.count-1)*stride+4>gl.bin.byteLength || (a.byteOffset||0)+(a.count-1)*stride+4>bv.byteLength)return null;
  const v=new DataView(gl.bin.buffer,gl.bin.byteOffset,gl.bin.byteLength), out=new Array(a.count);
  for(let i=0;i<a.count;i++)out[i]=v.getFloat32(offset+i*stride,true);
  return out;
}
function analyse(gl,r,p) {
  const a=gl.doc.animations?.[r.index];
  if(!a||a.name!==r.source)throw Error('源动画索引不一致');
  const checks=[], add=(item,ok,detail)=>checks.push({item,status:ok===null?'未检测':ok?'通过':'异常',detail});
  const duration=r.clip.duration;
  add('时长',Number.isFinite(duration)&&duration>=0,rounded(duration)+' 秒');
  add('动画轨道',r.clip.tracks.length>0,r.clip.tracks.length+' 条解码轨道');
  add('数值有效性',r.clip.tracks.every(t=>finite(t.times)&&finite(t.values)),'检查全部解码关键帧时间和值是否为有限数');
  const channels=a.channels||[], samplers=a.samplers||[];
  add('通道与采样器引用',channels.length>0&&channels.every(c=>Number.isInteger(c.sampler)&&!!samplers[c.sampler]&&Number.isInteger(c.target?.node)&&!!gl.doc.nodes?.[c.target.node]),channels.length+' 条源通道');
  const inputs=[...new Set(samplers.map(s=>s.input))], timelines=inputs.map(i=>scalarTimes(gl,i));
  const readable=timelines.every(t=>t!==null)&&timelines.length>0;
  add('源关键帧时间顺序',readable?timelines.every(t=>finite(t)&&t.every((v,i)=>i===0||v>t[i-1])):null,readable?inputs.length+' 个时间采样器':'源时间格式无法直接检查');
  const countOK=samplers.every(s=>{const x=gl.doc.accessors?.[s.input], y=gl.doc.accessors?.[s.output];return !!x&&!!y&&x.count>0&&y.count>0;});
  add('采样器数据引用',countOK,samplers.length+' 个采样器');
  let samples=null, hz=null, uniform=null, start=null, end=null;
  if(readable&&timelines.every(t=>finite(t))) {
    const union=timelines.flat().sort((a,b)=>a-b), unique=[];
    for(const t of union)if(!unique.length||Math.abs(t-unique[unique.length-1])>1e-5)unique.push(t);
    samples=unique.length;start=unique[0];end=unique[unique.length-1];
    if(samples>1){const step=(end-start)/(samples-1);uniform=step>0&&unique.every((t,i)=>Math.abs(t-(start+i*step))<=Math.max(2e-5,step*.002));if(uniform)hz=rounded(1/step);}
  }
  add('时间采样统计',null,samples===null?'无法读取':samples+' 个独立时间点；'+(uniform===true?'近似均匀':uniform===false?'非均匀':'不足以推断频率'));
  add('蒙皮骨骼',p.bones>0,p.bones+' 根实际预览骨骼');
  add('足部滑动、接地、IK、武器轨迹、动作自然度',null,'尚未进行空间运动学或人工视觉质量认证');
  return {schema:'ooglex.motion.asset.v1',asset_id:r.id,library:p.provider,source_file:p.file,source_animation:r.source,animation_index:r.index,name_zh:r.name,category:r.category,rig:r.rig||null,duration_seconds:rounded(duration),bone_count:p.bones,channel_count:channels.length,track_count:r.clip.tracks.length,sampler_count:samplers.length,keyframe_time_points:samples,sampling_uniform:uniform,inferred_keyframe_hz:hz,source_fps:null,source_frame_count:null,time_start:start===null?null:rounded(start),time_end:end===null?null:rounded(end),license:'CC0-1.0',license_url:'https://creativecommons.org/publicdomain/zero/1.0/',source_url:p.sourceURL,quality:{scope:'结构与数值基础检测，非生产级认证',checks}};
}
// Preserve the source mesh, skeleton, and binary chunks losslessly. Only the chosen animation remains in the GLB animation table.
function singleGLB(gl,index) {
  const d=JSON.parse(JSON.stringify(gl.doc));
  if(!d.animations?.[index])throw Error('找不到该动画');
  d.animations=[d.animations[index]];
  const raw=enc.encode(JSON.stringify(d)), n=Math.ceil(raw.length/4)*4;
  const total=12+8+n+gl.chunks.reduce((sum,c)=>sum+8+c.bytes.length,0);
  const out=new Uint8Array(total),v=new DataView(out.buffer);
  v.setUint32(0,0x46546c67,true);v.setUint32(4,2,true);v.setUint32(8,total,true);
  v.setUint32(12,n,true);v.setUint32(16,0x4e4f534a,true);
  out.fill(32,20,20+n);out.set(raw,20);
  let p=20+n;
  for(const c of gl.chunks){v.setUint32(p,c.bytes.length,true);v.setUint32(p+4,c.type,true);out.set(c.bytes,p+8);p+=8+c.bytes.length;}
  return out;
}
function download(data,name,type='application/json') {
  const u=URL.createObjectURL(new Blob([data],{type})), a=document.createElement('a');
  a.href=u;a.download=name;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(u),30000);
}
function boneNames(g) {
  const set=new Set();g.traverse(o=>{if(o.isSkinnedMesh)for(const b of o.skeleton.bones)set.add(b.name);});
  return [...set].filter(Boolean);
}
function norm(s){return s.toLowerCase().replace(/^mixamorig[:_]?/,'').replace(/[^a-z0-9]/g,'');}
export function attachAssetTools({getSelection,getPack,loader,providerInfo}) {
  let current=null, target=null, targetFile=null, importToken=0;
  const status=s=>$('toolstatus').textContent=s;
  const safe=()=>{if(!current)throw Error('请先选择一个动作');return current;};
  const run=fn=>async()=>{try{await fn();}catch(e){status('操作失败：'+e.message);}};
  function refresh() {
    current=null;$('toolreport').hidden=true;$('toolreport').replaceChildren();
    for(const id of ['tooljson','toolglb','toollicense','toolquality','toolpack','toolmap'])$(id).disabled=true;
    try {
      const r=getSelection();if(!r)return;
      const pack=getPack(r.pack);if(!pack)return;
      const info=providerInfo(r);
      const p={...pack,...info};
      const gl=parseGLB(p.buffer), meta=analyse(gl,r,p);
      current={r,p,gl,meta};
      $('facttracks').textContent=meta.track_count+' 条';
      $('factsamples').textContent=meta.keyframe_time_points===null?'无法读取':meta.keyframe_time_points+' 个';
      $('facthz').textContent=meta.inferred_keyframe_hz!==null?meta.inferred_keyframe_hz+' Hz（推算）':meta.sampling_uniform===false?'非均匀采样':'无法推算';
      $('factframes').textContent='源帧数 / FPS 未声明';
      $('factfile').textContent=p.file;
      for(const id of ['tooljson','toolglb','toollicense','toolquality','toolpack'])$(id).disabled=false;
      $('toolmap').disabled=!target;
      status('资产工具已就绪；源帧数与 FPS 不作假定。');
    }catch(e){status('技术参数读取失败：'+e.message);}
  }
  $('toolquality').onclick=run(()=>{
    const {meta}=safe(), el=$('toolreport');el.replaceChildren();el.hidden=false;
    for(const row of meta.quality.checks){const line=document.createElement('p');const strong=document.createElement('strong');strong.textContent=row.item+' · '+row.status;line.append(strong,document.createElement('br'),document.createTextNode(row.detail));el.append(line);}
    status('基础结构与数值检测完成，未执行 IK 或人工动作质量认证。');
  });
  $('tooljson').onclick=run(()=>{const {meta}=safe();download(JSON.stringify(meta,null,2),meta.asset_id.replace(/:/g,'-')+'_metadata.json');status('已生成当前动作 JSON 元数据。');});
  $('toolglb').onclick=run(()=>{
    const {r,gl}=safe(), data=singleGLB(gl,r.index);
    const check=parseGLB(data.buffer);
    if(check.doc.animations.length!==1||check.doc.animations[0].name!==r.source)throw Error('导出校验失败');
    download(data,r.name+'_'+r.id.replace(/:/g,'-')+'.glb','model/gltf-binary');
    status('已生成单动画 GLB；保留源模型、蒙皮及原始二进制块，文件体积可能接近原包。');
  });
  $('toolpack').onclick=run(()=>{const {p}=safe();download(p.buffer,p.file,'model/gltf-binary');status('已生成当前来源动画包下载。');});
  $('toollicense').onclick=run(async()=>{
    const {p}=safe();
    const response=await fetch(p.licensePath);
    if(!response.ok)throw Error('授权记录读取失败');
    download(await response.text(),p.provider.replace(/\W+/g,'_')+'_LICENSE.txt','text/plain;charset=utf-8');
    status('已生成来源授权记录下载。');
  });
  $('toolimport').onclick=()=>$('toolfile').click();
  $('toolfile').onchange=run(async()=>{
    const token=++importToken, file=$('toolfile').files?.[0];$('toolfile').value='';if(!file)return;
    if(file.size>100*1024*1024)throw Error('本地预检文件上限为 100 MB');
    const buffer=await file.arrayBuffer(), gl=parseGLB(buffer);
    if([...(gl.doc.buffers||[]),...(gl.doc.images||[])].some(x=>x.uri&&!x.uri.startsWith('data:')))throw Error('仅接受自包含 GLB，不读取外部资源');
    const g=await loader.parseAsync(buffer,'');
    const names=boneNames(g.scene);
    // Only names are retained: target never leaves the browser, and it does not replace the playing model.
    g.scene.traverse(o=>{if(o.geometry)o.geometry.dispose();for(const m of [].concat(o.material||[])){for(const v of Object.values(m))if(v?.isTexture)v.dispose();m.dispose();}});
    if(token!==importToken)return;
    if(!names.length)throw Error('未检测到带蒙皮骨骼的目标角色');
    target=names;targetFile=file.name;$('toolmap').disabled=!current;
    status('本地目标已读取：'+file.name+'，'+names.length+' 个具名骨骼。未上传文件。');
  });
  $('toolmap').onclick=run(()=>{
    const {p}=safe();if(!target)throw Error('请先导入目标角色');
    const src=boneNames(p.model), lookup=new Map();
    for(const b of target){const k=norm(b);if(!lookup.has(k))lookup.set(k,[]);lookup.get(k).push(b);}
    const sourceCounts=new Map();for(const b of src){const k=norm(b);sourceCounts.set(k,(sourceCounts.get(k)||0)+1);}
    const matched=[],unmatched=[];
    for(const b of src){const k=norm(b), candidates=lookup.get(k)||[];if(k&&sourceCounts.get(k)===1&&candidates.length===1)matched.push({source:b,target:candidates[0]});else unmatched.push({source:b,candidates});}
    const report={target_file:targetFile,source_bones:src.length,target_bones:target.length,matched,unmatched,scope:'仅名称唯一匹配；未验证层级、绑定姿势、轴向或比例；不是可执行重定向认证'};
    $('toolreport').hidden=false;$('toolreport').replaceChildren();
    const h=document.createElement('p');h.textContent='名称匹配 '+matched.length+' / '+src.length+'；未匹配或歧义 '+unmatched.length+'。仅预检，不执行重定向。';
    const pre=document.createElement('pre');pre.textContent=JSON.stringify(report,null,2);
    const b=document.createElement('button');b.textContent='下载骨骼映射预检 JSON';b.onclick=()=>download(JSON.stringify(report,null,2),'bone_mapping_precheck.json');
    $('toolreport').append(h,b,pre);status('骨骼名称映射预检完成，实际重定向仍需绑定姿势及轴向验证。');
  });
  return {refresh};
}
