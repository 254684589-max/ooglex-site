#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读探测：151 家「有申报但没抽到名单」的公司，名单到底在不在申报里。

## 为什么要这条

逐家申报状态落地之后，缺口的形状第一次看清楚了：

    有名单           88 家
    有申报但没抽到    151 家   ← 本探针要查的就是这一档
    无申报           256 家

256 家无申报是制度决定的（Form SD 只管产品里含 3TG 的发行人，银行没有产品），
那个 0 不会变。但 151 家**确实申报了**，抽取器却没从中抽到名单。这一档有两种
完全不同的可能：

  甲、这份申报本来就没列名单。Form SD 强制申报、不强制列名单——特斯拉那份
      42KB 只写流程不写名单，实测确认过。这是制度上限，不是缺陷。
  乙、名单在申报里，但**抽取器没看到**。已知三处可能漏掉：
        · list_documents 只收 .htm/.html —— 冲突矿产报告作为 PDF 附件提交就整份跳过
        · 文件名以 "0" 开头的一律跳过 —— 本意是跳过索引文件，可能误伤真文档
        · MAX_DOCS_PER_FILING = 4 —— 只看最大的四份

甲是事实，乙是缺陷。**在看到真实的文件清单之前，无法判断是哪一种**，
而两者的差别是「这条源到头了」还是「还有 151 家可以补」。

## 所以这个探针只做一件事

把这些公司申报目录里的**全部文件**原样列出来——包括被现有规则过滤掉的那些，
标明谁被过滤、为什么被过滤。不解析、不抽取、不写任何文件。

结论由人看文件清单得出，不由脚本给。前几轮每一次改对规则都是靠打印原始数据，
没有一次是靠自动结论；上一轮探针的自动结论还判错了两处。
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from urllib import error, request

TIMEOUT = 30
GAP = 0.20                 # SEC 建议不超过 10 请求/秒，这里远低于
MAX_COMPANIES = 40

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"

# 过滤规则从抽取器里直接引用，不复刻一份。本探针的全部价值在于如实显示
# 「哪些文件被现有规则挡掉了」——规则各写一份的话，抽取器一改探针就开始说假话。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_form_sd import skip_reason           # noqa: E402

# 文件名像不像一份冲突矿产报告。只用于给人排查线索，不作任何自动判定——
# 申报人给文件起什么名字是它自己的事，猜不中很正常。
# 「d」是 Workiva 那套模板里代替小数点的写法：de-20260518xex1d01.htm = Exhibit 1.01
_CMR_HINT = re.compile(r"conflict|cmr|ex\s*1[-_.d]?01|exhibit\s*1[-_.d]?01", re.I)


def _looks_like_cmr(name: str) -> bool:
    return bool(_CMR_HINT.search(name))


NODES_PATH = "apps/supply-chain/nodes.json"
IDENTITY_PATH = "apps/supply-chain/identity.json"


def _fetch(url: str, accept: str = "*/*") -> bytes:
    req = request.Request(url, headers={"User-Agent": UA, "Accept": accept})
    with request.urlopen(req, timeout=TIMEOUT) as resp:
        return resp.read(8_000_000)


def _why(exc: Exception) -> str:
    if isinstance(exc, error.HTTPError):
        return f"HTTP {exc.code}"
    return f"{type(exc).__name__}: {exc}"


def latest_form_sd(cik: int) -> dict | None:
    """取该 CIK 最近一份 Form SD 的归档目录。"""
    url = f"https://data.sec.gov/submissions/CIK{cik:010d}.json"
    payload = json.loads(_fetch(url, accept="application/json").decode("utf-8", "replace"))
    recent = (payload.get("filings") or {}).get("recent") or {}
    forms = recent.get("form") or []
    for i, form in enumerate(forms):
        if form != "SD":
            continue
        accession = (recent.get("accessionNumber") or [])[i].replace("-", "")
        return {
            "date": (recent.get("filingDate") or [])[i],
            "accession": (recent.get("accessionNumber") or [])[i],
            "indexUrl": f"https://www.sec.gov/Archives/edgar/data/{cik}/{accession}/",
        }
    return None


