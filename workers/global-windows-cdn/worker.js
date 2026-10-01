const MANIFEST_KEY = "manifest/windows.json";
const STATS_NAME = "global-v1";
const MAX_STATS_ITEMS = 500;
const STATS_RETENTION_DAYS = 30;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const cors = corsHeaders(request, env);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }

    if (url.pathname === "/health" && ["GET", "HEAD"].includes(request.method)) {
      const head = await env.WINDOW_MEDIA.head(MANIFEST_KEY);
      return json({
        ok: true,
        service: "ooglex-global-windows-cdn",
        bucket: "r2",
        manifest: Boolean(head),
        manifestSize: head ? head.size : 0,
        popularity: Boolean(env.WINDOW_STATS)
      }, 200, cors, request.method === "HEAD");
    }

    if (url.pathname === "/stats/health" && ["GET", "HEAD"].includes(request.method)) {
      return statsFetch(request, env, cors);
    }

    if (url.pathname === "/stats/popular" && ["GET", "HEAD"].includes(request.method)) {
      return statsFetch(request, env, cors);
    }

    if (url.pathname === "/stats/play" && request.method === "POST") {
      if (!isAllowedWriteOrigin(request, env)) {
        return json({ ok: false, error: "origin_not_allowed" }, 403, cors);
      }
      const len = Number(request.headers.get("Content-Length") || 0);
      if (len > 1024) return json({ ok: false, error: "payload_too_large" }, 413, cors);

      let body;
      try {
        body = await request.json();
      } catch {
        return json({ ok: false, error: "invalid_json" }, 400, cors);
      }
      const id = String(body && body.id || "");
      if (!/^r2-(?:seed-)?[a-z0-9]{8,32}$/i.test(id)) {
        return json({ ok: false, error: "invalid_window_id" }, 400, cors);
      }

      const stub = statsStub(env);
      const headers = new Headers({ "Content-Type": "application/json" });
      const client = transientClientToken(request);
      const upstream = await stub.fetch("https://stats.internal/play", {
        method: "POST",
        headers,
        body: JSON.stringify({ id, client })
      });
      return withCors(upstream, cors);
    }

    if (!["GET", "HEAD"].includes(request.method)) {
      return new Response("Method Not Allowed", {
        status: 405,
        headers: { ...cors, Allow: "GET, HEAD, POST, OPTIONS" }
      });
    }

    if (url.pathname === "/manifest.json") {
      return serveObject(request, env, ctx, MANIFEST_KEY, cors, false, true);
    }

    if (url.pathname.startsWith("/media/")) {
      const key = decodeURIComponent(url.pathname.slice(1));
      if (!/^media\/[a-z0-9][a-z0-9._-]{2,160}$/i.test(key)) {
        return new Response("Bad media key", { status: 400, headers: cors });
      }
      return serveObject(request, env, ctx, key, cors, false);
    }

    return json({
      ok: true,
      service: "Ooglex WINDOW CDN",
      endpoints: ["/health", "/manifest.json", "/media/:key", "/stats/play", "/stats/popular", "/stats/health"]
    }, 200, cors);
  }
};

export class WindowStats {
  constructor(state) {
    this.state = state;
    this.recentClients = new Map();
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/health") {
      const stats = await this.readStats();
      return json({ ok: true, items: Object.keys(stats.items).length, updatedAt: stats.updatedAt || null }, 200);
    }

