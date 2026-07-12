#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「各国经济状况概览」数据：从世界银行公开 API 抓取多项宏观指标（按国家最新可得值），
再叠加一份央行基准利率（整理自公开资料），写入 apps/world-economy/data.json，
供静态页面以世界地图（choropleth）形态渲染。

- 数据源：World Bank Open Data API（免登录、无需 Key，权威、覆盖约 190 国，年度数据）；
  央行基准利率为整理值（主要经济体，定期更新）。
- 纯 requests + 硬超时；单指标失败不影响整体；整体不足则保留上次 data.json 不覆盖。
- 国家代码统一用 ISO-3166 alpha-2（与前端地图一致），过滤掉世界银行的地区聚合项。
由 .github/workflows/world_economy.yml 每日定时运行，并把 data.json 提交回仓库。
"""
import json
import os
import time
from datetime import datetime, timezone

import requests

OUT_PATH = os.path.join("apps", "world-economy", "data.json")
WB = "https://api.worldbank.org/v2/country/all/indicator/{ind}?format=json&mrnev=1&per_page=400"
HEADERS = {"User-Agent": "economy-map/1.0 (personal site data job)"}

# 有效 ISO2 国家集合（过滤世界银行的地区聚合项，如 1W/EU/OE 等）
ISO2 = set((
    "AD AE AF AG AL AM AO AR AT AU AZ BA BB BD BE BF BG BH BI BJ BN BO BR BS BT BW BY BZ "
    "CA CD CF CG CH CI CL CM CN CO CR CU CV CY CZ DE DJ DK DM DO DZ EC EE EG ER ES ET FI FJ "
    "FR GA GB GD GE GH GM GN GQ GR GT GW GY HN HR HT HU ID IE IL IN IQ IR IS IT JM JO JP KE "
    "KG KH KM KR KW KZ LA LB LC LK LR LS LT LU LV LY MA MD ME MG MK ML MM MN MR MT MU MV MW "
    "MX MY MZ NA NE NG NI NL NO NP NZ OM PA PE PG PH PK PL PT PY QA RO RS RU RW SA SB SC SD "
    "SE SG SI SK SL SN SO SR SS ST SV SY SZ TD TG TH TJ TL TM TN TR TT TW TZ UA UG US UY UZ "
    "VE VN VU YE ZA ZM ZW").split())

# 世界银行指标：key / 中文名 / 单位 / WB 代码 / 配色(低→高) / 说明
INDICATORS = [
    {"key": "cpi", "nameEn": "Inflation", "name": "通胀率",       "unit": "%",   "wb": "FP.CPI.TOTL.ZG",    "scale": ["#3a2a12", "#f4a83a"], "desc": "消费者价格指数同比"},
    {"key": "unemp", "nameEn": "Unemployment", "name": "失业率",       "unit": "%",   "wb": "SL.UEM.TOTL.ZS",    "scale": ["#241a3a", "#b69cf5"], "desc": "占劳动力比例（ILO 估算）"},
    {"key": "gdp", "nameEn": "GDP Growth", "name": "GDP增长",      "unit": "%",   "wb": "NY.GDP.MKTP.KD.ZG", "scale": ["#0b3a36", "#34d8c4"], "desc": "实际 GDP 同比增速"},
    {"key": "debt", "nameEn": "Gov Debt/GDP", "name": "政府债务/GDP", "unit": "%",   "wb": "GC.DOD.TOTL.GD.ZS", "scale": ["#3a1030", "#f0489a"], "desc": "中央政府债务占 GDP"},
    {"key": "gdppc", "nameEn": "GDP per Capita", "name": "人均GDP",      "unit": "美元", "wb": "NY.GDP.PCAP.CD",    "scale": ["#0e2a14", "#5fd07a"], "desc": "现价美元"},
    {"key": "cab", "nameEn": "Current Account/GDP", "name": "经常账户/GDP", "unit": "%",   "wb": "BN.CAB.XOKA.GD.ZS", "scale": ["#10243a", "#4aa3f0"], "desc": "经常账户余额占 GDP"},
    {"key": "life", "nameEn": "Life Expectancy", "name": "预期寿命",     "unit": "岁",  "wb": "SP.DYN.LE00.IN",    "scale": ["#0e2a2a", "#46d6c6"], "desc": "出生时预期寿命（年）"},
    {"key": "urban", "nameEn": "Urbanization", "name": "城镇化率",     "unit": "%",   "wb": "SP.URB.TOTL.IN.ZS", "scale": ["#161f3a", "#6c8cff"], "desc": "城镇人口占总人口比例"},
    {"key": "exp", "nameEn": "Exports/GDP", "name": "出口/GDP",     "unit": "%",   "wb": "NE.EXP.GNFS.ZS",    "scale": ["#0b2a1e", "#46d07a"], "desc": "货物与服务出口占 GDP"},
    {"key": "popgr", "nameEn": "Population Growth", "name": "人口增长",     "unit": "%",   "wb": "SP.POP.GROW",       "scale": ["#2a1838", "#c08cff"], "desc": "人口年增长率"},
    {"key": "save", "nameEn": "Savings/GDP", "name": "储蓄率/GDP",   "unit": "%",   "wb": "NY.GNS.ICTR.ZS",    "scale": ["#2a2410", "#e8c24a"], "desc": "国民总储蓄占 GDP"},
]

# 欧元区成员（共用 ECB 利率）
EURO = "DE FR IT ES NL BE AT PT IE FI GR SK SI LT LV EE LU CY MT HR".split()
ECB_RATE = 2.15
# 非欧元区主要经济体央行基准利率（整理自公开资料，ISO2 -> %）
POLICY_NON_EURO = {
    "US": 4.50, "GB": 4.25, "JP": 0.50, "CN": 3.00, "CA": 2.75, "AU": 3.85, "NZ": 3.25,
    "CH": 0.00, "SE": 2.00, "NO": 4.25, "DK": 1.85, "IN": 5.50, "BR": 15.00, "MX": 8.00,
    "RU": 20.00, "ZA": 7.25, "KR": 2.50, "ID": 5.50, "TR": 43.00, "SA": 5.00, "AE": 4.40,
    "TH": 1.50, "MY": 3.00, "PH": 5.00, "PL": 5.25, "CZ": 3.50, "HU": 6.50, "RO": 6.50,
    "IL": 4.50, "CL": 4.75, "CO": 9.25, "PE": 4.50, "AR": 29.00, "NG": 27.50, "EG": 24.00,
    "VN": 4.50, "TW": 2.00, "HK": 4.75, "SG": 2.50, "PK": 11.00, "BD": 10.00,
}
POLICY_ASOF = "2025年末整理"


def fetch_wb(ind):
    """世界银行：返回 ({ISO2: value}, 最新年份字符串)。"""
    r = requests.get(WB.format(ind=ind), headers=HEADERS, timeout=25)
    r.raise_for_status()
    js = r.json()
    rows = js[1] if isinstance(js, list) and len(js) > 1 else []
    vals, year = {}, ""
    for row in rows or []:
        c = (row.get("country") or {}).get("id")
        v = row.get("value")
        if c in ISO2 and v is not None:
            try:
                vals[c] = round(float(v), 2)
            except (TypeError, ValueError):
                continue
            if row.get("date"):
                year = max(year, row["date"])
    return vals, year


def build_policy():
    out = dict(POLICY_NON_EURO)
    for c in EURO:
        out[c] = ECB_RATE
    return out


def load_prev():
    try:
        with open(OUT_PATH, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def build():
    prev = load_prev()
    indicators = [{
        "key": "policy", "nameEn": "Policy Rate", "name": "央行基准利率", "unit": "%",
        "desc": "主要经济体央行政策利率（整理自公开资料）",
        "scale": ["#3a2410", "#f3b13d"], "year": POLICY_ASOF,
        "values": build_policy(), "source": "整理自公开资料",
    }]
    for spec in INDICATORS:
        try:
            vals, year = fetch_wb(spec["wb"])
            if vals:
                indicators.append({
                    "key": spec["key"], "name": spec["name"], "nameEn": spec.get("nameEn", ""), "unit": spec["unit"],
                    "desc": spec["desc"], "scale": spec["scale"],
                    "year": year, "values": vals, "source": "World Bank",
                })
                print(f"[OK] {spec['name']}：{len(vals)} 国，最新 {year}")
            else:
                print(f"[..] {spec['name']}：无数据")
        except Exception as e:
            print(f"[..] {spec['name']} 失败：{str(e)[:60]}")
        time.sleep(0.3)

    if len(indicators) < 2:    # 只有整理的利率、World Bank 全挂 → 不覆盖
        if prev:
            print("World Bank 数据不足，保留上次 data.json。")
            return

    data = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asOf": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "sources": ["World Bank Open Data", "央行基准利率：整理自公开资料"],
        "defaultKey": "policy",
        "indicators": indicators,
        "note": ("宏观指标来自世界银行公开数据（年度，取各国最新可得值，故年份可能不一）；"
                 "央行基准利率为整理自公开资料的主要经济体政策利率，定期更新。仅供参考，不构成建议。"),
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"写入 {OUT_PATH}：{len(indicators)} 个指标")


if __name__ == "__main__":
    build()
