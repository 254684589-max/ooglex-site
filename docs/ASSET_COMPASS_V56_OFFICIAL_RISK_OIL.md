# 全球资产罗盘 V56｜两条真实官方数据：NFCI 金融条件 + EIA 商业原油库存

## 与 0–100 资产评分的关系

V55 已实算财政部5条利率变化与两个尚未校准的资产压力假设；V54 的**原始日频快照**中仅有四个因子组的观测（利率、通胀、增长、流动性）。V56 直接补齐另外两个因子组的**部分原始观测来源**，但不发布正式模型分数。

| 新来源 | 因子组 | 具体意义 | 时间口径 | 数值单位 |
|---|---|---|---|---|
| 芝加哥联储 NFCI，FRED 镜像 | 风险与信用 | 含货币/债券/股市/银行、风险、信用及杠杆信息的综合金融条件指数 | 每周，截至上周五 | 指数 |
| 美国 EIA WCESTUS1 | 资产专属 | 美国商业原油库存，不含战略石油储备 SPR | 每周，截至上周五 | 千桶 |

**不是**高收益债 OAS：ICE BofA HY OAS 的数据归属 ICE Data Indices，不能因为网页可见就推断具有在商业站点公开转存的许可。本阶段不收集、不导出 ICE 历史值。NFCI本身与利率、信用、流动性重叠，需将独立性标记为未核证；不是另一个可直接加进模型的独立投票。

**不是六资产专属指标全部接入**：EIA 原油库存只对 oil 对应的 `asset_specific` 组提供了一个基本面观察。黄金、美股、长期国债、美元、比特币五个资产尚缺各自的资产专属数据。

## 真正的数据捕获与研究计算

`scripts/build_asset_compass_new_sources_v56.py` 只从2条固定的 HTTPS 官方/官方镜像来源获取数据：

- 芝加哥联储 `NFCI`（FRED CSV）：`https://fred.stlouisfed.org/graph/fredgraph.csv?id=NFCI&cosd=2019-01-01`。
- 美国 EIA 商业原油库存 `WCESTUS1`：`https://www.eia.gov/dnav/pet/hist/LeafHandler.ashx?f=W&n=PET&s=WCESTUS1`。

读取源文本、解析真实日期和数值，拒绝错误列、来源标题、周五以外日期、重复记录、异常库存值、无效数字、未来日期及错域跳转。保留原始响应字节SHA-256（不把原网页作为站点素材转存）。观测只选最近156周公开在报告中。至少年历史110+周真实数据才允许进入研究计算。

NFCI 已是复合标准化金融条件指数；在 104 周历史基准（排除当前一周）上计算当前指数对过去分布的**描述性Z值**。正值代表比平均更紧，负值相反；不能当作历史未来股价、比特币涨跌概率。

EIA 库存计算最新周库存、周变化及4周库存变化（百万桶），在过去104个4周库存变化上生成描述性标准化Z值。四周变化与历史基准有**季节性与重叠窗口**，未经季调/样本外验证时绝不转换为预测信号。

两系列均以周五为**观察日，不是周三官方发布时间**；历史缓存可能包含事后修订，不能冒充 PIT 历史交易数据。报告显式固定：`source_vintages_qualified:0`、`independent_scoring_factor_groups_qualified:0`、`approved_asset_scores:0`，六资产 `score:null`。

**数据版权与归属**：NFCI 官方来源联邦储备银行芝加哥分行，经圣路易斯联储 FRED 获取（系列标注 Copyrighted: Citation Required），引用须同时标注 Chicago Fed 和 FRED；EIA 来源为美国能源信息署。使用仅限准确呈现、附来源的宏观观测，不推断拥有其他第三方系列（尤其ICE）的商业再发行授权。正式商用/重新分发的完整条款仍需持续遵循官方说明。

## 已改动范围

- `scripts/build_asset_compass_new_sources_v56.py`：标准库采集、两类不同单位和口径的周频实证数据、历史Z研究计算、来源及权益标签、六资产fail-closed。
- `tests/test_asset_compass_new_sources_v56.py`：24项严格离线检查；额外CI真实联网抓取不是合成样本。
- `tests/smoke_asset_compass_new_sources_v56.cjs`：官网实际JS行为测试，验证来源、数值、时效、PIT证明和伪造分数被拒。
- `macro/overview.html` + `macro/compass-pages.js`：在六资产总览增加有源的 NFCI 和 EIA 数据解释；其他资产不暗示含专属数据。
- `.github/workflows/asset-compass-new-sources-v56.yml`：新增周四 UTC 16:20 的真实官方数据工作流及 `main` 自动触发，经过单元测试→实际抓取→验证后，持久化到 `data/asset-compass-new-sources-v56.json` 并远端比对；30天派生报告备份，不存储原始受权利约束的整页内容。
- `.github/workflows/asset-compass-research-gates.yml`：既有V18–V56门禁和PR真实联网核验。
- `.github/workflows/deploy_protected_pages.yml`：网站缺报告时保持“未接入”提示；若报告已存在则构建验证真实性边界和零个正式评分。

## 验收标准

1. 两条官方源均**实际**抓到周频原始数值、来源SHA、最新观测日；不存在模拟替代。
2. 必须通过源标题/序列ID、周频时间、库存单位和异常值验证；第三方/ICE源权限不得假定。
3. V54（原始快照）和V56合并统计的六因子组**均存在至少一个源观察入口**；但是合格模型信号仍为 **0/6**。
4. 原油专属观察 `oil` 唯一匹配，另外五资产专属覆盖状态不变；六资产正式0–100分保持`null`。
5. PR测试、官网构建、main持久化及生产域名验收必须分别陈述实际状态。

## 最短验证命令

```bash
python3 -m unittest discover -s tests -p 'test_asset_compass_new_sources_v56.py' -v
node tests/smoke_asset_compass_new_sources_v56.cjs
python3 -m scripts.build_asset_compass_new_sources_v56 --fetch
```

## V57应做的工作

收集五个尚无资产专属源的真实序列（CFTC COT、国债拍卖、SEC财报等），每个源分开核验单位、发布时刻与版权限制。同时基于可投资资产总回报、仅使用历史当时可见数据建立滚动样本外回测，逐资产验证方向及权重。**不能把“有原始数据”偷换成“已取得独立风险因子或0–100可交易评分”。**
