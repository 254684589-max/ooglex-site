/* 数据中心改版 · 三个方案共用的取数与摘要层（设计稿专用，不被正式页面加载）。
   每个应用的读数逻辑与 ../app.js 相同，只是返回结构化摘要，方便三套版式各自排版。 */
(function () {
  "use strict";
  function isNum(v) { return v !== null && v !== undefined && v !== "" && !isNaN(v); }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function pct(v) { return !isNum(v) ? "—" : (v >= 0 ? "+" : "−") + Math.abs(v).toFixed(1) + "%"; }
  function cls(v) { return !isNum(v) ? "dim" : (v > 0 ? "up" : (v < 0 ? "down" : "dim")); }
  function worth(b) { return !isNum(b) ? "—" : (b >= 1000 ? "$" + (b / 1000).toFixed(2) + "T" : "$" + b.toFixed(1) + "B"); }
  function relTime(iso) {
    if (!iso) return "—";
    var t = Date.parse(iso); if (isNaN(t)) return "—";
    var d = (Date.now() - t) / 1000;
    if (d < 3600) return Math.max(1, Math.floor(d / 60)) + " 分钟前";
    if (d < 86400) return Math.floor(d / 3600) + " 小时前";
    return Math.floor(d / 86400) + " 天前";
  }
  function R(l, v, c) { return { l: l, v: v, c: c || "" }; }

  /* 摘要：key 主读数、sub 主读数说明、tone（stress/warn/calm）、rows 次要行（v 已转义，可含少量标记） */
  var APPS = [
    { folder: "fear-greed", en: "Fear & Greed", name: "恐慌与贪婪指数", freq: "日频",
      sum: function (d) {
        return { key: String(d.score), sub: "市场处于" + esc(d.ratingZh || "—"),
          tone: d.score < 45 ? "stress" : d.score > 55 ? "calm" : "warn", rows: [] };
      } },
    { folder: "macro-radar", en: "Macro Risk", name: "宏观风险监测", freq: "日频",
      sum: function (d) {
        var r = d.regime || {};
        var weak = (d.signals || []).filter(function (s) { return isNum(s.score); })
          .sort(function (a, b) { return a.score - b.score; }).slice(0, 2)
          .map(function (s) { return esc(s.zh) + " " + s.score; }).join(" · ");
        return { key: String(r.score), sub: esc(r.labelZh || ""),
          tone: r.score < 40 ? "stress" : r.score <= 58 ? "warn" : "calm",
          rows: [R("偏弱信号", weak || "—", "dim")] };
      } },
    { folder: "ofr-monitor", en: "OFR Risk", name: "美国金融风险监测", freq: "周频",
      sum: function (d) {
        var f = d.fsi || {}, fu = d.funding || {}, rows = [];
        if (fu.sofr && isNum(fu.sofr.value)) rows.push(R("SOFR 隔夜", fu.sofr.value.toFixed(2) + "%"));
        if (d.mmf && isNum(d.mmf.total)) rows.push(R("货基规模", "$" + d.mmf.total.toFixed(2) + "T"));
        return { key: f.value.toFixed(2),
          sub: "金融压力 · " + (f.value > 0.5 ? "高于平均" : f.value < -0.5 ? "低于平均" : "接近平均"),
          tone: f.value > 0.5 ? "stress" : f.value < -0.5 ? "calm" : "warn", rows: rows };
      } },
    { folder: "econ-calendar", en: "Calendar", name: "全球经济日历", freq: "周表",
      sum: function (d) {
        var evs = d.events || [], now = Date.now();
        var ev = evs.filter(function (e) { return e.impact === "high" && Date.parse(e.ts) >= now; })[0] ||
          evs.filter(function (e) { return e.impact === "high"; })[0] || evs[0];
        return { key: isNum(d.count) ? String(d.count) : "—", sub: "本周事件",
          news: (ev.flag || "🌐") + " " + esc(ev.title),
          rows: [R("预测 / 前值", esc(ev.forecast || "—") + " / " + esc(ev.previous || "—"), "dim")] };
      } },
    { folder: "heatmap", dataFolder: "companies", dataFile: "sp500.json", en: "S&P 500", name: "标普500热力图", freq: "日频",
      sum: function (d) {
        var m = (d.members || []).filter(function (x) { return isNum(x.changePct); });
        var up = m.filter(function (x) { return x.changePct > 0; }).length;
        var top = m.slice().sort(function (x, y) { return y.changePct - x.changePct; })[0];
        return { key: up + "/" + m.length, sub: "成分股今日上涨", breadth: up / m.length,
          rows: [R("领涨", esc(top.name || top.symbol) + " " + pct(top.changePct), "up")] };
      } },
    { folder: "markets", dataFolder: "asset-tracker", en: "Global Markets", name: "全球市场行情", freq: "日频",
      sum: function (d) {
        var a = (d.assets || []).filter(function (x) { return x.returns && isNum(x.returns.d1); });
        var up = a.filter(function (x) { return x.returns.d1 > 0; }).length;
        var top = a.slice().sort(function (x, y) { return y.returns.d1 - x.returns.d1; })[0];
        return { key: up + "/" + a.length, sub: "跨资产标的今日上涨", breadth: up / a.length,
          rows: [R("领涨", esc(top.name) + " " + pct(top.returns.d1), "up")] };
      } },
    { folder: "world-economy", en: "World Economy", name: "全球经济图谱", freq: "月/季",
      sum: function (d) {
        var inds = d.indicators || [];
        var pol = inds.filter(function (i) { return i.key === "policy"; })[0];
        var v = (pol && pol.values) || {};
        var rate = function (c) { return isNum(v[c]) ? v[c] + "%" : "—"; };
        return { key: rate("US"), sub: "美联储基准利率",
          rows: [R("中国 / 欧元区", rate("CN") + " / " + rate("DE")), R("覆盖", inds.length + " 项指标 · 约 180 国", "dim")] };
      } },
    { folder: "asset-ranking", en: "Market Cap", name: "全球资产市值榜", freq: "日频",
      sum: function (d) {
        var a = (d.assets || [])[0];
        return { key: worth(a.marketCap), sub: "#1 " + esc(a.name),
          rows: [R("前 " + (d.count || 250) + " 合计", worth(d.totalMarketCap))] };
      } },
    { folder: "asset-tracker", en: "YTD", name: "大类资产收益率", freq: "日频",
      sum: function (d) {
        var a = (d.assets || []).filter(function (x) { return x.returns && isNum(x.returns.ytd); })
          .sort(function (x, y) { return y.returns.ytd - x.returns.ytd; });
        var t = a[0], b = a[a.length - 1];
        return { key: pct(t.returns.ytd), keyCls: cls(t.returns.ytd), sub: "年初至今领涨 · " + esc(t.name),
          rows: [R("领跌", esc(b.name) + " " + pct(b.returns.ytd), "down")] };
      } },
    { folder: "house-prices", en: "Housing", name: "全球房价走势", freq: "季频",
      sum: function (d) {
        var cs = (d.countries || []).filter(function (c) { return isNum(c.yoyNominal); });
        var t = cs.slice().sort(function (a, b) { return b.yoyNominal - a.yoyNominal; })[0];
        var b = cs.slice().sort(function (a, b) { return a.yoyNominal - b.yoyNominal; })[0];
        return { key: pct(t.yoyNominal), keyCls: cls(t.yoyNominal), sub: "名义同比涨幅居首 · " + esc(t.name),
          rows: [R("跌幅居首", esc(b.name) + " " + pct(b.yoyNominal), "down")] };
      } },
    { folder: "billionaires", en: "Billionaires", name: "亿万富翁排行榜", freq: "日频",
      sum: function (d) {
        var p = (d.people || [])[0], n = d.count || (d.people || []).length;
        return { key: worth(p.worth), sub: "#1 " + esc(p.name), rows: [R(n + " 位合计", worth(d.totalWorth))] };
      } },
    { folder: "companies", en: "Companies", name: "全球公司市值榜", freq: "日频",
      sum: function (d) {
        var c = (d.companies || [])[0];
        return { key: worth(c.marketCap), sub: "#1 " + esc(c.name), rows: [R("前 " + (d.count || 0) + " 合计", worth(d.totalMarketCap))] };
      } },
    { folder: "superinvestors", en: "13F · AAII", name: "超级投资者持仓", freq: "季/周",
      sum: function (d) {
        var inv = (d.investors || [])[0], a = d.aaii, rows = [], key = "—", sub = "";
        if (a && (a.weeks || [])[0]) {
          var w0 = a.weeks[0];
          key = w0.bull + "%"; sub = "AAII 看涨比例";
          rows.push(R("AAII 看跌", w0.bear + "%", "down"));
        }
        if (inv) rows.push(R("#1 " + esc(inv.zh), inv.stocks + " 只持仓", "dim"));
        return { key: key, sub: sub, rows: rows };
      } },
    { folder: "ai-rankings", en: "AI Models", name: "大模型评测榜", freq: "日频",
      sum: function (d) {
        var ms = d.models || [], top = ms[0], open = ms.filter(function (m) { return m.open; })[0];
        return { key: esc(top.name), keyText: true, sub: "综合第一" + (top.flag ? " " + top.flag : ""),
          rows: [R("开源第一", open ? esc(open.name) : "—", "dim")] };
      } },
    { folder: "university-rankings", en: "Universities", name: "大学排名 300 强", freq: "年频",
      sum: function (d) {
        var top = (d.universities || [])[0];
        return { key: esc(top.cn || top.name), keyText: true, sub: "四榜平均第一" + (top.flag ? " " + top.flag : ""),
          rows: [R("来源", "QS · THE · ARWU · USN", "dim")] };
      } },
    { folder: "major-rankings", en: "Majors", name: "专业与就业前景", freq: "年频",
      sum: function (d) {
        var ms = d.majors || [];
        var byMid = ms.slice().sort(function (a, b) { return b.mid - a.mid; })[0];
        var byFut = ms.slice().sort(function (a, b) { return b.future - a.future; })[0];
        return { key: esc(byMid.cn), keyText: true, sub: "中位薪资第一 · $" + Math.round(byMid.mid / 1000) + "K",
          rows: [R("AI 前景第一", esc(byFut.cn), "dim")] };
      } }
  ];

  var GROUPS = [
    { id: "risk", name: "情绪与风险", en: "Sentiment & Risk", folders: ["macro-radar", "ofr-monitor", "econ-calendar"] },
    { id: "index", name: "指数与市场", en: "Markets", folders: ["heatmap", "markets", "world-economy"] },
    { id: "assets", name: "资产与回报", en: "Assets", folders: ["asset-ranking", "asset-tracker", "house-prices"] },
    { id: "people", name: "人物与公司", en: "People & Companies",
      folders: ["billionaires", "companies", "superinvestors", "ai-rankings", "university-rankings", "major-rankings"] }
  ];

  var cache = {};
  function getJSON(url) {
    if (!cache[url]) cache[url] = fetch(url + "?t=" + Date.now())
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); });
    return cache[url];
  }
  function load(app) {
    return getJSON("../../" + (app.dataFolder || app.folder) + "/" + (app.dataFile || "data.json"))
      .then(function (d) {
        var s;
        try { s = app.sum(d); } catch (e) { s = { err: "预览不可用" }; }
        s.updatedAt = d.updatedAt; s.ago = relTime(d.updatedAt); s.asOf = d.asOf;
        return s;
      })
      .catch(function () { return { err: "数据暂不可用", ago: "—" }; });
  }

  /* 恐慌贪婪五档：CNN 口径 0–24 / 25–44 / 45–55 / 56–75 / 76–100 */
  var FG_BANDS = [
    { to: 25, zh: "极度恐惧", c: "var(--fg-xf)" }, { to: 45, zh: "恐惧", c: "var(--fg-f)" },
    { to: 56, zh: "中性", c: "var(--fg-n)" }, { to: 76, zh: "贪婪", c: "var(--fg-g)" },
    { to: 101, zh: "极度贪婪", c: "var(--fg-xg)" }
  ];
  function band(v) { for (var i = 0; i < FG_BANDS.length; i++) if (v < FG_BANDS[i].to) return FG_BANDS[i]; return FG_BANDS[4]; }

  /* 半圆仪表 SVG：0 在左、100 在右 */
  function gauge(v, opt) {
    opt = opt || {};
    var W = 300, cx = 150, cy = 150, r = 120, sw = opt.stroke || 22, h = "";
    function pt(val, rad) { var a = Math.PI * (1 - val / 100); return [cx + rad * Math.cos(a), cy - rad * Math.sin(a)]; }
    var lo = 0;
    FG_BANDS.forEach(function (b) {
      var hi = Math.min(b.to, 100), p0 = pt(lo + 0.6, r), p1 = pt(hi - 0.6, r);
      h += "<path d='M" + p0[0].toFixed(1) + " " + p0[1].toFixed(1) + " A" + r + " " + r + " 0 0 1 " +
        p1[0].toFixed(1) + " " + p1[1].toFixed(1) + "' stroke='" + b.c + "' stroke-width='" + sw +
        "' fill='none' opacity='" + (v >= lo && v < b.to ? 1 : 0.28) + "'/>";
      lo = hi;
    });
    [0, 25, 50, 75, 100].forEach(function (t) {
      var p = pt(t, r - sw / 2 - 12);
      h += "<text x='" + p[0].toFixed(1) + "' y='" + (p[1] + 4).toFixed(1) + "' text-anchor='middle' class='gt'>" + t + "</text>";
    });
    var n = pt(v, r);
    h += "<circle cx='" + n[0].toFixed(1) + "' cy='" + n[1].toFixed(1) + "' r='" + (sw / 2 + 5) + "' class='mk'/>" +
      "<circle cx='" + n[0].toFixed(1) + "' cy='" + n[1].toFixed(1) + "' r='" + (sw / 2 - 4) + "' fill='" + band(v).c + "'/>";
    return "<svg viewBox='0 0 " + W + " 162' class='gauge' role='img' aria-label='恐慌与贪婪指数 " + v + "，" + band(v).zh + "'>" + h + "</svg>";
  }

  /* 一年走势面积图，带 25/45/55/75 分档参考线 */
  function spark(hist, opt) {
    opt = opt || {};
    var W = opt.w || 600, H = opt.h || 120, pad = 2;
    if (!hist || hist.length < 2) return "";
    var t0 = Date.parse(hist[0].t), t1 = Date.parse(hist[hist.length - 1].t);
    function X(t) { return pad + (Date.parse(t) - t0) / (t1 - t0) * (W - pad * 2); }
    function Y(v) { return pad + (1 - v / 100) * (H - pad * 2); }
    var line = hist.map(function (p, i) { return (i ? "L" : "M") + X(p.t).toFixed(1) + " " + Y(p.v).toFixed(1); }).join("");
    var g = "";
    [25, 45, 55, 75].forEach(function (y) { g += "<line x1='0' x2='" + W + "' y1='" + Y(y) + "' y2='" + Y(y) + "' class='grid'/>"; });
    g += "<rect x='0' y='" + Y(25) + "' width='" + W + "' height='" + (Y(0) - Y(25)) + "' class='zone-f'/>";
    g += "<rect x='0' y='" + Y(100) + "' width='" + W + "' height='" + (Y(75) - Y(100)) + "' class='zone-g'/>";
    var last = hist[hist.length - 1];
    return "<svg viewBox='0 0 " + W + " " + H + "' preserveAspectRatio='none' class='spark' role='img' aria-label='近一年恐慌与贪婪指数走势，" +
      hist[0].t + " 至 " + last.t + "'>" + g +
      "<path d='" + line + "L" + X(last.t).toFixed(1) + " " + H + "L" + X(hist[0].t).toFixed(1) + " " + H + "Z' class='area'/>" +
      "<path d='" + line + "' class='ln' vector-effect='non-scaling-stroke'/></svg>";
  }

  window.HubKit = { APPS: APPS, GROUPS: GROUPS, load: load, getJSON: getJSON, esc: esc, isNum: isNum,
    relTime: relTime, band: band, FG_BANDS: FG_BANDS, gauge: gauge, spark: spark,
    byFolder: function (f) { for (var i = 0; i < APPS.length; i++) if (APPS[i].folder === f) return APPS[i]; },
    fearGreed: function () { return getJSON("../../fear-greed/data.json"); },
    SOURCES: "来源 CNN · FRED · OFR · Yahoo Finance · CoinGecko · OECD · BIS · Forbes · Forex Factory · World Bank · QS · THE · ARWU · U.S. News · PayScale · BLS。各应用每日自动更新，均非实时行情，仅供参考，不构成投资建议。" };
})();
