#!/usr/bin/env python3
"""《铁冠之争》人物（二）素材导入（路线图 A.2；所有者上传到 ironcrown-assets 仓库的两个 Quaternius CC0 包）。

  python3 games/ironcrown/tools/import_outfits.py <ironcrown-assets 仓库目录>

从两个包里挑游戏用到的部分，写进 godot/assets/characters/outfits/：
- 四套服装（男 / 女 × 平民 / 游侠，Modular Character Outfits – Fantasy 的 Outfits/*.gltf）：身体、手臂、腿、脚、衣服都在里面，没有头；
- 两个头（Universal Base Characters 的 Superhero_Male / Female_FullBody）：只留脖子以上的三角形、眼睛、眉毛——包里的说明
  「用服装时只要底模的头，用整个身体会穿模」；
- 六种发型（Hairstyles/Rigged to Head Bone 的 glTF）。
五个包用的是同一副 65 根骨头的骨架、骨头顺序也一样（导入前用脚本核对过），游戏里把头和头发的网格挂到服装的骨架上就能一起动。

每个 glTF 重写一遍：只留游戏用得上的顶点属性（位置、法线、第一套贴图坐标、骨头、权重），去掉没用到的顶点，
贴图统一缩到 1024（原图 4K、每张 5–14 MB；A.1 的人物贴图导入时也是限到 1024），贴图文件名统一（同一张图在不同包里叫法不一）。
原包不进这个仓库（在 ironcrown-assets 仓库），来源与许可记在 assets/SOURCES.md。
"""
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "godot", "assets", "characters", "outfits")
TEX_SIZE = 512             # 网页首次加载有 60 MB 的预算（TECH.md 第六节）：只留底色贴图、缩到 512；法线、ORM 不要（NPC 在网页分辨率下几乎看不出）
KEEP_ATTRS = ["POSITION", "NORMAL", "TEXCOORD_0", "JOINTS_0", "WEIGHTS_0"]
COMP = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

OUTFITS = "Exports/glTF (Godot-Unreal)/Outfits"
BASE = "Universal Base Characters[Standard]/Base Characters/Godot - UE"
HAIR = "Universal Base Characters[Standard]/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)"
HAIR_TEX = "Universal Base Characters[Standard]/Hairstyles/Textures"
EXTRA_TEX = {   # 包里另外几张配色贴图（同一套服装换个颜色），游戏里按人物挑
    "T_Peasant_2_BaseColor.png": "Textures/Peasant/T_Peasant_2_BaseColor.png",
    "T_Ranger_3_BaseColor.png": "Textures/Ranger/T_Ranger_3_BaseColor.png",
}
## 头：脖子以上（骨架绑定姿势下的高度，米）。服装的领口盖住这条线以下
HEAD_CUT = {"Male": 1.47, "Female": 1.43}
## 头只留脖子这么宽（米，左右）：底模是 T 姿势，只按高度切会把两肩和伸平的整条胳膊（x 到 ±0.8）也留下，
## 藏在衣服下面、动起来从肩膀和袖子里戳出来（2026-10-23 所有者截图「衣服没包好、有破洞」）
NECK_HALF = 0.12


def read(src, g, bin_, acc_i):
    acc = g["accessors"][acc_i]
    bv = g["bufferViews"][acc["bufferView"]]
    n = acc["count"] * WIDTH[acc["type"]]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    dt = NP[acc["componentType"]]
    stride = bv.get("byteStride", 0)
    item = np.dtype(dt).itemsize * WIDTH[acc["type"]]
    if stride and stride != item:
        raw = np.frombuffer(bin_, dtype=np.uint8, count=stride * (acc["count"] - 1) + item, offset=off)
        rows = np.stack([raw[i * stride:i * stride + item] for i in range(acc["count"])])
        a = rows.view(dt)
    else:
        a = np.frombuffer(bin_, dtype=dt, count=n, offset=off).copy()
    return a.reshape(acc["count"], WIDTH[acc["type"]]) if WIDTH[acc["type"]] > 1 else a


