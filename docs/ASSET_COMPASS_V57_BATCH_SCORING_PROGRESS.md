# Ooglex V57｜一次完成多项关键工程：黄金/长债专属数据、评分门禁、部署冲突治理

## 核心目标：让六资产0–100模型有更多真实输入，而不是虚构评分

截至V56（2026-11-23）：
- 6个宏观因子组均有部分真实来源观察，但独立可评分因子组=0，6个资产的正式评分全部null；
- 只有原油有EIA商业库存资产专属数据；
- 不具备一手发布时点、有效资产总回报、多制度样本外校准；
- GitHub default Pages "pages build and deployment" 与自定义 "Deploy Protected Ooglex Pages" 偶发争用同一 Pages 部署，造成400 Conflict。

## 本次集中交付的模块

### 1. CFTC黄金持仓，真正官方来源
`scripts/build_asset_compass_asset_specific_v57.py` 从官方 Socrata 数据集 `72hh-3qpy`（Disaggregated Futures Only）筛选**COMEX GOLD、CFTC市场代码088691**，保留真实周二持仓日、Managed Money多头/空头合约、未平仓量与净持仓占OI百分比。历史104周参考分布计算描述性Z和tanh研究标量，**不推断其与未来金价的单调关系**。周二仓位不等于通常周五公布时点；CFTC个别假日会用周一仓位（真实官方样本2020-12-21、2023-07-03、2025-11-10），保留原始观测日期，不更改成周二。
官方CFTC报告：https://www.cftc.gov/MarketReports/CommitmentsofTraders/index.htm
官方原始数据：https://publicreporting.cftc.gov/Commitments-of-Traders/Disaggregated-Futures-Only/72hh-3qpy

### 2. Treasury长期国债拍卖数据，真正官方来源
从美国财政部 FiscalData 历史 `auctions_query` 与最新 `treasury_securities_auctions_v2` **合并并按（拍卖日、CUSIP）去重**，筛选30-Year Bond及29-Year剩余期限重开标的已完成拍卖，不使用未来公告、不填零。读取 `auction_date`、`cusip`、`security_term`、`bid_to_cover_ratio`，过去36场真实拍卖独立参考分布生成Z和tanh描述性指标。30年拍卖投标倍数只反映该场拍卖的需求覆盖，不代表债券可投资总收益、利率价格、发行人信用或ETF资金流；历史首次发布时间仍未核证。
官方原始数据：https://fiscaldata.treasury.gov/datasets/treasury-securities-auctions-data/

### 3. 量化模型资产覆盖审计
黄金(CFTC)、长期国债(30Y国债拍卖)、原油(EIA库存)各有真实专属观察，研究来源由1/6推进至3/6（成功抓取、持久化后才认定）。美股、美元和比特币仍缺对应专属观察。所有单位、时间及来源分别标记。**原始资料覆盖不等于经过独立PIT、方向校准、样本外评测的合格模型信号。**
正式分数保持 `score:null`，不再以零或中性分数替代缺失。

### 4. 从现在开始积累真实first-seen证据而非回填伪PIT

`scripts/archive_asset_compass_v57_first_seen.py` 会在每次真实采集后生成/追加 **SHA-256哈希链JSONL**，单独保存CFTC持仓或Treasury竞拍的来源原文哈希、观测日期、原值和Ooglex服务器首次看到该数据的UTC时间。若新快照/官方修订改变可保留多个版本，旧日志不得改变，重复采集同一值和响应哈希不会追加。验证包含篡改旧值、伪造批准、时间倒流和重复写入的回归测试。

**Ooglex首次采集时间不是官方首次公开发布时间**，历史2020-2026的回填数据仍不算PIT，任何数据不得自认证可用于交易/正式评分。

### 5. 真实因子重叠描述性审查

`scripts/audit_asset_compass_cross_source_v57.py` 对从同一主分支来源拿到的CFTC黄金持仓、芝加哥联储NFCI与财政部真实利率数据按市场观测日期做**事后同期对齐**，产生4个Pearson相关系数（黄金持仓/实际利率、NFCI/10年名义收益率、NFCI/实际收益率、NFCI/期限利差），标注样本量和重叠口径。它不能证明未来预测力、因果关系或独立性。尤其CFTC周二报告通常周五才公开，严禁把报告仓位日期当作周二即可交易的信息。全部真实研究结果自动保存到 `data/asset-compass-overlap-audit-v57.json`，无模型得分。

### 6. GitHub Pages 部署并发冲突处理
自定义部署中，添加 `actions:read` 与在调用 `actions/deploy-pages@v4` **之前** 查询本仓库自动 `pages build and deployment` 是否处于 queued/in_progress/waiting/pending；有竞争则等待，超时安全退出而不发起冲突部署。也保留源SHA V11/V12严格验收。此方法缓解冲突，未直接修改 GitHub Pages 设置。彻底根治需要仓库 Pages 设置选择唯一主发布源；不可在没有权限时声称已完成。

### 7. 保持全站安全回归
网站总览新增黄金、长期国债、原油三条资产专属观察，明确显示美股、美元、比特币仍缺；每种观察需具备独立来源、实际日期、历史基准、SHA和未验证状态。发现伪造分数、未知来源、PIT自认证或V56原油数据不一致则整块拒绝展示。网页与API缺源时显示不可用，不制造临时数字。

## 尚未完成，不因本次数据抓取而自动通过

- 美股、美元、比特币资产专属来源及其授权/数据质量；
- ICE高收益债OAS正式商业再发行许可；NFCI综合风险指标与利率、流动性重复计数消除；
- 真实历史**首次可得版本**、严格as-of时点、资产**总回报**而非收盘价；
- 稳健多周期独立样本外验证、风险权重校准与投资策略可用性证明；
- 六资产0–100正式分数全部继续锁定。

## 下一步动作
`python3 -m unittest discover -s tests -p 'test_asset_compass_asset_specific_v57.py' -v`；`node tests/smoke_asset_compass_asset_specific_v57.cjs`；
`python3 -m scripts.build_asset_compass_asset_specific_v57 --fetch`；GitHub PR研究门禁必须真实下载两条官方数据且严禁虚构结果，随后合并main，核验自动持久化数据、最新网站部署及准确的访问源SHA。
