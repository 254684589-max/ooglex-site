/* 数据中心 · 聚合各实时数据应用的 data.json，渲染带实时小预览的入口卡片。纯原生 JS。 */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  function isNum(v) { return v !== null && v !== undefined && !isNaN(v); }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function pct(v) { return !isNum(v) ? "—" : (v >= 0 ? "+" : "−") + Math.abs(v).toFixed(1) + "%"; }
  function cls(v) { return !isNum(v) ? "dim" : (v > 0 ? "up" : (v < 0 ? "down" : "dim")); }
  function worth(b) { return !isNum(b) ? "—" : (b >= 1000 ? "$" + (b / 1000).toFixed(2) + "T" : "$" + b.toFixed(1) + "B"); }
  function fgColor(s) { return !isNum(s) ? "#9099ad" : s < 25 ? "#d3403b" : s < 45 ? "#e8833a" : s < 55 ? "#e4b53d" : s < 75 ? "#7cb851" : "#3a9d5d"; }
  function radarColor(s) { return !isNum(s) ? "#9099ad" : s < 40 ? "#e0554f" : s <= 58 ? "#e0a750" : "#3fae7d"; }
  function row(l, v, c) { return "<div class='row'><span class='l'>" + l + "</span><span class='v " + (c || "") + "'>" + v + "</span></div>"; }
  // 迷你走势线：真实数值序列 → 面积填充 + 折线 + 末端高亮点
  function sparkSVG(vals, color, w, h) {
    w = w || 200; h = h || 34; var pad = 3;
    if (!vals || vals.length < 2) return "";
    var min = Math.min.apply(null, vals), max = Math.max.apply(null, vals), rng = (max - min) || 1, n = vals.length;
    var pts = vals.map(function (v, i) {
      return [pad + i * (w - 2 * pad) / (n - 1), h - pad - (v - min) / rng * (h - 2 * pad)];
    });
    var line = pts.map(function (p, i) { return (i ? "L" : "M") + p[0].toFixed(1) + " " + p[1].toFixed(1); }).join(" ");
    var area = line + " L " + pts[n - 1][0].toFixed(1) + " " + (h - pad) + " L " + pad.toFixed(1) + " " + (h - pad) + " Z";
    var id = "sp" + Math.random().toString(36).slice(2, 7), e = pts[n - 1];
    return "<svg viewBox='0 0 " + w + " " + h + "' preserveAspectRatio='none' aria-hidden='true'>" +
      "<defs><linearGradient id='" + id + "' x1='0' y1='0' x2='0' y2='1'>" +
      "<stop offset='0' stop-color='" + color + "' stop-opacity='.30'/>" +
      "<stop offset='1' stop-color='" + color + "' stop-opacity='0'/></linearGradient></defs>" +
      "<path d='" + area + "' fill='url(#" + id + ")'/>" +
      "<path d='" + line + "' fill='none' stroke='" + color + "' stroke-width='1.6' stroke-linejoin='round' stroke-linecap='round' vector-effect='non-scaling-stroke'/>" +
      "<circle cx='" + e[0].toFixed(1) + "' cy='" + e[1].toFixed(1) + "' r='2' fill='" + color + "' vector-effect='non-scaling-stroke'/></svg>";
  }
  // 排行迷你柱：全部为正，柱高按值比例，最高的一根实心、其余淡化
  function colBars(vals, color, w, h) {
    w = w || 200; h = h || 34; vals = (vals || []).filter(isNum); if (vals.length < 2) return "";
    var max = Math.max.apply(null, vals) || 1, n = vals.length, gap = n > 8 ? 1.5 : 3, bw = (w - (n - 1) * gap) / n;
    var s = "<svg viewBox='0 0 " + w + " " + h + "' preserveAspectRatio='none' aria-hidden='true'>";
    vals.forEach(function (v, i) {
      var bh = Math.max(1.5, v / max * (h - 3)), x = i * (bw + gap), y = h - bh;
      s += "<rect x='" + x.toFixed(1) + "' y='" + y.toFixed(1) + "' width='" + bw.toFixed(1) + "' height='" + bh.toFixed(1) +
        "' rx='1' fill='" + color + "' fill-opacity='" + (v === max ? 1 : 0.5) + "'/>";
    });
    return s + "</svg>";
  }
  // 涨跌迷你柱：以零轴为中线，正红负绿（国内习惯）
  function signedBars(vals, w, h) {
    w = w || 200; h = h || 34; vals = (vals || []).filter(isNum); if (vals.length < 2) return "";
    var max = Math.max.apply(null, vals.map(function (v) { return Math.abs(v); })) || 1;
    var mid = h / 2, n = vals.length, gap = 3, bw = (w - (n - 1) * gap) / n;
    var s = "<svg viewBox='0 0 " + w + " " + h + "' preserveAspectRatio='none' aria-hidden='true'>" +
      "<line x1='0' y1='" + mid + "' x2='" + w + "' y2='" + mid + "' stroke='rgba(255,255,255,.14)' stroke-width='1' vector-effect='non-scaling-stroke'/>";
    vals.forEach(function (v, i) {
      var bh = Math.max(1, Math.abs(v) / max * (mid - 1.5)), x = i * (bw + gap), y = v >= 0 ? mid - bh : mid;
      s += "<rect x='" + x.toFixed(1) + "' y='" + y.toFixed(1) + "' width='" + bw.toFixed(1) + "' height='" + bh.toFixed(1) +
        "' rx='1' fill='" + (v >= 0 ? "#ff5d6c" : "#28c79a") + "'/>";
    });
    return s + "</svg>";
  }
  function relTime(iso) {
    if (!iso) return "—";
    var t = Date.parse(iso); if (isNaN(t)) return "—";
    var d = (Date.now() - t) / 1000;
    if (d < 3600) return "更新于 " + Math.max(1, Math.floor(d / 60)) + " 分钟前";
    if (d < 86400) return "更新于 " + Math.floor(d / 3600) + " 小时前";
    return "更新于 " + Math.floor(d / 86400) + " 天前";
  }

  var APPS = [
    { folder: "macro-radar", emoji: "📡", name: "宏观雷达", tag: "市场机制 · 7 大制度信号 · 跨资产", accent: "#34e0c4",
      render: function (d) {
        var r = d.regime || {}; if (!isNum(r.score)) return "<div class='loading'>暂无数据</div>";
        var col = radarColor(r.score);
        var weak = (d.signals || []).filter(function (s) { return isNum(s.score); })
          .sort(function (a, b) { return a.score - b.score; }).slice(0, 2)
          .map(function (s) { return esc(s.zh) + " " + s.score; }).join(" · ");
        return "<div class='big' style='color:" + col + "'>" + r.score +
          "<small style='color:" + col + "'>" + esc(r.labelZh || "") + "</small></div>" +
          row("偏弱信号", weak || "—", "dim");
      } },
    { folder: "asset-tracker", emoji: "🌍", name: "全球大类资产收益率", tag: "股市 · 商品 · 外汇 · 债券", accent: "#6c8cff",
      render: function (d) {
        var a = (d.assets || []).filter(function (x) { return x.returns && isNum(x.returns.ytd); })
          .sort(function (x, y) { return y.returns.ytd - x.returns.ytd; });
        if (!a.length) return "<div class='loading'>暂无数据</div>";
        var t = a[0], b = a[a.length - 1];
        return row("年初至今领涨", esc(t.name) + " " + pct(t.returns.ytd), "up") +
          row("领跌", esc(b.name) + " " + pct(b.returns.ytd), "down");
      } },
    { folder: "asset-ranking", emoji: "🌐", name: "全球资产市值榜", tag: "不限品类 · 前 250 · 房产/国债/黄金/公司/加密", accent: "#f0a35e",
      render: function (d) {
        var a = (d.assets || [])[0]; if (!a) return "<div class='loading'>暂无数据</div>";
        return "<div class='big'>" + worth(a.marketCap) + "<small>#1 " + esc(a.name) + "</small></div>" +
          row("前 " + (d.count || 250) + " 总市值", worth(d.totalMarketCap));
      } },
    { folder: "house-prices", emoji: "🏘️", name: "全球房价走势", tag: "主要国家 · 名义/实际同比 · 季度走势", accent: "#5fd07a",
      render: function (d) {
        var cs = (d.countries || []).filter(function (c) { return isNum(c.yoyNominal); });
        if (!cs.length) return "<div class='loading'>暂无数据</div>";
        var t = cs.slice().sort(function (a, b) { return b.yoyNominal - a.yoyNominal; })[0];
        var b = cs.slice().sort(function (a, b) { return a.yoyNominal - b.yoyNominal; })[0];
        return row("涨幅居首", esc(t.name) + " " + pct(t.yoyNominal), "up") +
          row("跌幅居首", esc(b.name) + " " + pct(b.yoyNominal), "down");
      } },
    { folder: "billionaires", emoji: "🏆", name: "全球富豪实时榜", tag: "前 250 富豪身价", accent: "#f3c969",
      render: function (d) {
        var p = (d.people || [])[0]; if (!p) return "<div class='loading'>暂无数据</div>";
        return "<div class='big'>" + worth(p.worth) + "<small>#1 " + esc(p.name) + "</small></div>" +
          row("前 " + (d.count || 250) + " 总财富", worth(d.totalWorth));
      } },
    { folder: "companies", emoji: "🏢", name: "全球公司市值榜", tag: "全球 500 强 · 市值 · 股价", accent: "#38bdf8",
      render: function (d) {
        var c = (d.companies || [])[0]; if (!c) return "<div class='loading'>暂无数据</div>";
        return "<div class='big'>" + worth(c.marketCap) + "<small>#1 " + esc(c.name) + "</small></div>" +
          row("前 " + (d.count || 0) + " 总市值", worth(d.totalMarketCap));
      } },
    { folder: "fear-greed", emoji: "🧭", name: "恐慌与贪婪指数", tag: "CNN Fear & Greed · 近一年走势", accent: "#39c2c9",
      render: function (d) {
        if (!isNum(d.score)) return "<div class='loading'>暂无数据</div>";
        return "<div class='big' style='color:" + fgColor(d.score) + "'>" + d.score +
          "<small style='color:" + fgColor(d.score) + "'>" + esc(d.ratingZh || "") + "</small></div>";
      } },
    { folder: "world-economy", emoji: "🌐", name: "全球经济图谱", tag: "各国经济指标地图", accent: "#5fd07a",
      render: function (d) {
        var inds = d.indicators || [];
        var pol = inds.filter(function (i) { return i.key === "policy"; })[0];
        var v = (pol && pol.values) || {};
        var rate = function (c) { return isNum(v[c]) ? v[c] + "%" : "—"; };
        return row("覆盖", inds.length + " 项指标 · 约 180 国/地区", "dim") +
          row("央行基准利率", "🇺🇸 " + rate("US") + "　🇨🇳 " + rate("CN") + "　🇪🇺 " + rate("DE"));
      } },
    { folder: "superinvestors", emoji: "💼", name: "超级投资者持仓", tag: "13F · 60 位大佬 · 政治人物交易 · AAII", accent: "#8b7cf7",
      render: function (d) {
        var inv = (d.investors || [])[0], a = d.aaii;
        var h = "";
        if (inv) {
          var w = inv.value >= 1e12 ? "$" + (inv.value / 1e12).toFixed(2) + "T" : "$" + (inv.value / 1e9).toFixed(0) + "B";
          h += row("#1 " + esc(inv.zh), w + " · " + inv.stocks + " 只持仓");
        }
        if (a && (a.weeks || [])[0]) {
          var w0 = a.weeks[0];
          h += row("AAII 情绪", "<span class='up'>看涨 " + w0.bull + "%</span> · <span class='down'>看跌 " + w0.bear + "%</span>");
        }
        return h || "<div class='loading'>等待首次数据更新</div>";
      } },
    { folder: "ai-rankings", emoji: "🤖", name: "全球大模型评测榜", tag: "LMArena Elo · LiveBench · 智能指数", accent: "#39d3e0",
      render: function (d) {
        var ms = d.models || [];
        if (!ms.length) return "<div class='loading'>暂无数据</div>";
        var top = ms[0];
        var open = ms.filter(function (m) { return m.open; })[0];
        return row("综合第一", esc(top.name) + (top.flag ? " " + top.flag : "")) +
          row("开源第一", open ? esc(open.name) + (open.flag ? " " + open.flag : "") : "—", "dim");
      } },
    { folder: "university-rankings", emoji: "🎓", name: "全球大学排名 300 强", tag: "QS · THE · ARWU · U.S. News 四榜合一", accent: "#8aa6ff",
      render: function (d) {
        var us = d.universities || []; if (!us.length) return "<div class='loading'>暂无数据</div>";
        var top = us[0];
        return "<div class='big'>" + (top.flag || "🌐") + "<small>#1 " + esc(top.cn || top.name) + "</small></div>" +
          row("综合前 " + (d.count || us.length), "QS/THE/ARWU/USN 平均位次", "dim");
      } },
    { folder: "major-rankings", emoji: "🚀", name: "全球专业与就业前景榜", tag: "薪资 · 就业率 · 起薪 · AI 时代前景", accent: "#5fd07a",
      render: function (d) {
        var ms = d.majors || []; if (!ms.length) return "<div class='loading'>暂无数据</div>";
        var byMid = ms.slice().sort(function (a, b) { return b.mid - a.mid; })[0];
        var byFut = ms.slice().sort(function (a, b) { return b.future - a.future; })[0];
        return row("薪资第一", esc(byMid.cn) + " $" + Math.round(byMid.mid / 1000) + "K") +
          row("AI 前景第一", esc(byFut.cn), "dim");
      } },
    { folder: "econ-calendar", emoji: "📅", name: "全球经济日历", tag: "央行决议 · CPI · 非农", accent: "#e0729a",
      render: function (d) {
        var evs = d.events || [], now = Date.now();
        var ev = evs.filter(function (e) { return e.impact === "high" && Date.parse(e.ts) >= now; })[0] ||
          evs.filter(function (e) { return e.impact === "high"; })[0] || evs[0];
        if (!ev) return "<div class='loading'>暂无数据</div>";
        return "<div class='news'>" + (ev.flag || "🌐") + " " + esc(ev.title) + "</div>" +
          "<div class='sub'>预测 " + esc(ev.forecast || "—") + " · 前值 " + esc(ev.previous || "—") +
          (isNum(d.count) ? " · 本周 " + d.count + " 项" : "") + "</div>";
      } }
  ];

  // 每个应用的迷你图（w=容器宽度）：有序列→走势线，排行→Top 柱，多周期→涨跌柱
  var VIZ = {
    "macro-radar": function (d, w) {
      var col = radarColor((d.regime || {}).score);
      return getJSON("../macro-radar/history.json").then(function (h) {
        return sparkSVG(((h && h.regime) || []).slice(-42).filter(isNum), col, w, 34);
      });
    },
    "fear-greed": function (d, w) {
      return sparkSVG((d.history || []).map(function (x) { return x.v; }).filter(isNum), fgColor(d.score), w, 34);
    },
    "house-prices": function (d, w) {
      var cs = (d.countries || []).filter(function (c) { return isNum(c.yoyNominal); })
        .sort(function (a, b) { return b.yoyNominal - a.yoyNominal; });
      var lead = cs[0]; if (!lead || !lead.trend) return "";
      var vals = lead.trend.filter(function (t) { return t.p.indexOf("Q") >= 0; }).slice(-24).map(function (t) { return t.v; });
      return "<div class='vlab'>" + esc(lead.name) + " 房价指数走势</div>" + sparkSVG(vals, "#5fd07a", w, 30);
    },
    "superinvestors": function (d, w) {
      var wk = ((d.aaii || {}).weeks || []).slice().reverse().map(function (x) { return x.bull; }).filter(isNum);
      return wk.length > 1 ? "<div class='vlab'>AAII 看涨情绪 · 近 " + wk.length + " 周</div>" + sparkSVG(wk, "#8b7cf7", w, 30) : "";
    },
    "asset-tracker": function (d, w) {
      var a = (d.assets || []).filter(function (x) { return x.returns && isNum(x.returns.ytd); })
        .sort(function (x, y) { return y.returns.ytd - x.returns.ytd; });
      if (a.length < 4) return "";
      var pick = a.slice(0, 3).concat(a.slice(-3));
      return "<div class='vlab'>YTD 涨跌前三 / 后三</div>" + signedBars(pick.map(function (x) { return x.returns.ytd; }), w, 30);
    },
    "asset-ranking": function (d, w) {
      return "<div class='vlab'>市值前 8</div>" + colBars((d.assets || []).slice(0, 8).map(function (a) { return a.marketCap; }), "#f0a35e", w, 30);
    },
    "billionaires": function (d, w) {
      return "<div class='vlab'>身价前 8</div>" + colBars((d.people || []).slice(0, 8).map(function (p) { return p.worth; }), "#f3c969", w, 30);
    },
    "companies": function (d, w) {
      return "<div class='vlab'>市值前 8</div>" + colBars((d.companies || []).slice(0, 8).map(function (c) { return c.marketCap; }), "#38bdf8", w, 30);
    },
    "world-economy": function (d, w) {
      var pol = (d.indicators || []).filter(function (i) { return i.key === "policy"; })[0];
      var v = (pol && pol.values) || {}, ks = ["US", "CN", "DE", "JP", "GB", "IN", "BR"];
      var vals = ks.map(function (k) { return v[k]; }).filter(isNum);
      return vals.length > 1 ? "<div class='vlab'>主要央行基准利率 %</div>" + colBars(vals, "#5fd07a", w, 30) : "";
    },
    "ai-rankings": function (d, w) {
      var vals = (d.models || []).slice(0, 8).map(function (m) { return m.arena; }).filter(isNum);
      return vals.length > 1 ? "<div class='vlab'>竞技场 Elo 前 8</div>" + colBars(vals, "#39d3e0", w, 30) : "";
    },
    "major-rankings": function (d, w) {
      var top = (d.majors || []).slice().sort(function (a, b) { return b.mid - a.mid; }).slice(0, 8).map(function (m) { return m.mid; });
      return top.length > 1 ? "<div class='vlab'>薪资前 8（中位年薪）</div>" + colBars(top, "#5fd07a", w, 30) : "";
    },
    "university-rankings": function (d, w) {
      var cnt = {}; (d.universities || []).forEach(function (u) { var f = u.flag || "🌐"; cnt[f] = (cnt[f] || 0) + 1; });
      var top = Object.keys(cnt).map(function (k) { return cnt[k]; }).sort(function (a, b) { return b - a; }).slice(0, 8);
      return top.length > 1 ? "<div class='vlab'>各国上榜数（前 8 国）</div>" + colBars(top, "#8aa6ff", w, 30) : "";
    },
    "econ-calendar": function (d, w) {
      var evs = d.events || [], c = { high: 0, medium: 0, low: 0 };
      evs.forEach(function (e) { if (c[e.impact] != null) c[e.impact]++; });
      return "<div class='vlab'>本周事件影响分布（高/中/低）</div>" + colBars([c.high, c.medium, c.low], "#e0729a", w, 30);
    }
  };

  // 各应用 data.json 只取一次，卡片与「今日市场总览」共用，避免重复请求
  var _cache = {};
  function getJSON(url) {
    if (!_cache[url]) {
      _cache[url] = fetch(url + (url.indexOf("?") < 0 ? "?t=" + Date.now() : ""))
        .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); });
    }
    return _cache[url];
  }
  function getData(folder) { return getJSON("../" + folder + "/data.json"); }

  function card(app) {
    var a = document.createElement("a");
    a.className = "card"; a.href = "../" + app.folder + "/"; a.style.setProperty("--accent", app.accent);
    a.innerHTML =
      "<div class='ch'><span class='emoji'>" + app.emoji + "</span>" +
      "<div><div class='nm'>" + app.name + "</div><div class='tag'>" + app.tag + "</div></div>" +
      "<span class='live'></span></div>" +
      "<div class='body'><div class='loading'>加载中…</div></div>" +
      "<div class='cf'><span class='upd'>—</span><span class='go'>打开 →</span></div>";
    var body = a.querySelector(".body"), upd = a.querySelector(".upd");
    getData(app.folder)
      .then(function (d) {
        try { body.innerHTML = app.render(d); } catch (e) { body.innerHTML = "<div class='loading'>预览不可用</div>"; }
        upd.textContent = relTime(d.updatedAt);
        var vf = VIZ[app.folder];
        if (vf) {
          var w = Math.max(120, body.clientWidth || 240);
          Promise.resolve().then(function () { return vf(d, w); }).then(function (html) {
            if (html) { var div = document.createElement("div"); div.className = "spk"; div.innerHTML = html; body.appendChild(div); }
          }).catch(function () {});
        }
      })
      .catch(function () { body.innerHTML = "<div class='loading'>数据暂不可用</div>"; });
    return a;
  }

  // 今日市场总览：从几个应用数据里取头条读数，摘要在前，每项配一张迷你图
  function ovM(k, v, vcls, d, accent, viz) {
    return "<div class='ov-m' style='--accent:" + accent + "'>" +
      "<div class='k'>" + k + "</div>" +
      "<div class='v " + (vcls || "") + "'>" + v + "</div>" +
      "<div class='d dim'>" + d + "</div>" +
      (viz ? "<div class='spk'>" + viz + "</div>" : "") + "</div>";
  }
  function buildOverview() {
    var box = $("ovMetrics"), sec = $("overview"); if (!box) return;
    var parts = {}, W = 200;
    function render() {
      var html = ["mood", "up", "down", "rich", "cap"].map(function (k) { return parts[k] || ""; }).join("");
      if (html) { box.innerHTML = html; sec.className = "overview show"; }
    }
    getData("fear-greed").then(function (d) {
      if (isNum(d.score)) {
        var vals = (d.history || []).map(function (x) { return x.v; }).filter(isNum);
        parts.mood = ovM("市场情绪", "<span style='color:" + fgColor(d.score) + "'>" + d.score + "</span>",
          "", esc(d.ratingZh || ""), fgColor(d.score), sparkSVG(vals, fgColor(d.score), W, 24));
      }
      if (d.asOf) $("ovDate").textContent = d.asOf;
      render();
    }).catch(function () {});
    getData("asset-tracker").then(function (d) {
      var a = (d.assets || []).filter(function (x) { return x.returns && isNum(x.returns.ytd); })
        .sort(function (x, y) { return y.returns.ytd - x.returns.ytd; });
      if (a.length) {
        var t = a[0], b = a[a.length - 1];
        var per = function (x) { var r = x.returns; return signedBars([r.d1, r.w1, r.m1, r.ytd, r.y1], W, 24); };
        parts.up = ovM("YTD 领涨", pct(t.returns.ytd), "up", esc(t.name), "#ff5d6c", per(t));
        parts.down = ovM("YTD 领跌", pct(b.returns.ytd), "down", esc(b.name), "#28c79a", per(b));
        render();
      }
    }).catch(function () {});
    getData("billionaires").then(function (d) {
      var p = (d.people || [])[0];
      if (p) {
        parts.rich = ovM("全球首富", worth(p.worth), "", esc(p.name), "#f3c969",
          colBars((d.people || []).slice(0, 8).map(function (x) { return x.worth; }), "#f3c969", W, 24));
        render();
      }
    }).catch(function () {});
    getData("companies").then(function (d) {
      var c = (d.companies || [])[0];
      if (c) {
        parts.cap = ovM("市值 #1", worth(c.marketCap), "", esc(c.name), "#38bdf8",
          colBars((d.companies || []).slice(0, 8).map(function (x) { return x.marketCap; }), "#38bdf8", W, 24));
        render();
      }
    }).catch(function () {});
  }

  function boot() {
    buildOverview();
    var grid = $("grid");
    APPS.forEach(function (app) { grid.appendChild(card(app)); });
    $("foot").innerHTML = "各应用数据每日自动更新（来源 Yahoo Finance · CoinGecko · OECD · BIS · Forbes · CNN · Google News · World Bank · Forex Factory · QS · THE · ARWU · U.S. News · PayScale · NACE · BLS · WEF）。仅供参考，不构成建议。";
  }
  boot();
})();
