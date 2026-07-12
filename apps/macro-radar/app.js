/* 宏观雷达 · Macro Radar · 前端渲染
 * 读取同目录 data.json（由 scripts/macro-radar/build_radar.py 每日生成），
 * 渲染：机制总览红绿灯 + 7 大制度信号 + 跨资产热力图 + 异动流。纯原生 JS。 */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  function isNum(v) { return v !== null && v !== undefined && v !== "" && !isNaN(v); }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  var STCOL = { stress: "#e0554f", neutral: "#e0a750", support: "#3fae7d" };
  var MUTCOL = { red: "#e0554f", amber: "#e0a750", green: "#3fae7d" };

  /* 迷你走势线：把一组数值画成自适配的折线 */
  function sparkSVG(vals, color) {
    if (!vals || vals.length < 2) return "";
    var w = 100, h = 34, n = vals.length;
    var mn = Math.min.apply(null, vals), mx = Math.max.apply(null, vals);
    var rng = (mx - mn) || 1;
    var pts = vals.map(function (v, i) {
      var x = (i / (n - 1)) * w;
      var y = h - 4 - ((v - mn) / rng) * (h - 8);
      return x.toFixed(1) + "," + y.toFixed(1);
    });
    var area = "0," + h + " " + pts.join(" ") + " " + w + "," + h;
    var id = "g" + Math.random().toString(36).slice(2, 8);
    return "<svg viewBox='0 0 " + w + " " + h + "' preserveAspectRatio='none'>" +
      "<defs><linearGradient id='" + id + "' x1='0' y1='0' x2='0' y2='1'>" +
      "<stop offset='0' stop-color='" + color + "' stop-opacity='.28'/>" +
      "<stop offset='1' stop-color='" + color + "' stop-opacity='0'/></linearGradient></defs>" +
      "<polygon points='" + area + "' fill='url(#" + id + ")'/>" +
      "<polyline points='" + pts.join(" ") + "' fill='none' stroke='" + color +
      "' stroke-width='1.6' stroke-linejoin='round' stroke-linecap='round'/></svg>";
  }

  /* 热力图单元格底色：负→红，0→中性，正→绿（±5% 饱和） */
  function heatColor(v) {
    if (!isNum(v)) return "rgba(255,255,255,.03)";
    var t = Math.max(-1, Math.min(1, v / 5));
    if (t >= 0) return "rgba(63,174,125," + (0.10 + t * 0.42).toFixed(3) + ")";
    return "rgba(224,85,79," + (0.10 + (-t) * 0.42).toFixed(3) + ")";
  }
  function fmtPct(v) { return isNum(v) ? (v > 0 ? "+" : "") + v.toFixed(1) : "—"; }

  function renderBadges(d) {
    var live = !!d.live;
    var clock = d.updatedAt ? d.updatedAt.replace("T", " · ").replace("Z", "") : (d.asOf || "");
    $("badges").innerHTML =
      (live
        ? "<span class='pill live'><span class='d'></span>LIVE</span>"
        : "<span class='pill sample'><span class='d'></span>示例数据 · SAMPLE</span>") +
      "<span class='pill clock'>" + esc((d.asOf || "") + " · " + (d.asOfSh ? d.asOfSh.slice(11) : "")) + "</span>";
  }

  function renderRegime(d) {
    var r = d.regime || {};
    var sc = isNum(r.score) ? Math.max(0, Math.min(100, r.score)) : 50;
    $("regime").innerHTML =
      "<div class='top'>" +
        "<div><div class='lab'>市场机制 · OVERALL REGIME</div>" +
          "<div class='row2' style='margin-top:8px'>" +
            "<div class='big'>" + esc(r.labelZh || "—") + "</div>" +
            "<div class='score'>" + (isNum(r.score) ? r.score : "—") + "<s>/100</s></div>" +
          "</div></div>" +
        "<div class='desc'>" + esc(r.desc || "") + "</div>" +
      "</div>" +
      "<div class='scale'>" +
        "<div class='ticks'><span>0</span><span>25</span><span>50</span><span>75</span><span>100</span></div>" +
        "<div class='barwrap'><div class='track'></div>" +
          "<div class='mark' style='left:" + sc + "%'></div></div>" +
        "<div class='ends'><span class='l'>◂ 收紧 · 风险</span><span class='c'>中性</span>" +
          "<span class='r'>宽松 · 支持 ▸</span></div>" +
      "</div>";
  }

  function renderSignals(d) {
    var sigs = d.signals || [];
    $("signals").innerHTML = sigs.map(function (s) {
      var col = STCOL[s.status] || "#8a97a6";
      return "<div class='panel sig'>" +
        "<div class='r1'><span class='en'>" + esc(s.en || "") + "</span>" +
          "<span class='dot' style='background:" + col + "'></span></div>" +
        "<h3>" + esc(s.zh || "") + "</h3>" +
        "<div class='sc'><b>" + (isNum(s.score) ? s.score : "—") + "</b><s>/100</s>" +
          "<span class='tag " + esc(s.status || "neutral") + "'>" + esc(s.statusZh || "—") + "</span></div>" +
        "<div class='spark'>" + sparkSVG(s.spark, col) + "</div>" +
        "<div class='d'>" + esc(s.desc || "") + "</div>" +
      "</div>";
    }).join("");
  }


  function renderMuts(d) {
    var read = $("mut-read");
    if (read) { read.textContent = d.mutSummary || ""; read.style.display = d.mutSummary ? "" : "none"; }
    var muts = d.mutations || [];
    if (!muts.length) { $("muts").innerHTML = "<div class='mut'><div class='mb'><div class='mt' style='color:#8a97a6'>今日暂无显著异动。</div></div></div>"; return; }
    $("muts").innerHTML = muts.map(function (m) {
      var col = MUTCOL[m.status] || "#8a97a6";
      var txt = esc(m.text || "").replace(/([+\-]?\d[\d.,]*\s?(?:bp|pips|B|%|σ)?)/g, "<em>$1</em>");
      return "<div class='mut'>" +
        "<span class='md' style='background:" + col + "'></span>" +
        "<div class='mb'><div class='mtop'>" +
          "<span class='sig-chip'>" + esc(m.sig || "") + "</span>" +
          (m.time ? "<span class='time'>" + esc(m.time) + "</span>" : "") +
        "</div><div class='mt'>" + txt + "</div></div></div>";
    }).join("");
  }

  // 各分类醒目主色（标题 + 左侧色条）
  var CATCOL = {
    "利率走廊": "#f2b84b", "联储流动性": "#4ac6f2", "实际利率与通胀预期": "#a78bfa",
    "期限结构与利差": "#5fd39a", "金融压力": "#ff6b5c", "信用利差": "#f58fb4",
    "融资压力": "#ff9d5c", "商品比率": "#e0a750", "波动率全景": "#7fd0ff"
  };
  function renderMacro(d) {
    var cats = (d.macro || []).filter(function (c) { return c.rows && c.rows.length; });
    var sec = $("macro-sec");
    if (!cats.length) { if (sec) sec.hidden = true; return; }
    if (sec) sec.hidden = false;
    $("macro").innerHTML = cats.map(function (c) {
      var col = CATCOL[c.zh] || "#34e0c4";
      var rows = c.rows.map(function (r) {
        var tone = r.tone || "flat";
        return "<div class='mrow'><div class='mn'>" + esc(r.name || "") +
          "<s>" + esc(r.id || "") + (r.asOf ? " · " + esc(r.asOf) : "") + "</s></div>" +
          "<div class='mv'>" + esc(r.val || "—") + "</div>" +
          "<div class='mc " + tone + "'>" + esc(r.chg || "") + "</div></div>";
      }).join("");
      return "<div class='mcat' style='border-top:3px solid " + col + "'>" +
        "<div class='mhead'><b style='color:" + col + "'>" + esc(c.zh || "") + "</b>" +
        "<span class='en'>" + esc(c.en || "") + "</span>" +
        "<span class='src'>" + esc(c.src || "") + "</span></div>" +
        "<div class='mrows'>" + rows + "</div></div>";
    }).join("");
  }

  function renderFoot(d) {
    var when = d.asOfSh ? (d.asOfSh + " (Asia/Shanghai)") : (d.asOf || "—");
    $("foot-left").textContent = "数据更新 · " + when;
    if (d.source) $("foot-src").textContent = d.source;
  }

  function render(d) {
    try { renderBadges(d); renderRegime(d); renderSignals(d); renderMuts(d); renderMacro(d); renderFoot(d); }
    catch (e) { console.error(e); }
  }

  /* —— Regime 时光机 ——
   * 读取 history.json（周频回溯，2006→今），SVG 时间轴：拖动查看任意日期的
   * 机制读数 + 7 信号；点击危机事件 chip 自动重放该窗口。缺文件则隐藏区块。 */
  var SIGZH = { liquidity: "流动性", volatility: "波动率", term: "期限溢价",
    credit: "信用利差", growth: "增长动能", usd: "美元汇率", breadth: "市场广度" };
  var SIGORDER = ["liquidity", "volatility", "term", "credit", "growth", "usd", "breadth"];
  function regimeBucket(x) {
    if (!isNum(x)) return { zh: "—", col: "#8a97a6" };
    if (x < 35) return { zh: "收紧 · 风险", col: "#e0554f" };
    if (x < 48) return { zh: "中性偏紧", col: "#e0834a" };
    if (x < 58) return { zh: "中性", col: "#e0a750" };
    if (x < 68) return { zh: "中性偏松", col: "#7cba63" };
    return { zh: "宽松 · 支持", col: "#3fae7d" };
  }
  function sigColTM(s) { return !isNum(s) ? "#8a97a6" : (s < 40 ? "#e0554f" : (s <= 60 ? "#e0a750" : "#3fae7d")); }

  function buildTM(h) {
    var dates = h.dates || [], regime = h.regime || [];
    if (dates.length < 50) return;
    var sec = $("tm-sec"); sec.hidden = false;
    var N = dates.length;
    var VW = 1000, VH = 240, T = 16, B = 6, L = 2, R = 2;
    function X(i) { return L + (VW - L - R) * i / (N - 1); }
    function Y(s) { return T + (VH - T - B) * (100 - s) / 100; }
    function dateIdx(d) {
      var lo = 0, hi = N - 1;
      while (lo < hi) { var m = (lo + hi) >> 1; if (dates[m] < d) lo = m + 1; else hi = m; }
      return lo;
    }

    // —— SVG ——
    var s = "<svg viewBox='0 0 " + VW + " " + VH + "' preserveAspectRatio='none'>";
    s += "<defs><linearGradient id='tmg' x1='0' y1='0' x2='0' y2='1'>" +
      "<stop offset='0' stop-color='#3fae7d'/><stop offset='0.42' stop-color='#e0a750'/>" +
      "<stop offset='1' stop-color='#e0554f'/></linearGradient>" +
      "<linearGradient id='tmf' x1='0' y1='0' x2='0' y2='1'>" +
      "<stop offset='0' stop-color='#34e0c4' stop-opacity='.14'/>" +
      "<stop offset='1' stop-color='#34e0c4' stop-opacity='0'/></linearGradient></defs>";
    [25, 50, 75].forEach(function (g) {
      s += "<line x1='0' x2='" + VW + "' y1='" + Y(g).toFixed(1) + "' y2='" + Y(g).toFixed(1) +
        "' stroke='rgba(255,255,255,.05)' stroke-width='1'/>" +
        "<text x='4' y='" + (Y(g) - 3).toFixed(1) + "' fill='rgba(255,255,255,.18)' font-size='9'>" + g + "</text>";
    });
    // 危机事件带（手工标注的历史案例）
    (h.episodes || []).forEach(function (ep) {
      var a = X(dateIdx(ep.from)), b = X(dateIdx(ep.to));
      s += "<rect class='tmband' data-ep='" + ep.id + "' x='" + a.toFixed(1) + "' y='" + T +
        "' width='" + Math.max(2, b - a).toFixed(1) + "' height='" + (VH - T - B) +
        "' fill='rgba(224,85,79,.09)'/>" +
        "<text x='" + (a + 2).toFixed(1) + "' y='" + (T - 4) + "' fill='rgba(255,107,92,.6)' font-size='9'>" +
        esc(ep.from.slice(0, 4)) + "</text>";
    });
    // 自动预警带：连续 ≥2 周 regime≤35 且不与上面标注重叠的压力段——
    // 数据每日刷新，未来的新危机会在这里自动画出 ⚠ 红区，无需手工标注。
    function hitEpisode(d0, d1) {
      return (h.episodes || []).some(function (ep) { return d0 <= ep.to && d1 >= ep.from; });
    }
    var run0 = -1;
    for (var j = 0; j <= N; j++) {
      var bad = j < N && isNum(regime[j]) && regime[j] <= 35;
      if (bad && run0 < 0) run0 = j;
      if (!bad && run0 >= 0) {
        if (j - run0 >= 2 && !hitEpisode(dates[run0], dates[j - 1])) {
          var wa = X(run0), wb = X(j - 1);
          s += "<rect x='" + wa.toFixed(1) + "' y='" + T + "' width='" + Math.max(2, wb - wa).toFixed(1) +
            "' height='" + (VH - T - B) + "' fill='rgba(224,85,79,.13)'/>" +
            "<text x='" + (wa + 2).toFixed(1) + "' y='" + (T - 4) +
            "' fill='rgba(255,107,92,.75)' font-size='9'>⚠</text>";
        }
        run0 = -1;
      }
    }
    // 曲线 + 面积
    var pts = [], area = "";
    for (var i = 0; i < N; i++) {
      if (!isNum(regime[i])) continue;
      pts.push(X(i).toFixed(1) + "," + Y(regime[i]).toFixed(1));
    }
    if (pts.length > 1) {
      area = pts[0].split(",")[0] + "," + VH + " " + pts.join(" ") + " " + pts[pts.length - 1].split(",")[0] + "," + VH;
      s += "<polygon points='" + area + "' fill='url(#tmf)'/>";
      s += "<polyline points='" + pts.join(" ") + "' fill='none' stroke='url(#tmg)' stroke-width='1.8' stroke-linejoin='round'/>";
    }
    // 游标
    s += "<g id='tm-cursor'><line y1='" + T + "' y2='" + (VH - B) + "' x1='0' x2='0' stroke='#e8eef2' stroke-width='1' stroke-dasharray='2,3' opacity='.75'/>" +
      "<circle cx='0' cy='0' r='4.5' fill='#e8eef2' stroke='#0b0f14' stroke-width='1.5'/></g>";
    s += "</svg>";
    var chart = $("tm-chart");
    chart.innerHTML = s;
    var svg = chart.querySelector("svg");
    var cur = svg.querySelector("#tm-cursor");
    var curLine = cur.querySelector("line"), curDot = cur.querySelector("circle");

    // —— 读数 ——
    function setIdx(i) {
      i = Math.max(0, Math.min(N - 1, Math.round(i)));
      var x = X(i);
      curLine.setAttribute("x1", x); curLine.setAttribute("x2", x);
      curDot.setAttribute("cx", x);
      curDot.setAttribute("cy", isNum(regime[i]) ? Y(regime[i]) : VH / 2);
      var b = regimeBucket(regime[i]);
      $("tm-date").textContent = dates[i];
      $("tm-score").textContent = isNum(regime[i]) ? regime[i] : "—";
      $("tm-score").style.color = b.col;
      $("tm-label").textContent = b.zh;
      $("tm-label").style.color = b.col;
      $("tm-sigbars").innerHTML = SIGORDER.map(function (k) {
        var arr = (h.signals || {})[k] || [];
        var v = arr[i], c = sigColTM(v);
        return "<div class='tm-sig'><div class='n'>" + SIGZH[k] + "</div>" +
          "<div class='v' style='color:" + c + "'>" + (isNum(v) ? v : "—") + "</div>" +
          "<div class='bar'><i style='width:" + (isNum(v) ? v : 0) + "%;background:" + c + "'></i></div></div>";
      }).join("");
      return i;
    }

    // —— 拖动 ——
    var anim = null;
    function stopAnim() { if (anim) { cancelAnimationFrame(anim); anim = null; } }
    function posToIdx(clientX) {
      var r = chart.getBoundingClientRect();
      return (clientX - r.left) / Math.max(1, r.width) * (N - 1);
    }
    var dragging = false;
    chart.addEventListener("pointerdown", function (e) {
      dragging = true; stopAnim(); chart.setPointerCapture(e.pointerId); setIdx(posToIdx(e.clientX));
    });
    chart.addEventListener("pointermove", function (e) { if (dragging) setIdx(posToIdx(e.clientX)); });
    chart.addEventListener("pointerup", function () { dragging = false; });
    chart.addEventListener("pointercancel", function () { dragging = false; });

    // —— 危机事件 chips + 重放 ——
    var chipsEl = $("tm-chips"), descEl = $("tm-desc");
    chipsEl.innerHTML = (h.episodes || []).map(function (ep) {
      return "<button class='tm-chip' data-ep='" + ep.id + "'>" + esc(ep.name) + "</button>";
    }).join("");
    function playEpisode(ep, btn) {
      stopAnim();
      chipsEl.querySelectorAll(".tm-chip").forEach(function (c) { c.classList.remove("on"); });
      if (btn) btn.classList.add("on");
      descEl.hidden = false;
      descEl.innerHTML = "<b>" + esc(ep.name) + " · " + esc(ep.en || "") + "</b>　" + esc(ep.desc || "");
      var i0 = dateIdx(ep.from), i1 = dateIdx(ep.to);
      var dur = Math.max(2600, (i1 - i0) * 90), t0 = null;
      setIdx(i0);
      function step(ts) {
        if (t0 === null) t0 = ts;
        var p = Math.min(1, (ts - t0) / dur);
        var e2 = p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2; // easeInOut
        setIdx(i0 + (i1 - i0) * e2);
        if (p < 1) anim = requestAnimationFrame(step);
      }
      anim = requestAnimationFrame(step);
    }
    chipsEl.addEventListener("click", function (e) {
      var btn = e.target.closest(".tm-chip");
      if (!btn) return;
      var ep = (h.episodes || []).filter(function (x) { return x.id === btn.getAttribute("data-ep"); })[0];
      if (ep) playEpisode(ep, btn);
    });

    setIdx(N - 1);   // 初始停在最新
  }

  function renderTimeMachine() {
    fetch("history.json?t=" + Date.now())
      .then(function (r) { if (!r.ok) throw new Error("no history"); return r.json(); })
      .then(function (h) { try { buildTM(h); } catch (e) { console.error(e); } })
      .catch(function () { /* 无历史文件时隐藏区块 */ });
  }

  fetch("data.json?t=" + Date.now())
    .then(function (r) { if (!r.ok) throw new Error("data.json " + r.status); return r.json(); })
    .then(render)
    .catch(function (e) {
      console.error(e);
      $("regime").innerHTML = "<div class='regime' style='padding:26px'><div class='desc'>数据加载中或暂不可用，请稍后刷新。</div></div>";
    });
  renderTimeMachine();
})();
