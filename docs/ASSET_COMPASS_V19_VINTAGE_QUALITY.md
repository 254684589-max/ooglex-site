# Ooglex 全球资产罗盘 · 第十九阶段：历史发布版本质量审计

## 实际交付
- `scripts/asset_compass_vintage_quality.py`：只读取私有 SQLite `macro_vintages`，以用户提供的 `--asof` 决策时间截断可见记录。
- 月频系列：统计窗口内预期月份、可见月份、缺失月份、观测期间多版本修订及同月多个观测日期冲突。
- 日频和周频：在没有正式交易/发布日历前，**不计算错误的覆盖率**；返回 `coverage_requires_frequency_calendar`。
- 显式报告来源、单位、频率、修订数；没有系列或数据时覆盖率为 `null`，不设成0。
- 研究报告强制标记 `validated_for_live_scoring=false`、`historical_model_validated=false`；不提供正式因子信号、六资产分数、回测表现。
- `tests/test_asset_compass_vintage_quality_v19.py`：7项测试覆盖缺失月份、发布后修订隔离、历史修订计数、无数据、不足覆盖、非月频以及错误参数。

## 使用
此工具不连接生产网站，不上传历史授权数据，不凭今天的最终修订值回填当年发布时间。

```bash
python3 -m unittest tests.test_asset_compass_vintage_quality_v19 -v
python3 -m scripts.asset_compass_vintage_quality --db /tmp/asset-compass-vintages.sqlite --series CPIAUCSL --start 2021-01-01 --end 2025-12-31 --asof 2026-11-20T12:00:00Z
```

没有真实数据库则直接报错；示例中的序列 ID 必须与实际已登记的名称一致。所有测试中的指标均为合成测试夹具，不能被当作实际历史数据。

## 验收与下一步
1. 等待 V18 基础 PR 完成独立单测并合并，之后将本阶段叠加的分支重定向 `main`。
2. 验证月频各系列的发布时间、修订频次、首发/回看覆盖；尚无真实首次发布版本时只能报告缺口。
3. 为每日/每周系列接入正式发布日历，再给出可比覆盖率和跨资产因子可计算性。
4. 获取合法可发布的 VIX、信用利差、资金流与估值的版本化数据；不要假设供应商和接口已经授权。
5. 专门安排样本外测试及模型审核；正式0—100评分、收益预测和自动预警继续关闭。
