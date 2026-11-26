#!/usr/bin/env python3
"""Official human animation GLBs only; no test fixtures, no claimed skin conversion."""
import hashlib,json,re,urllib.request,urllib.parse
from pathlib import Path
from import_kinemiq import glb,anim_info,category
REPO='Mesh2Motion/mesh2motion-app'
API='https://api.github.com/repos/'+REPO
BASE=Path(__file__).resolve().parents[1]/'assets'/'mesh2motion'
def read(url,limit):
    req=urllib.request.Request(url,headers={'User-Agent':'OoglexMotionStudio/4.6.3.1'})
    with urllib.request.urlopen(req,timeout=90) as f:raw=f.read(limit+1)
    if len(raw)>limit:raise ValueError('download limit')
    return raw
def js(url):return json.loads(read(url,8_000_000))
def main():
    sha=js(API+'/commits/main')['sha']
    tree=js(API+'/git/trees/'+sha+'?recursive=1')
    if tree.get('truncated'):raise ValueError('truncated upstream tree')
    rawbase='https://raw.githubusercontent.com/'+REPO+'/'+sha+'/'
    license_text=read(rawbase+'LICENSE-CC0.MD',50_000).decode()
    if 'CC0' not in license_text:raise ValueError('missing CC0 declaration')
    entries=[x for x in tree['tree'] if x['type']=='blob' and re.fullmatch(r'static/assets/human/animations/[^/]+\.glb',x['path'],re.I)]
    if not entries:raise ValueError('official human animation directory missing')
    records=[];files=[];excluded=[];payloads={};seen=set();total=0
    for x in sorted(entries,key=lambda v:(not bool(re.search(r'kick|sword|melee|dodge|slash|fighting|attack|block',v['path'],re.I)),v['path'])):
        name=x['path'];size=x.get('size',0)
        if re.search(r'carnegie|cmu|mixamo|100style|accad|rest-pose',name,re.I):
            excluded.append({'path':name,'reason':'reference pose or third-party provenance review'});continue
        if size>20_000_000 or total+size>80_000_000:
            excluded.append({'path':name,'reason':'bounded artifact size'});continue
        data=read(rawbase+urllib.parse.quote(name),20_000_000)
        if hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()!=x['sha']:raise ValueError('upstream git blob mismatch: '+name)
        doc=glb(data);digest=hashlib.sha256(data).hexdigest()
        if digest in seen:continue
        seen.add(digest)
        if not doc.get('animations') or doc.get('extensionsRequired'):
            excluded.append({'path':name,'reason':'no animations or required decoder extension'});continue
        f=digest[:24]+'.glb';path='assets/mesh2motion/'+f
        try:
            items=[]
            for i,a in enumerate(doc['animations']):
                an=Path(name).stem if len(doc['animations'])==1 else (a.get('name') or Path(name).stem+' '+str(i))
                items.append({'id':digest[:24]+'-'+str(i),'name':an,'index':i,'duration':anim_info(doc,a),'category':category(an),'rig':'human','path':path,'sha256':digest,'original':name,'hasSkinnedMesh':bool(doc.get('meshes') and doc.get('skins')),'license':'CC0-1.0','source':rawbase+urllib.parse.quote(name),'unique_motion_credit':0})
        except (ValueError,KeyError,IndexError) as e:
            excluded.append({'path':name,'reason':str(e)});continue
        records.extend(items);payloads[f]=data;total+=len(data);files.append({'path':path,'sha256':digest,'original':name,'clips':len(items),'bytes':len(data)})
    if not records:raise ValueError('no genuine human animations')
    BASE.mkdir(parents=True,exist_ok=True)
    for name in BASE.glob('*.glb'):
        if name.name not in payloads:name.unlink()
    for f,data in payloads.items():(BASE/f).write_bytes(data)
    (BASE/'LICENSE-CC0.txt').write_text(license_text,encoding='utf-8')
    (BASE/'manifest.json').write_text(json.dumps({'schema':'ooglex.mesh2motion.v2','repository':'https://github.com/'+REPO,'source_commit':sha,'license':'CC0-1.0','records':records,'models':files,'excluded':excluded,'candidate_count':len(entries),'total_bytes':total,'unique_motion_credit':0,'scope':'official human animations only; skeleton preview, no new unique motion certification'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Imported',len(records),'animation entries across',len(files),'GLBs;',total,'bytes; exclusions',json.dumps(excluded,ensure_ascii=False))
if __name__=='__main__':main()
