# 聚合行情来源健康与恢复规范

本规范适用于金融终端复用的三条聚合管道：`asset-tracker`、`companies`与`asset-ranking`。目标是把“最后有效数据”和“最近一次取数是否成功”分开记录，避免整源失败后旧快照仍被误认为本轮更新。

## 文件与契约

每条管道保留原有`data.json`，并新增同目录`health.json`：

| 字段 | 含义 |
|---|---|
| `status` | `healthy`、`degraded`或`failed`；只描述管道健康，不替代逐条数据状态 |
| `lastAttemptAt` | 最近一次自动任务尝试时间 |
| `lastSuccessfulAt` | 最近一次成功发布快照的时间；不是金融数据本身的观测日期 |
| `consecutiveFailures` | 连续整批未发布次数；首次迁移无法追溯时为`null` |
| `publishedSnapshotAt` | 当前`data.json.updatedAt`，用于阻断健康文件与行情快照错配 |
| `snapshotPreserved` | 本轮未发布且保留旧快照时为`true` |
| `coverage` | 发布数量、最近任务当时的市场行情覆盖、已验证、可用以及逐条模式计数；不代表查看页面时仍然新鲜 |
| `attempt` | 最近一次尝试是否发布、产生多少记录及其模式计数 |
| `sources` | 各登记来源在本轮尝试中的记录数、状态与最后成功处理时间 |
| `recovery.steps` | 实际代码采用的恢复顺序，不代表独立供应商服务等级 |

`health.json`失败时可以更新，`data.json`仍保持最后有效版本。页面因此可以同时表达“数据快照仍可用”和“本轮管道失败”。

## 来源与恢复矩阵

| 管道 | 主要来源与频率 | 无密钥 | 当前条款状态 | 已实现恢复顺序 |
|---|---|---:|---|---|
| `asset-tracker` | Yahoo Finance日线，日频 | 是 | 使用现有公开接口；公开展示及商业使用条款仍需专项核查 | Yahoo备用域名 → 已登记候选代码/明确代理 → 上一条有效值 → 完整旧快照 |
| `companies` | Yahoo Finance股价与汇率，日频；multiples.vc公开融资估值，不定期 | 是 | 两类来源均需在正式商业化前完成条款复核 | Yahoo备用域名 → 已披露KRW静态汇率并降级 → 单公司旧值 → 低于50%覆盖或体检失败时保留整榜 |
| `asset-ranking` | Yahoo Finance日频、CoinGecko加密市值、`companies`上游快照、公开存量估值 | 是 | Yahoo、CoinGecko与估值资料分别待完成正式授权/引用核查 | Yahoo备用域名 → CoinGecko失败时Yahoo价格×静态流通量 → 公司榜上游快照 → 旧值或静态基准；整榜体检失败时保留旧榜 |

Yahoo的`query1`与`query2`只是同一提供方的镜像域名，不应被描述为独立备用供应商。ETF、期货、静态流通量和静态汇率仍按现有逐条备注明确标为代理或兜底，不能升级为原始标的口径。

`asset-tracker`的ETF、期货或替代指数候选一旦被选中，必须同时写入结构化`proxy`：`type`、目标`targetSymbol`、实际工具名称与`instrumentSymbol`、三位ISO币种、`price`或`total-return`回报口径及误差说明。实际行情代码必须与逐条`symbol`一致且不得等于目标代码。金融终端与跨资产详情页会显示`PROXY`，无效或不完整契约在发布前被拒绝；代理行情仍可保持`market/ok`，但不因此升级为目标指数的精确收益。

## 发布与失败判定

- `asset-tracker`：28项全部无法获得可发布行情时拒绝覆盖完整快照；单项失败可沿用上一条并标记回退。
- `companies`：有效报价低于公司清单的50%，或榜首市值不在既定合理区间时拒绝发布。
- `asset-ranking`：有效条目少于100项，或榜首总值不在50万亿至2000万亿美元区间时拒绝发布。
- 动态行情的回退、来源待确认或不可用会使管道`degraded`，但不会等同于整批失败。
- 已登记的慢频估值（公司榜未上市融资估值、资产榜公开存量估值）使用`estimate`和`weekly/monthly/quarterly/annual/irregular`频率；`status: partial`只表示报告日期等慢变量字段不完整，不再被误报为每日行情失败。
- 资产榜中价格乘公开存量/流通量形成的市值代理仍属于动态记录，必须保持`mode: market`、披露代理来源；仅对已登记的“公开存量基准/世界黄金协会”`partial`路径视为可用代理，其他动态`partial`、回退或未知路径继续降级。
- 只有未发布新`data.json`的尝试才增加`consecutiveFailures`；成功发布后归零。

## 验证与诊断

`scripts/validate_market_source_health.py`会交叉校验健康文件、逐条`dataMeta`、文件级`dataQuality`和`data.json.updatedAt`。只读质量工作流将三条结果汇总为`source-health.json`诊断产物，保留14天；诊断文件不进入生产页面、不会调用外部接口，也不读取Secrets。

金融终端按三条日频管道既有的72小时时效检查`lastAttemptAt`。超过阈值后健康栏显示`STALE`和明确过期说明，并把`freshCoveragePct`标为“本轮行情”，避免把上次任务当时的覆盖率冒充当前行情新鲜度。公司榜与资产榜运行卡另显示“慢频估值 x/y”，动态行情、已披露市值代理与静态估值分层计算。

健康状态只说明数据工程链路，不构成对来源准确性、许可范围或投资价值的保证。

Beta上线门禁会复用同一72小时时效和交叉校验：健康报告过期、最近整批失败或与发布快照错配时均输出`BLOCKED`；近期降级和首次迁移历史为`WARN`。旧快照可继续供页面标记过期后参考，但不能替代远端自动任务连续成功的证据。完整规则见`docs/FINANCE_TERMINAL_RELEASE_GATE.md`。

## 更新任务与Git历史治理

三条自动更新任务共享一个Git分支，但拥有互不重叠的生成路径：

| 管道 | 允许提交的路径 |
|---|---|
| `asset-tracker` | `apps/asset-tracker/data.json`、`health.json` |
| `companies` | `apps/companies/data.json`、`health.json`、`logos/`根目录下的PNG |
| `asset-ranking` | `apps/asset-ranking/data.json`、`health.json` |

- 每条管道使用独立的`market-data-<dataset>-${{ github.ref }}`并发组，阻止同一任务重叠运行。三条任务不共用一个并发组，避免GitHub Actions在同组已有等待任务时用新任务替换旧等待任务。
- 工作流只接受分支引用，并在生成前以远端`FETCH_HEAD`快进本地分支；`asset-ranking`因此会读取调度器已确认成功、且刚同步到本地的`companies`快照。
- `scripts/market_workflow_governance.py`在暂存前扫描已跟踪、已暂存与未跟踪文件。发现越权路径即失败，不能用宽范围`git add`夹带页面或脚本。
- 守卫通过GitHub步骤输出明确区分有差异与无差异；文件完全一致时跳过提交和推送。`health.json`中真实的最近尝试或状态变化仍属于有效差异，不会为了减少提交而隐瞒管道运行状态。
- 每次运行的来源健康与路径诊断只保留为14天GitHub Actions Artifact，不把逐次诊断历史、截图或报告文件提交进仓库。仓库只保存页面需要的最新数据与最新健康快照。
