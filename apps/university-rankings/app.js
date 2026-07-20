/* 全球大学排名 300 强 · 读取 data.json 渲染四榜合一的大学综合排名。纯原生 JS。 */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function isNum(v) { return v !== null && v !== undefined && !isNaN(v); }

  /* 四大榜单：key 对应 data 里的字段；轴的颜色与短名与 index.html 中 CSS 变量一致。 */
  var AXES = [
    { key: "qs", short: "QS", color: "var(--qs)" },
    { key: "the", short: "THE", color: "var(--the)" },
    { key: "arwu", short: "ARWU", color: "var(--arwu)" },
    { key: "usn", short: "USN", color: "var(--usn)" }
  ];
  var AXMAX = 500;  // 位次条的分母（超过按满格封顶）
  var TABS = [
    { key: "combo", label: "🏆 综合" },
    { key: "qs", label: "🎓 QS" },
    { key: "the", label: "📊 THE 泰晤士" },
    { key: "arwu", label: "🔬 ARWU 软科" },
    { key: "usn", label: "🌐 U.S. News" }
  ];

  /* 国家/地区英文键 → 中文名（用于中文界面显示；未收录则回退英文键）。 */
  var CN_COUNTRY = {
    "United States": "美国", "United Kingdom": "英国", "China": "中国",
    "Hong Kong SAR": "中国香港", "Hong Kong": "中国香港", "Taiwan": "中国台湾",
    "Singapore": "新加坡", "Japan": "日本", "South Korea": "韩国", "Switzerland": "瑞士",
    "Germany": "德国", "France": "法国", "Netherlands": "荷兰", "Canada": "加拿大",
    "Australia": "澳大利亚", "Sweden": "瑞典", "Belgium": "比利时", "Denmark": "丹麦",
    "Italy": "意大利", "Spain": "西班牙", "Finland": "芬兰", "Norway": "挪威",
    "Austria": "奥地利", "Ireland": "爱尔兰", "New Zealand": "新西兰", "Malaysia": "马来西亚",
    "Saudi Arabia": "沙特", "India": "印度", "Brazil": "巴西", "Russia": "俄罗斯",
    "Israel": "以色列", "Argentina": "阿根廷", "Mexico": "墨西哥", "South Africa": "南非",
    "Chile": "智利", "Qatar": "卡塔尔", "United Arab Emirates": "阿联酋", "Thailand": "泰国",
    "Portugal": "葡萄牙", "Czech Republic": "捷克", "Poland": "波兰", "Greece": "希腊",
    "Luxembourg": "卢森堡", "Estonia": "爱沙尼亚", "Turkey": "土耳其", "Iran": "伊朗",
    "Indonesia": "印度尼西亚"
  };
  function cc(c) { return CN_COUNTRY[c] || c || ""; }

  var DATA = null, tab = "combo", query = "", country = "";

  /* 综合分：至少命中 2 个榜才计；均位 = 各榜位次的平均（越小越靠前）。 */
  function avgRank(u) {
    var rs = [];
    AXES.forEach(function (a) { if (isNum(u[a.key])) rs.push(u[a.key]); });
    u._n = rs.length;
    u._avg = rs.length >= 2 ? rs.reduce(function (s, v) { return s + v; }, 0) / rs.length : null;
    return u._avg;
  }

  function currentList() {
    var us = DATA.universities.slice();
    if (country) us = us.filter(function (u) { return u.country === country; });
    if (query) {
      var q = query.toLowerCase();
      us = us.filter(function (u) {
        return ((u.name || "") + " " + (u.cn || "") + " " + (u.country || "") + " " + cc(u.country)).toLowerCase().indexOf(q) >= 0;
      });
    }
    if (tab === "combo") {
      us = us.filter(function (u) { return isNum(u._avg); });
      us.sort(function (a, b) { return a._avg - b._avg; });
    } else {
      us = us.filter(function (u) { return isNum(u[tab]); });
      us.sort(function (a, b) { return a[tab] - b[tab]; });
    }
    return us;
  }

  function mainScore(u) {
    if (tab === "combo") return { v: u._avg.toFixed(1), lab: u._n < 4 ? "均位 · " + u._n + " 榜" : "四榜均位" };
    var map = { qs: "QS 位次", the: "THE 位次", arwu: "ARWU 位次", usn: "U.S. News 位次" };
    return { v: "#" + u[tab], lab: map[tab] };
  }

  function render() {
    var list = $("list"), us = currentList();
    if (!us.length) { list.innerHTML = "<div class='empty'>没有匹配的学校</div>"; return; }
    var html = us.map(function (u, i) {
      var ini = esc((u.cn || u.name || "?").slice(0, 1));
      var bars = AXES.map(function (a) {
        var has = isNum(u[a.key]);
        var w = has ? Math.max(5, (1 - Math.min(u[a.key], AXMAX) / AXMAX) * 100) : 0;
        return "<div class='bar" + (has ? "" : " na") + "'><span>" + a.short + "</span>" +
          "<span class='tk'><i style='width:" + w.toFixed(1) + "%;background:" + a.color + "'></i></span>" +
          "<span class='v'>" + (has ? "#" + u[a.key] : "—") + "</span></div>";
      }).join("");
      var sc = mainScore(u);
      return "<div class='rowcard' style='animation-delay:" + Math.min(i * 18, 360) + "ms'>" +
        "<div class='rk" + (i < 3 ? " top" : "") + "'>" + (i + 1) + "</div>" +
        "<div class='logo'>" + ini + "</div>" +
        "<div class='info'><div class='nm'>" + esc(u.cn || u.name) + "</div>" +
          "<div class='meta'>" + (u.flag || "🌐") + " " + esc(cc(u.country)) +
          (u.cn && u.name ? " · " + esc(u.name) : "") + "</div></div>" +
        "<div class='bars'>" + bars + "</div>" +
        "<div class='score'><div class='big'>" + sc.v + "</div><div class='lab'>" + sc.lab + "</div></div>" +
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

  function renderCountries() {
    /* 上榜数最多的国家/地区作为快捷筛选。 */
    var cnt = {};
    DATA.universities.forEach(function (u) {
      if (u.country) cnt[u.country] = (cnt[u.country] || 0) + 1;
    });
    var top = Object.keys(cnt).sort(function (a, b) { return cnt[b] - cnt[a]; }).slice(0, 10);
    var flag = {};
    DATA.universities.forEach(function (u) { if (u.country && !flag[u.country]) flag[u.country] = u.flag; });
    var html = "<span class='chip2" + (country === "" ? " on" : "") + "' data-c=''>全部</span>";
    html += top.map(function (c) {
      return "<span class='chip2" + (country === c ? " on" : "") + "' data-c='" + esc(c) + "'>" +
        (flag[c] || "🌐") + " " + esc(cc(c)) + " " + cnt[c] + "</span>";
    }).join("");
    $("countries").innerHTML = html;
    Array.prototype.forEach.call($("countries").children, function (el) {
      el.onclick = function () { country = el.getAttribute("data-c"); renderCountries(); render(); };
    });
  }

  function renderMeta() {
    var d = DATA;
    var st = $("status"), stTxt = $("statusTxt");
    if (d.seed) {
      st.className = "status demo";
      stTxt.textContent = "上线快照（近似值）· 首次自动更新后即为四榜实时数据";
    } else {
      st.className = "status live";
      var t = Date.parse(d.updatedAt);
      var ago = isNaN(t) ? "" : Math.max(1, Math.round((Date.now() - t) / 3600000)) + " 小时前";
      stTxt.textContent = "四榜实时数据 · 更新于 " + (ago || d.asOf || "");
    }

    var byAvg = d.universities.slice().filter(function (u) { return isNum(u._avg); })
      .sort(function (a, b) { return a._avg - b._avg; });
    var countries = {};
    d.universities.forEach(function (u) { if (u.country) countries[u.country] = 1; });
    var cn = d.universities.filter(function (u) {
      return u.country === "China" || u.country === "Hong Kong SAR" || u.country === "Taiwan";
    }).length;
    var h = "<span>覆盖 <b>" + d.universities.length + "</b> 所</span>";
    if (byAvg[0]) h += "<span>综合第一 <b>" + esc(byAvg[0].cn || byAvg[0].name) + "</b></span>";
    h += "<span>上榜 <b>" + Object.keys(countries).length + "</b> 个国家/地区</span>";
    h += "<span>中国高校 <b>" + cn + "</b> 所</span>";
    $("summary").innerHTML = h;

    $("srcgrid").innerHTML = (d.sources || []).map(function (s) {
      return "<a class='srccard' href='" + esc(s.url) + "' target='_blank' rel='noopener'><b>" +
        esc(s.name) + " ↗</b><span>" + esc(s.desc || "") + "</span></a>";
    }).join("");
  }

  $("q").addEventListener("input", function () { query = this.value.trim(); render(); });

  fetch("data.json?t=" + Date.now())
    .then(function (r) { return r.json(); })
    .then(function (d) {
      DATA = d;
      d.universities.forEach(avgRank);
      renderMeta();
      renderTabs();
      renderCountries();
      render();
    })
    .catch(function () {
      $("list").innerHTML = "<div class='empty'>数据加载失败，请稍后刷新重试</div>";
      $("statusTxt").textContent = "加载失败";
    });
})();
