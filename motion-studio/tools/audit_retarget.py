#!/usr/bin/env python3
"""Audit source BVH hierarchy and target mannequin skin. No inferred retargeted animations."""
import hashlib,json,re
from collections import Counter
from pathlib import Path
from import_kinemiq import glb
ROOT=Path(__file__).resolve().parents[1]
def load(rel):return json.loads((ROOT/rel).read_text())
def checked(x):
    data=(ROOT/x['path']).read_bytes()
    assert hashlib.sha256(data).hexdigest()==x['sha256'],x['path']
    return data
def normalize(name):
    return re.sub(r'[^a-z0-9]','',re.sub(r'^(mixamorig|bip001|bip01|armature|def)[_ :.-]*','',name.lower()))
def semantic(name):
    n=normalize(name)
    aliases={'hips':'pelvis','hip':'pelvis','pelvis':'pelvis','spine':'spine','spine1':'spine1','spine2':'spine2','tospine':'spine0','neck':'neck','neck1':'neck1','head':'head'}
    if n in aliases:return aliases[n]
    for side,s in [('left','l'),('right','r')]:
        parts={'shoulder':'clavicle','clavicle':'clavicle','arm':'upperarm','upperarm':'upperarm','forearm':'forearm','lowerarm':'forearm','hand':'hand','upleg':'thigh','upperleg':'thigh','thigh':'thigh','leg':'shin','lowerleg':'shin','shin':'shin','calf':'shin','foot':'foot','toebase':'toe','toe':'toe','toes':'toe'}
        for x,y in parts.items():
            if n in (side+x,x+side,s+x,x+s):return side+'_'+y
    return None
def main():
    accad=load('assets/accad/manifest.json');kin=load('assets/kinemiq/manifest.json')
    model=kin['models'][0];doc=glb(checked(model))
    joint_ids=set(j for s in doc['skins'] for j in s['joints'])
    targets={}
    for j in sorted(joint_ids):
        n=doc['nodes'][j].get('name','');role=semantic(n)
        if role:targets.setdefault(role,[]).append(n)
    rigs={};clips=[]
    for x in accad['records']:
        data=checked(x);head=data.decode('utf-8-sig').split('MOTION',1)[0]
        joints=re.findall(r'^\s*(?:ROOT|JOINT)\s+([^\r\n]+)',head,re.M)
        joints=[j.strip() for j in joints]
        if not joints:raise ValueError(x['path'])
        sig=hashlib.sha256(head.encode()).hexdigest()
        if sig not in rigs:
            pairs=[dict(source=j,semantic=semantic(j),candidates=targets.get(semantic(j),[])) for j in joints]
            rigs[sig]=dict(joints=len(joints),pairs=pairs,unique_name_matches=sum(len(p['candidates'])==1 for p in pairs),unmatched=[p['source'] for p in pairs if not p['candidates']],ambiguous=[p['source'] for p in pairs if len(p['candidates'])>1])
        clips.append(dict(id=x['id'],name=x['name'],rig=sig,category=x['category']))
    result=dict(schema='ooglex.retarget.audit.v1',source_clips=len(clips),source_hierarchy_variants=len(rigs),target_skin_joint_count=len(joint_ids),target_joint_names=[doc['nodes'][j].get('name','') for j in sorted(joint_ids)],target_model=model,rigs=rigs,clips=clips,scope='Name candidates only. Rest transforms, axes, chain lengths, IK and motion validation remain required. Zero retargeted outputs.',retargeted_outputs=0)
    out=ROOT/'assets'/'research';out.mkdir(parents=True,exist_ok=True)
    (out/'retarget-audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print('ACCAD',len(clips),'clips;',len(rigs),'hierarchy variants; target',len(joint_ids),'skin joints; mapping candidate counts',sorted(set(r['unique_name_matches'] for r in rigs.values())))
if __name__=='__main__':main()
