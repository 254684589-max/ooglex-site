#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读探测：点名几家公司，把它们 Form SD 里**每一份文档的真实内容形态**打出来。

## 这条探针要回答两个 P1 问题

一、**洛马／埃森哲／丹纳赫那三份「整份没有表格」的报告，名单到底在不在。**
    上一轮只数出 `<table>0 <tr>0`，那只说明「没有 HTML 表格」，
    不说明「没有名单」——名单可能排成段落、列表，或者干脆是张图。
    待办里写着「要点开原文看名单在不在，**不要猜**」，这就是点开原文。

二、**PDF 附件里有没有名单。** 抽取器的 `list_documents` 只收 .htm/.html，
    麦当劳的 formsd2026.pdf（493KB）整份看不到。`pdf_text.py` 已经能解 PDF，
    但接线之前得先看清 PDF 里到底有没有东西——**先探后建**。

## 只打印，不判定

打的是：文件清单（含被规则过滤掉的，标明理由）、每份的体积与类型、
HTML 的标签计数与正文抽样、PDF 的解析裁决与文字抽样。

**不给「有名单／没名单」的结论。** 这个项目每一次改对规则都是靠人看原始数据，
没有一次是靠脚本的自动结论；上一轮探针的自动结论还判错过两处。

不写任何数据文件，不建任何边。
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sys
import time
from html.parser import HTMLParser
from urllib import error, request

TIMEOUT = 45
GAP = 0.20
BODY_LIMIT = 24_000_000
SAMPLE = 1200              # 正文抽样字符数

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_form_sd import skip_reason, latest_form_sd, _fetch   # noqa: E402


