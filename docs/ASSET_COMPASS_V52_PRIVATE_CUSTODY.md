# Ooglex 全球资产罗盘｜V52 私有原始证据保管与恢复验收

## 阶段定位

V51 的 **7/7 官方网页成功获取**是当时执行器的短期下载行为，GitHub 只保留了30天的 SHA-256 元数据工件，**原始 HTML 并没有长期保管**。V52 的交付是专门为这7份 BLS/BEA 文档建立可实际执行的*私有字节保管链*与*加密异地恢复验收*。此阶段不会伪造任何原始发布时间、历史首次版本、真实修订状态、预测模型资格。

### 本阶段新增能力

1. 只允许使用 `data/asset-compass-v51-release-candidates.json` 中已明确发布来源的7个单期官方 URL；继续禁止合成2025年10月 BLS 未发布的 CPI/就业月报。
2. 在 **项目仓库之外**抓取原始网页，每份 `artifact_id + SHA-256` 保存成独立不可覆写版本文件；检测被替换的源文件、残缺下载、链接不匹配、源文件权限越界。
3. 保存 `v52-custody.jsonl` 哈希链，逐次记载捕获时刻、观测期、官方 URL、文件SHA-256及本地保管连续性；重复相同摘要标为 `same_html_bytes_rechecked`，不同摘要只标为 `changed_html_bytes_observed_not_certified_revision`，**不得自动称作官方修订**。
4. 保管日志和全部原始文件采用既有 V37 的 scrypt KDF + AES-256-GCM 逻辑认证加密；本地生成不覆盖旧文件的版本化备份，随后临时解密恢复、逐份原始字节及整条哈希链核验。
5. 用户明确配置私有 Cloudflare R2 凭证和 `--offsite` 后，可上传**加密文件而非明文**，读回原始密文、核对摘要、独立解密还原7份原始网页。R2对象上传使用条件写入，禁止复用同一Key覆盖已存证据；该验收仅证明执行时的私有异地副本有效，不等于R2具有法律意义的WORM锁定。
6. GitHub Actions V52 专用工作流仅接受手动触发，**未配置全部必要的私有加密和R2凭证会直接失败**，绝不落入“短期Runner下载后号称已永久保管”的假成功状态。不会上传原始网页或解密密码到公开GitHub Actions工件。
7. 全部研究门禁 V18–V52 继续执行；六资产正式评分、历史策略收益及自动投资预警继续关闭。

## 项目文件

- `scripts/asset_compass_custody_v52.py`：`capture` / `audit` / `backup` / `restore` 四类操作；可选加密R2往返及恢复验收。
- `scripts/run_asset_compass_v52.sh`：macOS 一条命令完成 7 源抓取、私有保存、哈希链审计、AES备份及恢复验证。
- `tests/test_asset_compass_custody_v52.py`：离线测试，覆盖重复抓取、字节改变、篡改、源不齐、私有目录、加密恢复、错误密码、R2回读及防覆盖。
- `.github/workflows/asset-compass-private-custody-v52.yml`：专用私有 R2 备份与恢复的手动触发运行，必须拥有配置的必要Secrets。
- `.github/workflows/asset-compass-research-gates.yml`：扩展至 V18–V52 全部研究质量门禁。

## 不超过一条命令：Mac 本地持久化

在 Ooglex 网站工程目录运行：

```bash
bash scripts/run_asset_compass_v52.sh
```

执行过程中仅需要输入一次长度至少16位的私有备份密码，不显示到终端。默认保存位置：

- 原始网页及哈希链：`~/.local/share/ooglex/private-historical-evidence/v52/`
- 加密备份：`~/.local/share/ooglex/private-backups/v52/`
- 不包含机密的简短验收报告：`/tmp/ooglex-v52-{capture,audit,backup}.json`

上述 **本地副本仍可能因电脑损坏/丢失而失效**。真正异地恢复要求经过配置的独立私有 R2 存储。

## 可选 R2 异地加密恢复

配置 `CLOUDFLARE_ACCOUNT_ID`、`OOGLEX_R2_PRIVATE_BUCKET`、`AWS_ACCESS_KEY_ID`、`AWS_SECRET_ACCESS_KEY` 后，执行：

```bash
bash scripts/run_asset_compass_v52.sh --offsite
```

需授权一个**私有 R2 存储桶**，不能绑定公开网站读取权限。脚本只向 `ooglex-private/v52/` 路径上传AES-GCM密文，并验证 R2 下载与恢复。不要在聊天、公开仓库、命令文本或截图里暴露明文凭证及密码。工程原有 V37 R2 通道仍能独立使用，V52 不会变更旧V37文件的格式。

GitHub 网页手动触发：Actions → `Asset Compass V52 Private Custody Recovery` → Run workflow。前提是仓库已安全配置 `OOGLEX_BACKUP_PASSPHRASE` 等五项 Secrets。未配置则明确失败、**不能标记已异地保管**。

## 必须区分的四种证据强度

| 级别 | V52 能否证明 | 具体含义 |
| --- | --- | --- |
| A. 抓取时字节完整性 | 是，实际执行并通过时 | SHA-256 与本地真实文件一致 |
| B. 抓取后本地连续保管 | 是，日志链完整且文件通过验收时 | 本地未发现篡改；单纯哈希链本身可以被有权限者重写 |
| C. 加密异地备份及恢复 | 只有 R2 readback 和恢复通过才是 | AES认证、私有R2往返、解密与原文件内容一致 |
| D. 官方历史首次公开可得性 | **否** | 今天抓到的HTML字节不证明其是历史最初版本，发布时间仍待独立审定 |

官方历史数据版本所需的 **精确发布日期及UTC时间、原始统计值/单位/季调口径、完整修订拓扑、独立审核和样本外检验**仍未完成。2025-10 未发布BLS报告也不应被后期合并刊载的指标替代成不存在的当期首发版本。

## V52 验收记录标准

仓库代码合并 / 单元测试通过 ≠ 原始字节已经永久保管。
只有实际执行 `capture`、`backup` 的 private 目录版，并验证 `local_restore_verified=true`，才宣称本地恢复成功。只有 `offsite_restore_verified=true` 才宣称私有异地恢复成功。若没有执行、没有配置密钥、或网络故障，必须标记未验证，不能代为填写成功状态。

**下一阶段 V53**：基于稳定保管的真实原文做结构化统计字段提取及双人（独立复核）核证；只有证明原始版本时点与历史变更内容，才可能逐期推进PIT证据审查。
