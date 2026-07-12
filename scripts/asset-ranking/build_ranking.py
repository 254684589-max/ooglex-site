#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「全球资产市值排行榜（前 250，不限品类）」→ apps/asset-ranking/data.json。

一张榜把所有大类资产按美元市值横向拉通排名：房地产、政府债券、煤炭、石油、天然气、
铁矿石、铝、铜、黄金、白银、各国货币（广义货币 M2）、上市公司、加密货币……只看市值。

方法论（与 assetmarketcap / 8marketcap 同款，可每日实时更新）：
    市值 = 数量(储量/地面存量/M2) × 单位价格(实时行情/汇率)
  · 商品/贵金属：储量或地面存量 × Yahoo 期货/现货价（每日随行情浮动）
  · 货币：广义货币 M2/M3 × 实时汇率
  · 公司：直接复用每日刷新的 apps/companies/data.json（Yahoo Finance）
  · 加密货币：CoinGecko 实时市值（兜底 Yahoo 现价 × 流通量）
  · 房地产/政府债务/煤炭/天然气：权威机构存量估值（慢变量，静态基准）

稳健性（沿用本仓库取数风格）：
  · 纯 requests + 硬超时、逐项 try/except、主备双域名，单点失败不影响整体；
  · 某项实时价取不到时回退：上次 data.json 的值(stale) → 静态基准，绝不掉榜/闪烁；
  · 体检（榜首量级、条目数）不过则保留上次 data.json，不用空/脏数据覆盖好数据。
