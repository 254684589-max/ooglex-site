(function () {
  "use strict";

  var API_BASE = "https://pro-api.ooglex.com";
  var SESSION_KEY = "ooglex.tech-leaders.server-token.v1";
  var token = "";
  var resolveGate;
  var gatePromise = new Promise(function (resolve) { resolveGate = resolve; });
  var resolved = false;

  function finish(value) {
    if (resolved) return;
    resolved = true;
    resolveGate(!!value);
  }

  function readSessionToken() {
    try { return sessionStorage.getItem(SESSION_KEY) || ""; }
    catch (_) { return ""; }
  }

  function rememberToken(value) {
    token = String(value || "");
    try {
      if (token) sessionStorage.setItem(SESSION_KEY, token);
      else sessionStorage.removeItem(SESSION_KEY);
    } catch (_) {}
  }

  function authHeaders(headers) {
    var out = new Headers(headers || {});
    if (token) out.set("Authorization", "Bearer " + token);
    return out;
  }

  async function protectedFetch(input, init) {
    var options = Object.assign({}, init || {});
    options.headers = authHeaders(options.headers);
    var response = await fetch(input, options);
    if (response.status === 401 && String(input).indexOf("/v1/tech-leaders/") >= 0) {
      rememberToken("");
    }
    return response;
  }

  async function validateToken(value) {
    token = String(value || "");
    if (!token) return false;
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
      "#ooglex-tech-gate{visibility:visible!important;position:fixed;inset:0;z-index:2147483647;display:grid;place-items:center;padding:24px;background:var(--bg,#f7f1e9);color:var(--ink,#171717);font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei','Segoe UI',sans-serif}" +
      "#ooglex-tech-gate .gate-card{width:min(430px,100%);padding:30px;border:1px solid var(--line,#ded5cb);border-radius:18px;background:var(--panel,#fffaf4);box-shadow:0 24px 70px rgba(0,0,0,.12)}" +
      "#ooglex-tech-gate .gate-kicker{font:11px/1.2 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;letter-spacing:.16em;color:var(--faint,#8b837b);text-transform:uppercase}" +
      "#ooglex-tech-gate h1{margin:10px 0 7px;font-size:25px;line-height:1.2;letter-spacing:-.02em}" +
      "#ooglex-tech-gate p{margin:0 0 20px;color:var(--dim,#655f59);font-size:13px;line-height:1.65}" +
      "#ooglex-tech-gate .gate-row{display:flex;gap:9px}" +
      "#ooglex-tech-gate input{min-width:0;flex:1;height:44px;border:1px solid var(--line,#ded5cb);border-radius:10px;background:transparent;color:inherit;padding:0 13px;outline:none;font:14px/1 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}" +
      "#ooglex-tech-gate input:focus{border-color:#2a6fa4;box-shadow:0 0 0 3px rgba(42,111,164,.10)}" +
      "#ooglex-tech-gate button{height:44px;min-width:82px;border:0;border-radius:10px;background:#171717;color:#fff;padding:0 18px;font-weight:700;cursor:pointer}" +
      "#ooglex-tech-gate button[disabled]{opacity:.55;cursor:wait}" +
      "#ooglex-tech-gate .gate-error{min-height:18px;margin-top:10px;color:#b42318;font-size:12px}" +
      "#ooglex-tech-gate .gate-back{display:inline-block;margin-top:10px;color:#2a6fa4;font-size:12px;text-decoration:none}";
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
        '<div class="gate-kicker">OOGLEX · PRIVATE COLUMN</div>' +
        '<h1 id="ooglex-tech-gate-title">科技领袖实时动态流</h1>' +
        '<p>该专栏由服务器验证访问密码。密码通过后，本次浏览器会话内保持解锁。</p>' +
        '<form class="gate-row" id="ooglex-tech-gate-form">' +
          '<input id="ooglex-tech-gate-input" type="password" inputmode="numeric" autocomplete="current-password" maxlength="64" placeholder="请输入访问密码" aria-label="访问密码">' +
          '<button id="ooglex-tech-gate-submit" type="submit">进入</button>' +
        '</form>' +
        '<div class="gate-error" id="ooglex-tech-gate-error" aria-live="polite"></div>' +
        '<a class="gate-back" href="/">返回首页</a>' +
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
        var response = await fetch(API_BASE + "/v1/tech-leaders/auth", {
          method: "POST",
          cache: "no-store",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ password: input.value })
        });
        var data = {};
        try { data = await response.json(); } catch (_) {}
        if (!response.ok || !data.token) {
          if (response.status === 429) error.textContent = "尝试次数过多，请稍后再试。";
          else if (response.status === 503) error.textContent = "服务器门禁正在部署，请稍后刷新。";
          else error.textContent = "密码错误，请重试。";
          input.select();
          return;
        }
        rememberToken(data.token);
        unlockUi(root);
      } catch (_) {
        error.textContent = "暂时无法连接服务器门禁，请稍后重试。";
      } finally {
        submit.disabled = false;
        submit.textContent = "进入";
      }
    });

    setTimeout(function () { try { input.focus(); } catch (_) {} }, 0);
  }

  window.OoglexTechLeadersGate = {
    wait: function () { return gatePromise; },
    token: function () { return token; },
    fetch: protectedFetch,
    lock: function () {
      rememberToken("");
      location.reload();
    }
  };

  addStyle();
  document.documentElement.classList.add("ooglex-tech-locked");

  async function startGate() {
    var saved = readSessionToken();
    if (saved && await validateToken(saved)) {
      rememberToken(saved);
      document.documentElement.classList.remove("ooglex-tech-locked");
      finish(true);
      return;
    }
    rememberToken("");
    mountGate();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", startGate, { once: true });
  } else {
    startGate();
  }
})();
