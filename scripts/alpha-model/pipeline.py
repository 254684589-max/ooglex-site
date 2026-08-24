#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""横截面打分主流程：从对齐好的价量序列到 Alpha60 排名。

与取数、命令行解析完全分离，因此可以在没有网络的情况下用合成数据完整跑通并断言，
这也是 ``scripts/validate_alpha_model.py`` 的做法。
"""

from config import (
    CANDIDATE_MIN_ALPHA,
    CANDIDATE_MIN_CONFLUENCE,
    CANDIDATE_MIN_RISK,
    MAX_RECENT_GAPS,
    MIN_ADV_USD,
    MIN_HISTORY_DAYS,
    MIN_PRICE_USD,
    SUBWEIGHTS,
    WEIGHTS,
)
from factors import adv_usd, compute_price_factors
from prices import recent_gap_count
from factors import quantile, stdev
from scoring import alpha_score, block_scores, confluence, sector_neutral_rank, winsorize

# B 层族：实时可用，但没有 point-in-time 历史，因此默认不参与回测。
FUNDAMENTAL_FAMILIES = ("fundamental", "valuation", "revision")


def screen(closes, volumes, t,
           min_adv=MIN_ADV_USD, min_price=MIN_PRICE_USD,
           min_history=MIN_HISTORY_DAYS, max_gaps=MAX_RECENT_GAPS):
    """打分前的硬过滤。返回 (是否通过, 原因, 20日成交额)。

    目的是排除“统计上算得出但实际交易不了”的标的。放在打分之前，
    是为了让这些股票根本不进入横截面——否则它们会挤占分位数的分布。
    """
    price = closes[t] if t < len(closes) else None
    if price is None:
        return False, "最新交易日无价格", None
    if price < min_price:
        return False, f"股价 {price:.2f} 低于 {min_price}", None

    valid = sum(1 for c in closes[:t + 1] if c is not None)
    if valid < min_history:
        return False, f"有效历史 {valid} 天不足 {min_history} 天", None

    gaps = recent_gap_count(closes, t)
    if gaps > max_gaps:
        return False, f"最近20日缺失 {gaps} 天，超过 {max_gaps} 天", None

    adv = adv_usd(closes, volumes, t)
    if adv is None:
        return False, "无法计算20日成交额", None
    if adv < min_adv:
        return False, f"20日成交额 {adv/1e6:.1f}M 低于 {min_adv/1e6:.0f}M", adv
    return True, None, adv


def raw_cross_section(members, series, bench_closes, t):
    """算出通过过滤的股票的原始因子值。返回 (合格行, 剔除记录)。

    ``series``：{代码: (closes, volumes)}，均已对齐到同一主交易日历。
    """
    rows, rejected = [], []
    for member in members:
        pair = series.get(member["symbol"])
        if not pair:
            rejected.append({"symbol": member["symbol"], "reason": "无行情"})
            continue
        closes, volumes = pair
        ok, reason, adv = screen(closes, volumes, t)
        if not ok:
            rejected.append({"symbol": member["symbol"], "reason": reason})
            continue
        rows.append({
            "symbol": member["symbol"],
            "name": member.get("name") or member["symbol"],
            "sector": member.get("sector") or "其他",
            "price": closes[t],
            "advUsd": adv,
            "raw": compute_price_factors(closes, volumes, bench_closes, t),
        })
    return rows, rejected


def rank_cross_section(rows, fundamentals=None, subweights=SUBWEIGHTS, weights=WEIGHTS,
                       flip_families=()):
    """把原始因子值变成 0–100 分并合成 Alpha60。就地补齐每行的分数字段。

    ``fundamentals``：可选的 {代码: {族名: 原始值}}，用于接入 B 层。留空时
    B 层族分数为 None，总分按 A 层权重重新归一化，并在 coverage 字段里体现——
    绝不用中位数把缺失伪装成中性。
    """
    if not rows:
        return rows
    sectors = [r["sector"] for r in rows]

    # B 层原始值并入同一份 raw，走**完全相同**的归一化流水线。
    # 不给它单开一条路径：估值要和动量一样做去极值、一样做行业中性混合，
    # 否则两层的分数不在同一个尺度上，加权平均就没有意义。
    for row in rows:
        row["raw"].update((fundamentals or {}).get(row["symbol"]) or {})

    # 每个子因子独立做横截面归一化：去极值 → 全市场/行业内分位混合。
    factor_names = sorted({name for r in rows for name in r["raw"]})
    for name in factor_names:
        values = winsorize([r["raw"].get(name) for r in rows])
        for row, score in zip(rows, sector_neutral_rank(values, sectors)):
            row.setdefault("ranked", {})[name] = score

    if flip_families:
        # 在**已归一化的分位分数**上翻转（100 − 分数），不是在原始值上取负号：
        # 分位是 0–100 均匀的，100−x 仍是合法分位；在原始值上取负会改变
        # 去极值边界与并列处理，两者不等价。
        from variants import apply_flips
        apply_flips(rows, flip_families, subweights)

    for row in rows:
        # B 层缺失时，其子因子根本不在 ranked 里，族覆盖率为 0 → 族分数为 None，
        # 总分按剩余权重重新归一化。缺失不被填成中位数。
        families, coverage = block_scores(row["ranked"], subweights)
        row["families"] = families
        row["blockCoverage"] = coverage

        total, total_coverage = alpha_score(row["families"], weights)
        row["alpha"] = total
        row["coverage"] = total_coverage

        hits, detail, dispersion = confluence(row["families"])
        row["confluence"] = hits
        row["confluenceDetail"] = detail
        row["confluenceDispersion"] = dispersion

    scored = [r for r in rows if r["alpha"] is not None]
    scored.sort(key=lambda r: r["alpha"], reverse=True)
    for i, row in enumerate(scored, start=1):
        row["rank"] = i
        row["percentile"] = 100.0 * (len(scored) - i) / max(1, len(scored) - 1)
    return scored


def available_confluence_blocks(rows):
    """当前横截面里真正有数据的独立块数。

    只跑 A 层时只有“价格”一块，此时要求两块共振在数学上不可能满足，
    候选池会恒为空。所以门槛按实际可得块数封顶，并把这件事显式报出来，
    而不是悄悄放宽标准。
    """
    seen = set()
    for row in rows:
        for name, value in (row.get("confluenceDetail") or {}).items():
            if value is not None:
                seen.add(name)
    return len(seen)


def select_candidates(rows, min_alpha=CANDIDATE_MIN_ALPHA, min_risk=CANDIDATE_MIN_RISK,
                      min_confluence=CANDIDATE_MIN_CONFLUENCE):
    """候选池：高分 + 风险质量不差 + 尽可能多的独立块共振。

    三条是“且”的关系。只卡 Alpha 会放进一批单靠价格涨势拉分、
    风险和基本面都不支持的股票。

    返回 (候选行, 实际生效的门槛)。生效门槛可能低于配置值——B 层缺失时
    可共振的块本来就不够——调用方必须把它写进输出，让读者知道
    这批候选没有经过完整的跨块共振检验。
    """
    effective = min(min_confluence, max(1, available_confluence_blocks(rows)))
    out = []
    for row in rows:
        risk = (row.get("families") or {}).get("risk")
        if row.get("alpha") is None or row["alpha"] < min_alpha:
            continue
        if risk is None or risk < min_risk:
            continue
        if (row.get("confluence") or 0) < effective:
            continue
        out.append(row)
    return out, {"minAlpha": min_alpha, "minRisk": min_risk,
                 "minConfluence": effective,
                 "configuredMinConfluence": min_confluence,
                 "availableBlocks": available_confluence_blocks(rows),
                 "relaxed": effective < min_confluence}


def score_distribution(rows):
    """总分的分布刻画。

    Alpha60 是“若干个分位数的加权平均”，因此它本身**不是**分位数——
    多个 0–100 均匀分位取平均会向中间收敛，分布是钟形而不是均匀。
    所以「Alpha ≥ 80」远不等于「前 20%」，实际往往是前百分之几。
    把分位对照表一并输出，避免按均匀分布的直觉误读分数。
    """
    values = sorted(r["alpha"] for r in rows if r.get("alpha") is not None)
    if not values:
        return None
    from factors import mean as _mean

    # 直方图分箱：报告页画分布用。2.5 分一箱共 40 箱——箱宽再粗，
    # 柱子就会超过 24px 的marks上限而读成“大色块”；再细则单箱样本太少。
    bins = []
    for step in range(40):
        lo = step * 2.5
        hi = lo + 2.5
        count = sum(1 for v in values if lo <= v < hi or (step == 39 and v == 100))
        bins.append({"lo": lo, "hi": hi, "count": count})

    return {
        "histogram": bins,
        "count": len(values),
        "mean": _mean(values),
        "std": stdev(values),
        "min": values[0],
        "max": values[-1],
        "p50": quantile(values, 0.50),
        "p80": quantile(values, 0.80),
        "p90": quantile(values, 0.90),
        "p95": quantile(values, 0.95),
        "p99": quantile(values, 0.99),
        "shareAbove80": sum(1 for v in values if v >= 80) / len(values),
        "note": "总分是分位数的加权平均，分布呈钟形；不可按均匀分位解读",
    }


def explain(row, top_k=3):
    """给一行生成可读的“为什么高/为什么扣分”，让分数可解释而不是黑箱。"""
    ranked = row.get("ranked") or {}
    labels = {
        "mom_12_1": "12个月动量（剔除最近1个月）",
        "mom_6_1": "6个月动量（剔除最近1个月）",
        "rs_120": "120日相对基准超额",
        "trend_200": "相对200日均线位置",
        "reversal_21": "近1个月短期反转",
        "low_vol_60": "60日波动率（低者优）",
        "low_maxdd_120": "120日最大回撤（浅者优）",
        "low_downside_120": "120日下行波动（低者优）",
        "low_tail_252": "尾部风险（小者优）",
        "volume_expansion": "量能扩张 ADV20/ADV120",
        "accumulation_60": "吸筹比 上涨日量/下跌日量",
        "near_52w_high": "距52周高点",
        "volume_confirm_60": "量价配合度",
        "revenue_growth": "营收同比增速",
        "earnings_growth": "盈利同比增速",
        "operating_margin": "营业利润率",
        "gross_margin": "毛利率",
        "roe": "净资产收益率",
        "fcf_margin": "自由现金流利润率",
        "low_leverage": "净负债/EBITDA（轻者优）",
        "earnings_yield": "盈利收益率（前瞻PE倒数）",
        "ev_ebitda_yield": "EV/EBITDA倒数",
        "ev_sales_yield": "EV/Sales倒数",
        "fcf_yield": "自由现金流收益率",
        "eps_revision_90d": "EPS预期90日修正",
        "eps_revision_30d": "EPS预期30日修正",
        "revision_breadth": "修正广度（上调−下调）",
        "target_upside": "目标价相对现价",
    }
    present = [(v, k) for k, v in ranked.items() if v is not None]
    present.sort(reverse=True)
    strengths = [f"{labels.get(k, k)} {v:.0f}分" for v, k in present[:top_k]]
    weaknesses = [f"{labels.get(k, k)} {v:.0f}分" for v, k in present[-top_k:][::-1]]
    missing = sorted(k for k, v in ranked.items() if v is None)
    return {"strengths": strengths, "weaknesses": weaknesses, "missingFactors": missing}
