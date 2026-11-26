#!/usr/bin/env python3
"""Import public CC0 KinemIQ GLB distribution. All clips are derivatives, never new unique motions."""
import hashlib,io,json,math,re,struct,urllib.request,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]/'assets'/'kinemiq'
SOURCE='https://huggingface.co/datasets/Kinemiq/free-game-animations'
URL=SOURCE+'/resolve/main/KinemIQ_Free_Animations_CC0_GLB.zip'
def glb(data):
    if len(data)<20 or struct.unpack_from('<III',data)!=(0x46546c67,2,len(data)):raise ValueError('invalid GLB header')
    n,t=struct.unpack_from('<II',data,12)
    if t!=0x4e4f534a or n%4 or n+20>len(data):raise ValueError('invalid JSON chunk')
    doc=json.loads(data[20:20+n]);pos=20+n;binlen=None
    while pos<len(data):
        if pos+8>len(data):raise ValueError('truncated chunk')
        size,kind=struct.unpack_from('<II',data,pos);pos+=8
        if size%4 or pos+size>len(data):raise ValueError('invalid chunk length')
        if kind==0x004e4942:binlen=size
        pos+=size
    if any(x.get('uri') and not x['uri'].startswith('data:') for x in doc.get('buffers',[])+doc.get('images',[])):raise ValueError('external resources')
    if binlen is not None and doc.get('buffers',[{}])[0].get('byteLength',0)>binlen:raise ValueError('invalid buffer length')
    return doc
def anim_info(doc,a):
    channels=a.get('channels',[]);samplers=a.get('samplers',[]);acc=doc.get('accessors',[]);nodes=doc.get('nodes',[])
    if not channels or not samplers:raise ValueError('empty animation')
    for ch in channels:
        if not 0<=ch['sampler']<len(samplers) or not 0<=ch['target']['node']<len(nodes):raise ValueError('invalid channel reference')
    end=[]
    for s in samplers:
        i,o=s['input'],s['output']
        if not 0<=i<len(acc) or not 0<=o<len(acc):raise ValueError('invalid accessor reference')
        z=acc[i];count=z['count']
        if z['type']!='SCALAR' or count<1:raise ValueError('invalid time accessor')
        v=z.get('max',[None])[0]
        if not isinstance(v,(int,float)) or not math.isfinite(v) or v<0:raise ValueError('missing time bound')
        end.append(v)
    return max(end)
def category(name):
    for label,p in [('剑术与格斗',r'sword|punch|jab|cross|hook|slash|attack|block'),('移动',r'walk|run|sprint|crouch'),('跳跃与闪避',r'jump|roll|climb'),('受击与倒地',r'hit|death|fall|get.?up'),('基础姿态',r'idle|stand|sit')]:
        if re.search(p,name,re.I):return label
    return '其他'
def fetch_archive():
    errors=[]
    try:
        req=urllib.request.Request(URL,headers={'User-Agent':'OoglexMotionStudio/4.6.2'})
        with urllib.request.urlopen(req,timeout=45) as f:raw=f.read(30_000_001)
        if zipfile.is_zipfile(io.BytesIO(raw)):return raw,URL
    except Exception as e:errors.append(str(e))
    try:
        api='https://api.github.com/repos/Kinemiq/free-game-animations/releases'
        with urllib.request.urlopen(urllib.request.Request(api,headers={'User-Agent':'OoglexMotionStudio/4.6.2'}),timeout=30) as f:releases=json.load(f)
        assets=[a for r in releases for a in r.get('assets',[]) if a['name']=='KinemIQ_Free_Animations_CC0_GLB.zip']
        for a in assets:
            url=a['browser_download_url']
            with urllib.request.urlopen(url,timeout=60) as f:raw=f.read(30_000_001)
            if zipfile.is_zipfile(io.BytesIO(raw)):return raw,url
    except Exception as e:errors.append(str(e))
    raise RuntimeError('official download unavailable: '+'; '.join(errors))
def main():
    raw,download_url=fetch_archive()
    if len(raw)>30_000_000:raise ValueError('archive too large')
    archive=hashlib.sha256(raw).hexdigest();records=[];models=[];payloads={};seen=set();excluded=[]
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        files=[x for x in z.infolist() if x.filename.lower().endswith('.glb') and not x.filename.startswith('__MACOSX/')]
        if not files or sum(x.file_size for x in files)>100_000_000:raise ValueError('invalid archive')
        for entry in sorted(files,key=lambda x:x.filename):
            if entry.file_size>25_000_000:raise ValueError('GLB size limit')
            data=z.read(entry);digest=hashlib.sha256(data).hexdigest()
            if digest in seen:continue
            seen.add(digest);doc=glb(data);file=digest[:24]+'.glb';payloads[file]=data
            mesh=bool(doc.get('meshes') and doc.get('skins'))
            if mesh:models.append(dict(path='assets/kinemiq/'+file,sha256=digest,original=entry.filename))
            print('source file',entry.filename,'skinned',mesh,'animations',[a.get('name') for a in doc.get('animations',[])])
            if mesh and re.search(r'mannequin',Path(entry.filename).stem,re.I):
                excluded.extend(dict(original=entry.filename,index=i,name=a.get('name'),reason='animation embedded in companion mannequin, not separately distributed clip') for i,a in enumerate(doc.get('animations',[])))
                continue
            for i,a in enumerate(doc.get('animations',[])):
                name=a.get('name') or Path(entry.filename).stem
                if len(doc['animations'])==1 and name.lower() in ('animation','take 001','action'):name=Path(entry.filename).stem
                records.append(dict(id=digest[:24]+'-'+str(i),name=name,category=category(name),path='assets/kinemiq/'+file,sha256=digest,index=i,duration=anim_info(doc,a),original=entry.filename,hasSkinnedMesh=mesh,license='CC0-1.0',original_author='Quaternius',adapter='KinemIQ',source=SOURCE,provenance='retargeted_derivative',unique_motion_credit=0))
    if not records or not models:raise ValueError('missing clips or mannequin')
    ROOT.mkdir(parents=True,exist_ok=True)
    for name,data in payloads.items():(ROOT/name).write_bytes(data)
    (ROOT/'manifest.json').write_text(json.dumps(dict(schema='ooglex.kinemiq.v1',source=SOURCE,archive_url=download_url,archive_sha256=archive,license_url='https://creativecommons.org/publicdomain/zero/1.0/',records=records,models=models,excluded_companion_animations=excluded,unique_motion_credit=0,scope='retargeted Quaternius derivatives, overlap not individually adjudicated'),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('validated clips',len(records),'models',len(models),'unique motion credit 0')
if __name__=='__main__':main()
