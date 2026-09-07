#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读探测：10-K 附件 21 的子公司清单，能不能把冶炼厂那一端接回公司池。

## 为什么探这条

第十九轮量出一条硬边界：全库 1,767 家冶炼厂里，**按名字能对上池内公司的只有
6 条、去重 2 家（MTRN、RIO）**。中国 588 家里 0 家、印尼 155 家里 0 家。
当时的结论是「冶炼厂本来就多是非上市的民营精炼厂」——那句话没错，但它可能
**只对了一半**：冶炼厂常常不是独立公司，而是某家上市公司的**子公司或分厂**。
江西铜业的冶炼厂不叫「江西铜业」，PT Timah 的几个厂各有各的名字。按母公司
名字去匹配，本来就匹配不上。

Exhibit 21 正是补这一层的：**美国 10-K 申报人依 Regulation S-K Item 601(b)(21)
必须随年报列出重要子公司**。那是一份公司自己申报的、带出处的「这些实体归我」
清单——不是推断，不是模型知识。

## 要回答四件事，一件都不能靠猜

1. **取得到吗**：抽样 N 家 10-K 申报人，EX-21 附件的可得率是多少。
2. **解得开吗**：格式分布（HTML 表格 / 纯文本清单 / 排版成图的）。规模多大。
3. **能不能对上冶炼厂**：把解出来的子公司名与本板块 1,767 家冶炼厂做同一套
   规范化名字匹配。**这一条才是这个探针存在的理由**——对不上就不建。
4. **许可**：EDGAR 是美国政府公开记录（GOV）。这一条没有悬念，但按 §4.3 的
   规矩仍要在报告里逐条标出来。

## 判据先写死，免得看到结果再挑标准

    命中 ≥50 家冶炼厂  → 值得建（冶炼厂那一端能显著接回池内）
    命中 10~49 家      → 边际，要看命中的是不是关键国别（中国／印尼／刚果金）
    命中 <10 家        → 判死，与「按公司名匹配」同一个结局，不再重复探

匹配一律用**严格规范化后的全名相等**，不做子串、不做模糊。宁可少认，
不能把「Jiangxi Copper Trading」认成某座冶炼厂——**认错一条就是编一条关系**。

只读。不写仓库任何数据文件，只把报告打到日志。
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
BODY_LIMIT = 8_000_000
MAX_REQUESTS = int(os.environ.get("EX21_MAX_REQUESTS", "400"))
SAMPLE = int(os.environ.get("EX21_SAMPLE", "60"))

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"

SMELTERS_PATH = "apps/supply-chain/smelters.json"
IDENTITY_PATH = "apps/supply-chain/identity.json"
DOMESTIC_PATH = "apps/supply-chain/domestic.json"

# 公司名规范化：去掉法律后缀与标点，折空白、转小写。与 build_chain_nodes 里
# smelter_reach() 用的是同一套规则——**两处口径必须一样**，否则这个探针报出的
# 命中数与真接进去之后的命中数对不上，等于白探。
_SUFFIX = re.compile(
    r"\b(co|corp|corporation|inc|incorporated|ltd|limited|llc|lp|plc|ag|nv|bv|sa|"
    r"se|spa|srl|gmbh|kk|kabushiki|kaisha|pte|pty|pt|sdn|bhd|oyj|ab|as|a\/s|"
    r"holdings?|group|company|industries|international|technologies|technology)\b",
    re.I)
_PUNCT = re.compile(r"[^0-9a-z一-鿿 ]+")


def norm(name) -> str:
    text = str(name or "").lower()
    text = _PUNCT.sub(" ", text)
    text = _SUFFIX.sub(" ", text)
    return " ".join(text.split())


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
                pass
        return raw


def why(exc: Exception) -> str:
    if isinstance(exc, error.HTTPError):
        return f"HTTP {exc.code}"
    if isinstance(exc, error.URLError):
        return f"网络失败 {exc.reason}"
    return f"{type(exc).__name__} {exc}"


_TAG = re.compile(r"<[^>]+>")
_WS = re.compile(r"[ \t\xa0]+")


def to_text(raw: bytes) -> str:
    text = raw.decode("utf-8", "replace")
    text = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", text)
    text = re.sub(r"(?i)</(tr|p|div|li|table)>", "\n", text)
    text = re.sub(r"(?i)</t[dh]>", "\t", text)
    text = _TAG.sub(" ", text)
    text = (text.replace("&nbsp;", " ").replace("&amp;", "&")
                .replace("&#160;", " ").replace("&quot;", '"'))
    return _WS.sub(" ", text)


