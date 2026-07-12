/* 全球电影榜 · 前端
 * 读取 data.json（由 scripts/movies/build_movies.py 每日生成）：海报墙渲染 高分 Top 250 / 最新上映，
 * 含排名、评分、海报（缺图自动降级为标题占位），点击跳 TMDB；附 Web Audio 背景音乐。纯原生 JS。 */
(function () {
  "use strict";
  var DATA = null, KEY = null;
  var $ = function (id) { return document.getElementById(id); };
  function isNum(v) { return v !== null && v !== undefined && !isNaN(v); }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function attr(s) { return String(s == null ? "" : s).replace(/"/g, "%22").replace(/'/g, "%27"); }
  function votes(v) {
    if (!isNum(v)) return "";
    if (v >= 10000) { var w = v / 10000; return (w >= 100 ? w.toFixed(0) : w.toFixed(1)) + "万"; }
    return v + "";
  }
  function listOf(k) { return (DATA.lists || []).filter(function (l) { return l.key === k; })[0]; }

  function renderTabs() {
    var box = $("tabs"); box.innerHTML = "";
    (DATA.lists || []).forEach(function (l) {
      var b = document.createElement("button");
      b.textContent = l.name + (l.items ? " · " + l.items.length : "");
      if (l.key === KEY) b.className = "on";
      b.onclick = function () { KEY = l.key; renderTabs(); renderGrid(); };
      box.appendChild(b);
    });
  }

  function renderGrid() {
    var l = listOf(KEY), grid = $("grid");
    if (!l || !l.items || !l.items.length) {
      grid.innerHTML = "<div class='empty'>该榜单暂无数据，实时任务上线后展示 🙂</div>"; return;
    }
    grid.innerHTML = l.items.map(function (it) {
      var inner = "<span class='rk'>#" + it.rank + "</span>";
      if (it.poster) {
        inner += "<img loading='lazy' referrerpolicy='no-referrer' src='" + attr(it.poster) +
          "' onerror=\"this.style.display='none';this.parentNode.querySelector('.ph').style.display='flex'\">" +
          "<div class='ph' style='display:none'>" + esc(it.title) + "</div>";
      } else {
        inner += "<div class='ph'>" + esc(it.title) + "</div>";
      }
      if (isNum(it.rating)) inner += "<span class='rate'>★ " + it.rating.toFixed(1) + "</span>";
      var sub = (it.year || "") + (votes(it.votes) ? " · " + votes(it.votes) + "票" : "");
      return "<a class='movie' href='" + attr(it.link || "#") + "' target='_blank' rel='noopener'>" +
        "<div class='poster'>" + inner + "</div>" +
        "<div class='minfo'><div class='t'>" + esc(it.title) + "</div><div class='y'>" + sub + "</div></div></a>";
    }).join("");
  }

  function renderMeta() {
    var live = !/示例/.test(DATA.source || "");
    $("status").className = "status " + (live ? "live" : "demo");
    $("status").innerHTML = "<span class='sdot'></span>" + (live ? "实时 · 每日自动更新" : "示例数据 · 待刷新");
    $("avg").innerHTML = isNum(DATA.avgRating) ? "平均评分 <b>★ " + DATA.avgRating + "</b>" : "";
    $("foot").innerHTML = "数据来源 <b style='color:#f5c518'>" + esc(DATA.source || "TMDB") + "</b> · 更新于 " +
      (DATA.updatedAt || "").replace("T", " ").replace("Z", " UTC") + "<br>" + esc(DATA.note || "");
  }

  /* —— Web Audio 背景音乐（影院氛围 pad，点击开启）—— */
  var actx = null, voice = null, chordTimer = null;
  var CHORDS = [[130.81, 196, 261.63, 329.63], [110, 164.81, 261.63, 329.63], [146.83, 220, 293.66, 349.23], [98, 146.83, 246.94, 329.63]];
  function startMusic() {
    actx = actx || new (window.AudioContext || window.webkitAudioContext)();
    if (actx.state === "suspended") actx.resume();
    var master = actx.createGain(); master.gain.value = 0; master.connect(actx.destination);
    master.gain.linearRampToValueAtTime(0.07, actx.currentTime + 3);
    var filter = actx.createBiquadFilter(); filter.type = "lowpass"; filter.frequency.value = 700; filter.connect(master);
    var flfo = actx.createOscillator(); flfo.frequency.value = 0.03; var fg = actx.createGain(); fg.gain.value = 300;
    flfo.connect(fg); fg.connect(filter.frequency); flfo.start();
    var oscs = CHORDS[0].map(function (f, i) {
      var o = actx.createOscillator(); o.type = i % 2 ? "sine" : "triangle"; o.frequency.value = f;
      var g = actx.createGain(); g.gain.value = 0.2 / (i + 1); o.connect(g); g.connect(filter); o.start();
      var lfo = actx.createOscillator(); lfo.frequency.value = 0.05 + i * 0.012; var lg = actx.createGain(); lg.gain.value = 2;
      lfo.connect(lg); lg.connect(o.detune); lfo.start();
      return o;
    });
    voice = { master: master, oscs: oscs, extra: [flfo] };
    var ci = 0;
    chordTimer = setInterval(function () {
      ci = (ci + 1) % CHORDS.length;
      oscs.forEach(function (o, i) { o.frequency.linearRampToValueAtTime(CHORDS[ci][i], actx.currentTime + 5); });
    }, 12000);
    $("music").classList.add("on");
  }
  function stopMusic() {
    if (chordTimer) { clearInterval(chordTimer); chordTimer = null; }
    if (voice && actx) {
      voice.master.gain.cancelScheduledValues(actx.currentTime);
      voice.master.gain.linearRampToValueAtTime(0, actx.currentTime + 1.2);
      var v = voice; voice = null;
      setTimeout(function () { try { v.oscs.concat(v.extra).forEach(function (o) { o.stop(); }); } catch (e) {} }, 1500);
    }
    $("music").classList.remove("on");
  }

  function boot(data) {
    DATA = data;
    KEY = data.defaultKey || (data.lists && data.lists[0] && data.lists[0].key);
    renderTabs(); renderGrid(); renderMeta();
    $("music").onclick = function () { if (voice) stopMusic(); else { try { startMusic(); } catch (e) { console.log("music fail", e); } } };
  }

  fetch("data.json?t=" + Date.now())
    .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(boot)
    .catch(function (e) { $("grid").innerHTML = "<div class='empty'>数据加载失败：" + esc(e.message) + "</div>"; });
})();
