import nodeTest from 'node:test';
const test = (name, fn) => nodeTest(name, { timeout: 2000 }, fn);
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(process.env.PLAYER_SOURCE || 'apps/music-player/js/player.js', 'utf8');
function harness({ native = false, unsupported = '' } = {}) {
  const events = {}, windowEvents = {}, handlers = {}, notices = [];
  const nodes = new Map();
  const node = () => ({ textContent: '', hidden: false, dataset: {}, style: {},
    appendChild() {}, setAttribute() {}, removeAttribute() {}, addEventListener() {},
    classList: { add() {}, toggle() {}, contains() { return false; } }, querySelector() { return null; } });
  for (const id of ['play', 'prev', 'next', 'repeat', 'shuffle']) nodes.set(id, node());
  const audio = { src: '', currentSrc: '', paused: true, ended: false, error: null, currentTime: 0,
    duration: 28, readyState: 4, playbackRate: 1, volume: 1, plays: [],
    addEventListener(name, callback) { (events[name] ||= []).push(callback); },
    emit(name) { for (const callback of events[name] || []) callback(); },
    pause() { this.paused = true; this.emit('pause'); },
    removeAttribute() { this.src = ''; this.currentSrc = ''; }, load() { this.ended = false; this.error = null; },
    play() { this.plays.push(this.src); this.currentSrc = this.src; this.ended = false;
      if (this.reject) return Promise.reject(this.reject);
      this.paused = false; this.emit('play'); this.emit('playing'); return Promise.resolve(); }
  };
  const context = { console, URL, URLSearchParams, Promise, setTimeout, clearTimeout,
    navigator: { onLine: true, userAgent: native ? 'OoglexApp/1 OoglexMedia/1' : '',
      mediaSession: { setActionHandler(action, fn) { if (action === unsupported) throw Error('unsupported'); handlers[action] = fn; },
        setPositionState(value) { this.position = value; } } },
    MediaMetadata: function (values) { Object.assign(this, values); },
    localStorage: { setItem() {} }, location: { href: 'https://www.ooglex.com/apps/music-player/', hash: '' },
    document: { getElementById(id) { return nodes.get(id) || null; }, createElement: node,
      createElementNS: node, querySelectorAll() { return []; }, addEventListener() {}, title: '' },
    window: { addEventListener(name, fn) { windowEvents[name] = fn; },
      prompt(name, data) { notices.push(JSON.parse(data)); return 'ok'; } },
  };
  context.window.window = context.window;
  vm.createContext(context);
  const marker = '  if (document.readyState === "loading")';
  const instrumented = source.slice(0, source.lastIndexOf(marker)) + `
  audio = testAudio; seek = { addEventListener: function () {} };
  paintCurrent = function () {}; paintTransport = function () {}; paintSeek = function () {};
  setNotice = function (text) { state.notice = text || ""; };
  window.testPlayer = { state: state, playIndex: playIndex, toggle: toggle, step: step,
    currentTrack: currentTrack, bind: bindTransport, cue: cueTrack,
    sync: typeof syncPlayback === 'function' ? syncPlayback : function () {} };
})();`;
  context.testAudio = audio;
  vm.runInContext(instrumented, context);
  const p = context.window.testPlayer;
  p.bind();
  function album(n = 3, id = 'a') {
    const value = { id, title: id, tracks: Array.from({ length: n }, (_, i) => ({ id: String(i), title: 'Song ' + i, src: 'https://audio.example/' + i + '.mp3' })) };
    p.state.catalog = { albums: [value] }; return value;
  }
  function ended() { audio.paused = true; audio.ended = true; audio.currentSrc = audio.src; audio.emit('ended'); }
  return { p, audio, context, handlers, windowEvents, notices, events, album, ended };
}
const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };

test('旧音频 ended 不得改变正在异步解析的新曲目', async () => {
  const h = harness(), a = h.album();
  h.context.URL = class extends URL {};
  h.context.URL.createObjectURL = () => "blob:delayed";
  await h.p.playIndex(a, 0);
  let resolve;
  h.context.window.OoglexMusicStore = { getBlob: () => new Promise(r => { resolve = r; }) };
  a.tracks[1].src = 'idb:delayed';
  const pending = h.p.playIndex(a, 1);
  h.ended();
  assert.equal(h.p.state.index, 1);
  resolve({}); await pending;
});

test('顺序自然结束下一首，末尾停止', async () => {
  const h = harness(), a = h.album(); await h.p.playIndex(a, 0);
  h.ended(); await flush(); assert.equal(h.p.state.index, 1);
  h.ended(); await flush(); assert.equal(h.p.state.index, 2);
  h.ended(); await flush(); assert.equal(h.p.state.index, 2); assert.equal(h.audio.paused, true);
});

