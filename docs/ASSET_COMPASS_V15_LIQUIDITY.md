# 全球资产罗盘 V15｜美联储流动性组件与纽约联储衰退模型数据核验

## 三项已开发的独立流动性指标

| 指标 | 真实序列 | 原始提供者 | 数据口径 | 定期刷新 |
|---|---|---|---|---|
| 银行准备金 | WRESBAL | Federal Reserve Board H.4.1（经FRED镜像） | 周平均、百万美元 | 工作日检查 |
| 财政部一般账户 TGA | WTREGEN | Federal Reserve Board H.4.1（经FRED镜像） | 周平均、百万美元 | 工作日检查 |
| 隔夜逆回购 RRP | RRPONTSYD | New York Fed（经FRED镜像） | 日度、十亿美元 | 工作日检查 |

数据网址分别为：
- https://fred.stlouisfed.org/series/WRESBAL
- https://fred.stlouisfed.org/series/WTREGEN
- https://fred.stlouisfed.org/series/RRPONTSYD

采集程序在 `scripts/update_macro_liquidity.py`，独立下载、校验和部分写入。失败或陈旧时网页显示「暂无数据」。零隔夜逆回购是合法观测值；绝不能因为值为0而忽略。所有资产收益评分继续锁定。

**风险提示：三项观测频率、单位、资金传导机制不同，不能直接加减当成可投资的净流动性；即使人为统一单位也不能自动消除日期错配或金融机构资产负债表的其他变化。**

## 纽约联储未来12个月衰退概率

纽约联储官方 `https://www.newyorkfed.org/research/capital_markets/ycfaq.html` 明确将10年减3个月利差纳入收益率曲线模型。官网也提供月度 `allmonth.xls`：`https://www.newyorkfed.org/medialibrary/media/research/capital_markets/allmonth.xls`。V15 先使用**只读文件格式探针** `scripts/inspect_nyfed_recession_workbook.py`，成功确认官方工作表名为 `rec_prob`，包含 `Date` 与 `Rec_prob` 列；随后新增 `scripts/update_nyfed_recession.py` 进行真实数据解析。工作簿 Date 是12个月后预测**目标月**，解析器会回退12个月得到模型**观察期**，将0～1的小数概率转成百分比。

代码已加入工作表/列名、预测目标月、观察月和概率单位的机器校验，正式CI还需使用原始工作簿完成最终在线验收。通过后才能把模型数值写入正式数据快照。模型是**12个月后的某一个月**的衰退概率，不是未来任意12个月内累计发生衰退的概率；也不是纽约联储的官方预测。本阶段探针不发布数值。

## 数据治理

- 保存每条记录的来源、独立观测日期、频率、单位，记录首次采集而非假称官方历史首发时点。
- 无官方历史版本和独立模型回测之前，六资产0–100评分仍关闭。
- 当前公开FRED数据并不自动赋予所有商业再分发权利。公开使用前仍需按各数据源的使用条款核查。

## 在线验证记录（PR #413）

GitHub Actions 已核验 `WRESBAL` 2026-11-18 为 2,979,656 百万美元、`WTREGEN` 2026-11-18 为 916,613 百万美元、`RRPONTSYD` 2026-11-20 为 0.401 十亿美元。这些是各自不同时点的数据，不可简单相加。纽约联储工作簿共有 `rec_prob` 工作表827行7列，最新模型目标月为2027-10，值约0.124158（12.4158%）；正式解析程序仍需独立通过完整CI。
