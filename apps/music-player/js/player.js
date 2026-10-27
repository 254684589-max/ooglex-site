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
    globalAlbums: {}
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
    return state.globalAlbums[id] || null;
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
    if (hash === "#/global") return { name: "global" };
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
      var li = h("li");
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
    var data = null;
    var code = "";
    // 依次试主地址和备用地址；只有连不上才换下一个，接口给出的 HTTP 错误照常显示。
    // 哪个地址成功过，本页之后先用它。
    var apis = g.config.apis && g.config.apis.length ? g.config.apis : [g.config.api];
    var order = apis.slice(g.apiIndex || 0).concat(apis.slice(0, g.apiIndex || 0));
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
      if (seq !== g.seq) return;
      if (reached) { g.apiIndex = apis.indexOf(order[t]); break; }
    }
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
    if (route.name === "global") {
      renderGlobal();
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
    if (!skipAlbumScroll && (route.name === "album" || route.name === "global")) {
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
    var playing = !!(audio && !audio.paused && audio.src);
    if (art) art.classList.toggle("is-spinning", playing);
    paintAmbient(artFrom && artFrom.cover);
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

  // 页面背景的流光：当前封面放大模糊。只用已经校验过的封面地址；本机草稿（idb:）不用。
  var ambientSrc = null;
  function paintAmbient(src) {
    var node = $("ambient");
    if (!node) return;
    var url = src && String(src).indexOf("idb:") !== 0 ? String(src) : "";
    if (url === ambientSrc) return;
    ambientSrc = url;
    node.style.backgroundImage = url ? "url(" + JSON.stringify(new URL(url, location.href).href) + ")" : "";
    node.classList.toggle("is-on", !!url);
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
    var show = !!state.miniHasTrack && !state.stageVisible;
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

  function bindMini() {
    var mini = $("mini");
    if (!mini) return;
    state.stageVisible = true;
    $("mini-play").addEventListener("click", toggle);
    var next = $("mini-next");
    next.appendChild(icon("next"));
    next.addEventListener("click", function () { step(1); });
    $("mini-open").addEventListener("click", function () {
      document.querySelector(".stage").scrollIntoView({ block: "start", behavior: reduceMotion() ? "auto" : "smooth" });
    });
    var stage = document.querySelector(".stage");
    if (stage && "IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        // 主播放区还露出一小截时就算看得见，避免两套播控同时出现。
        state.stageVisible = entries[0].isIntersecting;
        updateMini();
      }, { threshold: 0.15 }).observe(stage);
    }
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
    bindMini();
    paintTransport();
    window.addEventListener("hashchange", onRoute);
    load();
    loadGlobalConfig();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();
