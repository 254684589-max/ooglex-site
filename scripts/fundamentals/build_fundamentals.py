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

# ── 单位：站内市值是「十亿美元」，SEC 报表项是原始美元 ──────────────────────
# apps/companies/data.json 里 marketCap 写的是 round(cap_usd / 1e9, 1)
# （见 scripts/companies/build_companies.py），而**这件事没有在 JSON 里声明**。
# 第一版直接拿 marketCap ÷ equity，算出 AAPL 的 PB = 5.5e-08 —— 量级差了 1e9。
# 所以这里显式换算，并且在 sanity_check 里**断言这个假设仍然成立**：
# 哪天上游改成原始美元，断言会先炸，而不是静默产出错 9 个数量级的比率。
MARKET_CAP_UNIT = 1e9

# ── 「像不像真的」：闸门原来只问「有没有值」，不问「值合不合理」 ────────────
# 第一版放过了一份 PB 中位数 4.6e-09、PE 一家都没有的文件，因为 debtToAssets
# 单独一项就把「至少有一个比率」的计数凑够了。数值范围与逐项覆盖两条一起补上。
#   区间给得很宽 —— 目的是拦「单位错了」「口径错了」这种整体性错误，
#   不是替读者判断某家公司贵不贵。
SANE_MEDIAN = {
    "pe":           (2.0, 200.0),      # 市盈率
    "pb":           (0.2, 60.0),        # 市净率
    "ps":           (0.1, 60.0),        # 市销率
    "roe":          (-50.0, 80.0),      # %
    "netMargin":    (-50.0, 70.0),      # %
    "debtToAssets": (5.0, 95.0),        # %
}
# 逐项最少要算出多少家。这几项都是美国大型申报人普遍披露的，覆盖面塌到个位数
# 就说明取数或口径出了问题，而不是「这些公司恰好没披露」。
MIN_PER_RATIO = {"pb": 100, "debtToAssets": 100, "roe": 80, "netMargin": 80, "ps": 80}


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


def median(vals):
    s = sorted(vals)
    n = len(s)
    if not n:
        return None
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2


def sanity_check(rows) -> list[str]:
    """落盘前问一句「这些数字像不像真的」。

    闸门原来只问「有没有值」。第一版因此放过了一份 PB 中位数 4.6e-09、
    PE 一家都没有的文件 —— 单位差了 1e9、EPS 标签的 URL 写错，两个错都不影响
    「至少有一个比率」的计数。所以这里加两条：

      1. **逐项覆盖面**：普遍披露的项塌到个位数，是取数坏了，不是公司没披露。
      2. **中位数落在合理区间**：区间给得很宽，拦的是「单位错了」「口径错了」
         这类整体性错误，不替读者判断某家公司贵不贵。

    另外顺手复核 MARKET_CAP_UNIT 这个假设本身：站内市值是十亿美元这件事
    **没有写在 JSON 里**，哪天上游改成原始美元，这里要先炸。
    """
    live = [r for r in rows if r.get("available")]
    problems = []
    for key, floor in sorted(MIN_PER_RATIO.items()):
        n = sum(1 for r in live if r.get(key) is not None)
        if n < floor:
            problems.append(f"{key} 只算出 {n} 家，低于下限 {floor} 家")
    for key, (lo, hi) in sorted(SANE_MEDIAN.items()):
        vals = [r[key] for r in live if isinstance(r.get(key), (int, float))]
        if not vals:
            continue
        m = median(vals)
        if not (lo <= m <= hi):
            problems.append(
                f"{key} 中位数 {m:.4g} 不在合理区间 [{lo}, {hi}]（{len(vals)} 家）"
                f"—— 这种整体性偏离通常是单位或口径错了，不是市场如此")
    # PE 是最容易被 URL 单位串写错而全空的一项，单独点名
    if not any(r.get("pe") is not None for r in live):
        problems.append(
            "PE 一家都没算出来 —— 检查 EarningsPerShareDiluted 的 frames 单位串"
            "（应是 USD-per-shares，写成 USD/shares 会把 URL 路径切断）")
    return problems


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

        # 报价不是美元就不算 PE：站内 price 对非美元公司记的是**上市地本币**
        # （data.json 的 note 自己写明了），而 SEC 的 EPS 是美元 —— 两者相除
        # 得到的不是 PE，是一个混了汇率的无意义数。逐行按 priceCur 判断。
        cur = c.get("priceCur")
        pe = ratio(price, f.get("epsDiluted")) if cur in (None, "USD") else None
        if cur not in (None, "USD"):
            skip(f"报价为 {cur} 非美元，不与美元 EPS 相除")
        cap_usd = cap * MARKET_CAP_UNIT if num(cap) else None
        pb = ratio(cap_usd, f.get("equity"))
        ps = ratio(cap_usd, f.get("revenue"))
        # ROE 的分母用「与利润表同财年」的权益，不是最新那一期 —— 否则是
        # 2024 年的净利除 2025 年末的权益，混了两个时点。取不到就不给 ROE。
        roe = ratio(f.get("netIncome"), f.get("equityAligned"))
        if f.get("netIncome") is not None and f.get("equityAligned") is None:
            skip("无同期权益，不给 ROE（不拿跨期的权益当分母）")
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
                "equityAligned": f.get("equityAligned"),
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

    bad = sanity_check(out_rows)
    if bad:
        return bail("落盘前的合理性检查不通过：" + "；".join(bad), prev)

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
        "tagCoverage": got.get("coverage") or {},
        "method": {
            "pe": "价格 ÷ 稀释每股收益（报表期，非前瞻）",
            "pb": "市值 ÷ 最新一期股东权益（市值已由站内的十亿美元换算成美元；"
                  "市价是今天的，所以账面取最近一期，与 ROE 的分母口径不同，各自写明）",
            "ps": "市值 ÷ 营收（同上）",
            "roe": "净利 ÷ 同财年末股东权益（分母与分子同期，不用最新那一期）",
            "netMargin": "净利 ÷ 营收",
            "debtToAssets": "负债 ÷ 资产",
            "nonPositiveDenominator": "分母非正时不给数 —— 负权益的 PB、负 EPS 的 PE 不是「便宜」",
        },
        "note": ("报表项来自公司向 SEC 递交的 XBRL 披露，季/年频、最长滞后数月；"
                 "价格与市值来自站内日频收盘。所以这些比率是「今天的价格 ÷ 上一期报表」，"
                 "逐条带 statementEnd 与 priceAsOf 两个日期，请对照看。"
                 "覆盖面只有美国申报人：非美申报人或只发 ADR 的公司 available=false，"
                 "缺的字段是 null 而不是 0。比率全部由本站按 method 段的公式现算，"
                 "非任何第三方计算结果。同类报表项统一取同一个期间（periodsUsed），"
                 "避免营收来自一个年度、净利来自另一个年度拼出假的利润率。"
                 "利润表与资产负债表各自按覆盖面挑期，可能不是同一财年（见 periodsUsed）；"
                 "因此 ROE 另取「与利润表同财年」的权益当分母，而 PB 用最新一期权益 —— "
                 "两者分母口径不同，method 段逐条写明。"
                 "报价非美元的公司不算 PE（站内价格记的是上市地本币，与美元 EPS 不可相除）。"
                 "仅供研究参考，不构成投资建议。"),
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
