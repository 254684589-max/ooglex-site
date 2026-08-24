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


def newey_west_se(values, lag):
    """Newey–West 修正后的均值标准误。

    重叠窗口的 IC 序列高度自相关，直接用 std/√n 会把标准误严重低估、t 值虚高。
    Newey–West 用带 Bartlett 权重的自协方差把这部分补回来，
    因此可以**既用上全部重叠样本（拿回统计功效），又不虚报显著性**。

    这是对原设计的修正：此前强制不重叠窗口，统计上干净，但 5 年历史只剩
    16 个独立样本——标准误 0.049，连 IC=0.02 这种量级都测不出来。
    把评估密度提上去 + NW 修正，才是真正能做判断的做法。
    """
    values = [v for v in values if v is not None]
    n = len(values)
    if n < 3:
        return None
    mu = sum(values) / n
    dev = [v - mu for v in values]

    def autocov(k):
        return sum(dev[i] * dev[i - k] for i in range(k, n)) / n

    variance = autocov(0)
    for k in range(1, min(lag, n - 1) + 1):
        weight = 1.0 - k / (lag + 1.0)          # Bartlett 核
        variance += 2.0 * weight * autocov(k)
    if variance <= 0:
        return None
    return math.sqrt(variance / n)


def rank_ic_series_dense(snapshots):
    """允许重叠的 IC 序列。显著性必须配 ``newey_west_se`` 使用，不可用普通标准误。"""
    out = []
    for index, scores, labels in sorted(snapshots, key=lambda s: s[0]):
        ic = spearman(scores, labels)
        if ic is not None:
            out.append((index, ic))
    return out


def factor_ic_table(factor_snapshots, nw_lag):
    """逐因子 IC 分解：composite 失败时，用它定位是哪些因子在拖后腿。

    ``factor_snapshots``：{因子名: [(评估日, IC), ...]}
    按 IC 均值降序返回，附 Newey–West t 值。
    """
    table = []
    for name, series in factor_snapshots.items():
        values = [ic for _, ic in series]
        if len(values) < 5:
            continue
        mu = mean(values)
        sd = stdev(values)
        se = newey_west_se(values, nw_lag)
        table.append({
            "factor": name,
            "n": len(values),
            "mean": mu,
            "std": sd,
            "ir": (mu / sd) if (sd and sd > 0) else None,
            "tStat": (mu / se) if (se and se > 0) else None,
            "hitRate": sum(1 for v in values if v > 0) / len(values),
        })
    table.sort(key=lambda r: (r["mean"] is None, -(r["mean"] or 0)))
    return table


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


def ic_summary(ic_series, nw_lag=None):
    """IC 均值、标准差、信息比、胜率与样本数。"""
    values = [ic for _, ic in ic_series]
    if not values:
        return {"n": 0, "mean": None, "std": None, "ir": None, "hitRate": None}
    mu = mean(values)
    sd = stdev(values)
    naive_se = (sd / math.sqrt(len(values))) if (sd and sd > 0) else None
    nw_se = newey_west_se(values, nw_lag) if nw_lag else None
    se = nw_se or naive_se
    return {
        "n": len(values),
        "mean": mu,
        "std": sd,
        "ir": (mu / sd) if (sd and sd > 0) else None,
        "hitRate": sum(1 for v in values if v > 0) / len(values),
        "stdError": se,
        "neweyWest": nw_se is not None,
        "tStat": (mu / se) if (se and se > 0) else None,
        "ci95": [mu - 1.96 * se, mu + 1.96 * se] if se else None,
        # |t| < 2 时，无论均值是正是负都不能下结论——只能说"测不出来"
        "distinguishableFromZero": bool(se and abs(mu / se) > 2.0),
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
    # 这条不是新门槛，是把"没通过"和"测不出来"分开：|t|<2 时前五条都无意义
    add("IC可与0区分", ic.get("distinguishableFromZero") is True,
        f"|t|={abs(ic['tStat']):.2f} > 2" if ic.get("tStat") is not None else "t值不可得")

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
