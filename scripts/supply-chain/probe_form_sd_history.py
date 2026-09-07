#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读探测：历年 Form SD 能不能撑起「时间维度」。

## 为什么探这条

台账里「整个工程的进度」那张表上，时间维度是**唯一一个 0%** 的格子：

    时间维度   1 期快照   多年对比   0%

而它是这几块空缺里**唯一不需要新数据源、不涉及任何许可的**——Form SD 每年
五月底前申报一次，EDGAR 把历年申报全留着，公共领域，与现在这套管线同源、
同一个解析器。抽取器只是每次都取最新那一份，把旧的丢了。

补上之后能回答的是这一类问题，而且每一条都带得出原始出处：

    这家公司今年比去年新增了哪些冶炼厂、砍掉了哪些
    某座冶炼厂是哪一年开始出现在申报里的、什么时候消失的
    受涵盖国家的暴露是在扩大还是在收缩

**这才是「供应链风险」真正该有的读法**——存量名单只能说明现状，变动才说明
方向。华尔街看供应链先看的就是变动。

## 要回答四件事

1. **有多少年**：抽样 N 家，每家在 EDGAR 上有几份 Form SD、最早到哪一年。
2. **旧的解得开吗**：拿同一个解析器跑历年文档，看抽出的冶炼厂条数是否合理。
   **解不开的年份要如实报，不能拿解析失败冒充「那年名单短」**——那是把
   抓取缺陷说成了业务事实，本板块栽过一模一样的跟头（第八轮的 77 家误判）。
3. **变动看得出来吗**：同一家公司相邻两年的名单做差集，新增／删除各多少。
   如果差集恒为 0，说明公司年年报同一份，时间维度就没有信息量，不值得建。
4. **代价多大**：多取几年就是多几倍请求。按实测的每份耗时估算全量成本。

## 判据先写死

    相邻两年平均变动 ≥5%   → 值得建，时间维度有信息量
    变动 1%~5%             → 边际，只做「新增／消失」两个小读数，不做趋势
    变动 <1%               → 判死：年年同一份名单，多存几年只是多占空间

