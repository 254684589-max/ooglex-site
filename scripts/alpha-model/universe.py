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

# GICS 英文行业名 → 与 SECTOR_MAP 相同的 11 个中文桶。
# PIT 成分表来自维基百科，用的是 GICS 官方英文名。
GICS_MAP = {
    "information technology": "科技",
    "financials": "金融",
    "health care": "医疗健康",
    "consumer discretionary": "可选消费",
    "consumer staples": "必需消费",
    "industrials": "工业",
    "energy": "能源",
    "utilities": "公用事业",
    "real estate": "房地产",
    "materials": "原材料",
    "communication services": "通信服务",
    "telecommunication services": "通信服务",
}


# 市值榜里含未上市公司（Anthropic、OpenAI、Stripe、Waymo…），它们的代码位是
# 占位符而不是真实 ticker。不滤掉会白抓一次并报出莫名其妙的“取数失败：—”。
PLACEHOLDER_SYMBOLS = {"—", "–", "-", "", "N/A", "NA", "—/—"}


def normalize_sector(raw):
    """中文与 GICS 英文都能归到同一套 11 个桶，两个数据源才可互换。"""
    text = (raw or "").strip()
    if text in SECTOR_MAP:
        return SECTOR_MAP[text]
    return GICS_MAP.get(text.lower(), UNKNOWN_SECTOR)


def is_tradeable_symbol(symbol):
    """判断是不是可交易的美股代码。

    真实 ticker 只由字母、点、连字符组成（BRK-B、BF.B）。占位符与含中文、
    空格等字符的条目一律排除——它们进不了行情接口，只会变成噪声。
    """
    symbol = (symbol or "").strip()
    if not symbol or symbol in PLACEHOLDER_SYMBOLS:
        return False
    if len(symbol) > 8:
        return False
    return all(c.isascii() and (c.isalnum() or c in ".-") for c in symbol) \
        and any(c.isalpha() for c in symbol)


def load_universe(path=COMPANIES_PATH, country="美国", limit=None):
    """读出 (成分列表, 来源元数据)。成分为 {symbol, name, sector}。"""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    members, seen, skipped = [], set(), 0
    for row in data.get("companies") or []:
        symbol = (row.get("symbol") or "").strip()
        if country and row.get("country") != country:
            continue
        if not is_tradeable_symbol(symbol):
            skipped += 1          # 未上市公司，不是抓取失败
            continue
        if symbol in seen:
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
        "skippedNonTradeable": skipped,
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


def load_pit_universe(path=None):
    """加载 point-in-time 成分股。

    返回 (成分并集, 快照, 元数据)。成分并集是**所有曾经出现过的代码**——
    取数必须覆盖它，否则那些后来被踢出指数的公司在历史日期上依然缺失，
    幸存者偏差根本没修掉。这是本次改动最容易做错的一步。

    文件不存在返回 (None, None, None)，调用方回退到静态股票池。
    """
    from pit_universe import DEFAULT_PATH, load as _load
    snapshots, sectors, meta = _load(path or DEFAULT_PATH)
    if not snapshots:
        return None, None, None

    union = set()
    for _, members in snapshots:
        union |= members

    members = [{"symbol": sym,
                "name": sym,
                "sector": normalize_sector(sectors.get(sym))}
               for sym in sorted(union)]
    meta = {**(meta or {}), "count": len(members),
            "unionOfAllHistoricalMembers": len(union),
            "survivorshipBias": ("已使用 point-in-time 成分股；"
                                 "每个横截面日只用当时在册的公司，"
                                 "被踢出指数的公司在其在册期间照常参与")}
    return members, snapshots, meta
