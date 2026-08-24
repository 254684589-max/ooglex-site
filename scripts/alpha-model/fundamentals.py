#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""B 层：基本面、估值、盈利修正的取数与派生。

数据源 Yahoo quoteSummary。与 v8/chart 不同，这个接口需要 cookie + crumb 握手，
握手失败或字段缺失时**整族留空**，总分按 A 层权重重新归一化——
绝不用中位数把「不知道」伪装成「中性」。

**关键限制，必须和结论一起读**：quoteSummary 只给"此刻"的快照，
没有 point-in-time 历史。它给不出「2020-03-16 那天市场看到的 TTM 净利润」——
那天的报表可能后来被重述，分析师预测更是没有留档。所以 B 层：
  · 可以用于**今天的横截面打分**；
  · **不能进回测**。用今天的财报回测三年前是未来函数，回测必然虚高。
真正的 PIT 财务要走 SEC EDGAR XBRL（companyfacts 带 filed 日期），属 V2。

解析与取数刻意分开：``extract_metrics`` 是纯函数，可以离线拿固定样本断言，
不依赖网络。
"""

import json
import os
import time

import requests

from config import (
    FUNDAMENTAL_CACHE_TTL_HOURS,
    HTTP_TIMEOUT,
    YF_COOKIE_URLS,
    YF_CRUMB_URL,
    YF_HEADERS,
    YF_QUOTE_MODULES,
)

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(HERE, "cache", "fundamentals")

# 用于诊断：每个族需要哪些原始字段才算"有数据"
REQUIRED_FIELDS = {
    "fundamental": ("revenueGrowth", "earningsGrowth", "operatingMargins",
                    "grossMargins", "returnOnEquity", "freeCashflow", "totalRevenue"),
    "valuation": ("forwardPE", "enterpriseToEbitda", "enterpriseToRevenue", "marketCap"),
    "revision": ("epsTrend", "epsRevisions", "targetMeanPrice"),
}


# ---------------------------------------------------------------------------
# 取数
# ---------------------------------------------------------------------------
def get_crumb(session):
    """cookie + crumb 握手。失败返回 None，调用方据此整体跳过 B 层。"""
    for url in YF_COOKIE_URLS:
        try:
            session.get(url, timeout=HTTP_TIMEOUT, allow_redirects=True)
        except Exception:
            continue                      # fc.yahoo.com 常返回 404，但 cookie 已种下
    try:
        response = session.get(YF_CRUMB_URL, timeout=HTTP_TIMEOUT)
        crumb = (response.text or "").strip()
        # 正常 crumb 是十来个字符的短串；返回 HTML 说明握手没成
        if response.status_code == 200 and 0 < len(crumb) < 64 and "<" not in crumb:
            return crumb
    except Exception:
        pass
    return None


def _cache_path(symbol):
    safe = symbol.replace("/", "_").replace("\\", "_")
    return os.path.join(CACHE_DIR, f"{safe}.json")


def _read_cache(symbol, ttl_hours):
    try:
        with open(_cache_path(symbol), encoding="utf-8") as f:
            payload = json.load(f)
    except Exception:
        return None
    if (time.time() - payload.get("fetchedAt", 0)) > ttl_hours * 3600:
        return None
    return payload.get("result")


def _write_cache(symbol, result):
    os.makedirs(CACHE_DIR, exist_ok=True)
    path = _cache_path(symbol)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"fetchedAt": time.time(), "symbol": symbol, "result": result}, f)
    os.replace(tmp, path)


def fetch_quote_summary(session, symbol, crumb, use_cache=True,
                        ttl_hours=FUNDAMENTAL_CACHE_TTL_HOURS):
    """取单只的 quoteSummary 原始结果；失败返回 None。"""
    if use_cache:
        cached = _read_cache(symbol, ttl_hours)
        if cached:
            return cached

    quoted = requests.utils.quote(symbol)
    modules = ",".join(YF_QUOTE_MODULES)
    for host in ("query2.finance.yahoo.com", "query1.finance.yahoo.com"):
        url = (f"https://{host}/v10/finance/quoteSummary/{quoted}"
               f"?modules={modules}&formatted=false")
        if crumb:
            url += f"&crumb={requests.utils.quote(crumb)}"
        try:
            response = session.get(url, timeout=HTTP_TIMEOUT)
            if response.status_code != 200:
                continue
            result = ((response.json().get("quoteSummary") or {}).get("result") or [None])[0]
            if result:
                if use_cache:
                    _write_cache(symbol, result)
                return result
        except Exception:
            continue
    return None


# ---------------------------------------------------------------------------
# 解析（纯函数，可离线断言）
# ---------------------------------------------------------------------------
def _num(value):
    """取数值。Yahoo 在 formatted=true 时把值包成 {"raw": x, "fmt": "..."}，两种都吃。"""
    if isinstance(value, dict):
        value = value.get("raw")
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if value != value or value in (float("inf"), float("-inf")):   # NaN / inf
        return None
    return float(value)


def _safe_div(numerator, denominator, min_denominator=1e-9):
    if numerator is None or denominator is None:
        return None
    if abs(denominator) < min_denominator:
        return None
    return numerator / denominator


def _inverse(value, floor=1e-6):
    """把「倍数」翻成「收益率」：市盈率 → 盈利收益率。

    负值保留符号且不取绝对值：亏损公司的盈利收益率为负，亏得越狠（PE 绝对值越小）
    越负，排序方向正确。接近 0 的倍数会炸出极端值，交给去极值处理。
    """
    if value is None or abs(value) < floor:
        return None
    return 1.0 / value


def _pick_trend(earnings_trend, period="+1y"):
    for item in (earnings_trend or {}).get("trend") or []:
        if item.get("period") == period:
            return item
    return None


def _revision_rate(eps_trend, key):
    """一致预期相对若干天前的变化率。

    分母取绝对值：预期为负（亏损）时，从 −1.0 上修到 −0.5 是**改善**，
    用带符号分母会把它算成 −50%，方向正好反了。
    """
    current = _num((eps_trend or {}).get("current"))
    past = _num((eps_trend or {}).get(key))
    if current is None or past is None or abs(past) < 0.01:
        return None
    return (current - past) / abs(past)


def extract_metrics(result):
    """把 quoteSummary 原始结果解析成 B 层子因子的原始值。

    返回 (子因子字典, 诊断字典)。取不到的子因子为 None，不填默认值。
    """
    result = result or {}
    fin = result.get("financialData") or {}
    stats = result.get("defaultKeyStatistics") or {}
    summary = result.get("summaryDetail") or {}
    price = result.get("price") or {}
    trend = _pick_trend(result.get("earningsTrend"))

    revenue = _num(fin.get("totalRevenue"))
    fcf = _num(fin.get("freeCashflow"))
    ebitda = _num(fin.get("ebitda"))
    debt = _num(fin.get("totalDebt"))
    cash = _num(fin.get("totalCash"))
    market_cap = _num(price.get("marketCap")) or _num(summary.get("marketCap"))
    current_price = _num(fin.get("currentPrice")) or _num(price.get("regularMarketPrice"))

    net_debt = None
    if debt is not None:
        net_debt = debt - (cash or 0.0)
    leverage = _safe_div(net_debt, ebitda) if (ebitda or 0) > 0 else None

    eps_trend = (trend or {}).get("epsTrend")
    revisions = (trend or {}).get("epsRevisions") or {}
    analysts = (_num((trend or {}).get("earningsEstimate", {}).get("numberOfAnalysts"))
                or _num(fin.get("numberOfAnalystOpinions")))
    up30 = _num(revisions.get("upLast30days"))
    down30 = _num(revisions.get("downLast30days"))
    breadth = None
    if up30 is not None and down30 is not None and analysts and analysts >= 3:
        breadth = (up30 - down30) / analysts

    target = _num(fin.get("targetMeanPrice"))
    upside = None
    if target is not None and current_price and current_price > 0:
        upside = target / current_price - 1.0

    metrics = {
        # 基本面
        "revenue_growth": _num(fin.get("revenueGrowth")),
        "earnings_growth": _num(fin.get("earningsGrowth")),
        "operating_margin": _num(fin.get("operatingMargins")),
        "gross_margin": _num(fin.get("grossMargins")),
        "roe": _num(fin.get("returnOnEquity")),
        "fcf_margin": _safe_div(fcf, revenue) if (revenue or 0) > 0 else None,
        "low_leverage": None if leverage is None else -leverage,
        # 估值：一律翻成"收益率"口径，使高分 = 便宜，方向与其他因子一致
        "earnings_yield": _inverse(_num(stats.get("forwardPE"))
                                   or _num(summary.get("forwardPE"))),
        "ev_ebitda_yield": _inverse(_num(stats.get("enterpriseToEbitda"))),
        "ev_sales_yield": _inverse(_num(stats.get("enterpriseToRevenue"))),
        "fcf_yield": _safe_div(fcf, market_cap) if (market_cap or 0) > 0 else None,
        # 盈利修正
        "eps_revision_90d": _revision_rate(eps_trend, "90daysAgo"),
        "eps_revision_30d": _revision_rate(eps_trend, "30daysAgo"),
        "revision_breadth": breadth,
        "target_upside": upside,
    }

    diagnostics = {
        "hasFinancialData": bool(fin),
        "hasKeyStatistics": bool(stats),
        "hasEarningsTrend": trend is not None,
        "analysts": analysts,
        "present": sorted(k for k, v in metrics.items() if v is not None),
        "missing": sorted(k for k, v in metrics.items() if v is None),
    }
    return metrics, diagnostics


# ---------------------------------------------------------------------------
def load_fundamentals(session, symbols, verbose=True, use_cache=True):
    """批量取 B 层原始值。返回 ({代码: 子因子字典}, 汇总信息)。

    握手失败时直接返回空——让整个 B 层显式缺失，而不是逐只静默失败后
    留下一批半残的分数。
    """
    crumb = get_crumb(session)
    if not crumb:
        return {}, {
            "ok": False,
            "reason": "cookie/crumb 握手失败，quoteSummary 不可用；B层整体跳过",
            "requested": len(symbols), "fetched": 0,
        }

    out, failures, field_counts = {}, [], {}
    for i, symbol in enumerate(symbols, start=1):
        result = fetch_quote_summary(session, symbol, crumb, use_cache=use_cache)
        if not result:
            failures.append(symbol)
            continue
        metrics, diag = extract_metrics(result)
        if not diag["present"]:
            failures.append(symbol)
            continue
        out[symbol] = metrics
        for key in diag["present"]:
            field_counts[key] = field_counts.get(key, 0) + 1
        if verbose and i % 50 == 0:
            print(f"  基本面已取 {i}/{len(symbols)}", flush=True)

    coverage = {k: round(v / max(1, len(out)), 3) for k, v in sorted(field_counts.items())}
    return out, {
        "ok": bool(out),
        "requested": len(symbols),
        "fetched": len(out),
        "failed": len(failures),
        "failedSamples": failures[:12],
        "fieldCoverage": coverage,
        "note": ("quoteSummary 为当前快照，无 point-in-time 历史；"
                 "仅用于当日打分，不参与回测"),
    }


def diagnose(symbols):
    """命令行诊断：逐只打印哪些字段拿到了、哪些没拿到。

    ``python3 scripts/alpha-model/fundamentals.py NVDA MSFT CSX``
    """
    from prices import new_session
    session = new_session()
    crumb = get_crumb(session)
    print(f"crumb 握手：{'成功 ' + crumb if crumb else '失败——B层将整体跳过'}\n")
    if not crumb:
        print("说明：Yahoo 的 quoteSummary 需要 cookie+crumb，行情接口 v8/chart 不需要。")
        print("握手失败通常是网络策略拦截或 Yahoo 改了握手方式；A 层不受影响。")
        return 1

    for symbol in symbols:
        result = fetch_quote_summary(session, symbol, crumb, use_cache=False)
        if not result:
            print(f"{symbol:<8} 取数失败")
            continue
        metrics, diag = extract_metrics(result)
        print(f"{symbol:<8} 拿到 {len(diag['present'])}/{len(metrics)} 个字段"
              f"（分析师 {diag['analysts']}）")
        for key, value in metrics.items():
            shown = "—" if value is None else f"{value:+.4f}"
            print(f"           {key:<20} {shown}")
        print()
    return 0


if __name__ == "__main__":
    import sys
    raise SystemExit(diagnose([s.upper() for s in sys.argv[1:]] or ["NVDA", "CSX"]))
