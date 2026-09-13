# OOGLEX 终端：长期工程说明

这份文件说明终端外壳怎么搭的、往里加一个金融功能要动哪几处、以及哪些功能卡在没有数据源上。
草案目录 `terminal-redesign/`，全部 `noindex`，不进 `sitemap.xml`，站内无入口。
**现有终端 `/apps/finance-terminal/` 一行未改。**

---

## 一、三层结构

```
assets/terminal/            代码层（三个页型共用）
├── core.js       10KB  公共口径：取数与单源失败隔离、格式化、出处行、Z 值与分位
│                       阈值、真实交易时段、转义。全终端只有这一份口径。
├── overview.js   10KB  横向模型：12 个站内 JSON → 跨品类总览（股指/利率/外汇/
│                       商品/信用/加密/宏观/曲线/日历/要闻/异动）
├── security.js    4KB  纵向模型：单标的的发行人、收盘历史、盘中快照、采集健康；
│                       以及榜单页的全量公司 + 迷你走势 + 要闻
├── render.js     24KB  渲染器：报价表、个股、曲线、利差、宏观监测、跨资产、日历、
│                       要闻、异动、自选、来源、折线、字段表
├── registry.js    9KB  功能注册表 —— 加一个功能就是加一条记录（见第二节）
├── chrome.js     15KB  外壳行为：标签条与功能键条渲染、命令行、编号跳转、弹层、
│                       分页、排序、迷你走势
├── behavior.js    8KB  密度切换与持久化、时钟与市场状态、窗口 MAX/SET/EXP
└── terminal.css  37KB  设计系统：外壳 + 数据区一套样式、四级字号、双密度、四档断点

apps/finance-terminal/      页面层（只做装配：哪个区域用哪个渲染器）
├── index.html         终端监控：13 个功能面板的等尺寸墙（首页）
├── security.html      证券描述：报价头 + 四个编号分页 + 编号菜单
├── trends.html        榜单与趋势：子标签 + 筛选条 + 编号行 + 相对强弱 + 迷你走势
├── quote.html         行情详情：单标的完整走势（改版前就有，未动；markets 页依赖它）
├── legacy.html        改版前的终端页，保留可用并 noindex
├── terms.html         使用条款（纯静态、零脚本）
├── privacy.html       隐私政策（纯静态、零脚本）
├── finance-terminal-geo-risk.mjs      地缘风险定价模型：新旧两个终端共用（新终端用
│                                      buildGeoRisk() 模型自己渲染成表格，legacy 用
│                                      renderGeoRisk() 画表盘）。契约：
│                                      validate_finance_terminal_geo_risk.mjs
├── app.js + 32 个其余 .mjs + terminal-*.css   legacy.html 在用，未动
└── data.json / readiness.json / market-source-readiness.json   数据管道，未动
```

**分层的意义**：口径只写一遍。改一处算法，三个页型同时生效。
页面里没有任何算数字的代码，也没有写死的功能名。

### 为什么是两个数据模型而不是一个

`overview.js` 是横向的（跨品类、一屏总览），`security.js` 是纵向的（单标的的时间
序列与明细）。两者读的源只有 3 个重叠，各自缺对方的一半 —— 合成一个大对象只会让
监控页为了拿一张表去下载 260 天的收盘历史。**该合的是公共部分**：`soft` / `fmt` /
`isNum` / `statusZh` / `UNAVAILABLE` / `srcLine` 原先在两个数据层里各写了一遍，
现在只在 `core.js` 里有一份。

### 配色语义的分工（外壳与数据区唯一要小心的地方）

| | 颜色承载什么 | 允许几种 |
|---|---|---|
| 外壳（`.t-tabs` `.t-fnbar` `.t-crumb` `.t-cmdbar` `.t-menu` `.t-sugg`） | **功能属于哪一类** | 8 种分类色，每种文字对比度实测 ≥4.5 |
| 数据区（`.t-win` `.t-panel` `.t-tbl` `.t-sig` `.t-chart` `.t-bars`） | **涨跌方向与风险档位** | 绿涨红跌 + 四档信号，且都有文字标签并行 |

彩色功能键条是导航，不受数据区「严格控色」约束 —— 但也不许越界表达涨跌。

### 命名只有一套

全部 `.t-` 前缀。合并时撞名的三处已显式改名，不靠后者覆盖：

