#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""补名单工程 · 阶段 2 探针：EX-10 材料合同能不能给出一级供应关系。

## 要回答的问题

一级供应商那一格现在是 **0 家**，因为没有免费源点名「谁向谁供货」。两条路
已判死（客户集中度披露不要求写客户名；EDGAR 全文反查按词频排序时提到某公司
最多的是起诉它的人）。**EX-10 是唯一还没探过的免费路。**

Regulation S-K Item 601(b)(10) 要求上市公司把**重大合同**作为附件提交给 SEC。
供货协议、制造协议、长期采购协议都在这一类里，而合同首段（preamble）按惯例
写明双方全称：

    This Supply Agreement is entered into as of ... by and between
    ACME CORPORATION, a Delaware corporation, and WIDGET INDUSTRIES, INC.

与已判死的全文反查有本质区别：**按附件类型结构化定位，不靠词频**；出处是
一份可点开的完整合同，不是一段正文。

## 判据（**探之前写死，不许探完再定**）

    抽样      全池按环节分层取 100 家
    范围      每家最近 12 份 10-K／10-Q／8-K 里的 EX-10.x 附件，最多读 6 份
              （第一版只看最近一份 10-K，实测 80 家里 48 家的 10-K 目录**只有
               审计师同意书与认证**——材料合同以「引用并入」指向更早的 8-K，
               范围选错了，阴性结果没有信息量）
    命中      附件标题命中供货类关键词 **且** 从首段解出交易对方
    判据      能稳定解出交易对方的 ≥15 份 → 值得建
              <15 份                     → 判「收益不足」，写进判决表

15 这条线的依据：一级供应商现在是 0 条，从零起步要建整条新管线（新 relation
类型、新边文件格式、页面新分区、公司页新区块），是两到三轮的工作量。
100 家里不到 15 份可用，外推到 5,897 家不足 900 条关系、且分布极散，
撑不起一个新分区——不如把那几轮花在别处。

## 取到 0 份 = 结论无效，不是判死

一家的 10-K 都没取到、或一份 EX-10 附件都没找到时，**报「结论无效」并非零
退出，不输出判据**。附件 21 探针第一轮 60/60 报「没有」，实际是我的文件名
正则挡掉了全部真实形态——那次的教训是这个探针家族的第一条禁令。

所以这里**逐层报数**，让失败发生在哪一层一眼可见：

    取到 10-K          → 取不到就是取数问题
    找到 EX-10 附件     → 找不到就是文件名规则问题
    标题像供货合同      → 命中少就是这类合同本来就少
    解出交易对方        → 解不出就是首段格式比我想的杂

## 附件 21 那轮的三个坑，这里提前避开

一、**文件名正则不能要求 "ex10" 后面跟非数字**。真实形态是 ex101、ex10_1、
    ex1001、d123456dex101 —— 附件编号紧跟其后，那条守卫会挡掉最常见的形态。
二、**索引页的类型与文件名不一定在同一行**，所以主路走申报目录的 index.json，
    不去刮索引页排版。
三、**只读附件开头**。合同正文可以有几百页，而交易对方写在首段——
    每份只取前 300KB，既快又够。

## 只读

不写任何数据文件、不建任何边、不改任何清单。
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from urllib import error, request

TIMEOUT = 30
GAP = 0.20
# 合同正文可以几百页，但交易对方写在首段——只取开头。
BODY_LIMIT = 300_000
SAMPLE = int(os.environ.get("EX10_SAMPLE", "100"))
MAX_EXHIBITS = int(os.environ.get("EX10_MAX_EXHIBITS", "6"))
# 每家回看几份申报。**只看最近一份 10-K 是错的**：实测 80 家里 48 家的 10-K
# 目录里只有 ex23（审计师同意书）、ex31/ex32（认证）和 10-K 正文本身——
# 材料合同按惯例以「引用并入」指向更早的 8-K／10-Q，不在最新这份里。
MAX_FILINGS = int(os.environ.get("EX10_MAX_FILINGS", "12"))
WANT_FORMS = ("10-K", "10-Q", "8-K")
MAX_REQUESTS = int(os.environ.get("EX10_MAX_REQUESTS", "6000"))
# 判据。改这个数等于改判据，必须连同上面的理由一起改。
HIT_FLOOR = int(os.environ.get("EX10_HIT_FLOOR", "15"))

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"
NODES_PATH = "apps/supply-chain/nodes.json"

# 文件名里的附件 10。**不加「后面跟非数字」那条守卫**——真实形态是
# ex101 / ex10_1 / ex1001 / d123456dex101，编号紧跟其后（附件 21 那轮的教训）。
EX10_NAME = re.compile(r"ex+[\-_]?10|exhibit[\-_ ]?10", re.I)

