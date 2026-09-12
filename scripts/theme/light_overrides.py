#!/usr/bin/env python3
"""为各页生成「浅色主题兜底」CSS，并追加进该页 <style> 末尾。

背景
----
站内每个页面各自内联一套 CSS，配色变量命名不统一，且有数百处写死的色值
（深色面板底、亮色强调文字、白色半透明覆盖层）。`assets/theme.css` 只能接管
常见变量名；写死的部分需要逐页翻转。

做法
----
1. 解析页面 <style>（含 @media 嵌套），取出每条含色值的声明。
2. 按「这条声明在纸色底上会不会瞎」判定是否需要翻转：
   - color：相对亮度 > 0.45 的亮色文字 → 同色相压暗
   - background：近中性的深色底 → 映射到主题变量（--bg / --panel / --tint-*）
                 白色半透明覆盖层 → 按 alpha 映射到 --tint-*
                 **饱和色一律保留**（热力图瓦片、涨跌徽标等属于数据编码）
   - border-color：白色半透明 → --line / --line-strong
   - box-shadow：黑色阴影 → 暖色浅阴影
3. 生成 `html[data-theme="ft"] <选择器>, html[data-theme="paper"] <选择器>{…}`，
   追加到该页 <style> 末尾，用注释横幅标出。

安全性
------
- 只生成 `html[data-theme="ft"|"paper"]` 前缀的规则，**深色分支零改动**。
- @keyframes 内不生成（动画里的发光色在浅底上无害）。
- 幂等：重复运行先删除上一次生成的横幅区块再重写。

用法
----
    python3 scripts/theme/light_overrides.py            # 写入
    python3 scripts/theme/light_overrides.py --dry-run  # 只打印统计
"""
from __future__ import annotations

import argparse
import colorsys
import glob
import re
import sys

BANNER_START = "/* ==== 浅色主题兜底（自动生成 · scripts/theme/light_overrides.py · 勿手改）==== */"
BANNER_END = "/* ==== 浅色主题兜底 结束 ==== */"

SKIP_PREFIXES = (".git/", "home-redesign/", "docs/", "node_modules/")

# 画面由整屏 canvas / iframe 主导、固定深色的页面：不生成浅色覆盖
LOCKED = {
    "apps/telescope/index.html",
    "apps/fish-lab/index.html",
    "apps/mosquito-lab/index.html",
    "games/gta-vice-city/index.html",
    "games/red-alert/index.html",
}
# 只被锁定页面引用的样式表，同样跳过
LOCKED_CSS = {"apps/telescope/styles.css"}

# assets/theme.css 已经手工调过的变量名：生成器不再自动推导，避免覆盖调色决定
THEME_OWNED = {
    "ac", "ac2", "accent", "accent2", "act", "amber", "amber-soft", "amber2", "aqua",
    "bear", "bg", "blue", "brand", "brand2", "bull", "calm", "card", "cyan",
    "cyan-soft", "dim", "dn", "down", "down-soft", "faint", "fear", "fear2", "gold",
    "gold-dim", "gold2", "greed", "greed2", "green", "head", "high", "hol", "hot",
    "ink", "ink-strong", "jade", "line", "line-strong", "line2", "link", "low", "med",
    "mint", "mint2", "mist", "muted", "neu", "neutral", "nodata", "on-accent",
    "overlay-bg", "overlay-ink", "panel", "panel-strong", "panel2", "paper", "purple",
    "red", "rule", "shade-1", "shade-2", "shadow-1", "shadow-2", "sheet", "sticky-bg",
    "stress", "teal", "text", "theme-name", "tint-1", "tint-2", "tint-3", "tint-line",
    "track", "up", "up-soft", "violet", "warn",
}

# 自动推导会判错的地方，在这里显式声明。
# (文件, 选择器, 属性) → "keep" 表示保持深色主题的原值不翻转，或直接给定新值。
# 变量级例外：(文件, 变量名) → "keep"
VAR_EXCEPTIONS = {
    # 瓦片底色是数据色阶（红→灰→绿），浅色主题下不翻转；
    # 这两个墨色由脚本按瓦片亮度配对选用，一并保持原值。
    ("apps/heatmap/index.html", "tile-ink-light"): "keep",
    ("apps/heatmap/index.html", "tile-ink-dark"): "keep",
}

