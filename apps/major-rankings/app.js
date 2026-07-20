/* 全球专业与就业前景榜 · 一份专业数据支撑四张榜单（薪资/就业率/起薪/AI前景）。纯原生 JS。 */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function isNum(v) { return v !== null && v !== undefined && !isNaN(v); }
  function usd(v) { return isNum(v) ? "$" + Math.round(v / 1000) + "K" : "—"; }

  var TABS = [
    { key: "mid", label: "💰 专业薪资", unit: "中期年薪", fmt: usd },
    { key: "start", label: "🎓 毕业起薪", unit: "应届起薪", fmt: usd },
    { key: "emp", label: "📈 就业率", unit: "毕业生就业率", fmt: function (v) { return v + "%"; } },
    { key: "future", label: "🚀 AI 时代前景", unit: "10 年前景分", fmt: function (v) { return v.toFixed(1); } }
  ];
  /* 四个可视化小条：字段 + 短名 + 取值格式 */
  var BARS = [
    { key: "start", short: "起薪", fmt: usd, color: "var(--c-start)" },
    { key: "mid", short: "薪资", fmt: usd, color: "var(--c-mid)" },
    { key: "emp", short: "就业", fmt: function (v) { return v + "%"; }, color: "var(--c-emp)" },
    { key: "future", short: "前景", fmt: function (v) { return v.toFixed(0); }, color: "var(--c-future)" }
  ];

  var DATA = null, tab = "mid", query = "", cat = "", RANGE = {};

  function aiTag(m) {
    if (m.aiBoost >= 70) return { t: "AI 受益", c: "boost" };
    if (m.aiRisk >= 50) return { t: "受 AI 冲击", c: "risk" };
    return { t: "AI 中性", c: "neu" };
  }

  function currentList() {
    var ms = DATA.majors.slice();
    if (cat) ms = ms.filter(function (m) { return m.cat === cat; });
    if (query) {
      var q = query.toLowerCase();
      ms = ms.filter(function (m) {
        var cl = (DATA.cats[m.cat] || {}).label || "";
        return ((m.en || "") + " " + (m.cn || "") + " " + cl).toLowerCase().indexOf(q) >= 0;
      });
    }
    ms = ms.filter(function (m) { return isNum(m[tab]); });
    ms.sort(function (a, b) { return b[tab] - a[tab]; });
    return ms;
  }

  function render() {
    var list = $("list"), ms = currentList();
    if (!ms.length) { list.innerHTML = "<div class='empty'>没有匹配的专业</div>"; return; }
    var t = TABS.filter(function (x) { return x.key === tab; })[0];
    var html = ms.map(function (m, i) {
      var c = DATA.cats[m.cat] || { label: m.cat, color: "#8aa6ff", emoji: "🎓" };
      var bars = BARS.map(function (b) {
        var has = isNum(m[b.key]), r = RANGE[b.key];
        var w = has && r ? Math.max(6, ((m[b.key] - r.min) / (r.span || 1)) * 100) : 0;
        return "<div class='bar" + (has ? "" : " na") + (b.key === tab ? " act" : "") + "'><span>" + b.short + "</span>" +
          "<span class='tk'><i style='width:" + w.toFixed(1) + "%;background:" + b.color + "'></i></span>" +
          "<span class='v'>" + (has ? b.fmt(m[b.key]) : "—") + "</span></div>";
      }).join("");
      var tg = aiTag(m);
      var meta = c.emoji + " " + esc(c.label) +
        "　<span class='gw" + (m.growth < 0 ? " dn" : "") + "'>10年 " + (m.growth >= 0 ? "+" : "") + m.growth + "%</span>" +
        "　<span class='ait " + tg.c + "'>" + tg.t + "</span>";
      return "<div class='rowcard' style='animation-delay:" + Math.min(i * 16, 340) + "ms'>" +
        "<div class='rk" + (i < 3 ? " top" : "") + "'>" + (i + 1) + "</div>" +
        "<div class='logo' style='background:" + c.color + "22;border-color:" + c.color + "55'>" + c.emoji + "</div>" +
        "<div class='info'><div class='nm'>" + esc(m.cn) + "</div>" +
          "<div class='meta'>" + esc(m.en) + "</div>" +
          "<div class='tags'>" + meta + "</div></div>" +
        "<div class='bars'>" + bars + "</div>" +
        "<div class='score'><div class='big'>" + t.fmt(m[tab]) + "</div><div class='lab'>" + t.unit + "</div></div>" +
        "</div>";
    }).join("");
    list.innerHTML = html;
  }

  function renderTabs() {
    $("tabs").innerHTML = TABS.map(function (t) {
      return "<span class='chip" + (t.key === tab ? " on" : "") + "' data-k='" + t.key + "'>" + t.label + "</span>";
    }).join("");
    Array.prototype.forEach.call($("tabs").children, function (el) {
      el.onclick = function () { tab = el.getAttribute("data-k"); renderTabs(); render(); };
    });
  }

  function renderCats() {
    var cnt = {};
    DATA.majors.forEach(function (m) { cnt[m.cat] = (cnt[m.cat] || 0) + 1; });
    var order = Object.keys(DATA.cats).filter(function (k) { return cnt[k]; });
    var html = "<span class='chip2" + (cat === "" ? " on" : "") + "' data-c=''>全部</span>";
    html += order.map(function (k) {
      var c = DATA.cats[k];
      return "<span class='chip2" + (cat === k ? " on" : "") + "' data-c='" + k + "'>" +
        c.emoji + " " + esc(c.label) + " " + cnt[k] + "</span>";
    }).join("");
    $("cats").innerHTML = html;
    Array.prototype.forEach.call($("cats").children, function (el) {
      el.onclick = function () { cat = el.getAttribute("data-c"); renderCats(); render(); };
    });
  }

  function renderMeta() {
    var d = DATA;
    $("statusTxt").textContent = "年度权威数据整理 · " + (d.vintage || d.asOf || "");
    var byMid = d.majors.slice().sort(function (a, b) { return b.mid - a.mid; })[0];
    var byFut = d.majors.slice().sort(function (a, b) { return b.future - a.future; })[0];
    var byEmp = d.majors.slice().sort(function (a, b) { return b.emp - a.emp; })[0];
    var h = "<span>覆盖 <b>" + d.majors.length + "</b> 个专业</span>";
    if (byMid) h += "<span>薪资第一 <b>" + esc(byMid.cn) + "</b></span>";
    if (byEmp) h += "<span>就业率第一 <b>" + esc(byEmp.cn) + "</b></span>";
    if (byFut) h += "<span>AI 前景第一 <b>" + esc(byFut.cn) + "</b></span>";
    $("summary").innerHTML = h;

    $("srcgrid").innerHTML = (d.sources || []).map(function (s) {
      return "<a class='srccard' href='" + esc(s.url) + "' target='_blank' rel='noopener'><b>" +
        esc(s.name) + " ↗</b><span>" + esc(s.desc || "") + "</span></a>";
    }).join("");
  }

  function prepRanges() {
    ["start", "mid", "emp", "future"].forEach(function (k) {
      var vs = DATA.majors.map(function (m) { return m[k]; }).filter(isNum);
      var mn = Math.min.apply(null, vs), mx = Math.max.apply(null, vs);
      RANGE[k] = { min: mn, max: mx, span: (mx - mn) || 1 };
    });
  }

  $("q").addEventListener("input", function () { query = this.value.trim(); render(); });

  fetch("data.json?t=" + Date.now())
    .then(function (r) { return r.json(); })
    .then(function (d) {
      DATA = d;
      prepRanges();
      renderMeta();
      renderTabs();
      renderCats();
      render();
    })
    .catch(function () {
      $("list").innerHTML = "<div class='empty'>数据加载失败，请稍后刷新重试</div>";
      $("statusTxt").textContent = "加载失败";
    });
})();
