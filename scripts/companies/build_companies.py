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
import csv
import io
import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone

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
SP500_PATH = os.path.join("apps", "companies", "sp500.json")
# 成分名单来自 datahub 的公开数据集（CSV，免密钥）。探测过：503 个代码，与标普500的
# 份额类数量一致（500 家公司、503 个代码，GOOGL/GOOG 这类双份额各占一个）。
SP500_LIST_URL = ("https://raw.githubusercontent.com/datasets/s-and-p-500-companies"
                  "/main/data/constituents.csv")
SP500_NOTE = ("标普500成分股的当日市值与涨跌，与全球公司榜同一次取数、同一来源。"
              "成分名单取自 datahub 公开数据集，站内按 Yahoo 的代码写法归一化后匹配；"
              "名单里站内没有行情的成分股逐个列在 missing 里，不用别的公司顶替、也不静默丢弃。"
              "市值为「最新价 × 流通股数」，与指数公司自己按自由流通量加权的口径不同，"
              "因此这里只用于相对大小的可视化，不是指数权重。")
HEALTH_PATH = os.path.join("apps", "companies", "health.json")
HISTORY_PATH = os.path.join("apps", "companies", "history.json")
LONG_HISTORY_PATH = os.path.join("apps", "companies", "history-monthly.json")
SPARK_PATH = os.path.join("apps", "companies", "spark.json")
SPARK_NOTE = ("行情板迷你走势专用：市值前列上市公司最近 60 个交易日的收盘，"
              "与 history 分片同一次取数、同一来源。只存行情板真正会用到的窗口——"
              "完整的 260 个交易日在 history 分片里，行情页按 historyShard 取自己那一片。"
              "共享日期轴上该标的当日无收盘则为 null，不做前向填充。")


def shard_of(index):
    """名次（从0起）落在第几片。片号从 1 起，与 data.json 里的 historyShard 一致。"""
    return index // SHARD_SIZE + 1


def shard_path(base, shard):
    """第 1 片沿用原文件名，其余加 -N；老的读取方仍能直接读到第 1 片。"""
    return base if shard == 1 else base.replace(".json", f"-{shard}.json")


def load_all_shards(base, count):
    """把各片的上一份历史合回一份。

    公司名次天天在变，今天在第 1 片的明天可能掉到第 2 片。若只拿本片的上一份做沿用，
    跨片移动的公司在本轮取数失败时就会丢掉全部历史。因此先合、后按新名次重新分片。
    """
    merged = {"dates": [], "series": {}}
    for shard in range(1, count + 1):
        part = load_json(shard_path(base, shard))
        if not part:
            continue
        if not merged["dates"] and part.get("dates"):
            merged["dates"] = part["dates"]
        if part.get("dates") == merged["dates"]:
            merged["series"].update(part.get("series") or {})
        else:
            # 日期轴对不齐（历史上分片规则变过）时逐条对齐，宁可慢也不能错位。
            for symbol, values in (part.get("series") or {}).items():
                pairs = {d: v for d, v in zip(part.get("dates") or [], values)
                         if isinstance(v, (int, float))}
                merged["series"][symbol] = [pairs.get(d) for d in merged["dates"]]
    return merged if merged["series"] else {}


