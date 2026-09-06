#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读探测：公司自己发布的供应商名单能不能成为第二条有出处的数据源。

## 为什么要这条

冶炼厂那一层已经落地，但它是**第三层**、语义是「出现在供应链中」。用户从第一天
想要的是**一级供应商**——直接供货的那一层。SEC 申报给不了：ASC 280 要求披露客户
集中度的幅度、不要求披露身份（已实测否决）。

但**公司自己会发布**。苹果每年发布前 200 大供应商名单（占采购额 98%），
耐克发布制造工厂地图，戴尔、惠普、英特尔、思科都有类似披露。这些是第一方公开
文件，有稳定 URL、有发布日期——**满足现有的 evidence 契约**，和 SEC 申报同一档。

## 这个探针要回答四件事

1. **找得到吗**——上一轮找苹果名单失败过：猜的两个地址都跳回同一个落地页，
   页面上唯一的 PDF 是《供应商行为准则》不是名单。这次不猜地址，改为发现式：
   抓落地页全文里的所有 URL，按文件名打分排序。
2. **是什么格式**——**这决定可行性，不是细节**。仓库规矩是不自动装新依赖，
   而 Python 标准库没有 PDF 解析器。HTML/CSV/XLSX 能解，纯图片型 PDF 解不了。
   所以逐个记录 Content-Type 与体积，不预设。
3. **PDF 能不能取到文字**——用 zlib 解 PDF 流对象、看有没有可读文本，
   这是不装依赖能做的最粗判断。取不到文字就是扫描件，这条路对那家公司走不通。
4. **许可与礼貌**——两件不同的事，必须分开答：
   - **礼貌**：先读 robots.txt，被 Disallow 的路径不抓，如实记下来；
   - **许可**：按 `SUPPLY_CHAIN_SOURCES.md` §4 逐条标 `GOV` / `IGO` / `PRIV`，
     **`PRIV` 一律拦下**。

   这一条曾经只做了前半截。结果是：报告里 robots 一路绿灯、格式解得开、
   内容读得出，看着像张准入通行证——而**许可这一问从头到尾没人答过**。
   `robots.txt 允许抓取` 与 `许可允许再分发` 是两码事：前者是站长对爬虫的
   礼貌约定，后者决定本站能不能把它的内容整理成数据集重新发布。
   现在每家都必须打出许可结论，取得到但不许登记的以 `[!!]` 标出。

## 边界

**本探针不写任何数据文件，不建任何边。** 它只回答「这条源可不可行」。
和前三轮一样：先探后建，探完把真实结果打到日志里人工核对，再决定接不接。
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
import zlib
from urllib import error, parse, request

# 标准库实现的 PDF 文本抽取。与抽取器共用同一份实现，两处各写一份必然会分叉。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pdf_text                                    # noqa: E402

TIMEOUT = 30
GAP = 0.8                  # 对方是普通企业站，比 SEC 更客气些
MAX_REQUESTS = 80
BODY_LIMIT = 8_000_000

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"

# 已知或很可能公开供应商／工厂名单的公司。刻意混几类：
# 终端品牌（苹果、耐克）、整机与半导体（戴尔、惠普、英特尔、英伟达）、
# 网络设备（思科）、以及一家预期没有的（摩根大通）作为对照——
# 没有的那家应当明确报「没有」，而不是被打分器凑出一个假候选。
TARGETS = [
    # 落地页多给几个：首轮苹果、耐克、惠普都因为种子地址不对而空手而归
    # （惠普 404、耐克 404）。404 会如实报出来，不算断言，多试几个成本很低。
    ("AAPL", "苹果", ["https://www.apple.com/supplier-responsibility/",
                      "https://www.apple.com/supplier-responsibility/pdf/",
                      "https://www.apple.com/environment/"]),
    ("NKE", "耐克", ["https://about.nike.com/en/impact-resources",
                     "https://about.nike.com/en/impact/manufacturing-map",
                     "https://about.nike.com/en/impact"]),
    ("DELL", "戴尔", ["https://www.dell.com/en-us/dt/corporate/social-impact/"
                      "advancing-sustainability/sustainable-supply-chain.htm",
                      "https://www.dell.com/en-us/dt/corporate/social-impact/"]),
    ("HPQ", "惠普", ["https://www.hp.com/us-en/hp-information/"
                     "sustainable-impact/supply-chain-responsibility.html",
                     "https://www.hp.com/us-en/hp-information/sustainable-impact.html"]),
    ("INTC", "英特尔", ["https://www.intel.com/content/www/us/en/corporate-"
                        "responsibility/supply-chain.html"]),
    ("CSCO", "思科", ["https://www.cisco.com/c/en/us/about/"
                      "supply-chain-sustainability.html"]),
    ("NVDA", "英伟达", ["https://www.nvidia.com/en-us/csr/"]),
    ("JPM", "摩根大通", ["https://www.jpmorganchase.com/impact"]),   # 对照组：预期没有
]

