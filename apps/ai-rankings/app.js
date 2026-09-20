/* 全球大模型评测榜 · 读取 data.json 渲染三榜合一的大模型排名。纯原生 JS。 */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function isNum(v) { return v !== null && v !== undefined && !isNaN(v); }

  /* 厂商配色（字母牌兜底） */
  var ORG = {
    "OpenAI": "#74d0a5", "Anthropic": "#e0997a", "Google": "#8ab4f8", "xAI": "#cbd5e1",
    "DeepSeek": "#6c8cff", "Alibaba": "#ff8f4d", "Moonshot AI": "#b48cff", "Zhipu AI": "#58c4dd",
    "Meta": "#4a9df8", "Mistral AI": "#ffb13d", "MiniMax": "#ff6c8f", "ByteDance": "#59d0ff"
  };
  /* 厂商 logo：优先本站自托管（logos/*.png，内地可达），失败回退字母牌 */
  var ORG_LOGO = {
    "OpenAI": "openai", "Anthropic": "anthropic", "Google": "google", "xAI": "xai",
    "Meta": "meta", "Mistral AI": "mistral", "DeepSeek": "deepseek",
    "Alibaba": "alibaba", "Moonshot AI": "moonshot", "Zhipu AI": "zhipu",
    "MiniMax": "minimax", "ByteDance": "bytedance", "Tencent": "tencent",
    "Baidu": "baidu", "NVIDIA": "nvidia", "Amazon": "amazon", "Cohere": "cohere",
    "Microsoft": "microsoft", "01.AI": "01ai", "Reka AI": "reka", "AI21 Labs": "ai21"
  };
  var TABS = [
    { key: "combo", label: "🏆 多源共识" },
    { key: "arena", label: "⚔️ 竞技场 Elo" },
    { key: "livebench", label: "🧪 LiveBench" },
    { key: "aa", label: "📊 AA 智能指数" },
    { key: "open", label: "🔓 开源模型" }
  ];
  var AXES = [
    { key: "arena", short: "Arena", color: "var(--arena)", fmt: function (v) { return Math.round(v); } },
    { key: "livebench", short: "LiveB", color: "var(--lb)", fmt: function (v) { return v.toFixed(1); } },
    { key: "aa", short: "智能", color: "var(--aa)", fmt: function (v) { return v.toFixed(1); } }
  ];
  var W = { arena: 0.20, livebench: 0.30, aa: 0.50 };

  var DATA = null, tab = "combo", query = "";

  /* 各轴 min/max 仅用于条形图。综合分优先使用后端已固定的数据口径，
     避免前端只拿 Top40 再归一化导致排名二次漂移。 */
  function prepare(models) {
    var rng = {};
    AXES.forEach(function (a) {
      var vs = models.map(function (m) { return m[a.key]; }).filter(isNum);
      rng[a.key] = vs.length ? { min: Math.min.apply(null, vs), max: Math.max.apply(null, vs) } : null;
    });
    var activeAxes = (DATA.comboAxes || AXES.map(function(a){return a.key;}))
      .filter(function(k){ return !DATA.axisStatus || DATA.axisStatus[k] !== false; });

    models.forEach(function (m) {
      m._n = {};
      AXES.forEach(function (a) {
        var r = rng[a.key];
        if (isNum(m[a.key]) && r && r.max > r.min) {
          m._n[a.key] = (m[a.key] - r.min) / (r.max - r.min);
        }
      });

      if (isNum(m.combo)) {
        m._combo = Number(m.combo);
        m._axes = Number(m.comboAxes || activeAxes.length || 0);
        return;
      }

      /* Backward compatibility for older data.json snapshots. Only calculate
         when the model fully covers every currently active source. */
      var ok = activeAxes.length >= 2 && activeAxes.every(function(k){
        return m._n[k] !== undefined;
      });
      if (!ok) {
        m._combo = null;
        m._axes = activeAxes.filter(function(k){return m._n[k] !== undefined;}).length;
        return;
      }
      var sum = 0, wsum = 0;
      activeAxes.forEach(function(k){
        var wt = W[k] || 0;
        sum += m._n[k] * wt;
        wsum += wt;
      });
      m._combo = wsum ? (sum / wsum) * 100 : null;
      m._axes = activeAxes.length;
    });
  }

  function currentList() {
    var ms = DATA.models.slice();
    if (tab === "open") ms = ms.filter(function (m) { return m.open; });
    if (query) {
      var q = query.toLowerCase();
      ms = ms.filter(function (m) {
        return (m.name + " " + m.org + " " + (m.orgCn || "")).toLowerCase().indexOf(q) >= 0;
      });
    }
    var key = (tab === "combo" || tab === "open") ? "_combo" : tab;
    ms = ms.filter(function (m) { return isNum(key === "_combo" ? m._combo : m[key]); });
    ms.sort(function (a, b) {
      var va = key === "_combo" ? a._combo : a[key], vb = key === "_combo" ? b._combo : b[key];
      return vb - va;
    });
    return ms;
  }

  function mainScore(m) {
    if (tab === "arena") return { v: Math.round(m.arena), lab: "Arena Elo" };
    if (tab === "livebench") return { v: m.livebench.toFixed(1), lab: "LiveBench 均分" };
    if (tab === "aa") return { v: m.aa.toFixed(1), lab: "AA 智能指数" };
    var cov = isNum(m.confidence) ? " · " + Math.round(m.confidence) + "%覆盖" : "";
    return { v: m._combo.toFixed(1), lab: "共识 · " + m._axes + "源" + cov };
  }

  function render() {
    var list = $("list"), ms = currentList();
    if (!ms.length) { list.innerHTML = "<div class='empty'>没有匹配的模型</div>"; return; }
    var html = ms.map(function (m, i) {
      var col = ORG[m.org] || "#8aa6ff";
      var ini = esc(m.org.replace(/ .*/, "").slice(0, 2));
      var slug = ORG_LOGO[m.org];
      var logo = slug
        ? "<img src='logos/" + slug + ".png' alt='' loading='lazy' " +
          "onerror=\"this.style.display='none';this.nextElementSibling.style.display='block'\">" +
          "<span class='ini' style='display:none'>" + ini + "</span>"
        : "<span class='ini'>" + ini + "</span>";
      var bars = AXES.map(function (a) {
        var has = isNum(m[a.key]) && m._n[a.key] !== undefined;
        var w = has ? Math.max(4, m._n[a.key] * 100) : 0;
        return "<div class='bar" + (has ? "" : " na") + "'><span>" + a.short + "</span>" +
          "<span class='tk'><i style='width:" + w.toFixed(1) + "%;background:" + a.color + "'></i></span>" +
          "<span class='v'>" + (has ? AXES.filter(function (x) { return x.key === a.key; })[0].fmt(m[a.key]) : "—") + "</span></div>";
      }).join("");
      var sc = mainScore(m);
      return "<div class='rowcard' style='animation-delay:" + Math.min(i * 22, 400) + "ms'>" +
        "<div class='rk" + (i < 3 ? " top" : "") + "'>" + (i + 1) + "</div>" +
        "<div class='logo' style='color:" + col + "'>" + logo + "</div>" +
        "<div class='info'><div class='nm'>" + esc(m.name) +
          " <span class='tag " + (m.open ? "open'>开源" : "closed'>闭源") + "</span></div>" +
          "<div class='meta'>" + (m.flag || "") + " " + esc(m.orgCn || m.org) +
          (m.ctx ? " · 上下文 " + esc(m.ctx) : "") + "</div></div>" +
        "<div class='bars'>" + bars + "</div>" +
        "<div class='score'><div class='big'>" + sc.v + "</div><div class='lab'>" + sc.lab + "</div></div>" +
        "</div>";
    }).join("");
    list.innerHTML = html;
  }

  function renderTabs() {
    var visibleTabs = TABS.filter(function(t){
      if (t.key === "aa") return !DATA.axisStatus || DATA.axisStatus.aa !== false;
      return true;
    });
    if (!visibleTabs.some(function(t){return t.key===tab;})) tab="combo";
    $("tabs").innerHTML = visibleTabs.map(function (t) {
      return "<span class='chip" + (t.key === tab ? " on" : "") + "' data-k='" + t.key + "'>" + t.label + "</span>";
    }).join("");
    Array.prototype.forEach.call($("tabs").children, function (el) {
      el.onclick = function () { tab = el.getAttribute("data-k"); renderTabs(); render(); };
    });
  }

  function renderMeta() {
    var d = DATA;
    var st = $("status"), stTxt = $("statusTxt");
    var t = Date.parse(d.updatedAt);
    var hours = isNaN(t) ? null : Math.max(0, Math.round((Date.now() - t) / 3600000));
    var ago = hours === null ? (d.asOf || "") : (hours < 1 ? "1 小时内" : hours + " 小时前");
    var active = ["arena","livebench","aa"].filter(function(k){
      return !d.axisStatus || d.axisStatus[k] !== false;
    });
    var sourceNames = {arena:"LMArena",livebench:"LiveBench",aa:"Artificial Analysis"};

    if (d.seed) {
      st.className = "status demo";
      stTxt.textContent = "快照数据 · 等待自动更新";
    } else {
      st.className = "status live";
      stTxt.textContent = "自动更新 · " + (ago || d.asOf || "");
    }

    var byCombo = d.models.slice().filter(function (m) { return isNum(m._combo); })
      .sort(function (a, b) { return b._combo - a._combo; });
    var openTop = byCombo.filter(function (m) { return m.open; })[0];
    var cn = d.models.filter(function (m) { return m.flag === "🇨🇳"; }).length;
    var h = "<span>覆盖 <b>" + d.models.length + "</b> 个模型</span>";
    if (byCombo[0]) h += "<span>共识第一 <b>" + esc(byCombo[0].name) + "</b></span>";
    if (openTop) h += "<span>开源第一 <b>" + esc(openTop.name) + "</b></span>";
    h += "<span>中国模型 <b>" + cn + "</b> 个</span>";
    h += "<span>当前综合 <b>" + active.length + " 源</b></span>";
    $("summary").innerHTML = h;

    var titleSub=document.querySelector(".title p");
    if(titleSub){
      titleSub.textContent = active.map(function(k){return sourceNames[k];}).join(" · ") +
        " —— 排名百分位多源共识，自动更新";
    }

    var cards = [];
    ["arena", "livebench", "aa"].forEach(function (k) {
      var src = d.sources && d.sources[k];
      if (src) {
        var meta=(d.sourceMeta&&d.sourceMeta[k])||{};
        cards.push({
          name: src.name,
          url: src.url,
          desc: src.desc +
            (meta.ok===false ? " · 当前未参与共识" : "") +
            (k==="aa" && meta.mode==="verified_snapshot_fallback" ? " · 核验快照 " + (meta.snapshotDate||"") : "")
        });
      }
    });
    (d.extraSources || []).forEach(function (src) { cards.push(src); });
    $("srcgrid").innerHTML = cards.map(function (src) {
      return "<a class='srccard' href='" + esc(src.url) + "' target='_blank' rel='noopener'><b>" +
        esc(src.name) + " ↗</b><span>" + esc(src.desc || "") + "</span></a>";
    }).join("");

    var foot=$("foot");
    if(foot){
      var inactive=["arena","livebench","aa"].filter(function(k){return d.axisStatus&&d.axisStatus[k]===false;});
      foot.innerHTML =
        "Ooglex 多源共识：先把各来源转换为榜内排名百分位，再合成共识分，避免 Elo、百分制与 Intelligence Index 直接混加。<br>" +
        "当前权重：Artificial Analysis 50% · LiveBench 30% · LMArena 20%。至少两个独立来源才进入主榜；缺源不会重新放大剩余权重，而会向中性分收缩。<br>" +
        "LMArena 代表大规模真人偏好；LiveBench 代表客观任务能力；Artificial Analysis 覆盖代理、编程、通用与科学推理。该榜是 Ooglex 多源综合参考，不等同于任何单一机构的“官方全球排名”。";
    }
  }

  $("q").addEventListener("input", function () { query = this.value.trim(); render(); });

  fetch("data.json?t=" + Date.now())
    .then(function (r) { return r.json(); })
    .then(function (d) {
      DATA = d;
      prepare(d.models);
      renderMeta();
      renderTabs();
      render();
    })
    .catch(function () {
      $("list").innerHTML = "<div class='empty'>数据加载失败，请稍后刷新重试</div>";
      $("statusTxt").textContent = "加载失败";
    });
})();
