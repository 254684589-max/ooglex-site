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
}


def require(condition, message, errors):
    if not condition:
        errors.append(message)


def validate_dataset(name):
    path, rows_key = DATASETS[name]
    data = json.loads(path.read_text(encoding="utf-8"))
    rows = data.get(rows_key)
    errors = validate_data_quality(rows, data.get("dataQuality"))
    require(data.get("frequency") in ("daily", "irregular"), "文件级frequency无效", errors)
    require(data.get("status") in ("ok", "partial", "stale", "error"), "文件级status无效", errors)
    require(data.get("status") == (data.get("dataQuality") or {}).get("status"),
            "文件级status与逐条汇总不一致", errors)

    if name == "asset-tracker":
        require(len(rows) == 28, "跨资产条目数必须为28", errors)
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
