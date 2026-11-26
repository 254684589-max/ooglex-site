#!/usr/bin/env python3
"""Experimental direction-based ACCAD transfer on real KinemIQ skin. No IK/twist certification."""
import json,math,struct,hashlib
from pathlib import Path
from audit_accad import parse,pose,mul,rotate
from audit_retarget import MAPPING
from import_kinemiq import glb
ROOT=Path(__file__).resolve().parents[1]
def sub(a,b):return tuple(x-y for x,y in zip(a,b))
def add(a,b):return tuple(x+y for x,y in zip(a,b))
def scale(a,s):return tuple(x*s for x in a)
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def unit(a):
    n=math.sqrt(dot(a,a))
    if n<1e-10:raise ValueError('degenerate vector')
    return scale(a,1/n)
def inv(q):return (-q[0],-q[1],-q[2],q[3])
def swing(a,b):
    a,b=unit(a),unit(b);d=max(-1,min(1,dot(a,b)))
    if d<-0.999999:
        c=unit(cross(a,min([(1,0,0),(0,1,0),(0,0,1)],key=lambda v:abs(dot(a,v)))))
        return (*c,0.)
    return unit((*cross(a,b),1+d))
def yaw_align(a,b):
    a,b=unit((a[0],0,a[2])),unit((b[0],0,b[2]))
    ang=math.atan2(cross(a,b)[1],dot(a,b))
    return (0,math.sin(ang/2),0,math.cos(ang/2))
def load(x):
    raw=(ROOT/x['path']).read_bytes()
    assert hashlib.sha256(raw).hexdigest()==x['sha256']
    return raw