EXCEPTIONS = {
    # 持仓条是三段强调色填充，段内文字必须是浅色（父级选择器上看不出底色）
    ("apps/superinvestors/index.html", ".wbar span", "color"): "var(--on-accent)",
}

COLOR_RE = re.compile(r"#[0-9a-fA-F]{3,8}\b|rgba?\([^)]*\)")

# ── 色值解析 ────────────────────────────────────────────────────────────────


def parse_color(tok: str):
    """色值字面量 → (r, g, b, a)；解析不了返回 None。"""
    t = tok.strip().lower()
    if t.startswith("#"):
        h = t[1:]
        if len(h) == 3:
            r, g, b = (int(c * 2, 16) for c in h)
            return r, g, b, 1.0
        if len(h) == 4:
            r, g, b, a = (int(c * 2, 16) for c in h)
            return r, g, b, a / 255
        if len(h) == 6:
            return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 1.0
        if len(h) == 8:
            return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), int(h[6:8], 16) / 255
        return None
    m = re.match(r"rgba?\(([^)]*)\)", t)
    if not m:
        return None
    parts = [p.strip() for p in re.split(r"[,/\s]+", m.group(1)) if p.strip()]
    if len(parts) < 3:
        return None
    try:
        vals = []
        for p in parts[:3]:
            vals.append(float(p[:-1]) * 255 / 100 if p.endswith("%") else float(p))
        a = 1.0
        if len(parts) > 3:
            a = float(parts[3][:-1]) / 100 if parts[3].endswith("%") else float(parts[3])
        return vals[0], vals[1], vals[2], a
    except ValueError:
        return None


def luminance(c) -> float:
    def f(x):
        x /= 255
        return x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])


def saturation(c) -> float:
    return colorsys.rgb_to_hls(c[0] / 255, c[1] / 255, c[2] / 255)[2]


def chroma(c) -> float:
    """绝对彩度（0–255）。深色区间里 HLS 饱和度会失真，用它判断是否近中性。"""
    return max(c[0], c[1], c[2]) - min(c[0], c[1], c[2])


PAPER = (255, 241, 229)   # FT 纸色，浅色主题里对比度最紧的一档底色


def contrast_on(c, bg=PAPER) -> float:
    l1, l2 = luminance(c), luminance(bg)
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def darken_for_contrast(c, target: float = 4.6, sat_cap: float = 0.8) -> str:
    """保留色相与饱和度，把亮度压到刚好满足 target 对比度（纸色底）。"""
    h, l, sat = colorsys.rgb_to_hls(c[0] / 255, c[1] / 255, c[2] / 255)
    # 近白/近黑的 HLS 饱和度会虚高（#f4f7fb 算出来 0.7），压暗时会凭空长出蓝紫色。
    # 用绝对彩度重新约束：原色几乎无彩，结果也必须几乎无彩。
    sat = min(sat, sat_cap, max(chroma(c) / 140.0, 0.02))
    lo, hi = 0.0, max(l, 0.02)
    for _ in range(22):
        mid = (lo + hi) / 2
        r, g, b = colorsys.hls_to_rgb(h, mid, sat)
        if contrast_on((r * 255, g * 255, b * 255)) >= target:
            lo = mid
        else:
            hi = mid
    r, g, b = colorsys.hls_to_rgb(h, lo, sat)
    out = (round(r * 255), round(g * 255), round(b * 255))
    if len(c) > 3 and c[3] < 0.95:      # 半透明的柔光/高亮：压暗但保持透明度
        return "rgba(%d,%d,%d,%s)" % (out[0], out[1], out[2], ("%.3f" % c[3]).rstrip("0").rstrip("."))
    return "#%02x%02x%02x" % out


