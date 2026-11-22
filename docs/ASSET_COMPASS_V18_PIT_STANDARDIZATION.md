# Ooglex 全球资产罗盘｜V18 历史版本滚动标准化（研究模块）

## 交付范围
- 新增 `scripts/asset_compass_pit_standardize.py`，复用 V9 的私有 SQLite `macro_vintages`。
- 对指定决策时间 `--asof`，仅查询 **发布时刻不晚于该时间** 的历史版本；同一观测期以当时可得的最新修订为准。
- 基准样本仅包含当前观测期之前的不同观测期；计算 `z=(当前值−历史均值)/历史总体标准差`。
- 默认窗口为 1827 日、最少 36 个**先前观测期**、最新数据时效 120 日。这些只是可配置的**研究阈值**，不是经实证校准的统一正式参数；对日频、周频、月频应按自身频率单独设置。
- 样本不足、陈旧、零方差、无真实归档版本均返回 `status=unavailable` 与 `z_score=null`。绝不补零。
- 输出包含来源 release ID、真实发布时间、基准样本数和比较窗口，`validated_for_live_scoring=false`、`asset_specific_signal=null` 永远不变。
- 新增单元测试覆盖未来修订不可见、样本不足、陈旧、零方差、输入错误与正式评分锁定。

## 使用
本模块是私有研究 CLI，不接入网站的正式资产评分，也不更改网站四页面。

```bash
python3 -m unittest tests.test_asset_compass_pit_standardize_v18 -v
python3 -m scripts.asset_compass_pit_standardize --db /tmp/asset-compass-vintages.sqlite --series US10Y --asof 2026-11-20T12:00:00Z --min-history 252 --max-age-days 11
```

如果没有已核验的真实历史发布版本，第二条命令会明确报告缺失，不会生成虚构样本。

## 待完成
1. 持续合法归档官方发布时间与原始观测，补全跨周期覆盖及修订版本。
2. 单独取得并核验 VIX、信用利差、六资产专属资金流及估值序列，进行独立性检验。
3. 完成按不同频率的历史标准化窗口、缺失和异常事件测试。
4. 在得到合法总回报序列、资产因子方向和独立样本外验证后，再考虑模型权重校准。

**限制：** 单一指标 Z 值不是六资产因子贡献，也不能直接解读为利多、利空、上涨概率、交易建议或 0—100 正式评分。
