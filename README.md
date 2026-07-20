# ZLQ6600E

欢迎来到 ZLQ6600E 项目！🎉

## 简介

这是我的个人主页项目，使用 HTML + CSS 构建，通过 GitHub Pages 免费托管。

🌐 在线访问：https://ooglex.com

## 开始使用

```bash
git clone https://github.com/zlq6600e-cyber/ZLQ6600E.git
cd ZLQ6600E
```

## 项目结构

```
ZLQ6600E/
├── index.html              # 个人主页（网站入口，GitHub Pages 根）
├── assets/
│   └── avatar.jpg          # 头像（网站静态资源）
├── apps/                   # 网页小应用
│   ├── ai-rankings/        # 🤖 全球大模型评测榜（LMArena Elo · LiveBench · 智能指数三榜合一，每日更新）
│   ├── university-rankings/ # 🎓 全球大学排名 300 强（QS · THE · ARWU · U.S. News 四榜合一·平均位次综合排序，年度权威整理）
│   ├── major-rankings/     # 🚀 全球专业与就业前景榜（专业薪资 / 就业率 / 毕业起薪 / AI 时代前景四榜合一）
│   ├── finance-column/     # 💹 金融知识终极架构（华尔街知识图谱 v4.0：8 层级·48 模块·560+ 双语术语，可检索）
│   ├── data-hub/           # 📊 数据中心（聚合全部实时数据应用 + 实时小预览）
│   ├── asset-ranking/      # 🌐 全球资产市值排行榜（不限品类·前 250·房产/国债/黄金/公司/加密，每日更新）
│   ├── house-prices/       # 🏘️ 全球主要国家房价走势（名义/实际同比·季度走势，每日更新）
│   ├── asset-tracker/      # 🌍 全球大类资产收益率（每日更新的行情追踪）
│   ├── billionaires/       # 🏆 全球富豪实时榜（前 250 富豪身价，每日更新）
│   ├── companies/          # 🏢 全球公司市值榜（全球 500 强 · 市值 · 股价，每日更新）
│   ├── fear-greed/         # 😱 恐慌与贪婪指数（CNN Fear & Greed，每日更新）
│   ├── whats-latest/       # 📰 最新消息是什么？（权威要闻聚合 + 市场快照）
│   ├── world-economy/      # 🌐 全球经济图谱（世界地图·各国经济指标，每日更新）
│   ├── movies/             # 🎬 全球电影榜（高分 Top 250 + 最新上映，每日更新）
│   ├── econ-calendar/      # 📅 全球经济日历（央行决议/CPI/非农…预测值与前值，每日更新）
│   ├── home-value/         # 🧭 房值罗盘（住宅价值参考估算）
│   ├── fish-lab/           # 🐟 声波诱鱼实验室（低频发生器 + 科普）
│   ├── ai-chat/            # ✨ 万象智聊（大模型聊天 · 多会话 · Markdown · PWA 可安装）
│   ├── mosquito-lab/       # 🦟 声波驱蚊实验室（频率发生器 + 科普）
│   ├── calculators/        # 🧮 万象算集（计算器大全 · 分类+搜索 · 70+ 计算器）
│   ├── radio/              # 🌍 环球电波（3D 地球听全球电台 · Radio Browser · 自托管 globe.gl）
│   ├── name-fortune/       # 🏮 知命阁（姓名测算 · 仅供娱乐）
│   └── telescope/          # 🔭 星瞳望远镜（手机摄像头数码望远镜）
├── games/                  # 网页小游戏
│   ├── hub/                # 🎮 游戏中心（游戏合集入口）
│   ├── gta-vice-city/      # 🌆 GTA Vice City 网页版
│   └── red-alert/          # 🚩 红色警戒 2 网页版（嵌入红色井界/共和国之辉 · 战役/联机 · 双源可切换）
├── scripts/
│   ├── ai-rankings/        # 全球大模型评测榜取数脚本
│   │   └── build_rankings.py    # 抓 LMArena/LiveBench/Artificial Analysis → 归一化合成综合分 → 写 data.json
│   ├── university-rankings/ # 全球大学排名 300 强取数脚本
│   │   └── build_universities.py # 抓 QS/THE/ARWU/U.S. News → 按平均位次聚合排前 300 → 写 data.json（内置 SEED 兜底）
│   ├── major-rankings/     # 全球专业与就业前景榜生成脚本
│   │   └── build_majors.py      # 权威整理的专业薪资/就业率/起薪 + 计算 AI 前景综合分 → 写 data.json
│   ├── asset-ranking/      # 全球资产市值排行榜取数脚本
│   │   ├── build_ranking.py     # 合并 大类资产×实时行情 + 公司 + 加密货币 → 按市值排前 250 → 写 data.json
│   │   └── baselines.py         # 各大类资产的储量/存量/M2 基准与分类定义（附来源）
│   ├── house-prices/       # 全球主要国家房价走势取数脚本
│   │   ├── build_house_prices.py # 取 OECD/BIS 房价指数(SDMX-JSON) → 算名义/实际同比·环比·季度趋势 → 写 data.json
│   │   └── countries.py         # 国家清单/区域 + 种子数据（首次/兜底）
│   ├── asset-tracker/      # 全球大类资产收益率取数脚本
│   │   └── build_assets.py      # 取 Yahoo 行情 → 算各周期涨跌 → 写 data.json
│   ├── billionaires/       # 全球富豪实时榜取数脚本
│   │   └── build_billionaires.py # 取 Forbes 实时富豪榜 → 算身价/当日变动 → 写 data.json
│   ├── companies/          # 全球公司市值榜取数脚本
│   │   ├── build_companies.py    # 取 Yahoo 行情按清单算市值 → 上市 450 + 非上市 50 → 写 data.json
│   │   ├── universe.json         # 烘焙清单：约 560 家上市公司（代码/中英名/行业/国别/流通股数/币种）
│   │   └── maps.py               # 中文名·行业·国别映射 + 非上市公司（PRIVATE）列表
│   ├── fear-greed/         # 恐慌与贪婪指数取数脚本
│   │   └── build_fear_greed.py   # 取 CNN Fear & Greed → 读数/7指标/历史 → 写 data.json
│   ├── whats-latest/       # 最新消息聚合脚本
│   │   └── build_news.py         # 聚合 Google News 中文要闻 + Yahoo 行情 → 写 data.json
│   ├── world-economy/      # 全球经济图谱取数脚本
│   │   └── build_economy.py      # 取世界银行多项宏观指标 + 整理央行利率 → 写 data.json
│   ├── movies/             # 全球电影榜取数脚本
│   │   └── build_movies.py       # 从 TMDB API 取高分 Top 250 + 最新上映 → 写 data.json
│   └── econ-calendar/      # 全球经济日历取数脚本
│       └── build_calendar.py     # 取 Forex Factory 周历 → 整理中文/分级 → 写 data.json
└── README.md               # 项目说明（就是本文件）
```

