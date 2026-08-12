# 金融终端辅助信息源健康与恢复规范

本规范适用于金融终端已经展示、但不属于四条核心行情生产管道的四个辅助来源：`fear-greed`、`ofr-monitor`、`econ-calendar`与`whats-latest`。目标是把“最后有效内容仍可展示”和“最近一次自动任务是否真正刷新”分开记录。

## 范围与时效

| 数据集 | 上游与用途 | 运行频率 | 健康报告阈值 | 终端必需组件 |
|---|---|---|---:|---|
| `fear-greed` | CNN Fear & Greed，市场情绪 | 每日 | 72小时 | `cnn-index` |
| `ofr-monitor` | OFR FSI、短融、货基、对冲基金及美联储G-SIB参考表 | 每日任务；组件为日/月/季/年频 | 72小时 | `fsi` |
| `econ-calendar` | Forex Factory公开周历 | 每日两次 | 36小时 | `weekly-calendar` |
| `whats-latest` | Google News五个板块；Yahoo行情仅供资讯应用自身使用 | 每6小时 | 12小时 | `markets-news` |

健康报告阈值描述自动任务证据，不改变各数据自身的观测时效。OFR月频、季频和年频组件不会因为观测值没有每日变化就被判定过期；任务是否在运行与组件数据日分别展示。

## `health.json`契约

每个应用保留原有`data.json`，并新增同目录`health.json`：

| 字段 | 含义 |
|---|---|
| `status` | `healthy`、`degraded`、`failed`或迁移期`unknown` |
| `historyStatus` | `tracked`表示已由真实任务记录；`migrated`表示旧历史不可追溯 |
| `lastAttemptAt` | 最近一次真实任务尝试时间；迁移时为`null` |
| `lastSuccessfulAt` | 最近一次成功发布快照的时间，不代替金融数据观测日期 |
| `consecutiveFailures` | 连续整批未发布次数；迁移时为`null` |
| `publishedSnapshotAt` | 当前`data.json.updatedAt`，用于阻断健康与内容快照错配 |
| `snapshotPreserved` | 整批失败且保留旧快照时为`true` |
| `coverage` | 组件总数、可展示、刷新、回退、不可用和未知覆盖 |
| `attempt` | 最近一次尝试是否发布，以及各模式的组件ID |
| `components` | 每个组件的频率、角色、模式、最后尝试与成功时间 |
| `policy` | 该来源的健康报告阈值和终端必需组件 |
| `recovery` | 实际采用的恢复顺序 |

首次迁移只确认现有快照中哪些组件可展示，所有组件模式仍为`unknown`，本轮刷新覆盖为0；不得根据文件存在、提交日期或当前可展示数量倒推以前任务成功。

## 发布与失败回退

- CNN或Forex Factory整源失败、空响应时，不覆盖现有`data.json`，只把失败写入健康文件。
- OFR四项动态组件独立刷新。至少一项动态组件成功时允许发布降级快照；其余组件沿用同组件旧值并标记`fallback`。四项动态来源均失败时不重写数据时间。
- Google News五个板块独立刷新。单个板块失败时沿用上一份同板块内容；五个板块均失败时保留整份旧快照。
- `whats-latest`中的Yahoo行情是资讯应用辅助组件，不参与金融终端核心行情，也不能替代Google News市场板块。
- 失败运行先提交新的`health.json`证据，再让工作流以失败结论结束；这样不会出现“任务失败但仓库仍显示上次健康”的假象。
- 空数组、默认零值、另一标的或新`updatedAt`不得覆盖旧的有效内容。

## 工作流与Git治理

四条任务各自使用独立并发组、生成前同步目标分支，并由`scripts/market_workflow_governance.py`限制为只拥有本应用的`data.json`与`health.json`。页面、脚本、其他应用和诊断历史都不在自动提交白名单内。

每次运行的来源健康和路径诊断只保存为14天GitHub Actions Artifact。仓库只保存页面需要的最新数据与最新健康快照；不把逐次日志、截图或长期诊断历史提交进Git。

## 页面与Beta边界

金融终端在CNN、OFR、经济日历和财经新闻现有卡片内显示`UPDATE HEALTH`：

- `HEALTHY`：本轮全部组件刷新。
- `DEGRADED`：本轮已发布，但含组件回退或不可用。
- `FAILED`：最近任务没有发布新快照，旧内容继续保留。
- `UNKNOWN`：首次迁移或健康契约不可验证。
- `STALE`：最近真实健康报告超过该来源的12、36或72小时阈值。

四个辅助来源不是当前公开Beta门禁要求连续3/7周期的四条核心行情管道，不能扩大或替代既有Beta放行条件；但其健康异常必须在页面上独立披露，质量CI也必须阻断契约错配、覆盖率篡改和越权提交。

## 开发分支资格验收

`.github/workflows/finance_terminal_supporting_qualification.yml`用于消除旧快照的迁移`UNKNOWN`，并为当前仍缺少真实健康历史的两条来源建立本轮远端证据：

1. 只接受`agent/finance-terminal-*`开发分支，拒绝默认生产分支。
2. CNN Fear & Greed与OFR先全部触发，再分别等待结果；任一来源失败不会取消另一条独立任务。
3. 触发前保存各工作流已有运行ID，只有本轮新增的`workflow_dispatch`运行可以进入报告，旧成功记录不能冒充本轮证据。
4. 两条任务结束后重新读取同一开发分支的最新提交，交叉校验四个辅助来源的`data.json`与`health.json`、失败保留、路径所有权和金融终端页面。
5. 资格报告与360/768/1280像素截图只作为7至14天Actions Artifact保留，不写入网站历史。

辅助资格通过只表示CNN与OFR本轮工作流都成功且最新快照通过契约检查；它不改变四条核心行情管道的Beta 3周期或稳定V1 7周期门槛，也不代表5项演示行情已经解决。
