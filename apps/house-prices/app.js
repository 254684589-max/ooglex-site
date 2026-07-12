/* 全球主要国家房价走势 · 前端渲染
 * 读取同目录 data.json（由 scripts/house-prices/build_house_prices.py 每周生成）。
 * 列表：各国 名义/实际同比、环比 + 近几年迷你走势；点击任一国家展开近 20 年历史走势折线图
 * （带坐标轴、悬停读数与统计）。支持区域筛选、按同比/环比排序与搜索。红涨绿跌。纯原生 JS。 */
(function () {
  "use strict";

  var DATA = null, REG = {};
  var state = { sort: "nom", q: "", reg: "all", open: {} };
  var $ = function (id) { return document.getElementById(id); };

  function isNum(v) { return v !== null && v !== undefined && !isNaN(v); }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function fmtPct(v, d) { return !isNum(v) ? "—" : (v >= 0 ? "+" : "−") + Math.abs(v).toFixed(d == null ? 1 : d) + "%"; }
  function cls(v) { return !isNum(v) ? "flat" : (v > 0 ? "up" : (v < 0 ? "down" : "flat")); }
  var KEYMAP = { nom: "yoyNominal", real: "yoyReal", qoq: "qoq" };

  function filtered() {
    var q = state.q.toLowerCase();
    return (DATA.countries || []).filter(function (c) {
      if (state.reg !== "all" && c.region !== state.reg) return false;
      if (!q) return true;
      return (c.name || "").toLowerCase().indexOf(q) >= 0 ||
             (c.nameEn || "").toLowerCase().indexOf(q) >= 0;
    });
  }
  function sorted(list) {
    var k = KEYMAP[state.sort];
    return list.slice().sort(function (a, b) {
      var va = isNum(a[k]) ? a[k] : -1e9, vb = isNum(b[k]) ? b[k] : -1e9;
      return vb - va;
    });
  }

  /* 迷你走势图：给定点数组，画归一化折线，按 涨/跌 着色（红涨绿跌）。 */
  function sparkline(pts) {
    if (!pts || pts.length < 2) return "";
    var vs = pts.map(function (t) { return t.v; });
    var lo = Math.min.apply(null, vs), hi = Math.max.apply(null, vs), rng = (hi - lo) || 1;
    var W = 96, H = 34, pad = 3, n = vs.length;
    var P = vs.map(function (v, i) {
      return [pad + (W - 2 * pad) * (i / (n - 1)), pad + (H - 2 * pad) * (1 - (v - lo) / rng)];
    });
    var up = vs[n - 1] >= vs[0], col = up ? "var(--up)" : "var(--down)";
    var d = P.map(function (p, i) { return (i ? "L" : "M") + p[0].toFixed(1) + " " + p[1].toFixed(1); }).join(" ");
    var area = "M" + P[0][0].toFixed(1) + " " + (H - pad) + " " + d.substring(1) +
      " L" + P[n - 1][0].toFixed(1) + " " + (H - pad) + " Z";
    var gid = "s" + Math.random().toString(36).slice(2, 8);
    return '<svg viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none">' +
      '<defs><linearGradient id="' + gid + '" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0" stop-color="' + col + '" stop-opacity="0.28"/>' +
      '<stop offset="1" stop-color="' + col + '" stop-opacity="0"/></linearGradient></defs>' +
      '<path d="' + area + '" fill="url(#' + gid + ')"/>' +
      '<path d="' + d + '" fill="none" stroke="' + col + '" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round"/>' +
      '<circle cx="' + P[n - 1][0].toFixed(1) + '" cy="' + P[n - 1][1].toFixed(1) + '" r="2" fill="' + col + '"/></svg>';
  }

  function regTag(c) {
    var r = REG[c.region];
    return r ? '<span class="rtag" style="color:' + r.color + '">' + esc(r.label) + "</span>" : "";
  }
  function metaOf(c) {
    return [(c.index != null ? "指数 " + c.index : ""), (c.base || ""),
      (c.asOf ? "截至 " + c.asOf : "")].filter(Boolean).join(" · ") +
      (c.seed ? " · 近似" : (c.stale ? " · 沿用上次" : ""));
  }

  /* —— 展开面板：近 20 年历史走势折线图（坐标轴 + 悬停读数 + 统计）—— */
  var PLOTH = 220;
  function yoyAt(hist, i) {                          // 该点相对 4 季前的名义同比
    if (i < 4) return null;
    var b = hist[i - 4].v;
    return b ? (hist[i].v / b - 1) * 100 : null;
  }
  function buildDetail(c) {
    var el = document.createElement("div"); el.className = "detail";
    var hist = c.trend || [];
    if (hist.length < 4) { el.innerHTML = '<div class="dnote">暂无足够历史数据可展示</div>'; return el; }
    var vs = hist.map(function (h) { return h.v; });
    var n = vs.length, lo = Math.min.apply(null, vs), hi = Math.max.apply(null, vs);
    var padr = (hi - lo) * 0.08 || 1, min = Math.max(0, lo - padr), max = hi + padr, rng = (max - min) || 1;
    var X = function (i) { return (i / (n - 1)) * 100; };
    var Y = function (v) { return (1 - (v - min) / rng) * 100; };

    // 折线 + 面积
    var dl = hist.map(function (h, i) { return (i ? "L" : "M") + X(i).toFixed(2) + " " + Y(h.v).toFixed(2); }).join(" ");
    var da = "M0 100 " + dl.substring(1) + " L100 100 Z";
    // 横向网格 4 档
    var grids = [0, 1, 2, 3, 4].map(function (k) { return min + rng * k / 4; });
    var gl = grids.map(function (g) { var y = Y(g).toFixed(2);
      return '<line x1="0" y1="' + y + '" x2="100" y2="' + y + '" class="gl" vector-effect="non-scaling-stroke"/>'; }).join("");
    var gid = "h" + Math.random().toString(36).slice(2, 8);
    var svg = '<svg viewBox="0 0 100 100" preserveAspectRatio="none">' +
      '<defs><linearGradient id="' + gid + '" x1="0" y1="0" x2="0" y2="1">' +
      '<stop offset="0" stop-color="var(--accent)" stop-opacity="0.26"/>' +
      '<stop offset="1" stop-color="var(--accent)" stop-opacity="0"/></linearGradient></defs>' +
      gl + '<path d="' + da + '" fill="url(#' + gid + ')"/>' +
      '<path d="' + dl + '" fill="none" stroke="var(--accent)" stroke-width="1.9" ' +
      'stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/></svg>';

    // Y 轴标签（指数值）
    var yl = grids.map(function (g) {
      return '<span style="top:' + (Y(g) / 100 * PLOTH - 6).toFixed(0) + 'px">' + Math.round(g) + "</span>";
    }).join("");
    // X 轴标签（约 6 个年份刻度）
    var ticks = [], seenYr = {};
    for (var t = 0; t <= 5; t++) {
      var i = Math.round(t / 5 * (n - 1)), yr = (hist[i].p || "").split("-")[0];
      if (yr && !seenYr[yr]) { seenYr[yr] = 1; ticks.push('<span style="left:' + X(i).toFixed(1) + '%">' + yr + "</span>"); }
    }

    // 统计：数据范围 / 全期累计 / 峰值 / 较峰值
    var first = hist[0], last = hist[n - 1];
    var maxi = vs.indexOf(hi);
    var total = (last.v / first.v - 1) * 100;
    var frPeak = (last.v / hi - 1) * 100;
    var stats = '<div class="hstats">' +
      '<span>区间 <b>' + esc(first.p) + " – " + esc(last.p) + "</b></span>" +
      '<span>全期累计 <b class="' + cls(total) + '">' + fmtPct(total, 0) + "</b></span>" +
      '<span>峰值 <b>' + Math.round(hi) + "</b>（" + esc(hist[maxi].p) + "）</span>" +
      '<span>较峰值 <b class="' + cls(frPeak) + '">' + fmtPct(frPeak, 1) + "</b></span></div>";

    el.innerHTML = stats +
      '<div class="chartbox"><div class="yaxis">' + yl + "</div>" +
      '<div class="plot"><div class="xaxis">' + ticks.join("") + "</div>" + svg +
      '<div class="cross"></div><div class="hdot"></div><div class="htip"></div>' +
      '<div class="cap"></div></div></div>' +
      '<div class="dsrc">名义房价指数（当地货币，' + esc(c.base || "2015=100") + "）· 悬停查看各季读数" +
      (c.src ? " · 来源 " + esc(c.src) : "") + (c.seed ? " · 近似序列" : "") + "</div>";

    // 悬停交互
    var plot = el.querySelector(".plot"), cap = el.querySelector(".cap");
    var cross = el.querySelector(".cross"), dot = el.querySelector(".hdot"), tip = el.querySelector(".htip");
    function move(ev) {
      var r = plot.getBoundingClientRect();
      var cx = (ev.touches ? ev.touches[0].clientX : ev.clientX) - r.left;
      var fx = Math.max(0, Math.min(1, cx / r.width));
      var i = Math.round(fx * (n - 1));
      var xp = X(i), yp = Y(hist[i].v);
      cross.style.left = xp + "%"; cross.style.display = "block";
      dot.style.left = xp + "%"; dot.style.top = yp + "%"; dot.style.display = "block";
      var yy = yoyAt(hist, i);
      tip.innerHTML = "<b>" + esc(hist[i].p) + "</b> 指数 " + hist[i].v +
        (isNum(yy) ? ' · 同比 <span class="' + cls(yy) + '">' + fmtPct(yy) + "</span>" : "");
      tip.style.display = "block";
      tip.style.left = Math.max(4, Math.min(88, xp)) + "%";
      tip.style.transform = xp > 70 ? "translateX(-100%)" : "none";
    }
    function leave() { cross.style.display = dot.style.display = tip.style.display = "none"; }
    cap.addEventListener("mousemove", move);
    cap.addEventListener("mouseleave", leave);
    cap.addEventListener("touchstart", move, { passive: true });
    cap.addEventListener("touchmove", move, { passive: true });
    cap.addEventListener("touchend", leave);
    return el;
  }

  function renderList() {
    var wrap = $("list"); wrap.innerHTML = "";
    var list = sorted(filtered());
    if (!list.length) { wrap.innerHTML = '<div class="empty">没有匹配的国家/地区，换个关键词或区域试试 🙂</div>'; return; }
    list.forEach(function (c, i) {
      var item = document.createElement("div"); item.className = "item";
      item.style.animationDelay = Math.min(i * 14, 340) + "ms";

      var card = document.createElement("div"); card.className = "rowcard";
      card.innerHTML =
        '<div class="rk">' + c.rank + "</div>" +
        '<div class="flag">' + (c.flag || "🌐") + "</div>" +
        '<div class="info"><div class="nm">' + esc(c.name) +
          (c.nameEn ? '<span class="en">' + esc(c.nameEn) + "</span>" : "") + regTag(c) + "</div>" +
          '<div class="meta">' + esc(metaOf(c)) + "</div></div>" +
        '<div class="spark">' + sparkline((c.trend || []).slice(-20)) + "</div>" +
        '<div class="money"><div class="yoy ' + cls(c.yoyNominal) + '">' + fmtPct(c.yoyNominal) + "</div>" +
          '<div class="sub">实际 <span class="rl ' + cls(c.yoyReal) + '">' + fmtPct(c.yoyReal) + "</span>" +
          " · 环比 " + fmtPct(c.qoq) + "</div></div>" +
        '<div class="chev">▾</div>';
      item.appendChild(card);

      function toggle() {
        var isOpen = item.classList.toggle("open");
        state.open[c.iso] = isOpen;
        if (isOpen && !item.querySelector(".detail")) item.appendChild(buildDetail(c));
      }
      card.addEventListener("click", toggle);
      if (state.open[c.iso]) { item.classList.add("open"); item.appendChild(buildDetail(c)); }
      wrap.appendChild(item);
    });
  }

  function renderChips() {
    var counts = {};
    (DATA.countries || []).forEach(function (c) { counts[c.region] = (counts[c.region] || 0) + 1; });
    var chips = [{ key: "all", label: "全部", color: "#9099ad", n: (DATA.countries || []).length }];
    (DATA.regions || []).forEach(function (r) {
      if (counts[r.key]) chips.push({ key: r.key, label: r.label, color: r.color, n: counts[r.key] });
    });
    var box = $("chips"); box.innerHTML = "";
    chips.forEach(function (r) {
      var el = document.createElement("div");
      el.className = "chip" + (state.reg === r.key ? " on" : "");
      el.innerHTML = '<span class="cdot" style="color:' + r.color + '"></span>' + esc(r.label) +
        ' <span style="opacity:.7">' + r.n + "</span>";
      el.onclick = function () {
        state.reg = r.key;
        box.querySelectorAll(".chip").forEach(function (x) { x.classList.remove("on"); });
        el.classList.add("on"); renderList();
      };
      box.appendChild(el);
    });
  }

  function renderSummary() {
    var cs = DATA.countries || [], el = $("summary");
    var withY = cs.filter(function (c) { return isNum(c.yoyNominal); });
    var top = withY.slice().sort(function (a, b) { return b.yoyNominal - a.yoyNominal; })[0];
    var bot = withY.slice().sort(function (a, b) { return a.yoyNominal - b.yoyNominal; })[0];
    var html = '<span class="pill-i">📅 ' + esc(DATA.asOf || "—") + "</span>" +
      '<span class="pill-i">覆盖 <b>' + (DATA.count || cs.length) + "</b> 国/地区</span>" +
      '<span class="pill-i">👆 点击国家看近 20 年走势</span>';
    if (top) html += '<span class="lead up">▲ 涨幅居首 ' + esc(top.name) + " " + fmtPct(top.yoyNominal) + "</span>";
    if (bot) html += '<span class="lead down">▼ 跌幅居首 ' + esc(bot.name) + " " + fmtPct(bot.yoyNominal) + "</span>";
    el.innerHTML = html;
  }

  function renderStatus() {
    var live = !DATA.seed;
    var el = $("status");
    el.className = "status " + (live ? "live" : "demo");
    el.innerHTML = '<span class="sdot"></span>' +
      (live ? "实时榜 · OECD/BIS 每周自动更新" : "近似数据 · 待每周任务接入 OECD/BIS");
  }

  function renderFooter() {
    var upd = DATA.updatedAt ? DATA.updatedAt.replace("T", " ").replace("Z", " UTC") : "—";
    var html = '<div class="src">数据来源 <b>' + esc(DATA.source || "—") + "</b> · 数据日期 <b>" +
      esc(DATA.asOf || "—") + "</b> · 更新于 " + esc(upd) + "</div>";
    if (DATA.note) html += "<div>" + esc(DATA.note) + "</div>";
    $("foot").innerHTML = html;
  }

  function initSorts() {
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
    (DATA.regions || []).forEach(function (r) { REG[r.key] = r; });
    renderStatus(); renderSummary(); renderChips(); initSorts(); renderList(); renderFooter();
  }

  fetch("data.json?t=" + Date.now())
    .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(boot)
    .catch(function (e) {
      $("list").innerHTML = '<div class="empty">数据加载失败：' + esc(e.message) + "<br>请稍后刷新重试。</div>";
    });
})();
