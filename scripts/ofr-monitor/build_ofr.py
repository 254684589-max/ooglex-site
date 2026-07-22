#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「美国金融风险监测」数据：抓取美国财政部金融研究办公室（OFR）公开数据，覆盖其
「活动监视器」页面的五大监测工具，写入 apps/ofr-monitor/data.json 供静态页面渲染。

五大监测（对应 https://www.financialresearch.gov/monitoring-tools/）：
  1. 金融压力指数 (FSI)        每日   ← www.financialresearch.gov/.../fsi.csv（CSV）
  2. 短期融资监测 (SOFR 等)    每日   ← STFM API fnyr 数据集：FNYR-SOFR-A / FNYR-EFFR-A / FNYR-SOFR_UV-A
  3. 货币市场基金 (MMF 规模)   每月   ← STFM API mmf 数据集：MMF-MMF_TOT-M（总规模）
  4. 对冲基金监测 (GAV/NAV)    每季   ← HFM API fpf 数据集：FPF-ALLQHF_GAV_SUM / _NAV_SUM
  5. 银行系统性风险监测        年度   ← 美联储核定的美国 G-SIB 附加资本（人工维护数据表）

设计原则（沿用本仓库 fear-greed 脚本约定）：
- 纯 requests + 硬超时，无需任何 API Key；
- 各来源各自独立 try/except，任一来源失败只影响该项，其余照常；
- 失败项回退到上一次 data.json 的对应值，绝不把半截/空数据覆盖上去；
- STFM/HFM 各序列改用「取整个数据集 + 确切助记符」精确定位（助记符经诊断脚本核对，见文首常量）。

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
    "bank": "https://www.financialresearch.gov/bank-systemic-risk-monitor/us-gsib-surcharges/",
}

# 美国 8 家 G-SIB 的系统性资本附加（%），衡量各行系统重要性 —— OFR 银行系统性风险监测
# 「U.S. G-SIB Surcharges」页所呈现的核心指标。该指标由美联储核定、约年度更新，且 OFR
# 未提供机器可读接口（仅交互图表），故此处以人工维护的权威数据表呈现。
# 当前为「适用 2025 年」一档：由美联储 2024Q4 依据 2023-12-31 系统性风险指标核定。
# 来源：Federal Reserve《Large Bank Capital Requirements》。美联储更新后，请同步修订下表与 GSIB_EFFECTIVE。
GSIB_EFFECTIVE = "2025"
US_GSIB_SURCHARGES = [
    {"bank": "JPMorgan Chase", "zh": "摩根大通", "surcharge": 4.5},
    {"bank": "Citigroup", "zh": "花旗集团", "surcharge": 3.5},
    {"bank": "Goldman Sachs", "zh": "高盛", "surcharge": 3.5},
    {"bank": "Bank of America", "zh": "美国银行", "surcharge": 3.0},
    {"bank": "Morgan Stanley", "zh": "摩根士丹利", "surcharge": 3.0},
    {"bank": "Wells Fargo", "zh": "富国银行", "surcharge": 1.5},
    {"bank": "Bank of New York Mellon", "zh": "纽约梅隆银行", "surcharge": 1.5},
    {"bank": "State Street", "zh": "道富银行", "surcharge": 1.0},
]


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


def dataset_roots(data):
    """STFM/HFM 数据集响应可能是 {助记符: 序列}，也可能外面再包一层。两种都试。"""
    roots = []
    if isinstance(data, dict):
        roots.append(data)
        for v in data.values():
            if isinstance(v, dict) and len(v) > 1:
                roots.append(v)
    return roots


def series_by_key(data, key):
    """按确切助记符取序列的 [日期, 数值] 列表；取不到返回 None。"""
    for root in dataset_roots(data):
        if isinstance(root, dict) and key in root:
            pairs = deep_pairs(root[key])
            if pairs:
                return pairs
    return None


def latest(pairs):
    d, v = pairs[-1]
    return d, float(v)


def prior(pairs, n):
    return float(pairs[-1 - n][1]) if len(pairs) > n else None


