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
const TECH_FREE_FEED_MAX_ITEMS = 20;
const TECH_FREE_FEED_TTL_MS = 30 * 60 * 1000;
const TECH_FREE_FEED_MAX_STALE_MS = 48 * 60 * 60 * 1000;
const TECH_PROFILE_CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const TECH_PROFILE_MAX_STALE_MS = 7 * 24 * 60 * 60 * 1000;

const TECH_AVATAR_MAX_BYTES = 3 * 1024 * 1024;
const TECH_AVATAR_CACHE_CONTROL = "public, max-age=21600, stale-while-revalidate=86400";
const TECH_AVATAR_CACHE_VERSION = "v6-x-current-first";
const TECH_AVATAR_POLICY = "x_original_then_verified_fallback";
const TECH_AVATAR_REFRESH_X_MS = 72 * 60 * 60 * 1000;
const TECH_AVATAR_REFRESH_PROXY_MS = 24 * 60 * 60 * 1000;
const TECH_AVATAR_REFRESH_FALLBACK_MS = 6 * 60 * 60 * 1000;

// Only use explicit fallback portraits from first-party company/institution sources.
// These are consulted only after all X-avatar routes fail.
const TECH_AVATAR_OFFICIAL_OVERRIDES = Object.freeze({
  rajaxg: "https://d1io3yog0oux5.cloudfront.net/_3ccf9cf30376bf77bbb27f582e51d00d/intel/news/193/1779/image.jpeg",
  sytses: "https://res.cloudinary.com/about-gitlab-com/image/upload/v1755613184/abfz99qjcfcvo6em0sgm.webp",
  svlevine: "https://vcresearch.berkeley.edu/sites/default/files/styles/faculty_photo_thumbnail/public/2023-04/sergey_levin_20200122_AVL_0050.jpg?h=726b1c9d&itok=Aa7Rxyv2",
  aselipsky: "https://www.helixdi.com/wp-content/uploads/2026/04/Adam-Selipsky.png",
  thetimellis: "https://images.squarespace-cdn.com/content/v1/59a8fb50d2b8575fad311abb/32f80d6d-e088-4fa8-a0d8-76db4966ac46/Tim_Ellis_Web.png",
  marvinrellison: "https://corporate.lowes.com/sites/lowes-corp/files/BOD-images/Marvin-R.Ellison_0.jpg"
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
  if (source === "unavatar_x") return "x_original_proxy";
  if (source === "official_override") return "official_fallback";
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
  return { ok: true, bytes, contentType, source, sourceType: avatarSourceType(source) };
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

  const params = new URLSearchParams({
    action: "query",
    generator: "search",
    gsrsearch: [cleanName, cleanCompany].filter(Boolean).join(" "),
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
      "user-agent": "Ooglex-Tech-Leaders-Avatar/5.1 (https://ooglex.com)"
    }
  });
  if (!res.ok) return { ok: false, status: res.status, source: "wikipedia" };

  let payload = null;
  try { payload = await res.json(); } catch {}
  const pages = payload && payload.query && Array.isArray(payload.query.pages) ? payload.query.pages : [];

  for (const page of pages) {
    if (!page || !page.thumbnail || !page.thumbnail.source) continue;
    if (!wikiTitleMatchesPerson(page.title, cleanName)) continue;
    const image = await fetchTechAvatarImage(page.thumbnail.source, "wikipedia");
    if (image.ok) return image;
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

  // 2) Only then use an X avatar proxy/mirror.
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

  return {
    ok: false,
    status: commons.status || wikipedia.status || xProxy.status || syndicated.status || followButton.status || direct.status || directX.status || 502,
    source: "avatar_unavailable",
    sourceType: "unknown"
  };
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
    else if (sourceType === "official_fallback" || sourceType === "public_fallback") status = "fallback";

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

function syndicationTweetAuthor(candidate) {
  const paths = [
    candidate && candidate.core && candidate.core.user_results && candidate.core.user_results.result,
    candidate && candidate.user_results && candidate.user_results.result,
    candidate && candidate.user
  ];
  for (const user of paths) {
    if (!user || typeof user !== "object") continue;
    const legacy = user.legacy && typeof user.legacy === "object" ? user.legacy : user;
    const screen = String(legacy.screen_name || legacy.username || user.username || "").replace(/^@/, "");
    if (screen) return screen;
  }
  return "";
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
  return {
    id,
    text,
    created_at: createdAt,
    lang: legacy.lang || candidate.lang || null,
    metrics,
    entities: normalizeSyndicationEntities(legacy.entities || candidate.entities),
    media: normalizeSyndicationMedia(legacy),
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

function normalizeFxTwitterStatus(status, handle) {
  if (!status || typeof status !== "object") return null;
  const id = String(status.id || status.rest_id || "");
  const text = String(status.text || status.full_text || "").trim();
  if (!/^\d{10,25}$/.test(id) || !text) return null;
  let createdAt = status.created_at || null;
  if (!createdAt && Number.isFinite(Number(status.created_timestamp))) {
    createdAt = new Date(Number(status.created_timestamp) * 1000).toISOString();
  }
  return {
    id,
    text,
    created_at: createdAt,
    lang: status.lang || null,
    metrics: {
      reply_count: Number(status.replies || 0),
      repost_count: Number(status.reposts || status.retweets || 0),
      retweet_count: Number(status.reposts || status.retweets || 0),
      like_count: Number(status.likes || 0),
      quote_count: Number(status.quotes || 0)
    },
    entities: { urls: [] },
    media: normalizeFxTwitterMedia(status),
    url: String(status.url || `https://x.com/${encodeURIComponent(handle)}/status/${id}`)
  };
}

async function fetchFxTwitterFreeFeed(handle, limit) {
  const count = Math.max(3, Math.min(20, limit || TECH_FEED_FETCH_SIZE));
  const url = `https://api.fxtwitter.com/2/profile/${encodeURIComponent(handle)}/statuses?count=${count}`;
  const res = await fetch(url, {
    redirect: "follow",
    headers: {
      accept: "application/json",
      "user-agent": "Ooglex-Tech-Leaders-Free-Feed/2.0"
    }
  });
  let payload = null;
  try { payload = await res.json(); } catch {}
  if (!res.ok || !payload || Number(payload.code || res.status) >= 400) {
    const err = new Error("fxtwitter_public_feed_error");
    err.code = "fxtwitter_public_feed_error";
    err.status = res.status || Number(payload && payload.code) || 502;
    throw err;
  }
  const results = Array.isArray(payload.results) ? payload.results : [];
  const posts = results.map((item) => normalizeFxTwitterStatus(item, handle)).filter(Boolean).slice(0, limit);
  if (!posts.length) {
    const err = new Error("fxtwitter_public_feed_empty");
    err.code = "fxtwitter_public_feed_empty";
    err.status = 502;
    throw err;
  }
  return {
    schema_version: 2,
    source: "fxtwitter_public_api",
    third_party: "FxEmbed/FxTwitter",
    uses_x_api: false,
    handle,
    fetched_at: new Date().toISOString(),
    posts
  };
}

async function fetchOfficialSyndicationFreeFeed(handle, limit) {
  const params = new URLSearchParams({
    dnt: "true",
    frame: "false",
    hideBorder: "true",
    hideFooter: "true",
    hideHeader: "true",
    lang: "en",
    limit: String(Math.max(3, Math.min(20, limit || TECH_FEED_FETCH_SIZE))),
    origin: "https://www.ooglex.com/",
    showHeader: "false",
    showReplies: "false",
    theme: "light",
    transparent: "true"
  });
  const url = `https://syndication.twitter.com/srv/timeline-profile/screen-name/${encodeURIComponent(handle)}?${params.toString()}`;
  const res = await fetch(url, {
    redirect: "follow",
    headers: {
      accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "accept-language": "en-US,en;q=0.9",
      referer: "https://publish.twitter.com/",
      "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    }
  });
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
    schema_version: 2,
    source: "x_public_syndication",
    uses_x_api: false,
    handle,
    fetched_at: new Date().toISOString(),
    posts
  };
}

async function fetchFreeTechLeaderFeed(handle, limit) {
  let officialError = null;
  try {
    return await fetchOfficialSyndicationFreeFeed(handle, limit);
  } catch (err) {
    officialError = err;
  }

  try {
    return await fetchFxTwitterFreeFeed(handle, limit);
  } catch (fxErr) {
    const err = new Error("free_public_feed_sources_unavailable");
    err.code = "free_public_feed_sources_unavailable";
    err.status = fxErr && Number.isInteger(fxErr.status) ? fxErr.status : 502;
    err.detail = {
      official_source: officialError && officialError.code ? officialError.code : "unknown",
      official_status: officialError && officialError.status ? officialError.status : null,
      fallback_source: fxErr && fxErr.code ? fxErr.code : "unknown",
      fallback_status: fxErr && fxErr.status ? fxErr.status : null
    };
    throw err;
  }
}

async function getFreeTechLeaderFeed(handle, limit, env) {
  const normalized = normalizeXHandle(handle);
  if (!normalized) {
    const err = new Error("invalid_free_feed_handle");
    err.code = "invalid_free_feed_handle";
    err.status = 400;
    throw err;
  }
  const key = `tech-leaders/free-feed/v1/${normalized.toLowerCase()}.json`;
  const cached = await readJson(env.PRO_DATA, key);
  const cachedAt = cached && cached.fetched_at ? Date.parse(cached.fetched_at) : NaN;
  const age = Number.isFinite(cachedAt) ? Math.max(0, Date.now() - cachedAt) : Infinity;
  const cachedPosts = cached && Array.isArray(cached.posts) ? cached.posts : [];
  const cachedRequestedLimit = Math.max(
    cachedPosts.length,
    Number(cached && cached.requested_limit) || 0
  );

  if (cachedPosts.length && age <= TECH_FREE_FEED_TTL_MS && cachedRequestedLimit >= limit) {
    return { ...cached, posts: cachedPosts.slice(0, limit), cache: { status: "fresh", age_ms: age } };
  }

  try {
    const requestedLimit = Math.max(limit, TECH_FEED_FETCH_SIZE);
    const fresh = await fetchFreeTechLeaderFeed(normalized, requestedLimit);
    const persisted = { ...fresh, requested_limit: requestedLimit };
    await writeJson(env.PRO_DATA, key, persisted);
    return { ...persisted, posts: persisted.posts.slice(0, limit), cache: { status: "refreshed", age_ms: 0 } };
  } catch (err) {
    if (cachedPosts.length && age <= TECH_FREE_FEED_MAX_STALE_MS) {
      return {
        ...cached,
        posts: cachedPosts.slice(0, limit),
        cache: { status: "stale", age_ms: age, reason: err && err.code ? err.code : "x_public_feed_error" }
      };
    }
    throw err;
  }
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
          cache_ttl_seconds: Math.round(TECH_FREE_FEED_TTL_MS / 1000)
        },
        free_mode_contract: {
          calls_api_x_com: false,
          free_profile_endpoint: "/v1/tech-leaders/free-profile",
          free_feed_endpoint: "/v1/tech-leaders/free-feed",
          media_proxy_endpoint: "/v1/tech-leaders/media"
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
