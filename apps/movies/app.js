/* 全球电影榜 · 前端
 * 读取 data.json（由 scripts/movies/build_movies.py 每日生成）：海报墙渲染 高分 Top 250 / 最新上映 / 公版经典，
 * 含排名、评分、海报（缺图自动降级为标题占位）。点击海报弹窗播放：公版片内嵌 Internet Archive 正片，
 * 其余内嵌 YouTube 官方预告片，并列出正版观看渠道（TMDB × JustWatch）；附 Web Audio 背景音乐。纯原生 JS。 */
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
  var REGION_NAMES = { CN: "中国大陆", HK: "香港", TW: "台湾", US: "美国", SG: "新加坡", GB: "英国", JP: "日本" };
  /* 只放行形如 YouTube key / Archive 标识的字符串，杜绝注入到 iframe src */
  function ytKey(k) { k = String(k || ""); return /^[\w-]{5,24}$/.test(k) ? k : null; }
  function iaId(v) { v = String(v || ""); return /^[A-Za-z0-9._-]+$/.test(v) ? v : null; }

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
    grid.innerHTML = l.items.map(function (it, i) {
      var inner = "<span class='rk'>#" + it.rank + "</span>";
      if (it.poster) {
        inner += "<img loading='lazy' referrerpolicy='no-referrer' src='" + attr(it.poster) +
          "' onerror=\"this.style.display='none';this.parentNode.querySelector('.ph').style.display='flex'\">" +
          "<div class='ph' style='display:none'>" + esc(it.title) + "</div>";
      } else {
        inner += "<div class='ph'>" + esc(it.title) + "</div>";
      }
      if (isNum(it.rating)) inner += "<span class='rate'>★ " + it.rating.toFixed(1) + "</span>";
      if (it.video) inner += "<span class='freebadge'>正片</span>";
      inner += "<span class='playbtn'>▶</span>";
      var sub = (it.year || "") + (votes(it.votes) ? " · " + votes(it.votes) + "票" : "");
      return "<a class='movie' data-i='" + i + "' href='" + attr(it.link || "#") + "' target='_blank' rel='noopener'>" +
        "<div class='poster'>" + inner + "</div>" +
        "<div class='minfo'><div class='t'>" + esc(it.title) + "</div><div class='y'>" + sub + "</div></div></a>";
    }).join("");
    grid.onclick = function (ev) {
      var a = ev.target && ev.target.closest ? ev.target.closest(".movie") : null;
      if (!a || ev.ctrlKey || ev.metaKey || ev.shiftKey) return;   // 修饰键点击保留原生新标签行为
      var cur = listOf(KEY);
      var it = cur && cur.items && cur.items[+a.getAttribute("data-i")];
      if (!it) return;
      ev.preventDefault();
      openModal(it);
    };
  }

  /* —— 播放弹窗：公版正片（Internet Archive）/ 官方预告片（YouTube）+ 正版观看渠道 —— */
  function openModal(it) {
    if (voice) stopMusic();
    var v = iaId(it.video), t = ytKey(it.trailer);
    var player;
    if (v) {
      player = "<iframe src='https://archive.org/embed/" + v + "?autoplay=1' allow='autoplay; fullscreen; encrypted-media' allowfullscreen loading='lazy'></iframe>";
    } else if (t) {
      player = "<iframe src='https://www.youtube-nocookie.com/embed/" + t + "?autoplay=1&rel=0' allow='autoplay; fullscreen; encrypted-media; picture-in-picture' allowfullscreen loading='lazy'></iframe>";
    } else {
      player = "<div class='noplay'>暂无可内嵌播放的预告片<span>数据每日更新，也可用下方链接搜索观看</span></div>";
    }
    $("mplayer").innerHTML = player;
    $("mtitle").textContent = (it.title || "") + (it.year ? "（" + it.year + "）" : "");
    $("msub").innerHTML = (it.orig && it.orig !== it.title ? esc(it.orig) + " · " : "") +
      (isNum(it.rating) ? "<b>★ " + it.rating.toFixed(1) + "</b>" : "") +
      (v ? " <span class='pd'>公有领域 · 免费正片</span>" : (t ? " 官方预告片" : ""));
    var links = [];
    if (v) links.push(["📼 在 Internet Archive 打开", "https://archive.org/details/" + v]);
    if (t) links.push(["▶ 在 YouTube 打开", "https://www.youtube.com/watch?v=" + t]);
    if (!v && !t) links.push(["🔍 YouTube 搜预告片",
      "https://www.youtube.com/results?search_query=" + encodeURIComponent(((it.orig || it.title || "") + " " + (it.year || "") + " trailer").trim())]);
    if (it.id) links.push(["TMDB 详情 ↗", "https://www.themoviedb.org/movie/" + it.id]);
    $("mlinks").innerHTML = links.map(function (p) {
      return "<a href='" + attr(p[1]) + "' target='_blank' rel='noopener'>" + p[0] + "</a>";
    }).join("");
    var w = it.watch || [], wb;
    if (v) {
      wb = "<div class='wnote'>该片已进入公有领域，正片由 Internet Archive 公益托管，可放心观看。</div>";
    } else if (w.length) {
      wb = "<div class='wtitle'>正版观看渠道</div>" + w.map(function (g) {
        return "<div class='wrow'><span class='wr'>" + esc(REGION_NAMES[g.region] || g.region) + "</span>" +
          (g.names || []).map(function (n) {
            return "<a class='wp' href='" + attr(g.link || "#") + "' target='_blank' rel='noopener'>" + esc(n) + "</a>";
          }).join("") + "</div>";
      }).join("") + "<div class='wnote'>渠道数据来自 TMDB × JustWatch，以各平台实际上架为准。</div>";
    } else {
      wb = "<div class='wnote'>暂无该片的流媒体上架数据，可到 TMDB 详情页查看更多信息。</div>";
    }
    $("mwatch").innerHTML = wb;
    $("mask").classList.add("show");
    document.body.style.overflow = "hidden";
  }
  function closeModal() {
    $("mask").classList.remove("show");
    $("mplayer").innerHTML = "";   // 清空 iframe，停止播放
    document.body.style.overflow = "";
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
    $("mclose").onclick = closeModal;
    $("mask").onclick = function (ev) { if (ev.target === $("mask")) closeModal(); };
    document.addEventListener("keydown", function (ev) {
      if (ev.key === "Escape" && $("mask").classList.contains("show")) closeModal();
    });
  }

  fetch("data.json?t=" + Date.now())
    .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(boot)
    .catch(function (e) { $("grid").innerHTML = "<div class='empty'>数据加载失败：" + esc(e.message) + "</div>"; });
})();
