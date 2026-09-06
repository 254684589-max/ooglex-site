#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""取报 10-K 的美国本土发行人（标普 500 之外的那些），写 domestic.json。

## 为什么是这一批

2026-09-06 的探针（supply_chain_probe run 34）数出来：

    报 10-K 的美国本土发行人   6,467 家（去重 CIK）
        其中有美股代码          4,884 家
    报 20-F／40-F 的外国发行人  1,222 家 → 有代码 1,193 家
    两者合计（去重）            6,076 家 ← SEC 这条路的上限

板块此前收 1,688 家（标普 495 + 外国发行人 1,193）。外国发行人那条路**已经
取尽**，真正没动的就是这一批。

**它比「按标普成分收」许可更干净。** 标普 500 成分名单是指数商的专有数据
（站内用的是公开镜像），而 10-K 全量是 EDGAR 政府公开记录，与现有管线同源。
范围更大、许可更稳，没有理由不收。

## 排除什么

只排一类：**SIC 6770 空白支票公司**。SPAC 在定义上就不是经营实体，没有产品、
没有供应链，放进产业链图上只是噪音。这是按行业码排除，不是按公司名挑——
排除规则写在这里，谁都能复核。

没有 SIC 的也不收：环节与产业链全靠 SIC 判，判不出来的进来就是一个无归属的
孤点。**这不是「数据缺失」，是「这家公司接不进这个模型」**，两者要分清。

## 与标普池的关系

标普那 495 家**本来就是这一批的子集**，它们已经在池子里、而且有站内报价与
板块分类。这里按 CIK 与代码双重跳过，绝不覆盖——覆盖会让一家有行情的公司
变成没行情的。

## 合规

SEC 要求声明身份的 User-Agent 并限速每秒 10 次，本脚本间隔远低于上限。
取数失败保留上一份缓存，不用空值覆盖——与另外两个取数脚本同一条规矩。
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import date, datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from edgar_index import (                          # noqa: E402
    GAP, INDEX_URL, SD_FORMS, SUBMISSIONS_URL, TICKERS_EXCHANGE_URL,
    _get_json, _why, parse_index_line, recent_quarters, stream_lines,
)
import edgar_region as region                      # noqa: E402

US_ANNUAL = {"10-K", "10-K/A", "10-KSB"}
SP500_PATH = "apps/companies/sp500.json"
FOREIGN_PATH = "apps/supply-chain/foreign.json"
OUT_PATH = "apps/supply-chain/domestic.json"
CONTRACT_VERSION = 1

# 空白支票公司（SPAC）。定义上不是经营实体，没有产品也没有供应链。
BLANK_CHECK_SIC = {6770}

_EXCHANGE_RANK = {"nyse": 0, "nasdaq": 1, "cboe": 2, "nyse american": 3, "otc": 8}


def exchange_rank(name: str) -> int:
    return _EXCHANGE_RANK.get(str(name or "").strip().lower(), 9)


def pick_primary(candidates: list[dict], taken: set) -> dict | None:
    """从同一个 CIK 的多个代码里选主代码。排序完全由数据决定，与输入顺序无关。"""
    ordered = sorted(
        candidates,
        key=lambda c: (exchange_rank(c.get("exchange")), len(c["ticker"]), c["ticker"]))
    for item in ordered:
        if item["ticker"] not in taken:
            return item
    return None


def scan(quarters: list[tuple[int, int]]) -> tuple[dict, set, list]:
    """扫季度全量索引，收 10-K 申报人与报 SD 的 CIK。"""
    filers: dict[int, dict] = {}
    sd_ciks: set = set()
    stats = []
    for year, quarter in quarters:
        st = {"quarter": f"{year}QTR{quarter}", "rows": 0, "unparsed": 0,
              "bytes": 0, "gzip": False}
        try:
            for line in stream_lines(INDEX_URL.format(year=year, quarter=quarter), st):
                if not line.strip():
                    continue
                row = parse_index_line(line)
                if row is None:
                    st["unparsed"] += 1
                    continue
                st["rows"] += 1
                if row["form"] in US_ANNUAL:
                    entry = filers.setdefault(row["cik"], {"name": row["name"], "last": ""})
                    if row["date"] > entry["last"]:
                        entry.update({"last": row["date"], "name": row["name"]})
                elif row["form"] in SD_FORMS:
                    sd_ciks.add(row["cik"])
        except Exception as exc:                   # noqa: BLE001
            st["error"] = _why(exc)
            print(f"[XX] {st['quarter']} 取不到：{st['error']}")
        else:
            print(f"[--] {st['quarter']}  {st['rows']:>7,} 行"
                  f"  下载 {st['bytes'] // 1048576:>3}MB"
                  f"  10-K 申报人累计 {len(filers):>6,} 家")
        stats.append(st)
        time.sleep(GAP)
    return filers, sd_ciks, stats


