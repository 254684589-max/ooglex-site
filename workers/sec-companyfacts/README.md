# SEC companyfacts 代理

给财务桑基页用的 Cloudflare Worker。浏览器打开任意美股代码时，由这里代为请求 SEC 公开的 companyfacts，并补上 User-Agent 和 CORS。

不抓付费站，不需要 API key，不转发调用方传入的任意 URL。

## 为什么不是挂在 www 上

`www.ooglex.com` 的 NS 在 Cloudflare，但主机记录是灰云，CNAME 到 GitHub Pages，响应头是 `server: GitHub.com`。Worker Routes 只有橙云（流量经过 Cloudflare）才会触发。把 `www` 改成橙云会让整个主站改道，这次不做。

现有可用的做法是 `pro-api.ooglex.com` 那种自定义域名。本 Worker 部署后地址是：

`https://sec-facts.ooglex.com/companyfacts/CIK##########.json`

页面同时会先试同源路径：

`/apps/financial-sankey/companyfacts/CIK##########.json`

Worker 两条都认识。灰云期间同源这一条由 GitHub Pages 返回 404，页面再请求上面的边缘域名。

## 上游

只请求：

`https://data.sec.gov/api/xbrl/companyfacts/CIK` + 10 位 CIK + `.json`

User-Agent：

`Ooglex financial-sankey (https://www.ooglex.com/apps/financial-sankey/; <SEC_CONTACT 或站点 URL>)`

`SEC_CONTACT` 用仓库已有的 Actions 变量（与基本面、产业链相同）。工作流把它写成 Worker Secret，不写进 Git，也不在日志里打印。

## 频率和缓存

| 限制 | 值 |
|---|---|
| 每个 IP 每分钟 | 20 次（含缓存命中） |
| 每个 IP 每天 | 120 次 |
| 打到 SEC 的间隔 | 每个隔离实例至少 1 秒 |
| 打到 SEC 的上限 | 每个隔离实例每分钟 20 次 |
| 成功响应缓存 | 6 小时 |

计数在单个 Worker 隔离实例的内存里，不是全机房共享的精确配额。6 小时缓存让同一个 CIK 不会被反复拉取。返回 429 时页面用中文提示稍后再试；NVDA / MSFT 仍可退回仓库里的摘录。

`GET /health` 只返回 `{ "ok": true, "proxy": "sec-companyfacts" }`，不访问 SEC。

## 部署

合并到 `main` 且 `workers/sec-companyfacts/` 有改动时，`.github/workflows/deploy-sec-companyfacts.yml` 会 `wrangler deploy`。

需要：

- 已有的 `CLOUDFLARE_API_TOKEN`（环球 TV、PRO API 已经在用）
- 可选：`CLOUDFLARE_ACCOUNT_ID`（令牌能看到多个账号时）
- 可选但建议：仓库变量 `SEC_CONTACT`

不需要新的付费套餐，也不要为了这条代理把 `www` 改成橙云。部署成功后 Cloudflare 会在现有区内加上 `sec-facts.ooglex.com`。

回退：把 `apps/financial-sankey/proxy.json` 的 `companyfacts` 改成 `""` 并发布页面，浏览器就不再请求边缘域名，回到直连失败后的 NVDA / MSFT 摘录。Worker 本身可以在 Cloudflare 面板删除；删掉后页面仍能打开。

## 本地验收

```bash
node --test workers/sec-companyfacts/worker.test.mjs
node apps/financial-sankey/model.test.js
node apps/financial-sankey/proxy.test.js
node workers/sec-companyfacts/smoke.mjs
node workers/sec-companyfacts/dev-server.mjs
```

`smoke.mjs` 会向 SEC 请求 AAPL 和 BAC 各一次，请不要放进定时任务。开发服务器只监听 `127.0.0.1`，把同源路径接到这个 Worker，然后打开：

`http://127.0.0.1:8765/apps/financial-sankey/?ticker=AAPL`
