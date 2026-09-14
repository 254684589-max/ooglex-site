#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建基本面数据 → apps/companies/fundamentals.json。

比率全部在这里由报表项现算，口径写在输出里、也写在页面上：

    PE   = 价格 / 稀释每股收益          （报表期 EPS，不是前瞻）
    PB   = 市值 / 股东权益
    PS   = 市值 / 营收
    ROE  = 净利 / 股东权益
    净利率 = 净利 / 营收
    负债率 = 负债 / 资产

价格与市值取自已有的 apps/companies/data.json（日频收盘），**报表项是季/年频、
最长滞后数月** —— 所以这些比率是「今天的价格 ÷ 上一期报表」，输出里逐条带上报表
期末日期，页面必须照实显示。

## 三条保护（照 build_companies.py 的既有规矩）

1. **取不到就是 None，绝不写 0。** 0 是一个有意义的值。
2. **整轮取数失败或覆盖率异常低时，保留上一份 JSON 不覆盖。** 宁可数据旧，
   不可用半份数据洗掉好数据。
3. **算出来离谱的值不写。** 负权益算出的 PB、EPS 为负算出的 PE 都没有意义，
   一律置 None 并记下原因，不把负数当成「便宜」摆出去。

由 .github/workflows/fundamentals.yml 手动触发运行。**刻意没有加进
scheduler.yml** —— 第一次真实运行应该由 owner 看着跑完、确认数据对，再决定要不要
进每日轮转。
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS_DIR = os.path.dirname(HERE)
ROOT = os.path.dirname(SCRIPTS_DIR)
sys.path.insert(0, HERE)
sys.path.insert(0, SCRIPTS_DIR)

from adapter_sec import AdapterError, fetch as adapter_fetch, DOC_URL, SOURCE_NAME  # noqa: E402
from market_data_quality import make_data_meta, summarize_data_quality  # noqa: E402

COMPANIES = os.path.join(ROOT, "apps", "companies", "data.json")
OUT_PATH = os.path.join(ROOT, "apps", "companies", "fundamentals.json")

# 覆盖率下限：命中率低于这个数就认为是限流或结构变化，保留上一份不覆盖。
MIN_MATCH_RATE = 0.35
MIN_RATIO_ROWS = 50


def load_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError):
        return None


def num(x):
    return isinstance(x, (int, float)) and x == x and abs(x) != float("inf")


def ratio(numer, denom, *, positive_denom_only=True):
    """安全除法。分母非正时返回 None —— 负权益算出的 PB、负 EPS 算出的 PE
       都不是「便宜」，把它们摆出去是误导。"""
    if not num(numer) or not num(denom):
        return None
    if denom == 0:
        return None
    if positive_denom_only and denom <= 0:
        return None
    v = numer / denom
    if not num(v):
        return None
    return v


def bail(reason: str, prev) -> int:
    """闸门统一出口：说清原因、保留上一份、给出正确的退出码。

    原因同时用 `::error::` 打出来 —— 否则它只在步骤日志里，GitHub 的运行摘要
    只显示一句「Process completed with exit code 1」，等于把真正的原因藏起来。
    """
    print(f"::error::{reason}")
    print(reason, file=sys.stderr)
    if prev:
        msg = "保留上一份 fundamentals.json 不覆盖（宁可数据旧，不用半份数据洗掉好数据）"
        print(f"::error::{msg}")
        print(msg, file=sys.stderr)
        return 0
    msg = "且没有上一份可保留 —— 不写任何文件"
    print(f"::error::{msg}")
    print(msg, file=sys.stderr)
    return 1