def main():
    catalog=json.loads((ROOT/'assets/accad/manifest.json').read_text())
    source=next(x for x in catalog['records'] if 'SpinningBackKick' in x['name'])
    m=parse(load(source));nodes,n,dt,_,_=m
    src={j[0]:i for i,j in enumerate(nodes) if j[0]!='Site'}
    assert set(src)==set(MAPPING)
    target=json.loads((ROOT/'assets/kinemiq/manifest.json').read_text())['models'][0]
    raw=load(target);d=glb(raw);assert len(d['buffers'])==1 and d['skins'] and d['meshes']
    jl=struct.unpack_from('<I',raw,12)[0];bl,kind=struct.unpack_from('<II',raw,20+jl);assert kind==0x004e4942
    buf=bytearray(raw[28+jl:28+jl+bl]);assert len(buf)==bl
    nd=d['nodes'];ti={a.get('name'):i for i,a in enumerate(nd)}
    parents={c:i for i,a in enumerate(nd) for c in a.get('children',[])}
    assert len(set(MAPPING.values()))==22
    for a in nd:
        assert 'matrix' not in a and all(abs(v-1)<1e-4 for v in a.get('scale',[1,1,1]))
    restq=[unit(a.get('rotation',[0,0,0,1])) for a in nd];restt=[tuple(a.get('translation',[0,0,0])) for a in nd]
    def world(qs,ts):
        P={};Q={}
        def get(i):
            if i in P:return P[i],Q[i]
            if i in parents:
                p,q=get(parents[i]);P[i]=add(p,rotate(q,ts[i]));Q[i]=unit(mul(q,qs[i]))
            else:P[i]=ts[i];Q[i]=qs[i]
            return P[i],Q[i]
        for i in range(len(nd)):get(i)
        return P,Q
    rp,rq=world(restq,restt);first=pose(m,0)
    align=yaw_align(sub(first[src['LeftUpLeg']],first[src['RightUpLeg']]),sub(rp[ti['thigh_l']],rp[ti['thigh_r']]))
    legsrc=math.dist(first[src['LeftUpLeg']],first[src['LeftLeg']])+math.dist(first[src['LeftLeg']],first[src['LeftFoot']])
    legtgt=math.dist(rp[ti['thigh_l']],rp[ti['calf_l']])+math.dist(rp[ti['calf_l']],rp[ti['foot_l']])
    ratio=legtgt/legsrc
    primary={'Hips':'ToSpine','ToSpine':'Spine','Spine':'Spine1','Spine1':'Neck','Neck':'Head'}
    for side in ('Left','Right'):
        for a,b in [('Shoulder','Arm'),('Arm','ForeArm'),('ForeArm','Hand'),('UpLeg','Leg'),('Leg','Foot'),('Foot','ToeBase')]:primary[side+a]=side+b
    mapped={s:ti[t] for s,t in MAPPING.items()}
    tracks={s:[] for s in mapped};translations=[];maxerr=0
    for f in range(n):
        p=pose(m,f);q=restq.copy();t=restt.copy()
        hip=mapped['Hips'];par=parents[hip]
        delta=scale(rotate(align,sub(p[src['Hips']],first[src['Hips']])),ratio)
        t[hip]=add(restt[hip],rotate(inv(rq[par]),delta))
        for s in src:
            i=mapped[s]
            if s not in primary:continue
            child=primary[s];j=mapped[child]
            pp,qq=world(q,t);base=sub(pp[j],pp[i]);want=rotate(align,sub(p[src[child]],p[src[s]]))
            if s=='Hips':
                lateral=sub(pp[ti['thigh_l']],pp[ti['thigh_r']])
                desired=rotate(align,sub(p[src['LeftUpLeg']],p[src['RightUpLeg']]))
                turn=yaw_align(lateral,desired);q[i]=unit(mul(inv(qq[parents[i]]),mul(turn,qq[i])))
                pp,qq=world(q,t);base=sub(pp[j],pp[i])
            correction=swing(base,want);q[i]=unit(mul(inv(qq[parents[i]]),mul(correction,qq[i])))
            pp,qq=world(q,t);err=math.degrees(math.acos(max(-1,min(1,dot(unit(sub(pp[j],pp[i])),unit(want))))))
            maxerr=max(maxerr,err)
        for s,i in mapped.items():
            v=q[i];prev=tracks[s][-4:]
            if prev and dot(prev,v)<0:v=scale(v,-1)
            tracks[s].extend(v)
        translations.extend(t[hip])
    assert maxerr<0.05 and all(math.isfinite(v) for a in list(tracks.values())+[translations] for v in a)
    def accessor(vals,typ):
        while len(buf)%4:buf.append(0)
        offset=len(buf);buf.extend(struct.pack('<'+'f'*len(vals),*vals));dim={'SCALAR':1,'VEC3':3,'VEC4':4}[typ]
        vi=len(d['bufferViews']);d['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(vals)*4})
        a={'bufferView':vi,'componentType':5126,'count':len(vals)//dim,'type':typ}
        if typ=='SCALAR':a.update(min=[0],max=[struct.unpack('<f',struct.pack('<f',vals[-1]))[0]])
        d['accessors'].append(a);return len(d['accessors'])-1
    time=accessor([i*dt for i in range(n)],'SCALAR')
    anim={'name':source['name']+' experimental transfer','channels':[],'samplers':[]}
    for i,path,vals,typ in [(mapped[s],'rotation',a,'VEC4') for s,a in tracks.items()]+[(mapped['Hips'],'translation',translations,'VEC3')]:
        ix=accessor(vals,typ);si=len(anim['samplers']);anim['samplers'].append({'input':time,'output':ix,'interpolation':'LINEAR'});anim['channels'].append({'sampler':si,'target':{'node':i,'path':path}})
    d['animations']=[anim];d['buffers'][0]['byteLength']=len(buf)
    d['asset']['extras']={'source':source['source'],'author':source['author'],'license':'CC BY 3.0','original':source['original'],'target':'KinemIQ mannequin CC0 1.0','changes':'Experimental direction swing transfer; fixed proportions; no IK, twist, ground or visual certification'}
    j=json.dumps(d,separators=(',',':')).encode();j+=b' '*((-len(j))%4)
    out=struct.pack('<III',0x46546c67,2,12+8+len(j)+8+len(buf))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(buf),0x004e4942)+buf
    check=glb(out);assert len(check['animations'][0]['channels'])==23 and check['skins']==d['skins']
    folder=ROOT/'assets/research/retarget';folder.mkdir(parents=True,exist_ok=True);file='spinning-back-kick-experimental.glb';(folder/file).write_bytes(out)
    report={'schema':'ooglex.retarget.prototype.v1','source':source,'target':target,'path':'assets/research/retarget/'+file,'sha256':hashlib.sha256(out).hexdigest(),'frames':n,'tracks':23,'skin_joints':66,'max_primary_direction_error_deg':maxerr,'root_motion_scale':ratio,'visual_certified':False,'ik_certified':False,'godot_certified':False,'scope':'Experimental joint-direction transfer, not a production-ready animation. Finger and end-joint twists held at rest.'}
    (folder/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print('EXPERIMENTAL GLB',n,'frames',len(anim['channels']),'tracks',maxerr,'max primary direction error; visual/IK uncertified')
if __name__=='__main__':main()
