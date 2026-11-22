# Ooglex 全球资产罗盘 V38｜真实加密异地备份一键验收

## 目标与边界
V37 已通过软件离线测试，但不能确认用户 Mac 上实际存在 BLS 原件或 Cloudflare R2 私有桶、S3 凭据和备份对象。V38 提供 **单一分阶段操作入口**，真实执行需要明确权限的动作，逐项留下审计结论，并在任何一步失败时停止下一步。

**不会替用户远程访问 Mac、自动读取私人密钥、创建 R2 Bucket，或假装已完成异地备份。**

## V38 分阶段真实验收
1. `--capture` 指令才实际下载3个官方 BLS CPI 历史新闻稿（2024年12月、2025年1月和2月发布期对应档案），放入 Mac 私人目录。任意下载失败将产生明确失败状态；只对真实文件记录 V36 私人哈希日志。
2. 无论是否选择下载，都必须从本地实际原件和 `custody-v36.jsonl` 校验文件 SHA-256、来源URL和哈希链；**没有私人原件时不允许制作空备份**。
3. 使用 V37 已验证的 AES-256-GCM+scrypt 将原件和哈希链加密存档到**另一私人目录**，名称含真实 UTC 时间和随机后缀，避免覆盖旧备份。随后自动解密到临时独立目录，重新验证原件及哈希链。
4. 只有明确传递 `--offsite`，才读取用户提供的 R2 私有桶和 S3 兼容凭据：上传**加密文件**，GET 远端返回的密文字节与源文件逐字节比对；重新下载并在新的隔离目录恢复，复核哈希链是否一致。
5. 所有阶段生成无密钥、无HTML正文的 JSON 结果 `/tmp/ooglex-v38-acceptance.json`。只有 `status=offsite_recovery_verified` 且 `offsite_copy_verified=true`、`offsite_restore_verified=true` 才能认定实测异地恢复成功；没有 `--offsite` 即使本地成功也必须显示 `local_recovery_verified_only`。

## 最少人工操作
在 **已 clone 并更新至最新 main 的 Ooglex 仓库**打开 Mac 终端，第一次运行联网取得3份 BLS 原件并做完整本地加密恢复：

```bash
bash scripts/run_asset_compass_v38.sh --capture
```

脚本会在私人家目录建立虚拟环境并安装 `cryptography` 和 `boto3`（仅首次或未安装时），加密口令会通过终端隐藏提示输入。**密码至少16字符；不要把密码、Cloudflare S3 Token或API密钥贴在聊天、提交到Git、写入脚本。**

如果已在自己账号配置一个私有Cloudflare R2 bucket和以下环境变量：
`CLOUDFLARE_ACCOUNT_ID`、`OOGLEX_R2_PRIVATE_BUCKET`、`AWS_ACCESS_KEY_ID`、`AWS_SECRET_ACCESS_KEY`，可以显式运行：

```bash
bash scripts/run_asset_compass_v38.sh --offsite
```

这条命令使用之前真实保存的本地原件，先执行本地加密备份及恢复，再做 R2 上传、回读和独立恢复；不会再请求 BLS 网络接口。若必须一次完成两者，在这些云端凭据已经安全注入当前终端时使用：

```bash
bash scripts/run_asset_compass_v38.sh --capture --offsite
```

R2连接凭据缺失时 `--offsite` 会在上传前明确失败。**任何 R2 参数、对象路径、备份和恢复文件均不允许放进网站仓库**。

## 安全和真实性
- GitHub 研究门禁运行11项 V38 合成原件加密真实往返测试与模拟 R2 传输测试，不触及 Mac 和真实云端账户。
- R2的上传后GET校验、完整下载后再次解密恢复，都在 Mac 实际执行时才可确认；连接器的 GitHub 仓库访问权限不等于 Mac 本地和 R2 访问权限。
- 本方案并未配置 R2 对象锁、防删除、生命周期规则或额外存储版本管理；一份可读回的备份不代表备份能够永久保存。
- 真正历史 PIT 原始发布时刻、数据许可、当时可得历史值仍待逐一认证，严格保持 `eligible_for_point_in_time_backtest=false`、正式六资产评分及投资通知关闭。
- 当成功验收后再考虑 V39 对官方新闻稿正文中的原始CPI数值做可溯源抽取与人工复核，而不应把今天下载的历史网页直接当作当年真实 available_at 的证据。
