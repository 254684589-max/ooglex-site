#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""历年 Form SD 的名单变动：新增了哪些冶炼厂、砍掉了哪些。

## 为什么建这一份

进度表上时间维度一直是 0%，而它是几块空缺里唯一不需要新数据源、不涉及任何
许可的：Form SD 一年一报，EDGAR 历年都留着，抽取器只是每次取最新的、
把旧的丢了。

**存量名单只说明现状，变动才说明方向。** 华尔街看供应链先看的是变动：
今年新进了哪座厂、砍掉了哪座、受涵盖国家的暴露在扩大还是收缩。

## 判据已实测（探针 run 36）

    14 家样本 · 37 组相邻年度对比
    按全部条目：  中位 33.3% · 最大 436.4%   ← 不可用
    只看带编号的：中位 17.4% · 最大  64.3%   ← 可信

17.4% 远高于「≥5% 才值得建」的门槛，所以建。

## 跨年身份只认 RMI 编号，这是本脚本最要紧的一条

登记表里只有三成条目带 RMI CID，七成只有名字。**按名字做跨年比对，一个
拼写差异就同时造出一条假新增和一条假消失**——探针第一版就是这么得出
「SLGN 31 家厂的名单相邻年换掉 50 家」「MO 变动率 1273%」的。那不是换厂，
是同一座厂换了写法。

所以：

    只比带 CID 的条目 —— CID 是设施的全球唯一编号，跨年可比
    只有名字的条目不进变动统计，但**要把它占多少如实报出来**

不报那个比例，读者会把「变动 17%」当成整份名单的换厂率，而它只覆盖三成条目。

## 不联网时怎么办

