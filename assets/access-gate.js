/* OOGLEX_ACCESS_GATE_V2
   Anonymous visitors get exactly 10% of the natural vertical content height on /apps/ and /games/.
   A verified Supabase Auth session unlocks the full page.
   The preview boundary is re-measured while dynamic content loads so every board stays close to 10%. */
(function () {
  "use strict";
  if (window.OoglexSiteAccess) return;

  var PATH = window.location.pathname || "/";
  var PREVIEW_RATIO = 0.10;
  var PROJECT_REF = "nwthqkpkvbtilafqpjlf";
  var AUTH_KEY = "sb-" + PROJECT_REF + "-auth-token";
  var SUPABASE_URL = "https://nwthqkpkvbtilafqpjlf.supabase.co";
  var SUPABASE_PUBLISHABLE_KEY = "sb_publishable_Vf8spXXXksPHKvfxp2XPcw_1dfaIR6r";
  var VERIFY_TIMEOUT_MS = 4500;
  var resolveReady;
  var ready = new Promise(function (resolve) { resolveReady = resolve; });
  var maxNaturalHeight = 0;
  var refreshTimer = 0;
  var stopObserveTimer = 0;
  var observer = null;

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
    } catch (_) {
      return false;
    } finally {
      if (timer) clearTimeout(timer);
    }
  }

  function addStyles() {
    if (document.getElementById("ooglex-registration-preview-style")) return;
    var style = document.createElement("style");
    style.id = "ooglex-registration-preview-style";
    style.textContent =
      "html.ooglex-access-checking body{max-height:10vh!important;overflow:hidden!important}" +
      "#ooglex-registration-preview{position:absolute;left:0;right:0;z-index:2147483647;min-height:560px;display:flex;justify-content:center;align-items:flex-start;padding:72px 20px 140px;background:linear-gradient(to bottom,rgba(11,14,19,0),#0b0e13 54px,#0b0e13 100%);color:#f1f5f9;font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei','Segoe UI',sans-serif}" +
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

  function ensureGate() {
    var gate = document.getElementById("ooglex-registration-preview");
    if (gate) return gate;
    gate = document.createElement("div");
    gate.id = "ooglex-registration-preview";
    gate.innerHTML =
      '<section class="ogx-access-card" role="region" aria-label="注册访问提示">' +
        '<div class="ogx-access-kicker">OOGLEX · 10% PREVIEW</div>' +
        '<h2>未注册用户仅开放 10% 预览</h2>' +
        '<p>当前板块仅展示前 10% 内容。注册并登录后可访问剩余 90%。</p>' +
        '<div class="ogx-access-actions">' +
          '<a class="ogx-access-primary" href="' + accountUrl() + '#signup">注册后完整访问</a>' +
          '<a class="ogx-access-secondary" href="' + accountUrl() + '">已有账户 · 登录</a>' +
        '</div>' +
      '</section>';
    document.body.appendChild(gate);
    return gate;
  }

  function clearBodyClamp() {
    if (!document.body) return;
    document.body.style.removeProperty("height");
    document.body.style.removeProperty("max-height");
    document.body.style.removeProperty("overflow");
  }

  function naturalHeight(gate) {
    var body = document.body;
    var root = document.documentElement;
    if (!body) return Math.max(root.scrollHeight || 0, window.innerHeight || 0);

    var oldDisplay = gate ? gate.style.display : "";
    if (gate) gate.style.display = "none";
    clearBodyClamp();

    var h = Math.max(
      body.scrollHeight || 0,
      body.offsetHeight || 0,
      root.scrollHeight || 0,
      root.offsetHeight || 0,
      root.clientHeight || 0,
      window.innerHeight || 0
    );

    if (gate) gate.style.display = oldDisplay;
    return h;
  }

  function layoutPreview() {
    var body = document.body;
    if (!body) return;
    var root = document.documentElement;
    var gate = ensureGate();

    var measured = naturalHeight(gate);
    if (measured > maxNaturalHeight) maxNaturalHeight = measured;
    var total = Math.max(maxNaturalHeight, measured, 1);
    var cutoff = Math.max(1, Math.floor(total * PREVIEW_RATIO));
    var overlayHeight = Math.max(560, window.innerHeight || 0);

    gate.style.top = cutoff + "px";
    gate.style.display = "flex";
    body.style.setProperty("height", (cutoff + overlayHeight) + "px", "important");
    body.style.setProperty("max-height", (cutoff + overlayHeight) + "px", "important");
    body.style.setProperty("overflow", "hidden", "important");

    root.setAttribute("data-ooglex-preview-ratio", "10");
    root.setAttribute("data-ooglex-preview-cutoff", String(cutoff));
    root.setAttribute("data-ooglex-preview-total", String(total));
  }

  function scheduleLayout(delay) {
    if (refreshTimer) clearTimeout(refreshTimer);
    refreshTimer = setTimeout(function () {
      refreshTimer = 0;
      layoutPreview();
    }, delay || 0);
  }

  function observeDynamicContent() {
    if (typeof MutationObserver === "undefined" || observer) return;
    observer = new MutationObserver(function (records) {
      for (var i = 0; i < records.length; i++) {
        var target = records[i].target;
        if (target && target.id === "ooglex-registration-preview") continue;
        scheduleLayout(220);
        break;
      }
    });
    observer.observe(document.body, { subtree: true, childList: true });
    stopObserveTimer = setTimeout(function () {
      if (observer) { observer.disconnect(); observer = null; }
    }, 12000);
  }

  function mountPreview() {
    addStyles();
    var root = document.documentElement;
    root.classList.remove("ooglex-access-checking");
    root.classList.add("ooglex-access-preview");
    layoutPreview();
    observeDynamicContent();

    [350, 900, 1800, 3500, 6000, 9000].forEach(function (ms) {
      setTimeout(layoutPreview, ms);
    });
    window.addEventListener("load", function () { setTimeout(layoutPreview, 120); }, { once: true });
    window.addEventListener("resize", function () { scheduleLayout(120); });
  }

  function applyPreview() {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function () { setTimeout(mountPreview, 80); }, { once: true });
    } else {
      setTimeout(mountPreview, 80);
    }
  }

  function unlock() {
    if (observer) { observer.disconnect(); observer = null; }
    if (stopObserveTimer) clearTimeout(stopObserveTimer);
    document.documentElement.classList.remove("ooglex-access-checking", "ooglex-access-preview");
    document.documentElement.removeAttribute("data-ooglex-preview-ratio");
    document.documentElement.removeAttribute("data-ooglex-preview-cutoff");
    document.documentElement.removeAttribute("data-ooglex-preview-total");
    var gate = document.getElementById("ooglex-registration-preview");
    if (gate) gate.remove();
    clearBodyClamp();
  }

  window.OoglexSiteAccess = Object.freeze({
    ready: ready,
    getStoredToken: storedToken,
    isProtectedPath: protectedPath,
    previewRatio: PREVIEW_RATIO
  });

  if (!protectedPath()) {
    resolveReady(true);
    return;
  }

  addStyles();
  document.documentElement.classList.add("ooglex-access-checking");

  (async function () {
    var ok = await verifyToken(storedToken());
    if (ok) unlock();
    else applyPreview();
    resolveReady(ok);
    try {
      document.dispatchEvent(new CustomEvent("ooglex:accessready", { detail: { authenticated: ok, previewRatio: PREVIEW_RATIO } }));
    } catch (_) {}
  })();
})();