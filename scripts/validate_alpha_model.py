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
import fundamentals as FU     # noqa: E402
import scoring as S           # noqa: E402
from build_alpha import REBALANCE_SPACING  # noqa: E402
from config import HORIZON_DAYS, MIN_HISTORY_DAYS, WEIGHTS_A  # noqa: E402
from fixtures import synthetic_market  # noqa: E402
from pipeline import raw_cross_section, rank_cross_section, screen, select_candidates  # noqa: E402
from prices import infer_interval  # noqa: E402
import pit_universe as PIT  # noqa: E402
import pit_wikipedia as WIKI  # noqa: E402

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

    # B 层输入是**子因子级**的（重构后），不是族级的。
    # 外部 --fundamentals 文件也必须用这套键名。
    from config import SUBWEIGHTS as _SW
    b_keys = [k for fam in ("fundamental", "valuation", "revision") for k in _SW[fam]]
    fundamentals = {m["symbol"]: {k: float(i) for k in b_keys}
                    for i, m in enumerate(members)}
    rows2, _ = raw_cross_section(members, series, bench, len(dates) - 1)
    scored2 = rank_cross_section(rows2, fundamentals=fundamentals)
    _, rule2 = select_candidates(scored2)
    check("接入B层后恢复三块", rule2["availableBlocks"] == 3, str(rule2))
    check("门槛恢复到配置值", rule2["minConfluence"] == 2 and rule2["relaxed"] is False)



# ---------------------------------------------------------------------------
QUOTE_FIXTURE = {
    "financialData": {
        "totalRevenue": 100_000_000_000, "revenueGrowth": 0.62,
        "earningsGrowth": 1.05, "grossMargins": 0.75, "operatingMargins": 0.61,
        "returnOnEquity": 1.19, "freeCashflow": 40_000_000_000,
        "totalDebt": 12_000_000_000, "totalCash": 4_000_000_000,
        "ebitda": 66_000_000_000, "currentPrice": 200.0,
        "targetMeanPrice": 250.0, "numberOfAnalystOpinions": 50,
    },
    "defaultKeyStatistics": {
        "forwardPE": 25.0, "enterpriseToEbitda": 40.0, "enterpriseToRevenue": 20.0,
    },
    "summaryDetail": {"marketCap": 4_000_000_000_000},
    "price": {"marketCap": 4_000_000_000_000, "regularMarketPrice": 200.0},
    "earningsTrend": {"trend": [
        {"period": "0q", "epsTrend": {"current": 1.0, "90daysAgo": 0.9}},
        {"period": "+1y",
         "epsTrend": {"current": 8.0, "30daysAgo": 7.6, "90daysAgo": 6.4},
         "epsRevisions": {"upLast30days": 22, "downLast30days": 2},
         "earningsEstimate": {"avg": 8.0, "numberOfAnalysts": 40}},
    ]},
}