# 名单类文件的地址长什么样。打分只用于排序候选，不作为「这就是名单」的判据——
# 判据是抓下来之后看内容。
# 打到这个分才算「地址本身指向一份名单」——只有命中 supplier-list /
# manufacturing-map / factory-list 这类明确词才够，「是个 PDF」（2 分）远远不够。
LIST_SCORE = 10

SCORE_RULES = [
    (12, r"supplier[-_]?list"),
    (12, r"supplier[-_]?responsibility[-_]?.*list"),
    (10, r"manufacturing[-_]?map|factory[-_]?list|facilit(y|ies)[-_]?list"),
    (8, r"smelter|refiner"),
    (6, r"supply[-_]?chain.*\.(pdf|xlsx|xls|csv)"),
    (5, r"supplier.*\.(pdf|xlsx|xls|csv)"),
    (3, r"\.(xlsx|xls|csv)$"),
    (2, r"\.pdf$"),
    (-8, r"code[-_]?of[-_]?conduct|standards?[-_]?of[-_]?engagement"),  # 行为准则不是名单
    (-6, r"privacy|cookie|legal|terms"),
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
        "User-Agent": UA, "Accept": accept, "Accept-Encoding": "gzip, deflate"})
    started = time.time()
    with request.urlopen(req, timeout=TIMEOUT) as response:
        raw = response.read(BODY_LIMIT)
        if response.headers.get("Content-Encoding") == "gzip":
            import gzip
            try:
                raw = gzip.decompress(raw)
            except Exception:                      # noqa: BLE001
                pass
        return raw, {
            "status": response.status,
            "contentType": (response.headers.get("Content-Type") or "").split(";")[0],
            "bytes": len(raw),
            "elapsedMs": int((time.time() - started) * 1000),
            "finalUrl": response.geturl(),
        }


def _why(exc: Exception) -> str:
    if isinstance(exc, error.HTTPError):
        return f"HTTP {exc.code}"
    if isinstance(exc, error.URLError):
        return f"网络失败 {exc.reason}"
    return f"{type(exc).__name__}: {exc}"


def robots_rules(origin: str) -> dict:
    """读 robots.txt。抓之前先问一句是基本礼貌，被 Disallow 的路径不碰。"""
    try:
        body, meta = _fetch(origin.rstrip("/") + "/robots.txt", accept="text/plain")
    except Exception as exc:                       # noqa: BLE001
        return {"ok": False, "why": _why(exc), "disallow": []}
    text = body.decode("utf-8", "replace")
    disallow: list[str] = []
    applies = False
    for line in text.splitlines():
        line = line.strip()
        low = line.lower()
        if low.startswith("user-agent:"):
            applies = low.split(":", 1)[1].strip() in ("*",)
        elif applies and low.startswith("disallow:"):
            path = line.split(":", 1)[1].strip()
            if path:
                disallow.append(path)
    return {"ok": True, "bytes": meta["bytes"], "disallow": disallow[:60]}


def blocked(url: str, disallow: list[str]) -> str | None:
    path = parse.urlsplit(url).path or "/"
    for rule in disallow:
        clean = rule.rstrip("*")
        if clean and path.startswith(clean):
            return rule
    return None


def score(url: str) -> int:
    total = 0
    for weight, pattern in SCORE_RULES:
        if re.search(pattern, url, re.I):
            total += weight
    return total


def find_candidates(text: str, base: str) -> list[tuple[int, str]]:
    """从整页正文里找 URL，不只找 href——JS 拼出来的地址在 href 里看不到。"""
    found = set(re.findall(r'https?://[^\s"\'<>()\\]{8,220}', text))
    for rel in re.findall(r'(?:href|src)="(/[^"\s<>]{4,200})"', text):
        found.add(parse.urljoin(base, rel))
    scored = [(score(u), u.rstrip(").,")) for u in found]
    return sorted({(s, u) for s, u in scored if s > 0}, key=lambda p: -p[0])[:12]


