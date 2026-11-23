# Ooglex 全球资产罗盘 V59｜补充美股及比特币原始研究来源（不开放评分）

## V59 范围

延续 V58 的正式资产分数均为 null 的评分锁，不重建模型，不增加模拟序列。V59 解决 Issue #478 中两种缺失专属研究观察源的采集器与证据门禁。

**美股研究源：** 美联储 Z.1 的 All Sectors; Corporate Equities; Asset, Market Value Levels（F51.1.s；系列 BOGZ1LM893064105Q，源代码 LM893064105）。季度、百万美元，FRED 官方发布镜像 CSV，保留真实原始字节 SHA256、实际季度观测记录。这是各部门公司股权市值存量，**包含非上市权益，不是标普500或美国上市股票指数，也不是股息再投资总回报**。存量变化包含估值、发行、部门构成和历史修订。

**BTC研究源：** Bitcoin mainnet 实际区块高度/区块哈希/区块时间，经 Blockstream Esplora 获取，并核对前第1008区块；使用共识规定的每210,000区块补贴减半规则，在整数聪单位推算名义累计区块补贴。这**包含不可花费的创世区块补贴及潜在未领取补贴**；不是实际流通量、UTXO、ETF存量或BTC投资收益。没有独立全节点交叉验证，不得自称链上独立认证。

**V59证据矩阵：** 从 V58 4/6 基线增加实际通过验证的来源。两份都真实有效是6/6，仅一份有效是5/6，全部缺失是4/6。全部正式分数仍为 null；原始数据有了，不代表因子、PIT或OOS通过。

## 原始链接及许可

- 美联储官方 Z.1 表：https://www.federalreserve.gov/releases/z1/current/html/F51_1_s.htm
- FRED series：https://fred.stlouisfed.org/series/BOGZ1LM893064105Q
- 比特币 Esplora API：https://github.com/Blockstream/esplora/blob/master/API.md
- Blockstream API 公共使用限制：https://blockstream.com/blockchain-data-explorer-api

FRED 系列官方标记 Public Domain: Citation Requested。FRED 原始单位为百万美元；1 万亿美元 = 1,000,000 百万美元。历史观察日是季度对应日期，不是发布日。FRED 最新修订值也不是当期首次公布版本。

Blockstream 免费公共 API 只用于小规模调用、存在速率限制。自动采样计划为每工作日一次，适用权限需按用途进一步核查。不得将公共区块浏览器结果宣传为本地 Bitcoin Core 全节点验证或商业授权确认。

## 工作流与检查

工作流文件：.github/workflows/asset-compass-sources-v59.yml。

PR 测试解析器和历史 V58 门禁，不把测试数据写到公开数据目录。合并 main 后在计划时刻和工作流触发下尝试真实联网，保留单来源失败的降级状态。输出：
- data/asset-compass-equities-z1-v59.json（只有真实成功采集时）
- data/asset-compass-bitcoin-chain-v59.json（只有真实成功采集时）
- data/asset-compass-model-gaps-v59.json（根据存在、时效、来源真实性重新生成）

本地测试命令：
- python3 -m unittest discover -s tests -p 'test_asset_compass_sources_v59.py' -v
- python3 -m scripts.build_asset_compass_sources_v59 fetch-equities
- python3 -m scripts.build_asset_compass_sources_v59 fetch-bitcoin
- python3 -m scripts.build_asset_compass_sources_v59 build-evidence
- node --check macro/asset-compass-sources-v59.js

若没有主分支真实联网运行记录，不得声称 V59 6/6 已采集。代码提交 / GitHub Actions 绿色 ≠ 数据已写 main ≠ 自定义域名同 SHA 正式发布。Issue #479 的双发布器和保护资源隔离仍需独立验收。

## 评分核心缺口保留

- 可投资总回报，仍0/6：股息再投资、票息、期货展期、汇兑、融资与交易费用、代理工具选择、逐产品授权。
- 历史首次可得 PIT vintage，仍0：FRED 最新修订、区块时间、首次见到的 GitHub 提交都不能替代研究决策时真实可得的版本。
- 模型因子独立性、方向、预注册权重和多市场样本外验证，均未认证。
- 研究源可用不代表对应模型因子合格；严禁公布0–100资产评分或交易指令。

**V59 成功定义：真实市场来源、来源证据链和 fail-closed 评分禁令，不以版本号或 UI 数量替代。**

## V59.1 官方源容错与严格历史长度披露

首次主分支采集核验：Blockstream 实际区块采集成功，FRED graph CSV 在 GitHub Actions 连续两次 TimeoutError，因此研究来源覆盖真实状态为 5/6 而非伪称6/6。V59.1优先使用美联储官方网站 Z.1 当前 F51.1.s HTML 表：只提取**Line 1 / Issues at market value / LM893064105** 的**最近六个季度**、按官方表原始十亿美元单位转换为百万美元，并保留原始网页 SHA256，禁止用年度栏目凑成季度历史。官网表无效时才尝试FRED长历史镜像。

特别注明：官网HTML仅提供6个季度，远少于FRED完整历史50+季度，**不能称为历史回测可用或正式PIT**。六资产原始研究覆盖6/6也不等于原始历史时序完整、投资总回报已认证、评分因子合格。源码和测试中保留 source format、实际季度数及历史深度否定标志。日期为季度期末，不是首次发布时间。

V59.1是修复真实数据采集链路，不改变原有V58/V59正式资产评分0/6的严格禁令。发布仍需核对main实际保存和当前受保护网站的同SHA部署。