def darken_to(c, light: float, sat_cap: float = 0.72) -> str:
    """保留色相，把亮度压到 light，得到能在纸色底上读的深色。"""
    h, _, s = colorsys.rgb_to_hls(c[0] / 255, c[1] / 255, c[2] / 255)
    s = min(s, sat_cap)
    r, g, b = colorsys.hls_to_rgb(h, light, s)
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def tint_token(alpha: float) -> str:
    if alpha <= 0.035:
        return "var(--tint-1)"
    if alpha <= 0.06:
        return "var(--tint-2)"
    if alpha <= 0.14:
        return "var(--tint-3)"
    return "var(--tint-line)"


# ── 单个色值的翻转规则 ──────────────────────────────────────────────────────


def map_color(tok: str, prop: str, ctx: dict | None = None):
    """返回浅色模式下应使用的值；None 表示这条不用改。

    ctx: {"on_accent": bool, "is_page": bool} —— on_accent 表示该块自带强调色底
         （其上的白字继续用白字），is_page 表示选择器是 body/html（极深底映射到页面底色）。
    """
    ctx = ctx or {}
    c = parse_color(tok)
    if c is None:
        return None
    r, g, b, a = c
    lum = luminance(c)
    sat = saturation(c)
    chr_ = chroma(c)
    # 深色区间的 HLS 饱和度会失真（rgba(12,18,27) 算出来 0.38），用绝对彩度兜底
    near_neutral = sat < 0.34 or chr_ <= 72
    is_white = r > 236 and g > 236 and b > 236
    # 「近中性的深色表面」：亮度低且彩度小
    dark_surface = lum < 0.16 and chr_ <= 90
    very_dark = lum < 0.055 and chr_ <= 90

    if prop == "color" or prop == "caret-color" or prop == "-webkit-text-fill-color":
        if a < 0.25:
            return None
        if is_white:
            if ctx.get("on_accent"):
                return None          # 强调色底上的白字，纸色主题下照旧
            return "var(--ink)" if a >= 0.95 else "var(--dim)"
        if ctx.get("on_accent"):
            # 强调色底：浅色主题里强调色本身变深，原本压在上面的深色文字要反过来变浅
            if a >= 0.85 and luminance(c) < 0.2:
                return "var(--on-accent)"
            return None                      # 浅色文字压在强调色上，照旧
        if contrast_on(c) < 4.0:             # 纸色底上读不清 → 同色相压到 AA
            return darken_for_contrast(c)
        return None                          # 本来就够深，纸底上没问题

    if prop in ("background", "background-color"):
        if a < 0.9:                          # 半透明覆盖层
            if is_white:
                return tint_token(a)
            if dark_surface:
                if a >= 0.75:
                    return "var(--sticky-bg)" if ctx.get("is_sticky") else "var(--panel)"
                return tint_token(min(a * 0.16, 0.13))
            return None                      # 有色半透明（高亮/选中）保留
        if very_dark:
            # body/html 的极深底 = 页面底色；其余元件是「比页面深一档」的表面
            return "var(--bg)" if ctx.get("is_page") else "var(--panel2)"
        if dark_surface:
            return "var(--panel)"
        if near_neutral and lum < 0.30:
            return "var(--panel2)"
        if is_white:
            return "var(--panel)"
        return None                          # 饱和色 = 数据编码，保留

    if prop.startswith("border") or prop == "outline" or prop == "outline-color":
        if is_white and a < 0.9:
            return "var(--line)" if a <= 0.14 else "var(--line-strong)"
        if is_white:
            return "var(--line-strong)"
        if dark_surface:
            return "var(--line)"
        if lum > 0.55 and sat >= 0.34:       # 亮色描边压暗，保持色相
            return darken_to(c, 0.42)
        return None

    if "shadow" in prop:
        if very_dark or (r < 26 and g < 26 and b < 26):
            return "rgba(120,92,64,%.2f)" % min(a * 0.45, 0.2)
        if is_white and a > 0.15:
            return "rgba(120,92,64,%.2f)" % min(a * 0.3, 0.14)
        return None

    if prop in ("fill", "stroke", "stop-color"):
        if is_white:
            return "var(--ink)"
        if contrast_on(c) < 3.0:
            return darken_for_contrast(c, 3.2)
        if dark_surface:
            return "var(--line)"
        return None

    return None


