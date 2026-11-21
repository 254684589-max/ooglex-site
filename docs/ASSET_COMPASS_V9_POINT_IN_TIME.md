# Ooglex 全球资产罗盘｜第九阶段：Point-in-Time 数据与滚动回测

## 本阶段落地

- `macro/migrations/0001_point_in_time.sql`：SQLite/Cloudflare D1 兼容的数据结构设计，保留宏观数据原始发布版本、模型因子版本与研究诊断记录。**目前没有连接或部署真实 D1 数据库。**
- `scripts/asset_compass_vintages.py`：只接受显式发布时刻（UTC 或带时区 ISO8601）、可核查的来源 URL 与 release ID；禁止未来日期、不允许悄悄改写旧版数据，按历史决策时点查当时可获得的数据。
- `scripts/asset_compass_walkforward.py`：扩展训练窗口、purged 训练标签、非重叠测试信号、简单常持有基准的方向命中率对比。输出始终标注 `validated_for_live_scoring=false`。

## 需要的真实输入

历史指标 CSV：

```csv
series_id,source,frequency,units,observation_date,available_at,value,source_release_id,source_url
```

历史因子 CSV：

```csv
asset_id,factor_group,observation_date,available_at,factor_signal,model_version,source_refs_json
```

其中 `source_refs_json` 是非空字符串数组，必须可追溯真实数据来源；没有实际发布存档不得编造 `available_at`。

研究型回测示例以用户合法持有的真实信号 CSV 和价格 CSV 输入：
```
python3 scripts/asset_compass_walkforward.py --signals /tmp/signals.csv --prices /tmp/prices.csv --output /tmp/research-folds.json
```

研究数据库操作：
```
python3 scripts/asset_compass_vintages.py --db /tmp/asset-compass-vintages.sqlite --macro-csv /tmp/official-releases.csv
python3 scripts/asset_compass_vintages.py --db /tmp/asset-compass-vintages.sqlite --asof 2026-11-20T12:00:00Z --series US10Y
```

只能运行在私有研究位置，禁止把带授权限制的价格和研究数据文件写入公开站点目录。

## 专业限制

1. 当前国债历史数据是后验下载的观测值，并不构成当时真实可得的首次发布档案。BLS CPI 与非农历史也存在修订，不能将今天查询到的最新修订值直接回填为过去每期首次发布信息。
2. `macro_vintages` 已具备多版本存储能力，但尚未自动采集各个历史发布时间的原始版本；缺真实数据即无可用的历史因子回测。
3. 六类资产目前只有价格型研究观测，未取得统一合法的总回报序列（股息/ETF分红、期货展期与资金占用等需要处理）。
4. 滚动诊断仅测试预先提供的历史评分方向，不进行超参数拟合、策略损益归因或投资胜率承诺；交叉验证窗口与日历效应仍需审计。
5. 本次不解锁实时评分、不更新官网的投资信号。生产评分发布需要独立的数据授权、因子校准、长期样本外验证和人工技术验收。

## 下一阶段实际条件

先合法获取与记录各历史版本的权威宏观发布资料和统一口径可用的资产总回报数据，测试多种经济周期。满足覆盖率和统计/回撤阈值之后，才讨论自动化开放评分。不得为了补齐网站的 0–100 分而假造信号。
