# Ooglex Asset Compass | SOFR V8 真实数据管道验收（2026-11-23）

## 目标
避免持续添加统计页面却无法证实生产日更成功。以主分支的V2采集函数为核心，新增**只读真实数据联网探针**，验证CheckMySwap与美国财政部同时可读、日期精确匹配和6期限可计算。

## 真实审计基线
- 查验时间：2026-11-23（UTC+8周一；美国前一交易日2026-11-20周五）。
- GitHub `.github/workflows/asset-compass-sofr-spreads.yml` 已配置UTC周二至周六03:35日更，但截至本阶段开始，GitHub最近100条Actions记录尚无明确该工作流成功记录。**配置≠实际日更成功**，不推断周日/周一理应有新报价。
- 主站归档 `macro/swap-spreads-history.json` 仍只有2026-11-20，不能将单条样本画作历史变化。
- CheckMySwap的 `GET /api/curves/USD` 近期仍返回2026-11-20的指示性DTCC SOFR曲线，来源：https://www.checkmyswap.com/rates ；非实际可成交互换固定报价。HTTP成功不代表交易所实时行情。
- 美国财政部官方日频XML文档：https://home.treasury.gov/treasury-daily-interest-rate-xml-feed 。

## V8新增
- `scripts/probe_swap_spread_pipeline.py`：与正式采集程序共用 `treasury_by_day` 和 `build_observation`，读取真实两端公共接口，输出 `no_new_day`、`new_candidate_available`、`source_behind_archive`、`date_mismatch`、`source_unavailable`、`source_invalid`、`archived_date_revision`。
- `tests/test_swap_spreads_pipeline_probe.py`：完整离线伪源测试，覆盖无新日、修订、缺失、日期不匹配、未来日期、非法估值方法。
- `.github/workflows/asset-compass-sofr-v8-probe.yml`：GitHub Actions Pull Request和手动只读网络探针，上传临时7日Artifact，不新增Secrets，不推送行情。
- 来源SHA-256作为报告元数据，真实原始响应不向外发布。
- 如果数据日与现存历史相同但任何一个期限数值或方法不一致，进入 `archived_date_revision` 状态并拒绝暗中替换旧值。

## 通过条件
1. Python语法与离线契约测试全部成功。
2. 真实联网探针从两个来源取到有效内容；精确日期与六期限校验通过，并按是否有新日期正确返回。
3. `git diff --exit-code -- macro/swap-spreads-history.json` 证明正式历史未被探针修改。
4. 若两源访问失败，应记录失败根因并保留既有数据，不把故障隐藏或改变评分阈值。

## 未完成事项
GitHub实际定时`schedule`成功记录需要后续运行确认。V8不触发生产写入，不开展历史回填或第三方数据授权认定。网站域名公开访问和360/768/1280浏览器验收需独立完成。

## 发布状态
仅开发PR，未合并或部署。以GitHub Actions实际测试结果为准。