## 数据中心

`apps/data-hub/` 是一个聚合入口：一页汇总下面**全部 11 个实时数据应用**，每张卡片直接读取对应应用的
`data.json` 渲染**实时小预览**（领涨领跌、富豪榜首、恐慌贪婪读数、今日头条、各国央行利率、本周经济大事…）并显示更新时间。
纯前端、无需取数脚本与工作流——它复用各应用每日自动更新的数据，点击卡片即进入对应应用。

## 全球大模型评测榜

`apps/ai-rankings/`（数据中心成员）是一张「全球大模型评测榜」：把 **LMArena 竞技场 Elo**（数百万用户
匿名对战投票）、**LiveBench**（定期换题的客观评测：数学/推理/编程/数据分析/指令遵循）与
**Artificial Analysis 智能指数**（综合多项基准，兼看速度与价格）三个业内公认榜单合到一张表，
GPT、Claude、Gemini、Grok、DeepSeek、Qwen、Kimi、GLM 等中外模型同台，支持按综合/单榜排序、
开源模型筛选与中英搜索，并链接 IntelligenceArena、HF Open LLM Leaderboard、HELM 供延伸阅读。

- **综合参考分**：三榜口径不同（Elo 是相对胜率、LiveBench 是客观题得分、智能指数是综合基准），
  绝对值不可跨榜比较；本站把各轴 min-max 归一化后按 0.4/0.3/0.3 加权得出「综合」列，仅用于粗略排序，页面已注明。
