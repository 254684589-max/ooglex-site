/* 全球富豪实时榜 · 前端渲染
 * 读取同目录 data.json（由 scripts/billionaires/build_billionaires.py 每日生成），
 * 渲染前 250 富豪排行卡片（头像 / 身价 / 当日变动 / 净值条），支持排序与搜索。纯原生 JS。 */
(function () {
  "use strict";

  var DATA = null, MAXW = 1;
  var state = { sort: "rank", q: "" };
  var $ = function (id) { return document.getElementById(id); };
  var raf = (typeof requestAnimationFrame !== "undefined")
    ? requestAnimationFrame : function (f) { return setTimeout(f, 16); };

  function isNum(v) { return v !== null && v !== undefined && !isNaN(v); }

  function fmtWorth(w) {
    if (!isNum(w)) return "—";
    return w >= 1000 ? "$" + (w / 1000).toFixed(2) + "T" : "$" + w.toFixed(1) + "B";
  }
  function fmtChange(c) {
    if (!isNum(c)) return null;
    var s = c >= 0 ? "+" : "−", a = Math.abs(c);
    return a >= 1 ? s + "$" + a.toFixed(2) + "B" : s + "$" + (a * 1000).toFixed(0) + "M";
  }
  function chgClass(c) { return !isNum(c) ? "flat" : (c > 0 ? "up" : (c < 0 ? "down" : "flat")); }
  function chgArrow(c) { return !isNum(c) ? "·" : (c > 0 ? "▲" : (c < 0 ? "▼" : "·")); }

  function sorted() {
    var list = (DATA.people || []).filter(function (p) {
      if (!state.q) return true;
      var q = state.q.toLowerCase();
      return (p.name || "").toLowerCase().indexOf(q) >= 0 ||
             (p.nameEn || "").toLowerCase().indexOf(q) >= 0;
    });
    var s = state.sort;
    return list.slice().sort(function (a, b) {
      if (s === "rank") return a.rank - b.rank;
      var ca = isNum(a.change) ? a.change : (s === "gain" ? -1e9 : 1e9);
      var cb = isNum(b.change) ? b.change : (s === "gain" ? -1e9 : 1e9);
      return s === "gain" ? cb - ca : ca - cb;
    });
  }

  function avatar(p) {
    var ava = document.createElement("div"); ava.className = "ava";
    var ini = (p.nameEn || p.name || "?").trim().charAt(0).toUpperCase();
    if (p.image) {
      var img = document.createElement("img");
      img.src = p.image; img.alt = p.name; img.loading = "lazy"; img.referrerPolicy = "no-referrer";
      img.onerror = function () { ava.innerHTML = '<div class="ini">' + ini + "</div>"; };
      ava.appendChild(img);
    } else {
      ava.innerHTML = '<div class="ini">' + ini + "</div>";
    }
    return ava;
  }

  function renderList() {
    var wrap = $("list"); wrap.innerHTML = "";
    var list = sorted();
    if (!list.length) { wrap.innerHTML = '<div class="empty">没有匹配的人物，换个关键词试试 🙂</div>'; return; }
    var grow = [];
    list.forEach(function (p, i) {
      var card = document.createElement("div"); card.className = "rowcard";
      card.style.animationDelay = Math.min(i * 14, 360) + "ms";

      var rk = document.createElement("div");
      rk.className = "rk" + (p.rank <= 3 ? " top" : ""); rk.textContent = p.rank;

      var info = document.createElement("div"); info.className = "info";
      var nm = document.createElement("div"); nm.className = "nm";
      nm.innerHTML = esc(p.name) + (p.nameEn && p.nameEn !== p.name ? '<span class="en">' + esc(p.nameEn) + "</span>" : "");
      var meta = document.createElement("div"); meta.className = "meta";
      meta.textContent = [(p.flag || "") + (p.country || ""), p.source, p.industry,
        (isNum(p.age) ? p.age + "岁" : "")].filter(Boolean).join(" · ");
      info.appendChild(nm); info.appendChild(meta);

      var money = document.createElement("div"); money.className = "money";
      var worth = document.createElement("div"); worth.className = "worth"; worth.textContent = fmtWorth(p.worth);
      money.appendChild(worth);
      var cs = (isNum(p.change) && p.change !== 0) ? fmtChange(p.change) : null;
      if (cs) {
        var chg = document.createElement("div"); chg.className = "chg " + chgClass(p.change);
        chg.textContent = chgArrow(p.change) + " " + cs + (isNum(p.changePct) ? " (" + (p.changePct >= 0 ? "+" : "−") + Math.abs(p.changePct).toFixed(2) + "%)" : "");
        money.appendChild(chg);
      }

      var bg = document.createElement("div"); bg.className = "wbarbg";
      var bar = document.createElement("div"); bar.className = "wbar"; bar.style.width = "0%";
      grow.push([bar, Math.max(1.5, (p.worth / MAXW) * 100)]);

      card.appendChild(rk); card.appendChild(avatar(p)); card.appendChild(info);
      card.appendChild(money); card.appendChild(bg); card.appendChild(bar);
      wrap.appendChild(card);
    });
    raf(function () { grow.forEach(function (g) { g[0].style.width = g[1] + "%"; }); });
  }

  function renderSummary() {
    var ppl = DATA.people || [], el = $("summary");
    var withChg = ppl.filter(function (p) { return isNum(p.change); });
    var top = withChg.slice().sort(function (a, b) { return b.change - a.change; })[0];
    var bot = withChg.slice().sort(function (a, b) { return a.change - b.change; })[0];
    var totalT = isNum(DATA.totalWorth) ? "$" + (DATA.totalWorth / 1000).toFixed(2) + "T" : "—";
    var html = '<span class="pill-i">📅 ' + (DATA.asOf || "—") + "</span>" +
      '<span class="pill-i">前 ' + (DATA.count || ppl.length) + ' 总财富 <b class="big">' + totalT + "</b></span>";
    if (top && top.change > 0) html += '<span class="lead up">▲ 今日领涨 ' + esc(top.name) + " " + fmtChange(top.change) + "</span>";
    if (bot && bot.change < 0) html += '<span class="lead down">▼ 今日领跌 ' + esc(bot.name) + " " + fmtChange(bot.change) + "</span>";
    el.innerHTML = html;
  }

  function renderStatus() {
    var live = /forbes/i.test(DATA.source || "") && !/示例/.test(DATA.source || "");
    var el = $("status");
    el.className = "status " + (live ? "live" : "demo");
    el.innerHTML = '<span class="sdot"></span>' + (live ? "实时榜 · 每日自动更新" : "示例数据 · 待每日任务刷新");
  }

  function renderFooter() {
    var upd = DATA.updatedAt ? DATA.updatedAt.replace("T", " ").replace("Z", " UTC") : "—";
    var html = '<div class="src">数据来源 <b>' + esc(DATA.source || "—") + "</b> · 数据日期 <b>" +
      (DATA.asOf || "—") + "</b> · 更新于 " + upd + "</div>";
    if (DATA.note) html += "<div>" + esc(DATA.note) + "</div>";
    $("foot").innerHTML = html;
  }

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  function initControls() {
    $("sorts").querySelectorAll("button").forEach(function (b) {
      b.onclick = function () {
        state.sort = b.getAttribute("data-sort");
        $("sorts").querySelectorAll("button").forEach(function (x) { x.classList.remove("on"); });
        b.classList.add("on"); renderList();
      };
    });
    $("q").oninput = function () { state.q = this.value.trim(); renderList(); };
  }

  function boot(data) {
    DATA = data;
    MAXW = Math.max.apply(null, (DATA.people || [{ worth: 1 }]).map(function (p) { return p.worth || 0; })) || 1;
    renderStatus(); renderSummary(); initControls(); renderList(); renderFooter();
  }

  fetch("data.json?t=" + Date.now())
    .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(boot)
    .catch(function (e) {
      $("list").innerHTML = '<div class="empty">数据加载失败：' + esc(e.message) + "<br>请稍后刷新重试。</div>";
    });
})();
