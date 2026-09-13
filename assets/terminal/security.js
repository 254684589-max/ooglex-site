/* ===========================================================================
   OOGLEX 终端单标的与榜单模型 · Security & Trends Model
   ---------------------------------------------------------------------------
   纵向模型：单个标的的发行人、证券、标识、收盘历史、盘中快照、采集健康；
   以及榜单页需要的全量公司 + 迷你走势 + 要闻。
   横向模型（跨品类总览、曲线、宏观、日历）在 overview.js。

   口径、格式化、统计全部来自 core.js —— 这里只做取数与归一化。
   =========================================================================== */
(function (global) {
  "use strict";
  var C = global.OOGLEX_CORE;
  var soft = C.soft, isNum = C.isNum, fmt = C.fmt, meta = C.meta;

  /* ── 单证券：公司榜 + 收盘历史 + 盘中快照 ──────────────────────────── */
  function loadSecurity() {
    return Promise.all([
      soft("companies/data.json"),
      soft("companies/history.json"),
      soft("companies/intraday.json"),
      soft("companies/health.json")
    ]).then(function (r) {
      var d = r[0], h = r[1], i = r[2], hl = r[3];
      var list = (d && !d.__error) ? (d.companies || []) : [];
      var histSeries = (h && !h.__error) ? (h.series || {}) : {};
      var histDates  = (h && !h.__error) ? (h.dates || []) : [];
      var quotes     = (i && !i.__error) ? (i.quotes || {}) : {};

      /* 有收盘历史的标的排前面 —— 走势页才有东西可画 */
      var pool = list.filter(function (c) { return c.symbol && isNum(c.price); })
        .sort(function (a, b) { return (b.marketCap || 0) - (a.marketCap || 0); });

      function sec(sym) {
        var c = pool.filter(function (x) { return x.symbol === sym; })[0];
        if (!c) return null;
        var q = quotes[sym];
        var hs = histSeries[sym] || null;
        var rt = c.returns || {};
        return {
          tk: c.symbol, zh: c.name, en: c.nameEn, sector: c.sector, country: c.country,
          domain: c.domain, cur: c.priceCur || "USD", rank: c.rank, sp500: !!c.sp500,
          close: c.price, d1: c.changePct, marketCap: c.marketCap,
          w1: rt.w1, m1: rt.m1, ytd: rt.ytd, y1: rt.y1,
          intraday: q && isNum(q.price) ? { price:q.price, prevClose:q.previousClose,
                                            changePct:q.changePct, asOf:q.asOf } : null,
          hist: hs, dates: histDates, stale: !!c.stale, meta: c.dataMeta || {}
        };
      }
      return {
        pool: pool.map(function (c) {
          return { tk:c.symbol, zh:c.name, en:c.nameEn, hasHist: !!histSeries[c.symbol] };
        }),
        sec: sec,
        src: {
          quote: meta("公司榜（收盘）", d, "日频收盘"),
          intra: meta("盘中快照", i, (i && i.cadenceMinutes ? "约" + i.cadenceMinutes + "分钟" : "约30分钟") + " · 非实时"),
          hist:  meta("收盘历史", h, (h && h.points ? h.points + " 个交易日" : "日频")),
          health: (hl && !hl.__error) ? hl : null
        },
        raw: { d:d, h:h, i:i, health:hl }
      };
    });
  }

  /* ── 榜单趋势：公司榜 + 要闻 ───────────────────────────────────────── */
  function loadTrends() {
    return Promise.all([
      soft("companies/data.json"),
      soft("companies/spark.json"),
      soft("whats-latest/data.json"),
      soft("asset-tracker/data.json")
    ]).then(function (r) {
      var d = r[0], sp = r[1], n = r[2], a = r[3];
      return {
        companies: (d && !d.__error) ? (d.companies || []) : [],
        spark: (sp && !sp.__error) ? (sp.series || {}) : {},
        sparkDates: (sp && !sp.__error) ? (sp.dates || []) : [],
        news: (n && !n.__error) ? n : null,
        assets: (a && !a.__error) ? (a.assets || []) : [],
        src: {
          comp: meta("公司榜", d, "日频收盘"),
          spark: meta("迷你走势", sp, (sp && sp.points ? sp.points + " 个交易日" : "日频")),
          news: meta("要闻", n, "日内多次"),
          assets: meta("大类资产", a, "日频收盘")
        },
        err: { comp: d && d.__error, spark: sp && sp.__error, news: n && n.__error, assets: a && a.__error }
      };
    });
  }

  global.OOGLEX_SECURITY = {
    loadSecurity: loadSecurity, loadTrends: loadTrends,
    fmt: fmt, isNum: isNum, srcLine: C.srcLine,
    UNAVAILABLE: C.UNAVAILABLE, UNAVAILABLE_NOTE: C.UNAVAILABLE_NOTE
  };
})(window);
