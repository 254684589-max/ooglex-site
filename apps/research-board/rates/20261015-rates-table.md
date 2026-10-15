# 宏观利率数据表汇总 — 20261015（即时首版）

- **生成时间**: 2026-10-15 18:05 CST
- **性质**: 用现有六张截图基线 + 2026-10-14 色标测试快照即时上站；**未重抓公开源**
- **截图覆盖**: shot-00…05 共 6 张（见下）
- **权威清单**: watchlist-full.json（106 项）；规则 thresholds.json
- **验收**: 全项入表；异常红标；上站页按分类折叠（默认收起）
- **不做交易建议**

## 六张截图

| 文件 | 说明 |
|---|---|
| shot-00-earlier-symbols.png | 较早符号页（对照） |
| shot-01-corridor-liquidity.png | 走廊 + 流动性 |
| shot-02-realrates-credit.png | 实际利率 / 信用等 |
| shot-03-credit-vol.png | 信用 / 波动 |
| shot-04-term-sofr-breadth.png | 期限 / SOFR / 宽度 |
| shot-05-breadth-china.png | 宽度 / 中国等 |

## 色标说明

- 🟢 正常 · 🔴 异常/需关注 · ⚪ 未取到/待核验

---

# 宏观利率动态监视清单 — 测试汇总（中文·色标）

- **生成时间**: 2026-10-14 12:11（Asia/Shanghai）
- **基准截图**: 2026-10-14 TradingView 观察列表
- **说明**: 数值复用测试快照，**未重抓**；按宏观利率监测启发式规则对「最新」「变动」同步标色。不做交易建议。

## 色标说明

- <span style="color:#16a34a;font-weight:600">绿色（正常）</span>：处于该指标常见合理区间，或相对截图基准变动不显著且水平不极端
- <span style="color:#dc2626;font-weight:600">红色（异常/需关注）</span>：水平明显偏离常态，或相对基准变动过大，或结构性紧张信号
- <span style="color:#6b7280;font-weight:600">灰色</span>：未取到/待核验，不标绿红

**主要规则摘要（详见 `thresholds.json`）**：
- 利率走廊：EFFR/SOFR/TGCR 落在目标区间附近，且 SOFR−IORB 未持续明显为正 → 绿
- ON RRP 余额极低（百万级 vs 既往数千亿–数万亿）→ 红
- 信用 OAS：HY ≳6、CCC ≳12 视为偏宽尾部 → 红
- VIX ≲20 且 VIX/VIX3M≤1 → 绿；VIX≥25 或期限倒挂 → 红
- TED 很低 → 绿；显著抬升 → 红；NFCI/STLFSI 负值偏松 → 绿
- GSCPI 显著为正、实际利率/按揭/10Y 过高、相对基准变动过大 → 红
- 「最新」与「变动」列同步着色；≈0 且水平正常 → 绿

## 今日标红关注

- **隔夜逆回购余额（国债，RRPONTSYD）**: 最新 275 M，变动 ≈0 — ON RRP余额极低（275M，远低于既往数千亿–数万亿常态）
- **5年TIPS实际利率 (DFII5)**: 最新 2.68，变动 ≈0 — 实际利率过高=紧
- **10年TIPS实际利率 (DFII10)**: 最新 2.91，变动 ≈0 — 水平高于关注阈值2.5
- **30年TIPS实际利率 (DFII30)**: 最新 3.32，变动 ≈0 — 水平高于关注阈值2.8
- **名义10年期国债−10年盈亏平衡通胀**: 最新 2.910，变动 +0.034 (+1.18%) — 水平高于关注阈值2.5
- **全球供应链压力指数 (GSCPI)**: 最新 1.28，变动 ≈0 — 显著为正=供应链压力
- **美高收益CCC及以下期权调整利差 (OAS)**: 最新 12.53，变动 ≈0 — CCC偏宽尾部
- **美国30年期按揭利率**: 最新 7.4，变动 ≈0 — ＞7%偏高压制购房
- **10年期国债常久期收益率 (DGS10)**: 最新 5.24，变动 ≈0 — ＞5%相对长期偏高
- **CBOE偏度指数 (SKEW)**: 最新 154.74，变动 ≈0 — 偏高=尾部对冲需求
- **铜/金比（期货连续）**: 最新 0.0016，变动 +0.0001171 (+7.81%) — 相对截图基准变动过大（+7.81%）
- **铜/金比（现货金类）**: 最新 0.0016，变动 +0.0001171 (+7.81%) — 相对截图基准变动过大（+7.81%）