| 冲突 | 处理 |
|---|---|
| 外壳的命令行**容器** vs 数据区的命令行**输入框** | 容器改 `.t-cmdbar`，`.t-cmd` 仍是输入框 |
| 外壳的建议功能条 vs 数据区的页脚一行 | 建议条改 `.t-sugg`，`.t-foot` 仍是页脚 |
| 外壳的通用横滚容器 vs 数据区的窗口修饰符 | 容器改 `.t-scroll-x`，`.t-scroll` 仍是窗口修饰符 |
| 两套表格组件 | 只留 `.t-tbl`（带双密度与四级字号），外壳那套整块删除 |

### 主题

终端四页（含 legacy）**锁深色** —— 专业终端本身是深色语言，且浅色兜底已从 11 个
legacy 样式表里剥离（省 43.7KB）。页面上主题选择器仍在，会显示锁定说明。
`terminal-board.css` 例外：它与 `apps/markets/` 共用，那一页不锁主题，所以它的浅色
兜底挪到了 `assets/theme.css` 手工维护（board.css 有 14KB 预算，放不进去）。

---

## 二、加一个金融功能：改一处

在 `assets/terminal/registry.js` 的 `FUNCTIONS` 里加一条：

```js
{ mn:"SCRN", zh:"条件选股", en:"Screener", cat:"anly", status:"live",
  href:"../apps/screener/", data:["companies/data.json","companies/fundamentals.json"],
  note:"按 PE / ROE / 营收增速筛选；财务字段为季频，与价格的日频口径不同" }
```

加完之后**自动生效**的地方：

1. 彩色功能键条多一个键，底色按 `cat` 自动取
2. 功能目录（`FDIR`）里多一行，带分类分组
3. 命令行认这个助记符，输入 `SCRN` 直接跳
4. 相关功能菜单、底部建议功能条、监控页的注册表面板同步出现

需要手写的只有那个功能页本身。

### 字段约定

| 字段 | 说明 |
|---|---|
| `mn` | 助记符。**用 OOGLEX 自己的**，不要用其他终端产品的助记符 |
| `cat` | `quote` `macro` `anly` `news` `rank` `tool` `chain` `sys` 之一，决定颜色 |
| `status` | `live` 站内已有 / `draft` 草案页 / `planned` 只在目录里列出 |
| `href` | `planned` 的一律为 `null`（注册表会统一打标，防止漏写跳到空地址） |
| `data` | 它读哪几个站内 JSON。写清楚，将来查「改这个源会影响谁」靠它 |
| `note` | 口径或限制。会出现在功能键的 tooltip、目录与建议条里 |

`PLANNED` 用另一组字段：`need`（缺什么）+ `blocked`（卡在哪）。
这两条会原样显示在功能目录里 —— **缺数据源就写缺哪一条，不先画空壳**。

---

## 三、规划中的功能与各自卡点

| 助记符 | 功能 | 需要什么 | 卡在哪 |
|---|---|---|---|
| `PORT` | 组合与持仓 | `positions[] = { symbol, qty, avgCost, currency, asOf }` | 站内无任何账户数据；汇率需另接官方源；风险指标依赖持仓协方差 |
| `QUOT` | 逐笔报价与深度 | 付费行情源（BID / ASK / VOL / 日内高低） | 无免费公开来源。现阶段这四组字段一律不显示 |
| `SWAP` | 资产互换分析 | 单券现金流表 + 互换曲线 + 日历规则 | 站内债券数据是主权收益率序列，没有券级现金流 |
| `OPTN` | 期权链与隐含波动 | 期权链快照（行权价、到期、隐含波动率） | 无来源 |
| `FLOW` | 资金流向 | 基金流向周报（EPFR / ICI 一类） | 无免费公开来源 |
| `SCRN` | 条件选股 | 基本面字段（PE / PB / ROE / 营收增速） | 站内公司数据只有价格、市值与收益率，没有财务报表字段 |
| `ALRT` | 条件告警 | 一处可写存储 + 定时评估 | 纯静态站无后端；浏览器本地只能在打开时评估 |
| `CHAT` | 终端问答 | 把站内数据口径做成可检索结构 | 否则会答出站内根本没有的数字 |
| `BOND` | 主权债收益率 | 一个展示页 | **数据已就绪**（`apps/bonds/data.json` 有 35 国 10 年期），只是 `apps/bonds/` 还没有 `index.html` —— 这是新终端契约跑出来的发现 |

