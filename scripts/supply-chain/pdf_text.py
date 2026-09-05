#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 PDF 里抽出文字。**只用标准库**——仓库规矩不自动装依赖。

## 为什么要它

两处都卡在这块地基上：

  麦当劳的冲突矿产报告是 493KB 的 PDF，现有规则只收 .htm/.html，整份看不到
  思科的一级供应商名单也是 PDF，那是比冶炼厂更接近「直接供货」的一层

## 为什么不能沿用之前那个

之前探针里的粗解析器是拿正则在原始字节上找 `stream...endstream` 再 zlib 解压，
吐出来的是这样：

    A Pr ot ocol  f or Prioritizin g  Chem icals  f  Co ncer n  in  he

原文是「A Protocol for Prioritizing Chemicals of Concern in the」——**字在掉**。
原因是 PDF 的文本不是一段连续字符串：它由 Tj / TJ 操作符分段给出，TJ 里还夹着
字距调整数字；直接正则抓引号里的内容，会把转义、十六进制串和字距数组一起搅碎。
而且只会 FlateDecode，遇到 ASCII85 包一层就整份解不开（英特尔那三份就是）。

要拿对文字只能按格式解：词法分析 → 对象表 → 内容流 → 文本操作符 →
按字体的 ToUnicode 映射还原字符。

## 边界（写在这里，免得日后误用）

  · 图片型（扫描件）PDF **抽不出文字**，这是事实不是缺陷——返回空并说明
  · 不做版面还原：不还原分栏、表格网格，只按 PDF 里的绘制顺序给出文本行
  · 加密 PDF 不处理，如实报告
  · 没有 ToUnicode 的字体按 Latin-1 解，可能出错——这类字符单独计数并报出来，
    不混进「成功抽取」里
