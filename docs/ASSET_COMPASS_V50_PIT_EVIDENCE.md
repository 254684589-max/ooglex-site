# Ooglex 全球资产罗盘｜V50 官方首发与修订证据登记册

## 目的与边界

在 V49 因子质量准入矩阵与六资产研究卡片之间增加「V50 官方历史首发与修订证据清单」，覆盖完全相同的 **14 个 canonical 源系列**；不把衍生的 10Y−2Y 利差、breakeven 或纽约联储模型输出当作独立投资信号。V50 是研究证据管理，不是 PIT 认证完成或策略回测结果。

本阶段的正式发布链接均为**检索线索**（`reference_only`），**不是逐点首次发布时刻的凭证**。网站首次归档时间、历史观测期、FRED 后来修订的当前曲线、ALFRED 的版本日期、源网站现存目录，都不能单独证明历史投资决策时点可用的数据版本。当前 14 项 **全部未核实**，模型评分、收益回测、预警均维持关闭。

## 登记文件与前端

- `data/asset-compass-pit-evidence-v50.json`：每个指标的官方发布入口、修订核对入口、数据频率、当前关键证据缺口，以及空的原始发布凭证与修订链列表。
- `macro/asset-compass-evidence-v50.js`：直接读取上述 JSON；与 `OVERVIEW_INDICATORS` 的 ID 和频率严格核对；验证外链为官方 HTTPS 域名；数据缺失、来源不匹配、伪造认证、未经确认的状态变动时安全回退。
- `macro/overview.html`：V49 门禁下展示 V50 14 行正式来源入口与证据缺口。
- `tests/smoke_asset_compass_evidence_v50.cjs`：使用生产 JS、真实注册表、真实历史准备度及六资产快照测试全部门禁。
- `.github/workflows/asset-compass-research-gates.yml`：纳入 V50 测试，保留完整 V18–V49 研究安全校验。

## 官方发布与修订核验线索

| 系列组 | 首发或历史检索 | 修订核证线索 | 需要补齐 |
| --- | --- | --- | --- |
| Treasury 10Y/2Y/TIPS | [财政部每日利率 XML](https://home.treasury.gov/treasury-daily-interest-rate-xml-feed) | [财政部利率统计说明](https://home.treasury.gov/policy-issues/financing-the-government/interest-rate-statistics) | 每个交易日首发文件内容、UTC 可得时点、后续更正完整链 |
| EFFR | [纽约联储 EFFR](https://www.newyorkfed.org/markets/reference-rates/effr) | [参考利率方法及订正说明](https://www.newyorkfed.org/markets/reference-rates/additional-information-about-reference-rates) | 每日初次公开记录及实际订正 |
| CPI / 核心 CPI | [BLS CPI 历史新闻稿](https://www.bls.gov/bls/news-release/cpi.htm) | [BLS 修订政策](https://www.bls.gov/about-bls/revisions.htm) | 发布时刻、当时版本、季调/口径变化 |
| 非农 / 失业率 | [BLS 就业历史新闻稿](https://www.bls.gov/bls/news-release/empsit.htm) | [BLS 修订政策](https://www.bls.gov/about-bls/revisions.htm) | 家庭调查与企业调查各自首发原值及后续修订 |
| 核心 PCE | [BEA 历史新闻稿](https://www.bea.gov/news/archive?field_related_product_target_id=716) | [FRED 逐版本查询文档](https://fred.stlouisfed.org/docs/api/fred/series_observations.html) | 当时可得的指数两期原值及同比计算；BEA 原发布版本优先 |
| H.4.1 及准备金、TGA | [美联储 H.4.1 历史发布](https://www.federalreserve.gov/releases/h41/) | [H.4.1 发布说明](https://www.federalreserve.gov/releases/h41/about.htm) 和 [FRED vintage API](https://fred.stlouisfed.org/docs/api/fred/series_vintagedates.html) | 各期发布文本及修订/重分类链；镜像不能直接充当原版 |
| 隔夜逆回购 | [纽约联储 RRP 操作结果](https://www.newyorkfed.org/markets/desk-operations/reverse-repo) | [纽约联储 RRP FAQ](https://www.newyorkfed.org/markets/rrp_faq.html) | 每日操作公布时刻和后续修订 |
| 纽约联储衰退概率 | [纽约联储收益率曲线研究](https://www.newyorkfed.org/research/capital_markets/ycfaq.html) | 逐月模型文件及相关历史更新 | 当时真正发布的预测版本；严禁使用后期重估结果冒充历史前瞻 |

**PIT 含义**：Point-in-Time，要求依历史决策时间戳恢复当时真实可获得的信息，而不是把今天的历史序列倒填进过去。FRED/ALFRED 查询接口可辅助恢复 vintage，但单有 vintage date 并不自动证明当日的**精确发布时间**，仍需核对发布机构时刻、时区和数据当期值。

## 未来证据条目的最低字段

`first_publication_records[]`、`revision_records[]` 允许未来逐期追加真实凭证，但新增条目仅能计入“待复核”，**不能令 `first_publication_verified` 或 `revision_chain_verified` 变成 true**。

每条凭证至少包括：

```json
{
  "observation_period": "YYYY-MM-DD 或 YYYY-MM",
  "publisher_released_at": "UTC ISO8601 秒级时刻",
  "captured_at": "UTC ISO8601 秒级时刻",
  "publisher_document_url": "官方 HTTPS 来源",
  "sha256": "64 位原始文件摘要",
  "version_id": "同观测期唯一版本标识"
}
```

**注意**：上述为字段模板，不是已采集的证据，禁止在生产注册表中填造样本值。上线 PIT 认证前还必须：核实原始内容与摘要的对应关系、来源文档发布时间、发布时间与抓取时间先后、历史修订的 `supersedes` 版本拓扑、观测单位/时区及修订缺口；经独立复核并完成 V48 信息增量检验及多市场周期样本外总回报测试。要独立验证凭证本身，应采用不可改写保存与签名的审计机制。

## 测试与预期结果

```bash
node --check macro/asset-compass-evidence-v50.js
node tests/smoke_asset_compass_evidence_v50.cjs
node tests/smoke_asset_compass_qualification_v49.cjs
```

当前应显示：14 项来源入口、28 个官方核验链接、0 项已认证首发 / 0 项已认证修订全链、正式评分 0 项准入。即便伪造超大历史覆盖数量或插入结构合法但未经审查的归档条目，正式评分也不得解锁。

## 下一实际数据阶段（V51）

优先取 BLS 就业及 CPI 历史新闻稿 + BEA PCE 公开原始版本，建立按 *observation period × publication UTC timestamp × source file SHA-256* 的可重现抓取与独立复核。Treasury 与纽约联储数据需另行寻找可信的原始发布时间证据，不能默认今天下载的历史表就是当时的原始版本。
