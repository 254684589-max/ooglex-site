# Ooglex SOFR V5｜历史覆盖审计与安全回填准备（2026-11-22）

## 目标与阶段边界
将“已有每日自动采集工作流”与“已经持续稳定取得真实数据”区分开。本阶段不修改日频采集脚本、原始利差归档文件或已合并V2/V3页面；补充可重复执行的只读审计器及手动验证工作流，为以后可信回填创造条件。

## 现状（检查时点 2026-11-22）
- 主分支 `macro/swap-spreads-history.json` 只有 2026-11-20 一条完整匹配交易日观测。
- 历史采集工作流设置为 UTC 周二至周六 03:35，最近一批GitHub Actions运行记录没有确认该采集任务实际成功。周日不能把尚未触发当作已失败。
- V4异常监测仍在独立PR #449；V5独立于V4，不擅自修改生产分支。
- CheckMySwap官方文档记载其USD存档始于2026-03-19，支持 `GET /api/curves/USD?date=YYYY-MM-DD`；404不能冒充上一个可用日期。历史同日存档可能更新，不能把当前下载误称当时的不可变原始版本。
- CheckMySwap指示性OIS数据不是可执行的交易商报价；美国财政部CMT是平价债券收益率，两端约定不同，计算只能作为研究利差。

## 新增文件
- `scripts/audit_swap_spreads_coverage.py`：对原始JSON只读审计，检查重复、未来日期、6期限、公式、数据质量方法，输出观测总数、起止日期、超过7日过期状态、稀疏收盘样本占比、工作日窗口缺口。工作日缺口 **包括美国节假日**，不是自动确认“采集失败”的交易日。
- `tests/test_swap_spreads_coverage.py`：离线测试，不使用API、没有生产写入。
- `.github/workflows/asset-compass-sofr-audit.yml`：手动按需执行只读审计，可选输入一个历史日期进行来源核验；仅上传14天报告Artifact，`contents: read`，不会推送数据。
- `.github/workflows/asset-compass-sofr-v5-check.yml`：PR运行测试，并确认生产历史JSON没有被修改。

## 运行方式
从仓库根目录运行：
```bash
python -m unittest discover -s tests -p test_swap_spreads_coverage.py -v
python scripts/audit_swap_spreads_coverage.py --today 2026-11-22
python scripts/audit_swap_spreads_coverage.py --date 2026-11-20 --output /tmp/sofr-coverage-audit.json
```
第三个命令执行联网来源验证；它仅返回`verified_only`、`missing_archive`或`not_matched`。**不会写入历史归档。** 支持一次最多10个指定日期。

## 后续生产回填门槛
先取得CheckMySwap历史数据保存和再发布许可判断，保存来源URL、方法字段、日期、抓取时间、版本/修订说明；逐日匹配美国财政部实际CMT观测、确认完整六期限，不跨日期填充。新增专门的回填审阅PR，并对现存同日期冲突值人工审核，禁止静默覆盖。当前阶段无历史自动回填与完整历史分位数，网站仍应显示样本不足。

## 验证与发布
只在独立PR中提交；GitHub CI实际完成前不宣称验收通过。未合并、未部署、未改变Secret或外部服务配置。
