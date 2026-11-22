# Ooglex SOFR V13｜GitHub调度注册状态真实预检

## 范围与背景
2026-11-23核查，正式历史归档仍只有2026-11-20一个交易日，`macro/swap-spreads-health.json`尚未生成；最近100条GitHub Actions运行列表中尚无正式SOFR日更或V12监督任务运行记录。明天才到首次计划执行日。此前V11端到端模拟测试成功，但不是生产成功。

当前GitHub连接器能读取Actions运行列表，却不支持直接查询Actions工作流注册状态。因此V13通过仓库内GitHub Actions的 `GITHUB_TOKEN` 以只读方式调用GitHub REST API核对注册与启用状态。

## 验证条件
- 仓库默认分支必须为 `main`。
- 两项工作流的GitHub注册路径必须与仓库中真实文件一致，状态必须 `active`。
- 正式日更仍为周二至周六 `35 3 * * 2-6`（UTC）。
- 独立监督仍为周二至周六 `35 7 * * 2-6`（UTC）。
- 两者保留手动测试入口及主分支约束。检查不写入行情、不能修改采集计划、不触发新的定时运行。
- 结果只证明**工作流已注册并启用**，不证明下一次GitHub schedule必然运行；注册成功不等于生产采集成功。

## 文件与CI
- `scripts/audit_sofr_workflow_registration.py`：只读查询GitHub API, 输出JSON报告。
- `tests/test_sofr_v13_registration.py`：无网络单元测试，覆盖禁用、遗漏、cron错配、默认分支错配。
- `.github/workflows/asset-compass-sofr-v13-check.yml`：PR触发，使用 `actions:read`/ `contents:read` 权限直接核对GitHub真实注册状态；报告存入14日Artifact。
- 若API权限不足、未注册或工作流禁用，CI应明确失败而非假装通过。

## 首轮生产验收
2026-11-24 11:35台北／北京时间对应正式采集计划；15:35为监督检查计划。GitHub可能延迟或跳过。要认定完成，必须看到正式`schedule`运行及输出，成功后核查JSON成功状态、原始历史和Run ID；V13不会提前伪造它们。
