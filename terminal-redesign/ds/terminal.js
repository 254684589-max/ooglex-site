/* ===========================================================================
   OOGLEX 终端交互层 · Terminal Shell
   ---------------------------------------------------------------------------
   三份草案共用。只做终端外壳的交互，不碰数据装配（那在 feed.js）。

   负责
   ----
   1. 命令栏：输入代码或功能名 → 高亮定位到对应窗口/行，回车跳转。
   2. 标准 / 专业模式：切换信息密度（行高、字号、次要列显隐），记在 localStorage。
   3. 时钟与市场状态：纽约 / 伦敦 / 东京 / 上海，按公开常规时段推算（不含节假日）。
   4. 窗口按钮：MAX 占满整行、SET 切换该窗口的次要列、EXP 导出该窗口为 CSV。
   =========================================================================== */
(function (global) {
  "use strict";

  var KEY_DENSITY = "ooglex.terminal.density";
  var F = global.OOGLEX_FEED;

  function $(s, r) { return (r || document).querySelector(s); }
  function $$(s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); }

  /* ── 标准 / 专业模式 ─────────────────────────────────────────────────── */
  function readDensity() {
    try {
      var v = localStorage.getItem(KEY_DENSITY);
      return v === "pro" || v === "std" ? v : "std";
    } catch (e) { return "std"; }
  }
  function applyDensity(d) {
    document.documentElement.setAttribute("data-density", d);
    try { localStorage.setItem(KEY_DENSITY, d); } catch (e) {}
    $$("[data-mode-btn]").forEach(function (b) {
      b.setAttribute("aria-pressed", b.getAttribute("data-mode-btn") === d ? "true" : "false");
    });
    /* 专业模式显示全部列；标准模式收起次要列 */
    $$(".t-col-pro").forEach(function (el) { el.classList.toggle("t-hide", d !== "pro"); });
    document.dispatchEvent(new CustomEvent("ooglex:density", { detail: { density: d } }));
  }
  function initModes() {
    $$("[data-mode-btn]").forEach(function (b) {
      b.addEventListener("click", function () { applyDensity(b.getAttribute("data-mode-btn")); });
    });
    applyDensity(readDensity());
  }

  /* ── 时钟与市场状态 ─────────────────────────────────────────────────── */
  function p2(n) { return n < 10 ? "0" + n : "" + n; }
  function initClocks() {
    var host = $("[data-clocks]");
    var mkts = $("[data-markets]");
    if (!host && !mkts) return;
    function tick() {
      var now = new Date();
      var st = F.marketStatus(now);
      if (host) {
        host.innerHTML = st.filter(function (x, i, a) {
          return a.findIndex(function (y) { return y.city === x.city; }) === i;
        }).map(function (x) {
          return "<span>" + x.city + " <b>" + p2(x.parts.h) + ":" + p2(x.parts.m) + "</b></span>";
        }).join("") + "<span>UTC <b>" + p2(now.getUTCHours()) + ":" + p2(now.getUTCMinutes()) + ":" + p2(now.getUTCSeconds()) + "</b></span>";
      }
      if (mkts) {
        mkts.innerHTML = st.filter(function (x) { return x.id !== "NASDAQ"; }).map(function (x) {
          return '<span class="t-mkt ' + (x.open ? "open" : "closed") + '"><i></i><b>' + x.id + "</b> " +
            (x.open ? "OPEN" : "CLOSED") + "</span>";
        }).join("");
      }
      setTimeout(tick, 1000 - (Date.now() % 1000));
    }
    tick();
  }

  /* ── 命令栏 ─────────────────────────────────────────────────────────── */
  /* 支持：① 窗口/功能名（MARKETS、RATES、FX…）② 标的代码或名称（SPX、US10Y、WTI…） */
  function initCommand() {
    var input = $("[data-command]");
    if (!input) return;
    var hint = $("[data-command-hint]");

    function clearMarks() {
      $$(".t-cmd-hit").forEach(function (el) { el.classList.remove("t-cmd-hit"); });
    }
    function run(q) {
      q = String(q || "").trim();
      if (!q) { clearMarks(); if (hint) hint.textContent = ""; return; }
      var Q = q.toUpperCase();
      clearMarks();

      /* ① 功能 / 窗口 */
      var win = $$("[data-fn]").find(function (el) {
        return el.getAttribute("data-fn").toUpperCase().split(/\s+/).indexOf(Q) >= 0;
      });
      if (win) {
        win.scrollIntoView({ block: "start", behavior: "smooth" });
        win.classList.add("t-cmd-hit");
        if (hint) hint.textContent = "定位窗口 " + Q;
        return;
      }
      /* ② 标的：按 data-tk（代码）或 data-nm（名称）匹配 */
      var rows = $$("[data-tk],[data-nm]").filter(function (el) {
        var tk = (el.getAttribute("data-tk") || "").toUpperCase();
        var nm = el.getAttribute("data-nm") || "";
        return tk === Q || tk.indexOf(Q) === 0 || nm.indexOf(q) >= 0;
      });
      if (rows.length) {
        rows.slice(0, 40).forEach(function (el) { el.classList.add("t-cmd-hit"); });
        rows[0].scrollIntoView({ block: "center", behavior: "smooth" });
        if (hint) hint.textContent = "命中 " + rows.length + " 行";
        return;
      }
      if (hint) hint.textContent = "无匹配：" + q + "（可试 SPX / US10Y / DXY / WTI / VIX / MACRO）";
    }
    input.addEventListener("keydown", function (e) {
      if (e.key === "Enter") { e.preventDefault(); run(input.value); }
      if (e.key === "Escape") { input.value = ""; clearMarks(); if (hint) hint.textContent = ""; }
    });
    var go = $("[data-command-go]");
    if (go) go.addEventListener("click", function () { run(input.value); });
    /* 斜杠聚焦命令栏，和真终端的习惯一致 */
    document.addEventListener("keydown", function (e) {
      if (e.key === "/" && document.activeElement !== input &&
          !/^(INPUT|TEXTAREA|SELECT)$/.test((document.activeElement || {}).tagName || "")) {
        e.preventDefault(); input.focus();
      }
    });
  }

  /* ── 窗口按钮：MAX / SET / EXP ──────────────────────────────────────── */
  function initWindowTools() {
    $$(".t-win").forEach(function (win) {
      var tools = $(".t-tools", win);
      if (!tools) return;
      tools.addEventListener("click", function (e) {
        var btn = e.target.closest("button");
        if (!btn) return;
        var act = btn.getAttribute("data-act");
        if (act === "max") {
          var on = win.classList.toggle("t-maxed");
          win.style.gridColumn = on ? "span 12" : "";
          btn.style.color = on ? "var(--t-amber)" : "";
          win.scrollIntoView({ block: "nearest" });
        } else if (act === "set") {
          /* 该窗口内的次要列显隐，与全局模式独立 */
          var hid = win.classList.toggle("t-win-compact");
          $$(".t-col-x", win).forEach(function (el) { el.classList.toggle("t-hide", hid); });
          btn.style.color = hid ? "var(--t-amber)" : "";
        } else if (act === "exp") {
          exportCSV(win);
        }
      });
    });
  }
  function exportCSV(win) {
    var tables = $$("table", win);
    var name = ($("h2", win) || {}).textContent || "window";
    if (!tables.length) { alert("本窗口没有可导出的表格。"); return; }
    function csvRows(tbl) {
      return $$("tr", tbl).map(function (tr) {
        return $$("th,td", tr).filter(function (c) { return !c.classList.contains("t-hide"); })
          .map(function (c) {
            var t = (c.innerText || "").replace(/\s+/g, " ").trim().replace(/"/g, '""');
            return /[",]/.test(t) ? '"' + t + '"' : t;
          }).join(",");
      }).join("\n");
    }
    /* 导出必须自带出处：窗口脚注里的来源 / 数据日期 / 频率 / 状态一起写进表头注释 */
    var foot = $("footer", win);
    var prov = foot ? (foot.innerText || "").replace(/\s+/g, " ").trim() : "";
    var head = "# OOGLEX " + name.trim() + " · 导出于 " + new Date().toISOString() + "\n";
    if (prov) head += "# " + prov + "\n";
    var body = tables.map(function (t, k) {
      var cap = tables.length > 1 ? "# 表 " + (k + 1) + (t.id ? " (" + t.id + ")" : "") + "\n" : "";
      return cap + csvRows(t);
    }).join("\n\n");
    var blob = new Blob(["\ufeff" + head + body], { type: "text/csv;charset=utf-8" });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "ooglex-" + name.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-") + ".csv";
    document.body.appendChild(a); a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 0);
  }

  /* ── 排序（给带 data-sort 的表用）────────────────────────────────────── */
  function makeSortable(table, onSort) {
    $$("thead th[data-k]", table).forEach(function (th) {
      th.classList.add("sortable");
      th.setAttribute("role", "button");
      th.setAttribute("tabindex", "0");
      function go() { onSort(th.getAttribute("data-k"), th); }
      th.addEventListener("click", go);
      th.addEventListener("keydown", function (e) {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); go(); }
      });
    });
  }

  function init() {
    initModes();
    initClocks();
    initCommand();
    initWindowTools();
  }

  global.OOGLEX_TERMINAL = {
    init: init, applyDensity: applyDensity, readDensity: readDensity,
    makeSortable: makeSortable, exportCSV: exportCSV, $: $, $$: $$
  };
})(window);
