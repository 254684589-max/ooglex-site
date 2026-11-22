# Ooglex 全球资产罗盘 V34｜官方历史新闻稿实物证据采集

## 研究目标
不是再生成一套“可能取得历史数据”的清单，而是从 **BLS 官方历史档案**真实获取一份固定的原始新闻稿文件，记录抓取行为与字节指纹，把它作为将来独立人工复核的候选证据。第一份明确目标：2025-01-15 官方 CPI 新闻稿，观测期2024-12（注意这两种日期不同）。

官方档案：https://www.bls.gov/news.release/archives/cpi_01152025.htm  
官方档案索引：https://www.bls.gov/bls/news-release/cpi.htm

## V34 实装
- `scripts/capture_asset_compass_bls_release_v34.py` 仅允许在明确名单内抓取 HTTPS `www.bls.gov/news.release/archives/cpi_01152025.htm`，禁止跨域、URL重定向、超过2MB、非HTML和不含CPI标识的响应。
- 为实际下载的字节生成 SHA-256、字节长度与 **本次实际抓取 UTC 时刻**。日期 `2025-01-15` 是候选历史发布日，绝不把本次抓取时间倒填到2025年。
- 传入 `--private-dir` 时，把完整新闻稿以内容指纹命名保存到仓库外部私人目录，存储权限目录0700/文件0600；相同指纹幂等，原有内容不匹配则拒绝覆盖。不上传原始新闻稿正文、私有SQLite或抓取缓存到公共代码仓库。
- 缺省仅生成 JSON 元数据回执（不保存原件）；在 GitHub Actions 中默认使用这一安全模式，上传30天回执 artifact，记录成功/失败状态。
- 11项离线测试覆盖安全域名、重定向、假HTML、时间与证据资格锁定、私人原件不覆盖等。
- 私人历史证据原件 **不能自动用作** `macro_vintages.available_at`。需人工核对原始发布材料、原始数值、时区、历史原件曾公开的证据和数据授权后，再导入私人PIT仓库。

## 获取真实证据：两种运行方式
仅临时生成审计摘要（默认不保存历史全文）：
```bash
python3 -m scripts.capture_asset_compass_bls_release_v34 --output /tmp/ooglex-v34-receipt.json
```

Mac本地私人保存官方原件：
```bash
python3 -m scripts.capture_asset_compass_bls_release_v34 \
  --private-dir "$HOME/.local/share/ooglex/private-historical-evidence" \
  --output /tmp/ooglex-v34-receipt.json
```

GitHub：`Asset Compass V34 Official BLS Release Capture` 可手动执行；合并该工作流文件进入 main 后有一次受限 push 验收。原始内容不会作为 Actions artifact 或 Git 提交；即使工作流成功也只证明 **本次能下载原始档案网页**，不证明该页面与2025-01-15的字节完全一致。

## 公共研究资格边界
- 最新实时必需指标采集仍为14/14；真实历史 PIT 资格维持 **0/14**。
- ALFRED 版本日期不等于可以做盘中决策的官方时间戳，且FRED API调用需要独立密钥和授权约束。
- 继续关闭真实历史收益回测、六资产正式评分及自动投资提醒。下一步应在私人仓库中逐批保存历史发布快照的真实数值与原始源版本证据，不得从当前修订数据伪造过去可获得时间。
