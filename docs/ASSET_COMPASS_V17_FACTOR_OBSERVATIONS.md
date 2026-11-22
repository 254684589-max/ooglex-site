# Ooglex 全球资产罗盘 · V17 研究性六因子观测证据

## 本阶段交付

新增 `scripts/build_asset_compass_factor_observations.py`，从仓库已有、经过采集程序验证的 `data/asset-scores.json` 提取**六组真实宏观观测**。在定时采集后生成 `data/asset-compass-factor-observations.json`；受保护站点构建时也独立生成并校验，网页 `/macro/attribution.html` 展示观测值、计量单位、观测日期、来源与计算方法。

本阶段**没有**对资产发布实测因子贡献、预测方向、0—100分、回测命中率或资产推荐。

## 六组数据分工

| 因子 | 本期可核验观测 | 本期限制 |
|---|---|---|
| 利率与货币政策 | 美国10Y、2Y名义收益率、10Y TIPS实际收益率、10Y−2Y利差、纽约联储EFFR | 利率当前水平不等于看多或看空哪项资产 |
| 通胀 | 10Y盈亏平衡通胀补偿、CPI与核心CPI同比、核心PCE同比（缺少真正上年同月值时不计算） | 10Y名义−10Y实际与前两者存在代数关系，不得重复算独立投票 |
| 增长与就业 | 失业率、非农月增量、纽约联储模型12个月后目标月份衰退概率 | 不是所有未来12个月内发生衰退的概率，也非纽约联储官方预测 |
| 流动性 | H.4.1总资产、银行准备金、TGA、隔夜逆回购 | 周平均与日度数据不能直接合并；RRPs单位为十亿美元而非百万美元 |
| 风险与信用环境 | 尚无可核验的VIX和信用利差正式数据 | 显示数据不足，不填0 |
| 资产专属估值与资金流 | 仍缺官方授权的CFTC持仓、资金流、估值等完整证据 | 显示数据不足，不填0 |

源数据过期、时间不一致、缺少HTTPS来源、无真实指标数值，都会使该条观测从报告中被**省略**，不会填中性信号。报告中每项值都标记 `qualifies_as_model_factor_signal=false`、`validated_historical_release_time=false`。即使一类因子有若干真实观测，也不意味它们独立、足够或已转换为资产专属因子。

### 公式

- 10Y−2Y 利差（百分点）＝同一观测日的 10Y 名义收益率 − 2Y 名义收益率。
- 10Y 盈亏平衡通胀补偿（百分点）＝同一观测日的 10Y 名义收益率 − 10Y TIPS 实际收益率，**不等同纯粹通胀预期**。
- CPI、核心CPI、核心PCE 同比：仅采用采集管道已经通过官方同月基期核验的数据字段，不通过历史价格回填或自行合成。

### 数据模型安全状态

```json
{
  "report_type": "asset_compass_factor_observations",
  "validated_for_live_scoring": false,
  "factor_signals_calibrated": false,
  "asset_specific_contributions_available": false,
  "independent_factor_group_count_certified": false,
  "no_missing_to_neutral_imputation": true
}
```

这些开关是公开研究报告的防误解说明，不授权开启模型正式评分。已有 `scripts/score_macro_assets.py` 仍保持缺少历史校准与独立样本外有效性时不计分。

## 下一阶段

为VIX、信用利差及资产专属资金/估值取得可合法公开的时间序列，构建**发布时点明确、跨年份统一历史版本**的因子库，再开展五年滚动标准化与多周期样本外检验。不能仅靠单个静态快照生成Z分数，也不能凭概念描述硬设因子权重贡献。
