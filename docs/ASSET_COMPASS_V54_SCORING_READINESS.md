# Ooglex 全球资产罗盘｜V54 六资产0–100评分主线：接口修复与真实就绪缺口

## 本阶段解决的明确问题

V53之前虽然已有一个数学评分器，但生产输出 `assets[asset].validation` 缺失；网站 `macro/compass-pages.js` 又把全局评分状态为 **false** 当作“快照有效”的必须条件。因此，将来真有独立验证的模型，一旦状态转为true反而可能触发前端错误或拒绝展示。本阶段使两端接口一致，**不自动打开评分**。

本次不再增加历史新闻稿数量、UI美化或虚构历史预测成绩，而是让网站明确回答“六资产为什么仍不能打分，哪个因子尚未完成”。

## 实际交付

1. `scripts/score_macro_assets.py` 的 `score_one()` 每个资产同时返回 `validation.historical_calibration_passed` 和 `validation.out_of_sample_passed`，包括因子不足时的空分数。格式与网页消费的验证契约完全一致。单元测试只通过**合成向量**验证未来可正确显示合法已校准分数，并不授权正式交易分数。
2. `macro/compass-pages.js` 不再要求全局 `calibration_verified===false` 和 `out_of_sample_verified===false` 才接收宏观数据。数据快照只要求这两字段确实是布尔值；若展示分数，仍需全局两个true、逐资产两个验证true、资产状态 `calibrated`、0–100合法数值。否则仍严格展示 `— / 100`。
3. `scripts/build_asset_compass_scoring_readiness_v54.py` 从**真实且在仓库已存在的** `asset-scores.json`、`asset-compass-factor-observations.json`、`asset-compass-history-readiness.json` 与 `macro/model-config.json` 构建公开研究就绪报告。逐组列出有多少个当前可用的源观测、原数据缺哪组；逐资产列出六因子权重、源观测覆盖权重（**非合格评分覆盖率**）、评分模型四项阻断原因和实际审批情况。输入留有规范化JSON SHA-256，时间戳与当前快照必须保持对应。
4. `macro/overview.html` 在六资产研究卡片之前新增「V54 六资产0–100评分建设进度」矩阵。若报告缺失、过期对应不上当前快照、含伪造分数或结构异常，即明确显示无合格报告，而不是继续使用旧百分比。
5. `.github/workflows/macro-treasury.yml` 在采集宏观源和首次归档后自动生成V54报告，并与正式快照一同持久提交；远端内容 `cmp` 校验。
6. 测试新增 `tests/test_asset_compass_scoring_readiness_v54.py` 与 `tests/smoke_asset_compass_scoring_v54.cjs`。包含真实研究源与合成未来模型两类输入；后者只用于验证接口，绝不写回网站。

## 目前真正的模型状态

- 六资产：黄金、美股、美国长期国债、美元、比特币、原油，均为 `score=null`、`status=unavailable`；
- 六大组：利率、通胀、经济增长、流动性、风险信用、资产专属资金/估值；
- 目前四组已经有部分真实宏观观测，但**0组构成经审计的资产方向信号**。风险信用、资产专属两组缺少符合当前研究要求的输入；
- 14项宏观源系列历史首发时点PIT认证仍为0；旧财政部来源年份关联错误保持显式隔离，不得据此进行因子校准；
- 资产分数必须至少具备**5组经独立验证的因子**、**85%资格权重覆盖**、通过历史校准和样本外检验；
- 各资产研究权重由 `macro/model-config.json` 提供，**是尚未回测校准的初始权重，不得读成经过测算的上涨概率**；
- 0个正式分数，0个可发布的收益预测和0个自动交易预警。

## 严格区分两类覆盖率

`source_observation_weight_pct_research_only`：有当前宏观真实**观测**的因子组，其权重相加。只供解释我们已采集多少信息，不允许进入评分器。比如某资产可能拥有超过60%的“已采集源数据相关权重”，但其中每项仍可能只有一个宏观快照、与别的源存在代数重叠、缺少方向解释。

`qualified_model_signal_coverage_pct`：真正满足独立性、资产方向、历史发布时间、审计与新鲜度的**模型信号**权重。现阶段全部为0%，不得偷换。

## 验收及可复现步骤

```bash
python3 -m unittest discover -s tests -p 'test_asset_compass_scoring_readiness_v54.py' -v
node tests/smoke_asset_compass_scoring_v54.cjs
python3 -m scripts.build_asset_compass_scoring_readiness_v54 --output /tmp/ooglex-v54-readiness.json
```

最终验收要求原版V18–V53研究门禁与新V54测试全部通过，PR受保护站点构建成功，main代码合并，正式宏观采集流程实际生成新版报告、校验 GitHub 远端提交。**“代码合并”与“正式宏观数据已运行并同步到网站”是两种不同验收状态。**

## 下一阶段 V55 应解决的真正模型问题

1. 使用已有V18 `asset_compass_pit_standardize.py` 对**私有、可核实发布时刻的时间序列**按频率滚动标准化，独立记录来源、单位、观测期、发布时刻、历史窗口；禁止单快照“Z-score”。
2. 建立「研究候选因子 → 针对六资产的方向映射 → 去重与独立性审查 → 历史校准」的清晰接口。任何未验证的 `verified=true` 不能自动成为投资信号。
3. 合规取得风险信用和资产专属两组的真实历史数据，并以可信回报序列进行跨制度样本外验证；逐资产获取资格，而非一次性解锁所有分数。
4. 数据证据仍不足时继续使用未开放状态，而不是以主观赋值或示例模拟推动评分上线。
