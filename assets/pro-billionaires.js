(function () {
  "use strict";

  if (location.pathname.indexOf("/apps/billionaires/") < 0 || !window.OoglexPro) return;

  var nativeFetch = window.fetch.bind(window);
  var product = "billionaires";

  // 与 pro-rich-data.js 同一条规矩：本页的 Top 10 预览是同源静态文件，
  // 会员校验却要访问跨域的 Worker。该域名在某些网络下挂住而不是快速失败，
  // 所以权限结果绝不能成为静态数据的前置条件 —— 否则整页只剩空壳。
  var ACCESS_GATE_MS = 4000;

  function previewAccess(degraded) {
    var access = { authenticated: false, plan: "free", access_level: "preview" };
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
      });
    });
  }

  // 没有登录态就不可能拿到 full（Worker 对无 token 的请求同样只返回 preview），
  // 直接按预览处理，连这次跨域请求都不发。
  var accessPromise = hasSession()
    ? withGate(window.OoglexPro.getAccess(product).catch(function () {
        return previewAccess("unreachable");
      }))
    : Promise.resolve(previewAccess());

  var fullPromise = accessPromise.then(function (access) {
    if (!access || access.access_level !== "full") return null;
    return window.OoglexPro.getData(product, "full");
  }).catch(function () { return null; });

  function isBillionairesDataRequest(input) {
    var raw = typeof input === "string" ? input : (input && input.url ? input.url : "");
    try {
      var u = new URL(raw, location.href);
      return u.origin === location.origin && u.pathname === "/apps/billionaires/data.json";
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
    if (!isBillionairesDataRequest(input)) return nativeFetch(input, init);
    return accessPromise.then(function (access) {
      if (!access || access.access_level !== "full") return nativeFetch(input, init);
      return fullPromise.then(function (bundle) {
        if (bundle && bundle.data) return jsonResponse(bundle.data);
        return new Response(JSON.stringify({ error: "full_payload_component_not_ready", path: "data.json" }), {
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
      ? String(access.plan || "PRO").toUpperCase() + " · FULL"
      : "FREE · 10% PREVIEW";
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

  function installWall(access, attempt) {
    if (access && access.access_level === "full") return true;
    if (document.getElementById("ooglex-preview-wall")) return true;

    var page = document.querySelector(".page");
    var list = document.getElementById("list");
    if (!page || !list || !list.children.length) {
      if (attempt < 60) window.setTimeout(function () { installWall(access, attempt + 1); }, 70);
      return false;
    }

    var pager = page.querySelector(".pager");
    if (pager) pager.style.display = "none";

    var search = document.getElementById("q");
    if (search) search.placeholder = "在免费 Top 10 预览中搜索姓名（中 / 英）…";

    var fade = document.createElement("div");
    fade.id = "ooglex-preview-fade";
    fade.setAttribute("aria-hidden", "true");
    fade.style.cssText = [
      "height:110px","margin-top:-110px","position:relative","z-index:5","pointer-events:none",
      "background:linear-gradient(to bottom,rgba(12,13,20,0),rgba(18,18,18,.96))"
    ].join(";");

    var wall = document.createElement("section");
    wall.id = "ooglex-preview-wall";
    wall.style.cssText = [
      "position:relative","z-index:6","box-sizing:border-box","width:100%","min-height:218px","padding:24px 20px 22px","text-align:center","background:#171717","color:#f5f5f5",
      "border-top:1px solid rgba(255,255,255,.10)","box-shadow:0 -18px 50px rgba(0,0,0,.30)",
      "font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei',sans-serif"
    ].join(";");

    var title = document.createElement("div");
    title.textContent = "继续查看完整数据";
    title.style.cssText = "font-size:27px;font-weight:760;letter-spacing:-.3px;margin:1px 0 8px";

    var sub = document.createElement("div");
    sub.textContent = access && access.degraded
      ? "当前网络连不上会员服务，已按预览显示本页原版数据。恢复连接后可查看完整数据。"
      : access && access.authenticated
        ? "当前为 FREE 预览。升级 PRO 后可继续查看完整数据。"
        : "当前展示原版页面预览。登录 PRO 后可继续查看完整数据。";
    sub.style.cssText = "font-size:14px;line-height:1.7;color:#c8c8c8;margin:0 auto 18px;max-width:720px";

    var button = document.createElement("a");
    button.href = "/account/";
    button.textContent = access && access.authenticated ? "查看会员权限" : "登录 / 注册";
    button.style.cssText = [
      "display:inline-flex","align-items:center","justify-content:center","min-width:270px","height:44px",
      "padding:0 22px","border-radius:4px","background:#fff","color:#111","text-decoration:none",
      "font-size:15px","font-weight:720","box-shadow:none"
    ].join(";");

    var note = document.createElement("div");
    note.textContent = "完整数据不会发送给 FREE 浏览器；页面下方仅保留受限预览。";
    note.style.cssText = "font-size:11px;color:#8f8f8f;margin-top:14px";

    wall.appendChild(title);
    wall.appendChild(sub);
    wall.appendChild(button);
    wall.appendChild(note);

    if (page.parentNode) {
      page.parentNode.insertBefore(fade, page.nextSibling);
      fade.parentNode.insertBefore(wall, fade.nextSibling);
    }

    return true;
  }

  accessPromise.then(function (access) {
    onReady(function () {
      installBadge(access);
      installWall(access, 0);
    });
  });
})();
