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
import re
import sys
import time
from datetime import datetime, timezone
from urllib import error, request

TIMEOUT = 45
# SEC 允许每秒 10 次。全表 495 家约 1100 次请求，0.30 秒间隔实测跑到 20 分钟以上，
# 逼近 job 超时。收到 0.20 秒（含往返延迟约每秒 3~4 次），仍远低于上限。
GAP = 0.20
BODY_LIMIT = 24_000_000    # 冶炼厂名单动辄几 MB
MAX_DOCS_PER_FILING = 4

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"

IDENTITY_PATH = "apps/supply-chain/identity.json"
SP500_PATH = "apps/companies/sp500.json"
OUT_DIR = "apps/supply-chain/edges"
SMELTERS_PATH = "apps/supply-chain/smelters.json"

# 本轮拿到的公司数低于磁盘已有的这个比例，判定整轮取数异常，保留旧数据不覆盖。
# 与 fetch_company_identity.py 的 MIN_SUCCESS_RATIO 同一个思路。
MIN_KEEP_RATIO = 0.6
# Form SD 每年 5 月 31 日前申报。只在申报季跑全量抓取，其余月份不动网络。
FILING_SEASON = (5, 6, 7)
# 边文件 + 登记表的体积上限。超了就中止——静态站点的数据文件会随站点发布，
# 而且永久留在 git 历史里。实测每条边约 275 字节，30 MB 够放十万条以上；
# 真撞上这条线，说明该先想清楚怎么存，而不是直接塞进仓库。
MAX_TOTAL_BYTES = 30 * 1024 * 1024

RELATION = "smelter-in-supply-chain"
RELATION_LABEL = "该冶炼厂出现在申报人的供应链中（间接、不含份额、不含层级）"


