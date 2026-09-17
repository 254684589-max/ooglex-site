/* ===========================================================================
   OOGLEX 终端数据层 · Terminal Feed
   ---------------------------------------------------------------------------
   把站内既有的 9 个 data.json 归一化成一份终端模型，三份草案共用。
   不写任何数据，只读；不新增依赖；无后端。

   诚实性口径（仓库规则第 6、7 条）
   -----------------------------------
   · 每个数据集都带 source / asOf / frequency / status，页面必须显示。
   · 收盘口径与盘中快照分开：intraday.json 自带 realtime:false、约 30 分钟刷新，
     只标为「盘中快照 30M」，绝不标成实时。
   · 站内**没有** BID / ASK / VOL / 日内高低 的免费公开来源，因此不提供这些字段，
     也不用占位数字冒充 —— 窗口页脚会写明这一点。
   · 派生值（5s30s、Z-Score、分位、信号判定）一律标注算法与窗口，可由原始字段复现。
   =========================================================================== */
(function (global) {
  "use strict";

  var BASE = (global.OOGLEX_FEED_BASE || "../apps/");

  function isNum(x) { return typeof x === "number" && isFinite(x); }
  function getJSON(p) {
    return fetch(BASE + p).then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status + " " + p);
      return r.json();
    });
  }
  /* 单源失败不拖垮整页：失败的源返回 null，页面各窗口自行显示失败态 */
  function soft(p) { return getJSON(p).catch(function (e) { return { __error: String(e.message || e) }; }); }

  /* ── 格式化 ───────────────────────────────────────────────────────────── */
  var fmt = {
    px: function (x) {
      if (!isNum(x)) return "—";
      var a = Math.abs(x);
      return a >= 10000 ? x.toLocaleString("en-US", { maximumFractionDigits: 0 })
           : a >= 1000 ? x.toLocaleString("en-US", { minimumFractionDigits: 0, maximumFractionDigits: 1 })
           : a >= 100 ? x.toFixed(2) : a >= 10 ? x.toFixed(3) : x.toFixed(4);
    },
    chg: function (x) {                     /* 绝对变动 */
      if (!isNum(x)) return "—";
      return (x >= 0 ? "+" : "−") + Math.abs(x).toFixed(Math.abs(x) >= 100 ? 1 : 2);
    },
    pct: function (x, dp) {
      if (!isNum(x)) return "—";
      return (x >= 0 ? "+" : "−") + Math.abs(x).toFixed(isNum(dp) ? dp : 2) + "%";
    },
    bp: function (x) {
      if (!isNum(x)) return "—";
      return (x >= 0 ? "+" : "−") + Math.abs(Math.round(x)) + "bp";
    },
    z: function (x) {
      if (!isNum(x)) return "—";
      return (x >= 0 ? "+" : "−") + Math.abs(x).toFixed(2);
    },
    utc: function (s) { return String(s || "").replace("T", " ").replace(/\.\d+Z?$/, "").replace("Z", "Z"); },
    hm: function (iso) {
      if (!iso) return "—";
      var d = new Date(iso);
      if (isNaN(d)) return "—";
      function p(n) { return n < 10 ? "0" + n : "" + n; }
      return p(d.getUTCHours()) + ":" + p(d.getUTCMinutes()) + "Z";
    },
    statusZh: function (s) {
      return { ok:"正常", partial:"部分缺失", stale:"数据过期", error:"读取失败", provider:"由提供方标注" }[s] || (s || "—");
    },
    cls: function (x) { return !isNum(x) ? "t-flat" : x > 0 ? "t-up" : x < 0 ? "t-dn" : "t-flat"; }
  };

  /* ── 统计：Z-Score 与分位（都从站内原始序列算，可复现）─────────────────── */
  function zscore(values) {
    var v = (values || []).filter(isNum);
    if (v.length < 30) return null;
    var last = v[v.length - 1];
    var mean = v.reduce(function (a, b) { return a + b; }, 0) / v.length;
    var sd = Math.sqrt(v.reduce(function (a, b) { return a + (b - mean) * (b - mean); }, 0) / (v.length - 1));
    if (!sd) return null;
    return { z: (last - mean) / sd, n: v.length, mean: mean, sd: sd, last: last };
  }

  /* 信号判定：沿用站内宏观风险监测既有的 0–100 分位分档，收敛为四级 */
  function signalFromPercentile(p) {
    if (!isNum(p)) return { k:"na", label:"—" };
    if (p < 35) return { k:"stress", label:"STRESS" };
    if (p < 48) return { k:"risk", label:"RISK" };
    if (p < 58) return { k:"watch", label:"WATCH" };
    return { k:"normal", label:"NORMAL" };
  }
  /* Z-Score 判定：按偏离幅度分档，与分位一路无关 */
  function signalFromZ(z) {
    if (!isNum(z)) return { k:"na", label:"—" };
    var a = Math.abs(z);
    if (a >= 2) return { k:"stress", label:"STRESS" };
    if (a >= 1.5) return { k:"risk", label:"RISK" };
    if (a >= 1) return { k:"watch", label:"WATCH" };
    return { k:"normal", label:"NORMAL" };
  }

  /* ── 市场状态：按公开的常规交易时段由时钟推算，不含节假日 ───────────────── */
  function usEasternOffset(d) {
    /* 美国夏令时：3 月第二个周日 ~ 11 月第一个周日 */
    var y = d.getUTCFullYear();
    function nthSunday(month, nth) {
      var x = new Date(Date.UTC(y, month, 1));
      var add = (7 - x.getUTCDay()) % 7 + (nth - 1) * 7;
      return new Date(Date.UTC(y, month, 1 + add, 7));
    }
    var start = nthSunday(2, 2), end = nthSunday(10, 1);
    return (d >= start && d < end) ? -4 : -5;
  }
  function londonOffset(d) {
    var y = d.getUTCFullYear();
    function lastSunday(month) {
      var x = new Date(Date.UTC(y, month + 1, 0));
      return new Date(Date.UTC(y, month, x.getUTCDate() - x.getUTCDay(), 1));
    }
    var start = lastSunday(2), end = lastSunday(9);
    return (d >= start && d < end) ? 1 : 0;
  }
  function localParts(d, offsetHours) {
    var t = new Date(d.getTime() + offsetHours * 3600e3);
    return { h: t.getUTCHours(), m: t.getUTCMinutes(), dow: t.getUTCDay(), t: t };
  }
  function inWindow(p, from, to, lunch) {
    if (p.dow === 0 || p.dow === 6) return false;
    var mins = p.h * 60 + p.m;
    if (mins < from || mins >= to) return false;
    if (lunch && mins >= lunch[0] && mins < lunch[1]) return false;
    return true;
  }
  function marketStatus(now) {
    var d = now || new Date();
    var et = localParts(d, usEasternOffset(d));
    var ld = localParts(d, londonOffset(d));
    var tk = localParts(d, 9);
    var sh = localParts(d, 8);
    return [
      { id:"NYSE",     city:"NEW YORK", parts:et, open: inWindow(et, 9 * 60 + 30, 16 * 60) },
      { id:"NASDAQ",   city:"NEW YORK", parts:et, open: inWindow(et, 9 * 60 + 30, 16 * 60) },
      { id:"LSE",      city:"LONDON",   parts:ld, open: inWindow(ld, 8 * 60, 16 * 60 + 30) },
      { id:"TSE",      city:"TOKYO",    parts:tk, open: inWindow(tk, 9 * 60, 15 * 60, [11 * 60 + 30, 12 * 60 + 30]) },
      { id:"SSE",      city:"SHANGHAI", parts:sh, open: inWindow(sh, 9 * 60 + 30, 15 * 60, [11 * 60 + 30, 13 * 60]) }
    ];
  }

  /* ── 标的清单：规范点名的代码 → 站内名称 ────────────────────────────────
     站内确实没有的（NDX、DJI 现货指数）不编造，改用有数据的近义标的并注明。 */
  var TICKERS = {
    indices: [
      { tk:"SPX",    name:"标普500",           key:"标普500" },
      { tk:"CCMP",   name:"纳斯达克综合",       key:"纳斯达克综合", note:"站内无 NDX 100，用综合指数" },
      { tk:"RTY",    name:"罗素2000",          key:"美国罗素2000" },
      { tk:"SX5E",   name:"欧元区斯托克50",     key:"欧元区斯托克50" },
      { tk:"DAX",    name:"德国DAX",           key:"德国DAX" },
      { tk:"UKX",    name:"英国富时100",        key:"英国富时100" },
      { tk:"NKY",    name:"日经225",           key:"日经225" },
      { tk:"HSI",    name:"恒生指数",           key:"恒生指数" },
      { tk:"CSI300", name:"沪深300",           key:"沪深300" },
      { tk:"VIX",    name:"标普500波动率",      key:"标普500波动率VIX" }
    ],
    fx: [
      { tk:"DXY",    name:"美元指数",           key:"美元指数" },
      { tk:"EURUSD", name:"欧元兑美元",         key:"欧元兑美元" },
      { tk:"USDJPY", name:"美元兑日元",         key:"美元兑日元" },
      { tk:"GBPUSD", name:"英镑兑美元",         key:"英镑兑美元" },
      { tk:"USDCNY", name:"美元兑人民币",       key:"美元兑人民币", note:"在岸 CNY，非离岸 CNH" }
    ],
    commodities: [
      { tk:"CL",     name:"WTI 原油",          key:"NYMEX WTI原油" },
      { tk:"CO",     name:"布伦特原油",         key:"ICE布油" },
      { tk:"XAU",    name:"黄金",              key:"COMEX黄金" },
      { tk:"XAG",    name:"白银",              key:"COMEX白银" },
      { tk:"HG",     name:"铜",                key:"LME铜" },
      { tk:"NG",     name:"天然气",            key:"NYMEX天然气" }
    ],
    credit: [
      { tk:"TLT",    name:"美国长期国债",       key:"美国长期国债", proxy:1 },
      { tk:"LQD",    name:"投资级公司债",       key:"美国投资级公司债", proxy:1 },
      { tk:"HYG",    name:"高收益债",          key:"美国高收益债", proxy:1 },
      { tk:"EMB",    name:"新兴市场美元主权债", key:"新兴市场美元主权债", proxy:1 }
    ]
  };

  /* 宏观表里按 id 取值（这些是 FRED / Yahoo 的官方序列，现值与日变动都是现成的） */
  function macroIndex(macro) {
    var idx = {};
    (macro || []).forEach(function (blk) {
      (blk.rows || []).forEach(function (r) {
        var k = r.id || r.name;
        if (k) idx[k] = Object.assign({ __group: blk.zh, __src: blk.src }, r);
      });
      (blk.rows || []).forEach(function (r) { if (r.name) idx["名:" + r.name] = Object.assign({ __group: blk.zh, __src: blk.src }, r); });
    });
    return idx;
  }

  /* ── 装配 ─────────────────────────────────────────────────────────────── */
  function load() {
    return Promise.all([
      soft("asset-tracker/data.json"),
      soft("asset-tracker/intraday.json"),
      soft("macro-radar/data.json"),
      soft("macro-radar/curve.json"),
      soft("macro-radar/history.json"),
      soft("macro-radar/series.json"),
      soft("fear-greed/data.json"),
      soft("ofr-monitor/data.json"),
      soft("econ-calendar/data.json"),
      soft("whats-latest/data.json"),
      soft("asset-ranking/crypto.json"),
      soft("companies/data.json")
    ]).then(function (r) {
      var assets = r[0], intraday = r[1], macro = r[2], curve = r[3], hist = r[4],
          series = r[5], fear = r[6], ofr = r[7], cal = r[8], news = r[9], crypto = r[10], comps = r[11];

      /* 收盘与盘中合并：收盘为准，盘中作为「最新」另列 */
      var byName = {}, bySym = {};
      if (assets && !assets.__error) (assets.assets || []).forEach(function (a) { byName[a.name] = a; bySym[a.symbol] = a; });
      var intraQ = (intraday && !intraday.__error) ? (intraday.quotes || {}) : {};

      function quote(def) {
        var a = byName[def.key];
        if (!a) return Object.assign({}, def, { missing: true });
        var rt = a.returns || {};
        var iq = intraQ[a.symbol];
        return Object.assign({}, def, {
          symbol: a.symbol,
          close: a.price,
          d1: rt.d1, w1: rt.w1, m1: rt.m1, ytd: rt.ytd, y1: rt.y1,
          intraday: iq && isNum(iq.price) ? { price: iq.price, changePct: iq.changePct, prevClose: iq.previousClose, asOf: iq.asOf } : null,
          stale: !!a.stale,
          meta: a.dataMeta || {}
        });
      }
      var markets = {};
      Object.keys(TICKERS).forEach(function (k) { markets[k] = TICKERS[k].map(quote); });

      /* 加密：CoinGecko 24 小时口径，与股票的当日口径不同，单列并注明 */
      markets.crypto = [];
      if (crypto && !crypto.__error) {
        ["BTC", "ETH"].forEach(function (sym) {
          var c = (crypto.assets || []).find(function (x) { return x.symbol === sym; });
          if (c) markets.crypto.push({ tk:sym, name:c.name, close:c.price, d1:c.changePct, marketCap:c.marketCap, meta:c.dataMeta || {} });
        });
      }

      /* 个股：站内公司榜（含 NVDA 等），按市值排序取前列。
         口径与指数不同：changePct 是公司榜自带的当日涨跌，市值单位为十亿美元。 */
      markets.stocks = [];
      if (comps && !comps.__error) {
        markets.stocks = (comps.companies || [])
          .filter(function (c) { return c.symbol && isNum(c.price); })
          .sort(function (a, b) { return (b.marketCap || 0) - (a.marketCap || 0); })
          .slice(0, 24)
          .map(function (c) {
            var rt = c.returns || {};
            return {
              tk: c.symbol, name: c.name || c.nameEn, close: c.price, d1: c.changePct,
              w1: rt.w1, m1: rt.m1, ytd: rt.ytd, y1: rt.y1,
              marketCap: c.marketCap, sector: c.sector, cur: c.priceCur,
              stale: !!c.stale, meta: c.dataMeta || {}
            };
          });
      }

      /* 利率：曲线 + 期限差（5s30s 由曲线现算） */
      var rates = { tenors: [], spreads: [], asOf: null, source: null, error: null };
      if (curve && !curve.__error) {
        rates.tenors = (curve.tenors || []).filter(function (t) { return isNum(t.value); });
        rates.asOf = curve.asOf; rates.source = curve.source; rates.note = curve.note;
        rates.spreads = (curve.spreads || []).map(function (s) {
          return { id:s.id, value:s.value, inverted:s.inverted, asOf:s.asOf, derived:false };
        });
        function ten(lbl) { var t = rates.tenors.find(function (x) { return x.label === lbl; }); return t ? t.value : null; }
        var y5 = ten("5Y"), y30 = ten("30Y");
        if (isNum(y5) && isNum(y30)) {
          rates.spreads.push({ id:"30Y-5Y", value: y30 - y5, inverted: (y30 - y5) < 0, asOf: rates.asOf, derived:true });
        }
      } else { rates.error = (curve && curve.__error) || "读取失败"; }

      /* 宏观：机制、信号（带分位与周变动）、官方表 */
      var mi = (macro && !macro.__error) ? macroIndex(macro.macro) : {};
      var signals = [];
      if (macro && !macro.__error) {
        var hs = (hist && !hist.__error) ? (hist.signals || {}) : {};
        signals = (macro.signals || []).map(function (s) {
          var h = hs[s.key] || [];
          var w1 = (h.length >= 2 && isNum(h[h.length - 1]) && isNum(h[h.length - 2])) ? h[h.length - 1] - h[h.length - 2] : null;
          return {
            key: s.key, name: s.zh, en: s.en, score: s.score, statusZh: s.statusZh,
            desc: s.desc, spark: s.spark, w1: w1, signal: signalFromPercentile(s.score)
          };
        });
      }

      /* 两条真 Z-Score：DGS10 与美元指数，从站内原始日序列算 */
      var zs = {};
      if (series && !series.__error) {
        var S = series.series || {};
        [["DGS10", "US10Y"], ["DTWEXBGS", "DXY-FED"], ["RWTC", "WTI-SPOT"]].forEach(function (pair) {
          var s = S[pair[0]];
          if (!s) return;
          var vals = (s.values || s.data || s.series || []).filter(isNum);
          if (!vals.length && Array.isArray(s)) vals = s.filter(isNum);
          var st = zscore(vals);
          if (st) zs[pair[1]] = Object.assign({ id: pair[0], n: st.n }, st, { signal: signalFromZ(st.z) });
        });
      }

      var model = {
        meta: {
          generatedAt: new Date().toISOString(),
          sources: [
            src("行情（收盘）", assets, "日频收盘"),
            src("行情（盘中快照）", intraday, "约30分钟 · 非实时"),
            src("宏观风险监测", macro, "日频"),
            src("美债曲线", curve, "日频"),
            src("恐慌贪婪", fear, "日频"),
            src("OFR 金融风险", ofr, "日频"),
            src("经济日历", cal, "周历 · 每日刷新"),
            src("要闻", news, "日内多次"),
            src("加密（CoinGecko）", crypto, "日频 · 24h 口径"),
            src("公司（个股）", comps, "日频收盘")
          ]
        },
        markets: markets,
        rates: rates,
        macro: {
          regime: (macro && !macro.__error) ? (macro.regime || {}) : null,
          signals: signals,
          mutations: (macro && !macro.__error) ? (macro.mutations || []) : [],
          mutSummary: (macro && !macro.__error) ? macro.mutSummary : null,
          tables: (macro && !macro.__error) ? (macro.macro || []) : [],
          index: mi,
          asOf: (macro && !macro.__error) ? macro.asOf : null,
          source: (macro && !macro.__error) ? macro.source : null,
          error: (macro && macro.__error) || null
        },
        z: zs,
        fear: (fear && !fear.__error) ? fear : null,
        ofr: (ofr && !ofr.__error) ? ofr : null,
        calendar: (cal && !cal.__error) ? cal : null,
        news: (news && !news.__error) ? news : null,
        companies: (comps && !comps.__error) ? comps : null,
        raw: { assets: assets, intraday: intraday, curve: curve, fear: fear, ofr: ofr, cal: cal, news: news, crypto: crypto, comps: comps }
      };
      return model;

      function src(label, d, cadence) {
        if (!d || d.__error) return { label: label, error: (d && d.__error) || "未加载", cadence: cadence };
        return { label: label, source: d.source, asOf: d.asOf, updatedAt: d.updatedAt,
                 frequency: d.frequency, status: d.status, cadence: cadence };
      }
    });
  }

  global.OOGLEX_FEED = {
    load: load, fmt: fmt, isNum: isNum,
    TICKERS: TICKERS,
    zscore: zscore,
    signalFromPercentile: signalFromPercentile,
    signalFromZ: signalFromZ,
    marketStatus: marketStatus,
    /* 站内没有的字段，统一在这里声明，页面据此显示说明而不是占位数字 */
    UNAVAILABLE: ["BID", "ASK", "VOL", "日内高/低"],
    UNAVAILABLE_NOTE: "BID / ASK / VOL / 日内高低无免费公开来源，本终端不显示，也不用占位数字冒充。"
  };
})(window);
