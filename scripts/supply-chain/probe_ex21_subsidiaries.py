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


# 金属矿业相关的 SIC 大类：10 金属矿开采 · 12 煤 · 14 非金属矿 ·
# 33 一次金属冶炼与加工 · 34 金属制品。池内共 293 家（NEM、FCX、NUE、STLD…）。
METAL_SIC_MAJORS = frozenset({10, 12, 14, 33, 34})
FRAME = os.environ.get("EX21_FRAME", "metal")


def load_pool() -> list[tuple[str, int]]:
    """取本土 10-K 申报人。EX-21 是 10-K 的附件，只有这一池有。

    **抽样框默认收窄到金属矿业（EX21_FRAME=metal）。** 上一轮在全池 4,705 家
    上均匀抽样，抽到的是耐克、MGNI、TRMK 这类消费／科技／金融公司——
    而这个探针要验的假设是「冶炼厂是某家上市公司的子公司」，那只可能在
    **金属矿业公司**身上成立。16 家解出 566 个实体、0 命中，说明不了任何事：
    **对照组选错了，阴性结果就没有信息量。**

    这不是挑样本凑结论——判据在文件头写死了，而且收窄的是「可能为真的范围」，
    不是「我希望为真的范围」。要看全池分布就传 EX21_FRAME=all。
    """
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
    sic_of: dict[str, int] = {}
    try:
        with open("apps/supply-chain/nodes.json", encoding="utf-8") as handle:
            for node in (json.load(handle).get("nodes") or []):
                if node.get("sic"):
                    sic_of[node["symbol"]] = int(node["sic"])
    except (OSError, ValueError):
        pass
    seen: set[str] = set()
    unique = []
    for symbol, cik in sorted(targets):
        if symbol in seen:
            continue
        if FRAME == "metal":
            sic = sic_of.get(symbol)
            if sic is None or sic // 100 not in METAL_SIC_MAJORS:
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
    """在最近的 10-K 里找 EX-21 附件。返回（URL, 说明）。

    **第一版在 60 家上全报「索引里没有 EX-21」，那是解析坏了，不是申报里没有**
    ——样本里有伊利诺伊工具和马丁玛丽埃塔这种大型工业企业，它们依
    Regulation S-K Item 601(b)(21) 必附子公司清单。而探针当时照旧打印
    「命中 0 家 → 判死」，**把取数失败冒充成了业务事实**，正是本板块反复
    禁止的那件事。

    改成两条路，按可靠性排序，并且取不到时把**实际看到的文件名打出来**——
    不然下一次失败照样无从诊断：

      一、申报目录 index.json 的文件名（最稳，不依赖索引页的排版）；
      二、索引页正文里「文件名 ↔ 附件类型」那一行（兜底，放宽到同一行内）。
    """
    url = f"https://data.sec.gov/submissions/CIK{cik:010d}.json"
    meta = json.loads(fetch(url).decode("utf-8", "replace"))
    recent = (meta.get("filings") or {}).get("recent") or {}
    forms = recent.get("form") or []
    accessions = recent.get("accessionNumber") or []
    for form, accession in zip(forms, accessions):
        if form not in ("10-K", "10-K/A"):
            continue
        acc = accession.replace("-", "")
        base = f"https://www.sec.gov/Archives/edgar/data/{cik}/{acc}"
        # 路一：目录清单里的文件名。EX-21 的命名高度套路化
        # （ex21.htm / ex-21_1.htm / exhibit21.htm / a10-kex21.htm …）。
        names: list[str] = []
        try:
            listing = json.loads(fetch(f"{base}/index.json")
                                 .decode("utf-8", "replace"))
            names = [item.get("name") or "" for item in
                     ((listing.get("directory") or {}).get("item") or [])]
        except Exception:                          # noqa: BLE001
            names = []
        # **上一版的守卫正好挡掉了最常见的真实形态。** 它要求 "ex21" 后面跟
        # 非数字，而附件 21 的文件名几乎都带子编号或年份：
        #
        #     msiex212025.htm · bowl-ex211x062826subsidiar.htm
        #     fy202510-kex211.htm · aphoenity_ex2100.htm · a10-k2025exx21.htm
        #
        # 放开数字，并允许 "exx21"（有些申报人双写 ex）。
        #
        # 代价是 `ex21.htm` 在命名上**分不清附件 21（子公司清单）与附件 2.1
        # （收购协议）**——S-K 两者都可能落到同一个文件名。所以文件名只当
        # **候选**，命中后还要看正文像不像一份实体清单；真正权威的类型在
        # 索引页的 Type 列，那是路二。
        pat = re.compile(r"ex+[\-_]?21|exhibit[\-_ ]?21", re.I)
        cands = [n for n in names
                 if n.lower().endswith((".htm", ".html", ".txt")) and pat.search(n)]
        for name in cands:
            try:
                body = to_text(fetch(f"{base}/{name}"))
            except Exception:                      # noqa: BLE001
                continue
            # 子公司清单的特征：要么自称 subsidiaries，要么密集列注册地。
            # 收购协议（附件 2.1）不会有这两样。
            if re.search(r"(?i)subsidiar", body) or len(parse_entities(body)) >= 5:
                return f"{base}/{name}", "ok（按目录文件名 + 正文核对）"

        # 路二：索引页那张表。文件名与附件类型在同一行，中间隔着制表位。
        try:
            page = to_text(fetch(f"{base}/{accession}-index.htm"))
        except Exception as exc:                   # noqa: BLE001
            return None, f"取申报索引失败：{why(exc)}"
        # **类型与文件名不一定在同一行。** 有些申报代理的索引页排版会让
        # to_text 把它们切开，上一轮的诊断就印出了只有 »EX-21.1« 的行——
        # 那说明索引页确实有这个附件，只是文件名落在相邻行。这类公司的文件名
        # 恰恰是 ex_868885.htm 这种流水号，路一的命名规则一个都认不出来，
        # 所以这条跨行配对不是锦上添花，是这 29 家里大部分的唯一出路。
        lines = page.split("\n")
        ex2_lines = [" ".join(x.split())[:90] for x in lines
                     if re.search(r"\bEX-2", x, re.I)]
        doc_re = re.compile(r"([A-Za-z0-9_\-.]+\.(?:htm|html|txt))", re.I)
        for i, line in enumerate(lines):
            if not re.search(r"\bEX-21(\.|\b)", line, re.I):
                continue
            # 先看本行，再看前后各两行——表格一行被切开时文件名就在邻近。
            for j in (i, i - 1, i + 1, i - 2, i + 2):
                if not 0 <= j < len(lines):
                    continue
                doc = doc_re.search(lines[j])
                if doc and not doc.group(1).lower().endswith(".txt"):
                    return (f"{base}/{doc.group(1)}",
                            f"ok（按索引页{'' if j == i else '·邻行'}）")

        # **取不到就把看到的东西打出来。** 只说「没有」等于把诊断线索丢掉。
        # **两条路都失败时，把两边看到的东西都打出来。** 上一轮只打了文件名，
        # 于是路二为什么也没命中，只能靠猜。
        sample = [n for n in names if n.lower().endswith((".htm", ".txt"))][:6]
        detail = "文件名：»" + "、".join(sample) + "«" if sample else "目录清单取不到"
        if cands:
            detail += f"；候选 {cands} 但正文不像实体清单"
        if ex2_lines:
            detail += "；索引页含 EX-2 的行：»" + " / ".join(ex2_lines[:3]) + "«"
        return None, "找不到 EX-21（" + detail + "）"
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
    print(f"抽样框：{FRAME}（metal = 仅金属矿业 SIC {10,12,14,33,34}xx）\n"
          f"框内 {len(pool)} 家，均匀抽 {len(sample)} 家探测\n")

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
    # **取到 0 份附件就没有判决权。** 命中 0 条在这种情况下说明的是探针取不到
    # 数据，不是「子公司里没有冶炼厂」。把前者写成后者，就是拿抓取失败冒充
    # 业务事实——第八轮那 77 家误判就是这么来的。
    if not got:
        print("[XX] **结论无效**：一份附件 21 都没取到，本探针没有测到它要测的东西。")
        print("     先修取附件那一步，再重探。**不得据此判死。**")
        print(f"\n请求预算：用掉 {MAX_REQUESTS - BUDGET.left} / {MAX_REQUESTS}")
        return 2
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
