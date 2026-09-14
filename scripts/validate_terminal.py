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
    "compare": APP / "compare.html",
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


_marked = 0


def section(name: str) -> None:
    """本节结论只看本节新增的失败——否则第一处失败之后每节都写 FAIL，定位不了问题。"""
    global _marked
    new = _failures[_marked:]
    _marked = len(_failures)
    print(f"- {name}: {'FAIL' if new else 'PASS'}" + (f"（{len(new)} 条）" if new else ""))


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
        # 缓存指纹（?v=<hash>）由 validate_asset_versions.py 打，断言只认路径不认指纹
        require(re.search(r'href="/assets/terminal/terminal\.css(?:\?v=[0-9a-f]{8})?"', s),
                f"{k} 必须引入合并后的设计系统")
        # 三页互链 + 通往旧版与法律页
        for target in ("/apps/finance-terminal/", "/apps/finance-terminal/security.html",
                       "/apps/finance-terminal/trends.html", "/apps/finance-terminal/compare.html",
                       "/apps/finance-terminal/legacy.html",
                       "/apps/finance-terminal/terms.html", "/apps/finance-terminal/privacy.html"):
            require(target in s, f"{k} 缺少通往 {target} 的链接")
    sm = read(ROOT / "sitemap.xml")
    for u in ("/apps/finance-terminal/", "/apps/finance-terminal/security.html",
              "/apps/finance-terminal/trends.html", "/apps/finance-terminal/compare.html"):
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
    require(len(mns) >= 26, f"注册表功能数偏少（{len(mns)}）")
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
        # 连查询串一起吃进来再剥掉：原先的 [^"?]+ 在资源加上 ?v= 指纹后一条都匹配不到，
        # 27 条断言就这么静默消失了。能静默匹配到零条的检查不算检查，所以下面还要
        # 断言「至少匹配到几条」——正则失效时要响，不要静。
        refs = set()
        for raw in re.findall(r'(?:src|href)="(/assets/[^"]+)"', s):
            refs.add(raw.split("?", 1)[0])
        require(len(refs) >= 2, f"{k} 只解析到 {len(refs)} 条 /assets/ 引用，正则可能已失效")
        for ref in refs:
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

    # ── 12 标的详情链路：点得开、分片取得对、取不到要写明 ─────────────────
    sec_js = lib["security.js"]
    ren = lib["render.js"]
    require("shardPath" in core, "core.js 必须提供 shardPath：公司历史按名次分片存放")
    require("historyShard" in sec_js, "security.js 必须按 historyShard 取对应那一片收盘历史")
    require("ensureHist" in sec_js and "ensureHist" in pages["security"],
            "证券描述页必须先补齐该标的所在分片再画图")
    require("loaded" in sec_js and "absorb" in sec_js,
            "分片要缓存，同一片不得重复下载")
    require("日期轴" in sec_js, "并片前必须核对日期轴，错轴不并")
    # 分片文件必须都在，且共用同一条日期轴——security.js 靠这个前提并片
    comp = ROOT / "apps" / "companies"
    axis = None
    shard_count = {}
    for i in range(1, 6):
        f = comp / ("history.json" if i == 1 else f"history-{i}.json")
        require(f.is_file(), f"缺少公司历史分片 {f.name}")
        if not f.is_file():
            continue
        d = json.loads(read(f))
        dates = d.get("dates") or []
        shard_count[i] = len(d.get("series") or {})
        if axis is None:
            axis = dates
        else:
            require(dates == axis, f"{f.name} 的日期轴与第 1 片不一致，不能并进同一张表")
    # 公司榜里每个真实标的都要标出所在分片，且那一片确实存在
    rows = json.loads(read(comp / "data.json")).get("companies") or []
    listed = [r for r in rows if r.get("symbol") and r["symbol"] != "—"
              and isinstance(r.get("price"), (int, float))]
    require(len(listed) >= 400, f"公司榜可显示标的过少（{len(listed)}）")
    missing = [r["symbol"] for r in listed if not r.get("historyShard")]
    require(not missing, f"公司榜有 {len(missing)} 个标的没标分片：{missing[:5]}")
    bad_shard = [r["symbol"] for r in listed
                 if r.get("historyShard") and int(r["historyShard"]) not in shard_count]
    require(not bad_shard, f"有标的指向不存在的分片：{bad_shard[:5]}")
    # 行情页与终端资源层的分片规则必须是同一套，否则两处会取到不同的文件
    qm = read(ROOT / "apps" / "finance-terminal" / "finance-terminal-quote.mjs")
    require("shardPath" in qm, "行情页仍须保留自己的 shardPath（模块页不吃全局 IIFE）")
    for src in (core, qm):
        require("<= 1) return path" in src or "i <= 1) return path" in src,
                "两处 shardPath 都必须把第 1 片映回原文件名")
    # 取不到序列时，两个图框和页脚都要写明原因，不能留空白
    require('empty: whyPx' in pages["security"] and 'empty: whyPx' in pages["security"],
            "证券描述页无序列时两个图框都要写明原因")
    require("没有该标的的收盘历史序列" in pages["security"], "无序列必须如实说明")
    require("不插值" in pages["security"] or "假曲线" in pages["security"],
            "不得插值补缺，且要说明")
    # 行内名称链接由 core.detailHref 统一产出，各表都要用上
    require("detailHref" in core and "nameCell" in ren,
            "行内详情链接必须走 core.detailHref + render.nameCell")
    require("nameCell: nameCell" in ren, "nameCell 必须导出，页面才不用各写一遍链接标记")
    # 页面不得自己拼 a.t-go —— 只有 render.nameCell 产出这段标记，否则又是多套真源。
    # 唯一例外是证券描述页那个静态的「全区间走势」按钮（它不是表格行，靠 JS 改 href）。
    for k, page in pages.items():
        for m in re.finditer(r'class="t-go"[^>]*', page):
            require("data-quote-link" in m.group(0),
                    f"{k} 自己拼了 a.t-go：{m.group(0)[:56]}——应改调 R.nameCell")
        require("CORE.detailHref" not in page and "C.detailHref" not in page,
                f"{k} 直接调了 detailHref 拼链接：链接标记只许由 render.nameCell 产出")
    for tbl in ("quoteTable", "ratesTable", "crossBars", "watchlist", "macroMonitor"):
        body = ren[ren.index("function " + tbl):]
        body = body[:body.index("\n  function ") if "\n  function " in body else len(body)]
        require("nameCell" in body or "data-sig" in body,
                f"{tbl} 的名称列没有接上详情链接")
    # 合成信号：有序列的就地展开，没有的保持不可点
    require('data-sig' in ren and 'aria-expanded' in ren,
            "合成信号要做成可展开按钮并带 aria-expanded")
    require("signalHist" in lib["overview.js"] and "signalHist" in ren,
            "合成信号的分位历史必须从模型层传到渲染层")
    require('id="svg-sig"' in mon and 'id="sig-box"' in mon, "监控页必须有合成信号的图框")
    require("周频" in mon and "回溯" in mon,
            "合成信号序列是周频回溯算出来的，页面必须写明，不能当成当年读数")
    require("valLabel" in ren and "fmtv" in ren,
            "非价格序列不得沿用「有效收盘」与价格格式")
    sig_hist = ROOT / "apps" / "macro-radar" / "history.json"
    require(sig_hist.is_file(), "缺少合成信号历史序列 macro-radar/history.json")
    if sig_hist.is_file():
        sd = json.loads(read(sig_hist))
        require(len(sd.get("dates") or []) > 100, "合成信号历史点数过少")
        require(sd.get("freq") == "W", "合成信号序列频率标注变了，页面上的「周频」字样要跟着改")
        for k, v in (sd.get("signals") or {}).items():
            require(len(v) == len(sd["dates"]), f"信号 {k} 的序列长度与日期轴不符")
    section("标的详情链路与历史分片")

    # ── 13 类名不得撞名 ─────────────────────────────────────────────────────
    # 合并那一版有三处撞名靠改名解决；后来 .t-go 又撞了一次——行内详情链接继承到
    # 命令行 GO 键的琥珀块底，白字被压到 1.79:1。撞名不是样式偏好问题，是会改变
    # 别处观感的隐蔽 bug，所以这里直接查：同一个裸单类不得在顶层定义两次。
    # @media / @supports 块里的重复是正常的响应式覆盖，先剥掉再查。
    def _strip_at_blocks(text: str) -> str:
        out, i = [], 0
        pat = re.compile(r"@(?:media|supports|container)[^{]*\{")
        while i < len(text):
            m = pat.search(text, i)
            if not m:
                out.append(text[i:])
                break
            out.append(text[i:m.start()])
            depth, j = 1, m.end()
            while j < len(text) and depth:
                if text[j] == "{":
                    depth += 1
                elif text[j] == "}":
                    depth -= 1
                j += 1
            out.append("\n" * text[m.start():j].count("\n"))
            i = j
        return "".join(out)

    top = _strip_at_blocks(css)
    seen: dict[str, list[int]] = {}
    for m in re.finditer(r"(?m)^((?:\.[A-Za-z][\w-]*\s*,\s*)*\.[A-Za-z][\w-]*)\s*\{", top):
        for sel in m.group(1).split(","):
            sel = sel.strip()
            if re.fullmatch(r"\.[A-Za-z][\w-]*", sel):
                seen.setdefault(sel, []).append(top[:m.start()].count("\n") + 1)
    for sel, lines in sorted(seen.items()):
        require(len(lines) == 1,
                f"terminal.css 里 {sel} 在顶层定义了 {len(lines)} 次（行 {lines}）："
                "撞名靠后者覆盖不可靠，合成一条或改名")
    # 详情链接必须显式归零背景与内边距——它的类名曾被别处的色块规则命中
    go = top[top.index(".t-go{"):]
    go = go[:go.index("}")]
    for prop in ("background:none", "padding:0", "border:0"):
        require(prop in go.replace(" ", ""), f".t-go 基础规则必须显式写 {prop}，别指望没人定义同名规则")
    # 可点提示不能只有颜色一种编码
    require("border-bottom:1px dotted" in css,
            "行内详情链接必须有常态可见的虚线提示，「能点」不能只靠颜色或悬停")
    # 密排表格里不给标的名称套色块：那会撑开行距并压低对比度
    require(".t-go{" in top and "background:var(--t-amber);color:#000" not in go,
            ".t-go 常态不得使用琥珀色块底（白字在琥珀上只有 1.79:1）")
    # 页面文案走 textContent，markdown 记号会原样显示成字面量。
    # 这个错犯过两次（口径说明里写了 **…**），所以做成检查。
    for k, page in pages.items():
        for m in re.finditer(r'"[^"\n]*\*\*[^"\n]*"', page):
            require(False,
                    f"{k} 的字符串里有 markdown 星号，textContent 会原样显示：{m.group(0)[:52]}")
    section("类名不得撞名")

    # ── 14 多标的比较：对齐与归一化的口径必须写在页面上 ──────────────────
    cmp_ = pages["compare"]
    for fn in ("alignSeries", "compareWindow", "rebase"):
        require(fn in core, f"core.js 必须提供 {fn}：比较页的对齐与归一化口径只能有一份")
        require(fn in cmp_, f"比较页必须调用 core.{fn}，不得自己另写一套对齐")
    require("multiLine" in ren and "smallMultiples" in ren,
            "比较页的叠加图与小倍数必须走 render 层的共用渲染器")
    # 两条管道的日期轴确实不同 —— 这是「必须按日期对齐」的事实依据，变了就得改口径说明
    ch = json.loads(read(ROOT / "apps" / "companies" / "history.json"))
    ah = json.loads(read(ROOT / "apps" / "asset-tracker" / "history.json"))
    require(ch.get("dates") != ah.get("dates"),
            "公司榜与跨资产的日期轴变成一样了：比较页「按日期对齐」的说明要跟着改")
    require("按日期" in cmp_ and "对齐" in cmp_, "比较页必须写明按日期对齐，不是按下标")
    require("不插值" in cmp_ and "不前向填充" in cmp_, "比较页必须写明不插值、不前向填充")
    require("去空列不是补数据" in cmp_,
            "去掉全空列这件事必须说清它不是补数据，否则读的人会以为缺口被填了")
    require("未做汇率换算" in cmp_, "各标的按本币计价，必须写明未做汇率换算")
    require("24 小时口径" in cmp_ or "24h" in cmp_, "加密标的口径与股票不同，必须写明")
    require("分红" in cmp_, "收盘价未做分红再投资调整，必须写明")
    require("不是标的历史最大回撤" in cmp_,
            "回撤是本窗口内口径，必须写明不是历史最大回撤")
    require("窗口不足一季不给年化" in cmp_ or "不年化" in cmp_,
            "窗口太短不得给年化数")
    # 归一化叠加不得用颜色编码身份：数据区颜色只承载涨跌与风险
    ml = ren[ren.index("function multiLine"):]
    ml = ml[:ml.index("function smallMultiples")]
    require("var(--t-dim)" in ml and "var(--t-cmd-line)" in ml,
            "叠加图只用「上下文灰 + 聚焦琥珀」两色")
    for bad in ("--t-up", "--t-dn", "#00b86b", "#ff4d4d"):
        require(bad not in ml,
                f"叠加图不得用涨跌色 {bad} 编码「这是哪条标的」——那会把色彩语义搞乱")
    require("esc(p.tk)" in ml, "叠加图必须在线尾直接标代码：身份不能只靠颜色")
    require("minGap" in ml, "线尾标签必须做避让，否则几条挤在一起看不清")
    # 单源隔离：一条取不到序列，不得把整次比较拖死；摘掉谁、为什么都要写出来
    require("unusable" in cmp_ and "已从本次比较摘出" in cmp_,
            "某条取不到序列时必须摘出并说明原因，剩下的照比，不得整页失败")
    require("counts" in lib["security.js"] and "整类不可选" in cmp_,
            "标的表取不到会让那一整类从选择器里消失，页面必须说明少了哪一类")
    require("读取失败" in cmp_,
            "失败措辞要与站内其余页一致（读取失败 / 未加载），别一页一个叫法")
    # 相关性与回归：短样本不得给系数，口径必须写明
    # 统计口径只能有一份：函数定义在 core，调用点可以在页面或 render 层
    # （pairCorr 就是在 render.corrMatrix 里调的，那是对的位置）。
    # 真正要拦的是「页面自己手写一遍皮尔逊或最小二乘」。
    for fn in ("dailyReturns", "pairCorr", "regress"):
        require(fn in core, f"core.js 必须提供 {fn}")
        require(fn in cmp_ or fn in ren,
                f"{fn} 没有任何调用点：口径函数写了却没用上")
    for hand in ("Math.sqrt(sxx", "sxy / sxx", "sxy/sxx"):
        require(hand not in cmp_,
                f"比较页里出现手写统计（{hand}）：皮尔逊与最小二乘只能有 core 一份")
    require("MIN_PAIRS" in core, "core.js 必须定义相关/回归的最小重叠样本")
    m_min = re.search(r"var MIN_PAIRS = (\d+)", core)
    require(m_min and int(m_min.group(1)) >= 60,
            "最小重叠样本不得低于 60 天：短样本的相关系数是噪声")
    require("corrMatrix" in ren, "相关性矩阵必须走 render 层")
    cmx = ren[ren.index("function corrMatrix"):]
    cmx = cmx[:cmx.index("\n  function ")]
    require("toFixed(2)" in cmx, "相关性矩阵每格必须印数字，颜色不能是唯一编码")
    require("n=" in cmx and "不足" in cmx, "样本不足的格子必须写出实际样本数")
    require('scope="row"' in cmx and 'scope="col"' in cmx, "矩阵表头必须带 scope")
    m_a = re.search(r"var CORR_ALPHA = ([0-9.]+)", ren)
    require(m_a and float(m_a.group(1)) <= 0.65,
            "染色透明度过高会压掉格内文字对比度（α=0.65 时绿底白字只剩 4.6:1）")
    require("不是 Jensen alpha" in cmp_ and "无风险利率" in cmp_,
            "Alpha 未扣无风险利率，必须写明它不是 Jensen alpha")
    require("相关性不等于因果" in cmp_, "相关性矩阵必须写明相关不等于因果")
    require("R²" in cmp_, "回归必须给出 R²：低 R² 时那个 beta 参考价值有限")
    require("混了汇率" in cmp_, "跨币种的 beta 里混了汇率变动，必须写明")
    # 季节性：月线是降采样的，跨季度的间隔绝不能算成月环比
    for fn in ("monthlySeries", "monthOverMonth", "seasonality", "monthlyCoverage"):
        require(fn in core, f"core.js 必须提供 {fn}")
        require(fn in cmp_ or fn in ren or fn in lib["security.js"],
                f"{fn} 没有任何调用点")
    mom = core[core.index("function monthOverMonth"):]
    mom = mom[:mom.index("\n  /*")] if "\n  /*" in mom else mom[:1200]
    require("!== 1" in mom and "不是相邻月" in mom,
            "monthOverMonth 必须只在日历上相邻的两个月都有值时才算："
            "跨着降采样区间算出来的是季收益，不是月收益")
    m_sy = re.search(r"var MIN_SEASON_YEARS = (\d+)", core)
    require(m_sy and int(m_sy.group(1)) >= 8, "季节性每月样本下限不得低于 8 年")
    require("seasonGrid" in ren, "季节性网格必须走 render 层")
    sg = ren[ren.index("function seasonGrid"):]
    sg = sg[:sg.index("\n  function ")]
    require("median" in sg and "toFixed(1)" in sg,
            "季节性格里印中位数：十来个观测里一次极端月能把平均拉得面目全非")
    require("n=" in sg, "样本不足的格子必须写出实际样本数")
    require("跨了多久，不等于月度样本有多少" in cmp_,
            "必须点明「序列跨了多久 ≠ 月度样本有多少」——这是本页最容易误读的地方")
    require("降采样" in cmp_ and "季度末" in cmp_, "必须写明月线降采样与季度末观测")
    require("描述过去，不是对未来的预测" in cmp_, "季节性必须写明是描述过去不是预测")
    require("活到今天" in cmp_, "长期季节性必须写明生存者偏差")
    require('id="tbl-cov"' in cmp_, "必须逐条给出月线覆盖面表（区间/观测数/相邻月对/逐月起点/非相邻间隔）")
    # 月线分片文件必须齐备
    for i in range(1, 6):
        f = ROOT / "apps" / "companies" / ("history-monthly.json" if i == 1 else f"history-monthly-{i}.json")
        require(f.is_file(), f"缺少公司月线分片 {f.name}")
    require((ROOT / "apps" / "asset-tracker" / "history-monthly.json").is_file(),
            "缺少跨资产月线")
    section("多标的比较的对齐与归一化")

    # ── 15 持股结构：覆盖面必须说清，否则会被读成完整 13F ─────────────────
    sec_p = pages["security"]
    require("loadOwners" in lib["security.js"], "security.js 必须提供 13F 反查模型")
    require('id="tbl-own"' in sec_p and 'id="pg-5"' in sec_p, "证券描述页必须有持股结构分页")
    require("这里没出现，不等于该机构没持有" in sec_p,
            "站内只收录前 10 大持仓，必须写明「没出现 ≠ 没持有」")
    require("前 10 大持仓" in sec_p, "必须写明只收录前 10 大持仓")
    require("declared" in lib["security.js"] and "只占" in sec_p,
            "必须把站内收录量与机构申报总仓位对比出百分比")
    require("没有代码" in sec_p or "noTk" in lib["security.js"],
            "有相当比例的仓位解析不出代码，按代码反查覆盖不到，必须计入覆盖面")
    require("只含美股多头" in sec_p and "不含空头" in sec_p,
            "13F 只含美股多头，必须写明不含空头、债券与海外持仓")
    require("滞后 45 天" in sec_p, "13F 最长滞后 45 天，必须写明")
    require("不是它占本公司股本的比例" in sec_p,
            "「占其组合」容易被读成占本公司股本，必须澄清")
    require("不构成投资建议" in sec_p, "持股结构页脚必须带免责")
    # 13F 源取不到不得影响本页其余部分，且不能静默
    require(".catch(function (e)" in sec_p,
            "持股结构那段必须显式收口：promise 里抛出会变成静默的 unhandledrejection")
    sup = ROOT / "apps" / "superinvestors" / "data.json"
    require(sup.is_file(), "缺少机构持仓数据 superinvestors/data.json")
    if sup.is_file():
        sd = json.loads(read(sup))
        require(len(sd.get("investors") or []) >= 30, "机构数过少")
        require("13F" in str(sd.get("source", "")), "机构持仓来源标注应指明 13F")
    section("持股结构与 13F 覆盖面")

    # ── 16 曲线三视图 ─────────────────────────────────────────────────────
    require("rates.history" in lib["overview.js"] or "curve.history" in lib["overview.js"],
            "模型层必须带上曲线历史（curve.json 里本来就有 11 个期限 × 260 天）")
    require("curveSnapshots" in ren, "曲线随时间必须走 render 层")
    require('data-cv="now"' in mon and 'data-cv="time"' in mon and 'data-cv="sprd"' in mon,
            "曲线面板必须有三个视图：当前形态 / 随时间 / 期限价差历史")
    require('aria-pressed' in mon, "视图切换必须有 aria-pressed")
    cs = ren[ren.index("function curveSnapshots"):]
    cs = cs[:cs.index("\n  function ")]
    require("var(--t-cmd-line)" in cs and "var(--t-dim)" in cs,
            "曲线随时间只用「最近琥珀 + 其余灰」两色")
    for bad in ("--t-up", "--t-dn"):
        require(bad not in cs, f"曲线随时间不得用涨跌色 {bad} 编码「这是哪一天」")
    require("esc(s.label)" in cs or "esc(pt.label)" in cs,
            "曲线随时间必须在线尾直接标日期：身份不能只靠颜色")
    require("轴是期限不是时间" in mon, "曲线随时间的横轴是期限，必须写明以免误读")
    require("倒挂" in mon and "低于 0 即倒挂" in mon,
            "利差倒挂必须有文字说明，不能只靠颜色")
    require("不是历史全区间" in mon, "利差历史只有 260 个交易日，必须写明不是全区间")
    # 绝对值序列不得套用「重基到 100」的图例口径
    require('legendMode:"abs"' in mon or "legendMode: \"abs\"" in mon,
            "利差是百分点而非重基指数，图例必须走 abs 口径"
            "（否则会算成末值−100，显示出 −99.6% 这种无意义的数）")
    require('legendMode === "abs"' in ren, "render 层必须实现 abs 图例口径")
    cj = json.loads(read(ROOT / "apps" / "macro-radar" / "curve.json"))
    require(len((cj.get("history") or {}).get("dates") or []) > 100, "曲线历史点数过少")
    require(len(cj.get("tenors") or []) >= 8, "曲线期限数过少")
    require("不插值" in str(cj.get("note", "")), "曲线数据源应声明不插值")
    section("曲线三视图")

    # ── 17 横截面汇总与交叉汇率：近似口径必须写明 ──────────────────────────
    require('data-agg="mov"' in mon and 'data-agg="ctry"' in mon,
            "横截面汇总面板必须有指数贡献与国别板块两个视图")
    require("不是官方指数贡献" in mon,
            "指数贡献是站内子集的市值加权近似，必须写明不是官方指数贡献")
    require("没有官方指数除数" in mon, "必须写明站内没有官方指数除数")
    require("自由流通股本调整" in mon, "必须写明未做自由流通股本调整")
    require("实际是 500 家" in mon, "必须写明站内标普成分覆盖不全")
    require("不是全市场" in mon, "国别／板块汇总的池子不是全市场，必须写明")
    require("中位数而不是平均" in mon, "横截面汇总用中位数，必须写明理由")
    require("fxCross" in ren, "交叉汇率必须走 render 层")
    require('data-fxv="cross"' in mon, "外汇面板必须有交叉汇率视图")
    fxc = ren[ren.index("function fxCross"):]
    fxc = fxc[:fxc.index("\n  function ")]
    require("非可成交报价" in fxc, "推导汇率必须标明不是可成交报价")
    require("usdPer" in fxc and "direct" in fxc,
            "交叉汇率必须区分美元腿推导与站内直盘")
    require("不是可成交报价" in mon, "交叉汇率页面说明必须写明非可成交")
    require("不是哪一边算错了" in mon,
            "推导值与直盘的差是快照时点造成的，必须说清不是算错")
    require("站内直盘" in mon, "凡站内有直盘的格子必须给出对账差值")
    section("横截面汇总与交叉汇率")

    # ── 18 自定义篮子：再平衡口径与缺成分处理必须写明 ──────────────────────
    require("basketIndex" in core, "core.js 必须提供 basketIndex")
    require("basketIndex" in cmp_, "篮子必须走 core.basketIndex，页面不得自己加权")
    bi = core[core.index("function basketIndex"):]
    bi = bi[:bi.index("\n  /*")] if "\n  /*" in bi else bi[:2600]
    require("不再平衡" in core, "篮子必须声明固定权重、不再平衡")
    require("重新归一化" in core, "缺成分时不得按剩余权重重新归一化，必须写明理由")
    require("固定权重、不再平衡" in cmp_, "页面必须写明固定权重不再平衡")
    require("与每日或每月再平衡的结果不同" in cmp_,
            "必须写明与再平衡的结果不同，否则会被当成可比的指数")
    require("只在全部成分当天都有值时才给点" in cmp_, "必须写明缺成分留空")
    require("悄悄换成另一只篮子" in cmp_, "必须写明为什么不重新归一化")
    require("不上传" in cmp_, "权重存 localStorage，必须写明只存本机不上传")
    require("不含交易成本" in cmp_, "篮子必须写明不含交易成本、税费与分红再投资")
    require("非任何指数或产品" in cmp_, "篮子必须声明它不是任何指数或产品")
    # localStorage 读写必须 try/catch，禁用存储时页面要照常能用
    for frag in ("try {", "catch (e) { return {}; }"):
        require(frag in cmp_, f"localStorage 读写必须 try/catch（缺 {frag!r}）")
    require("存储不可用" in cmp_, "存储不可用时必须在页面上说明改动只在本次会话有效")
    section("自定义篮子")

    # ── 19 主权利差：收益率是水平值，不是价格 ──────────────────────────────
    # 这一节盯的是同一类误读：把收益率当价格处理。收益率 2% → 3% 是「上行 100bp」，
    # 重基到 100 再报变动率会写成「+50%」；两个不同月份的观测相减不是利差；
    # 「利差」这个词本身也要求单位是基点而不是百分比。
    for fn in ("spreadSeries", "spreadCrossSection"):
        require(f"function {fn}(" in lib["core.js"],
                f"core.js 里必须定义 {fn}（主权利差口径不得散落在页面里）")
        require(f"{fn}: {fn}" in lib["core.js"],
                f"{fn} 必须从 core.js 导出，否则页面拿不到、只会各写一套")
    require("spreadCrossSection" in mon, "监控页必须调 core 的横截面利差，不在页面里手算")
    # 页面里不得再手搓「两条收益率相减 ×100」：口径只能有一处，否则改了 core 也没用
    sovr = mon[mon.index('var S = M.sovereign'):]
    sovr = sovr[:sovr.index("R.crossBars")]
    for bad in (".price - bench", "price - b.price", "- benchPrice", ") * 100"):
        require(bad not in sovr,
                f"主权利差面板里出现了手搓的利差算式 {bad!r} —— 口径必须只在 core 里一处")
    require('data-sv="cs"' in mon and 'data-sv="hist"' in mon,
            "主权利差面板必须有两个视图：相对基准 / 利差历史")
    require('id="p-sovr"' in mon, "缺少主权利差面板")
    require("SOVR" in mon, "主权利差面板必须可由命令行点名（data-fn 里带 SOVR）")
    # 横截面的核心约束：跨期不得相减
    require("同一个数据日" in mon, "横截面利差必须写明只在与基准同一个数据日的国家之间算")
    require("两个时点的混合" in mon,
            "必须写明跨期相减得到的不是利差 —— 这是这张表最容易被误读的地方")
    require("已摘出" in mon, "数据日与基准不同的国家必须逐条摘出并写明，不能悄悄算进去")
    require("不报百分比" in mon or "只报基点" in mon,
            "收益率是水平值，差值必须只报基点，不得报成百分比")
    require("1bp = 0.01 个百分点" in mon, "必须写明基点的定义")
    # 沿用上次的行必须标出来
    require('class="t-chip" title="本轮取数失败' in mon,
            "本轮取数失败的行必须在表里带一枚可见标记（只在说明文字里提一句不算："
            "读者看的是行，不是脚注）")
    require("r.stale" in mon, "必须逐行读上游的 stale 标记")
    require("沿用上次" in mon, "标记文字必须说清是沿用上次，不是刚取到的")
    # 历史视图：缺一边留空，且选的是谁必须说清
    require("两端同一个月都有观测时才算" in mon,
            "利差只在两端同月都有观测时才算，必须写明这个前提")
    require("缺一边就留空、折线断开" in mon, "必须写明缺一边留空且折线断开")
    require("不做前向填充" in mon, "必须写明不做前向填充")
    require("数据驱动，不是写死的一组" in mon,
            "历史视图画哪几个国家必须说明选取规则")
    require("排不进来" in mon,
            "被摘出的国家在历史视图里也排不进来，必须说明，不能让人以为漏了")
    # 绝对值序列的图例与基线口径
    require(mon.count('legendMode:"abs"') >= 2,
            "利差与期限价差都是绝对值序列，两处都必须走 abs 图例口径")
    require('opt.legendMode === "abs" ? 0 : 100' in ren,
            "虚线基线必须按口径选：重基指数画 100，绝对值序列画 0"
            "（利差为负就是低于基准、期限价差为负就是倒挂）")
    # 频率：34 条月频，涨跌不是当日
    require("较前一观测" in mon, "月频序列的涨跌必须写「较前一观测」，不得写成当日")
    require("月频" in mon, "必须写明这批序列是月频")
    # 上游月频桶把 frequency 错标成 daily，页面必须如实指出而不是跟着错标
    require("monthlyFreqLabelBug" in lib["overview.js"],
            "上游月频桶的 frequency 字段与日期轴不一致，模型层必须识别出来")
    require("frequency 字段写成了 daily" in mon,
            "这处上游不一致必须如实写在页面上，不跟着错标也不装看不见")
    # 不重复已有的那张水平表
    require("水平表在" in mon or "不重复" in mon,
            "35 条收益率已在全球市场行情的债券品类里列全，面板必须说明自己只做利差")
    bj = json.loads(read(ROOT / "apps" / "bonds" / "data.json"))
    require(len(bj.get("series") or []) >= 30, "主权债收益率条数过少")
    require("基点" in str(bj.get("note", "")), "主权债数据源应声明涨跌口径是基点")
    require("不是当日" in str(bj.get("note", "")) or "不是当日变动" in str(bj.get("note", "")),
            "主权债数据源应声明涨跌不是当日变动")
    hj = json.loads(read(ROOT / "apps" / "bonds" / "history.json"))
    mhist = (hj.get("monthly") or {})
    require(len(mhist.get("dates") or []) >= 300, "主权债月频历史点数过少")
    require(len(mhist.get("series") or {}) >= 30, "主权债月频历史序列数过少")
    require("不做前向填充" in str(hj.get("note", "")),
            "主权债历史数据源应声明不做前向填充")
    # registry 里 BOND 不得再说「数据在、页面没建」—— 那句已经不成立
    reg = lib["registry.js"]
    require("数据在、页面没建" not in reg,
            "BOND 的卡点说明已过时：35 条收益率在全球市场行情的债券品类里已经列全了")
    require('mn:"SOVR"' in reg, "主权利差必须登记进功能注册表")
    section("主权利差")

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
