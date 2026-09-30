const WINDY_ENDPOINT = 'https://api.windy.com/webcams/api/v3/webcams';

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin') || '';
    const cors = corsHeaders(origin, env.ALLOWED_ORIGINS);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (request.method !== 'GET') return json({ error: 'Method not allowed' }, 405, cors);

    const url = new URL(request.url);
    if (url.pathname === '/health') {
      return json({ ok: true, windyConfigured: Boolean(env.WINDY_WEBCAMS_API_KEY) }, 200, cors);
    }
    if (url.pathname !== '/v1/webcams') return json({ error: 'Not found' }, 404, cors);
    if (!originAllowed(origin, env.ALLOWED_ORIGINS)) return json({ error: 'Origin not allowed' }, 403, cors);
    if (!env.WINDY_WEBCAMS_API_KEY) return json({ error: 'Windy API key is not configured' }, 503, cors);

    const lat = numberParam(url.searchParams.get('lat'), -90, 90);
    const lng = numberParam(url.searchParams.get('lng'), -180, 180);
    const radius = numberParam(url.searchParams.get('radius') || '250', 1, 250);
    const limit = integerParam(url.searchParams.get('limit') || '50', 1, 50);
    const lang = /^[a-z]{2}(?:-[A-Z]{2})?$/.test(url.searchParams.get('lang') || '') ? url.searchParams.get('lang') : 'en';
    if (lat === null || lng === null || radius === null || limit === null) {
      return json({ error: 'Invalid lat/lng/radius/limit' }, 400, cors);
    }

    const upstream = new URL(WINDY_ENDPOINT);
    upstream.searchParams.set('nearby', [lat, lng, radius].join(','));
    upstream.searchParams.set('include', 'categories,images,location,player,urls');
    upstream.searchParams.set('lang', lang);
    upstream.searchParams.set('limit', String(limit));
    upstream.searchParams.set('sortKey', 'popularity');
    upstream.searchParams.set('sortDirection', 'desc');

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    try {
      const response = await fetch(upstream, {
        headers: {
          'X-WINDY-API-KEY': env.WINDY_WEBCAMS_API_KEY,
          'Accept': 'application/json'
        },
        signal: controller.signal
      });
      if (!response.ok) {
        return json({ error: 'Upstream webcam service unavailable', upstreamStatus: response.status }, response.status >= 500 ? 502 : 424, cors);
      }
      const payload = await response.json();
      const webcams = Array.isArray(payload.webcams) ? payload.webcams.map(normalizeWebcam).filter(Boolean) : [];
      return json({
        status: 'ok',
        demo: false,
        source: 'Windy Webcams API',
        asOf: new Date().toISOString(),
        total: Number(payload.total) || webcams.length,
        webcams
      }, 200, {
        ...cors,
        'Cache-Control': 'public, max-age=60, s-maxage=120',
        'X-Content-Type-Options': 'nosniff'
      });
    } catch (error) {
      const timeout = error && error.name === 'AbortError';
      return json({ error: timeout ? 'Upstream timeout' : 'Upstream request failed' }, 502, cors);
    } finally {
      clearTimeout(timer);
    }
  }
};

export function normalizeWebcam(w) {
  if (!w || w.status === 'inactive' || !w.location) return null;
  const lat = Number(w.location.latitude), lng = Number(w.location.longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  const current = w.images && w.images.current || {};
  const preview = firstString(current.preview, current.small, current.thumbnail, current.icon, ...Object.values(current));
  const player = w.player || {};
  const embed = firstString(player.live, player.day);
  return {
    id: String(w.webcamId || ''),
    name: String(w.title || 'Public webcam'),
    country: String(w.location.country || ''),
    city: String(w.location.city || w.location.region || ''),
    lat,
    lng,
    category: Array.isArray(w.categories) ? w.categories.map(x => x && x.name).filter(Boolean).slice(0, 3).join(' / ') : '',
    source: 'Windy Webcams API',
    preview_url: preview || '',
    embed_url: embed || '',
    source_url: String(w.urls && w.urls.detail || ''),
    playable: Boolean(embed || preview),
    demo: false,
    updated_at: String(w.lastUpdatedOn || '')
  };
}

function firstString(...values) {
  return values.find(v => typeof v === 'string' && /^https?:\/\//i.test(v)) || '';
}
function numberParam(value, min, max) {
  const n = Number(value);
  return Number.isFinite(n) && n >= min && n <= max ? n : null;
}
function integerParam(value, min, max) {
  const n = Number(value);
  return Number.isInteger(n) && n >= min && n <= max ? n : null;
}
function originAllowed(origin, allowed) {
  if (!origin) return false;
  const set = new Set(String(allowed || 'https://www.ooglex.com,https://ooglex.com').split(',').map(s => s.trim()).filter(Boolean));
  return set.has(origin);
}
function corsHeaders(origin, allowed) {
  const allow = originAllowed(origin, allowed) ? origin : 'https://www.ooglex.com';
  return {
    'Access-Control-Allow-Origin': allow,
    'Access-Control-Allow-Methods': 'GET,OPTIONS',
    'Access-Control-Allow-Headers': 'Accept,Content-Type',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin'
  };
}
function json(body, status, headers) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...headers }
  });
}
