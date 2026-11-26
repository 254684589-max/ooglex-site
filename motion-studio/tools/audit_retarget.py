#!/usr/bin/env python3
"""Actual 22-joint ACCAD -> KinemIQ mannequin name and topology preflight, not motion retargeting."""
import hashlib,json,re,math
from pathlib import Path
from import_kinemiq import glb
ROOT=Path(__file__).resolve().parents[1]
MAPPING={'Hips':'pelvis','ToSpine':'spine_01','Spine':'spine_02','Spine1':'spine_03','Neck':'neck_01','Head':'Head'}
for side,s in [('Left','l'),('Right','r')]:
    for a,b in [('Shoulder','clavicle'),('Arm','upperarm'),('ForeArm','lowerarm'),('Hand','hand'),('UpLeg','thigh'),('Leg','calf'),('Foot','foot'),('ToeBase','ball')]:
        MAPPING[side+a]=b+'_'+s
def load(rel):return json.loads((ROOT/rel).read_text())
def checked(x):
    data=(ROOT/x['path']).read_bytes()
    assert hashlib.sha256(data).hexdigest()==x['sha256'],x['path']
    return data
def hierarchy(text):
    tokens=re.findall(r'[{}]|[^\s{}]+',text)
    i=0;parents={};offsets={}
    def joint(parent):
        nonlocal i
        kind=tokens[i];i+=1
        if kind not in ('ROOT','JOINT','End'):raise ValueError(kind)
        name=tokens[i];i+=1
        if kind=='End' and name!='Site':raise ValueError('bad End Site')
        if tokens[i]!='{':raise ValueError('missing brace')
        i+=1
        if kind!='End':
            if name in parents:raise ValueError('duplicate joint '+name)
            parents[name]=parent
        while tokens[i]!='}':
            t=tokens[i]
            if t=='OFFSET':
                vals=list(map(float,tokens[i+1:i+4]));assert all(math.isfinite(x) for x in vals)
                if kind!='End':offsets[name]=vals
                i+=4
            elif t=='CHANNELS':i+=2+int(tokens[i+1])
            elif t in ('JOINT','End'):joint(name)
            else:raise ValueError(t)
        i+=1
    assert tokens[0]=='HIERARCHY';i=1;joint(None);assert i==len(tokens)
    return parents,offsets
def main():
    accad=load('assets/accad/manifest.json');kin=load('assets/kinemiq/manifest.json')
    model=kin['models'][0];doc=glb(checked(model))
    joint_ids=set(j for s in doc['skins'] for j in s['joints'])
    target_names={doc['nodes'][j].get('name',''):j for j in joint_ids}
    assert len(target_names)==len(joint_ids)
    parent_by_node={child:i for i,n in enumerate(doc['nodes']) for child in n.get('children',[])}
    assert len(set(MAPPING.values()))==len(MAPPING)==22
    assert set(MAPPING.values())<=set(target_names)
    topology={};rows=[]
    for x in accad['records']:
        head=checked(x).decode('utf-8-sig').split('MOTION',1)[0]
        parents,offsets=hierarchy(head)
        missing=sorted(set(parents)-set(MAPPING))
        mapped={j:MAPPING[j] for j in parents if j in MAPPING}
        edge_fail=[]
        for j,parent in parents.items():
            if parent is None:continue
            if j not in mapped or parent not in mapped:continue
            if parent_by_node.get(target_names[mapped[j]])!=target_names[mapped[parent]]:
                edge_fail.append([parent,j])
        key=hashlib.sha256(json.dumps(sorted(parents.items()),ensure_ascii=False).encode()).hexdigest()[:24]
        topology.setdefault(key,{'source_parents':parents,'mapping':mapped,'missing':missing,'parent_edge_failures':edge_fail})
        rows.append({'id':x['id'],'name':x['name'],'category':x['category'],'topology':key,'source_joints':len(parents),'mapped_joints':len(mapped),'edge_failures':len(edge_fail),'name_topology_pass':not missing and not edge_fail and len(mapped)==22})
    result={'schema':'ooglex.retarget.audit.v2','source_clips':len(rows),'source_topology_count':len(topology),'target_skin_joint_count':len(joint_ids),'target_joint_names':sorted(target_names),'target_model':model,'mapping':MAPPING,'topologies':topology,'clips':rows,'name_topology_pass_count':sum(r['name_topology_pass'] for r in rows),'retargeted_outputs':0,'scope':'Exact joint names and parent edges only. No rest-axis correction, proportion fitting, root motion or IK certification.'}
    out=ROOT/'assets'/'research';out.mkdir(parents=True,exist_ok=True)
    (out/'retarget-audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print('ACCAD source clips',len(rows),'mapped name and topology',result['name_topology_pass_count'],'target skin',len(joint_ids),'source topologies',len(topology),'retargeted outputs 0')
if __name__=='__main__':main()
