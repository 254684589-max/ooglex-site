# Ooglex 全球资产罗盘 V36｜BLS历史网页原件的私人完整性保管

## 已实现的实物保管机制
V34/V35 可下载三期真实的 BLS CPI 历史新闻稿，但此前 GitHub Actions 只留30天元数据回执；原件在临时 Runner 消失，无法称为长期历史证据库。V36 使 **Mac 等持久本地目录**中实际已取得的HTML原件有可复核的保管日志，避免混淆本地存储与云端临时抓取。

- `scripts/verify_asset_compass_private_custody_v36.py` 独立复核每一份本地 HTML 的 SHA-256、字节数、官方来源 URL、观测期、本次真实 UTC 抓取时间与文件访问权限。
- `custody-v36.jsonl` 采用链式 `prev_hash` / `entry_hash` 的 SHA-256 链，任何中间日志变更、原始 HTML 改动、缺失文件、额外权限均导致验证失败。重复相同回执不重复追加；本批失败项不冒充成功。
- `capture_asset_compass_bls_batch_v35.py --private-dir` 现在在三期真实下载保存后，自动检查文件并记录日志。本地目录及原件必须位于 GitHub 仓库外，目录权限0700、原件和日志0600。
- **限制**：没有额外可信签名或独立备份时，拥有完全写权限的攻击者可同时重写整条哈希链；链式哈希并非不可篡改的外部时间戳服务，不能证明历史上官方首次发布时刻。
- **持久性**：本地私人目录保留到用户删除或磁盘损坏为止；当前没有设置 Time Machine、异地备份、Cloudflare R2 或不可变存储，不能声称具备跨设备灾备。
- GitHub CI 仍然只生成临时回执元数据，**不应把原始 BLS HTML 上传至公共仓库或 GitHub Actions artifact**。V36 的本地保管功能仅在明确提供 `--private-dir` 并真正拿到文件后生效。

## 在 Mac 上一次执行
在已经克隆、更新到 main 的 ooglex-site 工程目录运行：

```bash
python3 -m scripts.capture_asset_compass_bls_batch_v35 \
  --private-dir "$HOME/.local/share/ooglex/private-historical-evidence" \
  --output /tmp/ooglex-v36-capture-receipts.json \
  --fail-if-incomplete
```

运行结束将生成三个来源的结果，以及本地 `custody-v36.jsonl`；如有 BLS 拒绝连接，只有真实成功下载的项目可以入账，失败结果按实际报错。

以后只读复核，不重新下载：
```bash
python3 -m scripts.verify_asset_compass_private_custody_v36 \
  --private-dir "$HOME/.local/share/ooglex/private-historical-evidence" \
  --output /tmp/ooglex-v36-custody-check.json
```

上面仅验证此前捕获内容，自身不能赋予新闻稿的 original published-at / historically available-at 资格。BLS/CPI 和其他13个宏观源的回测资格仍须在独立发布材料、数据许可、资产总回报及样本外检验后审核；正式六资产0–100评分和交易提醒继续关闭。

## GitHub 门禁验收
新增13项离线保管测试，覆盖篡改、断链、重复、原件消失、目录/文件权限过宽、伪造PIT资格、来源不符与失败项。正式研究门禁纳入这些测试，且继续强制 `score=None`。
