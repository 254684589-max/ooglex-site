/* Jamendo 曲目目录代理（Cloudflare Worker），供流光播放器「全球曲库」使用
   只转发一条只读查询：Jamendo API v3.0 /tracks。
   不接受调用方传入的任意 URL，也不转发音频：音频由 Jamendo 服务器直接给浏览器。

   为什么要这层：
     · client_id 放在 Cloudflare Secret（JAMENDO_CLIENT_ID），不进前端和仓库
     · 边缘缓存 30 分钟，同一曲风的翻页请求不会重复消耗 Jamendo 配额
     · 每 IP 限频，只认本站页面来源
     · 把上游字段裁成播放器要的几项，并只放行 https 地址

   用法：GET https://<worker>/tracks?tag=pop&order=popular&offset=0&q=
     tag     曲风标签，小写字母，可空（全部曲风）
     order   popular（近一月热门，默认）| week（本周热门）| new（最新发布）
     offset  0–980，步长由本 Worker 固定为 20
     q       搜索歌名或艺人，最多 40 字，可空
     id      Jamendo 曲目编号（1–12 位数字），可空；给了就只查这一首，其余参数不用。分享链接靠它打开单曲。 */

export const LIMITS = {
  perIpPerMinute: 30,
  perIpPerDay: 600,
  pageSize: 20,
  maxOffset: 980,
  cacheSeconds: 30 * 60,
  timeoutMs: 8000,
};

const DEFAULT_ALLOWED = "https://www.ooglex.com,https://ooglex.com";
const UPSTREAM = "https://api.jamendo.com/v3.0/tracks/";
const ORDERS = { popular: "popularity_month", week: "popularity_week", new: "releasedate_desc" };
const TAG_RE = /^[a-z]{2,16}$/;

const buckets = createLimiterState();

export function createLimiterState() {
  return { ips: new Map() };
}