class Writer:
    def __init__(self):
        self.blob = bytearray()
        self.views = []
        self.accs = []

    def add(self, arr, ctype, typ, target=None, minmax=False):
        while len(self.blob) % 4:
            self.blob.append(0)
        data = np.ascontiguousarray(arr.astype(NP[ctype])).tobytes()
        view = {"buffer": 0, "byteOffset": len(self.blob), "byteLength": len(data)}
        if target:
            view["target"] = target
        self.blob += data
        self.views.append(view)
        acc = {"bufferView": len(self.views) - 1, "componentType": ctype, "count": int(arr.shape[0]), "type": typ}
        if ctype in (5121, 5123) and typ == "VEC4" and False:
            pass
        if minmax:
            acc["min"] = [float(x) for x in arr.min(axis=0)]
            acc["max"] = [float(x) for x in arr.max(axis=0)]
        self.accs.append(acc)
        return len(self.accs) - 1


def rewrite(src_gltf, out_name, tex_map, keep_tri=None, mesh_names=None):
    """重写一个 glTF：src_gltf 原文件；out_name 输出文件名（不带扩展名）；tex_map 原图片 uri → 统一后的贴图文件名；
    keep_tri {材质名: f(三个顶点的位置) -> bool} 过滤用这个材质的网格的三角形；mesh_names 只留这些网格。"""
    src_dir = os.path.dirname(src_gltf)
    g = json.load(open(src_gltf))
    bin_ = open(os.path.join(src_dir, g["buffers"][0]["uri"]), "rb").read()
    w = Writer()
    meshes = []
    mesh_index = {}
    for mi, m in enumerate(g["meshes"]):
        if mesh_names is not None and m["name"] not in mesh_names:
            continue
        prims = []
        for p in m["primitives"]:
            attrs = {k: read(src_dir, g, bin_, v) for k, v in p["attributes"].items() if k in KEEP_ATTRS}
            idx = read(src_dir, g, bin_, p["indices"]).astype(np.int64).reshape(-1, 3)
            mat = g["materials"][p["material"]]["name"] if "material" in p else ""
            if keep_tri and mat in keep_tri:          # 按材质认网格（男性底模的身体网格叫 Sphere.005_Retopology.004，女性的叫 Superhero_Female）
                pos = attrs["POSITION"]
                keep = np.array([keep_tri[mat](pos[t]) for t in idx], dtype=bool)
                idx = idx[keep]
            used = np.unique(idx)
            remap = -np.ones(attrs["POSITION"].shape[0], dtype=np.int64)
            remap[used] = np.arange(used.size)
            idx = remap[idx]
            new_attrs = {}
            for k, a in attrs.items():
                a = a[used]
                ctype = g["accessors"][p["attributes"][k]]["componentType"]
                typ = g["accessors"][p["attributes"][k]]["type"]
                new_attrs[k] = w.add(a, ctype, typ, 34962, minmax=(k == "POSITION"))
            ictype = 5123 if used.size < 65536 else 5125
            prim = {"attributes": new_attrs, "indices": w.add(idx.reshape(-1), ictype, "SCALAR", 34963), "mode": 4}
            if "material" in p:
                prim["material"] = p["material"]
            prims.append(prim)
        mesh_index[mi] = len(meshes)
        meshes.append({"name": m["name"], "primitives": prims})
    nodes = []
    for n in g["nodes"]:
        n = dict(n)
        if "mesh" in n:
            if n["mesh"] in mesh_index:
                n["mesh"] = mesh_index[n["mesh"]]
            else:
                del n["mesh"]
                n.pop("skin", None)
        nodes.append(n)
    skins = []
    for s in g["skins"]:
        s = dict(s)
        s["inverseBindMatrices"] = w.add(read(src_dir, g, bin_, s["inverseBindMatrices"]), 5126, "MAT4")
        skins.append(s)
    mats = []
    for m in g.get("materials", []):                # 只留底色贴图（normalTexture、metallicRoughnessTexture 去掉，粗糙度给个常数）
        m = json.loads(json.dumps(m))
        m.pop("normalTexture", None)
        pbr = m.setdefault("pbrMetallicRoughness", {})
        if pbr.pop("metallicRoughnessTexture", None) is not None or "roughnessFactor" not in pbr:
            pbr["roughnessFactor"] = 0.85
        pbr["metallicFactor"] = 0
        mats.append(m)
    images = []
    for im in g.get("images", []):
        uri = tex_map.get(im["uri"], im["uri"])
        images.append({"name": os.path.splitext(uri)[0], "uri": uri, "mimeType": "image/png"})
    out = {
        "asset": {"version": "2.0", "generator": "ironcrown tools/import_outfits.py（源自 Quaternius CC0）"},
        "scene": 0, "scenes": g["scenes"], "nodes": nodes, "meshes": meshes, "skins": skins,
        "materials": mats, "textures": g.get("textures", []), "samplers": g.get("samplers", []), "images": images,
        "accessors": w.accs, "bufferViews": w.views, "buffers": [{"byteLength": len(w.blob), "uri": out_name + ".bin"}],
    }
    with open(os.path.join(OUT, out_name + ".bin"), "wb") as f:
        f.write(w.blob)
    with open(os.path.join(OUT, out_name + ".gltf"), "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    tris = sum(len(read(src_dir, {"accessors": w.accs, "bufferViews": w.views}, bytes(w.blob), p["indices"])) // 3 for m in meshes for p in m["primitives"])
    return tris


def texture(src, name, normal=False):
    im = Image.open(src)
    im = im.convert("RGBA" if im.mode in ("RGBA", "LA", "P") else "RGB")
    if max(im.size) > TEX_SIZE:
        im = im.resize((TEX_SIZE, TEX_SIZE), Image.LANCZOS)
    im.save(os.path.join(OUT, name), optimize=True)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    report = []
    # 贴图：服装、皮肤、眼睛、头发（统一文件名；_png.png 这种重复后缀去掉）
    tex = {}
    for d in [os.path.join(src, OUTFITS), os.path.join(src, BASE), os.path.join(src, HAIR_TEX)]:
        for f in sorted(os.listdir(d)):
            if f.endswith(".png"):
                clean = f.replace("_png.png", ".png")
                tex.setdefault(clean, os.path.join(d, f))
    for name, rel in EXTRA_TEX.items():
        tex[name] = os.path.join(src, rel)
    tex_map = {}
    for clean, path in tex.items():
        tex_map[os.path.basename(path)] = clean
        tex_map[clean] = clean
    # 头发 glTF 里的图片名
    tex_map["T_Hair_1_Normal_png.png"] = "T_Hair_1_Normal.png"
    tex_map["T_Eye_Normal_png.png"] = "T_Eye_Normal.png"
    used = set()
    for sex in ["Male", "Female"]:
        for kind in ["Peasant", "Ranger"]:
            n = "%s_%s" % (sex, kind)
            report.append((n, rewrite(os.path.join(src, OUTFITS, n + ".gltf"), "Outfit_" + n, tex_map)))
        cut = HEAD_CUT[sex]
        body = "MI_Superhero_" + sex
        n = "Superhero_%s_FullBody" % sex
        tris = rewrite(os.path.join(src, BASE, n + ".gltf"), "Head_" + sex, tex_map,
                       keep_tri={body: lambda p, c=cut: float(p[:, 1].min()) >= c and float(np.abs(p[:, 0]).max()) <= NECK_HALF})
        report.append(("Head_" + sex, tris))
    for h in ["Hair_SimpleParted", "Hair_Buzzed", "Hair_Beard", "Hair_Long", "Hair_Buns", "Hair_BuzzedFemale"]:
        report.append((h, rewrite(os.path.join(src, HAIR, h + ".gltf"), h, tex_map)))
    for f in os.listdir(OUT):
        if f.endswith(".gltf"):
            g = json.load(open(os.path.join(OUT, f)))
            for m in g.get("materials", []):
                t = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
                if t is not None:
                    used.add(g["images"][g["textures"][t["index"]]["source"]]["uri"])
    for name in sorted(used | set(EXTRA_TEX)):
        if name not in tex:
            print("缺贴图：", name)
            continue
        texture(tex[name], name)
    lic = os.path.join(src, "License_Standard.txt")
    with open(os.path.join(OUT, "LICENSE_Quaternius_CC0.txt"), "w") as f:
        f.write("Modular Character Outfits – Fantasy [Standard] 与 Universal Base Characters [Standard]，作者 Quaternius，CC0 1.0（包内 License_Standard.txt 原文如下）\n\n")
        f.write(open(lic, encoding="utf-8", errors="replace").read())
    for n, t in report:
        print("%-24s %6d 三角形" % (n, t))
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
    print("写入 %s：%d 个文件，%.1f MB" % (OUT, len(os.listdir(OUT)), total / 1e6))


if __name__ == "__main__":
    main()
