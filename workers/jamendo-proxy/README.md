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

- **Jamendo API 条款：非商业使用免费，商业使用需另购授权**（licensing@jamendo.com）。条款把广告收入也算作商业用途。ooglex 主站部分页面投放了 Google AdSense；流光播放器页面目前没有广告。**是否属于非商业使用由站长判断**；如不确定，先联系 Jamendo。
- 每首曲目有自己的 Creative Commons 许可（可能是 BY、BY-NC、BY-NC-SA、BY-ND 等）。页面逐首显示许可并链接到许可文本与 Jamendo 曲目页。
- 第三方资料称非商业应用每月约 35,000 次 API 请求，Jamendo 官方页面未能核实。边缘缓存用来压低消耗。
- Cloudflare Workers 免费版每天 10 万次请求。音频不经过 Worker，不耗 Worker 流量。

## 部署（站长操作，本仓库不会自动部署）

1. 在 [Jamendo 开发者门户](https://devportal.jamendo.com/) 注册应用，拿到 `client_id`。
2. 部署：
   ```bash
   cd workers/jamendo-proxy
   wrangler login
   wrangler secret put JAMENDO_CLIENT_ID   # 粘贴 client_id，不要写进任何文件
   wrangler deploy                         # 输出 https://ooglex-jamendo-proxy.<子域>.workers.dev
   ```
3. 自检：`curl -H 'Origin: https://www.ooglex.com' https://<地址>/health` 应返回 `"configured":true`。
4. 把地址填进 `apps/music-player/data/global.json` 的 `api`（不带结尾斜杠），提交后页面即开通。

## 回退

- 关闭全球曲库：把 `global.json` 的 `api` 改回 `""`，页面显示「尚未开通」，本站原创专辑不受影响。
- 删除接口：`wrangler delete ooglex-jamendo-proxy`。

## 测试

```bash
cd workers/jamendo-proxy
node --test worker.test.mjs
```
