# Ooglex 全球资产罗盘 V25｜真实首次观测账本连续性

## 排查结果（2026-11-22）
- `.github/workflows/macro-treasury.yml` 定时在周一至周五 23:40 UTC 执行。它在数项实时外部源采集、研究因子构建之后才归档；其中任一前序步骤失败，会阻断归档执行。
- GitHub `main` 曾未查询到 `data/asset-compass-observation-ledger.jsonl` 和 `data/asset-compass-history-readiness.json`；无法由此断定后台历史数据已经持久化，更不能证明官方首次发布历史版本已存在。
- GitHub Actions 的脚本定义不能代替真实采集结果；需结合工作流日志与仓库实际账本文件确认。

## 改动
1. **独立归档 GitHub Actions**：`.github/workflows/asset-compass-independent-archive.yml`，每周二至周六 UTC 01:20 调度，也支持手动工作流启动。先读取已经提交至 `main` 的官方快照，不要求再次联网下载。
2. **新鲜度验证**：`scripts/check_asset_compass_archive_continuity_v25.py` 只接受最近48小时内由管道产生的快照。超过时限、未来时间、来源字段缺失或未通过快照验证时失败告警；不把旧值误记为当天全新官方发布。
3. **只允许追加**：保留旧账本全量且严格顺序，不允许删除、回写、倒填、虚构官方首次发布时间或篡改已有版本。对于与此前完全相同的观测不会新增记录。
4. **远端持久化验收**：Git 提交并推送后，重新获取远端 `main`，逐字节对比账本；权限问题、Git 合并冲突或远端未保存时让 GitHub Actions 标红并输出故障摘要。
5. **并发串行化**：原来的官方宏观数据流水线和新增独立归档作业采用同一 concurrency group，并禁止取消正在进行的归档。
6. **离线单测**：新增10项合成测试，涵盖陈旧数据、未来时刻、来源失效、篡改、截断、重复、伪造官方版本和回填历史时间。
7. `asset-compass-research-gates.yml` 将 V25 文件和工作流变更纳入既有自动测试触发范围。

## 真实持续归档的局限
- 独立归档的 `first_seen_at` 只表示 Ooglex 此次**第一次看见并记录**某个数据。它不是 BLS/FED/Treasury 原始发布时刻。
- 如果数据管道连续失败超过48小时，独立任务会明确失败，**不会**从旧快照伪造新的每日观测；需要修复采集源或权限。
- GitHub Actions 调度可能延迟或不触发；只有实际成功执行、成功推送及远端账本存在才意味着连续归档已开始。
- 本阶段不拉取付费历史数据、不迁移私有 SQLite 到公开仓库、不启用收益回测/正式0–100分或自动预警。
- GitHub Actions 失败记录与仓库 Actions 通知是最基础告警渠道。尚未接入额外邮箱、短信或第三方自动呼叫渠道。

## 验收命令
```bash
python3 -m unittest discover -s tests -p 'test_asset_compass_*_v*.py' -v
python3 -m scripts.check_asset_compass_archive_continuity_v25 --mode preflight
```

如果当前 `asset-scores.json` 的 `generated_at` 超过48小时，第二条命令应明确失败，这是正确的安全行为，不是需要绕过的检查。

## 下一阶段必做
- 检查官方采集流水线实际历史运行记录与失败步骤；如果失效须修复真实采集，而不能延长快照时限以伪装新鲜。
- 在 `main` 核实 `data/asset-compass-observation-ledger.jsonl` 首次出现、持续增量和发布元数据。
- 以后真正的官方首次发布 vintage 历史需要独立资料和许可核验，并留存在私有历史库。
