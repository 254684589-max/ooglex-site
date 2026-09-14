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

  /* ── 13F 反查：站内收录的机构里，谁持有这只票 ──────────────────────────
     覆盖面必须说清楚，否则会被读成完整 13F：
       · 站内每家只收录**前 10 大持仓**（外加 8 条变动），主权基金同样前 10；
       · 实测 564 条仓位里 261 条没有解析出代码（Chubb、Western Digital、
         ETF 看跌期权等），按代码反查只能覆盖到有代码的那些；
       · 这 59 家自己申报的总仓位是 47832 条 —— 站内这点是零头。
     所以页面必须写明：**这里没出现，不等于没持有。**
     再加上 13F 本身的口径（来自数据源的 note）：季度披露、最长滞后 45 天、
     只有美股多头，不含空头、债券与海外持仓。 */
  function loadOwners() {
    return soft("superinvestors/data.json").then(function (d) {
      if (!d || d.__error) {
        return { ok:false, error:(d && d.__error) || "未加载", byTk:function () { return null; },
                 src: meta("机构持仓 13F", d, "季度") };
      }
      var idx = {}, rows = 0, noTk = 0, firms = 0;
      function absorb(list, kind) {
        (list || []).forEach(function (inv) {
          firms++;
          (inv.holdings || []).forEach(function (h) {
            rows++;
            if (!h.ticker) { noTk++; return; }
            var k = String(h.ticker).toUpperCase();
            (idx[k] = idx[k] || []).push({
              firm: inv.firmZh || inv.firm, firmEn: inv.firm, kind: kind,
              period: inv.period, filed: inv.filed,
              name: h.name, zh: h.zh, value: h.value, pct: h.pct,
              chg: h.chg, chgPct: h.chgPct,
              stocks: inv.stocks, total: inv.value
            });
          });
        });
      }
      absorb(d.investors, "机构");
      absorb(d.swfs, "主权基金");
      var declared = (d.investors || []).reduce(function (a, i) { return a + (i.stocks || 0); }, 0);
      return {
        ok: true,
        byTk: function (tk) {
          var v = idx[String(tk || "").toUpperCase()];
          return v && v.length ? v.slice().sort(function (a, b) { return (b.pct || 0) - (a.pct || 0); }) : null;
        },
        stats: { firms: firms, tickers: Object.keys(idx).length, rows: rows,
                 withTk: rows - noTk, noTk: noTk, declared: declared },
        topOwned: d.topOwned || [],
        note: d.note || "",
        src: meta("机构持仓 13F", d, "季度披露 · 最长滞后 45 天")
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
      /* 月线：形状与日线不同（{start,closes} 而不是共享日期轴），
         公司同样按片存放；跨资产月线是单文件。按需取，取过不再取。 */
      var monCache = {}, assetMon = null;
      function companyMonthly(it) {
        var shard = it.shard > 1 ? it.shard : 1;
        var key = "m" + shard;
        if (!monCache[key]) monCache[key] = soft(C.shardPath("companies/history-monthly.json", shard));
        return monCache[key].then(function (f) {
          if (!f || f.__error) return { tk:it.tk, name:it.name, months:[], closes:[],
                                        note:"第 " + shard + " 片月线读取失败（" + ((f && f.__error) || "未加载") + "）" };
          var e = (f.series || {})[it.tk];
          if (!e) return { tk:it.tk, name:it.name, months:[], closes:[],
                           note:"站内第 " + shard + " 片月线里没有这条序列" };
          var ms = C.monthlySeries(e);
          return { tk:it.tk, name:it.name, months:ms.months, closes:ms.closes, note:"" };
        });
      }
      function trackerMonthly(it) {
        if (!assetMon) assetMon = soft("asset-tracker/history-monthly.json");
        return assetMon.then(function (f) {
          if (!f || f.__error) return { tk:it.tk, name:it.name, months:[], closes:[],
                                        note:"跨资产月线读取失败（" + ((f && f.__error) || "未加载") + "）" };
          var e = (f.series || {})[it.tk];
          if (!e) return { tk:it.tk, name:it.name, months:[], closes:[],
                           note:"跨资产月线里没有这条序列" };
          var ms = C.monthlySeries(e);
          return { tk:it.tk, name:it.name, months:ms.months, closes:ms.closes, note:"" };
        });
      }
      function monthlyFor(list) {
        return Promise.all((list || []).map(function (it) {
          return it.kind === "company" ? companyMonthly(it) : trackerMonthly(it);
        }));
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
        seriesFor: seriesFor, monthlyFor: monthlyFor,
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

  /* ── 基本面：把 fundamentals.json 与公司榜按代码接起来 ────────────────────
     口径全部随数据一起来（method / periodsUsed / note），这里只做连接与汇总，
     不在页面里另立一套。三件事必须一路带到页面上：

       1. **两个日期**：statementEnd（报表期末）与 priceAsOf（价格日期）。
          PE/PB/PS 是「今天的价格 ÷ 上一期报表」，只标一个日期会被读成当期值。
       2. **利润表与资产负债表可能不是同一财年**（periodsUsed 里看得见）。
          所以 ROE 的分母是「同财年末权益」、PB 的分母是「最新一期权益」——
          两者口径不同，页面逐条写明，不含糊成一句「股东权益」。
       3. **分母非正不给比率**：负权益的 PB、负 EPS 的 PE 不是「便宜」。
          这些行的比率是 null，不是 0，页面按「不适用」显示并给出原因。 */
  var PEER_MIN = 5;          /* 少于 5 家不给同业中位 —— 一两家决定不了「同业」 */

  function median(list) {
    var s = list.slice().sort(function (a, b) { return a - b; });
    if (!s.length) return null;
    return s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2;
  }

  var RATIOS = ["pe", "pb", "ps", "roe", "netMargin", "debtToAssets"];

  function loadFundamentals() {
    return Promise.all([
      soft("companies/data.json"),
      soft("companies/fundamentals.json")
    ]).then(function (r) {
      var cd = r[0], fd = r[1];
      var out = { rows: [], err: {}, src: {}, method: null, periodsUsed: null,
                  note: null, asOf: null, updatedAt: null, source: null, sourceUrl: null,
                  dataQuality: null, counts: {}, sectors: [], countries: [], peer: {} };
      if (!cd || cd.__error) { out.err.companies = (cd && cd.__error) || "读取失败"; return out; }
      if (!fd || fd.__error) { out.err.fund = (fd && fd.__error) || "读取失败"; return out; }

      var byc = {};
      (cd.companies || []).forEach(function (c) { if (c.symbol) byc[c.symbol] = c; });

      out.method = fd.method || null;
      out.periodsUsed = fd.periodsUsed || null;
      out.note = fd.note || null;
      out.asOf = fd.asOf || null;
      out.updatedAt = fd.updatedAt || null;
      out.source = fd.source || null;
      out.sourceUrl = fd.sourceUrl || null;
      out.dataQuality = fd.dataQuality || null;
      out.src.fund = C.srcLine(C.meta("基本面（报表项现算）", fd, "季/年频"));
      out.src.comp = C.srcLine(C.meta("价格与市值", cd, "日频收盘"));

      (fd.rows || []).forEach(function (f) {
        var c = byc[f.symbol] || {};
        var row = {
          tk: f.symbol, name: c.name || f.symbol, nameEn: c.nameEn || "",
          sector: c.sector || "未标注", country: c.country || "未标注",
          price: c.price, priceCur: c.priceCur || "USD", marketCap: c.marketCap,
          available: !!f.available, reason: f.reason || "",
          statementEnd: f.statementEnd || null, priceAsOf: f.priceAsOf || null,
          raw: f.raw || {}, meta: f.dataMeta || {},
          detail: { kind: "company", symbol: f.symbol }
        };
        RATIOS.forEach(function (k) { row[k] = isNum(f[k]) ? f[k] : null; });
        out.rows.push(row);
      });

      /* 覆盖面逐项统计 —— 「有多少家能算」本身就是要显示的事实 */
      out.counts.total = out.rows.length;
      out.counts.available = out.rows.filter(function (x) { return x.available; }).length;
      out.counts.unavailable = out.counts.total - out.counts.available;
      RATIOS.forEach(function (k) {
        out.counts[k] = out.rows.filter(function (x) { return x[k] !== null; }).length;
      });
      /* 分母非正而被拒的行：可核的原因，不是「没数据」 */
      out.counts.negEps = out.rows.filter(function (x) {
        return x.available && isNum(x.raw.epsDiluted) && x.raw.epsDiluted <= 0;
      }).length;
      out.counts.negEquity = out.rows.filter(function (x) {
        return x.available && isNum(x.raw.equity) && x.raw.equity <= 0;
      }).length;

      var seenS = {}, seenC = {};
      out.rows.forEach(function (x) {
        if (!x.available) return;
        seenS[x.sector] = (seenS[x.sector] || 0) + 1;
        seenC[x.country] = (seenC[x.country] || 0) + 1;
      });
      out.sectors = Object.keys(seenS).sort(function (a, b) { return seenS[b] - seenS[a]; })
        .map(function (s) { return { name: s, n: seenS[s] }; });
      out.countries = Object.keys(seenC).sort(function (a, b) { return seenC[b] - seenC[a]; })
        .map(function (s) { return { name: s, n: seenC[s] }; });

      /* 板块中位：同业对比的基准。样本不足 PEER_MIN 就不给，并记下为什么不给。 */
      out.sectors.forEach(function (s) {
        var box = { n: s.n, need: PEER_MIN };
        RATIOS.forEach(function (k) {
          var vals = out.rows.filter(function (x) {
            return x.available && x.sector === s.name && x[k] !== null;
          }).map(function (x) { return x[k]; });
          box[k] = vals.length >= PEER_MIN ? median(vals) : null;
          box[k + "_n"] = vals.length;
        });
        out.peer[s.name] = box;
      });
      out.peerAll = (function () {
        var box = { n: out.counts.available, need: PEER_MIN };
        RATIOS.forEach(function (k) {
          var vals = out.rows.filter(function (x) { return x[k] !== null; }).map(function (x) { return x[k]; });
          box[k] = vals.length >= PEER_MIN ? median(vals) : null;
          box[k + "_n"] = vals.length;
        });
        return box;
      })();
      return out;
    });
  }

  global.OOGLEX_SECURITY = {
    loadSecurity: loadSecurity, loadTrends: loadTrends, loadCompare: loadCompare,
    loadOwners: loadOwners, loadFundamentals: loadFundamentals,
    RATIOS: RATIOS, PEER_MIN: PEER_MIN, median: median,
    fmt: fmt, isNum: isNum, srcLine: C.srcLine,
    UNAVAILABLE: C.UNAVAILABLE, UNAVAILABLE_NOTE: C.UNAVAILABLE_NOTE
  };
})(window);
