(function () {
  "use strict";

  var nativeFetch = window.fetch.bind(window);
  var path = location.pathname;
  var product = path.indexOf("/apps/macro-radar/") >= 0 ? "macro_risk"
    : path.indexOf("/apps/supply-chain/") >= 0 ? "supply_chain"
    : null;
  if (!product || !window.OoglexPro) return;

  // 这两个页面的预览数据是同源静态文件，会员校验却要访问跨域的 Worker。
  // 某些网络下该域名不可达且不会快速失败（请求一直挂住），所以权限结果
  // 绝不能成为静态数据的前置条件 —— 否则页面只剩一个空壳，连“加载失败”
  // 都显示不出来（app.js 的 catch 也等不到）。
  var ACCESS_GATE_MS = 4000;
  var BRIDGE_TIMEOUT_MS = 8000;

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

  // 没有登录态就不可能拿到 full 权限：Worker 对无 token 的请求同样只返回
  // preview，所以这里直接按预览处理，连这次跨域请求都不发。
  var accessPromise = hasSession()
    ? withGate(window.OoglexPro.getAccess(product).catch(function () {
        return previewAccess("unreachable");
      }))
    : Promise.resolve(previewAccess());

  var fullPromise = accessPromise.then(function (access) {
    if (access.access_level !== "full") return null;
    return window.OoglexPro.getData(product, "full");
  }).catch(function () { return null; });

  function accessLabel(access) {
    if (access && access.access_level === "full") {
      return String(access.plan || "PRO").toUpperCase() + " · FULL";
    }
    return "FREE · 10% PREVIEW";
  }

  function onReady(fn) {
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", fn, { once: true });
    else fn();
  }

  function installBadge(access) {
    onReady(function () {
      if (document.getElementById("ooglex-rich-access")) return;
      var chip = document.createElement("div");
      chip.id = "ooglex-rich-access";
      chip.textContent = accessLabel(access);
      chip.style.cssText = [
        "position:fixed","right:14px","bottom:14px","z-index:10001",
        "padding:7px 11px","border-radius:999px","font:600 11px/1.2 -apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif",
        "letter-spacing:.4px","color:#dfe7ec","background:rgba(10,14,20,.88)",
        "border:1px solid rgba(255,255,255,.14)","backdrop-filter:blur(8px)",
        "box-shadow:0 8px 24px rgba(0,0,0,.28)"
      ].join(";");
      document.body.appendChild(chip);
    });
  }

  function installPreviewWall(access) {
    if (access && access.access_level === "full") return;
    onReady(function () {
      if (document.getElementById("ooglex-preview-wall")) return;

      var fade = document.createElement("div");
      fade.id = "ooglex-preview-fade";
      fade.style.cssText = [
        "position:fixed","left:0","right:0","bottom:218px","height:110px","z-index:9998",
        "pointer-events:none",
        "background:linear-gradient(to bottom,rgba(0,0,0,0),rgba(10,10,10,.72))"
      ].join(";");

      var wall = document.createElement("div");
      wall.id = "ooglex-preview-wall";
      wall.style.cssText = [
        "position:fixed","left:0","right:0","bottom:0","z-index:9999","min-height:218px",
        "box-sizing:border-box","padding:24px 20px 22px","text-align:center",
        "background:#171717","color:#f5f5f5","border-top:1px solid rgba(255,255,255,.10)",
        "box-shadow:0 -18px 50px rgba(0,0,0,.30)",
        "font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei',sans-serif"
      ].join(";");

      var title = document.createElement("div");
      title.textContent = "继续查看完整数据";
      title.style.cssText = "font-size:27px;font-weight:760;letter-spacing:-.3px;margin:1px 0 8px";

      var sub = document.createElement("div");
      sub.textContent = access && access.degraded
        ? "当前网络连不上会员服务，已按预览显示本页原版数据。恢复连接后可查看完整数据。"
        : access && access.authenticated
          ? "当前为 FREE 预览。升级 PRO 后继续使用同一原版页面查看全部数据。"
          : "当前展示原版页面预览。登录 PRO 后可继续查看完整数据。";
      sub.style.cssText = "font-size:14px;line-height:1.6;color:#c8c8c8;margin:0 auto 17px;max-width:720px";

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
      document.body.appendChild(fade);
      document.body.appendChild(wall);

      var chip = document.getElementById("ooglex-rich-access");
      if (chip) chip.style.bottom = "232px";
    });
  }

  accessPromise.then(function (access) {
    installBadge(access);
    installPreviewWall(access);
  });

  function relPath(url) {
    var u;
    try { u = new URL(url, location.href); } catch (_) { return ""; }
    if (u.origin !== location.origin) return "";
    var base = product === "supply_chain" ? "/apps/supply-chain/" : "/apps/macro-radar/";
    if (u.pathname.indexOf(base) !== 0) return "";
    return decodeURIComponent(u.pathname.slice(base.length));
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

  function supplyPayload(rel, bundle) {
    if (!bundle) return undefined;
    var supp = bundle.supplemental || {};
    if (rel === "nodes.json") return bundle.primary;
    if (rel === "history.json") return supp.history;
    if (rel === "peers.json") return supp.peers;
    if (rel === "names-zh.json") return supp.namesZh;
    if (rel.indexOf("edges/") === 0) {
      var edges = supp.edges || {};
      return edges[rel];
    }
    return undefined;
  }

  function macroPayload(rel, bundle) {
    if (!bundle) return undefined;
    if (rel === "data.json") return bundle.data;
    if (rel === "history.json") return bundle.history;
    if (rel === "series.json") return bundle.series;
    if (rel === "curve.json") return bundle.curve;
    if (rel === "curve-monthly.json") return bundle.curveMonthly;
    return undefined;
  }

  function legacyFullBridge(rel) {
    if (product !== "supply_chain") return Promise.resolve(null);
    if (!(rel === "history.json" || rel === "peers.json" || rel === "names-zh.json" || rel.indexOf("edges/") === 0)) {
      return Promise.resolve(null);
    }
    var safe = rel.split("/").map(encodeURIComponent).join("/");
    var url = "https://raw.githubusercontent.com/254684589-max/ooglex-site/main/apps/supply-chain/" + safe;
    // 同样是跨域兜底源，同样可能在某些网络下挂住：必须能自己放弃。
    var init = { cache: "no-store" };
    var timer = null;
    if (typeof AbortController === "function") {
      var ctrl = new AbortController();
      init.signal = ctrl.signal;
      timer = setTimeout(function () { try { ctrl.abort(); } catch (_) {} }, BRIDGE_TIMEOUT_MS);
    }
    function settle(value) {
      if (timer) clearTimeout(timer);
      return value;
    }
    return nativeFetch(url, init).then(function (res) {
      if (!res.ok) return settle(null);
      return res.json().then(function (body) { return settle(jsonResponse(body)); })
        .catch(function () { return settle(null); });
    }).catch(function () { return settle(null); });
  }

  window.fetch = function (input, init) {
    var raw = typeof input === "string" ? input : (input && input.url ? input.url : "");
    var rel = relPath(raw);
    if (!rel) return nativeFetch(input, init);

    var protectedRequest = product === "supply_chain"
      ? (rel === "nodes.json" || rel === "history.json" || rel === "peers.json" || rel === "names-zh.json" || rel.indexOf("edges/") === 0)
      : (rel === "data.json" || rel === "history.json" || rel === "series.json" || rel === "curve.json" || rel === "curve-monthly.json");
    if (!protectedRequest) return nativeFetch(input, init);

    return accessPromise.then(function (access) {
      if (!access || access.access_level !== "full") {
        return nativeFetch(input, init);
      }
      return fullPromise.then(function (bundle) {
        var payload = product === "supply_chain"
          ? supplyPayload(rel, bundle)
          : macroPayload(rel, bundle);
        if (payload !== undefined && payload !== null) return jsonResponse(payload);

        return legacyFullBridge(rel).then(function (bridged) {
          if (bridged) return bridged;
          return new Response(JSON.stringify({ error: "full_payload_component_not_ready", path: rel }), {
            status: 503,
            headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" }
          });
        });
      });
    });
  };
})();
