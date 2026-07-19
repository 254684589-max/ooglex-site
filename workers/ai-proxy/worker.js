/* 万象智聊 · 共享通道代理（Cloudflare Worker）
   作用：持有站长的 API 密钥，替网站访客转发大模型请求，访客零配置开聊。
   防滥用：
     · 模型锁定为免费模型（body.model 被强制覆盖），密钥只在 Worker 侧
     · 每 IP 每日限额（KV 计数，默认 30 次）
     · CORS 白名单，只允许本站页面调用
     · 历史裁剪到最近 24 条，避免超长上下文烧额度 */

const JSON_HEADERS = { 'Content-Type': 'application/json; charset=utf-8' };

function json(obj, status, cors) {
  return new Response(JSON.stringify(obj), { status, headers: { ...JSON_HEADERS, ...cors } });
}

export default {
  async fetch(req, env) {
    const allow = (env.ALLOWED_ORIGINS || 'https://www.ooglex.com,https://ooglex.com')
      .split(',').map(s => s.trim()).filter(Boolean);
    const origin = req.headers.get('Origin') || '';
    const cors = {
      'Access-Control-Allow-Origin': allow.includes(origin) ? origin : allow[0],
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Access-Control-Max-Age': '86400',
    };
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });

    if (req.method !== 'POST' || !new URL(req.url).pathname.endsWith('/chat/completions')) {
      return json({ error: { message: 'not found' } }, 404, cors);
    }
    if (!env.API_KEY) {
      return json({ error: { message: '代理未配置密钥（wrangler secret put API_KEY）' } }, 500, cors);
    }

    // ---- 每 IP 每日限额 ----
    const limit = parseInt(env.DAILY_LIMIT || '30', 10);
    const ip = req.headers.get('CF-Connecting-IP') || 'unknown';
    const day = new Date().toISOString().slice(0, 10);
    const quotaKey = `q:${day}:${ip}`;
    if (env.QUOTA) {
      const used = parseInt((await env.QUOTA.get(quotaKey)) || '0', 10);
      if (used >= limit) {
        return json({ error: { code: 'daily_limit', message: `今日共享额度（${limit} 次）已用完，明天再来，或在设置里接入自己的密钥/本地模型～` } }, 429, cors);
      }
      await env.QUOTA.put(quotaKey, String(used + 1), { expirationTtl: 86400 * 2 });
    }

    // ---- 组装并转发 ----
    let body;
    try { body = await req.json(); } catch (e) {
      return json({ error: { message: 'invalid json' } }, 400, cors);
    }
    body.model = env.MODEL || 'glm-4-flash';          // 锁定免费模型，防止换模型烧钱
    if (Array.isArray(body.messages)) body.messages = body.messages.slice(-24);
    delete body.max_tokens;                            // 交给上游默认值
    const upstreamBase = (env.UPSTREAM || 'https://open.bigmodel.cn/api/paas/v4').replace(/\/+$/, '');

    const upstream = await fetch(upstreamBase + '/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + env.API_KEY },
      body: JSON.stringify(body),
    });

    // 流式响应原样透传（SSE），非流式也一样处理
    return new Response(upstream.body, {
      status: upstream.status,
      headers: {
        ...cors,
        'Content-Type': upstream.headers.get('Content-Type') || 'application/json',
        'Cache-Control': 'no-store',
      },
    });
  },
};
