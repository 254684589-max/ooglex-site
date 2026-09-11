#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""补名单工程 · 阶段 1 探针：历年 Form SD 能不能补上当年的空缺。

## 要回答的问题

670 家公司**交了 Form SD 但正文里没有可解析的冶炼厂名单**（占全池 11.4%）。
其中有多少家在**过去某一年**列过名单？

如果比例够高，那些历年名单同样是可核验的 SEC 原始申报——按这个板块的证据
标准完全够格上图，只是必须标明年份（阶段 0 已经把年份标注的地基做好了）。

## 判据（**写在探之前，不许探完再定**）

    抽样        670 家里**按环节分层**取 120 家，不手挑；
                分层是因为按代码排序取步长会让材料加工从 10% 掉到 5%，
                而那正是最可能有名单的环节——偏差方向是假阴性
    回溯        每家最多往回 4 份 SD 申报
    命中定义    某一年解出 ≥1 条**带 RMI 编号**的冶炼厂条目
    判据        命中率 ≥ 10%（120 家里 ≥12 家）→ 值得建
                命中率 <  10%                  → 判「收益不足」，写进判决表

10% 这条线的依据：接进管线要改抽取器、边文件要加年份维度、页面要区分
「今年的名单」与「历年补的名单」，是一轮的工作量。120 家里少于 12 家命中，
外推到 670 家不足 67 家，相对现有 369 家不到两成增量，不值得为此改动
已经稳定的抽取路径。

## 取到 0 份 = 结论无效，不是判死

如果一家都没取到申报（网络失败、接口变更、解析器全挂），**直接报「结论无效」
并非零退出，不输出任何判据**。拿取数失败冒充业务事实，是这个探针家族第一条
禁令——附件 21 探针第一轮 60/60 报「没有」，实际是我的文件名正则挡掉了所有
真实形态。

## 文档按**体积**降序读，解出带编号的就收手

一份 Form SD 提交里常有两份东西：正文（只列几家或一句话带过）和冲突矿产
报告附件（完整表格）。按文件名排序会读到正文那份短的（第二十二轮实测：
SHW 的条目数在 32 → 9 → 30 → 7 之间来回跳）。

第一版按文件名排序、每份申报读 6 个文档全解一遍，**跑 68 分钟没跑完**，
而且与生产抽取器（`extract_form_sd.list_documents()` 按 size 降序）不一致：
文档多于 6 个时最大那份可能被截掉，「有名单」会被读成「没名单」。

现在按体积降序读、最多 3 个、**解出带编号条目就立刻返回**——判据问的是
「这一年有没有带编号的名单」，不是「最全的名单有多大」，不必全解一遍。

## 只读

不写任何数据文件、不建任何边、不改任何清单。
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
SAMPLE = int(os.environ.get("BACKFILL_SAMPLE", "120"))
YEARS = int(os.environ.get("BACKFILL_YEARS", "4"))
MAX_REQUESTS = int(os.environ.get("BACKFILL_MAX_REQUESTS", "9000"))
# 判据。改这个数等于改判据，必须连同上面的理由一起改。
HIT_FLOOR = float(os.environ.get("BACKFILL_HIT_FLOOR", "0.10"))
# 每份申报最多读几个文档。按体积降序，最大那份几乎一定是完整名单表，
# 所以 3 个足够；第一版读 6 个且按文件名排序，跑 68 分钟没跑完。
MAX_DOCS = int(os.environ.get("BACKFILL_MAX_DOCS", "3"))

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"
NODES_PATH = "apps/supply-chain/nodes.json"


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
    """这份申报里值得一读的文档，**按体积从大到小**。

    第一版按文件名排序（"ex" 开头的优先），跑了 68 分钟还没完，而且排序方式
    与生产抽取器不一致——`extract_form_sd.list_documents()` 是按 `size` 降序取的。
    两处不一致有两个后果，方向都不好：

    一、**慢**。要把 6 份文档全解一遍才敢说「这年没名单」，而冲突矿产报告
        附件常有几百 KB 到几 MB。
    二、**假阴性**。文档超过 6 个时，最大那份（几乎一定是完整名单表）可能
        排在名字序后面被截掉，于是「有名单」被读成「没名单」。

    按体积降序同时解决两件事：最可能是名单的那份排第一，命中后立刻收手。
    跳过的规则也与生产抽取器对齐（`skip_reason`）：整份提交的 .txt 以 0 开头，
    它把所有附件拼在一起，解起来又大又慢，而真名单一定另有单独附件。
    """
    acc = accession.replace("-", "")
    base = f"https://www.sec.gov/Archives/edgar/data/{cik}/{acc}"
    try:
        listing = json.loads(fetch(f"{base}/index.json").decode("utf-8", "replace"))
    except Exception:                              # noqa: BLE001
        return []
    docs = []
    for item in ((listing.get("directory") or {}).get("item") or []):
        name = str(item.get("name") or "")
        low = name.lower()
        if not low.endswith((".htm", ".html")):
            continue
        if low.startswith("0") or "index" in low:  # 与 extract_form_sd 同一条规则
            continue
        try:
            size = int(item.get("size") or 0)
        except (TypeError, ValueError):
            size = 0
        docs.append((size, name))
    docs.sort(reverse=True)
    return [f"{base}/{n}" for _, n in docs[:MAX_DOCS]]


