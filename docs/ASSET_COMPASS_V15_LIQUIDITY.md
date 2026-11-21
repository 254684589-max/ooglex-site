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

纽约联储官方 `https://www.newyorkfed.org/research/capital_markets/ycfaq.html` 明确将10年减3个月利差纳入收益率曲线模型。官网也提供月度 `allmonth.xls`：`https://www.newyorkfed.org/medialibrary/media/research/capital_markets/allmonth.xls`。V15 新增**只读文件格式探针** `scripts/inspect_nyfed_recession_workbook.py`，用于查看官方工作簿的工作表名称、日期和概率列布局，以免误取12个月前的日期或转换错误。

必须通过对工作表、预测目标月、参考月和概率单位的机器校验，才能把模型数值写入正式数据快照。模型是**12个月后的某一个月**的衰退概率，不是未来任意12个月内累计发生衰退的概率；也不是纽约联储的官方预测。本阶段探针不发布数值。

## 数据治理

- 保存每条记录的来源、独立观测日期、频率、单位，记录首次采集而非假称官方历史首发时点。
- 无官方历史版本和独立模型回测之前，六资产0–100评分仍关闭。
- 当前公开FRED数据并不自动赋予所有商业再分发权利。公开使用前仍需按各数据源的使用条款核查。