**本页统计**: 绿 75 · 红 12 · 灰（未取到）18

## 一、美联储利率走廊（基石）

| 指标 | 基准(截图) | 最新 | 变动 | 数据源 |
|---|---|---|---|---|
| 贴现窗口一级信贷利率 (DPCREDIT) | 4 | <span style="color:#16a34a;font-weight:600">4</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · DPCREDIT |
| 常备回购便利最低投标利率 (SRF) | 4 | <span style="color:#16a34a;font-weight:600">4</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · SRFTSYD |
| 联邦基金目标区间上沿 (DFEDTARU) | 4 | <span style="color:#16a34a;font-weight:600">4</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · DFEDTARU |
| 美国政策利率 (USINTR) | 4 | <span style="color:#16a34a;font-weight:600">4</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · DFEDTARU（政策上沿代理） |
| 联邦基金有效利率 (EFFR/DFF) | 3.88 | <span style="color:#16a34a;font-weight:600">3.88</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · DFF |
| 联邦基金目标区间下沿 (DFEDTARL) | 3.75 | <span style="color:#16a34a;font-weight:600">3.75</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · DFEDTARL |
| 有担保隔夜融资利率 (SOFR) | 3.87 | <span style="color:#16a34a;font-weight:600">3.87</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · SOFR |
| 准备金余额利率 (IORB) | 3.9 | <span style="color:#16a34a;font-weight:600">3.9</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · IORB |
| 隔夜逆回购中标利率 (ON RRP) | 3.75 | <span style="color:#16a34a;font-weight:600">3.75</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · RRPONTSYAWARD |
| 三方通用抵押品利率 (TGCR) | 3.85 | <span style="color:#16a34a;font-weight:600">3.85</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · TGCRRATE |

## 二、美联储流动性（核心驱动层）

| 指标 | 基准(截图) | 最新 | 变动 | 数据源 |
|---|---|---|---|---|
| 净值流动性 WALCL−(TGA+ON RRP) | 5.87 T | <span style="color:#16a34a;font-weight:600">5.87 T</span> | <span style="color:#16a34a;font-weight:600">-0.002968 (-0.05%)</span> | 美联储FRED · WALCL−(TGA+ON RRP) |
| 准备金余额（周均，WRESBAL） | 3.03 T | <span style="color:#16a34a;font-weight:600">3.03 T</span> | <span style="color:#16a34a;font-weight:600">-0.000341 (-0.01%)</span> | 美联储FRED · WRESBAL |
| 财政部一般账户余额 / TGA (WDTGAL) | 885.78 B | <span style="color:#16a34a;font-weight:600">885.78 B</span> | <span style="color:#16a34a;font-weight:600">+0.003 (+0.00%)</span> | 美联储FRED · WDTGAL |
| 隔夜逆回购余额（国债，RRPONTSYD） | 275 M | <span style="color:#dc2626;font-weight:600">275 M</span> | <span style="color:#dc2626;font-weight:600">≈0</span> | 美联储FRED · RRPONTSYD |
| 美联储资产端回购余额 (WORAL) | 2 M | <span style="color:#16a34a;font-weight:600">2 M</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · WORAL |
| 隔夜正回购总购买量 (RPONTTLD) | 0 | <span style="color:#16a34a;font-weight:600">0</span> | <span style="color:#16a34a;font-weight:600">0</span> | 美联储FRED · RPONTTLD |
| SOFR−联邦基金有效利率利差 | -0.01 | <span style="color:#16a34a;font-weight:600">-0.01</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · 合成 |
| SOFR−准备金余额利率利差 | -0.03 | <span style="color:#16a34a;font-weight:600">-0.03</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · 合成 |
| 联邦基金有效利率−IORB 利差 | -0.02 | <span style="color:#16a34a;font-weight:600">-0.02</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · 合成 |
| IORB−联邦基金有效利率利差 | 0.02 | <span style="color:#16a34a;font-weight:600">0.02</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · 合成 |
| SOFR期货自定义曲线斜率（近端−远端） | -33.41 | <span style="color:#6b7280;font-weight:600">未取到/待核验</span> | <span style="color:#6b7280;font-weight:600">—</span> | CME |