    if (url.pathname === "/play" && request.method === "POST") {
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ ok: false, error: "invalid_json" }, 400);
      }
      const id = String(body && body.id || "");
      const client = String(body && body.client || "").slice(0, 64);
      if (!/^r2-(?:seed-)?[a-z0-9]{8,32}$/i.test(id)) {
        return json({ ok: false, error: "invalid_window_id" }, 400);
      }

      const now = Date.now();
      const rateKey = client ? client + "|" + id : "";
      if (rateKey) {
        const prev = this.recentClients.get(rateKey) || 0;
        if (now - prev < 5 * 60 * 1000) {
          return json({ ok: true, counted: false, reason: "rate_limited" }, 200);
        }
        this.recentClients.set(rateKey, now);
        if (this.recentClients.size > 2000) this.pruneRecent(now);
      }

      const stats = await this.readStats();
      const day = dayKey(now);
      const item = stats.items[id] || { total: 0, days: {}, lastPlayedAt: null };
      item.total = Number(item.total || 0) + 1;
      item.days = pruneDays(item.days || {}, now);
      item.days[day] = Number(item.days[day] || 0) + 1;
      item.lastPlayedAt = new Date(now).toISOString();
      stats.items[id] = item;
      stats.updatedAt = item.lastPlayedAt;

      if (Object.keys(stats.items).length > MAX_STATS_ITEMS) {
        const keep = Object.entries(stats.items)
          .sort((a, b) => Date.parse(b[1].lastPlayedAt || 0) - Date.parse(a[1].lastPlayedAt || 0))
          .slice(0, MAX_STATS_ITEMS);
        stats.items = Object.fromEntries(keep);
      }

      await this.state.storage.put("stats", stats);
      return json({ ok: true, counted: true }, 200);
    }

    if (url.pathname === "/popular" && ["GET", "HEAD"].includes(request.method)) {
      const days = clampInt(url.searchParams.get("days"), 1, STATS_RETENTION_DAYS, 7);
      const limit = clampInt(url.searchParams.get("limit"), 1, 500, 150);
      const stats = await this.readStats();
      const now = Date.now();
      const rows = Object.entries(stats.items).map(([id, item]) => {
        const daysMap = pruneDays(item.days || {}, now);
        return {
          id,
          plays: sumRecent(daysMap, now, days),
          plays30d: sumRecent(daysMap, now, 30),
          total: Number(item.total || 0),
          lastPlayedAt: item.lastPlayedAt || null
        };
      }).sort((a, b) =>
        b.plays - a.plays ||
        b.plays30d - a.plays30d ||
        b.total - a.total ||
        String(b.lastPlayedAt || "").localeCompare(String(a.lastPlayedAt || ""))
      ).slice(0, limit);

      return json({
        ok: true,
        windowDays: days,
        updatedAt: stats.updatedAt || null,
        items: rows
      }, 200, {}, request.method === "HEAD");
    }

    return json({ ok: false, error: "not_found" }, 404);
  }

  async readStats() {
    const current = await this.state.storage.get("stats");
    if (current && current.version === 1 && current.items && typeof current.items === "object") return current;
    return { version: 1, updatedAt: null, items: {} };
  }

  pruneRecent(now) {
    for (const [key, ts] of this.recentClients) {
      if (now - ts > 10 * 60 * 1000) this.recentClients.delete(key);
    }
  }
}

async function statsFetch(request, env, cors) {
  if (!env.WINDOW_STATS) return json({ ok: false, error: "stats_unavailable" }, 503, cors);
  const url = new URL(request.url);
  const stub = statsStub(env);
  const path = url.pathname === "/stats/health" ? "/health" : "/popular" + url.search;
  const upstream = await stub.fetch("https://stats.internal" + path, { method: request.method });
  return withCors(upstream, cors);
}

function statsStub(env) {
  const id = env.WINDOW_STATS.idFromName(STATS_NAME);
  return env.WINDOW_STATS.get(id);
}