- **数据每日自动更新**：`.github/workflows/ai_rankings.yml` 每日由 `scheduler.yml` 统一触发（北京时间 07:00 前）跑
  `scripts/ai-rankings/build_rankings.py`，抓取 LMArena 页面内嵌 JSON 与 LiveBench 站点数据（均免密钥），
  写入 `apps/ai-rankings/data.json` 提交回仓库；前端 `fetch` 即时渲染。
- **可选第三轴**：Artificial Analysis 提供免费 API（[注册申请](https://artificialanalysis.ai/)），
  把密钥存为仓库 Secret **`AA_API_KEY`** 即启用智能指数轴；未配置时该轴沿用内置快照/上次值。
- **强容错**：三源相互独立，单源失败该轴沿用上次值；三源全失败则保留上次 `data.json` 不覆盖；
  认不出厂商的长尾模型不进榜，榜面截前 40。首次合并前内置近似快照（页面标注），首跑后替换为实时数据。**仅供参考。**

## 全球大学排名 300 强

`apps/university-rankings/`（数据中心成员）把四大权威世界大学排名合到一张表：**QS 世界大学排名**
（侧重学术声誉、雇主声誉与国际化）、**THE 泰晤士高等教育世界大学排名**（18 项指标覆盖教学/研究/引用/产业/国际展望）、
**ARWU 软科世界大学学术排名**（上海交大发起，重科研产出与顶级奖项）、**U.S. News 全球最佳大学**
（以全球研究声誉与文献计量为主）。支持按综合/单榜排序、按国家/地区筛选与中英搜索，并链接四榜官方页供延伸阅读。

- **综合排名**：采用 ARTU 式聚合法，取每所大学在各榜位次的平均值排序（至少命中两个榜才计入综合，位次越小越靠前）；
  各榜评价口径不同，跨榜绝对位次不可直接比较，页面已注明。取综合前 300。
- **年度权威整理**：QS / THE / ARWU / U.S. News 四大排名官网均封锁自动抓取（实测 403 / 超时 / JS 渲染），
  故本榜采用四榜近一期公开位次的**年度整理**（`scripts/university-rankings/build_universities.py` 内置 SEED 数据表），
  **不进入每日调度**；`.github/workflows/university_rankings.yml` 仅保留手动触发，作 best-effort：若日后官网接口对机房可达，
  脚本会自动改用实时数据，否则保留整理数据不覆盖。改数据只需编辑脚本内 SEED 表再重跑生成 `data.json`。**数据以各榜官方公布为准，仅供参考，不构成升学建议。**

## 全球专业与就业前景榜

`apps/major-rankings/`（数据中心成员，与大学排名互相链接）用一份「专业」数据集支撑四张榜单，切换页签即重排：
**专业薪资 Top 100**（职业中期年薪）、**毕业起薪 Top 100**（应届起薪）、**就业率 Top 100**（毕业生就业率），
以及 **AI 时代未来 10 年最有前景专业排名**。支持按学科大类（计算机·AI / 工程 / 医学 / 自然科学 / 商科 / 社科 / 教育 / 艺术）
筛选与中英搜索，每行标注十年岗位增长与「AI 受益 / 中性 / 受冲击」。

- **数据来源**：薪资取自 PayScale 薪资报告与 NACE 起薪调查，就业率综合 US NACE First-Destination、英国 HESA
  Graduate Outcomes 与 QS 毕业生就业力，十年增长取自美国 BLS 职业展望，AI 前景参考 WEF《未来就业报告 2025》。
- **AI 前景分**：`build_majors.py` 计算 `100×(0.40×十年增长归一 + 0.35×AI 需求放大度 + 0.25×(1−AI 替代度))`，
  于是 AI/数据科学/网络安全/机器人/生物技术/可再生能源等既乘 AI 而上、又高增长的专业排名靠前。
- **年度整理**：为年度权威数据（非每日实时），以美元/年、美国市场为基准；改数据只需编辑脚本内数据表再重跑生成 `data.json`。**仅供参考，不构成升学或就业建议。**

## 全球资产市值排行榜

`apps/asset-ranking/` 是一张「不限品类、只看市值」的全球资产排行榜（前 250）：把 **房地产、政府债券、
煤炭、石油、天然气、铁矿石、铝、铜、黄金、白银、各国货币（广义货币 M2）、上市公司、加密货币** 放进
同一张榜按美元市值从高到低排名，支持分类筛选、按市值/今日涨跌排序与中英名/代码搜索，配色分类标签与市值条。

- **方法论（与 assetmarketcap / 8marketcap 同款，可每日实时更新）**：市值 = 数量(储量/地面存量/M2) × 单位价格(实时行情/汇率)。
  商品/贵金属以储量或地面存量 × Yahoo 期货/现货价、货币以广义货币 × 实时汇率、公司与加密货币以实时市值计；
  房地产、政府债务、煤炭、天然气为权威机构存量估值（慢变量，静态基准，附来源）。
- **数据每日自动更新**：`.github/workflows/asset_ranking.yml` 每日由 `scheduler.yml` 在 companies 成功后触发（北京时间 07:00 前）跑
  `scripts/asset-ranking/build_ranking.py`，从 **Yahoo Finance** 取商品/汇率、**CoinGecko** 取加密货币市值、
  复用当日 `apps/companies/data.json` 的公司市值，合并排序取前 250 写入 `apps/asset-ranking/data.json` 提交回仓库；前端 `fetch` 即时渲染。
- **零密钥、强容错**：数据源均免登录；逐项独立容错，某项实时价取不到时回退沿用上次值或静态基准，绝不掉榜；
  体检（榜首量级、条目数）不过则保留上次 `data.json`，不用空/脏数据覆盖好数据——与全站取数风格一致。

## 全球主要国家房价走势

`apps/house-prices/` 是一张「全球主要国家房价走势」看板：约 27 个国家/地区，每条含 **名义同比、
实际（经通胀调整）同比、环比** 与近几年的 **迷你走势图**，支持按区域筛选、按名义/实际同比·环比排序与搜索，
红涨绿跌，一眼看清全球谁的房价在涨在跌。**点击任一国家可展开近 20 年（视各国可获取历史而定）的房价指数
历史走势折线图**（带坐标轴、悬停读数与「全期累计/峰值/较峰值」统计）。

- **数据源（免密钥）**：**OECD 分析性房价指数**（季度，名义/实际，2015=100，历史回溯至 2005）为主，
  **BIS 住宅物业价格长序列**为备源；取数脚本用通用 SDMX-JSON 解析（不写死维度顺序，靠结构元数据识别名义/实际指数），
  同比/环比按真实季度标签对齐（缺季不误算），逐国独立容错。
- **数据每周自动更新**：`.github/workflows/house_prices.yml` 每周一 05:20 UTC 跑
  `scripts/house-prices/build_house_prices.py`（房价为季度数据，每周运行即可接住各国最新已发布季度），
  写入 `apps/house-prices/data.json` 提交回仓库；前端 `fetch` 即时渲染。
- **强容错**：OECD/BIS 都取不到的国家回退沿用上次值 → 内置近似种子，绝不掉榜；全源失败则保留上次
  `data.json`。首次接入官方数据前用近似种子占位（页面标注「近似数据」）。

## 全球大类资产收益率追踪

`apps/asset-tracker/` 是一个「全球大类资产收益率」看板，复刻示例图：把 **股市 / 商品 / 外汇 / 债券**
四大品类的 28 个核心标的，按所选周期（今日 / 近一周 / 近一月 / 年初至今 / 近一年）排序成分品类配色的
条形图，并提供可点表头排序的数据表、品类筛选与图表/表格切换。

- **数据每日自动更新**：`.github/workflows/asset_tracker.yml` 每日由 `scheduler.yml` 统一触发（美股收盘后、北京时间 07:00 前）跑
  `scripts/asset-tracker/build_assets.py`，从 **Yahoo Finance** 公开图表接口取各标的日线，算出各周期涨跌幅，
  写入 `apps/asset-tracker/data.json` 并提交回仓库；GitHub Pages 直接托管，页面前端 `fetch` 后即时渲染。
- **零密钥**：数据源 Yahoo Finance 免登录，无需任何 GitHub Secret——合并到默认分支后定时任务自动接管。
- **稳健取数**：每个标的独立容错、主备双域名、硬超时；单标的失败自动沿用上次值（图上标灰），
  整源被限流则保留上次的 `data.json` 不覆盖，绝不用空数据洗掉好数据。
- **异常值护栏**：标的可配多个候选代码，按序回退；某代码返回超出合理上限的涨跌幅
  （`SANE_CAPS`，如年初至今 >100%、近一年 >150%）即判为数据源脏数据，自动改用下一个候选；
  若候选全部越界，则只隐藏越界周期、保留正常周期并标注 ⚠️，避免脏数据带歪排序。
  护栏可**按标的覆盖**（asset 的 `caps`）：如韩股 2025-26 处于历史级大牛市，年初至今涨幅本就极高，
  已放宽其上限以如实呈现真实收益（而非误判为脏数据）。
- **代理与回退**：LME 铝/铜以全球期货代理；中债-国债总财富指数以国债 ETF 代理；
  韩国/日经指数在原代码数据异常时回退到对应 ETF（页面与数据里均有标注）。**仅供参考，非投资建议。**

> 首次合并前，`data.json` 内置的是示例图的 2024 全年快照（来源 Wind），页面即开即用；定时任务首次运行后
> 会自动替换为实时「年初至今」数据并补全其余周期。要手动触发：仓库 Actions → **Asset Tracker** → Run workflow。

## 全球富豪实时榜

`apps/billionaires/` 是一个「世界前 250 大富豪身价」看板：每人一张卡片，含头像、身价、当日变动、
净值条、国家与行业，并提供领涨领跌摘要、按身价 / 今日涨跌排序与姓名搜索（中英皆可）。

- **数据每日自动更新**：`.github/workflows/billionaires.yml` 每日由 `scheduler.yml` 统一触发（北京时间 07:00 前）跑
  `scripts/billionaires/build_billionaires.py`，抓取 **Forbes 实时富豪榜**公开 JSON 接口
  （`forbesapi/person/rtb`），取前 250，算身价（十亿美元）与当日变动，写入 `apps/billionaires/data.json`
  并提交回仓库；GitHub Pages 直接托管，前端 `fetch` 即时渲染。
- **零密钥**：Forbes 接口免登录，无需任何 GitHub Secret，合并到默认分支后定时任务自动接管。
- **稳健**：当日变动优先用 Forbes 的 `estWorthPrev`，缺失时退回「今值 − 上次快照值」；整源抓取失败则
  保留上次 `data.json` 不覆盖。中文名 / 国家 / 行业做了常见词映射，未命中回退英文，国家附 emoji 国旗。
- 首次合并前 `data.json` 内置示例快照（前 12 人），页面即开即用；定时任务首跑后替换为实时前 250。
  **仅供参考。** 手动触发：仓库 Actions → **Billionaires Tracker** → Run workflow。

## 全球公司市值榜

`apps/companies/` 是一个「按市值排名的全球大公司」看板：每家一张卡片，含 logo、市值、实时股价、
当日涨跌、国家与行业，并提供领涨领跌摘要、按市值 / 今日涨跌排序与中英名·代码搜索，上市/非上市分别标注。

- **数据每日自动更新**：`.github/workflows/companies.yml` 每日由 `scheduler.yml` 统一触发（北京时间 07:00 前）跑
  `scripts/companies/build_companies.py`，按烘焙清单 `universe.json`（标普 500 成分 + 海外巨头 ADR + 三星/沙特阿美，
  每条带流通股数与计价币种）用 **Yahoo Finance**（v8/chart）逐只取最新价，按「价 × 股数」算市值（本币按汇率折美元）、
  算当日涨跌；再并入 50 家知名**非上市公司**（`maps.py` 的 `PRIVATE`，最近一轮公开估值、非实时），
  按美元市值排前 500（**上市 450 在前、非上市 50 殿后**）写入 `apps/companies/data.json` 提交回仓库；前端 `fetch` 即时渲染。
- **零密钥**：Yahoo 图表接口免登录，无需任何 GitHub Secret——与 asset-tracker 同款数据通道。
- **稳健**：逐只独立容错、主备双域名、硬超时；某只当日取不到时自动沿用上次值（不掉榜），有效报价过少或榜首市值离谱时
  保留上次 `data.json` 不覆盖（绝不用空/脏数据洗掉好数据）。
- **logo**：头部公司用 Clearbit 高清品牌 logo，其余回退 FMP 公司图标，再回退首字母字母牌；非上市公司在榜单末段以分隔条与「未上市」徽标标注。
- `data.json` 已内置前 500 真实快照，页面即开即用；定时任务每日刷新为最新市值。
  手动触发：仓库 Actions → **Companies Tracker** → Run workflow。**仅供参考，非投资建议。**

## 市场恐慌与贪婪指数

`apps/fear-greed/` 复刻 CNN 的「市场恐慌与贪婪指数」：半圆**仪表盘**读数（0=极度恐惧 … 100=极度贪婪）、
**上一收盘 / 一周前 / 一月前 / 一年前**参考点、**7 个驱动指标**（市场动能、股价强度/广度、看跌看涨期权、
市场波动、避险需求、垃圾债需求）的分数条，以及**近一年走势**曲线。

- **数据每日自动更新**：`.github/workflows/fear_greed.yml` 每日由 `scheduler.yml` 统一触发（北京时间 07:00 前）跑
  `scripts/fear-greed/build_fear_greed.py`，抓取 **CNN 恐慌与贪婪指数**公开 JSON
  （`production.dataviz.cnn.io/index/fearandgreed/graphdata`，需带浏览器 UA），写入 `apps/fear-greed/data.json`。
- **零密钥**：无需任何 GitHub Secret；仪表盘为纯手绘 SVG，无第三方图表库。
- **稳健**：评级缺失时按分数阈值推导；整源抓取失败则保留上次 `data.json` 不覆盖；历史曲线降采样到约 80 点。
- 首次合并前 `data.json` 内置示例读数（37 / 恐惧），页面即开即用；定时任务首跑后替换为实时数据。**仅供参考。**

## 最新消息是什么？

`apps/whats-latest/` 是一个彭博风格的资讯终端：把权威媒体的实时要闻按板块（头条 / 市场 / 加密货币 /
人工智能·科技 / 国际·地缘 / 中国）聚合呈现，配顶部滚动行情条与右侧市场快照栏，**每条新闻都链接回原文**。

- **真实 / 权威 / 中文原生**：新闻来自 **Google News** 收录的权威媒体，用 `hl=zh-CN` 直接返回中文标题与来源，
  **每条链接回原文**，只做聚合、不改写、不编造；市场快照来自 **Yahoo Finance**。
- **零密钥**：Google News RSS + Yahoo 图表接口都免登录，无需任何 GitHub Secret。
- **更及时**：`.github/workflows/whats_latest.yml` **每 6 小时**跑一次 `scripts/whats-latest/build_news.py`
  （每日多次更新），整源失败则保留上次 `data.json` 不覆盖；全局按链接去重。
- 首次合并前 `data.json` 内置示例要闻，页面即开即用；定时任务首跑后替换为实时聚合。
  **仅作信息聚合，不代表本站观点，仅供参考。**

> 想要每条配 AI 中文摘要（像截图那样的叙述简报）？可在脚本里接入一个 `LLM_API_KEY`，
> 让大模型**仅根据抓到的真实标题**生成「今日要点」综述。默认不启用，保持零密钥与最高稳健性。

## 全球经济图谱

`apps/world-economy/` 以**世界地图（choropleth）**形态展示各国经济状况：**央行基准利率、通胀率、失业率、
GDP 增长、政府债务/GDP、人均 GDP、经常账户/GDP、预期寿命、城镇化率、出口/GDP、人口增长、储蓄率/GDP**
十二项指标一键切换，悬停看数值、配「最高 6 位」速览、完整可排序榜单，以及一段 **Web Audio 生成的环境背景音乐**（🎵 开关，需点击开启）。

- **数据每日自动更新**：`.github/workflows/world_economy.yml` 每日由 `scheduler.yml` 统一触发（北京时间 07:00 前）跑
  `scripts/world-economy/build_economy.py`，从 **世界银行公开 API** 抓取各国最新可得的宏观指标，写入
  `apps/world-economy/data.json`；央行基准利率为整理自公开资料的主要经济体政策利率。
- **零密钥**：World Bank API 免登录；地图库 jsVectorMap 走 CDN，**库不可用时自动降级为榜单表格**。
- **稳健**：单指标失败不影响整体；世界银行数据不足则保留上次 `data.json` 不覆盖；过滤地区聚合项，统一 ISO2 国家码。
- 首次合并前 `data.json` 内置 16 个主要经济体示例，页面即开即用；定时任务首跑后替换为全量国家数据。
  > 注：世界银行宏观数据为年度、取各国最新可得值（年份可能不一）；央行利率为整理值、定期更新。**仅供参考。**

## 全球电影榜

`apps/movies/`（数据中心成员）以**海报墙**形态展示 **高分电影 Top 250** 与 **全球最新上映** 两张榜单，
含排名、评分、票数、海报与中文片名，点击跳转 TMDB 原页；并带一段 **Web Audio 生成的影院氛围背景音乐**（🎵 开关）。

- **数据每日自动更新**：`.github/workflows/movies.yml` 每日由 `scheduler.yml` 统一触发（北京时间 07:00 前）跑 `scripts/movies/build_movies.py`，
  调用 **TMDB（The Movie Database）官方 API** 的 `/movie/top_rated`（高分 Top 250）与 `/movie/now_playing`
  （最新上映），以 `language=zh-CN` 取中文片名与海报，写入 `apps/movies/data.json`。
- **需要一个免费密钥**：在 [themoviedb.org](https://www.themoviedb.org/settings/api) 注册后免费申请 API Key（v3），
  存为仓库 Secret **`TMDB_KEY`** 即可；未配置或取数失败时脚本保留上次 `data.json`、**绝不用空数据覆盖**。
- **为什么不是 IMDb**：IMDb 官方禁止服务器抓取（机房 IP 实测返回空页），TMDB 提供稳定的官方 API 与
  中文本地化，是从 GitHub Actions 可靠取数的正路。**评分为 TMDB 用户评分，仅供参考。**

## 全球经济日历

`apps/econ-calendar/`（数据中心成员）是一个「本周全球经济日历」看板：把**央行利率决议、CPI、非农就业、
PMI、GDP** 等重要经济事件按天分组呈现，每条含**预测值 / 前值 / 实际值**与影响级别（高/中/低）配色，
可按影响级别筛选，事件时间**自动换算为访客本地时区**显示。

- **数据每日自动更新**：`.github/workflows/econ_calendar.yml` 每天跑两次（每日由 `scheduler.yml` 统一触发一次 + 12:30 UTC 定时一次）
  `scripts/econ-calendar/build_calendar.py`，抓取 **Forex Factory 公开周历**
  （`nfs.faireconomy.media/ff_calendar_thisweek.json`），整理为中文、按时间排序后写入
  `apps/econ-calendar/data.json`；跑两次是为了在事件公布后回填**实际值**。
- **零密钥**：数据源免登录、无需任何 GitHub Secret——合并到默认分支后定时任务自动接管。
- **稳健**：货币代码映射为中文国家/地区与旗帜，常见事件名映射为中文、未命中保留英文原名；
  整源抓取失败或返回空则保留上次 `data.json` 不覆盖，绝不用空数据洗掉好数据。
- 首次合并前 `data.json` 内置一周示例事件，页面即开即用；定时任务首跑后替换为本周实时日历。
  **仅供参考，不构成投资建议。** 手动触发：仓库 Actions → **Econ Calendar** → Run workflow。

## 计划

- [x] 确定项目方向：个人主页
- [x] 搭建项目基础结构
- [x] 上传头像
- [x] 第一个游戏：像素大冒险
- [ ] 替换为真实的个人信息
- [ ] 添加更多项目展示

## 许可证

待定
