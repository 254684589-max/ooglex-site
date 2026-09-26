/* OOGLEX_ACCESS_GATE_V3
   Bloomberg-style registration wall.
   Anonymous visitors can read the first 10% of the natural page height.
   The remaining 90% stays in place behind a continuous dim/blur veil and cannot be interacted with.
   A verified Supabase Auth session removes the wall completely. */
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
      "html.ooglex-access-checking body{overflow:hidden!important}" +
      "#ooglex-registration-preview{position:absolute;left:0;right:0;z-index:2147483646;display:block;pointer-events:auto;color:#f7f7f7;font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei','Segoe UI',sans-serif;background:linear-gradient(to bottom,rgba(8,11,15,.12) 0,rgba(8,11,15,.62) 54px,rgba(8,11,15,.78) 150px,rgba(8,11,15,.82) 100%);-webkit-backdrop-filter:blur(3px) saturate(.72) brightness(.72);backdrop-filter:blur(3px) saturate(.72) brightness(.72)}" +
      "#ooglex-registration-preview .ogx-access-panel{position:sticky;top:clamp(92px,24vh,230px);width:100%;margin:0;background:rgba(20,20,20,.96);border-top:1px solid rgba(255,255,255,.12);border-bottom:1px solid rgba(255,255,255,.12);box-shadow:0 18px 58px rgba(0,0,0,.36);text-align:center}" +
      "#ooglex-registration-preview .ogx-access-inner{width:min(760px,calc(100vw - 32px));margin:0 auto;padding:27px 18px 30px}" +
      "#ooglex-registration-preview .ogx-access-kicker{font:700 11px/1.2 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;letter-spacing:.16em;color:#9ca3af}" +
      "#ooglex-registration-preview h2{margin:10px 0 8px;font-size:clamp(22px,3vw,30px);line-height:1.2;color:#fff}" +
      "#ooglex-registration-preview p{margin:0 auto;max-width:620px;color:#c7cbd1;font-size:14px;line-height:1.65}" +
      "#ooglex-registration-preview .ogx-access-actions{display:flex;gap:11px;justify-content:center;flex-wrap:wrap;margin-top:20px}" +
      "#ooglex-registration-preview a{display:inline-flex;align-items:center;justify-content:center;min-width:164px;height:46px;padding:0 19px;border-radius:7px;text-decoration:none;font-weight:750;font-size:15px}" +
      "#ooglex-registration-preview .ogx-access-primary{background:#fff;color:#111}" +
      "#ooglex-registration-preview .ogx-access-secondary{border:1px solid rgba(255,255,255,.28);color:#fff;background:rgba(255,255,255,.04)}" +
      "#ooglex-registration-preview .ogx-access-note{margin-top:12px;font-size:11px;color:#8d939b}" +
      "@media(max-width:640px){#ooglex-registration-preview .ogx-access-panel{top:18vh}#ooglex-registration-preview .ogx-access-inner{padding:24px 16px 28px}#ooglex-registration-preview .ogx-access-actions{display:grid;grid-template-columns:1fr;max-width:290px;margin:18px auto 0}#ooglex-registration-preview a{width:100%}}";
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
    gate.setAttribute("role", "region");
    gate.setAttribute("aria-label", "注册访问限制");
    gate.innerHTML =
      '<section class="ogx-access-panel">' +
        '<div class="ogx-access-inner">' +
          '<div class="ogx-access-kicker">OOGLEX · 10% PREVIEW</div>' +
          '<h2>继续访问完整内容</h2>' +
          '<p>未注册用户可预览当前板块前 10%。注册并登录后解锁剩余 90% 内容。</p>' +
          '<div class="ogx-access-actions">' +
            '<a class="ogx-access-primary" href="' + accountUrl() + '#signup">注册后完整访问</a>' +
            '<a class="ogx-access-secondary" href="' + accountUrl() + '">已有账户 · 登录</a>' +
          '</div>' +
          '<div class="ogx-access-note">FREE · 10% PREVIEW</div>' +
        '</div>' +
      '</section>';
    document.body.appendChild(gate);
    return gate;
  }

  function clearCheckingClamp() {
    document.documentElement.classList.remove("ooglex-access-checking");
    if (document.body) document.body.style.removeProperty("overflow");
  }

  function naturalHeight(gate) {
    var body = document.body;
    var root = document.documentElement;
    if (!body) return Math.max(root.scrollHeight || 0, window.innerHeight || 0);

    var oldDisplay = gate ? gate.style.display : "";
    if (gate) gate.style.display = "none";

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
    var remaining = Math.max(total - cutoff, window.innerHeight || 0, 560);

    gate.style.top = cutoff + "px";
    gate.style.height = remaining + "px";
    gate.style.minHeight = remaining + "px";
    gate.style.display = "block";

    root.classList.add("ooglex-access-preview");
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
    if (typeof MutationObserver === "undefined" || observer || !document.body) return;
    observer = new MutationObserver(function (records) {
      for (var i = 0; i < records.length; i++) {
        var target = records[i].target;
        if (target && (target.id === "ooglex-registration-preview" ||
            (target.closest && target.closest("#ooglex-registration-preview")))) continue;
        scheduleLayout(180);
        break;
      }
    });
    observer.observe(document.body, { subtree: true, childList: true });
    stopObserveTimer = setTimeout(function () {
      if (observer) { observer.disconnect(); observer = null; }
    }, 15000);
  }

  function mountPreview() {
    addStyles();
    clearCheckingClamp();
    layoutPreview();
    observeDynamicContent();

    [300, 800, 1600, 3000, 5000, 8000, 12000].forEach(function (ms) {
      setTimeout(layoutPreview, ms);
    });
    window.addEventListener("load", function () { setTimeout(layoutPreview, 100); }, { once: true });
    window.addEventListener("resize", function () { scheduleLayout(100); });
  }

  function applyPreview() {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function () { setTimeout(mountPreview, 60); }, { once: true });
    } else {
      setTimeout(mountPreview, 60);
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
    if (document.body) document.body.style.removeProperty("overflow");
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
      document.dispatchEvent(new CustomEvent("ooglex:accessready", {
        detail: { authenticated: ok, previewRatio: PREVIEW_RATIO, style: "bloomberg" }
      }));
    } catch (_) {}
  })();
})();