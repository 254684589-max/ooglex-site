(function () {
  "use strict";

  var API_BASE = "https://pro-api.ooglex.com";
  var resolveGate;
  var gatePromise = new Promise(function (resolve) { resolveGate = resolve; });
  var resolved = false;

  function finish(value) {
    if (resolved) return;
    resolved = true;
    resolveGate(!!value);
  }

  async function protectedFetch(input, init) {
    var options = Object.assign({}, init || {});
    options.credentials = "include";
    return fetch(input, options);
  }

  async function validateSession() {
    try {
      var response = await protectedFetch(API_BASE + "/v1/tech-leaders/session", { cache: "no-store" });
      return response.ok;
    } catch (_) {
      return false;
    }
  }

  function addStyle() {
    if (document.getElementById("ooglex-tech-gate-style")) return;
    var style = document.createElement("style");
    style.id = "ooglex-tech-gate-style";
    style.textContent =
      "html.ooglex-tech-locked,html.ooglex-tech-locked body{overflow:hidden!important}" +
      "html.ooglex-tech-locked body>:not(#ooglex-tech-gate){visibility:hidden!important}" +
      // 用 flex 居中并给卡片固定上限宽度：之前用 grid + 百分比宽度，窄屏上卡片会撑出右边界。
      "#ooglex-tech-gate{visibility:visible!important;position:fixed;inset:0;z-index:2147483647;display:flex;align-items:center;justify-content:center;box-sizing:border-box;padding:max(20px,env(safe-area-inset-top)) max(16px,env(safe-area-inset-right)) max(20px,env(safe-area-inset-bottom)) max(16px,env(safe-area-inset-left));overflow-y:auto;background:var(--bg,#f7f1e9);color:var(--ink,#171717);font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei','Segoe UI',sans-serif;-webkit-font-smoothing:antialiased}" +
      "#ooglex-tech-gate *,#ooglex-tech-gate *::before,#ooglex-tech-gate *::after{box-sizing:border-box}" +
      "#ooglex-tech-gate .gate-card{width:100%;max-width:400px;margin:auto;padding:32px 28px 26px;border:1px solid var(--line,#ded5cb);border-radius:20px;background:var(--panel,#fffaf4);box-shadow:0 1px 2px rgba(0,0,0,.04),0 18px 48px rgba(0,0,0,.10);text-align:center}" +
      "#ooglex-tech-gate .gate-mark{position:relative;display:block;width:52px;height:52px;margin:0 auto 18px;border-radius:14px;background:#0b0e13;border:1px solid rgba(255,255,255,.10);box-shadow:0 6px 16px rgba(0,0,0,.16)}" +
      "#ooglex-tech-gate .gate-mark i{position:absolute;width:7px;height:7px;border-radius:50%}" +
      "#ooglex-tech-gate .gate-kicker{font:600 11px/1.2 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;letter-spacing:.18em;color:var(--faint,var(--dim,#8b837b));text-transform:uppercase}" +
      "#ooglex-tech-gate h1{margin:10px 0 8px;font-size:24px;line-height:1.25;font-weight:750;letter-spacing:-.01em}" +
      "#ooglex-tech-gate p{margin:0 auto 22px;max-width:300px;color:var(--dim,#655f59);font-size:14px;line-height:1.65}" +
      "#ooglex-tech-gate form{display:flex;flex-direction:column;gap:10px;margin:0}" +
      // 输入框字号 16px：小于 16px 时手机浏览器会在聚焦时自动放大页面。
      "#ooglex-tech-gate input{display:block;width:100%;height:48px;margin:0;padding:0 14px;border:1px solid var(--line,#ded5cb);border-radius:12px;background:var(--bg,#fff);color:inherit;font:16px/1 -apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei',sans-serif;text-align:center;letter-spacing:.04em;outline:none;-webkit-appearance:none;appearance:none}" +
      "#ooglex-tech-gate input::placeholder{color:var(--faint,var(--dim,#9a928a));letter-spacing:0}" +
      "#ooglex-tech-gate input:focus{border-color:#2a6fa4;box-shadow:0 0 0 3px rgba(42,111,164,.16)}" +
      "#ooglex-tech-gate button{display:block;width:100%;height:48px;margin:0;border:0;border-radius:12px;background:var(--ink,#171717);color:var(--bg,#fff);font:700 16px/1 -apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei',sans-serif;letter-spacing:.08em;cursor:pointer;-webkit-appearance:none;appearance:none}" +
      "#ooglex-tech-gate button:focus-visible{outline:2px solid #2a6fa4;outline-offset:2px}" +
      "#ooglex-tech-gate button[disabled]{opacity:.6;cursor:wait}" +
      "#ooglex-tech-gate .gate-error{min-height:18px;margin-top:8px;color:#b42318;font-size:13px;line-height:1.5}" +
      "#ooglex-tech-gate .gate-back{display:inline-flex;align-items:center;min-height:44px;margin-top:4px;padding:0 8px;color:var(--dim,#655f59);font-size:13px;text-decoration:none}" +
      "#ooglex-tech-gate .gate-back:hover,#ooglex-tech-gate .gate-back:focus-visible{color:var(--ink,#171717);text-decoration:underline}" +
      "@media (max-width:360px){#ooglex-tech-gate .gate-card{padding:26px 20px 20px;border-radius:18px}#ooglex-tech-gate h1{font-size:22px}}" +
      "@media (prefers-reduced-motion:reduce){#ooglex-tech-gate *{transition:none!important;animation:none!important}}";
    document.head.appendChild(style);
  }

  function unlockUi(root) {
    document.documentElement.classList.remove("ooglex-tech-locked");
    if (root) root.remove();
    finish(true);
  }

  function mountGate() {
    if (document.getElementById("ooglex-tech-gate")) return;
    var root = document.createElement("div");
    root.id = "ooglex-tech-gate";
    root.innerHTML =
      '<section class="gate-card" role="dialog" aria-modal="true" aria-labelledby="ooglex-tech-gate-title">' +
        '<span class="gate-mark" aria-hidden="true">' +
          '<i style="left:14px;top:14px;background:#7d5cff"></i><i style="left:30px;top:15px;background:#f04d38"></i>' +
          '<i style="left:31px;top:30px;background:#e4a11b"></i><i style="left:16px;top:31px;background:#4f9fd8"></i>' +
        '</span>' +
        '<div class="gate-kicker">Ooglex · Private Column</div>' +
        '<h1 id="ooglex-tech-gate-title">科技领袖实时动态流</h1>' +
        '<p>该专栏需要访问密码。验证通过后，本次浏览器会话内保持解锁。</p>' +
        '<form id="ooglex-tech-gate-form">' +
          '<input id="ooglex-tech-gate-input" type="password" inputmode="numeric" autocomplete="current-password" maxlength="64" placeholder="请输入访问密码" aria-label="访问密码">' +
          '<button id="ooglex-tech-gate-submit" type="submit">进入</button>' +
        '</form>' +
        '<div class="gate-error" id="ooglex-tech-gate-error" aria-live="polite"></div>' +
        '<a class="gate-back" href="/">← 返回首页</a>' +
      '</section>';
    document.body.appendChild(root);

    var form = document.getElementById("ooglex-tech-gate-form");
    var input = document.getElementById("ooglex-tech-gate-input");
    var submit = document.getElementById("ooglex-tech-gate-submit");
    var error = document.getElementById("ooglex-tech-gate-error");

    form.addEventListener("submit", async function (event) {
      event.preventDefault();
      error.textContent = "";
      submit.disabled = true;
      submit.textContent = "验证中…";
      try {
        // text/plain keeps this request CORS-simple and avoids a browser preflight
        // that can fail on some networks even when the Worker itself is reachable.
        var response = await fetch(API_BASE + "/v1/tech-leaders/auth", {
          method: "POST",
          cache: "no-store",
          credentials: "include",
          headers: { "content-type": "text/plain;charset=UTF-8" },
          body: input.value
        });
        var data = {};
        try { data = await response.json(); } catch (_) {}
        if (!response.ok || !data.ok) {
          if (response.status === 429) error.textContent = "尝试次数过多，请稍后再试。";
          else if (response.status === 401) error.textContent = "密码错误，请重试。";
          else if (response.status === 503) error.textContent = "服务器门禁正在部署，请稍后刷新。";
          else error.textContent = "服务器验证失败，请稍后重试。";
          input.select();
          return;
        }
        if (!(await validateSession())) {
          error.textContent = "密码已通过，但浏览器未保存访问会话，请刷新后重试。";
          return;
        }
        unlockUi(root);
      } catch (_) {
        error.textContent = "当前网络无法连接验证服务器，请检查网络后重试。";
      } finally {
        submit.disabled = false;
        submit.textContent = "进入";
      }
    });

    setTimeout(function () { try { input.focus(); } catch (_) {} }, 0);
  }

  window.OoglexTechLeadersGate = {
    wait: function () { return gatePromise; },
    fetch: protectedFetch,
    lock: function () { location.reload(); }
  };

  addStyle();
  document.documentElement.classList.add("ooglex-tech-locked");

  // 会话校验不依赖页面 DOM，脚本一加载就发出，与页面解析并行；
  // 只有需要显示密码框时才等待 DOM 就绪。
  var sessionCheck = validateSession();

  async function startGate() {
    if (await sessionCheck) {
      document.documentElement.classList.remove("ooglex-tech-locked");
      finish(true);
      return;
    }
    mountGate();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", startGate, { once: true });
  } else {
    startGate();
  }
})();
