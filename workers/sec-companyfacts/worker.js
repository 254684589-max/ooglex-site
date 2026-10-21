/* SEC companyfacts 代理（Cloudflare Worker）
   只转发这一条公开地址：
   https://data.sec.gov/api/xbrl/companyfacts/CIK##########.json
   10 位 CIK。不接受调用方传入的任意 URL。

   浏览器不能改 User-Agent，data.sec.gov 也没有 CORS。
   本 Worker 在边缘补上声明身份的 User-Agent，并限制频率。

   主站 www.ooglex.com 是 Cloudflare 灰云上的 GitHub Pages，流量不经过
   Cloudflare，因此不能把路由挂在 www 的路径上。自定义域名
   sec-facts.ooglex.com 与现有 pro-api.ooglex.com 同一做法。
   Worker 同时认识同源路径 /apps/financial-sankey/companyfacts/CIK##########.json，
   以便以后若把 www 接到边缘，页面不用再改。 */

export const LIMITS = {
  perIpPerMinute: 20,
  perIpPerDay: 120,
  upstreamGapMs: 1000,
  upstreamPerMinute: 20,
  cacheSeconds: 6 * 60 * 60,
};

const DEFAULT_ALLOWED = "https://www.ooglex.com,https://ooglex.com";
const DEFAULT_CONTACT = "contact via https://www.ooglex.com/apps/financial-sankey/";
const PATH_RE = /^\/(?:apps\/financial-sankey\/)?companyfacts\/CIK(\d{10})\.json$/;

const buckets = createLimiterState();

export function createLimiterState() {
  return { ips: new Map(), upstreamAt: [], upstreamMinute: [] };
}

export function resetLimiter() {
  buckets.ips.clear();
  buckets.upstreamAt.length = 0;
  buckets.upstreamMinute.length = 0;
}

export function matchCik(pathname) {
  const match = PATH_RE.exec(pathname || "");
  return match ? match[1] : null;
}

export function upstreamUrl(cik) {
  return "https://data.sec.gov/api/xbrl/companyfacts/CIK" + cik + ".json";
}

export function secUserAgent(env) {
  const raw = String((env && env.SEC_CONTACT) || "").replace(/[\r\n]+/g, " ").trim();
  const contact = raw || DEFAULT_CONTACT;
  return "Ooglex financial-sankey (https://www.ooglex.com/apps/financial-sankey/; " + contact + ")";
}

export function originAllowed(origin, env) {
  if (!origin) return true;
  const allow = String((env && env.ALLOWED_ORIGINS) || DEFAULT_ALLOWED)
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  if (allow.includes(origin)) return true;
  try {
    const url = new URL(origin);
    const local = url.hostname === "127.0.0.1" || url.hostname === "localhost";
    if (local && (url.protocol === "http:" || url.protocol === "https:")) return true;
  } catch (error) {
    return false;
  }
  return false;
}

function prune(list, cutoff) {
  while (list.length && list[0] <= cutoff) list.shift();
}

function ipRecord(state, ip, now) {
  const day = new Date(now).toISOString().slice(0, 10);
  let record = state.ips.get(ip);
  if (!record || record.day !== day) {
    record = { day: day, dayCount: 0, minute: [] };
    state.ips.set(ip, record);
  }
  if (state.ips.size > 5000) {
    const oldest = state.ips.keys().next().value;
    if (oldest !== ip) state.ips.delete(oldest);
  }
  return record;
}

export function consumeIp(state, ip, now, limits) {
  const rules = limits || LIMITS;
  const record = ipRecord(state, ip, now);
  prune(record.minute, now - 60 * 1000);
  if (record.minute.length >= rules.perIpPerMinute) {
    return { ok: false, retryAfter: 60, scope: "ip_minute" };
  }
  if (record.dayCount >= rules.perIpPerDay) {
    return { ok: false, retryAfter: 3600, scope: "ip_day" };
  }
  record.minute.push(now);
  record.dayCount += 1;
  return { ok: true };
}

export function consumeUpstream(state, now, limits) {
  const rules = limits || LIMITS;
  prune(state.upstreamAt, now - rules.upstreamGapMs);
  prune(state.upstreamMinute, now - 60 * 1000);
  if (state.upstreamAt.length >= 1) {
    return { ok: false, retryAfter: Math.ceil(rules.upstreamGapMs / 1000), scope: "upstream_gap" };
  }
  if (state.upstreamMinute.length >= rules.upstreamPerMinute) {
    return { ok: false, retryAfter: 30, scope: "upstream_minute" };
  }
  state.upstreamAt.push(now);
  state.upstreamMinute.push(now);
  return { ok: true };
}

function nowMs(env) {
  if (env && typeof env.now === "function") return env.now();
  return Date.now();
}

function clientIp(request) {
  return request.headers.get("CF-Connecting-IP") || request.headers.get("X-Forwarded-For") || "unknown";
}

