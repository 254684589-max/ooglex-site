# Ooglex SOFR V12｜生产定时采集监督（2026-11-23）

## 背景与事实
- 主分支SOFR正式日更：`.github/workflows/asset-compass-sofr-spreads.yml`，UTC周二至周六03:35（台北时间11:35），有`workflow_dispatch`但目前没有通过GitHub连接器发起新运行的能力。
- 2026-11-23核查最近100次Actions运行记录，没有名为`Asset compass SOFR spread history (daily reference)`的真实执行记录。
- `macro/swap-spreads-history.json`仍只有2026-11-20交易日；`macro/swap-spreads-health.json`尚未生成。
- V11 PR #458 的隔离端到端CI已通过，**不等同于生产运行成功**。

## V12 交付
- `scripts/watch_sofr_schedule.py`：GitHub Actions REST API只读获取指定正式采集工作流的运行记录，限定主分支和当天cron时窗，严格要求`event=schedule`；随后验证该运行完成且结论success，并与网站的无报价成功标记在Run ID、时间、数据日期、累计观测数上完全一致。不会把别的PR测试、V8联网探针、手动运行当成定时执行。
- `.github/workflows/asset-compass-sofr-v12-watchdog.yml`：另一个调度，UTC周二至周六07:35（台北时间15:35），计划比主日更晚4小时；只读`actions:read`和`contents:read`，自动输出Summary和14天保留Artifact。若缺少应有的定时运行、失败或状态不一致，会标红**监督工作流**而不是编造数据。
- `tests/test_sofr_v12_watchdog.py`：离线验证真实成功、无运行、源工作流错误、PR/手动冒充、失败/进行中、状态文件缺失或不一致、工作日/周末和重复数据。
- `.github/workflows/asset-compass-sofr-v12-check.yml`：PR专项测试。

## 关键限制
- V12自身也是GitHub schedule，因此它同样可能发生调度延迟/未触发。若监督工作流没有启动，不能误称已自动发现故障。需要到Actions页面检查两项工作流的执行记录。
- GitHub Actions实时检查状态只反映一次运行及已提交的心跳，不证明所有历史交易日连续入库。返回`no_new_observation`并且当次实际成功也可通过运行验收，但不代表数据已经更新。
- 手动触发的成功属于`workflow_dispatch`，与`schedule`应分别披露，本监督默认只接受`schedule`。
- 不自动回填、修改或公布任何新的利率报价；不处理第三方历史许可；无邮件/短信主动通知。监督失败会在GitHub Actions记录为失败，需要另行配置通知。
- 如果首次定时运行于UTC 2026-11-24 03:35被延迟超过4小时，监督可能先标记缺失；以GitHub原始运行记录为最终依据。

## 验收流程
1. PR专项测试通过后合并到main，保证监督和日更在同一主分支。
2. 到UTC 2026-11-24 07:35之后观察两项GitHub Actions的实际run ID与报告。
3. 对比日更任务Step Summary、Artifact、`macro/swap-spreads-health.json`及历史JSON，检查`runId`/时间/数据日/样本数是否匹配。
4. 再单独从公网检查网站HTML与状态文件实际部署，以及客户端布局。

## 当前状态
仅开发PR，没有把未到来的2026-11-24日更标记为成功。
