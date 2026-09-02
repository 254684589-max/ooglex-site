#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读探测：能不能从 SEC EDGAR 规模化抽出「带出处的」公司间供应链关系。

这是供应链图谱第 2 层的生死线，问的问题和 PortWatch 那次一样直白：

1. **认不认得出公司**——495 家标普成分股里有多少能解析到 CIK；
2. **拿不拿得到行业码**——`submissions` 是否返回 SIC，够不够细到判断产业链位置；
3. **抽不抽得出关系**——10-K 正文里「占营收 10% 以上的客户」这类强制披露段落，
   用规则能不能定位；一份 10-K 有多大、抽一次要多久；
4. **全文检索能不能用**——端点形态不写死，逐个候选实测后报告哪个通；
5. **跑一轮要多久**——按 SEC 限速估算 495 家的请求数与耗时。

**为什么必须先探**：公司级供应链关系是金融数据里最贵的一类，商业产品年费以万美元
计。免费路线唯一走得通的是 SEC 公有领域申报文件——但「能取到文件」不等于「能从文件
里可靠地抽出关系」。这两件事之间隔着一整个工程，不实测就动手是在赌。

**绝不做的事**：这个脚本不写任何关系数据。模型「知道」台积电给英伟达代工——但没有
出处的行业知识不是数据来源，把它写进 data.json 就是凭空捏造，违反 AGENTS.md。
本探针只回答「能不能抽」，抽出来的每条边将来都必须挂着可点开核验的原始申报文件。

**合规**：SEC 要求声明身份的 User-Agent 并限速每秒 10 次。本脚本远低于该上限，
联系方式从环境变量读取，不硬编码任何个人邮箱。只读，不写仓库任何数据文件。
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
GAP = 0.35                # 远低于 SEC 每秒 10 次的上限
MAX_REQUESTS = 80
BODY_LIMIT = 12_000_000   # 10-K 正文可能很大，但仍然封顶

# SEC 要求 User-Agent 声明身份与联系方式。默认指向站点联系页，
# 项目所有者可用 SEC_CONTACT 覆盖为申报用邮箱；脚本不硬编码任何个人邮箱。
CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"

SP500_PATH = "apps/companies/sp500.json"

TICKER_MAP_URL = "https://www.sec.gov/files/company_tickers.json"

# 端到端抽取的样本公司：一家品牌整合方、一家上游芯片、一家典型「客户高度集中」的供应商。
# 第三类是抽取效果最关键的样本——客户集中度披露正是在这类公司的 10-K 里。
SAMPLE_TICKERS = [
    # 终端品牌与芯片设计：客户分散，预期点名率低，用来看下限
    "AAPL", "NVDA",
    # 客户高度集中的元件与代工供应商：ASC 280 披露正是在这类公司的 10-K 里
    "AVGO", "QCOM", "SWKS", "JBL", "GLW", "MU",
    # 半导体设备：客户是台积电/三星/英特尔那几家，通常会点名
    "AMAT", "LRCX",
]

# 全文检索端点候选：不写死，实测哪个通。
# 空格必须预先百分号编码：urllib 会直接拒绝带控制字符/空格的 URL（冒烟测试实测）。
_FTS_QUERY = quote('"significant customer"', safe="")
FTS_CANDIDATES = [
    f'https://efts.sec.gov/LATEST/search-index?q={_FTS_QUERY}&forms=10-K',
    f'https://www.sec.gov/cgi-srv/srqsb?text={_FTS_QUERY}&first=1&last=10',
    f'https://efts.sec.gov/LATEST/search-index?q={_FTS_QUERY}',
]