function corsHeaders(origin, env) {
  const headers = {
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Accept, Content-Type",
    "Access-Control-Expose-Headers": "X-Ooglex-Sec-Cache, Retry-After",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  if (origin && originAllowed(origin, env)) headers["Access-Control-Allow-Origin"] = origin;
  return headers;
}

function applyCors(response, origin, env) {
  const headers = new Headers(response.headers);
  const cors = corsHeaders(origin, env);
  Object.keys(cors).forEach((key) => headers.set(key, cors[key]));
  return new Response(response.body, { status: response.status, headers: headers });
}

function jsonResponse(body, status, origin, env, extra) {
  const headers = {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  };
  if (extra) Object.keys(extra).forEach((key) => headers[key] = extra[key]);
  return applyCors(new Response(JSON.stringify(body), { status: status, headers: headers }), origin, env);
}

async function edgeCache(env) {
  if (env && env.CACHE) return env.CACHE;
  if (typeof caches !== "undefined" && caches.default) return caches.default;
  return null;
}

function cacheRequest(url) {
  return new Request(url, { method: "GET" });
}

export async function handle(request, env, ctx) {
  const config = env || {};
  const url = new URL(request.url);
  const origin = request.headers.get("Origin") || "";

  if (request.method === "OPTIONS") {
    if (origin && !originAllowed(origin, config)) {
      return jsonResponse({ error: "forbidden", message: "这个来源不能使用本代理。" }, 403, origin, config);
    }
    return new Response(null, { status: 204, headers: corsHeaders(origin, config) });
  }

  if (url.pathname === "/health") {
    if (request.method !== "GET") {
      return jsonResponse({ error: "method", message: "只接受 GET。" }, 405, origin, config);
    }
    return jsonResponse({ ok: true, proxy: "sec-companyfacts" }, 200, origin, config);
  }

  if (request.method !== "GET") {
    return jsonResponse({ error: "method", message: "只接受 GET。" }, 405, origin, config);
  }

  if (origin && !originAllowed(origin, config)) {
    return jsonResponse({ error: "forbidden", message: "这个来源不能使用本代理。" }, 403, origin, config);
  }

  const cik = matchCik(url.pathname);
  if (!cik) {
    return jsonResponse(
      { error: "not_found", message: "只转发 SEC companyfacts（10 位 CIK）。" },
      404,
      origin,
      config
    );
  }

  const ip = clientIp(request).split(",")[0].trim() || "unknown";
  const now = nowMs(config);
  const state = config.buckets || buckets;
  const ipLimit = consumeIp(state, ip, now, LIMITS);
  if (!ipLimit.ok) {
    return jsonResponse(
      { error: "rate_limited", message: "请求过于频繁，请稍后再试。", scope: ipLimit.scope },
      429,
      origin,
      config,
      { "Retry-After": String(ipLimit.retryAfter) }
    );
  }

  const target = upstreamUrl(cik);
  const cache = await edgeCache(config);
  const cacheKey = cacheRequest(target);
  if (cache) {
    const hit = await cache.match(cacheKey);
    if (hit) {
      const headers = new Headers(hit.headers);
      headers.set("X-Ooglex-Sec-Cache", "hit");
      headers.set("Cache-Control", "public, max-age=" + LIMITS.cacheSeconds);
      return applyCors(new Response(hit.body, { status: 200, headers: headers }), origin, config);
    }
  }

  const upstreamLimit = consumeUpstream(state, now, LIMITS);
  if (!upstreamLimit.ok) {
    return jsonResponse(
      { error: "rate_limited", message: "请求过于频繁，请稍后再试。", scope: upstreamLimit.scope },
      429,
      origin,
      config,
      { "Retry-After": String(upstreamLimit.retryAfter) }
    );
  }

  const doFetch = config.fetchImpl || fetch;
  let upstream;
  try {
    upstream = await doFetch(target, {
      method: "GET",
      redirect: "manual",
      headers: {
        Accept: "application/json",
        "User-Agent": secUserAgent(config),
      },
      signal: AbortSignal.timeout(20000),
    });
  } catch (error) {
    return jsonResponse({ error: "upstream", message: "SEC 暂时没有响应。" }, 502, origin, config);
  }

  if (upstream.status >= 300 && upstream.status < 400) {
    return jsonResponse({ error: "upstream", message: "SEC 暂时没有响应。" }, 502, origin, config);
  }

  if (upstream.status === 404) {
    return jsonResponse({ error: "unknown_cik", message: "SEC 没有这份 companyfacts。" }, 404, origin, config);
  }

  if (upstream.status === 429) {
    return jsonResponse(
      { error: "rate_limited", message: "SEC 暂时限制了访问，请稍后再试。" },
      429,
      origin,
      config,
      { "Retry-After": "60" }
    );
  }

  const type = (upstream.headers.get("Content-Type") || "").toLowerCase();
  if (!upstream.ok || !type.includes("json")) {
    return jsonResponse({ error: "upstream", message: "SEC 暂时没有响应。" }, 502, origin, config);
  }

  const headers = {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "public, max-age=" + LIMITS.cacheSeconds,
    "X-Ooglex-Sec-Cache": "miss",
  };
  const fresh = new Response(upstream.body, { status: 200, headers: headers });
  if (cache) {
    const saved = fresh.clone();
    const put = cache.put(cacheKey, saved).catch(() => {});
    if (ctx && typeof ctx.waitUntil === "function") ctx.waitUntil(put);
    else await put;
  }
  return applyCors(fresh, origin, config);
}

export default {
  fetch(request, env, ctx) {
    return handle(request, env, ctx);
  },
};
