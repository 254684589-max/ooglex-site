/* ===========================================================================
   OOGLEX 终端外壳行为 · Terminal Chrome Behavior
   ---------------------------------------------------------------------------
   1 标签条与彩色功能键条：全部由 chrome/registry.js 生成
   2 命令行：助记符（GMKT/MACR…）→ 跳功能；编号（11/25/94…）→ 跳本页编号项；
     标的代码（NVDA/US10Y…）→ 定位并高亮；其余当作检索词
   3 编号项：页面里凡带 data-num 的元素都能被编号键入命中，编号不是装饰
   4 相关功能菜单 / 功能目录 / 帮助：三个弹层，同样由注册表生成
   5 快捷键：/ 聚焦命令行，Esc 关弹层并清空，Alt+← / Alt+→ 走浏览器历史
   =========================================================================== */
(function (global) {
  "use strict";
  var FN = global.OOGLEX_FN;

  function $(s, r) { return (r || document).querySelector(s); }
  function $$(s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c];
    });
  }
  function el(tag, cls, txt) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (txt != null) e.textContent = txt;
    return e;
  }

  /* ── 1 标签条 ───────────────────────────────────────────────────────────
     tabs: [{mn,title,href,on}]，末尾自动补 + 与右侧系统键。
     这些标签是真链接 —— 不做成假的多标签容器。 */
  function tabs(host, list, current) {
    host = $(host); if (!host) return;
    host.innerHTML = "";
    list.forEach(function (t) {
      var a = el("a", "tab" + (t.mn === current ? " on" : ""));
      a.href = t.href || "#";
      a.appendChild(el("b", null, t.mn));
      a.appendChild(el("span", null, t.title));
      if (t.mn === current) {
        var x = el("span", "x", "✕");
        x.setAttribute("aria-hidden", "true");
        a.appendChild(x);
      }
      host.appendChild(a);
    });
    var add = el("a", "add", "+");
    add.href = "#fdir"; add.title = "打开功能目录，挑一个功能开新标签";
    add.setAttribute("aria-label", "新建标签：打开功能目录");
    host.appendChild(add);

    var r = el("div", "sysr");
    [["搜索", "⌕", "#fdir"], ["全屏", "⤢", null]].forEach(function (p) {
      var b = el("button", null, p[1]);
      b.type = "button"; b.title = p[0]; b.setAttribute("aria-label", p[0]);
      if (p[0] === "全屏") b.onclick = function () {
        try {
          if (document.fullscreenElement) document.exitFullscreen();
          else document.documentElement.requestFullscreen();
        } catch (e) { /* 浏览器不允许就算了，不报错给用户 */ }
      };
      else b.onclick = function () { openDir(); };
      r.appendChild(b);
    });
    var opt = el("button", "opt", "≡ Options");
    opt.type = "button"; opt.onclick = function () { openHelp(); };
    r.appendChild(opt);
    host.appendChild(r);
  }

  /* ── 2 彩色功能键条 ────────────────────────────────────────────────────
     一格一个功能，底色按分类。规划中的功能不出现在这里（只在功能目录里列出），
     免得点了没反应。 */
  function fnbar(host, current) {
    host = $(host); if (!host) return;
    host.innerHTML = "";
    var last = null;
    FN.shortcuts().forEach(function (f) {
      if (last && f.cat !== last) host.appendChild(el("span", "gap"));
      last = f.cat;
      var c = FN.catOf(f);
      var a = el("a", f.status === "draft" ? "draft" : null);
      a.href = f.href; a.textContent = f.mn;
      a.style.background = c.bg; a.style.color = c.ink;
      a.title = f.mn + " " + f.zh + " · " + c.zh +
        (f.status === "draft" ? "（本目录草案）" : "") + (f.note ? "\n" + f.note : "");
      if (f.mn === current) a.style.border = "1px solid #fff";
      host.appendChild(a);
    });
    var tools = el("div", "tools");
    var w = el("button", "wrench", "✎");
    w.type = "button"; w.title = "功能键条由 chrome/registry.js 生成：加一个功能就是加一条记录";
    w.setAttribute("aria-label", "功能目录");
    w.onclick = function () { openDir(); };
    tools.appendChild(w);
    host.appendChild(tools);
  }

  /* ── 3 弹层 ─────────────────────────────────────────────────────────── */
  var pop = null, backdrop = null;
  function closePop() {
    if (pop) { pop.remove(); pop = null; }
    if (backdrop) { backdrop.remove(); backdrop = null; }
  }
  function showPop(title, bodyHTML, anchor) {
    closePop();
    backdrop = el("div", "c-backdrop");
    backdrop.onclick = closePop;
    document.body.appendChild(backdrop);
    pop = el("div", "c-pop");
    pop.setAttribute("role", "dialog");
    pop.setAttribute("aria-label", title);
    pop.innerHTML = '<h3>' + esc(title) + '<button type="button" aria-label="关闭">✕</button></h3>' +
      '<div class="bd">' + bodyHTML + "</div>";
    document.body.appendChild(pop);
    $("h3 button", pop).onclick = closePop;
    var r = anchor ? anchor.getBoundingClientRect() : null;
    var w = pop.offsetWidth, h = pop.offsetHeight;
    var left = r ? Math.min(r.left, window.innerWidth - w - 8) : (window.innerWidth - w) / 2;
    var top  = r ? Math.min(r.bottom + 2, window.innerHeight - h - 8) : 60;
    pop.style.left = Math.max(8, left) + "px";
    pop.style.top  = Math.max(8, top) + "px";
    var f = $("a,button", pop.querySelector(".bd")) || $("h3 button", pop);
    if (f) f.focus();
  }

  function fnRow(f, dead) {
    var c = FN.catOf(f);
    var tag = dead ? "div" : "a";
    var href = dead ? "" : ' href="' + esc(f.href) + '"';
    return "<" + tag + ' class="row' + (dead ? " dead" : "") + '"' + href + ">" +
      '<span class="mn" style="background:' + c.bg + ";color:" + c.ink + '">' + esc(f.mn) + "</span>" +
      '<span class="tx">' + esc(f.zh) +
        '<em>' + esc(f.en) + (f.status === "draft" ? " · 草案" : "") + (dead ? " · 规划中" : "") + "</em>" +
        (f.note ? "<p>" + esc(f.note) + "</p>" : "") +
        (f.need ? "<p>需要：" + esc(f.need) + "</p>" : "") +
        (f.blocked ? "<p>卡在：" + esc(f.blocked) + "</p>" : "") +
      "</span></" + tag + ">";
  }
  function openDir(anchor) {
    var h = "";
    FN.BAR_ORDER.forEach(function (c) {
      var rows = FN.byCat(c);
      if (!rows.length) return;
      h += '<div class="grp">' + esc(FN.CATEGORIES[c].zh) + " · " + esc(FN.CATEGORIES[c].en) + "</div>";
      rows.forEach(function (f) { h += fnRow(f, false); });
    });
    h += '<div class="grp">规划中 · 缺什么写清楚，不先画空壳</div>';
    FN.PLANNED.forEach(function (f) { h += fnRow(f, true); });
    showPop("功能目录 FDIR · 已接入 " + FN.live().length + " 项 / 规划中 " + FN.PLANNED.length + " 项", h, anchor);
  }
  function openRelated(anchor, cats) {
    var h = "";
    (cats || FN.BAR_ORDER).forEach(function (c) {
      var rows = FN.byCat(c);
      if (!rows.length) return;
      h += '<div class="grp">' + esc(FN.CATEGORIES[c].zh) + "</div>";
      rows.forEach(function (f) { h += fnRow(f, false); });
    });
    showPop("相关功能菜单", h, anchor);
  }
  function openHelp(anchor) {
    var nums = $$("[data-num]").map(function (e) {
      return { n: e.getAttribute("data-num"), t: (e.getAttribute("data-num-label") ||
        (e.textContent || "").replace(/\s+/g, " ").trim()).slice(0, 40) };
    });
    var h = '<div class="grp">命令行</div>' +
      '<div class="row"><span class="mn">助记符</span><span class="tx">输入 <kbd>GMKT</kbd> <kbd>MACR</kbd> <kbd>NEWS</kbd> 这类四字助记符直接跳功能<p>全部助记符见功能目录 FDIR</p></span></div>' +
      '<div class="row"><span class="mn">编号</span><span class="tx">输入本页左侧或动作键上的编号跳转<p>本页可用编号：' +
        esc(nums.map(function (x) { return x.n; }).join(" ")) + "</p></span></div>" +
      '<div class="row"><span class="mn">代码</span><span class="tx">输入 <kbd>NVDA</kbd> <kbd>US10Y</kbd> <kbd>DXY</kbd> 这类标的代码，定位并高亮所在行<p>只认页面上真实存在的行，找不到就说找不到，不猜</p></span></div>' +
      '<div class="grp">快捷键</div>' +
      '<div class="row"><span class="mn">/</span><span class="tx">聚焦命令行</span></div>' +
      '<div class="row"><span class="mn">Esc</span><span class="tx">关闭弹层并清空命令行</span></div>' +
      '<div class="row"><span class="mn">Enter</span><span class="tx">执行命令行（等同 GO）</span></div>' +
      '<div class="grp">这个外壳刻意没有的东西</div>' +
      '<div class="row dead"><span class="mn">下单</span><span class="tx">无买卖键<p>站内没有任何经纪或订单通道，画一个买卖键就是假的</p></span></div>' +
      '<div class="row dead"><span class="mn">实时</span><span class="tx">无实时行情<p>盘中快照约 30 分钟刷新，页面一律标「快照」不标「实时」</p></span></div>' +
      '<div class="row dead"><span class="mn">BID/ASK</span><span class="tx">无买卖盘与成交量<p>无免费公开来源，这些字段不显示，也不用占位数字冒充</p></span></div>';
    showPop("帮助 HELP", h, anchor);
  }

  /* ── 4 命令行 ───────────────────────────────────────────────────────── */
  function flash(node) {
    $$(".c-hit").forEach(function (e) { e.classList.remove("c-hit"); });
    if (!node) return;
    node.classList.add("c-hit");
    if (node.scrollIntoView) node.scrollIntoView({ block: "center" });
  }
  function say(msg, ok) {
    var h = $("[data-cmd-hint]");
    if (h) { h.textContent = msg; h.style.color = ok ? "#8ce0b0" : "#ff6b6b"; }
  }
  function runCommand(raw) {
    var q = String(raw || "").trim();
    if (!q) return;
    var up = q.toUpperCase();

    /* 助记符 */
    var f = FN.byMn(up);
    if (f) {
      if (f.status === "planned" || !f.href) {
        say(up + " 规划中，尚未接入（见功能目录）", false); openDir(); return;
      }
      if (f.href === "#fdir") { openDir(); say("功能目录", true); return; }
      if (f.href === "#help") { openHelp(); say("帮助", true); return; }
      say("跳转 " + f.mn + " " + f.zh, true);
      location.href = f.href; return;
    }
    /* 编号 */
    if (/^\d{1,3}$/.test(q)) {
      var n = $('[data-num="' + q + '"]');
      if (n) {
        say(q + ") " + (n.getAttribute("data-num-label") || "").slice(0, 30), true);
        if (n.tagName === "A" || n.tagName === "BUTTON") { n.click(); n.focus(); }
        flash(n.closest(".c-block, .c-panel, tr") || n);
        return;
      }
      say("本页没有编号 " + q, false); return;
    }
    /* 页面上的标的行 / 字段 */
    var hit = $('[data-tk="' + up + '"]') ||
      $$("[data-tk],[data-nm]").filter(function (e) {
        return (e.getAttribute("data-tk") || "").toUpperCase().indexOf(up) === 0 ||
               (e.getAttribute("data-nm") || "").indexOf(q) >= 0;
      })[0];
    if (hit) {
      flash(hit);
      say("定位 " + (hit.getAttribute("data-tk") || hit.getAttribute("data-nm")), true);
      return;
    }
    /* 功能名模糊匹配 */
    var m = FN.live().filter(function (x) {
      return x.zh.indexOf(q) >= 0 || x.en.toUpperCase().indexOf(up) >= 0;
    })[0];
    if (m) { say("跳转 " + m.mn + " " + m.zh, true); location.href = m.href; return; }
    say("未匹配：" + q + "（输入 HELP 看用法，FDIR 看全部功能）", false);
  }

  function command(sel) {
    var inp = $(sel || "[data-command]");
    if (!inp) return;
    var go = $("[data-command-go]");
    if (go) go.onclick = function () { runCommand(inp.value); };
    inp.addEventListener("keydown", function (e) {
      if (e.key === "Enter") { e.preventDefault(); runCommand(inp.value); }
      if (e.key === "Escape") { inp.value = ""; say("", true); flash(null); closePop(); }
    });
    document.addEventListener("keydown", function (e) {
      var t = e.target || {};
      var typing = /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName || "");
      if (e.key === "/" && !typing) { e.preventDefault(); inp.focus(); inp.select(); }
      if (e.key === "Escape") { closePop(); flash(null); }
    });
  }

  /* ── 5 编号菜单与动作键的编号绑定 ─────────────────────────────────── */
  function wireNumbers() {
    $$("[data-num]").forEach(function (e) {
      if (!e.getAttribute("data-num-label")) {
        e.setAttribute("data-num-label", (e.textContent || "").replace(/\s+/g, " ").trim());
      }
    });
  }
  function wireMenus() {
    $$("[data-open='fdir']").forEach(function (b) {
      b.onclick = function (ev) { ev.preventDefault(); openDir(b); };
    });
    $$("[data-open='help']").forEach(function (b) {
      b.onclick = function (ev) { ev.preventDefault(); openHelp(b); };
    });
    $$("[data-open='related']").forEach(function (b) {
      b.onclick = function (ev) {
        ev.preventDefault();
        var c = (b.getAttribute("data-cats") || "").split(/\s+/).filter(Boolean);
        openRelated(b, c.length ? c : null);
      };
    });
    $$("[data-hist]").forEach(function (b) {
      b.onclick = function () { history[b.getAttribute("data-hist") === "back" ? "back" : "forward"](); };
    });
  }

  /* ── 6 分页（命令行右侧的 Page n/m） ───────────────────────────────── */
  function pager(opt) {
    var pages = opt.pages || [];
    var cur = 0;
    var lbl = $("[data-page-ind]"), ttl = $("[data-page-title]");
    function paint() {
      pages.forEach(function (p, i) {
        var n = $(p.sel);
        if (n) n.hidden = i !== cur;
      });
      if (lbl) lbl.textContent = "Page " + (cur + 1) + "/" + pages.length;
      if (ttl) ttl.textContent = pages[cur].title;
      $$("[data-page-go]").forEach(function (a) {
        var on = +a.getAttribute("data-page-go") === cur;
        a.classList.toggle("on", on);
        if (on) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current");
      });
    }
    $$("[data-page-go]").forEach(function (a) {
      a.onclick = function (e) { e.preventDefault(); cur = +a.getAttribute("data-page-go"); paint(); };
    });
    $$("[data-page-step]").forEach(function (b) {
      b.onclick = function () {
        cur = (cur + (+b.getAttribute("data-page-step")) + pages.length) % pages.length;
        paint();
      };
    });
    paint();
    return { set: function (i) { cur = i; paint(); } };
  }

  /* ── 7 迷你走势（编号行右边那个小图标位）───────────────────────────── */
  function spark(values, w, h) {
    var v = (values || []).filter(function (x) { return typeof x === "number" && isFinite(x); });
    if (v.length < 3) return "";
    w = w || 52; h = h || 15;
    var lo = Math.min.apply(null, v), hi = Math.max.apply(null, v), sp = (hi - lo) || 1;
    var d = v.map(function (x, i) {
      return (i ? "L" : "M") + (i / (v.length - 1) * (w - 1) + .5).toFixed(1) + "," +
        ((1 - (x - lo) / sp) * (h - 3) + 1.5).toFixed(1);
    }).join("");
    var rise = v[v.length - 1] >= v[0];
    return '<svg class="spk" viewBox="0 0 ' + w + " " + h + '" role="img" aria-label="' +
      (rise ? "区间上行" : "区间下行") + '"><path d="' + d + '" fill="none" stroke="' +
      (rise ? "#00b86b" : "#ff4d4d") + '" stroke-width="1"/></svg>';
  }

  /* ── 8 表头排序 ─────────────────────────────────────────────────────── */
  function sortable(table, onSort) {
    $$("thead th[data-k]", table).forEach(function (th) {
      th.tabIndex = 0;
      function run() {
        var k = th.getAttribute("data-k");
        var dir = th.getAttribute("aria-sort") === "descending" ? "asc" : "desc";
        $$("thead th[data-k]", table).forEach(function (o) { o.removeAttribute("aria-sort"); });
        th.setAttribute("aria-sort", dir === "desc" ? "descending" : "ascending");
        onSort(k, dir);
      }
      th.onclick = run;
      th.onkeydown = function (e) { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); run(); } };
    });
  }

  global.OOGLEX_CHROME = {
    tabs: tabs, fnbar: fnbar, command: command, runCommand: runCommand,
    wireNumbers: wireNumbers, wireMenus: wireMenus, pager: pager,
    spark: spark, sortable: sortable, openDir: openDir, openHelp: openHelp,
    openRelated: openRelated, flash: flash, say: say, esc: esc, $: $, $$: $$,
    init: function (opt) {
      opt = opt || {};
      if (opt.tabs) tabs("[data-tabs]", opt.tabs, opt.current);
      fnbar("[data-fnbar]", opt.current);
      wireNumbers(); wireMenus(); command("[data-command]");
    }
  };
})(window);