# 这些变量名代表「强调色/语义色」而非中性表面：其上的白字在浅色主题下仍应是白字
ACCENT_VARS = {
    "accent", "accent2", "blue", "cyan", "teal", "aqua", "brand", "brand2", "link",
    "up", "down", "dn", "red", "green", "mint", "mint2", "gold", "gold2", "amber",
    "amber2", "warn", "purple", "violet", "ac", "ac2", "high", "hot", "low", "med",
    "fear", "fear2", "greed", "greed2", "bull", "bear", "stress", "calm", "jade",
    "neutral", "neu", "act", "qs", "the", "arwu", "usn", "arena", "lb", "aa",
}
VAR_RE = re.compile(r"var\(\s*--([a-z0-9-]+)", re.I)


def on_accent(decls_text: str) -> bool:
    """这个规则块自己铺了强调色/饱和色底吗？"""
    for m in re.finditer(r"(background|background-color)\s*:\s*([^;{}]+)", decls_text, re.I):
        val = m.group(2)
        for v in VAR_RE.findall(val):
            if v in ACCENT_VARS:
                return True
        for tok in COLOR_RE.findall(val):
            c = parse_color(tok)
            if c and c[3] >= 0.85 and saturation(c) >= 0.34 and 0.18 < luminance(c) < 0.75:
                return True
        if "gradient" in val.lower():
            # 渐变里有饱和中间调才算强调色底；深色渐变面板不算
            for tok in COLOR_RE.findall(val):
                c = parse_color(tok)
                if c and c[3] >= 0.5 and saturation(c) >= 0.4 and 0.2 < luminance(c) < 0.72:
                    return True
    return False


# ── 极简 CSS 遍历 ───────────────────────────────────────────────────────────

PROPS = re.compile(
    r"(color|background|background-color|border|border-color|border-top|border-bottom|"
    r"border-left|border-right|border-top-color|border-bottom-color|border-left-color|"
    r"border-right-color|outline|outline-color|box-shadow|text-shadow|fill|stroke|"
    r"stop-color|caret-color|-webkit-text-fill-color)\s*:\s*([^;{}]+)",
    re.I,
)


COMMENT_RE = re.compile(r"/\*.*?\*/", re.S)


def strip_comments(css: str) -> str:
    return COMMENT_RE.sub(" ", css)


def walk(css: str):
    """产出 (at_rule_stack, selector, declarations_text)。"""
    out, i, n = [], 0, len(css)
    stack, buf = [], ""
    while i < n:
        ch = css[i]
        if ch == "{":
            head = buf.strip()
            buf = ""
            depth, j = 1, i + 1
            while j < n and depth:
                if css[j] == "{":
                    depth += 1
                elif css[j] == "}":
                    depth -= 1
                j += 1
            body = css[i + 1:j - 1]
            if head.startswith("@"):
                at = head.split("{")[0].strip()
                if at.lower().startswith(("@keyframes", "@-webkit-keyframes", "@font-face", "@media print")):
                    pass  # 动画帧 / 字体 / 打印样式不生成覆盖
                else:
                    for st2, sel2, decl2 in walk(body):
                        out.append(([at] + st2, sel2, decl2))
            else:
                out.append(([], head, body))
            i = j
            continue
        buf += ch
        i += 1
    return out


def selectors_of(head: str):
    return [re.sub(r"\s+", " ", s).strip() for s in head.split(",") if s.strip()]


def scope(sel: str) -> str:
    """把选择器挂到两个浅色主题下。"""
    if sel.startswith(("html", ":root")):
        return None  # 变量块单独处理，见 root_overrides()
    return 'html[data-theme="ft"] %s, html[data-theme="paper"] %s' % (sel, sel)


VARDECL_RE = re.compile(r"--([a-z0-9-]+)\s*:\s*([^;{}]+)", re.I)


