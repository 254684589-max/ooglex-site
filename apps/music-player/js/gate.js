/* 管理页轻量口令门。做法对齐站内密码门：djb2 哈希比对，源码不写明文。
   初始口令见本目录 README。存储键只属于本播放器，不读写环球TV 的门。 */
(function (root) {
  "use strict";

  var KEY = "ooglex_music_admin_gate";
  var HASH = 3532735777;

  function hash(text) {
    var x = 5381;
    var s = String(text || "");
    for (var i = 0; i < s.length; i++) x = ((x << 5) + x + s.charCodeAt(i)) >>> 0;
    return x;
  }

  function open() {
    try { return root.localStorage.getItem(KEY) === "1"; }
    catch (err) { return false; }
  }

  function tryUnlock(pass) {
    if (hash(String(pass || "").trim()) !== HASH) return false;
    try { root.localStorage.setItem(KEY, "1"); } catch (err) { /* 会话内仍放行 */ }
    return true;
  }

  function lock() {
    try { root.localStorage.removeItem(KEY); } catch (err) { /* 忽略 */ }
  }

  root.OoglexMusicGate = { hash: hash, open: open, tryUnlock: tryUnlock, lock: lock };
})(typeof globalThis !== "undefined" ? globalThis : this);
