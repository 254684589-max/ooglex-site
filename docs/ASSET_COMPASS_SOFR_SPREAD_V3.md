# Ooglex SOFR互换利差｜V3 历史分析与统计资格（2026-11-22）

## 本阶段变更
- 不改变V2原始交易日采集/利差数据口径。
- 新增 `macro/swap-spreads-analytics.js`：独立、无网络依赖的统计计算，检查期限完整性、相同日期重复和利差公式一致性。
- 新增 `macro/swap-spreads-analytics-panel.js`：日频历史统计卡、期限切换和利差结构。
- 修改 `macro/swap-spreads.html`，追加六期限可切换统计面板和10年减2年互换利差结构。
- 新增 `tests/test_swap_spreads_analytics.cjs` 和独立PR检查工作流。

## 指标定义
- 最新利差：`(SOFR OIS fixed rate - Treasury CMT par yield)*100`，单位bp，来源与日期继承V2。
- 变化量：最新利差减去前1、5或20个**已经采集且验证通过的匹配观测日**之利差；缺少观测则显示“样本不足”，不得称为“最近5个完整交易日”。
- 统计窗口：最近252条**先前**有效观测，最新一天不参与历史样本计算。
- 经验分位数：`count(history <= latest) / count(history) * 100`。必须先前样本至少60条，且样本起点与最新观测日相距至少90个日历日。
- 历史参考范围：至少20条先前真实观测后显示历史最小/最大利差。
- 跨期限结构：`10年Swap Spread - 2年Swap Spread`（单位bp）；不能误标成国债期限利差。
- 数据资料不足时不补零、不插值、不推测过去市场报价、不展示伪精确风险分数。

## 解释限制
- 经验分位不是全体历史分位、危机概率、上涨概率或交易信号。
- 覆盖率受实际采集天数约束；一条2026-11-20归档记录时，变化、分位数都应显示“样本不足”。
- CheckMySwap的指示性曲线不等于可执行的市场交易商报价，详见 `docs/ASSET_COMPASS_SOFR_SPREAD_V2.md`。

## 验收
- `node --check macro/swap-spreads-analytics.js`
- `node --check macro/swap-spreads-analytics-panel.js`
- `node --test tests/test_swap_spreads_analytics.cjs`
- `python -m json.tool macro/swap-spreads-history.json`
- 原有V2网页仍须通过360/768/1280px浏览器检查。

## 交付
本阶段作为堆叠PR以V2开发分支为基线，未合并到主分支，未触发生产上线。CI完成前不声称通过验证。
