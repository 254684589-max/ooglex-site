#!/usr/bin/env python3
"""修补 Quaternius Universal Base Characters [Standard] 的男性底模 glTF（阶段 A.1，2026-10-02）。

原始文件（CC0）有两处和我们手里的文件对不上，导入 Godot 会报「找不到贴图」：
  1. 眉毛材质 MI_Hair_1 引用的 T_Hair_1_BaseColor / T_Hair_1_Normal 没有随免费版附带 → 去掉这两张贴图，
     眉毛改用纯深棕色（baseColorFactor），不再依赖外部文件；
  2. 眼睛法线图写的是 T_Eye_Normal_png.png，实际文件叫 T_Eye_Normal.png → 改引用。
其余（骨架、蒙皮、网格、皮肤 / 粗糙度 / 法线贴图）原样保留。可重复运行：已经修补过就什么也不做。

用法：python3 games/ironcrown/tools/patch_character_gltf.py games/ironcrown/godot/assets/characters/Superhero_Male_FullBody.gltf
"""
from __future__ import annotations

import json
import sys

EYEBROW_COLOR = [0.085, 0.055, 0.035, 1.0]   # 深棕


def patch(path: str) -> bool:
    g = json.load(open(path, encoding="utf-8"))
    if g.get("asset", {}).get("extras", {}).get("ironcrown_patched"):
        return False
    images = g["images"]
    textures = g["textures"]
    drop_images = {i for i, im in enumerate(images) if im["uri"].startswith("T_Hair_1_")}
    drop_tex = {i for i, t in enumerate(textures) if t["source"] in drop_images}
    # 重新编号：删掉的下标之后的往前挪
    img_map, n = {}, 0
    for i in range(len(images)):
        if i not in drop_images:
            img_map[i] = n
            n += 1
    tex_map, n = {}, 0
    for i in range(len(textures)):
        if i not in drop_tex:
            tex_map[i] = n
            n += 1
    new_images = [im for i, im in enumerate(images) if i not in drop_images]
    new_textures = []
    for i, t in enumerate(textures):
        if i in drop_tex:
            continue
        t = dict(t)
        t["source"] = img_map[t["source"]]
        new_textures.append(t)
    for im in new_images:
        if im["uri"] == "T_Eye_Normal_png.png":
            im["uri"] = "T_Eye_Normal.png"
    for m in g["materials"]:
        pbr = m.get("pbrMetallicRoughness", {})
        for holder, key in ((m, "normalTexture"), (pbr, "baseColorTexture"), (pbr, "metallicRoughnessTexture")):
            if key in holder:
                if holder[key]["index"] in drop_tex:
                    del holder[key]
                else:
                    holder[key]["index"] = tex_map[holder[key]["index"]]
        if m["name"] == "MI_Hair_1":
            pbr["baseColorFactor"] = EYEBROW_COLOR
            m["name"] = "MI_Eyebrows"
    g["images"] = new_images
    g["textures"] = new_textures
    g["asset"].setdefault("extras", {})["ironcrown_patched"] = "eyebrows: flat colour; eye normal uri fixed"
    json.dump(g, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    return True


if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(("已修补 " if patch(p) else "已经修补过，跳过 ") + p)
