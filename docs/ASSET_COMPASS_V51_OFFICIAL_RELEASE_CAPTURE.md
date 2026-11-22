# Ooglex 全球资产罗盘｜V51 官方历史发布文件采集与校验

## 从 V50 的目录，进入真实官方文档采集

V50 只提供官方目录及证据缺口，不能被视作已取得原始时点（PIT）发布版本。V51 新增受控下载器，使用 7 个**已明确定位到单期发布文档**的 BLS、BEA 官方 URL，抓取时将实际响应字节计算 SHA-256。已取得的字节、抓取时间以及失败原因被逐笔记录，不伪造样本，也不将当前能下载到的历史文档认定为某个历史时刻可见的相同版本。

### 纳入本轮的 7 个候选

| 发布机构 | 历史报告 | 实际观测期 | 关联 V49 源系列 |
| --- | --- | --- | --- |
| BLS | CPI（2025-01-15 发布日期线索） | 2024-12 | bls.cpi, bls.core_cpi |
| BLS | CPI（2025-02-12 发布日期线索） | 2025-01 | bls.cpi, bls.core_cpi |
| BLS | CPI（2025-03-12 发布日期线索） | 2025-02 | bls.cpi, bls.core_cpi |
| BLS | Employment Situation（2025-02-07 发布日期线索） | 2025-01 | bls.unemployment, bls.payroll |
| BLS | Employment Situation（2025-03-07 发布日期线索） | 2025-02 | bls.unemployment, bls.payroll |
| BEA | Personal Income and Outlays（2025-09-26 发布日期线索） | 2025-08 | bea.core_pce |
| BEA | Personal Income and Outlays（2025-12-05 发布日期线索） | 2025-09 | bea.core_pce |

**发布日期仅为官方原始文本/存档目录的候选参考，不是精确 UTC 公开可得时刻、未经修订的数值，亦不能证明当前下载的文件与历史原版字节一致。**

重要例外：BLS 官方存档明确标示**2025 年 10 月 CPI、2025 年 10 月就业形势报告没有单独发布**（联邦政府拨款中断）。V51 强制保留这两个例外，拒绝制造“缺失月份的原始新闻稿”。其他报告可能随后补充相关统计数据，但不等于该月当时按时发布。

## 交付文件

- `data/asset-compass-v51-release-candidates.json`：真实单期候选 URL、观测期、覆盖的5项源指标、是否发布的例外记录。所有候选初始 `not_run`，认证布尔值全为 false。
- `scripts/capture_asset_compass_official_v51.py`：仅下载固定官方主域下的指定历史文档，拒绝重定向、站外链接、错误内容类型、异常大小、错误主题、相同地址重复与伪造验证标志。按抓取的**原始字节**生成 SHA-256。
- `tests/test_asset_compass_official_v51.py`：12个不依赖网络的安全测试，包括原始字节哈希、强制私有路径、异常响应、篡改文件检测、假的PIT认证、2025年10月未发布记录。
- `.github/workflows/asset-compass-release-capture-v51.yml`：独立真实网站采集工作流；主分支有 V51 相关代码更新或人工触发时抓取，30 天 GitHub Actions artifact **只保存元数据收据，不保存原始 HTML 文件**。
- `.github/workflows/asset-compass-research-gates.yml`：完整 V18–V51 离线研究门禁。

## 使用方法（项目根目录）

```bash
python3 -m scripts.capture_asset_compass_official_v51 --dry-run
python3 -m unittest discover -s tests -p 'test_asset_compass_official_v51.py' -v
```

真实抓取并保存到**仓库之外**的私有路径（例如 Mac 用户家目录）：

```bash
python3 -m scripts.capture_asset_compass_official_v51 \
  --private-dir "$HOME/.local/share/ooglex/private-historical-evidence/v51" \
  --output "/tmp/ooglex-v51-manifest.json" --fail-if-incomplete
```

安全约束：不得把 `--private-dir` 或 `--output` 放在 GitHub 网站仓库内。首次采集和重复采集均由实际字节计算摘要；同名摘要文件如果被篡改必须拒绝覆盖。GitHub Actions 的无私有目录模式只产生临时元数据收据，没有真正的长期原始字节保管能力；后续需接入独立私有存储和不可改写凭证，才可能构成持续的证据保管链。

## 逐期 PIT 认证仍需要额外完成

1. **发布时间核证**：对原始官方新闻稿的日期、时区、精确放行时刻做独立核对，证明每次历史模拟决策时间前文件已经可得。网页的 embargo 文句是线索，不是独立证据。
2. **历史版本完整性**：核对当前文件是否在首次公布后发生过修改，记录各个版本的原始 SHA-256、版本序列及修改时间；日后单次抓取不能替代历史修订全链。
3. **原值提取与审查**：将新闻稿中的 CPI 原指数、季调、非农就业修订、失业率和 BEA 核心 PCE 与表格口径匹配，留存单位/季调/舍入规则。单一新闻稿标题中的同比率，不能自动替代可回测的原始指数 vintage。
4. **源独立性与模型能力**：继续执行 V48 去重、V49 历史长度下限以及样本外多周期检验；资产总回报仍需可验证。
5. **版权与访问**：公开研究终端仅展示采集元数据及官方链接；原始网页不直接放入公开 GitHub，未经审查不再分发。

## 当前资格

- 正式认证历史首发系列：**0/14**。
- 完整修订链认证：**0/14**。
- 六资产正式评分、历史策略回测和自动投资预警：**关闭**。
- V51 目标：先产生真实、可追踪的**采集收据**，不是未经核证就解锁交易模型。

V52 推荐针对这批真实文件进行原始统计数值提取、初版与修订版逐期对照和独立证据复核；不得将未经实证核对的日历或发布时刻猜测填入 PIT 数据库。
