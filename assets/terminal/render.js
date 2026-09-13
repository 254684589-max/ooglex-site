/* ===========================================================================
   OOGLEX 终端渲染器 · Renderers
   ---------------------------------------------------------------------------
   把 overview.js / security.js 的模型渲染进 terminal.css 的组件里。
   三个页型（监控 / 证券描述 / 榜单趋势）共用同一套渲染器，所以数字口径必然
   一致 —— 改一处口径三页同时生效。

   每个渲染器只依赖：一个模型 + 一组目标选择器，不关心页面布局。
   格式化、出处行、阈值、转义全部来自 core.js。
   =========================================================================== */
(function (global) {
  "use strict";
  var C = global.OOGLEX_CORE;
  var fmt = C.fmt, isNum = C.isNum, esc = C.esc, srcLine = C.srcLine;

  function $(s, r) { return (r || document).querySelector(s); }
  function $$(s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); }
  function set(sel, text) { var e = $(sel); if (e) e.textContent = text; }
  function html(sel, h) { var e = $(sel); if (e) e.innerHTML = h; }

  function cell(v, cls) { return '<td class="' + (cls || "") + '">' + v + "</td>"; }

  /* 名称格：有真实详情页就做成链接，没有就保持纯文本。
     detail 由模型层附上（模型才知道这一行是什么品种），地址由 core.detailHref 产出。
     拿不到详情页的行不给死链，也不给假的手型光标。 */
  function nameCell(inner, detail, title) {
    var href = C.detailHref(detail);
    if (!href) return inner;
    return '<a class="t-go" href="' + href + '" title="' + esc(title || "打开走势详情") + '">' + inner + "</a>";
  }
  function pctCell(p, extraCls, dp) {
    return '<td class="' + (extraCls ? extraCls + " " : "") + fmt.cls(p) + '">' + fmt.pct(p, dp) + "</td>";
  }
  function sigTag(s) { return '<span class="t-sig ' + s.k + '">' + s.label + "</span>"; }

  /* 绝对变动：盘中有前收就相减；只有收盘价与日涨跌幅时由两者反解（可复现） */
  function absChg(q) {
    if (q.intraday && isNum(q.intraday.price) && isNum(q.intraday.prevClose)) return q.intraday.price - q.intraday.prevClose;
    if (isNum(q.close) && isNum(q.d1)) return q.close - q.close / (1 + q.d1 / 100);
    return null;
  }
  function lastPx(q) { return q.intraday && isNum(q.intraday.price) ? q.intraday.price : q.close; }
  function lastPct(q) { return q.intraday && isNum(q.intraday.changePct) ? q.intraday.changePct : q.d1; }


  /* ── 报价表 ─────────────────────────────────────────────────────────────
     cols 支持：last chg pct w1 w1pro m1 ytd y1 mcap；按传入顺序出列。
     带 pro 后缀的列只在专业模式下出现（t-col-pro t-hide）。 */
  function quoteTable(sel, list, cols) {
    var body = $(sel + " tbody");
    if (!body) return;
    cols = cols || ["last", "chg", "pct", "w1", "m1", "ytd"];
    var rows = list.filter(function (q) { return !q.missing; }).map(function (q) {
      var tds = cols.map(function (c) {
        if (c === "last") return cell(fmt.px(lastPx(q)) +
          (q.cur && q.cur !== "USD" ? '<span class="t-cur">' + esc(q.cur) + "</span>" : ""), "t-last");
        if (c === "chg") { var a = absChg(q); return cell(fmt.chg(a), fmt.cls(a)); }
        if (c === "pct") return pctCell(lastPct(q));
        if (c === "w1") return pctCell(q.w1, "t-col-x");
        if (c === "w1pro") return pctCell(q.w1, "t-col-pro t-hide");
        if (c === "m1") return pctCell(q.m1, "t-col-x");
        if (c === "ytd") return pctCell(q.ytd);
        if (c === "y1") return pctCell(q.y1, "t-col-pro t-hide");
        if (c === "mcap") return cell(isNum(q.marketCap) ? fmt.px(q.marketCap) : "—");
        return cell("—", "t-na");
      }).join("");
      var marks = (q.note ? "<sup>*</sup>" : "") + (q.proxy ? "<sup>P</sup>" : "");
      var inner = '<span class="t-tk">' + esc(q.tk) + '</span><span class="t-nm">' + esc(q.name) + marks + "</span>";
      return '<tr data-tk="' + esc(q.tk) + '" data-nm="' + esc(q.name) + '">' +
        "<td>" + nameCell(inner, q.detail, "打开 " + q.tk + " 的走势详情") + "</td>" +
        tds + "</tr>";
    }).join("");
    body.innerHTML = rows || '<tr><td colspan="9" style="text-align:left" class="t-flat">无可用标的</td></tr>';
  }

  /* ── 收益率曲线 ───────────────────────────────────────────────────────── */
  function curve(sel, tenors, opt) {
    opt = opt || {};
    var svg = $(sel);
    var t = (tenors || []).filter(function (x) { return isNum(x.value); });
    if (!svg || t.length < 3) return;
    var W = opt.w || 460, H = opt.h || 190, L = opt.l || 34, R = opt.r || 8, T = opt.t || 10, B = opt.b || 20;
    svg.setAttribute("viewBox", "0 0 " + W + " " + H);
    svg.innerHTML = "";
    var lo = Math.min.apply(null, t.map(function (x) { return x.value; }));
    var hi = Math.max.apply(null, t.map(function (x) { return x.value; }));
    var pad = (hi - lo) * .25 || .2; lo -= pad; hi += pad;
    function X(i) { return L + (W - L - R) * i / (t.length - 1); }
    function Y(v) { return T + (H - T - B) * (hi - v) / (hi - lo); }
    var ns = "http://www.w3.org/2000/svg";
    function add(tag, at, txt) {
      var e = document.createElementNS(ns, tag);
      Object.keys(at).forEach(function (k) { e.setAttribute(k, at[k]); });
      if (txt != null) e.textContent = txt;
      svg.appendChild(e);
    }
    [0, .5, 1].forEach(function (f) {
      var v = lo + (hi - lo) * f;
      add("line", { x1:L, y1:Y(v), x2:W - R, y2:Y(v), stroke:"#1f1f1f", "stroke-width":1 });
      add("text", { x:2, y:Y(v) + 3, fill:"#5e5e5e", "font-size":8.5, "font-family":"monospace" }, v.toFixed(2));
    });
    add("polyline", { points:t.map(function (x, i) { return X(i) + "," + Y(x.value); }).join(" "),
                      fill:"none", stroke:"#ffa028", "stroke-width":opt.thin ? 1.1 : 1.4 });
    var every = opt.labelEvery || 1;
    t.forEach(function (x, i) {
      add("circle", { cx:X(i), cy:Y(x.value), r:opt.thin ? 1.3 : 1.7, fill:"#ffd24a" });
      var isLast = i === t.length - 1;
      if (i % every === 0 || isLast) {
        add("text", { x:Math.min(X(i), W - R - 6), y:H - 5, fill:"#5e5e5e", "font-size":8.5,
                      "font-family":"monospace", "text-anchor": isLast ? "end" : "middle" }, x.label);
      }
    });
  }

  function spreadLegend(sel, spreads) {
    html(sel, (spreads || []).map(function (s) {
      var c = s.inverted ? "var(--t-dn)" : "var(--t-up)";
      return "<span>" + esc(s.id) + ' <b style="color:' + c + '">' + (isNum(s.value) ? fmt.z(s.value) : "—") +
        "</b>" + (s.inverted ? " INV" : "") + (s.derived ? " ·计算" : "") + "</span>";
    }).join(""));
  }
  function spreadTable(sel, spreads) {
    var body = $(sel + " tbody");
    if (!body) return;
    body.innerHTML = (spreads || []).map(function (s) {
      return "<tr><td>" + esc(s.id) + (s.derived ? '<span class="t-nm">由曲线计算</span>' : "") + "</td>" +
        cell(isNum(s.value) ? fmt.z(s.value) : "—", s.inverted ? "t-dn" : "t-up") +
        "<td>" + sigTag(s.inverted ? { k:"risk", label:"INVERTED" } : { k:"normal", label:"NORMAL" }) + "</td></tr>";
    }).join("");
  }

  /* ── 利率表（关键期限）───────────────────────────────────────────────── */
  function ratesTable(sel, rates, labels) {
    var body = $(sel + " tbody");
    if (!body) return;
    if (rates.error) {
      body.innerHTML = '<tr><td colspan="3" class="t-dn" style="text-align:left">曲线数据读取失败</td></tr>';
      return;
    }
    var want = labels || ["2Y", "5Y", "10Y", "30Y"];
    body.innerHTML = rates.tenors.filter(function (t) { return want.indexOf(t.label) >= 0; }).map(function (t) {
      return '<tr data-tk="US' + esc(t.label) + '" data-nm="' + esc(t.label) + '期美债">' +
        "<td>" + nameCell('<span class="t-tk">US' + esc(t.label) + "</span>", t.detail,
          "打开 " + t.label + " 期美债收益率的走势详情") + "</td>" +
        cell(t.value.toFixed(2) + "%", "t-last") +
        '<td class="t-col-x t-flat">' + esc(t.asOf || rates.asOf || "—") + "</td></tr>";
    }).join("");
  }

  /* ── 宏观 / 风险监测表（规范第五节）───────────────────────────────────── */
  var MONITOR_ROWS = [
    ["MOVE", "MOVE", "债券波动率"],
    ["VIX", "VIX", "股指波动率"],
    ["BAMLH0A0HYM2", "HY OAS", "高收益债 OAS"],
    ["BAMLC0A0CM", "IG OAS", "投资级债 OAS"],
    ["SOFR", "SOFR", "担保隔夜融资利率"],
    ["WTREGEN", "TGA", "财政部一般账户"],
    ["RRPONTSYD", "RRP", "隔夜逆回购用量"],
    ["NFCI", "NFCI", "芝加哥联储金融状况"],
    ["T10Y2Y", "2s10s", "10Y−2Y 期限利差"]
  ];
  function macroMonitor(sel, M) {
    var body = $(sel + " tbody");
    if (!body) return;
    var rows = [];
    rows.push('<tr class="t-grp"><td colspan="6">风险信号 · 0–100 相对分位（滚动 2 年）· 点名称看历史分位</td></tr>');
    /* 8 条合成信号没有单指标行情页，但站内有它们的分位历史序列。
       能画的就做成按钮，就地展开；画不出的保持纯文本 —— 不放点了没反应的假链接。 */
    var sh = M.macro.signalHist;
    function sigCell(s) {
      var inner = '<span class="t-tk">' + esc(String(s.en || s.key).toUpperCase()) + '</span>' +
                  '<span class="t-nm">' + esc(s.name) + "</span>";
      var ser = sh && sh.series ? sh.series[s.key] : null;
      var n = ser ? ser.filter(isNum).length : 0;
      if (n < 5) return inner;
      return '<button type="button" class="t-go" data-sig="' + esc(s.key) + '" aria-expanded="false"' +
             ' title="就地展开 ' + esc(s.name) + ' 的历史分位（' + n + ' 点）">' + inner + "</button>";
    }
    (M.macro.signals || []).forEach(function (s) {
      rows.push('<tr data-tk="' + esc(String(s.key).toUpperCase()) + '" data-nm="' + esc(s.name) + '">' +
        "<td>" + sigCell(s) + "</td>" +
        cell(isNum(s.score) ? s.score : "—", "t-last") +
        '<td class="t-flat">—</td>' +
        '<td class="t-col-x ' + fmt.cls(s.w1) + '">' + (isNum(s.w1) ? fmt.z(s.w1) : "—") + "</td>" +
        cell(isNum(s.score) ? s.score + "%ile" : "—") +
        "<td>" + sigTag(s.signal) + "</td></tr>");
    });
    /* 这两条有真实详情页：10 年期走美债曲线的 DGS10，美元指数走宏观 referenceSeries
       的 DTWEXBGS（站内 referenceSeries 只有 DTWEXBGS 与 RWTC 两个键）。 */
    var Z_DETAIL = { "US10Y": { kind:"curve", symbol:"DGS10" },
                     "DXY-FED": { kind:"macro", symbol:"DTWEXBGS" } };
    [["US10Y", "10 年期美债收益率"], ["DXY-FED", "美联储广义美元指数"]].forEach(function (p) {
      var z = M.z[p[0]];
      if (!z) return;
      var zi = '<span class="t-tk">' + esc(p[0]) + '</span><span class="t-nm">' + esc(p[1]) + "</span>";
      rows.push('<tr data-tk="' + esc(p[0]) + '" data-nm="' + esc(p[1]) + '">' +
        "<td>" + nameCell(zi, Z_DETAIL[p[0]], "打开 " + p[1] + " 的走势详情") + "</td>" +
        cell(fmt.px(z.last), "t-last") + '<td class="t-flat">—</td><td class="t-col-x t-flat">—</td>' +
        cell("Z " + fmt.z(z.z)) + "<td>" + sigTag(z.signal) + "</td></tr>");
    });
    rows.push('<tr class="t-grp"><td colspan="6">监测指标 · 仅现值与日变动（站内无历史序列，不给分位与判定）</td></tr>');
    var mi = M.macro.index || {};
    MONITOR_ROWS.forEach(function (def) {
      var r = mi[def[0]] || mi["名:" + def[0]];
      if (!r) return;
      var tone = String(r.tone) === "up" ? "t-up" : String(r.tone) === "down" ? "t-dn" : "t-flat";
      rows.push('<tr data-tk="' + esc(def[1]) + '" data-nm="' + esc(def[2]) + '">' +
        '<td><span class="t-tk">' + esc(def[1]) + '</span><span class="t-nm">' + esc(def[2]) + "</span></td>" +
        cell(esc(r.val), "t-last") + '<td class="' + tone + '">' + esc(r.chg || "—") + "</td>" +
        '<td class="t-col-x t-flat">—</td><td class="t-na">—</td><td>' + sigTag({ k:"na", label:"—" }) + "</td></tr>");
    });
    body.innerHTML = rows.join("");
  }
  var MONITOR_METHOD = "判定阈值：分位 <35 STRESS / <48 RISK / <58 WATCH / ≥58 NORMAL；" +
    "Z-Score |z|≥2 STRESS / ≥1.5 RISK / ≥1 WATCH（Z 由站内原始日序列现算，窗口见括号）";

  /* ── 宏观分组表：直接呈现 macro-radar 的官方序列分组（现值 + 日变动 + 数据日期）── */
  function macroBlock(sel, M, groups) {
    var body = $(sel + " tbody");
    if (!body) return;
    var blocks = (M.macro.tables || []).filter(function (b) {
      return !groups || groups.indexOf(b.zh) >= 0;
    });
    if (!blocks.length) { body.innerHTML = '<tr><td colspan="4" style="text-align:left" class="t-flat">无可用分组</td></tr>'; return; }
    body.innerHTML = blocks.map(function (b) {
      var rows = (b.rows || []).map(function (r) {
        var tone = String(r.tone) === "up" ? "t-up" : String(r.tone) === "down" ? "t-dn" : "t-flat";
        return '<tr data-tk="' + esc(r.id || "") + '" data-nm="' + esc(r.name || "") + '">' +
          "<td>" + esc(r.name || "") + (r.id ? '<span class="t-nm">' + esc(r.id) + "</span>" : "") + "</td>" +
          cell(esc(r.val), "t-last") +
          '<td class="' + tone + '">' + esc(r.chg || "—") + "</td>" +
          '<td class="t-col-x t-flat">' + esc(r.asOf || "—") + "</td></tr>";
      }).join("");
      return '<tr class="t-grp"><td colspan="4">' + esc(b.zh) + " · " + esc(b.src || "") + "</td></tr>" + rows;
    }).join("");
  }

  /* ── 跨资产强弱条 ─────────────────────────────────────────────────────── */
  function crossBars(sel, M, n) {
    var host = $(sel);
    if (!host) return;
    var pool = M.markets.indices.concat(M.markets.commodities, M.markets.fx, M.markets.credit)
      .filter(function (q) { return !q.missing && isNum(q.ytd); })
      .sort(function (a, b) { return b.ytd - a.ytd; });
    var k = n || 6;
    var top = pool.length > k * 2 ? pool.slice(0, k).concat(pool.slice(-k)) : pool;
    var mx = Math.max.apply(null, top.map(function (q) { return Math.abs(q.ytd); })) || 1;
    host.innerHTML = top.map(function (q) {
      var w = Math.abs(q.ytd) / mx * 50, left = q.ytd >= 0 ? 50 : 50 - w;
      var nm = nameCell(esc(q.name), q.detail, "打开 " + q.tk + " 的走势详情");
      return '<div class="r" data-tk="' + esc(q.tk) + '" data-nm="' + esc(q.name) + '"><span class="nm">' + nm + "</span>" +
        '<span class="tr"><span class="z" style="left:50%"></span><i style="left:' + left + "%;width:" + w +
        "%;background:" + (q.ytd >= 0 ? "var(--t-up)" : "var(--t-dn)") + '"></i></span>' +
        '<span class="vv ' + fmt.cls(q.ytd) + '">' + fmt.pct(q.ytd, 1) + "</span></div>";
    }).join("") +
      '<div class="t-ax" style="padding-top:4px"><span>−' + mx.toFixed(0) + "%</span><span>0</span><span>+" + mx.toFixed(0) + "%</span></div>";
  }

  /* ── 经济日历 ─────────────────────────────────────────────────────────── */
  function calendar(sel, M, limit) {
    var host = $(sel);
    if (!host) return;
    if (!M.calendar) { host.innerHTML = '<li><span class="tx t-dn">日历数据读取失败</span></li>'; return; }
    var now = Date.now();
    var ev = (M.calendar.events || []).filter(function (e) { return e.impact === "high" || e.impact === "medium"; })
      .sort(function (a, b) { return new Date(a.ts) - new Date(b.ts); });
    var fut = ev.filter(function (e) { return new Date(e.ts).getTime() >= now; });
    var past = ev.filter(function (e) { return new Date(e.ts).getTime() < now; }).reverse();
    var use = fut.slice(0, 5);
    while (use.length < (limit || 12) && past.length) use.push(past.shift());
    use.sort(function (a, b) { return new Date(a.ts) - new Date(b.ts); });
    function p2(n) { return n < 10 ? "0" + n : n; }
    host.innerHTML = use.map(function (e) {
      var d = new Date(e.ts);
      var tm = (d.getUTCMonth() + 1) + "-" + p2(d.getUTCDate()) + " " + p2(d.getUTCHours()) + ":" + p2(d.getUTCMinutes());
      var done = !!e.actual;
      return '<li><span class="tm">' + tm + '</span><span class="imp ' + (e.impact === "high" ? "h" : "m") + '"></span>' +
        '<span class="tx">' + esc((e.ccy ? e.ccy + " " : "") + (e.title || "")) + "</span>" +
        '<span class="vv" style="color:' + (done ? "var(--t-yellow)" : "var(--t-faint)") + '">' +
        esc(done ? "A " + e.actual : (e.forecast ? "F " + e.forecast : "待公布")) + "</span></li>";
    }).join("") || '<li><span class="tx">本周无高/中影响事件</span></li>';
  }

  /* ── 要闻 ─────────────────────────────────────────────────────────────── */
  function news(sel, M, limit) {
    var host = $(sel);
    if (!host) return;
    if (!M.news) { host.innerHTML = '<li><span class="tx t-dn">要闻读取失败</span></li>'; return; }
    var items = [];
    (M.news.categories || []).forEach(function (c) {
      (c.items || []).slice(0, 3).forEach(function (it) { items.push({ cat:c.name, it:it }); });
    });
    function p2(n) { return n < 10 ? "0" + n : n; }
    host.innerHTML = items.slice(0, limit || 10).map(function (x) {
      var t = x.it.published ? new Date(x.it.published * 1000) : null;
      var tm = t ? p2(t.getUTCHours()) + ":" + p2(t.getUTCMinutes()) + "Z" : "—";
      /* 没有原文地址就不做成链接 —— href="#" 点了原地不动，比纯文本更糟。
         地址来自外部源，只收 http(s)，别的协议一律当没有。 */
      var u = String(x.it.link || "");
      var tx = /^https?:\/\//i.test(u)
        ? '<a href="' + esc(u) + '" target="_blank" rel="noopener">' + esc(x.it.title || "") + "</a>"
        : esc(x.it.title || "");
      return '<li><span class="tm">' + tm + '</span><span class="tx">' + tx + '</span><span class="src">' +
        esc(x.it.source || "") + "</span></li>";
    }).join("") || '<li><span class="tx">暂无要闻</span></li>';
  }

  /* ── 风险提示（宏观异动）─────────────────────────────────────────────── */
  function alerts(sel, M) {
    var host = $(sel);
    if (!host) return;
    var muts = (M.macro && M.macro.mutations) || [];
    host.innerHTML = muts.map(function (m) {
      var k = m.status === "red" ? "h" : m.status === "green" ? "l" : "m";
      var lab = m.status === "red" ? "TIGHTEN" : m.status === "green" ? "EASE" : "NEUTRAL";
      return '<li><span class="imp ' + k + '"></span><span class="tx" style="white-space:normal">' +
        '<span class="t-tk">' + esc(m.sig || "") + "</span> " + esc(m.text || "") + "</span>" +
        '<span class="vv t-flat">' + lab + "</span></li>";
    }).join("") || '<li><span class="tx">今日无显著异动</span></li>';
  }

  /* ── 数据来源与状态表 ─────────────────────────────────────────────────── */
  function sources(sel, M) {
    var body = $(sel + " tbody");
    if (!body) return;
    body.innerHTML = M.meta.sources.map(function (s) {
      var ok = !s.error && (s.status === "ok" || s.status === undefined);
      return "<tr><td>" + esc(s.label) + '<span class="t-nm">' + esc(s.source || "") + " · " +
        esc(s.cadence || s.frequency || "—") + "</span></td>" +
        '<td class="t-rownum">' + esc(s.asOf || "—") + "</td>" +
        "<td>" + sigTag(s.error ? { k:"stress", label:"FAIL" } : ok ? { k:"normal", label:"OK" }
          : { k:"watch", label:String(fmt.statusZh(s.status)).toUpperCase() }) + "</td></tr>";
    }).join("");
  }

  /* ── 自选表（本地保存）───────────────────────────────────────────────── */
  function watchlist(opt) {
    var KEY = opt.key || "ooglex.terminal.watchlist";
    var M = opt.model;
    var pool = {};
    ["indices", "fx", "commodities", "credit"].forEach(function (g) {
      (M.markets[g] || []).forEach(function (q) { if (!q.missing) pool[q.tk] = q; });
    });
    (M.markets.crypto || []).forEach(function (c) {
      pool[c.tk] = { tk:c.tk, name:c.name, close:c.close, d1:c.d1, ytd:null, detail:c.detail };
    });
    (M.rates.tenors || []).forEach(function (t) {
      pool["US" + t.label] = { tk:"US" + t.label, name:t.label + "期美债收益率",
                               close:t.value, d1:null, ytd:null, detail:t.detail };
    });
    (M.markets.stocks || []).forEach(function (q) { if (!pool[q.tk]) pool[q.tk] = q; });

    function read() {
      try {
        var v = JSON.parse(localStorage.getItem(KEY) || "null");
        return Array.isArray(v) ? v : (opt.defaults || ["SPX", "US10Y", "DXY", "CL", "XAU"]);
      } catch (e) { return opt.defaults || ["SPX", "DXY", "XAU"]; }
    }
    function write(l) { try { localStorage.setItem(KEY, JSON.stringify(l)); } catch (e) {} }
    function render() {
      var list = read();
      html(opt.table + " tbody", list.map(function (tk) {
        var q = pool[tk];
        if (!q) {
          return "<tr><td><span class='t-tk'>" + esc(tk) + "</span><span class='t-nm'>未匹配</span></td>" +
            '<td class="t-na">—</td><td class="t-na">—</td><td class="t-na">—</td>' +
            '<td><button class="wl-del" data-del="' + esc(tk) + '" title="移出自选">×</button></td></tr>';
        }
        var wi = '<span class="t-tk">' + esc(q.tk) + '</span><span class="t-nm">' + esc(q.name) + "</span>";
        return '<tr data-tk="' + esc(q.tk) + '" data-nm="' + esc(q.name) + '">' +
          "<td>" + nameCell(wi, q.detail, "打开 " + q.tk + " 的走势详情") + "</td>" +
          cell(fmt.px(lastPx(q)), "t-last") + pctCell(lastPct(q)) + pctCell(q.ytd) +
          '<td><button class="wl-del" data-del="' + esc(q.tk) + '" title="移出自选">×</button></td></tr>';
      }).join("") || '<tr><td colspan="5" style="text-align:left" class="t-flat">自选表为空</td></tr>');
      if (opt.count) set(opt.count, "本地保存 · " + list.length + " 项");
    }
    function add(raw) {
      var q = String(raw || "").trim();
      if (!q) return;
      var Q = q.toUpperCase();
      var hit = Object.keys(pool).find(function (tk) { return tk === Q; }) ||
                Object.keys(pool).find(function (tk) { return (pool[tk].name || "").indexOf(q) >= 0; });
      if (!hit) { if (opt.count) set(opt.count, "未找到：" + q); return; }
      var list = read();
      if (list.indexOf(hit) < 0) list.push(hit);
      write(list); render();
      if (opt.input) $(opt.input).value = "";
    }
    if (opt.btn) $(opt.btn).addEventListener("click", function () { add($(opt.input).value); });
    if (opt.input) $(opt.input).addEventListener("keydown", function (e) {
      if (e.key === "Enter") { e.preventDefault(); add(this.value); }
    });
    var tbl = $(opt.table);
    if (tbl) tbl.addEventListener("click", function (e) {
      var b = e.target.closest("[data-del]");
      if (!b) return;
      write(read().filter(function (x) { return x !== b.getAttribute("data-del"); }));
      render();
    });
    render();
    return { render: render, add: add, pool: pool };
  }

  /* ── 顶部状态 ─────────────────────────────────────────────────────────── */
  function topStatus(M) {
    var eq = M.meta.sources[0], intra = M.meta.sources[1];
    var st = eq.error ? "读取失败" : fmt.statusZh(eq.status);
    var e = $("[data-data-status]");
    if (e) { e.textContent = st; e.style.color = st === "正常" ? "var(--t-up)" : st === "读取失败" ? "var(--t-dn)" : "var(--t-signal-watch)"; }
    set("[data-asof]", eq.asOf || "—");
    set("[data-updated]", fmt.utc(intra.updatedAt || eq.updatedAt));
    set("[data-cadence-badge]", intra.error ? "CLOSE ONLY" : "INTRADAY 30M");
    set("[data-feed-badge]", intra.error ? "DATA" : "SNAPSHOT");
    var un = $("[data-unavail]");
    if (un) un.textContent = C.UNAVAILABLE_NOTE;
  }

  /* 折线：共享日期轴上的空值处断开，绝不插值也不前向填充 */
  function priceLine(svgSel, hostSel, h, dates, opt) {
    opt = opt || {};
    var svg = typeof svgSel === "string" ? $(svgSel) : svgSel;
    var lg = hostSel ? $(hostSel) : null;
    if (!svg) return null;
    var from = opt.tail ? Math.max(0, h.length - opt.tail) : 0;
    var seg = h.slice(from), sd = dates.slice(from);
    var pts = [];
    for (var i = 0; i < seg.length; i++) if (isNum(seg[i])) pts.push({ i:i, v:seg[i], d:sd[i] });
    if (pts.length < 5) {
      svg.innerHTML = '<text x="10" y="24" fill="#8a8a8a" font-family="monospace" font-size="12">' +
        esc(opt.empty || "序列点数不足，不画图（不插值出一条假曲线）") + "</text>";
      if (lg) lg.innerHTML = "";
      return null;
    }
    var vb = (svg.getAttribute("viewBox") || "0 0 700 150").split(/\s+/);
    var W = +vb[2], H = +vb[3];
    var L = opt.l != null ? opt.l : 52, R = 10, T = 10, B = opt.b != null ? opt.b : 22;
    var lo = Math.min.apply(null, pts.map(function (p) { return p.v; }));
    var hi = Math.max.apply(null, pts.map(function (p) { return p.v; }));
    var pad = (hi - lo) * .08 || 1; lo -= pad; hi += pad;
    /* 有定义域的序列（比如 0–100 分位）不要把坐标轴垫到域外：
       轴上出现 −8 / 108 会让人以为分位能超界。 */
    if (opt.clamp) { lo = Math.max(lo, opt.clamp[0]); hi = Math.min(hi, opt.clamp[1]); }
    var n = seg.length - 1;
    function X(i) { return L + (W - L - R) * (n ? i / n : 0); }
    function Y(v) { return T + (H - T - B) * (hi - v) / (hi - lo); }
    var g = "", steps = opt.grid != null ? opt.grid : 4;
    for (var k = 0; k <= steps; k++) {
      var vv = lo + (hi - lo) * k / steps, y = Y(vv);
      g += '<line x1="' + L + '" y1="' + y.toFixed(1) + '" x2="' + (W - R) + '" y2="' + y.toFixed(1) +
           '" stroke="#1f1f1f" stroke-width="1"/><text x="' + (L - 6) + '" y="' + (y + 3.5).toFixed(1) +
           '" text-anchor="end" fill="#5e5e5e" font-family="monospace" font-size="9">' + (opt.fmtv || fmt.px)(vv) + "</text>";
    }
    var d = "", pen = false;
    for (var j = 0; j < seg.length; j++) {
      if (!isNum(seg[j])) { pen = false; continue; }
      d += (pen ? "L" : "M") + X(j).toFixed(1) + "," + Y(seg[j]).toFixed(1);
      pen = true;
    }
    var fv = opt.fmtv || fmt.px;          /* 分位/得分序列不是价格，别用价格格式和「收盘」字样 */
    var vl = opt.valLabel || "有效收盘";
    var rise = pts[pts.length - 1].v >= pts[0].v;
    var xt = "";
    var ticks = [0, Math.floor(n * .25), Math.floor(n * .5), Math.floor(n * .75), n];
    ticks.forEach(function (i, k) {
      if (!sd[i]) return;
      /* 首末两个日期贴着绘图区边缘，居中会有一半悬在框外（窄屏上就是越出视口）
         —— 两头改成内对齐，标签整体留在框内。 */
      var anchor = k === 0 ? "start" : k === ticks.length - 1 ? "end" : "middle";
      xt += '<text x="' + X(i).toFixed(1) + '" y="' + (H - 6) + '" text-anchor="' + anchor + '" fill="#5e5e5e" ' +
            'font-family="monospace" font-size="9">' + esc(sd[i]) + "</text>";
    });
    svg.innerHTML = g + '<path d="' + d + '" fill="none" stroke="' + (rise ? "#00b86b" : "#ff4d4d") +
      '" stroke-width="1.2"/>' + xt;
    var stat = {
      pts: pts, n: seg.length, lo: Math.min.apply(null, pts.map(function (p) { return p.v; })),
      hi: Math.max.apply(null, pts.map(function (p) { return p.v; })),
      first: pts[0], last: pts[pts.length - 1]
    };
    if (lg) {
      lg.innerHTML = "期间 <b>" + esc(sd[0] || "—") + " → " + esc(sd[n] || "—") +
        "</b>　" + esc(vl) + " <b>" + pts.length + " / " + seg.length +
        "</b>　区间 <b>" + fv(stat.lo) + " – " + fv(stat.hi) + "</b>　" +
        (opt.absChange
          ? "变动 <b>" + fmt.chg(stat.last.v - stat.first.v) + "</b>"
          : "变动 <b>" + fmt.pct((stat.last.v / stat.first.v - 1) * 100) + "</b>");
    }
    return stat;
  }

  /* ── 多标的叠加（归一化到 100）──────────────────────────────────────────
     身份靠「线尾直接标代码」，不靠颜色：本终端数据区的颜色只承载涨跌方向与
     风险档位，再拿它编码「这是哪条标的」就把色彩语义搞乱了。而且文档调色板里
     避开绿/红/琥珀/黄四族之后只剩两格能用（蓝与紫在色盲模拟下 ΔE 1.9 直接撞死），
     六条线本来就不可能靠颜色分开。所以：上下文线一律 --t-dim，聚焦那条抬到
     --t-cmd-line 并画在最上层，每条线尾都写代码。对比度已量：5.63:1 / 13.48:1。 */
  function multiLine(svgSel, legendSel, items, dates, opt) {
    opt = opt || {};
    var svg = typeof svgSel === "string" ? $(svgSel) : svgSel;
    var lg = legendSel ? $(legendSel) : null;
    if (!svg) return null;
    var live = (items || []).filter(function (it) { return it && it.values && it.values.filter(isNum).length >= 2; });
    if (live.length < 2) {
      svg.innerHTML = '<text x="10" y="24" fill="#8a8a8a" font-family="monospace" font-size="12">' +
        esc(opt.empty || "可比较的序列不足两条，不画图") + "</text>";
      if (lg) lg.innerHTML = "";
      return null;
    }
    var vb = (svg.getAttribute("viewBox") || "0 0 700 220").split(/\s+/);
    var W = +vb[2], H = +vb[3];
    var L = opt.l != null ? opt.l : 46, R = opt.r != null ? opt.r : 62, T = 10, B = opt.b != null ? opt.b : 24;
    var lo = Infinity, hi = -Infinity, n = 0;
    live.forEach(function (it) {
      n = Math.max(n, it.values.length);
      it.values.forEach(function (v) { if (isNum(v)) { if (v < lo) lo = v; if (v > hi) hi = v; } });
    });
    var pad = (hi - lo) * .08 || 1; lo -= pad; hi += pad;
    var span = n - 1 || 1;
    function X(i) { return L + (W - L - R) * i / span; }
    function Y(v) { return T + (H - T - B) * (hi - v) / (hi - lo); }

    /* 网格：100 那条基线单独画实线——归一化图里它是「起点」这个事实本身 */
    var g = "", steps = opt.grid != null ? opt.grid : 4;
    for (var k = 0; k <= steps; k++) {
      var vv = lo + (hi - lo) * k / steps, y = Y(vv);
      g += '<line x1="' + L + '" y1="' + y.toFixed(1) + '" x2="' + (W - R) + '" y2="' + y.toFixed(1) +
           '" stroke="#1f1f1f" stroke-width="1"/><text x="' + (L - 6) + '" y="' + (y + 3.5).toFixed(1) +
           '" text-anchor="end" fill="#5e5e5e" font-family="monospace" font-size="9">' + vv.toFixed(0) + "</text>";
    }
    if (lo < 100 && hi > 100) {
      g += '<line x1="' + L + '" y1="' + Y(100).toFixed(1) + '" x2="' + (W - R) + '" y2="' + Y(100).toFixed(1) +
           '" stroke="#3d3d3d" stroke-width="1" stroke-dasharray="3 3"/>';
    }

    function path(vals) {
      var d = "", pen = false;
      for (var j = 0; j < vals.length; j++) {
        if (!isNum(vals[j])) { pen = false; continue; }          /* 缺口断开，不插值 */
        d += (pen ? "L" : "M") + X(j).toFixed(1) + "," + Y(vals[j]).toFixed(1);
        pen = true;
      }
      return d;
    }
    /* 聚焦那条最后画，保证压在最上面 */
    var ordered = live.filter(function (it) { return !it.focus; }).concat(live.filter(function (it) { return it.focus; }));
    var lines = ordered.map(function (it) {
      return '<path d="' + path(it.values) + '" fill="none" stroke="' +
        (it.focus ? "var(--t-cmd-line)" : "var(--t-dim)") + '" stroke-width="' + (it.focus ? 1.7 : 1) + '"/>';
    }).join("");

    /* 线尾直接标代码。按末值排好后逐个往下推开，避免标签叠在一起看不清 */
    var ends = live.map(function (it) {
      var lastAt = -1;
      for (var j = it.values.length - 1; j >= 0; j--) if (isNum(it.values[j])) { lastAt = j; break; }
      return { tk: it.tk, y: Y(it.values[lastAt]), x: X(lastAt), focus: !!it.focus };
    }).sort(function (a, b) { return a.y - b.y; });
    var minGap = 10.5;
    for (var e = 1; e < ends.length; e++) {
      if (ends[e].y - ends[e - 1].y < minGap) ends[e].y = ends[e - 1].y + minGap;
    }
    var over = ends.length ? ends[ends.length - 1].y - (H - B) : 0;
    if (over > 0) ends.forEach(function (p) { p.y -= over; });      /* 整组上移，别顶出下边界 */
    var labels = ends.map(function (p) {
      return '<line x1="' + (p.x + 1).toFixed(1) + '" y1="' + p.y.toFixed(1) + '" x2="' + (W - R + 3) +
             '" y2="' + p.y.toFixed(1) + '" stroke="' + (p.focus ? "var(--t-cmd-line)" : "#2e2e2e") + '" stroke-width="1"/>' +
             '<text x="' + (W - R + 6) + '" y="' + (p.y + 3.2).toFixed(1) + '" fill="' +
             (p.focus ? "var(--t-cmd-line)" : "var(--t-ink2)") +
             '" font-family="monospace" font-size="9.5" font-weight="700">' + esc(p.tk) + "</text>";
    }).join("");

    var xt = "";
    var ticks = [0, Math.floor(span * .33), Math.floor(span * .66), span];
    ticks.forEach(function (i, ti) {
      if (!dates || !dates[i]) return;
      var anchor = ti === 0 ? "start" : ti === ticks.length - 1 ? "end" : "middle";
      xt += '<text x="' + X(i).toFixed(1) + '" y="' + (H - 6) + '" text-anchor="' + anchor +
            '" fill="#5e5e5e" font-family="monospace" font-size="9">' + esc(dates[i]) + "</text>";
    });
    svg.innerHTML = g + lines + labels + xt;

    if (lg) {
      lg.innerHTML = live.map(function (it) {
        var chg = isNum(it.last) ? it.last - 100 : null;
        return '<span><b' + (it.focus ? ' style="color:var(--t-cmd-line)"' : "") + ">" + esc(it.tk) + "</b> " +
          '<span class="' + fmt.cls(chg) + '">' + fmt.pct(chg, 1) + "</span>" +
          '<span style="color:var(--t-faint)"> 有效 ' + it.valid + "/" + it.n + "</span></span>";
      }).join("");
    }
    return { lo: lo, hi: hi, n: n, items: live };
  }

  /* ── 小倍数：一条序列一张小图，共用同一个纵轴范围 ──────────────────────
     六条线叠在一张图上谁也看不清；小倍数是「序列多到颜色分不开」时的正解。
     每张图只有一条线，身份靠标题，完全不用颜色编码。 */
  function smallMultiples(hostSel, items, dates, opt) {
    opt = opt || {};
    var host = typeof hostSel === "string" ? $(hostSel) : hostSel;
    if (!host) return;
    var live = (items || []).filter(function (it) { return it && it.values && it.values.filter(isNum).length >= 2; });
    if (!live.length) { host.innerHTML = '<p class="t-note">没有可画的序列</p>'; return; }
    var lo = Infinity, hi = -Infinity, n = 0;
    live.forEach(function (it) {
      n = Math.max(n, it.values.length);
      it.values.forEach(function (v) { if (isNum(v)) { if (v < lo) lo = v; if (v > hi) hi = v; } });
    });
    var pad = (hi - lo) * .08 || 1; lo -= pad; hi += pad;
    var W = 168, H = 52, span = n - 1 || 1;
    host.innerHTML = live.map(function (it) {
      var d = "", pen = false;
      for (var j = 0; j < it.values.length; j++) {
        if (!isNum(it.values[j])) { pen = false; continue; }
        d += (pen ? "L" : "M") + (W * j / span).toFixed(1) + "," +
             (H * (hi - it.values[j]) / (hi - lo)).toFixed(1);
        pen = true;
      }
      var chg = isNum(it.last) ? it.last - 100 : null;
      var y100 = H * (hi - 100) / (hi - lo);
      return '<figure class="t-sm"><figcaption><b>' + esc(it.tk) + "</b>" +
        '<span class="' + fmt.cls(chg) + '">' + fmt.pct(chg, 1) + "</span></figcaption>" +
        '<svg viewBox="0 0 ' + W + " " + H + '" preserveAspectRatio="none" role="img" aria-label="' +
        esc(it.tk + " 归一化走势 " + fmt.pct(chg, 1)) + '">' +
        (y100 >= 0 && y100 <= H
          ? '<line x1="0" y1="' + y100.toFixed(1) + '" x2="' + W + '" y2="' + y100.toFixed(1) +
            '" stroke="#2e2e2e" stroke-width="1" stroke-dasharray="3 3"/>' : "") +
        '<path d="' + d + '" fill="none" stroke="var(--t-ink2)" stroke-width="1.2"/></svg>' +
        '<figcaption class="sub">有效 ' + it.valid + "/" + it.n + "</figcaption></figure>";
    }).join("");
  }

  function fields(dl, list) {
    dl = typeof dl === "string" ? $(dl) : dl;
    if (!dl) return;
    dl.innerHTML = list.map(function (p) {
      if (!p) return "";
      var cls = p.na ? "na" : (p.mono ? "mono" : "");
      if (p.box) cls += " box";
      return "<dt>" + esc(p[0] !== undefined ? p[0] : p.k) + "</dt><dd class=\"" + cls + "\">" +
        (p.html || esc(p.v == null ? "—" : p.v)) + (p.u ? '<span class="u">' + esc(p.u) + "</span>" : "") + "</dd>";
    }).join("");
  }

  global.OOGLEX_RENDER = {
    $: $, $$: $$, esc: esc, set: set, html: html, cell: cell, pctCell: pctCell, sigTag: sigTag,
    absChg: absChg, lastPx: lastPx, lastPct: lastPct, srcLine: srcLine,
    quoteTable: quoteTable, curve: curve, spreadLegend: spreadLegend, spreadTable: spreadTable,
    ratesTable: ratesTable, macroMonitor: macroMonitor, MONITOR_METHOD: MONITOR_METHOD,
    macroBlock: macroBlock,
    priceLine: priceLine, multiLine: multiLine, smallMultiples: smallMultiples,
    fields: fields, nameCell: nameCell,
    crossBars: crossBars, calendar: calendar, news: news, alerts: alerts, sources: sources,
    watchlist: watchlist, topStatus: topStatus
  };
})(window);