def main() -> int:
    try:
        nodes = json.load(open(NODES_PATH, encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print(f"[XX] 读不到 {NODES_PATH}：{exc}")
        return 1
    identity = {}
    try:
        raw = json.load(open(IDENTITY_PATH, encoding="utf-8"))
        identity = raw.get("companies") or raw
    except (OSError, ValueError):
        pass

    status = ((nodes.get("coverage") or {}).get("formSd") or {}).get("filingStatus") or {}
    targets = [n for n in nodes.get("nodes") or []
               if status.get(n["symbol"]) == "filed-no-list"]
    if not targets:
        print("没有「有申报但没抽到名单」的公司——要么抽取器还没跑过带逐家状态的版本，"
              "要么这一档确实为空。")
        return 0

    print(f"── 有申报但没抽到名单：{len(targets)} 家，抽样查前 {MAX_COMPANIES} 家 ──\n")
    print("列出申报目录里的**全部文件**，标出现有规则会跳过哪些。\n"
          "重点看：有没有名字像冲突矿产报告、却因为不是 HTML 或名字以 0 开头被跳过的。\n")

    sample = targets[:MAX_COMPANIES]
    stats = {"cmr": 0, "pdf": 0, "lost": 0, "over4": 0, "clean": 0, "failed": 0}
    for node in sample:
        symbol = node["symbol"]
        cik = node.get("cik") or (identity.get(symbol) or {}).get("cik")
        if not cik:
            print(f"[XX] {symbol:<6} 没有 CIK，跳过")
            stats["failed"] += 1
            continue
        try:
            filing = latest_form_sd(int(cik))
            time.sleep(GAP)
        except Exception as exc:                       # noqa: BLE001
            print(f"[XX] {symbol:<6} 取申报索引失败：{_why(exc)}")
            stats["failed"] += 1
            continue
        if not filing:
            # 逐家状态说它申报过，这里却查不到——两处对不上，如实报出来。
            print(f"[??] {symbol:<6} 状态记为「有申报」但现在查不到 Form SD")
            stats["failed"] += 1
            continue
        try:
            payload = json.loads(_fetch(filing["indexUrl"] + "index.json",
                                        accept="application/json").decode("utf-8", "replace"))
            time.sleep(GAP)
        except Exception as exc:                       # noqa: BLE001
            print(f"[XX] {symbol:<6} 取目录失败：{_why(exc)}")
            stats["failed"] += 1
            continue

        items = ((payload.get("directory") or {}).get("item")) or []
        rows = []
        for item in items:
            name = str(item.get("name") or "")
            try:
                size = int(item.get("size") or 0)
            except (TypeError, ValueError):
                size = 0
            rows.append((name, size, skip_reason(name)))
        rows.sort(key=lambda r: -r[1])

        kept = [r for r in rows if r[2] is None]
        # 被跳过的 0 字节索引文件不是损失——那正是规则要跳的东西。
        # 首轮把它们算进「现有规则整份看不到」，40 家全中招，看着像发现了大金矿，
        # 其实一个都不是。**只有被跳过且有实质体积的文件才可能是损失。**
        pdfs = [r for r in rows if r[0].lower().endswith(".pdf") and r[1] > 4096]
        lost = [r for r in rows if r[2] and r[1] > 8192
                and not r[0].lower().endswith((".jpg", ".jpeg", ".png", ".gif",
                                               ".xsd", ".xml", ".zip", ".txt"))]
        # 真正该问的问题：这份申报里有没有一份**会读的**冲突矿产报告附件？
        # 有，却没抽到名单 —— 那就不是文件没选对，是解析器解不出来。
        cmr = [r for r in kept if _looks_like_cmr(r[0]) and r[1] > 8192]
        if pdfs:
            stats["pdf"] += 1
        if lost:
            stats["lost"] += 1
        if len(kept) > 4:
            stats["over4"] += 1
        if cmr:
            stats["cmr"] += 1
        elif not pdfs and not lost:
            stats["clean"] += 1

        flags = []
        if cmr:
            flags.append(f"有会读的冲突矿产报告 {cmr[0][1] // 1024}KB，却没抽到名单")
        if pdfs:
            flags.append(f"PDF {len(pdfs)} 份（{pdfs[0][1] // 1024}KB）")
        if lost:
            flags.append(f"被跳过的实质文件 {len(lost)} 份")
        if len(kept) > 4:
            flags.append(f"HTML {len(kept)} 份超过只看 4 份的上限")
        mark = "!!" if flags else "--"
        print(f"[{mark}] {symbol:<6} {filing['date']}  {filing['accession']}"
              + (f"  ← {'；'.join(flags)}" if flags else ""))
        for name, size, why in rows[:9]:
            tag = f"跳过（{why}）" if why else "会读"
            print(f"         {size // 1024:>6}KB  {tag:<18} {name}")
        if len(rows) > 9:
            print(f"         …另有 {len(rows) - 9} 份")
        print(f"         {filing['indexUrl']}")

    print("\n── 结论 ────────────────────────────────────────────────────────")
    print(f"抽样 {len(sample)} 家：")
    print(f"  有会读的冲突矿产报告却没抽到名单  {stats['cmr']} 家"
          "  ←← 文件选对了，是**解析器**解不出来")
    print(f"  冲突矿产报告是 PDF               {stats['pdf']} 家"
          "  ←← 现有规则整份看不到")
    print(f"  有被跳过的实质文件               {stats['lost']} 家")
    print(f"  会读的 HTML 超过 4 份            {stats['over4']} 家 —— 第 5 份起看不到")
    print(f"  以上都不沾                      {stats['clean']} 家 —— 这些多半真的没列名单")
    print(f"  查不到／失败                    {stats['failed']} 家")
    print("\n注意一：0 字节的 index / index-headers 文件被跳过**不是损失**，"
          "那正是规则要跳的东西。")
    print("        首轮把它们算进「看不到的文件」，40 家全中招，看着像发现了大金矿，"
          "其实一个都不是。")
    print("注意二：上面的计数只说明**文件层面**的情况，不说明那些文件里真有名单。")
    print("        要判断名单在不在，得点开上面的归档地址看原文——"
          "这一步由人做，本探针不替它下结论。")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
