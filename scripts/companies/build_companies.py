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
sys.path.insert(0, HERE)
from maps import SECTOR_ZH, COUNTRY_ZH, COUNTRY_FLAG, ZH_OVERLAY, PRIVATE, LAST_ROUND, NAME_ZH_EXTRA, NAME_ZH_EXTRA_PRIV  # noqa: E402

OUT_PATH = os.path.join("apps", "companies", "data.json")
UNI_PATH = os.path.join(HERE, "universe.json")
LOGO_DIR = os.path.join("apps", "companies", "logos")
TOP_N = 500
YF_HOSTS = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
YF_HEADERS = {"User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                             "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"), "Accept": "application/json"}
FX_FALLBACK = {"USD": 1.0, "SAR": 0.26667, "KRW": 0.0006408}  # 本币→美元（取不到实时汇率时兜底）


def yf_chart(session, symbol):
    """取单只最新价与上一收盘；失败返回 None。"""
    sym = requests.utils.quote(symbol)
    for host in YF_HOSTS:
        try:
            r = session.get(f"https://{host}/v8/finance/chart/{sym}?range=5d&interval=1d", timeout=12)
            if r.status_code != 200:
                continue
            meta = (r.json().get("chart", {}).get("result") or [{}])[0].get("meta") or {}
            price = meta.get("regularMarketPrice")
            prev = meta.get("chartPreviousClose") or meta.get("previousClose")
            if isinstance(price, (int, float)) and price > 0:
                return price, (prev if isinstance(prev, (int, float)) and prev > 0 else None)
        except Exception:
            continue
    return None


def fx_to_usd(session):
    """本币→美元换算因子。SAR 与美元挂钩固定；KRW 取 Yahoo 实时汇率，失败兜底。"""
    fx = dict(FX_FALLBACK)
    res = yf_chart(session, "KRW=X")            # USD/KRW
    if res and res[0]:
        fx["KRW"] = 1.0 / res[0]
    return fx


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
    prev_rows = {r["symbol"]: r for r in (prev_data or {}).get("companies", [])
                 if r.get("symbol") and r.get("symbol") != "—"}

    def keep(msg):
        print(msg + ("（保留上次 data.json，不覆盖）" if prev_data else "（且无历史快照，跳过）"))

    universe = load_json(UNI_PATH)
    if not universe:
        keep("读不到 universe.json")
        return

    session = requests.Session()
    session.headers.update(YF_HEADERS)
    fx = fx_to_usd(session)
    print(f"汇率 KRW→USD={fx['KRW']:.6g}")

    listed, fresh = [], 0
    for u in universe:
        sym = u["symbol"]
        cur = u.get("cur", "USD")
        shares = u.get("shares")
        zh, dom = ZH_OVERLAY.get(sym, (None, None))
        cap_usd = price = chg = None
        priceCur = cur
        res = yf_chart(session, sym) if shares else None
        if res and shares:
            price, prev = res
            cap_usd = price * shares * fx.get(cur, 1.0)
            if prev:
                chg = round((price / prev - 1) * 100, 2)
            fresh += 1
        else:                                   # 回退上次已知值，避免掉榜/闪烁
            p = prev_rows.get(sym)
            if not p or not p.get("marketCap"):
                continue
            cap_usd = p["marketCap"] * 1e9
            price = p.get("price"); chg = p.get("changePct"); priceCur = p.get("priceCur", cur)
        listed.append({
            "name": zh or NAME_ZH_EXTRA.get(sym) or u["nameEn"], "nameEn": u["nameEn"], "symbol": sym,
            "marketCap": round(cap_usd / 1e9, 1),
            "price": round(price, 2) if isinstance(price, (int, float)) else None,
            "priceCur": priceCur, "changePct": chg,
            "country": COUNTRY_ZH.get(u["country"], u["country"]), "flag": COUNTRY_FLAG.get(u["country"], "🌐"),
            "sector": SECTOR_ZH.get(u["sector"], u["sector"]), "domain": dom, "logo": local_logo(dom, sym),
        })
        time.sleep(0.12)

    print(f"取到实时价 {fresh}/{len(universe)} 家")
    if fresh < 0.5 * len(universe):
        keep(f"有效报价过少（{fresh}），疑似被限流")
        return

    listed.sort(key=lambda r: r["marketCap"] or 0, reverse=True)
    if not listed or not (300 <= listed[0]["marketCap"] <= 20000):
        keep(f"体检未过：榜首市值 ${listed[0]['marketCap'] if listed else '—'}B")
        return

    private = sorted(PRIVATE, key=lambda p: p["marketCap"], reverse=True)
    rows = listed[:TOP_N - len(private)] + [{
        "name": NAME_ZH_EXTRA_PRIV.get(p["nameEn"]) or p["name"], "nameEn": p["nameEn"], "symbol": "—", "marketCap": p["marketCap"],
        "price": None, "priceCur": "USD", "changePct": None, "country": p["country"], "flag": p["flag"],
        "sector": p["sector"], "domain": p["domain"], "logo": local_logo(p["domain"], None),
        "lastRound": LAST_ROUND.get(p["nameEn"]), "private": True,
    } for p in private]
    for i, r in enumerate(rows, 1):
        r["rank"] = i

    n_listed = len(rows) - len(private)
    data = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asOf": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "source": "Yahoo Finance",
        "count": len(rows), "listedCount": n_listed, "privateCount": len(private),
        "totalMarketCap": round(sum(r["marketCap"] for r in rows), 1),
        "note": ("上市公司市值/股价/当日涨跌每日自动更新（来源 Yahoo Finance，本币市值按汇率折美元）；"
                 "末段为知名非上市公司（标「未上市」，最近一轮公开估值、非实时）。仅供参考，不构成投资建议。"),
        "companies": rows,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"写入 {OUT_PATH}：{len(rows)} 家（上市 {n_listed} + 非上市 {len(private)}），"
          f"榜首 {rows[0]['nameEn']} ${rows[0]['marketCap']}B，总市值 ${data['totalMarketCap'] / 1000:.2f}T")


if __name__ == "__main__":
    build()
