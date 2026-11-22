# V19｜BlueGamma真实历史 API 接入与采购决策（2026-11-23）

## 已由供应商公开页面确认
- 官方历史互换率接口：`GET https://api.bluegamma.io/v1/historical_swap_rates`，必传 `index=SOFR`, `tenor`, `start_date`, `end_date`，请求头 `x-api-key`。文档：https://www.bluegamma.io/interest-rate-api
- USD SOFR历史官方宣传从2023年3月起：https://www.bluegamma.io/swap-rates
- 历史日期par swap是基于每日市场报价重建曲线后重新估值，不保证是原始不可变快照：https://www.bluegamma.io/methodology
- 官网报价：按指数起价USD 349/月，14天试用可以测试API：https://www.bluegamma.io/demo/api
- 产品公开展示、衍生价差、批量存储和对外分发属于需要写入合同的独立授权，不应假定上述基础费用已经包括：https://www.bluegamma.io/solutions/fintechs

## 暂缺的实质证据
- 六个期限2Y、3Y、5Y、7Y、10Y、30Y是否在历史全期逐日返回：**尚无合法试用API Key，因此未实际验证**。
- USD SOFR OIS固定腿日期计数、结算、报价截点与CheckMySwap是否可比：需要合同和真实样本确定。
- 用于Ooglex公共网页重新发布和下载历史利差的价格、许可范围：**未获得报价**。
- API调用频率、数据存储期限、供应商历史修订版本记录：需要明确证据。

## 接入禁止事项
不得把纽约联储的隔夜SOFR均值、FRED已终止的LIBOR swap历史伪装为2Y—30Y SOFR par swap。不能通过网页抓取规避商业API许可。不能在仓库、网站、PR中提交API Key或未获许可的BlueGamma历史市场报价。不覆盖CheckMySwap现有2026-11-20冲突记录。

## 为授权申请的询价要点
请 BlueGamma 确认：六期限完整性、2023-03起数据按日可查询性、历史版本/方法、试用token、试用期间可用于内部核验的限制，以及Ooglex公开商业网页显示「BlueGamma SOFR par swap − US Treasury CMT」及历史图表的书面授权价格。

## 本阶段状态
V19已建立独立、无报价、无Key、不可自动生产切换的供应商检查文件及离线合同测试。未真正连接供应商授权API，未购买授权，未取得公开展示许可。下一步是签约/试用后运行最小真实日期样本验收。