## 三、实际利率与通胀预期

| 指标 | 基准(截图) | 最新 | 变动 | 数据源 |
|---|---|---|---|---|
| 5年盈亏平衡通胀率 (T5YIE) | 2.33 | <span style="color:#16a34a;font-weight:600">2.33</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · T5YIE |
| 10年盈亏平衡通胀率 (T10YIE) | 2.33 | <span style="color:#16a34a;font-weight:600">2.33</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · T10YIE |
| 5年期5年远期通胀预期 (T5YIFR) | 2.33 | <span style="color:#16a34a;font-weight:600">2.33</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · T5YIFR |
| 5年TIPS实际利率 (DFII5) | 2.68 | <span style="color:#dc2626;font-weight:600">2.68</span> | <span style="color:#dc2626;font-weight:600">≈0</span> | 美联储FRED · DFII5 |
| 10年TIPS实际利率 (DFII10) | 2.91 | <span style="color:#dc2626;font-weight:600">2.91</span> | <span style="color:#dc2626;font-weight:600">≈0</span> | 美联储FRED · DFII10 |
| 30年TIPS实际利率 (DFII30) | 3.32 | <span style="color:#dc2626;font-weight:600">3.32</span> | <span style="color:#dc2626;font-weight:600">≈0</span> | 美联储FRED · DFII30 |
| 名义10年期国债−10年盈亏平衡通胀 | 2.876 | <span style="color:#dc2626;font-weight:600">2.910</span> | <span style="color:#dc2626;font-weight:600">+0.034 (+1.18%)</span> | 美联储FRED · 合成 |
| 货币市场基金总金融资产 | 8.44 T | <span style="color:#16a34a;font-weight:600">8.44 T</span> | <span style="color:#16a34a;font-weight:600">+0.001374 (+0.02%)</span> | 美联储FRED · MMMFFAQ027S |
| 全球供应链压力指数 (GSCPI) | 1.28 | <span style="color:#dc2626;font-weight:600">1.28</span> | <span style="color:#dc2626;font-weight:600">≈0</span> | 纽约联储 · GSCPI |

## 四、金融压力/状况

| 指标 | 基准(截图) | 最新 | 变动 | 数据源 |
|---|---|---|---|---|
| 芝加哥联储全国金融状况指数 (NFCI) | -0.49 | <span style="color:#16a34a;font-weight:600">-0.49</span> | <span style="color:#16a34a;font-weight:600">-0.004 (-0.82%)</span> | 美联储FRED · NFCI |
| 圣路易斯联储金融压力指数 (STLFSI4) | -0.47 | <span style="color:#16a34a;font-weight:600">-0.47</span> | <span style="color:#16a34a;font-weight:600">+0.0019 (+0.40%)</span> | 美联储FRED · STLFSI4 |
| TED利差 | 0.09 | <span style="color:#16a34a;font-weight:600">0.09</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · TEDRATE |
| 波罗的海干散货指数 (BDI) | 2,801 | <span style="color:#16a34a;font-weight:600">2,852</span> | <span style="color:#16a34a;font-weight:600">+51 (+1.82%)</span> | Investing · 波罗的海干散货 |

## 五、信用利差（风险偏好核心）

