#!/usr/bin/env python3
"""Import official Mesh2Motion packaged GLBs, preserving provenance and excluding ambiguous sources."""
import hashlib,json,re,urllib.request,urllib.parse
from pathlib import Path
from import_kinemiq import glb,anim_info,category
REPO='Mesh2Motion/mesh2motion-app'
API='https://api.github.com/repos/'+REPO
BASE=Path(__file__).resolve().parents[1]/'assets'/'mesh2motion'
def read(url,limit):
    req=urllib.request.Request(url,headers={'User-Agent':'OoglexMotionStudio/4.6.3'})
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
    entries=[x for x in tree['tree'] if x['type']=='blob' and x['path'].startswith('static/animations/') and x['path'].lower().endswith('.glb')]
    if not entries:raise ValueError('no official GLB candidates')
    records=[];files=[];excluded=[];payloads={};seen=set();total=0
    for x in sorted(entries,key=lambda v:v['path']):
        name=x['path'];size=x.get('size',0)
        if re.search(r'carnegie|cmu|mixamo|100style|accad',name,re.I):
            excluded.append({'path':name,'reason':'third-party provenance requires separate license audit'});continue
        if size>45_000_000 or total+size>80_000_000:
            excluded.append({'path':name,'reason':'bounded initial public artifact size'});continue
        data=read(rawbase+urllib.parse.quote(name),45_000_000)
        if hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()!=x['sha']:raise ValueError('upstream git blob mismatch: '+name)
        doc=glb(data);digest=hashlib.sha256(data).hexdigest()
        if digest in seen:continue
        seen.add(digest)
        if not doc.get('skins') or not doc.get('meshes') or not doc.get('animations'):
            excluded.append({'path':name,'reason':'not a self-contained animated skinned model'});continue
        if doc.get('extensionsRequired'):
            excluded.append({'path':name,'reason':'decoder extension needs separate browser validation','extensions':doc['extensionsRequired']});continue
        f=digest[:24]+'.glb';path='assets/mesh2motion/'+f
        for i,a in enumerate(doc['animations']):
            an=a.get('name') or 'Animation '+str(i+1)
            records.append({'id':digest[:24]+'-'+str(i),'name':an,'index':i,'duration':anim_info(doc,a),'category':category(an),'rig':Path(name).stem,'path':path,'sha256':digest,'original':name,'hasSkinnedMesh':True,'license':'CC0-1.0','source':rawbase+urllib.parse.quote(name),'unique_motion_credit':0})
        payloads[f]=data;total+=len(data);files.append({'path':path,'sha256':digest,'original':name,'clips':len(doc['animations']),'bytes':len(data)})
    if not records:raise ValueError('no browser-ready assets; exclusions: '+json.dumps(excluded))
    BASE.mkdir(parents=True,exist_ok=True)
    for f,data in payloads.items():(BASE/f).write_bytes(data)
    (BASE/'LICENSE-CC0.txt').write_text(license_text,encoding='utf-8')
    (BASE/'manifest.json').write_text(json.dumps({'schema':'ooglex.mesh2motion.v1','repository':'https://github.com/'+REPO,'source_commit':sha,'license':'CC0-1.0','records':records,'models':files,'excluded':excluded,'candidate_count':len(entries),'total_bytes':total,'unique_motion_credit':0,'scope':'source asset entries; cross-library semantic duplication not yet resolved'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Imported',len(records),'animation entries across',len(files),'GLBs;',total,'bytes; exclusions',json.dumps(excluded,ensure_ascii=False))
if __name__=='__main__':main()
