(function () {
  "use strict";

  var PROJECT_REF = "nwthqkpkvbtilafqpjlf";
  var STORAGE_KEY = "sb-" + PROJECT_REF + "-auth-token";
  var PREVIEW_RATIO = 0.10;
  var mounted = false;

  function readSession() {
    try {
      var raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      var session = JSON.parse(raw);
      if (!session || !session.access_token || !session.user) return null;
      var expiresAt = Number(session.expires_at || 0);
      if (expiresAt && expiresAt * 1000 <= Date.now() - 30000) return null;
      return session;
    } catch (_) {
      return null;
    }
  }

  function registered() {
    return !!readSession();
  }

  function nextUrl() {
    return location.pathname + location.search + location.hash;
  }

  function accountUrl() {
    return "/account/?next=" + encodeURIComponent(nextUrl());
  }

  function addStyle() {
    if (document.getElementById("ooglex-registration-preview-style")) return;
    var style = document.createElement("style");
    style.id = "ooglex-registration-preview-style";
    style.textContent =
      "html.ooglex-registration-preview-pending body{visibility:hidden!important}" +
      "body[data-ooglex-registration-preview='true']{position:relative!important}" +
      "#ooglex-registration-preview-fade{position:absolute;left:0;right:0;z-index:2147483000;pointer-events:none;height:120px;background:linear-gradient(to bottom,rgba(11,14,19,0),var(--bg,#0b0e13) 88%)}" +
      "#ooglex-registration-preview-wall{position:absolute;left:0;right:0;z-index:2147483001;box-sizing:border-box;display:flex;align-items:flex-start;justify-content:center;padding:28px 20px 44px;background:var(--bg,#0b0e13);color:var(--ink,#eef2f7);border-top:1px solid var(--line,rgba(255,255,255,.10));font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei','Segoe UI',sans-serif}" +
      "#ooglex-registration-preview-wall .ogx-reg-card{box-sizing:border-box;width:min(680px,100%);padding:28px 24px;text-align:center;border:1px solid var(--line,rgba(255,255,255,.12));border-radius:16px;background:var(--panel,#10141b);box-shadow:0 20px 60px rgba(0,0,0,.18)}" +
      "#ooglex-registration-preview-wall .ogx-reg-kicker{font:700 10px/1.2 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;letter-spacing:.16em;color:var(--faint,#667080);text-transform:uppercase}" +
      "#ooglex-registration-preview-wall h2{margin:10px 0 8px;font-size:25px;line-height:1.25;letter-spacing:-.02em;color:var(--ink,#eef2f7)}" +
      "#ooglex-registration-preview-wall p{margin:0 auto 18px;max-width:560px;font-size:13px;line-height:1.75;color:var(--dim,#98a2b3)}" +
      "#ooglex-registration-preview-wall a{display:inline-flex;align-items:center;justify-content:center;min-width:220px;min-height:44px;padding:0 20px;border-radius:10px;background:var(--ink,#eef2f7);color:var(--bg,#0b0e13)!important;text-decoration:none!important;font-size:14px;font-weight:760}" +
      "#ooglex-registration-preview-wall small{display:block;margin-top:12px;color:var(--faint,#667080);font-size:11px;line-height:1.55}" +
      "@media(max-width:640px){#ooglex-registration-preview-fade{height:86px}#ooglex-registration-preview-wall{padding:18px 14px 32px}#ooglex-registration-preview-wall .ogx-reg-card{padding:22px 17px}#ooglex-registration-preview-wall h2{font-size:22px}}";
    document.head.appendChild(style);
  }

  function mountPreview() {
    if (mounted || registered() || !document.body) return;
    mounted = true;

    var doc = document.documentElement;
    var body = document.body;
    var fullHeight = Math.max(
      body.scrollHeight || 0,
      body.offsetHeight || 0,
      doc.scrollHeight || 0,
      doc.offsetHeight || 0
    );
    var viewport = Math.max(window.innerHeight || 0, doc.clientHeight || 0, 640);
    var ratioCutoff = Math.ceil(fullHeight * PREVIEW_RATIO);
    var previewCutoff = Math.min(fullHeight, Math.max(Math.ceil(viewport * 1.05), ratioCutoff));
    if (!Number.isFinite(previewCutoff) || previewCutoff < 1) previewCutoff = viewport;

    var fadeHeight = window.matchMedia && window.matchMedia("(max-width: 640px)").matches ? 86 : 120;
    var wallHeight = window.matchMedia && window.matchMedia("(max-width: 640px)").matches ? 250 : 270;
    var fadeTop = Math.max(0, previewCutoff - fadeHeight);

    body.setAttribute("data-ooglex-registration-preview", "true");
    body.setAttribute("data-ooglex-preview-ratio", String(PREVIEW_RATIO));
    body.style.height = (previewCutoff + wallHeight) + "px";
    body.style.maxHeight = (previewCutoff + wallHeight) + "px";
    body.style.overflow = "hidden";

    var fade = document.createElement("div");
    fade.id = "ooglex-registration-preview-fade";
    fade.setAttribute("aria-hidden", "true");
    fade.style.top = fadeTop + "px";

    var wall = document.createElement("section");
    wall.id = "ooglex-registration-preview-wall";
    wall.setAttribute("data-ooglex-preview-hard-stop", "true");
    wall.style.top = previewCutoff + "px";
    wall.innerHTML =
      '<div class="ogx-reg-card">' +
        '<div class="ogx-reg-kicker">OOGLEX · 10% PUBLIC PREVIEW</div>' +
        '<h2>注册后查看完整内容</h2>' +
        '<p>当前公开页面仅开放约 10% 内容预览。完成免费注册并登录后，即可继续访问该板块完整内容。</p>' +
        '<a href="' + accountUrl().replace(/&/g, "&amp;").replace(/"/g, "&quot;") + '">注册 / 登录</a>' +
        '<small>已注册用户登录后会自动返回当前页面。</small>' +
      '</div>';

    body.appendChild(fade);
    body.appendChild(wall);
    doc.classList.remove("ooglex-registration-preview-pending");
    try {
      window.dispatchEvent(new CustomEvent("ooglex:registration-preview", {
        detail: { ratio: PREVIEW_RATIO, cutoff: previewCutoff, fullHeight: fullHeight }
      }));
    } catch (_) {}
  }

  window.OoglexSiteAccess = Object.freeze({
    previewRatio: PREVIEW_RATIO,
    getSession: readSession,
    registered: registered,
    accountUrl: accountUrl
  });

  if (registered()) return;
  addStyle();
  document.documentElement.classList.add("ooglex-registration-preview-pending");

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      requestAnimationFrame(function () {
        requestAnimationFrame(mountPreview);
      });
    }, { once: true });
  } else {
    requestAnimationFrame(function () {
      requestAnimationFrame(mountPreview);
    });
  }
})();