# 客户集中度披露的定位规则。ASC 280 要求披露占营收 10% 以上的客户，
# 措辞高度套路化，因此规则命中率值得实测。
CONCENTRATION_PATTERNS = [
    # 限定词允许叠加：真实申报里是「of our net revenue」而不是「of revenue」。
    # 只写单层限定会漏掉最有价值的那一类句式（离线用例实测，见 CHANGELOG）。
    r"accounted for\s+(?:approximately\s+)?\d{1,2}(?:\.\d+)?%\s+of\s+"
    r"(?:(?:our|the Company's|its|net|total|consolidated|worldwide|annual)\s+)*(?:revenue|sales)",
    r"represented\s+(?:approximately\s+)?\d{1,2}(?:\.\d+)?%\s+of\s+"
    r"(?:(?:our|the Company's|its|net|total|consolidated|worldwide|annual)\s+)*(?:revenue|sales)",
    # 客户名会插在中间（「One customer, Apple Inc., accounted for…」），必须容忍。
    r"(?:one|two|three|four|five|no)\s+customers?[^.]{0,80}?accounted for",
    r"significant customers?",
    r"major customers?",
    r"customer concentration",
    r"10%\s+or\s+more\s+of\s+(?:(?:our|the Company's|its|net|total)\s+)*(?:revenue|sales)",
]

# 定位到披露段落只是第一步。**能不能拿到边，取决于披露有没有点名对方**——
# 大量公司只写「一家客户占 22%」而不写是谁，这类段落抽不出边，只能作为线索。
# 因此探针把「命中段落数」和「其中点名了对方的段落数」分开报告。
NAMED_ENTITY_PATTERN = (
    r"\b([A-Z][A-Za-z0-9&.\-]*(?:\s+[A-Z][A-Za-z0-9&.\-]*){0,3}\s*"
    # 后缀按「长的排前面」，否则 Corp 会把 Corporation 截断成 X Corp。
    # 裸 Co 不能收：它会把「Customer Concentration」误当成「Customer Co」（离线用例实测）。
    r"(?:Corporation|Incorporated|Company|Limited|Holdings|Corp|Inc|Ltd|LLC|Co\.|"
    r"L\.P|plc|PLC|AG|N\.V|S\.A)\.?)"
)

