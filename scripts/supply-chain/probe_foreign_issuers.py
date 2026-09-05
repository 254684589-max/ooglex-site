#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读探测：SEC 外国私人发行人能不能当全球产业链的母池，以及它带不带来「边」。

## 为什么要这条

板块的目标是全球产业链，可现在的公司池是标普 500——单一国家指数。缺的不是零头：
ASML、台积电、三星、丰田、西门子、施耐德、宁德时代、必和必拓、力拓、淡水河谷，
没有一家在池子里，而半导体链上没有 ASML 和台积电根本画不出来。

母池的第一候选是 MSCI ACWI（约 2,460 只）与 S&P Global 1200。**这两条走不通，
但不是技术原因**：成分股名单是指数商的专有数据，不公开发布、再分发要授权，
与仓库此前因许可放弃的 SPX／DXY／LBMA 定盘价同类（见 docs/SUPPLY_CHAIN_SOURCES.md
第 2 节「许可红线」）。技术上抓得到不等于可以登记。

许可干净的那条路是 SEC 自己：外国私人发行人在美上市要报 20-F（非加拿大）或
40-F（加拿大 MJDS），文件全在 EDGAR，公共领域，与现在这套管线同源、同一个
User-Agent 规矩、同一套限速。台积电、ASML、丰田、索尼、必和必拓、力拓、
淡水河谷、壳牌、SAP、Infosys 都在里面。

## 决定性的问题不是「够不够得到这些公司」，是「加进来带不带关系」

上一轮已经想清楚的一点：**只扩公司范围只增加节点，不增加边**。图上多 500 个
孤立的点不叫产业链。所以这个探针真正要回答的是一句话：

    这些外国发行人，申不申报 Form SD？

申报，扩池就同时带来节点和边（冶炼厂名单是目前唯一跑通的边来源）；
不申报，扩池只得到一堆孤立的点，那得先解决边的来源再谈扩池。

## 怎么问

不猜、不用模型知识。去数 EDGAR 的季度全量索引（full-index/master.idx，公共领域、
管道分隔）：过去 N 个季度里报 20-F／40-F 的 CIK 集合、报 SD 的 CIK 集合，求交集。
交集有多大、都是谁，原样打到日志里。

顺带回答另外三件只有真数据能回答的事：
  · 这些外国发行人里有多少家有美股代码（有代码才接得进现有以 ticker 为键的数据模型）
  · 覆盖哪些国家、哪些交易所（按 EDGAR 自己填的注册地／地址国别统计，不按我以为的）
  · 用户点名的那几家里，哪几家 SEC 根本够不到（三星、宁德时代、西门子、施耐德、
    LVMH 都不在美上市）——**这是这条路的硬上限，要报出来，不能藏**

**只读。不写仓库、不建任何边、不改公司池。**结论由人看数据得出，不由脚本给。
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from datetime import date

QUARTERS = int(os.environ.get("PROBE_QUARTERS", "4") or 4)
MAX_SUBMISSIONS = int(os.environ.get("PROBE_MAX_SUBMISSIONS", "400") or 400)
MAX_DOC_LISTS = 12             # 抽几家外国 SD 申报人，把申报目录原样列出来

OUTPUT = os.environ.get("PROBE_OUTPUT", "")


sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_form_sd import skip_reason           # noqa: E402
# 索引读取与解析和取数脚本共用一份实现。两处各写一套的话，改了一处另一处就
# 开始说假话——`skip_reason` 当初拆出来是同一个理由。
from edgar_index import (                          # noqa: E402
    FOREIGN_ANNUAL, FOREIGN_INTERIM, SD_FORMS, GAP, INDEX_URL,
    SUBMISSIONS_URL, TICKERS_EXCHANGE_URL,
    _get_json, _why, accession_dir, parse_index_line, recent_quarters, stream_lines,
)

# 点名要查的公司。前半段是「应该在 SEC 里」的，后半段按名字在全量登记名录里搜——
# 搜不到就是搜不到，如实报，那正是这条路的边界。
NAMED_TICKERS = [
    ("TSM", "台积电"), ("ASML", "阿斯麦"), ("TM", "丰田"), ("SONY", "索尼"),
    ("BHP", "必和必拓"), ("RIO", "力拓"), ("VALE", "淡水河谷"), ("SHEL", "壳牌"),
    ("SAP", "SAP"), ("INFY", "Infosys"), ("STLA", "Stellantis"),
    ("AZN", "阿斯利康"), ("NVO", "诺和诺德"), ("UL", "联合利华"),
    ("MUFG", "三菱日联"), ("BABA", "阿里巴巴"),
]
NAMED_SEARCH = [
    ("SAMSUNG", "三星"), ("SIEMENS", "西门子"), ("SCHNEIDER", "施耐德"),
    ("CONTEMPORARY AMPEREX", "宁德时代"), ("LVMH", "LVMH"),
    ("TOYOTA", "丰田"), ("SONY", "索尼"), ("HYUNDAI", "现代"),
]


