#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读探测：Form SD 冲突矿产申报能不能产出「带出处」的上游关系边。

## 为什么是这条路

正查（解析 10-K 找客户名）与反查（按名搜谁提到目标）都已实测否决——根因是 ASC 280
不要求披露客户身份，而全文检索按词频排序会把专利诉讼方推到最前（见第 8.5 节）。

Form SD 不一样：**它是有强制格式的结构化披露**。上市公司若产品含锡、钽、钨、金，
须申报其供应链中的冶炼厂／精炼厂（SOR）清单。清单里的实体是**具名的**，不是
「一家供应商占 22%」这种匿名表述。

实测已知：苹果 11 份、英伟达 6 份、博通 9 份、应用材料 13 份、Skyworks 12 份。

## 这个探针要回答

1. **拿不拿得到**——Form SD 申报的文档结构，冲突矿产报告（CMR）是主文档还是附件；
2. **清单在不在里面**——正文里有没有冶炼厂名单，是表格还是散文，能不能定位；
3. **实体名可不可解析**——名单里的名字是否规整到可以作为节点（对照 RMI 标准冶炼厂名）；
4. **规模多大**——一家公司通常列多少家冶炼厂，全量抓要多久。

## 边界

即使拿到冶炼厂名单，它表示的是「该冶炼厂出现在申报人的供应链中」，**不是直接供货关系**，
也不含份额。建边时必须如实标注这一层语义，不得说成「X 是 Y 的供应商」。

只读，不写仓库任何数据文件。合规同前：声明身份的 UA、远低于 SEC 每秒 10 次上限、
联系方式从环境变量读取。
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from urllib import error, request

TIMEOUT = 30
GAP = 0.35
MAX_REQUESTS = 60
MAX_DOCS_PER_FILING = 4   # 滤掉系统文件后通常只剩 2~4 个真实文档
BODY_LIMIT = 12_000_000

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"

# 实测确认有 Form SD 的公司，覆盖终端品牌、芯片设计与半导体设备三类
# 覆盖三类申报人：终端品牌（苹果、特斯拉）、芯片设计（英伟达、博通）、
# 半导体设备与元件（应用材料、Skyworks）。首轮 4 家里苹果与博通因文档筛选缺陷漏检，
# 本轮扩到 6 家一并复核修复效果。
SAMPLES = [("AAPL", 320193), ("NVDA", 1045810), ("AVGO", 1730168),
           ("AMAT", 6951), ("TSLA", 1318605), ("SWKS", 4127)]

# 冶炼厂名单的定位线索。Form SD 的冲突矿产报告用语高度套路化。
SMELTER_CUES = [
    r"smelter[s]? (?:or|and) refiner[s]?", r"\bSOR\b", r"smelter list",
    r"Responsible Minerals Initiative", r"\bRMI\b", r"Conflict[- ]Free Smelter",
    r"\bCFSI\b", r"facilit(?:y|ies) (?:that|which) processed",
]
# 四种冲突矿产：名单通常按矿种分节
MINERAL_CUES = [r"\btantalum\b", r"\btin\b", r"\btungsten\b", r"\bgold\b", r"\b3TG\b"]


class Budget:
    def __init__(self, total: int = MAX_REQUESTS) -> None:
        self.left = total

    def spend(self) -> bool:
        if self.left <= 0:
            return False
        self.left -= 1
        return True


BUDGET = Budget()


def _fetch(url: str, accept: str = "*/*") -> tuple[bytes, dict]:
    if not BUDGET.spend():
        raise RuntimeError("已达全局请求上限，未发起")
    req = request.Request(url, headers={
        "User-Agent": UA, "Accept": accept, "Accept-Encoding": "gzip, deflate"})
    started = time.time()
    with request.urlopen(req, timeout=TIMEOUT) as response:
        raw = response.read(BODY_LIMIT)
        if response.headers.get("Content-Encoding") == "gzip":
            import gzip
            try:
                raw = gzip.decompress(raw)
            except Exception:                      # noqa: BLE001
                pass
        return raw, {"status": response.status, "bytes": len(raw),
                     "elapsedMs": int((time.time() - started) * 1000)}


