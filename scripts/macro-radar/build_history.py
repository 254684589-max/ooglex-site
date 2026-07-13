#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「Regime 时光机」历史数据 history.json：
按当前宏观雷达的方法学，把 7 大制度信号与综合机制读数回溯到 2006 年（周频），
并标注历史危机事件窗口，供前端时间轴拖动重放。

方法学与 build_radar.py 保持一致（滚动 2 年分位、同一权重、EMA 平滑）：
  流动性 = 净流动性(WALCL−TGA−RRP) 水平 0.35 + 13 周流量 impulse 0.40
           + 融资验证 0.25（TED 利差 ←2022-01 / SOFR−IORB 2023→ 接力；空档归一化）
  波动率 = 100 − VIX(FRED VIXCLS) 分位
  期限   = 0.55·T10Y3M 分位 + 0.45·(100 − ACM 期限溢价分位)
  信用   = 100 − 高收益债 OAS 分位
  增长   = mean(铜/金、SOX/SPY、XLY/XLP 分位)
  美元   = 100 − 美元指数分位
  广度   = RSP/SPY 水平分位 0.5 + 63 日 impulse 分位 0.5
综合 = 相同权重加权（缺失项按剩余权重归一化）→ 周频 EMA(α=0.6)。

由 .github/workflows/macro_radar.yml 每日在 build_radar.py 之后运行；
需要 FRED_API_KEY（Yahoo 免 key）。构建失败/数据不足时保留旧 history.json。
"""
import json
import os
import time
from bisect import bisect_right, insort
from datetime import date, datetime, timezone

import requests

OUT_PATH = os.path.join("apps", "macro-radar", "history.json")
UA = {"User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                     "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")}
WIN_D = 504   # 日频 2 年分位窗口
WIN_W = 104   # 周频 2 年分位窗口
START_OUT = "2006-01-01"   # 输出起点（此前用于分位窗口热身）

# 与 build_radar.py 相同的信号权重
WEIGHTS = {"liquidity": .20, "term": .15, "volatility": .13, "credit": .13,
           "growth": .15, "usd": .12, "breadth": .12}

# 历史危机事件（Transmission 案例）：id/名称/窗口/峰值/一句话机制解读
EPISODES = [
    {"id": "gfc", "name": "2008 全球金融危机", "en": "GFC · LEHMAN",
     "from": "2007-10-01", "to": "2009-06-30", "peak": "2008-11-21",
     "desc": "次贷→雷曼倒闭：信用冻结、VIX 破 80、美元融资挤兑；QE1 注入后机制自谷底修复。"},
    {"id": "eu11", "name": "2011 欧债·美债降级", "en": "EURO CRISIS",
     "from": "2011-07-01", "to": "2012-07-31", "peak": "2011-10-03",
     "desc": "欧债蔓延+美债降级：主权-银行死循环推升信用与波动，广度深度受损。"},
    {"id": "taper13", "name": "2013 缩减恐慌", "en": "TAPER TANTRUM",
     "from": "2013-05-01", "to": "2013-09-30", "peak": "2013-06-24",
     "desc": "伯南克暗示缩减 QE：实际利率与期限溢价急升，新兴市场资金外流。"},
    {"id": "cny15", "name": "2015 人民币冲击", "en": "CNY DEVAL",
     "from": "2015-08-01", "to": "2016-02-29", "peak": "2016-02-11",
     "desc": "811 汇改：贬值预期外溢，商品与广度走弱，强美元收紧全球金融条件。"},
    {"id": "q418", "name": "2018 联储双紧", "en": "FED TIGHTENING",
     "from": "2018-10-01", "to": "2018-12-31", "peak": "2018-12-24",
     "desc": "加息+QT 双紧：净流动性收缩传导至信用与波动，12 月市场逼宫联储转向。"},
    {"id": "repo19", "name": "2019 回购危机", "en": "REPO CRISIS",
     "from": "2019-09-01", "to": "2019-10-31", "peak": "2019-09-17",
     "desc": "回购利率飙升：准备金稀缺被低估，融资利率突破走廊上限，联储重启扩表。"},
    {"id": "covid20", "name": "2020 新冠崩盘", "en": "COVID CRASH",
     "from": "2020-02-15", "to": "2020-04-30", "peak": "2020-03-23",
     "desc": "全球停摆引发现金挤兑（连黄金都遭抛售）；无限 QE 后机制 V 型反转。"},
    {"id": "qt22", "name": "2022 通胀紧缩", "en": "INFLATION / QT",
     "from": "2022-01-01", "to": "2022-10-31", "peak": "2022-10-12",
     "desc": "通胀失控+激进加息：净流动性、久期、信用同步收缩，典型熊陡→倒挂周期。"},
    {"id": "svb23", "name": "2023 硅谷银行", "en": "SVB",
     "from": "2023-03-01", "to": "2023-05-15", "peak": "2023-03-13",
     "desc": "利率风险引爆银行：存款搬家+持债浮亏，BTFP 定向注入止血。"},
    {"id": "carry24", "name": "2024 套息平仓", "en": "YEN CARRY UNWIND",
     "from": "2024-07-25", "to": "2024-08-15", "peak": "2024-08-05",
     "desc": "日央行加息触发日元套息平仓：VIX 瞬时冲高，波动传染快去快回。"},
]


# ── 取数 ────────────────────────────────────────────────────────────────
def fred_full(series_id, start="2001-01-01"):
    """FRED 全历史序列，升序 [(date,value)]；无 key 或失败返回 []。"""
    key = os.environ.get("FRED_API_KEY")
    if not key:
        return []
    url = ("https://api.stlouisfed.org/fred/series/observations?series_id=%s"
           "&api_key=%s&file_type=json&observation_start=%s&limit=100000"
           % (series_id, key, start))
    for attempt in range(2):
        try:
            r = requests.get(url, headers=UA, timeout=(8, 30))
            r.raise_for_status()
            out = []
            for o in (r.json() or {}).get("observations") or []:
                v = o.get("value")
                if v in (".", "", None):
                    continue
                try:
                    out.append((o.get("date"), float(v)))
                except (TypeError, ValueError):
                    continue
            if out:
                return out
        except Exception as e:
            print("FRED %s: %s" % (series_id, repr(e)[:90]))
        time.sleep(1.0)
    return []


def yahoo_full(symbols):
    """Yahoo 全历史日线，升序 [(date,close)]；失败返回 []。
    用显式 period1/period2 请求真·日频——range=max 会被 Yahoo 降采样成月频，
    导致下游 504 日分位窗口永远填不满。period1/period2 才返回逐日收盘。"""
    syms = symbols if isinstance(symbols, (list, tuple)) else [symbols]
    p1, p2 = 1072915200, int(time.time())   # 2004-01-01 → 现在
    windows = ("period1=%d&period2=%d" % (p1, p2), "range=max")
    for sym in syms:
        for host in ("query1", "query2"):
            for win in windows:
                url = ("https://%s.finance.yahoo.com/v8/finance/chart/%s"
                       "?%s&interval=1d" % (host, sym, win))
                try:
                    r = requests.get(url, headers=UA, timeout=(8, 30))
                    if r.status_code != 200:
                        continue
                    res = (r.json().get("chart") or {}).get("result") or []
                    if not res:
                        continue
                    res = res[0]
                    ts = res.get("timestamp") or []
                    closes = (((res.get("indicators") or {}).get("quote") or [{}])[0]
                              .get("close") or [])
                    out = []
                    for t, c in zip(ts, closes):
                        if c is None:
                            continue
                        d = datetime.fromtimestamp(t, tz=timezone.utc).strftime("%Y-%m-%d")
                        out.append((d, float(c)))
                    if len(out) >= 200:
                        time.sleep(0.6)
                        return out
                except Exception:
                    pass
                time.sleep(0.3)
    return []


def stooq_full(sym):
    """Stooq 免 key 全历史日线 CSV，升序 [(date,close)]；失败返回 []。
    Yahoo 在 CI 上易被限流，Stooq 作为股票/期货类的兜底源。"""
    url = "https://stooq.com/q/d/l/?s=%s&i=d" % sym
    for attempt in range(2):
        try:
            r = requests.get(url, headers=UA, timeout=(8, 30))
            if r.status_code == 200 and "," in r.text[:200]:
                out = []
                for line in r.text.splitlines()[1:]:
                    p = line.split(",")
                    if len(p) >= 5:
                        try:
                            out.append((p[0], float(p[4])))
                        except ValueError:
                            continue
                if len(out) >= 200:
                    return out
        except Exception:
            pass
        time.sleep(2.0)
    return []


def equity_full(name, yahoo_syms, stooq_sym):
    """股票/期货类全历史：Yahoo 优先，失败切 Stooq；打印来源与跨度便于排障。"""
    s = yahoo_full(yahoo_syms)
    src = "yahoo"
    if not s and stooq_sym:
        s = stooq_full(stooq_sym)
        src = "stooq"
    if s:
        print("%s: %s %d 点 %s→%s" % (name, src, len(s), s[0][0], s[-1][0]))
    else:
        print("%s: 全部来源失败" % name)
    return s


# ── 工具 ────────────────────────────────────────────────────────────────
def rolling_pct(vals, win):
    """滚动窗口分位（0–100），窗口未满为 None。O(n·log w) 有序缓冲实现。"""
    out = [None] * len(vals)
    buf = []
    for i, v in enumerate(vals):
        insort(buf, v)
        if len(buf) > win:
            old = vals[i - win]
            j = bisect_right(buf, old) - 1
            buf.pop(j)
        if len(buf) == win:
            out[i] = 100.0 * bisect_right(buf, v) / win
    return out


def score_series(pairs, win, invert=False):
    """[(d,v)] → [(d, 分位分)]，invert=True 表示越低越好(100−分位)。"""
    if not pairs:
        return []
    dates = [d for d, _ in pairs]
    p = rolling_pct([v for _, v in pairs], win)
    out = []
    for d, pc in zip(dates, p):
        if pc is None:
            continue
        out.append((d, 100 - pc if invert else pc))
    return out


def align_ratio(a, b):
    mb = dict(b)
    out = []
    for d, va in a:
        vb = mb.get(d)
        if vb:
            out.append((d, va / vb))
    return out


def _daydiff(d1, d2):
    return abs((date.fromisoformat(d1) - date.fromisoformat(d2)).days)


def med_gap(pairs):
    """序列相邻观测的中位间隔（天）。用于把窗口/滞后按实际频率自适应，
    兼容 Yahoo 偶尔降采样成月频的情况。"""
    if len(pairs) < 3:
        return 1.0
    gaps = sorted(_daydiff(pairs[i][0], pairs[i - 1][0]) for i in range(1, len(pairs)))
    return max(1.0, float(gaps[len(gaps) // 2]))


def cadence_win(pairs, target_days=730, lo=16, hi=WIN_D):
    """按序列频率推 ~2 年分位窗口点数：日频≈504、周频≈104、月频≈24。"""
    return max(lo, min(hi, round(target_days / med_gap(pairs))))


def cadence_lag(pairs, floor):
    """按序列频率推 as-of 允许滞后（天）：月频信号不能只给 10 天窗。"""
    return max(floor, round(2.5 * med_gap(pairs)))


def asof_factory(pairs, max_lag):
    """返回 get(d)：取日期 ≤ d 且滞后不超 max_lag 天的最近值。"""
    ds = [d for d, _ in pairs]
    vs = [v for _, v in pairs]

    def get(d):
        i = bisect_right(ds, d) - 1
        if i < 0:
            return None
        if max_lag is not None and _daydiff(d, ds[i]) > max_lag:
            return None
        return vs[i]
    return get


def impulse(pairs, n):
    """n 期变化序列：[(d_i, v_i − v_{i−n})]。"""
    return [(pairs[i][0], pairs[i][1] - pairs[i - n][1])
            for i in range(n, len(pairs))]


# ── 组装 ────────────────────────────────────────────────────────────────
def build():
    # —— 底层序列 ——
    vix = fred_full("VIXCLS")
    slope = fred_full("T10Y3M")
    tp = fred_full("THREEFYTP10")
    hyoas = fred_full("BAMLH0A0HYM2")
    wal = fred_full("WALCL")
    tga = fred_full("WTREGEN")
    rrp = fred_full("RRPONTSYD")
    ted = fred_full("TEDRATE")   # LIBOR3M−T-bill3M，1986→2022-01 停编
    sofr = fred_full("SOFR")
    iorb = fred_full("IORB")

    for sid, s in [("VIXCLS", vix), ("T10Y3M", slope), ("THREEFYTP10", tp),
                   ("BAMLH0A0HYM2", hyoas), ("WALCL", wal), ("WTREGEN", tga),
                   ("RRPONTSYD", rrp), ("TEDRATE", ted)]:
        print("%s: %d 点 %s→%s" % (sid, len(s), s[0][0] if s else "-", s[-1][0] if s else "-"))

    hg = equity_full("铜", "HG=F", "hg.f")
    gc = equity_full("金", "GC=F", "gc.f")
    sox = equity_full("SOX", "^SOX", "^sox")
    spy = equity_full("SPY", "SPY", "spy.us")
    xly = equity_full("XLY", "XLY", "xly.us")
    xlp = equity_full("XLP", "XLP", "xlp.us")
    rsp = equity_full("RSP", "RSP", "rsp.us")
    dxy = equity_full("DXY", ["DX-Y.NYB", "DX=F"], "dx.f")
    if not dxy:
        dxy = fred_full("DTWEXBGS", "2006-01-01")  # 贸易加权广义美元指数兜底（2006→）

    # —— 各信号打分序列 ——
    sigs = {}

    # 流动性：净流动性（周频）水平 + 13 周 impulse（融资验证历史过短省略，权重归一化）
    # TGA/RRP 与 WALCL 报告日并非逐点对齐，且 RRP 在设施放量前（≈2014）逐日稀疏，
    # 精确日匹配会把 2015 前的点几乎全丢掉。改用 as-of（取最近值）对齐：
    # TGA 周频给 30 天容差、起点前用首值；RRP 取最近值（设施启用前≈0，稀疏无妨）、
    # 起点前置 0——从而净流动性覆盖 WALCL 全程（2002→），流动性信号回溯到 GFC。
    nl = []
    if wal and tga and rrp:
        g_t = asof_factory(tga, 30)
        g_r = asof_factory(rrp, None)
        t0, tv0, r0 = tga[0][0], tga[0][1], rrp[0][0]
        for d, w in wal:
            t = g_t(d)
            if t is None and d < t0:
                t = tv0
            r = g_r(d)
            if r is None:
                r = 0.0 if d < r0 else None
            if t is None or r is None:
                continue
            nl.append((d, w / 1e3 - t / 1e3 - r))
    # 融资验证（三合一第三支柱）：TED 利差（←2022-01 停编）与 SOFR−IORB（2023→，
    # 分位窗口热身后）接力，越高越紧 → 反向分位。银行挤兑型危机（GFC/欧债/SVB）
    # 会在净流动性水平/流量之外额外压低流动性读数；两段间空档按剩余权重归一化。
    fund = score_series(ted, WIN_D, invert=True)
    si = []
    if sofr and iorb:
        mi = dict(iorb)
        si = [(d, v - mi[d]) for d, v in sofr if d in mi]
    si_p = score_series(si, WIN_D, invert=True)
    if si_p:
        fund = [(d, v) for d, v in fund if d < si_p[0][0]] + si_p
    if fund:
        print("融资验证: %d 点 %s→%s" % (len(fund), fund[0][0], fund[-1][0]))

    if len(nl) > WIN_W + 14:
        lvl = score_series(nl, WIN_W)
        imp = score_series(impulse(nl, 13), WIN_W)
        g_lvl = asof_factory(lvl, 21)
        g_fund = asof_factory(fund, 10) if fund else (lambda d: None)
        liq = []
        for d, ip in imp:
            lv = g_lvl(d)
            if lv is None:
                continue
            fu = g_fund(d)
            if fu is None:
                liq.append((d, (0.35 * lv + 0.40 * ip) / 0.75))
            else:
                liq.append((d, 0.35 * lv + 0.40 * ip + 0.25 * fu))
        sigs["liquidity"] = liq

    # 波动率
    sigs["volatility"] = score_series(vix, WIN_D, invert=True)

    # 期限：0.55·斜率分位 + 0.45·(100−期限溢价分位)
    sl_p = score_series(slope, WIN_D)
    tp_p = score_series(tp, WIN_D, invert=True)
    if sl_p:
        g_tp = asof_factory(tp_p, 10) if tp_p else (lambda d: None)
        term = []
        for d, sp in sl_p:
            t = g_tp(d)
            term.append((d, 0.55 * sp + 0.45 * t if t is not None else sp))
        sigs["term"] = term

    # 信用：HY OAS 历史完整时用之；FRED API 对 ICE 授权序列只回近几年时，
    # 退回穆迪 Baa−10Y 利差（BAA10Y，1986→，无授权限制）保证全程覆盖。
    credit_src = hyoas
    if not hyoas or hyoas[0][0] > "2006-01-01":
        baa = fred_full("BAA10Y")
        if baa and (not hyoas or baa[0][0] < hyoas[0][0]):
            credit_src = baa
            print("credit 历史改用 BAA10Y（HY OAS API 历史不足）")
    sigs["credit"] = score_series(credit_src, WIN_D, invert=True)

    # 增长：铜/金 + SOX/SPY + XLY/XLP 均值（分位窗口随各比率的实际频率自适应）
    def ratio_score(a, b):
        r = align_ratio(a, b)
        return score_series(r, cadence_win(r)) if len(r) >= 20 else []
    parts = [p for p in (ratio_score(hg, gc), ratio_score(sox, spy),
                         ratio_score(xly, xlp)) if p]
    if parts:
        parts.sort(key=len, reverse=True)   # 用最密的一支作基准日期轴
        base = parts[0]
        gets_g = [asof_factory(p, cadence_lag(p, 10)) for p in parts[1:]]
        grw = []
        for d, v in base:
            vals = [v] + [g(d) for g in gets_g]
            vals = [x for x in vals if x is not None]
            grw.append((d, sum(vals) / len(vals)))
        sigs["growth"] = grw

    # 美元
    sigs["usd"] = score_series(dxy, WIN_D, invert=True)

    # 广度：水平 0.5 + ~季度 impulse 0.5（窗口/动量期随频率自适应）
    br = align_ratio(rsp, spy)
    bwin = cadence_win(br)
    bn = max(1, round(63 / med_gap(br)))   # 日频→63（对齐实时雷达），月频→~2
    if len(br) > bwin + bn + 5:
        lvl = score_series(br, bwin)
        imp = score_series(impulse(br, bn), bwin)
        g_lvl = asof_factory(lvl, cadence_lag(br, 10))
        brd = []
        for d, ip in imp:
            lv = g_lvl(d)
            if lv is None:
                continue
            brd.append((d, 0.5 * lv + 0.5 * ip))
        sigs["breadth"] = brd

    have = [k for k, v in sigs.items() if v]
    for k in WEIGHTS:
        v = sigs.get(k) or []
        if v:
            print("  %-11s %4d 点 %s→%s (间隔≈%.0fd)"
                  % (k, len(v), v[0][0], v[-1][0], med_gap(v)))
        else:
            print("  %-11s 空" % k)
    print("信号可用:", have)
    if len(have) < 5 or not sigs.get("volatility"):
        print("历史数据不足，保留旧 history.json。")
        return

    # —— 输出网格：T10Y3M 打分日期每 5 个取 1（≈周频），起点 START_OUT ——
    tail = [d for d, _ in sl_p if d >= START_OUT]
    grid = tail[::5]
    # 周频下采样会把最近不足 5 个交易日的一段丢掉，令曲线右端最多滞后约一周
    # （表现为"停在上周某分数"）。补一个"最新交易日"点，让右端追到当前；
    # 该点仍按同一 as-of + 2 年分位方法学计算，其余点保持周频回溯。
    if tail and grid and grid[-1] != tail[-1]:
        grid.append(tail[-1])
    if len(grid) < 200:
        print("输出网格过短（%d），保留旧 history.json。" % len(grid))
        return

    gets = {k: asof_factory(v, cadence_lag(v, 21 if k == "liquidity" else 10))
            for k, v in sigs.items() if v}

    dates_out, regime_out = [], []
    sig_out = {k: [] for k in WEIGHTS}
    ema = None
    for d in grid:
        vals = {k: g(d) for k, g in gets.items()}
        num = den = 0.0
        for k, v in vals.items():
            if v is not None:
                num += WEIGHTS[k] * v
                den += WEIGHTS[k]
        if den < 0.5:            # 可用权重过半才输出该点
            continue
        raw = num / den
        ema = raw if ema is None else 0.6 * raw + 0.4 * ema
        dates_out.append(d)
        regime_out.append(round(ema))
        for k in WEIGHTS:
            v = vals.get(k)
            sig_out[k].append(None if v is None else round(v))

    if len(dates_out) < 200:
        print("有效输出过短（%d），保留旧 history.json。" % len(dates_out))
        return

    out = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "freq": "W",
        "start": dates_out[0],
        "dates": dates_out,
        "regime": regime_out,
        "signals": sig_out,
        "episodes": EPISODES,
        "note": ("按当前方法学周频回溯（滚动 2 年分位、同权重、EMA 平滑）；"
                 "流动性融资验证以 TED 利差(←2022)/SOFR−IORB(2023→) 接力。"
                 "仅供研究，非投资建议。"),
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

    # 关键节点 sanity 输出
    def at(dt):
        i = bisect_right(dates_out, dt) - 1
        return (dates_out[i], regime_out[i]) if i >= 0 else ("-", None)
    print("写入 %s：%d 点（%s → %s）" % (OUT_PATH, len(dates_out), dates_out[0], dates_out[-1]))
    for tag, dt in [("GFC低点", "2008-11-21"), ("COVID低点", "2020-03-23"),
                    ("2021顶部", "2021-08-31"), ("2022低点", "2022-10-12")]:
        print("  %s %s → regime %s" % (tag, *at(dt)))


if __name__ == "__main__":
    try:
        build()
    except Exception as e:
        print("history 构建失败（保留旧文件）：%r" % e)
