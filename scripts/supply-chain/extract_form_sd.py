#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 Form SD 冲突矿产申报里抽出冶炼厂关系边，写入 apps/supply-chain/edges/。

## 为什么是这条路（前两条为什么不走）

- **正查**（解析 10-K 找客户名）：78 段集中度披露只产出 1 条真边。根因是 ASC 280
  要求披露客户集中度的**幅度**、不要求披露**身份**，「一家客户占 17%」是合规写法。
- **反查**（全文检索谁提到目标）：77 条命中里 0 条是客户语境。根因是检索按相关度≈词频
  排序，提「Apple Inc.」最多的是起诉苹果的专利公司。

Form SD 不同：**它强制列名**。产品含锡、钽、钨、金的公司须申报其供应链中的冶炼厂／
精炼厂，且名单普遍带 RMI 全球统一编号（CID）——有编号才谈得上跨申报人合并同一实体。

## 这条边到底是什么意思

**「该冶炼厂出现在申报人的供应链中」，仅此而已。** 不是直接供货，不含份额，不含层级。
申报人自己也不知道中间隔了几层。页面上必须按这个语义写，不得说成「X 是 Y 的供应商」。

## 覆盖率永远到不了 100%，这不是缺陷

Form SD 强制的是**申报**，不是**列名单**。实测：特斯拉那份 42KB、13 行表格、0 个 CID，
通篇只写尽职调查流程。这类申报如实计为「有申报、无名单」，不能算作没申报，
更不能拿别家的名单往上套。

## 两类条目，分开标记

带 RMI 编号的按编号建边，跨申报人可合并；无编号但「矿种 + 厂名 + 国别」齐全的
也建边，但标为 `name-only`——它没有全球统一标识，跨申报人合并只能靠名字，可能重复。
两类在登记表与页面上分开统计，不混成一个数。解析规则与三种假名单的排除见
form_sd_parse.py。

## 合规

声明身份的 User-Agent（联系方式从环境变量读），请求间隔远低于 SEC 每秒 10 次上限。
申报号未变时不重新下载文档——Form SD 一年一报，天天重下既无意义又浪费对方带宽。
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys
import time
from datetime import datetime, timezone
from urllib import error, request

TIMEOUT = 45
GAP = 0.30                 # 远低于 SEC 每秒 10 次上限
BODY_LIMIT = 24_000_000    # 冶炼厂名单动辄几 MB
MAX_DOCS_PER_FILING = 4

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"

IDENTITY_PATH = "apps/supply-chain/identity.json"
SP500_PATH = "apps/companies/sp500.json"
OUT_DIR = "apps/supply-chain/edges"
SMELTERS_PATH = "apps/supply-chain/smelters.json"

RELATION = "smelter-in-supply-chain"
RELATION_LABEL = "该冶炼厂出现在申报人的供应链中（间接、不含份额、不含层级）"


