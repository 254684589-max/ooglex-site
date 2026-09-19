const PRODUCTS = Object.freeze({
  supply_chain: {
    previewKey: "supply-chain/preview.json",
    fullKey: "supply-chain/full.json"
  },
  macro_risk: {
    previewKey: "macro-risk/preview.json",
    fullKey: "macro-risk/full.json"
  },
  billionaires: {
    previewKey: "billionaires/preview.json",
    fullKey: "billionaires/full.json"
  },
  finance_column: {
    previewKey: "finance-column/preview.json",
    fullKey: "finance-column/full.json"
  }
});


const TECH_LEADERS = Object.freeze({
  musk: { id: "musk", handle: "elonmusk", name: "Elon Musk" },
  huang: { id: "huang", handle: "JensenHuang", name: "Jensen Huang" },
  altman: { id: "altman", handle: "sama", name: "Sam Altman" },
  su: { id: "su", handle: "LisaSu", name: "Lisa Su" },
  pichai: { id: "pichai", handle: "sundarpichai", name: "Sundar Pichai" },
  nadella: { id: "nadella", handle: "satyanadella", name: "Satya Nadella" },
  "adena-friedman": { id: "adena-friedman", handle: "adenatfriedman", name: "Adena Friedman" }
});

const TECH_FEED_TTL_MS = 15 * 60 * 1000;
const TECH_FEED_MAX_STALE_MS = 7 * 24 * 60 * 60 * 1000;
const TECH_FEED_FETCH_SIZE = 10;

const TECH_AVATAR_MAX_BYTES = 3 * 1024 * 1024;
const TECH_AVATAR_CACHE_CONTROL = "public, max-age=604800, stale-while-revalidate=2592000";
const TECH_AVATAR_OVERRIDES = Object.freeze({
  jensenhuang: "https://iprsoftwaremedia.com/219/files/202604/f0e9efa72f909f3f08cdd0a48ff92880/69e6b9293d633260eec67804_jensen-1920x1920/jensen-1920x1920_6a7e6ad5-c215-4503-b70d-fe6e5e9de205-prv.jpg?v=6a7e6ad5-c215-4503-b70d-fe6e5e9de205",
  rajaxg: "https://d1io3yog0oux5.cloudfront.net/_3ccf9cf30376bf77bbb27f582e51d00d/intel/news/193/1779/image.jpeg",
  sytses: "https://res.cloudinary.com/about-gitlab-com/image/upload/v1755613184/abfz99qjcfcvo6em0sgm.webp",
  svlevine: "https://vcresearch.berkeley.edu/sites/default/files/styles/faculty_photo_thumbnail/public/2023-04/sergey_levin_20200122_AVL_0050.jpg?h=726b1c9d&itok=Aa7Rxyv2"
});

function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...headers
    }
  });
}

function corsHeaders(request, env) {
  const origin = request.headers.get("Origin") || "";
  const configured = String(env.ALLOWED_ORIGINS || "https://www.ooglex.com,https://ooglex.com")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const allow = configured.includes(origin) ? origin : configured[0] || "https://www.ooglex.com";
  return {
    "access-control-allow-origin": allow,
    "access-control-allow-headers": "authorization,content-type",
    "access-control-allow-methods": "GET,OPTIONS",
    "vary": "Origin"
  };
}

function bearerToken(request) {
  const auth = request.headers.get("Authorization") || "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  return m ? m[1] : null;
}

async function getUser(token, env) {
  if (!token) return null;
  const res = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: {
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${token}`
    }
  });
  if (!res.ok) return null;
  return res.json();
}

async function getAccess(product, token, env) {
  if (!token) return { plan: "free", access_level: "preview", authenticated: false };

  const user = await getUser(token, env);
  if (!user || !user.id) return { plan: "free", access_level: "preview", authenticated: false };

  const res = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/my_product_access`, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${token}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({ p_product_key: product })
  });

  if (!res.ok) {
    return { plan: "free", access_level: "preview", authenticated: true, user_id: user.id };
  }

  const rows = await res.json();
  const row = Array.isArray(rows) && rows[0] ? rows[0] : null;
  return {
    plan: row && row.plan ? row.plan : "free",
    access_level: row && row.access_level ? row.access_level : "preview",
    authenticated: true,
    user_id: user.id
  };
}

