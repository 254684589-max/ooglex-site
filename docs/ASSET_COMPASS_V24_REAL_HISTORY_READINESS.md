# Ooglex 全球资产罗盘 V24｜真实历史数据证据与就绪审计

## 实际现状（2026-11-22 检查）
- `main` 上 `data/asset-scores.json` 已有真实的近期宏观快照和数据来源字段；这不是历次首次官方发布版本。
- `main` 中 `data/asset-compass-observation-ledger.jsonl` 和 `data/asset-compass-history-readiness.json` 当前未发现已提交文件。这不证明生产工作流从未生成过任何数据，但**不能宣称已经形成持久可读取的长期历史归档**。
- 先前 V18–V22 研究模块和36项离线单测已验收合并，但没有证据证明已获得历史实时发布版本、第三方商业再分发许可或模型预测能力。
- 最新快照 `observation_date=2026-11-20`；只是该仓库当时的观测，不代表后续运行总是最新。

## V24 技术交付
`scripts/audit_asset_compass_real_history_v24.py` 将两种证据**分开计数**：
1. Ooglex 的 `first_seen_at` 增量账本：计算已有版本数量、观察期与首次记录时间，明确 `official_release_time_known=false`。
2. 仓库外私人 PIT SQLite 数据库：只读查询登记系列、观察期、修订版本数量与许可审核状态，不复制/导出任何原始市场数值。
3. 输出合计就绪报告，明确不可参与正式历史回测、资产专属贡献或发布评分；DB 缺失和账本缺失有各自明确状态，不伪装成0值或合格。

### 无私有历史数据时，可安全运行
```bash
python3 -m scripts.audit_asset_compass_real_history_v24 --output /tmp/ooglex-v24-evidence.json
python3 -m unittest discover -s tests -p 'test_asset_compass_*_v*.py' -v
```

### 已有真实私有 SQLite 历史库时
```bash
python3 -m scripts.audit_asset_compass_real_history_v24 --ledger /tmp/real-first-seen-ledger.jsonl --private-db /tmp/real-release-vintages.sqlite --output /tmp/ooglex-v24-private-audit.json
```
程序禁止把带私有 DB 审计的报告直接写入网站仓库。**脚本不联网下载市场数据，不向公共仓库上传第三方历史数据，也不自动创建不存在的真实历史库。**

## 下一阶段真实数据工作
- 审核 `macro-treasury.yml` 的采集持久化：确认 GitHub Action 实跑中账本是否存在、为什么未见提交文件、是否有遗漏的追加存档；首先保护已有账本，不能重写首次观测时间。
- 针对有真实首次发布时间和版本可核验的官方发布资料，在合规许可允许下导入私有仓库外的 PIT 数据库，记录版本可用时间、来源、授权状态；不存在时保持缺失。
- Cboe VIX、ICE BofA 信用利差、ETF 资金流及其他资产专属数据分别核对展示、缓存、再分发和商业使用许可。不得把公开可下载误判为可商用。
- 建立系列级历史时间覆盖、频率与缺失审计；五年窗口和样本外研究不得以当前修订值倒填历史；真实投资回报数据必须符合统一可投资、可授权、对齐的口径。

## 发布门槛
`validated_for_live_scoring=false`，`eligible_for_point_in_time_backtest=false`，`historical_data_license_certified=false`，`automatic_alerts_enabled=false`。即使某个数据源确有历史值，**研究者对证据真伪及使用许可的独立审核仍不可跳过**。
