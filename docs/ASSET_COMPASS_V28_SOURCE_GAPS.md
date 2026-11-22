# 全球资产罗盘 V28｜真实来源缺口与归档差异审计

## 对 main 的实际检查（2026-11-22）
- `data/asset-scores.json` 当前的 `generated_at` 为 2026-11-21T17:10:30Z，主要包含国债五个值、BLS CPI/失业率/非农三项、纽约联储 EFFR。
- 必需来源共14项，快照里已见7项，尚缺7项：`bls.core_cpi`、`bea.core_pce`、`fed_h41.total_assets`、`liquidity.reserves`、`liquidity.tga`、`liquidity.overnight_rrp`、`nyfed_recession.probability`。
- `data/asset-compass-observation-ledger.jsonl` 有14条 first-seen 版本记录（包括来源纠正后新增的5条），并非14天的宏观历史。基于此不可能声称已经取得可校准的 PIT 历史数据库。
- 仓库有 `scripts/update_macro_bls.py`（明确配置核心CPI series CUSR0000SA0L1E）、`scripts/update_macro_fed_bea.py`（PCEPILFE/WALCL）、`scripts/update_macro_liquidity.py`（WRESBAL/WTREGEN/RRPONTSYD）以及 `scripts/update_nyfed_recession.py`（官方 allmonth.xls）。
- 这些采集器对部分外部源错误使用“待验证/缺失”而非伪造值。**某个指标没有进入已提交快照，不能单凭这一点确定是该数据源无数据、接口超时、源解析失败，还是采集成功但提交链路没有运行。** 应结合对应 GitHub Actions 实际日志核实。

## V28 的实际修复
- `scripts/diagnose_asset_compass_sources_v28.py` 分别判定：`missing_from_latest_snapshot`、`snapshot_present_not_yet_archived`、`snapshot_observation_archived`。判定基于现存真实快照与不可篡改归档的值/观测期/单位/来源指纹。
- 对7项缺失指标逐一映射其实际采集脚本与官方指标符号。不会用缺失值填0，也不假定外部抓取成功。
- 若快照超48小时，自动运维检查失败；但已有数据仍可用于排查，绝不将快照采集时间当成经济数据的首次官方发布时间。
- 集成至只读 `asset-compass-continuity-v27.yml`：每周二至六 UTC 02:30 自动运行，输出 GitHub Actions 摘要，不将原始宏观数据重复公开或改变账本。
- 新增10项合成测试；依然禁止历史回测、正式0–100分及交易/投资警报。

## 下一阶段实证闭环
检查 `.github/workflows/macro-treasury.yml` 近期真实定时运行记录，将上述7项指标分辨为：
1. 官方数据暂缺或发布日未到；
2. 接口超时、限流或上游变更；
3. 采集已经成功但持久快照未包含；
4. 源字段存在但首次观测归档失败。

只在具有真实官方数值、可追溯来源、符合单位/频率和时效要求时才写入，禁止从当前修订后的长期历史倒填过去的首次发布时点。

## 本地只读验证
```bash
python3 -m scripts.diagnose_asset_compass_sources_v28 --output /tmp/asset-compass-v28-source-gaps.json
python3 -m unittest discover -s tests -p 'test_asset_compass_*_v*.py' -v
```
