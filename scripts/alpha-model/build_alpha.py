#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Ooglex Alpha 60 V1 —— 每日扫描与历史回测的命令行入口。

    python3 scripts/alpha-model/build_alpha.py scan       # 生成今日排名
    python3 scripts/alpha-model/build_alpha.py backtest    # 跑验收协议
    python3 scripts/alpha-model/build_alpha.py scan --offline      # 合成数据自检
    python3 scripts/alpha-model/build_alpha.py backtest --offline --null

规格见 docs/OOGLEX_ALPHA_MODEL.md。

两条纪律写进了代码而不是只写在文档里：
  · 回测只用 A 层（价格/成交量）因子。B 层基本面没有 point-in-time 历史，
    用今天的财务快照回测过去就是未来函数，会让回测虚高且不可信。
  · ``--offline`` 产出的一切都带 ``demo: true``，不得进入任何对外页面。
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from backtest import (  # noqa: E402
    decile_stats,
    evaluate_gates,
    factor_ic_table,
    ic_summary,
    rank_ic_series,
    rank_ic_series_dense,
    simulate_portfolio,
    spearman,
)
from config import (  # noqa: E402
    BACKTEST_COST_BPS_ONE_WAY,
    BACKTEST_TOP_N,
    BENCHMARK,
    HORIZON_DAYS,
    MIN_HISTORY_DAYS,
    MODEL_NAME,
    MODEL_VERSION,
    SOURCE_NAME,
    WEIGHTS,
    WEIGHTS_A,
)
from factors import forward_excess_return  # noqa: E402
from fundamentals import load_fundamentals  # noqa: E402
from pipeline import (  # noqa: E402
    explain,
    rank_cross_section,
    raw_cross_section,
    score_distribution,
    select_candidates,
)
from prices import (  # noqa: E402
    NotDailyDataError,
    align_to_calendar,
    fetch_history,
    infer_interval,
    new_session,
)
from report import write_report  # noqa: E402
from universe import load_symbols_file, load_universe  # noqa: E402

DEFAULT_OUT = os.path.join(HERE, "output")
REBALANCE_SPACING = 21          # 约一个月一次调仓
IC_STEP = 10                    # IC 评估间隔（交易日）。用重叠窗口换统计功效，
                                # 显著性由 Newey–West 修正，不靠丢样本换干净。


def _now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# --------------------------------------------------------------------------
# 数据装载
# --------------------------------------------------------------------------
def load_live(members, rng, verbose=True):  # noqa: C901
    """抓取基准与全部成分股，对齐到基准的交易日历。

    基准（SPY）的交易日就是主日历：它每个交易日都有成交，用它当标尺
    可以让个股的停牌与缺失暴露成显式缺口，而不是被悄悄压缩掉。
    """
    session = new_session()
    try:
        bench_series = fetch_history(session, BENCHMARK, rng=rng)
    except NotDailyDataError as error:
        raise SystemExit(
            f"\n粒度校验未通过：{error}\n\n"
            "为什么这条会直接终止：模型全部因子都按「一个 bar = 一个交易日」定义。\n"
            "拿到月线却继续跑，不会报错，只会算出一整套看上去正常的废数——\n"
            "60个交易日前瞻会变成60个月前瞻，12个月动量会变成19年动量。\n"
            "建议改用 --range 10y。")
    if not bench_series:
        raise SystemExit(f"基准 {BENCHMARK} 行情获取失败，终止；不用残缺日历打分")

    dates = bench_series["dates"]
    bench_closes = bench_series["closes"]
    interval, gap = infer_interval(dates)
    if verbose:
        print(f"  基准日历 {len(dates)} 个 bar，粒度 {interval}"
              f"（中位间隔 {gap} 天），{dates[0]} → {dates[-1]}", file=sys.stderr)

    series, failures, wrong_interval = {}, [], []
    for i, member in enumerate(members, start=1):
        try:
            raw = fetch_history(session, member["symbol"], rng=rng)
        except NotDailyDataError:
            wrong_interval.append(member["symbol"])   # 粒度不符，整只弃用
            continue
        if not raw:
            failures.append(member["symbol"])
            continue
        closes, volumes, _ = align_to_calendar(raw, dates)
        series[member["symbol"]] = (closes, volumes)
        if verbose and i % 50 == 0:
            print(f"  已取 {i}/{len(members)}", file=sys.stderr)

    if verbose and failures:
        print(f"  {len(failures)} 只取数失败：{', '.join(failures[:12])}"
              f"{' …' if len(failures) > 12 else ''}", file=sys.stderr)
    if verbose and wrong_interval:
        print(f"  {len(wrong_interval)} 只粒度不是日线，已弃用："
              f"{', '.join(wrong_interval[:8])}", file=sys.stderr)
    return series, bench_closes, dates, failures + wrong_interval


