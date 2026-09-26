#!/usr/bin/env python3
"""下载 Godot 4.7.2 编辑器，并从导出模板包里只取出网页模板（web_nothreads_release.zip）。

导出模板包约 1.28 GB，但网页构建只需要其中约 10 MB 的一个文件。GitHub Releases 支持按字节范围下载，
这里读 zip 的中央目录，只下载那一个成员，省下一个多 GB 的下载和磁盘占用（会话磁盘有额度）。

用法：
    python3 games/emberfall3d/tools/fetch_godot.py <目标目录>
完成后按提示设置 GODOT 环境变量即可运行 run_tests.sh / build_web.sh。
"""
from __future__ import annotations

import io
import os
import pathlib
import ssl
import struct
import sys
import urllib.request
import zipfile
import zlib

VERSION = "4.7.2"
BASE = f"https://github.com/godotengine/godot/releases/download/{VERSION}-stable"
EDITOR = f"Godot_v{VERSION}-stable_linux.x86_64"
TEMPLATES = f"Godot_v{VERSION}-stable_export_templates.tpz"
WANT = "web_nothreads_release.zip"


def _ctx() -> ssl.SSLContext:
    ca = "/root/.ccr/ca-bundle.crt"  # 云端开发环境的代理证书；本地没有就用系统默认
    return ssl.create_default_context(cafile=ca) if os.path.exists(ca) else ssl.create_default_context()


def _get(url: str, rng: tuple[int, int] | None = None) -> bytes:
    headers = {"Range": f"bytes={rng[0]}-{rng[1]}"} if rng else {}
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), context=_ctx(), timeout=300) as r:
        return r.read()


def _size(url: str) -> int:
    with urllib.request.urlopen(urllib.request.Request(url, method="HEAD"), context=_ctx(), timeout=60) as r:
        return int(r.headers["Content-Length"])


def fetch_member(url: str, want: str) -> bytes:
    size = _size(url)
    tail = _get(url, (size - 65536, size - 1))
    eocd = tail.rfind(b"PK\x05\x06")
    cd_size, cd_off = struct.unpack("<II", tail[eocd + 12:eocd + 20])
    if cd_off == 0xFFFFFFFF:
        z64 = tail.rfind(b"PK\x06\x06")
        cd_size, cd_off = struct.unpack("<QQ", tail[z64 + 40:z64 + 56])
    cd = _get(url, (cd_off, cd_off + cd_size - 1))
    p = 0
    while p < len(cd):
        comp = struct.unpack("<H", cd[p + 10:p + 12])[0]
        csz, usz = struct.unpack("<II", cd[p + 20:p + 28])
        nl, el, cl = struct.unpack("<HHH", cd[p + 28:p + 34])
        lho = struct.unpack("<I", cd[p + 42:p + 46])[0]
        name = cd[p + 46:p + 46 + nl].decode()
        extra = cd[p + 46 + nl:p + 46 + nl + el]
        if 0xFFFFFFFF in (csz, usz, lho):
            q = 0
            while q < len(extra):
                hid, hl = struct.unpack("<HH", extra[q:q + 4])
                if hid == 1:
                    vals = list(struct.unpack("<" + "Q" * (hl // 8), extra[q + 4:q + 4 + hl]))
                    if usz == 0xFFFFFFFF:
                        usz = vals.pop(0)
                    if csz == 0xFFFFFFFF:
                        csz = vals.pop(0)
                    if lho == 0xFFFFFFFF:
                        lho = vals.pop(0)
                q += 4 + hl
        if name.endswith(want):
            lh = _get(url, (lho, lho + 29))
            n2, e2 = struct.unpack("<HH", lh[26:30])
            start = lho + 30 + n2 + e2
            data = _get(url, (start, start + csz - 1))
            return zlib.decompress(data, -15) if comp == 8 else data
        p += 46 + nl + el + cl
    raise SystemExit(f"模板包里找不到 {want}")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    dest = pathlib.Path(sys.argv[1]).resolve()
    dest.mkdir(parents=True, exist_ok=True)
    editor = dest / EDITOR
    if not editor.exists():
        print("下载 Godot 编辑器……")
        zipfile.ZipFile(io.BytesIO(_get(f"{BASE}/{EDITOR}.zip"))).extract(EDITOR, dest)
        editor.chmod(0o755)
    tdir = pathlib.Path.home() / ".local/share/godot/export_templates" / f"{VERSION}.stable"
    tdir.mkdir(parents=True, exist_ok=True)
    if not (tdir / WANT).exists():
        print(f"从导出模板包里取出 {WANT}……")
        (tdir / WANT).write_bytes(fetch_member(f"{BASE}/{TEMPLATES}", WANT))
    print(f"完成。\n  export GODOT={editor}\n  网页模板：{tdir / WANT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
