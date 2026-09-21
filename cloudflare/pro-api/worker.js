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
const TECH_FREE_FEED_MAX_ITEMS = 100;
const TECH_FREE_FEED_TTL_MS = 10 * 60 * 1000;
const TECH_FREE_FEED_STRICT_TTL_MS = 60 * 1000;
const TECH_FREE_FEED_MAX_STALE_MS = 12 * 60 * 60 * 1000;
const ELON_TEMP_REFRESH_POST_ID = "2101601873115681037";
const ELON_TEMP_REFRESH_UNTIL_MS = Date.parse("2026-09-21T00:00:00Z");
const TECH_PROFILE_CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const TECH_PROFILE_MAX_STALE_MS = 7 * 24 * 60 * 60 * 1000;

const TECH_AVATAR_MAX_BYTES = 3 * 1024 * 1024;
const TECH_AVATAR_CACHE_CONTROL = "public, max-age=21600, stale-while-revalidate=86400";
const TECH_AVATAR_CACHE_VERSION = "v7-complete-portraits";
const TECH_AVATAR_POLICY = "x_original_then_verified_fallback";
const TECH_AVATAR_REFRESH_X_MS = 72 * 60 * 60 * 1000;
const TECH_AVATAR_REFRESH_PROXY_MS = 24 * 60 * 60 * 1000;
const TECH_AVATAR_REFRESH_FALLBACK_MS = 6 * 60 * 60 * 1000;