def write_shards(base, history, symbols, kind):
    """把一份完整历史按名次切片写出，并清掉不再需要的旧片。"""
    written = 0
    for shard in range(1, (len(symbols) - 1) // SHARD_SIZE + 2):
        part_symbols = symbols[(shard - 1) * SHARD_SIZE: shard * SHARD_SIZE]
        if not part_symbols:
            break
        part = dict(history)
        part["series"] = {s: history["series"][s] for s in part_symbols
                          if s in history.get("series", {})}
        part["symbols"] = part_symbols
        part["shard"] = shard
        part["shardSize"] = SHARD_SIZE
        with open(shard_path(base, shard), "w", encoding="utf-8") as handle:
            json.dump(part, handle, ensure_ascii=False, separators=(",", ":"))
        written += 1
    for stale in range(written + 1, written + 6):        # 清理缩编后遗留的旧片
        leftover = shard_path(base, stale)
        if os.path.exists(leftover):
            os.remove(leftover)
            print(f"删除不再需要的旧片 {leftover}")
    print(f"{kind}：写出 {written} 片，每片至多 {SHARD_SIZE} 家")
    return written
LONG_HISTORY_NOTE = ("市值前列上市公司自身的月线收盘，用于 5 年 / 10 年 / 25 年 / 全部区间的走势；"
                     "起始月即该公司在数据源上可得的最早月份。数据源对超长区间会自行降采样，"
                     "部分公司的早年只有季度末观测，缺月一律留空不做前向填充，"
                     "页面按真实时间轴作图；本轮未取到的公司沿用上次序列。")
HISTORY_SYMBOLS = 500    # 存日线的家数，与行情板股票行数对齐：每一行都要画得出迷你走势、
                         # 也都要能打开自己的走势页，不能一半有序列、一半写「无序列」。
                         # 500 家 × 260 个交易日约 830KB，一份文件太重，因此分两路存：
                         #   spark.json  —— 只留最近 60 个收盘（行情板画迷你走势只用这么多），
                         #                  一份约 190KB，打开股票品类时读它；
                         #   history-N   —— 完整 260 个交易日，按名次每 100 家一片，
                         #                  行情页只读自己那一片（约 170KB）而不是整份。
SHARD_SIZE = 100         # 每片家数；片号写进 data.json 逐行的 historyShard，页面据此直接取对片
SPARK_POINTS = 60        # 与行情板迷你走势的窗口一致——多存的点页面根本不会用
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


def sp500_symbol(raw):
    """把名单里的代码写成 Yahoo 的写法：类别股用连字符，BRK.B → BRK-B。

    不归一化就会把 BRK.B、BF.B 判成「站内没有」，而站内其实有 BRK-B、BF-B——
    同一家公司因为一个分隔符被算成缺失，得出的覆盖度是假的。
    """
    return str(raw or "").strip().upper().replace(".", "-")


def fetch_sp500_members(session):
    """取标普500成分名单，返回 (代码集合, 逐代码的GICS行业)；取不到返回 (None, None)。

    取不到就沿用上一份 sp500.json 的名单并标 stale：成分名单一年只变动几次，
    沿用一天远好过当天把整张热力图清空。
    """
    try:
        response = session.get(SP500_LIST_URL, timeout=20)
        response.raise_for_status()
        rows = list(csv.DictReader(io.StringIO(response.text)))
    except Exception as exc:                       # noqa: BLE001
        print(f"[!!] 标普500成分名单取数失败：{str(exc)[:80]}")
        return None, None
    members, sectors = set(), {}
    for row in rows:
        symbol = sp500_symbol(row.get("Symbol"))
        if not symbol:
            continue
        members.add(symbol)
        sectors[symbol] = (row.get("GICS Sector") or "").strip()
    if len(members) < 400:
        print(f"[!!] 成分名单只有 {len(members)} 条，明显不完整，按取数失败处理")
        return None, None
    print(f"标普500成分名单：{len(members)} 个代码")
    return members, sectors


def previous_sp500_members():
    """上一份 sp500.json 里的成分代码，供本轮取不到名单时沿用。"""
    try:
        with open(SP500_PATH, encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, ValueError):
        return set()
    return {row["symbol"] for row in payload.get("members") or [] if row.get("symbol")}


def write_sp500(listed, members, member_sectors, stale, updated_at, as_of, universe):
    """写标普500的当日快照：热力图按行业分块、按市值定面积、按当日涨跌上色。

    只收「名单里有、且站内当天确实取到行情」的公司。名单里站内没有行情的逐个列进
    missing，页面照实显示覆盖了多少家——一张少了几家还叫「标普500」的图是在骗人。
    """
    sector_en = {u["symbol"]: u.get("sector") or "" for u in universe if u.get("symbol")}
    rows = []
    for row in listed:
        if not row.get("sp500") or not isinstance(row.get("marketCap"), (int, float)):
            continue
        if not (row["marketCap"] > 0):
            continue
        rows.append({
            "symbol": row["symbol"], "name": row["name"], "nameEn": row["nameEn"],
            "marketCap": row["marketCap"], "price": row["price"],
            "changePct": row["changePct"],
            "sector": row["sector"],
            "sectorEn": member_sectors.get(row["symbol"]) or sector_en.get(row["symbol"]) or "",
            "logo": row.get("logo"), "stale": bool(row.get("stale")),
        })
    rows.sort(key=lambda r: r["marketCap"], reverse=True)
    for index, row in enumerate(rows, 1):
        row["rank"] = index
    covered = {row["symbol"] for row in rows}
    missing = sorted(members - covered)
    payload = {
        "updatedAt": updated_at,
        "asOf": as_of,
        "frequency": "daily",
        "source": "Yahoo Finance",
        "listSource": "datahub / s-and-p-500-companies",
        "listStale": bool(stale),
        "status": "ok" if not missing and not stale else "partial",
        "constituents": len(members),
        "count": len(rows),
        "missing": missing,
        "note": SP500_NOTE + ("（本轮成分名单未取到，沿用上一份。）" if stale else ""),
        "members": rows,
    }
    os.makedirs(os.path.dirname(SP500_PATH), exist_ok=True)
    with open(SP500_PATH, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
    print(f"写入 {SP500_PATH}：{len(rows)}/{len(members)} 家成分股，"
          f"缺 {len(missing)}{'（名单沿用上一份）' if stale else ''}")


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


def load_monthly_shards():
    """月线各片合回一份。月线是 {start, closes} 的逐条结构，没有共享日期轴，直接并 series。"""
    merged = {}
    for shard in range(1, 9):
        part = load_json(shard_path(LONG_HISTORY_PATH, shard))
        if part and isinstance(part.get("series"), dict):
            merged.update(part["series"])
    return {"series": merged} if merged else {}


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
        collected, load_monthly_shards(), run_updated_at,
        source="Yahoo Finance", note=LONG_HISTORY_NOTE)
    if not history:
        print("月线序列本轮全部失败，保留上次 history-monthly 分片（不写空数据）")
        return None
    write_shards(LONG_HISTORY_PATH, history, symbols, "月线历史")
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
        collected, load_all_shards(HISTORY_PATH, 8), run_updated_at,
        source="Yahoo Finance", note=HISTORY_NOTE, limit=HISTORY_POINTS)
    if not history:
        print("日线序列本轮全部失败，保留上次 history 分片（不写空数据）")
        return None
    history["symbols"] = symbols
    write_shards(HISTORY_PATH, history, symbols, "日线历史")
    write_spark(history, symbols, run_updated_at)
    attach_returns(history, symbols)
    print(f"日线历史：{len(collected)}/{len(symbols)} 只本轮取到，"
          f"{len(retained)} 只沿用上次，共 {history['points']} 个交易日")
    write_long_history(session, symbols, collected, run_updated_at)
    return history


