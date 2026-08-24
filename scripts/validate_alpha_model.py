#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Ooglex Alpha 60 V1 的离线自检。不联网，确定性，可在 CI 里跑。

覆盖四类断言：
  1. 数学基本功——分位、去极值、区间收益、回撤、秩相关，全部对着可手算的答案；
  2. **未来函数守卫**——把 t 之后的数据整段改掉，t 时刻的因子值必须一字不变；
  3. 缺失语义——缺数据必须是 None，绝不能被中位数或 50 分悄悄填成“中性”；
  4. 端到端——埋了信号的合成市场必须能被找出来，纯噪声市场必须找不到。

第 4 条的后半句比前半句重要：它证明这套代码不会从随机数里造出 alpha。
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts", "alpha-model"))

import backtest as B          # noqa: E402
import factors as F           # noqa: E402
import scoring as S           # noqa: E402
from build_alpha import REBALANCE_SPACING  # noqa: E402
from config import HORIZON_DAYS, MIN_HISTORY_DAYS, WEIGHTS_A  # noqa: E402
from fixtures import synthetic_market  # noqa: E402
from pipeline import raw_cross_section, rank_cross_section, screen, select_candidates  # noqa: E402

FAILURES = []


def check(name, condition, detail=""):
    if condition:
        print(f"  [✓] {name}")
    else:
        print(f"  [✗] {name}  {detail}")
        FAILURES.append(f"{name} {detail}".strip())


def close_to(a, b, tol=1e-9):
    return a is not None and b is not None and abs(a - b) <= tol


def section(title):
    print(f"\n{title}")


# ---------------------------------------------------------------------------
def test_math():
    section("1. 数学基本功")
    check("quantile 中位数", F.quantile([1, 2, 3, 4, 5], 0.5) == 3)
    check("quantile 线性插值", close_to(F.quantile([0, 10], 0.25), 2.5))
    check("stdev 样本标准差", close_to(F.stdev([2, 4, 4, 4, 5, 5, 7, 9]), 2.138089935299395, 1e-12))
    check("stdev 单点返回 None", F.stdev([1]) is None)

    check("percentile_rank 均匀", S.percentile_rank([1, 2, 3, 4, 5]) == [0.0, 25.0, 50.0, 75.0, 100.0])
    check("percentile_rank 并列取平均名次", S.percentile_rank([1, 1, 3]) == [25.0, 25.0, 100.0])
    check("percentile_rank 保留 None 位置", S.percentile_rank([5, None, 1]) == [100.0, None, 0.0])
    check("percentile_rank 单样本不造分数", S.percentile_rank([7]) == [None],
          "单样本横截面没有排序信息，给50分等于凭空造判断")

    w = S.winsorize(list(range(100)))
    check("winsorize 压两端", close_to(w[0], 0.99) and close_to(w[-1], 98.01))
    check("winsorize 样本过少时原样返回", S.winsorize([1, 2, 3]) == [1, 2, 3])

    closes = [100.0, 120.0, 60.0, 90.0]
    check("max_drawdown 手算 0.5", close_to(F.factor_max_drawdown(closes, 3, 4), 0.5))

    smooth = [100 * (1.001 ** i) for i in range(300)]
    check("等比序列波动率为 0", close_to(F.factor_volatility(smooth, 299, 60), 0.0, 1e-12))
    check("等比序列回撤为 0", close_to(F.factor_max_drawdown(smooth, 299, 120), 0.0))
    check("factor_return 带 skip 手算",
          close_to(F.factor_return(smooth, 299, 231, skip=21), 1.001 ** 231 - 1, 1e-9))
    check("factor_return 历史不足返回 None", F.factor_return(smooth, 10, 231, skip=21) is None)

    check("spearman 完全同序为 1", close_to(B.spearman([1, 2, 3, 4, 5, 6], [9, 8, 7, 6, 5, 4]), -1.0))
    check("spearman 单调变换不变",
          close_to(B.spearman([1, 2, 3, 4, 5, 6], [1, 4, 9, 16, 25, 36]), 1.0))


