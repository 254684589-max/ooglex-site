# SOFR V9：正式日更执行证据（2026-11-23）

## 目标
从“已配置每日GitHub工作流”推进到“每一次执行都有机器可读的结果”，但不伪称从未执行的定时任务已经成功。V8 PR #453 真实联网读取成功，返回 `no_new_day`（SOFR与财政部数据日均为2026-11-20，6个期限全部匹配）；其检查本身不等于正式日更任务执行。

## 代码变更
- `scripts/report_swap_spread_ingest.py`：读取既有数据和本轮采集日志，归档为 `new_observation`、`no_new_observation`、`source_revision_conflict`、`date_mismatch`、`source_behind_archive`、`incomplete_or_unsupported_tenors`、`ingestion_error`、`unverified_success`。报告包含最新观测日期、日期年龄、过期标记、归档数和Run ID。
- `.github/workflows/asset-compass-sofr-spreads.yml`：保留周二至周六UTC 03:35与main分支范围；将采集退出码显式保存，采集失败时仍上传诊断Artifact并将整个任务标红；仅采集返回0且正式数据确实发生变化时，才允许既有Git提交行为。
- 诊断仅保留7天GitHub Artifact，GitHub Step Summary显示运行类别和观测日期，不将故障标记直接变成市场分数。
- `tests/test_swap_spreads_ingest_report.py`及PR专项CI：涵盖成功追加、无新日、日期错配、上游修订、缺失期限、未知成功、过期及重复历史。

## 验收说明
1. 本阶段GitHub PR测试只能证明数据契约与工作流代码可用。
2. **真正的定时日更成功**还需要看到main分支下一次schedule或workflow_dispatch运行记录、GitHub退出状态、Artifact、数据归档前后比较。
3. 2026-11-23是周一，配置中的正常下次运行是UTC 2026-11-24 03:35；GitHub schedule可能延迟。不能将“截至目前无日更记录”自动断定为任务故障。
4. 对于同一日期原始数据发生修订，保留旧记录并标记冲突，不自动覆盖。
5. 使用CheckMySwap指示性 SOFR OIS，不是可执行市场报价；数据再发布许可需单独审查。

## 发布
V9开发在独立PR完成，未改写 `macro/swap-spreads-history.json`，未自动回填历史。合并前以本PR所有适用CI通过为准，合并后再监测首次实际日更执行。