def period_returns(points):
    """由日线序列算出四档区间涨跌幅，口径与跨资产管道完全一致：
    「最近观测」对「锚点日或之前的最后一个观测」，锚点当天没有观测就顺延到更早的一个。

    这四个数由管道算而不是由页面现场算，是因为行情板的迷你走势只读最近 60 个交易日
    的窄文件——用 60 个点算不出「年初至今」与「同比」。让页面为了两列数字去下载
    500 家的完整历史，是本末倒置。
    """
    pairs = sorted((str(d), float(v)) for d, v in (points or [])
                   if d and isinstance(v, (int, float)))
    if len(pairs) < 2:
        return None
    last_date, last = pairs[-1]
    day = datetime.strptime(last_date, "%Y-%m-%d").date()

    def before(anchor):
        chosen = None
        for date, value in pairs:
            if date <= anchor:
                chosen = value
            else:
                break
        return chosen

    def change(base):
        if not base:
            return None
        return round((last / base - 1.0) * 100, 2)

    return {
        "w1": change(before(str(day - timedelta(days=7)))),
        "m1": change(before(str(day - timedelta(days=30)))),
        "ytd": change(before(f"{day.year - 1}-12-31")),
        "y1": change(before(str(day - timedelta(days=365)))),
    }


def write_spark(history, symbols, run_updated_at):
    """行情板迷你走势专用的窄文件：只留最近 SPARK_POINTS 个收盘。

    行情板对每一行只画最近 60 个观测，却要为此下载 260 个点的完整历史——500 家时
    那是 830KB 换 190KB 的用量。这份文件把窗口裁到页面真正会用的宽度。
    """
    dates = (history.get("dates") or [])[-SPARK_POINTS:]
    series = {}
    for symbol in symbols:
        values = (history.get("series") or {}).get(symbol)
        if not isinstance(values, list):
            continue
        window = values[-SPARK_POINTS:]
        if any(value is not None for value in window):
            series[symbol] = window
    payload = {
        "updatedAt": run_updated_at, "source": "Yahoo Finance",
        "frequency": "daily", "points": len(dates), "count": len(series),
        "note": SPARK_NOTE, "dates": dates, "series": series,
    }
    with open(SPARK_PATH, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
    print(f"迷你走势：{len(series)} 家 × {len(dates)} 个交易日 → "
          f"{os.path.getsize(SPARK_PATH) // 1024} KB")


def attach_returns(history, symbols):
    """把四档区间涨跌写回已经落盘的 data.json 与 sp500.json 逐行。

    历史要等 data.json 写完之后才建（顺序不能反：历史失败不该拖累 data.json），
    所以这里回头补写一次，而不是在拼行的时候算。

    两份文件回写的是**同一次计算**的结果，不各算一遍——气泡图的「年初至今」与
    行情板公司行的「年初至今」必须是同一个数，两处各算一次早晚会对不上。
    """
    data = load_json(OUT_PATH)
    if not data or not isinstance(data.get("companies"), list):
        print("data.json 读不回来，跳过区间涨跌回写（不影响已写好的快照）")
        return
    dates = history.get("dates") or []
    series = history.get("series") or {}
    computed = {}
    filled = 0
    for row in data["companies"]:
        symbol = row.get("symbol")
        values = series.get(symbol) if symbol else None
        if not isinstance(values, list):
            continue
        points = [(d, v) for d, v in zip(dates, values) if isinstance(v, (int, float))]
        returns = period_returns(points)
        if returns:
            row["returns"] = returns
            computed[symbol] = returns
            filled += 1
    with open(OUT_PATH, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
    print(f"区间涨跌：{filled}/{len(symbols)} 家已写回 data.json（每周/月度/年初至今/同比）")

    # 同一批数字回写给标普500快照：气泡图的纵轴要按「年初至今」等区间摆位，
    # 而 sp500.json 是在历史建好之前写的，因此和 data.json 一样回头补一次。
    sp500 = load_json(SP500_PATH)
    if not sp500 or not isinstance(sp500.get("members"), list):
        print("sp500.json 读不回来，跳过区间涨跌回写（不影响已写好的快照）")
        return
    sp_filled = 0
    for row in sp500["members"]:
        returns = computed.get(row.get("symbol"))
        if returns:
            row["returns"] = returns
            sp_filled += 1
    with open(SP500_PATH, "w", encoding="utf-8") as handle:
        json.dump(sp500, handle, ensure_ascii=False, separators=(",", ":"))
    print(f"区间涨跌：{sp_filled}/{len(sp500['members'])} 家已写回 sp500.json")


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

    # 成分标记打在全部已取到的上市公司上，而不是截断后的前500：标普500里有几十家
    # 排不进全球市值前500，只标截断后的那批会把它们漏掉。
    members, member_sectors = fetch_sp500_members(session)
    members_stale = members is None
    if members_stale:
        members = previous_sp500_members()
        member_sectors = {}
    for row in listed:
        row["sp500"] = row["symbol"] in members

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
    # 逐行写上自己在第几片日线历史里。行情页据此只取自己那一片（约170KB），
    # 而不是把 500 家的完整历史整份拉下来。名次按上市公司自己的顺序数，
    # 不含未上市那几十家——它们本来就没有行情历史。
    for index, row in enumerate(r for r in rows if not r.get("private")):
        row["historyShard"] = shard_of(index) if index < HISTORY_SYMBOLS else None

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
    write_sp500(listed, members, member_sectors, members_stale, run_updated_at,
                max(fresh_as_of)[:10], universe)

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
