/* 全球经济日历 · 前端
 * 读取 data.json（由 scripts/econ-calendar/build_calendar.py 生成）：把本周经济事件按本地时区
 * 分日渲染，支持按影响级别筛选；含预测值 / 前值 / 实际值。纯原生 JS。 */
(function () {
  "use strict";
  var DATA = null, FILTER = "all";
  var $ = function (id) { return document.getElementById(id); };
  function isNum(v) { return v !== null && v !== undefined && !isNaN(v); }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  var IMPACT = {
    high:    { c: "var(--high)", zh: "高" },
    medium:  { c: "var(--med)",  zh: "中" },
    low:     { c: "var(--low)",  zh: "低" },
    holiday: { c: "var(--hol)",  zh: "假日" }
  };
  var WD = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];
  function pad(n) { return (n < 10 ? "0" : "") + n; }
  function hm(d) { return pad(d.getHours()) + ":" + pad(d.getMinutes()); }
  function dayKey(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()); }
  function dayLabel(d) { return (d.getMonth() + 1) + "月" + d.getDate() + "日 " + WD[d.getDay()]; }
  function relFuture(ts) {
    var ms = Date.parse(ts) - Date.now();
    if (isNaN(ms) || ms < 0) return null;
    var m = Math.round(ms / 60000);
    if (m < 1) return "即将公布";
    if (m < 60) return m + " 分钟后";
    var h = Math.round(m / 60);
    if (h < 24) return h + " 小时后";
    return Math.round(h / 24) + " 天后";
  }

  function counts() {
    var c = { all: 0, high: 0, medium: 0, low: 0, holiday: 0 };
    (DATA.events || []).forEach(function (e) { c.all++; c[e.impact] = (c[e.impact] || 0) + 1; });
    return c;
  }

  function renderTabs() {
    var c = counts(), box = $("tabs");
    var defs = [["all", "全部"], ["high", "🔴 高影响"], ["medium", "🟠 中"], ["low", "⚪ 低"]];
    box.innerHTML = "";
    defs.forEach(function (d) {
      var b = document.createElement("button");
      b.textContent = d[1] + " · " + (c[d[0]] || 0);
      if (FILTER === d[0]) b.className = "on";
      b.onclick = function () { FILTER = d[0]; renderTabs(); renderList(); };
      box.appendChild(b);
    });
  }

  function cell(label, v, isAct) {
    return "<div class='cell" + (isAct && v ? " act" : "") + "'><span class='cl'>" + label +
      "</span><span class='cv'>" + esc(v || "—") + "</span></div>";
  }

  function rowHtml(e) {
    var im = IMPACT[e.impact] || IMPACT.low;
    var d = new Date(e.ts);
    var en = (e.titleEn && e.titleEn !== e.title) ? "<div class='en'>" + esc(e.titleEn) + "</div>" : "";
    return "<div class='ev'>" +
      "<div class='tm'>" + (isNaN(d) ? "—" : hm(d)) + "</div>" +
      "<div class='cy'>" + (e.flag || "🌐") + " <span>" + esc(e.country) + "</span></div>" +
      "<div class='imp' title='" + im.zh + "影响' style='background:" + im.c + "'></div>" +
      "<div class='nm'><div class='t'>" + esc(e.title) + "</div>" + en + "</div>" +
      "<div class='vals'>" + cell("实际", e.actual, true) + cell("预测", e.forecast) + cell("前值", e.previous) + "</div>" +
      "</div>";
  }

  function renderList() {
    var evs = (DATA.events || []).filter(function (e) { return FILTER === "all" || e.impact === FILTER; });
    var box = $("list");
    if (!evs.length) { box.innerHTML = "<div class='empty'>本周该筛选下暂无事件 🙂</div>"; return; }
    var groups = {}, order = [];
    evs.forEach(function (e) {
      var d = new Date(e.ts); if (isNaN(d)) return;
      var k = dayKey(d);
      if (!groups[k]) { groups[k] = []; order.push({ k: k, d: d }); }
      groups[k].push(e);
    });
    var todayK = dayKey(new Date());
    box.innerHTML = order.map(function (g) {
      var isToday = g.k === todayK;
      return "<div class='day" + (isToday ? " today" : "") + "'><div class='dh'>" +
        dayLabel(g.d) + (isToday ? " · 今天" : "") + "</div>" +
        groups[g.k].map(rowHtml).join("") + "</div>";
    }).join("");
  }

  function renderNext() {
    var box = $("next"), now = Date.now();
    var up = (DATA.events || []).filter(function (e) { return Date.parse(e.ts) >= now; })
      .sort(function (a, b) { return Date.parse(a.ts) - Date.parse(b.ts); });
    if (!up.length) { box.style.display = "none"; return; }
    var e = up[0], im = IMPACT[e.impact] || IMPACT.low, d = new Date(e.ts);
    box.style.display = "";
    box.innerHTML = "<span class='lab'>⏭ 接下来</span>" +
      "<span class='dot' title='" + im.zh + "影响' style='background:" + im.c + "'></span>" +
      "<span class='ev2'>" + (e.flag || "🌐") + " " + esc(e.title) +
      " <span class='cy2'>" + esc(e.country) + "</span></span>" +
      "<span class='when'><b>" + (relFuture(e.ts) || "—") + "</b> · " + hm(d) + "</span>";
  }

  function renderMeta() {
    var live = !DATA.demo;
    $("status").className = "status " + (live ? "live" : "demo");
    $("status").innerHTML = "<span class='sdot'></span>" + (live ? "实时 · 每日自动更新" : "示例数据 · 待刷新");
    $("weekinfo").textContent = (DATA.weekOf ? "本周 " + DATA.weekOf + "（UTC）" : "") +
      (isNum(DATA.count) ? " · 共 " + DATA.count + " 项" : "");
    $("foot").innerHTML = "数据来源 <b style='color:var(--hot)'>" + esc(DATA.source || "Forex Factory") + "</b> · 更新于 " +
      (DATA.updatedAt || "").replace("T", " ").replace("Z", " UTC") + "<br>" + esc(DATA.note || "") +
      "<br>事件时间已自动换算为你的本地时区显示。";
  }

  function boot(data) {
    DATA = data;
    renderNext(); renderTabs(); renderList(); renderMeta();
  }

  fetch("data.json?t=" + Date.now())
    .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(boot)
    .catch(function (e) { $("list").innerHTML = "<div class='empty'>数据加载失败：" + esc(e.message) + "</div>"; });
})();