def _why(exc: Exception) -> str:
    if isinstance(exc, error.HTTPError):
        return f"HTTP {exc.code}"
    if isinstance(exc, error.URLError):
        return f"网络失败 {exc.reason}"
    return f"{type(exc).__name__}: {exc}"


def latest_form_sd(cik: int) -> dict:
    """从申报索引里取最近一份 Form SD 及其全部文档清单。"""
    body, _ = _fetch(f"https://data.sec.gov/submissions/CIK{cik:010d}.json",
                     accept="application/json")
    payload = json.loads(body.decode("utf-8", "replace"))
    recent = payload.get("filings", {}).get("recent", {})
    forms = recent.get("form", []) or []
    for i, form in enumerate(forms):
        if form == "SD":
            accession = (recent.get("accessionNumber", []) or [None] * (i + 1))[i]
            return {
                "ok": True,
                "accession": accession,
                "primaryDocument": (recent.get("primaryDocument", []) or [None] * (i + 1))[i],
                "filingDate": (recent.get("filingDate", []) or [None] * (i + 1))[i],
                "totalSD": sum(1 for f in forms if f == "SD"),
                "indexUrl": (f"https://www.sec.gov/Archives/edgar/data/{cik}/"
                             f"{str(accession).replace('-', '')}/"),
            }
    return {"ok": False, "why": "申报索引里没有 Form SD"}


def list_documents(index_url: str) -> list[str]:
    """列出该次申报下的全部文件名。冲突矿产报告常是附件而不是主文档。"""
    body, _ = _fetch(index_url, accept="text/html,*/*")
    text = body.decode("utf-8", "replace")
    names = re.findall(r'href="[^"]*?/([^/"]+\.(?:htm|html|txt|pdf))"', text, re.I)
    return sorted({n for n in names if not n.lower().startswith("index")})


def analyse(url: str) -> dict:
    """判断这份文档里有没有冶炼厂名单，以及名单大概什么形态。"""
    body, meta = _fetch(url, accept="text/html,*/*")
    raw = body.decode("utf-8", "replace")
    plain = re.sub(r"<[^>]+>", " ", raw)
    plain = re.sub(r"&(?:nbsp|#160|amp|#38);", " ", plain)
    plain = re.sub(r"\s+", " ", plain)

    cue_hits = {p: len(re.findall(p, plain, re.I)) for p in SMELTER_CUES
                if re.search(p, plain, re.I)}
    minerals = [p.strip(r"\b") for p in MINERAL_CUES if re.search(p, plain, re.I)]
    # 表格行数：名单多以表格呈现，行数是名单规模的下限估计
    rows = len(re.findall(r"<tr[\s>]", raw, re.I))
    # 冶炼厂名往往带国家后缀或 RMI 编号，粗略数一下可识别实体
    rmi_ids = re.findall(r"CID\s?0{0,2}\d{4,6}", plain, re.I)
    return {
        "ok": True,
        "url": url,
        "bytes": meta["bytes"],
        "plainChars": len(plain),
        "cueHits": cue_hits,
        "minerals": minerals,
        "tableRows": rows,
        "rmiIdCount": len(set(rmi_ids)),
        "rmiIdSample": sorted(set(rmi_ids))[:5],
        "hasSmelterList": bool(cue_hits) and (rows > 20 or len(set(rmi_ids)) > 5),
    }