// Only use explicit fallback portraits from first-party company/institution sources.
// These are consulted only after all X-avatar routes fail.
const TECH_AVATAR_OFFICIAL_OVERRIDES = Object.freeze({
  rickrieder: "https://www.blackrock.com/apac-retail-c-assets/cache-1700544361000/images/media-bin/web/retail/apac/jp/insight/Rick-Rieder-profile.jpg",
  rajaxg: "https://d1io3yog0oux5.cloudfront.net/_3ccf9cf30376bf77bbb27f582e51d00d/intel/news/193/1779/image.jpeg",
  sytses: "https://res.cloudinary.com/about-gitlab-com/image/upload/v1755613184/abfz99qjcfcvo6em0sgm.webp",
  svlevine: "https://vcresearch.berkeley.edu/sites/default/files/styles/faculty_photo_thumbnail/public/2023-04/sergey_levin_20200122_AVL_0050.jpg?h=726b1c9d&itok=Aa7Rxyv2",
  aselipsky: "https://www.helixdi.com/wp-content/uploads/2026/04/Adam-Selipsky.png",
  thetimellis: "https://images.squarespace-cdn.com/content/v1/59a8fb50d2b8575fad311abb/32f80d6d-e088-4fa8-a0d8-76db4966ac46/Tim_Ellis_Web.png",
  marvinrellison: "https://corporate.lowes.com/sites/lowes-corp/files/BOD-images/Marvin-R.Ellison_0.jpg",
  alq: "https://corp.dd-static.net/img/Portraits/alexis-le-quoc-2025.png?auto=format&fit=max&format=png&w=264",
  avishaiabrahami: "https://static.wixstatic.com/media/4a5235_03f03c77230a4960a552b2aff5e517b6~mv2.jpg",
  benoitdageville: "https://www.snowflake.com/wp-content/uploads/2026/04/Benoit.jpeg",
  tusharjain_: "https://images.ctfassets.net/qtbqvna1l0yq/3LcBoPhx9u1NmekXCX3wrZ/06be87a284486f9e1a41af419e4e0a87/tushar_headshot_2022_cropped.png?f=face&fit=fill&fm=png&h=1326&q=50&w=1326"
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
    "access-control-expose-headers": "x-ooglex-avatar-source,x-ooglex-avatar-source-type,x-ooglex-avatar-handle",
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

function techAvatarCacheKey(handle) {
  return `tech-leaders/avatars/${TECH_AVATAR_CACHE_VERSION}/${String(handle || "").toLowerCase()}.bin`;
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

function avatarSourceType(sourceValue) {
  const source = String(sourceValue || "").toLowerCase().replace(/-r2(?:-cache)?$/, "");
  if (source === "x_profile_redirect_x" || source === "x_profile_redirect" || source === "x_followbutton" || source === "x_syndication") return "x_original";
  if (source === "unavatar_x" || source === "fxtwitter_profile") return "x_original_proxy";
  if (source === "official_override") return "official_fallback";
  if (source === "generated_initials") return "generated_fallback";
  if (source === "wikipedia" || source === "wikimedia_commons") return "public_fallback";
  return "unknown";
}

function findXProfileImageUrl(value, depth = 0) {
  if (depth > 14 || value == null) return "";
  if (typeof value === "string") {
    return /^https:\/\/pbs\.twimg\.com\/profile_images\//i.test(value)
      ? twitterProfileImageLarge(value)
      : "";
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findXProfileImageUrl(item, depth + 1);
      if (found) return found;
    }
    return "";
  }
  if (typeof value === "object") {
    const keys = Object.keys(value);
    const preferred = keys.filter((key) => /profile.*image|image.*profile|avatar/i.test(key));
    for (const key of preferred) {
      const found = findXProfileImageUrl(value[key], depth + 1);
      if (found) return found;
    }
    for (const key of keys) {
      const found = findXProfileImageUrl(value[key], depth + 1);
      if (found) return found;
    }
  }
  return "";
}

async function fetchTechAvatarImage(url, source) {
  const res = await fetch(url, {
    redirect: "follow",
    headers: {
      accept: "image/avif,image/webp,image/png,image/jpeg,image/*,*/*;q=0.8",
      "user-agent": "Mozilla/5.0 (compatible; Ooglex-Tech-Leaders-Avatar/5.1)"
    }
  });
  if (!res.ok) return { ok: false, status: res.status, source };
  const contentType = String(res.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
  if (!contentType.startsWith("image/")) return { ok: false, status: 502, source };
  const bytes = await res.arrayBuffer();
  if (!bytes.byteLength || bytes.byteLength > TECH_AVATAR_MAX_BYTES) return { ok: false, status: 502, source };
  return { ok: true, bytes, contentType, source, sourceType: avatarSourceType(source), sourceUrl: res.url || url };
}

async function fetchTechAvatarViaFollowButton(handle) {
  const url = `https://cdn.syndication.twimg.com/widgets/followbutton/info.json?screen_names=${encodeURIComponent(handle)}`;
  const res = await fetch(url, {
    redirect: "follow",
    headers: {
      accept: "application/json,text/plain,*/*",
      "user-agent": "Mozilla/5.0 (compatible; Ooglex-Tech-Leaders-Avatar/6.0)"
    }
  });
  if (!res.ok) return { ok: false, status: res.status, source: "x_followbutton" };
  let data = null;
  try { data = await res.json(); } catch {}
  const imageUrl = findXProfileImageUrl(data);
  if (!imageUrl) return { ok: false, status: 404, source: "x_followbutton" };
  return fetchTechAvatarImage(imageUrl, "x_followbutton");
}

async function fetchTechAvatarViaSyndication(handle) {
  const url = `https://syndication.twitter.com/srv/timeline-profile/screen-name/${encodeURIComponent(handle)}`;
  const res = await fetch(url, {
    redirect: "follow",
    headers: {
      accept: "text/html,application/xhtml+xml",
      "user-agent": "Mozilla/5.0 (compatible; Ooglex-Tech-Leaders-Avatar/5.1)"
    }
  });
  if (!res.ok) return { ok: false, status: res.status, source: "x_syndication" };
  const html = await res.text();
  let imageUrl = "";
  const next = html.match(/<script[^>]+id=["']__NEXT_DATA__["'][^>]*>([\s\S]*?)<\/script>/i);
  if (next && next[1]) {
    try { imageUrl = findXProfileImageUrl(JSON.parse(next[1])); } catch {}
  }
  if (!imageUrl) {
    const normalized = html.replace(/\\u002F/gi, "/").replace(/\\\//g, "/").replace(/&amp;/g, "&");
    const match = normalized.match(/https:\/\/pbs\.twimg\.com\/profile_images\/[^"'<>\s\\]+/i);
    if (match) imageUrl = twitterProfileImageLarge(match[0]);
  }
  if (!imageUrl) return { ok: false, status: 404, source: "x_syndication" };
  return fetchTechAvatarImage(imageUrl, "x_syndication");
}

async function fetchTechAvatarViaFxTwitterProfile(handle, name) {
  try {
    const profile = await fetchFxTwitterPublicProfile(handle, name);
    const imageUrl = profile && profile.profile_image_url
      ? twitterProfileImageLarge(profile.profile_image_url)
      : "";
    if (!imageUrl) return { ok: false, status: 404, source: "fxtwitter_profile" };
    return fetchTechAvatarImage(imageUrl, "fxtwitter_profile");
  } catch (err) {
    return {
      ok: false,
      status: Number(err && err.status) || 502,
      source: "fxtwitter_profile"
    };
  }
}

function xProfileExpandedUrl(value) {
  if (!value || typeof value !== "object") return "";
  const direct = String(value.expanded_url || value.expandedUrl || value.url || "").trim();
  if (/^https?:\/\//i.test(direct) && !/^(https?:\/\/)?t\.co\//i.test(direct)) return direct;
  const entities = value.entities && value.entities.url && Array.isArray(value.entities.url.urls)
    ? value.entities.url.urls
    : [];
  for (const item of entities) {
    const expanded = String(item && (item.expanded_url || item.expandedUrl) || "").trim();
    if (/^https?:\/\//i.test(expanded)) return expanded;
  }
  return "";
}

function normalizePublicXProfile(candidate, handle) {
  if (!candidate || typeof candidate !== "object") return null;
  const screenName = String(candidate.screen_name || candidate.username || candidate.handle || "").replace(/^@/, "");
  if (screenName && screenName.toLowerCase() !== String(handle || "").toLowerCase()) return null;
  const metrics = candidate.public_metrics && typeof candidate.public_metrics === "object" ? candidate.public_metrics : {};
  const followers = candidate.followers_count ?? metrics.followers_count;
  const following = candidate.friends_count ?? candidate.following_count ?? metrics.following_count;
  const createdAt = candidate.created_at || candidate.createdAt || null;
  const url = xProfileExpandedUrl(candidate);
  const profileImage = candidate.profile_image_url_https || candidate.profile_image_url || "";
  const name = String(candidate.name || "").trim();
  const description = String(candidate.description || "").trim();
  const hasUseful = followers != null || following != null || createdAt || url || profileImage || description;
  if (!hasUseful) return null;
  return {
    handle: screenName || String(handle || ""),
    name,
    followers_count: followers == null ? null : Number(followers),
    following_count: following == null ? null : Number(following),
    created_at: createdAt || null,
    url: url || null,
    display_url: url ? url.replace(/^https?:\/\/(www\.)?/i, "").replace(/\/$/, "") : null,
    description: description || null,
    profile_image_url: profileImage || null
  };
}

function findPublicXProfile(value, handle, depth = 0) {
  if (depth > 16 || value == null) return null;
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findPublicXProfile(item, handle, depth + 1);
      if (found) return found;
    }
    return null;
  }
  if (typeof value !== "object") return null;

  const normalized = normalizePublicXProfile(value, handle);
  const candidateHandle = String(value.screen_name || value.username || value.handle || "").replace(/^@/, "");
  if (normalized && (!candidateHandle || candidateHandle.toLowerCase() === String(handle || "").toLowerCase())) return normalized;

  const keys = Object.keys(value);
  const preferred = keys.filter((key) => /user|profile|account|author/i.test(key));
  for (const key of [...preferred, ...keys.filter((key) => !preferred.includes(key))]) {
    const found = findPublicXProfile(value[key], handle, depth + 1);
    if (found) return found;
  }
  return null;
}

function mergePublicXProfiles(primary, secondary, handle, name) {
  const a = primary || {};
  const b = secondary || {};
  return {
    schema_version: 1,
    source: "x_public_syndication",
    uses_x_api: false,
    handle: a.handle || b.handle || handle,
    name: a.name || b.name || name || "",
    followers_count: a.followers_count ?? b.followers_count ?? null,
    following_count: a.following_count ?? b.following_count ?? null,
    created_at: a.created_at || b.created_at || null,
    url: a.url || b.url || null,
    display_url: a.display_url || b.display_url || null,
    description: a.description || b.description || null,
    profile_image_url: a.profile_image_url || b.profile_image_url || null,
    fetched_at: new Date().toISOString()
  };
}

function normalizeXApiPublicProfile(data, handle, name) {
  if (!data || typeof data !== "object") return null;
  const metrics = data.public_metrics && typeof data.public_metrics === "object" ? data.public_metrics : {};
  const url = String(data.url || "").trim();
  return {
    schema_version: 1,
    source: "x_api_profile_cache",
    uses_x_api: true,
    handle: String(data.username || handle || ""),
    name: String(data.name || name || ""),
    followers_count: metrics.followers_count == null ? null : Number(metrics.followers_count),
    following_count: metrics.following_count == null ? null : Number(metrics.following_count),
    created_at: data.created_at || null,
    url: url || null,
    display_url: url ? url.replace(/^https?:\/\/(www\.)?/i, "").replace(/\/$/, "") : null,
    description: data.description || null,
    profile_image_url: data.profile_image_url || null,
    verified: Boolean(data.verified),
    fetched_at: new Date().toISOString()
  };
}

async function fetchXApiPublicProfile(handle, name, env) {
  if (!env.X_BEARER_TOKEN) return null;
  const username = encodeURIComponent(handle);
  const payload = await xApiGet(
    `/2/users/by/username/${username}?user.fields=created_at,public_metrics,url,description,profile_image_url,verified`,
    env
  );
  if (!payload || !payload.data) return null;
  return normalizeXApiPublicProfile(payload.data, handle, name);
}

function publicProfileComplete(profile) {
  return Boolean(
    profile &&
    profile.followers_count != null &&
    profile.following_count != null &&
    profile.created_at
  );
}

function mergeProfileSupplement(primary, supplement, handle, name) {
  const a = primary || {};
  const b = supplement || {};
  return {
    schema_version: 1,
    source: b.uses_x_api ? "x_public_then_api_cache" : (a.source || b.source || "x_public_syndication"),
    uses_x_api: Boolean(b.uses_x_api),
    handle: a.handle || b.handle || handle,
    name: a.name || b.name || name || "",
    followers_count: a.followers_count ?? b.followers_count ?? null,
    following_count: a.following_count ?? b.following_count ?? null,
    created_at: a.created_at || b.created_at || null,
    url: a.url || b.url || null,
    display_url: a.display_url || b.display_url || null,
    description: a.description || b.description || null,
    profile_image_url: a.profile_image_url || b.profile_image_url || null,
    verified: Boolean(a.verified || b.verified),
    fetched_at: new Date().toISOString()
  };
}


async function fetchPublicXProfile(handle, name) {
  let followProfile = null;
  let syndicationProfile = null;

  try {
    const res = await fetch(
      `https://cdn.syndication.twimg.com/widgets/followbutton/info.json?screen_names=${encodeURIComponent(handle)}`,
      {
        redirect: "follow",
        headers: {
          accept: "application/json,text/plain,*/*",
          "user-agent": "Mozilla/5.0 (compatible; Ooglex-Tech-Leaders-Profile/1.0)"
        }
      }
    );
    if (res.ok) {
      const payload = await res.json();
      followProfile = findPublicXProfile(payload, handle);
    }
  } catch {}

  try {
    const res = await fetch(
      `https://syndication.twitter.com/srv/timeline-profile/screen-name/${encodeURIComponent(handle)}`,
      {
        redirect: "follow",
        headers: {
          accept: "text/html,application/xhtml+xml",
          "user-agent": "Mozilla/5.0 (compatible; Ooglex-Tech-Leaders-Profile/1.0)"
        }
      }
    );
    if (res.ok) {
      const html = await res.text();
      const next = html.match(/<script[^>]+id=["']__NEXT_DATA__["'][^>]*>([\s\S]*?)<\/script>/i);
      if (next && next[1]) {
        try { syndicationProfile = findPublicXProfile(JSON.parse(next[1]), handle); } catch {}
      }
    }
  } catch {}

  const merged = mergePublicXProfiles(syndicationProfile, followProfile, handle, name);
  if (publicProfileComplete(merged)) return merged;
  return merged;
}

function normalizeFxTwitterPublicProfile(payload, handle, name) {
  const user = payload && payload.user && typeof payload.user === "object" ? payload.user : null;
  if (!user) return null;

  const website = user.website && typeof user.website === "object" ? user.website : null;
  const websiteUrl = website && website.url ? String(website.url).trim() : "";
  const displayUrl = website && website.display_url
    ? String(website.display_url).trim()
    : (websiteUrl ? websiteUrl.replace(/^https?:\/\/(www\.)?/i, "").replace(/\/$/, "") : "");

  const followers = user.followers == null ? null : Number(user.followers);
  const following = user.following == null ? null : Number(user.following);
  const joined = user.joined || null;
  const avatar = user.avatar_url || null;
  const description = user.description || null;
  const verification = user.verification && typeof user.verification === "object" ? user.verification : {};

  const usable = (
    (Number.isFinite(followers) && followers >= 0) ||
    (Number.isFinite(following) && following >= 0) ||
    joined ||
    websiteUrl ||
    avatar ||
    description
  );
  if (!usable) return null;

  return {
    schema_version: 1,
    source: "fxtwitter_public_profile",
    uses_x_api: false,
    handle: String(user.screen_name || handle || ""),
    name: String(user.name || name || ""),
    followers_count: Number.isFinite(followers) && followers >= 0 ? followers : null,
    following_count: Number.isFinite(following) && following >= 0 ? following : null,
    created_at: joined,
    url: websiteUrl || null,
    display_url: displayUrl || null,
    description: description || null,
    profile_image_url: avatar || null,
    verified: Boolean(verification.verified),
    fetched_at: new Date().toISOString()
  };
}

async function fetchFxTwitterPublicProfile(handle, name) {
  const res = await fetch(
    `https://api.fxtwitter.com/2/profile/${encodeURIComponent(handle)}`,
    {
      redirect: "follow",
      headers: {
        accept: "application/json",
        "user-agent": "Ooglex-Tech-Leaders-Free-Profile/1.0"
      }
    }
  );

  let payload = null;
  try { payload = await res.json(); } catch {}
  if (!res.ok || !payload || Number(payload.code || res.status) >= 400) {
    const err = new Error("fxtwitter_public_profile_error");
    err.code = "fxtwitter_public_profile_error";
    err.status = res.status || Number(payload && payload.code) || 502;
    throw err;
  }

  const profile = normalizeFxTwitterPublicProfile(payload, handle, name);
  if (!profile) {
    const err = new Error("fxtwitter_public_profile_empty");
    err.code = "fxtwitter_public_profile_empty";
    err.status = 502;
    throw err;
  }
  return profile;
}

async function getFreePublicXProfile(handle, name, env) {
  const normalized = normalizeXHandle(handle);
  if (!normalized) {
    const err = new Error("invalid_profile_handle");
    err.code = "invalid_profile_handle";
    err.status = 400;
    throw err;
  }

  const key = `tech-leaders/profiles/free/v1/${normalized.toLowerCase()}.json`;
  const cached = await readJson(env.PRO_DATA, key);
  const cachedAt = cached && cached.fetched_at ? Date.parse(cached.fetched_at) : NaN;
  const age = Number.isFinite(cachedAt) ? Date.now() - cachedAt : Infinity;

  if (cached && age <= TECH_PROFILE_CACHE_TTL_MS) {
    return {
      ...cached,
      uses_x_api: false,
      cache: { status: "fresh", age_ms: age }
    };
  }

  try {
    const publicProfile = await fetchPublicXProfile(normalized, name);
    let fresh = {
      ...(publicProfile || {}),
      handle: publicProfile && publicProfile.handle ? publicProfile.handle : normalized,
      name: publicProfile && publicProfile.name ? publicProfile.name : (name || ""),
      source: publicProfile && publicProfile.source ? publicProfile.source : "x_public_sources",
      uses_x_api: false,
      fetched_at: new Date().toISOString()
    };

    if (!publicProfileComplete(fresh)) {
      try {
        const fxProfile = await fetchFxTwitterPublicProfile(normalized, name);
        fresh = mergeProfileSupplement(fresh, fxProfile, normalized, name);
        fresh.source = "x_public_then_fxtwitter";
        fresh.uses_x_api = false;
      } catch {}
    }

    const usable = fresh && (
      fresh.followers_count != null ||
      fresh.following_count != null ||
      fresh.created_at ||
      fresh.url ||
      fresh.profile_image_url
    );
    if (!usable) {
      const err = new Error("x_public_profile_unavailable");
      err.code = "x_public_profile_unavailable";
      err.status = 502;
      throw err;
    }
    await writeJson(env.PRO_DATA, key, fresh);
    return { ...fresh, cache: { status: "refreshed", age_ms: 0 } };
  } catch (err) {
    if (cached && age <= TECH_PROFILE_MAX_STALE_MS) {
      return {
        ...cached,
        uses_x_api: false,
        cache: {
          status: "stale",
          age_ms: age,
          reason: err && err.code ? err.code : "x_public_profile_error"
        }
      };
    }
    throw err;
  }
}

async function getPublicXProfile(handle, name, env) {
  const normalized = normalizeXHandle(handle);
  if (!normalized) {
    const err = new Error("invalid_profile_handle");
    err.code = "invalid_profile_handle";
    err.status = 400;
    throw err;
  }
  const key = `tech-leaders/profiles/v2/${normalized.toLowerCase()}.json`;
  const cached = await readJson(env.PRO_DATA, key);
  const cachedAt = cached && cached.fetched_at ? Date.parse(cached.fetched_at) : NaN;
  const age = Number.isFinite(cachedAt) ? Date.now() - cachedAt : Infinity;
  if (cached && publicProfileComplete(cached) && age <= TECH_PROFILE_CACHE_TTL_MS) {
    return { ...cached, cache: { status: "fresh", age_ms: age } };
  }

  try {
    const publicProfile = await fetchPublicXProfile(normalized, name);
    let fresh = publicProfile;
    if (!publicProfileComplete(publicProfile)) {
      const apiProfile = await fetchXApiPublicProfile(normalized, name, env);
      if (apiProfile) fresh = mergeProfileSupplement(publicProfile, apiProfile, normalized, name);
    }
    const usable = fresh && (fresh.followers_count != null || fresh.following_count != null || fresh.created_at || fresh.url);
    if (!usable) {
      const err = new Error("x_profile_metrics_unavailable");
      err.code = "x_profile_metrics_unavailable";
      err.status = 502;
      throw err;
    }
    await writeJson(env.PRO_DATA, key, fresh);
    return { ...fresh, cache: { status: "refreshed", age_ms: 0 } };
  } catch (err) {
    if (cached && publicProfileComplete(cached) && age <= TECH_PROFILE_MAX_STALE_MS) {
      return { ...cached, cache: { status: "stale", age_ms: age, reason: err && err.code ? err.code : "x_profile_error" } };
    }
    throw err;
  }
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
  const tokens = n.split(/\s+/).filter((x) => x.length >= 2);
  if (!tokens.length) return false;
  if (tokens.length === 1) return t.split(/\s+/).includes(tokens[0]);
  const first = tokens[0];
  const last = tokens[tokens.length - 1];
  return t.includes(first) && t.includes(last);
}

async function fetchTechAvatarViaWikipedia(name, company) {
  const cleanName = String(name || "").trim().slice(0, 120);
  const cleanCompany = String(company || "").trim().slice(0, 120);
  if (!cleanName) return { ok: false, status: 400, source: "wikipedia" };

  const queries = [];
  const withCompany = [cleanName, cleanCompany].filter(Boolean).join(" ");
  if (withCompany) queries.push(withCompany);
  if (!queries.includes(cleanName)) queries.push(cleanName);

  for (const query of queries) {
    const params = new URLSearchParams({
      action: "query",
      generator: "search",
      gsrsearch: query,
      gsrnamespace: "0",
      gsrlimit: "8",
      prop: "pageimages",
      pithumbsize: "500",
      pilimit: "8",
      format: "json",
      formatversion: "2",
      origin: "*"
    });

    const res = await fetch(`https://en.wikipedia.org/w/api.php?${params.toString()}`, {
      headers: {
        accept: "application/json",
        "user-agent": "Ooglex-Tech-Leaders-Avatar/6.1 (https://ooglex.com)"
      }
    });
    if (!res.ok) continue;

    let payload = null;
    try { payload = await res.json(); } catch {}
    const pages = payload && payload.query && Array.isArray(payload.query.pages) ? payload.query.pages : [];

    for (const page of pages) {
      if (!page || !page.thumbnail || !page.thumbnail.source) continue;
      if (!wikiTitleMatchesPerson(page.title, cleanName)) continue;
      const image = await fetchTechAvatarImage(page.thumbnail.source, "wikipedia");
      if (image.ok) return image;
    }
  }
  return { ok: false, status: 404, source: "wikipedia" };
}

async function fetchTechAvatarViaCommons(name) {
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
      "user-agent": "Ooglex-Tech-Leaders-Avatar/5.1 (https://ooglex.com)"
    }
  });
  if (!res.ok) return { ok: false, status: res.status, source: "wikimedia_commons" };

  let payload = null;
  try { payload = await res.json(); } catch {}
  const pages = payload && payload.query && Array.isArray(payload.query.pages) ? payload.query.pages : [];

  for (const page of pages) {
    if (!page || !wikiTitleMatchesPerson(page.title, cleanName)) continue;
    const info = Array.isArray(page.imageinfo) ? page.imageinfo[0] : null;
    if (!info) continue;
    const src = info.thumburl || info.url || "";
    const mime = String(info.mime || "").toLowerCase();
    if (!src || (mime && !mime.startsWith("image/"))) continue;
    const image = await fetchTechAvatarImage(src, "wikimedia_commons");
    if (image.ok) return image;
  }
  return { ok: false, status: 404, source: "wikimedia_commons" };
}

function techAvatarInitials(name, handle) {
  const raw = String(name || handle || "?").trim();
  const latin = raw.split(/\s+/).filter(Boolean);
  if (/[A-Za-z]/.test(raw) && latin.length > 1) {
    return (latin[0][0] + latin[latin.length - 1][0]).toUpperCase();
  }
  return raw.slice(0, 2).toUpperCase();
}

function techAvatarSvgEscape(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function generatedTechLeaderAvatar(name, handle) {
  const initials = techAvatarSvgEscape(techAvatarInitials(name, handle));
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><rect width="256" height="256" rx="128" fill="#e8e0d7"/><circle cx="128" cy="128" r="126" fill="none" stroke="#d3c8bd" stroke-width="4"/><text x="128" y="145" text-anchor="middle" font-family="Arial,Helvetica,sans-serif" font-size="78" font-weight="700" fill="#655c54">${initials}</text></svg>`;
  const bytes = new TextEncoder().encode(svg);
  return {
    ok: true,
    bytes: bytes.buffer,
    contentType: "image/svg+xml",
    source: "generated_initials",
    sourceType: "generated_fallback"
  };
}

async function resolveTechLeaderAvatar(handle, name, company) {
  // 1) Exhaust current X-owned/current-profile routes first.
  const directX = await fetchTechAvatarImage(
    `https://x.com/${encodeURIComponent(handle)}/profile_image?size=original`,
    "x_profile_redirect_x"
  );
  if (directX.ok) return directX;

  const direct = await fetchTechAvatarImage(
    `https://twitter.com/${encodeURIComponent(handle)}/profile_image?size=original`,
    "x_profile_redirect"
  );
  if (direct.ok) return direct;

  const followButton = await fetchTechAvatarViaFollowButton(handle);
  if (followButton.ok) return followButton;

  const syndicated = await fetchTechAvatarViaSyndication(handle);
  if (syndicated.ok) return syndicated;

  // 2) Public X-profile mirrors. FxTwitter is already used by the free-profile
  // path and often succeeds for accounts that X syndication does not expose.
  const fxProfile = await fetchTechAvatarViaFxTwitterProfile(handle, name);
  if (fxProfile.ok) return fxProfile;

  const xProxy = await fetchTechAvatarImage(
    `https://unavatar.io/x/${encodeURIComponent(handle)}?fallback=false`,
    "unavatar_x"
  );
  if (xProxy.ok) return xProxy;

  // 3) Verified first-party company / institution portrait.
  const officialUrl = TECH_AVATAR_OFFICIAL_OVERRIDES[String(handle || "").toLowerCase()];
  if (officialUrl) {
    const official = await fetchTechAvatarImage(officialUrl, "official_override");
    if (official.ok) return official;
  }

  // 4) Conservative public portrait fallbacks.
  const wikipedia = await fetchTechAvatarViaWikipedia(name, company);
  if (wikipedia.ok) return wikipedia;

  const commons = await fetchTechAvatarViaCommons(name);
  if (commons.ok) return commons;

  // 5) Never return a broken avatar. Keep this source explicit so it is never
  // confused with a verified photographic portrait.
  return generatedTechLeaderAvatar(name, handle);
}

async function getTechLeaderAvatar(handle, name, company, env) {
  const normalized = normalizeXHandle(handle);
  if (!normalized) {
    const err = new Error("invalid_avatar_handle");
    err.code = "invalid_avatar_handle";
    err.status = 400;
    throw err;
  }

  const key = techAvatarCacheKey(normalized);
  const cached = await env.PRO_DATA.get(key);
  let cachedMeta = null;
  let cachedSource = "unknown";
  let cachedSourceType = "unknown";
  let cachedNeedsRefresh = false;

  if (cached) {
    cachedMeta = cached.customMetadata || {};
    cachedSource = cachedMeta.source ? String(cachedMeta.source) : "unknown";
    cachedSourceType = cachedMeta.source_type
      ? String(cachedMeta.source_type)
      : avatarSourceType(cachedSource);
    const fetchedAtMs = Date.parse(String(cachedMeta.fetched_at || ""));
    const ageMs = Number.isFinite(fetchedAtMs) ? Math.max(0, Date.now() - fetchedAtMs) : Number.POSITIVE_INFINITY;
    const refreshAfterMs = cachedSourceType === "x_original"
      ? TECH_AVATAR_REFRESH_X_MS
      : cachedSourceType === "x_original_proxy"
        ? TECH_AVATAR_REFRESH_PROXY_MS
        : TECH_AVATAR_REFRESH_FALLBACK_MS;
    cachedNeedsRefresh = ageMs >= refreshAfterMs;

    if (!cachedNeedsRefresh) {
      const headers = new Headers({
        "cache-control": TECH_AVATAR_CACHE_CONTROL,
        "x-ooglex-avatar-source": cachedSource + "-r2-cache",
        "x-ooglex-avatar-source-type": cachedSourceType,
        "x-ooglex-avatar-handle": normalized
      });
      const type = cached.httpMetadata && cached.httpMetadata.contentType
        ? cached.httpMetadata.contentType
        : "image/jpeg";
      headers.set("content-type", type);
      if (cached.etag) headers.set("etag", cached.etag);
      return { body: cached.body, headers };
    }
  }

  const resolved = await resolveTechLeaderAvatar(normalized, name, company);
  if (!resolved.ok && cached) {
    const headers = new Headers({
      "cache-control": "public, max-age=1800, stale-while-revalidate=21600",
      "x-ooglex-avatar-source": cachedSource + "-r2-stale",
      "x-ooglex-avatar-source-type": cachedSourceType,
      "x-ooglex-avatar-handle": normalized
    });
    const type = cached.httpMetadata && cached.httpMetadata.contentType
      ? cached.httpMetadata.contentType
      : "image/jpeg";
    headers.set("content-type", type);
    if (cached.etag) headers.set("etag", cached.etag);
    return { body: cached.body, headers };
  }
  if (!resolved.ok) {
    const err = new Error("avatar_unavailable");
    err.code = "avatar_unavailable";
    err.status = resolved.status || 502;
    throw err;
  }

  const sourceType = resolved.sourceType || avatarSourceType(resolved.source);
  await env.PRO_DATA.put(key, resolved.bytes, {
    httpMetadata: {
      contentType: resolved.contentType,
      cacheControl: TECH_AVATAR_CACHE_CONTROL
    },
    customMetadata: {
      handle: normalized,
      source: resolved.source,
      source_type: sourceType,
      fetched_at: new Date().toISOString(),
      policy: TECH_AVATAR_POLICY,
      cache_version: TECH_AVATAR_CACHE_VERSION
    }
  });

  return {
    body: resolved.bytes,
    headers: new Headers({
      "content-type": resolved.contentType,
      "cache-control": TECH_AVATAR_CACHE_CONTROL,
      "x-ooglex-avatar-source": resolved.source + "-r2",
      "x-ooglex-avatar-source-type": sourceType,
      "x-ooglex-avatar-handle": normalized
    })
  };
}

async function getTechLeaderAvatarAudit(handles, env) {
  const unique = Array.from(new Set((handles || []).map(normalizeXHandle).filter(Boolean))).slice(0, 180);
  const items = await Promise.all(unique.map(async (handle) => {
    const obj = await env.PRO_DATA.head(techAvatarCacheKey(handle));
    const metadata = obj && obj.customMetadata ? obj.customMetadata : {};
    const source = String(metadata.source || "");
    const sourceType = String(metadata.source_type || avatarSourceType(source));
    let status = "missing";
    if (sourceType === "x_original") status = "x_original";
    else if (sourceType === "x_original_proxy") status = "x_original_proxy";
    else if (sourceType === "official_fallback" || sourceType === "public_fallback" || sourceType === "generated_fallback") status = "fallback";

    return {
      handle,
      status,
      source_type: status === "missing" ? null : sourceType,
      source: status === "missing" ? null : source,
      fetched_at: metadata.fetched_at || null
    };
  }));

  const count = (status) => items.filter((item) => item.status === status).length;
  const xOriginal = count("x_original");
  const xProxy = count("x_original_proxy");
  const fallback = count("fallback");
  const missing = count("missing");
  return {
    schema_version: 2,
    policy: TECH_AVATAR_POLICY,
    cache_version: TECH_AVATAR_CACHE_VERSION,
    total: items.length,
    x_original: xOriginal,
    x_original_proxy: xProxy,
    fallback,
    missing,
    usable: xOriginal + xProxy + fallback,
    items
  };
}

function normalizeSyndicationEntities(value) {
  const src = value && typeof value === "object" ? value : {};
  const urls = Array.isArray(src.urls) ? src.urls.map((item) => {
    const indices = Array.isArray(item && item.indices) ? item.indices : [];
    return {
      start: Number.isFinite(Number(item && item.start)) ? Number(item.start) : Number(indices[0]),
      end: Number.isFinite(Number(item && item.end)) ? Number(item.end) : Number(indices[1]),
      url: item && item.url ? String(item.url) : "",
      expanded_url: item && (item.expanded_url || item.expandedUrl) ? String(item.expanded_url || item.expandedUrl) : "",
      display_url: item && (item.display_url || item.displayUrl) ? String(item.display_url || item.displayUrl) : ""
    };
  }).filter((item) => Number.isFinite(item.start) && Number.isFinite(item.end)) : [];
  return { urls };
}

function normalizeSyndicationMedia(legacy) {
  const ext = legacy && legacy.extended_entities && Array.isArray(legacy.extended_entities.media)
    ? legacy.extended_entities.media
    : legacy && legacy.entities && Array.isArray(legacy.entities.media)
      ? legacy.entities.media
      : [];
  return ext.map((item) => {
    if (!item || typeof item !== "object") return null;
    const preview = item.media_url_https || item.media_url || "";
    let videoUrl = "";
    const variants = item.video_info && Array.isArray(item.video_info.variants) ? item.video_info.variants : [];
    const mp4 = variants
      .filter((v) => v && v.content_type === "video/mp4" && v.url)
      .sort((a, b) => Number(b.bitrate || 0) - Number(a.bitrate || 0))[0];
    if (mp4) videoUrl = mp4.url;
    return {
      media_key: item.media_key || item.id_str || null,
      type: item.type || "photo",
      url: item.type === "photo" ? preview : null,
      preview_image_url: preview || null,
      video_url: videoUrl || null,
      width: item.original_info && item.original_info.width ? item.original_info.width : null,
      height: item.original_info && item.original_info.height ? item.original_info.height : null
    };
  }).filter(Boolean);
}

function syndicationTweetAuthorProfile(candidate) {
  const paths = [
    candidate && candidate.core && candidate.core.user_results && candidate.core.user_results.result,
    candidate && candidate.user_results && candidate.user_results.result,
    candidate && candidate.user
  ];
  for (const user of paths) {
    if (!user || typeof user !== "object") continue;
    const legacy = user.legacy && typeof user.legacy === "object" ? user.legacy : user;
    const handle = String(legacy.screen_name || legacy.username || user.username || "").replace(/^@/, "");
    const name = String(legacy.name || user.name || "").trim();
    const avatar = String(
      legacy.profile_image_url_https ||
      legacy.profile_image_url ||
      user.profile_image_url_https ||
      user.profile_image_url ||
      ""
    );
    if (handle || name || avatar) {
      return {
        name: name || handle,
        handle: handle || null,
        avatar_url: avatar || null,
        verified: Boolean(user.is_blue_verified || user.verified || legacy.verified)
      };
    }
  }
  return null;
}

function syndicationTweetAuthor(candidate) {
  const author = syndicationTweetAuthorProfile(candidate);
  return author && author.handle ? author.handle : "";
}

function unwrapSyndicationTweetResult(value) {
  let node = value;
  for (let i = 0; i < 8; i += 1) {
    if (!node || typeof node !== "object") return null;
    const legacy = node.legacy && typeof node.legacy === "object" ? node.legacy : node;
    const id = String(node.rest_id || legacy.id_str || node.id_str || node.id || "");
    const text = String(legacy.full_text || legacy.text || node.full_text || node.text || "").trim();
    if (id || text) return node;
    const next =
      (node.tweet_results && node.tweet_results.result) ||
      node.result ||
      node.tweet ||
      node.status ||
      null;
    if (!next || next === node) break;
    node = next;
  }
  return null;
}

function syndicationEmbeddedRaw(candidate, legacy, type) {
  if (type === "quote") {
    return (
      legacy.quoted_status_result ||
      candidate.quoted_status_result ||
      legacy.quoted_status ||
      candidate.quoted_status ||
      null
    );
  }
  if (type === "retweet") {
    return (
      legacy.retweeted_status_result ||
      candidate.retweeted_status_result ||
      legacy.retweeted_status ||
      candidate.retweeted_status ||
      null
    );
  }
  return null;
}

function normalizeSyndicationEmbeddedStatus(raw) {
  const candidate = unwrapSyndicationTweetResult(raw);
  if (!candidate) return null;
  const legacy = candidate.legacy && typeof candidate.legacy === "object" ? candidate.legacy : candidate;
  const text = String(legacy.full_text || legacy.text || candidate.full_text || candidate.text || "").trim();
  const id = String(candidate.rest_id || legacy.id_str || candidate.id_str || candidate.id || "");
  if (!text && !/^\d{10,25}$/.test(id)) return null;
  const author = syndicationTweetAuthorProfile(candidate);
  const handle = author && author.handle ? author.handle : "";
  const url = /^\d{10,25}$/.test(id)
    ? (handle ? `https://x.com/${encodeURIComponent(handle)}/status/${id}` : `https://x.com/i/web/status/${id}`)
    : null;
  return {
    id: /^\d{10,25}$/.test(id) ? id : null,
    text,
    created_at: legacy.created_at || candidate.created_at || null,
    lang: legacy.lang || candidate.lang || null,
    author,
    metrics: {
      reply_count: Number(legacy.reply_count || 0),
      repost_count: Number(legacy.retweet_count || 0),
      retweet_count: Number(legacy.retweet_count || 0),
      like_count: Number(legacy.favorite_count || legacy.favourite_count || 0),
      quote_count: Number(legacy.quote_count || 0)
    },
    entities: normalizeSyndicationEntities(legacy.entities || candidate.entities),
    media: normalizeSyndicationMedia(legacy),
    url
  };
}

function syndicationTweetMeta(candidate, legacy, text) {
  const replyId = String(
    legacy.in_reply_to_status_id_str ||
    legacy.in_reply_to_status_id ||
    candidate.in_reply_to_status_id_str ||
    candidate.in_reply_to_status_id ||
    ""
  );
  const replyHandle = String(
    legacy.in_reply_to_screen_name ||
    candidate.in_reply_to_screen_name ||
    ""
  ).replace(/^@/, "");
  const quotedId = String(
    legacy.quoted_status_id_str ||
    legacy.quoted_status_id ||
    candidate.quoted_status_id_str ||
    candidate.quoted_status_id ||
    ""
  );
  const isRetweet = Boolean(
    legacy.retweeted_status_result ||
    legacy.retweeted_status ||
    candidate.retweeted_status_result ||
    candidate.retweeted_status ||
    /^RT\s+@/i.test(String(text || ""))
  );
  const isQuote = Boolean(
    legacy.is_quote_status ||
    candidate.is_quote_status ||
    quotedId ||
    legacy.quoted_status_result ||
    candidate.quoted_status_result
  );
  return {
    post_type: isRetweet ? "retweet" : (replyId || replyHandle ? "reply" : (isQuote ? "quote" : "post")),
    reply_to_status_id: replyId || null,
    reply_to_handle: replyHandle || null,
    quoted_status_id: quotedId || null
  };
}

function normalizeSyndicationTweet(candidate, handle) {
  if (!candidate || typeof candidate !== "object") return null;
  const legacy = candidate.legacy && typeof candidate.legacy === "object" ? candidate.legacy : candidate;
  const text = String(legacy.full_text || legacy.text || candidate.full_text || candidate.text || "").trim();
  const id = String(candidate.rest_id || legacy.id_str || candidate.id_str || candidate.id || "");
  if (!text || !/^\d{10,25}$/.test(id)) return null;

  const author = syndicationTweetAuthor(candidate);
  if (author && String(author).toLowerCase() !== String(handle || "").toLowerCase()) return null;

  const createdAt = legacy.created_at || candidate.created_at || null;
  const metrics = {
    reply_count: Number(legacy.reply_count || 0),
    repost_count: Number(legacy.retweet_count || 0),
    retweet_count: Number(legacy.retweet_count || 0),
    like_count: Number(legacy.favorite_count || legacy.favourite_count || 0),
    quote_count: Number(legacy.quote_count || 0)
  };
  const meta = syndicationTweetMeta(candidate, legacy, text);
  const embeddedPost = (meta.post_type === "quote" || meta.post_type === "retweet")
    ? normalizeSyndicationEmbeddedStatus(syndicationEmbeddedRaw(candidate, legacy, meta.post_type))
    : null;
  return {
    id,
    text,
    created_at: createdAt,
    lang: legacy.lang || candidate.lang || null,
    metrics,
    entities: normalizeSyndicationEntities(legacy.entities || candidate.entities),
    media: normalizeSyndicationMedia(legacy),
    ...meta,
    embedded_post: embeddedPost,
    url: `https://x.com/${encodeURIComponent(handle)}/status/${id}`
  };
}

function collectSyndicationTweets(value, handle, out, seenObjects, depth = 0) {
  if (depth > 22 || value == null) return;
  if (typeof value !== "object") return;
  if (seenObjects.has(value)) return;
  seenObjects.add(value);

  const normalized = normalizeSyndicationTweet(value, handle);
  if (normalized && !out.some((item) => item.id === normalized.id)) out.push(normalized);

  if (Array.isArray(value)) {
    for (const item of value) collectSyndicationTweets(item, handle, out, seenObjects, depth + 1);
    return;
  }
  for (const key of Object.keys(value)) {
    collectSyndicationTweets(value[key], handle, out, seenObjects, depth + 1);
  }
}

function parseSyndicationTimeline(html, handle, limit) {
  const posts = [];
  const next = String(html || "").match(/<script[^>]+id=["']__NEXT_DATA__["'][^>]*>([\s\S]*?)<\/script>/i);
  if (next && next[1]) {
    try {
      const payload = JSON.parse(next[1]);
      collectSyndicationTweets(payload, handle, posts, new WeakSet());
    } catch {}
  }

  if (!posts.length) {
    const normalized = String(html || "")
      .replace(/&quot;/g, '"')
      .replace(/&#x27;/g, "'")
      .replace(/&amp;/g, "&")
      .replace(/\\u002F/gi, "/")
      .replace(/\\\//g, "/");
    const scriptBlocks = normalized.match(/<script[^>]*>[\s\S]*?<\/script>/gi) || [];
    for (const block of scriptBlocks) {
      const body = block.replace(/^<script[^>]*>/i, "").replace(/<\/script>$/i, "").trim();
      if (!body || (body[0] !== "{" && body[0] !== "[")) continue;
      try { collectSyndicationTweets(JSON.parse(body), handle, posts, new WeakSet()); } catch {}
    }
  }

  posts.sort((a, b) => {
    const ta = Date.parse(a.created_at || "") || Number(a.id) || 0;
    const tb = Date.parse(b.created_at || "") || Number(b.id) || 0;
    return tb - ta;
  });
  return posts.slice(0, limit);
}

function normalizeFxTwitterMedia(status) {
  const media = status && status.media && typeof status.media === "object" ? status.media : {};
  const out = [];
  const seen = new Set();

  function push(item) {
    if (!item || typeof item !== "object") return;
    const rawType = String(item.type || "").toLowerCase();
    const isVideo = rawType === "video" || rawType === "gif" || rawType === "animated_gif";
    const directUrl = item.url ? String(item.url) : "";
    const thumb = item.thumbnail_url || item.poster || item.preview_image_url || "";
    const formats = Array.isArray(item.formats)
      ? item.formats
      : Array.isArray(item.variants)
        ? item.variants
        : [];
    const best = formats
      .filter((v) => v && (v.url || v.src))
      .sort((a, b) => Number(b.bitrate || 0) - Number(a.bitrate || 0))[0];
    const videoUrl = isVideo
      ? String((best && (best.url || best.src)) || directUrl || "")
      : "";
    const imageUrl = isVideo
      ? String(thumb || "")
      : String(directUrl || thumb || "");
    const key = String(item.id || item.media_key || imageUrl || videoUrl || "");
    if (!key || seen.has(key)) return;
    seen.add(key);

    out.push({
      media_key: item.id || item.media_key || null,
      type: isVideo ? (rawType === "gif" || rawType === "animated_gif" ? "animated_gif" : "video") : "photo",
      url: isVideo ? null : (imageUrl || null),
      preview_image_url: imageUrl || null,
      video_url: videoUrl || null,
      width: item.width || null,
      height: item.height || null,
      alt_text: item.altText || item.alt_text || null
    });
  }

  if (Array.isArray(media.all) && media.all.length) {
    media.all.forEach(push);
  } else {
    (Array.isArray(media.photos) ? media.photos : []).forEach(push);
    (Array.isArray(media.videos) ? media.videos : []).forEach(push);
    if (media.video && typeof media.video === "object") push(media.video);
    (Array.isArray(media.gifs) ? media.gifs : []).forEach(push);
  }

  return out;
}

function fxTwitterAuthorProfile(status) {
  if (!status || typeof status !== "object") return null;
  const author = (
    (status.author && typeof status.author === "object" && status.author) ||
    (status.user && typeof status.user === "object" && status.user) ||
    (status.account && typeof status.account === "object" && status.account) ||
    {}
  );
  const handle = String(
    author.screen_name ||
    author.username ||
    author.handle ||
    status.author_screen_name ||
    status.screen_name ||
    ""
  ).replace(/^@/, "");
  const name = String(author.name || status.author_name || "").trim();
  const avatar = String(
    author.avatar_url ||
    author.avatar_url_https ||
    author.avatar ||
    author.profile_image_url_https ||
    author.profile_image_url ||
    author.profile_image ||
    author.image_url ||
    author.image ||
    status.author_avatar_url ||
    status.author_avatar ||
    ""
  );
  if (!handle && !name && !avatar) return null;
  return {
    name: name || handle,
    handle: handle || null,
    avatar_url: avatar || null,
    verified: Boolean(author.verified || (author.verification && author.verification.verified))
  };
}

function unwrapFxTwitterStatus(value) {
  if (!value || typeof value !== "object") return null;
  return (
    (value.tweet && typeof value.tweet === "object" && value.tweet) ||
    (value.status && typeof value.status === "object" && value.status) ||
    (value.result && typeof value.result === "object" && value.result) ||
    value
  );
}

function normalizeFxTwitterEmbeddedStatus(raw) {
  const status = unwrapFxTwitterStatus(raw);
  if (!status) return null;
  const id = String(status.id || status.rest_id || "");
  const text = String(status.text || status.full_text || "").trim();
  if (!text && !/^\d{10,25}$/.test(id)) return null;
  let createdAt = status.created_at || null;
  if (!createdAt && Number.isFinite(Number(status.created_timestamp))) {
    createdAt = new Date(Number(status.created_timestamp) * 1000).toISOString();
  }
  const author = fxTwitterAuthorProfile(status);
  const handle = author && author.handle ? author.handle : "";
  const url = String(
    status.url ||
    (/^\d{10,25}$/.test(id)
      ? (handle ? `https://x.com/${encodeURIComponent(handle)}/status/${id}` : `https://x.com/i/web/status/${id}`)
      : "")
  ) || null;
  return {
    id: /^\d{10,25}$/.test(id) ? id : null,
    text,
    created_at: createdAt,
    lang: status.lang || null,
    author,
    metrics: {
      reply_count: Number(status.replies || 0),
      repost_count: Number(status.reposts || status.retweets || 0),
      retweet_count: Number(status.reposts || status.retweets || 0),
      like_count: Number(status.likes || 0),
      quote_count: Number(status.quotes || 0)
    },
    entities: { urls: [] },
    media: normalizeFxTwitterMedia(status),
    url
  };
}

function normalizeFxTwitterStatus(status, handle) {
  if (!status || typeof status !== "object") return null;
  const id = String(status.id || status.rest_id || "");
  const rawText = String(
    status.text ||
    status.full_text ||
    (status.raw_text && status.raw_text.text) ||
    ""
  ).trim();
  const text = /^https:\/\/t\.co\/[A-Za-z0-9]+$/i.test(rawText) ? "" : rawText;
  const normalizedMedia = normalizeFxTwitterMedia(status);
  if (!/^\d{10,25}$/.test(id)) return null;
  let createdAt = status.created_at || null;
  if (!createdAt && Number.isFinite(Number(status.created_timestamp))) {
    createdAt = new Date(Number(status.created_timestamp) * 1000).toISOString();
  }
  const replyTarget = status.replying_to_status_id || status.in_reply_to_status_id || status.replying_to || status.in_reply_to || null;
  const quoteTarget = status.quote || status.quoted_tweet || status.quoted_status || status.quote_tweet || null;
  const retweetTarget = status.retweeted_tweet || status.retweeted_status || status.retweet || null;
  const postType = retweetTarget || /^RT\s+@/i.test(text)
    ? "retweet"
    : (replyTarget ? "reply" : (quoteTarget ? "quote" : "post"));
  const embeddedPost = postType === "retweet"
    ? normalizeFxTwitterEmbeddedStatus(retweetTarget)
    : (postType === "quote" ? normalizeFxTwitterEmbeddedStatus(quoteTarget) : null);
  if (!text && !normalizedMedia.length && !embeddedPost) return null;
  return {
    id,
    text,
    created_at: createdAt,
    lang: status.lang || null,
    post_type: postType,
    embedded_post: embeddedPost,
    metrics: {
      reply_count: Number(status.replies || 0),
      repost_count: Number(status.reposts || status.retweets || 0),
      retweet_count: Number(status.reposts || status.retweets || 0),
      like_count: Number(status.likes || 0),
      quote_count: Number(status.quotes || 0)
    },
    entities: { urls: [] },
    media: normalizedMedia,
    url: String(status.url || `https://x.com/${encodeURIComponent(handle)}/status/${id}`)
  };
}

async function fetchFxTwitterFreeFeed(handle, limit) {
  const requested = Math.max(3, Math.min(TECH_FREE_FEED_MAX_ITEMS, limit || TECH_FEED_FETCH_SIZE));
  const pageSize = 20;
  const strictLatestProfile = ["elonmusk"].includes(String(handle || "").toLowerCase());
  const maxPages = Math.max(1, Math.ceil(requested / pageSize));
  const byId = new Map();
  let cursor = "";
  let pagesFetched = 0;

  for (let page = 0; page < maxPages && byId.size < requested; page += 1) {
    const count = strictLatestProfile && !cursor
      ? pageSize
      : Math.min(pageSize, requested - byId.size);
    const params = new URLSearchParams({ count: String(count) });
    if (cursor) params.set("cursor", cursor);
    if (strictLatestProfile && !cursor) {
      params.set("since", String(Math.floor(Date.now() / 1000) - 7 * 24 * 60 * 60));
    }
    const url = `https://api.fxtwitter.com/2/profile/${encodeURIComponent(handle)}/statuses?${params.toString()}`;

    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 3500);
    let res = null;
    try {
      res = await fetch(url, {
        signal: ctl.signal,
        redirect: "follow",
        headers: {
          accept: "application/json",
          "user-agent": "Ooglex-Tech-Leaders-Free-Feed/3.0"
        }
      });
    } finally {
      clearTimeout(timer);
    }

    let payload = null;
    try { payload = await res.json(); } catch {}
    if (!res.ok || !payload || Number(payload.code || res.status) >= 400) {
      if (byId.size) break;
      const err = new Error("fxtwitter_public_feed_error");
      err.code = "fxtwitter_public_feed_error";
      err.status = res.status || Number(payload && payload.code) || 502;
      throw err;
    }

    pagesFetched += 1;
    const results = Array.isArray(payload.results) ? payload.results : [];
    for (const item of results) {
      const normalized = normalizeFxTwitterStatus(item, handle);
      if (normalized && normalized.id && !byId.has(normalized.id)) byId.set(normalized.id, normalized);
    }

    const nextCursor = payload && payload.cursor && payload.cursor.bottom
      ? String(payload.cursor.bottom)
      : "";
    if (!results.length || !nextCursor || nextCursor === cursor) break;
    cursor = nextCursor;
  }

  const posts = Array.from(byId.values())
    .sort((a, b) => {
      const ta = Date.parse(a.created_at || "") || 0;
      const tb = Date.parse(b.created_at || "") || 0;
      if (ta !== tb) return tb - ta;
      return String(b.id || "").localeCompare(String(a.id || ""));
    })
    .slice(0, requested);

  if (!posts.length) {
    const err = new Error("fxtwitter_public_feed_empty");
    err.code = "fxtwitter_public_feed_empty";
    err.status = 502;
    throw err;
  }

  return {
    schema_version: 5,
    source: "fxtwitter_public_api",
    third_party: "FxEmbed/FxTwitter",
    uses_x_api: false,
    handle,
    fetched_at: new Date().toISOString(),
    pagination: {
      page_size: pageSize,
      pages_fetched: pagesFetched,
      requested,
      returned: posts.length,
      has_more: Boolean(cursor) && posts.length < requested
    },
    posts
  };
}

async function fetchFxTwitterStatusById(postId, handle) {
  const id = String(postId || "").trim();
  if (!/^\d{10,25}$/.test(id)) return null;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 3500);
  try {
    const res = await fetch(`https://api.fxtwitter.com/status/${encodeURIComponent(id)}`, {
      signal: ctl.signal,
      redirect: "follow",
      headers: {
        accept: "application/json",
        "user-agent": "Ooglex-Tech-Leaders-Free-Feed/3.1"
      }
    });
    if (!res.ok) return null;
    const payload = await res.json().catch(() => null);
    const raw = unwrapFxTwitterStatus(payload);
    if (!raw) return null;
    const normalized = normalizeFxTwitterStatus(raw, handle);
    if (!normalized || normalized.id !== id) return null;
    const url = String(normalized.url || "");
    if (String(handle || "").toLowerCase() === "elonmusk" && !/x\.com\/elonmusk\/status\//i.test(url)) {
      return null;
    }
    return normalized;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

async function applyTemporaryPublicFeedPatch(handle, posts, requested) {
  const normalized = String(handle || "").toLowerCase();
  const list = Array.isArray(posts) ? posts.slice() : [];
  if (normalized !== "elonmusk" || Date.now() >= ELON_TEMP_REFRESH_UNTIL_MS) {
    return list.slice(0, requested);
  }
  if (!list.some((post) => String(post && post.id || "") === ELON_TEMP_REFRESH_POST_ID)) {
    const target = await fetchFxTwitterStatusById(ELON_TEMP_REFRESH_POST_ID, handle);
    if (target) list.push(target);
  }
  list.sort((a, b) => {
    const ta = Date.parse(a && a.created_at || "") || 0;
    const tb = Date.parse(b && b.created_at || "") || 0;
    if (ta !== tb) return tb - ta;
    return String(b && b.id || "").localeCompare(String(a && a.id || ""));
  });
  return list.slice(0, requested);
}

async function fetchOfficialSyndicationFreeFeed(handle, limit) {
  const params = new URLSearchParams({
    dnt: "true",
    frame: "false",
    hideBorder: "true",
    hideFooter: "true",
    hideHeader: "true",
    lang: "en",
    limit: String(Math.max(3, Math.min(TECH_FREE_FEED_MAX_ITEMS, limit || TECH_FEED_FETCH_SIZE))),
    origin: "https://www.ooglex.com/",
    showHeader: "false",
    showReplies: "true",
    theme: "light",
    transparent: "true"
  });
  if (["elonmusk"].includes(String(handle || "").toLowerCase())) {
    // One-minute bucket reduces the chance of reusing a stale CDN timeline
    // without producing a unique URL for every single page view.
    params.set("_fresh", String(Math.floor(Date.now() / 60000)));
  }
  const url = `https://syndication.twitter.com/srv/timeline-profile/screen-name/${encodeURIComponent(handle)}?${params.toString()}`;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 3500);
  let res = null;
  try {
    res = await fetch(url, {
      signal: ctl.signal,
      redirect: "follow",
      headers: {
        accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "accept-language": "en-US,en;q=0.9",
        referer: "https://publish.twitter.com/",
        "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
      }
    });
  } finally {
    clearTimeout(timer);
  }
  if (!res.ok) {
    const err = new Error(res.status === 429 ? "x_public_syndication_rate_limited" : "x_public_syndication_error");
    err.code = res.status === 429 ? "x_public_syndication_rate_limited" : "x_public_syndication_error";
    err.status = res.status;
    throw err;
  }
  const html = await res.text();
  const posts = parseSyndicationTimeline(html, handle, limit);
  if (!posts.length) {
    const err = new Error("x_public_feed_empty");
    err.code = "x_public_feed_empty";
    err.status = 502;
    err.detail = { html_bytes: html.length, has_next_data: /__NEXT_DATA__/.test(html) };
    throw err;
  }
  return {
    schema_version: 4,
    source: "x_public_syndication",
    uses_x_api: false,
    handle,
    fetched_at: new Date().toISOString(),
    posts
  };
}



function publicFeedPostRichness(post) {
  if (!post || typeof post !== "object") return 0;
  let score = 0;
  if (String(post.text || "").trim()) score += 1;
  if (Array.isArray(post.media) && post.media.length) score += 2 + Math.min(3, post.media.length);
  if (post.embedded_post) {
    score += 4;
    if (String(post.embedded_post.text || "").trim()) score += 1;
    if (Array.isArray(post.embedded_post.media) && post.embedded_post.media.length) score += 2;
    if (post.embedded_post.author && post.embedded_post.author.handle) score += 1;
  }
  if (post.post_type && post.post_type !== "post") score += 1;
  return score;
}

function mergePublicFeedPosts(feeds, limit) {
  const byId = new Map();
  for (const feed of feeds) {
    const posts = feed && Array.isArray(feed.posts) ? feed.posts : [];
    for (const post of posts) {
      if (!post || !post.id) continue;
      const id = String(post.id);
      const prev = byId.get(id);
      if (!prev || publicFeedPostRichness(post) > publicFeedPostRichness(prev)) byId.set(id, post);
    }
  }
  return Array.from(byId.values())
    .sort((a, b) => {
      const ta = Date.parse(a.created_at || "") || 0;
      const tb = Date.parse(b.created_at || "") || 0;
      if (ta !== tb) return tb - ta;
      return String(b.id || "").localeCompare(String(a.id || ""));
    })
    .slice(0, limit);
}

async function fetchFreeTechLeaderFeed(handle, limit) {
  const requested = Math.max(1, Math.min(TECH_FREE_FEED_MAX_ITEMS, limit || TECH_FEED_FETCH_SIZE));

  // Fast first paint: one public page is enough for ordinary profiles.
  // Elon Musk retains a temporary exact-post patch below; all other profiles
  // use the generic public-source path with no catalog-specific exceptions.
  if (requested <= 20) {
    try {
      const fastFeed = await Promise.any([
        fetchFxTwitterFreeFeed(handle, requested).then((fast) => ({
          ...fast,
          schema_version: 6,
          source: "fxtwitter_public_api_fast",
          sources: ["fxtwitter_public_api"],
          fast_first_paint: true
        })),
        fetchOfficialSyndicationFreeFeed(handle, requested).then((official) => ({
          ...official,
          schema_version: 6,
          source: "x_public_syndication_fast",
          sources: ["x_public_syndication"],
          fast_first_paint: true
        }))
      ]);
      if (String(handle || "").toLowerCase() === "elonmusk") {
        fastFeed.posts = await applyTemporaryPublicFeedPatch(handle, fastFeed.posts, requested);
        fastFeed.source = "fxtwitter_public_api_exact_patch";
        fastFeed.sources = Array.from(new Set([...(fastFeed.sources || []), "fxtwitter_public_status"]));
      }
      return fastFeed;
    } catch {
      const err = new Error("free_public_feed_sources_unavailable");
      err.code = "free_public_feed_sources_unavailable";
      err.status = 502;
      throw err;
    }
  }

  const results = await Promise.allSettled([
    fetchOfficialSyndicationFreeFeed(handle, requested),
    fetchFxTwitterFreeFeed(handle, requested)
  ]);

  const feeds = results
    .filter((item) => item.status === "fulfilled" && item.value && Array.isArray(item.value.posts) && item.value.posts.length)
    .map((item) => item.value);

  if (!feeds.length) {
    const officialError = results[0] && results[0].status === "rejected" ? results[0].reason : null;
    const fxErr = results[1] && results[1].status === "rejected" ? results[1].reason : null;
    const err = new Error("free_public_feed_sources_unavailable");
    err.code = "free_public_feed_sources_unavailable";
    err.status = fxErr && Number.isInteger(fxErr.status)
      ? fxErr.status
      : (officialError && Number.isInteger(officialError.status) ? officialError.status : 502);
    err.detail = {
      official_source: officialError && officialError.code ? officialError.code : "empty",
      official_status: officialError && officialError.status ? officialError.status : null,
      fallback_source: fxErr && fxErr.code ? fxErr.code : "empty",
      fallback_status: fxErr && fxErr.status ? fxErr.status : null
    };
    throw err;
  }

  let posts = mergePublicFeedPosts(feeds, requested);
  if (String(handle || "").toLowerCase() === "elonmusk") {
    posts = await applyTemporaryPublicFeedPatch(handle, posts, requested);
  }
  if (!posts.length) {
    const err = new Error("free_public_feed_empty");
    err.code = "free_public_feed_empty";
    err.status = 502;
    throw err;
  }

  const sources = feeds.map((feed) => feed.source).filter(Boolean);
  return {
    schema_version: 6,
    source: sources.length > 1 ? "x_public_merged" : (sources[0] || "public_source"),
    sources,
    uses_x_api: false,
    handle,
    fetched_at: new Date().toISOString(),
    posts
  };
}

function freeTechLeaderCacheKey(handle) {
  const normalized = String(handle || "").toLowerCase();
  const version = normalized === "elonmusk" ? "v9-elon-target" : "v7";
  return `tech-leaders/free-feed/${version}/${normalized}.json`;
}

async function getFreeTechLeaderFeed(handle, limit, env) {
  const normalized = normalizeXHandle(handle);
  if (!normalized) {
    const err = new Error("invalid_free_feed_handle");
    err.code = "invalid_free_feed_handle";
    err.status = 400;
    throw err;
  }
  const key = freeTechLeaderCacheKey(normalized);
  const cached = await readJson(env.PRO_DATA, key);
  const cachedAt = cached && cached.fetched_at ? Date.parse(cached.fetched_at) : NaN;
  const age = Number.isFinite(cachedAt) ? Math.max(0, Date.now() - cachedAt) : Infinity;
  const cachedPosts = cached && Array.isArray(cached.posts) ? cached.posts : [];
  // A previous request target is not proof that the upstream actually returned
  // that many posts. Only the number of posts physically cached counts as
  // fulfilled history depth.
  const cachedCapacity = cachedPosts.length;
  const normalizedLower = normalized.toLowerCase();
  const strictLatestProfile = normalizedLower === "elonmusk";

  const activeTtl = strictLatestProfile ? TECH_FREE_FEED_STRICT_TTL_MS : TECH_FREE_FEED_TTL_MS;
  if (cachedPosts.length && age <= activeTtl && cachedCapacity >= limit) {
    return {
      ...cached,
      requested_limit: cachedCapacity,
      requested_target: Number(cached && cached.requested_target) || cachedCapacity,
      posts: cachedPosts.slice(0, limit),
      cache: { status: "fresh", age_ms: age }
    };
  }

  try {
    const requestedLimit = Math.max(limit, TECH_FEED_FETCH_SIZE);
    const fresh = await fetchFreeTechLeaderFeed(normalized, requestedLimit);
    const returnedPosts = Array.isArray(fresh && fresh.posts) ? fresh.posts : [];
    const fulfilledLimit = Math.min(requestedLimit, returnedPosts.length);
    const persisted = {
      ...fresh,
      requested_limit: fulfilledLimit,
      requested_target: requestedLimit,
      returned_items: returnedPosts.length
    };
    await writeJson(env.PRO_DATA, key, persisted);
    return { ...persisted, posts: returnedPosts.slice(0, limit), cache: { status: "refreshed", age_ms: 0 } };
  } catch (err) {
    if (cachedPosts.length && age <= TECH_FREE_FEED_MAX_STALE_MS) {
      return {
        ...cached,
        requested_limit: cachedPosts.length,
        requested_target: Number(cached && cached.requested_target) || cachedPosts.length,
        posts: cachedPosts.slice(0, limit),
        cache: { status: "stale", age_ms: age, reason: err && err.code ? err.code : "x_public_feed_error" }
      };
    }
    throw err;
  }
}

async function getFreeTechLeaderPost(handle, postId, env) {
  const normalized = normalizeXHandle(handle);
  const id = String(postId || "").trim();
  if (!normalized || !/^\d{10,25}$/.test(id)) {
    const err = new Error("invalid_free_post");
    err.code = "invalid_free_post";
    err.status = 400;
    throw err;
  }

  const key = freeTechLeaderCacheKey(normalized);
  const cached = await readJson(env.PRO_DATA, key);
  const cachedPosts = cached && Array.isArray(cached.posts) ? cached.posts : [];
  const cachedHit = cachedPosts.find((post) => String(post && post.id || "") === id);
  if (cachedHit) {
    return {
      schema_version: 1,
      source: cached.source || "ooglex_cache",
      uses_x_api: false,
      handle: normalized,
      fetched_at: cached.fetched_at || null,
      post: cachedHit,
      cache: { status: "hit" }
    };
  }

  const feed = await getFreeTechLeaderFeed(normalized, TECH_FREE_FEED_MAX_ITEMS, env);
  const post = Array.isArray(feed.posts)
    ? feed.posts.find((item) => String(item && item.id || "") === id)
    : null;
  let resolvedPost = post;
  if (!resolvedPost) {
    try {
      resolvedPost = await fetchFxTwitterStatusById(id, normalized);
    } catch {}
  }
  if (!resolvedPost) {
    const err = new Error("free_post_not_found");
    err.code = "free_post_not_found";
    err.status = 404;
    throw err;
  }

  return {
    schema_version: 1,
    source: feed.source || "public_source",
    uses_x_api: false,
    handle: normalized,
    fetched_at: feed.fetched_at || null,
    post: resolvedPost,
    cache: feed.cache || { status: "refreshed" }
  };
}

function shareHtmlEscape(value) {
  return String(value == null ? "" : value).replace(/[&<>"']/g, (ch) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;"
  }[ch]));
}

function techLeaderProfileByHandle(handle) {
  const target = String(handle || "").toLowerCase();
  return Object.values(TECH_LEADERS).find((profile) =>
    String(profile && profile.handle || "").toLowerCase() === target
  ) || null;
}

function techLeaderShareText(post) {
  if (!post || typeof post !== "object") return "";
  const type = String(post.post_type || "").toLowerCase();
  const embedded = post.embedded_post && typeof post.embedded_post === "object"
    ? post.embedded_post
    : null;
  const primary = String(post.text || "").trim();
  const embeddedText = String(embedded && embedded.text || "").trim();

  // For a pure repost, the reposted source text is the meaningful original post.
  // For quotes/replies/original posts, keep the leader's own public English text.
  const raw = (type === "retweet" || type === "repost")
    ? (embeddedText || primary)
    : (primary || embeddedText);
  return raw.replace(/\s+/g, " ").trim();
}

function techLeaderShareMedia(post, origin) {
  const images = [];
  const videos = [];
  const pushMedia = (source) => {
    const items = source && Array.isArray(source.media) ? source.media : [];
    for (const item of items) {
      if (!item || typeof item !== "object") continue;
      const type = String(item.type || "").toLowerCase();
      const imageRaw = item.preview_image_url || item.url || "";
      const videoRaw = item.video_url || "";
      if (imageRaw) images.push(String(imageRaw));
      if ((type === "video" || type === "animated_gif" || type === "gif") && videoRaw) {
        videos.push({
          raw: String(videoRaw),
          width: Number(item.width) || null,
          height: Number(item.height) || null
        });
      }
    }
  };
  pushMedia(post);
  pushMedia(post && post.embedded_post);

  const imageRaw = images[0] || "";
  const video = videos[0] || null;
  return {
    image: imageRaw
      ? `${origin}/v1/tech-leaders/media?url=${encodeURIComponent(imageRaw)}`
      : null,
    video: video
      ? `${origin}/v1/tech-leaders/media?url=${encodeURIComponent(video.raw)}`
      : null,
    videoWidth: video && video.width ? video.width : null,
    videoHeight: video && video.height ? video.height : null
  };
}

async function techLeaderCatalogShareCoverResponse(env, cors) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
    <rect width="512" height="512" fill="#f7f7f7"/>
    <rect x="18" y="18" width="476" height="476" rx="34" fill="#f8f6f2" stroke="#ded5cb" stroke-width="2"/>
    <text x="46" y="68" font-family="Arial,Helvetica,sans-serif" font-size="20" letter-spacing="2.2" fill="#6d6862">OOGLEX · PUBLIC X</text>
    <g>
      <circle cx="118" cy="182" r="47" fill="#fff" stroke="#d8d0c6" stroke-width="3"/>
      <circle cx="214" cy="182" r="47" fill="#fff" stroke="#d8d0c6" stroke-width="3"/>
      <circle cx="310" cy="182" r="47" fill="#fff" stroke="#d8d0c6" stroke-width="3"/>
      <circle cx="118" cy="168" r="15" fill="#1b1b1d"/><path d="M86 214c5-28 20-42 32-42s27 14 32 42" fill="#1b1b1d"/>
      <circle cx="214" cy="168" r="15" fill="#555b63"/><path d="M182 214c5-28 20-42 32-42s27 14 32 42" fill="#555b63"/>
      <circle cx="310" cy="168" r="15" fill="#948b82"/><path d="M278 214c5-28 20-42 32-42s27 14 32 42" fill="#948b82"/>
    </g>
    <circle cx="362" cy="214" r="25" fill="#fff"/>
    <path fill="#1d9bf0" d="M386 214l-5.1-5.8.8-7.7-7.5-1.7-3.9-6.7-7.2 3-7.2-3-3.9 6.7-7.5 1.7.8 7.7-5.1 5.8 5.1 5.8-.8 7.7 7.5 1.7 3.9 6.7 7.2-3 7.2 3 3.9-6.7 7.5-1.7-.8-7.7z"/>
    <path d="M353 214l6 6 13-15" fill="none" stroke="#fff" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>
    <text x="46" y="305" font-family="Arial,Helvetica,sans-serif" font-size="54" font-weight="700" fill="#171717">TECH LEADERS</text>
    <text x="48" y="354" font-family="Arial,Helvetica,sans-serif" font-size="26" font-weight="700" fill="#171717">LIVE PUBLIC X FEED</text>
    <text x="48" y="405" font-family="Arial,Helvetica,sans-serif" font-size="20" letter-spacing="1.3" fill="#50545a">CEO · FOUNDERS · S&amp;P 500</text>
    <text x="48" y="445" font-family="Arial,Helvetica,sans-serif" font-size="17" fill="#77716b">AI · CHIPS · CLOUD · SPACE · MARKETS</text>
  </svg>`;

  try {
    if (!env.IMAGES) throw new Error("images_binding_unavailable");
    const rendered = await env.IMAGES
      .input(new Blob([svg], { type: "image/svg+xml" }).stream())
      .output({ format: "image/png" });
    const response = rendered.response();
    const headers = new Headers(response.headers);
    Object.entries(cors).forEach(([key, value]) => headers.set(key, value));
    headers.set("content-type", "image/png");
    headers.set("cache-control", "public, max-age=86400, stale-while-revalidate=604800");
    headers.set("x-ooglex-share-cover", "tech-leaders-v2");
    return new Response(response.body, { status: 200, headers });
  } catch {
    const fallback = await fetch("https://www.ooglex.com/assets/og-cover.png");
    const headers = new Headers(cors);
    fallback.headers.forEach((value, key) => headers.set(key, value));
    headers.set("cache-control", "public, max-age=1800, stale-while-revalidate=21600");
    headers.set("x-ooglex-share-cover", "fallback");
    return new Response(fallback.body, { status: 200, headers });
  }
}

async function techLeaderShareAvatarResponse(url, env, cors) {
  const handle = normalizeXHandle(url.searchParams.get("handle"));
  const name = String(url.searchParams.get("name") || handle || "X").trim().slice(0, 120);
  const verified = String(url.searchParams.get("verified") || "1") !== "0";
  if (!handle) return json({ error: "invalid_share_avatar_handle" }, 400, cors);

  try {
    if (!env.IMAGES) throw new Error("images_binding_unavailable");

    const avatar = await getTechLeaderAvatar(handle, name, "", env);
    const fromB64 = (value) => {
      const raw = atob(value);
      const bytes = new Uint8Array(raw.length);
      for (let i = 0; i < raw.length; i += 1) bytes[i] = raw.charCodeAt(i);
      return bytes;
    };
    const maskBytes = fromB64("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");
    const badgeBytes = fromB64("iVBORw0KGgoAAAANSUhEUgAAAHAAAABwCAYAAADG4PRLAAAD+0lEQVR42u2dTZLjIAyFQeV93yCn62PldH2DnIBZTU0q05UY/aAn/NgHhD4/JIFj+hijbdC0k+jVJ35cBNRsf50AcaHNjtkJsAa0kjAPQqsN8yA4s939qgC3SH+zQR4EVxvkQXC1QQrh1Z6z7A7vdn9sDVGCjYeABwAxzA89aC8UUnU/31/Zy2qvoMARCcHyu4g+sx9sbwWGwTujnhlHf+pPa8NqJR5o8M469NmZGoXc7g9zH0ZfdSQFjihQaM05jpohCrryWCvGAnSFh66+IBtHFkAqDwCioMCroL5gW8cqgFQekBIFAV4l9S2wecrHs2XE2B0MSOnRIxTIpRNwKRXCqw1RCK82RKGPajeh+mqrMEyBzEDX+EKovtoqZAzcNAZSfUVUSAUWb79tpZnUx+TlfXM40e8hAAluGcjuvoQSXp7PXhXI04YPqomYs+W0QgXwiopb8QriBMjOLNTgWIBX9H+NgSNQ8tslG94+mOxvUIEOTv35/kp/mAnQQRGZEEVb++28jGrmZvGH8reDCnQEkZWZEyBQUU6ACerLroll9YQJz9eHVGBR5T0DVB8f7bCllg3P2NcQKi//obX0KVdVH9qyqe1bCK92E8LDmbdmjEvFwAq7LLNjCeJEIpa4SltkM2MKKjxPiNX2N2fGlkxVfBrDY8yK8GbslhXOsPSdcExTBp4qiclIwVeez1WCB5OFnjF6xQl5NXhqgFkJRqT6K8IzKTArwTjzotFV4LX278XetBMJi/HvviF6BXittZ4eAy0OfJ585TM9E0GLAj0dsDq7RYJn+acSzF4o8n4jcoPazEbd8SfACzt4VQycjoMrHO0dF5EfDu1/BKHPA4FeHuISmun4nZdleZUkokMs41WBN2lnvX/oam9nuVISA5nIaIN9JXieHzmYhpjhLM3FVZuA+y/USaIh5uX0FdTt/tgd3sclVKVAFuJLwX381JYZIkGGKa6XqwPZdIV8p2vwKoYZgGzFFUgVFlBfqAKv9DmuTF+IljxbvvoYAzePgVQhuPpmFEiIgPBml1BCBIPXWvANnmdb1W23wOwy5AbPMBVWLDkQ4GmzUC6lAEuntYzoV1ZhkK0qn8rqAdl8fSlZA1dVYYCNJh9KtgFUnrGDyTJiSYlxpqzwuElltg9n9bk8+IezQWEXR75znuZOo0/fpAmuTd1WLU8Fuirxdn9MP/Fnna7p11F9riEnAmBryVe4vgOZnCi55wtSxVCP5XY3eJEA/xrcUSAmwgv1g1R98mYgJsOLHSAoBsLFxR3heZcRZyc0CK4mwN1BpoSKA2DCg+BqAqwOEmIP+AB1yCC0egBRYUKfthwNv2XALHNEdrRarTvXmOXPMv8AsP/mYjIuw+sAAAAASUVORK5CYII=");

    let chain = env.IMAGES
      .input(avatar.body)
      .transform({ width: 512, height: 512, fit: "cover" })
      .draw(
        env.IMAGES.input(new Blob([maskBytes], { type: "image/png" }).stream()),
        { top: 0, left: 0 }
      );

    if (verified) {
      chain = chain.draw(
        env.IMAGES.input(new Blob([badgeBytes], { type: "image/png" }).stream()),
        { right: 34, bottom: 34 }
      );
    }

    const rendered = await chain.output({ format: "image/png" });
    const response = rendered.response();
    const headers = new Headers(response.headers);
    Object.entries(cors).forEach(([key, value]) => headers.set(key, value));
    headers.set("cache-control", "public, max-age=21600, stale-while-revalidate=86400");
    headers.set("x-ooglex-share-avatar", verified ? "circle-verified-png" : "circle-png");
    headers.set("x-ooglex-share-avatar-bg", "#f7f7f7");
    return new Response(response.body, { status: response.status, headers });
  } catch (err) {
    // Never leave WeChat with a blank thumbnail. If composition fails, fall
    // back to the normal raster avatar and expose the fallback in a header.
    try {
      const avatar = await getTechLeaderAvatar(handle, name, "", env);
      const headers = new Headers(cors);
      avatar.headers.forEach((value, key) => headers.set(key, value));
      headers.set("cache-control", "public, max-age=1800, stale-while-revalidate=21600");
      headers.set("x-ooglex-share-avatar", "raster-avatar-fallback");
      headers.set("x-ooglex-share-avatar-error", String(err && err.message || "compose_failed").slice(0, 120));
      return new Response(avatar.body, { status: 200, headers });
    } catch (fallbackErr) {
      const code = fallbackErr && fallbackErr.code ? fallbackErr.code : "share_avatar_unavailable";
      const status = fallbackErr && Number.isInteger(fallbackErr.status) ? fallbackErr.status : 502;
      return json({ error: code, handle }, status, { ...cors, "cache-control": "no-store" });
    }
  }
}

function techLeaderShareResponse(handle, post, requestUrl) {
  const profile = techLeaderProfileByHandle(handle);
  const author = String(profile && profile.name || `@${handle}`);
  const originalText = techLeaderShareText(post);
  const previewTitle = originalText
    ? (originalText.length > 180 ? `${originalText.slice(0, 177)}…` : originalText)
    : `${author} · Ooglex`;
  const handleLower = String(handle || "").toLowerCase();
  const publicAuthor = handleLower === "elonmusk" ? "马斯克 · Elon Musk" : author;
  const showVerifiedBadge = Boolean(handle);
  const verifiedBadgeHtml = showVerifiedBadge
    ? '<span class="verified-badge" aria-label="Verified" title="Verified"><svg viewBox="0 0 24 24" aria-hidden="true"><path class="verified-blue" d="M23 12l-2.44-2.79.39-3.68-3.61-.82L15.45 1.5 12 2.96 8.55 1.5 6.66 4.69l-3.61.81.39 3.68L1 12l2.44 2.79-.39 3.69 3.61.81 1.89 3.2L12 21.03l3.45 1.46 1.89-3.19 3.61-.82-.39-3.68L23 12z"/><path class="verified-check" d="M7.35 12.35 10.1 15.1 16.65 8.55"/></svg></span>'
    : "";
  const description = `${publicAuthor} (@${handle}) · Original public X post via Ooglex`;
  const descriptionHtml = `<span class="desc-author">${shareHtmlEscape(publicAuthor)}${verifiedBadgeHtml}</span> (@${shareHtmlEscape(handle)}) · Original public X post via Ooglex`;
  const shareMedia = techLeaderShareMedia(post, requestUrl.origin);
  const image = shareMedia.image;
  const video = shareMedia.video;
  const avatarParams = new URLSearchParams({
    handle: String(handle || ""),
    name: publicAuthor || String(handle || "X")
  });
  const avatarUrl = `${requestUrl.origin}/v1/tech-leaders/avatar?${avatarParams.toString()}`;
  // Social link previews (especially WeChat Moments) identify the publisher
  // with a dedicated square image whose visible portrait is circular and whose
  // blue badge means Ooglex has confirmed the public personal X account.
  const shareAvatarParams = new URLSearchParams({
    handle: String(handle || ""),
    name: publicAuthor || String(handle || "X"),
    verified: showVerifiedBadge ? "1" : "0",
    v: "20260921e"
  });
  const socialImage = `${requestUrl.origin}/v1/tech-leaders/share-avatar?${shareAvatarParams.toString()}`;

  const shareUrl = requestUrl.toString();
  const canonical = new URL(requestUrl.origin + requestUrl.pathname);
  const originalUrl = String(
    post && post.url ||
    `https://x.com/${encodeURIComponent(handle)}/status/${encodeURIComponent(String(post && post.id || ""))}`
  );

  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${shareHtmlEscape(previewTitle)}</title>
<meta name="description" content="${shareHtmlEscape(originalText || description)}">
<link rel="canonical" href="${shareHtmlEscape(canonical.toString())}">
<meta property="og:type" content="article">
<meta property="og:site_name" content="Ooglex">
<meta property="og:title" content="${shareHtmlEscape(previewTitle)}">
<meta property="og:description" content="${shareHtmlEscape(description)}">
<meta property="og:url" content="${shareHtmlEscape(shareUrl)}">
<meta property="og:image" content="${shareHtmlEscape(socialImage)}">
<meta property="og:image:secure_url" content="${shareHtmlEscape(socialImage)}">
<meta property="og:image:width" content="512">
<meta property="og:image:height" content="512">
${video ? `<meta property="og:video" content="${shareHtmlEscape(video)}">
<meta property="og:video:secure_url" content="${shareHtmlEscape(video)}">
<meta property="og:video:type" content="video/mp4">
${shareMedia.videoWidth ? `<meta property="og:video:width" content="${shareHtmlEscape(shareMedia.videoWidth)}">` : ""}
${shareMedia.videoHeight ? `<meta property="og:video:height" content="${shareHtmlEscape(shareMedia.videoHeight)}">` : ""}` : ""}
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${shareHtmlEscape(previewTitle)}">
<meta name="twitter:description" content="${shareHtmlEscape(description)}">
<meta name="twitter:image" content="${shareHtmlEscape(socialImage)}">
<style>
body{margin:0;background:#f7f1e9;color:#171717;font:16px/1.65 system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{width:min(680px,calc(100% - 32px));margin:32px auto;padding:28px;border:1px solid #ded5cb;border-radius:18px;background:#fffaf4}
.k{font:12px/1.2 ui-monospace,SFMono-Regular,Menlo,monospace;color:#8b837b;letter-spacing:.08em}
h1{margin:16px 0 10px;font-size:26px;line-height:1.35;white-space:pre-wrap;word-break:break-word}
.author-row{display:flex;align-items:center;gap:12px;margin:18px 0 8px}
.author-avatar{width:48px;height:48px;border-radius:50%;object-fit:cover;flex:0 0 48px;border:1px solid #ded5cb;background:#eee}
.author-copy{min-width:0}.author-name-row{display:flex;align-items:center;gap:7px;flex-wrap:wrap}.author-name{font-weight:700;font-size:17px;line-height:1.2}.author-meta{margin-top:3px;color:#776f67;font-size:14px}
.verified-badge{display:inline-block;flex:0 0 auto;width:20px;height:20px;vertical-align:-3px;pointer-events:none;filter:drop-shadow(0 1px 1px rgba(0,0,0,.10));line-height:0}
.verified-badge svg{display:block;width:100%;height:100%;overflow:visible}
.verified-badge .verified-blue{fill:#1d9bf0}
.verified-badge .verified-check{fill:none;stroke:#fff;stroke-width:2.15;stroke-linecap:round;stroke-linejoin:round}
.a{color:#655f59}.desc-author{display:inline-flex;align-items:center;gap:6px}.a .verified-badge{width:18px;height:18px;vertical-align:-3px}
.links{display:flex;gap:10px;flex-wrap:wrap;margin-top:22px}.links a{padding:10px 14px;border:1px solid #ded5cb;border-radius:10px;color:#2a6fa4;text-decoration:none}
.preview{display:block;width:100%;max-height:520px;object-fit:cover;margin-top:18px;border-radius:12px;background:#000}
video.preview{object-fit:contain}
.media-note{margin-top:8px;color:#8b837b;font-size:12px}
@media(max-width:560px){main{margin:16px auto;padding:20px}h1{font-size:22px}}
</style>
</head>
<body>
<main>
<div class="k">OOGLEX · PUBLIC X POST</div>
<div class="author-row">
  <img class="author-avatar" src="${shareHtmlEscape(avatarUrl)}" alt="${shareHtmlEscape(publicAuthor)} avatar" referrerpolicy="no-referrer" onerror="this.style.display='none'">
  <div class="author-copy">
    <div class="author-name-row">
      <div class="author-name">${shareHtmlEscape(publicAuthor)}</div>
      ${verifiedBadgeHtml}
    </div>
    <div class="author-meta">@${shareHtmlEscape(handle)} · Public X post</div>
  </div>
</div>
<h1>${shareHtmlEscape(originalText || previewTitle)}</h1>
<div class="a">${descriptionHtml}</div>
${video
  ? `<video class="preview" controls playsinline preload="metadata"${image ? ` poster="${shareHtmlEscape(image)}"` : ""} src="${shareHtmlEscape(video)}"></video>
<div class="media-note">Video post · tap play to watch</div>`
  : (image ? `<img class="preview" src="${shareHtmlEscape(image)}" alt="">` : "")}
<div class="links">
<a href="https://www.ooglex.com/apps/tech-leaders/">Back to Tech Leaders</a>
<a href="${shareHtmlEscape(originalUrl)}">View original on X</a>
</div>
</main>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=300, stale-while-revalidate=1800",
      "x-ooglex-x-api": "unused",
      "x-ooglex-share-preview": video ? "post-video" : "post-image"
    }
  });
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
  const users = Array.isArray(includes.users) ? includes.users : [];
  const includedTweets = Array.isArray(includes.tweets) ? includes.tweets : [];
  for (const item of media) {
    if (item && item.media_key) mediaByKey.set(item.media_key, item);
  }
  const userById = new Map(users.filter(Boolean).map((item) => [String(item.id || ""), item]));
  const tweetById = new Map(includedTweets.filter(Boolean).map((item) => [String(item.id || ""), item]));

  function apiMedia(tweet) {
    const keys = tweet && tweet.attachments && Array.isArray(tweet.attachments.media_keys)
      ? tweet.attachments.media_keys
      : [];
    return keys.map((key) => mediaByKey.get(key)).filter(Boolean).map((item) => ({
      media_key: item.media_key,
      type: item.type,
      url: item.url || null,
      preview_image_url: item.preview_image_url || null,
      width: item.width || null,
      height: item.height || null
    }));
  }

  function apiAuthor(tweet) {
    const authorId = String(tweet && tweet.author_id || "");
    const author = userById.get(authorId);
    if (!author) return null;
    return {
      name: String(author.name || author.username || ""),
      handle: author.username ? String(author.username) : null,
      avatar_url: author.profile_image_url || null,
      verified: Boolean(author.verified)
    };
  }

  function apiEmbedded(ref) {
    if (!ref || !ref.id) return null;
    const tweet = tweetById.get(String(ref.id));
    if (!tweet) return null;
    const author = apiAuthor(tweet);
    const handle = author && author.handle ? author.handle : "";
    return {
      id: String(tweet.id || ref.id),
      text: String(tweet.text || ""),
      created_at: tweet.created_at || null,
      lang: tweet.lang || null,
      author,
      metrics: tweet.public_metrics || {},
      entities: tweet.entities || {},
      media: apiMedia(tweet),
      url: handle
        ? `https://x.com/${encodeURIComponent(handle)}/status/${tweet.id || ref.id}`
        : `https://x.com/i/web/status/${tweet.id || ref.id}`
    };
  }

  const posts = (Array.isArray(payload && payload.data) ? payload.data : []).map((post) => {
    const refs = Array.isArray(post && post.referenced_tweets) ? post.referenced_tweets : [];
    const refTypes = new Set(refs.map((item) => String(item && item.type || "")));
    const postType = refTypes.has("retweeted")
      ? "retweet"
      : (refTypes.has("replied_to") ? "reply" : (refTypes.has("quoted") ? "quote" : "post"));
    const embedRef = refs.find((item) => item && item.type === "retweeted")
      || refs.find((item) => item && item.type === "quoted")
      || null;
    return {
      id: String(post.id || ""),
      text: String(post.text || ""),
      created_at: post.created_at || null,
      lang: post.lang || null,
      post_type: postType,
      referenced_tweets: refs,
      embedded_post: apiEmbedded(embedRef),
      metrics: post.public_metrics || {},
      entities: post.entities || {},
      media: apiMedia(post),
      url: `https://x.com/${profile.handle}/status/${post.id}`
    };
  });

  return {
    schema_version: 2,
    source: "x_api",
    leader: {
      id: profile.id,
      name: profile.name,
      handle: profile.handle,
      user_id: user.id,
      profile_image_url: user.profile_image_url || null,
      verified: Boolean(user.verified),
      public_metrics: user.public_metrics || {},
      created_at: user.created_at || null,
      url: user.url || null
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
      public_metrics: cached.leader.public_metrics || {},
      created_at: cached.leader.created_at || null,
      url: cached.leader.url || null
    };
  }

  if (!user) {
    const username = encodeURIComponent(profile.handle);
    const userPayload = await xApiGet(
      `/2/users/by/username/${username}?user.fields=profile_image_url,verified,public_metrics,description,created_at,url`,
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
    "tweet.fields": "created_at,public_metrics,lang,entities,attachments,referenced_tweets,author_id",
    expansions: "attachments.media_keys,referenced_tweets.id,referenced_tweets.id.author_id",
    "media.fields": "media_key,type,url,preview_image_url,width,height",
    "user.fields": "name,username,profile_image_url,verified"
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

    const shareMatch = url.pathname.match(/^\/share\/tech-leaders\/([A-Za-z0-9_]{1,15})\/(\d{10,25})\/?$/);
    if (shareMatch) {
      const handle = normalizeXHandle(shareMatch[1]);
      const postId = shareMatch[2];
      try {
        const result = await getFreeTechLeaderPost(handle, postId, env);
        return techLeaderShareResponse(handle, result.post, url);
      } catch (err) {
        return techLeaderShareResponse(handle || shareMatch[1], {
          id: postId,
          text: "",
          url: `https://x.com/${encodeURIComponent(handle || shareMatch[1])}/status/${encodeURIComponent(postId)}`,
          media: []
        }, url);
      }
    }

    if (url.pathname === "/health") {
      return json({ ok: true, service: "ooglex-pro-api" }, 200, { ...cors, "cache-control": "no-store" });
    }

    if (url.pathname === "/v1/access") {
      const product = url.searchParams.get("product") || "";
      if (!PRODUCTS[product]) return json({ error: "unknown_product" }, 400, cors);
      const access = await getAccess(product, token, env);
      return json({ product, ...access }, 200, { ...cors, "cache-control": "no-store" });
    }

function techLeaderMediaHostAllowed(hostname) {
  const host = String(hostname || "").toLowerCase();
  const exact = new Set([
    "pbs.twimg.com",
    "video.twimg.com",
    "abs.twimg.com",
    "ton.twimg.com",
    "syndication.twitter.com",
    "fxtwitter.com",
    "api.fxtwitter.com",
    "media.tenor.com"
  ]);
  if (exact.has(host)) return true;
  return host.endsWith(".fxtwitter.com") ||
    host.endsWith(".twittpr.com") ||
    host.endsWith(".fixupx.com");
}

function parseTechLeaderMediaUrl(raw) {
  if (!raw) return null;
  try {
    const target = new URL(String(raw));
    if (target.protocol !== "https:") return null;
    if (target.username || target.password) return null;
    if (!techLeaderMediaHostAllowed(target.hostname)) return null;
    return target;
  } catch {
    return null;
  }
}

async function proxyTechLeaderMedia(request, target, cors) {
  const reqHeaders = new Headers();
  reqHeaders.set("accept", request.headers.get("accept") || "image/avif,image/webp,image/apng,image/svg+xml,image/*,video/*,*/*;q=0.8");
  reqHeaders.set("user-agent", "Mozilla/5.0 (compatible; Ooglex-Tech-Leaders-Media/1.0)");
  reqHeaders.set("referer", "https://x.com/");
  const range = request.headers.get("range");
  if (range) reqHeaders.set("range", range);

  const upstream = await fetch(target.toString(), {
    method: request.method === "HEAD" ? "HEAD" : "GET",
    redirect: "follow",
    headers: reqHeaders
  });

  if (!upstream.ok && upstream.status !== 206) {
    return json({
      error: "media_upstream_error",
      upstream_status: upstream.status,
      uses_x_api: false
    }, upstream.status >= 400 && upstream.status < 600 ? upstream.status : 502, {
      ...cors,
      "cache-control": "no-store",
      "x-ooglex-x-api": "unused"
    });
  }

  const headers = new Headers(cors);
  const contentType = upstream.headers.get("content-type") || "application/octet-stream";
  headers.set("content-type", contentType);
  headers.set("cache-control", range ? "public, max-age=3600" : "public, max-age=86400, stale-while-revalidate=604800");
  headers.set("x-ooglex-x-api", "unused");
  headers.set("x-ooglex-media-proxy", "1");
  headers.set("accept-ranges", upstream.headers.get("accept-ranges") || "bytes");
  const contentRange = upstream.headers.get("content-range");
  const contentLength = upstream.headers.get("content-length");
  if (contentRange) headers.set("content-range", contentRange);
  if (contentLength) headers.set("content-length", contentLength);

  return new Response(request.method === "HEAD" ? null : upstream.body, {
    status: upstream.status,
    headers
  });
}

    if (url.pathname === "/v1/tech-leaders/media") {
      if (request.method !== "GET" && request.method !== "HEAD") {
        return json({ error: "method_not_allowed", uses_x_api: false }, 405, {
          ...cors,
          allow: "GET, HEAD",
          "x-ooglex-x-api": "unused"
        });
      }
      const target = parseTechLeaderMediaUrl(url.searchParams.get("url"));
      if (!target) {
        return json({ error: "invalid_media_url", uses_x_api: false }, 400, {
          ...cors,
          "cache-control": "no-store",
          "x-ooglex-x-api": "unused"
        });
      }
      try {
        return await proxyTechLeaderMedia(request, target, cors);
      } catch {
        return json({ error: "media_proxy_unavailable", uses_x_api: false }, 502, {
          ...cors,
          "cache-control": "no-store",
          "x-ooglex-x-api": "unused"
        });
      }
    }

    if (url.pathname === "/v1/tech-leaders/free-feed") {
      const handle = normalizeXHandle(url.searchParams.get("handle"));
      const limit = boundedInt(url.searchParams.get("limit"), 1, TECH_FREE_FEED_MAX_ITEMS, 10);
      if (!handle) return json({ error: "invalid_free_feed_handle" }, 400, cors);
      try {
        const feed = await getFreeTechLeaderFeed(handle, limit, env);
        return json(feed, 200, {
          ...cors,
          "cache-control": "public, max-age=120, stale-while-revalidate=600",
          "x-ooglex-source": feed.source || "public-source",
          "x-ooglex-x-api": "unused"
        });
      } catch (err) {
        const code = err && err.code ? err.code : "x_public_feed_unavailable";
        const status = err && Number.isInteger(err.status) ? err.status : 502;
        return json({
          error: code,
          handle,
          uses_x_api: false,
          upstream_status: err && err.status ? err.status : null,
          diagnostic: err && err.detail ? err.detail : null
        }, status, { ...cors, "cache-control": "no-store", "x-ooglex-x-api": "unused" });
      }
    }

    if (url.pathname === "/v1/tech-leaders/post") {
      const handle = normalizeXHandle(url.searchParams.get("handle"));
      const postId = String(url.searchParams.get("id") || "").trim();
      if (!handle || !/^\d{10,25}$/.test(postId)) {
        return json({ error: "invalid_free_post", uses_x_api: false }, 400, {
          ...cors,
          "cache-control": "no-store",
          "x-ooglex-x-api": "unused"
        });
      }
      try {
        const result = await getFreeTechLeaderPost(handle, postId, env);
        return json(result, 200, {
          ...cors,
          "cache-control": "public, max-age=300, stale-while-revalidate=1800",
          "x-ooglex-x-api": "unused"
        });
      } catch (err) {
        const status = err && Number.isInteger(err.status) ? err.status : 502;
        return json({
          error: err && err.code ? err.code : "free_post_unavailable",
          handle,
          id: postId,
          uses_x_api: false
        }, status, {
          ...cors,
          "cache-control": "no-store",
          "x-ooglex-x-api": "unused"
        });
      }
    }

    if (url.pathname === "/v1/tech-leaders/free-profile") {
      const handle = normalizeXHandle(url.searchParams.get("handle"));
      const name = String(url.searchParams.get("name") || "").trim().slice(0, 120);
      if (!handle) return json({ error: "invalid_profile_handle" }, 400, cors);
      try {
        const profile = await getFreePublicXProfile(handle, name, env);
        return json(profile, 200, {
          ...cors,
          "cache-control": "public, max-age=300, stale-while-revalidate=3600",
          "x-ooglex-source": profile.source || "x-public-sources",
          "x-ooglex-x-api": "unused"
        });
      } catch (err) {
        const code = err && err.code ? err.code : "x_public_profile_unavailable";
        const status = err && Number.isInteger(err.status) ? err.status : 502;
        return json({
          error: code,
          handle,
          uses_x_api: false
        }, status, { ...cors, "cache-control": "no-store", "x-ooglex-x-api": "unused" });
      }
    }

    if (url.pathname === "/v1/tech-leaders/profile") {
      const handle = normalizeXHandle(url.searchParams.get("handle"));
      const name = String(url.searchParams.get("name") || "").trim().slice(0, 120);
      if (!handle) return json({ error: "invalid_profile_handle" }, 400, cors);
      try {
        const profile = await getPublicXProfile(handle, name, env);
        return json(profile, 200, {
          ...cors,
          "cache-control": "public, max-age=300, stale-while-revalidate=3600",
          "x-ooglex-source": profile.uses_x_api ? "x-profile-cache" : "x-public-syndication"
        });
      } catch (err) {
        const code = err && err.code ? err.code : "x_public_profile_unavailable";
        const status = err && Number.isInteger(err.status) ? err.status : 502;
        return json({ error: code, handle }, status, { ...cors, "cache-control": "no-store" });
      }
    }

    if (url.pathname === "/v1/tech-leaders/avatar-audit") {
      const raw = String(url.searchParams.get("handles") || "");
      const handles = raw.split(",").map((value) => value.trim()).filter(Boolean);
      if (!handles.length) return json({ error: "avatar_handles_required" }, 400, cors);
      const audit = await getTechLeaderAvatarAudit(handles, env);
      return json(audit, 200, { ...cors, "cache-control": "no-store" });
    }

    if (url.pathname === "/v1/tech-leaders/avatar") {
      const handle = normalizeXHandle(url.searchParams.get("handle"));
      const name = String(url.searchParams.get("name") || "").trim().slice(0, 120);
      const company = String(url.searchParams.get("company") || "").trim().slice(0, 120);
      if (!handle) return json({ error: "invalid_avatar_handle" }, 400, cors);
      try {
        const avatar = await getTechLeaderAvatar(handle, name, company, env);
        const headers = new Headers(cors);
        avatar.headers.forEach((value, headerName) => headers.set(headerName, value));
        return new Response(avatar.body, { status: 200, headers });
      } catch (err) {
        const code = err && err.code ? err.code : "avatar_unavailable";
        const status = err && Number.isInteger(err.status) ? err.status : 502;
        return json({ error: code, handle }, status, { ...cors, "cache-control": "no-store" });
      }
    }

    if (url.pathname === "/v1/tech-leaders/share-avatar") {
      return techLeaderShareAvatarResponse(url, env, cors);
    }

    if (url.pathname === "/v1/tech-leaders/catalog-share-cover") {
      return techLeaderCatalogShareCoverResponse(env, cors);
    }

    if (url.pathname === "/v1/tech-leaders/status") {
      return json({
        ok: true,
        service: "tech-leaders",
        source: "x_api",
        configured: Boolean(env.X_BEARER_TOKEN),
        free_feed: {
          enabled: true,
          source: "public_source_ladder",
          sources: ["x_public_syndication", "fxtwitter_public_api"],
          uses_x_api: false,
          max_items: TECH_FREE_FEED_MAX_ITEMS,
          display_batch_size: 10,
          cache_ttl_seconds: Math.round(TECH_FREE_FEED_TTL_MS / 1000),
          strict_profile_cache_ttl_seconds: Math.round(TECH_FREE_FEED_STRICT_TTL_MS / 1000),
          strict_profile_strategy: "elonmusk: FxTwitter since=7d + media-only normalization"
        },
        free_mode_contract: {
          calls_api_x_com: false,
          free_profile_endpoint: "/v1/tech-leaders/free-profile",
          free_feed_endpoint: "/v1/tech-leaders/free-feed",
          single_post_endpoint: "/v1/tech-leaders/post",
          media_proxy_endpoint: "/v1/tech-leaders/media",
          share_avatar_endpoint: "/v1/tech-leaders/share-avatar",
          catalog_share_cover_endpoint: "/v1/tech-leaders/catalog-share-cover"
        },
        cache_ttl_seconds: Math.round(TECH_FEED_TTL_MS / 1000),
        avatar_policy: TECH_AVATAR_POLICY,
        avatar_cache_version: TECH_AVATAR_CACHE_VERSION,
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