# ---------------------------------------------------------------------------
def test_lookahead_guard():
    section("2. 未来函数守卫（最关键的一条）")
    _, series, bench, _ = synthetic_market(n_stocks=3, n_days=600, seed=11, signal_strength=0.002)
    closes, volumes = series["S000"]
    t = 400

    before = F.compute_price_factors(closes, volumes, bench, t)
    adv_before = F.adv_usd(closes, volumes, t)

    # 把 t 之后的全部数据换成完全不同的东西：价格 ×7、成交量归零、基准腰斩
    poisoned_closes = closes[:t + 1] + [c * 7.0 for c in closes[t + 1:]]
    poisoned_volumes = volumes[:t + 1] + [0.0 for _ in volumes[t + 1:]]
    poisoned_bench = bench[:t + 1] + [b * 0.5 for b in bench[t + 1:]]

    after = F.compute_price_factors(poisoned_closes, poisoned_volumes, poisoned_bench, t)
    adv_after = F.adv_usd(poisoned_closes, poisoned_volumes, t)

    check("篡改 t 之后的价格/成交量/基准后，t 时刻全部因子值不变",
          before == after,
          f"差异: {[k for k in before if before[k] != after.get(k)]}")
    check("20日成交额同样不受未来数据影响", close_to(adv_before, adv_after))

    check("forward_excess_return 确实读了未来（对照组，应当变化）",
          F.forward_excess_return(closes, bench, t, 60)
          != F.forward_excess_return(poisoned_closes, poisoned_bench, t, 60),
          "标签函数必须依赖未来，否则回测标签是错的")


# ---------------------------------------------------------------------------
def test_missing_semantics():
    section("3. 缺失语义：不知道 ≠ 中性")
    scores = {"momentum": 90.0, "reversal": None, "risk": None, "positioning": None}
    value, coverage = S._weighted_blend(scores, WEIGHTS_A, 0.6)
    check("族覆盖不足时返回 None 而不是补 50", value is None, f"得到 {value}")
    check("覆盖率如实报出", close_to(coverage, 30.0 / 60.0))

    scores2 = {"momentum": 90.0, "reversal": 90.0, "risk": 90.0, "positioning": None}
    value2, cov2 = S._weighted_blend(scores2, WEIGHTS_A, 0.6)
    check("缺一项时按剩余权重重新归一化", close_to(value2, 90.0), f"得到 {value2}")
    check("重新归一化后覆盖率 = 50/60", close_to(cov2, 50.0 / 60.0))

    # 缺失不得把分数拉向中位：全高分股票缺一项后仍应是高分
    check("缺失不产生向中位的拉扯", value2 > 80.0)


# ---------------------------------------------------------------------------
def test_cross_section():
    section("4. 横截面：行业中性与共振")
    values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
    sectors = ["科技"] * 10 + ["小行业", "小行业"]
    ranked = S.sector_neutral_rank(values, sectors, blend=0.5, min_members=8)
    check("样本不足的行业退回全市场分位",
          close_to(ranked[-1], S.percentile_rank(values)[-1]),
          f"{ranked[-1]} vs {S.percentile_rank(values)[-1]}")
    # 取一只行业内排名与全市场排名确实不同的：值 10 在 12 只里排 81.8 分位，
    # 但在 10 只的科技行业里是最高，行业内 100 分位，混合后应为 90.9。
    global_rank = S.percentile_rank(values)
    check("足够大的行业参与混合",
          close_to(ranked[9], 0.5 * global_rank[9] + 0.5 * 100.0),
          f"混合值 {ranked[9]}，全市场 {global_rank[9]}")
    check("行业内排名确实改变了分数", not close_to(ranked[9], global_rank[9]),
          f"{ranked[9]} vs {global_rank[9]}")

    single_leg = {"momentum": 95.0, "reversal": 95.0, "risk": 95.0, "positioning": 95.0,
                  "fundamental": 20.0, "valuation": 20.0, "revision": 20.0}
    hits, detail, dispersion = S.confluence(single_leg)
    check("单靠价格拉分的股票只算 1 块共振，不是 4 票", hits == 1, f"得到 {hits}")
    check("块间离散度暴露单腿支撑", dispersion is not None and dispersion > 30,
          f"离散度 {dispersion}")

    broad = {k: 85.0 for k in single_leg}
    check("三块齐强才算 3", S.confluence(broad)[0] == 3)


