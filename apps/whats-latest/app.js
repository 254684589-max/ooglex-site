/* 最新消息是什么？ · 新闻简报式前端
 * 保留 data.json 数据接口，只重构为报纸/晨报型展示。
 */
(function () {
  "use strict";

  var DATA = null;
  var tab = "all";
  var $ = function (id) { return document.getElementById(id); };

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  function isNum(v) {
    return v !== null && v !== undefined && !isNaN(v);
  }

  function relTime(pub) {
    if (!isNum(pub)) return "";
    var diff = Date.now() / 1000 - Number(pub);
    if (diff < 0) return "刚刚";
    if (diff < 3600) return Math.max(1, Math.floor(diff / 60)) + "分钟前";
    if (diff < 86400) return Math.floor(diff / 3600) + "小时前";
    if (diff < 86400 * 30) return Math.floor(diff / 86400) + "天前";
    return "";
  }

  function weekday(iso) {
    if (!iso) return "";
    var d = new Date(iso + "T00:00:00");
    if (isNaN(d.getTime())) return "";
    return "星期" + ["日","一","二","三","四","五","六"][d.getDay()];
  }

  function renderHeader() {
    var date = DATA.asOf || "—";
    $("edition-date").textContent = date + " · 最新";
    $("dateline").textContent = weekday(date) + " · " + date + " · Ooglex";
  }

  function renderHighlight() {
    var h = DATA.highlight;
    var el = $("highlight");
    if (!h || !h.title) {
      el.style.display = "none";
      return;
    }
    el.href = h.link || "#";
    el.target = "_blank";
    el.rel = "noopener";
    el.innerHTML =
      "<div class='kicker'>今日重点 · " + esc(h.category || "综合") + "</div>" +
      "<div class='title'>" + esc(h.title) + "</div>" +
      "<div class='meta'>" + esc(h.source || "来源未知") +
      (relTime(h.published) ? " · " + relTime(h.published) : "") +
      " · 阅读全文 →</div>";
  }

  function getCategory(key) {
    return (DATA.categories || []).filter(function (c) { return c.key === key; })[0] || null;
  }

  function newsItem(it) {
    var summary = it.summary || it.description || "";
    return "<a class='story' href='" + esc(it.link || "#") + "' target='_blank' rel='noopener'>" +
      "<div class='story-title'>" + esc(it.title) + "</div>" +
      (summary ? "<div class='story-summary'>" + esc(summary) + "</div>" : "") +
      "<div class='story-meta'><span class='source'>" + esc(it.source || "来源未知") + "</span>" +
      (relTime(it.published) ? " · " + relTime(it.published) : "") +
      " · 阅读全文 →</div></a>";
  }

  function renderNews() {
    var cats = DATA.categories || [];
    var box = $("news");
    var html = "";

    if (tab === "all") {
      cats.forEach(function (c) {
        if (!c.items || !c.items.length) return;
        html += "<section class='section'>" +
          "<h3 class='section-title'>" + esc(c.name) + "</h3>" +
          c.items.map(newsItem).join("") +
          "</section>";
      });
    } else {
      var c = getCategory(tab);
      if (c && c.items && c.items.length) {
        html = "<section class='section'>" +
          "<h3 class='section-title'>" + esc(c.name) + "</h3>" +
          c.items.map(newsItem).join("") +
          "</section>";
      }
    }

    box.innerHTML = html || "<div class='empty'>该板块暂无内容</div>";
  }

  function renderTabs() {
    var box = $("tabs");
    box.innerHTML = "";
    var tabs = [{ key: "all", name: "概述" }].concat((DATA.categories || []).map(function (c) {
      return { key: c.key, name: c.name };
    }));

    tabs.forEach(function (t) {
      var b = document.createElement("button");
      b.type = "button";
      b.textContent = t.name;
      if (t.key === tab) b.className = "on";
      b.onclick = function () {
        tab = t.key;
        box.querySelectorAll("button").forEach(function (x) { x.classList.remove("on"); });
        b.classList.add("on");
        renderNews();
      };
      box.appendChild(b);
    });
  }

  function fmtPrice(m) {
    if (!isNum(m.price)) return "—";
    var p = Number(m.price);
    var dec = p >= 1000 ? 0 : 2;
    var s = p.toLocaleString("en-US", { minimumFractionDigits: dec, maximumFractionDigits: dec });
    return (m.fmt === "usd" ? "$" : "") + s;
  }

  function pctClass(v) {
    return !isNum(v) ? "flat" : (Number(v) > 0 ? "up" : (Number(v) < 0 ? "down" : "flat"));
  }

  function pctText(v) {
    if (!isNum(v)) return "—";
    v = Number(v);
    return (v > 0 ? "▲" : (v < 0 ? "▼" : "•")) + Math.abs(v).toFixed(2) + "%";
  }

  function renderMarkets() {
    var mk = DATA.markets || [];
    $("markets").innerHTML = mk.length ? mk.map(function (m) {
      return "<div class='quote'>" +
        "<span class='name'>" + esc(m.name) + "</span>" +
        "<span class='value'>" + fmtPrice(m) +
          "<span class='pct " + pctClass(m.changePct) + "'>" + pctText(m.changePct) + "</span>" +
        "</span></div>";
    }).join("") : "<div class='empty'>暂无行情</div>";
  }

  function railStory(it) {
    if (!it) return "";
    return "<a class='rail-story' href='" + esc(it.link || "#") + "' target='_blank' rel='noopener'>" +
      "<div class='when'>" + (relTime(it.published) || "最新") + "</div>" +
      "<div class='t'>" + esc(it.title) + "</div>" +
      "<div class='m'>" + esc(it.source || "来源未知") + " · <span class='read-more'>阅读全文 →</span></div>" +
      "</a>";
  }

  function renderRail(key, id, n) {
    var c = getCategory(key);
    var items = c && c.items ? c.items.slice(0, n || 2) : [];
    $(id).innerHTML = items.length ? items.map(railStory).join("") : "<div class='empty'>暂无内容</div>";
  }

  function renderFooter() {
    var upd = DATA.updatedAt ? DATA.updatedAt.replace("T", " ").replace("Z", " UTC") : "—";
    $("sources").innerHTML =
      "数据来源 <b>" + esc(DATA.source || "—") + "</b> · 更新于 " + esc(upd) +
      (DATA.note ? "<br>" + esc(DATA.note) : "");
  }

  function boot(data) {
    DATA = data;
    renderHeader();
    renderTabs();
    renderHighlight();
    renderNews();
    renderMarkets();
    renderRail("tech", "rail-tech", 2);
    renderRail("world", "rail-world", 2);
    renderRail("markets", "rail-markets", 2);
    renderFooter();
  }

  fetch("data.json?t=" + Date.now())
    .then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    })
    .then(boot)
    .catch(function (e) {
      $("news").innerHTML = "<div class='empty'>数据加载失败：" + esc(e.message) + "<br>请稍后刷新重试。</div>";
    });
})();
