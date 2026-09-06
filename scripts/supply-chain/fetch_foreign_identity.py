#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""取 SEC 外国私人发行人的实体标识，写 apps/supply-chain/foreign.json。

## 为什么是这一批公司

板块的目标是全球产业链，公司池却一直是标普 500——单一国家指数。ASML、台积电、
索尼、丰田、必和必拓、力拓一家都不在，而半导体链上没有 ASML 和台积电根本
画不出来。

母池的第一候选 MSCI ACWI 与 S&P Global 1200 **走不通，但不是技术原因**：
成分股名单是指数商的专有数据，不公开发布、再分发要授权，与仓库此前因许可放弃的
SPX／DXY／LBMA 定盘价同类（见 docs/SUPPLY_CHAIN_SOURCES.md 第 2 节）。

许可干净的替代是 SEC 自己：外国私人发行人在美上市要报 20-F（非加拿大）或
40-F（加拿大 MJDS），文件全在 EDGAR，公共领域，与现有管线同源。

## 从「只收 147 家」改为全收（2026-09-06，项目所有者授权）

2026-09-05 的探针数出来：1,222 家报 20-F／40-F，其中 1,194 家有美股代码，
**147 家同时报 Form SD**。当初只收那 147 家，理由是——

    扩公司范围只增加节点，不增加边。图上多 500 个孤立的点不叫产业链。

**这条判决现在推翻，但推翻的不是它的事实，是它的前提。** 事实一点没变：
多收的那一千余家确实一条边都不会带来，「有出处」的比例会从 127/642（19.8%）
掉到 127/1,689（7.5%）。摆给项目所有者看过这个数之后，授权照做。

之所以可以做，是因为那句话真正怕的是**读者把点数当成关系覆盖**。
只要页面把「家数」与「有出处」分开说死、并且把分档理由写在看得见的地方，
多出来的点就只是一份更全的公司名录，不会被读成产业链关系。

**因此这个改动是有附带条件的，条件不成立就得改回去：**

一、`formSdStatus` 必须逐家给到，`no-filing` 这一档不能变成一个笼统的空白；
二、环节卡上的「N/M 有出处」旁边必须有**可见的**分档说明（不是 hover 提示，
   手机上没有 hover）；
三、页面任何位置不得把节点数增长表述为关系覆盖改善。

这三条由 `validate_supply_chain_graph.py` 与 `validate_supply_chain_page.mjs`
钉住，不靠自觉。

**够不到的仍然够不到：** 三星、LVMH、现代不在 EDGAR，不在美上市就不在 EDGAR。
扩到 1,194 家也补不上这一块，不能因为池子大了就说板块覆盖全球。

## 三件必须做对的事

一、**按 CIK 去重。** 同一家公司有多个代码（ASML/ASMLF、BABA/BABAF/BBAAY
   指向同一个 CIK），不去重的话同一家会在图上出现三次。
二、**主代码要选得稳。** 按交易所优先级（NYSE > Nasdaq > CBOE > OTC）再按
   代码长度与字典序，同一份输入永远得到同一个结果。
三、**与标普池的代码冲突要检出。** 撞了就换下一个代码；全撞就跳过这家并报出来，
   **绝不覆盖标普那一侧**——那会让一家美国公司的数据悄悄变成另一家外国公司的。

## 合规

SEC 要求声明身份的 User-Agent 并限速每秒 10 次，本脚本间隔远低于上限，
联系方式从环境变量读取，不硬编码任何个人邮箱。取数失败保留上一份缓存，
不用空值覆盖——与 fetch_company_identity.py 同一条规矩。
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
    FOREIGN_ANNUAL, GAP, INDEX_URL, SD_FORMS, SUBMISSIONS_URL,
    TICKERS_EXCHANGE_URL, _get_json, _why, parse_index_line,
    recent_quarters, stream_lines,
)
import edgar_region as region                      # noqa: E402

SP500_PATH = "apps/companies/sp500.json"
OUT_PATH = "apps/supply-chain/foreign.json"
CONTRACT_VERSION = 1

