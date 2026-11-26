#!/usr/bin/env python3
"""Selective import of original licensed 100STYLE sequences, not segmented attacks."""
import hashlib,json,zipfile
from pathlib import Path
from audit_100style import RemoteZip
from import_accad import inspect
ROOT=Path(__file__).resolve().parents[1]
def main():
    inv=json.loads((ROOT/'assets/research/100style-inventory.json').read_text())
    assert inv['license']=='CC-BY-4.0' and inv['directory_status']=='range_verified'
    raw=next(x for x in inv['files'] if x['name']=='100STYLE.zip')
    styles=['Kick','Punch','KarateChop','Lunge','Neutral','TwoFootJump']
    chosen=[]
    for style in styles:
        items=[x for x in inv['archive_entries'] if x['path'].startswith('100STYLE/'+style+'/') and x['bytes']<=15_000_000]
        if items:chosen.append(min(items,key=lambda x:x['compressed_bytes']))
    assert len(chosen)==len(styles)
    out=ROOT/'assets'/'100style';out.mkdir(parents=True,exist_ok=True)
    records=[];rejected=[];seen=set()
    with zipfile.ZipFile(RemoteZip(raw['url'],raw['bytes'])) as z:
        for x in chosen:
            path=x['path'];info=z.getinfo(path)
            assert info.file_size==x['bytes'] and f'{info.CRC:08x}'==x['crc32']
            data=z.read(info);sha=hashlib.sha256(data).hexdigest()
            if sha in seen:continue
            try:n,dt=inspect(data)
            except (ValueError,UnicodeError) as e:rejected.append({'path':path,'reason':str(e)});continue
            seen.add(sha);file=sha[:24]+'.bvh';(out/file).write_bytes(data)
            style=path.split('/')[1]
            records.append(dict(id=sha[:24],name=Path(path).stem,category=style,path='assets/100style/'+file,frames=n,frameTime=dt,duration=(n-1)*dt,sha256=sha,original=path,license='CC BY 4.0',author='Ian Mason, Sebastian Starke, Taku Komura',source=inv['source'],style=style,scope='Unmodified full recording; not an isolated or game-ready combat action'))
    assert records,'No verified recordings'
    (out/'manifest.json').write_text(json.dumps(dict(schema='ooglex.100style.v1',source=inv['source'],license='https://creativecommons.org/licenses/by/4.0/',records=records,rejected=rejected,scope='Original sequences; style labels do not establish discrete combat moves'),ensure_ascii=False,indent=2)+'\n')
    print('Validated original sequences',len(records),'frames',sum(r['frames'] for r in records),'rejected',rejected)
if __name__=='__main__':main()
