/* OOGLEX_ACCESS_GATE_V1
   Anonymous visitors get an approximately 10% preview on /apps/ and /games/.
   A verified Supabase Auth session unlocks the full page.
   Standalone copy for pages that intentionally do not load /assets/theme.js. */
(function () {
  "use strict";
  if (window.OoglexSiteAccess) return;

  var PATH = window.location.pathname || "/";
  var PROJECT_REF = "nwthqkpkvbtilafqpjlf";
  var AUTH_KEY = "sb-" + PROJECT_REF + "-auth-token";
  var SUPABASE_URL = "https://nwthqkpkvbtilafqpjlf.supabase.co";
  var SUPABASE_PUBLISHABLE_KEY = "sb_publishable_Vf8spXXXksPHKvfxp2XPcw_1dfaIR6r";
  var VERIFY_TIMEOUT_MS = 4500;
  var resolveReady;
  var ready = new Promise(function (resolve) { resolveReady = resolve; });

  function protectedPath() { return /^\/(apps|games)(\/|$)/.test(PATH); }
  function storedToken() {
    try {
      var raw = localStorage.getItem(AUTH_KEY);
      if (!raw) return "";
      var parsed = JSON.parse(raw);
      return parsed && parsed.access_token ? String(parsed.access_token) : "";
    } catch (_) { return ""; }
  }
  async function verifyToken(token) {
    if (!token) return false;
    var ctrl = typeof AbortController === "function" ? new AbortController() : null;
    var timer = ctrl ? setTimeout(function () { try { ctrl.abort(); } catch (_) {} }, VERIFY_TIMEOUT_MS) : null;
    try {
      var response = await fetch(SUPABASE_URL + "/auth/v1/user", {
        method: "GET",
        cache: "no-store",
        headers: { apikey: SUPABASE_PUBLISHABLE_KEY, Authorization: "Bearer " + token },
        signal: ctrl ? ctrl.signal : undefined
      });
      return response.ok;
    } catch (_) { return false; }
    finally { if (timer) clearTimeout(timer); }
  }
  function addStyles() {
    if (document.getElementById("ooglex-registration-preview-style")) return;
    var style = document.createElement("style");
    style.id = "ooglex-registration-preview-style";
    style.textContent =
      "html.ooglex-access-checking body{max-height:46vh!important;overflow:hidden!important}" +
      "#ooglex-registration-preview{position:absolute;left:0;right:0;z-index:2147483647;min-height:520px;display:flex;justify-content:center;align-items:flex-start;padding:72px 20px 120px;background:linear-gradient(to bottom,rgba(11,14,19,0),#0b0e13 54px,#0b0e13 100%);color:#f1f5f9;font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei','Segoe UI',sans-serif}" +
      "#ooglex-registration-preview .ogx-access-card{width:min(560px,calc(100vw - 32px));padding:26px 28px;border:1px solid rgba(255,255,255,.14);border-radius:16px;background:#10141b;box-shadow:0 24px 72px rgba(0,0,0,.26);text-align:center}" +
      "#ooglex-registration-preview .ogx-access-kicker{font:700 11px/1.2 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;letter-spacing:.15em;color:#8b93a1}" +
      "#ooglex-registration-preview h2{margin:10px 0 8px;font-size:24px;line-height:1.25;color:#f1f5f9}" +
      "#ooglex-registration-preview p{margin:0;color:#a8b0bc;font-size:14px;line-height:1.7}" +
      "#ooglex-registration-preview .ogx-access-actions{display:flex;gap:10px;justify-content:center;flex-wrap:wrap;margin-top:20px}" +
      "#ooglex-registration-preview a{display:inline-flex;align-items:center;justify-content:center;min-width:150px;height:44px;padding:0 18px;border-radius:9px;text-decoration:none;font-weight:700}" +
      "#ooglex-registration-preview .ogx-access-primary{background:#1f6feb;color:#fff}" +
      "#ooglex-registration-preview .ogx-access-secondary{border:1px solid rgba(255,255,255,.18);color:#f1f5f9;background:rgba(255,255,255,.05)}";
    document.head.appendChild(style);
  }
  function accountUrl() {
    return "/account/?next=" + encodeURIComponent(PATH + window.location.search + window.location.hash);
  }
  function mountPreview() {
    addStyles();
    var root = document.documentElement;
    root.classList.remove("ooglex-access-checking");
    root.classList.add("ooglex-access-preview");
    var old = document.getElementById("ooglex-registration-preview");
    if (old) old.remove();

    var body = document.body;
    if (!body) return;
    var total = Math.max(body.scrollHeight || 0, root.scrollHeight || 0, root.clientHeight || 0, window.innerHeight || 0);
    var cutoff = Math.max(220, Math.floor(total * 0.10));
    var cap = cutoff + Math.max(560, window.innerHeight || 0);
    body.style.setProperty("height", cap + "px", "important");
    body.style.setProperty("max-height", cap + "px", "important");
    body.style.setProperty("overflow", "hidden", "important");

    var gate = document.createElement("div");
    gate.id = "ooglex-registration-preview";
    gate.style.top = cutoff + "px";
    gate.innerHTML =
      '<section class="ogx-access-card" role="region" aria-label="注册访问提示">' +
      '<div class="ogx-access-kicker">OOGLEX · 10% PREVIEW</div>' +
      '<h2>未注册用户仅开放约 10% 预览</h2>' +
      '<p>注册并登录后可访问该板块全部内容。现有账户直接登录即可解锁。</p>' +
      '<div class="ogx-access-actions">' +
      '<a class="ogx-access-primary" href="' + accountUrl() + '#signup">注册后完整访问</a>' +
      '<a class="ogx-access-secondary" href="' + accountUrl() + '">已有账户 · 登录</a>' +
      '</div></section>';
    body.appendChild(gate);
  }
  function applyPreview() {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function () { setTimeout(mountPreview, 120); }, { once: true });
    } else setTimeout(mountPreview, 120);
  }
  function unlock() {
    document.documentElement.classList.remove("ooglex-access-checking", "ooglex-access-preview");
    var gate = document.getElementById("ooglex-registration-preview");
    if (gate) gate.remove();
    if (document.body) {
      document.body.style.removeProperty("height");
      document.body.style.removeProperty("max-height");
      document.body.style.removeProperty("overflow");
    }
  }

  window.OoglexSiteAccess = Object.freeze({ ready: ready, getStoredToken: storedToken, isProtectedPath: protectedPath });
  if (!protectedPath()) { resolveReady(true); return; }

  addStyles();
  document.documentElement.classList.add("ooglex-access-checking");
  (async function () {
    var ok = await verifyToken(storedToken());
    if (ok) unlock(); else applyPreview();
    resolveReady(ok);
    try { document.dispatchEvent(new CustomEvent("ooglex:accessready", { detail: { authenticated: ok } })); } catch (_) {}
  })();
})();