# Ooglex 全球资产罗盘 V30｜真实宏观采集验收

## 执行前基线（2026-11-22）
- 主分支 `data/asset-scores.json` 当前仍只有 Treasury、BLS 的 CPI/失业率/非农和 NY Fed EFFR，`generated_at=2026-11-21T17:10:30Z`。
- 14项必需来源中7项出现于快照；其余7项尚无已提交真实数据。现有首次观测归档14条，但不代表14个交易日。
- V29 已修复 Treasury 重建快照时清除近期合格 BEA/H41/流动性/衰退模型字段的错误；这项修复本身没有生成缺失数据。

## V30 流程变更
1. `.github/workflows/macro-treasury.yml` 现有工作流添加受限 `push` 触发，仅在自身配置文件合并到 `main` 时触发一次真实抓取；保留原 UTC 周一至周五 23:40 定时和人工触发。数据机器人提交不修改该 YAML，因此不会引发无限循环。
2. BLS 和 NY Fed EFFR 的外部网络异常不再阻断之后的 BEA PCE/WALCL、流动性、NY Fed 衰退模型抓取。对应步骤仍保留实际失败状态，在其他来源归档与远端保存后，统一使任务失败并标注错误；即尽量保存成功的观测，绝不把源故障伪装为全成功。
3. 工作流末尾 `git fetch origin main` 后读取远端最新真实快照与 append-only 历史账本，对两者作逐字节检查，且要求非空账本、已有状态和历史回测及正式评分锁定。
4. 通过 V28 诊断输出当前 `14` 项源的覆盖率、缺源清单、尚未归档指标、数据快照发布时间和历史账本行数。GitHub Actions 运行成功意味着本次抓取及持久化校验通过，**不等于14项来源都到齐**；任何缺源仍在概要中明确列出。
5. 新增6项离线工作流合约单测，确保独立抓取、来源步骤顺序、后置失败汇报、历史账本存盘校验和不解锁正式评分。

## 验收渠道
- GitHub Actions → `Ooglex Macro Official Data Pipeline` → 由本次 V30 合并触发的 `push` 运行。
- 查看 `Confirm snapshot and append-only archive persisted remotely` 及 `Fail run if critical BLS or EFFR collector failed` 两步。
- 真实快照 `data/asset-scores.json` 的 `generated_at` 与对应块源的 `retrieved_at` 必须来自**实际数据抓取**；源失败不可伪造时间。
- 对账 `data/asset-compass-observation-ledger.jsonl`，增加的记录须保留真实首次见到时间，不能将它当作原始官方公布时间。

## 不允许的误判
- 网络请求返回公开当前修订值，**不是**历史上首次发布的实时 PIT vintage。
- 联储 H41、FRED 以及 NY Fed XLS 等真实源缺失时不许填模拟值；不得随意把未通过验证的值算进0–100评分。
- 本阶段仍保持 `validated_for_live_scoring=false`、`eligible_for_point_in_time_backtest=false`，不触发资产投资交易通知。