def main() -> int:
    comp = load_json(COMPANIES)
    if not comp or not isinstance(comp.get("companies"), list):
        print("apps/companies/data.json 读不到或结构不对，不继续", file=sys.stderr)
        return 1
    rows = [c for c in comp["companies"]
            if isinstance(c, dict) and c.get("symbol") and c["symbol"] != "—"]
    symbols = [c["symbol"] for c in rows]
    print(f"站内可申报标的 {len(symbols)} 个")

    prev = load_json(OUT_PATH)
    now = datetime.now(timezone.utc)
    year = now.year

    try:
        got = adapter_fetch(symbols, year=year, log=print)
    except AdapterError as exc:
        return bail(f"取数失败：{exc}", prev)
    except Exception as exc:
        # 兜底：adapter 本该把一切收敛成 AdapterError，但万一漏了一个异常型，
        # 这里也不能让它带着 traceback 崩掉 —— 那样就绕过了「保留上一份」这条
        # 保护路径。第一版的 UnicodeDecodeError 正是这样漏出去的。
        return bail(f"取数时抛出未预期的 {type(exc).__name__}：{exc}", prev)

    facts = got["rows"]
    rate = got["matched"] / max(got["requested"], 1)
    print(f"CIK 命中率 {rate:.1%}（{got['matched']}/{got['requested']}）")
    if rate < MIN_MATCH_RATE:
        return bail(f"CIK 命中率 {rate:.1%} 低于下限 {MIN_MATCH_RATE:.0%}，疑似限流或结构变化", prev)

    out_rows, with_ratio, skipped = [], 0, {}

    def skip(why):
        skipped[why] = skipped.get(why, 0) + 1

    for c in rows:
        sym = c["symbol"]
        f = facts.get(sym.upper())
        price = c.get("price")
        cap = c.get("marketCap")
        if not f:
            out_rows.append({
                "symbol": sym,
                "available": False,
                "reason": "SEC 无此申报人（非美申报人或只发 ADR）",
                "dataMeta": make_data_meta(
                    "unavailable", SOURCE_NAME, as_of=None,
                    updated_at=now.isoformat(timespec="seconds"),
                    frequency="quarterly", note="站内无此公司的 SEC 申报"),
            })
            skip("SEC 无此申报人")
            continue

        pe = ratio(price, f.get("epsDiluted"))
        pb = ratio(cap, f.get("equity"))
        ps = ratio(cap, f.get("revenue"))
        roe = ratio(f.get("netIncome"), f.get("equity"))
        margin = ratio(f.get("netIncome"), f.get("revenue"))
        debt = ratio(f.get("liabilities"), f.get("assets"))

        if num(f.get("epsDiluted")) and f["epsDiluted"] <= 0 and pe is None:
            skip("EPS 非正，不给 PE")
        if num(f.get("equity")) and f["equity"] <= 0 and pb is None:
            skip("权益非正，不给 PB")

        ends = f.get("ends") or {}
        as_of = max([v for v in ends.values() if isinstance(v, str)], default=None)
        has_any = any(x is not None for x in (pe, pb, ps, roe, margin, debt))
        if has_any:
            with_ratio += 1

        out_rows.append({
            "symbol": sym,
            "available": True,
            "cik": f.get("cik"),
            "pe": pe, "pb": pb, "ps": ps,
            "roe": None if roe is None else roe * 100,
            "netMargin": None if margin is None else margin * 100,
            "debtToAssets": None if debt is None else debt * 100,
            "raw": {
                "revenue": f.get("revenue"), "netIncome": f.get("netIncome"),
                "equity": f.get("equity"), "assets": f.get("assets"),
                "liabilities": f.get("liabilities"), "epsDiluted": f.get("epsDiluted"),
            },
            "statementEnd": as_of,
            "priceAsOf": (c.get("dataMeta") or {}).get("asOf"),
            "dataMeta": make_data_meta(
                "market" if has_any else "unavailable", SOURCE_NAME,
                as_of=as_of, updated_at=now.isoformat(timespec="seconds"),
                frequency="quarterly",
                status="ok" if has_any else "error",
                note="比率由报表项与站内价格现算；报表期末见 statementEnd"),
        })

    print(f"算出至少一个比率的 {with_ratio} 家；跳过原因：{skipped}")
    if with_ratio < MIN_RATIO_ROWS:
        return bail(f"能算出比率的只有 {with_ratio} 家，不足下限 {MIN_RATIO_ROWS} 家", prev)

    payload = {
        "updatedAt": now.isoformat(timespec="seconds"),
        "asOf": max([r.get("statementEnd") for r in out_rows
                     if isinstance(r.get("statementEnd"), str)], default=None),
        "source": SOURCE_NAME,
        "sourceUrl": DOC_URL,
        "frequency": "quarterly",
        "status": "ok",
        "count": len(out_rows),
        "withRatio": with_ratio,
        "periodsUsed": got["periods"],
        "method": {
            "pe": "价格 ÷ 稀释每股收益（报表期，非前瞻）",
            "pb": "市值 ÷ 股东权益",
            "ps": "市值 ÷ 营收",
            "roe": "净利 ÷ 股东权益",
            "netMargin": "净利 ÷ 营收",
            "debtToAssets": "负债 ÷ 资产",
            "nonPositiveDenominator": "分母非正时不给数 —— 负权益的 PB、负 EPS 的 PE 不是「便宜」",
        },
        "note": ("报表项来自公司向 SEC 递交的 XBRL 披露，季/年频、最长滞后数月；"
                 "价格与市值来自站内日频收盘。所以这些比率是「今天的价格 ÷ 上一期报表」，"
                 "逐条带 statementEnd 与 priceAsOf 两个日期，请对照看。"
                 "覆盖面只有美国申报人：非美申报人或只发 ADR 的公司 available=false，"
                 "缺的字段是 null 而不是 0。比率全部由本站按 method 段的公式现算，"
                 "非任何第三方计算结果。仅供研究参考，不构成投资建议。"),
        "dataQuality": summarize_data_quality(out_rows),
        "rows": out_rows,
    }

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, separators=(",", ":"))
        fh.write("\n")
    print(f"已写出 {OUT_PATH}：{len(out_rows)} 行，其中 {with_ratio} 行有比率")
    return 0


if __name__ == "__main__":
    sys.exit(main())
