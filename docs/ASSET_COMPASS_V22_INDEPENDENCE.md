# Ooglex 全球资产罗盘 · V22 跨指标独立性与时间一致性

## 阶段交付
1. `scripts/asset_compass_independence_v22.py`：读取私有真实历史版本 JSON，按决策时刻 `asof` 选择已发布的最新修订，严格验证时间戳、来源、唯一性及单位。
2. 以一致观测日期配对，基于连续匹配样本的**差值**作 Pearson 相关诊断。不同频率、有效对不足、零方差时禁止计算相关系数。
3. 硬编码明确的代数关系：`10Y nominal = 10Y TIPS real + 10Y break-even` 和 `10Y-2Y = 10Y nominal - 2Y nominal`，标记不得作为独立三票。
4. `tests/test_asset_compass_independence_v22.py`：8组纯合成测试覆盖高相关、未来修订、频率不一致、代数关系、样本不足、常数列、证据篡改与计分锁。
5. `.github/workflows/asset-compass-research-gates.yml`：增加 PR 离线测试入口，一次验证 V18–V22 研究模块及生产计分锁。

## 统计限制
- **高相关≠因果，也不等于已证实因子重复；低相关也不能证明独立。** 本期是初筛审计，不是稳定性/经济含义或模型预测能力认证。
- 即使观测日期一致，也不意味着在同一时刻首次发布。使用真实发布版本只是必要条件，跨不同公布时间与可投资交易时点仍需审计。
- 一致日期的相邻差值可能跨越缺失观测日；本模块不声称这些是连续交易日收益或标准化的逐日变化。
- 任何第三方历史数据的查询与入库须有真实许可与版本证据；测试使用合成数据并不代表已经取得这些资料。
- 测试结果不能用于推导资产上涨概率、实现六资产专属贡献、正式0–100分、历史回测收益或自动预警。

## 运行
```bash
python3 -m unittest discover -s tests -p 'test_asset_compass_*_v*.py' -v
python3 -m scripts.asset_compass_independence_v22 --input /tmp/real-private-factor-vintages.json --asof 2026-11-20T12:00:00Z
```

## 合并门槛
本阶段依赖 V21（继而 V20→V19→V18）。保持 Draft，直到上游基础测试、当前离线测试、许可证与实际历史时点审核通过。研究工作流不得触发正式评分与公开历史收益绩效。
