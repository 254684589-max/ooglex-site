# Ooglex 全球资产罗盘｜V53 新闻稿原文数值与修订口径审查

## 目标

建立可复核的统计字段提取，而不是把 V51/V52 抓到的历史 HTML 误当成已经证实可用于当期交易的 PIT 原始值。BLS CPI / 核心 CPI、BLS 非农新增就业 / 失业率、BEA 核心 PCE 五条源系列各自拥有不同单位、季节调整和统计含义。它们在新闻稿中出现的**发布时摘要数值**不等于官方完整的 **CPI或PCE价格指数水平（index level）**，也不一定是该网页首次公开时的相同字节。

V53 在 V52 **经过哈希链/文件权限/原始字节 SHA-256 核验的真实私有网页副本**上做只读解析。若未实际运行 V52 保管或保管完整性失败，V53 拒绝生成可信的研究字段；不能用最新 FRED 曲线或自行填造缺失月份取代。

## 严格区分的字段

| 新闻稿 | 提取候选字段 | 单位、季调 / 方法 | 不等于什么 |
| --- | --- | --- | --- |
| CPI | all-items 环比 | %，季调 | CPI原始指数水平 |
| CPI | all-items 同比 | %，未季调 | 季调环比 |
| CPI | core CPI（除食品能源）环比 | %，季调 | all-items或同比 |
| CPI | core CPI 同比 | %，未季调 | 环比 |
| Employment Situation | 非农就业当月增加/减少 | 人数变动，企业调查，季调 | 就业总人数 / 家庭调查 |
| Employment Situation | U-3 失业率 | %，家庭调查，季调 | 非农就业变动 |
| BEA Personal Income and Outlays | core PCE 环比 | 新闻稿直接报告的百分比变动 | PCE价格指数水平 |
| BEA Personal Income and Outlays | core PCE 同比 | 新闻稿直接报告的同比百分比变动 | 环比或其数值指数 |

第一版对这7份特定文档预期 **20个新闻稿候选数值**。如果某个字段文本缺失或格式不满足严格语义，标记 `review_required_incomplete_headline`，不得默默设为0或向别的数据接口抓取一个修订后数值。

## 修订记录分两类，均不自动成为PIT证据

**A. 同一URL不同时间抓取的真实HTML版本**：V52会记录不同 SHA-256。V53只在 `source_series_id + 观测期 + metric statistic + seasonal_adjustment` 完全相同的情况下计算前后数值差，并标记 `observed_page_value_change_not_certified_historical_revision`。原HTML字节变化可能只是网页模板、脚注或排版改动，**不能声称历史发布时间的官方修订**。

**B. 后一期BLS就业新闻稿叙述对前月估计的修订**：V53解析 `from prior to revised` + 有符号修订量，并对照 V53 私有档案中前一期的新闻稿候选值。只有修订的数值算术与单位一致，才记录 `cross_release_revision_claims`。例如 2025 年3月7日就业稿称前一期2025年1月增加就业由 +143,000 修订至 +125,000，差值 -18,000；这份来源交叉证据不代表已经找到全部更早修订链或精确UTC公开可得时刻。官方新闻稿有公开说明，详情以实际保管的源文件摘要为准。

BEA September 2025 新闻稿明确其随后将通过2025年12月23日的数据表/API更新July–September数据，不另发相同September报告。因此**只对比新闻稿HTML可能漏掉真正的官方修订**；此阶段不会用“HTML没有变化”证明价格指数完全未修订。

## 文件与命令

- `scripts/asset_compass_release_values_v53.py`：仅接受本地 V52 哈希链核验通过的原文HTML；不猜数据；逐字节摘要锚定提取值；比较版本与跨报告修订声明；报告生成在**网站仓库外**。
- `tests/test_asset_compass_release_values_v53.py`：独立离线测试覆盖五项系列、月环比/年同比/季节调整、非农人数与失业率单位分离、历史修订、网页篡改、缺失拒绝与禁止PIT资格。
- `.github/workflows/asset-compass-release-values-v53.yml`：每次相关主分支变动或手工触发时 **临时下载** 七份官方新闻稿并提取候选值；上传 **30天元数据工件**（非原始HTML），**不代表私人R2保管已完成**。
- `.github/workflows/asset-compass-research-gates.yml`：包含V18–V53所有研究门禁。

在私有原文已经保存的位置执行：

```bash
python3 -m scripts.asset_compass_release_values_v53 \
  --private-dir "$HOME/.local/share/ooglex/private-historical-evidence/v52" \
  --output /tmp/ooglex-v53-source-reported-values.json --require-complete
```

如果本地尚无原文，请先执行 V52：`bash scripts/run_asset_compass_v52.sh`。不要提交这个私有输出报告或任何HTML到网站仓库。

## 明确未完成与后续阶段

- 7份网页的历史首次版本身份、首次公开精确 UTC 时间：未核证。
- CPI / PCE 真实指数水平逐月首发值和全部季调版本链：未核证；**新闻稿环比同比不能替代指数水平**。
- 所有14条原始源系列PIT认证、V48因子独立性审查和样本外全市场策略验证：仍不足。
- 正式六资产评分及自动投资预警：**0 准入，继续关闭**。
- 要取得真正多修订历史，应增添BLS/BEA官方每期可核证的首次发布表格、版本化指数水平及后来更新的统计表/API，并进行独立人工复核。

**建议 V54**：把来源的原始指数水平、官方版本时间戳和修订谱系引入独立校验流程，并建立技术/统计双重复核签署，逐期准入而非一键解锁。
