#!/usr/bin/env python3
"""Import original CC BY 3.0 ACCAD BVH archives; no generated motion."""
import argparse, hashlib, io, json, math, re, urllib.request, zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets'/'accad'
SOURCE='https://accad.osu.edu/research/motion-lab/mocap-system-and-data'
BASE='https://accad.osu.edu/sites/accad.osu.edu/files/'
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
def main():
    p=argparse.ArgumentParser();p.add_argument('--zip-dir',type=Path);args=p.parse_args()
    records=[]; rejected=[]; seen=set(); pending={}
    for pack in PACKS:
        if args.zip_dir:
            raw=(args.zip_dir/pack).read_bytes()
        else:
            req=urllib.request.Request(BASE+pack,headers={'User-Agent':'OoglexMotionStudio/4.5.7'})
            with urllib.request.urlopen(req,timeout=120) as f: raw=f.read(200_000_001)
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
                category='武术格斗' if re.search(r'kick|punch|martial|fight|block|jab|stance|hook|uppercut|dodge',name,re.I) else '其他真人动作'
                file=digest[:24]+'.bvh'; pending[file]=data
                records.append(dict(id=digest[:24],name=name,category=category,pack=pack,path='assets/accad/'+file,frames=n,frameTime=dt,duration=(n-1)*dt,sha256=digest,original=f.filename,license='CC BY 3.0',author='ACCAD/The Ohio State University',source=SOURCE))
    if not records: raise RuntimeError('no validated clips')
    OUT.mkdir(parents=True,exist_ok=True)
    for name,data in pending.items(): (OUT/name).write_bytes(data)
    (OUT/'manifest.json').write_text(json.dumps(dict(source=SOURCE,license='https://creativecommons.org/licenses/by/3.0/',records=records,rejected=rejected),ensure_ascii=False,indent=2),encoding='utf-8')
    print('validated:',len(records),'rejected:',len(rejected))
if __name__=='__main__': main()