| 指标 | 基准(截图) | 最新 | 变动 | 数据源 |
|---|---|---|---|---|
| 穆迪Baa公司债相对国债利差 (BAA10Y) | 1.45 | <span style="color:#16a34a;font-weight:600">1.45</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · BAA10Y |
| 美高收益CCC及以下期权调整利差 (OAS) | 12.53 | <span style="color:#dc2626;font-weight:600">12.53</span> | <span style="color:#dc2626;font-weight:600">≈0</span> | 美联储FRED · BAMLH0A3HYC |
| 美高收益债期权调整利差 (HY OAS) | 3.11 | <span style="color:#16a34a;font-weight:600">3.11</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · BAMLH0A0HYM2 |
| 美投资级公司债期权调整利差 (IG OAS) | 0.83 | <span style="color:#16a34a;font-weight:600">0.83</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · BAMLC0A0CM |
| 美高收益BB期权调整利差 | 1.88 | <span style="color:#16a34a;font-weight:600">1.88</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · BAMLH0A1HYBB |
| 美高收益单B期权调整利差 | 3.1 | <span style="color:#16a34a;font-weight:600">3.1</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · BAMLH0A2HYB |
| 新兴市场公司债期权调整利差 | 1.55 | <span style="color:#16a34a;font-weight:600">1.55</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · BAMLEMCBPIOAS |
| 新兴市场高收益公司债期权调整利差 | 3.3 | <span style="color:#16a34a;font-weight:600">3.3</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · BAMLEMHBHYCRPIOAS |
| 美AA公司债期权调整利差 | 0.58 | <span style="color:#16a34a;font-weight:600">0.58</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · BAMLC0A2CAA |
| BBB−AA 公司债利差（OAS差） | 0.44 | <span style="color:#16a34a;font-weight:600">0.44</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · 合成 |
| AA有效收益率−10年期国债 | 0.53 | <span style="color:#16a34a;font-weight:600">0.53</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · 合成 |
| 美投资级公司债有效收益率 | 5.96 | <span style="color:#16a34a;font-weight:600">5.96</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · BAMLC0A0CMEY |
| 美国30年期按揭利率 | 7.4 | <span style="color:#dc2626;font-weight:600">7.4</span> | <span style="color:#dc2626;font-weight:600">≈0</span> | 美联储FRED · MORTGAGE30US |
| 美AA公司债有效收益率 | 5.77 | <span style="color:#16a34a;font-weight:600">5.77</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · BAMLC0A2CAAEY |
| 高收益OAS−3年期国债（量纲慎读） | -1.78 | <span style="color:#16a34a;font-weight:600">-1.78</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | 美联储FRED · 合成 |
| 10年期国债常久期收益率 (DGS10) | 5.24 | <span style="color:#dc2626;font-weight:600">5.24</span> | <span style="color:#dc2626;font-weight:600">≈0</span> | 美联储FRED · DGS10 |
| 高收益债ETF/中期国债ETF (HYG/IEF) | 0.861 | <span style="color:#16a34a;font-weight:600">0.861</span> | <span style="color:#16a34a;font-weight:600">-0.00004 (-0.01%)</span> | Yahoo · HYG/IEF |
| 高收益公司债ETF (HYG) | 77.09 | <span style="color:#16a34a;font-weight:600">77.09</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | Yahoo · HYG |
| 投资级公司债ETF (LQD) | 102.55 | <span style="color:#16a34a;font-weight:600">102.55</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | Yahoo · LQD |

## 六、波动率全景

