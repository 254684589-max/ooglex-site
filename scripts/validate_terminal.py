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
    section("类名不得撞名")

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