async function readDataset(binding, key) {
  const obj = await binding.get(key);
  if (!obj) return null;
  const headers = new Headers();
  if (obj.httpMetadata && obj.httpMetadata.contentType) {
    headers.set("content-type", obj.httpMetadata.contentType);
  } else {
    headers.set("content-type", "application/json; charset=utf-8");
  }
  if (obj.etag) headers.set("etag", obj.etag);
  return { body: obj.body, headers };
}


async function readJson(binding, key) {
  const obj = await binding.get(key);
  if (!obj) return null;
  try {
    return JSON.parse(await obj.text());
  } catch {
    return null;
  }
}

async function writeJson(binding, key, value) {
  await binding.put(key, JSON.stringify(value), {
    httpMetadata: { contentType: "application/json; charset=utf-8" }
  });
}

function boundedInt(value, min, max, fallback) {
  const n = Number.parseInt(String(value || ""), 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, n));
}


function normalizeXHandle(value) {
  const handle = String(value || "").trim().replace(/^@/, "");
  return /^[A-Za-z0-9_]{1,15}$/.test(handle) ? handle : "";
}

function twitterProfileImageLarge(urlValue) {
  try {
    const u = new URL(urlValue);
    u.pathname = u.pathname.replace(/_(normal|bigger|mini|200x200)\.(jpg|jpeg|png|webp)$/i, "_400x400.$2");
    return u.toString();
  } catch {
    return String(urlValue || "");
  }
}

function findProfileImageUrl(value, depth = 0) {
  if (depth > 14 || value == null) return "";
  if (typeof value === "string") {
    return /^https:\/\/pbs\.twimg\.com\/profile_images\//i.test(value)
      ? twitterProfileImageLarge(value)
      : "";
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findProfileImageUrl(item, depth + 1);
      if (found) return found;
    }
    return "";
  }
  if (typeof value === "object") {
    const preferred = Object.keys(value).filter((key) => /profile.*image|image.*profile|avatar/i.test(key));
    for (const key of preferred) {
      const found = findProfileImageUrl(value[key], depth + 1);
      if (found) return found;
    }
    for (const key of Object.keys(value)) {
      const found = findProfileImageUrl(value[key], depth + 1);
      if (found) return found;
    }
  }
  return "";
}

