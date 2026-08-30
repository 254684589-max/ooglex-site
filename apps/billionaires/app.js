/* 全球富豪实时榜 · 前端渲染
 * 读取同目录 data.json（由 scripts/billionaires/build_billionaires.py 每日生成），
 * 渲染全球全部亿万富豪（约 3400 人）的排行卡片（头像 / 身价 / 当日变动 / 净值条），
 * 支持排序与搜索。纯原生 JS。
 *
 * 榜单从前 250 扩到全榜后，一次性建完整张列表在手机上要 1 秒以上（4 万个 DOM 节点），
 * 搜索框每敲一个字都会重来一遍，实测不可用。所以改成：
 *   - 分批渲染：先出 BATCH 条，滚到底再追加，DOM 只按实际看到的量增长；
 *   - 搜索防抖：输入停下来再过滤，避免逐字重建；
 *   - 过滤 / 排序结果缓存在 state.view，追加批次时不重复算。
 * IntersectionObserver 只是「自动点一下加载更多」的增强，按钮本身始终可用（也可键盘操作）。 */
(function () {
  "use strict";

  var BATCH = 60;          // 每批渲染条数：手机上约 20ms，一屏装得下且有余量
  var PRELOAD = "600px";   // 距底部多远就预加载下一批

  var DATA = null, MAXW = 1;
  var state = { sort: "rank", q: "", view: [], shown: 0 };
  var els = {};            // list / sentinel / moreBtn / moreTip
  var io = null, qTimer = null;

  var $ = function (id) { return document.getElementById(id); };
  var raf = (typeof requestAnimationFrame !== "undefined")
    ? requestAnimationFrame : function (f) { return setTimeout(f, 16); };
  var reduceMotion = !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);

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
  function fmtInt(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ","); }

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

  function card(p, i) {
    var el = document.createElement("div"); el.className = "rowcard";
    // 入场动画按「批内序号」错开，否则第 3000 条会排到几十秒之后
    if (!reduceMotion) el.style.animationDelay = Math.min(i * 14, 360) + "ms";

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
    var bar = document.createElement("div"); bar.className = "wbar";
    var pct = Math.max(1.5, (p.worth / MAXW) * 100);
    bar.style.width = reduceMotion ? pct + "%" : "0%";

    el.appendChild(rk); el.appendChild(avatar(p)); el.appendChild(info);
    el.appendChild(money); el.appendChild(bg); el.appendChild(bar);
    return { el: el, bar: bar, pct: pct };
  }

  /* 追加下一批。返回本批实际渲染条数（0 表示已到底）。 */
  function renderMore() {
    var list = state.view, from = state.shown;
    if (from >= list.length) return 0;
    var to = Math.min(from + BATCH, list.length);
    var frag = document.createDocumentFragment(), grow = [];
    for (var i = from; i < to; i++) {
      var c = card(list[i], i - from);
      frag.appendChild(c.el);
      if (!reduceMotion) grow.push(c);
    }
    els.list.appendChild(frag);
    state.shown = to;
    if (grow.length) raf(function () { grow.forEach(function (g) { g.bar.style.width = g.pct + "%"; }); });
    syncMore();
    return to - from;
  }

  /* 同步底部「加载更多 / 已全部显示」区域，并让观察器对新位置重新起效。 */
  function syncMore() {
    var total = state.view.length, left = total - state.shown;
    if (!total) { els.more.hidden = true; return; }
    els.more.hidden = false;
    els.moreTip.textContent = left > 0
      ? "已显示 " + fmtInt(state.shown) + " / " + fmtInt(total) + " 人" + (io ? " · 继续滚动加载" : "")
      : "已显示全部 " + fmtInt(total) + " 人";
    // 按钮只在没有 IntersectionObserver、无法自动加载时露出：
    // 两者并存时，按钮一进视口就触发自动追加，新卡片会把它往下推，用户永远点不中。
    els.moreBtn.hidden = left <= 0 || !!io;
    if (left > 0) {
      els.moreBtn.textContent = "加载更多（还有 " + fmtInt(left) + " 人）";
      // 重新观察：追加后哨兵若仍在视口内，交叉状态没变化就不会再触发回调
      if (io) raf(function () { io.unobserve(els.sentinel); io.observe(els.sentinel); });
    }
  }

  /* 过滤 / 排序变化后整表重来：只建第一批。 */
  function rebuild() {
    state.view = sorted();
    state.shown = 0;
    els.list.innerHTML = "";
    if (!state.view.length) {
      els.list.innerHTML = '<div class="empty">没有匹配的人物，换个关键词试试 🙂</div>';
      els.more.hidden = true;
      return;
    }
    renderMore();
  }

  function renderSummary() {
    var ppl = DATA.people || [], el = $("summary");
    var withChg = ppl.filter(function (p) { return isNum(p.change); });
    var top = withChg.slice().sort(function (a, b) { return b.change - a.change; })[0];
    var bot = withChg.slice().sort(function (a, b) { return a.change - b.change; })[0];
    var totalT = isNum(DATA.totalWorth) ? "$" + (DATA.totalWorth / 1000).toFixed(2) + "T" : "—";
    var n = DATA.count || ppl.length;
    var html = '<span class="pill-i">📅 ' + (DATA.asOf || "—") + "</span>" +
      '<span class="pill-i">' + fmtInt(n) + ' 位亿万富豪 总财富 <b class="big">' + totalT + "</b></span>";
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

  /* 底部「加载更多」+ 哨兵，插在列表之后。 */
  function buildMore() {
    var more = document.createElement("div"); more.className = "more"; more.hidden = true;
    var btn = document.createElement("button"); btn.type = "button";
    btn.onclick = function () { renderMore(); };
    var tip = document.createElement("span"); tip.className = "moretip";
    var sentinel = document.createElement("div"); sentinel.className = "sentinel"; sentinel.setAttribute("aria-hidden", "true");
    more.appendChild(btn); more.appendChild(tip); more.appendChild(sentinel);
    els.list.parentNode.insertBefore(more, els.list.nextSibling);
    els.more = more; els.moreBtn = btn; els.moreTip = tip; els.sentinel = sentinel;

    if (typeof IntersectionObserver !== "undefined") {
      io = new IntersectionObserver(function (entries) {
        if (entries[0].isIntersecting && state.shown < state.view.length) renderMore();
      }, { rootMargin: PRELOAD + " 0px" });
      io.observe(sentinel);
    }
  }

  function initControls() {
    $("sorts").querySelectorAll("button").forEach(function (b) {
      b.onclick = function () {
        state.sort = b.getAttribute("data-sort");
        $("sorts").querySelectorAll("button").forEach(function (x) {
          x.classList.remove("on"); x.setAttribute("aria-pressed", "false");
        });
        b.classList.add("on"); b.setAttribute("aria-pressed", "true");
        rebuild();
      };
      b.setAttribute("aria-pressed", b.classList.contains("on") ? "true" : "false");
    });
    // 防抖：3400 人时逐字重建会卡住输入
    $("q").oninput = function () {
      var v = this.value.trim();
      clearTimeout(qTimer);
      qTimer = setTimeout(function () {
        if (v === state.q) return;
        state.q = v; rebuild();
      }, 180);
    };
  }

  function boot(data) {
    DATA = data;
    els.list = $("list");
    MAXW = Math.max.apply(null, (DATA.people || [{ worth: 1 }]).map(function (p) { return p.worth || 0; })) || 1;
    renderStatus(); renderSummary(); buildMore(); initControls(); rebuild(); renderFooter();
  }

  fetch("data.json?t=" + Date.now())
    .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(boot)
    .catch(function (e) {
      $("list").innerHTML = '<div class="empty">数据加载失败：' + esc(e.message) + "<br>请稍后刷新重试。</div>";
    });
})();
