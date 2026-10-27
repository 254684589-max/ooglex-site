# Jamendo 曲目目录代理

流光播放器「全球曲库」（`/apps/music-player/#/global`）用的查询接口。只转发 Jamendo API v3.0 的 `/tracks` 只读查询，返回裁剪后的曲目目录。**不转发、不缓存音频**：浏览器直接从 Jamendo 服务器播放，本站和本 Worker 都不存音频。

## 为什么需要它

- Jamendo 的 `client_id` 放在 Cloudflare Secret，不写进前端和仓库
- 边缘缓存 30 分钟：同一曲风、同一页只消耗一次 Jamendo 配额
- 只认本站页面来源；每 IP 每分钟 30 次、每天 600 次
- 上游超时 8 秒；错误统一成 `{status:"error", error, message}`，不外传 Jamendo 原文
- 只放行 `jamendo.com` 的音频和封面、`creativecommons.org` 的许可链接；没有可播音频或许可链接的曲目整条丢掉

## 接口

`GET /tracks?tag=pop&order=popular&offset=0&q=`

| 参数 | 取值 |
|---|---|
| `tag` | 曲风标签，2–16 位小写字母；空 = 全部 |
| `order` | `popular`（近一月热门，默认）、`week`（本周热门）、`new`（最新发布） |
| `offset` | 0–980，20 的倍数 |
| `q` | 搜索歌名或艺人，最多 40 字 |

返回：`source`、`sourceUrl`、`updatedAt`（查询时间，UTC）、`frequency: "on-demand"`、`status`（`ok` / `partial` / `empty`）、`hasMore`、`tracks[]`（`id`、`title`、`artist`、`album`、`durationSec`、`image`、`src`、`license`、`page`）。

`GET /health` 返回 `{ ok, proxy, configured }`，`configured` 表示是否已设置 client_id。

## 许可与费用（部署前必读）

- **Jamendo API 条款：非商业使用免费，商业使用需另购授权**（licensing@jamendo.com）。条款把广告收入也算作商业用途。ooglex 主站部分页面投放了 Google AdSense；流光播放器页面没有广告。**站长已于 2026-10-27 确认本项目按非商业用途使用。** 为保持这一前提：播放器页（含 `#/global`）和 APK 不加广告、不收费；以后若要在这里投放广告或收费，先向 Jamendo 购买商业授权。
- 每首曲目有自己的 Creative Commons 许可（可能是 BY、BY-NC、BY-NC-SA、BY-ND 等）。页面逐首显示许可并链接到许可文本与 Jamendo 曲目页。
- Jamendo 开户邮件（2026-10-27）写明：应用访问量超过 50 万次可能被限制访问，直到提供项目信息。边缘缓存用来压低消耗。
- Cloudflare Workers 免费版每天 10 万次请求。音频不经过 Worker，不耗 Worker 流量。

## 部署（站长操作）

### Jamendo 侧

1. 打开开户邮件里的激活链接，激活账号。
2. devportal.jamendo.com →「应用程序」→ 你的应用：
   - 复制 **Client ID**（不是 Client Secret；本接口只用 Client ID）
   - 用途状态选 **非商业**
   - 「描述」填应用链接：`https://www.ooglex.com/apps/music-player/#/global`
   - 「账户」里补全联系信息

### 部署 Worker（GitHub Actions，不用命令行）

1. 仓库 Settings → Secrets and variables → Actions → New repository secret，名字 `JAMENDO_CLIENT_ID`，值为 Client ID。`CLOUDFLARE_API_TOKEN` 已经存在，与其他 Worker 共用。
2. 本目录合并进 main 后，「Deploy Jamendo proxy」工作流自动运行；之后也可在 Actions 页手动运行。它会跑测试、部署、把 client_id 写进 Worker Secret，并试查一次 `/tracks?tag=pop`。
3. 在运行摘要里拿到地址（形如 `https://ooglex-jamendo-proxy.<子域>.workers.dev`），填进 `apps/music-player/data/global.json` 的 `api`（不带结尾斜杠），提交后页面即开通。

### 备选：本机命令行

```bash
cd workers/jamendo-proxy
wrangler login
wrangler secret put JAMENDO_CLIENT_ID   # 粘贴 client_id，不要写进任何文件
wrangler deploy
curl -H 'Origin: https://www.ooglex.com' https://<地址>/health   # 应返回 "configured":true
```

## 回退

- 关闭全球曲库：把 `global.json` 的 `api` 改回 `""`，页面显示「尚未开通」，本站原创专辑不受影响。
- 删除接口：`wrangler delete ooglex-jamendo-proxy`，并删除 `.github/workflows/deploy-jamendo-proxy.yml`。

## 测试

```bash
cd workers/jamendo-proxy
node --test worker.test.mjs
```
