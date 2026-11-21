# Ooglex 全球资产罗盘｜第十阶段：真实首次观测归档

## 已实现

- `scripts/archive_asset_compass_observations.py`：从**已经核验并发布**的美国财政部收益率、BLS CPI/就业、纽约联储 EFFR 快照中追加观测记录。支持重复运行去重、同一观测值修订记录并存、防止倒填首次采集时间。
- `data/asset-compass-observation-ledger.jsonl`：工作日采集成功后增量生成。**首次归档前不存在完全正常**。文件保存当前已经在网站展示的官方宏观观测，不含六类资产原始市场行情。
- `scripts/check_asset_compass_history_readiness.py`：按系列汇总观测数、不同观测期、首次归档时点。报告始终 `validated_for_live_scoring=false`。
- `data/asset-compass-history-readiness.json`：站点构建前生成，只公开归档数量与质量状态，不复制指标数值。
- `macro/index.html`：展示真实归档进度，明确“首次看到的时间不等于官方首次发布时间”。
- 定时更新流程 `.github/workflows/macro-treasury.yml`：接在官方数据采集、评分安全门槛评估之后。采集失败不追加归档。

## 关于历史数据的关键区别

首次看到的数据归档只说明 Ooglex **在这个时间已经有了这个数**：

1. **观测期**：例如 BLS 2026年10月 CPI。
2. **首次归档时间 first_seen_at**：Ooglex 数据管道实际写下它的 UTC 时刻。
3. **官方首次发布时间 available_at**：本阶段没有自动取得，**不能通过首次归档时间或观测期推算**。

因此归档记录全部标记：
```json
{"official_release_time_known":false,"eligible_for_historical_official_vintage":false}
```

它们可以用于长期数据质量、之后的观测研究，但不能在2025年回测中被伪装为当时已经公布的数据。回测模型需要真正的发布历史或经授权的实时归档证据。

## 当前研究边界

- 目前只有美国财政部、BLS 与纽约联储部分指标；未包含完备的流动性、风险、资产专属等六因子；
- 2025年10月 CPI 缺少官方基期值时不计算对应2026年10月同比；
- 六类资产已有报价序列但未获得合格、统一的可投资总回报口径；
- 历史滚动样本外诊断工具已存在，但没有可信的足够多真实历史模型信号；
- 不输出虚构评分、命中率或收益预测，不宣称历史模型获得投资有效性证明。

## CI 验证与操作

离线测试：
```
python3 -m unittest discover -s tests -p 'test_macro_*.py' -v
```

手动重放当前真实快照生成私有测试归档（不写生产数据）：
```
python3 -m scripts.archive_asset_compass_observations --ledger /tmp/ooglex-first-seen-test.jsonl
python3 -m scripts.check_asset_compass_history_readiness --archive /tmp/ooglex-first-seen-test.jsonl --output /tmp/ooglex-readiness-test.json
```

正式运行：周一至周五 UTC 23:40 调度 `.github/workflows/macro-treasury.yml`；首次成功运行才建立生产归档。GitHub Actions、权限或上游接口问题可能影响实跑，须以实际运行日志为准。