def load_offline(null=False, n_stocks=120, n_days=900, signal=0.0016):
    from fixtures import synthetic_market
    strength = 0.0 if null else signal
    members, series, bench, dates = synthetic_market(
        n_stocks=n_stocks, n_days=n_days, signal_strength=strength)
    return members, series, bench, dates


# --------------------------------------------------------------------------
# scan：生成当日排名
# --------------------------------------------------------------------------
def run_scan(args):
    demo = bool(args.offline)
    if demo:
        members, series, bench_closes, dates = load_offline(
            null=args.null, n_stocks=args.limit or 120, signal=args.signal)
        failures, universe_meta = [], {"source": "合成数据", "pointInTime": False}
    else:
        members, universe_meta = _resolve_universe(args)
        series, bench_closes, dates, failures = load_live(members, args.range)

    t = len(dates) - 1
    rows, rejected = raw_cross_section(members, series, bench_closes, t)

    # B 层：默认联网抓取；给了外部文件则用文件；--no-fundamentals 跳过。
    # 拿不到就整体缺失，总分按 A 层权重重新归一化——不填中位数。
    fundamentals, fund_meta = _resolve_fundamentals(args, rows, demo)
    weights = WEIGHTS if fundamentals else WEIGHTS_A
    scored = rank_cross_section(rows, fundamentals=fundamentals, weights=weights)
    candidates, candidate_rule = select_candidates(scored)
    distribution = score_distribution(scored)

    top = []
    for row in scored[:args.top]:
        top.append({
            "rank": row["rank"],
            "symbol": row["symbol"],
            "name": row["name"],
            "sector": row["sector"],
            "price": round(row["price"], 4),
            "alpha60": round(row["alpha"], 2),
            "percentile": round(row["percentile"], 2),
            "coverage": round(row["coverage"], 3),
            "confluence": row["confluence"],
            "confluenceDispersion": (round(row["confluenceDispersion"], 2)
                                     if row["confluenceDispersion"] is not None else None),
            "families": {k: (round(v, 2) if v is not None else None)
                         for k, v in row["families"].items()},
            "isCandidate": any(c["symbol"] == row["symbol"] for c in candidates),
            "explain": explain(row),
        })

    status = "ok" if not failures else ("partial" if len(failures) < len(members) * 0.1 else "stale")
    payload = {
        "model": MODEL_NAME,
        "version": MODEL_VERSION,
        "horizonDays": HORIZON_DAYS,
        "benchmark": BENCHMARK,
        "objective": f"未来{HORIZON_DAYS}个交易日相对{BENCHMARK}的超额收益排序",
        "source": "合成数据（仅供自检）" if demo else SOURCE_NAME,
        "asOf": dates[t],
        "barInterval": _calendar_interval(dates)[0],
        "updatedAt": _now(),
        "frequency": "daily",
        "status": "ok" if demo else status,
        "demo": demo,
        "weightsUsed": weights,
        "blocksScored": ("A层价格因子" if weights is WEIGHTS_A else "A层价格因子 + B层基本面"),
        "note": ("合成数据自检结果，不是市场数据，不得作为研究结论"
                 if demo else
                 "打分基于日线收盘，非实时；B层为当前财务快照、无PIT历史，"
                 "仅用于当日打分不参与回测；缺失时总分按A层权重重新归一化"),
        "fundamentals": fund_meta,
        "universe": {**universe_meta, "requested": len(members),
                     "priced": len(series), "screened": len(scored),
                     "rejected": len(rejected), "fetchFailures": len(failures)},
        "scoreDistribution": distribution,
        "candidatePool": {"count": len(candidates),
                          "rule": candidate_rule,
                          "symbols": [c["symbol"] for c in candidates]},
        "rejectedSamples": rejected[:20],
        "ranking": top,
        "disclaimer": "研究用途，不构成投资建议。分数是横截面排序，不是收益预测。",
    }

    out = _write(payload, args.out, "alpha60.json")
    page = write_report(payload, out[:-5] + ".html", "scan")
    print(f"已写入 {out}")
    print(f"报告页 {page}   ← 双击用浏览器打开")
    print(f"股票池 {len(members)} → 通过过滤 {len(scored)} → 候选池 {len(candidates)}"
          + ("（共振门槛因B层缺失降为"
             f"{candidate_rule['minConfluence']}/{candidate_rule['configuredMinConfluence']}）"
             if candidate_rule["relaxed"] else ""))
    if fund_meta.get("used"):
        print(f"B层基本面 {fund_meta.get('fetched', fund_meta.get('count'))} 只可用"
              f"（当前快照，无PIT历史，不参与回测）")
    else:
        print(f"B层未接入：{fund_meta.get('reason', '未知')}；总分按A层权重重新归一化")
    if distribution:
        print(f"总分分布 中位 {distribution['p50']:.1f}  90分位 {distribution['p90']:.1f}  "
              f"99分位 {distribution['p99']:.1f}  ≥80占比 {distribution['shareAbove80']*100:.1f}%")
    for row in top[:min(10, len(top))]:
        print(f"  #{row['rank']:>3} {row['symbol']:<8} {row['alpha60']:>6.2f}  "
              f"共振{row['confluence']}  {row['sector']}")
    return payload