async function fetchAvatarImage(url, source) {
  const res = await fetch(url, {
    redirect: "follow",
    headers: {
      accept: "image/avif,image/webp,image/png,image/jpeg,image/*,*/*;q=0.8",
      "user-agent": "Mozilla/5.0 (compatible; Ooglex-Tech-Leaders-Avatar/4.2)"
    }
  });
  if (!res.ok) return { ok: false, status: res.status, source };
  const contentType = String(res.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
  if (!contentType.startsWith("image/")) return { ok: false, status: res.status, source };
  const bytes = await res.arrayBuffer();
  if (!bytes.byteLength || bytes.byteLength > TECH_AVATAR_MAX_BYTES) return { ok: false, status: 502, source };
  return { ok: true, bytes, contentType, source };
}

async function fetchAvatarViaSyndication(handle) {
  const url = `https://syndication.twitter.com/srv/timeline-profile/screen-name/${encodeURIComponent(handle)}`;
  const res = await fetch(url, {
    redirect: "follow",
    headers: {
      accept: "text/html,application/xhtml+xml",
      "user-agent": "Mozilla/5.0 (compatible; Ooglex-Tech-Leaders-Avatar/4.2)"
    }
  });
  if (!res.ok) return { ok: false, status: res.status, source: "x_syndication" };
  const html = await res.text();
  let imageUrl = "";
  const next = html.match(/<script[^>]+id=["']__NEXT_DATA__["'][^>]*>([\s\S]*?)<\/script>/i);
  if (next && next[1]) {
    try { imageUrl = findProfileImageUrl(JSON.parse(next[1])); } catch {}
  }
  if (!imageUrl) {
    const normalized = html.replace(/\\u002F/gi, "/").replace(/\\\//g, "/").replace(/&amp;/g, "&");
    const m = normalized.match(/https:\/\/pbs\.twimg\.com\/profile_images\/[^"'<>\s\\]+/i);
    if (m) imageUrl = twitterProfileImageLarge(m[0]);
  }
  if (!imageUrl) return { ok: false, status: 404, source: "x_syndication" };
  return fetchAvatarImage(imageUrl, "x_syndication");
}

function normalizeWikiText(value) {
  return String(value || "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function wikiTitleMatchesPerson(title, name) {
  const t = normalizeWikiText(title);
  const n = normalizeWikiText(name);
  if (!t || !n) return false;
  const tokens = n.split(/\s+/).filter(Boolean);
  if (!tokens.length) return false;
  const suffixes = new Set(["jr", "sr", "ii", "iii", "iv"]);
  let key = tokens[tokens.length - 1];
  if (suffixes.has(key) && tokens.length > 1) key = tokens[tokens.length - 2];
  if (key.length < 2) return false;
  return t.split(/\s+/).includes(key);
}

async function fetchAvatarViaWikipedia(name, company) {
  const cleanName = String(name || "").trim().slice(0, 120);
  const cleanCompany = String(company || "").trim().slice(0, 120);
  if (!cleanName) return { ok: false, status: 400, source: "wikipedia" };

  const search = [cleanName, cleanCompany].filter(Boolean).join(" ");
  const params = new URLSearchParams({
    action: "query",
    generator: "search",
    gsrsearch: search,
    gsrnamespace: "0",
    gsrlimit: "5",
    prop: "pageimages",
    pithumbsize: "500",
    pilimit: "5",
    format: "json",
    formatversion: "2",
    origin: "*"
  });

  const res = await fetch(`https://en.wikipedia.org/w/api.php?${params.toString()}`, {
    headers: {
      accept: "application/json",
      "user-agent": "Ooglex-Tech-Leaders-Avatar/4.2 (https://ooglex.com)"
    }
  });
  if (!res.ok) return { ok: false, status: res.status, source: "wikipedia" };

  let payload = null;
  try { payload = await res.json(); } catch {}
  const pages = payload && payload.query && Array.isArray(payload.query.pages)
    ? payload.query.pages
    : [];

  for (const page of pages) {
    if (!page || !page.thumbnail || !page.thumbnail.source) continue;
    if (!wikiTitleMatchesPerson(page.title, cleanName)) continue;
    const image = await fetchAvatarImage(page.thumbnail.source, "wikipedia");
    if (image.ok) return image;
  }
  return { ok: false, status: 404, source: "wikipedia" };
}

function commonsTitleMatchesPerson(title, name) {
  const t = normalizeWikiText(title);
  const n = normalizeWikiText(name);
  const tokens = n.split(/\s+/).filter((x) => x.length >= 2);
  if (!t || tokens.length < 2) return false;
  const first = tokens[0];
  const last = tokens[tokens.length - 1];
  return t.includes(first) && t.includes(last);
}

async function fetchAvatarViaCommons(name) {
  const cleanName = String(name || "").trim().slice(0, 120);
  if (!cleanName) return { ok: false, status: 400, source: "wikimedia_commons" };

  const params = new URLSearchParams({
    action: "query",
    generator: "search",
    gsrsearch: cleanName,
    gsrnamespace: "6",
    gsrlimit: "12",
    prop: "imageinfo",
    iiprop: "url|mime",
    iiurlwidth: "500",
    iilimit: "1",
    format: "json",
    formatversion: "2",
    origin: "*"
  });
  const res = await fetch(`https://commons.wikimedia.org/w/api.php?${params.toString()}`, {
    headers: {
      accept: "application/json",
      "user-agent": "Ooglex-Tech-Leaders-Avatar/4.2 (https://ooglex.com)"
    }
  });
  if (!res.ok) return { ok: false, status: res.status, source: "wikimedia_commons" };

  let payload = null;
  try { payload = await res.json(); } catch {}
  const pages = payload && payload.query && Array.isArray(payload.query.pages)
    ? payload.query.pages
    : [];

  for (const page of pages) {
    if (!page || !commonsTitleMatchesPerson(page.title, cleanName)) continue;
    const info = Array.isArray(page.imageinfo) ? page.imageinfo[0] : null;
    if (!info) continue;
    const src = info.thumburl || info.url || "";
    const mime = String(info.mime || "").toLowerCase();
    if (!src || (mime && !mime.startsWith("image/"))) continue;
    const image = await fetchAvatarImage(src, "wikimedia_commons");
    if (image.ok) return image;
  }
  return { ok: false, status: 404, source: "wikimedia_commons" };
}

async function resolveTechLeaderAvatar(handle, name, company) {
  const lower = handle.toLowerCase();

  if (TECH_AVATAR_OVERRIDES[lower]) {
    const official = await fetchAvatarImage(TECH_AVATAR_OVERRIDES[lower], "official_override");
    if (official.ok) return official;
  }

  const legacyProfile = await fetchAvatarImage(
    `https://twitter.com/${encodeURIComponent(handle)}/profile_image?size=original`,
    "x_profile_redirect"
  );
  if (legacyProfile.ok) return legacyProfile;

  const syndicated = await fetchAvatarViaSyndication(handle);
  if (syndicated.ok) return syndicated;

  const wikipedia = await fetchAvatarViaWikipedia(name, company);
  if (wikipedia.ok) return wikipedia;

  const commons = await fetchAvatarViaCommons(name);
  if (commons.ok) return commons;

  return fetchAvatarImage(
    `https://unavatar.io/x/${encodeURIComponent(handle)}?fallback=false`,
    "unavatar_x"
  );
}

async function getTechLeaderAvatar(handle, name, company, env) {
  const normalized = normalizeXHandle(handle);
  if (!normalized) {
    const err = new Error("invalid_avatar_handle");
    err.code = "invalid_avatar_handle";
    err.status = 400;
    throw err;
  }

  const key = `tech-leaders/avatars/${normalized.toLowerCase()}.bin`;
  const cached = await env.PRO_DATA.get(key);
  if (cached) {
    const headers = new Headers({
      "cache-control": TECH_AVATAR_CACHE_CONTROL,
      "x-ooglex-avatar-source": "r2",
      "x-ooglex-avatar-handle": normalized
    });
    const type = cached.httpMetadata && cached.httpMetadata.contentType
      ? cached.httpMetadata.contentType
      : "image/jpeg";
    headers.set("content-type", type);
    if (cached.etag) headers.set("etag", cached.etag);
    return { body: cached.body, headers };
  }

  const resolved = await resolveTechLeaderAvatar(normalized, name, company);
  if (!resolved.ok) {
    const err = new Error("avatar_upstream_unavailable");
    err.code = "avatar_upstream_unavailable";
    err.status = resolved.status || 502;
    throw err;
  }

  await env.PRO_DATA.put(key, resolved.bytes, {
    httpMetadata: {
      contentType: resolved.contentType,
      cacheControl: TECH_AVATAR_CACHE_CONTROL
    },
    customMetadata: {
      handle: normalized,
      source: resolved.source,
      fetched_at: new Date().toISOString()
    }
  });

  return {
    body: resolved.bytes,
    headers: new Headers({
      "content-type": resolved.contentType,
      "cache-control": TECH_AVATAR_CACHE_CONTROL,
      "x-ooglex-avatar-source": resolved.source + "-r2",
      "x-ooglex-avatar-handle": normalized
    })
  };
}

async function xApiGet(path, env) {
  if (!env.X_BEARER_TOKEN) {
    const err = new Error("x_api_not_configured");
    err.code = "x_api_not_configured";
    err.status = 503;
    throw err;
  }

  const res = await fetch(`https://api.x.com${path}`, {
    headers: {
      Authorization: `Bearer ${env.X_BEARER_TOKEN}`,
      "user-agent": "Ooglex-Tech-Leaders/2.0"
    }
  });

  if (!res.ok) {
    let detail = null;
    try { detail = await res.json(); } catch {}
    const err = new Error("x_api_error");
    err.code = "x_api_error";
    err.status = res.status;
    err.detail = detail;
    throw err;
  }
  return res.json();
}

function normalizeTechFeed(profile, user, payload) {
  const mediaByKey = new Map();
  const includes = payload && payload.includes ? payload.includes : {};
  const media = Array.isArray(includes.media) ? includes.media : [];
  for (const item of media) {
    if (item && item.media_key) mediaByKey.set(item.media_key, item);
  }

  const posts = (Array.isArray(payload && payload.data) ? payload.data : []).map((post) => {
    const keys = post && post.attachments && Array.isArray(post.attachments.media_keys)
      ? post.attachments.media_keys
      : [];
    return {
      id: String(post.id || ""),
      text: String(post.text || ""),
      created_at: post.created_at || null,
      lang: post.lang || null,
      metrics: post.public_metrics || {},
      entities: post.entities || {},
      media: keys.map((key) => mediaByKey.get(key)).filter(Boolean).map((item) => ({
        media_key: item.media_key,
        type: item.type,
        url: item.url || null,
        preview_image_url: item.preview_image_url || null,
        width: item.width || null,
        height: item.height || null
      })),
      url: `https://x.com/${profile.handle}/status/${post.id}`
    };
  });

  return {
    schema_version: 1,
    source: "x_api",
    leader: {
      id: profile.id,
      name: profile.name,
      handle: profile.handle,
      user_id: user.id,
      profile_image_url: user.profile_image_url || null,
      verified: Boolean(user.verified),
      public_metrics: user.public_metrics || {}
    },
    fetched_at: new Date().toISOString(),
    posts
  };
}

function techCacheMatchesProfile(profile, cached) {
  if (!profile || !cached || !cached.leader) return false;
  return String(cached.leader.handle || "").toLowerCase() === String(profile.handle || "").toLowerCase();
}

async function fetchTechLeaderFeed(profile, env, cached = null) {
  const cachedMatchesProfile = techCacheMatchesProfile(profile, cached);
  let user = null;
  if (cachedMatchesProfile && cached.leader && cached.leader.user_id) {
    user = {
      id: cached.leader.user_id,
      profile_image_url: cached.leader.profile_image_url || null,
      verified: Boolean(cached.leader.verified),
      public_metrics: cached.leader.public_metrics || {}
    };
  }

  if (!user) {
    const username = encodeURIComponent(profile.handle);
    const userPayload = await xApiGet(
      `/2/users/by/username/${username}?user.fields=profile_image_url,verified,public_metrics,description`,
      env
    );
    if (!userPayload || !userPayload.data || !userPayload.data.id) {
      const err = new Error("x_user_not_found");
      err.code = "x_user_not_found";
      err.status = 502;
      throw err;
    }
    user = userPayload.data;
  }

  const params = new URLSearchParams({
    max_results: String(TECH_FEED_FETCH_SIZE),
    exclude: "replies,retweets",
    "tweet.fields": "created_at,public_metrics,lang,entities,attachments,referenced_tweets",
    expansions: "attachments.media_keys",
    "media.fields": "media_key,type,url,preview_image_url,width,height"
  });

  const cachedPosts = cachedMatchesProfile && Array.isArray(cached.posts) ? cached.posts : [];
  const newestId = cachedPosts[0] && cachedPosts[0].id ? String(cachedPosts[0].id) : "";
  if (newestId) params.set("since_id", newestId);

  const postsPayload = await xApiGet(`/2/users/${encodeURIComponent(user.id)}/tweets?${params.toString()}`, env);
  const incoming = normalizeTechFeed(profile, user, postsPayload);

  if (!cachedPosts.length) return incoming;

  const merged = [];
  const seen = new Set();
  for (const post of [...incoming.posts, ...cachedPosts]) {
    if (!post || !post.id || seen.has(post.id)) continue;
    seen.add(post.id);
    merged.push(post);
  }
  merged.sort((a, b) => {
    const ta = Date.parse(a.created_at || "") || 0;
    const tb = Date.parse(b.created_at || "") || 0;
    return tb - ta;
  });

  return {
    ...incoming,
    posts: merged.slice(0, TECH_FEED_FETCH_SIZE)
  };
}

async function getTechLeaderFeed(profile, limit, env) {
  const key = `tech-leaders/${profile.id}.json`;
  const cached = await readJson(env.PRO_DATA, key);
  const now = Date.now();
  const cachedAt = cached && cached.fetched_at ? Date.parse(cached.fetched_at) : NaN;
  const age = Number.isFinite(cachedAt) ? now - cachedAt : Infinity;

  const cachedMatchesProfile = techCacheMatchesProfile(profile, cached);

  if (cachedMatchesProfile && age <= TECH_FEED_TTL_MS) {
    return {
      ...cached,
      posts: Array.isArray(cached.posts) ? cached.posts.slice(0, limit) : [],
      cache: { status: "fresh", age_ms: age }
    };
  }

  if (!env.X_BEARER_TOKEN) {
    if (cachedMatchesProfile && age <= TECH_FEED_MAX_STALE_MS) {
      return {
        ...cached,
        posts: Array.isArray(cached.posts) ? cached.posts.slice(0, limit) : [],
        cache: { status: "stale", age_ms: age, reason: "x_api_not_configured" }
      };
    }
    const err = new Error("x_api_not_configured");
    err.code = "x_api_not_configured";
    err.status = 503;
    throw err;
  }

  try {
    const fresh = await fetchTechLeaderFeed(profile, env, cached);
    await writeJson(env.PRO_DATA, key, fresh);
    return {
      ...fresh,
      posts: fresh.posts.slice(0, limit),
      cache: { status: "refreshed", age_ms: 0 }
    };
  } catch (err) {
    if (cachedMatchesProfile && age <= TECH_FEED_MAX_STALE_MS) {
      return {
        ...cached,
        posts: Array.isArray(cached.posts) ? cached.posts.slice(0, limit) : [],
        cache: {
          status: "stale",
          age_ms: age,
          reason: err && err.code ? err.code : "x_api_error"
        }
      };
    }
    throw err;
  }
}

export default {
  async fetch(request, env) {
    const cors = corsHeaders(request, env);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    if (request.method !== "GET") return json({ error: "method_not_allowed" }, 405, cors);

    if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY || !env.PRO_DATA) {
      return json({ error: "service_not_configured" }, 503, cors);
    }

    const url = new URL(request.url);
    const token = bearerToken(request);

    if (url.pathname === "/health") {
      return json({ ok: true, service: "ooglex-pro-api" }, 200, { ...cors, "cache-control": "no-store" });
    }

    if (url.pathname === "/v1/access") {
      const product = url.searchParams.get("product") || "";
      if (!PRODUCTS[product]) return json({ error: "unknown_product" }, 400, cors);
      const access = await getAccess(product, token, env);
      return json({ product, ...access }, 200, { ...cors, "cache-control": "no-store" });
    }

    if (url.pathname === "/v1/tech-leaders/avatar") {
      const handle = normalizeXHandle(url.searchParams.get("handle"));
      const name = String(url.searchParams.get("name") || "").trim().slice(0, 120);
      const company = String(url.searchParams.get("company") || "").trim().slice(0, 120);
      if (!handle) return json({ error: "invalid_avatar_handle" }, 400, cors);
      try {
        const avatar = await getTechLeaderAvatar(handle, name, company, env);
        const headers = new Headers(cors);
        avatar.headers.forEach((value, name) => headers.set(name, value));
        return new Response(avatar.body, { status: 200, headers });
      } catch (err) {
        const code = err && err.code ? err.code : "avatar_unavailable";
        const status = err && Number.isInteger(err.status) ? err.status : 502;
        return json({ error: code, handle }, status, { ...cors, "cache-control": "no-store" });
      }
    }

    if (url.pathname === "/v1/tech-leaders/status") {
      return json({
        ok: true,
        service: "tech-leaders",
        source: "x_api",
        configured: Boolean(env.X_BEARER_TOKEN),
        cache_ttl_seconds: Math.round(TECH_FEED_TTL_MS / 1000),
        leaders: Object.values(TECH_LEADERS).map(({ id, handle, name }) => ({ id, handle, name }))
      }, 200, { ...cors, "cache-control": "public, max-age=60" });
    }

    if (url.pathname === "/v1/tech-leaders/feed") {
      const leaderId = url.searchParams.get("leader") || "musk";
      const profile = TECH_LEADERS[leaderId];
      if (!profile) return json({ error: "unknown_leader" }, 400, cors);

      const limit = boundedInt(url.searchParams.get("limit"), 1, TECH_FEED_FETCH_SIZE, 8);
      try {
        const feed = await getTechLeaderFeed(profile, limit, env);
        return json(feed, 200, {
          ...cors,
          "cache-control": "public, max-age=60, stale-while-revalidate=300",
          "x-ooglex-source": "x-api"
        });
      } catch (err) {
        const code = err && err.code ? err.code : "tech_feed_unavailable";
        const status = err && Number.isInteger(err.status) ? err.status : 502;
        return json({
          error: code,
          leader: leaderId,
          configured: Boolean(env.X_BEARER_TOKEN),
          upstream_status: err && err.status ? err.status : null
        }, status, { ...cors, "cache-control": "no-store" });
      }
    }

    const m = url.pathname.match(/^\/v1\/data\/([a-z_]+)$/);
    if (!m) return json({ error: "not_found" }, 404, cors);

    const product = m[1];
    const def = PRODUCTS[product];
    if (!def) return json({ error: "unknown_product" }, 400, cors);

    const mode = url.searchParams.get("mode") === "full" ? "full" : "preview";
    const access = await getAccess(product, token, env);

    if (mode === "full" && access.access_level !== "full") {
      return json({
        error: access.authenticated ? "pro_required" : "sign_in_required",
        product,
        plan: access.plan,
        access_level: access.access_level
      }, access.authenticated ? 403 : 401, { ...cors, "cache-control": "no-store" });
    }

    const key = mode === "full" ? def.fullKey : def.previewKey;
    const dataset = await readDataset(env.PRO_DATA, key);
    if (!dataset) return json({ error: "dataset_not_ready", product, mode }, 503, cors);

    const headers = new Headers(cors);
    dataset.headers.forEach((value, name) => headers.set(name, value));
    headers.set("x-ooglex-product", product);
    headers.set("x-ooglex-access", mode);
    headers.set("cache-control", mode === "full" ? "private, no-store" : "public, max-age=300");

    return new Response(dataset.body, { status: 200, headers });
  }
};