**优先级建议**：`BOND`（数据现成，只差一页，最便宜）→ `SCRN`（只差一个财务字段源，价值最大）→ `ALRT`（可先做「打开时评估」的弱版本，写清它不是后台告警）→ `PORT`（要先有一处可写存储）→ 其余都要先解决数据授权。

---

## 四、刻意没有的东西

这几条是有意为之，不是漏做。往里加功能时请守住：

- **没有买卖下单键。** 站内没有任何经纪或订单通道，画一个买卖键就是假的。
  编号动作键只放真动作：口径说明、导出 CSV、加入自选。
- **不写「实时」。** 盘中快照约 30 分钟刷新且自带 `realtime:false`，页面一律标「快照」。
- **BID / ASK / VOL / 日内高低不显示。** 无来源，也不用占位数字冒充。
  `chrome/data.js` 的 `UNAVAILABLE` 与 `ds/feed.js` 的 `UNAVAILABLE` 统一声明，页面据此渲染说明。
- **没有阅读热度 / 新闻情绪 / 社交情绪 / 社交量 / 社交速度。** 站内不采集用户行为，也无社交数据授权。
  方案H 因此不做这几个标签，只做站内真能算出来的维度。
- **序列有缺口就断开，不插值也不前向填充。** 折线在空值处断开，页面显示「有效收盘 N / M」。
- **不假装有财务报表与信用评级。** 单证券页把这些列为「站内不可得字段」，并写明为什么。

---

## 五、已经做完的与还剩的

已完成（本次）：

1. 外壳与数据系统合并为一套 `assets/terminal/`，口径单一真源
2. 三个页型上线到 `/apps/finance-terminal/`，取代改版前那一页
3. 改版前那一页移到 `legacy.html` 并保留可用，它的 4000 行契约改指该文件后**全绿**
4. 新终端有了自己的契约 `scripts/validate_terminal.py`（230 条）

还剩：

| 下一步 | 说明 |
|---|---|
| ~~迁入 legacy 独有的两块~~ | **已完成**。地缘风险定价迁入（复用 `finance-terminal-geo-risk.mjs` 的模型，表格渲染）；品类看板核对后发现 `apps/markets/` 就是看板本体（8 个 board id 与 legacy 相同），改为在监控页加品类分布汇总面板并链过去，不复制第二份 |
| ~~退役 legacy 与它的契约~~ | **决定不做**。`validate_finance_terminal.py` 除页面断言外还覆盖数据管道与适配器（7 个源的取数、健康度、失败保留、单源隔离），而那正是新终端读的数据 —— 删掉它等于连新终端的数据覆盖一起删。legacy 已 noindex、不在导航与 sitemap，留着成本是零 |
| 按注册表逐个加功能 | 优先级见第三节 |
| 推广设计系统 | 把 `terminal.css` 的口径推到其余页面 |

---

## 六、校验清单（每次改完都跑）

```bash
# 语法
node --check assets/terminal/*.js
python3 -m py_compile scripts/validate_terminal.py

# 新终端契约（255 条：出处规范、不伪造实时、不可得字段声明、无下单键、
#              注册表完整性、代码层单一真源、迁入两块的专项、无孤儿引用、无障碍）
python3 scripts/validate_terminal.py

# legacy 页的旧契约（129 条页面断言 + 数据与适配器契约，一条未删）
python3 scripts/validate_finance_terminal.py
node scripts/validate_finance_terminal_loader.mjs
node scripts/validate_finance_terminal_board.mjs
node scripts/validate_finance_terminal_visuals.mjs
node scripts/validate_finance_terminal_geo_risk.mjs

# 主题审计（43 页 × 三套主题；终端四页锁深色、法律两页不接主题）
NODE_PATH=/opt/node22/lib/node_modules node scripts/theme/audit_theme.js
THEME=dark  NODE_PATH=... node scripts/theme/audit_theme.js
THEME=paper NODE_PATH=... node scripts/theme/audit_theme.js

# 浏览器端（本容器跑不动 Chrome，CI 里跑）
node scripts/validate_finance_terminal_browser.mjs   # 指向 legacy.html
```

响应式（三页 × 双密度 × 2560→360 九档）与失败态（全源阻断 + 单源隔离）
用 Playwright 手动跑，结果记在 `CHANGELOG.md` 对应条目里。
