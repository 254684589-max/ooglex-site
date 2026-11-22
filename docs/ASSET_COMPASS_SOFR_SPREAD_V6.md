# Ooglex SOFR Swap Spread V6｜带来源指纹的历史候选审核（2026-11-22）

## 目标
在V5只读历史覆盖审计之上，增加按日期采集的**未发布候选报告**，为合法、可复核的回填建立审计链。**不修改生产历史JSON，不自动部署。**

## 依赖
V6以尚未合并的V5开发分支 `feat/asset-compass-sofr-coverage-v5` 为基线；正式发布需先完成V5的测试、审查和合并。V4异常监测仍在独立PR #449，互不覆盖。

## 真实来源与约束
- CheckMySwap 公开USD SOFR OIS指示性历史曲线：`https://www.checkmyswap.com/api/curves/USD?date=YYYY-MM-DD`。官方方法说明：https://www.checkmyswap.com/methodology
- 美国财政部官方CMT：`https://home.treasury.gov/treasury-daily-interest-rate-xml-feed`（年度XML格式）。
- CheckMySwap USD归档始于2026-03-19；历史API的同日期快照可能被后续更新，日期不等于不可变原始版本。
- 按日期匹配、6个完整期限、`close`/`close-thin`方法、正利率与公式一致性沿用V2校验规则。
- HTTP 404不回退到最近日期；接口日期与请求日期不一致或缺少Treasury数据则拒绝。
- 两条源的原始响应分别计算SHA-256，报告还保留完整来源URL、审核日期、close/close-thin数量与是否与现有历史冲突。
- **严禁把指示性曲线误标为可执行交易价格。** 重新分发第三方历史数据前应核实许可。

## 本阶段新增
- `scripts/build_swap_spread_candidates.py`：一次最多10个指定日，报告状态区分 `candidate`、`already_archived`、`archive_conflict`、`no_archive`、`rejected`。
- `tests/test_swap_spreads_candidates.py`：无网络离线测试，覆盖6期限、原始响应摘要、日期拒绝、404、历史冲突与禁止越权扫描。
- `.github/workflows/asset-compass-sofr-v6-check.yml`：PR代码校验和历史数据未变检查。
- `.github/workflows/asset-compass-sofr-v6-review.yml`：手动指定一个历史日期，在GitHub Actions中产生最多7天保存期的候选Artifact；仅 `contents: read`，不提交、不发布行情。

## 使用说明
在仓库根目录（V5+V6分支）运行：
```bash
python -m unittest discover -s tests -p test_swap_spreads_candidates.py -v
python scripts/build_swap_spread_candidates.py --date 2026-11-20 --output /tmp/sofr-v6-candidates.json
```
这里2026-11-20是示例的已归档观测日期；当新取得的同日数值不同会报`archive_conflict`，并保留旧记录不受影响。这种报错应调查来源版本，而不是被忽略。

## 后续生产导入门禁
1. 完成数据许可与历史快照版本可追溯性核实。
2. 每个日期经两源对照，审核close与close-thin、同期财政部CMT、SHA-256、源文件来源。
3. 新建独立历史回填审核PR，禁止覆盖现有同日期记录，禁止伪造缺失交易日。
4. 在真实历史日数达到V3/V4门槛后开启分位数和统计异常提示。
5. 验证每日自动更新任务成功记录及真实线上页面。V6不会冒充这些工作已经完成。

## 发布状态
仅独立开发PR；未合并main、未实际回填任何历史日，未验证真实源站历史API下载，不声明生产数据已连续更新。
