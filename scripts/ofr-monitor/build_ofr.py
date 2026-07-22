#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「美国金融风险监测」数据：抓取美国财政部金融研究办公室（OFR）公开数据，覆盖其
「活动监视器」页面的五大监测工具，写入 apps/ofr-monitor/data.json 供静态页面渲染。

五大监测（对应 https://www.financialresearch.gov/monitoring-tools/）：
  1. 金融压力指数 (FSI)        每日   ← www.financialresearch.gov/.../fsi.csv（CSV，最稳）
  2. 短期融资监测 (SOFR 等)    每日   ← STFM REST API 的 fnyr 数据集（纽约联储参考利率）
  3. 货币市场基金 (MMF 规模)   每月   ← STFM REST API 的 mmf 数据集
  4. 对冲基金监测              月/季  ← 季度报告，暂以直达卡片呈现（见文末 TODO）
  5. 银行系统性风险监测        每季   ← 季度报告，暂以直达卡片呈现（见文末 TODO）

设计原则（沿用本仓库 fear-greed 脚本约定）：
- 纯 requests + 硬超时，无需任何 API Key；
- 五个来源各自独立 try/except，任一来源失败只影响该项，其余照常；
- 失败项回退到上一次 data.json 的对应值，绝不把半截/空数据覆盖上去；
- STFM 各序列的助记符（mnemonic）无法在本机联网核对，脚本改用「取整个数据集 + 关键词/量级
  启发式匹配」的方式自愈式定位序列，首跑后若某项仍为空，按 SOURCES 注释微调关键词即可。

