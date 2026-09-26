(function () {
  "use strict";

  if (location.pathname.indexOf("/apps/whats-latest/") < 0 || !window.OoglexPro) return;

  var nativeFetch = window.fetch.bind(window);
  var product = "whats_latest";
  var ACCESS_GATE_MS = 4000;

  function previewAccess(degraded) {
    var access = { authenticated: false, plan: "guest", access_level: "preview" };
    if (degraded) access.degraded = degraded;
    return access;
  }

  function hasSession() {
    try { return !!(window.OoglexPro.getSession && window.OoglexPro.getSession()); }
    catch (_) { return false; }
  }

  function withGate(promise) {
    return new Promise(function (resolve) {
      var done = false;
      var timer = setTimeout(function () {
        if (done) return;
        done = true;
        resolve(previewAccess("timeout"));
      }, ACCESS_GATE_MS);
      promise.then(function (access) {
        if (done) return;
        done = true;
        clearTimeout(timer);
        resolve(access && access.access_level ? access : previewAccess("empty"));
      }).catch(function () {
        if (done) return;
        done = true;
        clearTimeout(timer);
        resolve(previewAccess("unreachable"));
      });
    });
  }

  var accessPromise = hasSession()
    ? withGate(window.OoglexPro.getAccess(product))
    : Promise.resolve(previewAccess());

  var fullPromise = accessPromise.then(function (access) {
    if (!access || access.access_level !== "full") return null;
    return window.OoglexPro.getData(product, "full");
  }).catch(function () { return null; });

  function isDataRequest(input) {
    var raw = typeof input === "string" ? input : (input && input.url ? input.url : "");
    try {
      var u = new URL(raw, location.href);
      return u.origin === location.origin && u.pathname === "/apps/whats-latest/data.json";
    } catch (_) {
      return false;
    }
  }

  function jsonResponse(value) {
    return new Response(JSON.stringify(value), {
      status: 200,
      headers: {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "private, no-store",
        "x-ooglex-rich-access": "full"
      }
    });
  }

  window.fetch = function (input, init) {
    if (!isDataRequest(input)) return nativeFetch(input, init);
    return accessPromise.then(function (access) {
      if (!access || access.access_level !== "full") return nativeFetch(input, init);
      return fullPromise.then(function (bundle) {
        if (bundle && bundle.data) return jsonResponse(bundle.data);
        return new Response(JSON.stringify({ error: "full_payload_component_not_ready" }), {
          status: 503,
          headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" }
        });
      });
    });
  };

  function onReady(fn) {
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", fn, { once: true });
    else fn();
  }

  function installBadge(access) {
    if (document.getElementById("ooglex-rich-access")) return;
    var chip = document.createElement("div");
    chip.id = "ooglex-rich-access";
    chip.textContent = access && access.access_level === "full"
      ? "REGISTERED · FULL"
      : "GUEST · 10% PREVIEW";
    chip.style.cssText = [
      "position:fixed","right:14px","bottom:14px","z-index:10001",
      "padding:7px 11px","border-radius:999px",
      "font:600 11px/1.2 -apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif",
      "letter-spacing:.4px","color:#dfe7ec","background:rgba(10,14,20,.88)",
      "border:1px solid rgba(255,255,255,.14)","backdrop-filter:blur(8px)",
      "box-shadow:0 8px 24px rgba(0,0,0,.28)"
    ].join(";");
    document.body.appendChild(chip);
  }

  function installWall(access) {
    if (access && access.access_level === "full") return;
    if (document.getElementById("ooglex-preview-wall")) return;

    var wall = document.createElement("section");
    wall.id = "ooglex-preview-wall";
    wall.setAttribute("data-ooglex-preview-hard-stop", "true");
    wall.style.cssText = [
      "position:fixed","left:0","right:0","bottom:0","z-index:10000",
      "box-sizing:border-box","padding:23px 20px 22px","text-align:center",
      "background:rgba(18,18,18,.97)","color:#f5f5f5",
      "border-top:1px solid rgba(255,255,255,.10)","box-shadow:0 -18px 50px rgba(0,0,0,.28)",
      "font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei',sans-serif"
    ].join(";");

    var title = document.createElement("div");
    title.textContent = "注册后查看完整新闻源";
    title.style.cssText = "font-size:24px;font-weight:760;margin:0 0 7px";

    var sub = document.createElement("div");
    sub.textContent = access && access.degraded
      ? "账户权限服务暂时不可达，当前按约 10% 公开预览显示。"
      : "当前仅开放约 10% 新闻内容。免费注册并登录后可查看完整新闻源。";
    sub.style.cssText = "font-size:13px;line-height:1.65;color:#c8c8c8;margin:0 auto 15px;max-width:720px";

    var button = document.createElement("a");
    button.href = "/account/?next=" + encodeURIComponent(location.pathname + location.search + location.hash);
    button.textContent = access && access.authenticated ? "重新验证登录" : "注册 / 登录";
    button.style.cssText = [
      "display:inline-flex","align-items:center","justify-content:center","min-width:240px","height:42px",
      "padding:0 20px","border-radius:8px","background:#fff","color:#111","text-decoration:none",
      "font-size:14px","font-weight:720"
    ].join(";");

    var note = document.createElement("div");
    note.textContent = "未注册浏览器只接收约 10% 预览数据；完整数据仅在登录验证通过后返回。";
    note.style.cssText = "font-size:11px;color:#8f8f8f;margin-top:11px";

    wall.appendChild(title);
    wall.appendChild(sub);
    wall.appendChild(button);
    wall.appendChild(note);
    document.body.appendChild(wall);

    var chip = document.getElementById("ooglex-rich-access");
    if (chip) chip.style.bottom = "198px";
  }

  accessPromise.then(function (access) {
    onReady(function () {
      installBadge(access);
      installWall(access);
    });
  });
})();