def test_fundamental_parser():
    section("10. B层解析器（纯函数，可离线断言）")
    m, diag = FU.extract_metrics(QUOTE_FIXTURE)

    check("15 个子因子全部解析出来", len(diag["missing"]) == 0, str(diag["missing"]))
    check("营收增速直读", close_to(m["revenue_growth"], 0.62))
    check("FCF利润率 = FCF/营收", close_to(m["fcf_margin"], 0.4))
    check("FCF收益率 = FCF/市值", close_to(m["fcf_yield"], 0.01))
    check("净负债杠杆取负号（高分=负债轻）",
          close_to(m["low_leverage"], -(12e9 - 4e9) / 66e9), f'{m["low_leverage"]}')
    check("盈利收益率 = 1/前瞻PE", close_to(m["earnings_yield"], 0.04))
    check("目标价上行空间", close_to(m["target_upside"], 0.25))
    check("修正广度 = (上调−下调)/分析师数", close_to(m["revision_breadth"], 0.5))
    check("90日EPS修正 = (8.0−6.4)/6.4", close_to(m["eps_revision_90d"], 0.25))
    check("只读 +1y 那一期，不误取 0q",
          not close_to(m["eps_revision_90d"], (1.0 - 0.9) / 0.9))

    # 亏损公司：预期从 −1.00 上修到 −0.50 是改善，必须是正数。
    # 用带符号分母会算成 −50%，方向正好反了——这是最容易写错的一处。
    loss = {"earningsTrend": {"trend": [
        {"period": "+1y", "epsTrend": {"current": -0.50, "90daysAgo": -1.00}}]}}
    lm, _ = FU.extract_metrics(loss)
    check("亏损收窄记为正向修正（分母取绝对值）",
          lm["eps_revision_90d"] is not None and lm["eps_revision_90d"] > 0,
          f'得到 {lm["eps_revision_90d"]}')

    worse = {"earningsTrend": {"trend": [
        {"period": "+1y", "epsTrend": {"current": -1.50, "90daysAgo": -1.00}}]}}
    wm, _ = FU.extract_metrics(worse)
    check("亏损扩大记为负向修正", wm["eps_revision_90d"] < 0, f'{wm["eps_revision_90d"]}')

    # 亏损公司的前瞻PE为负，盈利收益率应保留负号且亏得越狠越负
    check("亏损公司盈利收益率为负", FU._inverse(-25.0) < 0)
    check("亏损越重（PE绝对值越小）排序越靠后",
          FU._inverse(-5.0) < FU._inverse(-100.0),
          f"{FU._inverse(-5.0)} vs {FU._inverse(-100.0)}")

    check("_num 解开 {raw:…} 包装", close_to(FU._num({"raw": 1.5, "fmt": "1.50"}), 1.5))
    check("_num 拒绝布尔值", FU._num(True) is None)
    check("_num 拒绝 None 与字符串", FU._num(None) is None and FU._num("3") is None)
    check("零倍数不炸成无穷", FU._inverse(0.0) is None)
    check("零分母不炸", FU._safe_div(1.0, 0.0) is None)

    empty, ed = FU.extract_metrics({})
    check("空响应全部返回 None，不返回 0",
          all(v is None for v in empty.values()), str({k: v for k, v in empty.items() if v is not None}))
    check("空响应的诊断如实报出全缺", len(ed["present"]) == 0)

    partial, pd_ = FU.extract_metrics({"financialData": {"revenueGrowth": 0.3}})
    check("部分响应只填拿到的那项",
          close_to(partial["revenue_growth"], 0.3) and partial["roe"] is None)
    check("分析师不足 3 位不算修正广度",
          FU.extract_metrics({"earningsTrend": {"trend": [{"period": "+1y",
              "epsRevisions": {"upLast30days": 1, "downLast30days": 0},
              "earningsEstimate": {"numberOfAnalysts": 2}}]}})[0]["revision_breadth"] is None)


def test_b_layer_pipeline():
    section("11. B层并入同一条归一化流水线")
    import random
    from fixtures import synthetic_market as _sm
    from config import WEIGHTS as _W
    members, series, bench, dates = _sm(n_stocks=40, n_days=500, seed=5, signal_strength=0.003)
    rng = random.Random(2)
    keys = [k for fam in ("fundamental", "valuation", "revision")
            for k in __import__("config").SUBWEIGHTS[fam]]
    fund = {m["symbol"]: {k: rng.gauss(0, 1) for k in keys} for m in members}

    rows, _ = raw_cross_section(members, series, bench, len(dates) - 1)
    scored = rank_cross_section(rows, fundamentals=fund, weights=_W)
    top = scored[0]

    check("七族分数全部算出", all(v is not None for v in top["families"].values()),
          str(top["families"]))
    check("总覆盖率为 1.0", close_to(top["coverage"], 1.0))
    check("可排名子因子数 = A层13 + B层15", len(top["ranked"]) == 28, str(len(top["ranked"])))
    check("B层子因子也做了0–100分位归一",
          all(0 <= top["ranked"][k] <= 100 for k in keys))

    _, rule = select_candidates(scored)
    check("接入B层后共振门槛不再降级", rule["relaxed"] is False and rule["minConfluence"] == 2)

    rows2, _ = raw_cross_section(members, series, bench, len(dates) - 1)
    scored2 = rank_cross_section(rows2, fundamentals=None, weights=_W)
    top2 = scored2[0]
    check("不给B层时三族为 None 而非 0 分",
          all(top2["families"][f] is None for f in ("fundamental", "valuation", "revision")))
    check("不给B层时覆盖率降到 0.6", close_to(top2["coverage"], 0.6))
    check("不给B层时总分仍算得出（按A层重新归一化）", top2["alpha"] is not None)



