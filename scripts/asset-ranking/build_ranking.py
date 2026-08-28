#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「全球资产市值排行榜（前 250，不限品类）」→ apps/asset-ranking/data.json。

一张榜把所有大类资产按美元市值横向拉通排名：房地产、政府债券、煤炭、石油、天然气、
铁矿石、铝、铜、黄金、白银、各国货币（广义货币 M2）、上市公司、加密货币……只看市值。

方法论（与 assetmarketcap / 8marketcap 同款，可每日更新）：
    市值 = 数量(储量/地面存量/M2) × 单位价格(日频行情/汇率)
  · 商品/贵金属：储量或地面存量 × Yahoo 期货/现货价（每日随行情浮动）
  · 货币：广义货币 M2/M3 × 日频汇率快照
  · 公司：直接复用每日刷新的 apps/companies/data.json（Yahoo Finance）
  · 加密货币：CoinGecko 最新市值快照（兜底 Yahoo 现价 × 流通量）
  · 房地产/政府债务/煤炭/天然气：权威机构存量估值（慢变量，静态基准）

稳健性（沿用本仓库取数风格）：
  · 纯 requests + 硬超时、逐项 try/except、主备双域名，单点失败不影响整体；
  · 某项行情价取不到时回退：上次 data.json 的值(stale) → 静态基准，绝不掉榜/闪烁；
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
SCRIPTS_DIR = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, SCRIPTS_DIR)
from baselines import (  # noqa: E402
    AGGREGATES,
    BASELINE_PROVENANCE,
    CATEGORIES,
    CRYPTO,
    DEFAULT_BASELINE_PROVENANCE,
)
from market_data_quality import (  # noqa: E402
    fallback_data_meta,
    make_data_meta,
    summarize_data_quality,
)
from market_history import build_rolling_history  # noqa: E402
from market_history_long import build_long_history  # noqa: E402
from market_monthly_yahoo import fetch_monthly  # noqa: E402
from market_source_health import (  # noqa: E402
    attach_upstream_health,
    load_json as load_health_json,
    make_source_health,
    write_health,
)