# 明显不是实体名的行：表头、页码、法律套话
_SKIP = re.compile(
    r"(?i)^(exhibit|subsidiar|name|state|jurisdiction|place|of incorporation|"
    r"organization|percent|owned|page \d|list of|the following|registrant|"
    r"\d+$|[-–—\s]*$)")


def parse_entities(text: str) -> list[str]:
    """从附件正文里抠实体名。**只收看着像公司名的行，宁缺毋滥。**

    附件 21 没有统一格式：有的是三列表格（名称｜注册地｜持股比例），有的是
    纯文本清单。共同点是每行以实体名开头。这里按行切，取第一格（制表位之前），
    丢掉表头、页码、纯数字与太长／太短的行。

    这一步只为**估规模与试匹配**，不作为发布路径——真要接入得重写得更严。
    """
    out: list[str] = []
    for line in text.split("\n"):
        cell = line.split("\t")[0].strip(" .·|")
        if not cell or len(cell) < 4 or len(cell) > 120:
            continue
        if _SKIP.match(cell):
            continue
        if not re.search(r"[A-Za-z]{3}", cell):
            continue
        # 整行都是大写的法律声明之类，通常不是实体名
        if cell.count(" ") > 14:
            continue
        out.append(cell)
    return out


def load_pool() -> list[tuple[str, int]]:
    """取本土 10-K 申报人。EX-21 是 10-K 的附件，只有这一池有。"""
    targets: list[tuple[str, int]] = []
    for path in (IDENTITY_PATH, DOMESTIC_PATH):
        try:
            with open(path, encoding="utf-8") as handle:
                rows = (json.load(handle) or {}).get("companies") or {}
        except (OSError, ValueError):
            continue
        for symbol, row in rows.items():
            if row.get("cik"):
                targets.append((symbol, int(row["cik"])))
    seen: set[str] = set()
    unique = []
    for symbol, cik in sorted(targets):
        if symbol in seen:
            continue
        seen.add(symbol)
        unique.append((symbol, cik))
    return unique


def load_smelters() -> dict[str, dict]:
    try:
        with open(SMELTERS_PATH, encoding="utf-8") as handle:
            return (json.load(handle) or {}).get("smelters") or {}
    except (OSError, ValueError):
        return {}


def find_ex21(cik: int) -> tuple[str | None, str]:
    """在最近的 10-K 里找 EX-21 附件。返回（URL, 说明）。"""
    url = f"https://data.sec.gov/submissions/CIK{cik:010d}.json"
    meta = json.loads(fetch(url).decode("utf-8", "replace"))
    recent = (meta.get("filings") or {}).get("recent") or {}
    forms = recent.get("form") or []
    accessions = recent.get("accessionNumber") or []
    for form, accession in zip(forms, accessions):
        if form not in ("10-K", "10-K/A"):
            continue
        acc = accession.replace("-", "")
        index = (f"https://www.sec.gov/Archives/edgar/data/{cik}/{acc}/"
                 f"{accession}-index.htm")
        try:
            page = to_text(fetch(index))
        except Exception as exc:                   # noqa: BLE001
            return None, f"取申报索引失败：{why(exc)}"
        # 索引页把附件类型与文件名列在一起。找 EX-21 那一行的文件名。
        hit = re.search(r"([A-Za-z0-9_\-.]+\.(?:htm|html|txt))[^\n]{0,120}?EX-21",
                        page, re.I)
        if not hit:
            hit = re.search(r"EX-21[^\n]{0,160}?([A-Za-z0-9_\-.]+\.(?:htm|html|txt))",
                            page, re.I)
        if not hit:
            return None, "该 10-K 的索引里没有 EX-21"
        return (f"https://www.sec.gov/Archives/edgar/data/{cik}/{acc}/"
                f"{hit.group(1)}"), "ok"
    return None, "近期没有 10-K"