def load_parser():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "form_sd_parse.py")
    spec = importlib.util.spec_from_file_location("form_sd_parse", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _name_key(name: str | None) -> str:
    """只用于比对「名字是不是完全一样」，不用于建标识。"""
    return re.sub(r"[^a-z0-9]+", "", (name or "").lower())


def write_if_changed(path: str, payload: dict, ignore: tuple = ("updatedAt",)) -> bool:
    """内容变了才写。返回是否真的写了。

    Form SD 一年一报。每天把几百个文件的时间戳刷一遍再提交，仓库里会堆出几 MB
    没有信息量的 diff，还会让「今年名单变了没有」这个问题在历史里查不出来。
    """
    def strip(data: dict) -> dict:
        return {k: v for k, v in data.items() if k not in ignore}

    try:
        with open(path, encoding="utf-8") as handle:
            if strip(json.load(handle)) == strip(payload):
                return False
    except (OSError, ValueError):
        pass
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    return True


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


def skip_reason(name: str) -> str | None:
    """这份文档要不要跳过，以及为什么。返回 None 表示会读。

    单独抽出来是因为 probe_form_sd_no_list.py 要用同一套规则去显示
    「哪些文件被规则挡掉了」。两边各写一份的话，规则一改探针就开始说假话——
    而那个探针的全部价值就在于如实显示被挡掉的文件。
    """
    low = name.lower()
    if not low.endswith((".htm", ".html")):
        return "非 HTML"
    if low.startswith("0"):
        return "文件名以 0 开头"
    if "index" in low:
        return "文件名含 index"
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
        if skip_reason(name):
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
            for i, row in enumerate(result["droppedSample"][:6]):
                print(f"            丢弃样例：{' | '.join(c[:34] for c in row)}")
                heads = result.get("droppedHeadings") or []
                if i < len(heads):
                    print(f"              上方小标题：{heads[i]}")
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
    """把解析结果变成带出处的边。

    ## 出处提到文件级，不是省事，是更严

    同一份申报里的每条边，出处文件、文件日期、来源类型、关系语义、confidence
    完全相同——一条边一份 evidence 是几百字节纯重复。按实测规模（有名单的公司
    动辄两三百家冶炼厂），逐边重复会让仓库多出十几 MB 一年只变一次的 JSON。

    更重要的是：出处放在文件级之后，**结构上不可能出现同一文件里某条边指向
    别的出处、或者干脆没有出处**。逐边存 evidence 反而给了这种可能。契约因此
    改为：文件必须有完整的 `evidence`（来源类型 + 可点开的 https 地址 + 文件日期），
    每条边必须有 `row`（在该文件里的行号）作为定位。同样可核验，且更难写错。

    contractVersion 因此 1 → 2。
    """
    filing, parse = outcome["filing"], outcome["parse"]
    doc_date = filing.get("reportDate") or filing.get("filingDate")
    edges = [{
        "from": item["id"],
        # rmi-cid：全球统一编号，跨申报人可合并。
        # name-only：只有名字，合并只能靠名字规范化，可能重复。页面须分开说。
        "idType": item["identifierType"],
        "cid": item["cid"],
        "name": item["name"],
        "country": item["country"],
        "countryEn": item["countryEn"],
        "minerals": item["minerals"],
        # 在原始申报文档里的行号，用来定位核验
        "row": item["rowIndex"] + 1,
    } for item in parse["smelters"]]

    by_country: dict[str, int] = {}
    by_mineral: dict[str, int] = {}
    for edge in edges:
        key = edge["country"] or "未归类"
        by_country[key] = by_country.get(key, 0) + 1
        for mineral in edge["minerals"] or ["未标注"]:
            by_mineral[mineral] = by_mineral.get(mineral, 0) + 1

    return {
        "contractVersion": 2,
        "dataset": "supply-chain-edges",
        "symbol": outcome["symbol"],
        "name": name_zh,
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        # 关系语义。页面靠它决定措辞，缺了就可能被写成直接供货关系。
        "relation": {"id": RELATION, "label": RELATION_LABEL, "tier": "smelter"},
        "confidence": "disclosed",
        "direction": {"from": "smelter", "to": outcome["symbol"], "toListed": True},
        # 出处：本文件里每一条边共用这一份，可点开核验。
        "evidence": {
            "sourceType": "sec-form-sd",
            "url": parse["url"],
            "docDate": doc_date,
            "form": "SD",
            "accession": filing["accession"],
            "filingDate": filing["filingDate"],
            "reportDate": filing.get("reportDate"),
            "document": parse["document"],
            "indexUrl": filing["indexUrl"],
            "totalSD": filing.get("totalSD"),
        },
        "parse": {k: parse[k] for k in
                  ("rowsScanned", "rowsWithCid", "nameOnly", "droppedNoCid", "unique",
                   "namedRatio", "countryRatio")},
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
    ap.add_argument("--tickers", default="",
                    help="逗号分隔，限定公司；留空或写 ALL 表示全部。"
                         "（写 ALL 是因为 GitHub 会把空字符串输入替换成默认值，"
                         "「留空=全部」在工作流里不成立）")
    ap.add_argument("--limit", type=int, default=0, help="最多处理几家")
    ap.add_argument("--sample-rows", type=int, default=0, help="每家打印前 N 条明细")
    ap.add_argument("--force", action="store_true",
                    help="忽略「一年一次」的季节闸门，立即全量重抓")
    ap.add_argument("--rebuild-registry", action="store_true",
                    help="不联网，只按磁盘上已有的边文件重算 smelters.json——"
                         "登记表口径变了不必重跑整轮抓取。边文件一个字节都不动。")
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
    if "ALL" in wanted:
        wanted = []
    targets = [(t, v["cik"]) for t, v in sorted(identity.items())
               if v.get("cik") and (not wanted or t.upper() in wanted)]
    if args.limit:
        targets = targets[:args.limit]
    if not targets:
        print("[XX] 没有可处理的公司（identity.json 里没有 CIK？）")
        return 1

    # ── 一年一次 ────────────────────────────────────────────────────────
    # Form SD 每年 5 月 31 日前申报，一年只变一次。全量扫 495 家要发 1100 多次
    # 请求、跑十几分钟，天天跑既拿不到新东西，也是在白占 SEC 的带宽。
    # 因此只在申报季（5–7 月）跑；其余月份直接退出，磁盘上的数据原样保留。
    # --force 可随时强制重抓。
    month = datetime.now(timezone.utc).month
    if not args.force and not args.dry_run and month not in FILING_SEASON:
        print(f"当前 {month} 月不在 Form SD 申报季（{FILING_SEASON[0]}–{FILING_SEASON[-1]} 月），"
              f"跳过全量抓取，保留现有数据。\n"
              f"（Form SD 每年 5 月 31 日前申报，一年只变一次；"
              f"要立即重抓加 --force）")
        return 0

    parser = load_parser()
    print(f"待处理 {len(targets)} 家"
          + ("（dry-run，不写文件）" if args.dry_run else "") + "\n")

    states: dict[str, list[str]] = {}
    results: list[dict] = []
    # 重建模式下不取任何数：扫描列表置空，写盘阶段照常从磁盘重算登记表。
    scan = [] if args.rebuild_registry else targets
    for i, (symbol, cik) in enumerate(scan, 1):
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
    # 逐家的申报状态。只报「495 家里 85 家有名单」，读者无法判断自己关心的那家
    # 属于哪一类，也就无法判断「没数据」是抓取失败还是这家本来就不申报。
    # 摩根大通没有实体产品，Form SD 对它根本不适用——这件事必须能按公司查到，
    # 否则页面上金融板块的 0 会被读成「还没抓」。
    filing_status = {r["symbol"]: ("failed" if r["state"] in
                                   ("error", "index-failed", "doc-failed") else r["state"])
                     for r in results}
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

    # ── 写盘 ──────────────────────────────────────────────────────────────
    # 三条规矩，都是「不拿坏结果覆盖好数据」的具体形态：
    # 1. 这一轮拿到的公司数比磁盘上已有的少太多 → 判定整轮失败，一个字都不写；
    # 2. 单家取数失败 → 保留它已有的边文件，不删；
    # 3. 内容没变（只有时间戳不同）→ 不重写。Form SD 一年一报，天天重写等于
    #    每天往仓库里塞几 MB 无意义的 diff。
    existing = {name[:-5] for name in os.listdir(OUT_DIR)
                if name.endswith(".json")} if os.path.isdir(OUT_DIR) else set()
    # 重建模式沿用上一份的扫描口径。取不到就中止——宁可不重建，也不发布
    # 一份「85 家有名单」被写成「0 家有名单」的覆盖率。
    scan_counts: dict = {}
    if args.rebuild_registry:
        try:
            with open(SMELTERS_PATH, encoding="utf-8") as handle:
                prior = (json.load(handle) or {}).get("coverage") or {}
        except (OSError, ValueError) as exc:
            print(f"[XX] 重建模式读不到上一份 {SMELTERS_PATH}（{exc}），中止")
            return 1
        keys = ("companiesScanned", "companiesWithList", "companiesFiledNoList",
                "companiesNoFiling", "companiesFailed")
        # failedSymbols 是后加的字段，旧文件可能没有；缺了就沿用空列表，
        # 不当成致命错误——但计数字段缺失仍然中止。
        missing = [k for k in keys if prior.get(k) is None]
        if missing:
            print(f"[XX] 上一份覆盖率缺少 {missing}，无法沿用扫描口径，中止")
            return 1
        scan_counts = {k: prior[k] for k in keys}
        scan_counts["failedSymbols"] = prior.get("failedSymbols") or []
        # 同 failedSymbols：后加的字段，旧文件没有就留空，不当致命错误。
        scan_counts["filingStatus"] = prior.get("filingStatus") or {}
        print(f"沿用上一轮扫描口径：扫 {scan_counts['companiesScanned']} 家，"
              f"其中 {scan_counts['companiesWithList']} 家有名单\n")

    # 重建模式本来就一家都没取，这道闸门在那里没有意义。
    if existing and not args.rebuild_registry and len(listed) < MIN_KEEP_RATIO * len(existing):
        print(f"\n[XX] 本轮只拿到 {len(listed)} 家的名单，磁盘上已有 {len(existing)} 家，"
              f"低于 {MIN_KEEP_RATIO:.0%} 阈值——判定整轮取数异常，保留现有数据不覆盖。")
        return 1

    os.makedirs(OUT_DIR, exist_ok=True)
    written = kept = unchanged = 0
    for outcome in results:
        if outcome["state"] != "listed":
            continue
        payload = build_edges(outcome, names.get(outcome["symbol"]))
        path = os.path.join(OUT_DIR, f"{outcome['symbol']}.json")
        if write_if_changed(path, payload):
            written += 1
        else:
            unchanged += 1

    # 登记表与索引一律从磁盘重建，保证它们和实际发布的边文件一致——
    # 只按本轮结果生成的话，取数失败那几家会从索引里消失，而文件还在，
    # 页面就会出现「文件在但没人索引」的孤儿。
    registry: dict[str, dict] = {}
    index: dict[str, dict] = {}
    for name in sorted(os.listdir(OUT_DIR)):
        if not name.endswith(".json"):
            continue
        symbol = name[:-5]
        try:
            with open(os.path.join(OUT_DIR, name), encoding="utf-8") as handle:
                bundle = json.load(handle)
        except (OSError, ValueError) as exc:
            print(f"[XX] 边文件 {name} 读不出来：{exc}")
            return 1
        if symbol not in {o["symbol"] for o in results if o["state"] == "listed"}:
            kept += 1
        evidence = bundle.get("evidence") or {}
        index[symbol] = {
            "file": f"edges/{symbol}.json",
            "count": len(bundle.get("edges") or []),
            "filingDate": evidence.get("filingDate"),
            "accession": evidence.get("accession"),
        }
        for edge in bundle.get("edges") or []:
            entry = registry.setdefault(edge["from"], {
                "id": edge["from"], "cid": edge.get("cid"),
                "identifierType": edge.get("idType"), "name": edge.get("name"),
                "country": edge.get("country"), "countryEn": edge.get("countryEn"),
                "minerals": [], "filers": []})
            entry["name"] = entry["name"] or edge.get("name")
            entry["country"] = entry["country"] or edge.get("country")
            entry["countryEn"] = entry["countryEn"] or edge.get("countryEn")
            entry["minerals"] = sorted(set(entry["minerals"]) | set(edge.get("minerals") or []))
            entry["filers"] = sorted(set(entry["filers"]) | {symbol})

    # 无编号条目里有大量与带编号条目**同名**的——实测 876 条里 681 条名字完全一致。
    # 不合并（没有编号就无从确认是同一家，`Aurubis AG` 与 `Aurubis AG, Hamburg`
    # 正是反例），但必须把「名字完全相同」这个**事实**记下来，否则条目数会把
    # 同一家数两次，约 1032 家报成 1713 家。
    cid_by_name = {_name_key(v["name"]): key for key, v in registry.items()
                   if v["identifierType"] == "rmi-cid" and v["name"]}
    exact_matches = 0
    for key, entry in registry.items():
        if entry["identifierType"] != "name-only" or not entry["name"]:
            continue
        twin = cid_by_name.get(_name_key(entry["name"]))
        if not twin:
            continue
        exact_matches += 1
        # 记事实，不做断言：名字一模一样，但没有编号佐证，仍是两条独立条目。
        entry["sameNameAs"] = twin
        registry[twin]["alsoListedWithoutCid"] = True

    published_edges = sum(v["count"] for v in index.values())
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    smelters_payload = {
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
                 "不可两家被错并成一家。因此 uniqueSmelters 是**条目数**，"
                 "不是「有多少家不同的冶炼厂」：无编号条目里有大量与带编号条目同名的，"
                 "sameNameAs 记录了这个事实（只记录、不合并），"
                 "distinctAfterExactNameMatch 是扣掉这部分后的下限估计。"),
        "companiesIndex": dict(sorted(index.items())),
        "coverage": {
            "claimComplete": False,
            # 这五个数来自本轮扫描，登记表重建模式下没有扫描——必须沿用上一份，
            # 不能归零。归零会让页面把「495 家里 85 家有名单」显示成「0 家有名单」，
            # 那是对事实的错误陈述，不是「暂无数据」。
            **(scan_counts if args.rebuild_registry else {
                "companiesScanned": len(targets),
                "companiesWithList": len(listed),
                "companiesFiledNoList": len(filed_no_list),
                "companiesNoFiling": len(no_filing),
                "companiesFailed": len(failed),
                # 只报「失败 5 家」而不说是哪 5 家，等于没人能去核对。
                # 名单写进数据，不只留在会过期的运行日志里。
                "failedSymbols": sorted(failed)[:40],
                # 逐家状态，供页面按板块解释缺口的成因。
                "filingStatus": dict(sorted(filing_status.items())),
            }),
            "companiesPublished": len(index),
            "edgesTotal": published_edges,
            # 条目数，不是「有多少家不同的冶炼厂」——见下面两个数。
            "uniqueSmelters": len(registry),
            # 名字与某条带编号条目完全一致的无编号条目数。几乎肯定是同一家，
            # 但没有编号佐证，所以只记录、不合并。
            "exactNameMatchWithCid": exact_matches,
            # 扣掉上面那部分后的下限估计。真实数目在这两个数之间——写法不同
            # 但其实同一家的（Aurubis AG / Aurubis AG, Hamburg）仍算两条。
            "distinctAfterExactNameMatch": len(registry) - exact_matches,
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
    }
    write_if_changed(SMELTERS_PATH, smelters_payload)

    # 体积闸门：抽取器跑飞了不该能往仓库里塞几十 MB。这是静态站点，
    # 边文件会随站点一起发布，一年只变一次却要永久留在 git 历史里。
    total_bytes = sum(os.path.getsize(os.path.join(OUT_DIR, f))
                      for f in os.listdir(OUT_DIR) if f.endswith(".json"))
    total_bytes += os.path.getsize(SMELTERS_PATH) if os.path.exists(SMELTERS_PATH) else 0
    print(f"\n边文件与登记表合计 {total_bytes / 1_048_576:.1f} MB")
    if total_bytes > MAX_TOTAL_BYTES:
        print(f"[XX] 超出上限 {MAX_TOTAL_BYTES / 1_048_576:.0f} MB——"
              f"这不是「数据变多了」，是该先想清楚怎么存，不是直接塞进仓库。")
        return 1

    print(f"边文件：新写／更新 {written}，内容未变 {unchanged}，"
          f"本轮未取到但保留 {kept} → {OUT_DIR}/")
    print(f"已发布 {len(index)} 家公司、{published_edges} 条边、"
          f"{len(registry)} 家冶炼厂 → {SMELTERS_PATH}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