# ---------------------------------------------------------------------------
def test_screen():
    section("5. 硬过滤")
    n = 400
    good_closes = [100.0] * n
    good_volumes = [1e6] * n          # ADV = 1亿美元
    ok, reason, adv = screen(good_closes, good_volumes, n - 1)
    check("正常标的通过", ok, reason or "")
    check("成交额计算正确", close_to(adv, 1e8))

    ok2, reason2, _ = screen([2.0] * n, good_volumes, n - 1)
    check("低价股被剔除", not ok2 and "股价" in (reason2 or ""), reason2 or "")

    ok3, reason3, _ = screen(good_closes, [1e3] * n, n - 1)
    check("低流动性被剔除", not ok3 and "成交额" in (reason3 or ""), reason3 or "")

    ok4, reason4, _ = screen([100.0] * 100, [1e6] * 100, 99)
    check("历史不足被剔除", not ok4 and "历史" in (reason4 or ""), reason4 or "")

    gappy = good_closes[:-10] + [None] * 10
    ok5, reason5, _ = screen(gappy, good_volumes, n - 1)
    check("近期停牌/缺失被剔除", not ok5, reason5 or "")


# ---------------------------------------------------------------------------
def test_overlap_and_costs():
    section("6. 统计与成本纪律")
    try:
        B.rank_ic_series([(0, [1, 2, 3, 4, 5, 6], [1, 2, 3, 4, 5, 6]),
                          (10, [1, 2, 3, 4, 5, 6], [1, 2, 3, 4, 5, 6])], 60)
        check("重叠窗口必须报错", False, "没有抛出 OverlappingWindowError")
    except B.OverlappingWindowError:
        check("重叠窗口必须报错", True)

    ok = B.rank_ic_series([(0, [1, 2, 3, 4, 5, 6], [1, 2, 3, 4, 5, 6]),
                           (60, [1, 2, 3, 4, 5, 6], [6, 5, 4, 3, 2, 1])], 60)
    check("不重叠窗口正常计算", len(ok) == 2 and close_to(ok[0][1], 1.0) and close_to(ok[1][1], -1.0))

    # 首期全换手：成本 = 2 × 1.0 × 10bp = 0.002
    result = B.simulate_portfolio(
        [("d1", {"A": 9, "B": 8, "C": 1}, {"A": 0.05, "B": 0.03, "C": -0.10})],
        2, cost_bps_one_way=10.0, spacing_days=21)
    check("换手率 = 被替换比例", close_to(result["periods"][0]["turnover"], 1.0))
    check("成本 = 2 × 换手 × 单边费率", close_to(result["periods"][0]["cost"], 0.002))
    check("净收益 = 毛收益 − 成本", close_to(result["periods"][0]["netExcess"], 0.04 - 0.002))

    zero_turn = B.simulate_portfolio(
        [("d1", {"A": 9, "B": 8}, {"A": 0.01, "B": 0.01}),
         ("d2", {"A": 9, "B": 8}, {"A": 0.01, "B": 0.01})],
        2, cost_bps_one_way=10.0, spacing_days=21)
    check("持仓不变则第二期零成本", close_to(zero_turn["periods"][1]["cost"], 0.0))


# ---------------------------------------------------------------------------
def _run_backtest(signal, n_stocks=60, n_days=760, seed_label=""):
    members, series, bench, dates = synthetic_market(
        n_stocks=n_stocks, n_days=n_days, seed=7, signal_strength=signal)

    snapshots, pooled_s, pooled_l = [], [], []
    last = len(dates) - HORIZON_DAYS - 1
    for t in range(MIN_HISTORY_DAYS, last + 1, HORIZON_DAYS):
        rows, _ = raw_cross_section(members, series, bench, t)
        scored = rank_cross_section(rows, fundamentals=None, weights=WEIGHTS_A)
        labels = [F.forward_excess_return(series[r["symbol"]][0], bench, t, HORIZON_DAYS)
                  for r in scored]
        scores = [r["alpha"] for r in scored]
        snapshots.append((t, scores, labels))
        pooled_s.extend(scores)
        pooled_l.extend(labels)

    ic = B.ic_summary(B.rank_ic_series(snapshots, HORIZON_DAYS))
    deciles = B.decile_stats(pooled_s, pooled_l)

    rebalances = []
    for t in range(MIN_HISTORY_DAYS, len(dates) - REBALANCE_SPACING - 1, REBALANCE_SPACING):
        rows, _ = raw_cross_section(members, series, bench, t)
        scored = rank_cross_section(rows, fundamentals=None, weights=WEIGHTS_A)
        rebalances.append((
            dates[t],
            {r["symbol"]: r["alpha"] for r in scored},
            {r["symbol"]: F.forward_excess_return(series[r["symbol"]][0], bench,
                                                  t, REBALANCE_SPACING) for r in scored},
        ))
    portfolio = B.simulate_portfolio(rebalances, 10, spacing_days=REBALANCE_SPACING)
    passed, checks = B.evaluate_gates(ic, deciles or {}, portfolio or {})
    return ic, deciles, portfolio, passed, checks


