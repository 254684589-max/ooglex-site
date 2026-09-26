#!/usr/bin/env python3
"""把 Godot 网页导出结果整理进 games/emberfall3d/play/，并给文件名加内容哈希。

为什么要改名：站点对静态资源有「版本号必须与内容一致」的规则
（scripts/validate_asset_versions.py）。Godot 的加载器按 GODOT_CONFIG.executable
拼出 .wasm / .pck / 音频 worklet 的文件名，没法在后面加 ?v=，所以直接把哈希写进
文件名：ef-<哈希>.wasm、ef-<哈希>.pck ……引擎或游戏数据一变，文件名就变，
回访玩家不会拿到「新页面 + 旧游戏包」的组合。

用法（一般由 build_web.sh 调用）：
    python3 stamp_web_build.py <godot 导出目录> <games/emberfall3d/play>
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import re
import sys

SUFFIXES = [".wasm", ".pck", ".js", ".audio.worklet.js", ".audio.position.worklet.js"]


def sha8(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:8]


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src = pathlib.Path(sys.argv[1])
    dst = pathlib.Path(sys.argv[2])
    html = (src / "index.html").read_text(encoding="utf-8")
    m = re.search(r"const GODOT_CONFIG = (\{.*?\});", html)
    if not m:
        print("导出的 index.html 里找不到 GODOT_CONFIG", file=sys.stderr)
        return 1
    config = json.loads(m.group(1))
    exe = config["executable"]
    wasm = (src / f"{exe}.wasm").read_bytes()
    pck = (src / f"{exe}.pck").read_bytes()
    js = (src / f"{exe}.js").read_bytes()
    new = f"ef-{sha8(wasm + pck + js)}"

    dst.mkdir(parents=True, exist_ok=True)
    for old in dst.iterdir():
        if old.is_file() and (old.name.startswith("ef-") or old.name == "index.html"):
            old.unlink()
    for suffix in SUFFIXES:
        f = src / f"{exe}{suffix}"
        if f.exists():
            (dst / f"{new}{suffix}").write_bytes(f.read_bytes())

    config["executable"] = new
    config["mainPack"] = f"{new}.pck"
    config["fileSizes"] = {f"{new}.pck": len(pck), f"{new}.wasm": len(wasm)}
    html = html.replace(m.group(0), "const GODOT_CONFIG = " + json.dumps(config, ensure_ascii=False, separators=(",", ":")) + ";")
    old_tag = f'<script src="{exe}.js"></script>'
    if old_tag not in html:
        print(f"导出的 index.html 里找不到 {old_tag}", file=sys.stderr)
        return 1
    html = html.replace(old_tag, f'<script src="{new}.js?v={sha8(js)}"></script>')
    (dst / "index.html").write_text(html.rstrip() + "\n", encoding="utf-8")
    # 介绍页的「开始游戏」链接带上构建号：play/ 的地址不变，浏览器 / CDN 会把旧的 index.html
    # 缓存约 10 分钟，更新后回访玩家可能还在玩旧版；换一个查询参数就是一个新的缓存键。
    intro = dst.parent / "index.html"
    if intro.exists():
        page = intro.read_text(encoding="utf-8")
        page = re.sub(r'href="play/(\?v=[0-9a-f]+)?"', f'href="play/?v={new[3:]}"', page)
        intro.write_text(page, encoding="utf-8")
    # 章节包（TECH.md 第 5.3 节）：原样复制到 play/packs/，由游戏运行时按需下载
    packs_src = src / "packs"
    packs_dst = dst / "packs"
    if packs_dst.exists():
        for old in packs_dst.iterdir():
            old.unlink()
    if packs_src.is_dir():
        packs_dst.mkdir(exist_ok=True)
        for f in packs_src.glob("*.pck"):
            (packs_dst / f.name).write_bytes(f.read_bytes())
    total = sum(p.stat().st_size for p in dst.rglob("*") if p.is_file())
    print(f"已写入 {dst}：{new}.*，共 {total / 1048576:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
