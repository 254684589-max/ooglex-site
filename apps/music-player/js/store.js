/* 本机草稿：清单放 localStorage（小 JSON），音频和封面放 IndexedDB。
   不写仓库，也不进别人的浏览器。 */
(function (root) {
  "use strict";

  var LS_KEY = "ooglex.music-player.draftCatalog";
  var DB_NAME = "ooglex-music-player";
  var STORE = "blobs";

  function openDb() {
    return new Promise(function (resolve, reject) {
      if (!root.indexedDB) {
        reject(new Error("这台浏览器没有 IndexedDB，不能暂存音频。"));
        return;
      }
      var req = root.indexedDB.open(DB_NAME, 1);
      req.onupgradeneeded = function () {
        var db = req.result;
        if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE);
      };
      req.onsuccess = function () { resolve(req.result); };
      req.onerror = function () { reject(req.error || new Error("打不开本机曲库")); };
    });
  }

  function withStore(mode, fn) {
    return openDb().then(function (db) {
      return new Promise(function (resolve, reject) {
        var tx = db.transaction(STORE, mode);
        var store = tx.objectStore(STORE);
        var result;
        try { result = fn(store); }
        catch (err) { reject(err); return; }
        tx.oncomplete = function () { resolve(result); };
        tx.onerror = function () { reject(tx.error || new Error("本机曲库写入失败")); };
        tx.onabort = function () { reject(tx.error || new Error("本机曲库已中止")); };
      });
    });
  }

  function loadCatalog() {
    try {
      var raw = root.localStorage.getItem(LS_KEY);
      if (!raw) return null;
      var data = JSON.parse(raw);
      if (!data || !Array.isArray(data.albums)) return null;
      return data;
    } catch (err) {
      return null;
    }
  }

  function saveCatalog(catalog) {
    var copy = JSON.parse(JSON.stringify(catalog));
    copy.savedAt = new Date().toISOString();
    var raw = JSON.stringify(copy);
    root.localStorage.setItem(LS_KEY, raw);
    return copy.savedAt;
  }

  function clearCatalog() {
    try { root.localStorage.removeItem(LS_KEY); } catch (err) { /* 忽略隐私模式 */ }
  }

  function putBlob(key, blob) {
    return withStore("readwrite", function (store) { store.put(blob, key); });
  }

  function getBlob(key) {
    return openDb().then(function (db) {
      return new Promise(function (resolve, reject) {
        var tx = db.transaction(STORE, "readonly");
        var req = tx.objectStore(STORE).get(key);
        req.onsuccess = function () { resolve(req.result || null); };
        req.onerror = function () { reject(req.error || new Error("读不到本机文件")); };
      });
    });
  }

  function deleteBlob(key) {
    return withStore("readwrite", function (store) { store.delete(key); });
  }

  function clearBlobs() {
    return withStore("readwrite", function (store) { store.clear(); });
  }

  root.OoglexMusicStore = {
    loadCatalog: loadCatalog,
    saveCatalog: saveCatalog,
    clearCatalog: clearCatalog,
    putBlob: putBlob,
    getBlob: getBlob,
    deleteBlob: deleteBlob,
    clearBlobs: clearBlobs
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