def main() -> int:
    print("═" * 74)
    print("探针：10-K 附件 21 子公司清单 —— 能不能把冶炼厂接回公司池")
    print("═" * 74)
    print("许可：SEC EDGAR = 美国政府公开记录（GOV）。按 §4.3，GOV 可用。\n")

    smelters = load_smelters()
    if not smelters:
        print("[XX] 读不到冶炼厂登记表，无从做匹配这一步")
        return 1
    by_norm: dict[str, list[str]] = {}
    for entry in smelters.values():
        key = norm(entry.get("name"))
        if key:
            by_norm.setdefault(key, []).append(entry.get("name"))
    print(f"冶炼厂登记表 {len(smelters)} 条，规范化后 {len(by_norm)} 个不同名字\n")

    pool = load_pool()
    if not pool:
        print("[XX] 读不到公司池")
        return 1
    # 均匀抽样，不挑大公司——挑了就只会证明大公司有附件 21。
    step = max(1, len(pool) // SAMPLE)
    sample = pool[::step][:SAMPLE]
    print(f"公司池 {len(pool)} 家，均匀抽 {len(sample)} 家探测\n")

    got = fail = 0
    total_entities = 0
    fmt: dict[str, int] = {}
    hits: list[tuple[str, str, str]] = []
    reasons: dict[str, int] = {}

    for i, (symbol, cik) in enumerate(sample, 1):
        try:
            url, note = find_ex21(cik)
        except Exception as exc:                   # noqa: BLE001
            fail += 1
            reasons[why(exc)] = reasons.get(why(exc), 0) + 1
            print(f"[XX] {symbol:6} {why(exc)}")
            continue
        if not url:
            reasons[note] = reasons.get(note, 0) + 1
            print(f"[--] {symbol:6} {note}")
            continue
        try:
            raw = fetch(url)
        except Exception as exc:                   # noqa: BLE001
            fail += 1
            print(f"[XX] {symbol:6} 取附件失败 {why(exc)}")
            continue
        got += 1
        kind = "txt" if url.endswith(".txt") else "html"
        fmt[kind] = fmt.get(kind, 0) + 1
        names = parse_entities(to_text(raw))
        total_entities += len(names)
        matched = []
        for name in names:
            key = norm(name)
            if key and key in by_norm:
                matched.append((name, by_norm[key][0]))
        for name, smelter in matched:
            hits.append((symbol, name, smelter))
        flag = f"  ← 命中冶炼厂 {len(matched)} 条" if matched else ""
        print(f"[OK] {symbol:6} 子公司约 {len(names):4} 条{flag}")

    print("\n" + "─" * 74)
    print(f"抽样 {len(sample)} 家：取到附件 21 的 {got} 家"
          f"（{got / len(sample) * 100:.0f}%）· 取数失败 {fail} 家")
    if reasons:
        print("  取不到的原因：" + " · ".join(
            f"{k}×{v}" for k, v in sorted(reasons.items(), key=lambda kv: -kv[1])))
    print(f"格式分布：{fmt or '—'}")
    if got:
        print(f"平均每家解出实体 {total_entities / got:.0f} 条"
              f"（合计 {total_entities} 条，含误收，仅用于估规模）")

    print("\n" + "─" * 74)
    print(f"**关键读数**：解出的子公司里，与冶炼厂登记表严格同名的 {len(hits)} 条")
    seen_smelters = {h[2] for h in hits}
    print(f"去重命中冶炼厂 {len(seen_smelters)} 家 / 全库 {len(smelters)} 家")
    for symbol, name, smelter in hits[:25]:
        print(f"    {symbol:6} 「{name}」→ 冶炼厂「{smelter}」")

    print("\n" + "─" * 74)
    scaled = len(seen_smelters) * (len(pool) / max(1, len(sample)))
    print(f"按抽样比例外推全池约 {scaled:.0f} 家（**只是量级参考，不是结论**："
          f"子公司多的大公司与壳公司分布不均，真要建必须全量跑）")
    if len(seen_smelters) * (len(pool) / max(1, len(sample))) >= 50:
        print("判据：命中量级达到「值得建」——下一步全量跑并接入发布路径")
    elif seen_smelters:
        print("判据：命中量级在「边际」区间——要看命中的是不是关键国别，"
              "把命中的冶炼厂国别列出来再决定")
        countries: dict[str, int] = {}
        for entry in smelters.values():
            if entry.get("name") in seen_smelters:
                c = entry.get("country") or "未写明"
                countries[c] = countries.get(c, 0) + 1
        print("  命中冶炼厂的国别：" + (" · ".join(
            f"{k} {v}" for k, v in sorted(countries.items(), key=lambda kv: -kv[1]))
            or "—"))
    else:
        print("判据：命中 0 家——与「按公司名匹配」同一个结局，判死，不再重复探")
    print(f"\n请求预算：用掉 {MAX_REQUESTS - BUDGET.left} / {MAX_REQUESTS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
