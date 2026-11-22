# Ooglex 全球资产罗盘 V27｜分频归档连续性监控

## 真实归档基线（2026-11-22）
`main` 的 `data/asset-compass-observation-ledger.jsonl` 已有14条追加记录，分别覆盖9个有历史记录的指标；其中5条是保留的财政部2025链接与2026观测日期不一致的旧版本，后续5条更正来源年份的记录按实际 first_seen 时间追加。14个版本不等于14个交易日或可回测时间样本。

在 `data/asset-compass-history-readiness.json` 登记的14个必需指标中，已入库7项，尚无归档的7项：
- `bls.core_cpi`
- `bea.core_pce`
- `fed_h41.total_assets`
- `liquidity.reserves`
- `liquidity.tga`
- `liquidity.overnight_rrp`
- `nyfed_recession.probability`

> 注意：账本还含期限利差与盈亏平衡通胀2个派生指标，因此总计9个已种子化指标，但14项必需来源中仅7项。后续以自动生成的最新报告为准。

## V27 交付
- `scripts/monitor_asset_compass_continuity_v27.py`：读取现有真实追加账本，执行先前 V25 的内容完整性检查，并按指标生成版本数、不同观测期、最后首次看到时刻、最后观测期及状态。
- 区分：`not_yet_archived`（从未入库）、`warming_up_single_period`（仅一个不同观测期）、`observed`、`observation_overdue_review`（可能断档，需排查）。将“缺源尚未接入”单列为工作清单，而非伪装成当天断更。
- **只按可观测日期做保守的运维诊断**。日频超过6个工作日、周频超过21个日历日、月频超过80个日历日才触发“待排查”异常；法定节假日、周末及实际统计发布日历尚未单独建模，因此仅是运维阈值，不是官方发布时间承诺。
- 期限利差、盈亏平衡通胀作为推导数据，不作独立来源 SLA 承诺；旧财政部历史来源异常仍报告，不删除历史。
- `.github/workflows/asset-compass-continuity-v27.yml`：在独立归档作业后的周二至周六 UTC 02:30 定时读取主分支账本（也支持手动运行和合并后首次验收），运维严重异常使 Actions 失败，记录可读的步骤摘要。**不会公开市场数据值、改写账本或发送交易指令**。
- `tests/test_asset_compass_continuity_v27.py`：10组离线合成测试，包括周末、跨频、单一期、未采集、来源异常、未来时间与状态锁。

## 运行
```bash
python3 -m unittest discover -s tests -p 'test_asset_compass_*_v*.py' -v
python3 -m scripts.monitor_asset_compass_continuity_v27 --output /tmp/ooglex-v27.json --fail-on-critical
```

该模块不接入投资预警，没有开通0–100分，不认为 first_seen 就是官方首次发布时间，也不宣称有完整 PIT vintage 或已实现可投资资产总回报校准。真正的多日稳定运行要在未来实际的多次定时作业后核验。
