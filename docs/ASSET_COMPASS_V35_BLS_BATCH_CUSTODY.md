# Ooglex 全球资产罗盘｜V35 BLS 三期历史新闻稿批量取证

## 取证范围：已经核对存在的官方 BLS 档案链接
| 观测期 | 历史新闻稿日期 | 来源 |
| --- | --- | --- |
| 2024-12 | 2025-01-15 | https://www.bls.gov/news.release/archives/cpi_01152025.htm |
| 2025-01 | 2025-02-12 | https://www.bls.gov/news.release/archives/cpi_02122025.htm |
| 2025-02 | 2025-03-12 | https://www.bls.gov/news.release/archives/cpi_03122025.htm |

以上是新闻稿的候选**历史发布日期**。本次网络下载的 `captured_at` 是实际下载时刻，不能倒填为2025年的历史可得时刻。即使页面包含当时发布禁令解除时间，也不证明当前返回的每一字节在当时就完全相同。

## V35 实装
- 扩展既有 `capture_asset_compass_bls_release_v34.py` 的强制 HTTPS BLS URL 白名单，另外登记两期有实际官方网页的新闻稿。
- `capture_asset_compass_bls_batch_v35.py` 逐份运行已审计的单文档抓取器。每份成功回执包含 SHA-256、字节数、观测期、文件 URL、本次抓取时间。失败项仅记录错误类别，不能误记为0或成功；支持 `--fail-if-incomplete` 使 CI 在任一期访问失败时标红，仍输出已成功的回执以方便诊断。
- `.github/workflows/asset-compass-bls-batch-v35.yml` 合并至主分支后有一次受限触发，也支持人工触发；单次 GitHub Actions 访问 BLS 3个 URL，上传 **30 天保留期**的 JSON 元数据 manifest。此工作流**不保存原件全文**，GitHub Runner 文件系统是临时的，不是长期证据仓库。
- Mac 通过 `--private-dir` 可以把三份原始 HTML 保存至本地私人目录，用内容 SHA-256 防篡改标识；源端每次返回内容可能发生变化，保管的时间起点是本次下载。
- 新增11项独立合成测试并纳入 V18–V35 研究门禁。测试通过不证明联网 BLS 实际成功；以 Actions 的实际下载结果或本地真实下载记录为准。
- 保留正式投资评分、历史回测和主动交易预警锁定：`historical_pit_series_approved=0`。

## 本地一次性执行（在 GitHub 工程根目录）
```bash
python3 -m scripts.capture_asset_compass_bls_batch_v35 \
  --private-dir "$HOME/.local/share/ooglex/private-historical-evidence" \
  --output /tmp/ooglex-v35-cpi-manifest.json \
  --fail-if-incomplete
```
上述命令保存本机私有 HTML 和私有研究元数据，不会替用户在 GitHub 建立长期原件存储。实际存储的内容仍需按原稿发布日期、当时可获得时刻、来源修改历史及再分发权限分别核验。

## 状态判断
- 前期 V30 已把实时必需来源从7/14提升至14/14；V31经真实采集证明跨来源时间戳一致。
- 首次观测历史账本最后一次核验为21条记录、每项只有1个不同观测期；没有得到足够的可回测历史样本。
- V34 workflow 的实际 GitHub 运行结论目前无法由现有连接的“按PR提交查询”接口直接枚举。不可把已配置工作流误报为已完成真实取证。
- V35 三期原始网页能否在 GitHub Actions 上被抓取，以合并后的该工作流运行记录为准；如果 BLS 限制 Runner IP，需要明确保留失败结论，不伪造 SHA-256、体积或数据发布时间。
