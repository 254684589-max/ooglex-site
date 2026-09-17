(function () {
  "use strict";

  var nativeFetch = window.fetch.bind(window);
  var path = location.pathname;
  var product = path.indexOf("/apps/macro-radar/") >= 0 ? "macro_risk"
    : path.indexOf("/apps/supply-chain/") >= 0 ? "supply_chain"
    : null;
  if (!product || !window.OoglexPro) return;

  var accessPromise = window.OoglexPro.getAccess(product).catch(function () {
    return { authenticated: false, plan: "free", access_level: "preview" };
  });
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

  function installBadge(access) {
    function add() {
      if (document.getElementById("ooglex-rich-access")) return;
      var chip = document.createElement("div");
      chip.id = "ooglex-rich-access";
      chip.textContent = accessLabel(access);
      chip.style.cssText = [
        "position:fixed","right:14px","bottom:14px","z-index:9999",
        "padding:7px 11px","border-radius:999px","font:600 11px/1.2 -apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif",
        "letter-spacing:.4px","color:#dfe7ec","background:rgba(10,14,20,.88)",
        "border:1px solid rgba(255,255,255,.14)","backdrop-filter:blur(8px)",
        "box-shadow:0 8px 24px rgba(0,0,0,.28)"
      ].join(";");
      document.body.appendChild(chip);
    }
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", add, { once: true });
    else add();
  }

  accessPromise.then(installBadge);

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
        return nativeFetch(input, init); // static legacy path contains only the 10% preview artifact
      }
      return fullPromise.then(function (bundle) {
        var payload = product === "supply_chain"
          ? supplyPayload(rel, bundle)
          : macroPayload(rel, bundle);
        if (payload === undefined || payload === null) {
          return new Response(JSON.stringify({ error: "full_payload_component_not_ready", path: rel }), {
            status: 503,
            headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" }
          });
        }
        return jsonResponse(payload);
      });
    });
  };
})();