test('列表循环、单曲循环、单曲列表循环', async () => {
  const h = harness(), a = h.album(); h.p.state.repeat = 'all';
  await h.p.playIndex(a, 2); h.ended(); await flush(); assert.equal(h.p.state.index, 0);
  h.p.state.repeat = 'one'; await h.p.playIndex(a, 1); h.ended(); await flush();
  assert.equal(h.p.state.index, 1); assert.equal(h.audio.paused, false);
  const b = h.album(1, 'b'); h.p.state.repeat = 'all'; await h.p.playIndex(b, 0);
  h.ended(); await flush(); assert.equal(h.p.state.index, 0); assert.equal(h.audio.paused, false);
});

test('随机避开当前歌曲，上一首回历史，手动前后跨列表边界', async () => {
  const h = harness(), a = h.album(); h.p.state.shuffle = true; await h.p.playIndex(a, 1);
  h.ended(); await flush(); assert.notEqual(h.p.state.index, 1);
  h.p.step(-1); await flush(); assert.equal(h.p.state.index, 1);
  h.p.state.shuffle = false; await h.p.playIndex(a, 0); h.p.step(-1); await flush(); assert.equal(h.p.state.index, 2);
  h.p.step(1); await flush(); assert.equal(h.p.state.index, 0);
});

test('失效音频有界跳过，全部失效不会无限循环', async () => {
  const h = harness(), a = h.album(); h.p.state.repeat = 'all'; await h.p.playIndex(a, 0);
  for (let i = 0; i < 3; i++) { h.audio.error = { code: 4 }; h.audio.emit('error'); await flush(); }
  assert.equal(h.audio.plays.length, 3); assert.equal(h.audio.paused, true);
  assert.match(h.p.state.notice, /无法播放|没有可播放/);
});

test('权限与不支持格式错误分开，权限失败不得跳完整列表', async () => {
  const h = harness(), a = h.album(); h.audio.reject = { name: 'NotAllowedError' };
  await h.p.playIndex(a, 0); assert.match(h.p.state.notice, /点一下播放/); assert.equal(h.audio.plays.length, 1);
  h.audio.reject = { name: 'NotSupportedError' }; await h.p.playIndex(a, 0); await flush();
  assert.doesNotMatch(h.p.state.notice, /点一下播放/); assert.equal(h.audio.plays.length, 4);
});

test('单个不支持的媒体动作不能阻止后续动作注册', () => {
  const h = harness({ unsupported: 'previoustrack' }); assert.equal(typeof h.handlers.nexttrack, 'function');
});

test('十次异步切歌只加载最后请求并回收废弃 blob', async () => {
  const h = harness(), a = h.album(10), resolvers = [], revoked = [];
  h.context.URL = class extends URL {};
  h.context.URL.createObjectURL = () => 'blob:' + Math.random();
  h.context.URL.revokeObjectURL = u => revoked.push(u);
  h.context.window.OoglexMusicStore = { getBlob: () => new Promise(r => resolvers.push(r)) };
  a.tracks.forEach(t => { t.src = 'idb:' + t.id; });
  const requests = a.tracks.map((_, i) => h.p.playIndex(a, i));
  resolvers.reverse().forEach(r => r({})); await Promise.all(requests);
  assert.equal(h.p.state.index, 9); assert.equal(h.audio.plays.length, 1); assert.equal(revoked.length, 9);
});

test('异步切歌期间暂停不能被晚到的音源恢复', async () => {
  const h = harness(), a = h.album(); let resolve;
  h.context.URL = class extends URL {};
  h.context.URL.createObjectURL = () => 'blob:pause';
  h.context.window.OoglexMusicStore = { getBlob: () => new Promise(r => { resolve = r; }) };
  a.tracks[0].src = 'idb:pause'; const pending = h.p.playIndex(a, 0); h.p.toggle();
  resolve({}); await pending; assert.equal(h.audio.paused, true); assert.equal(h.audio.plays.length, 0);
});

test('旧 play rejection 不覆盖最新歌曲状态', async () => {
  const h = harness(), a = h.album(); let reject;
  const play = h.audio.play.bind(h.audio);
  h.audio.play = () => new Promise((_, r) => { reject = r; });
  const old = h.p.playIndex(a, 0); await flush(); h.audio.play = play;
  await h.p.playIndex(a, 1); reject({ name: 'NotAllowedError' }); await old;
  assert.equal(h.p.state.index, 1); assert.equal(h.p.state.notice, '');
});

