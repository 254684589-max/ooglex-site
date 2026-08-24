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
    ic_summary,
    rank_ic_series,
    simulate_portfolio,
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
from prices import align_to_calendar, fetch_history, new_session  # noqa: E402
from report import write_report  # noqa: E402
from universe import load_symbols_file, load_universe  # noqa: E402

DEFAULT_OUT = os.path.join(HERE, "output")
REBALANCE_SPACING = 21          # 约一个月一次调仓


def _now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# --------------------------------------------------------------------------
# 数据装载
# --------------------------------------------------------------------------
def load_live(members, rng, verbose=True):
    """抓取基准与全部成分股，对齐到基准的交易日历。

    基准（SPY）的交易日就是主日历：它每个交易日都有成交，用它当标尺
    可以让个股的停牌与缺失暴露成显式缺口，而不是被悄悄压缩掉。
    """
    session = new_session()
    bench_series = fetch_history(session, BENCHMARK, rng=rng)
    if not bench_series:
        raise SystemExit(f"基准 {BENCHMARK} 行情获取失败，终止；不用残缺日历打分")

    dates = bench_series["dates"]
    bench_closes = bench_series["closes"]

    series, failures = {}, []
    for i, member in enumerate(members, start=1):
        raw = fetch_history(session, member["symbol"], rng=rng)
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
    return series, bench_closes, dates, failures


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

    # ---- IC 与分组：评估日必须不重叠，间隔 = 前瞻期 ----
    ic_snapshots, pooled_scores, pooled_labels = [], [], []
    for t in range(MIN_HISTORY_DAYS, last_usable + 1, HORIZON_DAYS):
        scored = _score_at(members, series, bench_closes, t)
        labels = [forward_excess_return(series[r["symbol"]][0], bench_closes, t, HORIZON_DAYS)
                  for r in scored]
        scores = [r["alpha"] for r in scored]
        if sum(1 for l in labels if l is not None) < 20:
            continue
        ic_snapshots.append((t, scores, labels))
        pooled_scores.extend(scores)
        pooled_labels.extend(labels)

    ic = ic_summary(rank_ic_series(ic_snapshots, HORIZON_DAYS))
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
                   "tradingDays": len(dates)},
        "rankIC": ic,
        "deciles": deciles,
        "portfolio": {k: v for k, v in (portfolio or {}).items() if k != "periods"},
        "gates": {"passed": passed, "checks": checks},
        "costModel": {"oneWayBps": BACKTEST_COST_BPS_ONE_WAY,
                      "note": "换手率按被替换仓位比例计，买卖各付一次单边成本"},
        "knownBiases": [
            universe_meta.get("survivorshipBias")
            or "股票池非 point-in-time，含幸存者偏差",
            "回测只含A层价格因子；B层基本面无PIT历史，不参与回测",
            f"评估日间隔{HORIZON_DAYS}个交易日，前瞻窗口不重叠",
            "未做多重检验校正；若尝试过多个因子变体，需对显著性打折",
        ],
        "disclaimer": "研究用途，不构成投资建议。历史表现不代表未来。",
    }

    out = _write(payload, args.out, "alpha60_backtest.json")
    page = write_report(payload, out[:-5] + ".html", "backtest")
    _print_backtest(payload, out)
    print(f"\n报告页 {page}   ← 双击用浏览器打开")
    return payload


def _score_at(members, series, bench_closes, t):
    """单个横截面日的打分。回测路径固定只用 A 层权重。"""
    rows, _ = raw_cross_section(members, series, bench_closes, t)
    return rank_cross_section(rows, fundamentals=None, weights=WEIGHTS_A)


def _print_backtest(payload, out):
    ic = payload["rankIC"]
    print(f"已写入 {out}")
    print(f"\n窗口 {payload['window']['from']} → {payload['window']['to']}"
          f"（{payload['window']['tradingDays']} 个交易日）")
    print(f"Rank IC  均值 {_f(ic['mean'])}  标准差 {_f(ic['std'])}  "
          f"信息比 {_f(ic['ir'])}  胜率 {_f(ic['hitRate'])}  样本 {ic['n']}")
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
        p.add_argument("--range", default="5y", help="行情区间，如 5y / 10y")
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

    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
