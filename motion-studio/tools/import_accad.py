#!/usr/bin/env python3
"""Import original CC BY 3.0 ACCAD BVH archives; no generated motion."""
import argparse, hashlib, io, json, math, re, urllib.request, zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets'/'accad'
SOURCE='https://accad.osu.edu/research/motion-lab/mocap-system-and-data'
BASE='https://accad.osu.edu/sites/accad.osu.edu/files/'
MIRROR='https://accad.ohio-state.edu/sites/accad.osu.edu/files/'
PACKS=['Male2_bvh.zip','Male1_bvh.zip','Female1_bvh.zip']
def inspect(data):
    text=data.decode('utf-8-sig')
    head,sep,body=text.partition('MOTION')
    if not sep or 'HIERARCHY' not in head or 'ROOT' not in head: raise ValueError('missing hierarchy')
    m=re.search(r'Frames:\s*(\d+)\s+Frame Time:\s*([0-9.eE+-]+)\s*',body)
    if not m: raise ValueError('missing frame header')
    n=int(m[1]); dt=float(m[2])
    channels=sum(int(x) for x in re.findall(r'CHANNELS\s+(\d+)',head))
    vals=body[m.end():].split()
    if not (n>1 and 0<dt<1 and channels>0 and len(vals)==n*channels and all(math.isfinite(float(v)) for v in vals)): raise ValueError('invalid frame samples')
    return n,dt
def classify(name):
    rules=[('校准与参考姿态',r'calibrat|t.?pose|reference'),('武术腿法',r'kick|round.?house|crescent|capoeira'),('武术拳法',r'punch|jab|hook|uppercut|strike'),('武术招架与站姿',r'block|guard|stance|ready|taunt'),('武术步法与转身',r'martial.*(?:walk|turn)|dodge|shuffle|fight'),('跳跃与翻腾',r'jump|spring|flip|roll'),('行走与转身',r'walk|turn'),('奔跑与冲刺',r'run|jog|sprint'),('日常与交互',r'sit|stand|gesture|reach|pick|crouch')]
    return next((cat for cat,pattern in rules if re.search(pattern,name,re.I)),'其他真人动作')
def fetch_archive(pack):
    errors=[]
    for base in (BASE,MIRROR):
        try:
            req=urllib.request.Request(base+pack,headers={'User-Agent':'OoglexMotionStudio/4.5.8'})
            with urllib.request.urlopen(req,timeout=90) as f: raw=f.read(200_000_001)
            if len(raw)>200_000_000 or not zipfile.is_zipfile(io.BytesIO(raw)): raise ValueError('not a valid ZIP')
            return raw
        except (OSError,ValueError) as e: errors.append(str(e))
    raise RuntimeError(pack+': '+'; '.join(errors))
def main():
    p=argparse.ArgumentParser();p.add_argument('--zip-dir',type=Path);p.add_argument('--pack',choices=PACKS,action='append');args=p.parse_args()
    records=[]; rejected=[]; seen=set(); pending={}
    for pack in (args.pack or PACKS):
        if args.zip_dir:
            raw=(args.zip_dir/pack).read_bytes()
        else:
            raw=fetch_archive(pack)
        if len(raw)>200_000_000: raise ValueError('archive too large')
        with zipfile.ZipFile(io.BytesIO(raw)) as z:
            files=[i for i in z.infolist() if i.filename.lower().endswith('.bvh') and not i.filename.startswith('__MACOSX/')]
            if not files or sum(i.file_size for i in files)>500_000_000: raise ValueError('invalid BVH archive')
            for f in sorted(files,key=lambda i:i.filename):
                if f.file_size>15_000_000: rejected.append([pack,f.filename,'file too large']);continue
                data=z.read(f); digest=hashlib.sha256(data).hexdigest()
                if digest in seen: continue
                try: n,dt=inspect(data)
                except (ValueError,UnicodeError) as e: rejected.append([pack,f.filename,str(e)]);continue
                seen.add(digest)
                name=Path(f.filename).stem
                category=classify(name)
                if category=='校准与参考姿态': rejected.append([pack,f.filename,'calibration/reference']);continue
                file=digest[:24]+'.bvh'; pending[file]=data
                records.append(dict(id=digest[:24],name=name,category=category,pack=pack,path='assets/accad/'+file,frames=n,frameTime=dt,duration=(n-1)*dt,sha256=digest,original=f.filename,license='CC BY 3.0',author='ACCAD/The Ohio State University',source=SOURCE))
    if not records: raise RuntimeError('no validated clips')
    manifest=OUT/'manifest.json'
    if args.pack and manifest.exists():
        old=json.loads(manifest.read_text(encoding='utf-8'))
        previous=[x for x in old['records'] if x['pack'] not in args.pack and x['sha256'] not in seen]
        records=previous+records
    OUT.mkdir(parents=True,exist_ok=True)
    for name,data in pending.items(): (OUT/name).write_bytes(data)
    (OUT/'manifest.json').write_text(json.dumps(dict(source=SOURCE,license='https://creativecommons.org/licenses/by/3.0/',records=records,rejected=rejected),ensure_ascii=False,indent=2),encoding='utf-8')
    print('validated:',len(records),'rejected:',len(rejected))
if __name__=='__main__': main()
