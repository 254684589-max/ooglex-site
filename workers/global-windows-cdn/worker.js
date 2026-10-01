const MANIFEST_KEY = "manifest/windows.json";

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const cors = corsHeaders(request, env);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (!["GET", "HEAD"].includes(request.method)) {
      return new Response("Method Not Allowed", { status: 405, headers: { ...cors, Allow: "GET, HEAD, OPTIONS" } });
    }

    if (url.pathname === "/health") {
      const head = await env.WINDOW_MEDIA.head(MANIFEST_KEY);
      return json({
        ok: true,
        service: "ooglex-global-windows-cdn",
        bucket: "r2",
        manifest: Boolean(head),
        manifestSize: head ? head.size : 0
      }, 200, cors);
    }

    if (url.pathname === "/manifest.json") {
      // The manifest is control-plane metadata and changes on every catalog
      // deployment. Never serve it from caches.default: stale manifests can
      // make a successful R2 upload look like an old 36-item deployment.
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
      endpoints: ["/health", "/manifest.json", "/media/:key"]
    }, 200, cors);
  }
};

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

  const options = {
    onlyIf: request.headers,
    ...(hasRange ? { range: request.headers } : {})
  };
  const object = isHead
    ? await env.WINDOW_MEDIA.head(key)
    : await env.WINDOW_MEDIA.get(key, options);

  if (!object) return new Response("Not Found", { status: 404, headers: cors });
  if (!isHead && !("body" in object)) return new Response(null, { status: 412, headers: cors });

  const headers = objectHeaders(object, cors);
  headers.set("Accept-Ranges", "bytes");
  if (manifest) {
    headers.set("Cache-Control", "no-cache, max-age=0, must-revalidate");
  }

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
  if (!headers.has("Cache-Control")) {
    headers.set("Cache-Control", "public, max-age=31536000, immutable");
  }
  headers.set("X-Content-Type-Options", "nosniff");
  return headers;
}

function corsHeaders(request, env) {
  const origin = request.headers.get("Origin") || "";
  const allowed = String(env.ALLOWED_ORIGINS || "https://www.ooglex.com,https://ooglex.com")
    .split(",")
    .map(x => x.trim())
    .filter(Boolean);
  const allowOrigin = allowed.includes(origin) ? origin : allowed[0] || "*";
  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
    "Access-Control-Allow-Headers": "Range, Content-Type, If-None-Match, If-Match, If-Modified-Since, If-Unmodified-Since",
    "Access-Control-Expose-Headers": "Content-Length, Content-Range, Accept-Ranges, ETag, Cache-Control",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin"
  };
}

function withCors(response, cors) {
  const headers = new Headers(response.headers);
  Object.entries(cors).forEach(([k, v]) => headers.set(k, v));
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

function json(value, status, extraHeaders = {}) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...extraHeaders
    }
  });
}
