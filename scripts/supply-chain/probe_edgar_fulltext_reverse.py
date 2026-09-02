#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读探测：EDGAR 全文检索「反查」能不能产出高精度的供应链关系边。

## 为什么改走这条路

首轮实测否决了「逐家解析 10-K 指望里面有客户名」的做法（见 docs/SUPPLY_CHAIN_GRAPH.md
第 8.5 节）：10 家样本 78 处客户集中度披露里只有 1 条真实客户名，8/10 家一处都没点名。
根因是 ASC 280 要求披露重大客户的存在与占比、**不要求披露身份**。

反查把问题倒过来：不指望对方主动写名字，而是**拿确定的名字去搜谁提到了它**。
`efts.sec.gov` 首轮已实测可用。

## 这个探针要回答三件事

1. **语法**——能不能限定表单类型、日期、并做短语精确匹配；返回结构里有没有申报人
   身份（CIK、公司名）和文档定位（accession、文件名）；
2. **上限**——首轮返回的 `10000` 是不是硬上限；`hits.total.relation` 说的是精确值
   还是下界；能不能靠日期切片把每片压到上限以内；
3. **精度**——这是关键。「提到 Apple Inc.」不等于「是 Apple 的供应商」：可能是竞争
   对手、诉讼、举例、指数成分、持仓。因此对命中文档取提及处的上下文窗口，按规则分成
   客户关系／竞争关系／其他三类并报告占比。

**精度不达标就不能建边。** 首轮的教训是抽出的 6 条里 3 条是噪声，照此建边会产出指向
错误公司的关系——规范里定义的唯一不可挽回的错误。

## 绝不做的事

不写任何关系数据。不把「提到」当成「供应关系」。上下文分类只用于**估算精度**，
不作为边的判据；真要建边时每条仍须人工或更严格的规则确认，并挂上原文出处。

合规：SEC 要求声明身份的 User-Agent 并限速每秒 10 次，本脚本远低于上限，联系方式
从环境变量读取，不硬编码任何个人邮箱。只读，不写仓库任何数据文件。
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from urllib import error, request
from urllib.parse import quote

TIMEOUT = 30
GAP = 0.35
MAX_REQUESTS = 45
BODY_LIMIT = 12_000_000

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"

FTS = "https://efts.sec.gov/LATEST/search-index"

# 深测目标：用户点名的用例。名字用申报文件里的正式写法，不用口语名。
DEEP_TARGET = '"Apple Inc."'
# 只数命中量、不深测的目标，用来看反查在不同体量公司上的规模
COUNT_TARGETS = ['"NVIDIA Corporation"', '"Taiwan Semiconductor"', '"Samsung Electronics"']

DEEP_DOCS = 8          # 深测抓几份原文；每份 1.5~3.4MB，不宜多

# ── 上下文分类规则 ──────────────────────────────────────────────────────────
# 「提到」不等于「供应关系」。这三组规则只用于估算精度，不作为建边判据。
CUSTOMER_CUES = [
    r"\bour (?:largest |principal |significant |major |key )?customers?\b",
    r"\brevenue[s]? from\b", r"\bsales to\b", r"\bnet (?:revenue|sales) (?:from|to)\b",
    r"\baccounted for\b", r"\bsupply(?:ing)? (?:to|products to)\b",
    r"\bsupplier (?:to|of)\b", r"\bship(?:ped|ments)? to\b",
    r"\bpurchases? from\b", r"\bcustomer concentration\b",
]
COMPETITOR_CUES = [
    r"\bcompet(?:e|es|ing|itor|itors|ition)\b", r"\bsuch as\b", r"\bincluding\b",
    r"\bpeer(?:s| group)\b", r"\balternatives?\b",
]
LEGAL_CUES = [
    r"\bv\.\s", r"\blitigation\b", r"\blawsuit\b", r"\bcomplaint\b", r"\bcourt\b",
    r"\bpatent infringement\b", r"\bplaintiff\b", r"\bdefendant\b",
]


class Budget:
    def __init__(self, total: int = MAX_REQUESTS) -> None:
        self.left = total

    def spend(self) -> bool:
        if self.left <= 0:
            return False
        self.left -= 1
        return True


BUDGET = Budget()


