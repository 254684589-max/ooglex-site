# 金融终端Beta数据运行与故障恢复手册

本手册用于维护Ooglex金融终端依赖的四条生产数据管道。目标是在不伪造新鲜度、不删除有效旧值、不扩大任务权限的前提下，判断故障、恢复更新并形成可审计的Beta运行证据。

## 适用范围

| 管道 | 工作流 | 页面数据 | 健康快照 | 预期规模 | 主要来源 |
|---|---|---|---|---:|---|
| `macro-radar` | `macro_radar.yml` | `apps/macro-radar/data.json` | `apps/macro-radar/health.json` | 3项官方序列 | FRED `DGS10`、FRED `DTWEXBGS`、EIA `RWTC` |
| `asset-tracker` | `asset_tracker.yml` | `apps/asset-tracker/data.json` | `apps/asset-tracker/health.json` | 28项资产 | Yahoo Finance及已披露代理/回退 |
| `companies` | `companies.yml` | `apps/companies/data.json` | `apps/companies/health.json` | 500家公司 | Yahoo Finance、multiples.vc公开融资估值 |
| `asset-ranking` | `asset_ranking.yml` | `apps/asset-ranking/data.json` | `apps/asset-ranking/health.json` | 250项资产 | Yahoo Finance、CoinGecko、公司榜上游、公开存量估值 |

四条任务只能在目标开发分支上运行。`asset-ranking`依赖当日最新的`companies`快照，必须在公司榜成功后再运行；另外三条可以独立恢复。

## 三层证据不可混用

| 证据 | 回答的问题 | 不能证明什么 |
|---|---|---|
| `data.json` | 页面当前能展示哪份最后有效数据 | 最近一次自动任务是否成功 |
| `health.json` | 最近尝试、最后成功、覆盖率、连续失败与回退 | 远端任务是否已连续稳定运行3或7个周期 |
| Beta门禁Artifact | 四条工作流在同一目标分支上的远端周期证据 | 外部数据许可已完成法律审查 |

页面中的`HEALTHY / DEGRADED / STALE / FAILED / UNKNOWN`只描述仓库内最近健康快照。公开Beta仍以`Finance Terminal Beta Gate`报告的`PASS / WARN / BLOCKED`为准。

## 日常验收顺序

### 1. 本地只读检查

在仓库根目录运行：

```bash
python scripts/validate_finance_terminal.py
python scripts/validate_market_data_quality.py --dataset all
python scripts/validate_market_source_health.py --dataset all --report /tmp/finance-terminal-source-health.json
python scripts/validate_macro_source_health.py --report /tmp/finance-terminal-macro-health.json
python scripts/validate_market_workflow_governance.py --dataset all
python scripts/validate_finance_terminal_release_gate.py
```

修改页面时再运行真实浏览器回归：

```bash
node scripts/validate_finance_terminal_browser.mjs
```

本地门禁契约通过不等于远端运行证据通过。完整报告必须由目标分支上的`Finance Terminal Beta Gate`工作流使用只读Actions权限生成。

### 2. 远端开发分支运行

1. 先运行`Finance Terminal Quality`，确认代码、数据契约、四份健康快照和响应式页面均通过。
2. 运行`Macro Radar`与`Asset Tracker`。
3. 运行`Companies Tracker`并等待成功。
4. 公司榜成功后运行`Asset Ranking`，确保读取同一分支的最新公司快照。
5. 最后运行`Finance Terminal Beta Gate`并下载`readiness.json`与`readiness.md`。

同一UTC日更窗口内的重跑只算一个周期；失败后重跑成功不会虚增连续周期。Beta至少观察3个周期，稳定V1至少观察7个周期。

## 状态分诊

