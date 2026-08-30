/* 全球富豪实时榜 · 前端渲染
 * 读取同目录 data.json（由 scripts/billionaires/build_billionaires.py 每日生成），
 * 渲染全球全部亿万富豪（约 3400 人）的排行卡片（头像 / 身价 / 当日变动 / 净值条），
 * 支持排序、搜索与分页。纯原生 JS。
 *
 * 为什么是分页而不是无限滚动：榜单 3400 余人，滚动加载要看到第 3000 名得先滚过
 * 2900 张卡片，尾部实际上不可达；分页后「第 3000 名」就是第 30 页，一步到位，
 * 且每页 DOM 恒定 100 条，不会越滚越重。搜索与排序都作用于全榜，不只当前页。 */
(function () {
  "use strict";

  var PER_PAGE = 100;

  var DATA = null, MAXW = 1;
  var state = { sort: "rank", q: "", view: [], page: 1 };
  var els = {};
  var qTimer = null;

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
  function pageCount() { return Math.max(1, Math.ceil(state.view.length / PER_PAGE)); }

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
    if (!reduceMotion) el.style.animationDelay = Math.min(i * 8, 280) + "ms";

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

  /* 渲染当前页的 100 条。 */
  function renderPage() {
    var wrap = els.list;
    wrap.innerHTML = "";
    if (!state.view.length) {
      wrap.innerHTML = '<div class="empty">没有匹配的人物，换个关键词试试 🙂</div>';
      els.pager.hidden = true;
      return;
    }
    els.pager.hidden = false;
    var from = (state.page - 1) * PER_PAGE;
    var slice = state.view.slice(from, from + PER_PAGE);
    var frag = document.createDocumentFragment(), grow = [];
    slice.forEach(function (p, i) {
      var c = card(p, i);
      frag.appendChild(c.el);
      if (!reduceMotion) grow.push(c);
    });
    wrap.appendChild(frag);
    if (grow.length) raf(function () { grow.forEach(function (g) { g.bar.style.width = g.pct + "%"; }); });
    renderPager(from, from + slice.length);
  }

  /* 页码条：首页、末页、当前页 ±N，中间用省略号。窄屏少留几个，避免横向溢出。 */
  function pageWindow(cur, total) {
    var span = (window.innerWidth && window.innerWidth < 560) ? 1 : 2;
    var set = {};
    set[1] = 1; set[total] = 1;
    for (var i = cur - span; i <= cur + span; i++) if (i >= 1 && i <= total) set[i] = 1;
    var nums = Object.keys(set).map(Number).sort(function (a, b) { return a - b; });
    var out = [];
    nums.forEach(function (n, i) {
      if (i && n - nums[i - 1] > 1) out.push("…");
      out.push(n);
    });
    return out;
  }

  function pageBtn(label, page, opts) {
    var b = document.createElement("button");
    b.type = "button"; b.textContent = label;
    if (opts && opts.current) { b.className = "cur"; b.setAttribute("aria-current", "page"); }
    if (opts && opts.disabled) { b.disabled = true; }
    else { b.onclick = function () { goPage(page); }; }
    if (opts && opts.label) b.setAttribute("aria-label", opts.label);
    return b;
  }

  function renderPager(from, to) {
    var total = pageCount(), cur = state.page;
    var nav = els.pageNav; nav.innerHTML = "";
    nav.appendChild(pageBtn("‹", cur - 1, { disabled: cur <= 1, label: "上一页" }));
    pageWindow(cur, total).forEach(function (n) {
      if (n === "…") {
        var s = document.createElement("span"); s.className = "gap"; s.textContent = "…";
        s.setAttribute("aria-hidden", "true"); nav.appendChild(s);
      } else {
        nav.appendChild(pageBtn(String(n), n, { current: n === cur, label: "第 " + n + " 页" }));
      }
    });
    nav.appendChild(pageBtn("›", cur + 1, { disabled: cur >= total, label: "下一页" }));

    els.pageTip.textContent = state.q
      ? "第 " + fmtInt(from + 1) + " – " + fmtInt(to) + " 条 · 共搜到 " + fmtInt(state.view.length) + " 人"
      : "第 " + fmtInt(from + 1) + " – " + fmtInt(to) + " 名 · 共 " + fmtInt(state.view.length) + " 人";
    els.jump.max = total;
    els.jump.value = "";
    els.jump.placeholder = cur + "/" + total;
  }

  function goPage(n) {
    var total = pageCount();
    n = Math.min(total, Math.max(1, n | 0));
    if (n === state.page) return;
    state.page = n;
    syncHash();
    renderPage();
    // 翻页后回到列表顶部，否则会停在上一页的位置、看起来像没翻
    var y = els.list.getBoundingClientRect().top + window.pageYOffset - 12;
    window.scrollTo(reduceMotion ? { top: y } : { top: y, behavior: "smooth" });
  }

  /* 过滤 / 排序变化后回到第 1 页重算。 */
  function rebuild(keepPage) {
    state.view = sorted();
    if (!keepPage) state.page = 1;
    else state.page = Math.min(state.page, pageCount());
    syncHash();
    renderPage();
  }

  /* 页码写进 URL hash：刷新、收藏、分享都能停在同一页。 */
  function syncHash() {
    var want = state.page > 1 ? "#p=" + state.page : "";
    if ((location.hash || "") !== want) {
      try {
        history.replaceState(null, "", location.pathname + location.search + want);
      } catch (e) { /* file:// 等环境下 replaceState 不可用，忽略即可 */ }
    }
  }
  function pageFromHash() {
    var m = /(?:^|#|&)p=(\d+)/.exec(location.hash || "");
    return m ? parseInt(m[1], 10) : 1;
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

  /* 分页条：页码按钮 + 「第 X–Y 名 / 共 N 人」+ 跳页输入框，插在列表之后。 */
  function buildPager() {
    var box = document.createElement("div"); box.className = "pager"; box.hidden = true;
    var nav = document.createElement("nav"); nav.className = "pagenav";
    nav.setAttribute("aria-label", "分页导航");

    var tip = document.createElement("div"); tip.className = "pagetip";
    tip.setAttribute("aria-live", "polite");

    var jumpWrap = document.createElement("div"); jumpWrap.className = "jump";
    var jl = document.createElement("label");
    jl.setAttribute("for", "jumpto"); jl.textContent = "跳至";
    var jump = document.createElement("input");
    jump.type = "number"; jump.id = "jumpto"; jump.min = "1"; jump.inputMode = "numeric";
    jump.setAttribute("aria-label", "跳转到指定页");
    var jb = document.createElement("button");
    jb.type = "button"; jb.className = "jumpgo"; jb.textContent = "页";
    var doJump = function () {
      var v = parseInt(jump.value, 10);
      if (v >= 1) goPage(v);
      jump.value = "";
    };
    jb.onclick = doJump;
    jump.onkeydown = function (e) { if (e.key === "Enter") { e.preventDefault(); doJump(); } };
    jumpWrap.appendChild(jl); jumpWrap.appendChild(jump); jumpWrap.appendChild(jb);

    box.appendChild(nav); box.appendChild(tip); box.appendChild(jumpWrap);
    els.list.parentNode.insertBefore(box, els.list.nextSibling);
    els.pager = box; els.pageNav = nav; els.pageTip = tip; els.jump = jump;
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
    // 防抖：全榜 3400 人，逐字过滤没必要每次都跑
    $("q").oninput = function () {
      var v = this.value.trim();
      clearTimeout(qTimer);
      qTimer = setTimeout(function () {
        if (v === state.q) return;
        state.q = v; rebuild();
      }, 180);
    };
    // 浏览器前进/后退改了 hash 时跟着翻页
    window.addEventListener("hashchange", function () {
      var n = pageFromHash();
      if (n !== state.page) { state.page = Math.min(pageCount(), Math.max(1, n)); renderPage(); }
    });
    // 窗口跨过窄屏断点时页码窗口大小会变，重画一下页码条
    var wasNarrow = window.innerWidth < 560;
    window.addEventListener("resize", function () {
      var narrow = window.innerWidth < 560;
      if (narrow !== wasNarrow) { wasNarrow = narrow; if (state.view.length) renderPage(); }
    });
  }

  function boot(data) {
    DATA = data;
    els.list = $("list");
    MAXW = Math.max.apply(null, (DATA.people || [{ worth: 1 }]).map(function (p) { return p.worth || 0; })) || 1;
    renderStatus(); renderSummary(); buildPager(); initControls();
    state.view = sorted();
    state.page = Math.min(pageCount(), Math.max(1, pageFromHash()));
    renderPage(); renderFooter();
  }

  fetch("data.json?t=" + Date.now())
    .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(boot)
    .catch(function (e) {
      $("list").innerHTML = '<div class="empty">数据加载失败：' + esc(e.message) + "<br>请稍后刷新重试。</div>";
    });
})();