def load_pdf_text():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pdf_text.py")
    spec = importlib.util.spec_from_file_location("pdf_text", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class _Text(HTMLParser):
    """抽出可见正文，并顺带统计结构标签。

    统计 li/p/br 是因为**名单不一定排成表格**：有的申报把冶炼厂排成项目符号，
    有的每行一个 <p>。只数 table/tr 会把这两种都说成「没有名单」。
    """

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.counts: dict[str, int] = {}
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        self.counts[tag] = self.counts.get(tag, 0) + 1
        if tag in ("script", "style"):
            self._skip += 1

    def handle_endtag(self, tag):
        if tag in ("script", "style") and self._skip:
            self._skip -= 1

    def handle_data(self, data):
        if not self._skip and data.strip():
            self.parts.append(data.strip())

    def text(self) -> str:
        return re.sub(r"\s+", " ", " ".join(self.parts)).strip()


def list_all_documents(index_url: str) -> list[dict]:
    """列出申报目录里的**全部**文件，包括现有规则会过滤掉的。"""
    payload = json.loads(_fetch(index_url.rstrip("/") + "/index.json",
                                accept="application/json").decode("utf-8", "replace"))
    out = []
    for item in ((payload.get("directory") or {}).get("item")) or []:
        name = str(item.get("name") or "")
        try:
            size = int(item.get("size") or 0)
        except (TypeError, ValueError):
            size = 0
        out.append({"name": name, "size": size, "skip": skip_reason(name)})
    out.sort(key=lambda d: -d["size"])
    return out


# 名单里几乎一定会出现的词。**只作为给人看的线索，不作判定**——
# 命中不代表有名单，不命中也不代表没有。分开计数是因为它们的分量完全不同：
# smelter／refiner 在尽职调查叙述里满天飞；**CID 编号只会出现在真名单里**。
_HINTS = {
    "CID编号": re.compile(r"\bCID[\s\-_]?\d{4,6}\b", re.I),
    "smelter": re.compile(r"smelter", re.I),
    "refiner": re.compile(r"refiner", re.I),
    "国名样本": re.compile(r"\b(CHINA|JAPAN|BRAZIL|INDONESIA|MALAYSIA|PERU|BOLIVIA)\b"),
    "附录": re.compile(r"\b(appendix|annex|exhibit\s+[A-Z]|schedule\s+[A-Z])\b", re.I),
}


def probe_company(symbol: str, cik: int, pdf_mod, max_docs: int,
                  ledger: list[dict], quiet: bool = False) -> None:
    print(f"\n{'=' * 72}\n{symbol}  CIK {cik}")
    try:
        filing = latest_form_sd(cik)
    except Exception as exc:                       # noqa: BLE001
        # 探针在 Actions 里一次跑好几家，一家取不到不该把整轮带走——
        # 后面那几家的原始内容才是这轮要看的东西。
        print(f"  [XX] 取申报清单失败：{type(exc).__name__}: {exc}")
        return
    time.sleep(GAP)
    if not filing:
        print("  没有 Form SD 申报")
        return
    print(f"  申报 {filing['accession']}  {filing['filingDate']}  共 {filing['totalSD']} 份 SD")
    print(f"  {filing['indexUrl']}")
    try:
        docs = list_all_documents(filing["indexUrl"])
    except Exception as exc:                       # noqa: BLE001
        print(f"  [XX] 目录取不到：{type(exc).__name__}: {exc}")
        return
    time.sleep(GAP)

    if not quiet:
        print(f"\n  目录里共 {len(docs)} 个文件（按体积倒序，标出被现有规则挡掉的）：")
        for d in docs:
            mark = f"  ← 抽取器跳过：{d['skip']}" if d["skip"] else ""
            print(f"    {d['size']:>9,}  {d['name']}{mark}")

    # 逐份取内容。**包括被规则挡掉的**——本探针的价值就在于看见被挡掉的东西。
    looked = 0
    for d in docs:
        low = d["name"].lower()
        if not low.endswith((".htm", ".html", ".pdf", ".txt")):
            continue
        if d["size"] < 2000:                       # 索引与占位文件
            continue
        if looked >= max_docs:
            print(f"\n  （只看前 {max_docs} 份，其余略）")
            break
        looked += 1
        url = filing["indexUrl"] + d["name"]
        if not quiet:
            print(f"\n  ── {d['name']}  {d['size']:,} 字节"
                  + (f"  [现有规则会跳过：{d['skip']}]" if d["skip"] else "") + " ──")
        try:
            raw = _fetch(url, accept="*/*")
        except Exception as exc:                   # noqa: BLE001
            print(f"    [XX] 取不到：{type(exc).__name__}: {exc}")
            continue
        time.sleep(GAP)

        counts_tags: dict[str, int] | None = None
        if low.endswith(".pdf"):
            got = pdf_mod.pdf_to_text(raw)
            print(f"    [PDF] {symbol} {d['name']} 裁决={got['verdict']}  "
                  f"页 {got.get('pages')}  字符 {got['chars']}  "
                  f"流 {got['decoded']}/{got['streams']}  加密={got['encrypted']}")
            text = got["text"]
        else:
            parser = _Text()
            try:
                parser.feed(raw.decode("utf-8", "replace"))
            except Exception as exc:               # noqa: BLE001
                print(f"    [XX] HTML 解析异常：{type(exc).__name__}: {exc}")
                continue
            c = counts_tags = parser.counts
            if not quiet:
                print(f"    标签：table {c.get('table',0)}  tr {c.get('tr',0)}  "
                  f"td {c.get('td',0)}  li {c.get('li',0)}  p {c.get('p',0)}  "
                      f"br {c.get('br',0)}  div {c.get('div',0)}  img {c.get('img',0)}")
            text = parser.text()

        # 线索词分开计数。**CID 编号是决定性的那个**：真名单几乎一定带 RMI 编号，
        # 而 smelter/refiner 在尽职调查的叙述正文里满天飞，数它只能说明这份报告
        # 在谈冶炼厂，说明不了它在**列**冶炼厂。
        counts = {k: len(rx.findall(text)) for k, rx in _HINTS.items()}
        # 记进汇总表。**Actions 的日志只读得到末尾那一段**，而每份文档的正文
        # 抽样又很长，前面几家会被挤出可读范围。所以把各份的计数在收尾处
        # 再列一遍——列的是数，不是结论。
        ledger.append({"symbol": symbol, "name": d["name"], "size": d["size"],
                       "skip": d["skip"], "chars": len(text),
                       "table": (counts_tags or {}).get("table", 0),
                       "tr": (counts_tags or {}).get("tr", 0),
                       **counts})
        if not quiet:
            print(f"    正文 {len(text)} 字符；线索词："
                  + "  ".join(f"{k}={v}" for k, v in counts.items()))
        if text and not quiet:
            print(f"    开头：{text[:SAMPLE]}")
            if len(text) > SAMPLE * 2:
                mid = len(text) // 2
                print(f"    中段：{text[mid:mid + SAMPLE]}")
            # **结尾必须打**。冲突矿产报告的冶炼厂名单绝大多数是**附录**，
            # 排在正文最后。只看开头和中段就下「没有名单」的结论，
            # 正是这个项目反复栽的那个跟头——把结果说多。
            if len(text) > SAMPLE:
                print(f"    结尾：{text[-SAMPLE:]}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--tickers",
                    help="逗号分隔的公司代码，例如 LMT,ACN,DHR,MCD")
    ap.add_argument("--from-status",
                    help="改从 nodes.json 的逐家申报状态里取目标，例如 filed-no-list")
    ap.add_argument("--limit", type=int, default=0,
                    help="配合 --from-status：最多看几家")
    ap.add_argument("--quiet", action="store_true",
                    help="只打文件清单与收尾汇总，不打正文抽样。"
                         "扫几十家时正文会把日志撑爆，而要看的是**分布**")
    ap.add_argument("--max-docs", type=int, default=3,
                    help="每家最多看几份文档正文（默认 3）")
    args = ap.parse_args()

    with open("apps/supply-chain/identity.json", encoding="utf-8") as handle:
        identity = (json.load(handle) or {}).get("companies") or {}

    if args.from_status:
        # 从实际发布的逐家申报状态里取，而不是我手写一串代码——
        # 手写的话看到的永远是我挑出来的那几家，看不到这一档的真实分布。
        with open("apps/supply-chain/nodes.json", encoding="utf-8") as handle:
            status = (((json.load(handle) or {}).get("coverage") or {})
                      .get("formSd") or {}).get("filingStatus") or {}
        wanted = sorted(k for k, v in status.items() if v == args.from_status)
        if args.limit:
            wanted = wanted[:args.limit]
        print(f"从申报状态 {args.from_status!r} 取出 {len(wanted)} 家"
              + (f"（该档共 {sum(1 for v in status.values() if v == args.from_status)} 家）"
                 if args.limit else ""))
    elif args.tickers:
        wanted = [t.strip().upper() for t in args.tickers.split(",") if t.strip()]
    else:
        print("[XX] 要么给 --tickers，要么给 --from-status")
        return 1
    print("只读探针：不写任何文件，不建任何边。")
    print(f"目标 {len(wanted)} 家：{'、'.join(wanted)}")

    pdf_mod = load_pdf_text()
    ledger: list[dict] = []
    missing = []
    for symbol in wanted:
        record = identity.get(symbol)
        cik = (record or {}).get("cik")
        if not cik:
            missing.append(symbol)
            continue
        probe_company(symbol, int(cik), pdf_mod, args.max_docs, ledger, args.quiet)

    if missing:
        print(f"\n[!!] 身份表里没有 CIK，跳过：{'、'.join(missing)}")

    if ledger:
        print(f"\n{'=' * 72}\n汇总（每份文档一行，全是计数，不含结论）\n")
        print(f"  {'代码':<6} {'文件':<34} {'字节':>9} {'正文':>7} "
              f"{'table':>5} {'tr':>4} {'CID':>4} {'smelt':>5} {'国名':>4} {'附录':>4}")
        for r in ledger:
            print(f"  {r['symbol']:<6} {r['name'][:34]:<34} {r['size']:>9,} "
                  f"{r['chars']:>7} {r['table']:>5} {r['tr']:>4} "
                  f"{r['CID编号']:>4} {r['smelter']:>5} {r['国名样本']:>4} {r['附录']:>4}")
        print("\n  CID 编号那一列是决定性的：真名单几乎一定带 RMI 编号，")
        print("  而 smelter 在尽职调查的叙述正文里满天飞，说明不了在列名单。")

    print("\n结论请人看上面的原始内容得出——本探针不判定有没有名单。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
