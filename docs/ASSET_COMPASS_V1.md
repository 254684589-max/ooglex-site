# Ooglex 全球资产罗盘｜Asset Compass V1

## 定位

网站首页数据栏目中的独立专栏，入口 `/macro/`。六类资产：黄金、美股、美国长期国债、美元、比特币、原油。

## 数据来源与观测日期

| 采集模块 | 权威来源 | 字段 |
|---|---|---|
| `update_asset_scores.py` | 美国财政部 | 2Y/10Y 名义收益率、10Y TIPS 实际收益率、10Y-2Y、名义与实际差 |
| `update_macro_bls.py` | BLS Public Data API v1 | CPI-U SA 同比、失业率 SA、非农就业总量 SA 月差 |
| `update_macro_nyfed.py` | 纽约联储 | EFFR、FOMC 目标区间 |

注意：10年名义与实际之差是盈亏平衡通胀补偿，不等于消费者真实通胀预期。就业初值会修订。市场休市日期不应被伪装成今日最新报价。

源数据与导出展示的使用许可独立审核，尤其是 FRED / ICE / ISM / Cboe 衍生或授权数据。

## 评分引擎与发布门槛

`scripts/score_macro_assets.py` 执行六大因子资产特定加权：`50 + 50 × Σ(weight × signal)`。权重在 `macro/model-config.json`，信号范围 -1 至 1。

正式分数发布前至少满足：
- 六大因子至少五类完成可核验的新鲜数据；
- 因子权重覆盖率至少 85%，缺失值不得重新加权冒充完整分数；
- 原始数据按发表日期归档，历史信号使用**当时可用版本**；
- 模型历史校准与独立样本外验证均通过；
- 发布每个资产的因子贡献与更新时间。

**目前这些条件未全部满足，页面不显示完整分数。**

## 历史验证 CLI

`python3 scripts/backtest_asset_compass.py --signals /path/signals.csv --prices /path/prices.csv --output /path/report.json`

信号 CSV 列名：`asset,observation_date,available_at,score`。
价格 CSV 列名：`asset,date,close`。价格必须采用同一个口径（需处理拆股、分红、交易日历、成交成本），且来源获许可。

当前 CLI 验证发布日期不晚于观察日 UTC 收盘，计算21个交易日的远期收益，时间序列前75%训练、末25%测试，禁止训练收益跨入测试集，测试采用非重叠区间。输出仅为**研究诊断**，不能自动解锁实时评分。下一步需增加多时期扩展窗口、不同市场时期、统计显著性与资产风险指标。

不使用模拟历史数据作为真实回测证据。

## 验证与部署

- 本地单元测试：`python3 -m unittest discover -s tests -p 'test_macro_*.py' -v`
- GitHub PR Actions 的 `Ooglex Macro Unit Tests` 会再进行在线数据源检查；
- 采集失败则不生成有效数据，不触发完整分数；
- 合并 `main` 后 `Deploy Protected Ooglex Pages` 才发布正式站；
- 单独 `Ooglex Macro Official Data Pipeline` 按工作日 UTC 23:40 定时更新，且其是否有权限写入仍需在合并后验证；
- 线上需检查 `/macro/`、首页入口、`/data/asset-scores.json`、移动屏幕显示以及提示信息。

## 状态（V1-Preview）

已实现独立专栏、官方指标采集、静态指标界面、评分发布防线、时间顺序回测框架与单元测试。尚缺充足独立因子、可信的长期真实回测、完整资产评分；不能宣称投资预测效果。
