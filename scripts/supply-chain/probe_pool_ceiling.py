#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""探针：SEC 这条路最多能扩到多少家公司，中文名有没有许可干净的源。

## 问题一：上限在哪

板块现在 1,688 家 = 标普 495 + 外国私人发行人 1,193。后者已经取尽
（1,222 家报 20-F／40-F，1,194 家有代码），**这条路走完了**。

真正没动过的是**美国本土发行人**：报 10-K 的那一批。它与外国发行人同源，
都是 EDGAR 上的政府公开记录，没有任何许可问题——而标普 500 成分名单反倒是
指数商的专有数据（站内用的是公开镜像）。所以「按 10-K 全量收」既比「按指数
成分收」范围大得多，许可上也更干净。

这个探针数三件事，全部按**去重后的 CIK**：

    报 10-K 的有多少家 · 其中有美股代码的有多少家 · 与现有池子重叠多少

## 问题二：中文名

1,688 家里 1,355 家显示英文原名。**其中 326 家经营地在两岸三地**——
ATA Creativity 的中文名是「全美在线」、Ascentage Pharma 是「亚盛医药」，
这些是公司自己的注册名，不是翻译。缺的是**源**，不是翻译能力。

板块的规矩是「给不出可靠译名就显示英文原文，不半译不硬造」。要突破它，
需要一个**权威且许可干净**的中文名来源。这个探针检查一条：SEC 备案本身
带不带中文名——如果 20-F 封面或 submissions 元数据里就有，那是政府公开
记录，与现有管线同源，许可上没有任何问题。

**探完的正确结局有可能是「没有源、不做」。** 前几轮 P1 与 P4 都是这么收的。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from edgar_index import (                          # noqa: E402
    FOREIGN_ANNUAL, GAP, INDEX_URL, SUBMISSIONS_URL, TICKERS_EXCHANGE_URL,
    _get_json, _why, parse_index_line, recent_quarters, stream_lines,
)

US_ANNUAL = {"10-K", "10-K/A", "10-KSB"}
SP500_PATH = "apps/companies/sp500.json"
FOREIGN_PATH = "apps/supply-chain/foreign.json"

# 中文字符（含扩展 A 区）。判「这份备案里有没有中文」用它就够，
# 不必引入分词——我们要的是「有没有」，不是「是什么」。
_CJK = re.compile(r"[一-鿿㐀-䶿]")


def scan(quarters):
    """扫季度全量索引，按年报表种收集 CIK。"""
    us: dict[int, str] = {}
    foreign: dict[int, str] = {}
    stats = []
    for year, quarter in quarters:
        st = {"quarter": f"{year}QTR{quarter}", "rows": 0, "bytes": 0, "gzip": False}
        try:
            for line in stream_lines(INDEX_URL.format(year=year, quarter=quarter), st):
                row = parse_index_line(line)
                if row is None:
                    continue
                st["rows"] += 1
                if row["form"] in US_ANNUAL:
                    us.setdefault(row["cik"], row["name"])
                elif row["form"] in FOREIGN_ANNUAL:
                    foreign.setdefault(row["cik"], row["name"])
        except Exception as exc:                   # noqa: BLE001
            st["error"] = _why(exc)
            print(f"[XX] {st['quarter']} 取不到：{st['error']}")
        else:
            print(f"[--] {st['quarter']}  {st['rows']:>7,} 行  "
                  f"下载 {st['bytes'] // 1048576:>3}MB  "
                  f"10-K {len(us):>6,} 家 · 20-F/40-F {len(foreign):>5,} 家（累计去重）")
        stats.append(st)
    return us, foreign, stats