def first_with_cid(parser, cik: int, accession: str) -> tuple[int, int, str]:
    """按体积从大到小读，**解出带编号的条目就立刻返回**。

    命中定义是「这一年有没有带 RMI 编号的名单」，不是「这一年最全的名单有多大」。
    所以不必把每份文档都解一遍——第一份带编号的就足以回答判据要问的问题。
    这是第一版跑 68 分钟没跑完的主因。
    """
    best = (0, 0, "")
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
        cids = sum(1 for r in rows if (r.get("cid") or "").strip())
        if cids > 0:
            return (len(rows), cids, url.rsplit("/", 1)[-1])
        if len(rows) > best[0]:
            best = (len(rows), 0, url.rsplit("/", 1)[-1])
    return best


def main() -> int:
    try:
        import form_sd_parse as parser
    except Exception as exc:                       # noqa: BLE001
        print(f"[XX] 载入解析器失败：{exc}")
        return 1

    with open(NODES_PATH, encoding="utf-8") as handle:
        payload = json.load(handle)
    stages = {s["id"]: s["label"] for s in (payload.get("stages") or [])}
    pool = [n for n in (payload.get("nodes") or [])
            if n.get("formSdStatus") == "filed-no-list" and n.get("cik")]
    pool.sort(key=lambda n: n.get("symbol") or "")
    if not pool:
        print("[XX] 节点表里没有「有申报无名单」的公司——判据无从谈起")
        return 1

    # ── 按环节分层取样 ───────────────────────────────────────────────────
    #
    # 不手挑（手挑会让阴性结果没有信息量，附件 21 的教训），但**也不能按代码
    # 排序取固定步长**：实测那样取出来材料加工从 10.1% 掉到 5.0%、分销从 8.2%
    # 掉到 3.3%，而材料加工恰恰是最可能有冶炼厂名单的环节。
    # **那个偏差会把命中率压低，方向正好是假阴性。**
    #
    # 所以按环节分层，每层内部再按代码排序取步长，保持各层占比与总体一致。
    by_stage: dict[str, list] = {}
    for node in pool:
        by_stage.setdefault(node.get("stage") or "未判定", []).append(node)
    sample = []
    for stage_id, members in sorted(by_stage.items(), key=lambda kv: -len(kv[1])):
        want = max(1, round(len(members) / len(pool) * SAMPLE))
        step = max(1, len(members) // want)
        sample.extend(members[::step][:want])
    sample = sample[:SAMPLE]
    print(f"「有申报无名单」共 {len(pool)} 家 · 按环节分层取样 {len(sample)} 家")
    print("  各层占比（总体 → 样本）：" + " · ".join(
        f"{stages.get(k, k)} {len(v) / len(pool) * 100:.0f}%→"
        f"{sum(1 for n in sample if (n.get('stage') or '未判定') == k) / max(1, len(sample)) * 100:.0f}%"
        for k, v in sorted(by_stage.items(), key=lambda kv: -len(kv[1]))[:5]))
    print(f"判据（探之前已写死）：命中率 ≥ {HIT_FLOOR * 100:.0f}% 才建；"
          f"回溯每家最多 {YEARS} 份 SD")
    print("命中定义：某一年解出 ≥1 条**带 RMI 编号**的冶炼厂条目\n")

    got = hit = only_one = no_filing = failed = 0
    hits: list[tuple] = []
    by_stage_hit: dict[str, int] = {}
    by_stage_all: dict[str, int] = {}
    for i, node in enumerate(sample, 1):
        symbol, cik = node.get("symbol"), int(node["cik"])
        label = stages.get(node.get("stage"), node.get("stage") or "未判定")
        by_stage_all[label] = by_stage_all.get(label, 0) + 1
        try:
            filings = sd_filings(cik, YEARS)
        except Exception as exc:                   # noqa: BLE001
            failed += 1
            if failed <= 5:
                print(f"[--] {symbol:6} 取申报清单失败：{why(exc)}")
            continue
        got += 1
        if not filings:
            no_filing += 1
            continue
        if len(filings) < 2:
            # 只有今年这一份，没有更早的可回溯——这不是「没命中」，是「没得比」。
            only_one += 1
            continue
        best_year = None
        for filing in filings[1:]:                 # 跳过最新那份（已知没名单）
            rows, cids, doc = first_with_cid(parser, cik, filing["accession"])
            if cids > 0:
                best_year = (filing["date"][:4], rows, cids, doc)
                break
        if best_year:
            hit += 1
            by_stage_hit[label] = by_stage_hit.get(label, 0) + 1
            hits.append((symbol, node.get("name") or symbol, *best_year))
            print(f"[OK] {symbol:6} {best_year[0]} 年有名单：{best_year[1]:4} 条"
                  f"（带编号 {best_year[2]:4}）· {best_year[3][:34]}")
        if i % 20 == 0:
            print(f"     … 已处理 {i}/{len(sample)}，命中 {hit}，"
                  f"请求用掉 {MAX_REQUESTS - BUDGET.left}")

    print("\n" + "─" * 74)
    if not got:
        # **取到 0 份就没有判决权。** 见文件头。
        print("[XX] **结论无效**：一家的申报清单都没取到。")
        print("     这是取数失败，不是业务事实——先修取数再重探，不得据此判死。")
        return 2

    comparable = got - only_one - no_filing
    rate = hit / max(1, comparable)
    print(f"取到申报清单 {got} 家 · 失败 {failed} 家")
    print(f"  其中只有一份 SD（没有更早的可回溯）{only_one} 家 · "
          f"一份都没有 {no_filing} 家")
    print(f"**可回溯的 {comparable} 家里，{hit} 家在更早年份列过名单 = "
          f"{rate * 100:.1f}%**")
    if by_stage_all:
        print("\n按环节（命中/取样）：")
        for label in sorted(by_stage_all, key=lambda k: -by_stage_all[k])[:8]:
            print(f"   {label:14} {by_stage_hit.get(label, 0):3}/{by_stage_all[label]:3}")
    if hits:
        total_cids = sum(h[4] for h in hits)
        print(f"\n命中的 {len(hits)} 家合计 {sum(h[3] for h in hits)} 条条目、"
              f"其中带编号 {total_cids} 条")
        print("最大的 8 家：")
        for sym, name, yr, rows, cids, doc in sorted(hits, key=lambda h: -h[4])[:8]:
            print(f"   {sym:6} {str(name)[:24]:26} {yr} 年 {rows:4} 条 "
                  f"（带编号 {cids:4}）")

    print("\n" + "─" * 74)
    if rate >= HIT_FLOOR:
        print(f"判据：命中率 {rate * 100:.1f}% ≥ {HIT_FLOOR * 100:.0f}% → **值得建**")
        print(f"按比例外推全部 {len(pool)} 家，约 {round(len(pool) * rate)} 家能补上名单"
              "（**只是量级参考**：取样是按代码排序的固定步长，不是随机抽样）")
    else:
        print(f"判据：命中率 {rate * 100:.1f}% < {HIT_FLOOR * 100:.0f}% → "
              "**收益不足，不建**，写进判决表")
    print(f"请求预算：用掉 {MAX_REQUESTS - BUDGET.left} / {MAX_REQUESTS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
