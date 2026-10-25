/* 把本机专辑发行到 GitHub，或打成待发布 zip。
   令牌只由调用方放在 sessionStorage，本文件不读取、不保存、不写进提交内容。 */
(function (root) {
  "use strict";

  var AUDIO_EXT = { mp3: 1, ogg: 1, wav: 1, m4a: 1, webm: 1 };
  var IMAGE_EXT = { svg: 1, png: 1, jpg: 1, webp: 1 };
  var MAX_AUDIO = 15 * 1024 * 1024;
  var MAX_COVER = 4 * 1024 * 1024;

  function extFor(mime, filename) {
    var map = {
      "image/svg+xml": "svg",
      "image/png": "png",
      "image/jpeg": "jpg",
      "image/webp": "webp",
      "audio/mpeg": "mp3",
      "audio/mp3": "mp3",
      "audio/wav": "wav",
      "audio/x-wav": "wav",
      "audio/wave": "wav",
      "audio/ogg": "ogg",
      "audio/mp4": "m4a",
      "audio/aac": "m4a",
      "audio/webm": "webm"
    };
    var clean = String(mime || "").toLowerCase().split(";")[0].trim();
    if (map[clean]) return map[clean];
    var name = String(filename || "");
    var dot = name.lastIndexOf(".");
    if (dot > 0) {
      var ext = name.slice(dot + 1).toLowerCase();
      if (ext === "jpeg") return "jpg";
      if (/^[a-z0-9]{2,4}$/.test(ext)) return ext;
    }
    return "";
  }

  function validSlug(id) {
    return /^[a-z0-9][a-z0-9-]{0,48}$/.test(String(id || ""));
  }

  function pad(n) {
    return (n < 10 ? "0" : "") + n;
  }

  function nextFree(used, prefix, ext) {
    var n = 1;
    var name = "";
    do {
      name = prefix + "-" + pad(n) + "." + ext;
      n += 1;
    } while (used[name]);
    used[name] = true;
    return name;
  }

  function bytesToBase64(bytes) {
    var chunk = 8192;
    var parts = [];
    for (var i = 0; i < bytes.length; i += chunk) {
      var slice = bytes.subarray(i, Math.min(i + chunk, bytes.length));
      var arr = new Array(slice.length);
      for (var j = 0; j < slice.length; j++) arr[j] = slice[j];
      parts.push(String.fromCharCode.apply(null, arr));
    }
    return btoa(parts.join(""));
  }

  async function materializeCatalog(catalog, getBlob, opts) {
    opts = opts || {};
    if (!catalog || !Array.isArray(catalog.albums)) throw new Error("清单里没有专辑。");
    var sourceAlbums = catalog.albums.filter(function (album) {
      return opts.includeUnreleased || album.released !== false;
    });
    if (!sourceAlbums.length) throw new Error("没有勾选发行的专辑。");

    var albums = [];
    var files = [];
    for (var a = 0; a < sourceAlbums.length; a++) {
      var album = sourceAlbums[a];
      if (!validSlug(album.id)) throw new Error("专辑编号不合法：" + (album.id || ""));
      var title = String(album.title || "").trim();
      if (!title) throw new Error("有一张专辑还没写名称。");
      var tracksIn = Array.isArray(album.tracks) ? album.tracks : [];
      if (!tracksIn.length) throw new Error("《" + title + "》还没有曲目。");
      if (!album.demo && !String(album.note || "").trim()) {
        throw new Error("《" + title + "》请填写权利说明，确认是自创或已获授权。");
      }

      var used = {};
      tracksIn.forEach(function (tr) {
        var src = String(tr && tr.src || "");
        if (src.indexOf("/apps/music-player/media/") === 0) used[src.split("/").pop()] = true;
      });

      var tracks = [];
      for (var t = 0; t < tracksIn.length; t++) {
        var tr = tracksIn[t];
        if (!validSlug(tr.id)) throw new Error("《" + title + "》里有曲目编号不合法。");
        var trackTitle = String(tr.title || "").trim();
        if (!trackTitle) throw new Error("《" + title + "》里有曲目没写歌名。");
        var src = String(tr.src || "");
        var publicSrc = src;
        if (src.indexOf("idb:") === 0) {
          var packed = await getBlob(src.slice(4));
          if (!packed || !packed.bytes || !packed.bytes.length) throw new Error("找不到音频：" + trackTitle);
          if (packed.bytes.length > MAX_AUDIO) throw new Error("《" + trackTitle + "》超过 15MB，请先压短。");
          var ext = extFor(packed.mime || tr.mime, packed.filename || tr.fileName);
          if (!AUDIO_EXT[ext]) throw new Error("《" + trackTitle + "》不是支持的音频（mp3、ogg、wav、m4a、webm）。");
          var filename = nextFree(used, "track", ext);
          var rel = "apps/music-player/media/" + album.id + "/" + filename;
          files.push({ path: rel, bytes: packed.bytes });
          publicSrc = "/" + rel;
        } else if (src.indexOf("/apps/music-player/media/") !== 0) {
          throw new Error("《" + trackTitle + "》的音频不在本站媒体目录。");
        }
        var out = {
          id: tr.id,
          title: trackTitle,
          artist: String(tr.artist || album.artist || "").trim(),
          src: publicSrc
        };
        if (tr.durationSec && isFinite(Number(tr.durationSec))) out.durationSec = Math.round(Number(tr.durationSec));
        if (tr.isrc) out.isrc = String(tr.isrc);
        tracks.push(out);
      }

      var cover = String(album.cover || "");
      var publicCover = cover;
      if (cover.indexOf("idb:") === 0) {
        var coverPack = await getBlob(cover.slice(4));
        if (!coverPack || !coverPack.bytes || !coverPack.bytes.length) throw new Error("《" + title + "》的封面文件丢失了。");
        if (coverPack.bytes.length > MAX_COVER) throw new Error("《" + title + "》封面超过 4MB。");
        var coverExt = extFor(coverPack.mime || album.coverMime, coverPack.filename || album.coverName);
        if (!IMAGE_EXT[coverExt]) throw new Error("《" + title + "》封面请用 svg、png、jpg 或 webp。");
        var coverRel = "apps/music-player/media/" + album.id + "/cover." + coverExt;
        files.push({ path: coverRel, bytes: coverPack.bytes });
        publicCover = "/" + coverRel;
      } else if (cover && cover.indexOf("/apps/music-player/") !== 0) {
        throw new Error("《" + title + "》的封面不在本站目录。");
      }

      albums.push({
        id: album.id,
        title: title,
        artist: String(album.artist || "").trim(),
        cover: publicCover,
        released: true,
        releasedAt: String(album.releasedAt || "").trim(),
        demo: !!album.demo,
        license: String(album.license || "").trim(),
        licenseUrl: String(album.licenseUrl || "").trim(),
        note: String(album.note || "").trim(),
        tracks: tracks
      });
    }

    var now = new Date();
    var next = {
      version: 1,
      status: "ok",
      demo: albums.every(function (album) { return album.demo; }),
      frequency: "static",
      updatedAt: now.toISOString(),
      asOf: now.toISOString().slice(0, 10),
      source: catalog.source || "",
      sourceUrl: catalog.sourceUrl || "",
      license: catalog.license || "",
      licenseUrl: catalog.licenseUrl || "",
      note: String(catalog.note || "").trim(),
      albums: albums
    };
    var json = JSON.stringify(next, null, 2) + "\n";
    files.push({ path: "apps/music-player/data/catalog.json", bytes: new TextEncoder().encode(json) });
    return { catalog: next, files: files, json: json };
  }

  function crc32(bytes) {
    if (!crc32.table) {
      var table = new Uint32Array(256);
      for (var n = 0; n < 256; n++) {
        var c = n;
        for (var k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
        table[n] = c >>> 0;
      }
      crc32.table = table;
    }
    var crc = 0xFFFFFFFF;
    for (var i = 0; i < bytes.length; i++) crc = crc32.table[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  function u16(n) {
    var b = new Uint8Array(2);
    new DataView(b.buffer).setUint16(0, n, true);
    return b;
  }

  function u32(n) {
    var b = new Uint8Array(4);
    new DataView(b.buffer).setUint32(0, n >>> 0, true);
    return b;
  }

  function concat(parts) {
    var len = 0;
    for (var i = 0; i < parts.length; i++) len += parts[i].length;
    var out = new Uint8Array(len);
    var offset = 0;
    for (var j = 0; j < parts.length; j++) {
      out.set(parts[j], offset);
      offset += parts[j].length;
    }
    return out;
  }

  function dosStamp(date) {
    var d = date || new Date();
    var time = (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1);
    var day = ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate();
    return [time, day];
  }

  function buildZip(entries) {
    var stamp = dosStamp(new Date());
    var locals = [];
    var centrals = [];
    var offset = 0;
    entries.forEach(function (entry) {
      var name = new TextEncoder().encode(String(entry.path || "file").replace(/^\/+/, ""));
      var data = entry.bytes instanceof Uint8Array ? entry.bytes : new Uint8Array(entry.bytes || []);
      var crc = crc32(data);
      var local = concat([
        u32(0x04034b50), u16(20), u16(0x0800), u16(0), u16(stamp[0]), u16(stamp[1]),
        u32(crc), u32(data.length), u32(data.length), u16(name.length), u16(0), name, data
      ]);
      locals.push(local);
      centrals.push(concat([
        u32(0x02014b50), u16(20), u16(20), u16(0x0800), u16(0), u16(stamp[0]), u16(stamp[1]),
        u32(crc), u32(data.length), u32(data.length), u16(name.length), u16(0), u16(0),
        u16(0), u16(0), u32(0), u32(offset), name
      ]));
      offset += local.length;
    });
    var central = concat(centrals);
    var eocd = concat([
      u32(0x06054b50), u16(0), u16(0), u16(entries.length), u16(entries.length),
      u32(central.length), u32(offset), u16(0)
    ]);
    return concat(locals.concat([central, eocd]));
  }

  async function gh(token, method, path, body) {
    var res = await fetch("https://api.github.com" + path, {
      method: method,
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: "Bearer " + token,
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json"
      },
      body: body ? JSON.stringify(body) : undefined
    });
    var text = await res.text();
    var data = {};
    if (text) {
      try { data = JSON.parse(text); }
      catch (err) { data = { message: text.slice(0, 180) }; }
    }
    if (!res.ok) {
      var error = new Error(data && data.message ? data.message : ("HTTP " + res.status));
      error.status = res.status;
      throw error;
    }
    return data;
  }

  async function publishRelease(opts) {
    var token = String(opts.token || "");
    var owner = String(opts.owner || "").trim();
    var repo = String(opts.repo || "").trim();
    var branch = String(opts.branch || "").trim();
    var files = opts.files || [];
    if (!token) throw new Error("还没有 GitHub 令牌。");
    if (!/^[A-Za-z0-9_.-]+$/.test(owner) || !/^[A-Za-z0-9_.-]+$/.test(repo)) {
      throw new Error("用户名或仓库名不合法。");
    }
    if (!branch || !/^[A-Za-z0-9._/-]+$/.test(branch) || branch.indexOf("..") >= 0 || branch.charAt(0) === "/" || branch.charAt(branch.length - 1) === "/") {
      throw new Error("分支名不合法。");
    }
    if ((branch === "main" || branch === "master") && !opts.allowMain) {
      throw new Error("目标是生产分支。默认不要写入 main。若确实要写，请先勾选确认。");
    }
    if (!files.length) throw new Error("没有要提交的文件。");

    var refPath = branch.split("/").map(encodeURIComponent).join("/");
    var base = "/repos/" + encodeURIComponent(owner) + "/" + encodeURIComponent(repo);
    var progress = typeof opts.onProgress === "function" ? opts.onProgress : function () {};

    progress("正在读取分支");
    var ref = await gh(token, "GET", base + "/git/ref/heads/" + refPath);
    var parent = ref.object && ref.object.sha;
    if (!parent) throw new Error("没有读到分支顶端。");
    var parentCommit = await gh(token, "GET", base + "/git/commits/" + parent);
    var treeItems = [];
    for (var i = 0; i < files.length; i++) {
      progress("正在上传 " + (i + 1) + "/" + files.length + "：" + files[i].path);
      var blob = await gh(token, "POST", base + "/git/blobs", {
        content: bytesToBase64(files[i].bytes),
        encoding: "base64"
      });
      treeItems.push({ path: files[i].path, mode: "100644", type: "blob", sha: blob.sha });
    }
    progress("正在提交");
    var tree = await gh(token, "POST", base + "/git/trees", {
      base_tree: parentCommit.tree.sha,
      tree: treeItems
    });
    var commit = await gh(token, "POST", base + "/git/commits", {
      message: String(opts.message || "music-player: publish catalog").slice(0, 400),
      tree: tree.sha,
      parents: [parent]
    });
    await gh(token, "PATCH", base + "/git/refs/heads/" + refPath, { sha: commit.sha });
    return {
      sha: commit.sha,
      url: "https://github.com/" + owner + "/" + repo + "/commit/" + commit.sha
    };
  }

  root.OoglexMusicPublish = {
    extFor: extFor,
    validSlug: validSlug,
    bytesToBase64: bytesToBase64,
    materializeCatalog: materializeCatalog,
    buildZip: buildZip,
    crc32: crc32,
    publishRelease: publishRelease
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