# 确切助记符（由 diag 打印的真实数据集结构确认；比关键词启发式稳）
FNYR_SOFR = "FNYR-SOFR-A"        # SOFR 隔夜担保融资利率（volume-weighted median）
FNYR_EFFR = "FNYR-EFFR-A"        # EFFR 有效联邦基金利率
FNYR_SOFR_VOL = "FNYR-SOFR_UV-A"  # SOFR 成交量（美元）
MMF_TOTAL = "MMF-MMF_TOT-M"       # 货币市场基金总规模（美元）
FPF_GAV = "FPF-ALLQHF_GAV_SUM"    # 合格对冲基金 总资产 GAV（美元）
FPF_NAV = "FPF-ALLQHF_NAV_SUM"    # 合格对冲基金 净资产 NAV（美元）


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

    def rate(key):
        p = series_by_key(data, key)
        if not p:
            return None
        d, v = latest(p)
        out["asOf"] = out["asOf"] or d
        return {"value": round(v, 2), "change": None if prior(p, 1) is None else round(v - prior(p, 1), 2)}

    sofr = rate(FNYR_SOFR)
    if sofr:
        out["sofr"] = sofr
    effr = rate(FNYR_EFFR)
    if effr:
        out["effr"] = effr
    vol = series_by_key(data, FNYR_SOFR_VOL)
    if vol:
        d, v = latest(vol)
        out["sofrVol"] = round(to_trillions(v), 3)
        out["asOf"] = out["asOf"] or d
    if "sofr" not in out and "effr" not in out:
        raise ValueError("fnyr 未取到 %s / %s" % (FNYR_SOFR, FNYR_EFFR))
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
    p = series_by_key(data, MMF_TOTAL)
    if not p:
        raise ValueError("mmf 未取到总规模序列 %s" % MMF_TOTAL)
    d, v = latest(p)
    prev_month = prior(p, 1)
    return {
        "total": round(to_trillions(v), 3),
        "change": None if prev_month is None else round(to_trillions(v) - to_trillions(prev_month), 3),
        "asOf": d,
        "url": LINKS["mmf"],
    }


# ── 4. 对冲基金监测（季度，取自 Hedge Fund Monitor API 的 fpf/Form PF 数据集）──────
def build_hedge():
    data = get_json(STFM_HF + "/series/dataset?dataset=fpf")
    out = {"note": "季度", "url": LINKS["hedge"]}

    def total(key):
        p = series_by_key(data, key)
        if not p:
            return None
        d, v = latest(p)
        out["asOf"] = out.get("asOf") or d
        return round(to_trillions(v), 2)

    gav = total(FPF_GAV)
    nav = total(FPF_NAV)
    if gav:
        out["gav"] = gav
    if nav:
        out["nav"] = nav
    # 总杠杆 = 总资产 / 净资产（合格对冲基金口径），比匹配单条杠杆序列更稳定
    if gav and nav:
        out["leverage"] = round(gav / nav, 2)
    if not (gav or nav):
        raise ValueError("fpf 未取到 GAV/NAV（%s / %s）" % (FPF_GAV, FPF_NAV))
    return out


# ── 5. 银行系统性风险监测（美国 G-SIB 系统性资本附加，约年度更新）─────────────────
# BSRM 无公开 REST 接口，此处呈现其核心指标「美国 G-SIB 附加资本」——权威、公开、变动
# 缓慢（美联储约年度核定）。以 US_GSIB_SURCHARGES 人工维护数据表输出，附生效年份与来源。
def build_bank():
    return {
        "note": "年度核定",
        "asOf": GSIB_EFFECTIVE,
        "effective": "适用 " + GSIB_EFFECTIVE + " 年 · 美联储据 2023 年末数据核定",
        "url": LINKS["bank"],
        "gsibs": [dict(x) for x in US_GSIB_SURCHARGES],
    }


# 抓取失败时的「前往 OFR」直达兜底卡片（供对冲基金等使用）
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
        "bank": build_bank(),
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
