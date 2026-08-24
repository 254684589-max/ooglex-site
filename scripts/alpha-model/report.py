#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把模型输出渲染成自包含的静态 HTML 报告，双击即可用浏览器打开。

刻意不做成 Streamlit 之类的服务端应用：
  · 不占端口，不用管进程，不和别的本地应用抢 8501/8502；
  · 不引入 streamlit / pandas / numpy，保持零新增依赖；
  · 单文件可归档、可发给别人、可离线看。

因此所有数据在生成时就渲染进 HTML，页面不做任何 fetch——
`file://` 协议下的 fetch 会被 CORS 挡掉，靠外部 JSON 的页面在本地打不开。
"""

import html
import json
import os
from datetime import datetime

# ---------------------------------------------------------------------------
# 配色：取自校验过的默认调色板。单序列用蓝，正负发散用蓝↔红，状态色另成一套。
# 明暗两套都跑过对比度、色觉障碍分离度与色度下限检查。
# ---------------------------------------------------------------------------
CSS = """
:root {
  color-scheme: light;
  --surface-0: #f4f3f0;
  --surface-1: #fcfcfb;
  --surface-2: #eceae5;
  --border:    #dcd9d2;
  --grid:      #e7e4dd;
  --ink-1:     #0b0b0b;
  --ink-2:     #52514e;
  --ink-3:     #82807a;
  --series-1:  #2a78d6;
  --series-1-wash: rgba(42, 120, 214, 0.10);
  --neg:       #e34948;
  --good:      #0ca30c;
  --warning:   #fab219;
  --critical:  #d03b3b;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    color-scheme: dark;
    --surface-0: #131312;
    --surface-1: #1a1a19;
    --surface-2: #242422;
    --border:    #3a3a37;
    --grid:      #2e2e2b;
    --ink-1:     #ffffff;
    --ink-2:     #c3c2b7;
    --ink-3:     #8f8e85;
    --series-1:  #3987e5;
    --series-1-wash: rgba(57, 135, 229, 0.14);
    --neg:       #e66767;
  }
}
:root[data-theme="dark"] {
  color-scheme: dark;
  --surface-0: #131312;
  --surface-1: #1a1a19;
  --surface-2: #242422;
  --border:    #3a3a37;
  --grid:      #2e2e2b;
  --ink-1:     #ffffff;
  --ink-2:     #c3c2b7;
  --ink-3:     #8f8e85;
  --series-1:  #3987e5;
  --series-1-wash: rgba(57, 135, 229, 0.14);
  --neg:       #e66767;
}

* { box-sizing: border-box; }
body {
  margin: 0;
  padding: 0 16px 64px;
  background: var(--surface-0);
  color: var(--ink-1);
  font: 15px/1.6 -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB",
        "Microsoft YaHei", "Segoe UI", Roboto, sans-serif;
  -webkit-font-smoothing: antialiased;
}
.wrap { max-width: 1180px; margin: 0 auto; }

header { padding: 32px 0 20px; }
h1 { font-size: 26px; font-weight: 650; margin: 0 0 4px; letter-spacing: -0.01em; }
.sub { color: var(--ink-2); font-size: 14px; margin: 0; }
h2 {
  font-size: 17px; font-weight: 650; margin: 40px 0 6px;
  padding-top: 24px; border-top: 1px solid var(--border);
}
h2:first-of-type { border-top: none; padding-top: 0; }
.note { color: var(--ink-2); font-size: 13px; margin: 0 0 18px; max-width: 70ch; }