def _fetch(url: str, accept: str = "application/json") -> tuple[bytes, dict]:
    if not BUDGET.spend():
        raise RuntimeError("已达全局请求上限，未发起")
    req = request.Request(url, headers={
        "User-Agent": UA, "Accept": accept, "Accept-Encoding": "gzip, deflate",
    })
    started = time.time()
    with request.urlopen(req, timeout=TIMEOUT) as response:
        raw = response.read(BODY_LIMIT)
        if response.headers.get("Content-Encoding") == "gzip":
            import gzip
            try:
                raw = gzip.decompress(raw)
            except Exception:                      # noqa: BLE001
                pass
        return raw, {"status": response.status, "bytes": len(raw),
                     "elapsedMs": int((time.time() - started) * 1000)}


def _why(exc: Exception) -> str:
    if isinstance(exc, error.HTTPError):
        return f"HTTP {exc.code}"
    if isinstance(exc, error.URLError):
        return f"网络失败 {exc.reason}"
    return f"{type(exc).__name__}: {exc}"


def search(phrase: str, **params) -> dict:
    """发一次全文检索。params 原样拼进查询串，用来实测哪些参数被接受。"""
    parts = [f"q={quote(phrase, safe='')}"]
    for key, value in params.items():
        if value is not None:
            parts.append(f"{key}={quote(str(value), safe='')}")
    body, meta = _fetch(f"{FTS}?{'&'.join(parts)}")
    payload = json.loads(body.decode("utf-8", "replace"))
    hits = payload.get("hits") or {}
    total = hits.get("total") or {}
    return {
        "ok": True,
        "total": total.get("value"),
        # relation=eq 是精确值，gte 表示「至少这么多」，即被上限截断
        "relation": total.get("relation"),
        "returned": len(hits.get("hits") or []),
        "aggregations": sorted((payload.get("aggregations") or {}).keys()),
        "raw": payload,
        **meta,
    }


def hit_identity(hit: dict) -> dict:
    """从命中项里取申报人身份与文档定位——建边必须能指回具体文件。"""
    source = hit.get("_source") or {}
    names = source.get("display_names") or []
    ciks = source.get("ciks") or []
    doc_id = str(hit.get("_id") or "")
    accession, _, filename = doc_id.partition(":")
    return {
        "displayName": names[0] if names else "",
        "cik": ciks[0] if ciks else None,
        "formType": source.get("root_form") or source.get("file_type"),
        "fileDate": source.get("file_date"),
        "accession": accession,
        "filename": filename,
    }


def document_url(identity: dict) -> str | None:
    cik, accession, filename = identity["cik"], identity["accession"], identity["filename"]
    if not (cik and accession and filename):
        return None
    return (f"https://www.sec.gov/Archives/edgar/data/{str(cik).lstrip('0')}/"
            f"{accession.replace('-', '')}/{filename}")


def _sentence_around(plain: str, start: int, end: int) -> str:
    """取包含该次提及的那一句。

    为什么必须收到句子级：520 字符的窗口里几乎必然出现无关的 `accounted for`
    （讲的是分部营收），会把「我们与 Apple 竞争」误判成「Apple 是我们的客户」——
    精度虚高，正好是会误导人去建错误边的方向（对抗用例实测，见 CHANGELOG）。

    `Inc.` `Corp.` 这类缩写会造成假句界，导致句子被截短。截短只会让线索变少、
    判定更保守，偏差方向安全，因此不额外处理。
    """
    left = plain.rfind(". ", max(0, start - 400), start)
    right = plain.find(". ", end, end + 400)
    lo = left + 2 if left != -1 else max(0, start - 140)
    hi = right + 1 if right != -1 else min(len(plain), end + 140)
    return plain[lo:hi]


