/* ===========================================================================
   OOGLEX 外壳数据层 · Chrome Data
   ---------------------------------------------------------------------------
   给「单证券页」与「榜单趋势页」用的最小数据层。口径规则与 ds/feed.js 一致：
     · 单源失败只影响对应区块，返回 {__error}，页面各自显示失败态
     · 盘中快照自带 realtime:false，只标「快照 30M」，绝不标「实时」
     · 站内没有的字段（BID/ASK/VOL/日内高低、财务报表、评级、券级现金流）
       在 UNAVAILABLE 里统一声明，页面据此写「无来源·不显示」而不是放占位数字
   =========================================================================== */
(function (global) {
  "use strict";
  var BASE = global.OOGLEX_DATA_BASE || "../apps/";

  function isNum(x) { return typeof x === "number" && isFinite(x); }
  function getJSON(p) {
    return fetch(BASE + p).then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status + " " + p);
      return r.json();
    });
  }
  function soft(p) {
    return getJSON(p).catch(function (e) { return { __error: String(e.message || e) }; });
  }

  var fmt = {
    px: function (x) {
      if (!isNum(x)) return "—";
      var a = Math.abs(x);
      return a >= 10000 ? x.toLocaleString("en-US", { maximumFractionDigits: 0 })
           : a >= 1000  ? x.toLocaleString("en-US", { maximumFractionDigits: 1 })
           : a >= 100   ? x.toFixed(2) : a >= 10 ? x.toFixed(3) : x.toFixed(4);
    },
    chg: function (x) { return !isNum(x) ? "—" : (x >= 0 ? "+" : "−") + Math.abs(x).toFixed(Math.abs(x) >= 100 ? 1 : 2); },
    pct: function (x, dp) { return !isNum(x) ? "—" : (x >= 0 ? "+" : "−") + Math.abs(x).toFixed(isNum(dp) ? dp : 2) + "%"; },
    cap: function (x) {
      if (!isNum(x)) return "—";
      return x >= 1000 ? (x / 1000).toFixed(2) + "T" : x.toFixed(1) + "B";
    },
    cls: function (x) { return !isNum(x) ? "fl" : x > 0 ? "up" : x < 0 ? "dn" : "fl"; },
    arrow: function (x) { return !isNum(x) || x === 0 ? "" : x > 0 ? "▲" : "▼"; },
    statusZh: function (s) {
      return { ok:"正常", partial:"部分缺失", stale:"数据过期", error:"读取失败",
               degraded:"降级", provider:"由提供方标注" }[s] || (s || "—");
    },
    utc: function (s) { return String(s || "—").replace("T", " ").replace(/\.\d+Z?$/, "Z"); }
  };

  var UNAVAILABLE = [
    { k:"BID / ASK / 买卖价差", why:"无免费公开的层级报价来源" },
    { k:"VOL 成交量 / 成交额",  why:"无免费公开来源" },
    { k:"日内最高 / 最低",       why:"盘中快照只给单点价格，不含区间" },
    { k:"财务报表字段（PE / PB / ROE / 营收）", why:"站内公司数据只到价格、市值与收益率" },
    { k:"信用评级 / 券级现金流",  why:"站内债券数据是主权收益率序列，无券级要素" },
    { k:"ISIN / FIGI / CUSIP",   why:"站内只有交易所代码（symbol），无付费标识符库" }
  ];
  var UNAVAILABLE_NOTE = "本终端不显示 BID / ASK / VOL / 日内高低 / 财务报表 / 评级 / 券级现金流：" +
    "站内没有这些来源，也不用占位数字冒充。";

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

  function meta(label, d, cadence) {
    if (!d || d.__error) return { label: label, error: (d && d.__error) || "未加载", cadence: cadence };
    return { label: label, source: d.source, asOf: d.asOf, updatedAt: d.updatedAt,
             frequency: d.frequency, status: d.status, cadence: cadence, note: d.note,
             count: d.count, realtime: d.realtime === true };
  }
  function srcLine(s, extra) {
    if (!s) return "来源 —";
    if (s.error) return "读取失败：" + s.error;
    return "来源 " + (s.source || "—") + " · AS OF " + (s.asOf || "—") + " · " +
      (s.cadence || s.frequency || "—") + " · 状态 " + fmt.statusZh(s.status) +
      (extra ? " · " + extra : "");
  }

  global.OOGLEX_CDATA = {
    loadSecurity: loadSecurity, loadTrends: loadTrends,
    fmt: fmt, isNum: isNum, srcLine: srcLine,
    UNAVAILABLE: UNAVAILABLE, UNAVAILABLE_NOTE: UNAVAILABLE_NOTE
  };
})(window);
