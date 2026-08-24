#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""确定性合成行情，仅供离线自检与管线演示使用。

**这不是市场数据。** 生成的任何结果都带 ``demo: true``，绝不可当作研究结论，
也绝不可写入任何对外页面。它存在的唯一目的是：在没有网络的环境里，
把打分与回测管线完整跑一遍并断言其行为。

两种模式对应两个必须都成立的性质：
  · ``signal_strength > 0``：股票收益中真的埋了一个动量可捕捉的持续漂移，
    管线必须能把它找出来（IC 显著为正）。
  · ``signal_strength = 0``：纯随机游走，什么规律都没有。管线必须找不到东西
    （IC ≈ 0，验收线不通过）。第二条比第一条重要——它证明这套代码
    不会从噪声里凭空造出 alpha。
"""

import random
from datetime import date, timedelta


def _trading_days(n, start=date(2019, 1, 2)):
    days, cursor = [], start
    while len(days) < n:
        if cursor.weekday() < 5:
            days.append(cursor.isoformat())
        cursor += timedelta(days=1)
    return days


def synthetic_market(n_stocks=120, n_days=900, seed=7, signal_strength=0.0):
    """生成 (成分, {代码: (closes, volumes)}, 基准收盘序列, 日期序列)。

    ``signal_strength`` 是每日漂移的幅度上限：股票 i 的漂移 = (q_i − 0.5) × 强度，
    q_i 为该股的隐含“质量”。强度取 0 即无任何可预测成分。
    基准是全体成分股的等权指数，与个股收益内部自洽。
    """
    rng = random.Random(seed)
    sectors = ["科技", "金融", "工业", "医疗健康", "可选消费", "能源"]

    members, params = [], []
    for i in range(n_stocks):
        quality = rng.random()
        members.append({
            "symbol": f"S{i:03d}",
            "name": f"合成标的{i:03d}",
            "sector": sectors[i % len(sectors)],
        })
        params.append({
            "drift": (quality - 0.5) * signal_strength,
            "sigma": 0.008 + 0.014 * rng.random(),
            "beta": 0.6 + 0.9 * rng.random(),
            "price": 40.0 + 160.0 * rng.random(),
            "volume": 8e5 + 2.4e6 * rng.random(),
        })

    closes = [[p["price"]] for p in params]
    volumes = [[p["volume"]] for p in params]
    for _ in range(n_days - 1):
        market = 0.0003 + 0.009 * rng.gauss(0, 1)
        for i, p in enumerate(params):
            ret = p["drift"] + p["beta"] * market + p["sigma"] * rng.gauss(0, 1)
            closes[i].append(max(1.0, closes[i][-1] * (1.0 + ret)))
            # 成交量与当日波动幅度正相关，并带自身随机游走，使量能因子有横截面差异
            shock = 1.0 + 2.5 * abs(ret) + 0.25 * rng.gauss(0, 1)
            volumes[i].append(max(1e4, p["volume"] * max(0.2, shock)))

    series = {m["symbol"]: (closes[i], volumes[i]) for i, m in enumerate(members)}

    bench = [100.0]
    for day in range(1, n_days):
        rets = [closes[i][day] / closes[i][day - 1] - 1.0 for i in range(n_stocks)]
        bench.append(bench[-1] * (1.0 + sum(rets) / len(rets)))

    return members, series, bench, _trading_days(n_days)
