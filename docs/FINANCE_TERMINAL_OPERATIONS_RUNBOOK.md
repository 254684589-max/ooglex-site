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

优先使用开发分支上的`Finance Terminal V1 Qualification`：

1. 资格脚本或工作流首次推送时自动启动，且只接受`agent/finance-terminal-*`分支；默认生产分支会被硬阻断。
2. `Macro Radar`、`Asset Tracker`与`Companies Tracker`先全部启动，单源失败不取消另外两条独立任务。
3. 只有`Companies Tracker`成功后才启动`Asset Ranking`，避免资产榜读取旧公司快照。
4. 四条任务结束后重新签出同一开发分支的最新提交，运行完整数据、来源健康、回退、治理、门禁和360/768/1280像素浏览器检查。
5. 上传`qualification.json/.md`、`readiness.json/.md`、健康诊断、响应式截图及四项免费代理的机器可读浏览器证据；代理证据只记录代码、宿主状态和受控原因，不保存报价。证据保留7至14天，不进入Git历史。

代理运行Artifact同时包含JSON与Markdown摘要。先查看逐视口`providerScript`：`failed`表示白名单脚本请求本身失败或被阻断，`failureCategory`只以`dns / tls / connection / timeout / blocked / other`受控枚举进一步分诊，原始Chrome错误文本不得写入证据；`loaded`表示只确认固定脚本收到2xx/3xx响应。再查看`diagnosis`区分组件注册超时、宿主验证失败、部分挂载或全部宿主挂载。每个代理还必须精确记录登记的TradingView官方标的链接，并满足`unavailable`时可见、`mounted`时隐藏；证据不主动访问该外链，避免将外部站点可达性误写成页面回退契约。`loaded`和`all-hosts-mounted`都不证明报价已渲染、数据新鲜或市场开市，不得据此补写行情。

质量工作流同一Artifact还包含`finance-terminal-proxy-runtime-history.json`和Markdown趋势摘要。趋势只读取目标开发分支最近14天内的既有代理证据，按21:00 UTC边界对同周期重跑取最新一份，最多保留7个周期；旧证据格式会跳过。GitHub API或只读令牌暂不可用时，`collection`必须标记`partial`并只保留本次真实证据，不伪造旧周期、不阻断生产数据，也不增加四条核心管道的3/7成功计数。

趋势的`assessment`只评价脚本传输和组件宿主，不评价行情。`HEALTHY`要求最近连续两个周期三档脚本均加载且12个宿主观测全部挂载；单周期、部分挂载或告警后的首个恢复周期为`WATCH`；连续两个周期存在脚本传输失败，或连续两个周期12/12均回退时为`WARN`；历史API或令牌不可用时为`UNKNOWN`。这些状态用于运维和统一上线复核，不替代四条核心数据管道的3/7与7/7门槛。

需要单项恢复时仍可按原顺序手动运行：先运行`Finance Terminal Quality`，再运行宏观雷达与跨资产；运行`Companies Tracker`并等待成功后，才运行`Asset Ranking`，最后运行Beta门禁。资格工作流失败不允许强行跳过依赖或修改时间戳，只能修复首个可操作问题后重跑。

同一UTC日更窗口内的重跑只算一个周期；失败后重跑成功不会虚增连续周期。Beta至少观察3个周期，稳定V1至少观察7个周期。

开发分支观察期间使用`.github/finance-terminal-v1-cycle.json`作为受控触发标记：外部日程任务在每日21:00 UTC窗口开启后读取目标开发分支；若标记已属于当前周期或四条管道均达到7/7则不写入，否则只更新该标记的`requestedAt`、`requestedCycleDate`和`requestedBy`。推送会触发资格工作流，但标记不作为成功证据；周期数仍由四条数据工作流的远端完成记录复算。任务不得修改`main`、其他文件、生产数据、发布或部署配置。

### 3. 辅助来源资格闭环

