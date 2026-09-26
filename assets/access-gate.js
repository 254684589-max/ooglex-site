/* OOGLEX_ACCESS_GATE_V9
   Unified 10% preview for non-password /apps/ and /games/ pages.
   Standard: visible content -> 110px fade -> 218px in-flow dark access block.
   The content root itself is clipped, so nothing can reappear underneath the wall. */
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
  var WALL_HEIGHT = 218;
  var FADE_HEIGHT = 110;
  var resolveReady;
  var ready = new Promise(function (resolve) { resolveReady = resolve; });
  var previewRoot = null;
  var rootState = null;
  var maxNaturalHeight = 0;
  var refreshTimer = 0;
  var observer = null;
  var observerTimer = 0;

  function nativePasswordPage() {
    if (PATH === "/apps/tech-leaders/" || PATH === "/apps/tech-leaders" ||
        PATH === "/apps/tv/" || PATH === "/apps/tv") return true;
    try { return document.documentElement.hasAttribute("data-ooglex-password-gate"); }
    catch (_) { return false; }
  }

  function nativePreviewPage() {
    if (PATH.indexOf("/apps/whats-latest/") === 0 ||
        PATH.indexOf("/apps/supply-chain/") === 0 ||
        PATH.indexOf("/apps/macro-radar/") === 0 ||
        PATH.indexOf("/apps/finance-column/") === 0 ||
        PATH.indexOf("/apps/billionaires/") === 0) return true;
    try { return document.documentElement.hasAttribute("data-ooglex-native-preview"); }
    catch (_) { return false; }
  }

  function protectedPath() {
    return /^\/(apps|games)(\/|$)/.test(PATH) &&
           !nativePasswordPage() &&
           !nativePreviewPage();
  }

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
      "html.ooglex-access-preview body>#ooglex-registration-preview~*:not(script):not(style):not(link):not(template){display:none!important}" +
      "#ooglex-registration-preview-fade{position:absolute;left:0;right:0;bottom:0;z-index:2147483645;height:110px;pointer-events:none;background:linear-gradient(to bottom,rgba(12,13,20,0),rgba(23,23,23,.96))}" +
      "#ooglex-registration-preview{position:relative;z-index:2147483646;box-sizing:border-box;width:100%;min-height:max(218px,32vh);padding:24px 20px 22px;text-align:center;background:#171717;color:#f5f5f5;border-top:1px solid rgba(255,255,255,.10);box-shadow:0 -18px 50px rgba(0,0,0,.30);font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei','Segoe UI',sans-serif}" +
      "#ooglex-registration-preview .ogx-access-kicker{font:700 10px/1.2 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;letter-spacing:.16em;color:#9aa1aa;margin-bottom:10px}" +
      "#ooglex-registration-preview h2{margin:1px 0 8px;font-size:27px;line-height:1.3;color:#f5f5f5;font-weight:760;letter-spacing:-.3px}" +
      "#ooglex-registration-preview p{margin:0 auto 17px;max-width:720px;color:#c8c8c8;font-size:14px;line-height:1.6}" +
      "#ooglex-registration-preview a{display:inline-flex;align-items:center;justify-content:center;min-width:270px;height:44px;padding:0 22px;border-radius:4px;background:#fff;color:#111;text-decoration:none;font-size:15px;font-weight:720;box-shadow:none}" +
      "#ooglex-registration-preview .ogx-access-note{font-size:11px;color:#8f8f8f;margin-top:14px}" +
      "#ooglex-registration-preview-badge{position:fixed;right:14px;bottom:14px;z-index:2147483647;padding:7px 11px;border-radius:999px;font:600 11px/1.2 -apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif;letter-spacing:.4px;color:#dfe7ec;background:rgba(10,14,20,.88);border:1px solid rgba(255,255,255,.14);backdrop-filter:blur(8px);box-shadow:0 8px 24px rgba(0,0,0,.28)}" +
      "@media(max-width:640px){#ooglex-registration-preview{padding:24px 16px 22px}#ooglex-registration-preview h2{font-size:25px}#ooglex-registration-preview p{font-size:13px}#ooglex-registration-preview a{min-width:min(270px,calc(100vw - 48px));width:min(270px,calc(100vw - 48px))}}";
    document.head.appendChild(style);
  }

  function accountUrl() {
    return "/account/?next=" + encodeURIComponent(PATH + window.location.search + window.location.hash);
  }

  function findPreviewRoot() {
    var selectors = [
      "body > .wrap", "body > .page", "body > .shell", "body > main",
      "body > #app", "body > .app", "body > #root", "body > .container"
    ];
    for (var i = 0; i < selectors.length; i++) {
      var el = document.querySelector(selectors[i]);
      if (el && el.offsetHeight > 0) return el;
    }
    return null;
  }

  function saveRootState(root) {
    if (!root || rootState) return;
    rootState = {
      maxHeight: root.style.getPropertyValue("max-height"),
      height: root.style.getPropertyValue("height"),
      overflow: root.style.getPropertyValue("overflow"),
      position: root.style.getPropertyValue("position")
    };
  }

  function restoreRootState() {
    if (!previewRoot || !rootState) return;
    var root = previewRoot;
    if (rootState.maxHeight) root.style.setProperty("max-height", rootState.maxHeight); else root.style.removeProperty("max-height");
    if (rootState.height) root.style.setProperty("height", rootState.height); else root.style.removeProperty("height");
    if (rootState.overflow) root.style.setProperty("overflow", rootState.overflow); else root.style.removeProperty("overflow");
    if (rootState.position) root.style.setProperty("position", rootState.position); else root.style.removeProperty("position");
  }

  function ensureGate(root) {
    var gate = document.getElementById("ooglex-registration-preview");
    if (!gate) {
      gate = document.createElement("section");
      gate.id = "ooglex-registration-preview";
      gate.setAttribute("role", "region");
      gate.setAttribute("aria-label", "公开预览限制");
      gate.innerHTML =
        '<div class="ogx-access-kicker">OOGLEX · 10% PREVIEW</div>' +
        '<h2>继续查看完整数据</h2>' +
        '<p>当前展示原版页面预览。登录 / 注册后可继续查看完整内容。</p>' +
        '<a href="' + accountUrl() + '">登录 / 注册</a>' +
        '<div class="ogx-access-note">完整内容不会发送给未登录浏览器；页面下方仅保留受限预览。</div>';
      if (root && root.parentNode) root.parentNode.insertBefore(gate, root.nextSibling);
      else document.body.appendChild(gate);
    }

    var fade = document.getElementById("ooglex-registration-preview-fade");
    if (!fade) {
      fade = document.createElement("div");
      fade.id = "ooglex-registration-preview-fade";
      fade.setAttribute("aria-hidden", "true");
      if (root) root.appendChild(fade);
      else document.body.appendChild(fade);
    }

    var badge = document.getElementById("ooglex-registration-preview-badge");
    if (!badge) {
      badge = document.createElement("div");
      badge.id = "ooglex-registration-preview-badge";
      badge.textContent = "FREE · 10% PREVIEW";
      document.body.appendChild(badge);
    }
    return { gate: gate, fade: fade, badge: badge };
  }

  function naturalHeight(root, parts) {
    if (!root) return Math.max(document.body.scrollHeight || 0, document.documentElement.scrollHeight || 0, window.innerHeight || 0);

    var gateDisplay = parts && parts.gate ? parts.gate.style.display : "";
    var fadeDisplay = parts && parts.fade ? parts.fade.style.display : "";
    var badgeDisplay = parts && parts.badge ? parts.badge.style.display : "";
    if (parts && parts.gate) parts.gate.style.display = "none";
    if (parts && parts.fade) parts.fade.style.display = "none";
    if (parts && parts.badge) parts.badge.style.display = "none";

    restoreRootState();
    var h = Math.max(root.scrollHeight || 0, root.offsetHeight || 0, root.clientHeight || 0);

    if (parts && parts.gate) parts.gate.style.display = gateDisplay;
    if (parts && parts.fade) parts.fade.style.display = fadeDisplay;
    if (parts && parts.badge) parts.badge.style.display = badgeDisplay;
    return h;
  }

  function layoutPreview() {
    if (!document.body) return;
    var root = previewRoot || findPreviewRoot();

    // Full-screen runtimes often have no normal content wrapper. For those, use a
    // viewport-height preview rather than exposing the interactive canvas.
    if (!root) {
      var fallback = ensureGate(null);
      var cutoff = Math.max(1, Math.floor((window.innerHeight || 720) * PREVIEW_RATIO));
      fallback.fade.style.position = "fixed";
      fallback.fade.style.top = Math.max(0, cutoff - FADE_HEIGHT) + "px";
      fallback.fade.style.bottom = "auto";
      fallback.fade.style.display = "block";
      fallback.gate.style.position = "fixed";
      fallback.gate.style.left = "0";
      fallback.gate.style.right = "0";
      fallback.gate.style.top = cutoff + "px";
      fallback.gate.style.display = "block";
      fallback.badge.style.display = "block";
      document.documentElement.classList.remove("ooglex-access-checking");
      document.documentElement.classList.add("ooglex-access-preview");
      document.body.style.setProperty("overflow", "hidden", "important");
      return;
    }

    previewRoot = root;
    saveRootState(root);
    var parts = ensureGate(root);
    var measured = naturalHeight(root, parts);
    if (measured > maxNaturalHeight) maxNaturalHeight = measured;
    var total = Math.max(maxNaturalHeight, measured, 1);
    var cutoff = Math.max(1, Math.floor(total * PREVIEW_RATIO));

    var computed = window.getComputedStyle(root);
    if (!computed.position || computed.position === "static") {
      root.style.setProperty("position", "relative", "important");
    }
    root.style.setProperty("max-height", cutoff + "px", "important");
    root.style.setProperty("height", cutoff + "px", "important");
    root.style.setProperty("overflow", "hidden", "important");

    parts.fade.style.position = "absolute";
    parts.fade.style.top = "auto";
    parts.fade.style.bottom = "0";
    parts.fade.style.display = "block";
    parts.gate.style.position = "relative";
    parts.gate.style.left = "auto";
    parts.gate.style.right = "auto";
    parts.gate.style.top = "auto";
    parts.gate.style.display = "block";
    parts.badge.style.display = "block";

    var html = document.documentElement;
    html.classList.remove("ooglex-access-checking");
    html.classList.add("ooglex-access-preview");
    html.setAttribute("data-ooglex-preview-ratio", "10");
    html.setAttribute("data-ooglex-preview-cutoff", String(cutoff));
    html.setAttribute("data-ooglex-preview-total", String(total));
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
        if (target && target.closest &&
            (target.closest("#ooglex-registration-preview") ||
             target.closest("#ooglex-registration-preview-fade") ||
             target.closest("#ooglex-registration-preview-badge"))) continue;
        scheduleLayout(180);
        break;
      }
    });
    observer.observe(document.body, { subtree: true, childList: true });
    observerTimer = setTimeout(function () {
      if (observer) { observer.disconnect(); observer = null; }
    }, 15000);
  }

  function mountPreview() {
    addStyles();
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
    if (observerTimer) clearTimeout(observerTimer);
    document.documentElement.classList.remove("ooglex-access-checking", "ooglex-access-preview");
    document.documentElement.removeAttribute("data-ooglex-preview-ratio");
    document.documentElement.removeAttribute("data-ooglex-preview-cutoff");
    document.documentElement.removeAttribute("data-ooglex-preview-total");
    ["ooglex-registration-preview","ooglex-registration-preview-fade","ooglex-registration-preview-badge"].forEach(function (id) {
      var el = document.getElementById(id);
      if (el) el.remove();
    });
    restoreRootState();
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
        detail: { authenticated: ok, previewRatio: PREVIEW_RATIO, style: "supply-chain-block-v4" }
      }));
    } catch (_) {}
  })();
})();