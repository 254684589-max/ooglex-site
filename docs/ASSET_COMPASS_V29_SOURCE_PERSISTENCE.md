# Ooglex 全球资产罗盘 V29｜宏观数据采集持久化修复

## 已通过源码确认的缺陷
`scripts/update_asset_scores.py` 每次新建国债快照 `data/asset-scores.json` 时，只从旧快照恢复 `bls` 和 `factor_signals`。即使其他采集器在上一个周期成功提交过 `bea`、`fed_h41`、`liquidity`、`nyfed_recession_model`，这些字段也会被下一轮国债更新无条件擦除。

这是确定的**持久化缺陷**，但不能证明现有7项缺失全部由此产生。当前已提交快照仍缺核心 CPI、核心 PCE、联储资产负债表、三项流动性、纽约联储衰退概率。对应独立采集程序都已存在，外部采集超时、解析问题或调度运行失败仍需依据实际日志排查。

## V29 改动
1. `scripts/update_asset_scores.py` 中新增 `retain_recent_auxiliary`：保留经过原先采集器校验的 BEA 核心 PCE、联储 H4.1、流动性、纽约联储衰退模型字段，但只允许 `retrieved_at` 为 UTC 时区完整且不超过 **72小时**的既有数据。缺失、未来时刻或时间戳格式错误的旧值不保留。
2. 保留还要满足原始**观测期时效性**：核心 PCE/衰退概率4个月、联储资产及周度流动性21日、隔夜逆回购11日；流动性子指标分别判定，过期子项丢弃，绝不将旧数值冒充新发布。
3. 原先 BLS 和 `factor_signals` 的代码保留策略未改，避免影响已有功能。独立接口采集仍需再次获取真实官方数据，不能由此视为已经补齐。
4. `.github/workflows/macro-treasury.yml` 在归档后添加只读审计摘要，显示14项必需宏观源的到达数、缺失项和“已到达但尚未归档”列表，便于定位步骤与数据提交问题。
5. 新增12项完全离线合成单测，覆盖四组数据保留、无授权时间戳、未来/超期采集、过时观测及流动性部分失效等。

## 后续需要实际确认
- 监测下一次真实宏观采集 GitHub Actions，确认源侧网络错误与持久化的具体影响；本阶段并未获得可枚举的定时运行完整历史日志，不能声称检查了所有运行详情。
- 真实源成功时，检查新快照是否含有该组；成功后由原 V25/V27 归档持续积累。
- 未经正式发布时间核验的数据只有 first-seen 证据。不可回填为正式 PIT vintage、不可自动启用0–100分、预测、收益回测或投资告警。

## 验收
```bash
python3 -m unittest discover -s tests -p 'test_asset_compass_*_v*.py' -v
python3 -m unittest discover -s tests -p 'test_macro_*.py' -v
```
