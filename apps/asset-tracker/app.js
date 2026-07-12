/* 全球大类资产收益率 · 前端渲染
 * 读取同目录 data.json（由 scripts/asset-tracker/build_assets.py 每日生成），
 * 渲染「示例图同款」的分品类排序条形图 + 可排序数据表。纯原生 JS，无第三方依赖。 */
(function () {
  "use strict";

  var DATA = null;
  var state = { period: "ytd", view: "chart", hidden: {}, sortKey: "ytd", sortDir: -1 };
  var catMap = {};      // key -> {label,color}
  var $ = function (id) { return document.getElementById(id); };
  var raf = (typeof requestAnimationFrame !== "undefined")
    ? requestAnimationFrame : function (f) { return setTimeout(f, 16); };

  function fmt(v, dp) {
    if (v === null || v === undefined || isNaN(v)) return "—";
    return (v >= 0 ? "+" : "−") + Math.abs(v).toFixed(dp == null ? 1 : dp) + "%";
  }
  function isNum(v) { return v !== null && v !== undefined && !isNaN(v); }
  function cls(v) { return !isNum(v) ? "na" : (v >= 0 ? "pos" : "neg"); }

  /* #rrggbb -> rgba()，用于条形发光阴影 */
  function rgba(hex, a) {
    var h = (hex || "#888888").replace("#", "");
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    var n = parseInt(h, 16);
    return "rgba(" + ((n >> 16) & 255) + "," + ((n >> 8) & 255) + "," + (n & 255) + "," + a + ")";
  }

  function periodHasData(key) {
    return DATA.assets.some(function (a) { return a.returns && isNum(a.returns[key]); });
  }
  function sortedByPeriod(period) {
    return DATA.assets.filter(function (a) {
      return !state.hidden[a.category] && a.returns && isNum(a.returns[period]);
    }).sort(function (a, b) { return b.returns[period] - a.returns[period]; });
  }

  /* —— 控制区 —— */
  function renderPeriods() {
    var box = $("periods"); box.innerHTML = "";
    DATA.periods.forEach(function (p) {
      var b = document.createElement("button");
      b.textContent = p.label;
      if (!periodHasData(p.key)) { b.disabled = true; b.title = "实时数据上线后可用"; }
      if (p.key === state.period) b.className = "on";
      b.onclick = function () {
        state.period = p.key; state.sortKey = p.key; state.sortDir = -1;
        renderPeriods(); render();
      };
      box.appendChild(b);
    });
  }

  function renderLegend() {
    var box = $("legend"); box.innerHTML = "";
    DATA.categories.forEach(function (c) {
      var chip = document.createElement("span");
      chip.className = "chip" + (state.hidden[c.key] ? " off" : "");
      chip.innerHTML = '<span class="dot" style="background:' + c.color + ';color:' + c.color + '"></span>' + c.label;
      chip.onclick = function () { state.hidden[c.key] = !state.hidden[c.key]; renderLegend(); render(); };
      box.appendChild(chip);
    });
  }

  function renderStatus() {
    var live = /yahoo/i.test(DATA.source || "");
    var el = $("status");
    el.className = "status " + (live ? "live" : "demo");
    el.innerHTML = '<span class="sdot"></span>' + (live ? "实时行情 · 每日自动更新" : "示例数据 · 合并后转实时");
  }

  function renderSummary() {
    var list = sortedByPeriod(state.period), el = $("summary");
    if (!list.length) { el.innerHTML = ""; return; }
    var top = list[0], bot = list[list.length - 1];
    var pl = ((DATA.periods.filter(function (p) { return p.key === state.period; })[0]) || {}).label || "";
    el.innerHTML =
      '<span class="pill-i">📅 ' + (DATA.asOf || "—") + "</span>" +
      '<span class="pill-i">' + pl + " · " + list.length + " 项</span>" +
      '<span class="lead up">▲ 领涨 ' + top.name + " " + fmt(top.returns[state.period]) + "</span>" +
      '<span class="lead down">▼ 领跌 ' + bot.name + " " + fmt(bot.returns[state.period]) + "</span>";
  }

  /* —— 条形图（分品类配色、按所选周期降序的发散条形）—— */
  function renderChart() {
    var wrap = $("chart"); wrap.innerHTML = "";
    var period = state.period, list = sortedByPeriod(period);
    if (!list.length) {
      wrap.innerHTML = '<div class="empty">该周期暂无数据，换个周期或品类试试 🙂</div>';
      return;
    }
    var vals = list.map(function (a) { return a.returns[period]; });
    var maxPos = Math.max(0, Math.max.apply(null, vals));
    var maxNeg = Math.max(0, -Math.min.apply(null, vals));
    var total = (maxPos + maxNeg) || 1;
    var GL = 14, GR = 12, USE = 100 - GL - GR;   // 左右预留标签位（% 计）
    var scale = USE / total;                      // 每 1% 收益对应的条宽（%）
    var zero = GL + maxNeg * scale;               // 零基线位置（%）
    var grow = [];                                // 收集条形，下一帧再展开做生长动画

    list.forEach(function (a, idx) {
      var v = a.returns[period], color = (catMap[a.category] || {}).color || "#888";
      var row = document.createElement("div"); row.className = "row";
      row.style.animationDelay = Math.min(idx * 16, 360) + "ms";

      var name = document.createElement("div");
      name.className = "name"; name.textContent = (a.suspect ? "⚠️ " : "") + a.name;
      name.title = a.name + (a.note ? "（" + a.note + "）" : "") + (isNum(a.price) ? " · 现价 " + a.price : "");

      var track = document.createElement("div"); track.className = "track";
      var zl = document.createElement("div"); zl.className = "zero"; zl.style.left = zero + "%";
      track.appendChild(zl);

      var bar = document.createElement("div"); bar.className = "bar";
      var w = Math.abs(v) * scale, left = v >= 0 ? zero : (zero - w);
      bar.style.background = color;
      bar.style.boxShadow = "0 1px 11px " + rgba(color, 0.5);
      bar.style.borderRadius = v >= 0 ? "4px 7px 7px 4px" : "7px 4px 4px 7px";
      bar.style.opacity = a.stale ? "0.55" : "1";
      bar.style.left = left + "%"; bar.style.width = "0%";
      grow.push([bar, w]);
      track.appendChild(bar);

      var lab = document.createElement("span"); lab.className = "val"; lab.textContent = fmt(v);
      if (v >= 0) { lab.style.left = "calc(" + (zero + w) + "% + 6px)"; }
      else { lab.style.left = "calc(" + (zero - w) + "% - 6px)"; lab.style.transform = "translate(-100%,-50%)"; }
      track.appendChild(lab);

      row.appendChild(name); row.appendChild(track);
      wrap.appendChild(row);
    });
    raf(function () { grow.forEach(function (g) { g[0].style.width = g[1] + "%"; }); });
  }

  /* —— 数据表（全周期、可点表头排序）—— */
  function renderTable() {
    var wrap = $("table"); wrap.innerHTML = "";
    var t = document.createElement("table"), thead = document.createElement("thead"), hr = document.createElement("tr");
    var cols = [{ k: "name", l: "资产" }].concat(DATA.periods.map(function (p) { return { k: p.key, l: p.label }; }));
    cols.forEach(function (c) {
      var th = document.createElement("th");
      th.textContent = c.l;
      if (c.k === state.sortKey) { th.className = "sorted"; th.textContent += state.sortDir < 0 ? " ↓" : " ↑"; }
      if (c.k !== "name") th.onclick = function () {
        if (state.sortKey === c.k) state.sortDir *= -1; else { state.sortKey = c.k; state.sortDir = -1; }
        renderTable();
      };
      hr.appendChild(th);
    });
    thead.appendChild(hr); t.appendChild(thead);

    var rows = DATA.assets.filter(function (a) { return !state.hidden[a.category]; });
    rows.sort(function (a, b) {
      var x = a.returns[state.sortKey], y = b.returns[state.sortKey];
      if (!isNum(x) && !isNum(y)) return 0; if (!isNum(x)) return 1; if (!isNum(y)) return -1;
      return (x - y) * state.sortDir;
    });

    var tb = document.createElement("tbody");
    rows.forEach(function (a) {
      var tr = document.createElement("tr"), c = catMap[a.category] || {};
      var td0 = document.createElement("td");
      td0.innerHTML = '<span class="nm"><span class="tag" style="background:' + (c.color || "#888") + ";color:" + (c.color || "#888") + '"></span>' +
        a.name + (a.note ? '<span class="note-i" title="' + a.note + '">ⓘ</span>' : "") +
        (a.suspect ? '<span class="note-i" title="部分周期数据异常，已隐藏">⚠️</span>' : "") + "</span>";
      tr.appendChild(td0);
      DATA.periods.forEach(function (p) {
        var v = a.returns ? a.returns[p.key] : null, td = document.createElement("td");
        td.className = cls(v); td.textContent = fmt(v, 2);
        tr.appendChild(td);
      });
      tb.appendChild(tr);
    });
    t.appendChild(tb); wrap.appendChild(t);
  }

  function render() {
    renderSummary();
    if (state.view === "chart") { $("chart").style.display = ""; $("table").style.display = "none"; renderChart(); }
    else { $("chart").style.display = "none"; $("table").style.display = ""; renderTable(); }
  }

  function renderFooter() {
    var notes = DATA.assets.filter(function (a) { return a.note; }).map(function (a) { return a.name + "：" + a.note; });
    var uniq = notes.filter(function (n, i) { return notes.indexOf(n) === i; });
    var upd = DATA.updatedAt ? DATA.updatedAt.replace("T", " ").replace("Z", " UTC") : "—";
    var html = '<div class="src">数据来源 <b>' + (DATA.source || "—") + "</b> · 数据日期 <b>" +
      (DATA.asOf || "—") + "</b> · 更新于 " + upd + "</div>";
    if (DATA.note) html += "<div>" + DATA.note + "</div>";
    if (uniq.length) html += '<div style="opacity:.8">代理说明：' + uniq.join("；") + "</div>";
    $("foot").innerHTML = html;
  }

  function initViews() {
    $("views").querySelectorAll("button").forEach(function (b) {
      b.onclick = function () {
        state.view = b.getAttribute("data-view");
        $("views").querySelectorAll("button").forEach(function (x) { x.classList.remove("on"); });
        b.classList.add("on"); render();
      };
    });
  }

  function boot(data) {
    DATA = data;
    (DATA.categories || []).forEach(function (c) { catMap[c.key] = c; });
    if (DATA.defaultPeriod && periodHasData(DATA.defaultPeriod)) state.period = DATA.defaultPeriod;
    else { var p = (DATA.periods || []).filter(function (x) { return periodHasData(x.key); })[0]; if (p) state.period = p.key; }
    state.sortKey = state.period;
    renderStatus(); renderPeriods(); renderLegend(); initViews(); render(); renderFooter();
    window.addEventListener("resize", function () { if (state.view === "chart") renderChart(); });
  }

  fetch("data.json?t=" + Date.now())
    .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(boot)
    .catch(function (e) {
      $("chart").innerHTML = '<div class="empty">数据加载失败：' + e.message + "<br>请稍后刷新重试。</div>";
    });
})();