| 指标 | 基准(截图) | 最新 | 变动 | 数据源 |
|---|---|---|---|---|
| 恐慌指数 (VIX) | 15.28 | <span style="color:#16a34a;font-weight:600">15.27</span> | <span style="color:#16a34a;font-weight:600">-0.01 (-0.07%)</span> | Yahoo · VIX |
| VIX波动率指数 (VVIX) | 85.38 | <span style="color:#16a34a;font-weight:600">85.38</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | Yahoo · VVIX |
| CBOE偏度指数 (SKEW) | 154.74 | <span style="color:#dc2626;font-weight:600">154.74</span> | <span style="color:#dc2626;font-weight:600">≈0</span> | Yahoo · SKEW |
| 美国债券波动率指数 (MOVE) | 101.10 | <span style="color:#16a34a;font-weight:600">101.09</span> | <span style="color:#16a34a;font-weight:600">-0.0098 (-0.01%)</span> | Yahoo · MOVE |
| 超长期国债ETF (TLT) | 78.37 | <span style="color:#16a34a;font-weight:600">78.37</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | Yahoo · TLT |
| VIX期货近月合约 (VX1) | 17.52 | <span style="color:#6b7280;font-weight:600">未取到</span> | <span style="color:#6b7280;font-weight:600">—</span> | CBOE |
| VIX期货次近月合约 (VX2) | 18.05 | <span style="color:#6b7280;font-weight:600">未取到</span> | <span style="color:#6b7280;font-weight:600">—</span> | CBOE |
| VIX近月/次近月期货比 (VX1/VX2) | 0.97 | <span style="color:#6b7280;font-weight:600">未取到</span> | <span style="color:#6b7280;font-weight:600">—</span> | CBOE |
| 标普500九日波动率指数 (VIX9D) | 11.99 | <span style="color:#16a34a;font-weight:600">11.99</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | Yahoo · VIX9D |
| 标普500三月波动率指数 (VIX3M) | 17.96 | <span style="color:#16a34a;font-weight:600">17.96</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | Yahoo · VIX3M |
| 标普500六月波动率指数 (VIX6M) | 19.92 | <span style="color:#16a34a;font-weight:600">19.92</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | Yahoo · VIX6M |
| 标普500一年波动率指数 (VIX1Y) | 21.66 | <span style="color:#16a34a;font-weight:600">21.66</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | Yahoo · VIX1Y |
| VIX/三月VIX（期限结构） | 0.85 | <span style="color:#16a34a;font-weight:600">0.85</span> | <span style="color:#16a34a;font-weight:600">+0.0002227 (+0.03%)</span> | Yahoo · VIX/VIX3M |
| 九日VIX/VIX（超短期相对） | 0.79 | <span style="color:#16a34a;font-weight:600">0.79</span> | <span style="color:#16a34a;font-weight:600">-0.0048 (-0.61%)</span> | Yahoo · VIX9D/VIX |

## 七、期限结构与利差

| 指标 | 基准(截图) | 最新 | 变动 | 数据源 |
|---|---|---|---|---|
| 美债10年−2年期限利差 | 0.424 | <span style="color:#16a34a;font-weight:600">0.420</span> | <span style="color:#16a34a;font-weight:600">-0.004 (-0.94%)</span> | 美联储FRED · T10Y2Y |
| 10年零息国债期限溢价 | 1.07 | <span style="color:#16a34a;font-weight:600">1.07</span> | <span style="color:#16a34a;font-weight:600">+0.0029 (+0.27%)</span> | 美联储FRED · THREEFYTP10 |
| 2年零息国债期限溢价 | 0.52 | <span style="color:#16a34a;font-weight:600">0.52</span> | <span style="color:#16a34a;font-weight:600">+0.0024 (+0.46%)</span> | 美联储FRED · THREEFYTP2 |
| 10年−2年期限溢价差 | 0.55 | <span style="color:#16a34a;font-weight:600">0.55</span> | <span style="color:#16a34a;font-weight:600">+0.0005 (+0.09%)</span> | 美联储FRED · 合成 |
| 名义10年国债−10年期限溢价 | 4.136 | <span style="color:#16a34a;font-weight:600">4.167</span> | <span style="color:#16a34a;font-weight:600">+0.0311 (+0.75%)</span> | 美联储FRED · 合成 |
| 曲线斜率（剔除期限溢价） | -0.127 | <span style="color:#16a34a;font-weight:600">-0.131</span> | <span style="color:#16a34a;font-weight:600">-0.0035 (-2.76%)</span> | 美联储FRED · 合成 |

## 八、跨国利差