CNN恐慌与贪婪、OFR金融压力、经济日历和财经新闻各自维护独立健康快照。四源均已由真实远端任务建立`tracked`历史；2026-08-12辅助资格确认CNN 1/1组件、OFR 5/5组件全部刷新并显示`HEALTHY`。以后出现`UNKNOWN`、`STALE`或失败时，继续使用开发分支上的`Finance Terminal Supporting Qualification`复核：

1. 资格流程同时启动CNN与OFR，单源失败不得取消另一个来源。
2. 完成后重新读取开发分支最新快照，运行四源健康、生成器失败保留、路径守卫、终端数据与360/768/1280像素页面检查。
3. CNN整源失败时保留旧指数；OFR允许逐组件回退，但全部动态来源失败时不得重写旧数据时间。
4. 辅助来源异常进入自己的`HEALTHY / DEGRADED / FAILED / UNKNOWN / STALE`状态，不得计入或替代核心四管道的3/7周期证据。

辅助资格报告只保存14天诊断，不合并`main`、不创建发布、不部署。修复失败来源时必须运行其原数据工作流，不能手工只改`health.json`或时间戳。

## 状态分诊

| 页面/门禁状态 | 典型原因 | 首要动作 | 禁止动作 |
|---|---|---|---|
| `STALE` / `BLOCKED` | 健康报告超过72小时 | 检查目标分支最近运行和调度链，再运行所属任务 | 手工只改时间戳制造新鲜状态 |
| `DEGRADED` / `WARN` | 部分来源回退、估值或迁移历史待建立 | 查看逐源/逐条覆盖与任务Artifact，确认是否符合既有降级口径 | 把回退或估值改写成实时行情 |
| `FAILED` / `BLOCKED` | 最近整批任务未发布新快照 | 保留旧`data.json`，查看失败来源与诊断Artifact，修复后重跑 | 用空文件、零值或模拟值覆盖旧快照 |
| `UNKNOWN` / `BLOCKED` | 健康文件缺失、契约无效或与数据快照错配 | 运行相应验证器，查找第一个不一致字段 | 放宽验证器或手工对齐两个文件时间 |
| 路径守卫失败 | 生成任务改动了不归本管道所有的路径 | 检查意外差异与脚本副作用，只修复越权来源 | 扩大`git add`范围绕过守卫 |
| 推送冲突 | 其他管道刚向同一分支写入 | 让工作流完成内置fetch/rebase重试；失败后从最新分支重新运行 | 强推、重写连续历史或删除其他管道提交 |
| 免费代理脚本传输失败 | `providerScript.failed`或`request-blocked`，结合受控`failureCategory` | 按DNS、TLS、连接、超时或阻断分类核对固定脚本URL与Runner网络，保留官方链接回退 | 保存原始网络错误、读取响应正文、抓取组件报价或加入未登记镜像 |
| 脚本成功但组件未注册 | `response-ok`配合`component-registration-timeout` | 检查第三方组件版本、浏览器控制台和跨日证据，继续保留逐卡回退 | 把HTTP成功描述为报价可用或缩短生产8秒窗口 |

## 四管道恢复步骤

### 宏观官方序列

1. 查看`macro-radar-source-health.json`，按`DGS10`、`DTWEXBGS`、`RWTC`逐源确认状态。
2. FRED单源失败时只保留该序列的最后有效观测；EIA API失败时先尝试同一`RWTC`官方公开历史页，两条访问路径都失败后才保留旧值。
3. 核对3/3/4个美国工作日的不同过期阈值、DGS10的bp变化和另外两项的百分比变化。
4. 不得用ICE DXY替代`DTWEXBGS`，不得用`CL=F`替代`RWTC`。
5. FRED Secret缺失或失效时只在GitHub仓库设置中处理；EIA Secret可提升API可用性，但不是RWTC公开历史页回退的前置条件。任何密钥都不得写入命令、Issue、日志或聊天。

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
