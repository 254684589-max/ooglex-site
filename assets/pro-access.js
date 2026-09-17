(function () {
  "use strict";

  var PROJECT_REF = "nwthqkpkvbtilafqpjlf";
  var STORAGE_KEY = "sb-" + PROJECT_REF + "-auth-token";
  var DEFAULT_API_BASE = "https://pro-api.ooglex.com";

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

  async function request(path, options) {
    var opts = Object.assign({ method: "GET", cache: "no-store" }, options || {});
    opts.headers = Object.assign({ Accept: "application/json" }, authHeaders(), opts.headers || {});
    var res = await fetch(apiBase() + path, opts);
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
    products: Object.freeze({ supplyChain: "supply_chain", macroRisk: "macro_risk" }),
    getSession: session,
    getAccess: getAccess,
    getData: getData
  });
})();
