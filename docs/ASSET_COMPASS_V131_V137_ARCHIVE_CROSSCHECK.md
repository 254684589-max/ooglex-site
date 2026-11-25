# V131–V137：历史报告与当前官方数据对账

V124–V130 run 45594690260 job 139137558558，8项CI成功。GLD 12季市价/NAV匹配，23列财务摘要最大价格/回报舍入误差0.0049965百分点，平均绝对市价/NAV差0.721358百分点，最大1.7百分点，年化净费用0.40%，不是实测成交成本。六资产共同7季15对相关性及0/5/10/25bp单边成本情景全部计算成功；样本不足正式权重认证。

BLS原文已核对：
- https://www.bls.gov/news.release/archives/empsit_09052025.htm （8月非农changed little带+22,000；失业率插入语）
- https://www.bls.gov/news.release/archives/empsit_12162025.htm （11月非农括号带明确符号）
- https://www.bls.gov/news.release/archives/empsit_01092026.htm （12月非农和失业率并列括号）
- https://www.bls.gov/news.release/archives/empsit_11202025.htm （edged up）
- https://www.bls.gov/news.release/archives/cpi_12122023.htm （截至当前月12个月通胀措辞）

扩充严格标题与月份匹配下的有限措辞，带符号括号值不是推测的0；旧解析优先，缺项保留。新增BLS已提取的同比CPI、失业率与当前官方FRED CPIAUCNS、UNRATE数据的逐月对账，CPI同比从当月/去年同月指数计算，允许原报告0.1百分点的舍入差0.05；排除重发与日期不匹配、留存原文SHA及当前来源摘要、记录不同值和缺失。不同不等于已证明修订事件，相同不等于原始PIT。复用原94份下载结果，不重复抓BLS；新联网结果待CI。黄金、比特币月频及独立PIT和实测投资成本仍未完成。主分支从3a96140a更新至3f0ae9da，4项非重叠JSON以blob SHA合入研究分支，不改生产。未部署。