def scan_quarter(year: int, quarter: int, foreign: dict, interim: set,
                 sd: dict) -> dict:
    url = INDEX_URL.format(year=year, quarter=quarter)
    stats = {"quarter": f"{year}QTR{quarter}", "url": url, "rows": 0,
             "unparsed": 0, "bytes": 0, "gzip": False}
    try:
        for line in stream_lines(url, stats):
            if not line.strip():
                continue
            row = parse_index_line(line)
            if row is None:
                # 表头那几行本来就解析不了，是正常的；数量异常才说明解析器有问题。
                stats["unparsed"] += 1
                continue
            stats["rows"] += 1
            form, cik = row["form"], row["cik"]
            if form in FOREIGN_ANNUAL:
                entry = foreign.setdefault(cik, {"name": row["name"], "forms": set(),
                                                 "last": ""})
                entry["forms"].add(form)
                if row["date"] > entry["last"]:
                    entry["last"] = row["date"]
                    entry["name"] = row["name"]
            elif form in FOREIGN_INTERIM:
                interim.add(cik)
            elif form in SD_FORMS:
                entry = sd.setdefault(cik, {"name": row["name"], "last": "", "path": ""})
                if row["date"] > entry["last"]:
                    entry.update({"last": row["date"], "path": row["path"],
                                  "name": row["name"]})
    except Exception as exc:                       # noqa: BLE001
        stats["error"] = _why(exc)
    return stats


