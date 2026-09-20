/* ===========================================================================
   OOGLEX 终端总览模型 · Overview Model
   ---------------------------------------------------------------------------
   横向模型：把站内 12 个 data.json 归一化成一份跨品类总览（股指 / 利率 / 外汇 /
   商品 / 信用 / 加密 / 宏观 / 曲线 / 日历 / 要闻 / 异动），供监控首页使用。
   纵向模型（单标的的收盘历史、盘中、采集健康）在 security.js。

   口径、格式化、统计、交易时段全部来自 core.js —— 这里只做取数与归一化。
   =========================================================================== */
(function (global) {
  "use strict";
  var C = global.OOGLEX_CORE;
  var soft = C.soft, isNum = C.isNum, fmt = C.fmt, meta = C.meta;
  var zscore = C.zscore, signalFromPercentile = C.signalFromPercentile, signalFromZ = C.signalFromZ;

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
      soft("companies/data.json"),
      soft("bonds/data.json"),
      soft("bonds/history.json")
    ]).then(function (r) {
      var assets = r[0], intraday = r[1], macro = r[2], curve = r[3], hist = r[4],
          series = r[5], fear = r[6], ofr = r[7], cal = r[8], news = r[9], crypto = r[10], comps = r[11],
          bonds = r[12], bondHist = r[13];

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
          /* 详情页：站内 quote.html 的 tracker kind 按 asset-tracker 的 symbol 取 */
          detail: a.symbol ? { kind:"tracker", symbol:a.symbol } : null,
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
          if (c) markets.crypto.push({ tk:sym, name:c.name, close:c.price, d1:c.changePct,
            marketCap:c.marketCap, meta:c.dataMeta || {},
            detail:{ kind:"crypto", symbol:c.symbol || c.id } });
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
              detail: { kind:"company", symbol:c.symbol },
              w1: rt.w1, m1: rt.m1, ytd: rt.ytd, y1: rt.y1,
              marketCap: c.marketCap, sector: c.sector, cur: c.priceCur,
              stale: !!c.stale, meta: c.dataMeta || {}
            };
          });
      }

      /* 利率：曲线 + 期限差（5s30s 由曲线现算） */
      var rates = { tenors: [], spreads: [], asOf: null, source: null, error: null };
      if (curve && !curve.__error) {
        rates.tenors = (curve.tenors || []).filter(function (t) { return isNum(t.value); })
          .map(function (t) {
            /* 详情页：quote.html 的 curve kind 按期限的 id（DGS10 这类）取 */
            return Object.assign({}, t, { detail: t.id ? { kind:"curve", symbol:t.id } : null });
          });
        rates.asOf = curve.asOf; rates.source = curve.source; rates.note = curve.note;
        rates.spreads = (curve.spreads || []).map(function (s) {
          /* 利差自带逐日序列（260 天），带上来才能画历史与数倒挂天数 */
          return { id:s.id, value:s.value, inverted:s.inverted, asOf:s.asOf, derived:false,
                   dates:s.dates || [], values:s.values || [] };
        });
        /* 十一个期限的逐日序列，共享一条日期轴 —— 可以重建任意历史日期上的曲线形态 */
        rates.history = (curve.history && curve.history.dates)
          ? { dates: curve.history.dates || [], values: curve.history.values || {} }
          : null;
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

      /* ── 各国主权债：收益率水平 + 相对基准的利差 ──────────────────────────
         站内 bonds/data.json 的 35 条收益率早就在「全球市场行情」的债券品类里
         按地区列出来了，每行还能点进自己的历史图 —— 这里**不重复那张水平表**，
         只补站内确实没有的一件事：**国与国之间的利差**。

         四条口径写在模型层，页面照着显示，不在页面上另算一套：
           · 利差单位是基点，由 core.spreadSeries / spreadCrossSection 算，
             收益率绝不重基到 100（那会把「上行 100bp」写成「+50%」）。
           · 横截面只在与基准**同一个数据日**的国家之间算，跨期的逐条摘出。
           · 34 条是月频（OECD 有滞后），涨跌一律「较前一观测」，不是当日。
           · 本轮取数失败沿用上次的行带 stale，页面必须标出来。 */
      var sovereign = { rows: [], error: null, hist: null, asOf: null, source: null,
                        note: null, monthlyFreqLabelBug: false };
      if (bonds && !bonds.__error) {
        sovereign.rows = (bonds.series || []).filter(function (b) { return b && b.id; })
          .map(function (b) {
            var m = b.dataMeta || {};
            return {
              id: b.id, name: b.name, nameEn: b.nameEn || "", region: b.region || "",
              price: b.price, changeBp: b.changeBp, previousAsOf: b.previousAsOf || "",
              frequency: b.frequency || m.frequency || "", stale: !!b.stale,
              asOf: m.asOf || null, status: m.status || "", mode: m.mode || "",
              source: m.source || bonds.source || "", note: b.note || m.note || "",
              detail: { kind: "bond", symbol: b.id }
            };
          });
        sovereign.asOf = bonds.asOf || null;
        sovereign.source = bonds.source || null;
        sovereign.note = bonds.note || null;
      } else {
        sovereign.error = (bonds && bonds.__error) || "读取失败";
      }
      if (bondHist && !bondHist.__error) {
        var mb = bondHist.monthly || {};
        /* 上游把月频桶的 frequency 写成了 "daily"（dates 实测是逐月的 1993-05…2026-08）。
           这里按**日期轴本身**判定频率，并把这处不一致如实带出来，页面注明，
           不跟着错标，也不假装没看见。 */
        var md = mb.dates || [];
        var looksMonthly = md.length > 2 && /^\d{4}-\d{2}-01$/.test(md[md.length - 1] || "");
        sovereign.monthlyFreqLabelBug = looksMonthly && mb.frequency === "daily";
        sovereign.hist = {
          dates: md, series: mb.series || {},
          declaredFreq: mb.frequency || null,
          freq: looksMonthly ? "monthly" : (mb.frequency || null),
          asOf: mb.asOf || null, source: mb.source || bondHist.source || null,
          note: bondHist.note || null
        };
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
            src("公司（个股）", comps, "日频收盘"),
            src("各国主权债收益率", bonds, "34条月频 + 1条日频"),
            src("主权债观测历史", bondHist, "月频 400 期")
          ]
        },
        markets: markets,
        rates: rates,
        macro: {
          regime: (macro && !macro.__error) ? (macro.regime || {}) : null,
          signals: signals,
          /* 8 条合成信号的 0–100 分位逐日序列：站内确实有，共用 history.json 的日期轴。
             不是价格，也没有单指标行情页，所以在监测面板里就地画，不伪造一个详情页。 */
          signalHist: (hist && !hist.__error)
            ? { dates: hist.dates || [], series: hist.signals || {}, freq: hist.freq || null,
                updatedAt: hist.updatedAt || null, note: hist.note || null }
            : null,
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
        sovereign: sovereign,
        /* raw 保留各源的原始 json：地缘风险模型要的是原始形态（signals 数组、fsi.spark），不是归一化后的 */
        raw: { assets: assets, intraday: intraday, macro: macro, curve: curve, fear: fear, ofr: ofr, cal: cal, news: news, crypto: crypto, comps: comps, bonds: bonds, bondHist: bondHist }
      };
      return model;

      /* 出处元数据统一由 core.meta 产出 */
      function src(label, d, cadence) { return meta(label, d, cadence); }
    });
  }

  global.OOGLEX_OVERVIEW = {
    load: load,
    TICKERS: TICKERS,
    /* 兼容口径：页面若只需要格式化与阈值，直接用 core 暴露的那一份 */
    fmt: fmt, isNum: isNum,
    marketStatus: C.marketStatus,
    UNAVAILABLE: C.UNAVAILABLE,
    UNAVAILABLE_NOTE: C.UNAVAILABLE_NOTE
  };
})(window);