export function resetLimiter() {
  buckets.ips.clear();
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

// 把查询参数收成固定形状；不合格返回 null。缓存键也用它，避免同义请求各算一份。
export function parseQuery(searchParams) {
  const tag = String(searchParams.get("tag") || "").trim();
  if (tag && !TAG_RE.test(tag)) return null;
  const order = String(searchParams.get("order") || "popular");
  if (!Object.prototype.hasOwnProperty.call(ORDERS, order)) return null;
  const rawOffset = String(searchParams.get("offset") || "0");
  if (!/^\d{1,4}$/.test(rawOffset)) return null;
  const offset = Number(rawOffset);
  if (offset > LIMITS.maxOffset || offset % LIMITS.pageSize !== 0) return null;
  const q = String(searchParams.get("q") || "").replace(/[\u0000-\u001f]+/g, " ").trim();
  if (q.length > 40) return null;
  const id = String(searchParams.get("id") || "");
  if (id && !/^[1-9]\d{0,11}$/.test(id)) return null;
  if (id) return { tag: "", order: "popular", offset: 0, q: "", id: id };
  return { tag: tag, order: order, offset: offset, q: q, id: "" };
}

// tagParam：Jamendo 的 tags 与 fuzzytags 都按曲风过滤。实测两者会各自间歇性地返回 0 条，
// 所以一种落空时换另一种再问一次（见 handle）。
export function upstreamUrl(query, clientId, tagParam) {
  const url = new URL(UPSTREAM);
  url.searchParams.set("client_id", clientId);
  url.searchParams.set("format", "json");
  url.searchParams.set("limit", String(LIMITS.pageSize));
  url.searchParams.set("offset", String(query.offset));
  url.searchParams.set("order", ORDERS[query.order]);
  url.searchParams.set("audioformat", "mp32");
  url.searchParams.set("imagesize", "200");
  url.searchParams.set("include", "licenses");
  if (query.tag) url.searchParams.set(tagParam || "tags", query.tag);
  if (query.q) url.searchParams.set("search", query.q);
  if (query.id) url.searchParams.set("id", query.id);
  return url.toString();
}

// 只放行白名单域名。Jamendo 的许可链接常是 http://creativecommons.org/…，这些域名都支持 https，直接升级。
function httpsUrl(value, hosts) {
  try {
    const url = new URL(String(value || ""));
    if (!hosts.some((host) => url.hostname === host || url.hostname.endsWith("." + host))) return "";
    if (url.protocol === "http:") url.protocol = "https:";
    if (url.protocol !== "https:" || url.username || url.password) return "";
    return url.toString();
  } catch (error) {
    return "";
  }
}

function text(value, max) {
  return String(value == null ? "" : value).replace(/[\u0000-\u001f]+/g, " ").trim().slice(0, max);
}

// 只留播放器要的字段。没有可播 https 音频或没有 CC 许可链接的曲目整条丢掉。
export function trimTrack(raw) {
  if (!raw || typeof raw !== "object") return null;
  const id = text(raw.id, 20);
  if (!/^\d+$/.test(id)) return null;
  const audio = httpsUrl(raw.audio, ["jamendo.com"]);
  const license = httpsUrl(raw.license_ccurl, ["creativecommons.org"]);
  if (!audio || !license) return null;
  const duration = Number(raw.duration);
  return {
    id: id,
    title: text(raw.name, 120) || "未命名",
    artist: text(raw.artist_name, 80) || "未知艺人",
    album: text(raw.album_name, 120),
    durationSec: isFinite(duration) && duration > 0 ? Math.round(duration) : 0,
    image: httpsUrl(raw.image || raw.album_image, ["jamendo.com"]),
    src: audio,
    license: license,
    page: httpsUrl(raw.shareurl, ["jamendo.com"]),
  };
}

function prune(list, cutoff) {
  while (list.length && list[0] <= cutoff) list.shift();
}

export function consumeIp(state, ip, now, limits) {
  const rules = limits || LIMITS;
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
  prune(record.minute, now - 60 * 1000);
  if (record.minute.length >= rules.perIpPerMinute) return { ok: false, retryAfter: 60, scope: "ip_minute" };
  if (record.dayCount >= rules.perIpPerDay) return { ok: false, retryAfter: 3600, scope: "ip_day" };
  record.minute.push(now);
  record.dayCount += 1;
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
    "Access-Control-Expose-Headers": "X-Ooglex-Jamendo-Cache, Retry-After",
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

function failure(error, message, status, origin, env, extra) {
  return jsonResponse({ status: "error", error: error, message: message }, status, origin, env, extra);
}

async function edgeCache(env) {
  if (env && env.CACHE) return env.CACHE;
  if (typeof caches !== "undefined" && caches.default) return caches.default;
  return null;
}

function cacheKey(query) {
  const url = new URL("https://jamendo-proxy.cache/tracks");
  url.searchParams.set("tag", query.tag);
  url.searchParams.set("order", query.order);
  url.searchParams.set("offset", String(query.offset));
  url.searchParams.set("q", query.q.toLowerCase());
  url.searchParams.set("id", query.id || "");
  return new Request(url.toString(), { method: "GET" });
}

async function fetchPage(doFetch, url) {
  let upstream;
  try {
    upstream = await doFetch(url, {
      method: "GET",
      redirect: "manual",
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(LIMITS.timeoutMs),
    });
  } catch (error) {
    const timeout = error && (error.name === "TimeoutError" || error.name === "AbortError");
    return { ok: false, error: timeout ? "timeout" : "upstream", message: "Jamendo 暂时没有响应。", status: 502 };
  }
  if (upstream.status === 429) {
    return { ok: false, error: "rate_limited", message: "Jamendo 暂时限制了访问，请稍后再试。", status: 429, extra: { "Retry-After": "60" } };
  }
  if (!upstream.ok) return { ok: false, error: "upstream", message: "Jamendo 暂时没有响应。", status: 502 };
  let data;
  try {
    data = await upstream.json();
  } catch (error) {
    return { ok: false, error: "upstream", message: "Jamendo 返回的内容读不了。", status: 502 };
  }
  const head = (data && data.headers) || {};
  if (head.status !== "success" || !Array.isArray(data.results)) {
    // Jamendo 把 client_id 无效等错误放在 200 正文里（code 非 0）。原文不外传，只留代码。
    return { ok: false, error: "upstream", message: "Jamendo 拒绝了这次查询（代码 " + text(head.code, 8) + "）。", status: 502 };
  }
  return { ok: true, results: data.results };
}

export async function handle(request, env, ctx) {
  const config = env || {};
  const url = new URL(request.url);
  const origin = request.headers.get("Origin") || "";

  if (request.method === "OPTIONS") {
    if (origin && !originAllowed(origin, config)) return failure("forbidden", "这个来源不能使用本代理。", 403, origin, config);
    return new Response(null, { status: 204, headers: corsHeaders(origin, config) });
  }
  if (request.method !== "GET") return failure("method", "只接受 GET。", 405, origin, config);
  if (origin && !originAllowed(origin, config)) return failure("forbidden", "这个来源不能使用本代理。", 403, origin, config);

  if (url.pathname === "/health") {
    return jsonResponse({ ok: true, proxy: "jamendo", configured: !!config.JAMENDO_CLIENT_ID }, 200, origin, config);
  }
  if (url.pathname !== "/tracks") return failure("not_found", "只提供 /tracks。", 404, origin, config);

  const query = parseQuery(url.searchParams);
  if (!query) return failure("bad_request", "参数不对。", 400, origin, config);

  const clientId = String(config.JAMENDO_CLIENT_ID || "").trim();
  if (!clientId) return failure("not_configured", "接口还没配置 Jamendo client_id。", 503, origin, config);

  const ip = clientIp(request).split(",")[0].trim() || "unknown";
  const limit = consumeIp(config.buckets || buckets, ip, nowMs(config), LIMITS);
  if (!limit.ok) {
    return failure("rate_limited", "请求过于频繁，请稍后再试。", 429, origin, config, { "Retry-After": String(limit.retryAfter) });
  }

  const cache = await edgeCache(config);
  const key = cacheKey(query);
  if (cache) {
    const hit = await cache.match(key);
    if (hit) {
      const headers = new Headers(hit.headers);
      headers.set("X-Ooglex-Jamendo-Cache", "hit");
      return applyCors(new Response(hit.body, { status: 200, headers: headers }), origin, config);
    }
  }

  const doFetch = config.fetchImpl || fetch;
  let page = await fetchPage(doFetch, upstreamUrl(query, clientId, "tags"));
  if (page.ok && !page.results.length && query.tag) {
    const retry = await fetchPage(doFetch, upstreamUrl(query, clientId, "fuzzytags"));
    if (retry.ok) page = retry;
  }
  if (!page.ok) return failure(page.error, page.message, page.status, origin, config, page.extra);

  const raw = page.results;
  const tracks = raw.map(trimTrack).filter(Boolean);
  const body = {
    source: "Jamendo",
    sourceUrl: "https://www.jamendo.com/",
    updatedAt: new Date(nowMs(config)).toISOString(),
    frequency: "on-demand",
    status: tracks.length ? (tracks.length < raw.length ? "partial" : "ok") : "empty",
    received: raw.length,
    tag: query.tag,
    order: query.order,
    q: query.q,
    offset: query.offset,
    pageSize: LIMITS.pageSize,
    hasMore: raw.length === LIMITS.pageSize && query.offset + LIMITS.pageSize <= LIMITS.maxOffset,
    tracks: tracks,
  };
  // 空结果多半是 Jamendo 间歇落空，不进缓存，下一次请求重新问。
  const cacheable = tracks.length > 0;
  const fresh = new Response(JSON.stringify(body), {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": cacheable ? "public, max-age=" + LIMITS.cacheSeconds : "no-store",
      "X-Ooglex-Jamendo-Cache": "miss",
    },
  });
  if (cache && cacheable) {
    const put = cache.put(key, fresh.clone()).catch(() => {});
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