def load_parser():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "form_sd_parse.py")
    spec = importlib.util.spec_from_file_location("form_sd_parse", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _fetch(url: str, accept: str = "*/*") -> bytes:
    req = request.Request(url, headers={
        "User-Agent": UA, "Accept": accept, "Accept-Encoding": "gzip, deflate"})
    with request.urlopen(req, timeout=TIMEOUT) as response:
        raw = response.read(BODY_LIMIT)
        if response.headers.get("Content-Encoding") == "gzip":
            import gzip
            try:
                raw = gzip.decompress(raw)
            except Exception:                      # noqa: BLE001
                pass
        return raw


def _why(exc: Exception) -> str:
    if isinstance(exc, error.HTTPError):
        return f"HTTP {exc.code}"
    if isinstance(exc, error.URLError):
        return f"网络失败 {exc.reason}"
    return f"{type(exc).__name__}: {exc}"


def latest_form_sd(cik: int) -> dict | None:
    """最近一份 Form SD 的申报号、日期与目录地址。没有就返回 None。"""
    body = _fetch(f"https://data.sec.gov/submissions/CIK{cik:010d}.json",
                  accept="application/json")
    recent = (json.loads(body.decode("utf-8", "replace"))
              .get("filings", {}).get("recent", {}))
    forms = recent.get("form", []) or []
    for i, form in enumerate(forms):
        if form != "SD":
            continue
        accession = (recent.get("accessionNumber") or [])[i]
        return {
            "accession": accession,
            "filingDate": (recent.get("filingDate") or [])[i],
            "reportDate": (recent.get("reportDate") or [None] * (i + 1))[i],
            "indexUrl": (f"https://www.sec.gov/Archives/edgar/data/{cik}/"
                         f"{str(accession).replace('-', '')}/"),
            "totalSD": sum(1 for f in forms if f == "SD"),
        }
    return None


def list_documents(index_url: str) -> list[dict]:
    """按体积倒序列出该次申报的真实文档。

    读 EDGAR 的 index.json，不从页面 HTML 刮 href——刮 href 会抓到站点导航链接
    （privacy.htm / search.htm 等），它们一律 404 且按字母序排在真文档前面，
    特斯拉的报告就是这么被整个跳过的（实测踩过）。
    """
    payload = json.loads(_fetch(index_url.rstrip("/") + "/index.json",
                                accept="application/json").decode("utf-8", "replace"))
    documents = []
    for item in ((payload.get("directory") or {}).get("item")) or []:
        name = str(item.get("name") or "")
        low = name.lower()
        if not low.endswith((".htm", ".html")) or low.startswith("0") or "index" in low:
            continue
        try:
            size = int(item.get("size") or 0)
        except (TypeError, ValueError):
            size = 0
        documents.append({"name": name, "size": size})
    documents.sort(key=lambda d: -d["size"])
    return documents


def extract_company(symbol: str, cik: int, parser, verbose: bool = False) -> dict:
    """取一家公司最近一份 Form SD 并解析冶炼厂名单。"""
    outcome: dict = {"symbol": symbol, "cik": cik}
    filing = latest_form_sd(cik)
    time.sleep(GAP)
    if not filing:
        outcome["state"] = "no-filing"          # 从未申报 Form SD（多半不涉 3TG）
        return outcome
    outcome["filing"] = filing

    try:
        documents = list_documents(filing["indexUrl"])
    except Exception as exc:                       # noqa: BLE001
        outcome["state"] = "index-failed"
        outcome["why"] = _why(exc)
        return outcome
    time.sleep(GAP)

    best: dict | None = None
    for doc in documents[:MAX_DOCS_PER_FILING]:
        url = filing["indexUrl"] + doc["name"]
        try:
            html = _fetch(url, accept="text/html,*/*").decode("utf-8", "replace")
        except Exception as exc:                   # noqa: BLE001
            if verbose:
                print(f"       [XX] {doc['name']}：{_why(exc)}")
            time.sleep(GAP)
            continue
        result = parser.parse_smelters(html)
        result["document"] = doc["name"]
        result["url"] = url
        if verbose:
            shape = result["shape"]
            print(f"       [--] {doc['name']:<40} {doc['size'] // 1024:>5}KB  "
                  f"行 {result['rowsScanned']:>4}  抽出 {result['unique']:>4}  "
                  f"丢弃 {result['droppedNoCid']:>3}  "
                  f"（<table>{shape['tableTags']} <tr>{shape['trTags']} "
                  f"CID {shape['cidTokens']}）")
            if result["unique"] == 0 and shape["trTags"] == 0:
                print(f"            正文开头：{shape['textHead'][:150]}")
            for row in result["droppedSample"][:6]:
                print(f"            丢弃样例：{' | '.join(c[:34] for c in row)}")
        time.sleep(GAP)
        if best is None or result["unique"] > best["unique"]:
            best = result
        if result["unique"] > 0:
            break                                  # 找到名单就停，不多下

    if best is None:
        outcome["state"] = "doc-failed"
        return outcome
    outcome["parse"] = best
    # 有申报但没名单，是这份披露的真实形态，不是抓取失败——分开记。
    outcome["state"] = "listed" if best["unique"] else "filed-no-list"
    return outcome


def build_edges(outcome: dict, name_zh: str | None) -> dict:
    """把解析结果变成带出处的边。每条边都自带可核验的申报链接。"""
    filing, parse = outcome["filing"], outcome["parse"]
    doc_date = filing.get("reportDate") or filing.get("filingDate")
    edges = []
    for item in parse["smelters"]:
        edges.append({
            "from": item["id"],
            "to": outcome["symbol"],
            "fromListed": False,        # 冶炼厂普遍不是标普成分股，不进节点表
            "toListed": True,
            "relation": RELATION,
            "relationLabel": RELATION_LABEL,
            "tier": "smelter",
            # rmi-cid：全球统一编号，跨申报人可合并。
            # name-only：只有名字，合并只能靠名字规范化，可能重复。页面须分开说。
            "identifierType": item["identifierType"],
            "cid": item["cid"],
            # 名称与国别在边上冗余一份：公司页只需拉这一个文件就能渲染，
            # 不必再拉几百 KB 的全局冶炼厂表。
            "name": item["name"],
            "country": item["country"],
            "countryEn": item["countryEn"],
            "minerals": item["minerals"],
            "confidence": "disclosed",
            "evidence": [{
                "sourceType": "sec-form-sd",
                "url": parse["url"],
                "docDate": doc_date,
                "locator": f"冲突矿产报告 · 冶炼厂清单第 {item['rowIndex'] + 1} 行",
                "quote": item["name"] or item["cid"],
            }],
        })
    by_country: dict[str, int] = {}
    for edge in edges:
        by_country[edge["country"] or "未归类"] = by_country.get(edge["country"] or "未归类", 0) + 1
    by_mineral: dict[str, int] = {}
    for edge in edges:
        for mineral in edge["minerals"] or ["未标注"]:
            by_mineral[mineral] = by_mineral.get(mineral, 0) + 1
    return {
        "contractVersion": 1,
        "dataset": "supply-chain-edges",
        "symbol": outcome["symbol"],
        "name": name_zh,
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "filing": {
            "form": "SD",
            "accession": filing["accession"],
            "filingDate": filing["filingDate"],
            "reportDate": filing.get("reportDate"),
            "document": parse["document"],
            "url": parse["url"],
            "indexUrl": filing["indexUrl"],
            "totalSD": filing.get("totalSD"),
        },
        "parse": {k: parse[k] for k in
                  ("rowsScanned", "rowsWithCid", "nameOnly", "droppedNoCid", "unique",
                   "namedRatio", "countryRatio")},
        "relation": {"id": RELATION, "label": RELATION_LABEL},
        "byCountry": dict(sorted(by_country.items(), key=lambda kv: -kv[1])),
        "byMineral": dict(sorted(by_mineral.items(), key=lambda kv: -kv[1])),
        "edges": edges,
        "coverage": {
            "claimComplete": False,
            "note": ("Form SD 强制申报、不强制列名单，本清单只是该公司披露的部分，"
                     "且语义是「出现在供应链中」，不是直接供货。"),
        },
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="只解析并打印，不写任何文件——上线前用它核对真实抽取结果")
    ap.add_argument("--tickers", default="", help="逗号分隔，限定公司（默认全部）")
    ap.add_argument("--limit", type=int, default=0, help="最多处理几家")
    ap.add_argument("--sample-rows", type=int, default=0, help="每家打印前 N 条明细")
    args = ap.parse_args()

    with open(IDENTITY_PATH, encoding="utf-8") as handle:
        identity = (json.load(handle) or {}).get("companies") or {}
    names = {}
    try:
        with open(SP500_PATH, encoding="utf-8") as handle:
            names = {m["symbol"]: m.get("name") for m in
                     (json.load(handle).get("members") or []) if m.get("symbol")}
    except (OSError, ValueError):
        pass

    wanted = [t.strip().upper() for t in args.tickers.split(",") if t.strip()]
    targets = [(t, v["cik"]) for t, v in sorted(identity.items())
               if v.get("cik") and (not wanted or t.upper() in wanted)]
    if args.limit:
        targets = targets[:args.limit]
    if not targets:
        print("[XX] 没有可处理的公司（identity.json 里没有 CIK？）")
        return 1

    parser = load_parser()
    print(f"待处理 {len(targets)} 家"
          + ("（dry-run，不写文件）" if args.dry_run else "") + "\n")

    states: dict[str, list[str]] = {}
    results: list[dict] = []
    for i, (symbol, cik) in enumerate(targets, 1):
        try:
            outcome = extract_company(symbol, cik, parser, verbose=bool(args.sample_rows))
        except Exception as exc:                   # noqa: BLE001
            outcome = {"symbol": symbol, "cik": cik, "state": "error", "why": _why(exc)}
        states.setdefault(outcome["state"], []).append(symbol)
        results.append(outcome)

        if outcome["state"] == "listed":
            parse = outcome["parse"]
            # 「行」是去重前的原始行数，「家」是去重后的实体数——两个数不一样时
            # 说明同一家按多种矿种各列了一行，不是解析出了岔子。
            print(f"[OK] {symbol:<6} {outcome['filing']['filingDate']}  "
                  f"冶炼厂 {parse['unique']:>4} 家"
                  f"（原始行：带编号 {parse['rowsWithCid']} / 仅名字 {parse['nameOnly']}）  "
                  f"带名 {parse['namedRatio']:.0%}  带国别 {parse['countryRatio']:.0%}  "
                  f"丢弃行 {parse['droppedNoCid']}")
            for item in parse["smelters"][:args.sample_rows]:
                print(f"       {item['id'][:22]:<22} {str(item['name'])[:40]:<40} "
                      f"{str(item['country'] or '—'):<8} {'/'.join(item['minerals']) or '—'}")
        elif outcome["state"] == "filed-no-list":
            print(f"[--] {symbol:<6} {outcome['filing']['filingDate']}  "
                  f"有申报无名单（扫 {outcome['parse']['rowsScanned']} 行，0 个 RMI 编号）")
        elif outcome["state"] == "no-filing":
            if args.sample_rows:
                print(f"[  ] {symbol:<6} 无 Form SD 申报")
        else:
            print(f"[XX] {symbol:<6} {outcome['state']}  {outcome.get('why', '')}")
        if i % 50 == 0:
            print(f"     …已处理 {i}/{len(targets)}")

    listed = states.get("listed", [])
    filed_no_list = states.get("filed-no-list", [])
    no_filing = states.get("no-filing", [])
    failed = [s for k, v in states.items() if k in ("error", "index-failed", "doc-failed") for s in v]
    total_edges = sum(r["parse"]["unique"] for r in results if r["state"] == "listed")
    total_cid = sum(r["parse"]["rowsWithCid"] for r in results if r["state"] == "listed")
    total_name_only = sum(r["parse"]["nameOnly"] for r in results if r["state"] == "listed")

    print("\n── 结论 ────────────────────────────────────────────────────────────")
    print(f"有名单 {len(listed)} 家 · 有申报无名单 {len(filed_no_list)} 家 · "
          f"无申报 {len(no_filing)} 家 · 失败 {len(failed)} 家")
    print(f"冶炼厂关系边合计 {total_edges} 条"
          f"（带 RMI 编号 {total_cid} · 仅有名字 {total_name_only}）")
    if filed_no_list:
        print(f"  有申报无名单：{', '.join(filed_no_list[:20])}"
              + (" …" if len(filed_no_list) > 20 else ""))
        print("  （Form SD 强制申报不强制列名单，这是披露本身的形态，不是抓取失败）")
    if failed:
        print(f"  失败：{', '.join(failed[:20])}")

    if args.dry_run:
        print("\ndry-run：未写入任何文件。核对上面的名称／国别／矿种再决定是否接入发布。")
        return 0

    os.makedirs(OUT_DIR, exist_ok=True)
    registry: dict[str, dict] = {}
    index: dict[str, dict] = {}
    written = 0
    for outcome in results:
        if outcome["state"] != "listed":
            continue
        payload = build_edges(outcome, names.get(outcome["symbol"]))
        path = os.path.join(OUT_DIR, f"{outcome['symbol']}.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        written += 1
        index[outcome["symbol"]] = {
            "file": f"edges/{outcome['symbol']}.json",
            "count": len(payload["edges"]),
            "filingDate": payload["filing"]["filingDate"],
            "accession": payload["filing"]["accession"],
        }
        for item in outcome["parse"]["smelters"]:
            entry = registry.setdefault(item["id"], {
                "id": item["id"], "cid": item["cid"],
                "identifierType": item["identifierType"], "name": item["name"],
                "country": item["country"], "countryEn": item["countryEn"],
                "minerals": [], "filers": []})
            entry["name"] = entry["name"] or item["name"]
            entry["country"] = entry["country"] or item["country"]
            entry["countryEn"] = entry["countryEn"] or item["countryEn"]
            entry["minerals"] = sorted(set(entry["minerals"]) | set(item["minerals"]))
            entry["filers"] = sorted(set(entry["filers"]) | {outcome["symbol"]})

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(SMELTERS_PATH, "w", encoding="utf-8") as handle:
        json.dump({
            "contractVersion": 1,
            "dataset": "supply-chain-smelters",
            "updatedAt": now,
            "frequency": "annual",     # Form SD 每年 5 月 31 日前申报
            "status": "ok",
            "source": "SEC EDGAR Form SD 冲突矿产申报",
            "sourceUrl": "https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&type=SD",
            "relation": {"id": RELATION, "label": RELATION_LABEL},
            "note": ("带 RMI 编号的条目按编号合并，跨申报人可靠；无编号的条目只能按"
                     "名字规范化归并，写法不同就会重复——两类分开统计，不混成一个数。"
                     "名字归一只处理大小写与标点，不做同义合并：宁可一家重复出现，"
                     "不可两家被错并成一家。"),
            "companiesIndex": dict(sorted(index.items())),
            "coverage": {
                "claimComplete": False,
                "companiesScanned": len(targets),
                "companiesWithList": len(listed),
                "companiesFiledNoList": len(filed_no_list),
                "companiesNoFiling": len(no_filing),
                "companiesFailed": len(failed),
                "edgesTotal": total_edges,
                "uniqueSmelters": len(registry),
                "uniqueByIdentifier": {
                    "rmi-cid": sum(1 for v in registry.values()
                                   if v["identifierType"] == "rmi-cid"),
                    "name-only": sum(1 for v in registry.values()
                                     if v["identifierType"] == "name-only"),
                },
                "note": ("Form SD 强制申报、不强制列名单：有申报无名单的公司如实单列，"
                         "不并入「无申报」。覆盖率因此永远到不了 100%，这是披露制度"
                         "本身的上限，不是抓取缺陷。"),
            },
            "smelters": dict(sorted(registry.items())),
        }, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print(f"\n已写入 {written} 个公司边文件 → {OUT_DIR}/")
    print(f"冶炼厂登记表 {len(registry)} 家 → {SMELTERS_PATH}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