OUT_PATH = os.path.join("apps", "asset-ranking", "data.json")
HEALTH_PATH = os.path.join("apps", "asset-ranking", "health.json")
CRYPTO_BOARD_PATH = os.path.join("apps", "asset-ranking", "crypto.json")
COMPANIES_PATH = os.path.join("apps", "companies", "data.json")
COMPANIES_HEALTH_PATH = os.path.join("apps", "companies", "health.json")
TOP_N = 250
YF_HOSTS = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
YF_HEADERS = {"User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                             "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"), "Accept": "application/json"}
CG_URL = ("https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc"
          "&per_page=50&page=1&price_change_percentage=24h")
CG_CHART_URL = "https://api.coingecko.com/api/v3/coins/{coin}/market_chart?vs_currency=usd&days=365"
CRYPTO_BOARD_COUNT = 20   # 金融终端加密品类展示的条数；行情与日线都来自同一次CoinGecko取数
CRYPTO_BOARD_POINTS = 260
# 免费档限速实测：日线按2秒间隔连发时第5个请求起就被拒。改为10秒一个（约6次/分钟），
# 失败再等30秒重试一次；连续4个都拿不到就本轮提前收工，已取到的照常写入，
# 其余沿用上次序列——历史会在若干轮里补齐，不靠一次跑满。
CRYPTO_CHART_INTERVAL = 10.0
CRYPTO_CHART_RETRY_WAIT = 30.0
CRYPTO_CHART_MAX_MISSES = 4
CRYPTO_BOARD_NOTE = ("CoinGecko 市值前列加密资产的日度快照与滚动日线；涨跌为过去24小时口径，"
                     "与股票的当日口径不同。共享日期轴上当日无价则为 null，不做前向填充；"
                     "本轮未取到的币种沿用上次序列，不补造新点。")
# 加密长周期月线：CoinGecko 免费档的历史只给 365 天，5年/10年/25年/全部这四档拿不到，
# 改由 Yahoo Finance 的现货交易对（{符号}-USD）月线补齐。这是与现价不同的另一个来源，
# 文件、页面都必须写明，不与 CoinGecko 的现价混为一谈。
CRYPTO_LONG_HISTORY_PATH = os.path.join("apps", "asset-ranking", "crypto-history-monthly.json")
CRYPTO_LONG_SOURCE = "Yahoo Finance"
CRYPTO_LONG_NOTE = ("加密资产的月线收盘，来自 Yahoo Finance 的现货交易对（{符号}-USD），"
                    "用于 5 年 / 10 年 / 25 年 / 全部四档区间；"
                    "与 crypto.json 的现价、24小时涨跌（CoinGecko）不是同一来源，"
                    "两边取价的交易所与时点不同，历史价位可能有小幅差异。"
                    "起始月即该币种在数据源上可得的最早月份（比特币约 2014 年 9 月起，"
                    "更早的价格该源没有），缺月一律留空不做前向填充；"
                    "本轮未取到的币种沿用上次序列，不补造新点。")
# 同名代码在 Yahoo 上可能指向另一个资产，因此每条序列都要用最新一个月的收盘与本轮
# CoinGecko 现价对表；偏离超过这个比例就判定为取错标的，宁可没有该币的长历史。
CRYPTO_LONG_TOLERANCE = 0.20
CRYPTO_LONG_INTERVAL = 0.35
# CoinGecko 只给英文名，这里补常见币种的中文名；未收录的如实沿用英文名，不臆造译名。
CRYPTO_NAME_ZH = {
    "BTC": "比特币", "ETH": "以太坊", "USDT": "泰达币", "BNB": "币安币", "XRP": "瑞波币",
    "SOL": "索拉纳", "USDC": "美元币", "DOGE": "狗狗币", "ADA": "艾达币", "TRX": "波场",
    "TON": "Toncoin", "AVAX": "雪崩", "SHIB": "柴犬币", "DOT": "波卡", "LINK": "Chainlink",
    "BCH": "比特币现金", "LTC": "莱特币", "XLM": "恒星币", "UNI": "Uniswap", "ATOM": "Cosmos",
    "XMR": "门罗币", "ETC": "以太经典", "HBAR": "Hedera", "FIL": "Filecoin", "APT": "Aptos",
}


# ————————————————————— 取数工具 —————————————————————
def yf_price(session, symbol):
    """取单个Yahoo代码的最新价、上一收盘与行情时点；失败返回None。"""
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
                return float(price), (float(prev) if isinstance(prev, (int, float)) and prev > 0 else None), as_of
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


def valid_iso(value):
    if not isinstance(value, str) or not value:
        return False
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
        return True
    except ValueError:
        return False


def baseline_provenance(asset):
    return BASELINE_PROVENANCE.get(asset["name"], DEFAULT_BASELINE_PROVENANCE)


# ————————————————————— 各品类构建 —————————————————————
def build_aggregates(session, prev_rows, run_updated_at):
    """房地产 / 大宗商品 / 贵金属 / 货币 / 债券：数量 × 行情价（或静态基准）。"""
    out = []
    for a in AGGREGATES:
        row = {"name": a["name"], "nameEn": a["nameEn"], "category": a["cat"], "emoji": a["emoji"],
               "unit": a.get("unit"), "qty": a.get("qty"), "note": a.get("note")}
        cap_b = price_disp = change = None
        stale = False
        baseline = baseline_provenance(a)
        combined_source = "Yahoo Finance · " + baseline["source"]
        row_meta = None

        if a.get("symbol"):                         # 有行情代码：数量 × 本轮行情单价
            res = yf_price(session, a["symbol"])
            if res:
                raw, raw_prev, quote_as_of = res
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
                row_meta = make_data_meta(
                    "market",
                    combined_source,
                    as_of=quote_as_of,
                    updated_at=run_updated_at,
                    frequency="daily",
                    status="partial" if not baseline.get("asOf") else "ok",
                    note="价格为本轮行情；存量基准的原报告日期尚未结构化。" if not baseline.get("asOf") else None,
                )
            else:                                   # 行情价取不到 → 沿用上次(stale) → 静态基准
                p = prev_rows.get(a["name"])
                if p and p.get("marketCap"):
                    cap_b = p["marketCap"]; price_disp = p.get("price"); change = p.get("changePct"); stale = True
                    row_meta = fallback_data_meta(
                        p,
                        source=combined_source,
                        frequency="daily",
                        legacy_updated_at=p.get("dataMeta", {}).get("updatedAt") if isinstance(p.get("dataMeta"), dict) else None,
                    )
                else:
                    price_disp = a.get("basePrice")
                    cap_b = (a["qty"] * a["basePrice"] / 1e9) if (a.get("qty") and a.get("basePrice")) else a.get("baseCap")
                    row_meta = make_data_meta(
                        "estimate",
                        baseline["source"],
                        as_of=baseline.get("asOf"),
                        updated_at=run_updated_at,
                        frequency="irregular",
                        status="partial",
                        note="行情请求失败且无历史快照，使用静态基准值。",
                    )
        elif a.get("baseCap") is not None:          # 纯静态基准（房地产/政府债/天然气）
            cap_b = a["baseCap"]
        elif a.get("qty") and a.get("basePrice"):   # 静态：储量 × 固定基准价（煤炭/铁矿石/美元 M2）
            price_disp = a["basePrice"]; cap_b = a["qty"] * a["basePrice"] / 1e9

        if not cap_b:
            continue
        if row_meta is None:
            row_meta = make_data_meta(
                "estimate",
                baseline["source"],
                as_of=baseline.get("asOf"),
                updated_at=run_updated_at,
                frequency="irregular",
                status="partial" if not baseline.get("asOf") else "ok",
                note="慢变量或静态存量估值；原报告日期未结构化。" if not baseline.get("asOf") else None,
            )
        row.update({"marketCap": round(cap_b, 1), "price": price_disp, "changePct": change,
                    "static": a.get("symbol") is None, "stale": stale, "dataMeta": row_meta})
        out.append(row)
    return out


def coingecko_markets(session):
    """CoinGecko 市值快照 {id: 记录}；失败返回空字典。一轮只取一次，资产榜与加密板共用。"""
    try:
        r = session.get(CG_URL, timeout=15)
        if r.status_code != 200:
            return {}
        return {c["id"]: c for c in r.json() if isinstance(c, dict) and c.get("id")}
    except Exception:
        return {}


def coingecko_daily_closes(session, coin_id):
    """取单个币种近一年的日线价格 [(YYYY-MM-DD, price), ...]；任何异常都返回空列表。"""
    try:
        r = session.get(CG_CHART_URL.format(coin=coin_id), timeout=20)
        if r.status_code != 200:
            return []
        daily = {}
        for point in (r.json().get("prices") or []):
            if not isinstance(point, list) or len(point) < 2:
                continue
            stamp, price = point[0], point[1]
            if not isinstance(stamp, (int, float)) or not isinstance(price, (int, float)):
                continue
            day = datetime.fromtimestamp(stamp / 1000, timezone.utc).strftime("%Y-%m-%d")
            daily[day] = float(price)          # 同一天有多个点时取最后一个
        return sorted(daily.items())
    except Exception:
        return []


def build_crypto_board(session, markets, run_updated_at):
    """市值前列加密资产的行情与日线 → apps/asset-ranking/crypto.json。

    行情直接复用本轮已经取到的 markets 快照（不重复请求），日线逐币单独取、单独容错；
    本轮全失败时返回 None，由调用方保留上次文件，不写空数据。
    """
    ranked = sorted(
        [m for m in markets.values()
         if isinstance(m.get("market_cap"), (int, float)) and m.get("symbol")],
        key=lambda m: m["market_cap"], reverse=True)[:CRYPTO_BOARD_COUNT]
    if not ranked:
        print("CoinGecko 市值快照不可用，保留上次 crypto.json（不写空数据）")
        return None

    assets, as_of_list = [], []
    for rank, m in enumerate(ranked, 1):
        symbol = str(m["symbol"]).upper()
        as_of = m.get("last_updated") if valid_iso(m.get("last_updated")) else None
        if as_of:
            as_of_list.append(as_of)
        change = m.get("price_change_percentage_24h")
        assets.append({
            "id": m["id"],
            "symbol": symbol,
            "name": CRYPTO_NAME_ZH.get(symbol) or m.get("name") or symbol,
            "nameEn": m.get("name") or symbol,
            "price": m.get("current_price"),
            "changePct": round(change, 2) if isinstance(change, (int, float)) else None,
            "marketCap": round(m["market_cap"] / 1e9, 1),
            "rank": rank,
            "stale": as_of is None,
            "dataMeta": make_data_meta(
                "market",
                "CoinGecko",
                as_of=as_of,
                updated_at=run_updated_at,
                frequency="daily",
                status="ok" if as_of else "partial",
                note=None if as_of else "本轮快照缺少可核验的时点。",
            ),
        })

    collected, misses = {}, 0
    for asset in assets:
        points = coingecko_daily_closes(session, asset["id"])
        if not points:
            time.sleep(CRYPTO_CHART_RETRY_WAIT)
            points = coingecko_daily_closes(session, asset["id"])
        if points:
            collected[asset["symbol"]] = points
            misses = 0
        else:
            misses += 1
            if misses >= CRYPTO_CHART_MAX_MISSES:
                print(f"CoinGecko 连续{misses}次拒绝日线请求，本轮提前停止取历史；"
                      "已取到的照常写入，其余沿用上次序列")
                break
        time.sleep(CRYPTO_CHART_INTERVAL)      # 免费档限速：串行且留足间隔
    prev = load_json(CRYPTO_BOARD_PATH) or {}
    history, retained = build_rolling_history(
        collected, prev.get("history"), run_updated_at,
        source="CoinGecko", note=CRYPTO_BOARD_NOTE, limit=CRYPTO_BOARD_POINTS)

    data = {
        "updatedAt": run_updated_at,
        "asOf": max(as_of_list)[:10] if as_of_list else run_updated_at[:10],
        "source": "CoinGecko",
        "frequency": "daily",
        "status": "ok" if (history and len(collected) >= len(assets) * 0.6) else "partial",
        "count": len(assets),
        "changeBasis": "24_hours",
        "note": CRYPTO_BOARD_NOTE,
        "assets": assets,
        "history": history,
    }
    os.makedirs(os.path.dirname(CRYPTO_BOARD_PATH), exist_ok=True)
    with open(CRYPTO_BOARD_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    print(f"写入 {CRYPTO_BOARD_PATH}：{len(assets)} 币，"
          f"日线 {len(collected)} 币本轮取到、{len(retained)} 币沿用上次")
    return data


def crypto_yahoo_symbol(symbol):
    """币种代码 → Yahoo 现货交易对代码；Yahoo 统一以 {符号}-USD 表示美元现货。"""
    text = str(symbol or "").strip().upper()
    if not text or not text.isalnum():
        return None
    return f"{text}-USD"


def plausible_monthly(points, spot):
    """月线尾点必须与本轮现价对得上，否则判定同名代码在数据源上是另一个资产。

    interval=1mo 的最后一根是当月未走完的那根，收盘即最新成交价，正常应与
    CoinGecko 现价高度一致；差得离谱只可能是取错标的，这种序列宁可不要。
    """
    if not points or not isinstance(spot, (int, float)) or spot <= 0:
        return False
    last = points[-1][1]
    if not isinstance(last, (int, float)) or last <= 0:
        return False
    return abs(last - spot) / spot <= CRYPTO_LONG_TOLERANCE


def build_crypto_long_history(assets, run_updated_at):
    """加密品类的长周期月线 → apps/asset-ranking/crypto-history-monthly.json。

    CoinGecko 免费档只回溯 365 天，5年/10年/25年/全部四档在那边根本拿不到，
    因此这份历史走 Yahoo Finance 的现货交易对；来源与现价不同，写进文件的
    source/note 里如实说明。逐币单独取、单独容错，取错标的的直接丢弃；
    本轮一条都没取到时不写文件，保留上次那份。
    """
    collected, skipped = {}, []
    for asset in assets:
        symbol = asset.get("symbol")
        pair = crypto_yahoo_symbol(symbol)
        if not pair:
            skipped.append(f"{symbol}：代码不合法")
            continue
        try:
            points = fetch_monthly(pair)
        except Exception as error:                   # noqa: BLE001 - 单币失败只跳过自己
            skipped.append(f"{symbol}（{pair}）：{error}")
            time.sleep(CRYPTO_LONG_INTERVAL)
            continue
        if plausible_monthly(points, asset.get("price")):
            collected[str(symbol).upper()] = points
        else:
            skipped.append(f"{symbol}（{pair}）：月末价与现价对不上，疑似同名的别的资产")
        time.sleep(CRYPTO_LONG_INTERVAL)

    prev = load_json(CRYPTO_LONG_HISTORY_PATH) or {}
    history, retained = build_long_history(
        collected, prev, run_updated_at, source=CRYPTO_LONG_SOURCE, note=CRYPTO_LONG_NOTE)
    if not history:
        print(f"本轮无可用加密月线，保留上次 {CRYPTO_LONG_HISTORY_PATH}，不覆盖。")
        return None
    os.makedirs(os.path.dirname(CRYPTO_LONG_HISTORY_PATH), exist_ok=True)
    with open(CRYPTO_LONG_HISTORY_PATH, "w", encoding="utf-8") as f:
        json.dump(history, f, ensure_ascii=False, separators=(",", ":"))
    print(f"写入 {CRYPTO_LONG_HISTORY_PATH}：{history['symbols']} 币月线，"
          f"本轮取到 {len(collected)} 币、沿用上次 {len(retained)} 币")
    if skipped:
        print(f"月线未取到：{'; '.join(skipped[:8])}")
    return history


def build_crypto(session, prev_rows, run_updated_at, markets=None):
    """加密货币：优先CoinGecko最新市值；兜底Yahoo现价×流通量；再兜底基准。"""
    out = []
    cg = markets if markets is not None else coingecko_markets(session)
    if cg:
        print(f"CoinGecko 市值快照：{len(cg)} 币")

    for c in CRYPTO:
        row = {"name": c["name"], "nameEn": c["nameEn"], "category": "crypto", "emoji": "₿",
               "symbol": c["symbol"]}
        cap_b = price_disp = change = None
        row_meta = None
        m = cg.get(c["id"])
        if m and m.get("market_cap") and valid_iso(m.get("last_updated")):
            cap_b = m["market_cap"] / 1e9
            price_disp = m.get("current_price")
            change = round(m["price_change_percentage_24h"], 2) if isinstance(
                m.get("price_change_percentage_24h"), (int, float)) else None
            row_meta = make_data_meta(
                "market",
                "CoinGecko",
                as_of=m["last_updated"],
                updated_at=run_updated_at,
                frequency="daily",
            )
        elif c.get("yf") and c.get("supply"):        # Yahoo 现价 × 流通量
            res = yf_price(session, c["yf"])
            if res:
                raw, raw_prev, quote_as_of = res
                cap_b = raw * c["supply"] / 1e9; price_disp = raw; change = pct(raw, raw_prev)
                row_meta = make_data_meta(
                    "market",
                    "Yahoo Finance · 静态流通量基准",
                    as_of=quote_as_of,
                    updated_at=run_updated_at,
                    frequency="daily",
                    status="partial",
                    note="价格为本轮行情，流通量为静态兜底基准。",
                )
        if cap_b is None:                            # 沿用上次 → 基准
            p = prev_rows.get(c["name"])
            if p and p.get("marketCap"):
                cap_b = p["marketCap"]; price_disp = p.get("price"); change = p.get("changePct"); row["stale"] = True
                row_meta = fallback_data_meta(
                    p,
                    source="CoinGecko · Yahoo Finance",
                    frequency="daily",
                    legacy_updated_at=p.get("dataMeta", {}).get("updatedAt") if isinstance(p.get("dataMeta"), dict) else None,
                )
            else:
                cap_b = c["baseCap"]
                row_meta = make_data_meta(
                    "estimate",
                    "静态加密市值基准（原始来源未结构化）",
                    as_of=None,
                    updated_at=run_updated_at,
                    frequency="irregular",
                    status="partial",
                    note="CoinGecko与Yahoo均不可用，且无历史快照。",
                )
        row.update({"marketCap": round(cap_b, 1), "price": price_disp, "changePct": change,
                    "stale": row.get("stale") is True, "dataMeta": row_meta})
        out.append(row)
    return out


def build_companies(run_updated_at):
    """直接复用每日刷新的 apps/companies/data.json（Yahoo Finance）。"""
    d = load_json(COMPANIES_PATH)
    if not d or not d.get("companies"):
        print("读不到 apps/companies/data.json，本轮不含公司条目")
        return []
    out = []
    for c in d["companies"]:
        if not c.get("marketCap"):
            continue
        company_meta = c.get("dataMeta")
        if not isinstance(company_meta, dict):
            company_meta = make_data_meta(
                "unknown",
                "Yahoo Finance" if c.get("private") is not True else "公开融资估值（旧快照）",
                as_of=None,
                updated_at=d.get("updatedAt") or run_updated_at,
                frequency="daily" if c.get("private") is not True else "irregular",
                note="上游公司榜旧快照未提供逐条来源状态。",
            )
        out.append({
            "name": c["name"], "nameEn": c.get("nameEn"), "category": "company",
            "marketCap": c["marketCap"], "price": c.get("price"), "priceCur": c.get("priceCur"),
            "changePct": c.get("changePct"), "country": c.get("country"), "flag": c.get("flag"),
            "sector": c.get("sector"), "symbol": c.get("symbol"),
            # 公司 logo 存放在 apps/companies/logos/，本页用相对上级路径引用，无需复制文件
            "logo": ("../companies/" + c["logo"]) if c.get("logo") else None,
            "private": c.get("private"), "lastRound": c.get("lastRound"),
            "stale": c.get("stale") is True, "dataMeta": dict(company_meta),
        })
    print(f"复用公司榜 {len(out)} 家")
    return out


# ————————————————————— 主流程 —————————————————————
def build():
    prev_data = load_json(OUT_PATH)
    prev_health = load_health_json(HEALTH_PATH)
    prev_rows = {r["name"]: r for r in (prev_data or {}).get("assets", []) if r.get("name")}
    run_updated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    def with_companies_health(health):
        companies_data = load_json(COMPANIES_PATH) or {}
        return attach_upstream_health(
            health,
            source_id="companies-upstream",
            upstream_dataset="companies",
            upstream_health=load_health_json(COMPANIES_HEALTH_PATH),
            upstream_snapshot_at=companies_data.get("updatedAt"),
        )

    def keep(msg, attempted_rows=None):
        health = make_source_health(
            "asset-ranking",
            published_rows=(prev_data or {}).get("assets", []),
            attempted_rows=attempted_rows or [],
            attempted_at=run_updated_at,
            published_snapshot_at=(prev_data or {}).get("updatedAt"),
            published=False,
            previous_health=prev_health,
            failure_reason=msg + "；本轮未发布新快照。",
        )
        write_health(HEALTH_PATH, with_companies_health(health))
        print(msg + ("（保留上次 data.json，不覆盖）" if prev_data else "（且无历史快照，跳过）"))

    session = requests.Session()
    session.headers.update(YF_HEADERS)

    aggregates = build_aggregates(session, prev_rows, run_updated_at)
    markets = coingecko_markets(session)
    crypto = build_crypto(session, prev_rows, run_updated_at, markets=markets)
    companies = build_companies(run_updated_at)

    assets = aggregates + crypto + companies
    assets = [a for a in assets if a.get("marketCap")]
    assets.sort(key=lambda r: r["marketCap"] or 0, reverse=True)
    assets = assets[:TOP_N]
    for i, r in enumerate(assets, 1):
        r["rank"] = i

    # —— 体检：条目足够、榜首量级合理（房地产/债券在 5 万亿~200 万亿美元区间）——
    if len(assets) < 100 or not assets:
        keep(f"条目过少（{len(assets)}）", assets); return
    top_cap_t = assets[0]["marketCap"] / 1000
    if not (50 <= top_cap_t <= 2000):
        keep(f"体检未过：榜首市值 ${top_cap_t:.1f}T", assets); return

    cat_count = {}
    for r in assets:
        cat_count[r["category"]] = cat_count.get(r["category"], 0) + 1

    data_quality = summarize_data_quality(assets)
    market_as_of = [r["dataMeta"]["asOf"] for r in assets
                    if r.get("dataMeta", {}).get("mode") == "market" and r["dataMeta"].get("asOf")]
    data = {
        "updatedAt": run_updated_at,
        "asOf": max(market_as_of)[:10] if market_as_of else run_updated_at[:10],
        "frequency": "daily",
        "status": data_quality["status"],
        "source": "Yahoo Finance · CoinGecko · 公开估算（世界黄金协会 / IMF / Savills 等）",
        "count": len(assets),
        "totalMarketCap": round(sum(r["marketCap"] for r in assets), 1),
        "categories": CATEGORIES,
        "categoryCount": cat_count,
        "note": ("全球资产不限品类按市值排名（前 250）。商品/贵金属以储量或地面存量×日频行情、"
                 "货币以广义货币 M2×日频汇率、公司/加密货币以最新市值快照计；房地产、政府债务、煤炭、"
                 "天然气为权威机构存量估值（慢变量，静态基准）。每日自动更新，仅供参考，不构成投资建议。"),
        "assets": assets,
        "dataQuality": data_quality,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    health = make_source_health(
        "asset-ranking",
        published_rows=assets,
        attempted_rows=assets,
        attempted_at=run_updated_at,
        published_snapshot_at=run_updated_at,
        published=True,
        previous_health=prev_health,
    )
    write_health(HEALTH_PATH, with_companies_health(health))
    print(f"写入 {OUT_PATH}：{len(assets)} 项，榜首 {assets[0]['name']} "
          f"${top_cap_t:.1f}T，总市值 ${data['totalMarketCap'] / 1000:.1f}T，分类 {cat_count}")

    # 加密品类板是附加产物：放在主快照之后，任何失败都只跳过它，不影响已写好的 data.json
    board = None
    try:
        board = build_crypto_board(session, markets, run_updated_at)
    except Exception as error:                       # noqa: BLE001 - 附加产物不得拖垮主管道
        print(f"加密品类板构建异常：{error}；保留上次 crypto.json")

    # 长周期月线又是加密板的附加产物，且来源与现价不同，失败同样只跳过自己
    try:
        if board and board.get("assets"):
            build_crypto_long_history(board["assets"], run_updated_at)
    except Exception as error:                       # noqa: BLE001 - 附加产物不得拖垮主管道
        print(f"加密长周期月线构建异常：{error}；保留上次 crypto-history-monthly.json")


if __name__ == "__main__":
    build()
