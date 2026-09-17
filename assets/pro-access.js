(function () {
  "use strict";

  var PROJECT_REF = "nwthqkpkvbtilafqpjlf";
  var STORAGE_KEY = "sb-" + PROJECT_REF + "-auth-token";
  var DEFAULT_API_BASE = "https://ooglex-pro-api.zlq6600e.workers.dev";
  // 会员 API 在跨域的 Worker 上。某些网络（例如中国大陆直连 *.workers.dev）
  // 既连不上也不会快速失败，请求会一直挂住。没有超时的话，调用方拿到的
  // Promise 永远不会 settle，页面就卡在“等权限”这一步。
  var REQUEST_TIMEOUT_MS = 7000;

  function apiBase() {
    var meta = document.querySelector('meta[name="ooglex-pro-api"]');
    var value = meta && meta.getAttribute("content");
    return (value || window.OOGLEX_PRO_API || DEFAULT_API_BASE).replace(/\/$/, "");
  }

  function session() {
    try {
      var raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      var parsed = JSON.parse(raw);
      return parsed && parsed.access_token ? parsed : null;
    } catch (_) {
      return null;
    }
  }

  function authHeaders() {
    var s = session();
    return s && s.access_token ? { Authorization: "Bearer " + s.access_token } : {};
  }

  function abortGuard(ms) {
    if (typeof AbortController !== "function") return null;
    var ctrl = new AbortController();
    var timer = setTimeout(function () { try { ctrl.abort(); } catch (_) {} }, ms);
    return { signal: ctrl.signal, clear: function () { clearTimeout(timer); } };
  }

  async function request(path, options) {
    var opts = Object.assign({ method: "GET", cache: "no-store" }, options || {});
    opts.headers = Object.assign({ Accept: "application/json" }, authHeaders(), opts.headers || {});
    var guard = opts.signal ? null : abortGuard(REQUEST_TIMEOUT_MS);
    if (guard) opts.signal = guard.signal;

    var res;
    try {
      res = await fetch(apiBase() + path, opts);
    } catch (e) {
      var offline = new Error(e && e.name === "AbortError" ? "network_timeout" : "network_error");
      offline.status = 0;
      offline.cause = e;
      throw offline;
    } finally {
      if (guard) guard.clear();
    }

    var body = null;
    try { body = await res.json(); } catch (_) { body = null; }
    if (!res.ok) {
      var err = new Error(body && body.error ? body.error : ("HTTP " + res.status));
      err.status = res.status;
      err.body = body;
      throw err;
    }
    return body;
  }

  async function getAccess(product) {
    return request("/v1/access?product=" + encodeURIComponent(product));
  }

  async function getData(product, mode) {
    return request("/v1/data/" + encodeURIComponent(product) + "?mode=" + encodeURIComponent(mode || "preview"));
  }

  window.OoglexPro = Object.freeze({
    products: Object.freeze({
      supplyChain: "supply_chain",
      macroRisk: "macro_risk",
      billionaires: "billionaires"
    }),
    requestTimeoutMs: REQUEST_TIMEOUT_MS,
    getSession: session,
    getAccess: getAccess,
    getData: getData
  });
})();
