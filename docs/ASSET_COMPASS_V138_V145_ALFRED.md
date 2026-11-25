# V138–V145：ALFRED 历史日期版本与 BLS 档案对账

V131–V137真实 run 45604313579/job 139171050238：8/8 CI通过。94份报告，263项统计，77份完整，54项非农修订叙述。52项可比修订中45项匹配、4冲突、3缺历史值。当前FRED对档案：CPI同比45/45在舍入容差内；失业率28/44一致、16/44不同，最大0.1百分点。说明最新修订历史不能直接冒充当时数据。

ALFRED官方说明 https://alfred.stlouisfed.org/help/downloaddata ，历史日期版本和普通最新数据不同。标准FRED API需注册密钥 https://fred.stlouisfed.org/docs/api/fred/series_observations.html 。新增公开图表CSV候选下载，接口使用方式参见 https://prismdatalab.com/posts/alfred-vintages-data-revisions.html （第三方实测，非官方稳定API承诺）。本轮未能在网页工具直接取得CSV，真实下载待CI。

复用94份BLS档案，排除重发和日期不匹配，取报告日期次日ALFRED快照；CPIAUCNS使用同一版本当月与上年同月指数计算同比，UNRATE直接值，PAYEMS同一版本相邻月份级别差乘1000计算新增就业人数。固定域名、拒绝重定向、每批最多6个日期、请求间隔2秒、严格列名及日期绑定、禁止未来非空观测、缺失不补值。CPI和失业率0.05百分点舍入容差，非农人数精确对账。输出逐项日期、摘要、差异与缺口，不保存原始水平序列至仓库。日期级快照不是独立认证的日内发布时刻或历史完整修订链；暂不自动接入正式评分。

Coinbase/FRED CBBTCUSD来源 https://fred.stlouisfed.org/series/CBBTCUSD ，Coinbase市场数据条款 https://www.coinbase.com/legal/market_data 限制研究外部应用使用，未授权公开评分前不接入；黄金发行商许可同样待核实。未购买付费数据、未获取API密钥、未改生产分支。正式OOS已有8折、80事件、5年、3状态要求；现有四资产6–24个六特征测试月、六资产7个共同季度远不足。保留门禁。新增ALFRED研究代码与测试待真实验收，未部署。