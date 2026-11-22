# Ooglex 全球资产罗盘｜V18 SOFR 互换历史数据替代源选型（2026-11-23）

## 目标
为 `macro/swap-spreads.html` 建立真实、合法、可以持续维护的2/3/5/7/10/30Y SOFR **互换固定利率**历史曲线，而非用隔夜SOFR、复利均值或2016年以前LIBOR互换报价冒充。

## 初步核实与优先级

| 数据源 | 可证实的范围/定义 | 期限匹配 | 再发布状态 | 结论 |
|---|---|---|---|---|
| BlueGamma Swap Curves/Interest Rate API | 官网说明支持USD SOFR par swap曲线，历史从2023年3月起，支持指定历史日查询；具体每一到期点、报价重建方式需协议确认 | 初步相关，六个期限需API实测 | 合同约定API及再发布权利，**尚无Ooglex授权** | **优先咨询**，不能直接入库 |
| CheckMySwap | 已验证2026-03-19起指示性USD SOFR OIS档案，按日期API；V15样本10日中9候选，1历史冲突 | 已通过六期限技术筛选 | **第三方再发布许可未确认** | 现有研究源，保留并限制历史回填 |
| DTCC / CFTC Part 43公开互换交易记录 | 法规要求交换数据仓库公开部分交易记录，含成交条款；自行建立固定对SOFR交易筛选与稳健汇总需新方法学 | 没有开箱即用六期限par曲线 | DTCC官网一般使用条款对复制、数据库和商业衍生用途有明确限制，需专项审查；公开监管数据≠无限转载许可 | **中期独立重建备选**，不得把成交直接当par报价 |
| NY Fed SOFR、SOFR 30/90/180天均值、SOFR Index | 纽约联储公布隔夜担保融资基准及历史复利指数；这些是回顾过去利率，不是2–30Y固定端OIS par rate | **不匹配** | 需遵守纽约联储使用条款 | 可作为独立宏观因子，**禁止替代**互换利率 |
| FRED旧H.15 SWP系列 | 2016年10月末已停止的传统利率互换报价，并非现代SOFR互换par曲线 | **不匹配** | FRED API本身不替代底层第三方数据权利 | 不可拼接现代SOFR历史 |

## 查证官方链接（开放可访问，不意味着可以批量转发）
- [BlueGamma Interest Rate API](https://www.bluegamma.io/interest-rate-api)
- [BlueGamma swap rate catalogue](https://www.bluegamma.io/swap-rates)
- [BlueGamma methodology](https://www.bluegamma.io/methodology)
- [BlueGamma API historical endpoint documentation](https://www.bluegamma.io/documentation/integrations/api/api-reference)
- [CheckMySwap historical OIS archive](https://www.checkmyswap.com/rates)
- [CheckMySwap methodology](https://www.checkmyswap.com/methodology)
- [New York Fed SOFR averages and index](https://www.newyorkfed.org/markets/reference-rates/sofr-averages-and-index)
- [Fed H.15 legacy swaps discontinuation](https://www.federalreserve.gov/feeds/h15.html)
- [FRED API terms](https://fred.stlouisfed.org/docs/api/terms_of_use.html)
- [DTCC terms](https://www.dtcc.com/terms)
- [CFTC swap data repositories](https://www.cftc.gov/IndustryOversight/DataRepositories/index.htm)

## 技术与合规选型判断
优先让BlueGamma提供**正式报价/条款与具体样本**：
1. 2023年3月以来每日USD-SOFR par swap，覆盖2/3/5/7/10/30年六期限？ 不是只提供指定的10Y/30Y曲线吗？
2. 能否查询point-in-time原始快照而非事后重新bootstrap的同日曲线，如何取得版本/修订时间？
3. 是否支持一次取全曲线以及批量日期，并提供API调用限额、计费、SLA及导出限制？
4. 是否准许 Ooglex 持续留存报价、公开显示六期限数据及衍生 `swap - Treasury CMT` 利差、前端历史走势图、公开API或下载，且可以在网站商业化场景使用？明确归属/署名条款。
5. 是否有试用沙箱或价格透明的小项目授权；如果许可过贵，优先展示外链、另开自有模型研究线，不偷换指标。

## 不能偷换的金融定义
- SOFR年化隔夜融资率 \(r_t\) 不能代替5Y或10Y固定端 **par swap** 利率 \(S_{5Y,t}\) / \(S_{10Y,t}\)。
- SOFR 30/90/180-day `backward looking compounded averages`不是固定端OIS报价。
- 2016年停更的 `LIBOR swap` 与2026年现代 `SOFR OIS` 有不同的浮动参考率、约定和基差，**不得直接拼接**。
- DTCC交易记录里的票息可能是单笔协商条款；要建立par曲线，需要排除远期起始/非标准期限/不同浮动基准，并明确固定腿支付频率、日计数与贴现/清算规则。成交票息不能自动等同于par互换率。
- 即使以后更换为许可数据，原2026-11-20历史快照也不允许静默重写；应开新的有版本的提供者序列，清楚声明方法变化与不可连续比较的区间。

## 发布门禁与实操下一步
- V18只完成供应商可行性与权利差异研究，**不复制任何第三方历史数值**，不修改历史 JSON。
- 取得BlueGamma回复及样本数据许可后，单独建 `provider=bluegamma` 隔离数据契约与日期覆盖报告，验证六期限、CMT时间、par convention。样本不足或版权不明则拒绝写入。
- 持续保留 `docs/data-rights/sofr-historical-publication.json` 的`blocked`状态；原CheckMySwap数据与新供应商数据应分开存储并用明显来源标签展示。
- 2026-11-24自动日更监测仍独立执行；它不会替代过去的历史积累。

## 供BlueGamma的英文许可与试用咨询
**Subject: Ooglex — Historical USD SOFR Par Swap Curve License / Small Website API Inquiry**

Hello BlueGamma team,

I run Ooglex, a public macro-financial research website. We are exploring a historical USD SOFR par swap curve feed to display 2Y, 3Y, 5Y, 7Y, 10Y and 30Y rates alongside matching-date official U.S. Treasury CMT yields, including derived swap-spread history charts.

Could you confirm: (1) which tenors and daily history dates are available since March 2023, (2) whether rates are point-in-time original quotes or subsequently reconstructed curves, with available revision/version metadata, (3) API access limits and monthly costs for a small project, and (4) whether a license can expressly include long-term storage, public web charting, derived spreads, commercial/advertising display, and optional public downloads?

We would appreciate a sample under evaluation terms and a suitable small-project licensing proposal. We will not publish or redistribute the data until permitted by the contract.

Thank you,
Ooglex Financial Research Project

**Status:** research only, no contract obtained, no outward request sent.