| 指标 | 基准(截图) | 最新 | 变动 | 数据源 |
|---|---|---|---|---|
| 美−德10年期国债利差 | 1.746 | <span style="color:#16a34a;font-weight:600">1.756</span> | <span style="color:#16a34a;font-weight:600">+0.0102 (+0.58%)</span> | Yahoo^TNX − Investing 德债10年 |
| 美−日10年期国债利差 | 2.201 | <span style="color:#16a34a;font-weight:600">2.216</span> | <span style="color:#16a34a;font-weight:600">+0.015 (+0.68%)</span> | Yahoo^TNX − Investing 日债10年 |
| 美−英10年期国债利差 | -0.245 | <span style="color:#16a34a;font-weight:600">-0.236</span> | <span style="color:#16a34a;font-weight:600">+0.0094 (+3.84%)</span> | Yahoo^TNX − Investing 英债10年 |
| 美−德2年期国债利差 | 1.676 | <span style="color:#16a34a;font-weight:600">1.665</span> | <span style="color:#16a34a;font-weight:600">-0.011 (-0.66%)</span> | Investing · 美2年−德2年 |
| 欧元兑美元+美元指数（自定义） | 103.21 | <span style="color:#16a34a;font-weight:600">103.22710</span> | <span style="color:#16a34a;font-weight:600">+0.02005 (+0.02%)</span> | Yahoo · EURUSD+DXY |

## 九、SOFR 期货（短端利率）

| 指标 | 基准(截图) | 最新 | 变动 | 数据源 |
|---|---|---|---|---|
| 三月期SOFR期货（2026年6月） | 96.35 | <span style="color:#6b7280;font-weight:600">未取到</span> | <span style="color:#6b7280;font-weight:600">—</span> | CME |
| 三月期SOFR期货（2026年9月） | 96.05 | <span style="color:#16a34a;font-weight:600">96.0525</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | Yahoo · SOFR期货 Sep-2026 |
| 三月期SOFR期货（2026年12月） | 95.75 | <span style="color:#16a34a;font-weight:600">95.7450</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | Yahoo · SOFR期货 Dec-2026 |
| SOFR期货2026年12月−2027年12月价差 | 0.49 | <span style="color:#16a34a;font-weight:600">0.490</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | Yahoo · SOFR期货 Dec-2026−Dec-2027 |

## 十一、市场宽度

| 指标 | 基准(截图) | 最新 | 变动 | 数据源 |
|---|---|---|---|---|
| 标普500站上200日均线比例 | 49.7 | <span style="color:#6b7280;font-weight:600">未取到</span> | <span style="color:#6b7280;font-weight:600">—</span> | TradingView |
| 标普500站上50日均线比例 | 38.17 | <span style="color:#6b7280;font-weight:600">未取到</span> | <span style="color:#6b7280;font-weight:600">—</span> | TradingView |
| 全市场站上200日均线比例 | 42.98 | <span style="color:#6b7280;font-weight:600">未取到/待核验</span> | <span style="color:#6b7280;font-weight:600">—</span> | TradingView |
| 全市场站上50日均线比例 | 29.17 | <span style="color:#6b7280;font-weight:600">未取到/待核验</span> | <span style="color:#6b7280;font-weight:600">—</span> | TradingView |
| 纳斯达克100站上200日均线比例 | 64.35 | <span style="color:#6b7280;font-weight:600">未取到/待核验</span> | <span style="color:#6b7280;font-weight:600">—</span> | TradingView |
| 纽交所52周新高家数 | 50 | <span style="color:#6b7280;font-weight:600">未取到/待核验</span> | <span style="color:#6b7280;font-weight:600">—</span> | TradingView |
| 纽交所52周新低家数 | 88 | <span style="color:#6b7280;font-weight:600">未取到/待核验</span> | <span style="color:#6b7280;font-weight:600">—</span> | TradingView |

## 十二、市场内部结构（情绪/资金流）

| 指标 | 基准(截图) | 最新 | 变动 | 数据源 |
|---|---|---|---|---|
| 美股涨跌家数差 | -526 | <span style="color:#6b7280;font-weight:600">未取到</span> | <span style="color:#6b7280;font-weight:600">—</span> | TradingView |
| 纽交所上涨成交量 | 572,903,905 | <span style="color:#6b7280;font-weight:600">未取到</span> | <span style="color:#6b7280;font-weight:600">—</span> | TradingView |
| 纽交所下跌成交量 | 594,785,018 | <span style="color:#6b7280;font-weight:600">未取到</span> | <span style="color:#6b7280;font-weight:600">—</span> | TradingView |
| 纽交所累计Tick | -179 | <span style="color:#6b7280;font-weight:600">未取到</span> | <span style="color:#6b7280;font-weight:600">—</span> | TradingView |
| 纽交所Arms指数 (TRIN) | 1.34 | <span style="color:#6b7280;font-weight:600">未取到</span> | <span style="color:#6b7280;font-weight:600">—</span> | TradingView |