# 供货类合同的标题关键词。**不收雇佣、股权、租赁、信贷那几类**——
# 它们占 EX-10 的大多数，但与供应链无关。
SUPPLY_TITLE = re.compile(
    r"\b(supply|manufactur\w*|purchas\w*|procurement|distribution|"
    r"tolling|offtake|off-take|toll\s+processing|foundry|"
    r"contract\s+manufactur\w*|master\s+(?:supply|purchase|services))\b"
    r"[^.]{0,60}\bagreement\b", re.I)
# **排除项优先，而且要匹配整个协议名。**
#
# 第一版写成一堆单词，与供货项同时命中时 `and not` 让排除失效——离线一验，
# 「SECURITIES PURCHASE AGREEMENT」「ASSET PURCHASE AGREEMENT」都被判成了供货类。
# 那是融资与并购文件，一条供应关系都没有；收进来会让判据虚高，方向是假阳性。
#
# 所以改成匹配完整的协议名：「<金融名词> purchase agreement」整体排除，
# 而不是看到 purchase 就纠结。
NOT_SUPPLY = re.compile(
    r"\b(?:"
    r"(?:securities|asset|share|stock|membership\s+interest|equity|unit)\s+"
    r"purchase\s+agreement"
    r"|(?:employment|severance|indemnification|credit|loan|lease|merger|"
    r"consulting|underwriting|retention|separation|transition\s+services|"
    r"registration\s+rights|stockholders?|shareholders?)\s+agreement"
    r"|(?:equity|incentive|option|restricted\s+stock|compensation)\s+plan"
    # 实测（run 42）补两条。CAHO 那份「PURCHASE AND ACQUISITION AGREEMENT」
    # 被上面的 purchas\w* 收进来了，而它是一份**并购**文件——全样本唯一那
    # 「1 份命中」就是它，真实可用数是 0。RAPH 的认购协议同理。
    # 两条都只收实测见过的形态，不替没见过的形态提前立规则。
    r"|acquisition\s+agreement"
    r"|subscription\s+agreement"
    r")\b", re.I)

# 首段的双方。合同惯例是 "by and between A ... and B"。
PARTIES = re.compile(
    r"by\s+and\s+between\s+(.{3,120}?)\s+and\s+(.{3,120}?)(?:[.,;]|\s+\()",
    re.I | re.S)

# 首段里常见的套话，一个公司名都没有——解出这些等于没解出。
BOILERPLATE = re.compile(
    r"\b(the\s+persons?|entities\s+listed|schedule\s+[IVX0-9]|"
    r"purchasers?|investors?|holders?|parties\s+hereto|signator|"
    r"each\s+of\s+the|undersigned|lenders?|guarantors?)\b", re.I)
# 公司主体后缀。有它基本可以确定是一家实体，没有就再看有没有两个大写词。
SUFFIX = re.compile(
    r"\b(inc|corp|corporation|company|co|llc|l\.?l\.?c|ltd|limited|plc|"
    r"gmbh|s\.?a|n\.?v|a\.?g|kg|oy|ab|as|bv|pte|sdn|bhd|kk|"
    r"holdings?|group|industries|technologies|laborator)\b\.?", re.I)

TAG = re.compile(r"<[^>]+>")
WS = re.compile(r"\s+")


class Budget:
    def __init__(self, total: int = MAX_REQUESTS) -> None:
        self.left = total

    def spend(self) -> bool:
        if self.left <= 0:
            return False
        self.left -= 1
        return True


BUDGET = Budget()


def fetch(url: str) -> bytes:
    if not BUDGET.spend():
        raise RuntimeError("已达全局请求上限，未发起")
    req = request.Request(url, headers={
        "User-Agent": UA, "Accept": "*/*", "Accept-Encoding": "gzip, deflate"})
    time.sleep(GAP)
    with request.urlopen(req, timeout=TIMEOUT) as response:
        raw = response.read(BODY_LIMIT)
        if response.headers.get("Content-Encoding") == "gzip":
            import gzip
            try:
                raw = gzip.decompress(raw)
            except Exception:                      # noqa: BLE001
                pass                               # 截断的 gzip 解不开，用原文
        return raw


def why(exc: Exception) -> str:
    if isinstance(exc, error.HTTPError):
        return f"HTTP {exc.code}"
    if isinstance(exc, error.URLError):
        return f"网络失败 {exc.reason}"
    return f"{type(exc).__name__} {exc}"