.badges { display: flex; flex-wrap: wrap; gap: 8px; margin: 16px 0 0; }
.badge {
  font-size: 12px; padding: 4px 10px; border-radius: 999px;
  background: var(--surface-2); color: var(--ink-2);
  border: 1px solid var(--border); white-space: nowrap;
}
.badge.demo { background: var(--warning); color: #1a1a19; border-color: var(--warning); font-weight: 600; }
.badge.ok { color: var(--good); border-color: var(--good); background: transparent; }
.badge.bad { color: var(--critical); border-color: var(--critical); background: transparent; }

.tiles { display: grid; gap: 10px; grid-template-columns: repeat(auto-fit, minmax(158px, 1fr)); }
.tile {
  background: var(--surface-1); border: 1px solid var(--border);
  border-radius: 10px; padding: 14px 16px;
}
.tile .label { font-size: 12px; color: var(--ink-2); margin-bottom: 6px; }
.tile .value { font-size: 27px; font-weight: 640; letter-spacing: -0.02em; font-variant-numeric: tabular-nums; }
.tile .hint { font-size: 12px; color: var(--ink-3); margin-top: 4px; }

figure { margin: 0; background: var(--surface-1); border: 1px solid var(--border);
         border-radius: 10px; padding: 18px 20px 12px; }
figure svg { margin: 0 auto; }
figcaption { font-size: 12px; color: var(--ink-3); margin-top: 10px; }
.chart-scroll { overflow-x: auto; }
svg { display: block; max-width: 100%; height: auto; }
svg text { font: 11px -apple-system, "PingFang SC", sans-serif; fill: var(--ink-2); }
svg .axis-line { stroke: var(--grid); stroke-width: 1; }
svg .bar { fill: var(--series-1); }
svg .bar.neg { fill: var(--neg); }
svg .bar:hover { opacity: 0.75; cursor: default; }
svg .thresh { stroke: var(--critical); stroke-width: 1; }
svg .thresh-label { fill: var(--critical); font-weight: 600; }

.table-scroll { overflow-x: auto; -webkit-overflow-scrolling: touch; }
table { border-collapse: collapse; width: 100%; font-size: 13px; min-width: 720px; }
th {
  text-align: left; font-weight: 600; color: var(--ink-2); font-size: 12px;
  padding: 8px 10px; border-bottom: 1px solid var(--border); white-space: nowrap;
}
th.num, td.num { text-align: right; font-variant-numeric: tabular-nums; }
td { padding: 9px 10px; border-bottom: 1px solid var(--grid); vertical-align: middle; }
tbody tr:hover { background: var(--series-1-wash); }
tbody tr.cand { background: var(--series-1-wash); }
.sym { font-weight: 640; letter-spacing: 0.01em; }
.muted { color: var(--ink-3); }
.tag { font-size: 11px; color: var(--ink-2); background: var(--surface-2);
       border-radius: 4px; padding: 1px 6px; white-space: nowrap; }

.mbar { display: flex; align-items: center; gap: 8px; }
.mbar .track {
  display: block; width: 56px; flex: none; height: 7px;
  background: var(--surface-2); border-radius: 999px; overflow: hidden;
}
.mbar .fill { display: block; height: 7px; background: var(--series-1); border-radius: 0 4px 4px 0; }
.mbar .fill.zero { border-radius: 999px; }
.mbar .n { font-variant-numeric: tabular-nums; font-size: 12px; color: var(--ink-2);
           min-width: 26px; text-align: right; }
.kv .mbar .track { width: 100%; max-width: 260px; }
.na { font-size: 12px; color: var(--ink-3); }
table.sub { min-width: 620px; }
table.sub td { white-space: nowrap; }
.dbar { position: relative; display: inline-block; width: 84px; height: 7px;
        background: var(--surface-2); border-radius: 999px; vertical-align: middle;
        margin-right: 8px; overflow: hidden; }
.dbar::after { content: ""; position: absolute; left: 50%; top: 0; bottom: 0;
               width: 1px; background: var(--border); }
.dfill { position: absolute; top: 0; height: 7px; border-radius: 2px; }
.dnum { font-variant-numeric: tabular-nums; font-size: 12px; }

details { background: var(--surface-1); border: 1px solid var(--border);
          border-radius: 10px; padding: 0; margin-bottom: 8px; }
summary { padding: 12px 16px; cursor: pointer; font-size: 14px; list-style: none;
          display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
summary::-webkit-details-marker { display: none; }
summary::before { content: "▸"; color: var(--ink-3); font-size: 11px; }
details[open] summary::before { content: "▾"; }
summary:focus-visible { outline: 2px solid var(--series-1); outline-offset: -2px; }
.detail-body { padding: 4px 16px 16px 30px; border-top: 1px solid var(--grid); }
.kv { display: grid; grid-template-columns: 96px 1fr; gap: 6px 14px; font-size: 13px;
      align-items: center; margin-top: 12px; }
.kv .k { color: var(--ink-2); font-size: 12px; }
ul.reasons { margin: 10px 0 0; padding-left: 18px; font-size: 13px; color: var(--ink-2); }
ul.reasons li { margin: 3px 0; }

.checks { list-style: none; padding: 0; margin: 0; }
.checks li { display: flex; align-items: baseline; gap: 10px; padding: 9px 0;
             border-bottom: 1px solid var(--grid); font-size: 14px; flex-wrap: wrap; }
.checks .mark { font-weight: 700; font-size: 13px; min-width: 62px; }
.checks .pass .mark, .mark.pass { color: var(--good); }
.checks .fail .mark, .mark.fail { color: var(--critical); }
.checks .detail { color: var(--ink-3); font-size: 12px; font-variant-numeric: tabular-nums; }

.callout { background: var(--surface-1); border: 1px solid var(--border);
           border-left: 3px solid var(--warning); border-radius: 8px;
           padding: 14px 16px; font-size: 13px; color: var(--ink-2); }
.callout strong { color: var(--ink-1); }
.callout ul { margin: 8px 0 0; padding-left: 18px; }
.callout li { margin: 4px 0; }

footer { margin-top: 44px; padding-top: 18px; border-top: 1px solid var(--border);
         font-size: 12px; color: var(--ink-3); }
#tt {
  position: fixed; pointer-events: none; opacity: 0; transition: opacity .1s;
  background: var(--surface-1); border: 1px solid var(--border); border-radius: 7px;
  padding: 7px 10px; font-size: 12px; color: var(--ink-1); z-index: 99;
  box-shadow: 0 4px 14px rgba(0,0,0,.13); white-space: nowrap;
}
#themer {
  position: fixed; top: 12px; right: 12px; z-index: 100;
  background: var(--surface-1); color: var(--ink-2); border: 1px solid var(--border);
  border-radius: 999px; padding: 6px 13px; font-size: 12px; cursor: pointer;
}
@media (max-width: 640px) {
  body { padding: 0 12px 48px; }
  h1 { font-size: 21px; }
  .tile .value { font-size: 23px; }
  .kv { grid-template-columns: 84px 1fr; }
  #themer { top: 8px; right: 8px; }
}
@media (prefers-reduced-motion: reduce) { * { transition: none !important; } }
"""

JS = """
(function () {
  var tt = document.getElementById('tt');
  function show(e, text) {
    tt.textContent = text;
    tt.style.opacity = '1';
    var x = e.clientX + 14, y = e.clientY + 14;
    var box = tt.getBoundingClientRect();
    if (x + box.width > window.innerWidth - 8) x = e.clientX - box.width - 14;
    if (y + box.height > window.innerHeight - 8) y = e.clientY - box.height - 14;
    tt.style.left = x + 'px'; tt.style.top = y + 'px';
  }
  document.querySelectorAll('[data-tip]').forEach(function (el) {
    el.addEventListener('mousemove', function (e) { show(e, el.getAttribute('data-tip')); });
    el.addEventListener('mouseleave', function () { tt.style.opacity = '0'; });
  });
  var btn = document.getElementById('themer');
  function label() {
    var t = document.documentElement.getAttribute('data-theme');
    btn.textContent = t === 'dark' ? '浅色' : (t === 'light' ? '深色' : '切换主题');
  }
  btn.addEventListener('click', function () {
    var cur = document.documentElement.getAttribute('data-theme');
    var dark = cur ? cur === 'dark'
      : window.matchMedia('(prefers-color-scheme: dark)').matches;
    document.documentElement.setAttribute('data-theme', dark ? 'light' : 'dark');
    label();
    try { localStorage.setItem('ooglexAlphaTheme', dark ? 'light' : 'dark'); } catch (err) {}
  });
  try {
    var saved = localStorage.getItem('ooglexAlphaTheme');
    if (saved) document.documentElement.setAttribute('data-theme', saved);
  } catch (err) {}
  label();
})();
"""


# ---------------------------------------------------------------------------
# 小工具
# ---------------------------------------------------------------------------
def esc(value):
    """所有来自接口的文本都必须转义后再拼进 HTML。

    公司名、行业名来自 Yahoo，属于不可信外部输入；直接拼接等于开一个注入口子。
    """
    return html.escape("" if value is None else str(value), quote=True)


def num(value, digits=2, dash="—"):
    if value is None:
        return dash
    return f"{value:.{digits}f}"


def pct(value, digits=1, dash="—"):
    if value is None:
        return dash
    return f"{value * 100:.{digits}f}%"


def _plain_bar(score):
    """只有条、没有数字的版本：同一行里数字已经在旁边一列，不必重复。"""
    if score is None:
        return '<span class="na">—</span>'
    width = max(0.0, min(100.0, score))
    radius = " zero" if width < 2 else ""
    return (f'<span class="mbar"><span class="track">'
            f'<span class="fill{radius}" style="width:{width:.1f}%"></span></span></span>')


def mini_bar(score, tip=None):
    """表格内联分数条：0–100 一根细条 + 数字。数字保证读数不依赖颜色。"""
    if score is None:
        return '<span class="na">无数据</span>'
    width = max(0.0, min(100.0, score))
    radius = ' zero' if width < 2 else ''
    attr = f' data-tip="{esc(tip)}"' if tip else ""
    return (f'<span class="mbar"{attr}><span class="track">'
            f'<span class="fill{radius}" style="width:{width:.1f}%"></span></span>'
            f'<span class="n">{score:.0f}</span></span>')


# ---------------------------------------------------------------------------
# 图表
# ---------------------------------------------------------------------------
CHART_W = 1120        # 与内容容器同宽，使 1 个 viewBox 单位 ≈ 1 CSS 像素：
                      # 否则 SVG 被放大后，11px 字号会渲染成 28px、柱宽远超 24px 上限。
MAX_BAR = 24.0        # marks 规范：柱子不得填满整个槽位，留白由槽位余量承担


def histogram_svg(bins, threshold=80.0, threshold_label=None):
    """分数分布直方图。

    单序列，所以只用一个色相、不加图例——标题已经说明画的是什么。
    ≥80 处画一条阈值线并直接标注，因为整张图要说的就是那一件事：
    总分是分位数的加权平均，分布呈钟形，80 分位于极端尾部而不是“前 20%”。
    """
    if not bins:
        return '<p class="na">无分布数据</p>'
    width, height = CHART_W, 236
    pad_l, pad_r, pad_t, pad_b = 38, 16, 16, 32
    plot_w = width - pad_l - pad_r
    plot_h = height - pad_t - pad_b
    top = max(b["count"] for b in bins) or 1
    slot = plot_w / len(bins)
    # 直方图的横轴是连续的，柱子只用 2px 表面间隙分隔，不额外留空——
    # 拉开大间隙会把连续分布画成离散类别。
    bar_w = max(3.0, min(MAX_BAR, slot - 2.0))

    parts = [f'<svg viewBox="0 0 {width} {height}" role="img" '
             f'aria-label="Alpha60 总分分布直方图">']

    # 横轴与刻度
    y0 = pad_t + plot_h
    parts.append(f'<line class="axis-line" x1="{pad_l}" y1="{y0}" x2="{width - pad_r}" y2="{y0}"/>')
    for tick in (0, 20, 40, 60, 80, 100):
        x = pad_l + plot_w * tick / 100.0
        parts.append(f'<text x="{x:.1f}" y="{y0 + 16}" text-anchor="middle">{tick}</text>')
    parts.append(f'<text x="{pad_l - 8}" y="{pad_t + 8}" text-anchor="end">{top}</text>')
    parts.append(f'<text x="{pad_l - 8}" y="{y0}" text-anchor="end">0</text>')

    for i, b in enumerate(bins):
        h = plot_h * b["count"] / top
        x = pad_l + i * slot + (slot - bar_w) / 2.0
        y = y0 - h
        tip = f'{b["lo"]}–{b["hi"]} 分：{b["count"]} 只'
        if b["count"] == 0:
            continue
        # 4px 圆角数据端、基线端为直角
        r = min(4.0, h, bar_w / 2.0)
        parts.append(
            f'<path class="bar" data-tip="{esc(tip)}" d="M{x:.1f},{y0} '
            f'V{y + r:.1f} Q{x:.1f},{y:.1f} {x + r:.1f},{y:.1f} '
            f'H{x + bar_w - r:.1f} Q{x + bar_w:.1f},{y:.1f} {x + bar_w:.1f},{y + r:.1f} '
            f'V{y0} Z"/>')

    if threshold is not None:
        tx = pad_l + plot_w * threshold / 100.0
        parts.append(f'<line class="thresh" x1="{tx:.1f}" y1="{pad_t}" x2="{tx:.1f}" y2="{y0}"/>')
        if threshold_label:
            anchor = "end" if threshold > 55 else "start"
            dx = -6 if threshold > 55 else 6
            parts.append(f'<text class="thresh-label" x="{tx + dx:.1f}" y="{pad_t + 11}" '
                         f'text-anchor="{anchor}">{esc(threshold_label)}</text>')
    parts.append("</svg>")
    return "".join(parts)


def decile_svg(groups):
    """十分组平均超额收益。

    这是有极性的数据（正/负超额），所以用发散配色：蓝为正、红为负，
    零线是中性灰。要看的不是哪一组最高，而是 D1→D10 是不是单调下降。
    """
    if not groups:
        return '<p class="na">无分组数据</p>'
    width, height = CHART_W, 262
    pad_l, pad_r, pad_t, pad_b = 52, 16, 18, 36
    plot_w = width - pad_l - pad_r
    plot_h = height - pad_t - pad_b
    values = [g.get("meanForward") or 0.0 for g in groups]
    span = max(abs(v) for v in values) or 0.01
    span *= 1.15
    zero_y = pad_t + plot_h / 2.0
    slot = plot_w / len(groups)
    bar_w = min(MAX_BAR, max(6.0, slot - 10.0))   # 十个离散分组，柱宽封顶、余量留白

    parts = [f'<svg viewBox="0 0 {width} {height}" role="img" '
             f'aria-label="按模型分数分十组的未来超额收益">']
    parts.append(f'<line class="axis-line" x1="{pad_l}" y1="{zero_y}" '
                 f'x2="{width - pad_r}" y2="{zero_y}"/>')
    for frac, lbl in ((1.0, f"+{span * 100:.0f}%"), (0.0, "0"), (-1.0, f"−{span * 100:.0f}%")):
        y = zero_y - frac * plot_h / 2.0
        parts.append(f'<text x="{pad_l - 8}" y="{y + 4:.1f}" text-anchor="end">{lbl}</text>')

    for i, g in enumerate(groups):
        v = g.get("meanForward") or 0.0
        h = abs(v) / span * (plot_h / 2.0)
        x = pad_l + i * slot + (slot - bar_w) / 2.0
        y = zero_y - h if v >= 0 else zero_y
        cls = "bar" if v >= 0 else "bar neg"
        tip = f'D{g["decile"]}（{g["count"]} 个样本）：平均超额 {v * 100:+.2f}%'
        r = min(4.0, h, bar_w / 2.0)
        if v >= 0:
            path = (f'M{x:.1f},{zero_y} V{y + r:.1f} Q{x:.1f},{y:.1f} {x + r:.1f},{y:.1f} '
                    f'H{x + bar_w - r:.1f} Q{x + bar_w:.1f},{y:.1f} {x + bar_w:.1f},{y + r:.1f} '
                    f'V{zero_y} Z')
        else:
            b = zero_y + h
            path = (f'M{x:.1f},{zero_y} V{b - r:.1f} Q{x:.1f},{b:.1f} {x + r:.1f},{b:.1f} '
                    f'H{x + bar_w - r:.1f} Q{x + bar_w:.1f},{b:.1f} {x + bar_w:.1f},{b - r:.1f} '
                    f'V{zero_y} Z')
        parts.append(f'<path class="{cls}" data-tip="{esc(tip)}" d="{path}"/>')
        parts.append(f'<text x="{x + bar_w / 2:.1f}" y="{pad_t + plot_h + 20}" '
                     f'text-anchor="middle">D{g["decile"]}</text>')
    parts.append("</svg>")
    return "".join(parts)


def factor_ic_svg(table, labels=None):
    """逐因子 IC 横条。正蓝负红，零线居中，按 IC 降序。

    显著性不靠颜色表达：|t|>2 的行在标签前加实心点并加粗数值，
    其余保持常规字重——颜色只表示方向，不表示可信度。
    """
    if not table:
        return '<p class="na">无逐因子数据</p>'
    labels = labels or {}
    row_h, label_w, num_w = 22, 190, 108
    width = CHART_W
    height = row_h * len(table) + 26
    plot_w = width - label_w - num_w - 16
    span = max(abs(r["mean"] or 0) for r in table) or 0.01
    span *= 1.12
    zero_x = label_w + plot_w / 2.0
    bar_h = 11

    parts = [f'<svg viewBox="0 0 {width} {height}" role="img" '
             f'aria-label="各因子的 Rank IC 与显著性">']
    parts.append(f'<line class="axis-line" x1="{zero_x}" y1="4" '
                 f'x2="{zero_x}" y2="{height - 22}"/>')
    for frac, lbl in ((-1.0, f"−{span:.2f}"), (0.0, "IC 0"), (1.0, f"+{span:.2f}")):
        x = zero_x + frac * plot_w / 2.0
        parts.append(f'<text x="{x:.1f}" y="{height - 6}" text-anchor="middle">{lbl}</text>')

    for i, row in enumerate(table):
        y = i * row_h + 6
        value = row["mean"] or 0.0
        tstat = row.get("tStat")
        strong = tstat is not None and abs(tstat) > 2.0
        w = abs(value) / span * (plot_w / 2.0)
        x = zero_x if value >= 0 else zero_x - w
        cls = "bar" if value >= 0 else "bar neg"
        name = labels.get(row["factor"], row["factor"])
        tip = (f'{name}：IC {value:+.4f}，t {tstat:+.2f}，'
               f'胜率 {row["hitRate"] * 100:.0f}%，样本 {row["n"]}'
               if tstat is not None else f'{name}：IC {value:+.4f}')
        marker = "● " if strong else "○ "
        parts.append(f'<text x="{label_w - 10}" y="{y + 10}" text-anchor="end">'
                     f'{esc(marker + name)}</text>')
        r_ = min(4.0, w, bar_h / 2.0)
        if w > 0.5:
            if value >= 0:
                path = (f'M{x:.1f},{y} H{x + w - r_:.1f} Q{x + w:.1f},{y} '
                        f'{x + w:.1f},{y + r_:.1f} V{y + bar_h - r_:.1f} '
                        f'Q{x + w:.1f},{y + bar_h} {x + w - r_:.1f},{y + bar_h} H{x:.1f} Z')
            else:
                path = (f'M{zero_x:.1f},{y} H{x + r_:.1f} Q{x:.1f},{y} {x:.1f},{y + r_:.1f} '
                        f'V{y + bar_h - r_:.1f} Q{x:.1f},{y + bar_h} '
                        f'{x + r_:.1f},{y + bar_h} H{zero_x:.1f} Z')
            parts.append(f'<path class="{cls}" data-tip="{esc(tip)}" d="{path}"/>')
        weight = ' font-weight="640"' if strong else ""
        parts.append(f'<text x="{width - 8}" y="{y + 10}" text-anchor="end"{weight}>'
                     f'{value:+.3f}'
                     f'{f"  t{tstat:+.1f}" if tstat is not None else ""}</text>')
    parts.append("</svg>")
    return "".join(parts)


def subperiod_table(stability, labels=None):
    """子区间 IC 稳定性表。每个因子三段并排，一眼看出符号稳不稳。

    单个 t 值把九年压成一个数，制度切换被平均掉了；分段才看得出
    「因子方向真的反了」和「这段历史恰好对它不友好」的区别。
    """
    if not stability or not stability.get("rows"):
        return ""
    labels = labels or {}
    bounds = stability["bounds"]
    rows = stability["rows"]
    span = max((abs(c["mean"]) for r in rows for c in r["periods"] if c), default=0.01) or 0.01

    def cell(c):
        if not c:
            return '<td class="num na">—</td>'
        width = min(100.0, abs(c["mean"]) / span * 100.0)
        side = "left:50%" if c["mean"] >= 0 else f"right:50%"
        color = "var(--series-1)" if c["mean"] >= 0 else "var(--neg)"
        tip = f'IC {c["mean"]:+.4f}，t {c["tStat"]:+.2f}，{c["n"]} 次评估' \
            if c.get("tStat") is not None else f'IC {c["mean"]:+.4f}'
        return (f'<td class="num" data-tip="{esc(tip)}">'
                f'<span class="dbar"><span class="dfill" style="{side};'
                f'width:{width / 2:.1f}%;background:{color}"></span></span>'
                f'<span class="dnum">{c["mean"]:+.3f}</span></td>')

    head = "".join(f'<th class="num">{esc(b["from"][:7])}<br>~{esc(b["to"][:7])}</th>'
                   for b in bounds)
    body = []
    for row in rows:
        name = labels.get(row["factor"], row["factor"])
        if row["consistent"]:
            verdict = ('<span class="mark pass">✓ 三段同号</span>' if row["sign"] > 0
                       else '<span class="mark fail">✓ 三段同负</span>')
        else:
            verdict = '<span class="muted">✗ 符号翻转</span>'
        body.append(f'<tr><td>{esc(name)}</td>'
                    + "".join(cell(c) for c in row["periods"])
                    + f"<td>{verdict}</td></tr>")
    return ('<div class="table-scroll"><table class="sub"><thead><tr><th>因子</th>'
            + head + "<th>稳定性</th></tr></thead><tbody>"
            + "".join(body) + "</tbody></table></div>")


def sector_svg(counts):
    """行业分布横条。11 个行业超过配色能承载的类别数，所以用单色 + 文字标签。"""
    if not counts:
        return ""
    rows = sorted(counts.items(), key=lambda kv: kv[1], reverse=True)
    top = max(c for _, c in rows) or 1
    row_h, label_w = 26, 100
    width = CHART_W
    height = row_h * len(rows) + 8
    plot_w = width - label_w - 52
    parts = [f'<svg viewBox="0 0 {width} {height}" role="img" aria-label="入选标的的行业分布">']
    for i, (sector, count) in enumerate(rows):
        y = i * row_h + 6
        w = plot_w * count / top
        r = min(4.0, w, 8.0)
        parts.append(f'<text x="{label_w - 10}" y="{y + 13}" text-anchor="end">{esc(sector)}</text>')
        if w > 0:
            parts.append(
                f'<path class="bar" data-tip="{esc(f"{sector}：{count} 只")}" '
                f'd="M{label_w},{y + 3} H{label_w + w - r:.1f} '
                f'Q{label_w + w:.1f},{y + 3} {label_w + w:.1f},{y + 7:.1f} '
                f'V{y + 13:.1f} Q{label_w + w:.1f},{y + 17} {label_w + w - r:.1f},{y + 17} '
                f'H{label_w} Z"/>')
        parts.append(f'<text x="{label_w + w + 8:.1f}" y="{y + 14}">{count}</text>')
    parts.append("</svg>")
    return "".join(parts)


# ---------------------------------------------------------------------------
# 页面骨架
# ---------------------------------------------------------------------------
FAMILY_LABELS = [
    ("momentum", "动量"), ("reversal", "反转"), ("risk", "风险质量"),
    ("positioning", "量能"), ("fundamental", "基本面"),
    ("valuation", "估值"), ("revision", "盈利修正"),
]
FAMILY_NAME_MAP = {k: v for k, v in FAMILY_LABELS}
VARIANT_LABELS = {
    "baseline": "基线", "no-risk": "去掉风险块", "flip-risk": "风险块反向",
    "momentum-only": "只用动量", "reversal-only": "只用反转",
    "no-momentum": "去掉动量",
}
FACTOR_NAME_MAP = {
    "mom_12_1": "12月动量(剔近1月)", "mom_6_1": "6月动量(剔近1月)",
    "rs_120": "120日相对基准", "trend_200": "相对200日均线",
    "reversal_21": "近1月反转", "low_vol_60": "低波动60日",
    "low_maxdd_120": "低回撤120日", "low_downside_120": "低下行波动",
    "low_tail_252": "低尾部风险", "volume_expansion": "量能扩张",
    "accumulation_60": "吸筹比", "near_52w_high": "距52周高点",
    "volume_confirm_60": "量价配合",
    "revenue_growth": "营收增速", "earnings_growth": "盈利增速",
    "operating_margin": "营业利润率", "gross_margin": "毛利率",
    "roe": "ROE", "fcf_margin": "FCF利润率", "low_leverage": "低杠杆",
    "earnings_yield": "盈利收益率", "ev_ebitda_yield": "EV/EBITDA倒数",
    "ev_sales_yield": "EV/Sales倒数", "fcf_yield": "FCF收益率",
    "eps_revision_90d": "EPS修正90日", "eps_revision_30d": "EPS修正30日",
    "revision_breadth": "修正广度", "target_upside": "目标价空间",
}
FAMILY_TIPS = {
    "momentum": "12/6个月动量（剔除最近1个月）、120日相对基准、200日均线位置",
    "reversal": "最近1个月短期反转，取负号",
    "risk": "60日波动率、120日最大回撤、下行波动、尾部风险；分高=风险小",
    "positioning": "量能扩张、吸筹比、距52周高点、量价配合",
    "fundamental": "增长、盈利能力、现金流、资产负债表（B层，需外部数据）",
    "valuation": "行业相对估值与GARP（B层，需外部数据）",
    "revision": "盈利预测修正与修正广度（B层，需外部数据）",
}


def _page(title, body):
    return (
        '<!doctype html>\n<html lang="zh-CN">\n<head>\n'
        '<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        f"<title>{esc(title)}</title>\n<style>{CSS}</style>\n</head>\n<body>\n"
        '<button id="themer" type="button">切换主题</button>\n<div id="tt"></div>\n'
        f'<div class="wrap">\n{body}\n</div>\n'
        f"<script>{JS}</script>\n</body>\n</html>\n"
    )


def _meta_badges(payload):
    badges = []
    if payload.get("demo"):
        badges.append('<span class="badge demo">⚠ 合成数据 · 非市场数据 · 不可作为研究结论</span>')
    else:
        badges.append(f'<span class="badge">数据源 {esc(payload.get("source"))}</span>')
    badges.append(f'<span class="badge">数据日期 {esc(payload.get("asOf"))}</span>')
    interval = payload.get("barInterval") or (payload.get("window") or {}).get("barInterval")
    if interval and interval != "1d":
        badges.append(f'<span class="badge bad">⚠ 行情粒度 {esc(interval)}，'
                      f'不是日线——结果无效</span>')
    else:
        badges.append('<span class="badge">日频收盘 · 非实时</span>')
    status = payload.get("status")
    cls = {"ok": "badge ok", "partial": "badge", "stale": "badge bad", "error": "badge bad"}.get(status, "badge")
    text = {"ok": "✓ 数据完整", "partial": "◐ 部分缺失", "stale": "✗ 数据过期", "error": "✗ 失败"}.get(status, status)
    badges.append(f'<span class="{cls}">{esc(text)}</span>')
    if payload.get("blocksScored"):
        badges.append(f'<span class="badge">{esc(payload["blocksScored"])}</span>')
    fund = payload.get("fundamentals") or {}
    if fund.get("used"):
        badges.append(f'<span class="badge ok">✓ B层已接入 '
                      f'{fund.get("fetched", fund.get("count", "—"))} 只</span>')
    elif "used" in fund:
        badges.append('<span class="badge bad">✗ B层未接入</span>')
    return '<div class="badges">' + "".join(badges) + "</div>"


def _footer(payload):
    generated = datetime.now().strftime("%Y-%m-%d %H:%M")
    return (
        "<footer>"
        f'{esc(payload.get("model"))} V{esc(payload.get("version"))} · '
        f'报告生成于 {esc(generated)} · 数据更新时间 {esc(payload.get("updatedAt"))}<br>'
        f'{esc(payload.get("disclaimer") or "研究用途，不构成投资建议。")}'
        "</footer>"
    )


# ---------------------------------------------------------------------------
# 扫描报告
# ---------------------------------------------------------------------------
def render_scan(payload):
    rows = payload.get("ranking") or []
    dist = payload.get("scoreDistribution") or {}
    uni = payload.get("universe") or {}
    pool = payload.get("candidatePool") or {}
    rule = pool.get("rule") or {}

    body = ['<header><h1>Ooglex Alpha 60 · 选股扫描</h1>'
            f'<p class="sub">{esc(payload.get("objective"))}</p>'
            f'{_meta_badges(payload)}</header>']

    # ---- 关键数字 ----
    share = dist.get("shareAbove80")
    body.append('<h2>一眼看全</h2>')
    body.append('<div class="tiles">')
    body.append(_tile("股票池", uni.get("requested"), f'剔除未上市 {uni.get("skippedNonTradeable", 0)} 家'))
    body.append(_tile("通过硬过滤", uni.get("screened"),
                      f'流动性/股价/历史不达标 {uni.get("rejected", 0)} 只'))
    body.append(_tile("候选池", pool.get("count"),
                      f'Alpha≥{num(rule.get("minAlpha"), 0)} 且 风险≥{num(rule.get("minRisk"), 0)}'
                      f' 且 共振≥{rule.get("minConfluence", "—")}'))
    body.append(_tile("总分中位", num(dist.get("p50"), 1), f'99分位 {num(dist.get("p99"), 1)}'))
    body.append(_tile("≥80 占比", pct(share) if share is not None else "—",
                      "这就是候选池小的原因"))
    body.append("</div>")

    if uni.get("fetchFailures"):
        body.append(f'<p class="note">本轮有 {uni["fetchFailures"]} 只取数失败'
                    f'（真实退市或代码变更），已从股票池剔除，未用旧值顶替。</p>')

    # ---- B 层状态 ----
    body.append(_fundamentals_panel(payload.get("fundamentals") or {}))

    # ---- 分布 ----
    body.append("<h2>总分分布：为什么 80 分这么难</h2>")
    body.append('<p class="note">总分是七个族分位数的<strong>加权平均</strong>，'
                '因此它本身不是分位数——多个 0–100 的均匀分位取平均会向中间收敛，'
                '分布呈钟形而非均匀。所以「Alpha ≥ 80」是极端尾部，'
                '不是直觉上的「前 20%」。要按名次分档请看下表的百分位列。</p>')
    label = f'≥80 仅 {pool.get("count", 0)} 只' if share is None else \
            f'≥80 仅占 {share * 100:.1f}%'
    body.append('<figure><div class="chart-scroll">'
                + histogram_svg(dist.get("histogram"), 80.0, label)
                + "</div><figcaption>横轴 = Alpha60 总分（0–100），纵轴 = 标的数量。"
                  f'样本 {dist.get("count", 0)} 只，{_bin_width(dist)} 分一箱。'
                  "红线为候选池门槛 80 分。悬停查看每箱数量。</figcaption></figure>")

    # ---- 排名表 ----
    body.append(f"<h2>排名前 {len(rows)} 名</h2>")
    body.append('<p class="note">每个族的分数都是当日横截面百分位（0–100，越高越强），'
                '已做去极值与行业中性混合。风险质量一列分高代表波动与回撤小。'
                'B 层三族需要外部基本面数据，未接入时显示「无数据」，'
                '总分按 A 层权重重新归一化，不用中位数填充。</p>')
    body.append('<div class="table-scroll"><table><thead><tr>'
                '<th class="num">#</th><th>代码</th><th>行业</th>'
                '<th class="num">Alpha60</th><th>总分条</th><th class="num">百分位</th>'
                + "".join(f'<th>{esc(lbl)}</th>' for _, lbl in FAMILY_LABELS[:4])
                + "<th>共振</th></tr></thead><tbody>")
    for row in rows:
        fam = row.get("families") or {}
        cand = ' class="cand"' if row.get("isCandidate") else ""
        cells = "".join(
            f"<td>{mini_bar(fam.get(key), FAMILY_TIPS.get(key))}</td>"
            for key, _ in FAMILY_LABELS[:4])
        conf = row.get("confluence")
        body.append(
            f"<tr{cand}>"
            f'<td class="num muted">{row.get("rank")}</td>'
            f'<td class="sym">{esc(row.get("symbol"))}'
            + ('<br><span class="tag">候选</span>' if row.get("isCandidate") else "")
            + "</td>"
            f'<td class="muted">{esc(row.get("sector"))}</td>'
            f'<td class="num"><strong>{num(row.get("alpha60"), 2)}</strong></td>'
            f'<td>{_plain_bar(row.get("alpha60"))}</td>'
            f'<td class="num muted">{num(row.get("percentile"), 1)}</td>'
            f'{cells}'
            f'<td class="muted">{conf if conf is not None else "—"}/3</td>'
            "</tr>")
    body.append("</tbody></table></div>")

    # ---- 行业分布 ----
    sectors = {}
    for row in rows:
        sectors[row.get("sector") or "其他"] = sectors.get(row.get("sector") or "其他", 0) + 1
    if sectors:
        body.append("<h2>入选标的的行业分布</h2>")
        body.append('<p class="note">行业中性混合（全市场分位与行业内分位各占一半）'
                    '限制了单一行业占满榜单，但不会完全抹平——真实的跨行业强弱应当保留。</p>')
        body.append('<figure><div class="chart-scroll">' + sector_svg(sectors)
                    + f"</div><figcaption>前 {len(rows)} 名按行业计数。</figcaption></figure>")

    # ---- 逐只拆解 ----
    body.append("<h2>逐只拆解：这个分数是怎么来的</h2>")
    body.append('<p class="note">点开任意一只，看它七个族各得多少分、'
                '哪三个因子把它拉上来、哪三个拖了后腿、有没有缺失因子。'
                '分数可解释是 V1 的三个目标之一——你必须能看懂为什么它排第一。</p>')
    for row in rows[:20]:
        body.append(_detail(row))

    # ---- 数据诚实 ----
    body.append("<h2>这份结果的边界</h2>")
    body.append('<div class="callout"><strong>必须和结论一起读的几条：</strong><ul>'
                "<li>分数是<strong>横截面排序</strong>，不是收益预测。"
                "「84 分」不代表任何预期涨幅。</li>"
                "<li>候选 ≠ 买入。它只是把人工研究的注意力收敛到 20–30 只以内。</li>"
                f'<li>股票池取自当日市值榜，<strong>不是 point-in-time 成分股</strong>，'
                "含幸存者偏差。这对当日扫描无影响，但让历史回测结论只能用于否决模型。</li>"
                "<li>B 层基本面未接入时，共振门槛会按可得块数降级——"
                "此时高分股本质上仍是价格因子选出来的。</li>"
                "<li>行情为日线收盘，非实时。不要按盘中价理解这份排名。</li>"
                "</ul></div>")

    body.append(_footer(payload))
    return _page("Ooglex Alpha 60 · 选股扫描", "\n".join(body))


def _significance_note(table, unit):
    """图注里的结论从数据推，不写死。

    写死一句「全无显著项」，遇到确实有显著项的那次运行就成了谎话——
    图注说谎比图画错更难被发现。
    """
    if not table:
        return ""
    strong = [r for r in table if r.get("tStat") is not None and abs(r["tStat"]) > 2.0]
    positive = [r for r in strong if (r["mean"] or 0) > 0]
    negative = [r for r in strong if (r["mean"] or 0) < 0]
    if not strong:
        return (f"没有一个{unit}的 IC 能与 0 区分（全部 |t| ≤ 2）。"
                "这种情况下调权重是没有意义的——先加历史长度。")
    bits = []
    def _name(row):
        return FACTOR_NAME_MAP.get(row["factor"],
                                   FAMILY_NAME_MAP.get(row["factor"], row["factor"]))
    if positive:
        bits.append(f"{len(positive)} 个{unit}显著为正："
                    + "、".join(_name(r) for r in positive[:4]))
    if negative:
        bits.append(f"{len(negative)} 个{unit}显著为负："
                    + "、".join(_name(r) for r in negative[:4])
                    + "——方向与设计相反，值得单独查是不是符号搞反了")
    return "；".join(bits) + "。"


def _bin_width(dist):
    """箱宽从数据推，不写死——改了分箱粒度而图注没跟上是最常见的图表谎言。"""
    bins = (dist or {}).get("histogram") or []
    if not bins:
        return "—"
    w = bins[0]["hi"] - bins[0]["lo"]
    return f"{w:g}"


def _fundamentals_panel(fund):
    """B 层数据的来源、覆盖与限制。空着不写，等于让读者以为模型是完整的。"""
    if not fund:
        return ""
    body = ["<h2>B 层基本面数据</h2>"]
    if fund.get("used"):
        body.append('<p class="note">基本面、估值、盈利修正三族已接入，'
                    f'来源 {esc(fund.get("source"))}，'
                    f'{fund.get("fetched", fund.get("count", "—"))} / '
                    f'{fund.get("requested", "—")} 只有数据。'
                    'B 层子因子与 A 层走<strong>完全相同</strong>的归一化流水线'
                    '（去极值 → 全市场/行业内分位混合），两层分数才在同一尺度上。</p>')
        coverage = fund.get("fieldCoverage") or {}
        if coverage:
            weak = sorted((v, k) for k, v in coverage.items())[:5]
            rows = "".join(
                f'<li>{esc(k)}：{v * 100:.0f}% 的标的有数据</li>' for v, k in weak)
            body.append('<div class="callout"><strong>覆盖率最低的几个字段</strong>'
                        f"<ul>{rows}</ul>"
                        "覆盖率低的子因子在缺失的标的上不参与打分，"
                        "该族权重按剩余项重新归一化。</div>")
    else:
        body.append('<p class="note">基本面、估值、盈利修正三族<strong>未接入</strong>：'
                    f'{esc(fund.get("reason") or "取数失败")}。'
                    '这三族占设计权重的 40%，缺失时总分只由 A 层价格因子构成，'
                    '并按 A 层权重重新归一化——不是用中位数补 50 分。'
                    '此时的高分股本质上是价格因子选出来的，'
                    '跨块共振检验也无法进行。</p>')
        body.append('<div class="callout"><strong>怎么把它接上</strong><ul>'
                    "<li><code>python3 scripts/alpha-model/fundamentals.py NVDA CSX</code>"
                    "——逐字段诊断，看是握手失败还是字段缺失</li>"
                    "<li>或用 <code>--fundamentals 你的文件.json</code> 接别家数据源</li>"
                    "</ul></div>")

    body.append('<div class="callout"><strong>B 层的硬限制</strong>'
                "<ul><li>它是<strong>当前快照</strong>，没有 point-in-time 历史——"
                "给不出「2020-03-16 那天市场看到的 TTM 净利润」，"
                "那天的报表可能后来被重述，分析师预测更是没有留档。</li>"
                "<li>所以 B 层<strong>只用于今天的横截面打分，不参与回测</strong>。"
                "用今天的财报回测三年前是未来函数，回测结果必然虚高。</li>"
                "<li>真正的 PIT 财务要走 SEC EDGAR XBRL（companyfacts 带 filed 日期），"
                "属于 V2。</li></ul></div>")
    return "\n".join(body)


def _tile(label, value, hint=None):
    shown = "—" if value is None else esc(value)
    hint_html = f'<div class="hint">{esc(hint)}</div>' if hint else ""
    return (f'<div class="tile"><div class="label">{esc(label)}</div>'
            f'<div class="value">{shown}</div>{hint_html}</div>')


def _detail(row):
    fam = row.get("families") or {}
    exp = row.get("explain") or {}
    kv = []
    for key, lbl in FAMILY_LABELS:
        kv.append(f'<div class="k">{esc(lbl)}</div>'
                  f"<div>{mini_bar(fam.get(key), FAMILY_TIPS.get(key))}</div>")
    strengths = "".join(f"<li>▲ {esc(s)}</li>" for s in exp.get("strengths") or [])
    weaknesses = "".join(f"<li>▼ {esc(w)}</li>" for w in exp.get("weaknesses") or [])
    missing = exp.get("missingFactors") or []
    missing_html = (f'<p class="note" style="margin:10px 0 0">缺失因子：'
                    f'{esc("、".join(missing))}（未参与打分，权重已重新归一化）</p>'
                    ) if missing else ""
    disp = row.get("confluenceDispersion")
    disp_html = ""
    if disp is not None and disp > 25:
        disp_html = ('<p class="note" style="margin:10px 0 0">⚠ 块间离散度 '
                     f'{disp:.1f}，属于单腿支撑：高分主要由一个块拉动，'
                     "而不是多个独立信号共振。</p>")
    return (
        "<details><summary>"
        f'<span class="sym">{esc(row.get("symbol"))}</span>'
        f'<span class="muted">{esc(row.get("name"))}</span>'
        f'<span class="tag">{esc(row.get("sector"))}</span>'
        f'<span class="muted">Alpha {num(row.get("alpha60"), 2)} · '
        f'第 {row.get("rank")} 名 · 共振 {row.get("confluence")}/3</span>'
        "</summary>"
        f'<div class="detail-body"><div class="kv">{"".join(kv)}</div>'
        f'<ul class="reasons">{strengths}{weaknesses}</ul>'
        f"{missing_html}{disp_html}</div></details>"
    )


# ---------------------------------------------------------------------------
# 回测报告
# ---------------------------------------------------------------------------
def render_backtest(payload):
    ic = payload.get("rankIC") or {}
    dec = payload.get("deciles") or {}
    pf = payload.get("portfolio") or {}
    gates = payload.get("gates") or {}
    window = payload.get("window") or {}
    passed = gates.get("passed")

    badges = []
    if payload.get("demo"):
        badges.append('<span class="badge demo">⚠ 合成数据 · 非市场数据</span>')
    if payload.get("null"):
        badges.append('<span class="badge demo">零信号对照组</span>')
    badges.append(f'<span class="badge">前瞻 {payload.get("horizonDays")} 个交易日</span>')
    badges.append(f'<span class="badge">基准 {esc(payload.get("benchmark"))}</span>')
    win_interval = (payload.get("window") or {}).get("barInterval")
    if win_interval and win_interval != "1d":
        badges.append(f'<span class="badge bad">⚠ 粒度 {esc(win_interval)} 非日线，'
                      f'本页全部数字无效</span>')
    badges.append('<span class="badge">仅 A 层价格因子</span>')
    variant = payload.get("variant")
    if variant and variant != "baseline":
        badges.append(f'<span class="badge demo">变体 '
                      f'{esc(payload.get("variantLabel") or variant)}</span>')
    badges.append(f'<span class="badge {"ok" if passed else "bad"}">'
                  f'{"✓ 验收通过" if passed else "✗ 验收未通过"}</span>')

    body = ['<header><h1>Ooglex Alpha 60 · 回测验收</h1>'
            f'<p class="sub">{esc(window.get("from"))} → {esc(window.get("to"))}'
            f'（{window.get("tradingDays")} 个交易日）</p>'
            f'<div class="badges">{"".join(badges)}</div></header>']

    body.append("<h2>六条验收线</h2>")
    body.append('<p class="note">阈值在跑之前就写死在 <code>config.py</code> 里，'
                '不允许看到结果再改标准。任一条不过，该版本判为不可用。</p>')
    body.append('<ul class="checks">')
    for check in gates.get("checks") or []:
        ok = check.get("pass")
        body.append(f'<li class="{"pass" if ok else "fail"}">'
                    f'<span class="mark">{"✓ 通过" if ok else "✗ 未过"}</span>'
                    f'<span>{esc(check.get("name"))}</span>'
                    f'<span class="detail">{esc(check.get("detail"))}</span></li>')
    body.append("</ul>")

    body.append("<h2>Rank IC</h2>")
    body.append('<p class="note">每个评估日算一次「模型分数排名」与「未来超额收益排名」的秩相关。'
                '评估日间隔强制不小于前瞻期——重叠窗口会让 t 值虚高约 √60 倍。</p>')
    ci = ic.get("ci95") or [None, None]
    body.append('<div class="tiles">')
    body.append(_tile("IC 均值", num(ic.get("mean"), 4), "阈值 > 0.02"))
    body.append(_tile("t 值", num(ic.get("tStat"), 2),
                      "可与0区分" if ic.get("distinguishableFromZero")
                      else "|t|<2：样本不足以判断"))
    body.append(_tile("95% 区间",
                      f"{num(ci[0], 3)} ~ {num(ci[1], 3)}" if ci[0] is not None else "—",
                      "跨过0即无结论" if (ci[0] is not None and ci[0] < 0 < ci[1])
                      else "不含0"))
    body.append(_tile("信息比 IR", num(ic.get("ir"), 3), "阈值 > 0.30"))
    body.append(_tile("IC 胜率", pct(ic.get("hitRate")), "阈值 > 55%"))
    body.append(_tile("评估次数", ic.get("n"),
                      f'每{ic.get("step", "—")}个交易日一次' if ic.get("overlapping")
                      else "不重叠"))
    body.append("</div>")
    if ic.get("distinguishableFromZero") is False:
        body.append('<div class="callout" style="margin-top:14px">'
                    '<strong>先看这条：|t| &lt; 2，这批数据判不了。</strong>'
                    "均值是正是负都不能当结论——它和「IC 恰好等于 0」在统计上无法区分。"
                    "这不是模型失败，是**样本不足**。"
                    "先用 <code>--range max</code> 拉长历史再跑，"
                    "或者接受「这个前瞻期在这个股票池上就是测不动」。</div>")

    if dec.get("groups"):
        mono = dec.get("monotonicSpearman")
        body.append("<h2>十分组：排名到底可不可信</h2>")
        body.append('<p class="note">按模型分数从高到低分成十组，看每组未来 '
                    f'{payload.get("horizonDays")} 个交易日的平均超额收益。'
                    '<strong>单调性比「第一组赚钱」重要得多</strong>——'
                    '只有头部好、中间乱序，说明排名本身不可信，'
                    '赚钱可能只是少数几只票的运气。</p>')
        body.append('<figure><div class="chart-scroll">' + decile_svg(dec["groups"])
                    + "</div><figcaption>横轴 = 分组（D1 分数最高），"
                      "纵轴 = 平均超额收益（相对基准，蓝正红负）。"
                      f'单调秩相关 {num(mono, 3)}（越接近 −1 越好，阈值 < −0.70）；'
                      f'D1 − D10 = {pct(dec.get("topMinusBottom"), 2)}。悬停看每组数值。'
                      "</figcaption></figure>")

    factor_ic = payload.get("factorIC") or []
    family_ic = payload.get("familyIC") or []
    if family_ic or factor_ic:
        body.append("<h2>逐因子分解：signal 到底在哪一层</h2>")
        body.append('<p class="note">总分失败时，这张图是唯一有用的东西——它告诉你'
                    '是所有因子都没用，还是有几个有用但被没用的稀释了。'
                    '<strong>●</strong> 表示 |t| &gt; 2（该因子的 IC 可与 0 区分），'
                    '<strong>○</strong> 表示样本不足以判断。'
                    '颜色只表示方向，不表示可信度——看点不看色。</p>')
        if family_ic:
            body.append('<figure><div class="chart-scroll">'
                        + factor_ic_svg(family_ic, FAMILY_NAME_MAP)
                        + "</div><figcaption>七个族各自的 Rank IC。"
                          f"{_significance_note(family_ic, '族')}"
                          "</figcaption></figure>")
        if factor_ic:
            body.append('<figure style="margin-top:12px"><div class="chart-scroll">'
                        + factor_ic_svg(factor_ic, FACTOR_NAME_MAP)
                        + "</div><figcaption>每个子因子单独的 Rank IC，按均值降序。"
                          f"{_significance_note(factor_ic, '子因子')}"
                          "有显著正 IC 的因子才值得留；显著为负的可考虑反向使用。"
                          "</figcaption></figure>")

    mt = payload.get("multipleTesting") or {}
    if mt:
        body.append('<div class="callout" style="margin-top:14px">'
                    f'<strong>读上面那些 t 值之前，先看这条。</strong>'
                    f'一共测了 {mt.get("numTests")} 个子因子。'
                    f'即使它们<strong>全部无效</strong>，纯靠运气也会出现约 '
                    f'<strong>{mt.get("expectedFalsePositives", 0):.1f} 个</strong> |t|&gt;2。'
                    f'所以单看「有几个因子 |t|&gt;2」没有意义。'
                    f'多重检验校正后需要 |t| &gt; <strong>'
                    f'{mt.get("effectiveT", mt.get("bonferroniT", 0)):.2f}</strong> 才算确立'
                    f'（按约 {mt.get("effectiveTests", "—")} 个独立因子群算；'
                    f'三个低波动因子测的是同一件事，Bonferroni 的 '
                    f'{mt.get("bonferroniT", 0):.2f} 过于保守）。'
                    '没过这条线的因子属于<strong>值得追查</strong>，不是<strong>已确立</strong>。'
                    "</div>")

    stability = payload.get("subperiodIC")
    if stability:
        body.append("<h2>子区间稳定性：方向真的反了，还是这段历史不友好</h2>")
        body.append('<p class="note">单个 t 值把整段历史压成一个数，制度切换被平均掉了。'
                    '把评估期切成三段分别算，才分得出两种情况：'
                    '<strong>三段同号</strong>说明这是稳定的因子方向（哪怕是负的，'
                    '也可以反向使用）；<strong>符号翻转</strong>说明它随市场制度变，'
                    '在一段历史上的显著性不能外推。'
                    '这一条比任何单一 t 值都更能说明问题。</p>')
        body.append(subperiod_table(stability, FACTOR_NAME_MAP))
        consistent = [r for r in stability["rows"] if r["consistent"]]
        body.append(f'<p class="note" style="margin-top:12px">'
                    f'{len(consistent)} / {len(stability["rows"])} 个因子三段同号。'
                    '同号且均值绝对值大的那几个，才是下一步唯一值得动的地方。</p>')

    if pf:
        body.append("<h2>组合模拟（扣成本后）</h2>")
        body.append('<p class="note">每月调仓，等权持有分数最高的若干只到下次调仓，'
                    '因此收益序列不重叠。换手率按被替换仓位比例计，'
                    '买卖各付一次单边成本——不计成本的年化收益没有意义。</p>')
        body.append('<div class="tiles">')
        body.append(_tile("累计超额", pct(pf.get("cumulativeExcess"), 2), "扣成本后"))
        body.append(_tile("每期均值", pct(pf.get("meanExcessPerPeriod"), 2), "单次调仓周期"))
        body.append(_tile("胜率", pct(pf.get("hitRate")), "跑赢基准的期数占比"))
        body.append(_tile("年换手", num(pf.get("annualTurnover"), 2), "倍"))
        body.append(_tile("成本拖累", pct(pf.get("costDrag"), 2), "累计"))
        body.append(_tile("最大回撤", pct(pf.get("maxDrawdown"), 2), "相对净值峰值"))
        body.append("</div>")

    led = payload.get("attemptLedger") or {}
    if led:
        current_t = abs((payload.get("rankIC") or {}).get("tStat") or 0)
        threshold = led.get("deflatedT", 1.96)
        clears = current_t > threshold
        body.append("<h2>尝试台账：你已经试了多少次</h2>")
        body.append('<p class="note">看过回测结果之后再改模型，改动就带着'
                    '「已经看过答案」的污染。试十个变体挑最好的那个，'
                    '即使十个全是噪声，出现至少一个 |t|&gt;2 的概率也有 37%。'
                    '所以每跑一次就记一次，阈值随次数收紧——'
                    '<strong>让每多试一次都变贵，而不是免费。</strong>'
                    '台账只增不改。</p>')
        body.append('<div class="tiles">')
        body.append(_tile("累计尝试", led.get("attempts"), "只增不改"))
        body.append(_tile("不同变体", led.get("distinctVariants"), "已试过的种类"))
        body.append(_tile("打折后阈值", f'|t| > {threshold:.2f}',
                          f'基准 1.96 收紧至此'))
        body.append(_tile("当前 |t|", f"{current_t:.2f}",
                          "✓ 过线" if clears else "✗ 未过线"))
        body.append(_tile("假阳性概率",
                          f'{led.get("anyFalsePositiveProb", 0) * 100:.0f}%',
                          "纯靠运气至少出现一个"))
        body.append("</div>")

        rows = led.get("byVariant") or []
        if len(rows) > 1:
            body.append('<div class="table-scroll" style="margin-top:14px">'
                        '<table><thead><tr><th>变体</th><th class="num">最佳 |t|</th>'
                        '<th class="num">IC 均值</th><th>验收</th>'
                        '<th>最近一次</th></tr></thead><tbody>')
            for row in sorted(rows, key=lambda x: -abs(x.get("tStat") or 0)):
                label = VARIANT_LABELS.get(row["variant"], row["variant"])
                tv = row.get("tStat")
                body.append(
                    f'<tr><td>{esc(label)}</td>'
                    f'<td class="num">{abs(tv):.2f}</td>' if tv is not None
                    else f'<tr><td>{esc(label)}</td><td class="num na">—</td>')
                body.append(f'<td class="num">{num(row.get("icMean"), 4)}</td>'
                            f'<td>{"✓ 通过" if row.get("passed") else "✗ 未过"}</td>'
                            f'<td class="muted">{esc((row.get("at") or "")[:10])}</td></tr>')
            body.append("</tbody></table></div>")

        if not clears:
            body.append('<div class="callout" style="margin-top:14px">'
                        f'<strong>当前 |t| = {current_t:.2f}，没到打折后的 '
                        f'{threshold:.2f}。</strong>'
                        "继续试变体只会让阈值更高、更难过线。"
                        "如果几轮之后仍然过不了，说明问题不在权重配比，"
                        "而在因子本身或股票池——那时候该换的是数据，不是参数。"
                        "</div>")

    biases = payload.get("knownBiases") or []
    if biases:
        body.append("<h2>已知偏差</h2>")
        body.append('<div class="callout"><strong>这些必须和上面的数字一起读：</strong><ul>'
                    + "".join(f"<li>{esc(b)}</li>" for b in biases)
                    + "</ul></div>")

    body.append(_footer(payload))
    return _page("Ooglex Alpha 60 · 回测验收", "\n".join(body))


# ---------------------------------------------------------------------------
def write_report(payload, path, kind="scan"):
    html_text = render_scan(payload) if kind == "scan" else render_backtest(payload)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(html_text)
    os.replace(tmp, path)
    return path


def main():
    """独立使用：从已有的 JSON 重新生成 HTML。"""
    import argparse
    parser = argparse.ArgumentParser(description="把 Alpha60 的 JSON 输出渲染成 HTML 报告")
    parser.add_argument("json_path")
    parser.add_argument("--kind", choices=("scan", "backtest"), default=None)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    with open(args.json_path, encoding="utf-8") as f:
        payload = json.load(f)
    kind = args.kind or ("backtest" if payload.get("mode") == "backtest" else "scan")
    out = args.out or os.path.splitext(args.json_path)[0] + ".html"
    print("已写入", write_report(payload, out, kind))


if __name__ == "__main__":
    main()