| 页面/门禁状态 | 典型原因 | 首要动作 | 禁止动作 |
|---|---|---|---|
| `STALE` / `BLOCKED` | 健康报告超过72小时 | 检查目标分支最近运行和调度链，再运行所属任务 | 手工只改时间戳制造新鲜状态 |
| `DEGRADED` / `WARN` | 部分来源回退、估值或迁移历史待建立 | 查看逐源/逐条覆盖与任务Artifact，确认是否符合既有降级口径 | 把回退或估值改写成实时行情 |
| `FAILED` / `BLOCKED` | 最近整批任务未发布新快照 | 保留旧`data.json`，查看失败来源与诊断Artifact，修复后重跑 | 用空文件、零值或模拟值覆盖旧快照 |
| `UNKNOWN` / `BLOCKED` | 健康文件缺失、契约无效或与数据快照错配 | 运行相应验证器，查找第一个不一致字段 | 放宽验证器或手工对齐两个文件时间 |
| 路径守卫失败 | 生成任务改动了不归本管道所有的路径 | 检查意外差异与脚本副作用，只修复越权来源 | 扩大`git add`范围绕过守卫 |
| 推送冲突 | 其他管道刚向同一分支写入 | 让工作流完成内置fetch/rebase重试；失败后从最新分支重新运行 | 强推、重写连续历史或删除其他管道提交 |

## 四管道恢复步骤

### 宏观官方序列

1. 查看`macro-radar-source-health.json`，按`DGS10`、`DTWEXBGS`、`RWTC`逐源确认状态。
2. FRED或EIA单源失败时，只保留该序列的最后有效观测；另外两项继续独立更新。
3. 核对3/3/4个美国工作日的不同过期阈值、DGS10的bp变化和另外两项的百分比变化。
4. 不得用ICE DXY替代`DTWEXBGS`，不得用`CL=F`替代`RWTC`。
5. 若FRED/EIA Secret缺失或失效，只在GitHub仓库设置中处理；不得把密钥写入命令、Issue、日志或聊天。

### 跨资产强弱

1. 核对28项逐条`dataMeta`与`dataQuality`汇总。
2. 单项失败可以按登记顺序使用Yahoo镜像、候选代码/明确代理、上一条有效值。
3. 28项全部不可发布时保留完整旧快照，并让健康状态记录整批失败。
4. 历史回退、异常值和缺值不得参与当期强弱排行。

### 全球公司榜

1. 核对500条记录，其中上市公司行情与50家未上市公开估值必须保持不同频率和状态。
2. Yahoo报价、汇率或Logo处理失败时查看公司榜诊断；静态KRW汇率只能作为已披露降级。
3. 有效报价低于50%或榜首合理性检查失败时拒绝覆盖旧榜。
4. 未上市估值不得进入当日领涨/领跌计算。

### 全球资产榜

1. 先确认同一分支的`companies`任务已成功，再检查250项榜单。
2. 核对Yahoo、CoinGecko、公司榜上游和公开估值的角色，不能把同提供方镜像描述为独立备用源。
3. 有效条目少于100项或榜首总值超出既定区间时拒绝发布。
4. 公司榜上游状态必须透传；上游降级不能在资产榜中被升级为健康行情。

## 诊断证据

每条数据工作流和门禁只把逐次诊断保存为14天Artifact，不提交进Git历史。处理问题时至少记录：

- 目标分支、工作流名称、运行链接和UTC时间；
- 失败步骤及首个可操作错误；
- `data.json.updatedAt`、`health.json.lastAttemptAt`、`lastSuccessfulAt`；
- 受影响来源、覆盖率、是否保留旧快照；
- 修复提交和复测结果。

不要复制包含凭据、账号、个人持仓或其他敏感信息的日志。公开问题统一使用金融终端的结构化数据反馈表单。

## 回退与关闭标准

- 代码问题使用新的修复提交；需要撤销错误提交时使用可审阅的`git revert`，不得重置或强推共享分支。
- 数据任务修复后重新从最新目标分支运行，让所属工作流原子生成`data.json`与`health.json`；不得手工只修其中一个文件。
- 关闭故障前，本地质量检查必须通过，四份健康报告必须与数据快照一致且不超过72小时，最近任务不得为整批失败。
- 进入公开Beta评审前，四条工作流必须分别连续成功至少3个日更周期且门禁无`BLOCKED`；稳定V1还需7个周期并消除核心资产演示数据。
- 数据许可、收费方案、Secret权限、生产部署或访问控制问题不在本手册的自动处置范围内，必须暂停并由项目所有者决定。

详细契约见`docs/MACRO_SOURCE_HEALTH.md`、`docs/AGGREGATE_SOURCE_HEALTH.md`与`docs/FINANCE_TERMINAL_RELEASE_GATE.md`。
