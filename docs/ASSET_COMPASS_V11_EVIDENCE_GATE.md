# 全球资产罗盘 V11｜真实历史回测证据准入

## 本阶段的工作范围

本阶段实现**可重复运行的模型回测证据审计**，不是声称六类资产已在过去若干经济周期预测成功。统计检验本身不能代替数据的真实性、来源许可或独立审计。

### 数据事实（本阶段开始时核实）

- `data/asset-compass-observation-ledger.jsonl` **尚未出现在 main 仓库**。
- `data/asset-compass-history-readiness.json` **尚未出现在 main 仓库**（网站构建可在部署产物中自动生成元数据文件）。
- 这意味着正式归档还没有可核查的累积记录；上一阶段在 GitHub Actions 测试环境成功归档9项，只是测试证据。
- 现有历史国债观测并不是可回溯的官方历次首发版本；六类资产的历史报价也不是统一口径的可投资总回报数据。

### 准入流程

1. 取得官方首发及修订版本的原始归档证据，明确实际 `available_at`，不能用数据观测期或 Ooglex 首次采集时间倒推。
2. 取得合法、可持续使用的资产总回报历史（股息、ETF分红、期货展期与资金成本、交易日历等），逐源保存许可和口径证明。
3. 使用预先冻结的参数划分多时期滚动样本外，防止看过测试集后调参。只用当时可知的数据形成信号。
4. 对方向命中率报告基准、独立样本数和置信区间，并控制多重检验与重叠持有期产生的相关性。研究胜率不是资产上涨概率。
5. 取得外部独立审计并明确批准的发布方案。当前 `scripts/audit_asset_compass_oos_evidence.py` **不会**自行将任何报告认证为可发布的模型成绩。

### 研究工具

```bash
python3 -m scripts.asset_compass_walkforward --signals /tmp/actual_signals.csv --prices /tmp/licensed_asset_closes.csv --output /tmp/rolling_diagnostics.json

python3 -m scripts.audit_asset_compass_oos_evidence --diagnostics /tmp/rolling_diagnostics.json --manifest /tmp/verified_evidence.json --output /tmp/oos_evidence_audit.json
```

第二步输出 `validated_for_live_scoring=false`。它是**证据缺口报告**而非自动发布授权。

### 统计约束

目前研究验收起始门槛设置为至少8个不重叠滚动测试区间、报告至少80个活跃历史测试信号、至少5年跨度；这些只是最低研究数据质量检查，**不是统计显著性或策略有效性的充分条件**。每段的21个交易日标签可能共享市场风险，即使测试区间没有交叉也不应随意当作独立伯努利试验。Wilson 区间和精确二项尾概率工具用于经过独立性检验的事件级别输入，不直接用于叠加滚动窗口结果。

### 当前发布边界

继续展示美国财政部、BLS、纽约联储真实宏观观测、六类资产报价覆盖和历史归档进度。不向公众提供缺少合格证据的收益回测绩效，不将滚动诊断视为校准通过，不启用未验证的资产评分。
