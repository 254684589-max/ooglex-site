/* OOGLEX_AUTH_SESSION_V2
   全站共用的登录会话读取与续期。
   Supabase 的 access_token 约 1 小时过期，只有账户页加载了 supabase-js 会自动续期；
   用户登录后只浏览各应用页时，localStorage 里的旧 token 过期，权限校验就会把
   已登录用户当成访客，退回 10% 预览。这里在 token 临近过期时用 refresh_token
   向 Supabase 换新 token 并写回同一个存储键（与 supabase-js 的格式一致）。
   只用公开的 publishable key，不涉及任何密钥。 */
(function () {
  "use strict";
  if (window.OoglexAuthSession) return;

  var PROJECT_REF = "nwthqkpkvbtilafqpjlf";
  var STORAGE_KEY = "sb-" + PROJECT_REF + "-auth-token";
  var SUPABASE_URL = "https://nwthqkpkvbtilafqpjlf.supabase.co";
  var SUPABASE_PUBLISHABLE_KEY = "sb_publishable_Vf8spXXXksPHKvfxp2XPcw_1dfaIR6r";
  var REFRESH_MARGIN_S = 60;
  var DEFAULT_PRO_API = "https://pro-api.ooglex.com";
  var REFRESH_TIMEOUT_MS = 5000;
  var inflight = null;

  function readSession() {
    try {
      var raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      var parsed = JSON.parse(raw);
      return parsed && parsed.access_token ? parsed : null;
    } catch (_) {
      return null;
    }
  }

  // 返回 token 的过期时间（秒）；解不出来时返回 0，表示“不知道”，不据此判过期。
  function expiresAt(session) {
    if (!session) return 0;
    var exp = Number(session.expires_at);
    if (exp > 0) return exp;
    try {
      var part = String(session.access_token).split(".")[1];
      if (!part) return 0;
      var json = atob(part.replace(/-/g, "+").replace(/_/g, "/"));
      exp = Number(JSON.parse(json).exp);
      return exp > 0 ? exp : 0;
    } catch (_) {
      return 0;
    }
  }

  function isExpiring(session, marginS) {
    var exp = expiresAt(session);
    if (!exp) return false;
    return exp - Date.now() / 1000 <= (marginS == null ? REFRESH_MARGIN_S : marginS);
  }

  function proApiBase() {
    var meta = document.querySelector('meta[name="ooglex-pro-api"]');
    var value = meta && meta.getAttribute("content");
    return (value || window.OOGLEX_PRO_API || DEFAULT_PRO_API).replace(/\/$/, "");
  }

  // 发一次续期请求，返回 { status: "ok" | "denied" | "unreachable", session }。
  async function requestRefresh(url, headers, refreshToken) {
    var ctrl = typeof AbortController === "function" ? new AbortController() : null;
    var timer = ctrl ? setTimeout(function () { try { ctrl.abort(); } catch (_) {} }, REFRESH_TIMEOUT_MS) : null;
    try {
      var res = await fetch(url, {
        method: "POST",
        cache: "no-store",
        headers: headers,
        body: JSON.stringify({ refresh_token: refreshToken }),
        signal: ctrl ? ctrl.signal : undefined
      });
      if (res.status === 400 || res.status === 401 || res.status === 403) return { status: "denied" };
      if (!res.ok) return { status: "unreachable" };
      var next = await res.json();
      return next && next.access_token ? { status: "ok", session: next } : { status: "unreachable" };
    } catch (_) {
      return { status: "unreachable" };
    } finally {
      if (timer) clearTimeout(timer);
    }
  }

  // 先经本站会员接口（pro-api，大陆网络可达）续期；它连不上时才直连 Supabase。
  // 续期令牌被明确拒绝时不再换路重试，避免同一个 refresh_token 被用两次。
  async function refresh(session) {
    if (!session || !session.refresh_token) return null;
    var json = { "content-type": "application/json" };
    var result = await requestRefresh(proApiBase() + "/v1/auth/refresh", json, session.refresh_token);
    if (result.status === "unreachable") {
      result = await requestRefresh(
        SUPABASE_URL + "/auth/v1/token?grant_type=refresh_token",
        { apikey: SUPABASE_PUBLISHABLE_KEY, "content-type": "application/json" },
        session.refresh_token
      );
    }
    if (result.status !== "ok") return null;
    var next = result.session;
    // 另一个标签页（例如账户页的 supabase-js）可能已先续期，以最新存储为基准合并。
    var merged = Object.assign({}, readSession() || session, next);
    if (!next.expires_at && next.expires_in) {
      merged.expires_at = Math.floor(Date.now() / 1000) + Number(next.expires_in);
    }
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(merged)); } catch (_) {}
    return merged;
  }

  // 拿一个可用的 access_token：未过期直接返回；临近过期则续期（同页并发只续一次）。
  // 续期失败时返回原 token，由服务端给出最终判断。
  async function getAccessToken() {
    var session = readSession();
    if (!session) return "";
    if (!isExpiring(session)) return String(session.access_token);
    if (!inflight) {
      inflight = refresh(session).finally(function () { inflight = null; });
    }
    var fresh = await inflight;
    if (fresh && fresh.access_token) return String(fresh.access_token);
    var latest = readSession();
    return latest ? String(latest.access_token) : "";
  }

  window.OoglexAuthSession = Object.freeze({
    storageKey: STORAGE_KEY,
    getSession: readSession,
    expiresAt: expiresAt,
    isExpiring: isExpiring,
    getAccessToken: getAccessToken
  });
})();