def test_end_to_end_signal():
    section("7. 端到端 · 有信号：埋进去的规律必须能被找出来")
    ic, deciles, portfolio, passed, _ = _run_backtest(0.006)
    print(f"      IC均值 {ic['mean']:.4f}  信息比 {ic['ir']:.3f}  "
          f"单调性 {deciles['monotonicSpearman']:.3f}  "
          f"组合累计超额 {portfolio['cumulativeExcess']:.4f}")
    check("IC 显著为正", ic["mean"] > 0.15, f"IC={ic['mean']}")
    check("分组单调递减", deciles["monotonicSpearman"] < -0.7,
          f"rho={deciles['monotonicSpearman']}")
    check("D1 优于 D10", deciles["topMinusBottom"] > 0)
    check("六条验收线全部通过", passed)


def test_end_to_end_null():
    section("8. 端到端 · 零信号：纯噪声里不许找出 alpha")
    ic, deciles, portfolio, passed, checks = _run_backtest(0.0)
    print(f"      IC均值 {ic['mean']:.4f}  信息比 {ic['ir']:.3f}  "
          f"单调性 {deciles['monotonicSpearman']:.3f}  "
          f"组合累计超额 {portfolio['cumulativeExcess']:.4f}")
    check("IC 接近 0", abs(ic["mean"]) < 0.15, f"IC={ic['mean']}")
    check("验收不通过", not passed,
          "纯随机游走通过了验收，说明管线在无中生有")
    check("失败原因里包含 IC 或单调性",
          any(not c["pass"] and c["name"] in ("IC均值", "IC信息比", "分组单调性")
              for c in checks))
    check("扣成本后组合不赚钱", portfolio["cumulativeExcess"] < 0.05,
          f"累计 {portfolio['cumulativeExcess']}")


# ---------------------------------------------------------------------------
def test_candidate_rule():
    section("9. 候选池门槛的诚实降级")
    members, series, bench, dates = synthetic_market(
        n_stocks=40, n_days=500, seed=3, signal_strength=0.004)
    rows, _ = raw_cross_section(members, series, bench, len(dates) - 1)
    scored = rank_cross_section(rows, fundamentals=None, weights=WEIGHTS_A)
    _, rule = select_candidates(scored)
    check("只有A层时可共振块数为 1", rule["availableBlocks"] == 1, str(rule))
    check("门槛按可得块数封顶", rule["minConfluence"] == 1)
    check("降级被显式标记", rule["relaxed"] is True,
          "门槛放宽必须写进输出，不能悄悄放宽")

    fundamentals = {m["symbol"]: {"fundamental": i, "valuation": i, "revision": i}
                    for i, m in enumerate(members)}
    rows2, _ = raw_cross_section(members, series, bench, len(dates) - 1)
    scored2 = rank_cross_section(rows2, fundamentals=fundamentals)
    _, rule2 = select_candidates(scored2)
    check("接入B层后恢复三块", rule2["availableBlocks"] == 3, str(rule2))
    check("门槛恢复到配置值", rule2["minConfluence"] == 2 and rule2["relaxed"] is False)


def main():
    print("Ooglex Alpha 60 V1 · 离线自检（不联网）")
    test_math()
    test_lookahead_guard()
    test_missing_semantics()
    test_cross_section()
    test_screen()
    test_overlap_and_costs()
    test_end_to_end_signal()
    test_end_to_end_null()
    test_candidate_rule()

    print()
    if FAILURES:
        print(f"自检未通过，{len(FAILURES)} 项失败：")
        for item in FAILURES:
            print(f"  · {item}")
        return 1
    print("自检全部通过。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
