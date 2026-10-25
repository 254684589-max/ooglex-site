/* 流光播放器：唱片主画面、专辑列表、播控。不自动播放。 */
(function () {
  "use strict";

  var audio;
  var seek;
  var volume;
  var view;
  var live;
  var queuePop;
  var state = {
    catalog: null,
    loadError: "",
    draftMode: false,
    draftSavedAt: "",
    viewAlbumId: "",
    playingAlbumId: "",
    index: -1,
    seeking: false,
    objectUrl: "",
    volume: 0.9,
    muted: false,
    lastVolume: 0.9,
    repeat: "off",
    shuffle: false,
    history: [],
    notice: ""
  };

  function $(id) { return document.getElementById(id); }

  function h(tag, cls, text) {
    var node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text != null) node.textContent = text;
    return node;
  }

  function icon(name) {
    var ns = "http://www.w3.org/2000/svg";
    var svg = document.createElementNS(ns, "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("aria-hidden", "true");
    svg.classList.add("ico");
    function path(d) {
      var p = document.createElementNS(ns, "path");
      p.setAttribute("fill", "currentColor");
      p.setAttribute("d", d);
      svg.appendChild(p);
    }
    function stroke(d) {
      var p = document.createElementNS(ns, "path");
      p.setAttribute("fill", "none");
      p.setAttribute("stroke", "currentColor");
      p.setAttribute("stroke-width", "1.8");
      p.setAttribute("stroke-linecap", "round");
      p.setAttribute("stroke-linejoin", "round");
      p.setAttribute("d", d);
      svg.appendChild(p);
    }
    if (name === "play") path("M8 5v14l11-7z");
    else if (name === "pause") { path("M6 5h4v14H6z"); path("M14 5h4v14h-4z"); }
    else if (name === "prev") path("M6 6h2v12H6zm3.5 6 8.5 6V6z");
    else if (name === "next") path("M6 6v12l8.5-6zM16 6h2v12h-2z");
    else if (name === "vol") path("M4 9v6h4l5 4V5L8 9H4zm11.5 3a3.5 3.5 0 0 0-2-3.16v6.32A3.5 3.5 0 0 0 15.5 12z");
    else if (name === "mute") path("M4 9v6h4l5 4V5L8 9H4zm13.2.8-1.4-1.4L13.6 10.6 11.4 8.4 10 9.8l2.2 2.2-2.2 2.2 1.4 1.4 2.2-2.2 2.2 2.2 1.4-1.4-2.2-2.2z");
    else if (name === "queue") path("M4 6h16v2H4zm0 5h16v2H4zm0 5h10v2H4z");
    else if (name === "repeat" || name === "repeat-one") {
      stroke("M17 2l4 4-4 4");
      stroke("M3 11V9a4 4 0 0 1 4-4h14");
      stroke("M7 22l-4-4 4-4");
      stroke("M21 13v2a4 4 0 0 1-4 4H3");
      if (name === "repeat-one") {
        var t = document.createElementNS(ns, "text");
        t.setAttribute("x", "12");
        t.setAttribute("y", "16");
        t.setAttribute("text-anchor", "middle");
        t.setAttribute("font-size", "8");
        t.setAttribute("font-weight", "700");
        t.setAttribute("fill", "currentColor");
        t.textContent = "1";
        svg.appendChild(t);
      }
    }
    else if (name === "shuffle") {
      stroke("M16 3h5v5");
      stroke("M4 20 21 3");
      stroke("M21 16v5h-5");
      stroke("M15 15l6 6");
      stroke("M4 4l5 5");
    }
    else path("M4 9v6h4l5 4V5L8 9H4z");
    return svg;
  }

  function fmt(sec) {
    if (!isFinite(sec) || sec < 0) return "0:00";
    sec = Math.floor(sec);
    var m = Math.floor(sec / 60);
    var s = sec % 60;
    return m + ":" + (s < 10 ? "0" : "") + s;
  }

  function visibleAlbums() {
    var albums = (state.catalog && state.catalog.albums) || [];
    return albums.filter(function (album) {
      if (!album || !Array.isArray(album.tracks)) return false;
      if (!state.draftMode && album.released === false) return false;
      return state.draftMode || album.tracks.length > 0;
    });
  }

  function findAlbum(id) {
    var albums = (state.catalog && state.catalog.albums) || [];
    for (var i = 0; i < albums.length; i++) if (albums[i].id === id) return albums[i];
    return null;
  }

  function currentAlbum() {
    return findAlbum(state.playingAlbumId);
  }

  function currentTrack() {
    var album = currentAlbum();
    if (!album || state.index < 0) return null;
    return album.tracks[state.index] || null;
  }

  function artistOf(track, album) {
    return (track && track.artist) || (album && album.artist) || "未知艺人";
  }

  function setNotice(text) {
    state.notice = text || "";
    var node = $("notice");
    if (!node) return;
    node.textContent = state.notice;
    node.hidden = !state.notice;
  }

  function announce(text) {
    if (live) live.textContent = text;
  }

  function parseRoute() {
    var hash = "";
    try { hash = decodeURIComponent(location.hash || ""); }
    catch (err) { hash = location.hash || ""; }
    var match = /^#\/album\/([a-z0-9][a-z0-9-]{0,48})$/.exec(hash);
    if (match) return { name: "album", id: match[1] };
    return { name: "list" };
  }

  function coverNode(album, cls) {
    var wrap = h("div", cls || "cover");
    if (album && album.cover && album.cover.indexOf("idb:") !== 0) {
      var img = h("img");
      img.alt = "";
      img.src = album.cover;
      img.addEventListener("error", function () {
        img.remove();
        wrap.appendChild(h("span", "ph", (album.title || "乐").slice(0, 1)));
      });
      wrap.appendChild(img);
      return wrap;
    }
    if (album && album.cover && album.cover.indexOf("idb:") === 0 && window.OoglexMusicStore) {
      var img2 = h("img");
      img2.alt = "";
      wrap.appendChild(img2);
      window.OoglexMusicStore.getBlob(album.cover.slice(4)).then(function (blob) {
        if (!blob) throw new Error("missing");
        img2.src = URL.createObjectURL(blob);
      }).catch(function () {
        img2.remove();
        wrap.appendChild(h("span", "ph", (album.title || "乐").slice(0, 1)));
      });
      return wrap;
    }
    wrap.appendChild(h("span", "ph", album && album.title ? album.title.slice(0, 1) : "乐"));
    return wrap;
  }

  function renderList() {
    view.appendChild(h("h2", "section-title", "专辑"));
    if (!visibleAlbums().length) {
      view.appendChild(h("p", "empty", "还没有可播放的专辑。"));
      return;
    }
    var grid = h("div", "albums");
    visibleAlbums().forEach(function (album) {
      var card = h("a", "album-card");
      card.href = "#/album/" + album.id;
      card.appendChild(coverNode(album, "cover"));
      var meta = h("div", "meta");
      meta.appendChild(h("h3", "name", album.title || "未命名专辑"));
      meta.appendChild(h("p", "by", artistOf(null, album)));
      var bits = [];
      bits.push((album.tracks || []).length + " 首");
      if (album.demo) bits.push("演示样例");
      if (album.released === false) bits.push("未发行");
      meta.appendChild(h("p", "bits", bits.join(" · ")));
      card.appendChild(meta);
      grid.appendChild(card);
    });
    view.appendChild(grid);
  }

  function renderAlbum(id) {
    var album = findAlbum(id);
    var back = h("a", "text-link", "← 全部专辑");
    back.href = "#/";
    view.appendChild(back);
    if (!album || (!state.draftMode && album.released === false)) {
      view.appendChild(h("p", "empty", "没有这张专辑。"));
      return;
    }
    var layout = h("div", "detail");
    layout.appendChild(coverNode(album, "cover lg"));
    var side = h("div", "detail-main");
    side.appendChild(h("p", "kicker", album.demo ? "演示样例" : "专辑"));
    side.appendChild(h("h2", "album-title", album.title || "未命名专辑"));
    side.appendChild(h("p", "by", artistOf(null, album) + (album.releasedAt ? " · " + album.releasedAt : "")));
    layout.appendChild(side);
    if (album.released === false) layout.appendChild(h("p", "badge", "未发行 · 只有本机预览看得到"));
    if (album.note || album.license) {
      var det = h("details", "fine");
      det.appendChild(h("summary", null, "署名与许可"));
      if (album.note) det.appendChild(h("p", null, album.note));
      if (album.license) {
        var lic = h("p");
        lic.appendChild(document.createTextNode(album.license));
        if (album.licenseUrl) {
          lic.appendChild(document.createTextNode(" · "));
          var a = h("a", null, "许可文本");
          a.href = album.licenseUrl;
          a.target = "_blank";
          a.rel = "noopener noreferrer";
          lic.appendChild(a);
        }
        det.appendChild(lic);
      }
      layout.appendChild(det);
    }
    var list = h("ol", "tracks");
    (album.tracks || []).forEach(function (track, index) {
      var li = h("li");
      var btn = h("button", "track");
      btn.type = "button";
      btn.dataset.album = album.id;
      btn.dataset.id = track.id;
      btn.dataset.index = String(index);
      var idx = h("span", "idx", String(index + 1));
      var titles = h("span", "titles");
      titles.appendChild(h("span", "t-title", track.title || "未命名"));
      titles.appendChild(h("span", "t-artist", artistOf(track, album)));
      var flag = h("span", "flag", "");
      var time = h("span", "t-time", track.durationSec ? fmt(track.durationSec) : "");
      btn.appendChild(idx);
      btn.appendChild(titles);
      btn.appendChild(flag);
      btn.appendChild(time);
      btn.addEventListener("click", function () { onTrackClick(album, index); });
      li.appendChild(btn);
      list.appendChild(li);
    });
    if (!(album.tracks || []).length) layout.appendChild(h("p", "empty", "这张专辑还没有曲目。"));
    layout.appendChild(list);
    view.appendChild(layout);
  }

  var skipAlbumScroll = true;

  function reduceMotion() {
    try { return window.matchMedia("(prefers-reduced-motion: reduce)").matches; }
    catch (err) { return false; }
  }

  function renderView() {
    if (!view) return;
    var route = parseRoute();
    state.viewAlbumId = route.name === "album" ? route.id : "";
    view.textContent = "";
    if (state.loadError) {
      view.appendChild(h("p", "empty", state.loadError));
      var retry = h("button", "text-btn", "重试");
      retry.type = "button";
      retry.addEventListener("click", load);
      view.appendChild(retry);
      return;
    }
    if (!state.catalog) {
      view.appendChild(h("p", "empty", "正在读取专辑…"));
      return;
    }
    if (state.draftMode) {
      var draft = h("p", "draft-banner", state.draftSavedAt
        ? "本机草稿预览。这些改动还没写进仓库，别人打开网站看不到。保存于 " + state.draftSavedAt.replace("T", " ").slice(0, 19) + " UTC。"
        : "本机草稿预览。没有找到草稿，下面仍是已发布清单。");
      view.appendChild(draft);
    }
    if (route.name === "album") renderAlbum(route.id);
    else renderList();
    paintCurrent();
    if (!skipAlbumScroll && route.name === "album") {
      requestAnimationFrame(function () {
        view.scrollIntoView({ block: "start", behavior: reduceMotion() ? "auto" : "smooth" });
      });
    }
    skipAlbumScroll = false;
  }

  function paintSeek() {
    if (!seek) return;
    var duration = audio && isFinite(audio.duration) ? audio.duration : 0;
    var time = state.seeking ? Number(seek.value) : (audio ? audio.currentTime : 0);
    if (!state.seeking) {
      seek.max = String(duration || 0);
      seek.value = String(duration ? time : 0);
      seek.disabled = !duration;
    }
    var shown = duration || currentDurationHint();
    var pct = shown ? Math.max(0, Math.min(100, (time / shown) * 100)) : 0;
    seek.style.setProperty("--p", pct + "%");
    seek.setAttribute("aria-valuemin", "0");
    seek.setAttribute("aria-valuemax", String(Math.round(shown || 0)));
    seek.setAttribute("aria-valuenow", String(Math.round(time || 0)));
    seek.setAttribute("aria-valuetext", fmt(time) + " / " + fmt(shown));
    var now = $("time-now");
    var end = $("time-end");
    var remain = Math.max(0, shown - time);
    if (now) now.textContent = fmt(time);
    if (end) end.textContent = shown ? ("-" + fmt(remain)) : "0:00";
  }

  function currentDurationHint() {
    var track = currentTrack();
    return track && track.durationSec ? track.durationSec : 0;
  }

  function paintTransport() {
    var track = currentTrack();
    var album = currentAlbum();
    var title = $("now-title");
    var by = $("now-artist");
    var play = $("play");
    if (title) title.textContent = track ? track.title : "尚未选择曲目";
    if (by) by.textContent = track ? artistOf(track, album) : "从专辑里点一首";
    var art = $("now-art");
    var artKey = (album && album.cover) || (album && album.id) || "";
    if (art && art.dataset.art !== artKey) {
      art.dataset.art = artKey;
      var spinning = art.classList.contains("is-spinning");
      art.textContent = "";
      art.appendChild(coverNode(album || { title: "流" }, "cover sm"));
      if (spinning) art.classList.add("is-spinning");
    }
    var playing = !!(audio && !audio.paused && audio.src);
    if (art) art.classList.toggle("is-spinning", playing);
    if (play) {
      play.textContent = "";
      play.appendChild(icon(playing ? "pause" : "play"));
      play.setAttribute("aria-label", playing ? "暂停" : "播放");
      play.setAttribute("aria-pressed", playing ? "true" : "false");
    }
    var repeatBtn = $("repeat");
    if (repeatBtn) {
      repeatBtn.textContent = "";
      repeatBtn.appendChild(icon(state.repeat === "one" ? "repeat-one" : "repeat"));
      repeatBtn.classList.toggle("is-on", state.repeat !== "off");
      repeatBtn.setAttribute("aria-pressed", state.repeat === "off" ? "false" : "true");
      repeatBtn.setAttribute("aria-label", state.repeat === "one" ? "单曲循环" : state.repeat === "all" ? "列表循环" : "循环：关");
    }
    var shuffleBtn = $("shuffle");
    if (shuffleBtn) {
      shuffleBtn.textContent = "";
      shuffleBtn.appendChild(icon("shuffle"));
      shuffleBtn.classList.toggle("is-on", state.shuffle);
      shuffleBtn.setAttribute("aria-pressed", state.shuffle ? "true" : "false");
      shuffleBtn.setAttribute("aria-label", state.shuffle ? "随机播放：开" : "随机播放：关");
    }
    var mute = $("mute");
    if (mute) {
      mute.textContent = "";
      mute.appendChild(icon(state.muted || state.volume === 0 ? "mute" : "vol"));
      mute.setAttribute("aria-label", state.muted || state.volume === 0 ? "取消静音" : "静音");
      mute.setAttribute("aria-pressed", state.muted ? "true" : "false");
    }
    paintSeek();
    renderQueue();
    if (track) document.title = track.title + " · 流光播放器";
    else document.title = "流光播放器 · Ooglex";
  }

  function paintCurrent() {
    var track = currentTrack();
    document.querySelectorAll(".track").forEach(function (node) {
      var on = !!(track && node.dataset.album === state.playingAlbumId && node.dataset.id === track.id);
      node.classList.toggle("is-current", on);
      var flag = node.querySelector(".flag");
      if (flag) flag.textContent = on ? (audio && !audio.paused ? "正在播放" : "已暂停") : "";
      if (on) node.setAttribute("aria-current", "true");
      else node.removeAttribute("aria-current");
    });
    paintTransport();
  }

  function renderQueue() {
    if (!queuePop) return;
    queuePop.textContent = "";
    var album = findAlbum(state.playingAlbumId) || findAlbum(state.viewAlbumId) || visibleAlbums()[0];
    if (!album || !(album.tracks || []).length) {
      queuePop.appendChild(h("p", "empty", "还没有歌单。先打开一张专辑。"));
      return;
    }
    queuePop.appendChild(h("p", "queue-title", album.title || "歌单"));
    var list = h("ol", "queue-list");
    album.tracks.forEach(function (track, index) {
      var btn = h("button", "queue-item", (index + 1) + ". " + (track.title || "未命名"));
      btn.type = "button";
      if (album.id === state.playingAlbumId && index === state.index) btn.classList.add("is-current");
      btn.addEventListener("click", function () { onTrackClick(album, index); });
      var li = h("li");
      li.appendChild(btn);
      list.appendChild(li);
    });
    queuePop.appendChild(list);
  }

  async function resolveSrc(src) {
    if (String(src || "").indexOf("idb:") === 0) {
      if (!window.OoglexMusicStore) throw new Error("store");
      var blob = await window.OoglexMusicStore.getBlob(src.slice(4));
      if (!blob) throw new Error("missing");
      return URL.createObjectURL(blob);
    }
    if (!src) throw new Error("empty");
    return src;
  }

  function randomIndex(n, avoid) {
    if (n <= 1) return 0;
    if (avoid < 0 || avoid >= n) return Math.floor(Math.random() * n);
    var j = Math.floor(Math.random() * (n - 1));
    return j >= avoid ? j + 1 : j;
  }

  function remember(key, value) {
    try { localStorage.setItem(key, value); } catch (err) { /* 忽略 */ }
  }

  async function playIndex(album, index) {
    if (!album || !album.tracks || !album.tracks.length) return;
    if (state.playingAlbumId !== album.id) state.history = [];
    var n = album.tracks.length;
    var i = ((index % n) + n) % n;
    var track = album.tracks[i];
    state.playingAlbumId = album.id;
    state.index = i;
    setNotice("");
    var url;
    try {
      url = await resolveSrc(track.src);
    } catch (err) {
      setNotice("这首还播不了。若是本机上传的曲目，请用「本机预览」打开，或先发行到仓库。");
      paintCurrent();
      return;
    }
    if (state.objectUrl) URL.revokeObjectURL(state.objectUrl);
    state.objectUrl = url.indexOf("blob:") === 0 ? url : "";
    audio.src = url;
    audio.volume = state.muted ? 0 : state.volume;
    try {
      await audio.play();
      announce("正在播放 " + track.title + "，" + artistOf(track, album));
    } catch (err) {
      setNotice("浏览器还没允许播放。请再点一次播放。");
    }
    paintCurrent();
    setMediaSession(track, album);
  }

  function setMediaSession(track, album) {
    try {
      if (!("mediaSession" in navigator)) return;
      var art = [];
      if (album.cover && album.cover.indexOf("idb:") !== 0) {
        art.push({ src: new URL(album.cover, location.href).href });
      }
      navigator.mediaSession.metadata = new MediaMetadata({
        title: track.title || "",
        artist: artistOf(track, album),
        album: album.title || "",
        artwork: art
      });
    } catch (err) { /* 媒体会话是增强，失败不影响页内播控 */ }
  }

  function onTrackClick(album, index) {
    if (state.playingAlbumId === album.id && state.index === index && audio.src) {
      toggle();
      return;
    }
    playIndex(album, index);
  }

  function firstPlayable() {
    var viewed = findAlbum(state.viewAlbumId);
    if (viewed && viewed.tracks && viewed.tracks.length) return viewed;
    var list = visibleAlbums();
    for (var i = 0; i < list.length; i++) {
      if (list[i].tracks && list[i].tracks.length) return list[i];
    }
    return null;
  }

  function toggle() {
    if (!audio.src) {
      var album = firstPlayable();
      if (album) playIndex(album, 0);
      return;
    }
    if (audio.paused) {
      audio.play().catch(function () { setNotice("浏览器还没允许播放。请再点一次播放。"); });
    } else {
      audio.pause();
    }
  }

  function step(delta) {
    var album = currentAlbum() || firstPlayable();
    if (!album || !album.tracks || !album.tracks.length) return;
    var n = album.tracks.length;
    var onThis = state.playingAlbumId === album.id && state.index >= 0;
    if (state.shuffle && delta > 0) {
      if (onThis && n > 1) {
        state.history.push(state.index);
        if (state.history.length > 40) state.history.splice(0, state.history.length - 40);
      }
      playIndex(album, randomIndex(n, onThis ? state.index : -1));
      return;
    }
    if (state.shuffle && delta < 0 && onThis && state.history.length) {
      playIndex(album, state.history.pop());
      return;
    }
    var start = onThis ? state.index : (delta > 0 ? -1 : 0);
    playIndex(album, start + delta);
  }

  function nudge(sec) {
    if (!audio || !isFinite(audio.duration)) return;
    var next = Math.max(0, Math.min(audio.duration, (audio.currentTime || 0) + sec));
    audio.currentTime = next;
    paintSeek();
  }

  function bindTransport() {
    $("prev").appendChild(icon("prev"));
    $("next").appendChild(icon("next"));
    var queueBtn = $("queue-btn");
    queueBtn.textContent = "";
    queueBtn.appendChild(icon("queue"));
    $("play").addEventListener("click", toggle);
    $("prev").addEventListener("click", function () { step(-1); });
    $("next").addEventListener("click", function () { step(1); });
    $("repeat").addEventListener("click", function () {
      state.repeat = state.repeat === "off" ? "all" : state.repeat === "all" ? "one" : "off";
      remember("ooglex.music-player.repeat", state.repeat);
      paintTransport();
      announce(state.repeat === "one" ? "单曲循环" : state.repeat === "all" ? "列表循环" : "循环已关闭");
    });
    $("shuffle").addEventListener("click", function () {
      state.shuffle = !state.shuffle;
      if (!state.shuffle) state.history = [];
      remember("ooglex.music-player.shuffle", state.shuffle ? "1" : "0");
      paintTransport();
      announce(state.shuffle ? "随机播放" : "顺序播放");
    });
    $("queue-btn").addEventListener("click", function () {
      var open = queuePop.hidden;
      queuePop.hidden = !open;
      $("queue-btn").setAttribute("aria-expanded", open ? "true" : "false");
      if (open) renderQueue();
    });
    seek.addEventListener("pointerdown", function () { state.seeking = true; });
    seek.addEventListener("input", function () {
      state.seeking = true;
      var t = Number(seek.value);
      if (audio && isFinite(audio.duration)) audio.currentTime = t;
      paintSeek();
    });
    function endSeek() {
      if (!state.seeking) return;
      state.seeking = false;
      paintSeek();
    }
    seek.addEventListener("change", endSeek);
    seek.addEventListener("pointerup", endSeek);
    seek.addEventListener("pointercancel", endSeek);
    window.addEventListener("pointerup", endSeek);

    volume.addEventListener("input", function () {
      state.volume = Math.max(0, Math.min(1, Number(volume.value) / 100));
      state.muted = state.volume === 0;
      if (state.volume > 0) state.lastVolume = state.volume;
      if (audio) audio.volume = state.volume;
      remember("ooglex.music-player.volume", String(state.volume));
      paintVolume();
      paintTransport();
    });
    $("mute").addEventListener("click", function () {
      if (state.muted || state.volume === 0) {
        state.muted = false;
        state.volume = state.lastVolume || 0.9;
      } else {
        state.lastVolume = state.volume || 0.9;
        state.muted = true;
      }
      if (audio) audio.volume = state.muted ? 0 : state.volume;
      paintVolume();
      paintTransport();
    });

    audio.addEventListener("timeupdate", function () { if (!state.seeking) paintSeek(); });
    audio.addEventListener("loadedmetadata", paintSeek);
    audio.addEventListener("durationchange", paintSeek);
    audio.addEventListener("play", paintCurrent);
    audio.addEventListener("pause", paintCurrent);
    audio.addEventListener("ended", function () {
      var album = currentAlbum();
      if (!album || !album.tracks || !album.tracks.length) { paintCurrent(); return; }
      if (state.repeat === "one") {
        audio.currentTime = 0;
        audio.play().catch(function () { setNotice("浏览器还没允许播放。请再点一次播放。"); });
        return;
      }
      var n = album.tracks.length;
      if (state.shuffle && n > 1) {
        state.history.push(state.index);
        if (state.history.length > 40) state.history.splice(0, state.history.length - 40);
        playIndex(album, randomIndex(n, state.index));
        return;
      }
      if (state.index < n - 1) playIndex(album, state.index + 1);
      else if (state.repeat === "all") playIndex(album, 0);
      else paintCurrent();
    });
    audio.addEventListener("error", function () {
      if (!audio.src) return;
      setNotice("这首曲目没有播出来。可以换下一首，或稍后再试。");
    });

    document.addEventListener("keydown", function (event) {
      var tag = (event.target && event.target.tagName || "").toLowerCase();
      if (tag === "input" || tag === "textarea" || tag === "select" || tag === "button" || tag === "a") return;
      if (event.key === " ") { event.preventDefault(); toggle(); }
      else if (event.key === "ArrowRight") { event.preventDefault(); nudge(5); }
      else if (event.key === "ArrowLeft") { event.preventDefault(); nudge(-5); }
    });

    try {
      if ("mediaSession" in navigator) {
        navigator.mediaSession.setActionHandler("play", function () { if (audio.paused) toggle(); });
        navigator.mediaSession.setActionHandler("pause", function () { if (!audio.paused) toggle(); });
        navigator.mediaSession.setActionHandler("previoustrack", function () { step(-1); });
        navigator.mediaSession.setActionHandler("nexttrack", function () { step(1); });
      }
    } catch (err) { /* 个别浏览器不允许重复注册 */ }
  }

  function paintVolume() {
    var shown = state.muted ? 0 : Math.round(state.volume * 100);
    volume.value = String(shown);
    volume.style.setProperty("--p", shown + "%");
    volume.setAttribute("aria-valuenow", String(shown));
    volume.setAttribute("aria-valuetext", shown + "%");
  }

  async function load() {
    state.loadError = "";
    state.draftMode = /(?:^|[?&])draft=1(?:&|$)/.test(location.search);
    renderView();
    try {
      if (state.draftMode && window.OoglexMusicStore) {
        var draft = window.OoglexMusicStore.loadCatalog();
        if (draft) {
          state.catalog = draft;
          state.draftSavedAt = draft.savedAt || "";
          renderView();
          return;
        }
      }
      var res = await fetch("/apps/music-player/data/catalog.json", { cache: "no-store" });
      if (!res.ok) throw new Error("HTTP " + res.status);
      var data = await res.json();
      if (!data || !Array.isArray(data.albums)) throw new Error("清单格式不对");
      state.catalog = data;
      if (state.draftMode) state.draftSavedAt = "";
    } catch (err) {
      state.catalog = null;
      state.loadError = "专辑清单没有加载成功。请检查网络后重试。";
    }
    renderView();
  }

  function main() {
    audio = $("audio");
    seek = $("seek");
    volume = $("volume");
    view = $("view");
    live = $("live");
    queuePop = $("queue-pop");
    try {
      var rawVolume = localStorage.getItem("ooglex.music-player.volume");
      if (rawVolume != null) {
        var saved = Number(rawVolume);
        if (isFinite(saved) && saved >= 0 && saved <= 1) state.volume = saved;
      }
      var rawRepeat = localStorage.getItem("ooglex.music-player.repeat");
      if (rawRepeat === "all" || rawRepeat === "one" || rawRepeat === "off") state.repeat = rawRepeat;
      state.shuffle = localStorage.getItem("ooglex.music-player.shuffle") === "1";
    } catch (err) { /* 使用默认音量 */ }
    state.lastVolume = state.volume || 0.9;
    audio.volume = state.volume;
    paintVolume();
    bindTransport();
    paintTransport();
    window.addEventListener("hashchange", renderView);
    load();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();