# --------------------------------------------------------------------------
# backtest：验收协议
# --------------------------------------------------------------------------
def run_backtest(args):
    demo = bool(args.offline)
    if demo:
        members, series, bench_closes, dates = load_offline(
            null=args.null, n_stocks=args.limit or 120, n_days=args.days or 900,
            signal=args.signal)
        universe_meta = {"source": "合成数据", "pointInTime": False}
    else:
        members, universe_meta = _resolve_universe(args)
        series, bench_closes, dates, _ = load_live(members, args.range)

    last_usable = len(dates) - HORIZON_DAYS - 1
    if last_usable <= MIN_HISTORY_DAYS:
        raise SystemExit(f"历史长度不足：需要至少 {MIN_HISTORY_DAYS + HORIZON_DAYS} 个交易日")

    # ---- IC 与分组 ----
    # 密集评估（每 IC_STEP 个交易日）+ Newey–West 修正标准误。
    # 此前强制不重叠窗口，统计上干净但功效太低：5 年只剩 16 个样本，
    # 标准误 0.049，连 IC=0.02 都测不出来，"未通过"和"测不出"分不开。
    dense, sparse, pooled_scores, pooled_labels = [], [], [], []
    factor_series, family_series = {}, {}

    for t in range(MIN_HISTORY_DAYS, last_usable + 1, IC_STEP):
        scored = _score_at(members, series, bench_closes, t)
        labels = [forward_excess_return(series[r["symbol"]][0], bench_closes, t, HORIZON_DAYS)
                  for r in scored]
        if sum(1 for l in labels if l is not None) < 20:
            continue
        scores = [r["alpha"] for r in scored]
        dense.append((t, scores, labels))

        # 逐因子分解：composite 失败时用它定位是哪些因子在拖后腿
        for name in sorted(scored[0].get("ranked") or {}):
            ic_one = spearman([r["ranked"].get(name) for r in scored], labels)
            if ic_one is not None:
                factor_series.setdefault(name, []).append((t, ic_one))
        for fam in sorted(scored[0].get("families") or {}):
            ic_one = spearman([(r["families"] or {}).get(fam) for r in scored], labels)
            if ic_one is not None:
                family_series.setdefault(fam, []).append((t, ic_one))

        # 不重叠子集：作为交叉核对，两者应当同号同量级
        if not sparse or (t - sparse[-1][0]) >= HORIZON_DAYS:
            sparse.append((t, scores, labels))
            pooled_scores.extend(scores)
            pooled_labels.extend(labels)

    nw_lag = max(1, -(-HORIZON_DAYS // IC_STEP))     # 前瞻期换算成评估期数
    ic = ic_summary(rank_ic_series_dense(dense), nw_lag=nw_lag)
    ic["step"] = IC_STEP
    ic["overlapping"] = True
    ic["neweyWestLag"] = nw_lag
    ic["nonOverlappingCheck"] = ic_summary(rank_ic_series(sparse, HORIZON_DAYS))

    factor_ic = factor_ic_table(factor_series, nw_lag)
    family_ic = factor_ic_table(family_series, nw_lag)
    deciles = decile_stats(pooled_scores, pooled_labels)

    # ---- 组合：每月调仓，持有到下次调仓，收益序列不重叠 ----
    rebalances = []
    for t in range(MIN_HISTORY_DAYS, len(dates) - REBALANCE_SPACING - 1, REBALANCE_SPACING):
        scored = _score_at(members, series, bench_closes, t)
        if not scored:
            continue
        rebalances.append((
            dates[t],
            {r["symbol"]: r["alpha"] for r in scored},
            {r["symbol"]: forward_excess_return(series[r["symbol"]][0], bench_closes,
                                                t, REBALANCE_SPACING)
             for r in scored},
        ))
    portfolio = simulate_portfolio(rebalances, BACKTEST_TOP_N,
                                   spacing_days=REBALANCE_SPACING)

    passed, checks = evaluate_gates(ic, deciles or {}, portfolio or {})

    payload = {
        "model": MODEL_NAME,
        "version": MODEL_VERSION,
        "mode": "backtest",
        "demo": demo,
        "null": bool(args.null),
        "horizonDays": HORIZON_DAYS,
        "benchmark": BENCHMARK,
        "factorsUsed": list(WEIGHTS_A),
        "updatedAt": _now(),
        "window": {"from": dates[MIN_HISTORY_DAYS], "to": dates[len(dates) - 1],
                   "tradingDays": len(dates),
                   "barInterval": _calendar_interval(dates)[0],
                   "medianGapDays": _calendar_interval(dates)[1]},
        "rankIC": ic,
        "factorIC": factor_ic,
        "familyIC": family_ic,
        "deciles": deciles,
        "portfolio": {k: v for k, v in (portfolio or {}).items() if k != "periods"},
        "gates": {"passed": passed, "checks": checks},
        "costModel": {"oneWayBps": BACKTEST_COST_BPS_ONE_WAY,
                      "note": "换手率按被替换仓位比例计，买卖各付一次单边成本"},
        "knownBiases": [
            universe_meta.get("survivorshipBias")
            or "股票池非 point-in-time，含幸存者偏差",
            "回测只含A层价格因子；B层基本面无PIT历史，不参与回测",
            f"IC用重叠窗口（每{IC_STEP}个交易日一次）换取统计功效，"
            f"标准误已按 Newey–West（滞后{max(1, -(-HORIZON_DAYS // IC_STEP))}期）修正",
            "若 |t| < 2，说明样本不足以判断，不能读成「模型是负的」",
            "未做多重检验校正；若尝试过多个因子变体，需对显著性打折",
        ],
        "disclaimer": "研究用途，不构成投资建议。历史表现不代表未来。",
    }

    out = _write(payload, args.out, "alpha60_backtest.json")
    page = write_report(payload, out[:-5] + ".html", "backtest")
    _print_backtest(payload, out)
    print(f"\n报告页 {page}   ← 双击用浏览器打开")
    return payload


def _calendar_interval(dates):
    """主日历的真实粒度。写进输出，让读者能一眼确认这是日线而不是被降级的月线。"""
    from prices import infer_interval as _infer
    return _infer(dates)


def _score_at(members, series, bench_closes, t):
    """单个横截面日的打分。回测路径固定只用 A 层权重。"""
    rows, _ = raw_cross_section(members, series, bench_closes, t)
    return rank_cross_section(rows, fundamentals=None, weights=WEIGHTS_A)


def _print_backtest(payload, out):
    ic = payload["rankIC"]
    print(f"已写入 {out}")
    print(f"\n窗口 {payload['window']['from']} → {payload['window']['to']}"
          f"（{payload['window']['tradingDays']} 个交易日）")
    print(f"Rank IC  均值 {_f(ic['mean'])}  信息比 {_f(ic['ir'])}  "
          f"胜率 {_f(ic['hitRate'])}  样本 {ic['n']}")
    print(f"         t值 {_f(ic.get('tStat'), 2)}  "
          f"95%区间 [{_f((ic.get('ci95') or [None, None])[0])}, "
          f"{_f((ic.get('ci95') or [None, None])[1])}]  "
          f"{'可与0区分' if ic.get('distinguishableFromZero') else '← 无法与0区分，样本不足'}")
    top_factors = (payload.get("factorIC") or [])[:5]
    if top_factors:
        print("\n单因子 IC 排名（前5）：")
        for row in top_factors:
            print(f"  {row['factor']:<20} IC {_f(row['mean'])}  "
                  f"t {_f(row.get('tStat'), 2)}  胜率 {_f(row['hitRate'], 3)}")
        worst = (payload.get("factorIC") or [])[-3:]
        print("单因子 IC 垫底（后3）：")
        for row in worst:
            print(f"  {row['factor']:<20} IC {_f(row['mean'])}  "
                  f"t {_f(row.get('tStat'), 2)}  胜率 {_f(row['hitRate'], 3)}")
    dec = payload.get("deciles") or {}
    if dec.get("groups"):
        print(f"分组单调性 {_f(dec['monotonicSpearman'])}（期望接近 −1）  "
              f"D1−D10 {_f(dec['topMinusBottom'])}")
        for g in dec["groups"]:
            print(f"  D{g['decile']:<2} n={g['count']:<5} 平均超额 {_f(g['meanForward'])}")
    pf = payload.get("portfolio") or {}
    if pf:
        print(f"组合 Top{BACKTEST_TOP_N} 等权：累计超额 {_f(pf.get('cumulativeExcess'))}  "
              f"每期均值 {_f(pf.get('meanExcessPerPeriod'))}  胜率 {_f(pf.get('hitRate'))}")
        print(f"      年换手 {_f(pf.get('annualTurnover'))}  "
              f"成本累计 {_f(pf.get('costDrag'))}  最大回撤 {_f(pf.get('maxDrawdown'))}")
    print(f"\n验收：{'通过' if payload['gates']['passed'] else '未通过'}")
    for check in payload["gates"]["checks"]:
        print(f"  [{'✓' if check['pass'] else '✗'}] {check['name']}：{check['detail']}")


def _f(value, digits=4):
    return "—" if value is None else f"{value:.{digits}f}"


# --------------------------------------------------------------------------
# 辅助
# --------------------------------------------------------------------------
def _resolve_universe(args):
    if args.symbols:
        return load_symbols_file(args.symbols), {
            "source": os.path.basename(args.symbols), "pointInTime": False}
    return load_universe(limit=args.limit)


def _resolve_fundamentals(args, rows, demo):
    """决定 B 层数据从哪来。返回 (数据或 None, 元数据)。

    优先级：--no-fundamentals > --fundamentals 文件 > 联网抓取。
    外部文件的口子保留，是为了让换用别家数据源（含真正 PIT 的）不必改模型。

    外部文件格式是**子因子级**而不是族级：
        {"NVDA": {"revenue_growth": 0.62, "earnings_yield": 0.04, ...}, ...}
    键名见 ``config.SUBWEIGHTS`` 的 fundamental / valuation / revision 三族。
    这样外部数据和内建取数走同一条归一化流水线，尺度一致。
    """
    if demo or getattr(args, "no_fundamentals", False):
        return None, {"used": False,
                      "reason": "合成数据模式" if demo else "--no-fundamentals 显式跳过"}

    if getattr(args, "fundamentals", None):
        with open(args.fundamentals, encoding="utf-8") as f:
            data = json.load(f)
        return data, {"used": True, "source": os.path.basename(args.fundamentals),
                      "pointInTime": "未知，取决于外部文件", "count": len(data)}

    symbols = [r["symbol"] for r in rows]
    print(f"  取 B 层基本面（{len(symbols)} 只）…", file=sys.stderr)
    session = new_session()
    data, meta = load_fundamentals(session, symbols)
    if not data:
        print(f"  B层跳过：{meta.get('reason') or '全部取数失败'}", file=sys.stderr)
        return None, {"used": False, **meta, "source": SOURCE_NAME}
    print(f"  B层取到 {meta['fetched']}/{meta['requested']} 只", file=sys.stderr)
    return data, {"used": True, "source": SOURCE_NAME, "pointInTime": False, **meta}


def _write(payload, out_dir, filename):
    out_dir = out_dir or DEFAULT_OUT
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, filename)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)
    return path


