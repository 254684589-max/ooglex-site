# 环球TV · HLS 直播代理部署指南

让 **Chrome / 安卓**（用 hls.js 播直播）也能看更多台：这个 Cloudflare Worker 替浏览器
抓取 HLS 流并补上跨域（CORS）头，解决「源不带 CORS → 网页里黑屏/一直缓冲」的问题。

> 苹果 Safari 有原生 HLS、不受 CORS 限制，**不需要**代理，网页端会自动直连、不走代理省流量。

## 先看清楚它能解决什么、不能解决什么

- ✅ 解决 **Chrome/安卓 因跨域（CORS）黑屏**：这是网页播直播最主要的拦路虎。
- ⚠️ **不解决地域封锁**：Worker 跑在 Cloudflare 境外边缘。
  - 看**境外台**：代理能补 CORS，边缘也连得到源，通常有改善（但国内↔Cloudflare 链路快慢不定）。
  - 看**国内台（CCTV 等）**：请求要绕一圈境外边缘再回国内源，**可能反而更慢、甚至被源站拒绝境外 IP**。国内台仍以「直连能通」为主。
- 💸 **耗流量**：直播视频每几秒拉一个切片，都会过代理。Cloudflare Workers 免费版每天 10 万次请求，人一多就会触顶。

## 自动部署（推荐：一次配置，以后永不手动）

仓库已带 `.github/workflows/deploy-tv-proxy.yml`：main 分支上 `worker.js` / `wrangler.toml`
有改动就自动 `wrangler deploy`。只需一次性配好 API Token：

1. **创建 Cloudflare API Token**：
   [dash.cloudflare.com](https://dash.cloudflare.com) → 右上角头像 → **My Profile → API Tokens →
   Create Token** → 选模板 **Edit Cloudflare Workers** → 按默认生成，复制 Token。
2. **加到仓库 Secrets**：GitHub 仓库 → **Settings → Secrets and variables → Actions →
   New repository secret**，名字填 `CLOUDFLARE_API_TOKEN`，值粘贴刚才的 Token。
3. **首次部署**：Actions 页面 → **Deploy TV Proxy** → **Run workflow** 跑一次即可。
   之后每次 worker 代码有改动合入 main 都会自动部署。

可选 Secrets（一般不用配）：
- `CLOUDFLARE_ACCOUNT_ID`：Token 能访问多个 Cloudflare 账号时才需要。
- `CLOUDFLARE_KV_QUOTA_ID`：想启用每 IP 每日限额时，填 KV 命名空间的 id
  （`wrangler kv namespace create QUOTA` 的输出）；不配则按无限额模式部署。

## 手动部署（备选，约 10 分钟）

需要一个 [Cloudflare](https://dash.cloudflare.com) 账号（免费版即可）。

1. **装 wrangler 并登录**
   ```bash
   npm install -g wrangler
   cd workers/tv-proxy
   wrangler login
   ```

2. **（可选）创建限额计数用的 KV**，把输出的 `id` 填进 `wrangler.toml` 的 `[[kv_namespaces]]`：
   ```bash
   wrangler kv namespace create QUOTA
   ```
   不想要限额，就把 `wrangler.toml` 里整段 `[[kv_namespaces]]` 删掉。

3. **部署**
   ```bash
   wrangler deploy      # 输出形如 https://ooglex-tv-proxy.<你的子域>.workers.dev
   ```

4. **让网页用上它**：把上一步的地址填进 `apps/tv/proxy.json`：
   ```json
   { "hls": "https://ooglex-tv-proxy.你的子域.workers.dev" }
   ```
   提交推送后（GitHub Pages 部署完），Chrome/安卓打开环球TV 就会自动走代理。
   留空 `""` 则关闭代理、维持直连行为。

## 强烈建议：绑自定义域名（否则国内可能连不上代理本身）

`*.workers.dev` 域名在国内经常被墙/不稳，那样代理本身就打不开。建议把 Worker
绑到一个**国内可达的自有域名**（比如 `tv-proxy.ooglex.com`）：

- Cloudflare 面板 → Workers & Pages → 你的 Worker → **Settings → Domains & Routes → Add Custom Domain**
- 前提是该域名托管在 Cloudflare。绑好后把 `proxy.json` 的 `hls` 换成 `https://tv-proxy.ooglex.com`。

> 你的站点主域 `ooglex.com` 在国内能正常打开，用它的子域做代理，国内可达性最好。

## 已部署过的注意：升级后要重新 deploy 一次

频道库现在会收录**无 `.m3u8` 后缀**的 HLS 清单（前端走代理时会带 `?m3u8=1` 提示参数，
Worker 据此改写清单）。旧版 Worker 不认识这个参数——已部署过的请按上面「自动部署」
配好 Token 后跑一次 **Deploy TV Proxy** 工作流（或本地重新 `wrangler deploy`），
否则这类源走代理会失败（其余源不受影响）。

## 安全与限额

- 只有 `ALLOWED_ORIGINS` 列出的页面来源能调用（校验 Origin/Referer），别的站点/直连一律 403，防止被白嫖带宽。
- 禁止代理内网/环回地址（防 SSRF）。
- 配了 KV 时按每 IP 每日 `DAILY_LIMIT` 抽样限额。
- 想改额度/来源：编辑 `wrangler.toml` 的 `[vars]` 后重新 `wrangler deploy`。
