#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""取标普成分股的 SEC 实体标识：CIK 与 SIC 行业码，写入 apps/supply-chain/identity.json。

## 为什么单独一步

第 0 层的阶段判定只有 GICS 一级板块可用，313/495 个节点只能给候选集。SIC 码能把它们
分开（实测：苹果 3571 品牌整合 / 英伟达 3674 中间制造 / 微软 7372 平台服务）。

但取 SIC 要联网，而 `build_chain_nodes.py` 是纯离线、可本地复算的。因此拆成两步：
本脚本负责联网取回并缓存，构建脚本只读缓存，**缓存缺失时自动退回板块级口径**，
不会因为一次取数失败就产出空数据或让整条管道失败。

CIK 同时是将来建边的实体锚点——关系边必须指向标识符，不能指向公司名。实测教训：
EDGAR 里同一个 CIK 有多种历史名称写法（`Apple Inc.` 与 `APPLE INC`），按名字比对会漏。

## 合规

SEC 要求声明身份的 User-Agent 并限速每秒 10 次。本脚本间隔远低于上限，联系方式从
环境变量读取，不硬编码任何个人邮箱。取数失败时保留上一份有效缓存，不用空值覆盖。
"""
from __future__ import annotations

import json
import os
import sys
import time
from urllib import error, request

TIMEOUT = 30
GAP = 0.25                 # 495 家约 2 分钟，远低于 SEC 每秒 10 次上限
MIN_SUCCESS_RATIO = 0.8    # 成功率低于此值视为整体失败，保留旧缓存

CONTACT = os.environ.get("SEC_CONTACT", "contact via https://www.ooglex.com")
UA = f"Ooglex Supply Chain Research/1.0 ({CONTACT})"

SP500_PATH = "apps/companies/sp500.json"
OUT_PATH = "apps/supply-chain/identity.json"
TICKER_MAP_URL = "https://www.sec.gov/files/company_tickers.json"


def _get_json(url: str) -> dict:
    req = request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with request.urlopen(req, timeout=TIMEOUT) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def load_previous() -> dict:
    try:
        with open(OUT_PATH, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


def main() -> int:
    with open(SP500_PATH, encoding="utf-8") as handle:
        members = json.load(handle).get("members") or []
    tickers = [m["symbol"] for m in members if m.get("symbol")]
    if not tickers:
        print(f"[XX] {SP500_PATH} 里没有成分股，中止")
        return 1

    print(f"标普成分股 {len(tickers)} 个，开始解析 CIK 与 SIC")
    try:
        payload = _get_json(TICKER_MAP_URL)
    except Exception as exc:                       # noqa: BLE001
        print(f"[XX] ticker→CIK 映射表取不到：{exc}；保留上一份缓存")
        return 0
    index = {str(row["ticker"]).upper(): row.get("cik_str")
             for row in payload.values() if isinstance(row, dict) and row.get("ticker")}

    previous = load_previous()
    prior_entries = previous.get("companies") or {}
    entries: dict[str, dict] = {}
    failed: list[str] = []
    for i, ticker in enumerate(tickers, 1):
        cik = index.get(ticker.upper())
        if not cik:
            failed.append(ticker)
            continue
        url = f"https://data.sec.gov/submissions/CIK{int(cik):010d}.json"
        try:
            sub = _get_json(url)
            entries[ticker] = {
                "cik": int(cik),
                "sic": int(sub["sic"]) if str(sub.get("sic", "")).isdigit() else None,
                "sicDescription": sub.get("sicDescription"),
                # SEC 按公众持股量给的申报人分档。站内报价只覆盖标普这一池，
                # 扩到 5,897 家之后是 8%——这条轴 100% 覆盖，且是政府分类，
                # 三个池都存同一个字段，页面才能按同一把尺子比。
                "filerCategory": (sub.get("category") or "").strip() or None,
                "secName": sub.get("name"),
            }
        except Exception as exc:                   # noqa: BLE001
            # 单家失败沿用上一份有效值并标记，不让一次抖动抹掉已有数据
            kept = prior_entries.get(ticker)
            if kept:
                entries[ticker] = {**kept, "stale": True}
            failed.append(f"{ticker}({type(exc).__name__})")
        if i % 100 == 0:
            print(f"    已处理 {i}/{len(tickers)}")
        time.sleep(GAP)

    resolved = [t for t, v in entries.items() if v.get("sic")]
    ratio = len(resolved) / len(tickers) if tickers else 0.0
    print(f"解析成功 {len(entries)}/{len(tickers)}，其中带 SIC {len(resolved)}（{ratio:.1%}）")
    if failed:
        print(f"失败 {len(failed)} 家：{', '.join(failed[:15])}")

    if ratio < MIN_SUCCESS_RATIO:
        print(f"[XX] SIC 覆盖率 {ratio:.1%} 低于阈值 {MIN_SUCCESS_RATIO:.0%}，"
              f"判定为整体失败，保留上一份缓存不覆盖")
        return 1

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as handle:
        json.dump({
            "contractVersion": 1,
            "dataset": "supply-chain-identity",
            "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "source": "SEC EDGAR company_tickers.json + data.sec.gov/submissions",
            "sourceUrl": "https://www.sec.gov/os/accessing-edgar-data",
            "expected": len(tickers),
            "resolved": len(entries),
            "withSic": len(resolved),
            "failed": failed,
            "note": ("CIK 是建边时的实体锚点——关系必须指向标识符不能指向公司名，"
                     "EDGAR 同一 CIK 存在多种历史名称写法。"),
            "companies": entries,
        }, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(f"已写入 {OUT_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