# 交易所优先级：主板挂牌的代码比 OTC 的粉单代码更适合当主代码。
# 数字小的优先，认不出的排最后。
_EXCHANGE_RANK = {"nyse": 0, "nasdaq": 1, "cboe": 2, "nyse american": 3, "otc": 8}


def exchange_rank(name: str) -> int:
    return _EXCHANGE_RANK.get(str(name or "").strip().lower(), 9)


def pick_primary(candidates: list[dict], taken: set) -> dict | None:
    """从同一个 CIK 的多个代码里选主代码。

    `candidates` 每项是 {"ticker", "exchange"}；`taken` 是已被占用的代码
    （标普池 + 已选定的外国发行人）。排序完全由数据决定，不看输入顺序——
    同一份输入必须永远得到同一个结果，否则每次重跑都会换一批主代码。
    """
    ordered = sorted(
        candidates,
        key=lambda c: (exchange_rank(c.get("exchange")),
                       len(str(c.get("ticker") or "")),
                       str(c.get("ticker") or "")),
    )
    for item in ordered:
        ticker = str(item.get("ticker") or "").upper()
        if ticker and ticker not in taken:
            return {"ticker": ticker, "exchange": item.get("exchange")}
    return None


def scan_index(quarters: list[tuple[int, int]]) -> tuple[dict, set, list]:
    """扫季度全量索引，返回（外国发行人年报申报人, 报 SD 的 CIK, 每季统计）。"""
    foreign: dict[int, dict] = {}
    sd_ciks: set = set()
    stats_all = []
    for year, quarter in quarters:
        stats = {"quarter": f"{year}QTR{quarter}", "rows": 0, "unparsed": 0,
                 "bytes": 0, "gzip": False}
        try:
            for line in stream_lines(INDEX_URL.format(year=year, quarter=quarter), stats):
                if not line.strip():
                    continue
                row = parse_index_line(line)
                if row is None:
                    stats["unparsed"] += 1      # 表头那几行本来就解析不了
                    continue
                stats["rows"] += 1
                form, cik = row["form"], row["cik"]
                if form in FOREIGN_ANNUAL:
                    entry = foreign.setdefault(cik, {"name": row["name"], "last": ""})
                    if row["date"] > entry["last"]:
                        entry.update({"last": row["date"], "name": row["name"]})
                elif form in SD_FORMS:
                    sd_ciks.add(cik)
        except Exception as exc:                   # noqa: BLE001
            stats["error"] = _why(exc)
            print(f"[XX] {stats['quarter']} 取不到：{stats['error']}")
        else:
            print(f"[--] {stats['quarter']}  {stats['rows']:>7,} 行"
                  f"  下载 {stats['bytes'] // 1048576:>3}MB"
                  f"  解析不了 {stats['unparsed']} 行")
        stats_all.append(stats)
        time.sleep(GAP)
    return foreign, sd_ciks, stats_all


def load_sp500_symbols() -> set:
    try:
        with open(SP500_PATH, encoding="utf-8") as handle:
            return {str(m.get("symbol") or "").upper()
                    for m in (json.load(handle).get("members") or []) if m.get("symbol")}
    except (OSError, ValueError):
        return set()


def cik_of(item: dict) -> int:
    return int(item["cik"])


