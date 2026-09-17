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
  }
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