只读。不写仓库任何数据文件。
"""
from __future__ import annotations

import json
import os
import statistics
import sys
import time
from urllib import error, request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

TIMEOUT = 30
GAP = 0.20
BODY_LIMIT = 12_000_000
MAX_REQUESTS = int(os.environ.get("HIST_MAX_REQUESTS", "300"))
SAMPLE = int(os.environ.get("HIST_SAMPLE", "12"))
YEARS = int(os.environ.get("HIST_YEARS", "4"))

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"
NODES_PATH = "apps/supply-chain/nodes.json"
EDGES_DIR = "apps/supply-chain/edges"


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


def load_targets() -> list[tuple[str, int]]:
    """只取**已经有名单**的公司。它们证过能解出冶炼厂，历年解不开就确实是
    旧文档的问题，而不是这家公司本来就没名单——**对照组要选对**。"""
    with open(NODES_PATH, encoding="utf-8") as handle:
        payload = json.load(handle)
    index = payload.get("edgeIndex") or {}
    cik_of = {n.get("symbol"): n.get("cik") for n in (payload.get("nodes") or [])}
    out = [(s, cik_of.get(s)) for s in sorted(index) if cik_of.get(s)]
    return out


def sd_filings(cik: int, limit: int) -> list[dict]:
    url = f"https://data.sec.gov/submissions/CIK{cik:010d}.json"
    meta = json.loads(fetch(url).decode("utf-8", "replace"))
    recent = (meta.get("filings") or {}).get("recent") or {}
    rows = []
    for form, accession, date, doc in zip(
            recent.get("form") or [], recent.get("accessionNumber") or [],
            recent.get("filingDate") or [], recent.get("primaryDocument") or []):
        if form != "SD":
            continue
        rows.append({"accession": accession, "date": date, "doc": doc})
        if len(rows) >= limit:
            break
    return rows


def exhibit_urls(cik: int, accession: str) -> list[str]:
    """冶炼厂名单在附件里（通常 EX-1.01），不在主文档。"""
    acc = accession.replace("-", "")
    base = f"https://www.sec.gov/Archives/edgar/data/{cik}/{acc}"
    try:
        listing = json.loads(fetch(f"{base}/index.json").decode("utf-8", "replace"))
    except Exception:                              # noqa: BLE001
        return []
    names = [item.get("name") for item in
             ((listing.get("directory") or {}).get("item") or [])]
    docs = [n for n in names if n and n.lower().endswith((".htm", ".html", ".txt"))]
    # 名单文档通常比主文档大得多；这里全给出来，由调用方逐个试到抽出为止。
    docs.sort(key=lambda n: (0 if "ex" in n.lower() else 1, n))
    return [f"{base}/{n}" for n in docs[:6]]


def main() -> int:
    print("═" * 74)
    print("探针：历年 Form SD —— 时间维度有没有信息量")
    print("═" * 74)
    print("许可：SEC EDGAR = 美国政府公开记录（GOV）。与现有管线同源，无新增许可。\n")

    try:
        import form_sd_parse
    except Exception as exc:                       # noqa: BLE001
        print(f"[XX] 载入解析器失败：{exc}")
        return 1

    targets = load_targets()
    if not targets:
        print("[XX] 读不到有名单的公司")
        return 1
    step = max(1, len(targets) // SAMPLE)
    sample = targets[::step][:SAMPLE]
    print(f"有名单的公司 {len(targets)} 家，均匀抽 {len(sample)} 家 · "
          f"每家最多回溯 {YEARS} 份 Form SD\n")

    per_company: list[dict] = []
    for symbol, cik in sample:
        try:
            filings = sd_filings(int(cik), YEARS)
        except Exception as exc:                   # noqa: BLE001
            print(f"[XX] {symbol:6} 取申报清单失败 {why(exc)}")
            continue
        if not filings:
            print(f"[--] {symbol:6} EDGAR 上没有 SD 申报")
            continue
        years: list[tuple[str, set]] = []
        for filing in filings:
            names: set = set()
            for url in exhibit_urls(int(cik), filing["accession"]):
                try:
                    raw = fetch(url)
                except Exception:                  # noqa: BLE001
                    continue
                try:
                    parsed = form_sd_parse.parse_smelters(
                        raw.decode("utf-8", "replace"))
                except Exception:                  # noqa: BLE001
                    continue
                # 返回的键是 "smelters"（见 parse_smelters 的 docstring）。
                # 凭印象写键名就是在编数据——这一行按源码核过。
                for row in (parsed.get("smelters") or []):
                    key = (row.get("cid") or row.get("name") or "").strip()
                    if key:
                        names.add(key)
                if names:
                    break
            years.append((filing["date"], names))
        got = [(d, n) for d, n in years if n]
        print(f"[{'OK' if got else '--'}] {symbol:6} SD 申报 {len(filings)} 份 · "
              + " · ".join(f"{d[:4]} {len(n) or '解不开'}" for d, n in years))
        if len(got) >= 2:
            deltas = []
            for (d1, a), (d2, b) in zip(got, got[1:]):
                added = len(a - b)
                dropped = len(b - a)
                base = max(1, len(b))
                deltas.append((d1[:4], d2[:4], added, dropped,
                               (added + dropped) / base))
            per_company.append({"symbol": symbol, "deltas": deltas})
            for y1, y2, add, drop, rate in deltas:
                print(f"        {y2} → {y1}：新增 {add:4} · 消失 {drop:4} · "
                      f"变动率 {rate * 100:5.1f}%")

    print("\n" + "─" * 74)
    if not per_company:
        print("[XX] 没有一家取到两年以上可解析的名单——这条路要么解析器对旧文档"
              "无效，要么 EDGAR 上就只有一份。**不能据此说「名单没变化」。**")
        return 0
    rates = [d[4] for row in per_company for d in row["deltas"]]
    median = statistics.median(rates)
    print(f"可比公司 {len(per_company)} 家 · 相邻年度对比 {len(rates)} 组")
    print(f"变动率：中位 {median * 100:.1f}% · 最小 {min(rates) * 100:.1f}%"
          f" · 最大 {max(rates) * 100:.1f}%")
    print()
    if median >= 0.05:
        print("判据：中位变动率 ≥5% —— **值得建**。时间维度有信息量，"
              "下一步把抽取器改成保留历年、建「新增／消失」两个读数。")
    elif median >= 0.01:
        print("判据：中位变动率 1%~5% —— 边际。只做「本年新增／本年消失」两个"
              "小读数，不做趋势线（样本太薄，趋势会被读成规律）。")
    else:
        print("判据：中位变动率 <1% —— **判死**。年年报同一份名单，多存几年"
              "只是多占空间，不产生新读数。")
    print(f"\n代价：本次抽 {len(sample)} 家 × 最多 {YEARS} 年用掉请求 "
          f"{MAX_REQUESTS - BUDGET.left}；全量 128 家 × {YEARS} 年约 "
          f"{int((MAX_REQUESTS - BUDGET.left) / max(1, len(sample)) * 128)} 次")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
