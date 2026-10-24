#!/usr/bin/env python3
# 高地冷杉、云杉的枝条贴图（路线图 5.1b）：从 Poly Haven fir_tree_01 的小枝照片（CC0）拼出两种整根枝条，存成带透明的 PNG。
#   python3 games/ironcrown/tools/make_branches.py fir_tree_01_twig_diff_1k.png fir_tree_01_twig_alpha_1k.png godot/chapters/ch2/trees/conifer_branches.png
# 小枝照片从 https://polyhaven.com/a/fir_tree_01 下载（1K PNG 的 twig_diff、twig_alpha）。需要 Pillow。固定种子，每次结果一样。
from PIL import Image, ImageDraw, ImageFilter
import random
from collections import deque
import sys
d=Image.open(sys.argv[1]).convert('RGB'); m=Image.open(sys.argv[2]).convert('L')
rgba=d.copy(); rgba.putalpha(m)
boxes=[(320,410,660,795),(660,460,975,850),(190,40,435,330),(665,40,965,385)]
def largest(s):
    a=s.split()[3]; W,H=a.size; px=a.load(); seen=bytearray(W*H); best=[]
    for y in range(H):
        for x in range(W):
            if px[x,y]>40 and not seen[y*W+x]:
                comp=[]; q=deque([(x,y)]); seen[y*W+x]=1
                while q:
                    cx,cy=q.popleft(); comp.append((cx,cy))
                    for nx,ny in ((cx+1,cy),(cx-1,cy),(cx,cy+1),(cx,cy-1),(cx+1,cy+1),(cx-1,cy-1),(cx+1,cy-1),(cx-1,cy+1)):
                        if 0<=nx<W and 0<=ny<H and not seen[ny*W+nx] and px[nx,ny]>40:
                            seen[ny*W+nx]=1; q.append((nx,ny))
                if len(comp)>len(best): best=comp
    keep=Image.new('L',(W,H),0); kp=keep.load()
    for (x,y) in best: kp[x,y]=255
    keep=keep.filter(ImageFilter.MaxFilter(5))
    na=Image.composite(a, Image.new('L',(W,H),0), keep); s.putalpha(na); return s.crop(s.getbbox())
sprigs=[]
for b in boxes:
    sprigs.append(largest(rgba.crop(b)).rotate(-90, expand=True, resample=Image.BICUBIC))
def branch(W,H,seed,n,spread):
    rnd=random.Random(seed); img=Image.new('RGBA',(W,H),(0,0,0,0)); cy=H//2
    for i in range(n):
        t=rnd.random()**0.8
        x=int(4+t*(W-120)); size=1.0-0.5*t
        s=rnd.choice(sprigs); sc=(H*0.95*size)/max(s.size)
        sp=s.resize((max(2,int(s.size[0]*sc)),max(2,int(s.size[1]*sc))),Image.BICUBIC)
        side=rnd.choice([-1,1]); sp=sp.rotate(side*rnd.uniform(25,70),expand=True,resample=Image.BICUBIC)
        off=int(rnd.uniform(-spread,spread)*H*(1.0-0.6*t))
        y=cy-sp.size[1]//2+off
        img.paste(sp,(x,y),sp) if False else img.alpha_composite(sp.crop((0,max(0,-y),sp.size[0],min(sp.size[1],H-y))),(x,max(0,y)))
    s=sprigs[0]; sc=(H*0.5)/max(s.size); sp=s.resize((int(s.size[0]*sc),int(s.size[1]*sc)),Image.BICUBIC)
    img.alpha_composite(sp,(W-sp.size[0]-2,cy-sp.size[1]//2))
    ImageDraw.Draw(img).line([(0,cy),(W-30,cy)],fill=(64,48,34,255),width=5)
    return img
atlas=Image.new('RGBA',(1024,512),(0,0,0,0))
atlas.alpha_composite(branch(1024,256,3,60,0.22),(0,0))
atlas.alpha_composite(branch(1024,256,9,38,0.18),(0,256))
rgb=atlas.convert('RGB'); a=atlas.split()[3]; blur=rgb
for k in range(6): blur=blur.filter(ImageFilter.MaxFilter(5))
fill=Image.composite(rgb, blur, a.point(lambda v:255 if v>8 else 0)); out=fill.copy(); out.putalpha(a)
out.save(sys.argv[3], optimize=True)