test('断网错误等待联网，恢复同首；用户暂停取消恢复', async () => {
  const h = harness(), a = h.album(); await h.p.playIndex(a, 0); h.context.navigator.onLine = false;
  h.audio.error = { code: 2 }; h.audio.emit('error'); await flush();
  assert.equal(h.p.state.index, 0); assert.match(h.p.state.notice, /网络/);
  h.context.navigator.onLine = true; h.windowEvents.online(); await flush();
  assert.equal(h.audio.paused, false); assert.equal(h.p.state.index, 0);
  h.context.navigator.onLine = false; h.audio.error = { code: 2 }; h.audio.emit('error'); await flush();
  h.p.toggle(); h.context.navigator.onLine = true; h.windowEvents.online(); await flush(); assert.equal(h.audio.paused, true);
});

test('媒体动作播放/暂停/前后，metadata 和 playbackState 保持同步', async () => {
  const h = harness(), a = h.album(); a.tracks[0].album = 'Original album'; await h.p.playIndex(a, 0); h.p.sync();
  assert.equal(h.context.navigator.mediaSession.metadata.title, 'Song 0');
  assert.equal(h.context.navigator.mediaSession.metadata.album, 'Original album');
  assert.equal(h.context.navigator.mediaSession.playbackState, 'playing');
  h.handlers.pause(); h.p.sync(); assert.equal(h.audio.paused, true);
  assert.equal(h.context.navigator.mediaSession.playbackState, 'paused');
  h.handlers.play(); await flush(); h.handlers.nexttrack(); await flush(); assert.equal(h.p.state.index, 1);
  h.handlers.previoustrack(); await flush(); assert.equal(h.p.state.index, 0);
});

test('原生桥只传状态，系统命令复用同一队列且不注册第二套网页媒体会话', async () => {
  const h = harness({ native: true }), a = h.album(); await h.p.playIndex(a, 0); h.p.sync();
  assert.ok(h.notices.some(s => s.title === 'Song 0' && s.status === 'playing'));
  assert.equal(Object.keys(h.handlers).length, 0);
  h.context.window.OoglexMediaControl('next'); await flush(); assert.equal(h.p.state.index, 1);
  h.context.window.OoglexMediaControl('pause'); assert.equal(h.audio.paused, true);
});

test('同步 play 抛错也要分类处理，当前 AbortError 给出重试提示', async () => {
  const h = harness(), a = h.album();
  h.audio.play = () => { throw { name: 'NotAllowedError' }; };
  await h.p.playIndex(a, 0); assert.match(h.p.state.notice, /点一下播放/);
  h.audio.play = () => Promise.reject({ name: 'AbortError' });
  await h.p.playIndex(a, 0); assert.match(h.p.state.notice, /被中断/);
});

test('缓冲超时有界换歌，单曲循环的坏音源停止而不死循环', async () => {
  const h = harness(), a = h.album(); let timeout;
  h.context.setTimeout = fn => { timeout = fn; return 1; };
  h.context.clearTimeout = () => {};
  await h.p.playIndex(a, 0); h.audio.emit('stalled'); timeout(); await flush();
  assert.equal(h.p.state.index, 1);
  h.p.state.repeat = 'one'; h.audio.error = { code: 3 }; h.audio.emit('error'); await flush();
  assert.equal(h.p.state.index, 1); assert.equal(h.audio.paused, true); assert.match(h.p.state.notice, /解码/);
});

test('收藏页面替换展示对象不应修改正在播放的队列快照', async () => {
  const h = harness(), a = h.album(3, 'favorites'); h.p.state.globalAlbums.favorites = a;
  await h.p.playIndex(a, 1);
  h.p.state.catalog = { albums: [] };
  h.p.state.globalAlbums.favorites = { ...a, tracks: [a.tracks[0]] };
  assert.equal(h.p.currentTrack().title, 'Song 1');
  h.ended(); await flush(); assert.equal(h.p.currentTrack().title, 'Song 2');
});

test('切歌异步解析时路由 cue 不得改写播放状态', async () => {
  const h = harness(), a = h.album(), b = { id: 'other', tracks: [{ id: 'b', src: '/b' }] }; let resolve;
  h.context.URL = class extends URL {}; h.context.URL.createObjectURL = () => 'blob:cue';
  h.context.window.OoglexMusicStore = { getBlob: () => new Promise(r => { resolve = r; }) };
  a.tracks[0].src = 'idb:cue'; const pending = h.p.playIndex(a, 0);
  h.p.cue(b, 0); assert.equal(h.p.state.playingAlbumId, a.id);
  resolve({}); await pending;
});