# ---------------------------------------------------------------------------
def test_interval_guard():
    section("12. 行情粒度校验（Yahoo 会静默降级）")
    from datetime import date as _date, timedelta as _td

    def gen(n, step, skip_weekend=False, start=_date(2020, 1, 1)):
        out, d = [], start
        while len(out) < n:
            if not skip_weekend or d.weekday() < 5:
                out.append(d.isoformat())
            d += _td(days=step)
        return out

    check("日线（跳周末）识别为 1d", infer_interval(gen(300, 1, True))[0] == "1d")
    check("连续日线识别为 1d", infer_interval(gen(300, 1))[0] == "1d")
    check("周线识别为 1wk", infer_interval(gen(120, 7))[0] == "1wk")
    check("月线识别为 1mo", infer_interval(gen(120, 30))[0] == "1mo")
    check("季线识别为 coarser", infer_interval(gen(60, 91))[0] == "coarser")
    check("样本过少返回 unknown", infer_interval(["2020-01-01"])[0] == "unknown")
    check("脏日期不炸", infer_interval(["x", "y", "z"])[0] == "unknown")

    # 复现真实事故：range=max 下 Yahoo 返回 SPY 上市至今的月线，
    # 403 个月被当成 403 个交易日，60日前瞻变成 60 个月前瞻。
    monthly = gen(404, 30, start=_date(1993, 2, 1))
    interval, gap = infer_interval(monthly)
    check("复现 404 个月线 bar 被识破", interval == "1mo" and gap >= 28,
          f"{interval}/{gap}")
    check("月线中位间隔远超日线上限", gap > 4)



# ---------------------------------------------------------------------------
WIKI_FIXTURE = """
<table class="wikitable sortable" id="constituents"><tbody>
<tr><th>Symbol</th><th>Security</th><th>GICS Sector</th><th>Date added</th></tr>
<tr><td><a href="/a">MMM</a></td><td>3M</td><td>Industrials</td><td>1957-03-04</td></tr>
<tr><td><a href="/b">BRK.B</a></td><td>Berkshire</td><td>Financials</td><td>2010-02-16</td></tr>
<tr><td>—</td><td>占位</td><td>N/A</td><td></td></tr>
</tbody></table>
<table class="wikitable sortable"><tbody>
<tr><th>Date</th><th>Added Ticker</th><th>Added Security</th>
    <th>Removed Ticker</th><th>Removed Security</th><th>Reason</th></tr>
<tr><td rowspan="2">March 18, 2024</td><td>SMCI</td><td>Super Micro</td>
    <td>WHR</td><td>Whirlpool</td><td>Market cap<sup>[1]</sup></td></tr>
<tr><td>DECK</td><td>Deckers</td><td>ZION</td><td>Zions</td><td>Market cap change</td></tr>
<tr><td>June 24, 2023</td><td>PANW</td><td>Palo Alto</td><td>DXC</td>
    <td>DXC Tech</td><td>Index rebalance</td></tr>
</tbody></table>
"""


def test_pit_reconstruction():
    section("13. Point-in-time 成分股回溯重建")
    # 手算样例：今天 {A,B,C}；2024-06-01 C 换掉 D；2023-01-10 B 换掉 E
    snaps = PIT.build_snapshots(["A", "B", "C"], "2025-01-01", [
        {"date": "2024-06-01", "added": "C", "removed": "D"},
        {"date": "2023-01-10", "added": "B", "removed": "E"},
    ])
    at = lambda d: sorted(PIT.constituents_at(snaps, d))  # noqa: E731

    # 这三条守住的是一个真实踩过的 off-by-one：撤销 D 日变更后得到的成分，
    # 生效区间是 **D 之前**，用 D 当快照键会让整串错位一格。
    check("变更之后取到新成分", at("2024-12-01") == ["A", "B", "C"], str(at("2024-12-01")))
    check("两次变更之间取到中间态", at("2023-06-01") == ["A", "B", "D"], str(at("2023-06-01")))
    check("最早变更之前取到原始成分", at("2022-06-01") == ["A", "D", "E"], str(at("2022-06-01")))
    check("变更当日即生效（含当天）", at("2024-06-01") == ["A", "B", "C"], str(at("2024-06-01")))
    check("变更前一天仍是旧成分", at("2024-05-31") == ["A", "B", "D"], str(at("2024-05-31")))

    # 同一天多笔调整必须一起撤销
    multi = PIT.build_snapshots(["A", "B", "C", "D"], "2025-01-01", [
        {"date": "2024-03-18", "added": "C", "removed": "X"},
        {"date": "2024-03-18", "added": "D", "removed": "Y"},
    ])
    check("同日多笔一起撤销",
          sorted(PIT.constituents_at(multi, "2024-01-01")) == ["A", "B", "X", "Y"],
          str(sorted(PIT.constituents_at(multi, "2024-01-01"))))

    check("未来日期的变更被丢弃",
          len(PIT.build_snapshots(["A"], "2020-01-01",
                                  [{"date": "2030-01-01", "added": "Z"}])) == 1)
    check("无变更时只有一份快照",
          len(PIT.build_snapshots(["A", "B"], "2025-01-01", [])) == 1)

    check("BRK.B 归一成 Yahoo 口径", PIT.normalize_ticker("BRK.B") == "BRK-B")
    check("占位符被剔除", PIT.normalize_ticker("—") is None
          and PIT.normalize_ticker("") is None)
    check("中文名不是代码", PIT.normalize_ticker("瑞波") is None)


