#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""股票池与行业归类。

复用仓库里已经在每日维护的 ``apps/companies/data.json``（Yahoo Finance，
全球市值前 500），取其中的美国上市公司作为默认股票池，不新增数据源。

**已知偏差，必须随结论一起披露**：这是“今天”的市值前列名单。用它回测过去，
模型等于事先知道了哪些公司活下来并变大——幸存者偏差 + 前视选择偏差。
它会系统性抬高全部回测收益，且对动量因子的抬高尤其严重（今天的大公司
正是过去涨得最多的那批）。因此 V1 回测只能用来**否决坏模型**，
不能用来**证明好模型**。修掉它需要 point-in-time 成分股历史，属于 V2。
"""

import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COMPANIES_PATH = os.path.join(ROOT, "apps", "companies", "data.json")

# 把源数据里的长尾行业标签归并成 11 个可用于行业内排名的桶。
# 只有 6 个样本的“机器人”行业做不出有意义的行业内分位。
SECTOR_MAP = {
    "科技": "科技", "软件": "科技", "人工智能": "科技", "数据与AI": "科技",
    "数据中心": "科技", "AI数据": "科技", "数据存储": "科技", "游戏": "科技",
    "金融": "金融", "支付": "金融", "金融科技": "金融", "保险经纪": "金融",
    "加密货币": "金融",
    "工业": "工业", "国防科技": "工业", "机器人": "工业",
    "可选消费": "可选消费", "自动驾驶": "可选消费", "电商": "可选消费",
    "品牌授权": "可选消费", "消费品": "可选消费",
    "必需消费": "必需消费", "食品": "必需消费",
    "医疗健康": "医疗健康", "公用事业": "公用事业", "能源": "能源",
    "房地产": "房地产", "通信服务": "通信服务", "原材料": "原材料",
}
UNKNOWN_SECTOR = "其他"


def normalize_sector(raw):
    return SECTOR_MAP.get((raw or "").strip(), UNKNOWN_SECTOR)


def load_universe(path=COMPANIES_PATH, country="美国", limit=None):
    """读出 (成分列表, 来源元数据)。成分为 {symbol, name, sector}。"""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    members, seen = [], set()
    for row in data.get("companies") or []:
        symbol = (row.get("symbol") or "").strip()
        if not symbol or symbol in seen:
            continue
        if country and row.get("country") != country:
            continue
        seen.add(symbol)
        members.append({
            "symbol": symbol,
            "name": row.get("name") or row.get("nameEn") or symbol,
            "sector": normalize_sector(row.get("sector")),
        })
        if limit and len(members) >= limit:
            break

    meta = {
        "source": data.get("source") or "Yahoo Finance",
        "sourceFile": os.path.relpath(path, ROOT),
        "asOf": data.get("asOf"),
        "updatedAt": data.get("updatedAt"),
        "count": len(members),
        "pointInTime": False,
        "survivorshipBias": ("股票池取自当日市值榜，含幸存者偏差与前视选择偏差；"
                             "回测结论只可用于否决模型，不可用于证明模型"),
    }
    return members, meta


def load_symbols_file(path):
    """从纯文本文件读股票池，每行 ``SYMBOL`` 或 ``SYMBOL,行业``。"""
    members = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = [p.strip() for p in line.split(",")]
            symbol = parts[0].upper()
            sector = normalize_sector(parts[1]) if len(parts) > 1 else UNKNOWN_SECTOR
            members.append({"symbol": symbol, "name": symbol, "sector": sector})
    return members
