/* 全球公司市值榜 · 前端渲染
 * 读取同目录 data.json（由 scripts/companies/build_companies.py 每日生成），
 * 渲染按市值排名的公司卡片（logo / 市值 / 股价 / 当日涨跌 / 30天迷你走势 / 市值条），
 * 支持按市值·今日涨幅·今日跌幅排序与中英名/代码搜索。纯原生 JS。 */
(function () {
  "use strict";

  var DATA = null, MAXC = 1;
  var state = { sort: "rank", q: "" };
  var $ = function (id) { return document.getElementById(id); };
  var raf = (typeof requestAnimationFrame !== "undefined")
    ? requestAnimationFrame : function (f) { return setTimeout(f, 16); };

  function isNum(v) { return v !== null && v !== undefined && !isNaN(v); }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  var CURSYM = { USD: "$", EUR: "€", JPY: "¥", HKD: "HK$", KRW: "₩",
    TWD: "NT$", INR: "₹", CHF: "CHF ", SAR: "SAR ", GBP: "£", CNY: "¥" };

  function fmtCap(b) {
    if (!isNum(b)) return "—";
    return b >= 1000 ? "$" + (b / 1000).toFixed(2) + "T" : "$" + b.toFixed(1) + "B";
  }
  function fmtPrice(p, cur) {
    if (!isNum(p)) return "—";
    var sym = CURSYM[cur] || "";
    return sym + (p >= 1000 ? p.toLocaleString("en-US", { maximumFractionDigits: 2 }) : p.toFixed(2));
  }
  function fmtPct(v) { return !isNum(v) ? null : (v >= 0 ? "+" : "−") + Math.abs(v).toFixed(2) + "%"; }
  function pctClass(v) { return !isNum(v) ? "flat" : (v > 0 ? "up" : (v < 0 ? "down" : "flat")); }
  function pctArrow(v) { return !isNum(v) ? "·" : (v > 0 ? "▲" : (v < 0 ? "▼" : "·")); }

  function sorted() {
    var list = (DATA.companies || []).filter(function (c) {
      if (!state.q) return true;
      var q = state.q.toLowerCase();
      return (c.name || "").toLowerCase().indexOf(q) >= 0 ||
             (c.nameEn || "").toLowerCase().indexOf(q) >= 0 ||
             (c.symbol || "").toLowerCase().indexOf(q) >= 0;
    });
    var s = state.sort;
    return list.slice().sort(function (a, b) {
      if (s === "rank") return a.rank - b.rank;
      var ca = isNum(a.changePct) ? a.changePct : (s === "gain" ? -1e9 : 1e9);
      var cb = isNum(b.changePct) ? b.changePct : (s === "gain" ? -1e9 : 1e9);
      return s === "gain" ? cb - ca : ca - cb;
    });
  }

  function logoEl(c) {
    var box = document.createElement("div"); box.className = "logo";
    var ini = (c.nameEn || c.name || "?").trim().charAt(0).toUpperCase();
    // 只用本地同源 logo（apps/companies/logos/，由工作流预先下载）；缺失则字母牌。
    // 不再请求任何境外图床，保证中国大陆无 VPN 也零卡顿、秒出。
    var mono = '<div class="ini">' + ini + "</div>";
    if (!c.logo) { box.innerHTML = mono; return box; }
    var img = document.createElement("img");
    img.src = c.logo; img.alt = c.name; img.loading = "lazy"; img.referrerPolicy = "no-referrer";
    img.onerror = function () { box.innerHTML = mono; };
    box.appendChild(img);
    return box;
  }

  function renderList() {
    var wrap = $("list"); wrap.innerHTML = "";
    var list = sorted();
    if (!list.length) { wrap.innerHTML = '<div class="empty">没有匹配的公司，换个关键词试试 🙂</div>'; return; }
    var grow = [], dividerShown = false;
    list.forEach(function (c, i) {
      if (c.private && !dividerShown) {
        dividerShown = true;
        var dv = document.createElement("div"); dv.className = "divider";
        dv.innerHTML = "<span>🌐 全球最有价值私营公司 · 未上市 / 待上市 · 最新估值（非实时）</span>";
        wrap.appendChild(dv);
      }
      var card = document.createElement("div"); card.className = "rowcard";
      card.style.animationDelay = Math.min(i * 14, 360) + "ms";

      var rk = document.createElement("div");
      rk.className = "rk" + (c.rank <= 3 ? " top" : ""); rk.textContent = c.rank;

      var info = document.createElement("div"); info.className = "info";
      var nm = document.createElement("div"); nm.className = "nm";
      nm.innerHTML = esc(c.name) + (c.nameEn && c.nameEn !== c.name ? '<span class="en">' + esc(c.nameEn) + "</span>" : "") +
        (c.private ? '<span class="pri">未上市</span>' : "");
      var meta = document.createElement("div"); meta.className = "meta";
      meta.textContent = [(c.flag || "") + (c.country || ""), c.sector,
        c.private ? (c.lastRound ? "上轮融资 " + c.lastRound : "") : c.symbol].filter(Boolean).join(" · ");
      info.appendChild(nm); info.appendChild(meta);

      var money = document.createElement("div"); money.className = "money";
      var cap = document.createElement("div"); cap.className = "cap"; cap.textContent = fmtCap(c.marketCap);
      var px = document.createElement("div"); px.className = "px";
      if (c.private) {
        px.innerHTML = '<span style="color:var(--dim)">最新估值</span>';
      } else {
        var pxHtml = esc(fmtPrice(c.price, c.priceCur));
        var ps = fmtPct(c.changePct);
        if (ps) pxHtml += ' <span class="chg ' + pctClass(c.changePct) + '">' + pctArrow(c.changePct) + " " + ps + "</span>";
        px.innerHTML = pxHtml;
      }
      money.appendChild(cap); money.appendChild(px);

      var bg = document.createElement("div"); bg.className = "wbarbg";
      var bar = document.createElement("div"); bar.className = "wbar"; bar.style.width = "0%";
      grow.push([bar, Math.max(1.5, (c.marketCap / MAXC) * 100)]);

      card.appendChild(rk); card.appendChild(logoEl(c)); card.appendChild(info);
      card.appendChild(money);
      card.appendChild(bg); card.appendChild(bar);
      wrap.appendChild(card);
    });
    raf(function () { grow.forEach(function (g) { g[0].style.width = g[1] + "%"; }); });
  }

  function renderSummary() {
    var cs = DATA.companies || [], el = $("summary");
    var withChg = cs.filter(function (c) { return isNum(c.changePct); });
    var top = withChg.slice().sort(function (a, b) { return b.changePct - a.changePct; })[0];
    var bot = withChg.slice().sort(function (a, b) { return a.changePct - b.changePct; })[0];
    var totalT = isNum(DATA.totalMarketCap) ? "$" + (DATA.totalMarketCap / 1000).toFixed(2) + "T" : "—";
    var html = '<span class="pill-i">📅 ' + (DATA.asOf || "—") + "</span>" +
      '<span class="pill-i">前 ' + (DATA.count || cs.length) + ' 总市值 <b class="big">' + totalT + "</b></span>" +
      (DATA.listedCount ? '<span class="pill-i">' + DATA.listedCount + " 上市 · " + DATA.privateCount + " 未上市</span>" : "");
    if (top && top.changePct > 0) html += '<span class="lead up">▲ 今日领涨 ' + esc(top.name) + " " + fmtPct(top.changePct) + "</span>";
    if (bot && bot.changePct < 0) html += '<span class="lead down">▼ 今日领跌 ' + esc(bot.name) + " " + fmtPct(bot.changePct) + "</span>";
    el.innerHTML = html;
  }

  function renderStatus() {
    var src = DATA.source || "";
    var live = !!src && !/示例/.test(src);
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
    MAXC = Math.max.apply(null, (DATA.companies || [{ marketCap: 1 }]).map(function (c) { return c.marketCap || 0; })) || 1;
    renderStatus(); renderSummary(); initControls(); renderList(); renderFooter();
  }

  fetch("data.json?t=" + Date.now())
    .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(boot)
    .catch(function (e) {
      $("list").innerHTML = '<div class="empty">数据加载失败：' + esc(e.message) + "<br>请稍后刷新重试。</div>";
    });
})();