def pdf_text_sample(raw: bytes) -> dict:
    """用 pdf_text 抽字。判据分三种，**不把「我解不开」说成「文件没有文字」**。

    早先这里是拿正则在原始字节上找 stream…endstream 再 zlib 解压，吐出来的是
    「A Pr ot ocol  f or Prioritizin g」这种掉字的东西，而且只会 FlateDecode，
    英特尔那三份 ASCII85 包一层的整份解不开，还被报成「多半是扫描件」。
    """
    r = pdf_text.pdf_to_text(raw)
    # **字段名必须对上调用方的契约。** 调用方先设 doc["kind"] = "pdf" 再 update()，
    # 所以这里不能有同名的 kind——曾经有，把 "pdf" 覆盖成了 "text"，
    # 于是 PDF 那条显示分支整个没走，extractable 也没设，
    # 思科三份明明解出了文字，结论却报「0/8 家，内容没取到」。
    return {
        "extractable": r["verdict"] == "text" and r["chars"] > 0,
        "pdfVerdict": r["verdict"],
        "verdict": {
            "text": f"可提取文字（{r['pages']} 页，{r['chars']} 字）",
            "image-only": "流解开了但没有文本操作符，多半是扫描件",
            "undecodable": "本探针解不开这份 PDF 的压缩流——是探针能力不足，"
                           "不能据此说文件没有文字",
            "no-pages": "找不到页面对象：xref 形态特殊或文件损坏",
            "not-pdf": "不是 PDF",
        }.get(r["verdict"], r["verdict"]),
        "streams": r["streams"],
        "inflatedStreams": r["decoded"],
        "textStreams": r["chars"] and r["decoded"] or 0,
        "pages": r["pages"],
        "filters": r["filters"],
        "encrypted": r["encrypted"],
        "unmapped": r["unmapped"],
        "textSample": re.sub(r"\s+", " ", r["text"][:200]).strip(),
    }


def html_shape(raw: bytes) -> dict:
    """HTML 名单的形态：表格行数、看着像公司名的行有多少。"""
    text = raw.decode("utf-8", "replace")
    rows = len(re.findall(r"<tr[\s>]", text, re.I))
    plain = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", text))
    corporate = len(re.findall(
        r"\b(?:Co\.,? Ltd|Corporation|Incorporated|Limited|GmbH|S\.A\.|Pte|Sdn Bhd)\b",
        plain))
    return {"tableRows": rows, "corporateTokens": corporate,
            "looksLikeList": rows > 20 or corporate > 20}


def probe(symbol: str, zh: str, pages: list[str]) -> dict:
    entry: dict = {"symbol": symbol, "name": zh, "pages": [], "candidates": [],
                   "documents": []}
    origin = "{0}://{1}".format(*parse.urlsplit(pages[0])[:2])
    entry["robots"] = robots_rules(origin)
    time.sleep(GAP)

    for page in pages:
        stop = blocked(page, entry["robots"].get("disallow") or [])
        if stop:
            entry["pages"].append({"url": page, "skipped": f"robots Disallow {stop}"})
            continue
        try:
            body, meta = _fetch(page, accept="text/html,*/*")
        except Exception as exc:                   # noqa: BLE001
            entry["pages"].append({"url": page, "why": _why(exc)})
            time.sleep(GAP)
            continue
        text = body.decode("utf-8", "replace")
        entry["pages"].append({"url": page, **meta})
        entry["candidates"] += find_candidates(text, page)
        time.sleep(GAP)

    seen: set[str] = set()
    ranked = []
    for weight, url in sorted(entry["candidates"], key=lambda p: -p[0]):
        if url in seen:
            continue
        seen.add(url)
        ranked.append((weight, url))
    entry["candidates"] = ranked[:10]

    for weight, url in ranked[:3]:
        stop = blocked(url, entry["robots"].get("disallow") or [])
        if stop:
            entry["documents"].append({"url": url, "skipped": f"robots Disallow {stop}"})
            continue
        try:
            body, meta = _fetch(url)
        except Exception as exc:                   # noqa: BLE001
            entry["documents"].append({"url": url, "score": weight, "why": _why(exc)})
            time.sleep(GAP)
            continue
        doc = {"url": url, "score": weight, **meta}
        if body[:5] == b"%PDF-":
            doc["kind"] = "pdf"
            doc.update(pdf_text_sample(body))
        elif "html" in doc.get("contentType", ""):
            doc["kind"] = "html"
            doc.update(html_shape(body))
        else:
            doc["kind"] = doc.get("contentType") or "unknown"
        entry["documents"].append(doc)
        time.sleep(GAP)
    return entry


# 许可结论。**这不是探测出来的，是按 SUPPLY_CHAIN_SOURCES.md §4 的规矩定的**：
# 公司自行发布的文档属于 PRIV，PRIV 一律拦下。写死在这里是为了让报告每一次
# 都把这一问答出来——上一版只查 robots.txt，报告看着像通行证，
# 而许可这一问从头到尾没人答过（见 SOURCES.md §2.1）。
LICENSE_CLASS = "PRIV"
LICENSE_VERDICT = ("不许登记：公司自行发布的文档属 PRIV，"
                   "按 SUPPLY_CHAIN_SOURCES.md §4 一律拦下；"
                   "§2.1 逐条写了为什么它与 SEC 申报不能类推。"
                   "要接入的前置条件是拿到发布方书面许可。")


