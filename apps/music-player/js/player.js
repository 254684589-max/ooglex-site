/* 流光播放器：唱片主画面、专辑列表、播控。不自动播放。 */
(function () {
  "use strict";
  if (window.__ooglexMusicPlayerInitialized) return;
  window.__ooglexMusicPlayerInitialized = true;

  var audio;
  var seek;
  var view;
  var live;
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
    // 音量交给手机或电脑的系统音量键，页内不再调节。
    volume: 1,
    repeat: "off",
    shuffle: false,
    history: [],
    notice: "",
    global: {
      config: null,
      configError: "",
      tag: "",
      order: "popular",
      q: "",
      albumId: "",
      status: "idle",
      message: "",
      updatedAt: "",
      hasMore: false,
      seq: 0
    },
    globalAlbums: {},
    favs: []
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
    else if (name === "chevron-down") {
      stroke("M6 9.5 12 15.5 18 9.5");
    }
    else if (name === "share") {
      stroke("M12 3.5v11");
      stroke("M7.5 8 12 3.5 16.5 8");
      stroke("M5.5 12.5v6a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2v-6");
    }
    else if (name === "heart") {
      stroke("M12 20.2s-7.4-4.5-9.4-9C1.2 8 2.9 4.6 6.4 4.6c2 0 3.3 1.1 4.2 2.3.7.9 2 .9 2.7 0 .9-1.2 2.2-2.3 4.2-2.3 3.5 0 5.2 3.4 3.8 6.6-2 4.5-9.3 9-9.3 9z");
    }
    else if (name === "heart-fill") {
      path("M12 20.2s-7.4-4.5-9.4-9C1.2 8 2.9 4.6 6.4 4.6c2 0 3.3 1.1 4.2 2.3.7.9 2 .9 2.7 0 .9-1.2 2.2-2.3 4.2-2.3 3.5 0 5.2 3.4 3.8 6.6-2 4.5-9.3 9-9.3 9z");
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
    return state.globalAlbums[id] || null;
  }

  function currentAlbum() {
    return state.queueAlbum || findAlbum(state.playingAlbumId);
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
    var match = /^#\/album\/([a-z0-9][a-z0-9-]{0,48})(?:\/([A-Za-z0-9_.-]{1,80}))?$/.exec(hash);
    if (match) return { name: "album", id: match[1], track: match[2] || "" };
    var shared = /^#\/track\/([1-9]\d{0,11})$/.exec(hash);
    if (shared) return { name: "track", id: shared[1] };
    if (hash === "#/global") return { name: "global" };
    if (hash === "#/favorites") return { name: "favorites" };
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
    var hero = h("section", "hero");
    hero.setAttribute("aria-label", "全球曲库");
    var entry = h("a", "hero-main");
    entry.href = "#/global";
    entry.appendChild(h("span", "hero-kicker", "GLOBAL LIBRARY"));
    entry.appendChild(h("span", "hero-title", "全球曲库"));
    entry.appendChild(h("span", "hero-sub", globalEntryText()));
    entry.appendChild(h("span", "hero-go", "进入 →"));
    hero.appendChild(entry);
    var cfg = state.global.config;
    if (cfg && cfg.api) {
      var quick = h("div", "hero-genres");
      cfg.genres.filter(function (g) { return g.tag; }).slice(0, 8).forEach(function (g) {
        var a = h("a", "hero-genre", g.label);
        a.href = "#/global";
        // 点之前先记下曲风，路由切过去时 onRoute 按它查询。
        a.addEventListener("click", function () { state.global.tag = g.tag; state.global.q = ""; });
        quick.appendChild(a);
      });
      hero.appendChild(quick);
    }
    view.appendChild(hero);
    var favEntry = h("a", "fav-entry");
    favEntry.href = "#/favorites";
    var favIco = h("span", "fav-entry-ico");
    favIco.setAttribute("aria-hidden", "true");
    favIco.appendChild(icon("heart-fill"));
    favEntry.appendChild(favIco);
    var favText = h("span", "fav-entry-text");
    favText.appendChild(h("span", "fav-entry-title", "我的收藏"));
    favText.appendChild(h("span", "fav-entry-sub", state.favs.length
      ? state.favs.length + " 首 · 保存在这台设备的浏览器里"
      : "还没有收藏。点歌曲右侧的 ♡ 即可收藏"));
    favEntry.appendChild(favText);
    favEntry.appendChild(h("span", "fav-entry-go", "→"));
    view.appendChild(favEntry);
    var head = h("div", "section-head");
    head.appendChild(h("h2", "section-title", "本站专辑"));
    head.appendChild(h("span", "section-count", visibleAlbums().length + " 张"));
    view.appendChild(head);
    if (!visibleAlbums().length) {
      view.appendChild(h("p", "empty", "还没有可播放的专辑。"));
      return;
    }
    var grid = h("div", "albums");
    visibleAlbums().forEach(function (album) {
      var card = h("a", "album-card");
      card.href = "#/album/" + album.id;
      var art = coverNode(album, "cover");
      var badge = h("span", "play-badge");
      badge.setAttribute("aria-hidden", "true");
      badge.appendChild(icon("play"));
      art.appendChild(badge);
      card.appendChild(art);
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
    var route = parseRoute();
    if (route.track) {
      var at = (album.tracks || []).map(function (t) { return t.id; }).indexOf(route.track);
      if (at >= 0) cueTrack(album, at);
    }
    var layout = h("div", "detail");
    layout.appendChild(coverNode(album, "cover lg"));
    var side = h("div", "detail-main");
    side.appendChild(h("p", "kicker", album.demo ? "演示样例" : "专辑"));
    side.appendChild(h("h2", "album-title", album.title || "未命名专辑"));
    var count = (album.tracks || []).length;
    side.appendChild(h("p", "by", artistOf(null, album) + (album.releasedAt ? " · " + album.releasedAt : "") + (count ? " · " + count + " 首" : "")));
    if (count) {
      var all = h("button", "play-all");
      all.type = "button";
      all.appendChild(icon("play"));
      all.appendChild(document.createTextNode(count > 1 ? "播放全部" : "播放"));
      all.addEventListener("click", function () { playIndex(album, 0); });
      side.appendChild(all);
    }
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
      var li = h("li", "row");
      var btn = h("button", "track");
      btn.type = "button";
      btn.dataset.album = album.id;
      btn.dataset.id = track.id;
      btn.dataset.index = String(index);
      var idx = leadNode(index);
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
      var heart = favButton(album, track);
      if (heart) li.appendChild(heart);
      list.appendChild(li);
    });
    if (!(album.tracks || []).length) layout.appendChild(h("p", "empty", "这张专辑还没有曲目。"));
    layout.appendChild(list);
    view.appendChild(layout);
  }


  // 序号格；当前曲目改显示跳动的电平条（纯装饰，状态另由「正在播放」文字和 aria-current 表达）。
  function leadNode(index) {
    var idx = h("span", "idx");
    idx.appendChild(h("span", "num", String(index + 1)));
    var eq = h("span", "eq");
    eq.setAttribute("aria-hidden", "true");
    eq.appendChild(h("i"));
    eq.appendChild(h("i"));
    eq.appendChild(h("i"));
    idx.appendChild(eq);
    return idx;
  }

  function thumbNode(src, title) {
    var wrap = h("span", "thumb");
    wrap.setAttribute("aria-hidden", "true");
    if (src) {
      var img = h("img");
      img.alt = "";
      img.loading = "lazy";
      img.decoding = "async";
      img.src = src;
      img.addEventListener("error", function () { img.remove(); wrap.textContent = (title || "♪").slice(0, 1); });
      wrap.appendChild(img);
    } else {
      wrap.textContent = (title || "♪").slice(0, 1);
    }
    return wrap;
  }

  function pill(text, href, cls) {
    var a = h("a", "pill" + (cls ? " " + cls : ""), text);
    a.href = href;
    a.target = "_blank";
    a.rel = "noopener noreferrer";
    return a;
  }

  /* ---------------- 全球曲库：Jamendo 独立音乐目录，经 workers/jamendo-proxy 查询 ---------------- */

  var GLOBAL_ORDERS = [
    { key: "popular", label: "近一月热门" },
    { key: "week", label: "本周热门" },
    { key: "new", label: "最新发布" }
  ];

  function globalEntryText() {
    var g = state.global;
    if (g.configError) return "配置没有读到，点进去重试";
    if (!g.config) return "正在读取…";
    if (!g.config.api) return "尚未开通 · Jamendo 授权独立音乐";
    return (g.config.genres || []).length + " 种曲风 · Jamendo 授权独立音乐 · 本站不存音频";
  }

  // 不信任接口返回：只放行 Jamendo / Creative Commons 的 https 地址，文字只走 textContent。
  function safeUrl(value, hosts) {
    try {
      var url = new URL(String(value || ""));
      if (url.protocol !== "https:") return "";
      var ok = hosts.some(function (host) { return url.hostname === host || url.hostname.slice(-(host.length + 1)) === "." + host; });
      return ok ? url.href : "";
    } catch (err) { return ""; }
  }

  function cleanGlobalTrack(raw) {
    if (!raw || typeof raw !== "object" || !/^\d{1,20}$/.test(String(raw.id || ""))) return null;
    var src = safeUrl(raw.src, ["jamendo.com"]);
    var license = safeUrl(raw.license, ["creativecommons.org"]);
    if (!src || !license) return null;
    var dur = Number(raw.durationSec);
    return {
      id: "j" + raw.id,
      title: String(raw.title || "未命名").slice(0, 120),
      artist: String(raw.artist || "未知艺人").slice(0, 80),
      album: String(raw.album || "").slice(0, 120),
      durationSec: isFinite(dur) && dur > 0 ? Math.round(dur) : 0,
      image: safeUrl(raw.image, ["jamendo.com"]),
      src: src,
      license: license,
      page: safeUrl(raw.page, ["jamendo.com"]),
      source: "Jamendo"
    };
  }

  function licenseName(url) {
    var m = /\/licenses\/([a-z-]+)\/([\d.]+)/.exec(url || "");
    return m ? "CC " + m[1].toUpperCase() + " " + m[2] : "Creative Commons";
  }

  function genreLabel(tag) {
    var list = (state.global.config && state.global.config.genres) || [];
    for (var i = 0; i < list.length; i++) if (list[i].tag === tag) return list[i].label;
    return tag || "全部";
  }

  function globalKey() {
    var g = state.global;
    return "global:" + g.tag + ":" + g.order + ":" + g.q.toLowerCase();
  }

  // 重绘会换掉整块节点。焦点原本在这块里（刚点的曲风、搜索框、加载更多），就还给同一个控件。
  function rerenderGlobal() {
    if (parseRoute().name !== "global") return;
    var active = document.activeElement;
    var key = active && view.contains(active) && active.dataset ? (active.dataset.focus || "") : "";
    skipAlbumScroll = true;
    renderView();
    if (!key) return;
    var target = view.querySelector('[data-focus="' + key + '"]');
    if (target) try { target.focus({ preventScroll: true }); } catch (err) { target.focus(); }
  }

  function onRoute() {
    renderView();
    var g = state.global;
    if (parseRoute().name === "global" && g.config && g.config.api && g.status !== "loading" && g.albumId !== globalKey()) {
      fetchGlobal(false);
    }
  }

  function globalError(code) {
    if (code === "not_configured") return "接口已部署，但还没配置 Jamendo client_id。";
    if (code === "rate_limited") return "请求太频繁了，请一分钟后再试。";
    if (code === "timeout") return "Jamendo 响应超时，请稍后重试。";
    if (code === "bad_request") return "查询条件不对，换个曲风或关键词试试。";
    return "全球曲库暂时连不上，请稍后重试。已加载的曲目仍可播放。";
  }

  async function loadGlobalConfig() {
    var g = state.global;
    g.configError = "";
    try {
      var res = await fetch("/apps/music-player/data/global.json", { cache: "no-store" });
      if (!res.ok) throw new Error("HTTP " + res.status);
      var data = await res.json();
      if (!data || !Array.isArray(data.genres)) throw new Error("格式不对");
      var api = safeApi(data.api);
      // apiFallback：主地址连不上（断网、超时、被墙）时再试的备用地址，例如 workers.dev。
      var apis = [api, safeApi(data.apiFallback)].filter(function (u, i, all) { return u && all.indexOf(u) === i; });
      g.config = { api: api, apis: apis, genres: data.genres.filter(function (x) {
        return x && typeof x.label === "string" && /^(?:[a-z]{2,16})?$/.test(String(x.tag || ""));
      }), source: String(data.source || "Jamendo"), sourceUrl: safeUrl(data.sourceUrl, ["jamendo.com"]) };
    } catch (err) {
      g.config = null;
      g.configError = "全球曲库的配置没有读到。";
    }
    if (parseRoute().name === "list") { skipAlbumScroll = true; renderView(); }
    else if (parseRoute().name === "track") { skipAlbumScroll = true; renderView(); }
    else if (parseRoute().name === "global") {
      rerenderGlobal();
      if (g.config && g.config.api && !state.globalAlbums[globalKey()]) fetchGlobal(false);
    }
  }

  function safeApi(value) {
    try {
      var url = new URL(String(value || ""));
      var local = url.hostname === "127.0.0.1" || url.hostname === "localhost";
      if (url.protocol !== "https:" && !(local && url.protocol === "http:")) return "";
      return url.href.replace(/\/+$/, "");
    } catch (err) { return ""; }
  }

  // 依次试主地址和备用地址；只有连不上才换下一个，接口给出的 HTTP 错误照常显示。
  // 哪个地址成功过，本页之后先用它。
  async function apiTracks(params) {
    var g = state.global;
    var apis = g.config.apis && g.config.apis.length ? g.config.apis : [g.config.api];
    var order = apis.slice(g.apiIndex || 0).concat(apis.slice(0, g.apiIndex || 0));
    var data = null;
    var code = "";
    for (var t = 0; t < order.length; t++) {
      var ctrl = typeof AbortController === "function" ? new AbortController() : null;
      var timer = setTimeout(function () { if (ctrl) ctrl.abort(); }, 8000);
      data = null;
      code = "";
      var reached = false;
      try {
        var res = await fetch(order[t] + "/tracks?" + params.toString(), ctrl ? { signal: ctrl.signal } : {});
        reached = true;
        try { data = await res.json(); } catch (err) { data = null; }
        if (!res.ok || !data || data.status === "error") code = (data && data.error) || "upstream";
      } catch (err) {
        code = err && err.name === "AbortError" ? "timeout" : "upstream";
      }
      clearTimeout(timer);
      if (reached) { g.apiIndex = apis.indexOf(order[t]); break; }
    }
    return { data: data, code: code };
  }

  async function fetchGlobal(append) {
    var g = state.global;
    if (!g.config || !g.config.api) return;
    var key = globalKey();
    var album = state.globalAlbums[key];
    if (!append && album) {
      g.albumId = key;
      g.status = album.tracks.length ? "ok" : "empty";
      g.hasMore = album.hasMore;
      g.updatedAt = album.updatedAt;
      g.message = "";
      rerenderGlobal();
      return;
    }
    var seq = ++g.seq;
    var offset = append && album ? album.nextOffset : 0;
    g.status = append ? "more" : "loading";
    g.message = "";
    if (!append) g.albumId = "";
    rerenderGlobal();
    var params = new URLSearchParams();
    if (g.tag) params.set("tag", g.tag);
    params.set("order", g.order);
    params.set("offset", String(offset));
    if (g.q) params.set("q", g.q);
    var got = await apiTracks(params);
    var data = got.data;
    var code = got.code;
    if (seq !== g.seq) return;
    if (code || !data || !Array.isArray(data.tracks)) {
      g.status = append ? "ok" : "error";
      if (append && album) g.albumId = key;
      g.message = globalError(code || "upstream");
      rerenderGlobal();
      return;
    }
    var tracks = data.tracks.map(cleanGlobalTrack).filter(Boolean);
    if (!album || !append) {
      var title = g.q ? "搜索：" + g.q : genreLabel(g.tag);
      album = {
        id: key,
        title: "全球曲库 · " + title,
        artist: "多位艺人",
        global: true,
        tracks: []
      };
      state.globalAlbums[key] = album;
    }
    var seen = {};
    album.tracks.forEach(function (t) { seen[t.id] = true; });
    tracks.forEach(function (t) { if (!seen[t.id]) { album.tracks.push(t); seen[t.id] = true; } });
    album.nextOffset = offset + (Number(data.pageSize) || 20);
    album.hasMore = !!data.hasMore;
    album.updatedAt = String(data.updatedAt || "");
    album.partial = album.partial || data.status === "partial" || tracks.length < data.tracks.length;
    g.albumId = key;
    g.hasMore = album.hasMore;
    g.updatedAt = album.updatedAt;
    g.status = album.tracks.length ? "ok" : "empty";
    // Jamendo 偶尔对有曲目的曲风也回 0 条；空结果不留在本页缓存，再点一次会重新查询。
    if (!album.tracks.length) delete state.globalAlbums[key];
    rerenderGlobal();
  }

  function pickGlobal(change) {
    var g = state.global;
    Object.keys(change).forEach(function (k) { g[k] = change[k]; });
    fetchGlobal(false);
  }

  function chip(label, on, onClick, focusKey) {
    var b = h("button", "chip" + (on ? " is-on" : ""), label);
    b.type = "button";
    b.setAttribute("aria-pressed", on ? "true" : "false");
    b.dataset.focus = focusKey;
    b.addEventListener("click", onClick);
    return b;
  }

  function renderGlobal() {
    var g = state.global;
    var back = h("a", "text-link", "← 全部专辑");
    back.href = "#/";
    view.appendChild(back);
    var head = h("div", "global-head");
    head.appendChild(h("p", "hero-kicker", "GLOBAL LIBRARY"));
    head.appendChild(h("h2", "global-title", "全球曲库"));
    var about = h("p", "global-about");
    about.appendChild(document.createTextNode("来自 "));
    var src = h("a", null, "Jamendo");
    src.href = "https://www.jamendo.com/";
    src.target = "_blank";
    src.rel = "noopener noreferrer";
    about.appendChild(src);
    about.appendChild(document.createTextNode(" 的全球独立音乐人作品，每首按其 Creative Commons 许可署名。音频直接从 Jamendo 播放，本站不存储；这里没有主流唱片公司的热门歌。"));
    head.appendChild(about);
    view.appendChild(head);

    if (g.configError) {
      view.appendChild(h("p", "global-status is-error", "⚠ " + g.configError));
      var retryCfg = h("button", "text-btn", "重试");
      retryCfg.type = "button";
      retryCfg.addEventListener("click", loadGlobalConfig);
      view.appendChild(retryCfg);
      return;
    }
    if (!g.config) {
      view.appendChild(h("p", "global-status", "正在读取全球曲库配置…"));
      return;
    }
    if (!g.config.api) {
      view.appendChild(h("p", "global-status is-off", "○ 尚未开通：查询接口还没部署，暂时听不了。本站原创专辑照常可听。"));
      return;
    }

    var genres = h("div", "chips genres");
    genres.setAttribute("role", "group");
    genres.setAttribute("aria-label", "曲风");
    g.config.genres.forEach(function (item) {
      genres.appendChild(chip(item.label, !g.q && g.tag === item.tag, function () {
        pickGlobal({ tag: item.tag, q: "" });
      }, "tag:" + item.tag));
    });
    view.appendChild(genres);
    var picked = genres.querySelector(".chip.is-on");
    if (picked && genres.scrollWidth > genres.clientWidth) {
      genres.scrollLeft = Math.max(0, picked.offsetLeft - genres.offsetLeft - genres.clientWidth / 2 + picked.offsetWidth / 2);
    }

    var orders = h("div", "chips seg");
    orders.setAttribute("role", "group");
    orders.setAttribute("aria-label", "排序");
    GLOBAL_ORDERS.forEach(function (item) {
      orders.appendChild(chip(item.label, g.order === item.key, function () {
        pickGlobal({ order: item.key });
      }, "order:" + item.key));
    });
    view.appendChild(orders);

    var form = h("form", "global-search");
    form.setAttribute("role", "search");
    var input = h("input");
    input.type = "search";
    input.maxLength = 40;
    input.placeholder = "搜索歌名或艺人";
    input.setAttribute("aria-label", "搜索全球曲库");
    input.value = g.q;
    input.dataset.focus = "search";
    var go = h("button", "text-btn", "搜索");
    go.type = "submit";
    form.appendChild(input);
    form.appendChild(go);
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      var q = input.value.replace(/\s+/g, " ").trim().slice(0, 40);
      pickGlobal({ q: q, tag: q ? "" : g.tag });
    });
    view.appendChild(form);

    var album = state.globalAlbums[g.albumId];
    var status = h("p", "global-status");
    status.setAttribute("role", "status");
    if (g.status === "loading" || g.status === "idle") status.textContent = "正在从 Jamendo 读取曲目…";
    else if (g.status === "error") { status.className += " is-error"; status.textContent = "⚠ " + g.message; }
    else if (g.status === "empty") status.textContent = g.q ? "没有找到「" + g.q + "」相关的曲目。" : "这次没有取到曲目。Jamendo 偶尔会返回空结果，可以再试一次或换个曲风。";
    else {
      var bits = ["来源 Jamendo"];
      if (album) bits.push(album.tracks.length + " 首");
      if (g.updatedAt) bits.push("查询于 " + g.updatedAt.replace("T", " ").slice(0, 16) + " UTC");
      if (album && album.partial) bits.push("部分曲目缺少可播音频或许可，已略过");
      status.textContent = bits.join(" · ");
      if (g.message) {
        status.className += " is-error";
        status.textContent = "⚠ " + g.message + " " + status.textContent;
      }
    }
    view.appendChild(status);
    if (g.status === "error" || g.status === "empty") {
      var retry = h("button", "text-btn", g.status === "empty" ? "再试一次" : "重试");
      retry.type = "button";
      retry.addEventListener("click", function () { fetchGlobal(false); });
      view.appendChild(retry);
    }

    if (album && album.tracks.length) {
      var list = h("ol", "tracks global-tracks");
      album.tracks.forEach(function (track, index) {
        var li = h("li", "row");
        var btn = h("button", "track has-thumb");
        btn.type = "button";
        btn.dataset.album = album.id;
        btn.dataset.id = track.id;
        btn.dataset.index = String(index);
        btn.appendChild(leadNode(index));
        btn.appendChild(thumbNode(track.image, track.title));
        var titles = h("span", "titles");
        titles.appendChild(h("span", "t-title", track.title));
        titles.appendChild(h("span", "t-artist", track.artist + (track.album && track.album !== track.title ? " · " + track.album : "")));
        btn.appendChild(titles);
        btn.appendChild(h("span", "flag", ""));
        btn.appendChild(h("span", "t-time", track.durationSec ? fmt(track.durationSec) : ""));
        btn.addEventListener("click", function () { onTrackClick(album, index); });
        li.appendChild(btn);
        var links = h("p", "t-links");
        links.appendChild(pill(licenseName(track.license), track.license));
        if (track.page) links.appendChild(pill("Jamendo ↗", track.page, "is-src"));
        li.appendChild(links);
        var heart = favButton(album, track);
        if (heart) li.appendChild(heart);
        list.appendChild(li);
      });
      view.appendChild(list);
      if (g.hasMore) {
        var more = h("button", "text-btn global-more", g.status === "more" ? "正在加载…" : "加载更多");
        more.type = "button";
        more.disabled = g.status === "more";
        more.dataset.focus = "more";
        more.addEventListener("click", function () { fetchGlobal(true); });
        view.appendChild(more);
      }
    }
  }


  /* ---------------- 收藏：存在这台设备的浏览器（localStorage），不需要登录，也不跨设备同步 ---------------- */

  var FAV_STORE = "ooglex.music-player.favorites";
  var FAV_MAX = 500;
  var FAV_KEY_RE = /^(?:j:\d{1,20}|l:[a-z0-9][a-z0-9-]{0,48}:[A-Za-z0-9_.-]{1,80})$/;

  // 本站媒体用站内路径，全球曲库只认 Jamendo 的 https 地址；本机草稿（idb:）不能收藏。
  function favMediaUrl(value) {
    var u = String(value || "");
    if (/^\/apps\/music-player\/media\/[A-Za-z0-9._\/-]+$/.test(u) && u.indexOf("..") < 0) return u;
    return safeUrl(u, ["jamendo.com"]);
  }

  function favKey(album, track) {
    if (!track) return "";
    if (track.favKey) return track.favKey;
    if (track.source === "Jamendo") return "j:" + String(track.id).replace(/^j/, "");
    return album && album.id ? "l:" + album.id + ":" + track.id : "";
  }

  // 收藏时把歌名、封面、播放地址和署名一起记下，之后在收藏页直接能播，不用重新查询。
  function favRecord(album, track) {
    var key = favKey(album, track);
    var src = favMediaUrl(track && track.src);
    if (!FAV_KEY_RE.test(key) || !src) return null;
    var local = !album || !album.global;
    var dur = Number(track.durationSec);
    return {
      key: key,
      title: String(track.title || "未命名").slice(0, 120),
      artist: String(track.favKey ? track.artist : artistOf(track, album)).slice(0, 80),
      album: String(track.favKey ? (track.album || "") : (track.album || (local && album ? album.title : "") || "")).slice(0, 120),
      src: src,
      image: favMediaUrl(track.image || (local && album && !track.favKey ? album.cover : "")),
      durationSec: isFinite(dur) && dur > 0 ? Math.round(dur) : 0,
      source: track.source === "Jamendo" ? "Jamendo" : "",
      license: safeUrl(track.license || (local && album ? album.licenseUrl : ""), ["creativecommons.org"]),
      licenseName: String(track.licenseName || (local && album && !track.license ? album.license || "" : "")).slice(0, 40),
      page: safeUrl(track.page, ["jamendo.com"]),
      addedAt: String(track.addedAt || new Date().toISOString()).slice(0, 30)
    };
  }

  function loadFavs() {
    var raw = null;
    try { raw = JSON.parse(localStorage.getItem(FAV_STORE) || "[]"); } catch (err) { raw = null; }
    if (!Array.isArray(raw)) return [];
    var seen = {};
    var out = [];
    raw.forEach(function (r) {
      if (!r || typeof r !== "object" || seen[r.key]) return;
      var clean = favRecord(null, Object.assign({}, r, { favKey: String(r.key || "") }));
      if (!clean) return;
      seen[clean.key] = true;
      out.push(clean);
    });
    return out.slice(0, FAV_MAX);
  }

  function saveFavs() {
    try {
      localStorage.setItem(FAV_STORE, JSON.stringify(state.favs));
      return true;
    } catch (err) {
      return false;
    }
  }

  function isFav(key) {
    for (var i = 0; i < state.favs.length; i++) if (state.favs[i].key === key) return true;
    return false;
  }

  function toggleFav(album, track) {
    var rec = favRecord(album, track);
    if (!rec) return;
    var was = isFav(rec.key);
    if (was) state.favs = state.favs.filter(function (r) { return r.key !== rec.key; });
    else state.favs = [rec].concat(state.favs).slice(0, FAV_MAX);
    if (!saveFavs()) setNotice("这台浏览器不允许保存收藏（可能是无痕模式），刷新后会丢失。");
    announce(was ? "已取消收藏 " + rec.title : "已收藏 " + rec.title);
    var route = parseRoute().name;
    if (route === "favorites" || route === "list") {
      // 重绘后把焦点还给同一首歌的心形按钮
      var active = document.activeElement;
      var keep = active && active.dataset ? active.dataset.favKey : "";
      skipAlbumScroll = true;
      renderView();
      var again = keep && view.querySelector('.fav-btn[data-fav-key="' + keep.replace(/"/g, "") + '"]');
      if (again) try { again.focus({ preventScroll: true }); } catch (err) { again.focus(); }
    }
    paintFavButtons();
  }

  function paintHeart(btn, on, title) {
    btn.textContent = "";
    btn.appendChild(icon(on ? "heart-fill" : "heart"));
    btn.classList.toggle("is-on", on);
    btn.setAttribute("aria-pressed", on ? "true" : "false");
    btn.setAttribute("aria-label", (on ? "取消收藏 " : "收藏 ") + (title || ""));
  }

  function favButton(album, track) {
    var rec = favRecord(album, track);
    if (!rec) return null;
    var btn = h("button", "fav-btn");
    btn.type = "button";
    btn.dataset.favKey = rec.key;
    paintHeart(btn, isFav(rec.key), rec.title);
    btn.addEventListener("click", function () { toggleFav(album, track); });
    return btn;
  }

  function paintFavButtons() {
    document.querySelectorAll(".fav-btn[data-fav-key]").forEach(function (btn) {
      var on = isFav(btn.dataset.favKey);
      if (btn.classList.contains("is-on") !== on) paintHeart(btn, on, (btn.getAttribute("aria-label") || "").replace(/^(取消收藏|收藏) /, ""));
    });
    var track = currentTrack();
    paintNowFav(track, currentAlbum());
  }

  function paintNowFav(track, album) {
    var btn = $("now-fav");
    if (!btn) return;
    var rec = track ? favRecord(album, track) : null;
    btn.hidden = !rec;
    if (rec) paintHeart(btn, isFav(rec.key), rec.title);
  }

  // 播放收藏时用当时的一份快照；播放中取消收藏不会打断正在放的这首。
  function favoritesAlbum() {
    var album = {
      id: "favorites",
      title: "我的收藏",
      artist: "多位艺人",
      global: true,
      tracks: state.favs.map(function (r) { return Object.assign({}, r, { id: r.key, favKey: r.key }); })
    };
    state.globalAlbums.favorites = album;
    return album;
  }

  function playFavorite(index) {
    var rec = state.favs[index];
    var cur = currentTrack();
    if (rec && cur && state.playingAlbumId === "favorites" && cur.id === rec.key && audio.src) {
      toggle();
      return;
    }
    playIndex(favoritesAlbum(), index);
  }

  function renderFavorites() {
    var back = h("a", "text-link", "← 全部专辑");
    back.href = "#/";
    view.appendChild(back);
    var head = h("div", "fav-head");
    head.appendChild(h("p", "hero-kicker", "FAVORITES"));
    head.appendChild(h("h2", "global-title", "我的收藏"));
    head.appendChild(h("p", "fav-note", state.favs.length
      ? state.favs.length + " 首。收藏保存在这台设备的浏览器里，换手机或换浏览器不会同步，清除浏览器数据会一并清除。"
      : "还没有收藏。在专辑或全球曲库里点歌曲右侧的 ♡，或点正在播放歌名旁的 ♡。收藏只保存在这台设备的浏览器里。"));
    if (state.favs.length) {
      var all = h("button", "play-all");
      all.type = "button";
      all.appendChild(icon("play"));
      all.appendChild(document.createTextNode(state.favs.length > 1 ? "播放全部" : "播放"));
      all.addEventListener("click", function () { playIndex(favoritesAlbum(), 0); });
      head.appendChild(all);
    }
    view.appendChild(head);
    if (!state.favs.length) return;
    var list = h("ol", "tracks global-tracks");
    state.favs.forEach(function (rec, index) {
      var li = h("li", "row");
      var btn = h("button", "track has-thumb");
      btn.type = "button";
      btn.dataset.album = "favorites";
      btn.dataset.id = rec.key;
      btn.dataset.index = String(index);
      btn.appendChild(leadNode(index));
      btn.appendChild(thumbNode(rec.image, rec.title));
      var titles = h("span", "titles");
      titles.appendChild(h("span", "t-title", rec.title));
      titles.appendChild(h("span", "t-artist", rec.artist + (rec.album && rec.album !== rec.title ? " · " + rec.album : "")));
      btn.appendChild(titles);
      btn.appendChild(h("span", "flag", ""));
      btn.appendChild(h("span", "t-time", rec.durationSec ? fmt(rec.durationSec) : ""));
      btn.addEventListener("click", function () { playFavorite(index); });
      li.appendChild(btn);
      var links = h("p", "t-links");
      if (rec.license) links.appendChild(pill(rec.licenseName || licenseName(rec.license), rec.license));
      if (rec.page) links.appendChild(pill("Jamendo ↗", rec.page, "is-src"));
      li.appendChild(links);
      var heart = h("button", "fav-btn");
      heart.type = "button";
      heart.dataset.favKey = rec.key;
      paintHeart(heart, true, rec.title);
      heart.addEventListener("click", function () { toggleFav(null, Object.assign({}, rec, { favKey: rec.key })); });
      li.appendChild(heart);
      list.appendChild(li);
    });
    view.appendChild(list);
  }


  /* ---------------- 分享：系统分享面板、复制链接、分享海报；应用内置浏览器里引导用右上角菜单 ---------------- */

  var SITE = "https://www.ooglex.com/apps/music-player/";
  var share = { album: null, track: null, url: "", blob: null, objectUrl: "", busy: false };

  // 每首歌一条固定链接：本站专辑 #/album/<专辑>/<曲目>，全球曲库 #/track/<Jamendo 编号>。本机草稿不能分享。
  function shareUrl(album, track) {
    if (!track) return "";
    var key = favKey(album, track);
    var m = /^j:(\d{1,12})$/.exec(key);
    if (m) return SITE + "#/track/" + m[1];
    m = /^l:([a-z0-9][a-z0-9-]{0,48}):([A-Za-z0-9_.-]{1,80})$/.exec(key);
    if (m && favMediaUrl(track.src)) return SITE + "#/album/" + m[1] + "/" + m[2];
    return "";
  }

  // 聊天、社交类应用的内置浏览器（页面文字里不点名具体应用）
  function inAppBrowser() {
    return /MicroMessenger|\bQQ\/|Weibo|DingTalk/i.test(navigator.userAgent || "");
  }

  // 分享链接打开时，把那首歌摆到播放器上，但不自动出声（浏览器也不允许）。
  function cueTrack(album, index) {
    if (audio && (audio.src || loadingSource)) return;
    if (state.playingAlbumId === album.id && state.index === index) return;
    state.queueAlbum = album;
    state.playingAlbumId = album.id;
    state.index = index;
    state.history = [];
    setNotice("分享的歌曲已就绪，点播放即可收听。");
  }

  var sharedFetch = { id: "", status: "idle", message: "" };

  async function renderSharedTrackData(id) {
    sharedFetch = { id: id, status: "loading", message: "" };
    var params = new URLSearchParams();
    params.set("id", id);
    var got = await apiTracks(params);
    if (sharedFetch.id !== id) return;
    var track = got.data && Array.isArray(got.data.tracks) ? cleanGlobalTrack(got.data.tracks[0]) : null;
    if (got.code || !got.data) {
      sharedFetch.status = "error";
      sharedFetch.message = globalError(got.code || "upstream");
    } else if (!track) {
      sharedFetch.status = "empty";
    } else {
      state.globalAlbums.shared = { id: "shared", title: "分享的歌曲", artist: track.artist, global: true, tracks: [track], forId: id };
      sharedFetch.status = "ok";
    }
    if (parseRoute().name === "track" && parseRoute().id === id) {
      skipAlbumScroll = true;
      renderView();
    }
  }

  function renderSharedTrack(id) {
    var back = h("a", "text-link", "← 全部专辑");
    back.href = "#/";
    view.appendChild(back);
    var head = h("div", "fav-head share-head");
    head.appendChild(h("p", "hero-kicker", "SHARED WITH YOU"));
    head.appendChild(h("h2", "global-title", "分享给你的歌曲"));
    head.appendChild(h("p", "fav-note", "来自流光播放器的全球曲库：Jamendo 上独立音乐人以 Creative Commons 许可发布的作品。点播放即可收听。"));
    view.appendChild(head);
    var g = state.global;
    if (g.configError) { view.appendChild(h("p", "global-status is-error", "⚠ " + g.configError)); return; }
    if (!g.config) { view.appendChild(h("p", "global-status", "正在读取…")); return; }
    if (!g.config.api) { view.appendChild(h("p", "global-status is-off", "○ 全球曲库尚未开通，暂时打不开这首歌。")); return; }
    var album = state.globalAlbums.shared;
    if (!album || album.forId !== id) {
      if (sharedFetch.id !== id || sharedFetch.status === "idle") { renderSharedTrackData(id); }
      if (sharedFetch.status === "error" && sharedFetch.id === id) {
        view.appendChild(h("p", "global-status is-error", "⚠ " + sharedFetch.message));
        var retry = h("button", "text-btn", "重试");
        retry.type = "button";
        retry.addEventListener("click", function () { sharedFetch.status = "idle"; renderSharedTrackData(id); });
        view.appendChild(retry);
      } else if (sharedFetch.status === "empty" && sharedFetch.id === id) {
        view.appendChild(h("p", "global-status", "这首歌找不到了，可能已从 Jamendo 下架。"));
      } else {
        view.appendChild(h("p", "global-status", "正在从 Jamendo 读取这首歌…"));
      }
    } else {
      cueTrack(album, 0);
      var track = album.tracks[0];
      var list = h("ol", "tracks global-tracks");
      var li = h("li", "row");
      var btn = h("button", "track has-thumb");
      btn.type = "button";
      btn.dataset.album = album.id;
      btn.dataset.id = track.id;
      btn.dataset.index = "0";
      btn.appendChild(leadNode(0));
      btn.appendChild(thumbNode(track.image, track.title));
      var titles = h("span", "titles");
      titles.appendChild(h("span", "t-title", track.title));
      titles.appendChild(h("span", "t-artist", track.artist + (track.album && track.album !== track.title ? " · " + track.album : "")));
      btn.appendChild(titles);
      btn.appendChild(h("span", "flag", ""));
      btn.appendChild(h("span", "t-time", track.durationSec ? fmt(track.durationSec) : ""));
      btn.addEventListener("click", function () { onTrackClick(album, 0); });
      li.appendChild(btn);
      var links = h("p", "t-links");
      links.appendChild(pill(licenseName(track.license), track.license));
      if (track.page) links.appendChild(pill("Jamendo ↗", track.page, "is-src"));
      li.appendChild(links);
      var heart = favButton(album, track);
      if (heart) li.appendChild(heart);
      list.appendChild(li);
      view.appendChild(list);
    }
    var more = h("a", "text-btn share-more", "去全球曲库听更多 →");
    more.href = "#/global";
    view.appendChild(more);
  }

  function shareText(album, track) {
    return "我在 Ooglex 流光播放器听《" + track.title + "》— " + artistOf(track, album);
  }

  function setShareStatus(text) {
    var node = $("share-status");
    if (node) node.textContent = text || "";
  }

  function openShare(album, track) {
    var url = shareUrl(album, track);
    var dlg = $("share-dlg");
    if (!url || !dlg) return;
    share.album = album;
    share.track = track;
    share.url = url;
    share.blob = null;
    if (share.objectUrl) { URL.revokeObjectURL(share.objectUrl); share.objectUrl = ""; }
    $("share-song").textContent = "《" + track.title + "》 · " + artistOf(track, album);
    $("share-url").value = url;
    $("share-native").hidden = !navigator.share;
    $("share-poster-box").hidden = true;
    $("share-poster-share").hidden = true;
    setShareStatus("");
    var app = inAppBrowser();
    var hint = $("share-inapp");
    hint.hidden = !app;
    if (app) {
      hint.textContent = "点右上角 ··· 菜单即可分享。页面地址已换成这首歌的链接，对方打开就是这首。";
      // 内置浏览器的右上角菜单分享的是当前地址，先换成这首歌的链接（不触发页面跳转）
      try { history.replaceState(null, "", url.replace(SITE, location.pathname)); } catch (err) { /* 忽略 */ }
    }
    if (typeof dlg.showModal === "function") { if (!dlg.open) dlg.showModal(); }
    else dlg.setAttribute("open", "");
    var first = navigator.share ? $("share-native") : $("share-copy");
    try { first.focus(); } catch (err) { /* 忽略 */ }
  }

  function closeShare() {
    var dlg = $("share-dlg");
    if (!dlg) return;
    if (typeof dlg.close === "function" && dlg.open) dlg.close();
    else dlg.removeAttribute("open");
    var back = $("now-share");
    if (back && !back.hidden) try { back.focus({ preventScroll: true }); } catch (err) { /* 忽略 */ }
  }

  async function copyShareLink() {
    var input = $("share-url");
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(share.url);
        setShareStatus("链接已复制，可以粘贴发给朋友。");
        return;
      }
    } catch (err) { /* 换下面的办法 */ }
    try {
      input.focus();
      input.select();
      if (document.execCommand && document.execCommand("copy")) { setShareStatus("链接已复制。"); return; }
    } catch (err) { /* 忽略 */ }
    setShareStatus("这个浏览器不让自动复制，请长按上面的链接手动复制。");
  }

  async function nativeShare() {
    try {
      await navigator.share({ title: share.track.title + " · 流光播放器", text: shareText(share.album, share.track), url: share.url });
    } catch (err) {
      if (err && err.name === "AbortError") return;
      setShareStatus("系统分享没有打开，可以改用「复制链接」或「生成海报」。");
    }
  }

  function loadImage(src, cors) {
    return new Promise(function (resolve) {
      if (!src) { resolve(null); return; }
      var img = new Image();
      if (cors) img.crossOrigin = "anonymous";
      img.onload = function () { resolve(img); };
      img.onerror = function () { resolve(null); };
      img.src = src;
    });
  }

  function roundRect(ctx, x, y, w, hgt, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + hgt, r);
    ctx.arcTo(x + w, y + hgt, x, y + hgt, r);
    ctx.arcTo(x, y + hgt, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  function wrapText(ctx, text, x, y, maxW, lineH, maxLines) {
    var chars = Array.from(String(text || ""));
    var line = "";
    var lines = [];
    for (var i = 0; i < chars.length; i++) {
      var next = line + chars[i];
      if (ctx.measureText(next).width > maxW && line) {
        lines.push(line);
        line = chars[i];
        if (lines.length === maxLines) { line = ""; lines[maxLines - 1] = lines[maxLines - 1].slice(0, -1) + "…"; break; }
      } else {
        line = next;
      }
    }
    if (line && lines.length < maxLines) lines.push(line);
    lines.forEach(function (l, k) { ctx.fillText(l, x, y + k * lineH); });
    return y + lines.length * lineH;
  }

  // 1080×1440 竖版海报：封面、歌名、艺人、扫码打开播放器的二维码与署名。
  async function drawPoster(withCover) {
    var track = share.track;
    var album = share.album;
    var canvas = document.createElement("canvas");
    canvas.width = 1080;
    canvas.height = 1440;
    var ctx = canvas.getContext("2d");
    var font = '"PingFang SC","Microsoft YaHei","Noto Sans SC",sans-serif';
    var bg = ctx.createLinearGradient(0, 0, 1080, 1440);
    bg.addColorStop(0, "#0d2a33");
    bg.addColorStop(0.55, "#1b1d45");
    bg.addColorStop(1, "#2a1230");
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, 1080, 1440);
    ctx.fillStyle = "#e0c36a";
    ctx.font = "600 30px " + font;
    ctx.fillText("OOGLEX MUSIC · 流光播放器", 90, 110);

    var cover = null;
    var src = track.image || (album && !album.global ? album.cover : "");
    if (withCover && src && String(src).indexOf("idb:") !== 0) {
      var abs = new URL(src, location.href);
      cover = await loadImage(abs.href, abs.origin !== location.origin);
    }
    ctx.save();
    ctx.shadowColor = "rgba(0,0,0,.45)";
    ctx.shadowBlur = 60;
    ctx.shadowOffsetY = 24;
    roundRect(ctx, 180, 170, 720, 720, 44);
    ctx.fillStyle = "#16303a";
    ctx.fill();
    ctx.restore();
    ctx.save();
    roundRect(ctx, 180, 170, 720, 720, 44);
    ctx.clip();
    if (cover) {
      ctx.drawImage(cover, 180, 170, 720, 720);
    } else {
      var g = ctx.createRadialGradient(540, 530, 30, 540, 530, 420);
      g.addColorStop(0, "#2f7c86");
      g.addColorStop(1, "#141a3a");
      ctx.fillStyle = g;
      ctx.fillRect(180, 170, 720, 720);
      ctx.fillStyle = "rgba(255,255,255,.9)";
      ctx.font = "300 260px " + font;
      ctx.textAlign = "center";
      ctx.fillText("♪", 540, 620);
      ctx.textAlign = "left";
    }
    ctx.restore();

    ctx.fillStyle = "#ffffff";
    ctx.font = "800 64px " + font;
    var y = wrapText(ctx, track.title, 90, 1000, 900, 78, 2);
    ctx.fillStyle = "rgba(255,255,255,.75)";
    ctx.font = "400 36px " + font;
    wrapText(ctx, artistOf(track, album), 90, y + 6, 900, 46, 1);

    var qr = await loadImage("/apps/music-player/icons/qr-player.svg", false);
    roundRect(ctx, 90, 1180, 200, 200, 22);
    ctx.fillStyle = "#ffffff";
    ctx.fill();
    if (qr) {
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(qr, 100, 1190, 180, 180);
      ctx.imageSmoothingEnabled = true;
    }
    ctx.fillStyle = "#ffffff";
    ctx.font = "700 36px " + font;
    ctx.fillText("扫码打开流光播放器", 320, 1240);
    ctx.fillStyle = "rgba(255,255,255,.7)";
    ctx.font = "400 28px " + font;
    ctx.fillText("ooglex.com/apps/music-player", 320, 1290);
    ctx.font = "400 24px " + font;
    var credit = track.source === "Jamendo"
      ? "歌曲来自 Jamendo · " + (track.licenseName || licenseName(track.license)) + " · 艺人保留权利"
      : (album && album.license ? "演示样例 · " + album.license : "本站原创 · 流光");
    wrapText(ctx, credit, 320, 1340, 680, 32, 2);

    return new Promise(function (resolve, reject) {
      try {
        canvas.toBlob(function (b) { b ? resolve(b) : reject(new Error("blob")); }, "image/png");
      } catch (err) {
        reject(err);
      }
    });
  }

  async function makePoster() {
    if (share.busy) return;
    share.busy = true;
    setShareStatus("正在生成海报…");
    var blob = null;
    try {
      blob = await drawPoster(true);
    } catch (err) {
      // 外站封面不允许画进图片时，换成默认图案再画一次
      try { blob = await drawPoster(false); } catch (err2) { blob = null; }
    }
    share.busy = false;
    if (!blob) { setShareStatus("这个浏览器生成不了图片，请改用「复制链接」。"); return; }
    share.blob = blob;
    if (share.objectUrl) URL.revokeObjectURL(share.objectUrl);
    share.objectUrl = URL.createObjectURL(blob);
    $("share-poster").src = share.objectUrl;
    $("share-poster-box").hidden = false;
    var file = new File([blob], "liuguang-share.png", { type: "image/png" });
    $("share-poster-share").hidden = !(navigator.canShare && navigator.share && navigator.canShare({ files: [file] }));
    setShareStatus(inAppBrowser()
      ? "长按图片可保存到相册，再发布分享。"
      : "海报已生成，保存图片后即可发布分享。");
  }

  function savePoster() {
    if (!share.objectUrl) return;
    var a = document.createElement("a");
    a.href = share.objectUrl;
    // 文件名只用英文和数字：部分浏览器遇到中文文件名会退回成 "download"
    a.download = "liuguang-" + (favKey(share.album, share.track) || "song").replace(/[^A-Za-z0-9-]+/g, "-").slice(0, 60) + ".png";
    document.body.appendChild(a);
    a.click();
    a.remove();
  }

  async function sharePoster() {
    if (!share.blob) return;
    var file = new File([share.blob], "liuguang-share.png", { type: "image/png" });
    try {
      await navigator.share({ files: [file], title: share.track.title + " · 流光播放器", text: shareText(share.album, share.track) + " " + share.url });
    } catch (err) {
      if (err && err.name === "AbortError") return;
      setShareStatus("系统没能分享图片，请用「保存图片」。");
    }
  }

  function bindShareDialog() {
    var dlg = $("share-dlg");
    if (!dlg) return;
    $("share-close").addEventListener("click", closeShare);
    $("share-native").addEventListener("click", nativeShare);
    $("share-copy").addEventListener("click", copyShareLink);
    $("share-make").addEventListener("click", makePoster);
    $("share-poster-save").addEventListener("click", savePoster);
    $("share-poster-share").addEventListener("click", sharePoster);
    $("share-url").addEventListener("focus", function () { this.select(); });
    dlg.addEventListener("click", function (event) { if (event.target === dlg) closeShare(); });
    dlg.addEventListener("cancel", function (event) { event.preventDefault(); closeShare(); });
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
    if (route.name === "global" || route.name === "favorites" || route.name === "track") {
      if (route.name === "global") renderGlobal();
      else if (route.name === "track") renderSharedTrack(route.id);
      else renderFavorites();
      paintCurrent();
      scrollToView(route);
      return;
    }
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
    scrollToView(route);
  }

  function scrollToView(route) {
    if (!skipAlbumScroll && route.name !== "list") {
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
    if (by) by.textContent = track ? artistOf(track, album) + (track.source ? " · " + track.source : "") : "从专辑里点一首";
    var art = $("now-art");
    // 全球曲库每首自带封面，按曲目换；本站专辑仍用专辑封面。
    var artFrom = track && track.image ? { title: track.title, cover: track.image } : album;
    var artKey = (artFrom && artFrom.cover) || (album && album.id) || "";
    if (art && art.dataset.art !== artKey) {
      art.dataset.art = artKey;
      var spinning = art.classList.contains("is-spinning");
      art.textContent = "";
      art.appendChild(coverNode(artFrom || { title: "流" }, "cover sm"));
      if (spinning) art.classList.add("is-spinning");
    }
    var playing = !!(audio && ((!audio.paused && audio.src) || (wantsPlayback && (loadingSource || waitingOnline))));
    if (art) art.classList.toggle("is-spinning", playing);
    paintAmbient(artFrom && artFrom.cover);
    paintNowFav(track, album);
    var shareBtn = $("now-share");
    if (shareBtn) shareBtn.hidden = !(track && shareUrl(album, track));
    paintMini(track, album, artFrom, playing);
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
    paintSeek();
    if (track) document.title = track.title + " · 流光播放器";
    else document.title = "流光播放器 · Ooglex";
  }

  // 页面背景的流光：当前封面放大模糊。只用已经校验过的封面地址；本机草稿（idb:）不用。
  var ambientSrc = null;
  function paintAmbient(src) {
    var node = $("ambient");
    if (!node) return;
    var url = src && String(src).indexOf("idb:") !== 0 ? String(src) : "";
    if (url === ambientSrc) return;
    ambientSrc = url;
    var css = url ? "url(" + JSON.stringify(new URL(url, location.href).href) + ")" : "";
    node.style.backgroundImage = css;
    node.classList.toggle("is-on", !!url);
    document.documentElement.style.setProperty("--mp-cover", css || "none");
  }

  function paintMini(track, album, artFrom, playing) {
    var mini = $("mini");
    if (!mini) return;
    $("mini-title").textContent = track ? track.title : "";
    $("mini-artist").textContent = track ? artistOf(track, album) : "";
    var thumb = $("mini-thumb");
    var key = (artFrom && artFrom.cover) || "";
    if (thumb.dataset.src !== key) {
      thumb.dataset.src = key;
      thumb.textContent = "";
      thumb.appendChild(thumbNode(key && key.indexOf("idb:") !== 0 ? key : "", track ? track.title : ""));
    }
    var btn = $("mini-play");
    btn.textContent = "";
    btn.appendChild(icon(playing ? "pause" : "play"));
    btn.setAttribute("aria-label", playing ? "暂停" : "播放");
    state.miniHasTrack = !!track;
    updateMini();
  }

  // 只在窄屏、有曲目、主播放区滚出视野时出现。
  function updateMini() {
    var mini = $("mini");
    if (!mini) return;
    var show = !!state.miniHasTrack && !state.stageVisible && !state.full;
    mini.hidden = !show;
    document.body.classList.toggle("has-mini", show);
  }

  function paintCurrent() {
    var track = currentTrack();
    document.querySelectorAll(".track").forEach(function (node) {
      var on = !!(track && node.dataset.album === state.playingAlbumId && node.dataset.id === track.id);
      node.classList.toggle("is-current", on);
      node.classList.toggle("is-playing", on && !!audio && !audio.paused);
      var flag = node.querySelector(".flag");
      if (flag) flag.textContent = on ? (audio && !audio.paused ? "正在播放" : "已暂停") : "";
      if (on) node.setAttribute("aria-current", "true");
      else node.removeAttribute("aria-current");
    });
    paintTransport();
  }

  function resolveSrc(src) {
    if (String(src || "").indexOf("idb:") === 0) {
      if (!window.OoglexMusicStore) throw new Error("store");
      return window.OoglexMusicStore.getBlob(src.slice(4)).then(function (blob) {
        if (!blob) throw new Error("missing");
        return URL.createObjectURL(blob);
      });
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

  // 只有已装载的当前音源才能推进队列；换歌时立即停止旧音频。
  var playSeq = 0;
  var sourceSeq = -1;
  var playAttempt = 0;
  var loadingSource = false;
  var wantsPlayback = false;
  var waitingOnline = false;
  var failedTracks = {};
  var recoveryTimer = null;
  var resumePosition = 0;
  var lastProgress = -1;
  var nativeMedia = /\bOoglexMedia\/1\b/.test(navigator.userAgent || "");
  var BLOCKED_NOTICE = "点一下播放键即可开始播放。";

  function clearRecovery() {
    clearTimeout(recoveryTimer);
    recoveryTimer = null;
  }

  function sourceIsCurrent() {
    return !loadingSource && sourceSeq === playSeq && !!audio.src
      && (!audio.currentSrc || audio.currentSrc === audio.src);
  }

  function pausePlayback() {
    wantsPlayback = false;
    waitingOnline = false;
    ++playAttempt;
    clearRecovery();
    audio.pause();
    paintCurrent();
    syncPlayback();
  }

  function failTrack(message) {
    if (!wantsPlayback) return;
    clearRecovery();
    if (navigator.onLine === false) {
      resumePosition = audio.currentTime || 0;
      waitingOnline = true;
      // 保留用户的继续播放意图；不在断网期间遍历整份列表。
      audio.pause();
      setNotice("网络已中断，连接恢复后重试。也可以点暂停取消恢复。");
      paintCurrent();
      syncPlayback();
      return;
    }
    var album = currentAlbum();
    var n = album && album.tracks.length;
    failedTracks[state.index] = true;
    var candidates = [];
    for (var offset = 1; offset < n; offset++) {
      var i = (state.index + offset) % n;
      if (!state.shuffle && state.repeat !== "all" && i <= state.index) break;
      if (!failedTracks[i]) candidates.push(i);
    }
    if (state.repeat !== "one" && candidates.length) {
      var next = state.shuffle ? candidates[Math.floor(Math.random() * candidates.length)] : candidates[0];
      playIndex(album, next, { automatic: true, notice: message + " 已跳过这首。" });
      return;
    }
    pausePlayback();
    setNotice(message + " 当前队列没有可播放的后续曲目，请稍后重试或手动换歌。");
  }

  function armRecovery() {
    if (recoveryTimer || !wantsPlayback || waitingOnline) return;
    var seq = playSeq;
    recoveryTimer = setTimeout(function () {
      recoveryTimer = null;
      if (seq === playSeq && wantsPlayback) failTrack("音频加载超时。");
    }, 20000);
  }

  function tryPlay(seq) {
    if (seq === undefined) seq = playSeq;
    var attempt = ++playAttempt;
    wantsPlayback = true;
    waitingOnline = false;
    syncPlayback();
    armRecovery();
    var result;
    try { result = audio.play(); }
    catch (err) { result = Promise.reject(err); }
    return Promise.resolve(result).then(function () {
      if (seq !== playSeq || attempt !== playAttempt || !wantsPlayback) return false;
      syncPlayback();
      return true;
    }, function (err) {
      if (seq !== playSeq || attempt !== playAttempt || !wantsPlayback) return false;
      if (err && err.name === "NotAllowedError") {
        pausePlayback();
        setNotice(BLOCKED_NOTICE);
      } else if (err && err.name === "AbortError") {
        pausePlayback();
        setNotice("播放被中断，点播放可重试。");
      } else {
        failTrack(err && err.name === "NotSupportedError" ? "音频地址失效或格式不受支持。" : "音频未能播放。");
      }
      return false;
    });
  }

  async function playIndex(album, index, options) {
    if (!album || !album.tracks || !album.tracks.length) return;
    options = options || {};
    if (state.playingAlbumId !== album.id || state.queueAlbum !== album) state.history = [];
    if (!options.automatic) failedTracks = {};
    var n = album.tracks.length;
    var i = ((index % n) + n) % n;
    var track = album.tracks[i];
    var seq = ++playSeq;
    ++playAttempt;
    sourceSeq = -1;
    loadingSource = true;
    wantsPlayback = true;
    waitingOnline = false;
    clearRecovery();
    audio.pause();
    audio.removeAttribute("src");
    audio.load();
    if (state.objectUrl) URL.revokeObjectURL(state.objectUrl);
    state.objectUrl = "";
    state.queueAlbum = album;
    state.playingAlbumId = album.id;
    state.index = i;
    resumePosition = options.position || 0;
    setNotice(options.notice || "");
    setMediaSession(track, album);
    paintCurrent();
    syncPlayback();
    armRecovery();
    var url;
    try {
      // 普通 URL 不跨异步边界，保留浏览器手势与 ended 调用链。
      url = resolveSrc(track.src);
      if (url && typeof url.then === "function") url = await url;
    } catch (err) {
      if (seq !== playSeq) return;
      loadingSource = false;
      failTrack("这首音频无法读取。若是本机上传的曲目，请用「本机预览」打开，或先发行到仓库。");
      return;
    }
    if (seq !== playSeq) {
      if (url.indexOf("blob:") === 0) URL.revokeObjectURL(url);
      return;
    }
    state.objectUrl = url.indexOf("blob:") === 0 ? url : "";
    audio.src = url;
    audio.volume = state.volume;
    loadingSource = false;
    sourceSeq = seq;
    if (wantsPlayback && await tryPlay(seq)) announce("正在播放 " + track.title + "，" + artistOf(track, album));
    if (seq !== playSeq) return;
    paintCurrent();
    syncPlayback();
  }

  function playbackStatus() {
    if (!currentTrack() || !audio.src && !loadingSource) return "none";
    if (waitingOnline || !wantsPlayback) return "paused";
    if (loadingSource || audio.readyState < 3) return "buffering";
    return !audio.paused && !audio.ended ? "playing" : "paused";
  }

  // 原生只接收状态；系统操作仍回到本文件的同一播放器和队列。
  function syncPlayback() {
    var status = playbackStatus();
    var track = currentTrack();
    var album = currentAlbum();
    var duration = isFinite(audio.duration) ? audio.duration : (track && track.durationSec || 0);
    var position = audio.currentTime || 0;
    if (nativeMedia) {
      try {
        window.prompt("__ooglex_media_v1__", JSON.stringify({
          status: status, title: track && track.title || "", artist: artistOf(track, album),
          album: album && album.title || "", duration: duration, position: position,
          artwork: track && track.image || album && album.cover || ""
        }));
      } catch (err) { /* 旧外壳或页面销毁时不影响网页播放 */ }
      return;
    }
    if (!("mediaSession" in navigator)) return;
    try { navigator.mediaSession.playbackState = status === "playing" ? "playing" : status === "none" ? "none" : "paused"; } catch (err) { /* 不支持 */ }
    try {
      if (navigator.mediaSession.setPositionState) {
        if (duration > 0) navigator.mediaSession.setPositionState({ duration: duration,
          position: Math.max(0, Math.min(duration, position)), playbackRate: audio.playbackRate || 1 });
        else navigator.mediaSession.setPositionState();
      }
    } catch (err) { /* 流媒体时长可能未知 */ }
  }

  function mediaAction(action, value) {
    if (action === "play") {
      if (waitingOnline || audio.error || !audio.src && !loadingSource) {
        var album = currentAlbum() || firstPlayable();
        if (album) playIndex(album, Math.max(0, state.index));
      } else if (audio.paused && !loadingSource) tryPlay();
      else if (loadingSource) { wantsPlayback = true; syncPlayback(); }
    } else if (action === "pause") pausePlayback();
    else if (action === "next") step(1);
    else if (action === "previous") step(-1);
    else if (action === "seek" && isFinite(value) && isFinite(audio.duration)) {
      audio.currentTime = Math.max(0, Math.min(audio.duration, Number(value)));
      paintSeek(); syncPlayback();
    } else if (action === "nativeerror") {
      pausePlayback();
      setNotice("系统暂不允许后台媒体播放，请返回播放器后重试。");
    }
  }

  function setMediaSession(track, album) {
    try {
      if (nativeMedia || !("mediaSession" in navigator)) return;
      var art = [];
      var cover = track.image || album.cover;
      if (cover && cover.indexOf("idb:") !== 0) {
        art.push({ src: new URL(cover, location.href).href });
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
    if (wantsPlayback && (loadingSource || waitingOnline || !audio.paused)) pausePlayback();
    else mediaAction("play");
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


    var lastSync = 0;
    audio.addEventListener("timeupdate", function () {
      if (!sourceIsCurrent()) return;
      if (!state.seeking) paintSeek();
      if (audio.currentTime !== lastProgress) { lastProgress = audio.currentTime; clearRecovery(); }
      if (Date.now() - lastSync > 1000) { lastSync = Date.now(); syncPlayback(); }
    });
    audio.addEventListener("loadedmetadata", function () {
      if (!sourceIsCurrent()) return;
      if (resumePosition && isFinite(audio.duration)) audio.currentTime = Math.min(resumePosition, audio.duration);
      resumePosition = 0;
      paintSeek(); syncPlayback();
    });
    audio.addEventListener("durationchange", function () { paintSeek(); syncPlayback(); });
    audio.addEventListener("play", function () { paintCurrent(); syncPlayback(); });
    audio.addEventListener("playing", function () {
      if (!sourceIsCurrent() || audio.paused) return;
      clearRecovery();
      setNotice("");
      paintCurrent(); syncPlayback();
    });
    audio.addEventListener("pause", function () {
      if (sourceIsCurrent() && audio.paused && !audio.ended && !waitingOnline) {
        wantsPlayback = false; ++playAttempt; clearRecovery();
      }
      paintCurrent(); syncPlayback();
    });
    ["waiting", "stalled"].forEach(function (name) {
      audio.addEventListener(name, function () { if (sourceIsCurrent()) { armRecovery(); syncPlayback(); } });
    });
    audio.addEventListener("ended", function () {
      if (!sourceIsCurrent() || !audio.ended || !wantsPlayback) return;
      clearRecovery();
      failedTracks = {};
      var album = currentAlbum();
      if (!album || !album.tracks.length) { pausePlayback(); return; }
      if (state.repeat === "one") {
        audio.currentTime = 0;
        tryPlay();
        return;
      }
      var n = album.tracks.length;
      if (state.shuffle && n > 1) {
        state.history.push(state.index);
        if (state.history.length > 40) state.history.splice(0, state.history.length - 40);
        playIndex(album, randomIndex(n, state.index), { automatic: true });
      } else if (state.index < n - 1) playIndex(album, state.index + 1, { automatic: true });
      else if (state.repeat === "all") playIndex(album, 0, { automatic: true });
      else pausePlayback();
    });
    audio.addEventListener("error", function () {
      if (!sourceIsCurrent() || !audio.error) return;
      if (audio.error.code === 1) { pausePlayback(); setNotice("播放被中断，点播放可重试。"); return; }
      failTrack(audio.error.code === 2 ? "音频网络请求失败。" : audio.error.code === 3 ? "音频解码失败。" : "音频地址失效或格式不受支持。");
    });
    window.addEventListener("online", function () {
      if (waitingOnline && wantsPlayback) playIndex(currentAlbum(), state.index, { automatic: true, position: resumePosition });
    });
    document.addEventListener("visibilitychange", syncPlayback);
    window.addEventListener("pagehide", function () {
      pausePlayback();
      if (nativeMedia) window.prompt("__ooglex_media_v1__", '{"status":"none"}');
    });

    document.addEventListener("keydown", function (event) {
      var shareOpen = $("share-dlg") && $("share-dlg").open;
      if (state.full && !shareOpen && event.key === "Escape") { event.preventDefault(); closeFull(); return; }
      var tag = (event.target && event.target.tagName || "").toLowerCase();
      if (state.full && !shareOpen && tag !== "input" && (event.key === "ArrowDown" || event.key === "ArrowUp")) {
        event.preventDefault();
        swipeTo(event.key === "ArrowDown" ? 1 : -1);
        return;
      }
      if (tag === "input" || tag === "textarea" || tag === "select" || tag === "button" || tag === "a") return;
      if (event.key === " ") { event.preventDefault(); toggle(); }
      else if (event.key === "ArrowRight") { event.preventDefault(); nudge(5); }
      else if (event.key === "ArrowLeft") { event.preventDefault(); nudge(-5); }
    });

    if (nativeMedia) {
      window.OoglexMediaControl = mediaAction;
      window.addEventListener("ooglexmediaready", syncPlayback);
    } else if ("mediaSession" in navigator) {
      var actions = {
        play: function () { mediaAction("play"); }, pause: pausePlayback,
        previoustrack: function () { step(-1); }, nexttrack: function () { step(1); },
        seekto: function (details) { mediaAction("seek", details.seekTime); },
        seekbackward: function (details) { nudge(-(details.seekOffset || 5)); syncPlayback(); },
        seekforward: function (details) { nudge(details.seekOffset || 5); syncPlayback(); },
        stop: pausePlayback
      };
      Object.keys(actions).forEach(function (action) {
        try { navigator.mediaSession.setActionHandler(action, actions[action]); } catch (err) { /* 逐项降级 */ }
      });
    }
  }


  /* ---------------- 全屏播放：点迷你播放条打开；上滑下一首、下滑上一首；返回键或 ⌄ 收起 ---------------- */

  function openFull() {
    var stage = document.querySelector(".stage");
    if (!stage || state.full) return;
    state.full = true;
    stage.classList.add("is-full");
    stage.setAttribute("role", "dialog");
    stage.setAttribute("aria-modal", "true");
    stage.setAttribute("aria-label", "全屏播放");
    document.body.classList.add("mp-full");
    $("full-close").hidden = false;
    // 记一条历史，让手机的返回键 / 返回手势先收起全屏，而不是离开页面
    try { history.pushState({ mpFull: true }, ""); state.fullPushed = true; } catch (err) { state.fullPushed = false; }
    updateMini();
    try { $("full-close").focus({ preventScroll: true }); } catch (err) { /* 忽略 */ }
  }

  function closeFull(fromHistory) {
    var stage = document.querySelector(".stage");
    if (!stage || !state.full) return;
    state.full = false;
    stage.classList.remove("is-full", "is-dragging");
    stage.style.removeProperty("--swipe-y");
    stage.removeAttribute("role");
    stage.removeAttribute("aria-modal");
    stage.setAttribute("aria-label", "正在播放");
    document.body.classList.remove("mp-full");
    $("full-close").hidden = true;
    if (!fromHistory && state.fullPushed) {
      state.fullPushed = false;
      try { history.back(); } catch (err) { /* 忽略 */ }
    }
    state.fullPushed = false;
    updateMini();
    var back = $("mini-open");
    if (back && !$("mini").hidden) try { back.focus({ preventScroll: true }); } catch (err) { /* 忽略 */ }
  }

  // 切歌，并让唱片顺着手势方向滑走再回来
  function swipeTo(dir) {
    var stage = document.querySelector(".stage");
    if (!currentAlbum() && !firstPlayable()) return;
    step(dir);
    if (!stage || reduceMotion()) return;
    stage.classList.add("is-dragging");
    stage.style.setProperty("--swipe-y", (dir > 0 ? 60 : -60) + "px");
    // 两帧：先瞬移到起点，下一帧再打开过渡滑回原位
    requestAnimationFrame(function () {
      requestAnimationFrame(function () {
        stage.classList.remove("is-dragging");
        stage.style.setProperty("--swipe-y", "0px");
      });
    });
  }

  function bindFull() {
    var stage = document.querySelector(".stage");
    var close = $("full-close");
    if (!stage || !close) return;
    close.appendChild(icon("chevron-down"));
    close.addEventListener("click", function () { closeFull(); });
    window.addEventListener("popstate", function () { if (state.full) closeFull(true); });

    // 进度条、按钮、链接上开始的触摸不算切歌，免得拖进度时误切
    var start = null;
    function skip(target) { return !!(target && target.closest && target.closest("input, button, a, summary, dialog")); }
    stage.addEventListener("touchstart", function (event) {
      if (!state.full || event.touches.length !== 1 || skip(event.target)) { start = null; return; }
      var t = event.touches[0];
      start = { x: t.clientX, y: t.clientY, at: Date.now() };
      stage.classList.add("is-dragging");
    }, { passive: true });
    stage.addEventListener("touchmove", function (event) {
      if (!start || !state.full) return;
      var dy = event.touches[0].clientY - start.y;
      if (!reduceMotion()) stage.style.setProperty("--swipe-y", Math.max(-120, Math.min(120, dy * 0.4)) + "px");
    }, { passive: true });
    function end(event) {
      if (!start) return;
      var t = event.changedTouches && event.changedTouches[0];
      var dx = t ? t.clientX - start.x : 0;
      var dy = t ? t.clientY - start.y : 0;
      var quick = Date.now() - start.at < 900;
      start = null;
      stage.classList.remove("is-dragging");
      stage.style.setProperty("--swipe-y", "0px");
      if (quick && Math.abs(dy) > 60 && Math.abs(dy) > Math.abs(dx) * 1.5) swipeTo(dy < 0 ? 1 : -1);
    }
    stage.addEventListener("touchend", end);
    stage.addEventListener("touchcancel", function () {
      start = null;
      stage.classList.remove("is-dragging");
      stage.style.setProperty("--swipe-y", "0px");
    });
  }

  function bindMini() {
    var mini = $("mini");
    if (!mini) return;
    state.stageVisible = true;
    $("mini-play").addEventListener("click", toggle);
    var next = $("mini-next");
    next.appendChild(icon("next"));
    next.addEventListener("click", function () { step(1); });
    $("mini-open").addEventListener("click", openFull);
    var stage = document.querySelector(".stage");
    if (stage && "IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        // 主播放区还露出一小截时就算看得见，避免两套播控同时出现。
        state.stageVisible = entries[0].isIntersecting;
        updateMini();
      }, { threshold: 0.15 }).observe(stage);
    }
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
    view = $("view");
    live = $("live");
    try {
      // 以前存过的页内音量不再使用，免得有人调低后再也调不回来。
      localStorage.removeItem("ooglex.music-player.volume");
      var rawRepeat = localStorage.getItem("ooglex.music-player.repeat");
      if (rawRepeat === "all" || rawRepeat === "one" || rawRepeat === "off") state.repeat = rawRepeat;
      state.shuffle = localStorage.getItem("ooglex.music-player.shuffle") === "1";
    } catch (err) { /* 本机存储不可用时用默认设置 */ }
    audio.volume = state.volume;
    state.favs = loadFavs();
    bindTransport();
    bindMini();
    bindFull();
    var nowShare = $("now-share");
    if (nowShare) {
      nowShare.appendChild(icon("share"));
      nowShare.addEventListener("click", function () {
        var track = currentTrack();
        if (track) openShare(currentAlbum(), track);
      });
    }
    bindShareDialog();
    var nowFav = $("now-fav");
    if (nowFav) nowFav.addEventListener("click", function () {
      var track = currentTrack();
      if (track) toggleFav(currentAlbum(), track);
    });
    paintTransport();
    window.addEventListener("hashchange", onRoute);
    load();
    loadGlobalConfig();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();
