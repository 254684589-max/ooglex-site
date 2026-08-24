#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""因子计算：纯函数，只用标准库，不引入 numpy/pandas。

约定（这是整个模型不出未来函数的关键）：
  · 序列按日期升序排列，索引 t 表示“第 t 个交易日收盘后”。
  · 本模块所有 ``factor_*`` 与 ``compute_price_factors`` 只允许读取 [0, t]。
    任何读取 t 之后数据的函数都必须叫 ``forward_*``，并且只在回测里用于生成标签。
  · 数据不足以定义某个因子时返回 ``None``，不返回 0、不返回中位数。
    “不知道”和“中性”是两回事，混淆它们会在过滤阶段系统性偏向缺数据的股票。
"""

import math


# --------------------------------------------------------------------------
# 基础统计
# --------------------------------------------------------------------------
def mean(values):
    values = [v for v in values if v is not None]
    return sum(values) / len(values) if values else None


def stdev(values):
    """样本标准差；样本量不足 2 返回 None。"""
    values = [v for v in values if v is not None]
    if len(values) < 2:
        return None
    mu = sum(values) / len(values)
    var = sum((v - mu) ** 2 for v in values) / (len(values) - 1)
    return math.sqrt(var)


def quantile(values, q):
    """线性插值分位数；空序列返回 None。q 取 [0, 1]。"""
    values = sorted(v for v in values if v is not None)
    if not values:
        return None
    if len(values) == 1:
        return values[0]
    pos = q * (len(values) - 1)
    low = int(math.floor(pos))
    high = int(math.ceil(pos))
    if low == high:
        return values[low]
    return values[low] + (values[high] - values[low]) * (pos - low)


def pearson(xs, ys):
    """两序列的皮尔逊相关；方差为 0 或样本不足返回 None。"""
    pairs = [(x, y) for x, y in zip(xs, ys) if x is not None and y is not None]
    if len(pairs) < 3:
        return None
    n = len(pairs)
    mx = sum(p[0] for p in pairs) / n
    my = sum(p[1] for p in pairs) / n
    num = sum((p[0] - mx) * (p[1] - my) for p in pairs)
    dx = math.sqrt(sum((p[0] - mx) ** 2 for p in pairs))
    dy = math.sqrt(sum((p[1] - my) ** 2 for p in pairs))
    if dx <= 0 or dy <= 0:
        return None
    return num / (dx * dy)


def daily_returns(closes, start, end):
    """closes[start..end] 的逐日收益；start 必须 ≥ 1。"""
    out = []
    for i in range(max(start, 1), end + 1):
        prev, cur = closes[i - 1], closes[i]
        if prev is None or cur is None or prev <= 0:
            continue
        out.append(cur / prev - 1.0)
    return out


# --------------------------------------------------------------------------
# 单个因子（全部只读 [0, t]）
# --------------------------------------------------------------------------
def factor_return(closes, t, lookback, skip=0):
    """区间收益：closes[t-skip] / closes[t-skip-lookback] − 1。

    ``skip`` 用于跳过最近若干日。动量用 skip=21 剔除最近 1 个月，
    因为短期反转会污染中期动量，这是 Jegadeesh–Titman 之后的标准处理。
    """
    end = t - skip
    begin = end - lookback
    if begin < 0 or end < 0 or end >= len(closes):
        return None
    a, b = closes[begin], closes[end]
    if a is None or b is None or a <= 0:
        return None
    return b / a - 1.0


def factor_sma_gap(closes, t, window):
    """收盘价相对 window 日均线的偏离度。"""
    if t + 1 < window:
        return None
    seg = [c for c in closes[t - window + 1:t + 1] if c is not None and c > 0]
    if len(seg) < window * 0.9 or closes[t] is None:
        return None
    avg = sum(seg) / len(seg)
    return closes[t] / avg - 1.0 if avg > 0 else None


def factor_volatility(closes, t, window):
    """年化已实现波动率（越小越好，调用方负责取负号）。"""
    if t < window:
        return None
    rets = daily_returns(closes, t - window + 1, t)
    if len(rets) < window * 0.8:
        return None
    sd = stdev(rets)
    return sd * math.sqrt(252) if sd is not None else None


def factor_max_drawdown(closes, t, window):
    """window 日内最大回撤，返回正数（0.25 表示最深跌 25%）。"""
    if t + 1 < window:
        return None
    seg = [c for c in closes[t - window + 1:t + 1] if c is not None and c > 0]
    if len(seg) < window * 0.8:
        return None
    peak, worst = seg[0], 0.0
    for price in seg:
        peak = max(peak, price)
        worst = max(worst, 1.0 - price / peak)
    return worst


def factor_downside_deviation(closes, t, window):
    """只用负收益算的下行波动率（年化）。"""
    if t < window:
        return None
    rets = daily_returns(closes, t - window + 1, t)
    negatives = [r for r in rets if r < 0]
    if len(negatives) < 5:
        return None
    sd = math.sqrt(sum(r * r for r in negatives) / len(negatives))
    return sd * math.sqrt(252)


def factor_tail_loss(closes, t, window):
    """尾部风险：过去 window 日收益的 1% 分位数的绝对值。"""
    if t < window:
        return None
    rets = daily_returns(closes, t - window + 1, t)
    if len(rets) < window * 0.8:
        return None
    q = quantile(rets, 0.01)
    return abs(q) if q is not None else None


def factor_volume_expansion(volumes, t, short=20, long=120):
    """量能扩张：ADV20 / ADV120 − 1。

    用股数而不是成交额：成交额里含价格涨幅，会把动量重复算进量能因子。
    """
    if t + 1 < long:
        return None
    s = mean(volumes[t - short + 1:t + 1])
    l = mean(volumes[t - long + 1:t + 1])
    if not s or not l or l <= 0:
        return None
    return s / l - 1.0


def factor_accumulation(closes, volumes, t, window=60):
    """吸筹比：上涨日均量 / 下跌日均量。>1 说明买盘更积极。"""
    if t < window:
        return None
    up, down = [], []
    for i in range(t - window + 1, t + 1):
        prev, cur, vol = closes[i - 1], closes[i], volumes[i]
        if prev is None or cur is None or vol is None or prev <= 0:
            continue
        (up if cur > prev else down).append(vol)
    if len(up) < 5 or len(down) < 5:
        return None
    mu_up, mu_down = mean(up), mean(down)
    if not mu_down or mu_down <= 0:
        return None
    return mu_up / mu_down


def factor_near_52w_high(closes, t, window=252):
    """当前价 / 过去一年最高价，取值 (0, 1]。"""
    if t + 1 < window:
        return None
    seg = [c for c in closes[t - window + 1:t + 1] if c is not None and c > 0]
    if not seg or closes[t] is None:
        return None
    high = max(seg)
    return closes[t] / high if high > 0 else None


def factor_volume_confirm(closes, volumes, t, window=60):
    """量价配合度：日收益与成交量变化率的相关系数。"""
    if t < window + 1:
        return None
    rets, dvol = [], []
    for i in range(t - window + 1, t + 1):
        prev, cur = closes[i - 1], closes[i]
        pv, cv = volumes[i - 1], volumes[i]
        if None in (prev, cur, pv, cv) or prev <= 0 or pv <= 0:
            continue
        rets.append(cur / prev - 1.0)
        dvol.append(cv / pv - 1.0)
    return pearson(rets, dvol)


def adv_usd(closes, volumes, t, window=20):
    """20 日平均成交额（美元），用于流动性硬过滤，不作为 alpha。"""
    if t + 1 < window:
        return None
    vals = []
    for i in range(t - window + 1, t + 1):
        if closes[i] is not None and volumes[i] is not None:
            vals.append(closes[i] * volumes[i])
    return mean(vals) if len(vals) >= window * 0.8 else None


# --------------------------------------------------------------------------
# 族聚合
# --------------------------------------------------------------------------
def compute_price_factors(closes, volumes, bench_closes, t):
    """算出 A 层（可回测）的全部原始因子值。

    ``bench_closes`` 必须与 ``closes`` 按同一交易日历对齐。
    风险类因子在这里统一取负号，使“分高 = 风险质量好”，
    让下游不必为每个因子记方向。
    """
    vol60 = factor_volatility(closes, t, 60)
    mdd120 = factor_max_drawdown(closes, t, 120)
    dd120 = factor_downside_deviation(closes, t, 120)
    tail = factor_tail_loss(closes, t, 252)

    rs_120 = None
    own = factor_return(closes, t, 120)
    bench = factor_return(bench_closes, t, 120)
    if own is not None and bench is not None:
        rs_120 = own - bench

    return {
        "mom_12_1": factor_return(closes, t, 231, skip=21),   # 252 − 21
        "mom_6_1": factor_return(closes, t, 105, skip=21),    # 126 − 21
        "rs_120": rs_120,
        "trend_200": factor_sma_gap(closes, t, 200),
        "reversal_21": (lambda r: None if r is None else -r)(factor_return(closes, t, 21)),
        "low_vol_60": None if vol60 is None else -vol60,
        "low_maxdd_120": None if mdd120 is None else -mdd120,
        "low_downside_120": None if dd120 is None else -dd120,
        "low_tail_252": None if tail is None else -tail,
        "volume_expansion": factor_volume_expansion(volumes, t),
        "accumulation_60": factor_accumulation(closes, volumes, t),
        "near_52w_high": factor_near_52w_high(closes, t),
        "volume_confirm_60": factor_volume_confirm(closes, volumes, t),
    }


# --------------------------------------------------------------------------
# 标签：唯一允许读取 t 之后数据的地方
# --------------------------------------------------------------------------
def forward_excess_return(closes, bench_closes, t, horizon):
    """未来 horizon 个交易日的相对基准超额收益，回测标签专用。

    命名以 forward_ 开头是刻意的：审阅时只要在打分路径上看到 forward_，
    就说明有未来函数。
    """
    end = t + horizon
    if end >= len(closes) or end >= len(bench_closes):
        return None
    a, b = closes[t], closes[end]
    ba, bb = bench_closes[t], bench_closes[end]
    if None in (a, b, ba, bb) or a <= 0 or ba <= 0:
        return None
    return (b / a - 1.0) - (bb / ba - 1.0)
