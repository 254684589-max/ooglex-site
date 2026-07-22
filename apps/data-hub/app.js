/* 数据中心 · 聚合各实时数据应用的 data.json，以「编排 / Editorial」排版渲染入口卡片。纯原生 JS。 */
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
  function relTime(iso) {
    if (!iso) return "—";
    var t = Date.parse(iso); if (isNaN(t)) return "—";
    var d = (Date.now() - t) / 1000;
    if (d < 3600) return "更新于 " + Math.max(1, Math.floor(d / 60)) + " 分钟前";
    if (d < 86400) return "更新于 " + Math.floor(d / 3600) + " 小时前";
    return "更新于 " + Math.floor(d / 86400) + " 天前";
  }

  var APPS = [
    { folder: "macro-radar", en: "Regime", name: "宏观雷达", tag: "市场机制 · 7 大制度信号 · 跨资产",
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
    { folder: "asset-tracker", en: "Assets · YTD", name: "全球大类资产收益率", tag: "股市 · 商品 · 外汇 · 债券",
      render: function (d) {
        var a = (d.assets || []).filter(function (x) { return x.returns && isNum(x.returns.ytd); })
          .sort(function (x, y) { return y.returns.ytd - x.returns.ytd; });
        if (!a.length) return "<div class='loading'>暂无数据</div>";
        var t = a[0], b = a[a.length - 1];
        return row("年初至今领涨", esc(t.name) + " " + pct(t.returns.ytd), "up") +
          row("领跌", esc(b.name) + " " + pct(b.returns.ytd), "down");
      } },
    { folder: "asset-ranking", en: "Market Cap", name: "全球资产市值榜", tag: "不限品类 · 前 250 · 房产/国债/黄金/公司/加密",
      render: function (d) {
        var a = (d.assets || [])[0]; if (!a) return "<div class='loading'>暂无数据</div>";
        return "<div class='big'>" + worth(a.marketCap) + "<small>#1 " + esc(a.name) + "</small></div>" +
          row("前 " + (d.count || 250) + " 总市值", worth(d.totalMarketCap));
      } },
    { folder: "house-prices", en: "Housing", name: "全球房价走势", tag: "主要国家 · 名义/实际同比 · 季度走势",
      render: function (d) {
        var cs = (d.countries || []).filter(function (c) { return isNum(c.yoyNominal); });
        if (!cs.length) return "<div class='loading'>暂无数据</div>";
        var t = cs.slice().sort(function (a, b) { return b.yoyNominal - a.yoyNominal; })[0];
        var b = cs.slice().sort(function (a, b) { return a.yoyNominal - b.yoyNominal; })[0];
        return row("涨幅居首", esc(t.name) + " " + pct(t.yoyNominal), "up") +
          row("跌幅居首", esc(b.name) + " " + pct(b.yoyNominal), "down");
      } },
    { folder: "billionaires", en: "Billionaires", name: "全球富豪实时榜", tag: "前 250 富豪身价",
      render: function (d) {
        var p = (d.people || [])[0]; if (!p) return "<div class='loading'>暂无数据</div>";
        return "<div class='big'>" + worth(p.worth) + "<small>#1 " + esc(p.name) + "</small></div>" +
          row("前 " + (d.count || 250) + " 总财富", worth(d.totalWorth));
      } },
    { folder: "companies", en: "Companies", name: "全球公司市值榜", tag: "全球 500 强 · 市值 · 股价",
      render: function (d) {
        var c = (d.companies || [])[0]; if (!c) return "<div class='loading'>暂无数据</div>";
        return "<div class='big'>" + worth(c.marketCap) + "<small>#1 " + esc(c.name) + "</small></div>" +
          row("前 " + (d.count || 0) + " 总市值", worth(d.totalMarketCap));
      } },
    { folder: "fear-greed", en: "Fear & Greed", name: "恐慌与贪婪指数", tag: "CNN Fear & Greed · 近一年走势",
      render: function (d) {
        if (!isNum(d.score)) return "<div class='loading'>暂无数据</div>";
        return "<div class='big' style='color:" + fgColor(d.score) + "'>" + d.score +
          "<small style='color:" + fgColor(d.score) + "'>" + esc(d.ratingZh || "") + "</small></div>";
      } },
    { folder: "world-economy", en: "World Economy", name: "全球经济图谱", tag: "各国经济指标地图",
      render: function (d) {
        var inds = d.indicators || [];
        var pol = inds.filter(function (i) { return i.key === "policy"; })[0];
        var v = (pol && pol.values) || {};
        var rate = function (c) { return isNum(v[c]) ? v[c] + "%" : "—"; };
        return row("覆盖", inds.length + " 项指标 · 约 180 国/地区", "dim") +
          row("央行基准利率", "🇺🇸 " + rate("US") + "　🇨🇳 " + rate("CN") + "　🇪🇺 " + rate("DE"));
      } },
    { folder: "superinvestors", en: "13F · AAII", name: "超级投资者持仓", tag: "13F · 60 位大佬 · 政治人物交易 · AAII",
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
    { folder: "ai-rankings", en: "AI Models", name: "全球大模型评测榜", tag: "LMArena Elo · LiveBench · 智能指数",
      render: function (d) {
        var ms = d.models || [];
        if (!ms.length) return "<div class='loading'>暂无数据</div>";
        var top = ms[0];
        var open = ms.filter(function (m) { return m.open; })[0];
        return row("综合第一", esc(top.name) + (top.flag ? " " + top.flag : "")) +
          row("开源第一", open ? esc(open.name) + (open.flag ? " " + open.flag : "") : "—", "dim");
      } },
    { folder: "university-rankings", en: "Universities", name: "全球大学排名 300 强", tag: "QS · THE · ARWU · U.S. News 四榜合一",
      render: function (d) {
        var us = d.universities || []; if (!us.length) return "<div class='loading'>暂无数据</div>";
        var top = us[0];
        return row("综合第一", (top.flag ? top.flag + " " : "") + esc(top.cn || top.name)) +
          row("综合前 " + (d.count || us.length), "QS/THE/ARWU/USN 平均位次", "dim");
      } },
    { folder: "major-rankings", en: "Majors", name: "全球专业与就业前景榜", tag: "薪资 · 就业率 · 起薪 · AI 时代前景",
      render: function (d) {
        var ms = d.majors || []; if (!ms.length) return "<div class='loading'>暂无数据</div>";
        var byMid = ms.slice().sort(function (a, b) { return b.mid - a.mid; })[0];
        var byFut = ms.slice().sort(function (a, b) { return b.future - a.future; })[0];
        return row("薪资第一", esc(byMid.cn) + " $" + Math.round(byMid.mid / 1000) + "K") +
          row("AI 前景第一", esc(byFut.cn), "dim");
      } },
    { folder: "econ-calendar", en: "Calendar", name: "全球经济日历", tag: "央行决议 · CPI · 非农",
      render: function (d) {
        var evs = d.events || [], now = Date.now();
        var ev = evs.filter(function (e) { return e.impact === "high" && Date.parse(e.ts) >= now; })[0] ||
          evs.filter(function (e) { return e.impact === "high"; })[0] || evs[0];
        if (!ev) return "<div class='loading'>暂无数据</div>";
        return "<div class='news'>" + (ev.flag || "🌐") + " " + esc(ev.title) + "</div>" +
          "<div class='sub'>预测 " + esc(ev.forecast || "—") + " · 前值 " + esc(ev.previous || "—") +
          (isNum(d.count) ? " · 本周 " + d.count + " 项" : "") + "</div>";
      } },
    { folder: "ofr-monitor", en: "OFR Risk", name: "美国金融风险监测", tag: "OFR · 金融压力 · SOFR · 货币基金 · 系统性风险",
      render: function (d) {
        var f = d.fsi || {}; if (!isNum(f.value)) return "<div class='loading'>暂无数据</div>";
        var col = f.value > 0.5 ? "#e0554f" : f.value < -0.5 ? "#3fae7d" : "#e4b53d";
        var lab = f.value > 0.5 ? "高于平均压力" : f.value < -0.5 ? "低于平均压力" : "接近平均";
        var h = "<div class='big' style='color:" + col + "'>" + f.value.toFixed(2) +
          "<small style='color:" + col + "'>金融压力 · " + lab + "</small></div>";
        var fu = d.funding || {};
        if (fu.sofr && isNum(fu.sofr.value)) h += row("SOFR 隔夜利率", fu.sofr.value.toFixed(2) + "%");
        if (d.mmf && isNum(d.mmf.total)) h += row("货币基金规模", "$" + d.mmf.total.toFixed(2) + "T");
        return h;
      } }
  ];

  // 各应用 data.json 只取一次，卡片与「今日市场」头版共用，避免重复请求
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
    a.className = "art"; a.href = "../" + app.folder + "/";
    a.innerHTML =
      "<div class='hn'><span class='t'>" + app.name + "</span><span class='tag'>" + (app.en || "") + "</span></div>" +
      "<div class='body'><div class='loading'>加载中…</div></div>" +
      "<div class='upd'>—</div>";
    var body = a.querySelector(".body"), upd = a.querySelector(".upd");
    getData(app.folder)
      .then(function (d) {
        try { body.innerHTML = app.render(d); } catch (e) { body.innerHTML = "<div class='loading'>预览不可用</div>"; }
        upd.textContent = relTime(d.updatedAt);
      })
      .catch(function () { body.innerHTML = "<div class='loading'>数据暂不可用</div>"; });
    return a;
  }

  // 「今日市场」头版：情绪读数领衔 + 首富/市值/资产总市值侧栏，数据到齐即渐进渲染
  function buildLead() {
    var lead = $("lead"); if (!lead) return;
    var st = { fg: null, mv: null, rich: null, cap: null, ass: null };
    function sr(k, sub, v) {
      return "<div class='sr'><div class='sk'>" + esc(k) + "<em>" + esc(sub) + "</em></div><div class='sv'>" + v + "</div></div>";
    }
    function render() {
      var feat = "";
      if (st.fg) {
        feat += "<div class='hn'>市场情绪 · Fear &amp; Greed</div>";
        feat += "<div class='num'>" + st.fg.score + "</div>";
        var cap = "市场处于 <b>" + esc(st.fg.rating || "—") + "</b> 区间。";
        if (st.mv) {
          cap += "年初至今 <b class='up'>" + esc(st.mv.topName) + " " + pct(st.mv.top) + "</b> 领涨全球，" +
            "<b class='down'>" + esc(st.mv.botName) + " " + pct(st.mv.bot) + "</b> 领跌。";
        }
        feat += "<div class='cap'>" + cap + "</div>";
      }
      var side = "";
      if (st.rich) side += sr("全球首富", st.rich.name, worth(st.rich.worth));
      if (st.cap) side += sr("市值 #1", st.cap.name, worth(st.cap.worth));
      if (st.ass) side += sr("资产总市值", "前 250 · 含房产/国债/黄金", worth(st.ass.total));
      if (!feat && !side) return;
      lead.innerHTML = "<div>" + feat + "</div><div class='side'>" + side + "</div>";
      lead.className = "lead show";
    }
    getData("fear-greed").then(function (d) {
      if (isNum(d.score)) st.fg = { score: d.score, rating: d.ratingZh || "" };
      if (d.asOf) $("mDate").textContent = d.asOf;
      render();
    }).catch(function () {});
    getData("asset-tracker").then(function (d) {
      var a = (d.assets || []).filter(function (x) { return x.returns && isNum(x.returns.ytd); })
        .sort(function (x, y) { return y.returns.ytd - x.returns.ytd; });
      if (a.length) {
        var t = a[0], b = a[a.length - 1];
        st.mv = { topName: t.name, top: t.returns.ytd, botName: b.name, bot: b.returns.ytd };
        render();
      }
    }).catch(function () {});
    getData("billionaires").then(function (d) {
      var p = (d.people || [])[0];
      if (p) { st.rich = { name: p.name, worth: p.worth }; render(); }
    }).catch(function () {});
    getData("companies").then(function (d) {
      var c = (d.companies || [])[0];
      if (c) { st.cap = { name: c.name, worth: c.marketCap }; render(); }
    }).catch(function () {});
    getData("asset-ranking").then(function (d) {
      if (isNum(d.totalMarketCap)) { st.ass = { total: d.totalMarketCap }; render(); }
    }).catch(function () {});
  }

  function boot() {
    buildLead();
    var grid = $("grid");
    APPS.forEach(function (app) { grid.appendChild(card(app)); });
    $("foot").innerHTML = "各应用数据每日自动更新（来源 Yahoo Finance · CoinGecko · OECD · BIS · OFR · Forbes · CNN · Google News · World Bank · Forex Factory · QS · THE · ARWU · U.S. News · PayScale · NACE · BLS · WEF）。仅供参考，不构成建议。";
  }
  boot();
})();
