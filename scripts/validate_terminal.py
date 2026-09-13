#!/usr/bin/env python3
"""新版金融终端的契约校验。

针对 /apps/finance-terminal/ 的三个页型（监控 / 证券描述 / 榜单与趋势）与
/assets/terminal/ 的代码层。改版前那一页的契约在 validate_finance_terminal.py
（它已改指 legacy.html，129 条断言一条未动）。

这份契约管的是「数据诚实」与「结构不腐」，不管像素：

  1 三页与代码层齐备、互链、被 sitemap 收录、锁深色
  2 金融数据规范：每块都要有来源／数据日期／频率／状态的出处位
  3 不得把日频或快照标成实时
  4 站内没有的字段必须显式声明，不得留占位数字
  5 没有买卖下单键（站内没有经纪或订单通道）
  6 功能注册表完整：助记符唯一、已接入项地址存在、规划中项无地址且写清卡点
  7 代码层单一真源：口径只有一份，不允许再出现第二套 fmt / soft / 表格组件
  8 无孤儿资源引用、无外部脚本、无装饰动画

用法：python3 scripts/validate_terminal.py
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "apps" / "finance-terminal"
LIB = ROOT / "assets" / "terminal"

PAGES = {
    "monitor": APP / "index.html",
    "security": APP / "security.html",
    "trends": APP / "trends.html",
}
LIB_FILES = ["core.js", "overview.js", "security.js", "render.js",
             "registry.js", "chrome.js", "behavior.js", "terminal.css"]

_failures: list[str] = []
_checks = 0


def require(cond: bool, message: str) -> None:
    global _checks
    _checks += 1
    if not cond:
        _failures.append(message)


def section(name: str) -> None:
    print(f"- {name}: {'FAIL' if _failures else 'PASS'}")


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


def main() -> int:
    # ── 1 文件齐备 ────────────────────────────────────────────────────────
    for name, p in PAGES.items():
        require(p.is_file(), f"缺少页面 {p.relative_to(ROOT)}")
    for f in LIB_FILES:
        require((LIB / f).is_file(), f"缺少代码层 assets/terminal/{f}")
    require((APP / "legacy.html").is_file(), "旧版终端 legacy.html 必须保留可用")
    require((APP / "quote.html").is_file(), "行情详情 quote.html 必须保留（markets 页依赖它）")
    for f in ("terms.html", "privacy.html"):
        require((APP / f).is_file(), f"法律页 {f} 必须保留")
    if _failures:
        return report()
    pages = {k: read(p) for k, p in PAGES.items()}
    lib = {f: read(LIB / f) for f in LIB_FILES}
    section("三个页型与代码层齐备")

    # ── 2 页面骨架：锁深色、canonical、互链、主题插槽 ──────────────────
    for k, s in pages.items():
        require('data-theme-lock="dark"' in s, f"{k} 必须锁深色（专业终端是深色语言，浅色兜底已剥离）")
        require('data-finance-terminal' in s, f"{k} 缺少 data-finance-terminal 标记")
        require("<html" in s and 'lang="zh-CN"' in s, f"{k} 必须声明中文")
        require('rel="canonical"' in s, f"{k} 缺少 canonical")
        require("data-theme-slot" in s, f"{k} 必须给主题选择器留插槽，否则它会浮在标签条上")
        require('href="/assets/terminal/terminal.css"' in s, f"{k} 必须引入合并后的设计系统")
        # 三页互链 + 通往旧版与法律页
        for target in ("/apps/finance-terminal/", "/apps/finance-terminal/security.html",
                       "/apps/finance-terminal/trends.html", "/apps/finance-terminal/legacy.html",
                       "/apps/finance-terminal/terms.html", "/apps/finance-terminal/privacy.html"):
            require(target in s, f"{k} 缺少通往 {target} 的链接")
    sm = read(ROOT / "sitemap.xml")
    for u in ("/apps/finance-terminal/", "/apps/finance-terminal/security.html",
              "/apps/finance-terminal/trends.html"):
        require(f"https://www.ooglex.com{u}" in sm, f"sitemap 未收录 {u}")
    require("finance-terminal/legacy.html" not in sm, "旧版终端不应进 sitemap（它已 noindex）")
    require('name="robots"' in read(APP / "legacy.html"), "legacy.html 必须 noindex，避免与新终端争收录")
    section("页面骨架与互链")

    # ── 3 金融数据规范：出处位 ───────────────────────────────────────────
    # 监控页每个面板都要有 data-src 脚注位；三页都要有来源块
    mon = pages["monitor"]
    panels = re.findall(r'<section class="t-panel[^"]*"[^>]*>', mon)
    require(len(panels) >= 12, f"监控页面板数不足（当前 {len(panels)}，应 ≥12）")
    src_slots = re.findall(r'data-src="([a-z-]+)"', mon)
    require(len(src_slots) >= 11, f"监控页出处脚注位不足（当前 {len(src_slots)}）")
    require('id="tbl-sources"' in mon, "监控页必须有数据来源表")
    for k, s in pages.items():
        require("来源" in s, f"{k} 页面上必须出现来源字样")
    # 出处行的四要素由 core.srcLine 统一产出
    core = lib["core.js"]
    for token in ("来源 ", "AS OF ", "状态 ", "statusZh"):
        require(token in core, f"core.js 的出处行缺少 {token!r}")
    require("frequency" in core and "updatedAt" in core and "asOf" in core,
            "core.meta 必须带上 asOf / updatedAt / frequency")
    section("金融数据出处规范")

    # ── 4 不得伪造实时 ───────────────────────────────────────────────────
    for k, s in pages.items():
        text = re.sub(r"<[^>]+>", " ", s)
        for m in re.finditer(r"[^。；\n]{0,24}实时[^。；\n]{0,24}", text):
            frag = m.group(0)
            ok = any(w in frag for w in ("非实时", "无实时", "不标", "实时事件", "标为实时", "realtime"))
            require(ok, f"{k} 出现未加限定的「实时」：{frag.strip()[:40]}")
    require("realtime:false" in core.replace(" ", "") or "realtime === true" in core,
            "core.js 必须按源自带的 realtime 字段判断，不得默认当成实时")
    require("非实时" in lib["overview.js"] or "非实时" in mon,
            "盘中快照必须标注非实时")
    section("不伪造实时")

    # ── 5 站内没有的字段必须显式声明 ─────────────────────────────────────
    require("UNAVAILABLE" in core and "UNAVAILABLE_NOTE" in core,
            "core.js 必须统一声明站内不可得字段")
    for field in ("BID", "ASK", "VOL", "ISIN", "评级", "持仓"):
        require(field in core, f"不可得字段声明里缺 {field}")
    require("不用占位数字冒充" in core, "core.js 必须写明不用占位数字冒充")
    require("data-unavail" in mon, "监控页必须有不可得字段声明位")
    sec = pages["security"]
    require("站内无来源" in sec and "不显示" in sec, "证券描述页必须逐条声明不可得字段")
    section("不可得字段显式声明")

    # ── 6 没有买卖下单键 ─────────────────────────────────────────────────
    for k, s in pages.items():
        for tag in re.findall(r"<(?:button|a)[^>]*>([^<]{0,12})</(?:button|a)>", s):
            t = tag.strip()
            require(not re.match(r"^(买入|卖出|下单|Buy|Sell|BUY|SELL)$", t),
                    f"{k} 出现下单键「{t}」：站内没有经纪或订单通道")
    require("没有经纪" in sec or "没有买" in sec, "证券描述页应说明为什么没有买卖键")
    section("无下单键")

    # ── 7 功能注册表完整性 ───────────────────────────────────────────────
    reg = lib["registry.js"]
    mns = re.findall(r'\bmn:"([A-Z0-9]+)"', reg)
    require(len(mns) == len(set(mns)), f"注册表助记符重复：{[m for m in set(mns) if mns.count(m) > 1]}")
    require(len(mns) >= 25, f"注册表功能数偏少（{len(mns)}）")
    # 已接入项的站内地址必须真实存在
    for href in re.findall(r'href:"(/apps/[^"]*)"', reg):
        path = href.split("#")[0].split("?")[0]          # 锚点与查询不参与文件定位
        target = ROOT / path.lstrip("/")
        if path.endswith("/"):
            target = target / "index.html"
        require(target.exists(), f"注册表指向不存在的页面 {href}")
        if "#" in href:                                   # 带锚点的，目标页里必须真有这个 id
            anchor = href.split("#", 1)[1]
            page = read(target)
            require(f'id="{anchor}"' in page or f'data-category="{anchor}"' in page,
                    f"注册表的锚点 {href} 在目标页里不存在")
    # 规划中的项不得有地址，且必须写清需要什么、卡在哪
    planned = reg[reg.index("var PLANNED"):reg.index("function byMn")] if "var PLANNED" in reg else ""
    require(planned, "注册表缺少 PLANNED 段")
    require(planned.count("need:") >= 6 and planned.count("blocked:") >= 6,
            "规划中的功能必须逐条写清「需要什么」与「卡在哪」")
    require('f.href = null' in reg, "注册表必须把规划中项的地址统一置空，避免命令行跳到空地址")
    require('status === "planned" || !f.href' in lib["chrome.js"],
            "命令行必须对规划中或无地址的功能给出「规划中」提示，而不是跳转")
    section("功能注册表完整性")

    # ── 8 代码层单一真源 ─────────────────────────────────────────────────
    # 口径只能有一份：fmt / soft / isNum 只在 core.js 里定义
    for name, src in lib.items():
        if not name.endswith(".js") or name == "core.js":
            continue
        require("var fmt = {" not in src, f"{name} 不得再定义一套 fmt（口径只有 core.js 一份）")
        require("function soft(" not in src, f"{name} 不得再定义一套 soft")
    require("var fmt = {" in core and "function soft(" in core, "core.js 必须持有唯一一份口径实现")
    # 表格组件只有一套
    css = lib["terminal.css"]
    require(".c-tbl" not in css, "样式表不得再出现第二套表格组件 .c-tbl")
    require(re.search(r"(?m)^\.t-tbl\s*\{", css), "样式表必须定义 .t-tbl")
    require(css.count("{") == css.count("}"), "样式表大括号不配平")
    # 令牌不得引用未定义
    used = set(re.findall(r"var\((--[a-z0-9-]+)", css))
    defined = set(re.findall(r"(?m)^\s*(--[a-z0-9-]+)\s*:", css))
    require(not (used - defined), f"样式表引用了未定义的令牌：{sorted(used - defined)}")
    require("button{font:inherit" in css.replace(" ", ""),
            "样式表必须重置 button，否则外壳按钮会露浏览器默认浅灰底")
    section("代码层单一真源")

    # ── 9 无孤儿引用 / 无外部脚本 / 无装饰动画 ───────────────────────────
    for k, s in pages.items():
        for ref in set(re.findall(r'(?:src|href)="(/assets/[^"?]+)"', s)):
            require((ROOT / ref.lstrip("/")).is_file(), f"{k} 引用了不存在的资源 {ref}")
        ext = [u for u in re.findall(r'<script[^>]+src="(https?://[^"]+)"', s)]
        require(not ext, f"{k} 不得引入外部脚本：{ext}")
        require("<iframe" not in s, f"{k} 不得使用 iframe")
    for name in ("terminal.css",):
        src = lib[name]
        # box-shadow:none 是重置不是装饰，只禁「真的画出阴影」的那种
        for bad in ("backdrop-filter", "linear-gradient", "radial-gradient",
                    "@keyframes", "text-shadow"):
            require(bad not in src, f"{name} 不得使用 {bad}（装饰归零）")
        shadows = [m for m in re.findall(r"box-shadow:\s*([^;}]+)", src) if m.strip() != "none"]
        require(not shadows, f"{name} 不得画阴影（装饰归零）：{shadows}")
        require("prefers-reduced-motion" in src, "样式表必须保留 reduced-motion 兜底约束")
    section("无孤儿引用与装饰")

    # ── 10 从旧终端迁入的两块 ────────────────────────────────────────────
    geo_mod = ROOT / "apps" / "finance-terminal" / "finance-terminal-geo-risk.mjs"
    require(geo_mod.is_file(), "地缘风险模型文件缺失（新旧两个终端都在用它）")
    geo_src = read(geo_mod)
    require("消费方有两个" in geo_src, "地缘风险模型必须写明它有两个消费方，避免被误删")
    require("buildGeoRisk" in geo_src and "export function buildGeoRisk" in geo_src,
            "地缘风险模型必须导出 buildGeoRisk")
    # 新终端只复用模型，不复制打分逻辑
    require('/apps/finance-terminal/finance-terminal-geo-risk.mjs' in mon,
            "监控页必须 import 地缘风险模型，而不是另写一份打分")
    for token in ("GEO_LEVELS", "buildGeoRisk"):
        require(token in mon, f"监控页缺少 {token}")
    for bad in ("energyAxis", "havenAxis", "linearScore", "percentileScore"):
        require(bad not in mon, f"监控页不得复制打分实现 {bad}（单一真源在那个模块里）")
    require('id="tbl-geo"' in mon and 'data-src="geo"' in mon, "监控页缺少地缘风险面板")
    require("四条轴等权" in mon, "地缘风险面板必须写明四条轴等权")
    require("不使用任何 AI 生成的文本作为数据来源" in mon,
            "地缘风险面板必须声明不以 AI 文本为数据源")
    # 品类分布：只做汇总并链向看板本体，不在终端里复制第二份看板
    require('id="tbl-cat"' in mon and 'data-src="cat"' in mon, "监控页缺少品类分布面板")
    require("/apps/markets/" in mon, "品类分布必须链向看板本体所在的页面")
    for bad in ('id="board-tabs"', 'id="board-panel"', 'id="board-live"'):
        require(bad not in mon, f"监控页不得复制品类看板的 {bad}（看板本体在 /apps/markets/）")
    require("category" in mon, "品类分布必须按跨资产管道的 category 字段汇总")
    section("迁入的地缘风险与品类分布")

    # ── 10 无障碍：涨跌不能只靠颜色 ───────────────────────────────────────
    require(".t-sig" in css and "NORMAL" in lib["render.js"],
            "风险档位必须带文字标签，颜色不是唯一编码")
    require("aria-" in mon, "监控页必须有 aria 标注")
    require("focus-visible" in css, "必须有可见焦点样式")
    section("无障碍")

    return report()


def report() -> int:
    if _failures:
        print(f"\n新终端契约：{len(_failures)} / {_checks} 条不通过", file=sys.stderr)
        for f in _failures:
            print("  ✗ " + f, file=sys.stderr)
        return 1
    print(f"\n新终端契约：{_checks} 条全部通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