本脚本要回溯历年申报，必须联网（Actions 里跑）。取不到就**原样保留已有的
history.json，不写空文件**——与抽取器同一条规矩：不得用空数据覆盖有效数据。
"""
from __future__ import annotations

import json
import os
import sys
import time
from urllib import error, request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

TIMEOUT = 30
GAP = 0.20
BODY_LIMIT = 12_000_000
YEARS = int(os.environ.get("HISTORY_YEARS", "4"))
# 每份申报现在要把候选附件都解一遍（见 parse_one），请求数比「取第一个」
# 多几倍。预算按 369 家 × 4 份 × (1 索引 + 最多 6 份文档) 留足。
MAX_REQUESTS = int(os.environ.get("HISTORY_MAX_REQUESTS", "24000"))
# 每个年度对里，逐条列出的新增／消失上限。超出只报数，并写明「另有 N 条未单列」
# ——默默截断会让读者以为那就是全部。
LIST_CAP = int(os.environ.get("HISTORY_LIST_CAP", "40"))
# 一个年度对要能按编号比，**两年都得有过半条目带编号**。
#
# 实测 ALLE：条目数四年稳在 354/370/343/338，而带编号的是 24/38/343/338——
# 申报人自己在 2025 年开始写编号了。拿「7% 带编号」的一年去比「100% 带编号」
# 的一年，得出「新增 306、消失 1」，那不是换厂，是编号覆盖率变了。
#
# 半数这条线是可以说清的：编号条目低于一半时，它只是这份名单的少数样本，
# 年度差异由「哪些条目刚好带了编号」主导，而不是由供应链变化主导。
# 阈值随数据一起发布，页面照它说话。
MIN_CID_COVERAGE = float(os.environ.get("HISTORY_MIN_CID_COVERAGE", "0.5"))

# ── 单边整批变动：报不了，因为分不清 ───────────────────────────────────────
#
# 实测这一形状 15 组（459 组里 3.3%）：
#
#     ERII 2023→2024   316 →  13 条   新增   0   消失 303
#     HAYW 2025→2026   368 →  20 条   新增   0   消失 348
#     NRG  2023→2024    67 → 331 条   新增 265   消失   1
#
# 一边整批进出、另一边几乎没动静。**这有两种同样说得通的解释**：申报人真的
# 大改了名单口径，或者那一年只解析到了文档的一部分。两者在数据上完全一样，
# 要分清必须调出原文逐份核对——而本容器取不到 SEC。
#
# 所以标不可比，写明「需核对原文」。不是判它错，是**说清楚我判不了**。
# 放着不管的后果是它们会占据榜首：按变动率排序时这 15 组里有 4 组进前 10。
ONESIDED_SMALL = 2       # 「另一边几乎没动静」＝ ≤2 条
ONESIDED_RATIO = 2       # 条数差一倍以上
ONESIDED_FLOOR = 20      # 规模太小的不算（3→1 条说明不了什么，且变动率本就有界）

# 榜单排名要求的最小分母。**比值要成为「率」，分母得够大。**
# 实测 444 组可比里 19 组分母 <10，而它们占了榜单前 20 的 4 席：
# SOUNDTHINKING 分母 2、好市多分母 3——加两座减一座就印成「150%」。
# 那不是换厂强度，是分母太小。数据里照留，**只是不参与按比例排的榜**，
# 并在页脚报出有多少家因此没上榜。
MIN_BASE_FOR_RANKING = int(os.environ.get("HISTORY_MIN_BASE_RANK", "10"))


def onesided(added: int, dropped: int, base: int, new: int) -> bool:
    """一边整批进出、另一边几乎没动静，且条数差一倍以上、规模够大。"""
    hi, lo = max(base, new), min(base, new)
    return (min(added, dropped) <= ONESIDED_SMALL
            and hi >= ONESIDED_RATIO * max(1, lo)
            and hi >= ONESIDED_FLOOR)

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"
NODES_PATH = "apps/supply-chain/nodes.json"
OUT_PATH = "apps/supply-chain/history.json"


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


def sd_filings(cik: int, limit: int) -> list[dict]:
    url = f"https://data.sec.gov/submissions/CIK{cik:010d}.json"
    meta = json.loads(fetch(url).decode("utf-8", "replace"))
    recent = (meta.get("filings") or {}).get("recent") or {}
    rows = []
    for form, accession, date in zip(
            recent.get("form") or [], recent.get("accessionNumber") or [],
            recent.get("filingDate") or []):
        if form != "SD":
            continue
        rows.append({"accession": accession, "date": date})
        if len(rows) >= limit:
            break
    return rows


def exhibit_urls(cik: int, accession: str) -> list[str]:
    acc = accession.replace("-", "")
    base = f"https://www.sec.gov/Archives/edgar/data/{cik}/{acc}"
    try:
        listing = json.loads(fetch(f"{base}/index.json").decode("utf-8", "replace"))
    except Exception:                              # noqa: BLE001
        return []
    names = [item.get("name") or "" for item in
             ((listing.get("directory") or {}).get("item") or [])]
    docs = [n for n in names if n.lower().endswith((".htm", ".html", ".txt"))]
    docs.sort(key=lambda n: (0 if "ex" in n.lower() else 1, n))
    return [f"{base}/{n}" for n in docs[:6]]


# 一份申报里认为「名单已经拿全」的行数。到了这个量级就不再试别的附件，省请求。
RICH_ENOUGH = 100


def parse_one(parser, cik: int, accession: str) -> tuple[set, int, int]:
    """返回（该年的 CID 集合, 总条目数, 只有名字的条目数）。

    **取这份申报里条目最多的那个附件，不是第一个能解出东西的。**

    第一版是「谁先解出行就用谁」，跑出来的数一眼就不对：

        SHW   32 → 9 → 30 → 7 条       ERII  316 → 13 → 13 → 49 条
        HAYW  336 → 351 → 368 → 20 条  MO     19 → 257 → 266 → 41 条

    没有公司会这一年报 368 座厂、下一年报 20 座，更不会来回跳。真相是一份
    Form SD 提交里常有**两份东西**：正文（只列几家或一句话带过）和冲突矿产
    报告附件（完整的表）。文件名排序一变，先解出行的就成了那份短的，于是
    「少了 348 座」被记成换厂——而它只是我取错了附件。

    这一条比按名字比对更阴险：ERII 2023→2024 的变动率只有 96%，**按数值筛
    异常永远筛不到它**，只有看「新增 0 / 消失 303」这个形状才看得出来。

    所以逐个附件都解一遍，取条目最多的。代价是请求数翻几倍（预算已相应放大），
    换来的是不把取错附件说成企业换了供应链。parse_smelters 只收像冶炼厂行的
    行（带编号，或厂名＋国别＋矿种齐全），所以「条目最多」不会被财务表带偏。
    """
    best: tuple[set, int, int] = (set(), 0, 0)
    for url in exhibit_urls(cik, accession):
        try:
            raw = fetch(url)
        except Exception:                          # noqa: BLE001
            continue
        try:
            parsed = parser.parse_smelters(raw.decode("utf-8", "replace"))
        except Exception:                          # noqa: BLE001
            continue
        rows = parsed.get("smelters") or []
        if len(rows) <= best[1]:
            continue
        cids = {(r.get("cid") or "").strip() for r in rows if (r.get("cid") or "").strip()}
        name_only = sum(1 for r in rows if not (r.get("cid") or "").strip())
        best = (cids, len(rows), name_only)
        if len(rows) >= RICH_ENOUGH:
            break                                  # 已经是完整表，不必再试
    return best


def summarise(companies: dict, targets_n: int, failed: list) -> dict:
    """按当前规则重算 coverage。产出方与 --repair 共用同一份实现。"""
    rates = [c["rate"] for comp in companies.values() for c in comp["changes"]
             if c.get("comparable") and c.get("yearGap") == 1]
    rates.sort()
    median = rates[len(rates) // 2] if rates else 0.0
    p90 = rates[min(len(rates) - 1, int(len(rates) * 0.9))] if rates else 0.0
    pairs = sum(1 for comp in companies.values() for c in comp["changes"]
                if c.get("comparable"))
    with_cid = sum(y["withCid"] for c in companies.values() for y in c["years"][:1])
    listed = sum(y["listed"] for c in companies.values() for y in c["years"][:1])
    onesided_n = sum(1 for comp in companies.values() for c in comp["changes"]
                     if c.get("oneSided"))
    return {
        "companiesTracked": len(companies),
        "companiesWithList": targets_n,
        "pairsComparable": pairs,
        "adjacentPairs": len(rates),
        "medianRate": round(median, 4),
        "p90Rate": round(p90, 4),
        "trackableShare": round(with_cid / max(1, listed), 4),
        # 分不清是「真的大改名单」还是「只解析到部分文档」的那些，单独报数。
        "oneSidedSetAside": onesided_n,
        # 分母太小、不参与按比例排名的公司数（数据里照留）
        "belowRankingBase": sum(
            1 for comp in companies.values()
            for c in comp["changes"][:1]
            if c.get("comparable") and (c.get("baseWithCid") or 0) < MIN_BASE_FOR_RANKING),
        "failed": failed[:20],
        "failedCount": len(failed),
    }


def repair() -> int:
    """按当前规则重判已发布的 history.json。纯本地变换，不发起网络请求。

    与 backfill_edge_country.py 同一条理由：**重新抽取历年申报要跑近一小时的
    网络回溯，而规则变了不该每次都重跑**。判据全是已发布数据里现成的字段
    （新增数、消失数、分母、年份），离线就能重算。

    幂等：产出方已经按同一套规则写过的文件，跑这个不会有任何改动。
    """
    with open(OUT_PATH, encoding="utf-8") as handle:
        doc = json.load(handle)
    companies = doc.get("companies") or {}
    moved = gapped = 0
    for sym, comp in companies.items():
        rebuilt = []
        for ch in comp.get("changes") or []:
            if not ch.get("comparable"):
                rebuilt.append(ch)
                continue
            base = ch.get("baseWithCid") or 0
            a, d = ch.get("addedCount", 0), ch.get("droppedCount", 0)
            new_n = base - d + a
            if onesided(a, d, base, new_n):
                rebuilt.append({
                    "from": ch["from"], "to": ch["to"], "comparable": False,
                    "note": (f"{base} 条 → {new_n} 条，新增 {a}、消失 {d}"
                             "——一边整批进出、另一边几乎没动静。申报人真的大改"
                             "名单，与那一年只解析到部分文档，在数据上分不开，"
                             "需核对原文"),
                    "oneSided": True,
                    "cidCoverageFrom": ch.get("cidCoverageFrom"),
                    "cidCoverageTo": ch.get("cidCoverageTo")})
                moved += 1
                continue
            ch["yearGap"] = int(ch["to"]) - int(ch["from"])
            if ch["yearGap"] != 1:
                gapped += 1
            rebuilt.append(ch)
        comp["changes"] = rebuilt
    # 一组可比都不剩的公司要摘掉——与产出方同一条规矩。
    dropped = [s for s, c in companies.items()
               if not any(x.get("comparable") for x in c["changes"])]
    for s in dropped:
        del companies[s]
    doc["minCidCoverage"] = doc.get("minCidCoverage", MIN_CID_COVERAGE)
    doc["minBaseForRanking"] = MIN_BASE_FOR_RANKING
    doc["coverage"] = summarise(companies,
                                (doc.get("coverage") or {}).get("companiesWithList", 0),
                                (doc.get("coverage") or {}).get("failed") or [])
    with open(OUT_PATH, "w", encoding="utf-8") as handle:
        json.dump(doc, handle, ensure_ascii=False, indent=2)
    cov = doc["coverage"]
    print(f"改判单边整批变动 {moved} 组 · 标出跨多年 {gapped} 组 · "
          f"整家摘掉 {len(dropped)} 家（{'、'.join(dropped[:6])}）")
    print(f"可比 {cov['pairsComparable']} 组（其中真正相邻的 {cov['adjacentPairs']} 组）"
          f" · 中位 {cov['medianRate'] * 100:.1f}% · 90 分位 {cov['p90Rate'] * 100:.0f}%")
    return 0


def main() -> int:
    if "--repair" in sys.argv:
        return repair()
    try:
        import form_sd_parse as parser
    except Exception as exc:                       # noqa: BLE001
        print(f"[XX] 载入解析器失败：{exc}")
        return 1

    with open(NODES_PATH, encoding="utf-8") as handle:
        payload = json.load(handle)
    index = payload.get("edgeIndex") or {}
    cik_of = {n.get("symbol"): n.get("cik") for n in (payload.get("nodes") or [])}
    targets = [(s, int(cik_of[s])) for s in sorted(index) if cik_of.get(s)]
    if not targets:
        print("[XX] 没有有名单的公司，跳过")
        return 0
    print(f"有名单的公司 {len(targets)} 家 · 每家回溯至多 {YEARS} 份 Form SD")
    print(f"跨年身份只认 RMI 编号——只有名字的条目追不了，会如实报它占多少\n")

    companies: dict[str, dict] = {}
    failed: list[str] = []
    rates: list[float] = []
    tracked = total_rows = 0
    for i, (symbol, cik) in enumerate(targets, 1):
        try:
            filings = sd_filings(cik, YEARS)
        except Exception as exc:                   # noqa: BLE001
            failed.append(f"{symbol}:{why(exc)}")
            continue
        years = []
        for filing in filings:
            cids, rows, name_only = parse_one(parser, cik, filing["accession"])
            if rows:
                years.append({"date": filing["date"], "year": filing["date"][:4],
                              "listed": rows, "withCid": len(cids),
                              "nameOnly": name_only, "_cids": cids})
        if len(years) < 2:
            continue
        changes = []
        for new, old in zip(years, years[1:]):
            a, b = new["_cids"], old["_cids"]
            cov_new = new["withCid"] / max(1, new["listed"])
            cov_old = old["withCid"] / max(1, old["listed"])
            if not a or not b:
                # **一边没有带编号的条目就算不了**，如实标出来，不拿 0 充当「没变」。
                changes.append({"from": old["year"], "to": new["year"],
                                "comparable": False,
                                "note": "该年没有带 RMI 编号的条目，跨年无法比对"})
                continue
            if min(cov_new, cov_old) < MIN_CID_COVERAGE:
                # 见 MIN_CID_COVERAGE 的注释：编号覆盖率差太远时，差异说的是
                # 「哪些条目带了编号」而不是供应链变化。如实标不可比。
                changes.append({
                    "from": old["year"], "to": new["year"], "comparable": False,
                    "note": (f"{old['year']} 年 {cov_old * 100:.0f}%、"
                             f"{new['year']} 年 {cov_new * 100:.0f}% 的条目带 RMI 编号，"
                             f"不足 {MIN_CID_COVERAGE * 100:.0f}%——按编号比对只会"
                             "反映编号覆盖率的变化，不是换厂"),
                    "cidCoverageFrom": round(cov_old, 4),
                    "cidCoverageTo": round(cov_new, 4)})
                continue
            added = sorted(a - b)
            dropped = sorted(b - a)
            if onesided(len(added), len(dropped), len(b), len(a)):
                changes.append({
                    "from": old["year"], "to": new["year"], "comparable": False,
                    "note": (f"{len(b)} 条 → {len(a)} 条，新增 {len(added)}、"
                             f"消失 {len(dropped)}——一边整批进出、另一边几乎没动静。"
                             "申报人真的大改名单，与那一年只解析到部分文档，"
                             "在数据上分不开，需核对原文"),
                    "oneSided": True,
                    "cidCoverageFrom": round(cov_old, 4),
                    "cidCoverageTo": round(cov_new, 4)})
                continue
            # 跨度必须如实标。四份申报里若缺了中间几年（MO 实测是
            # 2026/2025/2019/2018），「列表里相邻」并不等于「年份相邻」，
            # 把跨 6 年的变动混进「年度变动率」的中位数就是换了口径还不说。
            gap = int(new["year"]) - int(old["year"])
            rate = (len(added) + len(dropped)) / len(b)
            if gap == 1:
                rates.append(rate)
            changes.append({
                "from": old["year"], "to": new["year"], "comparable": True,
                "basis": "rmi-cid", "yearGap": gap,
                "addedCount": len(added), "droppedCount": len(dropped),
                "added": added[:LIST_CAP], "dropped": dropped[:LIST_CAP],
                "addedOmitted": max(0, len(added) - LIST_CAP),
                "droppedOmitted": max(0, len(dropped) - LIST_CAP),
                "baseWithCid": len(b), "rate": round(rate, 4),
                "cidCoverageFrom": round(cov_old, 4),
                "cidCoverageTo": round(cov_new, 4),
            })
        if not any(c.get("comparable") for c in changes):
            continue
        tracked += 1
        total_rows += years[0]["listed"]
        companies[symbol] = {
            "years": [{k: v for k, v in y.items() if k != "_cids"} for y in years],
            "changes": changes,
            # 这家公司最新一份名单里，有多少条追得动（带编号）
            "trackableShare": round(years[0]["withCid"] / max(1, years[0]["listed"]), 4),
        }
        if i % 40 == 0:
            print(f"  … 已处理 {i}/{len(targets)}，可比 {tracked} 家，"
                  f"请求用掉 {MAX_REQUESTS - BUDGET.left}")

    if not companies:
        print("[XX] 一家都没取到可比的历年名单——**保留已有文件，不写空数据**")
        return 0

    rates.sort()
    median = rates[len(rates) // 2] if rates else 0.0
    # **不发布最大值。** 分母从 2 条到 500 条不等，最大值永远由最小的那个分母
    # 决定（实测 MO 2018→2019：基年 19 条、次年 257 条 = 1388%，算术没错，
    # 但它说的是「那年名单很短」，不是「换厂最猛」）。90 分位才是能读的高位。
    p90 = rates[min(len(rates) - 1, int(len(rates) * 0.9))] if rates else 0.0
    with_cid = sum(y["withCid"] for c in companies.values() for y in c["years"][:1])
    listed = sum(y["listed"] for c in companies.values() for y in c["years"][:1])
    out = {
        "contractVersion": 1,
        "dataset": "supply-chain-smelter-history",
        "basis": "rmi-cid",
        "note": "变动只统计带 RMI 编号的条目——编号是冶炼厂设施的全球唯一标识，"
                "跨年可比；只有名字的条目一个拼写差异就会同时造出一条假新增和"
                "一条假消失，因此不计入。下面的 trackableShare 是追得动的比例。",
        "years": YEARS,
        # 按编号比对的前置条件，随数据发布——页面要能照着说，而不是我在代码里
        # 定了个数、页面上写另一个数。
        "minCidCoverage": MIN_CID_COVERAGE,
        # 榜单的最小分母，随数据发布——页面照它筛、照它说。
        "minBaseForRanking": MIN_BASE_FOR_RANKING,
        "companies": companies,
        "coverage": summarise(companies, len(targets), failed),
        "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    with open(OUT_PATH, "w", encoding="utf-8") as handle:
        json.dump(out, handle, ensure_ascii=False, indent=2)
    print(f"\n可比公司 {len(companies)} 家 · 年度对比 {len(rates)} 组")
    print(f"变动率（带编号口径）：中位 {median * 100:.1f}% · "
          f"最小 {rates[0] * 100:.1f}% · 最大 {rates[-1] * 100:.1f}%")
    print(f"追得动的条目占比 {out['coverage']['trackableShare'] * 100:.0f}%"
          f"（其余只有名字，跨年追不了）")
    if failed:
        print(f"取数失败 {len(failed)} 家（保留不撤，失败≠没有）")
    print(f"→ {OUT_PATH} · 请求用掉 {MAX_REQUESTS - BUDGET.left}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