def main(argv=None):
    parser = argparse.ArgumentParser(description=f"{MODEL_NAME} V{MODEL_VERSION}")
    sub = parser.add_subparsers(dest="command", required=True)

    for name, handler in (("scan", run_scan), ("backtest", run_backtest)):
        p = sub.add_parser(name)
        p.add_argument("--offline", action="store_true",
                       help="用合成数据跑通管线，输出标记 demo:true")
        p.add_argument("--null", action="store_true",
                       help="合成数据不含任何信号，用于确认管线不会无中生有")
        p.add_argument("--signal", type=float, default=0.0016,
                       help="合成数据的每日漂移幅度；越大信噪比越高")
        p.add_argument("--limit", type=int, default=None, help="股票池上限")
        p.add_argument("--symbols", default=None, help="自定义股票池文件")
        p.add_argument("--range", default="5y",
                       help="行情区间，如 5y / 10y。不要用 max——Yahoo 在超长区间下"
                            "会静默把日线降级成月线，程序会因粒度校验直接终止")
        p.add_argument("--out", default=None, help="输出目录")
        p.set_defaults(func=handler)

    sub.choices["scan"].add_argument("--top", type=int, default=50, help="输出前 N 名")
    sub.choices["scan"].add_argument("--fundamentals", default=None,
                                     help="外部B层 JSON，形如 {代码: {子因子: 原始值}}，"
                                          "子因子键名见 config.SUBWEIGHTS 的后三族；"
                                          "缺省则联网抓取")
    sub.choices["scan"].add_argument("--no-fundamentals", action="store_true",
                                     dest="no_fundamentals",
                                     help="跳过B层，只用A层价格因子打分")
    sub.choices["backtest"].add_argument("--days", type=int, default=None,
                                         help="合成数据天数")
    sub.choices["backtest"].set_defaults(range="10y")   # 回测默认拉满历史：
    # 5y 只能给出十几个独立窗口，统计上判不了任何事

    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