## 十三、商品比率（经济周期/避险）

| 指标 | 基准(截图) | 最新 | 变动 | 数据源 |
|---|---|---|---|---|
| 铜/金比（期货连续） | 0.0015 | <span style="color:#dc2626;font-weight:600">0.0016</span> | <span style="color:#dc2626;font-weight:600">+0.0001171 (+7.81%)</span> | Yahoo · 铜/金期货 |
| 金/银比（期货连续） | 70.5 | <span style="color:#16a34a;font-weight:600">70.409</span> | <span style="color:#16a34a;font-weight:600">-0.09132 (-0.13%)</span> | Yahoo · 金/银期货 |
| 原油/铜比（期货连续） | 14.01 | <span style="color:#16a34a;font-weight:600">13.99</span> | <span style="color:#16a34a;font-weight:600">-0.01739 (-0.12%)</span> | Yahoo · 原油/铜期货 |
| 铜×100/金比 | 0.1615 | <span style="color:#16a34a;font-weight:600">0.1617</span> | <span style="color:#16a34a;font-weight:600">+0.0002103 (+0.13%)</span> | Yahoo · 铜×100/金 |
| 铜/金比（现货金类） | 0.0015 | <span style="color:#dc2626;font-weight:600">0.0016</span> | <span style="color:#dc2626;font-weight:600">+0.0001171 (+7.81%)</span> | Yahoo · 铜/金期货 |
| WTI原油/金比 | 0.02 | <span style="color:#16a34a;font-weight:600">0.0226</span> | <span style="color:#16a34a;font-weight:600">+0.002627 (+13.14%)</span> | Yahoo · 原油/金期货 |
| 金/银比 | 70.32 | <span style="color:#16a34a;font-weight:600">70.409</span> | <span style="color:#16a34a;font-weight:600">+0.08468 (+0.12%)</span> | Yahoo · 金/银期货 |

## 十四、中国相关

| 指标 | 基准(截图) | 最新 | 变动 | 数据源 |
|---|---|---|---|---|
| 中国人民银行资产负债表总资产 | 49.86 T | <span style="color:#16a34a;font-weight:600">49.86 T</span> | <span style="color:#16a34a;font-weight:600">-0.003 (-0.01%)</span> | fxmacrodata · 央行资产 |
| 离岸−在岸人民币点差 (USDCNH−USDCNY) | 0.0009⁴ | <span style="color:#16a34a;font-weight:600">0.00090</span> | <span style="color:#16a34a;font-weight:600">-0.00004 (-4.26%)</span> | Yahoo · 离岸−在岸人民币 |
| 中国政策/基准利率 | 3 | <span style="color:#6b7280;font-weight:600">未取到/待核验</span> | <span style="color:#6b7280;font-weight:600">—</span> | TradingView |
| 中国10年期国债收益率 | 1.65 | <span style="color:#16a34a;font-weight:600">1.650</span> | <span style="color:#16a34a;font-weight:600">≈0</span> | Investing · 中国10年国债 |

## 十、（截图中缺号）

> 截图中缺号分类，无条目。

## 抓取统计

- **成功**: 87
- **失败/未取到**: 18
- **合计（去重后）**: 105
- **色标**: 绿 75 / 红 12 / 灰 18

### 低置信未核验项

- SOFR期货自定义曲线斜率（近端−远端）
- 全市场站上200日均线比例
- 全市场站上50日均线比例
- 纳斯达克100站上200日均线比例
- 纽交所52周新高家数
- 纽交所52周新低家数
- 中国政策/基准利率

---
*测试汇总 · 色标为监测启发式 · 仅供版面验收 · 非投资建议*