def map_var_value(val: str):
    """自定义属性的取值映射；返回新值或 None。"""
    toks = COLOR_RE.findall(val)
    if not toks:
        return None                      # 字体栈、尺寸等非颜色变量
    newval, touched = val.strip().rstrip(";"), False
    for t in dict.fromkeys(toks):
        c = parse_color(t)
        if not c:
            continue
        lum_, chr_, a = luminance(c), chroma(c), c[3]
        is_white = c[0] > 236 and c[1] > 236 and c[2] > 236
        if a >= 0.9 and lum_ < 0.16 and chr_ <= 90:
            mapped = "var(--panel2)" if lum_ < 0.055 else "var(--panel)"
        elif a < 0.9 and is_white:
            mapped = tint_token(a)
        elif contrast_on(c) < 4.0:
            mapped = darken_for_contrast(c)     # 透明度由 darken_for_contrast 保留
        else:
            continue
        newval = re.sub(re.escape(t), mapped, newval, flags=re.I)
        touched = True
    return newval if touched else None


def root_overrides(css: str, path: str = ""):
    """页面 :root 里 theme.css 没接管的颜色变量，按同一套规则自动推导浅色取值。

    典型是各页私有的命名：--card-2、--mc、--qs/--the/--arwu、--tile-ink-light…
    """
    out = {}
    for at_stack, head, body in walk(strip_comments(css)):
        if head is None or at_stack:
            continue
        if not any(x.startswith((":root", "html")) for x in selectors_of(head)):
            continue
        for name, val in VARDECL_RE.findall(body):
            key = name.lower()
            if key in THEME_OWNED or key in out:
                continue
            if VAR_EXCEPTIONS.get((path, key)) == "keep":
                continue
            mapped = map_var_value(val)
            if mapped:
                out[key] = mapped
    return out


PAGE_SEL_RE = re.compile(r"^(html|body|:root)\b", re.I)


def build_overrides(css: str, path: str = ""):
    rules, stats = {}, {"decl": 0, "sel": 0, "vars": 0}
    for name, val in root_overrides(css, path).items():
        key = ((), 'html[data-theme="ft"], html[data-theme="paper"]')
        rules.setdefault(key, [])
        rules[key].append("--%s: %s" % (name, val))
        stats["vars"] += 1
    for at_stack, head, body in walk(strip_comments(css)):
        if head is None or not head or head.startswith("@"):
            continue
        changed = []
        # 渐变文字（-webkit-background-clip:text + 透明填充）在纸色底上必然读不清，
        # 浅色主题下统一回落为纯墨色。
        if re.search(r"background-clip\s*:\s*text", body, re.I):
            changed.append("background: none")
            changed.append("-webkit-background-clip: border-box")
            changed.append("background-clip: border-box")
            changed.append("-webkit-text-fill-color: currentColor")
            changed.append("color: var(--ink)")
            stats["decl"] += 1
        ctx = {
            "on_accent": on_accent(body),
            "is_page": any(PAGE_SEL_RE.match(x) for x in selectors_of(head)),
            "is_sticky": bool(re.search(r"position\s*:\s*(sticky|fixed)|backdrop-filter", body, re.I)),
        }
        # 局部自定义属性（如 .board-tab[data-category] { --accent: #f2bd5c }）
        # 这类声明挂在元素上，assets/theme.css 的全局变量覆盖不到，必须逐条映射
        for name, val in VARDECL_RE.findall(body):
            mapped = map_var_value(val)
            if mapped:
                changed.append("--%s: %s" % (name, mapped))
                stats["decl"] += 1

        for m in PROPS.finditer(body):
            prop, val = m.group(1).lower(), m.group(2).strip()
            if "var(--" in val and not COLOR_RE.search(val):
                continue
            toks = COLOR_RE.findall(val)
            if not toks:
                continue
            newval, touched = val, False
            for t in dict.fromkeys(toks):
                mapped = map_color(t, prop, ctx)
                if mapped:
                    newval = re.sub(re.escape(t), mapped, newval, flags=re.I)
                    touched = True
            if touched:
                imp = " !important" if "!important" in val else ""
                newval = newval.replace("!important", "").strip().rstrip(";")
                changed.append("%s: %s%s" % (prop, newval, imp))
                stats["decl"] += 1
        # 人工例外：自动推导判错的少数位置
        for sel in selectors_of(head):
            for pr in ("color", "background", "background-color"):
                ex = EXCEPTIONS.get((path, sel, pr))
                if ex is None:
                    continue
                changed = [c for c in changed if not c.startswith(pr + ":")]
                if ex != "keep":
                    changed.append("%s: %s" % (pr, ex))
        if not changed:
            continue
        for sel in selectors_of(head):
            sc = scope(sel)
            if not sc:
                continue
            key = (tuple(at_stack), sc)
            rules.setdefault(key, [])
            for c in changed:
                if c not in rules[key]:
                    rules[key].append(c)
            stats["sel"] += 1
    return rules, stats