def test_pit_coverage():
    section("14. PIT 可靠性报告")
    changes = ([{"date": f"2024-{m:02d}-01", "added": f"A{m}"} for m in range(1, 13)]
               + [{"date": f"2023-{m:02d}-01", "added": f"B{m}"} for m in range(1, 13)]
               + [{"date": "2018-05-01", "added": "C1"}])       # 2018 只有 1 条
    snaps = PIT.build_snapshots(["Z"], "2025-01-01", changes)
    report = PIT.coverage_report(snaps, changes)
    check("逐年统计变更条数", report["changesPerYear"]["2024"] == 12)
    check("记录稀疏的年份被识别为不可靠边界",
          report["reliableFrom"] == "2019-01-01", str(report["reliableFrom"]))
    check("报出最早/最晚变更日",
          report["earliestChange"] == "2018-05-01" and report["latestChange"] == "2024-12-01")
    check("不把 date.min 当成有意义的最早日期", "earliest" not in report)


def test_wikipedia_parser():
    section("15. 维基百科成分表解析")
    tickers, sectors = WIKI.parse_constituents(WIKI_FIXTURE, min_members=2)
    check("解析出成分与行业", tickers == ["MMM", "BRK-B"], str(tickers))
    check("行业取 GICS 列", sectors.get("MMM") == "Industrials")
    check("占位符行被跳过", len(tickers) == 2)
    check("成分数明显偏少时不认这张表",
          WIKI.parse_constituents(WIKI_FIXTURE, min_members=400)[0] == [])

    changes = WIKI.parse_changes(WIKI_FIXTURE)
    dates = [c["date"] for c in changes]
    # rowspan 合并日期：同一天的第二笔调整少一个单元格，日期必须沿用上一行。
    # 漏掉这一步会让当天第二笔之后的调整全部错位，而且不会报错。
    check("rowspan 合并日期被正确沿用", dates.count("2024-03-18") == 2, str(dates))
    check("变更按日期升序", dates == sorted(dates))
    check("脚注 <sup> 被剥掉",
          all("[1]" not in c["reason"] for c in changes),
          str([c["reason"] for c in changes]))
    check("增删代码都解析到",
          any(c["added"] == "SMCI" and c["removed"] == "WHR" for c in changes))


def test_pit_filters_cross_section():
    section("16. PIT 过滤真的作用在横截面上")
    from fixtures import synthetic_market as _sm
    members, series, bench, dates = _sm(n_stocks=30, n_days=400, seed=9,
                                        signal_strength=0.002)
    t = len(dates) - 1
    allowed = {m["symbol"] for m in members[:10]}

    full, _ = raw_cross_section(members, series, bench, t)
    subset, _ = raw_cross_section(members, series, bench, t, allowed=allowed)
    check("不传 allowed 时全量参与", len(full) > len(subset), f"{len(full)} vs {len(subset)}")
    check("传了 allowed 只算在册成分",
          {r["symbol"] for r in subset} <= allowed and len(subset) == 10,
          str(len(subset)))
    check("被排除的标的完全不出现",
          not ({r["symbol"] for r in subset} & {m["symbol"] for m in members[10:]}))


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
    test_fundamental_parser()
    test_b_layer_pipeline()
    test_interval_guard()
    test_pit_reconstruction()
    test_pit_coverage()
    test_wikipedia_parser()
    test_pit_filters_cross_section()

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