async function serveObject(request, env, ctx, key, cors, cacheable, manifest = false) {
  const isHead = request.method === "HEAD";
  const hasRange = request.headers.has("Range");

  if (cacheable && !hasRange && !isHead) {
    const cache = caches.default;
    const cacheKey = new Request(request.url, { method: "GET" });
    const cached = await cache.match(cacheKey);
    if (cached) return withCors(cached, cors);

    const object = await env.WINDOW_MEDIA.get(key, { onlyIf: request.headers });
    if (!object) return new Response("Not Found", { status: 404, headers: cors });
    if (!("body" in object)) return new Response(null, { status: 412, headers: cors });

    const headers = objectHeaders(object, cors);
    headers.set("Cache-Control", "public, max-age=300, s-maxage=3600, stale-while-revalidate=86400");
    const response = new Response(object.body, { status: 200, headers });
    ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  }

  const options = { onlyIf: request.headers, ...(hasRange ? { range: request.headers } : {}) };
  const object = isHead ? await env.WINDOW_MEDIA.head(key) : await env.WINDOW_MEDIA.get(key, options);

  if (!object) return new Response("Not Found", { status: 404, headers: cors });
  if (!isHead && !("body" in object)) return new Response(null, { status: 412, headers: cors });

  const headers = objectHeaders(object, cors);
  headers.set("Accept-Ranges", "bytes");
  if (manifest) headers.set("Cache-Control", "no-cache, max-age=0, must-revalidate");

  let status = 200;
  if (!isHead && object.range) {
    const offset = Number(object.range.offset || 0);
    const length = Number(object.range.length || 0);
    if (length > 0) {
      headers.set("Content-Range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
      headers.set("Content-Length", String(length));
      status = 206;
    }
  } else if (Number.isFinite(Number(object.size))) {
    headers.set("Content-Length", String(object.size));
  }

  return new Response(isHead ? null : object.body, { status, headers });
}

function objectHeaders(object, cors) {
  const headers = new Headers(cors);
  if (object.writeHttpMetadata) object.writeHttpMetadata(headers);
  if (object.httpEtag) headers.set("ETag", object.httpEtag);
  if (!headers.has("Cache-Control")) headers.set("Cache-Control", "public, max-age=31536000, immutable");
  headers.set("X-Content-Type-Options", "nosniff");
  return headers;
}

function corsHeaders(request, env) {
  const origin = request.headers.get("Origin") || "";
  const allowed = allowedOrigins(env);
  const allowOrigin = allowed.includes(origin) ? origin : allowed[0] || "*";
  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Methods": "GET, HEAD, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Range, Content-Type, If-None-Match, If-Match, If-Modified-Since, If-Unmodified-Since",
    "Access-Control-Expose-Headers": "Content-Length, Content-Range, Accept-Ranges, ETag, Cache-Control",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin"
  };
}

function allowedOrigins(env) {
  return String(env.ALLOWED_ORIGINS || "https://www.ooglex.com,https://ooglex.com")
    .split(",").map(x => x.trim()).filter(Boolean);
}

function isAllowedWriteOrigin(request, env) {
  const origin = request.headers.get("Origin") || "";
  return allowedOrigins(env).includes(origin);
}

function transientClientToken(request) {
  const ip = request.headers.get("CF-Connecting-IP") || "";
  const ua = request.headers.get("User-Agent") || "";
  const day = new Date().toISOString().slice(0, 10);
  return hashString(ip + "|" + ua.slice(0, 120) + "|" + day);
}

function hashString(value) {
  let h = 2166136261;
  for (let i = 0; i < value.length; i++) {
    h ^= value.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return (h >>> 0).toString(36);
}

function dayKey(ts) {
  return new Date(ts).toISOString().slice(0, 10);
}

function pruneDays(days, now) {
  const cutoff = new Date(now - (STATS_RETENTION_DAYS - 1) * 86400000).toISOString().slice(0, 10);
  const out = {};
  for (const [day, count] of Object.entries(days || {})) {
    if (/^\d{4}-\d{2}-\d{2}$/.test(day) && day >= cutoff) out[day] = Number(count || 0);
  }
  return out;
}

function sumRecent(days, now, windowDays) {
  const cutoff = new Date(now - (windowDays - 1) * 86400000).toISOString().slice(0, 10);
  return Object.entries(days || {}).reduce((sum, [day, count]) => day >= cutoff ? sum + Number(count || 0) : sum, 0);
}

function clampInt(value, min, max, fallback) {
  const n = Number.parseInt(String(value || ""), 10);
  return Number.isFinite(n) ? Math.max(min, Math.min(max, n)) : fallback;
}

function withCors(response, cors) {
  const headers = new Headers(response.headers);
  Object.entries(cors).forEach(([k, v]) => headers.set(k, v));
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

function json(value, status, extraHeaders = {}, head = false) {
  return new Response(head ? null : JSON.stringify(value), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...extraHeaders
    }
  });
}
