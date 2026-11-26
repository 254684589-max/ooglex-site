#!/usr/bin/env python3
"""Audit the immutable ACCAD catalog; generate actual FK pose SVGs, not stock art."""
import hashlib,json,math,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]/'assets'/'accad'
def parse(raw):
    h,body=raw.decode('utf-8-sig').split('MOTION')
    tokens=iter(re.findall(r'[{}]|[^\s{}]+',h))
    nodes=[]; channels=0
    def take(expected=None):
        x=next(tokens)
        if expected is not None and x!=expected: raise ValueError((expected,x))
        return x
    def joint(parent,kind):
        nonlocal channels
        name=take()
        if kind=='End' and name!='Site': raise ValueError('bad end site')
        take('{');take('OFFSET');offset=[float(take()) for _ in range(3)]
        cs=[]
        if kind!='End':
            take('CHANNELS');cs=[take() for _ in range(int(take()))]
        if any(not re.fullmatch('[XYZ](position|rotation)',c) for c in cs):raise ValueError('bad channel')
        index=len(nodes);nodes.append((name,parent,offset,cs,channels));channels+=len(cs)
        while True:
            k=take()
            if k=='}':break
            if k not in ('JOINT','End'):raise ValueError('bad joint')
            joint(index,k)
    take('HIERARCHY');take('ROOT');joint(-1,'ROOT')
    if next(tokens,None) is not None:raise ValueError('trailing hierarchy')
    m=re.search(r'Frames:\s*(\d+)\s+Frame Time:\s*([0-9.eE+-]+)\s*',body)
    n,dt=int(m[1]),float(m[2]); vals=list(map(float,body[m.end():].split()))
    if n<2 or not 0<dt<1 or len(vals)!=n*channels or not all(map(math.isfinite,vals)):raise ValueError('bad samples')
    return nodes,n,dt,channels,vals
def mul(a,b):
    x,y,z,w=a;X,Y,Z,W=b
    return (w*X+x*W+y*Z-z*Y,w*Y-x*Z+y*W+z*X,w*Z+x*Y-y*X+z*W,w*W-x*X-y*Y-z*Z)
def rotate(q,v):
    return mul(mul(q,(*v,0)),(-q[0],-q[1],-q[2],q[3]))[:3]
def pose(m,f):
    nodes,n,dt,channels,vals=m; pos=[]; rot=[]
    for name,parent,offset,cs,start in nodes:
        t=list(offset);q=(0,0,0,1)
        for k,c in enumerate(cs):
            a='XYZ'.index(c[0]);v=vals[f*channels+start+k]
            if c.endswith('position'):t[a]+=v
            else:
                h=math.radians(v)/2;b=[0,0,0,math.cos(h)];b[a]=math.sin(h);q=mul(q,b)
        if parent>=0:
            t=[a+b for a,b in zip(pos[parent],rotate(rot[parent],t))];q=mul(rot[parent],q)
        pos.append(t);rot.append(q)
    return pos
def svg(m,points):
    # Three-quarter orthographic projection, fitted to actual pose.
    xy=[(.866*x+.5*z,-y+.16*(.5*x-.866*z)) for x,y,z in points]
    lo=[min(p[i] for p in xy) for i in (0,1)];hi=[max(p[i] for p in xy) for i in (0,1)]
    k=100/max(hi[0]-lo[0],hi[1]-lo[1],1e-9)
    xy=[(64+(x-(lo[0]+hi[0])/2)*k,64+(y-(lo[1]+hi[1])/2)*k) for x,y in xy]
    out=['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><rect width="128" height="128" rx="8" fill="#25303c"/>']
    for i,(_,p,*_) in enumerate(m[0]):
        if p>=0:
            x,y=xy[i];X,Y=xy[p];out.append(f'<path d="M{X:.2f} {Y:.2f}L{x:.2f} {y:.2f}" stroke="#ffce65" stroke-width="3" stroke-linecap="round"/>')
    for x,y in xy:out.append(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="2" fill="#ffe2a2"/>')
    return ''.join(out)+'</svg>\n'
def main():
    manifest=json.loads((ROOT/'manifest.json').read_text());records=manifest['records']
    assert len({x['sha256'] for x in records})==len(records)
    thumbs=ROOT/'thumbs';thumbs.mkdir(exist_ok=True)
    reports=[]
    for x in records:
        assert re.fullmatch('[a-f0-9]{24}',x['id'])
        raw=(ROOT/(x['id']+'.bvh')).read_bytes()
        assert hashlib.sha256(raw).hexdigest()==x['sha256'],x['id']
        m=parse(raw);nodes,n,dt,channels,vals=m
        assert n==x['frames'] and abs(dt-x['frameTime'])<1e-8
        first=pose(m,0); prev=first; peak=0; best=first; bestf=0; bestmotion=-1
        for f in range(1,n):
            points=pose(m,f)
            assert all(math.isfinite(v) for p in points for v in p)
            peak=max(peak,max(math.dist(a,b)/dt for a,b in zip(points,prev)))
            # Choose largest root-relative change from initial pose.
            motion=sum(sum(((p[j]-points[0][j])-(q[j]-first[0][j]))**2 for j in range(3)) for p,q in zip(points,first))
            if motion>bestmotion:bestmotion=motion;best=points;bestf=f
            prev=points
        (thumbs/(x['id']+'.svg')).write_text(svg(m,best),encoding='utf-8')
        reports.append(dict(id=x['id'],frames=n,channels=channels,joints=sum(bool(v[3]) for v in nodes),thumbnail_frame=bestf,peak_joint_speed_source_units_per_second=round(peak,5),root_net_displacement_source_units=round(math.dist(first[0],prev[0]),5),hash_verified=True,all_fk_frames_finite=True,visual_quality_certified=False,retarget_certified=False))
    report=dict(schema='ooglex.accad.audit.v1',scope='Hash, parsing, finite forward kinematics; speed in unverified source units; no contact or visual certification',count=len(reports),records=reports)
    (ROOT/'quality.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('ACCAD verified',len(reports),'real clips;',sum(x['frames'] for x in reports),'frames; thumbnails generated')
if __name__=='__main__':main()