# 苹果供应商名单：用户点名的用例，也是第 1 层的起点。
# 年度 PDF 地址每年变，因此先探落地页，再探已知形态。
APPLE_CANDIDATES = [
    "https://www.apple.com/supplier-responsibility/",
    "https://www.apple.com/supply-chain/",
    "https://investor.apple.com/esg/default.aspx",
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


def _fetch(url: str, accept: str = "*/*") -> tuple[bytes, dict]:
    if not BUDGET.spend():
        raise RuntimeError("已达全局请求上限，未发起")
    req = request.Request(url, headers={
        "User-Agent": UA,
        "Accept": accept,
        "Accept-Encoding": "gzip, deflate",
    })
    started = time.time()
    with request.urlopen(req, timeout=TIMEOUT) as response:
        raw = response.read(BODY_LIMIT)
        if response.headers.get("Content-Encoding") == "gzip":
            import gzip
            try:
                raw = gzip.decompress(raw)
            except Exception:                      # noqa: BLE001 — 截断的 gzip 不致命
                pass
        return raw, {
            "status": response.status,
            "bytes": len(raw),
            "elapsedMs": int((time.time() - started) * 1000),
            "contentType": response.headers.get("Content-Type", ""),
        }


def _why(exc: Exception) -> str:
    if isinstance(exc, error.HTTPError):
        return f"HTTP {exc.code}"
    if isinstance(exc, error.URLError):
        return f"网络失败 {exc.reason}"
    return f"{type(exc).__name__}: {exc}"


def load_sp500_tickers() -> list[str]:
    """从站内已有的成分股文件读代码，不另建第二套事实来源。"""
    try:
        with open(SP500_PATH, encoding="utf-8") as handle:
            payload = json.load(handle)
        return [m["symbol"] for m in payload.get("members", []) if m.get("symbol")]
    except Exception as exc:                       # noqa: BLE001
        print(f"[XX] 读不到 {SP500_PATH}：{_why(exc)}")
        return []


def probe_ticker_map(tickers: list[str]) -> dict:
    """ticker → CIK 官方映射表。这是所有后续调用的入口，通不了后面全免谈。"""
    body, meta = _fetch(TICKER_MAP_URL, accept="application/json")
    payload = json.loads(body.decode("utf-8", "replace"))
    # 官方格式是 {"0": {"cik_str": 320193, "ticker": "AAPL", "title": "Apple Inc."}, ...}
    index = {}
    for row in payload.values() if isinstance(payload, dict) else []:
        if isinstance(row, dict) and row.get("ticker"):
            index[str(row["ticker"]).upper()] = row.get("cik_str")
    resolved = [t for t in tickers if t.upper() in index]
    missing = [t for t in tickers if t.upper() not in index]
    return {
        "ok": True,
        "totalInMap": len(index),
        "asked": len(tickers),
        "resolved": len(resolved),
        "resolvePct": round(100.0 * len(resolved) / len(tickers), 1) if tickers else 0.0,
        "missingSample": missing[:15],
        "_index": index,
        **meta,
    }


def probe_submissions(ticker: str, cik: int) -> dict:
    """公司申报索引：同时验证 SIC 行业码（第 0 层要用）与最近一份 10-K（第 2 层要用）。"""
    url = f"https://data.sec.gov/submissions/CIK{int(cik):010d}.json"
    body, meta = _fetch(url, accept="application/json")
    payload = json.loads(body.decode("utf-8", "replace"))
    recent = payload.get("filings", {}).get("recent", {})
    forms = recent.get("form", []) or []
    accessions = recent.get("accessionNumber", []) or []
    documents = recent.get("primaryDocument", []) or []
    dates = recent.get("filingDate", []) or []
    latest_10k = None
    for i, form in enumerate(forms):
        if form == "10-K":
            latest_10k = {
                "accession": accessions[i] if i < len(accessions) else None,
                "primaryDocument": documents[i] if i < len(documents) else None,
                "filingDate": dates[i] if i < len(dates) else None,
            }
            break
    form_sd = sum(1 for f in forms if f == "SD")
    return {
        "ok": True,
        "ticker": ticker,
        "cik": int(cik),
        "sic": payload.get("sic"),
        "sicDescription": payload.get("sicDescription"),
        "name": payload.get("name"),
        "formsTracked": len(forms),
        "latest10K": latest_10k,
        "formSDCount": form_sd,
        **meta,
    }


def probe_10k_extraction(cik: int, filing: dict) -> dict:
    """把一份真 10-K 拉下来，实测客户集中度披露段落用规则能不能定位。"""
    accession = (filing.get("accession") or "").replace("-", "")
    doc = filing.get("primaryDocument")
    if not accession or not doc:
        return {"ok": False, "why": "申报索引里没有主文档名"}
    url = f"https://www.sec.gov/Archives/edgar/data/{int(cik)}/{accession}/{doc}"
    body, meta = _fetch(url, accept="text/html,*/*")
    text = body.decode("utf-8", "replace")
    # 只做粗去标签：判断规则命中率不需要完美的正文抽取。
    plain = re.sub(r"<[^>]+>", " ", text)
    plain = re.sub(r"&(?:nbsp|#160);", " ", plain)
    plain = re.sub(r"\s+", " ", plain)
    hits: dict[str, int] = {}
    samples: list[str] = []
    named_windows = 0
    total_windows = 0
    named_examples: list[str] = []
    for pattern in CONCENTRATION_PATTERNS:
        found = list(re.finditer(pattern, plain, re.I))
        if not found:
            continue
        hits[pattern] = len(found)
        for match in found[:6]:
            # 取披露句前后各 200 字符作为判断窗口：客户名通常就在同一句里。
            window = plain[max(0, match.start() - 200):match.end() + 200]
            total_windows += 1
            entities = [e for e in re.findall(NAMED_ENTITY_PATTERN, window)
                        if len(e) > 4 and not e.lower().startswith("the compan")]
            if entities:
                named_windows += 1
                if len(named_examples) < 5:
                    named_examples.append(entities[0].strip())
            if len(samples) < 3 and match is found[0]:
                samples.append(window.strip())
    return {
        "ok": True,
        "url": url,
        "rawBytes": meta["bytes"],
        "plainChars": len(plain),
        "elapsedMs": meta["elapsedMs"],
        "patternsHit": len(hits),
        "hitCounts": hits,
        # 命中段落里有多少真的点名了对方——这才决定能不能抽出边
        "windows": total_windows,
        "windowsWithNamedEntity": named_windows,
        "namedEntityExamples": named_examples,
        "samples": samples,          # 留证用：证明抽出来的是真披露文字，不是模型编的
    }


def probe_full_text_search() -> dict:
    """全文检索端点不写死，逐个候选实测。通了才谈规模化反查。"""
    outcomes: dict = {}
    for url in FTS_CANDIDATES:
        try:
            body, meta = _fetch(url, accept="application/json")
            entry: dict = {"ok": True, **meta}
            try:
                payload = json.loads(body.decode("utf-8", "replace"))
                total = (payload.get("hits", {}).get("total", {}) or {}).get("value")
                entry["hits"] = total
                entry["shape"] = list(payload)[:8]
            except Exception:                      # noqa: BLE001
                entry["shape"] = "非JSON响应"
            outcomes[url] = entry
        except Exception as exc:                   # noqa: BLE001
            outcomes[url] = {"ok": False, "why": _why(exc)}
        time.sleep(GAP)
    return outcomes


def probe_apple_list() -> dict:
    """第 1 层起点：苹果年度供应商名单是否公开可取、是什么格式。"""
    outcomes: dict = {}
    for url in APPLE_CANDIDATES:
        try:
            body, meta = _fetch(url)
            entry = {"ok": True, **meta}
            if body[:4] == b"%PDF":
                entry["container"] = "PDF · 需确认可否用标准库解析，否则要评估依赖"
            elif b"<html" in body[:4000].lower():
                # 落地页：地址每年变，靠发现而不是猜。只找 href 会漏掉 JS 里拼的地址，
                # 因此对整页正文找 URL，并单独挑出名字里含 supplier/list 的候选。
                text = body.decode("utf-8", "replace")
                pdfs = re.findall(r'https?://[^\s"\'<>]+?\.pdf', text, re.I)
                relative = re.findall(r'(?:href|src)="(/[^"]+?\.pdf)"', text, re.I)
                supplier_urls = [u for u in re.findall(r'https?://[^\s"\'<>]{6,200}', text, re.I)
                                 if re.search(r'supplier[-_]?list|supply[-_]?chain[-_]?list', u, re.I)]
                entry["container"] = "HTML 落地页"
                entry["pdfLinks"] = sorted(set(pdfs))[:15]
                entry["pdfRelative"] = sorted(set(relative))[:10]
                entry["supplierListCandidates"] = sorted(set(supplier_urls))[:10]
            outcomes[url] = entry
        except Exception as exc:                   # noqa: BLE001
            outcomes[url] = {"ok": False, "why": _why(exc)}
        time.sleep(GAP)
    return outcomes


def main() -> None:
    report: dict = {"contact": "由 SEC_CONTACT 环境变量提供" if os.environ.get("SEC_CONTACT") else "默认站点联系方式"}
    tickers = load_sp500_tickers()
    print(f"── 标普成分股清单：站内 {SP500_PATH} 读到 {len(tickers)} 个代码 ──\n")

    print("── A. ticker → CIK 官方映射 ─────────────────────────────────────────")
    try:
        ticker_map = probe_ticker_map(tickers)
    except Exception as exc:                       # noqa: BLE001
        ticker_map = {"ok": False, "why": _why(exc)}
    index = ticker_map.pop("_index", {})
    report["tickerMap"] = ticker_map
    if ticker_map.get("ok"):
        print(f"[OK] 映射表 {ticker_map['totalInMap']} 家；标普 {ticker_map['asked']} 个代码"
              f"解析到 {ticker_map['resolved']} 个（{ticker_map['resolvePct']}%），"
              f"{ticker_map['bytes']} 字节 / {ticker_map['elapsedMs']}ms")
        if ticker_map["missingSample"]:
            print(f"     未解析样例：{', '.join(ticker_map['missingSample'])}")
    else:
        print(f"[XX] 映射表取不到：{ticker_map.get('why')}")
    time.sleep(GAP)

    print("\n── B. 申报索引：SIC 行业码 + 最近 10-K ──────────────────────────────")
    report["submissions"] = {}
    for ticker in SAMPLE_TICKERS:
        cik = index.get(ticker)
        if not cik:
            report["submissions"][ticker] = {"ok": False, "why": "未解析到 CIK"}
            print(f"[XX] {ticker:<6} 未解析到 CIK")
            continue
        try:
            outcome = probe_submissions(ticker, cik)
        except Exception as exc:                   # noqa: BLE001
            outcome = {"ok": False, "why": _why(exc)}
        report["submissions"][ticker] = outcome
        if outcome.get("ok"):
            tenk = outcome.get("latest10K") or {}
            print(f"[OK] {ticker:<6} CIK {outcome['cik']}  SIC {outcome.get('sic')} "
                  f"{str(outcome.get('sicDescription'))[:34]:<36} "
                  f"最近10-K {tenk.get('filingDate')}  Form SD {outcome['formSDCount']} 份")
        else:
            print(f"[XX] {ticker:<6} {outcome.get('why')}")
        time.sleep(GAP)

    print("\n── C. 端到端抽取：真 10-K 里的客户集中度披露 ────────────────────────")
    report["extraction"] = {}
    for ticker in SAMPLE_TICKERS:
        sub = report["submissions"].get(ticker, {})
        if not sub.get("ok") or not sub.get("latest10K"):
            continue
        try:
            outcome = probe_10k_extraction(sub["cik"], sub["latest10K"])
        except Exception as exc:                   # noqa: BLE001
            outcome = {"ok": False, "why": _why(exc)}
        report["extraction"][ticker] = outcome
        if outcome.get("ok"):
            named = outcome.get("windowsWithNamedEntity", 0)
            total = outcome.get("windows", 0)
            # 点名率才是能成边的比例：命中段落多但一个都不点名，等于零条边。
            print(f"[{'OK' if named else 'XX'}] {ticker:<6} "
                  f"{outcome['rawBytes'] // 1024}KB / 正文 {outcome['plainChars'] // 1000}K字符 / "
                  f"{outcome['elapsedMs']}ms  命中规则 {outcome['patternsHit']}/{len(CONCENTRATION_PATTERNS)}"
                  f"  段落 {total} 处，**点名 {named} 处**")
            for name in outcome.get("namedEntityExamples", [])[:4]:
                print(f"     点名 → {name}")
            for sample in outcome["samples"][:1]:
                print(f"     样例：…{sample[:150]}…")
        else:
            print(f"[XX] {ticker:<6} {outcome.get('why')}")
        time.sleep(GAP)

    print("\n── D. 全文检索端点候选 ──────────────────────────────────────────────")
    report["fullTextSearch"] = probe_full_text_search()
    for url, entry in report["fullTextSearch"].items():
        tag = url.split("//")[1].split("/")[0]
        detail = (f"命中 {entry.get('hits')}  结构 {entry.get('shape')}"
                  if entry.get("ok") else entry.get("why", ""))
        print(f"[{'OK' if entry.get('ok') else 'XX'}] {tag:<22} {detail}")

    print("\n── E. 苹果供应商名单（第 1 层起点） ─────────────────────────────────")
    report["appleSupplierList"] = probe_apple_list()
    for url, entry in report["appleSupplierList"].items():
        detail = (f"{entry.get('bytes')} 字节  {entry.get('container','')}"
                  if entry.get("ok") else entry.get("why", ""))
        print(f"[{'OK' if entry.get('ok') else 'XX'}] {url.rsplit('/', 1)[-1] or 'landing':<30} {detail}")
        for link in (entry.get("supplierListCandidates") or [])[:5]:
            print(f"     疑似名单：{link}")
        for link in (entry.get("pdfLinks") or [])[:6]:
            print(f"     PDF：{link}")
        for link in (entry.get("pdfRelative") or [])[:4]:
            print(f"     相对PDF：{link}")

    # ── 结论：能不能规模化 ──────────────────────────────────────────────────
    # 判定门槛是「点名」而不是「命中」：命中只说明找到了披露段落，
    # 段落里不写对方是谁就抽不出边。
    extraction_ok = [t for t, v in report["extraction"].items()
                     if v.get("ok") and v.get("windowsWithNamedEntity")]
    located_only = [t for t, v in report["extraction"].items()
                    if v.get("ok") and v.get("patternsHit") and not v.get("windowsWithNamedEntity")]
    sizes = [v["rawBytes"] for v in report["extraction"].values() if v.get("ok")]
    times = [v["elapsedMs"] for v in report["extraction"].values() if v.get("ok")]
    resolved = report["tickerMap"].get("resolved", 0)
    avg_ms = int(sum(times) / len(times)) if times else 0
    # 每家两次请求（submissions + 10-K），按本脚本的保守间隔估算，非 SEC 上限
    est_requests = resolved * 2
    est_minutes = round((est_requests * (GAP + avg_ms / 1000.0)) / 60.0, 1) if resolved else 0

    print("\n── 结论 ────────────────────────────────────────────────────────────")
    total_windows = sum(v.get("windows", 0) for v in report["extraction"].values() if v.get("ok"))
    named_windows = sum(v.get("windowsWithNamedEntity", 0) for v in report["extraction"].values() if v.get("ok"))
    print(f"CIK 解析率 {report['tickerMap'].get('resolvePct', 0)}%")
    print(f"客户集中度：{len(report['extraction'])} 家样本共 {total_windows} 处披露段落，"
          f"其中 {named_windows} 处点名对方"
          f"（{round(100.0 * named_windows / total_windows, 1) if total_windows else 0}%）")
    if located_only:
        print(f"只找到披露、但一处都没点名的公司：{', '.join(located_only)}——这些抽不出边，只能算线索")
    if sizes:
        print(f"10-K 体量：{min(sizes)//1024}~{max(sizes)//1024}KB，平均取回 {avg_ms}ms")
    print(f"全量估算：{resolved} 家 × 2 次请求 ≈ {est_requests} 次，约 {est_minutes} 分钟"
          f"（本脚本间隔 {GAP}s，远低于 SEC 每秒 10 次上限）")
    print("第2层可行性：" + (
        f"{len(extraction_ok)}/{len(report['extraction'])} 家样本能抽出点名的对手方，可进入抽取器开发"
        if extraction_ok else
        "**没有任何样本抽出点名的对手方**——只定位到披露段落不足以成边，"
        "需改用全文检索反查（按已知大客户名反向搜谁提到它）或扩大样本再判断"))

    report["verdict"] = {
        "cikResolvePct": report["tickerMap"].get("resolvePct", 0),
        "extractionSamplesNamed": extraction_ok,
        "extractionSamplesLocatedOnly": located_only,
        "windowsTotal": total_windows,
        "windowsNamed": named_windows,
        "avgFetchMs": avg_ms,
        "estimatedRequests": est_requests,
        "estimatedMinutes": est_minutes,
        "layer2Feasible": bool(extraction_ok),   # 以点名为准，不是以命中为准
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