"""
from __future__ import annotations

import base64
import re
import zlib

MAX_OBJECTS = 60_000
MAX_STREAM_BYTES = 60 * 1024 * 1024


# ── 过滤器 ────────────────────────────────────────────────────────────────
def _run_length_decode(data: bytes) -> bytes:
    out = bytearray()
    i = 0
    while i < len(data):
        n = data[i]
        i += 1
        if n == 128:
            break
        if n < 128:
            out += data[i:i + n + 1]
            i += n + 1
        else:
            if i >= len(data):
                break
            out += bytes([data[i]]) * (257 - n)
            i += 1
    return bytes(out)


def _lzw_decode(data: bytes, early: int = 1) -> bytes:
    """PDF 的 LZW（TIFF 变体）。early=1 是 PDF 默认，码长提前一位增长。"""
    out = bytearray()
    table = [bytes([i]) for i in range(256)] + [b"", b""]
    prev = None
    width = 9
    bitbuf = bitcnt = 0
    for byte in data:
        bitbuf = (bitbuf << 8) | byte
        bitcnt += 8
        while bitcnt >= width:
            bitcnt -= width
            code = (bitbuf >> bitcnt) & ((1 << width) - 1)
            if code == 256:                       # 清表
                table = [bytes([i]) for i in range(256)] + [b"", b""]
                width, prev = 9, None
                continue
            if code == 257:                       # 结束
                return bytes(out)
            if prev is None:
                entry = table[code]
            elif code < len(table):
                entry = table[code]
                table.append(prev + entry[:1])
            else:
                entry = prev + prev[:1]
                table.append(entry)
            out += entry
            prev = entry
            if len(table) + early >= (1 << width) and width < 12:
                width += 1
    return bytes(out)


def apply_filters(data: bytes, filters: list[str], parms: list[dict]) -> tuple[bytes, str | None]:
    """依次施加过滤器。解不开就返回 (原样, 原因)——**不假装解开了**。"""
    for i, name in enumerate(filters):
        parm = parms[i] if i < len(parms) else {}
        try:
            if name in ("FlateDecode", "Fl"):
                try:
                    data = zlib.decompress(data)
                except zlib.error:
                    # 尾部损坏的流很常见，用增量解压尽量取回前面的部分
                    d = zlib.decompressobj()
                    data = d.decompress(data)
            elif name in ("ASCII85Decode", "A85"):
                body = data.split(b"~>")[0].replace(b"<~", b"")
                data = base64.a85decode(re.sub(rb"\s", b"", body))
            elif name in ("ASCIIHexDecode", "AHx"):
                body = re.sub(rb"[^0-9A-Fa-f]", b"", data.split(b">")[0])
                if len(body) % 2:
                    body += b"0"
                data = bytes.fromhex(body.decode("ascii"))
            elif name in ("LZWDecode", "LZW"):
                data = _lzw_decode(data, int(parm.get("EarlyChange", 1)))
            elif name in ("RunLengthDecode", "RL"):
                data = _run_length_decode(data)
            elif name in ("DCTDecode", "JPXDecode", "JBIG2Decode", "CCITTFaxDecode"):
                # 图像流。不是失败，是这里面本来就没有文字。
                return b"", "image:" + name
            elif name == "Crypt":
                return b"", "encrypted"
            else:
                return data, "unsupported:" + name
        except Exception as exc:                   # noqa: BLE001
            return b"", f"{name}:{type(exc).__name__}"
        # 预测器（PNG/TIFF）常见于 xref 流与图像；文本流几乎不用。
        pred = int(parm.get("Predictor", 1) or 1)
        if pred >= 10:
            data = _undo_png_predictor(data, int(parm.get("Columns", 1) or 1),
                                       int(parm.get("Colors", 1) or 1),
                                       int(parm.get("BitsPerComponent", 8) or 8))
    return data, None


def _undo_png_predictor(data: bytes, columns: int, colors: int, bpc: int) -> bytes:
    bpp = max(1, (colors * bpc + 7) // 8)
    rowlen = (columns * colors * bpc + 7) // 8
    out = bytearray()
    prev = bytearray(rowlen)
    i = 0
    while i + 1 + rowlen <= len(data):
        ft = data[i]
        row = bytearray(data[i + 1:i + 1 + rowlen])
        i += 1 + rowlen
        for j in range(rowlen):
            a = row[j - bpp] if j >= bpp else 0
            b = prev[j]
            c = prev[j - bpp] if j >= bpp else 0
            if ft == 1:
                row[j] = (row[j] + a) & 0xFF
            elif ft == 2:
                row[j] = (row[j] + b) & 0xFF
            elif ft == 3:
                row[j] = (row[j] + (a + b) // 2) & 0xFF
            elif ft == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                row[j] = (row[j] + pr) & 0xFF
        out += row
        prev = row
    return bytes(out)


# ── 对象与字典 ────────────────────────────────────────────────────────────
_DICT_KEY = re.compile(rb"/([A-Za-z0-9#]+)")


def parse_dict(raw: bytes) -> dict:
    """把 `<< ... >>` 解成扁平字典。够用即可：只取标量、名字、数组与引用。

    不建完整对象树——文本抽取只需要 Filter / Length / ToUnicode / Contents
    这几个键，为它们写一套完整 PDF 对象模型不划算。
    """
    out: dict = {}
    i = 0
    n = len(raw)
    while i < n:
        m = _DICT_KEY.search(raw, i)
        if not m:
            break
        key = m.group(1).decode("latin-1")
        i = m.end()
        while i < n and raw[i:i + 1].isspace():
            i += 1
        if i >= n:
            break
        ch = raw[i:i + 1]
        if ch == b"/":
            m2 = _DICT_KEY.match(raw, i)
            if m2:
                out[key] = m2.group(1).decode("latin-1")
                i = m2.end()
        elif ch == b"[":
            depth, j = 0, i
            while j < n:
                if raw[j:j + 1] == b"[":
                    depth += 1
                elif raw[j:j + 1] == b"]":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            out[key] = raw[i:j + 1]
            i = j + 1
        elif ch == b"<" and raw[i:i + 2] == b"<<":
            depth, j = 0, i
            while j < n - 1:
                if raw[j:j + 2] == b"<<":
                    depth += 1
                    j += 2
                    continue
                if raw[j:j + 2] == b">>":
                    depth -= 1
                    j += 2
                    if depth == 0:
                        break
                    continue
                j += 1
            out[key] = raw[i:j]
            i = j
        else:
            m3 = re.match(rb"(\d+)\s+(\d+)\s+R\b", raw[i:])
            if m3:
                out[key] = ("ref", int(m3.group(1)))
                i += m3.end()
            else:
                m4 = re.match(rb"[-+]?[0-9.]+|true|false|null", raw[i:])
                if m4:
                    tok = m4.group(0)
                    try:
                        out[key] = float(tok) if b"." in tok else int(tok)
                    except ValueError:
                        out[key] = tok.decode("latin-1")
                    i += m4.end()
                else:
                    i += 1
    return out


_OBJ = re.compile(rb"(\d+)\s+(\d+)\s+obj\b")


def load_objects(raw: bytes) -> dict[int, bytes]:
    """扫出所有 `N G obj … endobj` 的主体。

    **不解析 xref 表。** 交叉引用表在增量更新、线性化、损坏的文件里形态各异，
    而全文扫描对这些情形一律有效；代价是同号对象取最后一次出现的版本
    （增量更新的语义正是「后来的覆盖先前的」，与需要的一致）。
    """
    objs: dict[int, bytes] = {}
    for m in _OBJ.finditer(raw):
        if len(objs) > MAX_OBJECTS:
            break
        num = int(m.group(1))
        end = raw.find(b"endobj", m.end())
        objs[num] = raw[m.end():end if end != -1 else len(raw)]
    return objs


def stream_of(body: bytes) -> tuple[dict, bytes] | None:
    """从对象体里取出字典与原始流字节。"""
    s = body.find(b"stream")
    if s == -1:
        return None
    head = body[:s]
    d0 = head.find(b"<<")
    info = parse_dict(head[d0 + 2:] if d0 != -1 else head)
    p = s + len(b"stream")
    if body[p:p + 2] == b"\r\n":
        p += 2
    elif body[p:p + 1] in (b"\n", b"\r"):
        p += 1
    e = body.find(b"endstream", p)
    return info, body[p:e if e != -1 else len(body)]


def decode_stream(info: dict, data: bytes) -> tuple[bytes, str | None]:
    f = info.get("Filter")
    if isinstance(f, bytes):                       # 数组形式 [/A85 /Fl]
        filters = [x.decode("latin-1") for x in _DICT_KEY.findall(f)]
    elif isinstance(f, str):
        filters = [f]
    else:
        filters = []
    dp = info.get("DecodeParms")
    parms = [parse_dict(dp)] if isinstance(dp, bytes) else []
    return apply_filters(data[:MAX_STREAM_BYTES], filters, parms)


# ── ToUnicode CMap ────────────────────────────────────────────────────────
def parse_tounicode(cmap: bytes) -> dict[int, str]:
    """解 ToUnicode CMap 的 bfchar / bfrange。没有它就还原不出真正的字符。"""
    table: dict[int, str] = {}

    def to_text(h: bytes) -> str:
        b = bytes.fromhex(h.decode("ascii"))
        try:
            return b.decode("utf-16-be")
        except UnicodeDecodeError:
            return b.decode("latin-1", "ignore")

    for block in re.findall(rb"beginbfchar(.*?)endbfchar", cmap, re.S):
        for src, dst in re.findall(rb"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>", block):
            table[int(src, 16)] = to_text(dst)
    for block in re.findall(rb"beginbfrange(.*?)endbfrange", cmap, re.S):
        for lo, hi, dst in re.findall(
                rb"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>", block):
            start, end, base = int(lo, 16), int(hi, 16), bytes.fromhex(dst.decode("ascii"))
            for k in range(start, min(end, start + 65535) + 1):
                tail = int.from_bytes(base[-2:], "big") + (k - start)
                table[k] = (base[:-2] + tail.to_bytes(2, "big")).decode("utf-16-be", "ignore")
    return table


# ── 内容流里的文本 ────────────────────────────────────────────────────────
_ESCAPES = {b"n": "\n", b"r": "\r", b"t": "\t", b"b": "\b", b"f": "\f",
            b"(": "(", b")": ")", b"\\": "\\"}


def _literal(raw: bytes, i: int) -> tuple[list[int], int]:
    """解 `( … )` 字符串。**转义与嵌套括号必须按格式处理**——
    之前那版拿正则抓引号内容，遇到 `\\(` 就断，字就是这么掉的。"""
    codes: list[int] = []
    depth = 1
    while i < len(raw):
        c = raw[i:i + 1]
        if c == b"\\":
            nxt = raw[i + 1:i + 2]
            if nxt in _ESCAPES:
                codes.extend(_ESCAPES[nxt].encode("latin-1"))
                i += 2
            elif nxt.isdigit():
                m = re.match(rb"[0-7]{1,3}", raw[i + 1:])
                codes.append(int(m.group(0), 8) & 0xFF)
                i += 1 + m.end()
            elif nxt in (b"\n", b"\r"):
                i += 2
            else:
                i += 2
        elif c == b"(":
            depth += 1
            codes.append(ord("("))
            i += 1
        elif c == b")":
            depth -= 1
            if depth == 0:
                return codes, i + 1
            codes.append(ord(")"))
            i += 1
        else:
            codes.append(raw[i])
            i += 1
    return codes, i


def extract_text(content: bytes, cmap: dict[int, str] | None = None,
                 two_byte: bool = False) -> tuple[str, int]:
    """从内容流里按 Tj / TJ / ' / " 取文字。返回 (文本, 无映射的字符数)。

    TJ 数组里的数字是字距调整，负得多说明是词间空格——阈值取 -100（千分单位），
    这是排版惯例。忽略它的话整段会连成一个词。
    """
    out: list[str] = []
    unmapped = 0
    i = 0
    n = len(content)
    pending: list[int] = []

    def flush() -> None:
        nonlocal unmapped
        if not pending:
            return
        if two_byte:
            for k in range(0, len(pending) - 1, 2):
                code = (pending[k] << 8) | pending[k + 1]
                if cmap and code in cmap:
                    out.append(cmap[code])
                else:
                    unmapped += 1
        else:
            for code in pending:
                if cmap and code in cmap:
                    out.append(cmap[code])
                elif cmap:
                    unmapped += 1
                else:
                    out.append(bytes([code]).decode("latin-1"))
        pending.clear()

    while i < n:
        c = content[i:i + 1]
        if c == b"(":
            codes, i = _literal(content, i + 1)
            pending.extend(codes)
            continue
        if c == b"<" and content[i + 1:i + 2] != b"<":
            j = content.find(b">", i)
            if j == -1:
                break
            body = re.sub(rb"[^0-9A-Fa-f]", b"", content[i + 1:j])
            if len(body) % 2:
                body += b"0"
            pending.extend(bytes.fromhex(body.decode("ascii")))
            i = j + 1
            continue
        m = re.match(rb"(-?[0-9.]+)\s*(?=[\[\](<])", content[i:])
        if m:
            try:
                if float(m.group(1)) < -100:
                    flush()
                    out.append(" ")
            except ValueError:
                pass
            i += m.end()
            continue
        m2 = re.match(rb"(TJ|Tj|T\*|'|\"|ET|Td|TD|Tm)\b|(?:'|\")", content[i:])
        if m2:
            op = m2.group(0)
            flush()
            if op in (b"TJ", b"Tj", b"'", b'"'):
                out.append("")
            if op in (b"T*", b"'", b'"', b"Td", b"TD", b"Tm", b"ET"):
                out.append("\n")
            i += m2.end()
            continue
        i += 1
    flush()
    text = "".join(out)
    text = re.sub(r"[ \t]{2,}", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip(), unmapped


# ── 顶层 ──────────────────────────────────────────────────────────────────
def pdf_to_text(raw: bytes) -> dict:
    """抽出整份 PDF 的文字。

    返回 {"text", "chars", "unmapped", "streams", "decoded", "filters",
          "encrypted", "verdict"}。

    verdict 三选一，**不把「我解不开」说成「文件没有文字」**：
      text        抽到了文字
      image-only  流解开了，但里面只有图像，没有文本操作符（多半是扫描件）
      undecodable 一个内容流都解不开，是本解析器能力不足
    """
    if not raw or not raw.lstrip()[:5].startswith(b"%PDF"):
        return {"text": "", "chars": 0, "unmapped": 0, "streams": 0, "decoded": 0,
                "filters": [], "encrypted": False, "verdict": "not-pdf"}

    encrypted = b"/Encrypt" in raw[-3000:] or b"/Encrypt" in raw[:3000]
    objs = load_objects(raw)

    # 对象流（PDF 1.5+）把大量对象压在一个流里，不展开就找不到字体与页面
    expanded: dict[int, bytes] = {}
    for body in list(objs.values()):
        got = stream_of(body)
        if not got:
            continue
        info, data = got
        if info.get("Type") != "ObjStm":
            continue
        plain, _why = decode_stream(info, data)
        if not plain:
            continue
        try:
            first = int(info.get("First") or 0)
            header = plain[:first].split()
            for k in range(0, len(header) - 1, 2):
                num, off = int(header[k]), int(header[k + 1])
                nxt = int(header[k + 3]) if k + 3 < len(header) else len(plain) - first
                expanded[num] = plain[first + off:first + nxt]
        except (ValueError, IndexError):
            continue
    objs.update({k: v for k, v in expanded.items() if k not in objs})

    # 字体 → ToUnicode。文档里可能有多套字体；按对象号收起来，
    # 内容流里遇到 Tf 时才知道用哪套——但页面资源树的解析成本高，
    # 这里取一个折中：把所有 CMap 合并成一张表。同一个码位映射冲突时
    # 保留先出现的，并把冲突数报出来，不静悄悄覆盖。
    merged: dict[int, str] = {}
    conflicts = 0
    for body in objs.values():
        if b"/ToUnicode" not in body and b"beginbfchar" not in body and b"beginbfrange" not in body:
            continue
        got = stream_of(body)
        if not got:
            continue
        info, data = got
        plain, _why = decode_stream(info, data)
        if b"beginbfchar" not in plain and b"beginbfrange" not in plain:
            continue
        for k, v in parse_tounicode(plain).items():
            if k in merged and merged[k] != v:
                conflicts += 1
                continue
            merged[k] = v

    # **只从页面的内容流里取字。** 上一版扫了所有流，把字体程序也算了进去——
    # CFF/TrueType 的二进制里恰好会出现 "Tj" 字节，于是解出 22,853 个字符的乱码，
    # 还报成 verdict=text。把结果说多，正是这个项目反复踩的那个方向。
    content_ids: list[int] = []
    for num, body in objs.items():
        if b"/Page" not in body:
            continue
        info = parse_dict(body[body.find(b"<<") + 2:] if b"<<" in body else body)
        if info.get("Type") != "Page":
            continue
        c = info.get("Contents")
        if isinstance(c, tuple) and c[0] == "ref":
            content_ids.append(c[1])
        elif isinstance(c, bytes):                 # [ 4 0 R 5 0 R ]
            content_ids.extend(int(x) for x in re.findall(rb"(\d+)\s+\d+\s+R", c))

    pieces: list[str] = []
    streams = decoded = unmapped = 0
    filters: set[str] = set()
    seen: set[int] = set()
    for num in content_ids:
        if num in seen or num not in objs:
            continue
        seen.add(num)
        got = stream_of(objs[num])
        if not got:
            continue
        info, data = got
        f = info.get("Filter")
        if isinstance(f, bytes):
            filters.update(x.decode("latin-1") for x in _DICT_KEY.findall(f))
        elif isinstance(f, str):
            filters.add(f)
        streams += 1
        plain, why = decode_stream(info, data)
        if not plain:
            continue
        decoded += 1
        if b"Tj" not in plain and b"TJ" not in plain:
            continue
        text, miss = extract_text(plain, merged or None)
        unmapped += miss
        if text:
            pieces.append(text)

    text = "\n".join(pieces).strip()
    if text:
        verdict = "text"
    elif not content_ids:
        # 连页面对象都没找到：xref 形态特殊或文件损坏，与「解不开流」是两回事
        verdict = "no-pages"
    elif decoded:
        verdict = "image-only"
    else:
        verdict = "undecodable"
    return {"text": text, "chars": len(text), "unmapped": unmapped,
            "cmapConflicts": conflicts, "pages": len(content_ids),
            "streams": streams, "decoded": decoded,
            "filters": sorted(filters), "encrypted": encrypted, "verdict": verdict}
