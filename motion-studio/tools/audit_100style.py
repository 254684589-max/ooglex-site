#!/usr/bin/env python3
"""Inventory official 100STYLE release metadata; bounded ZIP central-directory reads, no large archive downloads."""
import io,json,re,urllib.request,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
API='https://zenodo.org/api/records/8127870'
def request(url,headers={}):
    return urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'OoglexMotionStudio/4.6.4','Accept-Encoding':'identity',**headers}),timeout=45)
class RemoteZip(io.RawIOBase):
    def __init__(self,url,size):self.url=url;self.size=size;self.pos=0;self.used=0
    def seekable(self):return True
    def readable(self):return True
    def tell(self):return self.pos
    def seek(self,offset,whence=0):
        p=offset if whence==0 else self.pos+offset if whence==1 else self.size+offset
        if p<0:raise ValueError('negative offset')
        self.pos=p;return p
    def read(self,n=-1):
        n=min(self.size-self.pos,n if n>=0 else self.size-self.pos)
        if n<=0:return b''
        if self.used+n>8_000_000:raise ValueError('range budget exceeded')
        end=self.pos+n-1
        with request(self.url,{'Range':f'bytes={self.pos}-{end}'}) as f:
            if f.status!=206 or f.headers.get('Content-Range')!=f'bytes {self.pos}-{end}/{self.size}':raise ValueError('server did not honor exact byte range')
            data=f.read(n+1)
        if len(data)!=n:raise ValueError('range length mismatch')
        self.pos+=n;self.used+=n;return data
def main():
    with request(API) as f:d=json.loads(f.read(2_000_001))
    meta=d['metadata'];license=meta.get('license',{});assert license.get('id','').lower()=='cc-by-4.0',license
    files=[{'name':f['key'],'bytes':f['size'],'checksum':f['checksum'],'url':f['links']['self']} for f in d['files']]
    raw=next(f for f in files if f['name']=='100STYLE.zip')
    result=dict(schema='ooglex.100style.inventory.v1',source='https://zenodo.org/records/8127870',doi=meta.get('doi'),license='CC-BY-4.0',creators=[x['name'] for x in meta.get('creators',[])],files=files,archive_entries=[],verified_clips=0,scope='Official metadata and, if available, ZIP central directory only; no raw BVH clips imported.')
    try:
        with zipfile.ZipFile(RemoteZip(raw['url'],raw['bytes'])) as z:
            result['archive_entries']=[{'path':i.filename,'bytes':i.file_size,'compressed_bytes':i.compress_size,'crc32':f'{i.CRC:08x}'} for i in z.infolist() if i.filename.lower().endswith('.bvh') and not i.is_dir()]
        original_count=len(result['archive_entries'])
        result['archive_entries']=[i for i in result['archive_entries'] if not i['path'].startswith('__MACOSX/') and not i['path'].split('/')[-1].startswith('._')]
        result['excluded_macos_metadata_entries']=original_count-len(result['archive_entries'])
        result['directory_bvh_candidates']=len(result['archive_entries'])
        result['directory_status']='range_verified'
    except Exception as e:result['directory_status']='unavailable';result['directory_error']=str(e)
    out=ROOT/'assets'/'research';out.mkdir(parents=True,exist_ok=True)
    (out/'100style-inventory.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print('100STYLE archive',raw['bytes'],'bytes; central directory',result['directory_status'],'BVH entries',len(result['archive_entries']),'imported clips',0)
if __name__=='__main__':main()