def render(rules) -> str:
    by_at = {}
    for (at_stack, sel), decls in rules.items():
        by_at.setdefault(at_stack, []).append((sel, decls))
    lines = [BANNER_START]
    for at_stack in sorted(by_at, key=lambda s: (len(s), s)):
        body = []
        for sel, decls in by_at[at_stack]:
            body.append("%s { %s; }" % (sel, "; ".join(decls)))
        if at_stack:
            lines.append(" ".join(at_stack) + " {")
            lines.extend("  " + b for b in body)
            lines.append("}")
        else:
            lines.extend(body)
    lines.append(BANNER_END)
    return "\n".join(lines) + "\n"


def process_css(path: str, dry: bool):
    """独立样式表：把覆盖区块追加到文件末尾。"""
    src = open(path, encoding="utf-8").read()
    src_clean = re.sub(
        r"[ \t]*" + re.escape(BANNER_START) + r".*?" + re.escape(BANNER_END) + r"[ \t]*\n?",
        "", src, flags=re.S,
    )
    rules, stats = build_overrides(src_clean, path)
    out = src_clean if not rules else src_clean.rstrip("\n") + "\n\n" + render(rules)
    if not dry and out != src:
        open(path, "w", encoding="utf-8").write(out)
    stats["bytes"] = len(render(rules)) if rules else 0
    return stats


def process(path: str, dry: bool):
    src = open(path, encoding="utf-8").read()
    # 先移除上一次生成的区块（幂等）
    src_clean = re.sub(
        r"[ \t]*" + re.escape(BANNER_START) + r".*?" + re.escape(BANNER_END) + r"[ \t]*\n?",
        "", src, flags=re.S,
    )
    blocks = list(re.finditer(r"<style[^>]*>(.*?)</style>", src_clean, re.S))
    if not blocks:
        return None
    css = "\n".join(b.group(1) for b in blocks)
    rules, stats = build_overrides(css, path)
    if not rules:
        if src_clean != src and not dry:
            open(path, "w", encoding="utf-8").write(src_clean)
        return stats
    block = render(rules)
    last = blocks[-1]
    # 插入点之前可能残留只含空格的空行（历史上的清理留下的），一并规整
    head = src_clean[:last.end(1)].rstrip(" \t\n")
    out = head + "\n" + block + src_clean[last.end(1):]
    if not dry:
        open(path, "w", encoding="utf-8").write(out)
    stats["bytes"] = len(block)
    return stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("paths", nargs="*")
    a = ap.parse_args()
    if a.paths:
        files = a.paths
    else:
        files = sorted(
            p for p in glob.glob("**/*.html", recursive=True)
            if not p.startswith(SKIP_PREFIXES) and p not in LOCKED
        ) + sorted(
            p for p in glob.glob("**/*.css", recursive=True)
            if not p.startswith(SKIP_PREFIXES) and p not in LOCKED_CSS
            and p != "assets/theme.css"
        )
    tot_d = tot_b = 0
    for p in files:
        st = process_css(p, a.dry_run) if p.endswith(".css") else process(p, a.dry_run)
        if not st:
            continue
        tot_d += st["decl"]
        tot_b += st.get("bytes", 0)
        print("%-46s 翻转声明 %3d  变量 %2d  选择器 %3d  +%s"
              % (p, st["decl"], st.get("vars", 0), st["sel"], f"{st.get('bytes',0)}B"))
    print("\n合计：翻转 %d 条声明，页面体积共增加 %.1f KB%s"
          % (tot_d, tot_b / 1024, "（dry-run，未写入）" if a.dry_run else ""))


if __name__ == "__main__":
    sys.exit(main())
