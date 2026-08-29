#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验三条聚合行情管道的逐条来源与新鲜度契约。"""

import argparse
import json
from pathlib import Path

from market_data_quality import validate_data_quality


ROOT = Path(__file__).resolve().parents[1]
DATASETS = {
    "asset-tracker": (ROOT / "apps" / "asset-tracker" / "data.json", "assets"),
    "companies": (ROOT / "apps" / "companies" / "data.json", "companies"),
    "asset-ranking": (ROOT / "apps" / "asset-ranking" / "data.json", "assets"),
    "commodities": (ROOT / "apps" / "commodities" / "data.json", "series"),
    "bonds": (ROOT / "apps" / "bonds" / "data.json", "series"),
}


def require(condition, message, errors):
    if not condition:
        errors.append(message)


def validate_dataset(name):
    path, rows_key = DATASETS[name]
    if not path.exists():
        # 新管道首轮跑完之前它的数据文件还不存在，这不是校验失败——上线顺序本来就是
        # 「先合代码、再由工作流生成数据」。文件一旦存在，下面所有契约照常执行。
        print(f"{name}: SKIP · {path.relative_to(ROOT)} 尚未生成（首轮运行前属于正常状态）")
        return
    data = json.loads(path.read_text(encoding="utf-8"))
    rows = data.get(rows_key)
    errors = validate_data_quality(rows, data.get("dataQuality"))
    # 商品现货管道同时含日频、周频与月频序列，因此文件级频率是 mixed，逐条各自标注。
    # 商品现货与主权债两条管道都同时含多种频率，因此文件级频率是 mixed，逐条各自标注。
    allowed_frequency = (("daily", "irregular", "mixed") if name in ("commodities", "bonds")
                         else ("daily", "irregular"))
    require(data.get("frequency") in allowed_frequency, "文件级frequency无效", errors)
    require(data.get("status") in ("ok", "partial", "stale", "error"), "文件级status无效", errors)
    require(data.get("status") == (data.get("dataQuality") or {}).get("status"),
            "文件级status与逐条汇总不一致", errors)

    if name == "asset-tracker":
        # 清单条数由取数脚本的 ASSETS 决定（validate_finance_terminal.py 逐条比对），
        # 这里只守住「不得缩水」与「代码唯一」，避免清单扩容当天与数据文件互相卡住。
        require(len(rows) >= 28, f"跨资产条目数不得少于28，当前{len(rows)}", errors)
        require(len({row.get("symbol") for row in rows}) == len(rows),
                "跨资产代码必须唯一", errors)
        for row in rows:
            meta = row.get("dataMeta") or {}
            require(meta.get("source") == "Yahoo Finance", f"{row.get('name')}逐条来源不是Yahoo Finance", errors)
            require((meta.get("mode") == "fallback") == (row.get("stale") is True),
                    f"{row.get('name')}回退模式与stale字段不一致", errors)
            if row.get("suspect") is True:
                require(meta.get("status") == "partial", f"{row.get('name')}异常值未标记partial", errors)
            if row.get("proxy"):
                require("代理" in row["proxy"].get("note", "")
                        and "误差" in row["proxy"].get("note", ""),
                        f"{row.get('name')}代理说明未披露代理性质或误差", errors)

    if name == "bonds":
        # 这条管道的诚实边界同样全在「频率」上：除欧元区AAA曲线一条为日频外全是月频，
        # 月频绝不能被写成日频，涨跌必须是相对上一观测的基点变化而不是当日变动。
        require(len({row.get("id") for row in rows}) == len(rows), "主权债序列代码必须唯一", errors)
        daily_ids = {row.get("id") for row in rows if row.get("frequency") == "daily"}
        require(daily_ids <= {"ECB-EA-AAA-10Y"},
                f"只有欧元区AAA曲线可以是日频，多出：{sorted(daily_ids - {'ECB-EA-AAA-10Y'})}", errors)
        for row in rows:
            meta = row.get("dataMeta") or {}
            require(meta.get("source") in ("FRED / OECD Main Economic Indicators", "ECB Data Portal"),
                    f"{row.get('name')}逐条来源未登记", errors)
            require(row.get("frequency") in ("daily", "monthly"),
                    f"{row.get('name')}逐条频率无效：月频不得写成日频", errors)
            require(meta.get("frequency") == row.get("frequency"),
                    f"{row.get('name')}逐条频率与元数据不一致", errors)
            require(row.get("region") in ("americas", "europe", "asia", "oceania", "africa"),
                    f"{row.get('name')}地区未登记", errors)
            require(row.get("unit") == "年化收益率",
                    f"{row.get('name')}单位必须写明是年化收益率而不是债券价格", errors)
            require((meta.get("mode") == "fallback") == (row.get("stale") is True),
                    f"{row.get('name')}回退模式与stale字段不一致", errors)
            if meta.get("mode") == "market":
                require(row.get("previousAsOf"),
                        f"{row.get('name')}缺少上一观测日期，涨跌口径无法复核", errors)
                price, bp = row.get("price"), row.get("changeBp")
                require(isinstance(price, (int, float)) and 0 <= price <= 100,
                        f"{row.get('name')}收益率越界（应为年化百分数）：{price}", errors)
                if bp is not None:
                    require(isinstance(bp, (int, float)) and abs(bp) <= 5000,
                            f"{row.get('name')}基点变化越界：{bp}", errors)

    if name == "commodities":
        # 这条管道的诚实边界全在「频率」上：月频不得被写成日频，涨跌必须相对上一观测。
        require(len({row.get("id") for row in rows}) == len(rows), "商品序列代码必须唯一", errors)
        for row in rows:
            meta = row.get("dataMeta") or {}
            require(meta.get("source") in ("FRED / U.S. EIA", "FRED / IMF Primary Commodity Prices"),
                    f"{row.get('name')}逐条来源未登记", errors)
            require(row.get("frequency") in ("daily", "weekly", "monthly"),
                    f"{row.get('name')}逐条频率无效：月频不得写成日频", errors)
            require(meta.get("frequency") == row.get("frequency"),
                    f"{row.get('name')}逐条频率与元数据不一致", errors)
            require(row.get("group") in ("energy", "precious", "base", "grain", "soft",
                                         "livestock", "index"),
                    f"{row.get('name')}分组未登记", errors)
            require(bool(row.get("unit")), f"{row.get('name')}缺少单位", errors)
            require((meta.get("mode") == "fallback") == (row.get("stale") is True),
                    f"{row.get('name')}回退模式与stale字段不一致", errors)
            if meta.get("mode") == "market":
                require(row.get("previousAsOf"),
                        f"{row.get('name')}缺少上一观测日期，涨跌口径无法复核", errors)

    if name == "companies":
        require(len(rows) == data.get("count") == 500, "公司榜数量元数据不一致", errors)
        for row in rows:
            meta = row.get("dataMeta") or {}
            if row.get("private") is True:
                require(meta.get("mode") == "estimate", f"{row.get('name')}未上市估值模式无效", errors)
                require(row.get("changePct") is None, f"{row.get('name')}未上市估值不得含当日涨跌", errors)
            else:
                require(meta.get("mode") in ("market", "fallback", "unknown"),
                        f"{row.get('name')}上市公司数据模式无效", errors)
                require((meta.get("mode") == "fallback") == (row.get("stale") is True),
                        f"{row.get('name')}回退模式与stale字段不一致", errors)

    if name == "asset-ranking":
        require(len(rows) == data.get("count") == 250, "全球资产榜数量元数据不一致", errors)
        for row in rows:
            meta = row.get("dataMeta") or {}
            if row.get("static") is True:
                require(meta.get("mode") == "estimate", f"{row.get('name')}慢变量估值模式无效", errors)
            require((meta.get("mode") == "fallback") == (row.get("stale") is True),
                    f"{row.get('name')}回退模式与stale字段不一致", errors)
            if row.get("category") == "company" and row.get("private") is not True:
                require(meta.get("mode") in ("market", "fallback", "unknown"),
                        f"{row.get('name')}公司条目数据模式无效", errors)

    if errors:
        raise SystemExit(name + " 数据质量校验失败：\n- " + "\n- ".join(errors))
    counts = data["dataQuality"]["counts"]
    print(f"{name}: PASS · " + " · ".join(f"{key}={value}" for key, value in counts.items()))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", choices=[*DATASETS, "all"], default="all")
    args = parser.parse_args()
    selected = DATASETS if args.dataset == "all" else [args.dataset]
    for name in selected:
        validate_dataset(name)


if __name__ == "__main__":
    main()
