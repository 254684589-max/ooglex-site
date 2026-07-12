#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「全球大类资产收益率」数据：从 Yahoo Finance 抓取各品类标的的日线行情，
计算 今日 / 近一周 / 近一月 / 年初至今 / 近一年 涨跌幅，写入
apps/asset-tracker/data.json，供个人主页的静态页面读取渲染。

设计要点（与仓库里 market-bot 的取数风格保持一致）：
- 纯 requests + 硬超时，绝不挂起；每个标的独立 try/except，单个失败不影响整体；
- 不需要任何 API Key —— Yahoo 图表接口实测可从 GitHub Actions 机房 IP 访问；
- 标的代码支持多个候选（按序回退），某个代码失效时自动尝试下一个；
- 本轮全失败则保留上次的 data.json（不会用空数据覆盖好数据）；
- 本轮个别标的失败但历史上拿到过的，沿用上次的值并标记 stale，避免图表忽隐忽现。

由 .github/workflows/asset_tracker.yml 每日定时运行，并把更新后的 data.json 提交回仓库；
GitHub Pages 直接托管该 JSON，页面前端 fetch 后即时渲染。
"""
import json
import os
import time
from datetime import datetime, timezone, timedelta

import requests

OUT_PATH = os.path.join("apps", "asset-tracker", "data.json")

# 四大品类：key / 中文名 / 颜色（沿用示例图语义：股市红、商品蓝、外汇橙、债券青，精修为更通透的配色）
CATEGORIES = [
    {"key": "equity",    "label": "股市", "color": "#ff5d6c"},
    {"key": "commodity", "label": "商品", "color": "#4aa3f0"},
    {"key": "fx",        "label": "外汇", "color": "#ffb13d"},
    {"key": "bond",      "label": "债券", "color": "#2ed1b0"},
]

# 展示的时间周期（前端可切换，默认「年初至今」与示例图一致）
PERIODS = [
    {"key": "d1",  "label": "今日"},
    {"key": "w1",  "label": "近一周"},
    {"key": "m1",  "label": "近一月"},
    {"key": "ytd", "label": "年初至今"},
    {"key": "y1",  "label": "近一年"},
]

# 标的清单：完全对应示例图的 28 个品类。
#   name 中文名 / cat 品类 / syms 候选 Yahoo 代码（按序回退）/ note 代理说明（可选）
ASSETS = [
    # —— 股市 ——
    {"name": "标普500",          "cat": "equity",    "syms": ["^GSPC"]},
    {"name": "日经225",          "cat": "equity",    "syms": [
        "^N225", {"sym": "EWJ", "note": "以日本 ETF（美元计）代理"}]},
    {"name": "德国DAX",          "cat": "equity",    "syms": ["^GDAXI"]},
    {"name": "恒生指数",         "cat": "equity",    "syms": ["^HSI"]},
    {"name": "富时新加坡海峡指数", "cat": "equity",   "syms": ["^STI"]},
    {"name": "沪深300",          "cat": "equity",    "syms": ["000300.SS"]},
    {"name": "新西兰NZ50",       "cat": "equity",    "syms": ["^NZ50"]},
    {"name": "印度SENSEX30",     "cat": "equity",    "syms": ["^BSESN"]},
    {"name": "澳洲标普200",      "cat": "equity",    "syms": ["^AXJO"]},
    {"name": "中证500",          "cat": "equity",    "syms": ["000905.SS"]},
    {"name": "欧洲STOXX600",     "cat": "equity",    "syms": ["^STOXX"]},
    {"name": "英国富时100",      "cat": "equity",    "syms": ["^FTSE"]},
    {"name": "法国CAC40",        "cat": "equity",    "syms": ["^FCHI"]},
    # 韩股 2025-26 处于历史级大牛市，年初至今/近一年涨幅本就极高，放宽护栏以如实呈现
    {"name": "韩国综合指数",     "cat": "equity", "caps": {"ytd": 300, "y1": 400},
     "syms": ["^KS11", {"sym": "^KS200", "note": "以 KOSPI 200 指数代理"},
              {"sym": "EWY", "note": "以韩国 ETF（美元计）代理"}]},
    {"name": "圣保罗IBOVESPA指数", "cat": "equity",  "syms": ["^BVSP"]},
    # —— 商品 ——（LME 现货 Yahoo 无免费源，以全球期货代理，涨跌方向高度一致）
    {"name": "COMEX黄金",        "cat": "commodity", "syms": ["GC=F"]},
    {"name": "COMEX白银",        "cat": "commodity", "syms": ["SI=F"]},
    {"name": "LME铝",            "cat": "commodity", "syms": ["ALI=F"], "note": "以期货铝代理 LME 铝"},
    {"name": "LME铜",            "cat": "commodity", "syms": ["HG=F"],  "note": "以 COMEX 铜代理 LME 铜"},
    {"name": "NYMEX WTI原油",    "cat": "commodity", "syms": ["CL=F"]},
    {"name": "ICE布油",          "cat": "commodity", "syms": ["BZ=F"]},
    # —— 外汇 ——（涨跌幅即各汇率自身变动，与示例图口径一致）
    {"name": "美元兑日元",       "cat": "fx",        "syms": ["USDJPY=X", "JPY=X"]},
    {"name": "美元指数",         "cat": "fx",        "syms": ["DX-Y.NYB", "DX=F"]},
    {"name": "美元兑人民币",     "cat": "fx",        "syms": ["USDCNY=X", "CNY=X"]},
    {"name": "英镑兑美元",       "cat": "fx",        "syms": ["GBPUSD=X"]},
    {"name": "欧元兑美元",       "cat": "fx",        "syms": ["EURUSD=X"]},
    {"name": "澳元兑美元",       "cat": "fx",        "syms": ["AUDUSD=X"]},
    # —— 债券 ——（中债总财富指数无免费日更源，以国债 ETF 代理）
    {"name": "中国国债",         "cat": "bond",      "syms": ["511260.SS", "511010.SS", "511090.SS"],
     "note": "以国债 ETF 代理（非中债-国债总财富指数）"},
]

YF_HOSTS = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
# Yahoo 对非浏览器 UA 容易返回 429，这里伪装成浏览器
YF_HEADERS = {"User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                             "AppleWebKit/537.36 (KHTML, like Gecko) "
                             "Chrome/123.0 Safari/537.36")}


def fetch_series(symbol, rng="1y"):
    """Yahoo 图表接口（requests + 硬超时）：返回按日期升序的 [(YYYY-MM-DD, close), ...]。"""
    sym = requests.utils.quote(symbol)
    last_err = ValueError("无可用数据")
    for host in YF_HOSTS:                 # 主备双域名，单个超时 12s
        url = f"https://{host}/v8/finance/chart/{sym}?range={rng}&interval=1d"
        try:
            r = requests.get(url, headers=YF_HEADERS, timeout=12)
            r.raise_for_status()
            res = r.json()["chart"]["result"][0]
            ts = res["timestamp"]
            closes = res["indicators"]["quote"][0]["close"]
            pts = [(time.strftime("%Y-%m-%d", time.gmtime(t)), float(c))
                   for t, c in zip(ts, closes) if c is not None]
            if len(pts) < 2:
                raise ValueError("行情数据点不足")
            return pts
        except Exception as e:
            last_err = e
    raise last_err


def pct(cur, base):
    """涨跌幅（%），保留两位小数；base 缺失或为 0 时返回 None。"""
    if not base:
        return None
    return round((cur / base - 1.0) * 100, 2)


def close_on_or_before(pts, target_date):
    """pts 按日期升序；返回 date <= target_date 的最后一个收盘价，没有则 None。"""
    chosen = None
    for d, c in pts:
        if d <= target_date:
            chosen = c
        else:
            break
    return chosen


def compute_returns(pts):
    """由日线序列算出各周期涨跌幅，并返回 (returns, 数据日期, 最新价)。"""
    last_date, last = pts[-1][0], pts[-1][1]
    ld = datetime.strptime(last_date, "%Y-%m-%d").date()
    returns = {
        "d1":  pct(last, pts[-2][1]),                                              # 对前一交易日
        "w1":  pct(last, close_on_or_before(pts, str(ld - timedelta(days=7)))),    # 近一周
        "m1":  pct(last, close_on_or_before(pts, str(ld - timedelta(days=30)))),   # 近一月
        "ytd": pct(last, close_on_or_before(pts, f"{ld.year - 1}-12-31")),         # 上年末收盘起算
        "y1":  pct(last, pts[0][1]),                                               # 序列最早点（≈ 一年前）
    }
    return returns, last_date, round(last, 4)


# —— 异常值护栏 ——
# 这 28 个标的都是宽基指数 / 主要商品 / 货币 / 国债，正常情况下不会出现下列量级的涨跌幅。
# 一旦某代码返回超过下列上限的涨跌幅，基本可判定为数据源（Yahoo）对该代码的脏数据/口径异常，
# 据此先尝试下一个候选代码；若所有候选都越界，则隐藏越界的周期、只保留正常周期（并标注 suspect）。
SANE_CAPS = {"d1": 25, "w1": 40, "m1": 60, "ytd": 100, "y1": 150}


def breached_periods(returns, caps=SANE_CAPS):
    """返回涨跌幅超出（该标的）合理上限的周期 key 列表（空列表表示通过护栏）。"""
    return [k for k, cap in caps.items()
            if returns.get(k) is not None and abs(returns[k]) > cap]


def _first_sym(a):
    """取标的第一个候选代码（候选可为字符串或 {sym,note} 字典）。"""
    c = a["syms"][0]
    return c["sym"] if isinstance(c, dict) else c


def load_prev():
    """读取上次的 data.json，按标的名建索引，用于失败时兜底沿用。"""
    try:
        with open(OUT_PATH, encoding="utf-8") as f:
            prev = json.load(f)
        return {a["name"]: a for a in prev.get("assets", [])}
    except Exception:
        return {}


def fetch_bdi():
    """波罗的海干散货指数（BDI，真实点位）：取自 CNBC 行情接口（symbol .BADI，免密钥、机房可达）。
    单独存到 data['bdi']（不进 assets，避免影响大类资产收益率页面），供首页行情带读取。"""
    url = ("https://quote.cnbc.com/quote-html-webservice/restQuote/symbolType/symbol"
           "?symbols=.BADI&requestMethod=itv&noform=1&partnerId=2&fund=1&exthrs=1&output=json")
    try:
        r = requests.get(url, headers=YF_HEADERS, timeout=12)
        r.raise_for_status()
        q = r.json()["FormattedQuoteResult"]["FormattedQuote"][0]
        last = float(str(q.get("last", "")).replace(",", ""))
        raw_pct = str(q.get("change_pct", "")).replace("%", "").replace(",", "").strip()
        raw_chg = str(q.get("change", "")).replace(",", "").strip()
        cp = None
        try:
            cp = abs(float(raw_pct))
            if raw_chg.startswith("-") or raw_pct.startswith("-"):
                cp = -cp
        except Exception:
            cp = None
        if last > 0:
            print(f"[OK] BDI .BADI = {last} ({cp}%)")
            return {"price": round(last, 2), "changePct": cp,
                    "asOf": (str(q.get("last_time", ""))[:10] or None), "symbol": ".BADI", "source": "CNBC"}
    except Exception as e:
        print(f"[..] BDI(.BADI/CNBC) 取数失败：{str(e)[:60]}")
    return None


def prev_bdi():
    """上次 data.json 里的 bdi（CNBC 本轮失败时兜底沿用）。"""
    try:
        with open(OUT_PATH, encoding="utf-8") as f:
            return json.load(f).get("bdi")
    except Exception:
        return None


def build():
    prev = load_prev()
    assets_out, as_of, ok = [], "", 0

    for a in ASSETS:
        rec = {"name": a["name"], "category": a["cat"]}
        if a.get("note"):
            rec["note"] = a["note"]

        chosen = None        # 通过护栏的干净候选
        suspect = None       # 第一个越界候选（所有候选都越界时的兜底）
        caps = {**SANE_CAPS, **a.get("caps", {})}   # 支持按标的放宽/收紧护栏
        for cand in a["syms"]:
            sym = cand["sym"] if isinstance(cand, dict) else cand
            note = cand.get("note") if isinstance(cand, dict) else None
            try:
                returns, last_date, price = compute_returns(fetch_series(sym))
            except Exception as e:
                print(f"[..] {a['name']} {sym} 取数失败：{str(e)[:50]}")
                continue
            bad = breached_periods(returns, caps)
            if not bad:
                chosen = (sym, note, returns, price, last_date)
                break
            print(f"[!!] {a['name']} {sym} 异常周期 {bad}（ytd={returns.get('ytd')}），改用下一个候选")
            if suspect is None:
                suspect = (sym, note, returns, price, last_date, bad)

        if chosen:
            sym, note, returns, price, last_date = chosen
            rec.update({"symbol": sym, "price": price, "returns": returns})
            if note:
                rec["note"] = note
            as_of = max(as_of, last_date); ok += 1
            print(f"[OK] {a['name']:<16} {sym:<12} ytd={returns['ytd']}")
        elif suspect:
            # 所有候选都越界：隐藏越界周期、只保留正常周期，并标注 suspect
            sym, note, returns, price, last_date, bad = suspect
            for k in bad:
                returns[k] = None
            rec.update({"symbol": sym, "price": price, "returns": returns, "suspect": True})
            rec["note"] = (note + "；" if note else "") + "部分周期数据异常，已隐藏"
            as_of = max(as_of, last_date); ok += 1
            print(f"[~~] {a['name']:<16} {sym:<12} 仅保留正常周期，隐藏 {bad}")
        else:
            # 本轮一个候选都没取到：优先沿用上次的有效值（标 stale），否则留空
            old = prev.get(a["name"])
            if old and old.get("returns", {}).get("ytd") is not None:
                rec.update({"symbol": old.get("symbol", _first_sym(a)),
                            "price": old.get("price"),
                            "returns": old["returns"], "stale": True})
                print(f"[==] {a['name']} 本轮失败，沿用上次数据（stale）")
            else:
                rec.update({"symbol": _first_sym(a), "price": None,
                            "returns": {p["key"]: None for p in PERIODS}})
                print(f"[XX] {a['name']} 全部候选失败，留空")
        assets_out.append(rec)
        time.sleep(0.4)   # 轻微限速，降低 Yahoo 429 概率

    if ok == 0:
        print("\n本轮 0 个标的成功（可能整源被限流），保留上次的 data.json，不覆盖。")
        return

    bdi = fetch_bdi() or prev_bdi()   # 真实 BDI 点位（CNBC .BADI），失败则沿用上次

    data = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asOf": as_of,
        "defaultPeriod": "ytd",
        "source": "Yahoo Finance",
        "note": ("数据来自 Yahoo Finance 公开行情，每日自动更新；涨跌幅为各标的自身价格变动。"
                 "LME 金属以全球期货代理、债券以国债 ETF 代理（详见各条备注）。仅供参考，非投资建议。"),
        "categories": CATEGORIES,
        "periods": PERIODS,
        "assets": assets_out,
        "bdi": bdi,
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"\n写入 {OUT_PATH}：{ok}/{len(ASSETS)} 个标的成功，as_of={as_of}")


if __name__ == "__main__":
    build()
