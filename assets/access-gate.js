/* OOGLEX_ACCESS_GATE_V15
   Generic 10% preview hard-stop for non-password /apps/ pages.
   /games/ is intentionally fully public.
   Mobile-safe rule: clip the document to the visual viewport, keep the preview above,
   and anchor the dark access wall to the real bottom edge. */
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
  var PRO_API = "https://pro-api.ooglex.com";
  var resolveReady;
  var ready = new Promise(function (resolve) { resolveReady = resolve; });
  var original = null;

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
    return /^\/apps(\/|$)/.test(PATH) &&
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

  async function timedFetch(url, init) {
    var ctrl = typeof AbortController === "function" ? new AbortController() : null;
    var timer = ctrl ? setTimeout(function () { try { ctrl.abort(); } catch (_) {} }, VERIFY_TIMEOUT_MS) : null;
    try {
      return await fetch(url, Object.assign({ cache: "no-store", signal: ctrl ? ctrl.signal : undefined }, init));
    } finally {
      if (timer) clearTimeout(timer);
    }
  }

  // 经本站会员接口校验（大陆网络可达）。「最新消息」只看是否登录，正好用来判断会话。
  async function verifyViaProApi(token) {
    try {
      var res = await timedFetch(PRO_API + "/v1/access?product=whats_latest", {
        headers: { Accept: "application/json", Authorization: "Bearer " + token }
      });
      if (!res.ok) return "unreachable";
      var body = await res.json();
      return body && body.authenticated === true ? "ok" : "denied";
    } catch (_) {
      return "unreachable";
    }
  }

  async function verifyViaSupabase(token) {
    try {
      var res = await timedFetch(SUPABASE_URL + "/auth/v1/user", {
        headers: { apikey: SUPABASE_PUBLISHABLE_KEY, Authorization: "Bearer " + token }
      });
      if (res.ok) return "ok";
      return res.status === 401 || res.status === 403 ? "denied" : "unreachable";
    } catch (_) {
      return "unreachable";
    }
  }

  // 返回 "ok" / "denied" / "unreachable"。两条路同时问，谁先给出明确答案就用谁；
  // 只有两条都连不上才算 unreachable。
  function verifyToken(token) {
    if (!token) return Promise.resolve("denied");
    return new Promise(function (resolve) {
      var pending = 2;
      function settle(result) {
        if (result !== "unreachable") { resolve(result); return; }
        pending -= 1;
        if (!pending) resolve("unreachable");
      }
      verifyViaProApi(token).then(settle);
      verifyViaSupabase(token).then(settle);
    });
  }

  // 先续期再校验：access_token 约 1 小时过期，账户页之外没有别的地方会续期，
  // 不续期的话登录一小时后打开任意应用页都会被当成访客。
  async function freshToken() {
    var auth = window.OoglexAuthSession;
    if (auth) {
      try { return await auth.getAccessToken(); } catch (_) {}
    }
    return storedToken();
  }

  async function checkAccess() {
    var token = await freshToken();
    if (!token) return false;
    var result = await verifyToken(token);
    if (result === "ok") return true;
    if (result === "denied") return false;
    // Supabase 暂时连不上：本地会话 token 仍在有效期内就按已登录处理，
    // 不因网络抖动把已登录用户退回 10% 预览；token 已过期则仍按预览。
    var auth = window.OoglexAuthSession;
    var session = auth ? auth.getSession() : null;
    return !!(session && session.access_token === token &&
              auth.expiresAt(session) > Date.now() / 1000);
  }

  function addStyles() {
    if (document.getElementById("ooglex-registration-preview-style")) return;
    var style = document.createElement("style");
    style.id = "ooglex-registration-preview-style";
    style.textContent =
      "html.ooglex-access-checking,html.ooglex-access-preview{height:100%!important;overflow:hidden!important;overscroll-behavior:none!important}" +
      "html.ooglex-access-checking body,html.ooglex-access-preview body{position:fixed!important;inset:0!important;width:100%!important;height:100dvh!important;min-height:0!important;overflow:hidden!important;overscroll-behavior:none!important;touch-action:none}" +
      "#ooglex-registration-preview-fade{position:fixed;left:0;right:0;bottom:clamp(290px,34dvh,390px);z-index:2147483645;height:110px;pointer-events:none;background:linear-gradient(to bottom,rgba(12,13,20,0),rgba(23,23,23,.97))}" +
      "#ooglex-registration-preview{position:fixed;left:0;right:0;bottom:0;z-index:2147483646;box-sizing:border-box;width:100%;height:clamp(290px,34dvh,390px);min-height:0!important;max-height:390px;overflow:hidden;padding:24px 20px 22px;text-align:center;background:#171717;color:#f5f5f5;border-top:1px solid rgba(255,255,255,.10);box-shadow:0 -18px 50px rgba(0,0,0,.30);font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei','Segoe UI',sans-serif}" +
      "#ooglex-registration-preview .ogx-access-kicker{font:700 10px/1.2 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;letter-spacing:.16em;color:#9aa1aa;margin-bottom:10px}" +
      "#ooglex-registration-preview h2{margin:1px 0 8px;font-size:27px;line-height:1.3;color:#f5f5f5;font-weight:760;letter-spacing:-.3px}" +
      "#ooglex-registration-preview p{margin:0 auto 17px;max-width:720px;color:#c8c8c8;font-size:14px;line-height:1.6}" +
      "#ooglex-registration-preview a{display:inline-flex;align-items:center;justify-content:center;min-width:270px;height:44px;padding:0 22px;border-radius:4px;background:#fff;color:#111;text-decoration:none;font-size:15px;font-weight:720;box-shadow:none;touch-action:manipulation}" +
      "#ooglex-registration-preview .ogx-access-note{font-size:11px;color:#8f8f8f;margin-top:14px}" +
      "#ooglex-registration-preview-badge{position:fixed;right:14px;bottom:14px;z-index:2147483647;padding:7px 11px;border-radius:999px;font:600 11px/1.2 -apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif;letter-spacing:.4px;color:#dfe7ec;background:rgba(10,14,20,.88);border:1px solid rgba(255,255,255,.14);backdrop-filter:blur(8px);box-shadow:0 8px 24px rgba(0,0,0,.28)}" +
      "@supports not (height:100dvh){html.ooglex-access-checking body,html.ooglex-access-preview body{height:100vh!important}#ooglex-registration-preview{height:34vh}#ooglex-registration-preview-fade{bottom:34vh}}" +
      "@media(max-width:640px){#ooglex-registration-preview{padding:22px 16px 20px}#ooglex-registration-preview h2{font-size:25px}#ooglex-registration-preview p{font-size:13px}#ooglex-registration-preview a{min-width:min(270px,calc(100vw - 48px));width:min(270px,calc(100vw - 48px))}}";
    document.head.appendChild(style);
  }

  function accountUrl() {
    return "/account/?next=" + encodeURIComponent(PATH + window.location.search + window.location.hash);
  }

  function ensureGate() {
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
      document.body.appendChild(gate);
    }

    var fade = document.getElementById("ooglex-registration-preview-fade");
    if (!fade) {
      fade = document.createElement("div");
      fade.id = "ooglex-registration-preview-fade";
      fade.setAttribute("aria-hidden", "true");
      document.body.appendChild(fade);
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

  function freezeDocument() {
    var html = document.documentElement;
    var body = document.body;
    if (!body) return;

    if (!original) {
      original = {
        htmlStyle: html.getAttribute("style"),
        bodyStyle: body.getAttribute("style")
      };
    }

    try { if ("scrollRestoration" in history) history.scrollRestoration = "manual"; } catch (_) {}
    try { window.scrollTo({ top: 0, left: 0, behavior: "auto" }); } catch (_) { window.scrollTo(0, 0); }

    html.classList.remove("ooglex-access-checking");
    html.classList.add("ooglex-access-preview");
    html.setAttribute("data-ooglex-preview-ratio", "10");
    html.setAttribute("data-ooglex-preview-mode", "bottom-hard-stop");
  }

  function mountPreview() {
    addStyles();
    ensureGate();
    freezeDocument();
  }

  function applyPreview() {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function () { setTimeout(mountPreview, 30); }, { once: true });
    } else {
      setTimeout(mountPreview, 30);
    }
  }

  function unlock() {
    var html = document.documentElement;
    var body = document.body;

    html.classList.remove("ooglex-access-checking", "ooglex-access-preview");
    html.removeAttribute("data-ooglex-preview-ratio");
    html.removeAttribute("data-ooglex-preview-mode");

    ["ooglex-registration-preview","ooglex-registration-preview-fade","ooglex-registration-preview-badge"].forEach(function (id) {
      var el = document.getElementById(id);
      if (el) el.remove();
    });

    if (original) {
      if (original.htmlStyle == null) html.removeAttribute("style"); else html.setAttribute("style", original.htmlStyle);
      if (body) {
        if (original.bodyStyle == null) body.removeAttribute("style"); else body.setAttribute("style", original.bodyStyle);
      }
    }
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

  function announce(ok) {
    try {
      document.dispatchEvent(new CustomEvent("ooglex:accessready", {
        detail: { authenticated: ok, previewRatio: PREVIEW_RATIO, style: "bottom-hard-stop-v12" }
      }));
    } catch (_) {}
  }

  (async function () {
    var ok = await checkAccess();
    if (ok) unlock();
    else applyPreview();
    resolveReady(ok);
    announce(ok);
  })();

  // 在另一个标签页登录后，本页不用刷新也能解除预览。
  window.addEventListener("storage", function (ev) {
    if (ev.key !== AUTH_KEY || !ev.newValue) return;
    if (!document.documentElement.classList.contains("ooglex-access-preview")) return;
    checkAccess().then(function (ok) {
      if (!ok) return;
      unlock();
      announce(true);
    });
  });
})();