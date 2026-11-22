# Ooglex 全球资产罗盘 V33｜官方历史版本资格审查

## 实际基线
2026-11-22 的 `main` 首次观测账本共21条、14项必需宏观指标初始覆盖14/14，但每项只有1个不同观测期；5条早期财政部记录使用错误年份来源 URL，后续5条按真实采集时刻更正。V31已通过完整快照时间一致性审查，V32已部署质量监控。

**现有完整覆盖只表示“今天能采集到”；绝不表示历史上每个交易日发布了什么、什么时刻可获知。**

## 官方候选证据与限制
- 美国财政部收益率：财政部公布收益率历史表，可作数值历史研究；仅历史数据日期不能证明原始公开时间。
- BLS 核心/整体CPI、失业率、非农：查看 BLS 官方历史新闻稿和发布时间表。需要按每次原新闻稿及后续修订逐条验证；计划发布时间不等于实际可交易时刻。
- BEA 核心 PCE、联储 H.4.1、准备金和一般账户：查 BEA / Fed 原始发布档案，或 FRED/ALFRED 的实时版本历史；FRED 当前下载 CSV 往往反映最新修订值，不是过去的可得版本。
- 纽约联储 EFFR、隔夜逆回购及衰退模型：需逐一核对官方系列、最早可得时刻及以后修订。衰退概率模型不是官方经济衰退预测承诺。
- **ALFRED 的 vintage date** 提供一日粒度的版本日期，并非 intraday 分秒发布时间；当天决策回测需要证明实际发布时刻与时区，或者采用保守的次日可用规则并明示。
- FRED API 的 `fred/series/vintagedates` 与 `fred/series/observations` 可检索版本日期及对应实时观测（需要 FRED API Key）；但“API查到历史数据”不等于已完成原始来源独立核验、许可证审查和资产回报校准。

官方技术资料：
- https://fred.stlouisfed.org/docs/api/fred/series_vintagedates.html
- https://fred.stlouisfed.org/docs/api/fred/series_observations.html
- https://www.bls.gov/bls/news-release/cpi.htm
- https://www.bea.gov/data/consumer-spending/main
- https://www.federalreserve.gov/releases/h41/

## V33 实现
- `scripts/qualify_asset_compass_pit_v33.py` 整合 V24 私有 SQLite 元数据与 V32 账本审计，逐一输出14项证据登记：候选官方档案入口、现有 first-seen 版本、不同观测期、可选私有研究版本数、来源原始发布时间核验、版本原值核验、发布材料完整性、授权、真实可投资资产收益资料等。
- **缺少被独立复核的原始发布材料与许可批准时，14项全部标记 `requires_independent_release_and_license_review`；私有数据库有任何行数也不会被自动认证。**
- 如指定 `--private-db`，它必须位于 GitHub 工作区以外；私有数据库本体不会导出到仓库。工作流默认不连接用户电脑私人数据库，输出的是无私有数据的候选审查 JSON。
- `.github/workflows/asset-compass-quality-v32.yml` 已合并 V33 只读质量门禁，每周二至周六 UTC 03:00 和合并工作流后的首次触发。产物为 `ooglex-v33-pit-evidence`（30天），不得包含原始宏观版本值或私有数据库原文。
- 新增 10 项离线合成测试，尤其验证私有 SQLite 中存在一个看似完整的来源记录时仍不得自行标记为已认证。

## 资格判定
目前：
- 当前真实数据源覆盖：**14/14**
- 已独立认证、具备可按历史决策时点回测的来源：**0/14**
- 资产真实总回报序列及多经济周期样本外验证：**未完成**
- 正式 0–100 分、历史预测回测、自动投资提醒：**持续锁定**

下一步必须通过真实可复核的官方原始发布证据建立私人、不可变版本记录，再做许可审查和真实资产收益校准；不能把 today 获取的修订后值以伪造的 first_seen 方式倒填过去。

## 只读运行
```bash
python3 -m scripts.qualify_asset_compass_pit_v33 --output /tmp/ooglex-v33-pit.json
python3 -m unittest discover -s tests -p 'test_asset_compass_*_v*.py' -v
```