def main() -> None:
    print("── 公司自己发布的供应商名单：找得到吗、什么格式、解得开吗、许可准不准 ──\n")
    print(f"[!!] 许可结论（全部目标）：{LICENSE_CLASS} —— {LICENSE_VERDICT}")
    print("     下面的「取得到／解得开」只回答技术问题。"
          "**技术通过不等于许可通过**，这两件事这个探针分开报。\n")
    report: dict = {"companies": {}}
    for symbol, zh, pages in TARGETS:
        entry = probe(symbol, zh, pages)
        report["companies"][symbol] = entry
        robots = entry["robots"]
        entry["licenseClass"] = LICENSE_CLASS
        entry["licenseVerdict"] = LICENSE_VERDICT
        print(f"[!!] {symbol:<5} {zh:<6} 许可 {LICENSE_CLASS} · 不许登记"
              f"　｜　robots {'可读' if robots.get('ok') else robots.get('why')}"
              f"（Disallow {len(robots.get('disallow') or [])} 条）")
        for page in entry["pages"]:
            if page.get("skipped"):
                print(f"       落地页 [跳过] {page['skipped']}  {page['url'][:70]}")
            elif page.get("why"):
                print(f"       落地页 [XX] {page['why']}  {page['url'][:70]}")
            else:
                print(f"       落地页 [OK] {page['bytes'] // 1024}KB  {page['url'][:70]}")
        if entry["candidates"]:
            print(f"       候选 {len(entry['candidates'])} 个（按打分）：")
            for weight, url in entry["candidates"][:5]:
                print(f"         {weight:>3}  {url[:96]}")
        else:
            print("       候选：无")
        for doc in entry["documents"]:
            if doc.get("skipped") or doc.get("why"):
                print(f"       文档 [XX] {doc.get('skipped') or doc['why']}  {doc['url'][:60]}")
                continue
            head = (f"{doc['kind']:<6} {doc['bytes'] // 1024:>5}KB")
            if doc["kind"] == "pdf":
                print(f"       文档 [{'OK' if doc['extractable'] else '--'}] {head}  "
                      f"打分 {doc['score']}  流 {doc['streams']}"
                      f"（解开 {doc['inflatedStreams']}，含文字 {doc['textStreams']}）"
                      f"  压缩 {'/'.join(doc['filters']) or '未知'}")
                print(f"            → {doc['verdict']}")
                if doc.get("textSample"):
                    print(f"            文字样例：{doc['textSample'][:110]}")
            elif doc["kind"] == "html":
                print(f"       文档 [{'OK' if doc['looksLikeList'] else '--'}] {head}  "
                      f"打分 {doc['score']}  "
                      f"表格行 {doc['tableRows']}，公司后缀 {doc['corporateTokens']} → "
                      f"{'像名单' if doc['looksLikeList'] else '不像名单'}")
            else:
                print(f"       文档 [--] {head}  {doc['url'][:60]}")
        print()

    # **「PDF 里有文字」不等于「这是一份供应商名单」。**
    # 首轮我就是这么判的，结果把英伟达的《可持续发展报告》算成了名单——
    # 它只是一个恰好有文字的 PDF，打分只有 2（「是个 PDF」）。
    # 判据改成两条同时成立：地址本身指向名单（打分 ≥ LIST_SCORE），且内容取得到。
    usable = [s for s, v in report["companies"].items()
              if any(d.get("score", 0) >= LIST_SCORE
                     and (d.get("extractable") or d.get("looksLikeList"))
                     for d in v.get("documents") or [])]
    named_only = [s for s, v in report["companies"].items()
                  if s not in usable
                  and any(d.get("score", 0) >= LIST_SCORE for d in v.get("documents") or [])]
    print("── 结论 ────────────────────────────────────────────────────────────")
    print(f"{len(usable)}/{len(TARGETS)} 家：地址指向名单**且**内容取得到 —— "
          f"{', '.join(usable) or '无'}")
    if named_only:
        print(f"{len(named_only)} 家：地址指向名单但内容没取到 —— {', '.join(named_only)}")
    print(f"请求用掉 {MAX_REQUESTS - BUDGET.left}/{MAX_REQUESTS}")
    print("注意：打分只用于排序候选，**不是「这就是名单」的判据**——"
          "判据是把文档抓下来看内容，并由人逐条核对样例。"
          "上一轮就是靠猜地址失败的，这一轮的候选也要人看过才算数。")
    report["verdict"] = {"usable": usable, "namedButUnread": named_only,
                         "listScoreThreshold": LIST_SCORE,
                         "sampleSize": len(TARGETS),
                         "requestsSpent": MAX_REQUESTS - BUDGET.left}
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
