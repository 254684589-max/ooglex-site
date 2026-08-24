#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""横截面归一化与分数合成。

流水线（每个横截面日独立执行，绝不跨日共用统计量）：
    原始值 → 去极值 → 全市场百分位 / 行业内百分位 → 混合 → 子因子加权
          → 族分数 → 总分 Alpha60 → Confluence

为什么用百分位而不是 Z-score：财务与收益数据尾部极厚（例如去年利润接近 0
导致 EPS 增速 +2800%），Z-score 会被单个异常值主导整张表。百分位对任何单调
变换不变，天然抗尾部。代价是丢掉“强多少”的信息，所以评估阶段仍用原始收益，
只在打分阶段用百分位。
"""

from config import (
    CONFLUENCE_BLOCKS,
    CONFLUENCE_THRESHOLD,
    MIN_BLOCK_COVERAGE,
    MIN_TOTAL_COVERAGE,
    SECTOR_BLEND,
    SECTOR_MIN_MEMBERS,
    SUBWEIGHTS,
    WEIGHTS,
    WINSOR_HIGH,
    WINSOR_LOW,
)
from factors import quantile, stdev


def winsorize(values, low=WINSOR_LOW, high=WINSOR_HIGH):
    """把两端极值压到分位边界；None 原样保留。"""
    present = [v for v in values if v is not None]
    if len(present) < 5:
        return list(values)
    lo, hi = quantile(present, low), quantile(present, high)
    if lo is None or hi is None or lo > hi:
        return list(values)
    return [None if v is None else min(max(v, lo), hi) for v in values]


def percentile_rank(values):
    """横截面百分位 0–100，并列取平均名次。

    n < 2 时返回全 None：只有一个样本的横截面不包含任何排序信息，
    给 50 分等于凭空造出一个“中性”判断。
    """
    present = [(i, v) for i, v in enumerate(values) if v is not None]
    out = [None] * len(values)
    if len(present) < 2:
        return out
    present.sort(key=lambda p: p[1])
    n = len(present)
    i = 0
    while i < n:
        j = i
        while j + 1 < n and present[j + 1][1] == present[i][1]:
            j += 1
        avg_rank = (i + j) / 2.0            # 并列取平均名次
        score = 100.0 * avg_rank / (n - 1)
        for k in range(i, j + 1):
            out[present[k][0]] = score
        i = j + 1
    return out


def sector_neutral_rank(values, sectors, blend=SECTOR_BLEND,
                        min_members=SECTOR_MIN_MEMBERS):
    """全市场分位与行业内分位的混合。

    纯行业中性（blend=0）会丢掉真实存在的跨行业差异；纯全市场（blend=1）会在
    主题行情里让榜单被单一行业占满。默认各占一半。
    行业样本数不足 ``min_members`` 时无法稳定排名，该股退回纯全市场分位。
    """
    global_scores = percentile_rank(values)

    buckets = {}
    for idx, sector in enumerate(sectors):
        buckets.setdefault(sector, []).append(idx)

    sector_scores = [None] * len(values)
    for sector, idxs in buckets.items():
        if len(idxs) < min_members:
            continue
        ranked = percentile_rank([values[i] for i in idxs])
        for pos, i in enumerate(idxs):
            sector_scores[i] = ranked[pos]

    out = []
    for g, s in zip(global_scores, sector_scores):
        if g is None:
            out.append(None)
        elif s is None:
            out.append(g)                    # 行业太小，只用全市场分位
        else:
            out.append(blend * g + (1.0 - blend) * s)
    return out


def _weighted_blend(scores, weights, min_coverage):
    """按可得项重新归一化权重后加权平均。

    缺失项绝不用中位数或 50 分填充：那会把“不知道”伪装成“中性”，
    并在 Alpha≥80 这类过滤上系统性偏向数据缺失的股票（它们分数方差被人为压低）。
    """
    total = sum(weights.values())
    if total <= 0:
        return None, 0.0
    available = sum(w for k, w in weights.items() if scores.get(k) is not None)
    coverage = available / total
    if coverage < min_coverage or available <= 0:
        return None, coverage
    value = sum(weights[k] * scores[k] for k in weights if scores.get(k) is not None)
    return value / available, coverage


def block_scores(ranked_factors, subweights=SUBWEIGHTS):
    """由已排名的子因子分数合成 A 层各族分数。

    ``ranked_factors``：{子因子名: 0–100 分或 None}
    返回：({族名: 分数或 None}, {族名: 覆盖率})
    """
    scores, coverage = {}, {}
    for block, weights in subweights.items():
        value, cov = _weighted_blend(ranked_factors, weights, MIN_BLOCK_COVERAGE)
        scores[block] = value
        coverage[block] = cov
    return scores, coverage


def alpha_score(family_scores, weights=WEIGHTS):
    """由七个族分数合成 Alpha60 总分。返回 (总分或 None, 有效权重覆盖率)。"""
    return _weighted_blend(family_scores, weights, MIN_TOTAL_COVERAGE)


def confluence(family_scores, blocks=CONFLUENCE_BLOCKS,
               threshold=CONFLUENCE_THRESHOLD):
    """因子共振：把七族先按同源性归并为独立块，再数有多少块达标。

    直接数“七族里几个 >80”会重复计数——动量、反转、量能、风险都来自同一份
    价格序列，一只单纯涨得猛的股票能轻松拿到 4 票，看上去像多因子共振，
    其实只有一条腿。归并成价格 / 质量 / 预期三块后，共振才有信息量。

    返回 (达标块数, {块名: 块分数}, 块间离散度)。离散度大说明是单腿支撑。
    """
    detail = {}
    for name, families in blocks.items():
        sub = {f: family_scores.get(f) for f in families}
        w = {f: WEIGHTS[f] for f in families if f in WEIGHTS}
        value, _ = _weighted_blend(sub, w, MIN_BLOCK_COVERAGE)
        detail[name] = value
    hits = sum(1 for v in detail.values() if v is not None and v >= threshold)
    present = [v for v in detail.values() if v is not None]
    dispersion = stdev(present) if len(present) >= 2 else None
    return hits, detail, dispersion