def text_of(raw: bytes) -> str:
    body = raw.decode("utf-8", "replace")
    body = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", body)
    body = TAG.sub(" ", body)
    for a, b in (("&nbsp;", " "), ("&amp;", "&"), ("&#8217;", "'"),
                 ("&quot;", '"'), ("&#160;", " "), ("&ldquo;", '"'),
                 ("&rdquo;", '"'), ("&rsquo;", "'")):
        body = body.replace(a, b)
    return WS.sub(" ", body).strip()


def recent_filings(cik: int, limit: int) -> list[dict]:
    """近若干份 10-K／10-Q／8-K。**不能只看最近一份 10-K**，见 MAX_FILINGS 的注释。"""
    url = f"https://data.sec.gov/submissions/CIK{cik:010d}.json"
    meta = json.loads(fetch(url).decode("utf-8", "replace"))
    recent = (meta.get("filings") or {}).get("recent") or {}
    rows = []
    for form, accession, date in zip(
            recent.get("form") or [], recent.get("accessionNumber") or [],
            recent.get("filingDate") or []):
        if form not in WANT_FORMS:
            continue
        rows.append({"form": form, "accession": accession, "date": date})
        if len(rows) >= limit:
            break
    return rows


def ex10_urls(cik: int, accession: str) -> tuple[list[str], list[str]]:
    """（EX-10 候选 URL, 该目录下全部文件名）。

    第二个返回值是**诊断用**：找不到候选时要能看出到底有哪些文件，
    而不是只报一句「没有」——附件 21 探针第一轮就是因为只报「没有」，
    我翻了半天日志才发现是正则挡掉了真实形态。
    """
    acc = accession.replace("-", "")
    base = f"https://www.sec.gov/Archives/edgar/data/{cik}/{acc}"
    try:
        listing = json.loads(fetch(f"{base}/index.json").decode("utf-8", "replace"))
    except Exception:                              # noqa: BLE001
        return [], []
    names = [str(item.get("name") or "")
             for item in ((listing.get("directory") or {}).get("item") or [])]
    picks = []
    for name in names:
        low = name.lower()
        if not low.endswith((".htm", ".html")):
            continue
        if low.startswith("0") or "index" in low:
            continue
        if EX10_NAME.search(low):
            picks.append(f"{base}/{name}")
    return picks[:MAX_EXHIBITS], names


def classify(body: str) -> tuple[str, str | None]:
    """（判定, 标题片段）。判定 ∈ supply / other / unknown。"""
    head = body[:4000]
    # **排除优先**：标题区里出现完整的「证券购买协议」「雇佣协议」这类名字，
    # 就直接判 other，不再看供货关键词——否则 purchase 这个词会让两边同时命中，
    # 而 `and not` 会让排除失效（离线复验时抓到的）。
    if NOT_SUPPLY.search(head[:400]):
        return "other", head[:90]
    hit = SUPPLY_TITLE.search(head)
    if hit:
        return "supply", hit.group(0)[:90]
    return "other" if head else "unknown", head[:90] or None


def counterparty(body: str, issuer: str) -> str | None:
    """从首段解出交易对方。解不出返回 None——**解不出就是解不出，不猜**。"""
    hit = PARTIES.search(body[:6000])
    if not hit:
        return None
    left, right = (WS.sub(" ", g).strip(" ,;") for g in hit.groups())
    issuer_key = re.sub(r"[^a-z]", "", (issuer or "").lower())[:10]

    def is_issuer(name: str) -> bool:
        key = re.sub(r"[^a-z]", "", name.lower())
        return bool(issuer_key) and issuer_key in key
    # **套话不是公司名。** 实测 TARA 解出的「对方」是
    # "the persons and entities listed on Schedule I attached hereto"——
    # 那是证券购买协议里的认购人清单。收进来就是把融资文件当成供应关系，
    # 方向是假阳性，而且是最难看的那种：判据虚高全靠它。
    for name in (right, left):
        if is_issuer(name) or not (3 < len(name) < 120):
            continue
        if BOILERPLATE.search(name):
            continue
        # 真公司名总带一个主体后缀或至少两个大写词
        if not SUFFIX.search(name) and len(re.findall(r"\b[A-Z][\w&.]+", name)) < 2:
            continue
        return name
    return None


