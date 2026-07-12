/* 市场恐慌与贪婪指数 · 前端渲染
 * 读取同目录 data.json（由 scripts/fear-greed/build_fear_greed.py 每日生成），
 * 渲染仪表盘 + 4 个参考点 + 7 个驱动指标 + 近一年走势。纯原生 JS（含手绘 SVG 仪表盘）。 */
(function () {
  "use strict";
  var DATA = null;
  var $ = function (id) { return document.getElementById(id); };

  function isNum(v) { return v !== null && v !== undefined && !isNaN(v); }
  function zoneColor(s) {
    if (!isNum(s)) return "#98a3b2";
    return s < 25 ? "#d3403b" : s < 45 ? "#e8833a" : s < 55 ? "#e4b53d" : s < 75 ? "#7cb851" : "#3a9d5d";
  }
  function ratingZh(s) {
    if (!isNum(s)) return "—";
    return s < 25 ? "极度恐惧" : s < 45 ? "恐惧" : s < 55 ? "中性" : s < 75 ? "贪婪" : "极度贪婪";
  }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  /* —— 手绘 SVG 半圆仪表盘 —— */
  function gaugeSVG(score) {
    var cx = 160, cy = 160, r = 120, sw = 22;
    function pt(v, rr) { rr = rr || r; var a = Math.PI * v / 100; return [cx - rr * Math.cos(a), cy - rr * Math.sin(a)]; }
    function arc(v1, v2) {
      var p1 = pt(v1), p2 = pt(v2);
      return "M" + p1[0].toFixed(1) + " " + p1[1].toFixed(1) + " A" + r + " " + r + " 0 0 1 " + p2[0].toFixed(1) + " " + p2[1].toFixed(1);
    }
    var zones = [[0, 25, "#d3403b"], [25, 45, "#e8833a"], [45, 55, "#e4b53d"], [55, 75, "#7cb851"], [75, 100, "#3a9d5d"]];
    var s = "<svg viewBox='0 0 320 176' class='gauge'>";
    zones.forEach(function (z) {
      s += "<path d='" + arc(z[0], z[1]) + "' fill='none' stroke='" + z[2] + "' stroke-width='" + sw + "' stroke-linecap='butt'/>";
    });
    [0, 25, 50, 75, 100].forEach(function (v) {
      var lp = pt(v, r + 21);
      s += "<text x='" + lp[0].toFixed(1) + "' y='" + (lp[1] + 4).toFixed(1) + "' class='tick' text-anchor='middle'>" + v + "</text>";
    });
    var sc = isNum(score) ? Math.max(0, Math.min(100, score)) : 50;
    var deg = sc * 1.8 - 90;
    s += "<g class='needle' transform='rotate(" + deg.toFixed(1) + " " + cx + " " + cy + ")'>" +
      "<polygon points='" + (cx - 5) + "," + cy + " " + (cx + 5) + "," + cy + " " + cx + "," + (cy - r + 16) + "' fill='#f3f6f8'/></g>";
    s += "<circle cx='" + cx + "' cy='" + cy + "' r='10' fill='#f3f6f8'/><circle cx='" + cx + "' cy='" + cy + "' r='4.5' fill='#0b0e14'/></svg>";
    return s;
  }

  function renderGauge() {
    $("gauge").innerHTML = gaugeSVG(DATA.score);
    var col = zoneColor(DATA.score);
    $("reading").innerHTML =
      "<div class='num' style='color:" + col + "'>" + (isNum(DATA.score) ? DATA.score : "—") + "</div>" +
      "<div class='lab' style='color:" + col + "'>" + esc(DATA.ratingZh || ratingZh(DATA.score)) +
      " · " + esc((DATA.rating || "").toUpperCase()) + "</div>" +
      "<div class='sub'>综合读数（0–100）· 数据日期 " + esc(DATA.asOf || "—") + "</div>";
  }

  function renderRefs() {
    var map = [["close", "上一收盘"], ["week", "一周前"], ["month", "一月前"], ["year", "一年前"]];
    var refs = DATA.refs || {};
    $("refs").innerHTML = map.map(function (m) {
      var o = refs[m[0]], col = o ? zoneColor(o.score) : "#98a3b2";
      return "<div class='ref'><div class='k'>" + m[1] + "</div>" +
        "<div class='v' style='color:" + col + "'>" + (o ? o.score : "—") + "</div>" +
        "<div class='r' style='color:" + col + "'>" + (o ? esc(o.ratingZh || ratingZh(o.score)) : "") + "</div></div>";
    }).join("");
  }

  function renderIndicators() {
    var inds = DATA.indicators || [];
    if (!inds.length) { $("indicators").innerHTML = "<div class='empty'>暂无指标数据</div>"; return; }
    $("indicators").innerHTML = inds.map(function (it) {
      var col = zoneColor(it.score), left = Math.max(0, Math.min(100, it.score));
      return "<div class='ind'><div class='top'>" +
        "<div class='nm'>" + esc(it.name) + (it.desc ? "<small>" + esc(it.desc) + "</small>" : "") + "</div>" +
        "<div class='rt' style='color:" + col + "'>" + (isNum(it.score) ? it.score + " · " + esc(it.ratingZh || ratingZh(it.score)) : "—") + "</div>" +
        "</div><div class='barwrap'><div class='mk' style='left:" + left + "%'></div></div></div>";
    }).join("");
  }

  function renderHistory() {
    var h = DATA.history || [];
    if (h.length < 2) { $("histcard").style.display = "none"; return; }
    $("histcard").style.display = "";
    var W = 600, H = 120, pad = 8;
    function x(i) { return pad + i / (h.length - 1) * (W - 2 * pad); }
    function y(v) { return pad + (1 - Math.max(0, Math.min(100, v)) / 100) * (H - 2 * pad); }
    var bands = [[0, 25, "#d3403b"], [25, 45, "#e8833a"], [45, 55, "#e4b53d"], [55, 75, "#7cb851"], [75, 100, "#3a9d5d"]];
    var s = "<svg viewBox='0 0 " + W + " " + H + "' class='spark' preserveAspectRatio='none'>";
    bands.forEach(function (b) {
      var y1 = y(b[1]), y2 = y(b[0]);
      s += "<rect x='0' y='" + y1.toFixed(1) + "' width='" + W + "' height='" + (y2 - y1).toFixed(1) + "' fill='" + b[2] + "' opacity='0.08'/>";
    });
    var pts = h.map(function (p, i) { return x(i).toFixed(1) + "," + y(p.v).toFixed(1); }).join(" ");
    s += "<polyline points='" + pts + "' fill='none' stroke='#cdd6df' stroke-width='2' stroke-linejoin='round'/>";
    var last = h[h.length - 1];
    s += "<circle cx='" + x(h.length - 1).toFixed(1) + "' cy='" + y(last.v).toFixed(1) + "' r='3.5' fill='" + zoneColor(last.v) + "'/>";
    s += "</svg><div class='sub' style='color:var(--dim);font-size:0.76rem;text-align:right;margin-top:4px'>" +
      esc(h[0].t) + " → " + esc(last.t) + "</div>";
    $("hist").innerHTML = s;
  }

  function renderStatus() {
    var live = /cnn/i.test(DATA.source || "") && !/示例/.test(DATA.source || "");
    var el = $("status");
    el.className = "status " + (live ? "live" : "demo");
    el.innerHTML = "<span class='sdot'></span>" + (live ? "实时 · 每日自动更新" : "示例数据 · 待每日任务刷新");
  }

  function renderFooter() {
    var upd = DATA.updatedAt ? DATA.updatedAt.replace("T", " ").replace("Z", " UTC") : "—";
    var html = "<div class='src'>数据来源 <b>" + esc(DATA.source || "—") + "</b> · 数据日期 <b>" +
      esc(DATA.asOf || "—") + "</b> · 更新于 " + upd + "</div>";
    if (DATA.note) html += "<div>" + esc(DATA.note) + "</div>";
    $("foot").innerHTML = html;
  }

  function boot(data) {
    DATA = data;
    renderStatus(); renderGauge(); renderRefs(); renderHistory(); renderIndicators(); renderFooter();
  }

  fetch("data.json?t=" + Date.now())
    .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(boot)
    .catch(function (e) {
      $("gauge").innerHTML = "<div class='empty'>数据加载失败：" + esc(e.message) + "<br>请稍后刷新重试。</div>";
    });
})();
