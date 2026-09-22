(function () {
  "use strict";

  var SESSION_KEY = "ooglex.tech-leaders.access.JB2e";
  var SALT_B64 = "RA0HH2UArl2Dc3wjsz7M3A==";
  var HASH_B64 = "JB2e+zsOwsmJskntOW8Y42DKqA5IfXxbVE3oZVOzlSE=";
  var ITERATIONS = 250000;

  var resolveGate;
  var gatePromise = new Promise(function (resolve) { resolveGate = resolve; });
  var resolved = false;

  function finish(value) {
    if (resolved) return;
    resolved = true;
    resolveGate(!!value);
  }

  function sessionGranted() {
    try { return sessionStorage.getItem(SESSION_KEY) === "1"; }
    catch (_) { return false; }
  }

  function rememberSession() {
    try { sessionStorage.setItem(SESSION_KEY, "1"); } catch (_) {}
  }

  function fromBase64(value) {
    var raw = atob(value);
    var out = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  }

  function equalBytes(a, b) {
    if (!a || !b || a.length !== b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
    return diff === 0;
  }

  async function verifyPassword(value) {
    if (!window.crypto || !window.crypto.subtle || !window.TextEncoder) return false;
    var material = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(String(value || "")),
      "PBKDF2",
      false,
      ["deriveBits"]
    );
    var bits = await crypto.subtle.deriveBits({
      name: "PBKDF2",
      salt: fromBase64(SALT_B64),
      iterations: ITERATIONS,
      hash: "SHA-256"
    }, material, 256);
    return equalBytes(new Uint8Array(bits), fromBase64(HASH_B64));
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

  function mountGate() {
    if (document.getElementById("ooglex-tech-gate")) return;
    var root = document.createElement("div");
    root.id = "ooglex-tech-gate";
    root.innerHTML =
      '<section class="gate-card" role="dialog" aria-modal="true" aria-labelledby="ooglex-tech-gate-title">' +
        '<div class="gate-kicker">OOGLEX · PRIVATE COLUMN</div>' +
        '<h1 id="ooglex-tech-gate-title">科技领袖实时动态流</h1>' +
        '<p>该专栏已设置访问密码。请输入密码后继续。</p>' +
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
        var ok = await verifyPassword(input.value);
        if (!ok) {
          error.textContent = "密码错误，请重试。";
          input.select();
          return;
        }
        rememberSession();
        document.documentElement.classList.remove("ooglex-tech-locked");
        root.remove();
        finish(true);
      } catch (_) {
        error.textContent = "当前浏览器无法完成密码验证。";
      } finally {
        submit.disabled = false;
        submit.textContent = "进入";
      }
    });

    setTimeout(function () { try { input.focus(); } catch (_) {} }, 0);
  }

  window.OoglexTechLeadersGate = {
    wait: function () { return gatePromise; },
    lock: function () {
      try { sessionStorage.removeItem(SESSION_KEY); } catch (_) {}
      location.reload();
    }
  };

  addStyle();

  if (sessionGranted()) {
    finish(true);
    return;
  }

  document.documentElement.classList.add("ooglex-tech-locked");
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mountGate, { once: true });
  } else {
    mountGate();
  }
})();
