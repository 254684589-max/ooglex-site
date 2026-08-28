#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「全球公司市值榜（前 500）」数据 → apps/companies/data.json。

数据源 Yahoo Finance（免密钥，与本仓库 asset-tracker 同款 v8/chart 接口，机房可达）：
- 上市公司清单（约 560 家：标普 500 成分 + 海外巨头 ADR + 三星/沙特阿美等）烘焙在 universe.json，
  每条带 shares（流通股数）与 cur（计价币种）；
- 本脚本逐只取最新价，按「价 × 股数」算市值（本币市值再按汇率折美元），算当日涨跌；
- 末段并入若干知名非上市公司（maps.PRIVATE，最近公开估值、非实时），按美元市值排前 500：
  上市公司在前、非上市公司殿后，共 500 家。

稳健性：
- 逐只独立容错、主备双域名、硬超时；某只当日取不到时回退沿用上次 data.json 的已知值，不掉榜；
- 有效报价过少（疑似被限流）或榜首市值离谱时，保留上次 data.json 不覆盖，绝不用空/脏数据洗掉好数据。
由 .github/workflows/companies.yml 每日运行并提交回仓库。
"""
import json
import os
import sys
import time
from datetime import datetime, timezone

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS_DIR = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, SCRIPTS_DIR)
from maps import SECTOR_ZH, COUNTRY_ZH, COUNTRY_FLAG, ZH_OVERLAY, PRIVATE, LAST_ROUND, NAME_ZH_EXTRA, NAME_ZH_EXTRA_PRIV  # noqa: E402
from market_data_quality import (  # noqa: E402
    fallback_data_meta,
    make_data_meta,
    summarize_data_quality,
)
from market_history import build_rolling_history
from market_history_long import build_long_history, monthly_from_daily  # noqa: E402
from market_source_health import (  # noqa: E402
    load_json as load_health_json,
    make_source_health,
    write_health,
)

OUT_PATH = os.path.join("apps", "companies", "data.json")
HEALTH_PATH = os.path.join("apps", "companies", "health.json")
HISTORY_PATH = os.path.join("apps", "companies", "history.json")
LONG_HISTORY_PATH = os.path.join("apps", "companies", "history-monthly.json")
LONG_HISTORY_NOTE = ("市值前列上市公司自身的月线收盘，用于 5 年 / 10 年 / 25 年 / 全部区间的走势；"
                     "起始月即该公司在数据源上可得的最早月份。数据源对超长区间会自行降采样，"
                     "部分公司的早年只有季度末观测，缺月一律留空不做前向填充，"
                     "页面按真实时间轴作图；本轮未取到的公司沿用上次序列。")
HISTORY_SYMBOLS = 40     # 只给市值最高的一段存日线：金融终端品类行情板按这份历史画走势
HISTORY_POINTS = 260     # 滚动保留约一年交易日，文件大小恒定而非逐日增长
HISTORY_NOTE = ("市值前列上市公司自身收盘价的滚动历史，与 data.json 同一次取数、同一来源；"
                "共享日期轴上该标的当日无收盘则为 null，不做前向填充。"
                "本轮未取到的标的沿用上次序列，不补造新点。")
UNI_PATH = os.path.join(HERE, "universe.json")
LOGO_DIR = os.path.join("apps", "companies", "logos")
TOP_N = 500
YF_HOSTS = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
YF_HEADERS = {"User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                             "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"), "Accept": "application/json"}
FX_FALLBACK = {"USD": 1.0, "SAR": 0.26667, "KRW": 0.0006408}  # 本币→美元（取不到实时汇率时兜底）


def yf_chart(session, symbol):
    """取单只最新价、上一收盘与行情时点；缺少时点也视为失败。"""
    sym = requests.utils.quote(symbol)
    for host in YF_HOSTS:
        try:
            r = session.get(f"https://{host}/v8/finance/chart/{sym}?range=5d&interval=1d", timeout=12)
            if r.status_code != 200:
                continue
            meta = (r.json().get("chart", {}).get("result") or [{}])[0].get("meta") or {}
            price = meta.get("regularMarketPrice")
            prev = meta.get("chartPreviousClose") or meta.get("previousClose")
            market_time = meta.get("regularMarketTime")
            if isinstance(price, (int, float)) and price > 0 \
                    and isinstance(market_time, (int, float)) and market_time > 0:
                as_of = datetime.fromtimestamp(market_time, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                return price, (prev if isinstance(prev, (int, float)) and prev > 0 else None), as_of
        except Exception:
            continue
    return None


def yf_daily_closes(session, symbol, rng="1y"):
    """取单只日线收盘序列 [(YYYY-MM-DD, close), ...]；任何异常都返回空列表。"""
    sym = requests.utils.quote(symbol)
    for host in YF_HOSTS:
        try:
            r = session.get(
                f"https://{host}/v8/finance/chart/{sym}?range={rng}&interval=1d", timeout=12)
            if r.status_code != 200:
                continue
            res = (r.json().get("chart", {}).get("result") or [{}])[0]
            stamps = res.get("timestamp") or []
            quote = (res.get("indicators", {}).get("quote") or [{}])[0]
            closes = quote.get("close") or []
            points = [(datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%d"), float(c))
                      for t, c in zip(stamps, closes)
                      if isinstance(t, (int, float)) and isinstance(c, (int, float))]
            if len(points) >= 2:
                return points
        except Exception:
            continue
    return []


def yf_monthly_closes(session, symbol, rng="max"):
    """取单只月线收盘序列 [(YYYY-MM, close), ...]；任何异常都返回空列表。"""
    sym = requests.utils.quote(symbol)
    for host in YF_HOSTS:
        try:
            r = session.get(
                f"https://{host}/v8/finance/chart/{sym}?range={rng}&interval=1mo", timeout=15)
            if r.status_code != 200:
                continue
            res = (r.json().get("chart", {}).get("result") or [{}])[0]
            stamps = res.get("timestamp") or []
            quote = (res.get("indicators", {}).get("quote") or [{}])[0]
            closes = quote.get("close") or []
            points = [(datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m"), float(c))
                      for t, c in zip(stamps, closes)
                      if isinstance(t, (int, float)) and isinstance(c, (int, float))]
            if len(points) >= 2:
                return points
        except Exception:
            continue
    return []


def write_long_history(session, symbols, daily, run_updated_at):
    """再补一份月线长历史；失败只跳过，不影响 data.json 与日线历史。"""
    collected = {}
    for sym in symbols:
        # 数据源对超长区间会自行降采样，再取一次最近十年把近端补稠密。
        merged = dict(yf_monthly_closes(session, sym))
        merged.update(dict(yf_monthly_closes(session, sym, "10y")))
        points = sorted(merged.items())
        if len(points) < 2:
            points = monthly_from_daily(daily.get(sym) or [])
        if len(points) >= 2:
            collected[sym] = points
        time.sleep(0.12)
    history, retained = build_long_history(
        collected, load_json(LONG_HISTORY_PATH), run_updated_at,
        source="Yahoo Finance", note=LONG_HISTORY_NOTE)
    if not history:
        print("月线序列本轮全部失败，保留上次 history-monthly.json（不写空数据）")
        return None
    with open(LONG_HISTORY_PATH, "w", encoding="utf-8") as f:
        json.dump(history, f, ensure_ascii=False, separators=(",", ":"))
    print(f"月线历史：{len(collected)}/{len(symbols)} 只本轮取到，"
          f"{len(retained)} 只沿用上次，最新月 {history['asOf']}")
    return history


def write_history(session, rows, run_updated_at):
    """给市值前列的上市公司补一份滚动日线历史；失败只跳过，绝不影响已写好的 data.json。"""
    symbols = [r["symbol"] for r in rows
               if not r.get("private") and r.get("symbol") and r["symbol"] != "—"][:HISTORY_SYMBOLS]
    collected = {}
    for sym in symbols:
        points = yf_daily_closes(session, sym)
        if points:
            collected[sym] = points
        time.sleep(0.12)
    history, retained = build_rolling_history(
        collected, load_json(HISTORY_PATH), run_updated_at,
        source="Yahoo Finance", note=HISTORY_NOTE, limit=HISTORY_POINTS)
    if not history:
        print("日线序列本轮全部失败，保留上次 history.json（不写空数据）")
        return None
    history["symbols"] = symbols
    with open(HISTORY_PATH, "w", encoding="utf-8") as f:
        json.dump(history, f, ensure_ascii=False, separators=(",", ":"))
    print(f"日线历史：{len(collected)}/{len(symbols)} 只本轮取到，"
          f"{len(retained)} 只沿用上次，共 {history['points']} 个交易日")
    write_long_history(session, symbols, collected, run_updated_at)
    return history


def fx_to_usd(session):
    """本币→美元换算因子，并返回KRW是否使用静态兜底。"""
    fx = dict(FX_FALLBACK)
    res = yf_chart(session, "KRW=X")            # USD/KRW
    if res and res[0]:
        fx["KRW"] = 1.0 / res[0]
        return fx, False
    return fx, True


def last_round_as_of(value):
    """把 ``May 2026`` 规范成月初日期；仅代表月份精度。"""
    if not value:
        return None
    try:
        return datetime.strptime(value, "%b %Y").strftime("%Y-%m-01")
    except (TypeError, ValueError):
        return None


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def local_logo(domain, symbol):
    """命中本地已下载的 logo 则返回同源相对路径（墙内也快），否则 None（前端回退境外图床/字母牌）。"""
    keys = ([domain] if domain else []) + (["sym_" + symbol] if symbol and symbol != "—" else [])
    for key in keys:
        name = key.replace("/", "_") + ".png"
        f = os.path.join(LOGO_DIR, name)
        if os.path.exists(f) and os.path.getsize(f) > 200:
            return "logos/" + name
    return None


def build():
    prev_data = load_json(OUT_PATH)
    prev_health = load_health_json(HEALTH_PATH)
    prev_rows = {r["symbol"]: r for r in (prev_data or {}).get("companies", [])
                 if r.get("symbol") and r.get("symbol") != "—"}
    run_updated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    def keep(msg, attempted_rows=None):
        health = make_source_health(
            "companies",
            published_rows=(prev_data or {}).get("companies", []),
            attempted_rows=attempted_rows or [],
            attempted_at=run_updated_at,
            published_snapshot_at=(prev_data or {}).get("updatedAt"),
            published=False,
            previous_health=prev_health,
            failure_reason=msg + "；本轮未发布新快照。",
        )
        write_health(HEALTH_PATH, health)
        print(msg + ("（保留上次 data.json，不覆盖）" if prev_data else "（且无历史快照，跳过）"))

    universe = load_json(UNI_PATH)
    if not universe:
        keep("读不到 universe.json")
        return

    session = requests.Session()
    session.headers.update(YF_HEADERS)
    fx, krw_fx_fallback = fx_to_usd(session)
    print(f"汇率 KRW→USD={fx['KRW']:.6g}" + ("（静态兜底）" if krw_fx_fallback else ""))

    listed, fresh, fresh_as_of = [], 0, []
    for u in universe:
        sym = u["symbol"]
        cur = u.get("cur", "USD")
        shares = u.get("shares")
        zh, dom = ZH_OVERLAY.get(sym, (None, None))
        cap_usd = price = chg = None
        priceCur = cur
        res = yf_chart(session, sym) if shares else None
        if res and shares:
            price, prev, quote_as_of = res
            cap_usd = price * shares * fx.get(cur, 1.0)
            if prev:
                chg = round((price / prev - 1) * 100, 2)
            fresh += 1
            fresh_as_of.append(quote_as_of)
            if cur == "KRW" and krw_fx_fallback:
                row_meta = make_data_meta(
                    "fallback",
                    "Yahoo Finance",
                    as_of=quote_as_of,
                    updated_at=run_updated_at,
                    frequency="daily",
                    status="partial",
                    note="股价本轮更新，但KRW兑美元换算使用静态兜底汇率。",
                )
                stale = True
            else:
                row_meta = make_data_meta(
                    "market",
                    "Yahoo Finance",
                    as_of=quote_as_of,
                    updated_at=run_updated_at,
                    frequency="daily",
                )
                stale = False
        else:                                   # 回退上次已知值，避免掉榜/闪烁
            p = prev_rows.get(sym)
            if not p or not p.get("marketCap"):
                continue
            cap_usd = p["marketCap"] * 1e9
            price = p.get("price"); chg = p.get("changePct"); priceCur = p.get("priceCur", cur)
            row_meta = fallback_data_meta(
                p,
                source="Yahoo Finance",
                frequency="daily",
                legacy_updated_at=(prev_data or {}).get("updatedAt"),
            )
            stale = True
        listed.append({
            "name": zh or NAME_ZH_EXTRA.get(sym) or u["nameEn"], "nameEn": u["nameEn"], "symbol": sym,
            "marketCap": round(cap_usd / 1e9, 1),
            "price": round(price, 2) if isinstance(price, (int, float)) else None,
            "priceCur": priceCur, "changePct": chg,
            "country": COUNTRY_ZH.get(u["country"], u["country"]), "flag": COUNTRY_FLAG.get(u["country"], "🌐"),
            "sector": SECTOR_ZH.get(u["sector"], u["sector"]), "domain": dom, "logo": local_logo(dom, sym),
            "stale": stale, "dataMeta": row_meta,
        })
        time.sleep(0.12)

    print(f"取到实时价 {fresh}/{len(universe)} 家")
    if fresh < 0.5 * len(universe):
        keep(f"有效报价过少（{fresh}/{len(universe)}），未达到50%发布门槛", listed)
        return

    listed.sort(key=lambda r: r["marketCap"] or 0, reverse=True)
    if not listed or not (300 <= listed[0]["marketCap"] <= 20000):
        keep(f"体检未过：榜首市值 ${listed[0]['marketCap'] if listed else '—'}B", listed)
        return

    private = sorted(PRIVATE, key=lambda p: p["marketCap"], reverse=True)
    private_rows = []
    for p in private:
        last_round = LAST_ROUND.get(p["nameEn"])
        estimate_as_of = last_round_as_of(last_round)
        private_rows.append({
            "name": NAME_ZH_EXTRA_PRIV.get(p["nameEn"]) or p["name"], "nameEn": p["nameEn"],
            "symbol": "—", "marketCap": p["marketCap"], "price": None, "priceCur": "USD", "changePct": None,
            "country": p["country"], "flag": p["flag"], "sector": p["sector"], "domain": p["domain"],
            "logo": local_logo(p["domain"], None), "lastRound": last_round, "private": True, "stale": False,
            "dataMeta": make_data_meta(
                "estimate",
                "multiples.vc（公开融资估值汇总）",
                as_of=estimate_as_of,
                updated_at=run_updated_at,
                frequency="irregular",
                status="ok" if estimate_as_of else "partial",
                note="最近一轮公开估值，非交易行情。" if estimate_as_of else "未记录可核验的最近融资月份。",
            ),
        })
    rows = listed[:TOP_N - len(private_rows)] + private_rows
    for i, r in enumerate(rows, 1):
        r["rank"] = i

    n_listed = len(rows) - len(private_rows)
    data_quality = summarize_data_quality(rows)
    data = {
        "updatedAt": run_updated_at,
        "asOf": max(fresh_as_of)[:10],
        "frequency": "daily",
        "status": data_quality["status"],
        "source": "Yahoo Finance",
        "count": len(rows), "listedCount": n_listed, "privateCount": len(private_rows),
        "totalMarketCap": round(sum(r["marketCap"] for r in rows), 1),
        "note": ("上市公司市值/股价/当日涨跌每日自动更新（来源 Yahoo Finance，本币市值按汇率折美元）；"
                 "末段为知名非上市公司（标「未上市」，最近一轮公开估值、非实时）。仅供参考，不构成投资建议。"),
        "companies": rows,
        "dataQuality": data_quality,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    health = make_source_health(
        "companies",
        published_rows=rows,
        attempted_rows=rows,
        attempted_at=run_updated_at,
        published_snapshot_at=run_updated_at,
        published=True,
        previous_health=prev_health,
    )
    write_health(HEALTH_PATH, health)
    print(f"写入 {OUT_PATH}：{len(rows)} 家（上市 {n_listed} + 非上市 {len(private_rows)}），"
          f"榜首 {rows[0]['nameEn']} ${rows[0]['marketCap']}B，总市值 ${data['totalMarketCap'] / 1000:.2f}T")

    # 历史序列是附加产物：放在主快照之后，任何失败都只跳过它，不影响已经写好的 data.json
    try:
        write_history(session, rows, run_updated_at)
    except Exception as error:                       # noqa: BLE001 - 附加产物不得拖垮主管道
        print(f"日线历史构建异常：{error}；保留上次 history.json")


if __name__ == "__main__":
    build()
