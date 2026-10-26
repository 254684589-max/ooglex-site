/* 数据中心 · 四张大数字卡片。数字只来自各应用已有的 data.json，不另造读数。纯原生 JS。 */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  function isNum(v) { return v !== null && v !== undefined && v !== "" && !isNaN(v); }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  /* 十亿美元。≥1000 显示为万亿，与富豪榜、资产榜页面同一套写法。 */
  function worth(b) { return !isNum(b) ? "—" : (b >= 1000 ? "$" + (b / 1000).toFixed(2) + "T" : "$" + b.toFixed(1) + "B"); }

  var APPS = [
    { folder: "fear-greed", name: "恐慌与贪婪指数" },
    { folder: "macro-radar", name: "宏观风险监测" },
    { folder: "ofr-monitor", name: "美国金融风险监测" },
    { folder: "econ-calendar", name: "全球经济日历" },
    // 标普500热力图读公司管道另出的成分股快照（sp500.json），不是公司榜本身。
    { folder: "heatmap", dataFolder: "companies", dataFile: "sp500.json", name: "标普500热力图" },
    // 全球市场行情自己不产数据文件：预览读它体量最大的跨资产管道，并在数字旁写明这是全球市场行情。
    { folder: "markets", dataFolder: "asset-tracker", name: "全球市场行情" },
    { folder: "world-economy", name: "全球经济图谱" },
    { folder: "asset-ranking", name: "全球资产市值榜" },
    { folder: "asset-tracker", name: "全球大类资产收益率" },
    { folder: "house-prices", name: "全球房价走势" },
    { folder: "billionaires", name: "福布斯亿万富翁实时排行榜" },
    { folder: "companies", name: "全球公司市值榜" },
    { folder: "superinvestors", name: "超级投资者持仓" },
    { folder: "ai-rankings", name: "全球大模型评测榜" },
    { folder: "university-rankings", name: "全球大学排名 300 强" },
    { folder: "major-rankings", name: "全球专业与就业前景榜" }
  ];

  /* 附图上的四个主读数，以及仍需留在卡片里的其余入口。
     资产总市值放在「人物与公司」是附图的位置，数字仍是资产市值榜的合计，点进去也是那一页。 */
  var GROUPS = [
    { id: "risk", name: "情绪与风险", hero: "risk",
      extras: ["ofr-monitor", "econ-calendar"] },
    { id: "index", name: "指数与热力图", hero: "index",
      extras: ["world-economy"] },
    { id: "assets", name: "资产与回报", hero: "assets",
      extras: ["house-prices"] },
    { id: "people", name: "人物与公司", hero: "people",
      extras: ["companies", "superinvestors", "ai-rankings", "university-rankings", "major-rankings"] }
  ];

  var _cache = {};
  function getJSON(url) {
    if (!_cache[url]) {
      _cache[url] = fetch(url + (url.indexOf("?") < 0 ? "?t=" + Date.now() : ""))
        .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); });
    }
    return _cache[url];
  }
  function getData(folder, file) { return getJSON("../" + folder + "/" + (file || "data.json")); }
  function settle(p) {
    return p.then(function (v) { return { ok: true, v: v }; }, function () { return { ok: false }; });
  }

  function linkOpen(folder, cls, label) {
    var html = "<a class=\"" + cls + "\" href=\"../" + folder + "/\"";
    if (label) html += " aria-label=\"" + esc(label) + "\"";
    return html + ">";
  }
  function numLink(folder, cls, text, label) {
    return linkOpen(folder, cls, label) + esc(text) + "</a>";
  }
  function capLink(folder, inner, title) {
    var html = "<a class=\"cap\" href=\"../" + folder + "/\"";
    if (title) html += " title=\"" + esc(title) + "\"";
    return html + ">" + inner + "</a>";
  }

  function sideHero(n1, n2, caps) {
    return "<div class=\"hero side\"><div class=\"nums\">" + n1 + n2 + "</div><div class=\"caps\">" + caps + "</div></div>";
  }
  function missingCap() { return "<span class=\"k\">暂无数据</span>"; }

  function paintRisk(slot) {
    slot.innerHTML = "<div class=\"hero side\"><span class=\"loading\">加载中…</span></div>";
    Promise.all([settle(getData("fear-greed")), settle(getData("macro-radar"))]).then(function (rs) {
      var fg = rs[0].ok ? rs[0].v : {};
      var regime = rs[1].ok && rs[1].v.regime ? rs[1].v.regime : {};
      var s1 = isNum(fg.score) ? String(fg.score) : "—";
      var s2 = isNum(regime.score) ? String(regime.score) : "—";
      var rating = fg.ratingZh || "—";
      var label = regime.labelZh || "—";
      var cap1 = isNum(fg.score)
        ? "<span class=\"k\">市场处于</span><b>" + esc(rating) + "</b>"
        : missingCap();
      var cap2 = isNum(regime.score)
        ? "<b class=\"accent\">" + esc(s2) + "</b> <span class=\"k\">" + esc(label) + "</span>"
        : missingCap();
      slot.innerHTML = sideHero(
        numLink("fear-greed", "n1", s1, "恐慌与贪婪指数"),
        numLink("macro-radar", "n2", s2, "宏观风险监测"),
        capLink("fear-greed", cap1) + capLink("macro-radar", cap2, "宏观风险监测")
      );
    });
  }

  function paintIndex(slot) {
    slot.innerHTML = "<div class=\"hero side\"><span class=\"loading\">加载中…</span></div>";
    Promise.all([
      settle(getData("companies", "sp500.json")),
      settle(getData("asset-tracker"))
    ]).then(function (rs) {
      var heat = rs[0].ok ? rs[0].v : {};
      var book = rs[1].ok ? rs[1].v : {};
      var members = (heat.members || []).filter(function (x) { return isNum(x.changePct); });
      var listed = isNum(heat.count) ? heat.count : (members.length || null);
      var cross = (book.assets || []).filter(function (x) { return x.returns && isNum(x.returns.d1); });
      var s1 = listed != null ? String(listed) : "—";
      var s2 = cross.length ? String(cross.length) : "—";
      slot.innerHTML = sideHero(
        numLink("heatmap", "n1", s1, "标普500热力图"),
        numLink("markets", "n2", s2, "全球市场行情"),
        capLink("heatmap", "<span class=\"k\">标普500</span>", "标普500热力图") +
          capLink("markets", "<span class=\"k\">全球市场行情</span>")
      );
    });
  }

  function paintAssets(slot) {
    slot.innerHTML = "<div class=\"hero stack\"><span class=\"loading\">加载中…</span></div>";
    settle(getData("asset-ranking")).then(function (r) {
      var top = r.ok && r.v.assets ? r.v.assets[0] : null;
      var big = top ? worth(top.marketCap) : "—";
      slot.innerHTML =
        "<div class=\"hero stack\">" +
          numLink("asset-ranking", "n1 money", big, "全球资产市值榜") +
          "<div class=\"caps under\">" +
            capLink("asset-tracker", "<span class=\"k\">全球大类资产</span>", "全球大类资产收益率") +
            capLink("asset-ranking", "<span class=\"k\">全球资产市值</span>", "全球资产市值榜") +
          "</div>" +
        "</div>";
    });
  }

  function paintPeople(slot) {
    slot.innerHTML = "<div class=\"hero people\"><span class=\"loading\">加载中…</span></div>";
    Promise.all([settle(getData("billionaires")), settle(getData("asset-ranking"))]).then(function (rs) {
      var person = rs[0].ok && rs[0].v.people ? rs[0].v.people[0] : null;
      var book = rs[1].ok ? rs[1].v : {};
      var fortune = person ? worth(person.worth) : "—";
      var total = worth(book.totalMarketCap);
      slot.innerHTML =
        "<div class=\"hero people\">" +
          "<div class=\"rowline lead\">" +
            numLink("billionaires", "n1 money", fortune, "福布斯亿万富翁实时排行榜") +
            capLink("billionaires", "<span class=\"k\">全球首富</span>", "福布斯亿万富翁实时排行榜") +
          "</div>" +
          "<div class=\"rowline minor\">" +
            numLink("asset-ranking", "n3", total, "资产总市值") +
            capLink("asset-ranking", "<span class=\"k\">资产总市值</span>", "全球资产市值榜") +
          "</div>" +
        "</div>";
    });
  }

  var PAINT = { risk: paintRisk, index: paintIndex, assets: paintAssets, people: paintPeople };

  function moreNav(folders, byFolder) {
    var links = [];
    folders.forEach(function (folder) {
      var app = byFolder[folder];
      if (!app) return;
      links.push("<a href=\"../" + folder + "/\">" + esc(app.name) + "</a>");
    });
    if (!links.length) return null;
    var nav = document.createElement("nav");
    nav.className = "more";
    nav.setAttribute("aria-label", "更多应用");
    nav.innerHTML = links.join("");
    return nav;
  }

  function stampDate() {
    getData("fear-greed").then(function (d) {
      if (d.asOf && $("mDate")) $("mDate").textContent = d.asOf;
    }).catch(function () {});
  }

  function boot() {
    stampDate();
    var board = $("board");
    if (!board) return;
    var byFolder = {};
    APPS.forEach(function (app) { byFolder[app.folder] = app; });
    var placed = {
      "fear-greed": true, "macro-radar": true, "heatmap": true, "markets": true,
      "asset-ranking": true, "asset-tracker": true, "billionaires": true
    };
    GROUPS.forEach(function (g) { g.extras.forEach(function (folder) { placed[folder] = true; }); });
    var loose = APPS.filter(function (app) { return !placed[app.folder]; }).map(function (app) { return app.folder; });
    if (loose.length) GROUPS[GROUPS.length - 1].extras = GROUPS[GROUPS.length - 1].extras.concat(loose);

    GROUPS.forEach(function (g) {
      var sec = document.createElement("section");
      sec.className = "hub-card";
      sec.setAttribute("aria-labelledby", "hub-" + g.id);
      var h = document.createElement("h2");
      h.className = "pill";
      h.id = "hub-" + g.id;
      h.textContent = g.name;
      var slot = document.createElement("div");
      slot.className = "hero-slot";
      sec.appendChild(h);
      sec.appendChild(slot);
      var nav = moreNav(g.extras, byFolder);
      if (nav) sec.appendChild(nav);
      board.appendChild(sec);
      if (PAINT[g.hero]) PAINT[g.hero](slot);
    });
    $("foot").innerHTML = "各应用数据每日自动更新（来源 Yahoo Finance · CoinGecko · OECD · BIS · OFR · Forbes · CNN · Google News · World Bank · Forex Factory · QS · THE · ARWU · U.S. News · PayScale · NACE · BLS · WEF）。仅供参考，不构成建议。";
  }
  boot();
})();
