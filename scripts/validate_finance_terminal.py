#!/usr/bin/env python3
"""Validate the static Finance Terminal market-overview MVP without third-party dependencies."""

from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PAGE = ROOT / "apps" / "finance-terminal" / "index.html"
APP = ROOT / "apps" / "finance-terminal" / "app.js"
DATA = ROOT / "apps" / "finance-terminal" / "data.json"
HOME = ROOT / "index.html"

EXPECTED_SYMBOLS = {"SPX", "NDX", "DJI", "US10Y", "DXY", "XAU/USD", "WTI", "BTC/USD"}
REQUIRED_ASSET_FIELDS = {
    "id", "name", "nameEn", "symbol", "category", "price", "changePct", "updatedAt", "spark"
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def parse_iso(value: str) -> None:
    datetime.fromisoformat(value.replace("Z", "+00:00"))


def main() -> None:
    for path in (PAGE, APP, DATA, HOME):
        require(path.is_file(), f"缺少文件：{path.relative_to(ROOT)}")

    data = json.loads(DATA.read_text(encoding="utf-8"))
    require(data.get("demo") is True, "data.json 必须包含 demo: true")
    require("演示" in data.get("source", ""), "数据来源必须明确标注为演示数据")
    require(data.get("status") == "ok", "演示数据状态必须为 ok")
    parse_iso(data["updatedAt"])

    assets = data.get("assets")
    require(isinstance(assets, list) and len(assets) == 8, "必须且只能包含8项核心资产")
    require({asset.get("symbol") for asset in assets} == EXPECTED_SYMBOLS, "资产代码与需求不一致")

    for asset in assets:
        missing = REQUIRED_ASSET_FIELDS - asset.keys()
        require(not missing, f"{asset.get('symbol', 'unknown')} 缺少字段：{sorted(missing)}")
        require(isinstance(asset["price"], (int, float)), f"{asset['symbol']} price 必须为数值")
        require(isinstance(asset["changePct"], (int, float)), f"{asset['symbol']} changePct 必须为数值")
        require(isinstance(asset["spark"], list) and len(asset["spark"]) >= 2, f"{asset['symbol']} 缺少演示走势")
        parse_iso(asset["updatedAt"])

    page = PAGE.read_text(encoding="utf-8")
    app = APP.read_text(encoding="utf-8")
    home = HOME.read_text(encoding="utf-8")
    require("当前为演示数据" in page, "页面首屏缺少明确演示数据提示")
    require('id="market-grid"' in page, "页面缺少市场卡片容器")
    require('src="app.js"' in page, "页面未加载本地 app.js")
    compact_page = re.sub(r"\s+", "", page)
    require('content="width=device-width,initial-scale=1.0"' in compact_page, "页面缺少移动端 viewport")
    require(
        ".market-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr))" in compact_page,
        "桌面端必须显示四列市场卡片",
    )
    require(
        "@media(max-width:1040px)" in compact_page
        and ".market-grid{grid-template-columns:repeat(2,minmax(0,1fr))" in compact_page,
        "平板端必须显示两列市场卡片",
    )
    require(
        "@media(max-width:620px)" in compact_page
        and ".market-grid{grid-template-columns:1fr" in compact_page,
        "手机端必须显示单列市场卡片",
    )
    require("data.json?t=" in app, "app.js 未读取本地 data.json")
    require("data.demo !== true" in app, "app.js 未强制校验演示数据标记")
    require("apps/finance-terminal/" in home, "首页缺少金融终端入口")

    external_scripts = re.findall(r'<script[^>]+src=["\']https?://', page, flags=re.I)
    require(not external_scripts, "金融终端页面不得引入外部脚本依赖")
    print("Finance Terminal MVP validation: PASS")
    print("- demo flag and source label: PASS")
    print("- eight required assets and fields: PASS")
    print("- timestamps and numeric values: PASS")
    print("- homepage route and local assets: PASS")
    print("- 360 / 768 / 1280 responsive rules: PASS")
    print("- no external script dependencies: PASS")


if __name__ == "__main__":
    main()