def main() -> int:
    with open(NODES_PATH, encoding="utf-8") as handle:
        payload = json.load(handle)
    stages = {s["id"]: s["label"] for s in (payload.get("stages") or [])}
    pool = [n for n in (payload.get("nodes") or []) if n.get("cik")]
    pool.sort(key=lambda n: n.get("symbol") or "")
    if not pool:
        print("[XX] 节点表为空")
        return 1

    # 按环节分层，与阶段 1 同一条理由：按代码排序取步长会让某些环节占比腰斩，
    # 而供货合同在制造类环节最可能出现，偏差方向是假阴性。
    by_stage: dict[str, list] = {}
    for node in pool:
        by_stage.setdefault(node.get("stage") or "未判定", []).append(node)
    sample = []
    for _, members in sorted(by_stage.items(), key=lambda kv: -len(kv[1])):
        want = max(1, round(len(members) / len(pool) * SAMPLE))
        step = max(1, len(members) // want)
        sample.extend(members[::step][:want])
    sample = sample[:SAMPLE]

    print(f"全池 {len(pool)} 家 · 按环节分层取样 {len(sample)} 家")
    print(f"判据（探之前已写死）：能解出交易对方的 ≥{HIT_FLOOR} 份 → 值得建")
    print("逐层报数：取到 10-K → 找到 EX-10 → 标题像供货合同 → 解出交易对方\n")

    got10k = withex = supply = named = failed = 0
    hits: list[tuple] = []
    no_ex_samples: list[str] = []
    supply_no_party: list[str] = []
    for i, node in enumerate(sample, 1):
        symbol = node.get("symbol")
        name = node.get("nameEn") or node.get("name") or symbol
        try:
            filings = recent_filings(int(node["cik"]), MAX_FILINGS)
        except Exception as exc:                   # noqa: BLE001
            failed += 1
            if failed <= 5:
                print(f"[--] {symbol:6} 取申报清单失败：{why(exc)}")
            continue
        if not filings:
            continue
        got10k += 1
        found_ex = False
        done = False
        for filing in filings:
            if done:
                break
            urls, all_names = ex10_urls(int(node["cik"]), filing["accession"])
            if not urls:
                if len(no_ex_samples) < 6 and all_names and not found_ex:
                    no_ex_samples.append(
                        f"{symbol} {filing['form']}：{'、'.join(all_names[:5])}")
                continue
            if not found_ex:
                found_ex = True
                withex += 1
            for url in urls:
                try:
                    body = text_of(fetch(url))
                except Exception:                  # noqa: BLE001
                    continue
                kind, title = classify(body)
                if kind != "supply":
                    continue
                supply += 1
                other = counterparty(body, name)
                if other:
                    named += 1
                    hits.append((symbol, other, title, url.rsplit("/", 1)[-1]))
                    print(f"[OK] {symbol:6} → {other[:46]:48} | {(title or '')[:40]}")
                elif len(supply_no_party) < 10:
                    supply_no_party.append(f"{symbol}：{(title or '')[:60]}")
                done = True                        # 一家一份就够回答判据
                break
        if i % 20 == 0:
            print(f"     … 已处理 {i}/{len(sample)}，解出 {named} 份，"
                  f"请求用掉 {MAX_REQUESTS - BUDGET.left}")

    print("\n" + "─" * 74)
    if not got10k:
        print("[XX] **结论无效**：一家的申报清单都没取到。这是取数失败，不是业务事实——")
        print("     先修取数再重探，不得据此判死。")
        return 2
    if not withex:
        print("[XX] **结论无效**：取到了申报清单，但一份 EX-10 附件都没找到。")
        print("     多半是文件名规则的问题（附件 21 那轮就是），实际文件名样例：")
        for line in no_ex_samples:
            print(f"       {line}")
        return 2

    print(f"取到申报清单 {got10k} 家 · 失败 {failed} 家 · 请求 {MAX_REQUESTS - BUDGET.left}")
    print(f"  近 {MAX_FILINGS} 份 10-K/10-Q/8-K 里找到 EX-10 附件的 {withex} 家（{withex / max(1, got10k) * 100:.0f}%）")
    print(f"  附件标题像供货类合同的 {supply} 份")
    print(f"  **从首段解出交易对方的 {named} 份**")
    if no_ex_samples:
        print("\n没找到 EX-10 的那些，实际文件名样例（判断是不是规则问题）：")
        for line in no_ex_samples:
            print(f"   {line}")
    if supply_no_party:
        print("\n标题像供货合同、但首段解不出双方的（判断是不是解析问题）：")
        for line in supply_no_party:
            print(f"   {line}")
    if hits:
        print(f"\n解出的 {len(hits)} 对，全部列出（**人工核对用，别只看计数**）：")
        for sym, other, title, doc in hits:
            print(f"   {sym:6} → {other[:50]:52} | {doc[:30]}")

    print("\n" + "─" * 74)
    if named >= HIT_FLOOR:
        print(f"判据：解出 {named} 份 ≥ {HIT_FLOOR} → **值得建**")
        print("注意：判据只说「解得出对方」，**没说那些名字都是真供应商**——")
        print("      接入前必须逐条人工核对，并确认对方是不是池内公司。")
    else:
        print(f"判据：解出 {named} 份 < {HIT_FLOOR} → **收益不足，不建**，写进判决表")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