def load_taken() -> tuple[set, set]:
    """已被占用的代码与 CIK：标普池 + 外国发行人池。绝不覆盖它们。"""
    tickers: set = set()
    ciks: set = set()
    try:
        with open(SP500_PATH, encoding="utf-8") as handle:
            for m in (json.load(handle).get("members") or []):
                if m.get("symbol"):
                    tickers.add(str(m["symbol"]).upper())
                if m.get("cik"):
                    ciks.add(int(m["cik"]))
    except (OSError, ValueError, TypeError):
        pass
    try:
        with open(FOREIGN_PATH, encoding="utf-8") as handle:
            for v in ((json.load(handle) or {}).get("companies") or {}).values():
                if v.get("symbol"):
                    tickers.add(str(v["symbol"]).upper())
                if v.get("cik"):
                    ciks.add(int(v["cik"]))
    except (OSError, ValueError, TypeError):
        pass
    return tickers, ciks


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quarters", type=int, default=4)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    quarters = recent_quarters(date.today(), args.quarters)
    print(f"扫 {args.quarters} 个季度：" + "、".join(f"{y}Q{q}" for y, q in quarters))
    filers, sd_ciks, stats = scan(quarters)
    if not any("error" not in s for s in stats):
        print("[XX] 一个季度的索引都没取到，保留上一份缓存")
        return 1
    print(f"\n报 10-K 的 {len(filers):,} 家 · 同期报 SD 的 {len(sd_ciks):,} 家")

    try:
        payload = _get_json(TICKERS_EXCHANGE_URL)
    except Exception as exc:                       # noqa: BLE001
        print(f"[XX] 全量登记名录取不到：{_why(exc)}；保留上一份缓存")
        return 1
    idx = {name: i for i, name in enumerate(payload.get("fields") or [])}
    by_cik: dict[int, list] = {}
    for row in payload.get("data") or []:
        try:
            cik = int(row[idx["cik"]])
            ticker = str(row[idx["ticker"]] or "")
        except (KeyError, IndexError, TypeError, ValueError):
            continue
        if not ticker:
            continue
        by_cik.setdefault(cik, []).append(
            {"ticker": ticker.upper(),
             "exchange": str(row[idx["exchange"]] or "") if "exchange" in idx else ""})

    taken_tickers, taken_ciks = load_taken()
    if not taken_tickers:
        print("[XX] 读不到标普与外国发行人池，无法检出重复，中止——"
              "撞码会让一家有行情的公司变成没行情的")
        return 1
    print(f"已占用：代码 {len(taken_tickers):,} 个 · CIK {len(taken_ciks):,} 个")

    chosen: list[dict] = []
    skipped = {"already": 0, "no_ticker": 0, "collision": 0}
    for cik in sorted(filers):
        if cik in taken_ciks:
            skipped["already"] += 1
            continue
        candidates = by_cik.get(cik) or []
        if not candidates:
            skipped["no_ticker"] += 1
            continue
        picked = pick_primary(candidates, taken_tickers)
        if not picked:
            skipped["collision"] += 1
            continue
        taken_tickers.add(picked["ticker"])
        chosen.append({"cik": cik, "primary": picked, "candidates": candidates})

    print(f"待取 {len(chosen):,} 家（已在池中 {skipped['already']:,} · "
          f"无代码 {skipped['no_ticker']:,} · 代码全撞 {skipped['collision']:,}）")
    if args.limit:
        chosen = chosen[:args.limit]

    metas: list[tuple[dict, dict]] = []
    failed = 0
    print(f"\n逐家取 submissions（{len(chosen):,} 家，约 "
          f"{len(chosen) * GAP / 60:.0f} 分钟）")
    for i, item in enumerate(chosen, 1):
        try:
            metas.append((item, _get_json(SUBMISSIONS_URL.format(cik=item["cik"]))))
            time.sleep(GAP)
        except Exception:                          # noqa: BLE001
            failed += 1
        if i % 500 == 0:
            print(f"     …{i:,}/{len(chosen):,}")

    code_map = region.build_code_map(
        pair for _, meta in metas for pair in region.address_pairs(meta))

    companies: dict[str, dict] = {}
    dropped = {"blank_check": 0, "no_sic": 0}
    for item, meta in metas:
        sic = int(meta["sic"]) if str(meta.get("sic") or "").isdigit() else None
        if sic is None:
            # 环节与产业链全靠 SIC 判。判不出来的进来就是一个无归属的孤点——
            # 这不是「数据缺失」，是「这家接不进这个模型」。
            dropped["no_sic"] += 1
            continue
        if sic in BLANK_CHECK_SIC:
            dropped["blank_check"] += 1
            continue
        symbol = item["primary"]["ticker"]
        place = region.resolve_country(meta, code_map)
        operating = region.operating_location(meta, code_map)
        companies[symbol] = {
            "symbol": symbol,
            "cik": int(item["cik"]),
            "name": (meta.get("name") or filers[item["cik"]]["name"] or symbol).strip(),
            "sic": sic,
            "sicDescription": meta.get("sicDescription"),
            "country": place["country"],
            "region": place["region"],
            "countryBasis": place["countryBasis"],
            "countryCode": place["countryCode"],
            "offshoreIncorporation": region.is_offshore(place["country"]),
            "operatingCountry": operating["country"],
            "operatingRegion": operating["region"],
            "operatingBasis": operating["basis"],
            "exchange": item["primary"].get("exchange"),
            "tickers": sorted({c["ticker"] for c in item["candidates"]}),
            # ── 规模：SEC 自己的申报人类别 ────────────────────────────────
            # 扩到 5,897 家之后站内报价只覆盖 495 家（8%），逐环节 4%~22%——
            # 板块分不出苹果和一家 500 万美元的壳公司，而每个环节卡上的家数
            # 把它们算得一样重。
            #
            # `category` 是 SEC 按**公众持股量**给的监管分档
            # （Large accelerated ≥7 亿美元 / Accelerated 0.75~7 亿 /
            #  Non-accelerated / Smaller reporting），**100% 覆盖、政府公开
            # 记录、零许可问题**——正是市值给不了的那条轴。
            #
            # 它不是市值：分档按公众持股量（流通股 × 股价）而非总市值，且
            # 一年只在财年末重定一次。页面必须照实说是「申报人类别」，
            # 不能当成市值区间来用。
            "filerCategory": (meta.get("category") or "").strip() or None,
            "entityType": (meta.get("entityType") or "").strip() or None,
            "annualForm": "10-K",
            "lastAnnual": filers[item["cik"]]["last"],
            "filesFormSd": item["cik"] in sd_ciks,
        }
    sd_yes = sum(1 for v in companies.values() if v.get("filesFormSd"))
    print(f"\n收录 {len(companies):,} 家 · submissions 失败 {failed} 家")
    print(f"  排除：空白支票公司（SIC 6770）{dropped['blank_check']:,} 家 · "
          f"无 SIC {dropped['no_sic']:,} 家")
    print(f"  其中报 Form SD 的 {sd_yes} 家——不报的那些结构上不会有冶炼厂边")

    from collections import Counter as _C
    _cat = _C(v.get("filerCategory") or "未标注" for v in companies.values())
    print("申报人类别（SEC 按公众持股量分档）："
          + "、".join(f"{k} {v}" for k, v in _cat.most_common()))
    from collections import Counter
    top = Counter(v.get("sicDescription") or "未标注" for v in companies.values())
    print("  行业前 8：" + "、".join(f"{k[:22]} {v}" for k, v in top.most_common(8)))

    previous = {}
    try:
        with open(OUT_PATH, encoding="utf-8") as handle:
            previous = json.load(handle) or {}
    except (OSError, ValueError):
        pass
    prior = previous.get("companies") or {}
    if prior and len(companies) < 0.6 * len(prior):
        print(f"[XX] 本轮 {len(companies)} 家不足既有 {len(prior)} 家的 60%，"
              "判定取数异常，保留现有缓存不覆盖")
        return 1

    out = {
        "contractVersion": CONTRACT_VERSION,
        "dataset": "supply-chain-domestic-filers",
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": "SEC EDGAR 季度全量索引 + submissions（公共领域）",
        "note": ("报 10-K 的美国本土发行人中，标普 500 之外的那些。"
                 "标普那批本来就是这一批的子集，已在池中、且有站内报价，按 CIK 与代码"
                 "双重跳过，绝不覆盖。排除 SIC 6770 空白支票公司（定义上不是经营实体）"
                 "与没有 SIC 的（环节与产业链判不出来，接不进模型）。"
                 "**这一池只增加节点、不增加关系边**——Form SD 是冶炼厂边的唯一来源，"
                 "逐家由 filesFormSd 标出；公司家数变多不表示关系覆盖变好。"),
        "coverage": {
            "annualFilers": len(filers),
            "alreadyInPool": skipped["already"],
            "skippedNoTicker": skipped["no_ticker"],
            "skippedTickerCollision": skipped["collision"],
            "attempted": len(chosen),
            "published": len(companies),
            "droppedBlankCheck": dropped["blank_check"],
            "droppedNoSic": dropped["no_sic"],
            "submissionsFailed": failed,
            "publishedFilesFormSd": sd_yes,
        },
        "quarters": [dict(s) for s in stats],
        "companies": companies,
    }
    if args.dry_run:
        print("\ndry-run：未写文件。抽样：")
        for symbol in list(companies)[:12]:
            r = companies[symbol]
            print(f"  {symbol:<7} {str(r['name'])[:38]:<38} SIC {r['sic']} {r['country']}")
        return 0

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as handle:
        json.dump(out, handle, ensure_ascii=False, indent=2, sort_keys=True)
    print(f"\n{len(companies):,} 家 → {OUT_PATH}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