def main() -> None:
    report: dict = {"companies": {}}
    print("── Form SD 冲突矿产申报：能不能拿到具名的上游实体 ──────────────────\n")

    for ticker, cik in SAMPLES:
        entry: dict = {"ticker": ticker, "cik": cik}
        try:
            filing = latest_form_sd(cik)
        except Exception as exc:                   # noqa: BLE001
            filing = {"ok": False, "why": _why(exc)}
        if not filing.get("ok"):
            entry.update(filing)
            report["companies"][ticker] = entry
            print(f"[XX] {ticker:<6} {filing.get('why')}")
            time.sleep(GAP)
            continue
        entry.update(filing)
        print(f"[--] {ticker:<6} 最近 Form SD {filing['filingDate']}"
              f"（共 {filing['totalSD']} 份）  {filing['indexUrl']}")

        try:
            documents = list_documents(filing["indexUrl"])
        except Exception as exc:                   # noqa: BLE001
            documents = []
            print(f"     文档清单取不到：{_why(exc)}")
        # EDGAR 每次申报都带一批系统文件（index / .txt / brokers / companysearch），
        # 它们排在最前。只看前几个会把真正的申报文档整个遮住——苹果与博通的冲突
        # 矿产报告首轮漏检就是这么来的。先滤掉系统文件再看。
        SYSTEM = ("index", "brokers.htm", "companysearch", "primary_doc")
        real = [d for d in documents
                if not any(d.lower().startswith(p) or p in d.lower() for p in SYSTEM)
                and not d.endswith(".txt")]
        entry["documents"] = documents
        entry["realDocuments"] = real
        print(f"     文档 {len(documents)} 个（滤掉系统文件后 {len(real)} 个）：{', '.join(real)}")
        time.sleep(GAP)

        # 命名各家不同（a2026conflictmineralsrepor / cmrcy2025_final / ef20073373_sd），
        # 靠文件名猜必然漏。改为探测全部真实文档——冶炼厂名单动辄几百行，
        # 报告一定是这批文件里最大的那份，探测顺序不影响结论。
        candidates = list(real)
        if filing.get("primaryDocument") and filing["primaryDocument"] not in candidates:
            candidates.append(filing["primaryDocument"])
        entry["analysed"] = []
        for name in candidates[:MAX_DOCS_PER_FILING]:
            try:
                outcome = analyse(filing["indexUrl"] + name)
            except Exception as exc:               # noqa: BLE001
                outcome = {"ok": False, "why": _why(exc), "url": filing["indexUrl"] + name}
            entry["analysed"].append(outcome)
            if outcome.get("ok"):
                print(f"     [{'OK' if outcome['hasSmelterList'] else 'XX'}] {name:<34} "
                      f"{outcome['bytes'] // 1024}KB  表格行 {outcome['tableRows']}  "
                      f"RMI编号 {outcome['rmiIdCount']}  矿种 {outcome['minerals']}")
                if outcome["cueHits"]:
                    print(f"          名单线索：{list(outcome['cueHits'])[:3]}")
                if outcome["rmiIdSample"]:
                    print(f"          RMI 样例：{outcome['rmiIdSample']}")
            else:
                print(f"     [XX] {name:<34} {outcome.get('why')}")
            time.sleep(GAP)
        report["companies"][ticker] = entry
        print()

    with_list = [t for t, v in report["companies"].items()
                 if any(a.get("hasSmelterList") for a in v.get("analysed") or [])]
    total_rows = sum(a.get("tableRows", 0) for v in report["companies"].values()
                     for a in v.get("analysed") or [] if a.get("ok"))
    total_rmi = sum(a.get("rmiIdCount", 0) for v in report["companies"].values()
                    for a in v.get("analysed") or [] if a.get("ok"))

    print("── 结论 ────────────────────────────────────────────────────────────")
    print(f"{len(with_list)}/{len(SAMPLES)} 家的 Form SD 里检出冶炼厂名单：{', '.join(with_list) or '无'}")
    print(f"合计表格行 {total_rows}，可识别 RMI 冶炼厂编号 {total_rmi} 个")
    print("可行性：" + (
        "Form SD 含具名的上游实体，可进入抽取器设计——但边的语义是"
        "「该冶炼厂出现在申报人供应链中」，不是直接供货关系，也不含份额，建边时须如实标注"
        if with_list else
        "**未检出可解析的冶炼厂名单**：可能名单在 PDF 附件或外部链接中，"
        "需先确认承载形式，不得据此推进抽取器"))

    report["verdict"] = {
        "companiesWithSmelterList": with_list,
        "sampleSize": len(SAMPLES),
        "totalTableRows": total_rows,
        "totalRmiIds": total_rmi,
        "feasible": bool(with_list),
        "edgeSemantics": ("冶炼厂出现在申报人供应链中，非直接供货关系，不含份额"),
        "requestsSpent": MAX_REQUESTS - BUDGET.left,
    }
    out = os.environ.get("PROBE_OUTPUT")
    if out:
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "w", encoding="utf-8") as handle:
            json.dump(report, handle, ensure_ascii=False, indent=2)
        print(f"报告：{out}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