def load_previous() -> dict:
    try:
        with open(OUT_PATH, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quarters", type=int, default=4,
                    help="回溯几个季度的全量索引")
    ap.add_argument("--dry-run", action="store_true",
                    help="只解析并打印，不写文件——上线前用它核对")
    ap.add_argument("--limit", type=int, default=0, help="最多取几家的 submissions")
    args = ap.parse_args()

    quarters = recent_quarters(date.today(), args.quarters)
    print(f"扫 {args.quarters} 个季度：" + "、".join(f"{y}Q{q}" for y, q in quarters))
    foreign, sd_ciks, stats = scan_index(quarters)
    if not any("error" not in s for s in stats):
        print("[XX] 一个季度的索引都没取到，保留上一份缓存")
        return 1

    sd_foreign = set(foreign) & sd_ciks
    # 全收：报 20-F／40-F 的都要，报不报 SD 只作标记。见文件开头那段判决。
    selected = sorted(foreign)
    print(f"\n外国发行人年报申报人 {len(foreign):,} 家 · 报 SD 的 {len(sd_ciks):,} 家"
          f" · 两者都有 {len(sd_foreign):,} 家")
    if not sd_foreign:
        # 交集为空说明 SD 那一侧根本没扫到。此时仍能产出节点，但每一家都会被
        # 标成「不报 SD」——那是**假数据**，比少一批公司糟得多，所以照样中止。
        print("[XX] 交集为空，与 2026-09-05 实测的 147 家差得太远，说明 SD 那侧没扫到；"
              "继续下去会把每一家都标成「不报 Form SD」，那是假数据。保留上一份缓存")
        return 1

    # 代码与交易所。没有代码的接不进以 ticker 为键的数据模型，只能先放着。
    try:
        payload = _get_json(TICKERS_EXCHANGE_URL)
    except Exception as exc:                       # noqa: BLE001
        print(f"[XX] 全量登记名录取不到：{_why(exc)}；保留上一份缓存")
        return 1
    fields = payload.get("fields") or []
    idx = {name: i for i, name in enumerate(fields)}
    by_cik: dict[int, list] = {}
    for row in payload.get("data") or []:
        try:
            cik = int(row[idx["cik"]])
        except (KeyError, IndexError, TypeError, ValueError):
            continue
        ticker = str(row[idx["ticker"]] or "") if "ticker" in idx else ""
        if not ticker:
            continue
        by_cik.setdefault(cik, []).append(
            {"ticker": ticker.upper(),
             "exchange": str(row[idx["exchange"]] or "") if "exchange" in idx else ""})

    sp500 = load_sp500_symbols()
    if not sp500:
        print("[XX] 读不到标普成分股清单，无法检出代码冲突，中止——"
              "撞码会让一家公司的数据悄悄变成另一家的")
        return 1

    taken = set(sp500)
    chosen: list[dict] = []
    no_ticker: list[int] = []
    collided: list[str] = []
    for cik in selected:
        candidates = by_cik.get(cik) or []
        if not candidates:
            no_ticker.append(cik)
            continue
        picked = pick_primary(candidates, taken)
        if not picked:
            # 全部代码都与标普池或已选定的撞了。宁可少收一家，也不覆盖既有节点。
            collided.append(f"CIK {cik}（{foreign[cik]['name']}）"
                            f"：{'/'.join(c['ticker'] for c in candidates)}")
            continue
        taken.add(picked["ticker"])
        chosen.append({"cik": cik, "primary": picked, "candidates": candidates})

    print(f"有代码可用 {len(chosen)} 家 · 无代码 {len(no_ticker)} 家 · "
          f"代码全撞标普池 {len(collided)} 家")
    for line in collided:
        print(f"  [!!] 跳过 {line}")

    if args.limit:
        chosen = chosen[:args.limit]

    # 逐家取 submissions：公司名、SIC、国别、交易所。与标普那侧同一套字段，
    # 这样节点构建不必为两个池写两套逻辑。
    metas: list[tuple[dict, dict]] = []          # (chosen item, submissions meta)
    failed = 0
    print(f"\n逐家取 submissions（{len(chosen)} 家）")
    for item in chosen:
        cik = item["cik"]
        try:
            meta = _get_json(SUBMISSIONS_URL.format(cik=cik))
            time.sleep(GAP)
        except Exception:                          # noqa: BLE001
            failed += 1
            continue
        metas.append((item, meta))

    # 先扫一遍全部结果，把 EDGAR 自己给出的「地区代码 ↔ 描述」收集成表，
    # 再拿它去补那些只有代码没有描述的公司（台积电、本田那一批）。
    # 表由数据长出来而不是我硬编：记错一个代码就是把一家公司放到别的国家去。
    code_map = region.build_code_map(
        pair for _, meta in metas for pair in region.address_pairs(meta))
    print(f"EDGAR 自带的地区代码表：{len(code_map)} 个代码带描述")

    companies: dict[str, dict] = {}
    for item, meta in metas:
        symbol = item["primary"]["ticker"]
        place = region.resolve_country(meta, code_map)
        companies[symbol] = {
            "symbol": symbol,
            "cik": cik_of(item),
            "name": (meta.get("name") or foreign[item["cik"]]["name"] or symbol).strip(),
            "sic": int(meta["sic"]) if str(meta.get("sic") or "").isdigit() else None,
            "sicDescription": meta.get("sicDescription"),
            # country 是国家，region 是它下面那一级（省／州）。曾经把
            # 「Ontario, Canada」整条当国别，加拿大在按国别的表里出现六次。
            "country": place["country"],
            "region": place["region"],
            # 这个结论是从哪个字段来的。注册地与营业地址的偏差方向不同，
            # 页面要照实标，不能让读者以为两者是一回事。
            "countryBasis": place["countryBasis"],
            "countryCode": place["countryCode"],
            # 被判定不可用的字段（例如「营业地址只说到美国某个州」）。
            # 留着是为了让「为什么这家没有国别」在数据里查得到，而不是只剩一个空值。
            "countryRejected": place.get("countryRejected"),
            "exchange": item["primary"].get("exchange"),
            "tickers": sorted({c["ticker"] for c in item["candidates"]}),
            "annualForm": "20-F/40-F",
            # 这家**结构上**可不可能有冶炼厂边：Form SD 是边的唯一来源，
            # 不报 SD 的公司没有边不是抽取失败，是规则根本不适用。
            # 页面靠这个字段把「没抽到」与「不可能有」分开说。
            "filesFormSd": item["cik"] in sd_foreign,
            "lastAnnual": foreign[item["cik"]]["last"],
        }
    sd_yes = sum(1 for v in companies.values() if v.get("filesFormSd"))
    print(f"取到 {len(companies)} 家，失败 {failed} 家"
          f"（其中报 Form SD {sd_yes} 家 · 不报 {len(companies) - sd_yes} 家——"
          f"不报的那些结构上不会有冶炼厂边）")

    # 定不出国别的，把 SEC 那几个字段的**原值**原样打出来。
    # 台积电、本田、沃达丰这一批三个字段全空，光看结论只能看出「没有」，
    # 看不出「SEC 到底写了什么」——不打出来就只能靠猜，而猜就是编。
    # 定不出国别的，把 SEC 那几个字段的**原值**连同地址块其余的键一起记进
    # 产出文件。台积电、本田、沃达丰这一批光看结论只能看出「没有」，
    # 看不出「SEC 到底写了什么」——不留原值就只能靠猜，而猜就是编。
    #
    # 写进数据而不是只打日志：Actions 的日志会过期、下载还受出网策略限制，
    # 而这问题要跨好几轮才查得清。留在文件里，谁都能直接查。
    unresolved_geo: dict[str, dict] = {}
    for item, meta in metas:
        if region.resolve_country(meta, code_map)["country"] is not None:
            continue
        addresses = meta.get("addresses") or {}
        biz = addresses.get("business") or {}
        mail = addresses.get("mailing") or {}
        unresolved_geo[item["primary"]["ticker"]] = {
            "name": meta.get("name"),
            "stateOfIncorporation": meta.get("stateOfIncorporation"),
            "stateOfIncorporationDescription": meta.get("stateOfIncorporationDescription"),
            "businessStateOrCountry": biz.get("stateOrCountry"),
            "businessStateOrCountryDescription": biz.get("stateOrCountryDescription"),
            "mailingStateOrCountry": mail.get("stateOrCountry"),
            "mailingStateOrCountryDescription": mail.get("stateOrCountryDescription"),
            # 境外那一套字段的**值**。上一版只存了键名，结果看得见
            # 「有 country 这个键」却看不见它写的是什么——等于只走到一半。
            "businessCountry": biz.get("country"),
            "businessCountryCode": biz.get("countryCode"),
            "businessForeignStateTerritory": biz.get("foreignStateTerritory"),
            "businessIsForeignLocation": biz.get("isForeignLocation"),
            "mailingCountry": mail.get("country"),
            # 地址块里还有哪些键。也许国别根本不在我读的那两个字段里。
            "businessKeys": sorted(biz),
            # submissions 顶层还有哪些看着像地理信息的键，同理。
            "metaKeys": sorted(k for k in meta
                               if any(w in k.lower()
                                      for w in ("state", "country", "address", "phone",
                                                "fiscal", "entity", "category"))),
        }
    if unresolved_geo:
        print(f"\n定不出国别的 {len(unresolved_geo)} 家，SEC 原值已写入产出文件的 "
              f"unresolvedGeo；抽样：")
        for ticker in sorted(unresolved_geo)[:4]:
            print(f"  {ticker}: {json.dumps(unresolved_geo[ticker], ensure_ascii=False)}")

    from collections import Counter
    basis_count = Counter(v.get("countryBasis") or "未标注" for v in companies.values())
    print("国别取自：" + "、".join(f"{k} {v} 家" for k, v in basis_count.most_common()))
    top = Counter(v.get("country") or "未标注" for v in companies.values())
    print("国别分布：" + "、".join(f"{k} {v}" for k, v in top.most_common(10)))

    previous = load_previous()
    prior = previous.get("companies") or {}
    # 与 fetch_company_identity.py 同一条规矩：整轮取数明显异常时保留旧缓存，
    # 不用坏结果覆盖好数据。
    if prior and len(companies) < 0.6 * len(prior):
        print(f"[XX] 本轮 {len(companies)} 家不足既有 {len(prior)} 家的 60%，"
              "判定整轮取数异常，保留现有缓存不覆盖")
        return 1

    without_sic = sorted(s for s, v in companies.items() if not v.get("sic"))
    out = {
        "contractVersion": CONTRACT_VERSION,
        "dataset": "supply-chain-foreign-issuers",
        # 见上：定不出国别的那几家，SEC 原值留在这里备查。
        "unresolvedGeo": unresolved_geo,
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": "SEC EDGAR 季度全量索引 + submissions（公共领域）",
        "note": ("在美上市的外国私人发行人（报 20-F／40-F）全体，不再限于同时报 Form SD 的那一批。"
                 "**多收的这些只增加节点、不增加关系边**——Form SD 是冶炼厂边的唯一来源，"
                 "不报 SD 的公司没有边是规则不适用，不是抽取失败，逐家由 filesFormSd 标出。"
                 "因此公司家数变多不表示关系覆盖变好，页面必须把两者分开说。"
                 "按 CIK 去重，主代码按交易所优先级选定，与标普池撞码的一律跳过而"
                 "不是覆盖。"),
        "coverage": {
            "foreignAnnualFilers": len(foreign),
            "formSdFilers": len(sd_ciks),
            "bothAnnualAndFormSd": len(sd_foreign),
            # 收进来的里面有多少家结构上可能有边。这个数才是「关系覆盖」的分母，
            # published 不是——把 published 当分母会把不适用的公司算成缺口。
            "publishedFilesFormSd": sd_yes,
            "withTicker": len(chosen) + len(collided),
            "published": len(companies),
            "skippedNoTicker": len(no_ticker),
            "skippedTickerCollision": len(collided),
            "submissionsFailed": failed,
            "withoutSic": len(without_sic),
        },
        "quarters": [{k: v for k, v in s.items()} for s in stats],
        "companies": companies,
    }
    if args.dry_run:
        print("\ndry-run：未写入任何文件。抽样核对：")
        for symbol in list(companies)[:12]:
            row = companies[symbol]
            print(f"  {symbol:<8} {str(row['name'])[:40]:<40} SIC {row['sic']} "
                  f"{row['country']} {row['exchange']}")
        return 0

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as handle:
        json.dump(out, handle, ensure_ascii=False, indent=2, sort_keys=True)
    print(f"\n{len(companies)} 家 → {OUT_PATH}")
    if without_sic:
        print(f"[!!] {len(without_sic)} 家没有 SIC，环节与产业链判不了："
              f"{'、'.join(without_sic[:10])}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