def classify_mentions(plain: str, phrase: str) -> dict:
    """对每处提及按其所在句子分类。只为估算精度，不作为建边判据。"""
    target = phrase.strip('"')
    counts = {"customer": 0, "competitor": 0, "legal": 0, "other": 0}
    samples: dict[str, str] = {}
    for match in list(re.finditer(re.escape(target), plain, re.I))[:40]:
        sentence = _sentence_around(plain, match.start(), match.end())
        if any(re.search(p, sentence, re.I) for p in CUSTOMER_CUES):
            bucket = "customer"
        elif any(re.search(p, sentence, re.I) for p in LEGAL_CUES):
            bucket = "legal"
        elif any(re.search(p, sentence, re.I) for p in COMPETITOR_CUES):
            bucket = "competitor"
        else:
            bucket = "other"
        counts[bucket] += 1
        # 样例保留更宽的窗口，便于人工核对分类对不对——首轮的教训是
        # 不能只看机器结论，必须能读到原文。
        window = plain[max(0, match.start() - 260):match.end() + 260]
        samples.setdefault(bucket, re.sub(r"\s+", " ", window).strip()[:240])
    return {"counts": counts, "samples": samples, "mentions": sum(counts.values())}


def main() -> None:
    report: dict = {}

    # ── A. 语法：哪些参数被接受，返回结构里有没有建边需要的身份与定位 ──────
    print("── A. 查询语法 ──────────────────────────────────────────────────────")
    syntax_cases = {
        "仅短语": {},
        "限定10-K": {"forms": "10-K"},
        "限定10-K+日期": {"forms": "10-K", "startdt": "2025-01-01", "enddt": "2026-09-01"},
        "限定10-K+年度切片": {"forms": "10-K", "startdt": "2025-01-01", "enddt": "2025-12-31"},
    }
    report["syntax"] = {}
    first_ok = None
    for label, params in syntax_cases.items():
        try:
            outcome = search(DEEP_TARGET, **params)
        except Exception as exc:                   # noqa: BLE001
            outcome = {"ok": False, "why": _why(exc)}
        raw = outcome.pop("raw", None)
        report["syntax"][label] = outcome
        if outcome.get("ok"):
            if first_ok is None and params.get("forms"):
                first_ok = raw
            print(f"[OK] {label:<18} 命中 {outcome['total']} ({outcome['relation']})  "
                  f"返回 {outcome['returned']} 条  聚合 {outcome['aggregations']}  {outcome['elapsedMs']}ms")
        else:
            print(f"[XX] {label:<18} {outcome.get('why')}")
        time.sleep(GAP)

    # ── B. 上限：10000 是不是硬顶，能不能翻页 ────────────────────────────────
    print("\n── B. 结果上限与分页 ────────────────────────────────────────────────")
    report["paging"] = {}
    for label, offset in (("首页", 0), ("第100条起", 100), ("第9900条起", 9900), ("第10000条起", 10000)):
        try:
            outcome = search(DEEP_TARGET, forms="10-K", **{"from": offset})
            outcome.pop("raw", None)
        except Exception as exc:                   # noqa: BLE001
            outcome = {"ok": False, "why": _why(exc)}
        report["paging"][label] = outcome
        detail = (f"返回 {outcome['returned']} 条（总数 {outcome['total']} {outcome['relation']}）"
                  if outcome.get("ok") else outcome.get("why", ""))
        print(f"[{'OK' if outcome.get('ok') else 'XX'}] {label:<12} offset={offset:<6} {detail}")
        time.sleep(GAP)

    # ── C. 精度：提到 ≠ 供应关系 ────────────────────────────────────────────
    print("\n── C. 精度：命中里有多少真是供应关系 ────────────────────────────────")
    print(f"    目标 {DEEP_TARGET}，抓前 {DEEP_DOCS} 份原文逐处分类上下文\n")
    report["precision"] = {"target": DEEP_TARGET, "documents": []}
    hits = ((first_ok or {}).get("hits") or {}).get("hits") or []
    totals = {"customer": 0, "competitor": 0, "legal": 0, "other": 0}
    docs_with_customer = 0
    for hit in hits[:DEEP_DOCS]:
        identity = hit_identity(hit)
        url = document_url(identity)
        entry = {**identity, "url": url}
        if not url:
            entry["ok"] = False
            entry["why"] = "命中项里没有足够的文档定位信息"
        else:
            try:
                body, meta = _fetch(url, accept="text/html,*/*")
                text = body.decode("utf-8", "replace")
                plain = re.sub(r"<[^>]+>", " ", text)
                plain = re.sub(r"&(?:nbsp|#160|amp|#38);", " ", plain)
                plain = re.sub(r"\s+", " ", plain)
                entry.update({"ok": True, "bytes": meta["bytes"], **classify_mentions(plain, DEEP_TARGET)})
                for key in totals:
                    totals[key] += entry["counts"][key]
                if entry["counts"]["customer"]:
                    docs_with_customer += 1
            except Exception as exc:               # noqa: BLE001
                entry.update({"ok": False, "why": _why(exc)})
        report["precision"]["documents"].append(entry)
        if entry.get("ok"):
            counts = entry["counts"]
            print(f"[{'OK' if counts['customer'] else 'XX'}] "
                  f"{str(entry['displayName'])[:38]:<40} {entry['formType']} {entry['fileDate']}  "
                  f"提及 {entry['mentions']}  客户 {counts['customer']} / 竞争 {counts['competitor']}"
                  f" / 诉讼 {counts['legal']} / 其他 {counts['other']}")
            sample = (entry.get("samples") or {}).get("customer")
            if sample:
                print(f"     客户语境：…{sample[:170]}…")
        else:
            print(f"[XX] {str(entry.get('displayName'))[:38]:<40} {entry.get('why')}")
        time.sleep(GAP)

    # ── D. 其他目标的命中规模 ────────────────────────────────────────────────
    print("\n── D. 其他目标命中规模 ──────────────────────────────────────────────")
    report["otherTargets"] = {}
    for phrase in COUNT_TARGETS:
        try:
            outcome = search(phrase, forms="10-K")
            outcome.pop("raw", None)
        except Exception as exc:                   # noqa: BLE001
            outcome = {"ok": False, "why": _why(exc)}
        report["otherTargets"][phrase] = outcome
        detail = (f"命中 {outcome['total']} ({outcome['relation']})"
                  if outcome.get("ok") else outcome.get("why", ""))
        print(f"[{'OK' if outcome.get('ok') else 'XX'}] {phrase:<28} {detail}")
        time.sleep(GAP)

    # ── 结论 ────────────────────────────────────────────────────────────────
    mentions = sum(totals.values())
    precision = round(100.0 * totals["customer"] / mentions, 1) if mentions else 0.0
    analysed = [d for d in report["precision"]["documents"] if d.get("ok")]
    capped = any(v.get("relation") == "gte" for v in report["syntax"].values() if v.get("ok"))

    print("\n── 结论 ────────────────────────────────────────────────────────────")
    print(f"语法：限定表单{'可用' if report['syntax'].get('限定10-K', {}).get('ok') else '不可用'}，"
          f"日期切片{'可用' if report['syntax'].get('限定10-K+年度切片', {}).get('ok') else '不可用'}")
    print(f"上限：{'命中总数被截断（relation=gte），需靠日期切片分段取全' if capped else '返回精确总数，未触上限'}")
    print(f"精度：{len(analysed)} 份原文共 {mentions} 处提及——"
          f"客户语境 {totals['customer']}（{precision}%）/ 竞争 {totals['competitor']}"
          f" / 诉讼 {totals['legal']} / 其他 {totals['other']}")
    print(f"      {docs_with_customer}/{len(analysed)} 份文档至少有一处客户语境")
    verdict = ("精度足够高，可进入「按名反查 + 上下文确认」的抽取器设计"
               if precision >= 30 else
               "**精度不足**：多数提及不是供应关系，直接建边会产出错误关系；"
               "需先收紧上下文规则或改用更强的定位（如只取分部报告与客户集中度章节）再评估")
    print(f"反查可行性：{verdict}")

    report["verdict"] = {
        "formFilterWorks": bool(report["syntax"].get("限定10-K", {}).get("ok")),
        "dateSliceWorks": bool(report["syntax"].get("限定10-K+年度切片", {}).get("ok")),
        "totalsCapped": capped,
        "documentsAnalysed": len(analysed),
        "mentions": mentions,
        "customerContext": totals["customer"],
        "precisionPct": precision,
        "docsWithCustomerContext": docs_with_customer,
        "requestsSpent": MAX_REQUESTS - BUDGET.left,
    }

    out = os.environ.get("PROBE_OUTPUT")
    if out:
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "w", encoding="utf-8") as handle:
            json.dump(report, handle, ensure_ascii=False, indent=2)
        print(f"报告：{out}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