由 .github/workflows/ofr_monitor.yml 每日定时运行，并把更新后的 data.json 提交回仓库。
数据来源：U.S. Office of Financial Research（OFR），公开数据，仅供参考。
"""
import csv
import io
import json
import os
from datetime import datetime, timezone

import requests

OUT_PATH = os.path.join("apps", "ofr-monitor", "data.json")

FSI_CSV = "https://www.financialresearch.gov/financial-stress-index/data/fsi.csv"
STFM = "https://data.financialresearch.gov/v1"          # 短期融资监测 API
STFM_HF = "https://data.financialresearch.gov/hf/v1"    # 对冲基金监测 API（结构与 STFM 一致）
HEADERS = {
    "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                   "(KHTML, like Gecko) Chrome/123.0 Safari/537.36"),
    "Accept": "application/json, text/csv, */*",
}
TIMEOUT = 25

# FSI CSV 里五个分项与三个地区的列名 → 中文标签（列名大小写/空格做归一化后匹配）
FSI_CATEGORIES = [
    ("credit", "信用"),
    ("equity valuation", "股票估值"),
    ("funding", "融资"),
    ("safe assets", "避险资产"),
    ("volatility", "波动率"),
]
FSI_REGIONS = [("united states", "us"), ("other advanced economies", "oae"),
               ("emerging markets", "em")]

# 各监测工具在 OFR 官网的详情页，用于卡片「前往 OFR」直达
LINKS = {
    "fsi": "https://www.financialresearch.gov/financial-stress-index/",
    "funding": "https://www.financialresearch.gov/short-term-funding-monitor/",
    "mmf": "https://www.financialresearch.gov/money-market-funds/",
    "hedge": "https://www.financialresearch.gov/hedge-fund-monitor/",
    "bank": "https://www.financialresearch.gov/bank-systemic-risk-monitor/",
}


# ── 通用工具 ──────────────────────────────────────────────────────────────
def isnum(v):
    try:
        return v is not None and not isinstance(v, bool) and not (float(v) != float(v))
    except (TypeError, ValueError):
        return False


def norm(s):
    return " ".join(str(s).lower().replace("_", " ").replace("-", " ").split())


def load_prev():
    try:
        with open(OUT_PATH, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def get_json(url):
    r = requests.get(url, headers=HEADERS, timeout=TIMEOUT)
    r.raise_for_status()
    return r.json()


def _is_pair(x):
    return (isinstance(x, (list, tuple)) and len(x) == 2
            and isinstance(x[0], str) and isnum(x[1]))


def deep_pairs(obj, best=None):
    """在任意嵌套 JSON 中找出最长的 [日期字符串, 数值] 列表（STFM 时间序列即长这样）。"""
    if isinstance(obj, list):
        if obj and all(_is_pair(x) for x in obj):
            if best is None or len(obj) > len(best):
                best = obj
        for it in obj:
            best = deep_pairs(it, best)
    elif isinstance(obj, dict):
        for v in obj.values():
            best = deep_pairs(v, best)
    return best


def collect_strings(obj, out):
    if isinstance(obj, str):
        out.append(obj)
    elif isinstance(obj, list):
        for it in obj:
            collect_strings(it, out)
    elif isinstance(obj, dict):
        for v in obj.values():
            collect_strings(v, out)


def dataset_roots(data):
    """STFM 数据集响应可能是 {助记符: 序列}，也可能外面再包一层。两种都试。"""
    roots = []
    if isinstance(data, dict):
        roots.append(data)
        for v in data.values():
            if isinstance(v, dict) and len(v) > 1:
                roots.append(v)
    return roots


def scan_dataset(data, include, exclude=()):
    """在数据集里按关键词匹配序列，返回 [(key, pairs)]；关键词同时对助记符键名与内嵌
    的元数据名称/描述做匹配，因此即使不知道确切助记符也能定位。"""
    inc = [norm(k) for k in include]
    exc = [norm(k) for k in exclude]
    seen, hits = set(), []
    for root in dataset_roots(data):
        for key, val in root.items():
            if not isinstance(val, (dict, list)) or key in seen:
                continue
            pairs = deep_pairs(val)
            if not pairs:
                continue
            strs = [key]
            collect_strings(val, strs)
            hay = norm(" ".join(strs))
            if all(k in hay for k in inc) and not any(x in hay for x in exc):
                seen.add(key)
                hits.append((key, pairs))
    return hits


def latest(pairs):
    d, v = pairs[-1]
    return d, float(v)


def prior(pairs, n):
    return float(pairs[-1 - n][1]) if len(pairs) > n else None


def spark(pairs, n=180):
    return [round(float(v), 3) for _, v in pairs[-n:]]


# ── 1. 金融压力指数 FSI（每日）─────────────────────────────────────────────
def build_fsi():
    r = requests.get(FSI_CSV, headers=HEADERS, timeout=TIMEOUT)
    r.raise_for_status()
    rows = list(csv.reader(io.StringIO(r.text)))
    if len(rows) < 2:
        raise ValueError("FSI CSV 为空")
    header = [norm(h) for h in rows[0]]

    def col(name):
        n = norm(name)
        for i, h in enumerate(header):
            if h == n:
                return i
        for i, h in enumerate(header):
            if n in h:
                return i
        return -1

    date_i = col("date")
    fsi_i = col("ofr fsi")
    if fsi_i < 0:
        fsi_i = col("fsi")

    def cell(row, i):
        if i < 0 or i >= len(row):
            return None
        try:
            return float(row[i])
        except (TypeError, ValueError):
            return None

    data = [row for row in rows[1:] if row and cell(row, fsi_i) is not None]
    if not data:
        raise ValueError("FSI 无有效数值行")
    cur, prev = data[-1], (data[-2] if len(data) > 1 else data[-1])
    yr = data[-253] if len(data) > 253 else data[0]

    value = cell(cur, fsi_i)
    cats = []
    for name, zh in FSI_CATEGORIES:
        v = cell(cur, col(name))
        if v is not None:
            cats.append({"name": zh, "value": round(v, 2)})
    regions = {}
    for name, key in FSI_REGIONS:
        v = cell(cur, col(name))
        if v is not None:
            regions[key] = round(v, 2)

    series = [round(cell(row, fsi_i), 3) for row in data[-260:]
              if cell(row, fsi_i) is not None]
    return {
        "value": round(value, 2),
        "change": round(value - cell(prev, fsi_i), 2) if cell(prev, fsi_i) is not None else None,
        "yearAgo": round(cell(yr, fsi_i), 2) if cell(yr, fsi_i) is not None else None,
        "regions": regions,
        "categories": cats,
        "spark": series,
        "asOf": cur[date_i] if 0 <= date_i < len(cur) else None,
        "url": LINKS["fsi"],
    }


# ── 2. 短期融资监测：SOFR / EFFR / SOFR 成交量（每日，取自 fnyr 数据集）──────
def build_funding():
    data = get_json(STFM + "/series/dataset?dataset=fnyr")
    out = {"asOf": None, "url": LINKS["funding"]}

    def pick_rate(include, exclude=()):
        # 利率类：值域约 0~15；同名候选取助记符最短者（通常即基准利率而非分位数）
        cands = [(k, p) for k, p in scan_dataset(data, include, exclude)
                 if 0 <= latest(p)[1] <= 15]
        if not cands:
            return None
        cands.sort(key=lambda kp: len(kp[0]))
        k, p = cands[0]
        d, v = latest(p)
        out["asOf"] = out["asOf"] or d
        return {"value": round(v, 2), "change": None if prior(p, 1) is None else round(v - prior(p, 1), 2)}

    sofr = pick_rate(["sofr"], ["percentile", "pctl", "1st", "25th", "75th", "99th", "volume", "vol"])
    if sofr:
        out["sofr"] = sofr
    effr = pick_rate(["effr"]) or pick_rate(["effective", "federal", "funds"], ["percentile", "pctl"])
    if effr:
        out["effr"] = effr

    # SOFR 成交量：量级远大于利率，取带 volume/成交量 语义、且数值巨大的序列
    vol_hits = scan_dataset(data, ["sofr", "volume"]) or scan_dataset(data, ["sofr", "vol"])
    vol_hits = [(k, p) for k, p in vol_hits if latest(p)[1] > 1e4]
    if not vol_hits:
        vol_hits = [(k, p) for k, p in scan_dataset(data, ["sofr"]) if latest(p)[1] > 1e5]
    if vol_hits:
        vol_hits.sort(key=lambda kp: latest(kp[1])[1], reverse=True)
        d, v = latest(vol_hits[0][1])
        out["sofrVol"] = round(to_trillions(v), 3)
        out["asOf"] = out["asOf"] or d
    if "sofr" not in out and "effr" not in out:
        raise ValueError("fnyr 数据集未匹配到 SOFR/EFFR，需按 build_funding 注释调整关键词")
    return out


# ── 3. 货币市场基金规模 MMF（每月，取自 mmf 数据集）──────────────────────────
def to_trillions(v):
    """把未知单位（美元 / 百万 / 十亿）的规模统一折算为「万亿美元」。MMF 总规模约 6~7 万亿。"""
    v = float(v)
    if v >= 1e12:      # 以美元计
        return v / 1e12
    if v >= 1e6:       # 以百万计（6.5e6 百万 = 6.5 万亿）
        return v / 1e6
    if v >= 1e3:       # 以十亿计（6500 十亿 = 6.5 万亿）
        return v / 1e3
    return v           # 已是万亿


def build_mmf():
    data = get_json(STFM + "/series/dataset?dataset=mmf")
    # 总规模：优先匹配 total/assets/aum/outstanding，再退化为「数值最大的序列」（总规模量级最大）
    hits = (scan_dataset(data, ["total", "asset"]) or scan_dataset(data, ["total", "aum"])
            or scan_dataset(data, ["total", "outstanding"]) or scan_dataset(data, ["total"]))
    if not hits:
        # 兜底：全数据集里挑最新值最大的序列
        allhits = scan_dataset(data, [""])
        hits = sorted(allhits, key=lambda kp: latest(kp[1])[1], reverse=True)[:1]
    if not hits:
        raise ValueError("mmf 数据集未匹配到总规模序列")
    hits.sort(key=lambda kp: latest(kp[1])[1], reverse=True)
    k, p = hits[0]
    d, v = latest(p)
    prev_month = prior(p, 1)
    total = to_trillions(v)
    return {
        "total": round(total, 3),
        "change": None if prev_month is None else round(to_trillions(v) - to_trillions(prev_month), 3),
        "asOf": d,
        "url": LINKS["mmf"],
    }


# ── 4. 对冲基金监测（季度，取自 Hedge Fund Monitor API 的 fpf/Form PF 数据集）──────
def build_hedge():
    data = get_json(STFM_HF + "/series/dataset?dataset=fpf")
    out = {"note": "季度", "url": LINKS["hedge"]}

    def pick_total(include, exclude=()):
        # 规模类（GAV/NAV）：量级大，取匹配到的最大序列并折算为万亿
        hits = [(k, p) for k, p in scan_dataset(data, include, exclude) if latest(p)[1] > 0]
        if not hits:
            return None
        hits.sort(key=lambda kp: latest(kp[1])[1], reverse=True)
        d, v = latest(hits[0][1])
        out["asOf"] = out.get("asOf") or d
        return round(to_trillions(v), 2)

    gav = pick_total(["gross", "asset"])
    nav = pick_total(["net", "asset"])
    if gav:
        out["gav"] = gav
    if nav:
        out["nav"] = nav
    # 杠杆倍数：小数值（约 1~10），取助记符最短的一条
    lev = [(k, p) for k, p in scan_dataset(data, ["leverage"]) if 0 < latest(p)[1] < 100]
    if lev:
        lev.sort(key=lambda kp: len(kp[0]))
        out["leverage"] = round(latest(lev[0][1])[1], 2)
    if not (gav or nav):
        raise ValueError("fpf 数据集未匹配到 GAV/NAV，需按 build_hedge 注释调整关键词")
    return out


# ── 5. 银行系统性风险监测（季度）──────────────────────────────────────────────
# OFR 银行系统性风险监测（BSRM）无公开 REST 接口，仅提供交互式图表与不定期静态文件
# （如 gsib-scores-chart/files/*.xlsx），无法稳定按序列抓取，故保留为「前往 OFR」直达卡片。
def build_report_card(key):
    return {"asOf": None, "note": "季度更新", "url": LINKS[key]}


# ── 汇总 ──────────────────────────────────────────────────────────────────
def main():
    prev = load_prev()
    # 上一份是示例数据时，失败来源不要沿用示例数值（否则会把示例当真实值展示），置空更诚实
    keep = {} if prev.get("demo") else prev
    now = datetime.now(timezone.utc)
    out = {
        "updatedAt": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asOf": now.strftime("%Y-%m-%d"),
        "source": "U.S. Office of Financial Research (OFR)",
        "fsi": keep.get("fsi"),
        "funding": keep.get("funding"),
        "mmf": keep.get("mmf"),
        "hedge": keep.get("hedge"),
        "bank": build_report_card("bank"),
    }

    for name, fn in (("fsi", build_fsi), ("funding", build_funding),
                     ("mmf", build_mmf), ("hedge", build_hedge)):
        try:
            out[name] = fn()
            print("[ok] %s" % name)
        except Exception as e:  # noqa: BLE001 — 单源失败不影响其余
            print("[skip] %s: %s（保留上次数据）" % (name, e))

    # 对冲基金取数失败且无历史值时，回退到「前往 OFR」直达卡片
    if not out.get("hedge"):
        out["hedge"] = build_report_card("hedge")

    fsi = out.get("fsi") or {}
    if fsi.get("asOf"):
        out["asOf"] = fsi["asOf"]

    hedge_live = (out.get("hedge") or {}).get("gav") or (out.get("hedge") or {}).get("nav")
    if not any([out.get("fsi"), out.get("funding"), out.get("mmf"), hedge_live]):
        # 数据源全灭且没有历史值：不覆盖已有文件，避免写入空壳
        if prev:
            print("全部数据源失败且已有历史文件，跳过写入")
            return
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print("已写入 " + OUT_PATH)


if __name__ == "__main__":
    main()
