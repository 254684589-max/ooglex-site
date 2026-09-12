# 全站主题配色

访客可以在任意页面右上角切换主题，选择记在 `localStorage["ooglex.theme"]`，
同源下所有子页面自动沿用。

| 主题 | 值 | 页面底色 | 强调色 | 说明 |
|---|---|---|---|---|
| 深色 | `dark` | `#0b0e13` | 各页原有 | 默认，接入主题层前后逐像素一致 |
| FT 纸色 | `ft` | `#fff1e5` | `#0d7680` 青 / `#990f3d` 酒红 | Financial Times 的米粉色纸底 |
| 亮白 | `paper` | `#ffffff` | `#1a5fb4` 蓝 | 中性纸白 |

## 组成

```
assets/theme.css                    调色板 + 浅色模式共性兜底 + 选择器控件样式
assets/theme.js                     控件、持久化、跨标签同步、运行时着色
scripts/theme/light_overrides.py    逐页生成浅色兜底 CSS（可重复运行）
各页 <head>                          theme.css + 首屏防闪内联脚本 + theme.js
各页 <style> 末尾                     生成器写入的「浅色主题兜底」区块
```

### 为什么需要生成器

站内每个页面各自内联一套 CSS，配色变量命名不统一（`--bg` / `--text` / `--ink` /
`--card` / `--panel` 混用），并且有约 900 处写死的色值。`assets/theme.css` 只能
接管常见变量名；写死的部分由生成器逐页翻转。

生成器的判定规则：

| 属性 | 条件 | 浅色主题下的取值 |
|---|---|---|
| `color` | 纸色底上对比度 < 4.0 | 同色相压暗到 AA（4.6:1） |
| `color` | 所在规则块自带强调色底，且原文字是深色 | `var(--on-accent)` |
| `background` | 近中性的深色（亮度 < 0.16、彩度 ≤ 90） | `var(--bg)` / `var(--panel)` / `var(--panel2)` |
| `background` | 白色半透明覆盖层 | 按 alpha 映射到 `var(--tint-1..3)` |
| `background` | **饱和色** | **保留**——热力图瓦片、涨跌徽标属于数据编码 |
| `border-color` | 白色半透明 / 深色 | `var(--line)` / `var(--line-strong)` |
| `box-shadow` | 黑色阴影 | 暖色浅阴影 |
| 自定义属性 | 同上逐值映射 | 含局部覆盖（如 `.board-tab{--accent:…}`） |

压暗时**只改亮度，保留色相与饱和度**，所以涨绿跌红、机制分档这些用颜色承载的
信息在浅色主题下依然成立。近白/近黑色值的 HLS 饱和度会虚高，另用绝对彩度约束，
避免 `#f4f7fb` 压暗后变成蓝紫色。

生成的区块有注释横幅包裹，重复运行会先删除上一次的结果再重写：

```sh
python3 scripts/theme/light_overrides.py            # 写入
python3 scripts/theme/light_overrides.py --dry-run  # 只看统计
python3 scripts/theme/light_overrides.py index.html # 只处理指定文件
```

自动推导判错的少数位置写在脚本顶部的 `EXCEPTIONS` / `VAR_EXCEPTIONS` 里，
带原因注释。

### 运行时着色

页面脚本会按深色配色把颜色直接写进 inline style（机制分档色、恐慌贪婪读数、
迷你走势线的 `stroke`、逐项强调色 `--mc`）。CSS 覆盖不到这些，`theme.js` 在浅色
主题下按同一套规则压暗，并用 `WeakMap` 记住原值，切回深色时还原。

**运行时只改文字色与 SVG 的 `fill`/`stroke`，不碰 inline 背景色**——脚本写进
背景的基本都是数据色（热力图瓦片、持仓条、走势填充），翻转会破坏数据编码。

### 固定深色的页面

画面由整屏 canvas / iframe 主导的页面在 `<html>` 上标 `data-theme-lock="dark"`，
固定深色显示；主题选择仍然记住并对其他页面生效，控件菜单里会说明原因。

- `apps/telescope/`、`apps/fish-lab/`、`apps/mosquito-lab/`（整屏 canvas 仿真）
- `games/gta-vice-city/`、`games/red-alert/`（整屏游戏画面）

要把某页解锁，删掉 `<html>` 上的 `data-theme-lock`，从
`scripts/theme/light_overrides.py` 的 `LOCKED` 里移除，重跑生成器即可。

## 新增页面时

1. 在 `<head>` 第一个 `<style>` 之前加入三行（与其他页面一致）：

```html
<link rel="stylesheet" href="/assets/theme.css">
<script>/* 主题首屏防闪 */(function(){try{var d=document.documentElement,l=d.getAttribute("data-theme-lock"),t=localStorage.getItem("ooglex.theme");if(t!=="ft"&&t!=="paper"&&t!=="dark")t=null;d.setAttribute("data-theme",l||t||"dark");if(t)d.setAttribute("data-theme-choice",t);}catch(e){}})();</script>
<script src="/assets/theme.js" defer></script>
```

2. 配色尽量用 `assets/theme.css` 已接管的变量名（`--bg` `--panel` `--ink`
   `--text` `--dim` `--line` `--up` `--down` `--accent` …），这样不需要生成器介入。
3. 跑一遍 `python3 scripts/theme/light_overrides.py`。
4. 用 `scripts/theme/audit_theme.js` 核对三套主题（见下）。

控件默认插进页面顶栏（按 `[data-theme-slot]`、`nav .links`、`.topbar`、`.bar`…
顺序找），找不到或容器不可见就落到右上角浮动。想指定位置，在容器上加
`data-theme-slot`。

## 校验

```sh
python3 -m http.server 8899 &
node scripts/theme/audit_theme.js ft      # 逐页量对比度、深色块、控件可见性
node scripts/theme/audit_theme.js paper
node scripts/theme/audit_theme.js dark    # 回归：深色下应当全部干净
```

判定口径：

- **深色块**：浅色主题下面积 > 18000px² 且亮度 < 0.22 的**近中性**底色（饱和色不算，
  那是数据编码）。
- **低对比**：直接含文字的元素，前景与最近不透明底色的对比度 < 3.0；渐变底跳过。
- **控件可见性**：主题选择器实际量得的尺寸 > 10px。
- 固定深色的页面只看控件与报错，不看深色块与对比度。
