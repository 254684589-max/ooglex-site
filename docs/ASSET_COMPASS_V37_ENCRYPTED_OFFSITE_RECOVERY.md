# Ooglex 全球资产罗盘 V37｜加密备份、Cloudflare R2 异地保存与实测恢复

## 真正实现了什么
此前 V36 的 `custody-v36.jsonl`、三期原始BLS HTML 仅能在实际执行本地抓取后存在，且没有异地备份。V37 将**已经存在且校验通过**的私人原件与日志封装为加密文件，并提供远端R2上传/下载、远端字节读回及异地灾备恢复校验。GitHub Actions不会替用户创建云端凭据或代传私人原件。

- 加密：`scripts/backup_asset_compass_private_v37.py` 使用 scrypt 密钥派生（随机16B salt，N=16384）和 AES-256-GCM 认证加密（随机12B nonce）。封装文件仅包含密文、随机salt和nonce，不在仓库中存储密码、明文、原件或 SQLite。出于敏感性与大文件限制，仅供现有少量新闻稿试点（明文上限32MB），**不是完整宏观数据仓库快照**。
- 备份前重新执行 V36 `verify_journal`，任何篡改、缺失文件、权限过宽或空的保管日志直接失败。
- 恢复只允许**尚不存在**的目标目录；解密后重建权限0700/0600，调用 V36 检查日志链、原件SHA-256、大小及来源登记，再宣布恢复通过。口令错误、密文改动、原件缺失都会失败，不覆盖旧目录。
- Cloudflare R2（可选）：`scripts/sync_asset_compass_r2_v37.py` 仅能上传 V37 加密封装，强制 `https://<账户ID>.r2.cloudflarestorage.com`、私有桶和 `ooglex-private/v37/*.enc` 键；上传后再从R2读取比对SHA256和字节，下载也核对远端记录的SHA256。不提供公共下载链接、不改桶权限。
- **未实际提供R2账号ID、S3密钥和私有桶**，因此任何通过CI的模拟R2测试只能证明程序逻辑，不能证明云端已存有正式备份。

## Mac 一次性准备
建议将密码保管在独立密码管理器。以下命令只建立隔离Python环境，不会自动采集或备份真实文件。

```bash
python3 -m venv "$HOME/.local/share/ooglex/v37-venv"
"$HOME/.local/share/ooglex/v37-venv/bin/python" -m pip install 'cryptography==46.0.4' boto3
```

你已经在本机创建了 V36 私人原件及日志后，可运行：
```bash
cd /Users/mac/Developer/ooglex-site
read -s "OOGLEX_BACKUP_PASSPHRASE?备份密码（至少16字符）: "
export OOGLEX_BACKUP_PASSPHRASE
"$HOME/.local/share/ooglex/v37-venv/bin/python" -m scripts.backup_asset_compass_private_v37 backup \
  --private-dir "$HOME/.local/share/ooglex/private-historical-evidence" \
  --output "$HOME/.local/share/ooglex/bls-evidence-20261122.enc"
unset OOGLEX_BACKUP_PASSPHRASE
```

注意：如果本地V36原件从未真实抓取，备份会明确失败，不会生成空的假备份。备份密码丢失后无法恢复密文；要保存密码离线副本。

## 可选R2上传和恢复验收
需要在Cloudflare R2创建 **私有** S3兼容API Token 和私有 bucket，预先配置环境变量 `CLOUDFLARE_ACCOUNT_ID`、`OOGLEX_R2_PRIVATE_BUCKET`、`AWS_ACCESS_KEY_ID` 和 `AWS_SECRET_ACCESS_KEY`。不要复制到Git、聊天或命令历史，建议从密钥管理器注入。

```bash
"$HOME/.local/share/ooglex/v37-venv/bin/python" -m scripts.sync_asset_compass_r2_v37 upload \
  --archive "$HOME/.local/share/ooglex/bls-evidence-20261122.enc" \
  --key "ooglex-private/v37/bls-evidence-20261122.enc"

"$HOME/.local/share/ooglex/v37-venv/bin/python" -m scripts.sync_asset_compass_r2_v37 download \
  --key "ooglex-private/v37/bls-evidence-20261122.enc" \
  --output "$HOME/.local/share/ooglex/bls-evidence-remote-check.enc"
```

下载后，在备份密码仍可用时，执行恢复（此时密码通过 `OOGLEX_BACKUP_PASSPHRASE` 注入）：
```bash
"$HOME/.local/share/ooglex/v37-venv/bin/python" -m scripts.backup_asset_compass_private_v37 restore \
  --archive "$HOME/.local/share/ooglex/bls-evidence-remote-check.enc" \
  --target "$HOME/.local/share/ooglex/restored-evidence-test"
```

只有上传远端、读取校验成功、独立目录恢复成功且 V36 原件哈希核验全通过后，才算建立可恢复的 **异地加密备份**。不表示R2具有对象锁、永久保留或异地多活；有关版本管理及防删除策略仍需单独设置。

## 安全边界
- 加密备份和事后哈希复核不证明BLS在2025年某一天、某一分钟已向市场公开**完全相同**的网页版本。
- 不确认发布许可，不提供 historical available-at，绝不把私人保管日志转成经认证的历史 PIT vintage。
- 宏观数据当前覆盖为14/14，已独立认证PIT系列仍为0/14；六资产正式0–100评分、历史回测和投资提醒保持关闭。
- GitHub CI只运行虚拟的加解密和模拟R2对象存储测试，不会访问用户电脑的证据、密码或云端账户。
