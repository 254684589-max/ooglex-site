(function () {
  "use strict";

  var PROJECT_REF = "nwthqkpkvbtilafqpjlf";
  var STORAGE_KEY = "sb-" + PROJECT_REF + "-auth-token";

  function session() {
    try {
      var raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      var value = JSON.parse(raw);
      return value && value.access_token && value.user ? value : null;
    } catch (_) {
      return null;
    }
  }

  function registered() {
    return !!session();
  }

  function accountUrl() {
    return "/account/?next=" + encodeURIComponent(location.pathname + location.search + location.hash);
  }

  async function protectedFetch(input, init) {
    var options = Object.assign({}, init || {});
    var headers = new Headers(options.headers || {});
    var current = session();
    if (current && current.access_token) {
      headers.set("Authorization", "Bearer " + current.access_token);
    }
    options.headers = headers;
    options.credentials = "include";
    return fetch(input, options);
  }

  function mountPreviewNotice() {
    if (registered() || document.getElementById("ooglex-tech-registration-preview")) return;

    var style = document.createElement("style");
    style.textContent =
      "#ooglex-tech-registration-preview{position:fixed;right:14px;bottom:14px;z-index:10000;display:flex;align-items:center;gap:10px;max-width:min(520px,calc(100vw - 28px));padding:10px 12px;border:1px solid var(--line,rgba(255,255,255,.12));border-radius:12px;background:var(--panel,#10141b);color:var(--dim,#98a2b3);box-shadow:0 12px 34px rgba(0,0,0,.24);font:12px/1.45 -apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei','Segoe UI',sans-serif}" +
      "#ooglex-tech-registration-preview b{color:var(--ink,#eef2f7)}" +
      "#ooglex-tech-registration-preview a{flex:0 0 auto;display:inline-flex;align-items:center;justify-content:center;min-height:34px;padding:0 12px;border-radius:8px;background:var(--ink,#eef2f7);color:var(--bg,#0b0e13)!important;text-decoration:none!important;font-weight:750}" +
      "@media(max-width:560px){#ooglex-tech-registration-preview{left:10px;right:10px;bottom:10px;align-items:flex-start;flex-wrap:wrap}#ooglex-tech-registration-preview a{width:100%}}";
    document.head.appendChild(style);

    var notice = document.createElement("div");
    notice.id = "ooglex-tech-registration-preview";
    notice.setAttribute("data-ooglex-preview-ratio", "0.10");
    notice.innerHTML =
      "<span><b>10% 公开预览</b> · 注册并登录后可查看完整科技领袖目录与动态。</span>" +
      '<a href="' + accountUrl().replace(/&/g, "&amp;").replace(/"/g, "&quot;") + '">注册 / 登录</a>';
    document.body.appendChild(notice);
  }

  window.OoglexTechLeadersGate = Object.freeze({
    wait: function () { return Promise.resolve(true); },
    fetch: protectedFetch,
    registered: registered,
    getSession: session,
    lock: function () { location.reload(); }
  });

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mountPreviewNotice, { once: true });
  } else {
    mountPreviewNotice();
  }
})();