def load_json(path, key=None):
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle) or {}
        return data.get(key) if key else data
    except (OSError, ValueError):
        return {}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quarters", type=int, default=4)
    ap.add_argument("--zh-sample", type=int, default=25,
                    help="抽多少家两岸三地公司查 submissions 里有没有中文名")
    args = ap.parse_args()

    quarters = recent_quarters(date.today(), args.quarters)
    print("═══ 问题一：SEC 这条路的公司数上限 ═══\n")
    print(f"扫 {args.quarters} 个季度：" + "、".join(f"{y}Q{q}" for y, q in quarters))
    us, foreign, stats = scan(quarters)
    if not any("error" not in s for s in stats):
        print("[XX] 一个季度都没取到，无法作答")
        return 1

    try:
        payload = _get_json(TICKERS_EXCHANGE_URL)
    except Exception as exc:                       # noqa: BLE001
        print(f"[XX] 全量登记名录取不到：{_why(exc)}")
        return 1
    fields = payload.get("fields") or []
    idx = {name: i for i, name in enumerate(fields)}
    ticker_ciks: set = set()
    for row in payload.get("data") or []:
        try:
            if row[idx["ticker"]]:
                ticker_ciks.add(int(row[idx["cik"]]))
        except (KeyError, IndexError, TypeError, ValueError):
            continue

    sp = {m.get("symbol") for m in (load_json(SP500_PATH, "members") or [])}
    fi = load_json(FOREIGN_PATH, "companies") or {}
    have_ciks = {int(v["cik"]) for v in fi.values() if v.get("cik")}

    us_t = {c for c in us if c in ticker_ciks}
    fo_t = {c for c in foreign if c in ticker_ciks}
    print(f"""
    报 10-K 的美国本土发行人      {len(us):>7,} 家（去重 CIK）
        其中有美股代码             {len(us_t):>7,} 家  ← 能接进以 ticker 为键的模型
    报 20-F／40-F 的外国发行人    {len(foreign):>7,} 家
        其中有美股代码             {len(fo_t):>7,} 家
    ─────────────────────────────────────────────
    两者合计（有代码、去重）       {len(us_t | fo_t):>7,} 家  ← **这就是上限**

    现在板块收了                  {len(sp) + len(fi):>7,} 家
        标普成分股                 {len(sp):>7,} 家（是 10-K 那一批的子集）
        外国私人发行人             {len(fi):>7,} 家（这条路已取尽）
    还能扩出来                    {len(us_t | fo_t) - len(sp) - len(fi):>7,} 家
    """)
    print("说明：标普 500 成分名单是指数商的专有数据（站内用的是公开镜像），")
    print("      而按 10-K 全量收是 EDGAR 政府公开记录——**范围更大，许可更干净**。")
    print("      够不到的仍然够不到：不在美上市就不在 EDGAR（三星、LVMH、现代）。\n")

    print("═══ 问题二：SEC 备案里带不带中文名 ═══\n")
    zh_targets = [(s, v) for s, v in fi.items()
                  if v.get("operatingCountry") in ("China", "Hong Kong", "Taiwan")][:args.zh_sample]
    if not zh_targets:
        print("[--] foreign.json 里没有带 operatingCountry 的记录，跳过")
        return 0
    print(f"抽 {len(zh_targets)} 家经营地在两岸三地的公司，查 submissions 元数据：\n")
    hit = 0
    import time
    for symbol, row in zh_targets:
        try:
            meta = _get_json(SUBMISSIONS_URL.format(cik=int(row["cik"])))
            time.sleep(GAP)
        except Exception as exc:                   # noqa: BLE001
            print(f"  [XX] {symbol:<7} 取不到：{_why(exc)}")
            continue
        # 元数据里所有字符串字段拼起来找中文
        blob = json.dumps({k: v for k, v in meta.items()
                           if k not in ("filings",)}, ensure_ascii=False)
        found = _CJK.findall(blob)
        former = [f.get("name") for f in (meta.get("formerNames") or [])]
        if found:
            hit += 1
            print(f"  [OK] {symbol:<7} {str(meta.get('name'))[:34]:<34} 含中文字符 "
                  f"{len(found)} 个：{''.join(found[:12])}")
        else:
            print(f"  [--] {symbol:<7} {str(meta.get('name'))[:34]:<34} 无中文"
                  + (f"（曾用名 {former[0][:24]}）" if former else ""))
    print(f"\n结论：{len(zh_targets)} 家里 {hit} 家的 SEC 元数据带中文字符。")
    if hit == 0:
        print("      **SEC 元数据这条路不通**——它只存英文法定名称。要拿官方中文名")
        print("      得另找源，而那多半是交易所或数据商的数据，属于许可决策，")
        print("      按规矩交给项目所有者定，不自行接入。")
    else:
        print("      有中文的那几家值得逐份看清是名称还是别的字段，再决定能不能用。")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
