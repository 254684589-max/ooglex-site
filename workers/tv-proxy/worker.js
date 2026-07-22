/* 环球TV · HLS 直播代理（Cloudflare Worker）
   作用：替浏览器抓取 HLS 直播流并补上 CORS 头 —— 解决 Chrome / 安卓用 hls.js 播直播时，
   因电视源不带跨域许可（Access-Control-Allow-Origin）而黑屏/一直缓冲的问题。
   （苹果 Safari 有原生 HLS、不受 CORS 限制，网页端不会走这个代理。）

   用法：GET  https://<worker>/?url=<encodeURIComponent(上游 m3u8 或 ts 地址)>
     · m3u8 会被改写：把里面的子清单 / 切片 / 密钥地址也改成走本代理，hls.js 才能连贯取流
     · 所有响应都加上 Access-Control-Allow-Origin

   防滥用：
     · 只允许白名单来源（Referer / Origin 命中本站）调用，其它一律 403
     · 禁止代理内网 / 环回地址（防 SSRF）
     · 每 IP 每日请求限额（可选 KV，直播切片请求多，额度给大些）

   注意：直播视频走代理很耗流量；Cloudflare Workers 免费版每天 10 万次请求。
   国内可达性取决于把本 Worker 绑到哪个域名（建议自定义域名，见 README）。 */

const DEFAULT_ALLOWED = 'https://www.ooglex.com,https://ooglex.com';

function isPrivateHost(host) {
  if (!host) return true;
  host = host.toLowerCase().replace(/^\[|\]$/g, '');
  if (host === 'localhost' || host.endsWith('.local') || host.endsWith('.internal')) return true;
  if (host === '::1') return true;
  if (/^127\./.test(host) || /^10\./.test(host) || /^192\.168\./.test(host) || /^169\.254\./.test(host) || /^0\./.test(host)) return true;
  if (/^172\.(1[6-9]|2\d|3[0-1])\./.test(host)) return true;
  if (/^(fc|fd)[0-9a-f]{2}:/.test(host) || /^fe80:/.test(host)) return true;   // IPv6 私网/链路本地
  return false;
}

function corsHeaders(env, req) {
  const allow = (env.ALLOWED_ORIGINS || DEFAULT_ALLOWED).split(',').map(s => s.trim()).filter(Boolean);
  const origin = req.headers.get('Origin') || '';
  return {
    'Access-Control-Allow-Origin': allow.includes(origin) ? origin : '*',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Range, Content-Type',
    'Access-Control-Expose-Headers': 'Content-Length, Content-Range, Accept-Ranges',
    'Access-Control-Max-Age': '86400',
  };
}

function rewriteManifest(text, baseUrl, proxyOrigin) {
  const abs = (u) => { try { return new URL(u, baseUrl).toString(); } catch (e) { return u; } };
  const prox = (u) => proxyOrigin + '/?url=' + encodeURIComponent(abs(u));
  return text.split(/\r?\n/).map((line) => {
    const t = line.trim();
    if (!t) return line;
    if (t.startsWith('#')) {
      // 改写标签内的 URI="..."（#EXT-X-KEY / #EXT-X-MEDIA / #EXT-X-MAP / #EXT-X-I-FRAME-STREAM-INF）
      return line.replace(/URI="([^"]+)"/g, (_m, u) => `URI="${prox(u)}"`);
    }
    return prox(t);   // 切片 / 子清单地址
  }).join('\n');
}

export default {
  async fetch(req, env) {
    const cors = corsHeaders(env, req);
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (req.method !== 'GET') return new Response('method not allowed', { status: 405, headers: cors });

    const reqUrl = new URL(req.url);
    const target = reqUrl.searchParams.get('url');
    if (!target) return new Response('missing ?url', { status: 400, headers: cors });

    // 来源白名单：只允许本站页面调用
    const allow = (env.ALLOWED_ORIGINS || DEFAULT_ALLOWED).split(',').map(s => s.trim()).filter(Boolean);
    const origin = req.headers.get('Origin') || '';
    const referer = req.headers.get('Referer') || '';
    const okOrigin = origin && allow.includes(origin);
    const okReferer = referer && allow.some((a) => referer.startsWith(a));
    if (!okOrigin && !okReferer) return new Response('forbidden', { status: 403, headers: cors });

    let tu;
    try { tu = new URL(target); } catch (e) { return new Response('bad url', { status: 400, headers: cors }); }
    if (!/^https?:$/.test(tu.protocol) || isPrivateHost(tu.hostname)) {
      return new Response('blocked target', { status: 400, headers: cors });
    }

    // 每 IP 每日限额（抽样计数，避免每个切片都写 KV）
    if (env.QUOTA) {
      const limit = parseInt(env.DAILY_LIMIT || '20000', 10);
      const ip = req.headers.get('CF-Connecting-IP') || 'unknown';
      const key = `q:${new Date().toISOString().slice(0, 10)}:${ip}`;
      const used = parseInt((await env.QUOTA.get(key)) || '0', 10);
      if (used >= limit) return new Response('daily limit reached', { status: 429, headers: cors });
      if (Math.random() < 0.05) {
        await env.QUOTA.put(key, String(used + 20), { expirationTtl: 172800 }).catch(() => {});
      }
    }

    // 抓上游（带浏览器 UA；Referer 指向上游自身域，绕过部分防盗链）
    const fwd = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
      'Referer': tu.origin + '/',
      'Accept': '*/*',
    };
    const range = req.headers.get('Range');
    if (range) fwd['Range'] = range;

    let up;
    try {
      up = await fetch(tu.toString(), { headers: fwd, redirect: 'follow' });
    } catch (e) {
      return new Response('upstream error: ' + e.message, { status: 502, headers: cors });
    }

    const ct = (up.headers.get('Content-Type') || '').toLowerCase();
    const isManifest = /mpegurl|vnd\.apple/.test(ct) || /\.m3u8($|\?)/i.test(tu.pathname + tu.search);

    if (isManifest) {
      const text = await up.text();
      const body = rewriteManifest(text, tu.toString(), reqUrl.origin);
      return new Response(body, {
        status: up.status,
        headers: { ...cors, 'Content-Type': 'application/vnd.apple.mpegurl; charset=utf-8', 'Cache-Control': 'no-store' },
      });
    }

    // 切片 / 密钥 / 其它：流式透传 + CORS
    const h = new Headers(cors);
    for (const k of ['Content-Type', 'Content-Length', 'Content-Range', 'Accept-Ranges', 'Cache-Control']) {
      const v = up.headers.get(k);
      if (v) h.set(k, v);
    }
    return new Response(up.body, { status: up.status, headers: h });
  },
};
