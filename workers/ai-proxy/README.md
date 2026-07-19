# 万象智聊 · 共享通道代理部署指南

让网站访客**零配置**直接和 AI 聊天：这个 Cloudflare Worker 持有你的
API 密钥（访客拿不到），转发聊天请求并做好防滥用。全程用免费资源：
Cloudflare Workers 免费版（每天 10 万次请求）+ 智谱 glm-4-flash（免费模型）。

## 部署步骤（约 10 分钟，一次性）

1. **申请智谱密钥**（免费）：注册 [open.bigmodel.cn](https://open.bigmodel.cn)
   → 控制台 → API 密钥，复制备用。glm-4-flash 模型免费。

2. **装 wrangler 并登录**（需要 [Cloudflare](https://dash.cloudflare.com) 账号，免费版即可）：

   ```bash
   npm install -g wrangler
   cd workers/ai-proxy
   wrangler login
   ```

3. **创建限额计数用的 KV 命名空间**，把输出的 `id` 填进 `wrangler.toml`：

   ```bash
   wrangler kv namespace create QUOTA
   ```

4. **设置密钥并部署**：

   ```bash
   wrangler secret put API_KEY   # 粘贴第 1 步的智谱密钥
   wrangler deploy               # 输出形如 https://ooglex-ai-proxy.xxx.workers.dev
   ```

5. **开通前端**：编辑 `apps/ai-chat/shared-config.json`：

   ```json
   {
     "enabled": true,
     "base": "https://ooglex-ai-proxy.xxx.workers.dev/v1",
     "model": "glm-4-flash"
   }
   ```

   提交推送后，新访客打开万象智聊即默认走共享通道，无需任何配置。

## 防滥用设计

| 措施 | 说明 |
| --- | --- |
| 模型锁定 | 请求里的 `model` 被强制覆盖为免费模型，别人拿代理也烧不了钱 |
| 每日限额 | 每 IP 每天 `DAILY_LIMIT`（默认 30）次，KV 计数自动过期 |
| CORS 白名单 | 只允许 `ALLOWED_ORIGINS` 里的页面调用 |
| 历史裁剪 | 上下文最多 24 条，防止超长请求 |
| 密钥隔离 | 密钥存在 Worker Secret，前端与仓库中都不出现 |

限额用完时 Worker 返回 429，前端会自动降级（本地模型 → 离线小智）并提示。

## 可选调整

- 换上游/模型：改 `wrangler.toml` 的 `UPSTREAM` / `MODEL`（任何 OpenAI 兼容接口都行）
- 调限额：改 `DAILY_LIMIT` 后重新 `wrangler deploy`
- 自定义域名：在 Cloudflare 控制台给 Worker 绑一个子域（如 `ai.ooglex.com`），
  国内访问 `workers.dev` 域名偶有不稳，绑自有域名更可靠
