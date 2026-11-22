# SOFR V11｜正式日更首次执行前完整链路验收

## 本阶段目的
截至2026-11-23（北京时间），GitHub主分支的SOFR日更工作流已经配置，但最近100条Actions记录中没有该工作流真正执行的记录；正式历史仍只有2026-11-20一条。V10的成功状态文件 `macro/swap-spreads-health.json` 尚不存在，原因是**正式成功运行尚未发生**，不能人工伪造。

V11不继续扩充金融指标，而是补齐现有三个生产脚本的隔离端到端检查：
1. `update_swap_spreads.py`：从明确日期的SOFR与财政部模拟输入生成历史观测，公式、日期和方法沿用生产代码。
2. `report_swap_spread_ingest.py`：读取真实命令退出码/日志，区分新增数据、无更新和错误。
3. `publish_swap_spread_health.py`：只有成功的证据能输出无报价的成功状态。

## 测试案例
- **新日期**：从完全隔离的合成夹具增加一条六期限观测，并形成对应运行证据和成功状态，始终不将夹具写入仓库。
- **同日幂等**：对现存2026-11-20归档精确匹配的测试夹具，验证输出 `UNCHANGED`，文件字节级不发生变化，状态不误报新增交易日。
- **历史修订冲突**：若同日期原始来源值不一致，采集失败，旧历史字节不变，报告状态为 `source_revision_conflict`，不允许成功状态文件生成。
- **日期不匹配**：SOFR与财政部两端日期不同则拒绝，历史和成功状态均不能更新。

## 安全边界
所有新增行情数字**仅存在于测试运行器的临时目录中，是虚构的测试夹具**，并非金融市场数据。CI只读权限，不需要外部API、密钥或额外数据源许可。生产数据 `macro/swap-spreads-history.json` 保持不变，首次正式成功状态文件依然由主分支日更任务产生。

## 正式日更后必须确认
- 计划UTC周二至周六03:35运行，下一次为UTC 2026-11-24 03:35（台北/北京时间11:35），实际GitHub schedule可能延迟。
- GitHub `Asset compass SOFR spread history (daily reference)` 工作流出现真实 `schedule` 或 `workflow_dispatch` 事件；PR任务不能替代。
- Step Summary与7天Artifact中的 `ingestionResult`、`lastArchivedObservationDate`、`ingestionExitCode` 可互相核对。
- 首次真正成功后产生 `macro/swap-spreads-health.json`；如 `no_new_observation`，应保持原数据日期不变。
- 若返回失败，报告失效原因；历史不可静默替换。不将绿色Actions结果误称为新交易日行情发布。
- 网站公开域名、手机桌面布局，以及第三方历史数据再发布许可仍需单独验证。

## 状态
本PR只交付完整链路离线验收。CI通过后可考虑合并，但**不能据此声称首次真实定时日更已经完成**。
