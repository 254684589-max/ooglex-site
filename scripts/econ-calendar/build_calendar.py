#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「全球经济日历」数据：从 Forex Factory 公开周历 JSON 抓取本周重要经济事件
（央行利率决议、CPI、非农、PMI、GDP… 含预测值 / 前值 / 实际值），整理成中文、
按时间排序，写入 apps/econ-calendar/data.json，供静态页面渲染。

- 数据源：Forex Factory 周历（https://nfs.faireconomy.media/ff_calendar_thisweek.json），
  免登录、无需 Key，覆盖主要货币区（美/欧/英/日/澳/纽/加/瑞/中…）。
- 纯 requests + 硬超时；取数失败 / 空数据则保留上次 data.json 不覆盖，绝不用空数据洗掉好数据。
- 货币代码映射为中文国家/地区与旗帜；常见事件名映射为中文，未命中保留英文原名；时间统一存 UTC。
由 .github/workflows/econ_calendar.yml 定时运行，并把 data.json 提交回仓库。
"""
import json
import os
from datetime import datetime, timezone

import requests

OUT_PATH = os.path.join("apps", "econ-calendar", "data.json")
FEED = "https://nfs.faireconomy.media/ff_calendar_thisweek.json"
# 该源会拒绝非浏览器 UA，给一个浏览器样式的 UA
HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; personal-site-econ-calendar/1.0)"}

# 货币代码 → (中文国家/地区, 旗帜 emoji)
CCY = {
    "USD": ("美国", "🇺🇸"), "EUR": ("欧元区", "🇪🇺"), "GBP": ("英国", "🇬🇧"),
    "JPY": ("日本", "🇯🇵"), "AUD": ("澳大利亚", "🇦🇺"), "NZD": ("新西兰", "🇳🇿"),
    "CAD": ("加拿大", "🇨🇦"), "CHF": ("瑞士", "🇨🇭"), "CNY": ("中国", "🇨🇳"),
    "HKD": ("香港", "🇭🇰"), "SGD": ("新加坡", "🇸🇬"), "KRW": ("韩国", "🇰🇷"),
    "INR": ("印度", "🇮🇳"), "BRL": ("巴西", "🇧🇷"), "MXN": ("墨西哥", "🇲🇽"),
    "ZAR": ("南非", "🇿🇦"), "RUB": ("俄罗斯", "🇷🇺"), "TRY": ("土耳其", "🇹🇷"),
    "SEK": ("瑞典", "🇸🇪"), "NOK": ("挪威", "🇳🇴"), "All": ("全球", "🌐"),
}

# 事件名关键词 → 中文（按顺序匹配第一个命中的子串；未命中保留英文原名）。
# 顺序很重要：更具体的写在前面（如 Core CPI 必须在 CPI 之前）。
TRANSLATE = [
    ("Non-Farm Employment Change", "非农就业人数变化"),
    ("Non-Farm Payrolls", "非农就业人数"),
    ("ADP Non-Farm", "ADP 就业人数"),
    ("Unemployment Claims", "申请失业金人数"),
    ("Unemployment Rate", "失业率"),
    ("Employment Change", "就业人数变化"),
    ("Average Hourly Earnings", "平均时薪"),
    ("Core CPI", "核心 CPI"),
    ("CPI", "CPI（消费者物价指数）"),
    ("Core PCE", "核心 PCE 物价指数"),
    ("PCE Price", "PCE 物价指数"),
    ("Core PPI", "核心 PPI"),
    ("PPI", "PPI（生产者物价指数）"),
    ("Core Retail Sales", "核心零售销售"),
    ("Retail Sales", "零售销售"),
    ("Advance GDP", "GDP 初值"),
    ("Prelim GDP", "GDP 修正值"),
    ("Final GDP", "GDP 终值"),
    ("GDP", "GDP（国内生产总值）"),
    ("FOMC Economic Projections", "FOMC 经济预测"),
    ("FOMC Statement", "FOMC 政策声明"),
    ("FOMC Meeting Minutes", "FOMC 会议纪要"),
    ("FOMC Press Conference", "美联储新闻发布会"),
    ("Federal Funds Rate", "美联储利率决议"),
    ("Official Bank Rate", "英央行利率决议"),
    ("Main Refinancing Rate", "欧央行利率决议"),
    ("Official Cash Rate", "新西兰联储利率决议"),
    ("Cash Rate", "澳央行利率决议"),
    ("Overnight Rate", "加央行利率决议"),
    ("Policy Rate", "央行利率决议"),
    ("Monetary Policy Statement", "货币政策声明"),
    ("Rate Statement", "利率声明"),
    ("Interest Rate Decision", "利率决议"),
    ("Press Conference", "新闻发布会"),
    ("Flash Manufacturing PMI", "制造业 PMI 初值"),
    ("Flash Services PMI", "服务业 PMI 初值"),
    ("ISM Manufacturing PMI", "ISM 制造业 PMI"),
    ("ISM Services PMI", "ISM 服务业 PMI"),
    ("Manufacturing PMI", "制造业 PMI"),
    ("Services PMI", "服务业 PMI"),
    ("Trade Balance", "贸易帐"),
    ("Consumer Confidence", "消费者信心指数"),
    ("Consumer Sentiment", "消费者信心指数"),
    ("Industrial Production", "工业产出"),
    ("Building Permits", "营建许可"),
    ("Housing Starts", "新屋开工"),
    ("Durable Goods Orders", "耐用品订单"),
    ("Crude Oil Inventories", "原油库存"),
    ("Natural Gas Storage", "天然气库存"),
    ("Empire State Manufacturing", "纽约联储制造业指数"),
    ("Existing Home Sales", "成屋销售"),
    ("Pending Home Sales", "成屋签约销售"),
    ("New Home Sales", "新屋销售"),
    ("Bank Holiday", "银行假日"),
    ("Tankan Non-Manufacturing", "日央行短观非制造业指数"),
    ("Tankan Manufacturing", "日央行短观制造业指数"),
    ("Nationwide HPI", "全国房价指数（Nationwide）"),
    ("S&P/CS Composite-20 HPI", "标普/CS 20 城房价指数"),
    ("ISM Manufacturing Prices", "ISM 制造业物价"),
    ("10-y Bond Auction", "10 年期国债拍卖"),
    ("Bond Auction", "国债拍卖"),
    ("Revised Business Investment", "企业投资修正值"),
    ("Business Investment", "企业投资"),
    ("French Consumer Spending", "法国消费支出"),
    ("Consumer Spending", "消费支出"),
    ("French Gov Budget Balance", "法国政府预算差额"),
    ("Gov Budget Balance", "政府预算差额"),
    ("German Import Prices", "德国进口物价"),
    ("Import Prices", "进口物价"),
    ("BRC Shop Price Index", "BRC 店铺价格指数"),
    ("Net Lending to Individuals", "对个人净贷款"),
    ("Private Sector Credit", "私营部门信贷"),
    ("Private Loans", "私人贷款"),
    ("M3 Money Supply", "M3 货币供应"),
    ("M4 Money Supply", "M4 货币供应"),
    ("Money Supply", "货币供应"),
    ("Monetary Base", "基础货币"),
    ("Monetary Policy Meeting Minutes", "货币政策会议纪要"),
    ("Mortgage Approvals", "抵押贷款批准数"),
    ("Building Approvals", "建筑许可"),
    ("Building Consents", "营建许可"),
    ("Construction Spending", "建筑支出"),
    ("Factory Orders", "工厂订单"),
    ("JOLTS Job Openings", "JOLTS 职位空缺"),
    ("Challenger Job Cuts", "挑战者企业裁员数"),
    ("Current Account", "经常账户"),
    ("Chicago PMI", "芝加哥 PMI"),
    ("KOF Economic Barometer", "KOF 经济晴雨表"),
    ("ANZ Business Confidence", "ANZ 商业信心指数"),
    ("Commodity Prices", "商品价格指数"),
    ("Omdia Total Vehicle Sales", "Omdia 汽车总销量"),
    ("Total Vehicle Sales", "汽车总销量"),
    ("API Weekly Statistical Bulletin", "API 原油库存周报"),
    ("BOE Credit Conditions Survey", "英央行信贷状况调查"),
    ("SNB Financial Stability Report", "瑞士央行金融稳定报告"),
    ("HPI", "房价指数"),
    ("PMI", "采购经理人指数 PMI"),
]


SPEAKS = [
    ("fed chair", "美联储主席讲话"), ("fomc", "美联储官员讲话"),
    ("boe gov", "英央行行长讲话"), ("mpc member", "英央行 MPC 委员讲话"), ("mpc ", "英央行 MPC 委员讲话"),
    ("ecb president", "欧央行行长讲话"), ("ecb ", "欧央行官员讲话"),
    ("rba gov", "澳央行行长讲话"), ("rba ", "澳央行官员讲话"),
    ("boc gov", "加央行行长讲话"), ("boc ", "加央行官员讲话"),
    ("snb ", "瑞士央行官员讲话"), ("buba", "德央行行长讲话"), ("bundesbank", "德央行行长讲话"),
    ("boj", "日央行官员讲话"), ("rbnz", "新西兰联储官员讲话"),
]


def _suffix(low):
    if low.endswith("y/y"):
        return " 同比"
    if low.endswith("m/m"):
        return " 环比"
    if low.endswith("q/q"):
        return " 季环比"
    return ""


def to_zh(title):
    low = title.lower()
    if "speaks" in low or "speech" in low:
        for kw, zh in SPEAKS:
            if kw in low:
                return zh
        return "央行官员讲话"
    for kw, zh in TRANSLATE:
        if kw.lower() in low:
            return zh + _suffix(low)
    return title


def norm_impact(s):
    s = (s or "").lower()
    if "high" in s:
        return "high"
    if "medium" in s:
        return "medium"
    if "holiday" in s:
        return "holiday"
    return "low"


def to_utc(s):
    """把 Forex Factory 的带时区 ISO 时间转成 UTC datetime。"""
    try:
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except Exception:
        return None


def clean(v):
    v = (v or "").strip()
    return v or None


def load_prev():
    try:
        with open(OUT_PATH, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def build():
    prev = load_prev()
    try:
        r = requests.get(FEED, headers=HEADERS, timeout=25)
        r.raise_for_status()
        raw = r.json()
    except Exception as e:
        print(f"[..] 取数失败：{str(e)[:90]}")
        if prev:
            print("保留上次 data.json，不覆盖。")
        return

    events = []
    for it in raw if isinstance(raw, list) else []:
        dt = to_utc(it.get("date"))
        title_en = (it.get("title") or "").strip()
        if not dt or not title_en:
            continue
        ccy = (it.get("country") or "").strip()
        zh, flag = CCY.get(ccy, (ccy or "全球", "🌐"))
        events.append({
            "ts": dt.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "ccy": ccy, "country": zh, "flag": flag,
            "title": to_zh(title_en), "titleEn": title_en,
            "impact": norm_impact(it.get("impact")),
            "forecast": clean(it.get("forecast")),
            "previous": clean(it.get("previous")),
            "actual": clean(it.get("actual")),
        })

    if not events:
        if prev:
            print("未取到事件，保留上次 data.json，不覆盖。")
        return

    events.sort(key=lambda e: e["ts"])
    days = sorted({e["ts"][:10] for e in events})
    highs = sum(1 for e in events if e["impact"] == "high")

    data = {
        "updatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asOf": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "source": "Forex Factory 经济日历",
        "weekOf": (days[0] + " ~ " + days[-1]) if days else "",
        "count": len(events),
        "highCount": highs,
        "events": events,
        "note": ("经济日历来自 Forex Factory 公开周历（免登录），含央行利率决议、CPI、非农、PMI、GDP 等"
                 "重要事件的预测值与前值；时间为 UTC，事件公布后会回填实际值。仅供参考，不构成投资建议。"),
    }
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"写入 {OUT_PATH}：{len(events)} 条事件（{highs} 条高影响），{len(days)} 天")


if __name__ == "__main__":
    build()
