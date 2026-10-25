/* 站长页：编辑专辑草稿，本机预览，导出 zip，或用会话里的令牌提交到 GitHub。 */
(function () {
  "use strict";

  var PAT_KEY = "ooglex.music-player.pat";
  var catalog = null;
  var selectedId = "";
  var saveTimer = 0;
  var busy = false;

  function $(id) { return document.getElementById(id); }

  function h(tag, cls, text) {
    var node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text != null) node.textContent = text;
    return node;
  }

  function setStatus(text) {
    var node = $("status");
    if (node) node.textContent = text;
  }

  function selected() {
    if (!catalog) return null;
    for (var i = 0; i < catalog.albums.length; i++) {
      if (catalog.albums[i].id === selectedId) return catalog.albums[i];
    }
    return null;
  }

  function slug() {
    return "a" + Date.now().toString(36);
  }

  function trackSlug(index) {
    return ("t" + Date.now().toString(36) + index.toString(36)).replace(/[^a-z0-9]/g, "").slice(0, 24);
  }

  function scheduleSave() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveNow, 200);
  }

  function saveNow() {
    if (!catalog) return;
    catalog.note = $("catalog-note") ? $("catalog-note").value : catalog.note;
    try {
      var at = window.OoglexMusicStore.saveCatalog(catalog);
      setStatus("已保存到本机。" + at.replace("T", " ").slice(0, 19) + " UTC");
    } catch (err) {
      setStatus("本机保存失败。清单可能太大，或浏览器禁止了本地存储。");
    }
  }

  async function getPacked(key) {
    var blob = await window.OoglexMusicStore.getBlob(key);
    if (!blob) return null;
    return {
      bytes: new Uint8Array(await blob.arrayBuffer()),
      mime: blob.type || "",
      filename: blob.name || ""
    };
  }

  function readDuration(file) {
    return new Promise(function (resolve) {
      var url = URL.createObjectURL(file);
      var audio = document.createElement("audio");
      function done(value) {
        URL.revokeObjectURL(url);
        resolve(value);
      }
      audio.preload = "metadata";
      audio.onloadedmetadata = function () {
        done(isFinite(audio.duration) ? Math.round(audio.duration) : null);
      };
      audio.onerror = function () { done(null); };
      audio.src = url;
    });
  }

  function renderList() {
    var box = $("list");
    box.textContent = "";
    var add = h("button", "btn", "新建专辑");
    add.type = "button";
    add.addEventListener("click", createAlbum);
    box.appendChild(add);
    catalog.albums.forEach(function (album) {
      var btn = h("button", "album-btn" + (album.id === selectedId ? " is-on" : ""));
      btn.type = "button";
      var state = album.released === false ? "未发行" : "已发行";
      btn.textContent = (album.title || "未命名") + " · " + state + " · " + (album.tracks || []).length + " 首";
      btn.addEventListener("click", function () {
        selectedId = album.id;
        render();
      });
      box.appendChild(btn);
    });
  }

  function field(label, value, attrs) {
    var wrap = h("label", null, label);
    var input = document.createElement("input");
    input.type = attrs.type || "text";
    input.value = value == null ? "" : value;
    if (attrs.field) input.dataset.field = attrs.field;
    if (attrs.track) input.dataset.track = attrs.track;
    if (attrs.trackField) input.dataset.trackField = attrs.trackField;
    wrap.appendChild(input);
    return wrap;
  }

  function renderEditor() {
    var box = $("editor");
    box.textContent = "";
    var album = selected();
    if (!album) {
      box.appendChild(h("p", "help", "先新建一张专辑，或从左边点开已有的。"));
      return;
    }
    box.appendChild(h("h2", null, album.title || "未命名专辑"));
    box.appendChild(h("p", "file-name", "编号 " + album.id + "。发行后文件会放在 media/" + album.id + "/。"));
    var grid = h("div", "grid");
    grid.appendChild(field("专辑名称", album.title, { field: "title" }));
    grid.appendChild(field("艺人", album.artist, { field: "artist" }));
    grid.appendChild(field("发行日期", album.releasedAt, { field: "releasedAt", type: "date" }));
    grid.appendChild(field("许可", album.license, { field: "license" }));
    box.appendChild(grid);

    var released = h("label", "check");
    var releasedInput = document.createElement("input");
    releasedInput.type = "checkbox";
    releasedInput.dataset.field = "released";
    releasedInput.checked = album.released !== false;
    released.appendChild(releasedInput);
    released.appendChild(document.createTextNode("对访客发行（不勾选则只留在本机）"));
    box.appendChild(released);

    var demo = h("label", "check");
    var demoInput = document.createElement("input");
    demoInput.type = "checkbox";
    demoInput.dataset.field = "demo";
    demoInput.checked = !!album.demo;
    demo.appendChild(demoInput);
    demo.appendChild(document.createTextNode("这是免版税演示样例（自创专辑不要勾）"));
    box.appendChild(demo);

    var note = h("label", null, "权利与来源说明");
    var area = document.createElement("textarea");
    area.dataset.field = "note";
    area.value = album.note || "";
    area.placeholder = "自创，或已获授权。写清作者与许可。";
    note.appendChild(area);
    box.appendChild(note);

    var coverRow = h("div", "row-actions");
    var coverBtn = h("button", "btn", album.cover ? "更换封面" : "上传封面");
    coverBtn.type = "button";
    coverBtn.dataset.action = "cover";
    coverRow.appendChild(coverBtn);
    box.appendChild(coverRow);
    var preview = h("div");
    if (album.cover && album.cover.indexOf("idb:") === 0) {
      window.OoglexMusicStore.getBlob(album.cover.slice(4)).then(function (blob) {
        if (!blob) return;
        var img = h("img", "cover-preview");
        img.alt = "";
        img.src = URL.createObjectURL(blob);
        preview.appendChild(img);
      }).catch(function () {});
    } else if (album.cover) {
      var img = h("img", "cover-preview");
      img.alt = "";
      img.src = album.cover;
      preview.appendChild(img);
    }
    box.appendChild(preview);
    if (album.coverName) box.appendChild(h("p", "file-name", album.coverName));

    box.appendChild(h("h3", null, "曲目"));
    (album.tracks || []).forEach(function (track, index) {
      var card = h("article", "track-card");
      card.appendChild(h("h3", null, (index + 1) + ". " + (track.title || "未命名")));
      var g = h("div", "grid");
      g.appendChild(field("歌名", track.title, { track: track.id, trackField: "title" }));
      g.appendChild(field("艺人", track.artist, { track: track.id, trackField: "artist" }));
      var duration = field("时长（秒，可空）", track.durationSec || "", { track: track.id, trackField: "durationSec", type: "number" });
      g.appendChild(duration);
      card.appendChild(g);
      var where = track.src && track.src.indexOf("idb:") === 0
        ? ("本机文件" + (track.fileName ? "：" + track.fileName : ""))
        : ("已在仓库：" + (track.src || ""));
      card.appendChild(h("p", "file-name", where));
      var actions = h("div", "row-actions");
      function mini(text, action) {
        var b = h("button", "mini", text);
        b.type = "button";
        b.dataset.action = action;
        b.dataset.track = track.id;
        return b;
      }
      actions.appendChild(mini("上移", "up"));
      actions.appendChild(mini("下移", "down"));
      actions.appendChild(mini("更换音频", "replace"));
      actions.appendChild(mini("删除曲目", "remove-track"));
      card.appendChild(actions);
      box.appendChild(card);
    });

    var add = h("button", "btn", "添加曲目");
    add.type = "button";
    add.dataset.action = "add";
    var del = h("button", "btn warn", "删除这张专辑");
    del.type = "button";
    del.dataset.action = "remove-album";
    var bar = h("div", "actions");
    bar.appendChild(add);
    bar.appendChild(del);
    box.appendChild(bar);
  }

  function render() {
    if ($("catalog-note") && document.activeElement !== $("catalog-note")) {
      $("catalog-note").value = catalog.note || "";
    }
    renderList();
    renderEditor();
  }

  function createAlbum() {
    var album = {
      id: slug(),
      title: "未命名专辑",
      artist: "",
      cover: "",
      released: false,
      releasedAt: new Date().toISOString().slice(0, 10),
      demo: false,
      license: "",
      licenseUrl: "",
      note: "",
      tracks: []
    };
    catalog.albums.push(album);
    selectedId = album.id;
    scheduleSave();
    render();
  }

  function onInput(event) {
    var target = event.target;
    var album = selected();
    if (!album) return;
    if (target.dataset.field) {
      album[target.dataset.field] = target.type === "checkbox" ? target.checked : target.value;
      if (target.dataset.field === "title" || target.dataset.field === "released") renderList();
      scheduleSave();
      return;
    }
    if (target.dataset.track && target.dataset.trackField) {
      var track = findTrack(album, target.dataset.track);
      if (!track) return;
      if (target.dataset.trackField === "durationSec") {
        track.durationSec = target.value === "" ? null : Number(target.value);
      } else {
        track[target.dataset.trackField] = target.value;
      }
      scheduleSave();
    }
  }

  function findTrack(album, id) {
    for (var i = 0; i < album.tracks.length; i++) if (album.tracks[i].id === id) return album.tracks[i];
    return null;
  }

  function pickFiles(multiple, accept, done) {
    var input = document.createElement("input");
    input.type = "file";
    input.accept = accept;
    input.multiple = !!multiple;
    input.style.position = "fixed";
    input.style.left = "-9999px";
    document.body.appendChild(input);
    input.addEventListener("change", function () {
      var files = input.files;
      input.remove();
      done(files);
    });
    input.click();
  }

  async function addFiles(files) {
    var album = selected();
    if (!album || !files || !files.length) return;
    setStatus("正在读取音频…");
    for (var i = 0; i < files.length; i++) {
      var file = files[i];
      var id = trackSlug(i);
      var key = "track:" + album.id + ":" + id;
      await window.OoglexMusicStore.putBlob(key, file);
      album.tracks.push({
        id: id,
        title: String(file.name || "未命名").replace(/\.[^.]+$/, "") || "未命名",
        artist: album.artist || "",
        src: "idb:" + key,
        mime: file.type || "",
        fileName: file.name || "",
        durationSec: await readDuration(file)
      });
    }
    scheduleSave();
    render();
  }

  async function replaceTrack(trackId, file) {
    var album = selected();
    var track = album && findTrack(album, trackId);
    if (!track || !file) return;
    var key = track.src && track.src.indexOf("idb:") === 0 ? track.src.slice(4) : ("track:" + album.id + ":" + track.id);
    await window.OoglexMusicStore.putBlob(key, file);
    track.src = "idb:" + key;
    track.mime = file.type || "";
    track.fileName = file.name || "";
    track.durationSec = await readDuration(file);
    scheduleSave();
    render();
  }

  async function setCover(file) {
    var album = selected();
    if (!album || !file) return;
    var key = "cover:" + album.id;
    await window.OoglexMusicStore.putBlob(key, file);
    album.cover = "idb:" + key;
    album.coverMime = file.type || "";
    album.coverName = file.name || "";
    scheduleSave();
    render();
  }

  async function removeTrack(trackId) {
    var album = selected();
    if (!album) return;
    var next = [];
    for (var i = 0; i < album.tracks.length; i++) {
      var track = album.tracks[i];
      if (track.id !== trackId) { next.push(track); continue; }
      if (track.src && track.src.indexOf("idb:") === 0) {
        try { await window.OoglexMusicStore.deleteBlob(track.src.slice(4)); } catch (err) { /* 文件可能已经不在 */ }
      }
    }
    album.tracks = next;
    scheduleSave();
    render();
  }

  function move(trackId, dir) {
    var album = selected();
    if (!album) return;
    var index = -1;
    for (var i = 0; i < album.tracks.length; i++) if (album.tracks[i].id === trackId) index = i;
    var target = index + dir;
    if (index < 0 || target < 0 || target >= album.tracks.length) return;
    var item = album.tracks[index];
    album.tracks[index] = album.tracks[target];
    album.tracks[target] = item;
    scheduleSave();
    render();
  }

  async function removeAlbum() {
    var album = selected();
    if (!album) return;
    if (!window.confirm("删除《" + (album.title || album.id) + "》？已发行的专辑要再点一次发行，才会从公开清单里拿掉。仓库里的旧文件不会自动删除。")) return;
    var jobs = [];
    if (album.cover && album.cover.indexOf("idb:") === 0) jobs.push(window.OoglexMusicStore.deleteBlob(album.cover.slice(4)));
    (album.tracks || []).forEach(function (track) {
      if (track.src && track.src.indexOf("idb:") === 0) jobs.push(window.OoglexMusicStore.deleteBlob(track.src.slice(4)));
    });
    await Promise.all(jobs.map(function (job) { return job.catch(function () {}); }));
    catalog.albums = catalog.albums.filter(function (item) { return item.id !== album.id; });
    selectedId = catalog.albums.length ? catalog.albums[0].id : "";
    scheduleSave();
    render();
  }

  function onClick(event) {
    var button = event.target.closest("[data-action]");
    if (!button) return;
    var action = button.dataset.action;
    if (action === "add") {
      pickFiles(true, "audio/*,.mp3,.ogg,.wav,.m4a,.webm", addFiles);
    } else if (action === "cover") {
      pickFiles(false, "image/*,.svg", function (files) { if (files && files[0]) setCover(files[0]); });
    } else if (action === "replace") {
      pickFiles(false, "audio/*,.mp3,.ogg,.wav,.m4a,.webm", function (files) {
        if (files && files[0]) replaceTrack(button.dataset.track, files[0]);
      });
    } else if (action === "remove-track") {
      removeTrack(button.dataset.track);
    } else if (action === "up") {
      move(button.dataset.track, -1);
    } else if (action === "down") {
      move(button.dataset.track, 1);
    } else if (action === "remove-album") {
      removeAlbum();
    }
  }

  function tokenFromForm() {
    var typed = $("pat").value.trim();
    if (typed) {
      try { sessionStorage.setItem(PAT_KEY, typed); } catch (err) { /* 下面会直接用这次输入 */ }
      $("pat").value = "";
      return typed;
    }
    try { return sessionStorage.getItem(PAT_KEY) || ""; }
    catch (err) { return ""; }
  }

  function setBusy(on) {
    busy = on;
    ["publish", "export", "preview", "discard"].forEach(function (id) {
      var node = $(id);
      if (node) node.disabled = on;
    });
  }

  async function onExport() {
    if (busy) return;
    setBusy(true);
    try {
      saveNow();
      var result = await window.OoglexMusicPublish.materializeCatalog(catalog, getPacked);
      var guide = [
        "流光播放器 · 待发布包",
        "",
        "把 zip 解压到 ooglex-site 仓库根目录，路径已经按仓库结构放好：",
        "- apps/music-player/data/catalog.json",
        "- apps/music-player/media/<专辑编号>/…",
        "",
        "然后自己提交。未勾选「对访客发行」的专辑不在这个包里，仍留在本机。",
        "删除公开清单里的专辑不会自动删掉仓库中的旧音频。",
        "",
        "本次专辑："
      ];
      result.catalog.albums.forEach(function (album) {
        guide.push("- " + album.title + " (" + album.id + ") " + album.tracks.length + " 首");
      });
      var entries = result.files.concat([{
        path: "PUBLISH.txt",
        bytes: new TextEncoder().encode(guide.join("\n") + "\n")
      }]);
      var zip = window.OoglexMusicPublish.buildZip(entries);
      var url = URL.createObjectURL(new Blob([zip], { type: "application/zip" }));
      var link = h("a");
      link.href = url;
      link.download = "music-player-release.zip";
      document.body.appendChild(link);
      link.click();
      link.remove();
      setTimeout(function () { URL.revokeObjectURL(url); }, 4000);
      setStatus("已导出待发布包，里面是已勾选发行的专辑。");
    } catch (err) {
      setStatus(err && err.message ? err.message : "导出失败。");
    } finally {
      setBusy(false);
    }
  }

  async function onPublish() {
    if (busy) return;
    var owner = $("owner").value.trim();
    var repo = $("repo").value.trim();
    var branch = $("branch").value.trim();
    var token = tokenFromForm();
    if (!branch) {
      setStatus("请填写分支。不要把 main 当成默认目标。");
      return;
    }
    setBusy(true);
    try {
      saveNow();
      var result = await window.OoglexMusicPublish.materializeCatalog(catalog, getPacked);
      var titles = result.catalog.albums.map(function (album) { return album.title; }).join("、");
      if (!window.confirm("将把 " + result.catalog.albums.length + " 张已发行专辑提交到 " + owner + "/" + repo + " 的 " + branch + "。\n" + titles)) {
        setStatus("已取消发行。");
        return;
      }
      var published = await window.OoglexMusicPublish.publishRelease({
        token: token,
        owner: owner,
        repo: repo,
        branch: branch,
        allowMain: $("allow-main").checked,
        message: "music-player: publish " + titles,
        files: result.files,
        onProgress: setStatus
      });
      var unreleased = catalog.albums.filter(function (album) { return album.released === false; });
      catalog.albums = result.catalog.albums.concat(unreleased);
      catalog.note = result.catalog.note;
      catalog.updatedAt = result.catalog.updatedAt;
      catalog.demo = result.catalog.demo;
      catalog.source = result.catalog.source;
      catalog.sourceUrl = result.catalog.sourceUrl;
      catalog.license = result.catalog.license;
      catalog.licenseUrl = result.catalog.licenseUrl;
      saveNow();
      setStatus("已提交 " + published.sha.slice(0, 7) + "。" + published.url);
    } catch (err) {
      var message = err && err.message ? err.message : "发行失败。";
      if (err && err.status === 401) message = "GitHub 拒绝了这个令牌。请确认为细粒度 PAT，且对本仓库有 Contents 读写。";
      setStatus(message);
    } finally {
      setBusy(false);
    }
  }

  async function loadRemote() {
    var res = await fetch("/apps/music-player/data/catalog.json", { cache: "no-store" });
    if (!res.ok) throw new Error("清单没有加载成功（HTTP " + res.status + "）。");
    var data = await res.json();
    if (!data || !Array.isArray(data.albums)) throw new Error("清单格式不对。");
    return data;
  }

  async function boot() {
    try {
      var draft = window.OoglexMusicStore.loadCatalog();
      if (draft) {
        catalog = draft;
        setStatus("已恢复本机草稿。公开网站还是旧清单，直到你发行或手动提交。");
      } else {
        catalog = await loadRemote();
        setStatus("已载入已发布清单。之后的修改会另存在这台浏览器。");
      }
    } catch (err) {
      setStatus(err && err.message ? err.message : "清单没有加载成功。");
      catalog = { version: 1, note: "", albums: [] };
    }
    if (!selectedId && catalog.albums[0]) selectedId = catalog.albums[0].id;
    if ($("catalog-note")) $("catalog-note").value = catalog.note || "";
    render();
  }

  function openApp() {
    $("gate").hidden = true;
    $("app").hidden = false;
    boot();
  }

  function main() {
    var pass = $("gpass");
    var enter = function () {
      if (window.OoglexMusicGate.tryUnlock(pass.value)) openApp();
      else {
        $("gerr").textContent = "口令不对，请重试";
        pass.value = "";
        pass.focus();
      }
    };
    $("gbtn").addEventListener("click", enter);
    pass.addEventListener("keydown", function (event) { if (event.key === "Enter") enter(); });
    if (window.OoglexMusicGate.open()) openApp();
    else setTimeout(function () { try { pass.focus(); } catch (err) { /* 忽略 */ } }, 60);

    $("editor").addEventListener("input", onInput);
    $("editor").addEventListener("change", onInput);
    $("editor").addEventListener("click", onClick);
    $("catalog-note").addEventListener("input", function () {
      if (catalog) catalog.note = $("catalog-note").value;
      scheduleSave();
    });
    $("remember").addEventListener("click", function () {
      var value = $("pat").value.trim();
      if (!value) { setStatus("先把令牌填在上面。"); return; }
      try { sessionStorage.setItem(PAT_KEY, value); }
      catch (err) { setStatus("这台浏览器没有留下会话存储。发行时会改用刚才填的那一次。"); return; }
      $("pat").value = "";
      setStatus("令牌只留在本次会话。关掉这个标签页就会清掉，不会写入仓库。");
    });
    $("forget").addEventListener("click", function () {
      try { sessionStorage.removeItem(PAT_KEY); } catch (err) { /* 忽略 */ }
      $("pat").value = "";
      setStatus("已从本次会话清掉令牌。");
    });
    $("preview").addEventListener("click", function () {
      saveNow();
      window.open("/apps/music-player/?draft=1", "_blank", "noopener");
    });
    $("export").addEventListener("click", onExport);
    $("publish").addEventListener("click", onPublish);
    $("discard").addEventListener("click", async function () {
      if (!window.confirm("放弃这台浏览器里的草稿？已发布的专辑还在，本机上传的文件会从这台浏览器删掉。")) return;
      window.OoglexMusicStore.clearCatalog();
      try { await window.OoglexMusicStore.clearBlobs(); } catch (err) { /* 没有库也无妨 */ }
      location.reload();
    });
    $("lock").addEventListener("click", function () {
      window.OoglexMusicGate.lock();
      location.reload();
    });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();