由 .github/workflows/asset_ranking.yml 每日运行并提交回仓库。
"""
import json
import os
import sys
import time
from datetime import datetime, timezone

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from baselines import CATEGORIES, AGGREGATES, CRYPTO  # noqa: E402

OUT_PATH = os.path.join("apps", "asset-ranking", "data.json")
COMPANIES_PATH = os.path.join("apps", "companies", "data.json")
TOP_N = 250
YF_HOSTS = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
YF_HEADERS = {"User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                             "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"), "Accept": "application/json"}
CG_URL = ("https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc"
          "&per_page=50&page=1&price_change_percentage=24h")


# ————————————————————— 取数工具 —————————————————————
def yf_price(session, symbol):
    """取单个 Yahoo 代码的最新价与上一收盘；失败返回 None。"""
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
                return float(price), (float(prev) if isinstance(prev, (int, float)) and prev > 0 else None)
        except Exception:
            continue
    return None


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def pct(cur, base):
    if not base:
        return None
    return round((cur / base - 1.0) * 100, 2)


# ————————————————————— 各品类构建 —————————————————————
def build_aggregates(session, prev_rows):
    """房地产 / 大宗商品 / 贵金属 / 货币 / 债券：数量 × 实时价（或静态基准）。"""
    out = []
    for a in AGGREGATES:
        row = {"name": a["name"], "nameEn": a["nameEn"], "category": a["cat"], "emoji": a["emoji"],
               "unit": a.get("unit"), "qty": a.get("qty"), "note": a.get("note")}
        cap_b = price_disp = change = None
        stale = False

        if a.get("symbol"):                         # 有实时代码：数量 × 实时单价
            res = yf_price(session, a["symbol"])
            if res:
                raw, raw_prev = res
                if a["cat"] == "currency":          # 汇率 → 本币兑美元单价（invert 时取倒数）
                    unit_usd = (1.0 / raw) if a.get("invert") else raw
                    prev_usd = (1.0 / raw_prev) if (a.get("invert") and raw_prev) else raw_prev
                    price_disp = round(unit_usd, 6)
                    change = pct(unit_usd, prev_usd)
                    cap_b = a["qty"] * unit_usd / 1e9
                else:                               # 商品/贵金属：储量/存量 × 现货价
                    price_disp = round(raw, 4)
                    change = pct(raw, raw_prev)
                    cap_b = a["qty"] * raw / 1e9
            else:                                   # 实时价取不到 → 沿用上次(stale) → 静态基准
                p = prev_rows.get(a["name"])
                if p and p.get("marketCap"):
                    cap_b = p["marketCap"]; price_disp = p.get("price"); change = p.get("changePct"); stale = True
                else:
                    price_disp = a.get("basePrice")
                    cap_b = (a["qty"] * a["basePrice"] / 1e9) if (a.get("qty") and a.get("basePrice")) else a.get("baseCap")
        elif a.get("baseCap") is not None:          # 纯静态基准（房地产/政府债/天然气）
            cap_b = a["baseCap"]
        elif a.get("qty") and a.get("basePrice"):   # 静态：储量 × 固定基准价（煤炭/铁矿石/美元 M2）
            price_disp = a["basePrice"]; cap_b = a["qty"] * a["basePrice"] / 1e9

        if not cap_b:
            continue
        row.update({"marketCap": round(cap_b, 1), "price": price_disp, "changePct": change,
                    "static": a.get("symbol") is None, "stale": stale})
        out.append(row)
    return out


def build_crypto(session, prev_rows):
    """加密货币：优先 CoinGecko 实时市值；兜底 Yahoo 现价 × 流通量；再兜底基准。"""
    out = []
    cg = {}
    try:
        r = session.get(CG_URL, timeout=15)
        if r.status_code == 200:
            for c in r.json():
                if isinstance(c, dict) and c.get("id"):
                    cg[c["id"]] = c
    except Exception:
        cg = {}
    if cg:
        print(f"CoinGecko 实时市值：{len(cg)} 币")

    for c in CRYPTO:
        row = {"name": c["name"], "nameEn": c["nameEn"], "category": "crypto", "emoji": "₿",
               "symbol": c["symbol"]}
        cap_b = price_disp = change = None
        m = cg.get(c["id"])
        if m and m.get("market_cap"):
            cap_b = m["market_cap"] / 1e9
            price_disp = m.get("current_price")
            change = round(m["price_change_percentage_24h"], 2) if isinstance(
                m.get("price_change_percentage_24h"), (int, float)) else None
        elif c.get("yf") and c.get("supply"):        # Yahoo 现价 × 流通量
            res = yf_price(session, c["yf"])
            if res:
                raw, raw_prev = res
                cap_b = raw * c["supply"] / 1e9; price_disp = raw; change = pct(raw, raw_prev)
        if cap_b is None:                            # 沿用上次 → 基准
            p = prev_rows.get(c["name"])
            if p and p.get("marketCap"):
                cap_b = p["marketCap"]; price_disp = p.get("price"); change = p.get("changePct"); row["stale"] = True
            else:
                cap_b = c["baseCap"]
        row.update({"marketCap": round(cap_b, 1), "price": price_disp, "changePct": change})
        out.append(row)
    return out


def build_companies():
    """直接复用每日刷新的 apps/companies/data.json（Yahoo Finance）。"""
    d = load_json(COMPANIES_PATH)
    if not d or not d.get("companies"):
        print("读不到 apps/companies/data.json，本轮不含公司条目")
        return []
    out = []
    for c in d["companies"]:
        if not c.get("marketCap"):
            continue
        out.append({
            "name": c["name"], "nameEn": c.get("nameEn"), "category": "company",
            "marketCap": c["marketCap"], "price": c.get("price"), "priceCur": c.get("priceCur"),
            "changePct": c.get("changePct"), "country": c.get("country"), "flag": c.get("flag"),
            "sector": c.get("sector"), "symbol": c.get("symbol"),
            # 公司 logo 存放在 apps/companies/logos/，本页用相对上级路径引用，无需复制文件
            "logo": ("../companies/" + c["logo"]) if c.get("logo") else None,
            "private": c.get("private"), "lastRound": c.get("lastRound"),
        })
    print(f"复用公司榜 {len(out)} 家")
    return out


# ————————————————————— 主流程 —————————————————————
def build():
    prev_data = load_json(OUT_PATH)
    prev_rows = {r["name"]: r for r in (prev_data or {}).get("assets", []) if r.get("name")}

    def keep(msg):
        print(msg + ("（保留上次 data.json，不覆盖）" if prev_data else "（且无历史快照，跳过）"))

    session = requests.Session()
    session.headers.update(YF_HEADERS)

    aggregates = build_aggregates(session, prev_rows)
    crypto = build_crypto(session, prev_rows)
    companies = build_companies()

    assets = aggregates + crypto + companies
    assets = [a for a in assets if a.get("marketCap")]
    assets.sort(key=lambda r: r["marketCap"] or 0, reverse=True)
    assets = assets[:TOP_N]
    for i, r in enumerate(assets, 1):
        r["rank"] = i

    # —— 体检：条目足够、榜首量级合理（房地产/债券在 5 万亿~200 万亿美元区间）——
    if len(assets) < 100 or not assets:
        keep(f"条目过少（{len(assets)}）"); return
    top_cap_t = assets[0]["marketCap"] / 1000
    if not (50 <= top_cap_t <= 2000):
        keep(f"体检未过：榜首市值 ${top_cap_t:.1f}T"); return

    cat_count = {}
    for r in assets:
        cat_count[r["category"]] = cat_count.get(r["category"], 0) + 1

    data = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asOf": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "source": "Yahoo Finance · CoinGecko · 公开估算（世界黄金协会 / IMF / Savills 等）",
        "count": len(assets),
        "totalMarketCap": round(sum(r["marketCap"] for r in assets), 1),
        "categories": CATEGORIES,
        "categoryCount": cat_count,
        "note": ("全球资产不限品类按市值排名（前 250）。商品/贵金属以储量或地面存量×实时行情、"
                 "货币以广义货币 M2×实时汇率、公司/加密货币以实时市值计；房地产、政府债务、煤炭、"
                 "天然气为权威机构存量估值（慢变量，静态基准）。每日自动更新，仅供参考，不构成投资建议。"),
        "assets": assets,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"写入 {OUT_PATH}：{len(assets)} 项，榜首 {assets[0]['name']} "
          f"${top_cap_t:.1f}T，总市值 ${data['totalMarketCap'] / 1000:.1f}T，分类 {cat_count}")


if __name__ == "__main__":
    build()
