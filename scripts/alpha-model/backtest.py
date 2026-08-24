#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""回测与统计检验。

这是判定模型能不能用的唯一裁决处，所以刻意把三件容易自欺的事写死在代码里：

1. **重叠窗口**。60 日前瞻收益在日频上高度自相关，按日算 IC 会把有效样本量
   夸大约 60 倍，t 值虚高约 √60。``rank_ic_series`` 因此强制要求相邻评估日
   至少相隔 ``horizon`` 个交易日，重叠调用直接抛错，而不是给个警告。
2. **交易成本**。换手不计成本的年化收益没有意义。组合模拟必须传成本。
3. **验收线先写、结果后看**。``evaluate_gates`` 的阈值来自 config，
   跑之前就固定，避免看到结果再改标准。
"""

import math

from config import (
    BACKTEST_COST_BPS_ONE_WAY,
    DECILES,
    GATE_DECILE_SPEARMAN,
    GATE_IC_HIT_RATE,
    GATE_IC_IR,
    GATE_IC_MEAN,
    GATE_NET_SPREAD,
)
from factors import mean, pearson, stdev


class OverlappingWindowError(ValueError):
    """评估日间隔小于前瞻期，样本重叠，统计量不可信。"""


def _rank(values):
    """平均名次（1 起）；None 保持 None。"""
    present = [(i, v) for i, v in enumerate(values) if v is not None]
    out = [None] * len(values)
    present.sort(key=lambda p: p[1])
    n, i = len(present), 0
    while i < n:
        j = i
        while j + 1 < n and present[j + 1][1] == present[i][1]:
            j += 1
        avg = (i + j) / 2.0 + 1.0
        for k in range(i, j + 1):
            out[present[k][0]] = avg
        i = j + 1
    return out


def spearman(xs, ys):
    """秩相关。用秩而不是原值，因为模型解决的是排序问题，不是回归问题。"""
    pairs = [(x, y) for x, y in zip(xs, ys) if x is not None and y is not None]
    if len(pairs) < 5:
        return None
    rx = _rank([p[0] for p in pairs])
    ry = _rank([p[1] for p in pairs])
    return pearson(rx, ry)


def rank_ic_series(snapshots, horizon):
    """逐评估日算 Rank IC。

    ``snapshots``：[(交易日索引, [分数...], [未来超额收益...]), ...]，按日期升序。
    相邻评估日间隔必须 ≥ horizon，否则前瞻窗口重叠，抛 OverlappingWindowError。
    """
    ordered = sorted(snapshots, key=lambda s: s[0])
    for prev, cur in zip(ordered, ordered[1:]):
        if cur[0] - prev[0] < horizon:
            raise OverlappingWindowError(
                f"评估日 {prev[0]} 与 {cur[0]} 间隔 {cur[0] - prev[0]} < 前瞻 {horizon}，"
                "前瞻窗口重叠会使 IC 的 t 值虚高，请改用不重叠评估日")
    out = []
    for index, scores, labels in ordered:
        ic = spearman(scores, labels)
        if ic is not None:
            out.append((index, ic))
    return out


def ic_summary(ic_series):
    """IC 均值、标准差、信息比、胜率与样本数。"""
    values = [ic for _, ic in ic_series]
    if not values:
        return {"n": 0, "mean": None, "std": None, "ir": None, "hitRate": None}
    mu = mean(values)
    sd = stdev(values)
    return {
        "n": len(values),
        "mean": mu,
        "std": sd,
        "ir": (mu / sd) if (sd and sd > 0) else None,
        "hitRate": sum(1 for v in values if v > 0) / len(values),
        "tStat": (mu / (sd / math.sqrt(len(values)))) if (sd and sd > 0) else None,
    }


def decile_stats(scores, labels, k=DECILES):
    """按分数分 k 组，返回各组的平均未来超额收益与单调性秩相关。

    单调性比“Top10 赚钱”重要得多：只有 Top 组好、中间乱序，说明排名本身
    不可信，赚钱可能来自少数几只票的运气。
    """
    pairs = [(s, l) for s, l in zip(scores, labels) if s is not None and l is not None]
    if len(pairs) < k * 2:
        return None
    pairs.sort(key=lambda p: p[0], reverse=True)      # D1 = 分数最高
    n = len(pairs)
    groups = []
    for g in range(k):
        lo = g * n // k
        hi = (g + 1) * n // k
        chunk = pairs[lo:hi]
        groups.append({
            "decile": g + 1,
            "count": len(chunk),
            "meanScore": mean([c[0] for c in chunk]),
            "meanForward": mean([c[1] for c in chunk]),
        })
    monotonic = spearman([g["decile"] for g in groups],
                         [g["meanForward"] for g in groups])
    top, bottom = groups[0]["meanForward"], groups[-1]["meanForward"]
    return {
        "groups": groups,
        "monotonicSpearman": monotonic,   # 期望为负：组号越大收益越低
        "topMinusBottom": (top - bottom) if (top is not None and bottom is not None) else None,
    }


def simulate_portfolio(rebalances, top_n, cost_bps_one_way=BACKTEST_COST_BPS_ONE_WAY,
                       spacing_days=21):
    """等权 Top-N 组合模拟。

    ``rebalances``：[(日期, {代码: 分数}, {代码: 持有到下次调仓的超额收益}), ...]
    持有到下一次调仓，因此收益序列不重叠，可以直接连乘。
    ``spacing_days`` 是调仓间隔（交易日），只用于把每期指标年化。

    成本口径：换手率取“被替换掉的仓位比例”，卖出与买入各付一次单边成本，
    所以本期成本 = 2 × 换手率 × 单边费率。
    """
    equity, held = 1.0, set()
    periods = []
    for date, scores, forwards in rebalances:
        ranked = sorted(((s, t) for t, s in scores.items() if s is not None), reverse=True)
        picks = [t for _, t in ranked[:top_n]]
        if not picks:
            continue

        returns = [forwards[t] for t in picks if forwards.get(t) is not None]
        gross = mean(returns) if returns else 0.0

        turnover = len(set(picks) - held) / len(picks)
        cost = 2.0 * turnover * (cost_bps_one_way / 10_000.0)
        net = gross - cost
        equity *= (1.0 + net)

        periods.append({
            "date": date,
            "names": len(picks),
            "priced": len(returns),
            "grossExcess": gross,
            "turnover": turnover,
            "cost": cost,
            "netExcess": net,
            "equity": equity,
        })
        held = set(picks)

    if not periods:
        return None
    nets = [p["netExcess"] for p in periods]
    sd = stdev(nets)
    per_year = 252.0 / max(1, spacing_days)
    return {
        "periods": periods,
        "rebalances": len(periods),
        "cumulativeExcess": equity - 1.0,
        "meanExcessPerPeriod": mean(nets),
        "hitRate": sum(1 for v in nets if v > 0) / len(nets),
        "avgTurnover": mean([p["turnover"] for p in periods]),
        "annualTurnover": mean([p["turnover"] for p in periods]) * per_year,
        "informationRatio": (mean(nets) / sd * math.sqrt(per_year)) if (sd and sd > 0) else None,
        "worstPeriod": min(nets),
        "maxDrawdown": _equity_drawdown([p["equity"] for p in periods]),
        "costDrag": sum(p["cost"] for p in periods),
    }


def _equity_drawdown(equities):
    peak, worst = None, 0.0
    for value in equities:
        peak = value if peak is None else max(peak, value)
        if peak > 0:
            worst = max(worst, 1.0 - value / peak)
    return worst


def evaluate_gates(ic, deciles, portfolio):
    """对照 config 里预先写死的验收线逐条判定，返回 (是否通过, 明细)。"""
    checks = []

    def add(name, ok, detail):
        checks.append({"name": name, "pass": bool(ok), "detail": detail})

    add("IC均值", ic.get("mean") is not None and ic["mean"] > GATE_IC_MEAN,
        f"{ic.get('mean')} > {GATE_IC_MEAN}")
    add("IC信息比", ic.get("ir") is not None and ic["ir"] > GATE_IC_IR,
        f"{ic.get('ir')} > {GATE_IC_IR}")
    add("IC胜率", ic.get("hitRate") is not None and ic["hitRate"] > GATE_IC_HIT_RATE,
        f"{ic.get('hitRate')} > {GATE_IC_HIT_RATE}")

    mono = (deciles or {}).get("monotonicSpearman")
    add("分组单调性", mono is not None and mono < -GATE_DECILE_SPEARMAN,
        f"{mono} < {-GATE_DECILE_SPEARMAN}")

    spread = (deciles or {}).get("topMinusBottom")
    add("多空价差", spread is not None and spread > GATE_NET_SPREAD,
        f"{spread} > {GATE_NET_SPREAD}")

    net = (portfolio or {}).get("cumulativeExcess")
    add("扣成本后组合超额", net is not None and net > 0,
        f"{net} > 0")

    return all(c["pass"] for c in checks), checks