def main() -> int:
    today = date.today()
    quarters = recent_quarters(today, QUARTERS)
    print("── EDGAR 季度全量索引 ─────────────────────────────────────────")
    print(f"扫 {QUARTERS} 个季度："
          + "、".join(f"{y}Q{q}" for y, q in quarters))
    print("数三件事：报 20-F／40-F 的 CIK、报 6-K 的 CIK、报 SD 的 CIK。\n")

    foreign: dict[int, dict] = {}
    interim: set[int] = set()
    sd: dict[int, dict] = {}
    quarter_stats = []
    for year, quarter in quarters:
        stats = scan_quarter(year, quarter, foreign, interim, sd)
        quarter_stats.append(stats)
        if "error" in stats:
            # 本季度还没生成（当季）或取不到，如实标出来，不当成「这季度没人申报」。
            print(f"[XX] {stats['quarter']}  取不到：{stats['error']}")
        else:
            print(f"[--] {stats['quarter']}  {stats['rows']:>7,} 行"
                  f"  下载 {stats['bytes'] // 1048576:>3}MB"
                  f"{'（gzip）' if stats['gzip'] else '（未压缩）'}"
                  f"  解析不了 {stats['unparsed']} 行")
        time.sleep(GAP)

    ok_quarters = [s for s in quarter_stats if "error" not in s]
    if not ok_quarters:
        print("\n[XX] 一个季度的索引都没取到，下面的数字全都无意义，中止。")
        return 1

    sd_ciks = set(sd)
    foreign_ciks = set(foreign)
    both = sorted(foreign_ciks & sd_ciks, key=lambda c: foreign[c]["name"])

    print("\n── 规模 ───────────────────────────────────────────────────────")
    print(f"报 20-F／40-F 的公司（外国私人发行人年报）  {len(foreign_ciks):>6,} 家")
    print(f"报 6-K 的公司（外国私人发行人临时报告）    {len(interim):>6,} 家"
          "  ← 交叉验证，年报窗口在扫描期外的能被它兜住")
    print(f"报 Form SD 的公司（全体，含美国本土）      {len(sd_ciks):>6,} 家")

    print("\n── 决定性的一问：外国发行人申不申报 Form SD ───────────────────")
    print(f"两者都有的                                {len(both):>6,} 家")
    if foreign_ciks:
        print(f"占外国发行人的                            "
              f"{len(both) / len(foreign_ciks) * 100:>6.1f}%")

    # ticker 映射：接进现有以 ticker 为键的数据模型，得有代码。
    tickers_by_cik: dict[int, list[str]] = {}
    exch_by_cik: dict[int, list[str]] = {}
    name_index: list[tuple[int, str, str]] = []
    try:
        payload = _get_json(TICKERS_EXCHANGE_URL)
        fields = payload.get("fields") or []
        idx = {name: i for i, name in enumerate(fields)}
        for row in payload.get("data") or []:
            try:
                cik = int(row[idx["cik"]])
            except (KeyError, IndexError, TypeError, ValueError):
                continue
            ticker = str(row[idx["ticker"]]) if "ticker" in idx else ""
            exchange = str(row[idx["exchange"]] or "") if "exchange" in idx else ""
            name = str(row[idx["name"]] or "") if "name" in idx else ""
            if ticker:
                tickers_by_cik.setdefault(cik, []).append(ticker)
            if exchange:
                exch_by_cik.setdefault(cik, []).append(exchange)
            if name:
                name_index.append((cik, name.upper(), ticker))
        print(f"\n[--] 全量登记名录（含代码与交易所）{len(name_index):,} 条")
    except Exception as exc:                       # noqa: BLE001
        print(f"\n[XX] 取全量登记名录失败：{_why(exc)}；下面「有代码」的统计会缺")

    with_ticker = [c for c in foreign_ciks if tickers_by_cik.get(c)]
    both_with_ticker = [c for c in both if tickers_by_cik.get(c)]
    print(f"\n外国发行人里有美股代码的                  {len(with_ticker):>6,} 家"
          "  ←← 这才是能直接接进现有数据模型的候选池")
    print(f"其中同时报 Form SD 的                      {len(both_with_ticker):>6,} 家"
          "  ←← 这些加进来同时带节点和边")

    print("\n── 外国发行人里报 Form SD 的，逐家列出 ────────────────────────")
    if not both:
        print("一家都没有。**那就意味着扩池只增加孤立节点，不增加边**，")
        print("先解决边的来源再谈扩池——这是个真结论，不是失败。")
    for cik in both[:120]:
        codes = "/".join(tickers_by_cik.get(cik, [])) or "—"
        exch = "/".join(sorted(set(exch_by_cik.get(cik, [])))) or "—"
        print(f"  {codes:<10} {exch:<10} {foreign[cik]['name'][:44]:<44}"
              f"  SD {sd[cik]['last']}  CIK {cik}")
    if len(both) > 120:
        print(f"  …另有 {len(both) - 120} 家")

    # 国别与交易所：按 EDGAR 自己填的字段统计，不按我以为的。
    print("\n── 国别与交易所（抽样查 submissions） ─────────────────────────")
    sample = sorted(set(both_with_ticker) | set(with_ticker[:MAX_SUBMISSIONS]))
    sample = sample[:MAX_SUBMISSIONS]
    countries: dict[str, int] = {}
    exchanges: dict[str, int] = {}
    sic_desc: dict[str, int] = {}
    detail: dict[int, dict] = {}
    failed = 0
    print(f"抽 {len(sample)} 家（上限 {MAX_SUBMISSIONS}），逐家取 submissions")
    for cik in sample:
        try:
            meta = _get_json(SUBMISSIONS_URL.format(cik=cik))
            time.sleep(GAP)
        except Exception:                          # noqa: BLE001
            failed += 1
            continue
        biz = (meta.get("addresses") or {}).get("business") or {}
        country = (biz.get("stateOrCountryDescription")
                   or meta.get("stateOfIncorporationDescription")
                   or meta.get("stateOfIncorporation") or "未填")
        countries[country] = countries.get(country, 0) + 1
        for name in meta.get("exchanges") or []:
            exchanges[str(name)] = exchanges.get(str(name), 0) + 1
        desc = str(meta.get("sicDescription") or "未填")
        sic_desc[desc] = sic_desc.get(desc, 0) + 1
        detail[cik] = {"country": country, "sic": meta.get("sic"),
                       "sicDescription": desc,
                       "tickers": meta.get("tickers") or [],
                       "exchanges": meta.get("exchanges") or []}
    print(f"取到 {len(sample) - failed} 家，失败 {failed} 家\n")
    print("国别（按 EDGAR 营业地址国别）：")
    for country, count in sorted(countries.items(), key=lambda kv: -kv[1])[:30]:
        print(f"    {count:>4}  {country}")
    print("\n交易所：")
    for name, count in sorted(exchanges.items(), key=lambda kv: -kv[1])[:12]:
        print(f"    {count:>4}  {name}")
    print("\n行业（SIC 描述，前 20）：")
    for desc, count in sorted(sic_desc.items(), key=lambda kv: -kv[1])[:20]:
        print(f"    {count:>4}  {desc}")

    print("\n── 点名的公司在不在，报什么表 ─────────────────────────────────")
    cik_by_ticker: dict[str, int] = {}
    for cik, codes in tickers_by_cik.items():
        for code in codes:
            cik_by_ticker.setdefault(code.upper(), cik)
    named_rows = []
    for ticker, zh in NAMED_TICKERS:
        cik = cik_by_ticker.get(ticker.upper())
        if not cik:
            print(f"[XX] {ticker:<6} {zh:<10} 全量登记名录里没有这个代码")
            named_rows.append({"ticker": ticker, "zh": zh, "cik": None})
            continue
        forms = sorted(foreign.get(cik, {}).get("forms") or [])
        has_sd = cik in sd_ciks
        mark = "!!" if has_sd else "--"
        note = f"报 SD（{sd[cik]['last']}）" if has_sd else "扫描期内没报 SD"
        print(f"[{mark}] {ticker:<6} {zh:<10} CIK {cik:<9} "
              f"{'/'.join(forms) or '扫描期内没报 20-F/40-F':<22} {note}")
        named_rows.append({"ticker": ticker, "zh": zh, "cik": cik,
                           "forms": forms, "formSd": has_sd,
                           "sdDate": sd[cik]["last"] if has_sd else None})

    print("\n── SEC 够不到的（按公司名在全量登记名录里搜） ─────────────────")
    print("这不是抓取失败，是这条路的硬上限：不在美上市就不在 EDGAR。\n")
    for needle, zh in NAMED_SEARCH:
        hits = [(c, n, t) for c, n, t in name_index if needle in n][:4]
        if hits:
            for cik, name, ticker in hits:
                tag = "报 SD" if cik in sd_ciks else "无 SD"
                print(f"[--] {zh:<10} {name[:46]:<46} {ticker or '—':<8} CIK {cik} {tag}")
        else:
            print(f"[XX] {zh:<10} 名录里搜不到「{needle}」——SEC 母池够不到这家")

    # 有 SD 不等于 SD 里有名单。抽几家把申报目录原样列出来给人看。
    print("\n── 抽查：外国发行人的 SD 申报里有没有冲突矿产报告附件 ─────────")
    print("有 SD ≠ SD 里有名单。特斯拉那份 42KB 只写流程不列名单，实测确认过。\n")
    doc_rows = []
    for cik in both_with_ticker[:MAX_DOC_LISTS]:
        base = accession_dir(cik, sd[cik]["path"])
        if not base:
            print(f"[XX] CIK {cik} 归档路径推不出目录：{sd[cik]['path']}")
            continue
        try:
            payload = _get_json(base + "index.json")
            time.sleep(GAP)
        except Exception as exc:                   # noqa: BLE001
            print(f"[XX] CIK {cik} 取目录失败：{_why(exc)}")
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
        codes = "/".join(tickers_by_cik.get(cik, [])) or str(cik)
        kept = [r for r in rows if r[2] is None and r[1] > 8192]
        print(f"[{'!!' if kept else '--'}] {codes:<10} {foreign[cik]['name'][:40]:<40}"
              f" SD {sd[cik]['last']}  会读的实质文件 {len(kept)} 份")
        for name, size, why in rows[:6]:
            tag = f"跳过（{why}）" if why else "会读"
            print(f"         {size // 1024:>6}KB  {tag:<18} {name}")
        print(f"         {base}")
        doc_rows.append({"cik": cik, "tickers": tickers_by_cik.get(cik, []),
                         "readable": len(kept), "indexUrl": base})

    print("\n── 结论要人来下 ───────────────────────────────────────────────")
    print("这个探针只报三个数，不替人做判断：")
    print(f"  1. 许可干净的外国发行人母池有多大        {len(with_ticker):,} 家（有美股代码）")
    print(f"  2. 其中带边进来的有多少                  {len(both_with_ticker):,} 家（同时报 SD）")
    print(f"  3. 覆盖多少个国别                        {len(countries)} 个（抽样口径）")
    print("\n第 2 个数是决定性的。它大，扩池就同时长节点和边；它小，")
    print("扩池只是给图上加孤立的点——那得先解决边的来源，不是先扩池。")
    print("\n另外：上面「会读的实质文件 N 份」只说明文件层面，不说明里面真有名单。")
    print("要判断名单在不在，得点开归档地址看原文——这一步由人做。")

    if OUTPUT:
        os.makedirs(os.path.dirname(OUTPUT) or ".", exist_ok=True)
        report = {
            "generatedAt": today.isoformat(),
            "quarters": [{k: v for k, v in s.items()} for s in quarter_stats],
            "counts": {
                "foreignAnnualFilers": len(foreign_ciks),
                "foreignInterimFilers": len(interim),
                "formSdFilers": len(sd_ciks),
                "foreignAndFormSd": len(both),
                "foreignWithTicker": len(with_ticker),
                "foreignWithTickerAndFormSd": len(both_with_ticker),
            },
            "foreignFormSdFilers": [
                {"cik": c, "name": foreign[c]["name"],
                 "tickers": tickers_by_cik.get(c, []),
                 "exchanges": sorted(set(exch_by_cik.get(c, []))),
                 "sdDate": sd[c]["last"],
                 "country": (detail.get(c) or {}).get("country")}
                for c in both
            ],
            "countries": countries,
            "exchanges": exchanges,
            "named": named_rows,
            "sdDocumentSamples": doc_rows,
        }
        with open(OUTPUT, "w", encoding="utf-8") as handle:
            json.dump(report, handle, ensure_ascii=False, indent=2, sort_keys=True)
        print(f"\n报告写入 {OUTPUT}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
