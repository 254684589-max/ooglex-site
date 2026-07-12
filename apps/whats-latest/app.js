/* 最新消息是什么？ · 前端渲染
 * 读取同目录 data.json（由 scripts/whats-latest/build_news.py 定时生成）：
 * 滚动行情条 + 今日重点 + 板块标签 + 新闻列表（点击直达原文）+ 市场快照栏。纯原生 JS。 */
(function () {
  "use strict";
  var DATA = null, tab = "all";
  var $ = function (id) { return document.getElementById(id); };

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function isNum(v) { return v !== null && v !== undefined && !isNaN(v); }

  function fmtPrice(m) {
    if (!isNum(m.price)) return "—";
    var dec = m.price >= 1000 ? 0 : 2;
    var s = Number(m.price).toLocaleString("en-US", { minimumFractionDigits: dec, maximumFractionDigits: dec });
    return (m.fmt === "usd" ? "$" : "") + s;
  }
  function pctCls(c) { return !isNum(c) ? "flat" : (c > 0 ? "up" : (c < 0 ? "down" : "flat")); }
  function pctTxt(c) { return !isNum(c) ? "" : (c > 0 ? "▲" : (c < 0 ? "▼" : "•")) + Math.abs(c).toFixed(2) + "%"; }

  function relTime(pub) {
    if (!isNum(pub)) return "";
    var diff = Date.now() / 1000 - pub;
    if (diff < 0) return "刚刚";
    if (diff < 3600) return Math.max(1, Math.floor(diff / 60)) + "分钟前";
    if (diff < 86400) return Math.floor(diff / 3600) + "小时前";
    if (diff < 86400 * 30) return Math.floor(diff / 86400) + "天前";
    return "";
  }

  function renderMeta() {
    var live = /google|yahoo|reuters/i.test(DATA.source || "") && !/示例/.test(DATA.source || "");
    var upd = DATA.updatedAt ? DATA.updatedAt.replace("T", " ").replace("Z", " UTC") : "—";
    $("meta").innerHTML =
      "<span class='status " + (live ? "live" : "demo") + "'><span class='sdot'></span>" +
      (live ? "实时聚合 · 自动更新" : "示例数据 · 待刷新") + "</span><br>" +
      "数据日期 " + esc(DATA.asOf || "—") + "<br>更新于 " + esc(upd);
  }

  function renderTicker() {
    var mk = DATA.markets || [];
    if (!mk.length) { $("ticker").parentNode.style.display = "none"; return; }
    var one = mk.map(function (m) {
      return "<span class='tk'><b>" + esc(m.name) + "</b><span class='p'>" + fmtPrice(m) +
        "</span><span class='" + pctCls(m.changePct) + "'>" + pctTxt(m.changePct) + "</span></span>";
    }).join("");
    $("ticker").innerHTML = one + one;   // 复制一份实现无缝滚动
  }

  function renderHighlight() {
    var h = DATA.highlight, el = $("highlight");
    if (!h || !h.title) { el.style.display = "none"; return; }
    el.href = h.link || "#"; el.target = "_blank"; el.rel = "noopener";
    el.innerHTML = "<span class='tag'>今日重点 · " + esc(h.category || "") + "</span>" +
      "<div class='t'>" + esc(h.title) + "</div>" +
      "<div class='m'>" + esc(h.source || "") + (relTime(h.published) ? " · " + relTime(h.published) : "") + " · 点击阅读原文 →</div>";
  }

  function newsItem(it) {
    var t = relTime(it.published);
    return "<a class='news' href='" + esc(it.link || "#") + "' target='_blank' rel='noopener'>" +
      "<div class='t'>" + esc(it.title) + "</div>" +
      "<div class='m'><span class='src'>" + esc(it.source || "来源未知") + "</span>" +
      (t ? " · " + t : "") + "</div></a>";
  }

  function renderNews() {
    var cats = DATA.categories || [], box = $("news"), html = "";
    if (tab === "all") {
      cats.forEach(function (c) {
        if (!c.items || !c.items.length) return;
        html += "<div class='sec-h'>" + esc(c.name) + "</div>" + c.items.map(newsItem).join("");
      });
    } else {
      var c = cats.filter(function (x) { return x.key === tab; })[0];
      html = (c && c.items && c.items.length) ? c.items.map(newsItem).join("") : "<div class='empty'>该板块暂无内容</div>";
    }
    box.innerHTML = html || "<div class='empty'>暂无新闻</div>";
  }

  function renderTabs() {
    var box = $("tabs"); box.innerHTML = "";
    var tabsList = [{ key: "all", name: "全部" }].concat((DATA.categories || []).map(function (c) {
      return { key: c.key, name: c.name };
    }));
    tabsList.forEach(function (t) {
      var b = document.createElement("button");
      b.textContent = t.name;
      if (t.key === tab) b.className = "on";
      b.onclick = function () {
        tab = t.key;
        box.querySelectorAll("button").forEach(function (x) { x.classList.remove("on"); });
        b.classList.add("on"); renderNews();
      };
      box.appendChild(b);
    });
  }

  function renderMarkets() {
    var mk = DATA.markets || [];
    $("mklive").textContent = mk.length ? "● 实时" : "";
    $("markets").innerHTML = mk.length ? mk.map(function (m) {
      return "<div class='q'><span class='qn'>" + esc(m.name) + "</span>" +
        "<span class='qp'>" + fmtPrice(m) + "</span>" +
        "<span class='qc " + pctCls(m.changePct) + "'>" + pctTxt(m.changePct) + "</span></div>";
    }).join("") : "<div class='empty'>暂无行情</div>";
  }

  function renderFooter() {
    var html = "数据来源 <b>" + esc(DATA.source || "—") + "</b>";
    if (DATA.note) html += "<br>" + esc(DATA.note);
    $("foot").innerHTML = html;
  }

  function boot(data) {
    DATA = data;
    renderMeta(); renderTicker(); renderHighlight(); renderTabs(); renderNews(); renderMarkets(); renderFooter();
  }

  fetch("data.json?t=" + Date.now())
    .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(boot)
    .catch(function (e) {
      $("news").innerHTML = "<div class='empty'>数据加载失败：" + esc(e.message) + "<br>请稍后刷新重试。</div>";
    });
})();
