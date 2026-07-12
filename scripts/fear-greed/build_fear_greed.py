#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「市场恐慌与贪婪指数」数据：抓取 CNN Fear & Greed Index 公开 JSON 接口，
提取当前读数、参考点（上一收盘 / 一周前 / 一月前 / 一年前）、7 个驱动指标与历史曲线，
写入 apps/fear-greed/data.json，供静态页面读取渲染。

- 数据源：CNN Business 恐慌与贪婪指数（production.dataviz.cnn.io），需带浏览器 UA，无需 API Key；
- 纯 requests + 硬超时；整源失败则保留上次 data.json 不覆盖；
- 0=极度恐惧 … 100=极度贪婪；评级缺失时按分数阈值推导。
由 .github/workflows/fear_greed.yml 每日定时运行，并把更新后的 data.json 提交回仓库。
"""
import json
import os
import time
from datetime import datetime, timezone

import requests

OUT_PATH = os.path.join("apps", "fear-greed", "data.json")
API = "https://production.dataviz.cnn.io/index/fearandgreed/graphdata"
HEADERS = {
    "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                   "(KHTML, like Gecko) Chrome/123.0 Safari/537.36"),
    "Accept": "application/json",
}

# CNN 的 7 个驱动指标：接口 key / 中文名 / 简述
INDICATORS = [
    ("market_momentum_sp500", "市场动能", "标普500 相对125日均线"),
    ("stock_price_strength", "股价强度", "创52周新高 vs 新低个股"),
    ("stock_price_breadth", "股价广度", "麦克莱伦成交量总和指数"),
    ("put_call_options", "看跌/看涨期权", "5日 Put/Call 比率"),
    ("market_volatility_vix", "市场波动", "VIX 及其50日均线"),
    ("safe_haven_demand", "避险需求", "股票 vs 国债 20日收益差"),
    ("junk_bond_demand", "垃圾债需求", "投资级 vs 垃圾债收益利差"),
]

RATING_ZH = {"extreme fear": "极度恐惧", "fear": "恐惧", "neutral": "中性",
             "greed": "贪婪", "extreme greed": "极度贪婪"}


def rating_from_score(s):
    if s is None:
        return None
    if s < 25:
        return "extreme fear"
    if s < 45:
        return "fear"
    if s < 55:
        return "neutral"
    if s < 75:
        return "greed"
    return "extreme greed"


def pack(score, rating=None):
    """把分数（+可选评级）打包为 {score,rating,ratingZh}；分数缺失返回 None。"""
    if score is None:
        return None
    try:
        score = round(float(score))
    except (TypeError, ValueError):
        return None
    r = (rating or rating_from_score(score) or "").lower()
    return {"score": score, "rating": r, "ratingZh": RATING_ZH.get(r, "")}


def fetch():
    r = requests.get(API, headers=HEADERS, timeout=20)
    r.raise_for_status()
    return r.json()


def load_prev():
    try:
        with open(OUT_PATH, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def build():
    prev_file = load_prev()
    try:
        d = fetch()
    except Exception as e:
        print(f"CNN 抓取失败：{str(e)[:120]}")
        if prev_file:
            print("保留上次的 data.json，不覆盖。")
        return

    fg = d.get("fear_and_greed", {}) or {}
    cur = pack(fg.get("score"), fg.get("rating"))
    if not cur:
        print("无当前读数，跳过（不覆盖）。")
        return

    refs = {
        "now": cur,
        "close": pack(fg.get("previous_close")),
        "week": pack(fg.get("previous_1_week")),
        "month": pack(fg.get("previous_1_month")),
        "year": pack(fg.get("previous_1_year")),
    }

    inds = []
    for key, zh, desc in INDICATORS:
        o = d.get(key) or {}
        p = pack(o.get("score"), o.get("rating"))
        if p:
            p.update({"key": key, "name": zh, "desc": desc})
            inds.append(p)

    # 历史曲线：取最近约一年，降采样到 ~80 点，保持 data.json 精简
    hist = []
    data = ((d.get("fear_and_greed_historical") or {}).get("data")) or []
    if data:
        cutoff = time.time() * 1000 - 370 * 86400 * 1000
        recent = [pt for pt in data if pt.get("x", 0) >= cutoff] or data[-260:]
        step = max(1, len(recent) // 80)
        for pt in recent[::step]:
            try:
                t = datetime.fromtimestamp(pt["x"] / 1000, tz=timezone.utc).strftime("%Y-%m-%d")
                hist.append({"t": t, "v": round(float(pt["y"]))})
            except Exception:
                continue

    out = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asOf": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "source": "CNN Business Fear & Greed Index",
        "score": cur["score"], "rating": cur["rating"], "ratingZh": cur["ratingZh"],
        "refs": refs, "indicators": inds, "history": hist,
        "note": ("数据来自 CNN 恐慌与贪婪指数：0 = 极度恐惧，100 = 极度贪婪，"
                 "由 7 个市场情绪指标综合而成，每日自动更新。仅供参考，不构成建议。"),
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"写入 {OUT_PATH}：score={cur['score']} {cur['rating']}，"
          f"指标 {len(inds)} 个，历史 {len(hist)} 点")


if __name__ == "__main__":
    build()
