/* ===========================================================================
   OOGLEX 终端单标的与榜单模型 · Security & Trends Model
   ---------------------------------------------------------------------------
   纵向模型：单个标的的发行人、证券、标识、收盘历史、盘中快照、采集健康；
   榜单页需要的全量公司 + 迷你走势 + 要闻；以及多标的比较页要的序列取数。
   「纵向」指的是时间轴 —— 比较页要的也是时间序列，所以归在这里，
   不另开第五个模型文件。（横截面快照在 overview.js。）
   横向模型（跨品类总览、曲线、宏观、日历）在 overview.js。

   口径、格式化、统计全部来自 core.js —— 这里只做取数与归一化。
   =========================================================================== */
(function (global) {
  "use strict";
  var C = global.OOGLEX_CORE;
  var soft = C.soft, isNum = C.isNum, fmt = C.fmt, meta = C.meta;

  /* ── 单证券：公司榜 + 收盘历史 + 盘中快照 ──────────────────────────── */
  /* 收盘历史按市值名次每 100 家一片存放，逐行的 historyShard 指明在第几片。
     首屏只取第 1 片（约 170KB），选到别的片里的标的时再按需补那一片，
     不为了让每个标的都有图而把 450 家的整份历史一次拉下来。
     五片共用同一条日期轴（管道保证，validate_terminal.py 逐片核对），
     所以各片的 series 可以并进同一张表，按共享日期轴对齐。 */
  var HIST = "companies/history.json";

  function loadSecurity() {
    return Promise.all([
      soft("companies/data.json"),
      soft(HIST),
      soft("companies/intraday.json"),
      soft("companies/health.json")
    ]).then(function (r) {
      var d = r[0], h = r[1], i = r[2], hl = r[3];
      var list = (d && !d.__error) ? (d.companies || []) : [];
      var quotes     = (i && !i.__error) ? (i.quotes || {}) : {};

      /* 并进来的各片 series；日期轴以第 1 片为准，后续片上轴不一致就整片不收 */
      var histSeries = {}, histDates = [];
      var loaded = {};            /* 片号 → 该片的取数结果（成功或失败都记，失败不重试到死） */
      function absorb(shard, file) {
        loaded[shard] = file;
        if (!file || file.__error) return false;
        var dates = file.dates || [];
        if (!histDates.length) histDates = dates;
        else if (dates.length !== histDates.length ||
                 dates[0] !== histDates[0] || dates[dates.length - 1] !== histDates[histDates.length - 1]) {
          /* 日期轴对不上就不并——错轴画出来的线是假的，宁可这一片没有图 */
          loaded[shard] = { __error: "第 " + shard + " 片日期轴与第 1 片不一致，未采用" };
          return false;
        }
        var ss = file.series || {};
        for (var k in ss) if (ss.hasOwnProperty(k)) histSeries[k] = ss[k];
        return true;
      }
      absorb(1, h);

      var shardOf = {};
      list.forEach(function (c) {
        if (c.symbol) shardOf[c.symbol] = C.shardPath(HIST, c.historyShard) === HIST ? 1 : Number(c.historyShard);
      });

      var pool = list.filter(function (c) { return c.symbol && isNum(c.price); })
        .sort(function (a, b) { return (b.marketCap || 0) - (a.marketCap || 0); });

      function histMeta(shard) {
        var f = loaded[shard];
        var extra = shard > 1 ? "第 " + shard + " 片" : null;
        var m = meta("收盘历史" + (extra ? "（" + extra + "）" : ""), f,
                     (f && !f.__error && f.points ? f.points + " 个交易日" : "日频"));
        return m;
      }

      /* 按需补齐某个标的所在的那一片。已在表里、片号不明、或这一片取过了都直接返回。
         无论成败都把 src.hist 换成实际读到的那一片的来源行——出处必须对得上画出来的线。 */
      function ensureHist(sym) {
        var shard = shardOf[sym] || 1;
        if (loaded.hasOwnProperty(shard)) { out.src.hist = histMeta(shard); return Promise.resolve(out); }
        return soft(C.shardPath(HIST, shard)).then(function (f) {
          absorb(shard, f);
          out.src.hist = histMeta(shard);
          return out;
        });
      }

      function sec(sym) {
        var c = pool.filter(function (x) { return x.symbol === sym; })[0];
        if (!c) return null;
        var q = quotes[sym];
        var hs = histSeries[sym] || null;
        var rt = c.returns || {};
        return {
          tk: c.symbol, zh: c.name, en: c.nameEn, sector: c.sector, country: c.country,
          detail: { kind:"company", symbol:c.symbol },
          domain: c.domain, cur: c.priceCur || "USD", rank: c.rank, sp500: !!c.sp500,
          close: c.price, d1: c.changePct, marketCap: c.marketCap,
          w1: rt.w1, m1: rt.m1, ytd: rt.ytd, y1: rt.y1,
          intraday: q && isNum(q.price) ? { price:q.price, prevClose:q.previousClose,
                                            changePct:q.changePct, asOf:q.asOf } : null,
          hist: hs, dates: hs ? histDates : [], histShard: shardOf[sym] || null,
          /* 「站内没有这条序列」和「这一片这次没取到」是两回事，页面得分开说 */
          histErr: (function () {
            var f = loaded[shardOf[sym] || 1];
            if (!f) return "该片收盘历史尚未取回";
            return f.__error ? String(f.__error) : null;
          })(),
          stale: !!c.stale, meta: c.dataMeta || {}
        };
      }

      var out = {
        pool: pool.map(function (c) {
          /* hasHist 按管道写的片号报，不为了这一行去把五片全拉下来；
             片号有而那一片里确实没有序列的（站内目前 1 家）走势页照实说没有序列，不画插值线。 */
          return { tk:c.symbol, zh:c.name, en:c.nameEn,
                   shard: shardOf[c.symbol] || null, hasHist: !!shardOf[c.symbol] };
        }),
        sec: sec,
        ensureHist: ensureHist,
        src: {
          quote: meta("公司榜（收盘）", d, "日频收盘"),
          intra: meta("盘中快照", i, (i && i.cadenceMinutes ? "约" + i.cadenceMinutes + "分钟" : "约30分钟") + " · 非实时"),
          hist:  histMeta(1),
          health: (hl && !hl.__error) ? hl : null
        },
        raw: { d:d, h:h, i:i, health:hl }
      };
      return out;
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

  /* ── 比较页：公司（分片日线）＋ 跨资产（单文件日线）的序列取数 ─────────
     两条管道的日期轴不同，所以这里只负责「按标的取回它自己的 dates+values」，
     对齐交给 core.alignSeries —— 对齐规则只有一份，两边都不各写一遍。 */
  function loadCompare() {
    return Promise.all([
      soft("companies/data.json"),
      soft("asset-tracker/data.json"),
      soft("asset-tracker/history.json")
    ]).then(function (r) {
      var cd = r[0], ad = r[1], ah = r[2];
      var comps = (cd && !cd.__error) ? (cd.companies || []) : [];
      var assets = (ad && !ad.__error) ? (ad.assets || []) : [];
      var aHist = (ah && !ah.__error) ? ah : null;

      var pool = [];
      comps.filter(function (c) { return c.symbol && c.symbol !== "—" && isNum(c.price) && c.historyShard; })
        .sort(function (a, b) { return (b.marketCap || 0) - (a.marketCap || 0); })
        .forEach(function (c) {
          pool.push({ tk:c.symbol, name:c.name, kind:"company", shard:Number(c.historyShard),
                      cur:c.priceCur || "USD", group:"公司 " + (c.sector || "未标注"),
                      detail:{ kind:"company", symbol:c.symbol } });
        });
      var ZH = { equity:"跨资产 股票", commodity:"跨资产 商品", fx:"跨资产 外汇", bond:"跨资产 债券" };
      assets.filter(function (a) { return a.symbol && isNum(a.price); }).forEach(function (a) {
        pool.push({ tk:a.symbol, name:a.name, kind:"tracker",
                    cur:"—", group:ZH[a.category] || "跨资产 其他",
                    detail:{ kind:"tracker", symbol:a.symbol } });
      });

      var shardCache = {};                      /* 片号 → 取数结果，取过就不再取 */
      function companySeries(it) {
        var shard = it.shard > 1 ? it.shard : 1;
        var key = "s" + shard;
        if (!shardCache[key]) shardCache[key] = soft(C.shardPath("companies/history.json", shard));
        return shardCache[key].then(function (f) {
          if (!f || f.__error) return { tk:it.tk, name:it.name, cur:it.cur, dates:[], values:[],
                                        note:"第 " + shard + " 片收盘历史没取回（" + ((f && f.__error) || "未加载") + "）" };
          var ser = (f.series || {})[it.tk];
          if (!ser) return { tk:it.tk, name:it.name, cur:it.cur, dates:[], values:[],
                             note:"站内第 " + shard + " 片里没有这条序列" };
          return { tk:it.tk, name:it.name, cur:it.cur, dates:f.dates || [], values:ser, note:"" };
        });
      }
      function trackerSeries(it) {
        if (!aHist) return Promise.resolve({ tk:it.tk, name:it.name, cur:it.cur, dates:[], values:[],
                                             note:"跨资产历史没取回" });
        var ser = (aHist.series || {})[it.tk];
        return Promise.resolve(ser
          ? { tk:it.tk, name:it.name, cur:it.cur, dates:aHist.dates || [], values:ser, note:"" }
          : { tk:it.tk, name:it.name, cur:it.cur, dates:[], values:[], note:"跨资产历史里没有这条序列" });
      }
      /* 取一组标的的序列。公司按需补片，跨资产直接从已加载的单文件里取。 */
      function seriesFor(list) {
        return Promise.all((list || []).map(function (it) {
          return it.kind === "company" ? companySeries(it) : trackerSeries(it);
        }));
      }

      return {
        pool: pool,
        byTk: function (tk) { return pool.filter(function (p) { return p.tk === tk; })[0] || null; },
        seriesFor: seriesFor,
        /* 「能选哪些标的」本身也会退化：标的表取不到，那一类就整类从选择器里消失。
           所以标的表与历史序列分开报，页面才能说清少了哪一类、少了多少。 */
        counts: { company: pool.filter(function (p) { return p.kind === "company"; }).length,
                  tracker: pool.filter(function (p) { return p.kind === "tracker"; }).length },
        src: {
          comp: meta("公司榜收盘历史", cd, "日频收盘"),
          compList: meta("公司榜标的表", cd, "日频"),
          asset: meta("跨资产收盘历史", ah, (aHist && aHist.points ? aHist.points + " 个交易日" : "日频")),
          assetList: meta("跨资产标的表", ad, "日频")
        },
        err: { comp: cd && cd.__error, asset: ah && ah.__error, assetList: ad && ad.__error }
      };
    });
  }

  global.OOGLEX_SECURITY = {
    loadSecurity: loadSecurity, loadTrends: loadTrends, loadCompare: loadCompare,
    fmt: fmt, isNum: isNum, srcLine: C.srcLine,
    UNAVAILABLE: C.UNAVAILABLE, UNAVAILABLE_NOTE: C.UNAVAILABLE_NOTE
  };
})(window);
