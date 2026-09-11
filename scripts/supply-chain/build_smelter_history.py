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
MAX_REQUESTS = int(os.environ.get("HISTORY_MAX_REQUESTS", "9000"))
# 每个年度对里，逐条列出的新增／消失上限。超出只报数，并写明「另有 N 条未单列」
# ——默默截断会让读者以为那就是全部。
LIST_CAP = int(os.environ.get("HISTORY_LIST_CAP", "40"))

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


def parse_one(parser, cik: int, accession: str) -> tuple[set, int, int]:
    """返回（该年的 CID 集合, 总条目数, 只有名字的条目数）。"""
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
        if not rows:
            continue
        cids = {(r.get("cid") or "").strip() for r in rows if (r.get("cid") or "").strip()}
        name_only = sum(1 for r in rows if not (r.get("cid") or "").strip())
        return cids, len(rows), name_only
    return set(), 0, 0


def main() -> int:
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
            if not a or not b:
                # **一边没有带编号的条目就算不了**，如实标出来，不拿 0 充当「没变」。
                changes.append({"from": old["year"], "to": new["year"],
                                "comparable": False,
                                "note": "该年没有带 RMI 编号的条目，跨年无法比对"})
                continue
            added = sorted(a - b)
            dropped = sorted(b - a)
            rate = (len(added) + len(dropped)) / len(b)
            rates.append(rate)
            changes.append({
                "from": old["year"], "to": new["year"], "comparable": True,
                "basis": "rmi-cid",
                "addedCount": len(added), "droppedCount": len(dropped),
                "added": added[:LIST_CAP], "dropped": dropped[:LIST_CAP],
                "addedOmitted": max(0, len(added) - LIST_CAP),
                "droppedOmitted": max(0, len(dropped) - LIST_CAP),
                "baseWithCid": len(b), "rate": round(rate, 4),
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
        "companies": companies,
        "coverage": {
            "companiesTracked": len(companies),
            "companiesWithList": len(targets),
            "pairsComparable": len(rates),
            "medianRate": round(median, 4),
            "minRate": round(rates[0], 4) if rates else 0,
            "maxRate": round(rates[-1], 4) if rates else 0,
            # **这个比例必须跟着中位数一起发布。** 17% 的变动只覆盖三成条目，
            # 不写出来读者会当成整份名单的换厂率。
            "trackableShare": round(with_cid / max(1, listed), 4),
            "failed": failed[:20],
            "failedCount": len(failed),
        },
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
