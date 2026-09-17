/* Ooglex globe: same-origin startup policy + mainland fast path.
 *
 * 这是**源文件**，由 scripts/globe/patch-network.mjs 复制进构建产物
 * （apps/globe/app/network-policy.js）。**只改这里，不要改产物里的那份** ——
 * 曾经发生过：一次 119 行的 no-VPN 启动修复只写进了产物、没回写源文件，
 * 于是那份修复只活在构建产物里，任何人跑一次 build.sh 就会被静默还原。
 * build.sh 现在有一道自检会拦住这种漂移。
 */
(function () {
  'use strict';
  var script = document.currentScript;
  var base = new URL('./', script.src).href;
  var C = window.Cesium;
  var scene = null, ready = false, bootTimer = null, tileCount = 0;
  var english = new URLSearchParams(location.search).get('lang') === 'en';
  var localId = 'local-earth', previousMap = null;
  var overviewHeight = 22000000;
  var remoteEnabled = false;
  /* 本地基础底图是 Cesium 自带的 NaturalEarthII，maximumLevel 只有 2，在低空
   * 彻底失去细节。实测（旧金山上方，取画面中心 200×200 的唯一颜色数）：
   *   1344 km → 180 色   668 km → 80 色   263 km → 20 色
   *     32 km →   2 色   468 m  →  1 色（整屏一片纯绿，正是用户报的那个画面）
   * 所以下限取 500 公里，并且**只在本地底图生效**：换上真实影像后立刻放开，
   * 街景/驾驶舱/CCTV 地面投影照旧。刻意不做全局硬夹 —— 那会把有影像时的近景
   * 一起废掉，是之前踩过的坑。 */
  var LOCAL_FLOOR_M = 500000;
  var upstreamFloor = null;
  var floorNoticeShown = false;
  var hdAttempted = false;
  var nativeFetch = window.fetch ? window.fetch.bind(window) : null;
  var REMOTE_HOSTS = /(^|\.)(earthquake\.usgs\.gov|api\.adsb\.lol|overpass-api\.de|celestrak\.org|www\.celestrak\.org|ll\.thespacedevs\.com|services\.arcgisonline\.com|tile\.openstreetmap\.org)$/i;

  function words(zh, en) { return english ? en : zh; }
  function sameOrigin(input) {
    try {
      var u = new URL(typeof input === 'string' ? input : input.url, location.href);
      return u.origin === location.origin;
    } catch (_) { return true; }
  }
  function blockedRemote(input) {
    try {
      var u = new URL(typeof input === 'string' ? input : input.url, location.href);
      return u.origin !== location.origin && REMOTE_HOSTS.test(u.hostname);
    } catch (_) { return false; }
  }
  // Critical for mainland/no-VPN startup: known optional remote APIs must fail fast instead of
  // occupying browser connection slots for tens of seconds. Explicit map switching temporarily
  // enables remote traffic; local snapshots and every same-origin asset are always allowed.
  if (nativeFetch) {
    window.fetch = function (input, init) {
      if (!remoteEnabled && blockedRemote(input)) {
        return Promise.reject(new TypeError('Ooglex startup fast-path blocked optional remote request'));
      }
      return nativeFetch(input, init);
    };
  }

  function report(type, detail) {
    if (!document.documentElement) return;
    document.documentElement.dataset.globeState = type;
    if (window.parent !== window) window.parent.postMessage(
      { type: 'ooglex:globe', url: location.href.split('#')[0], state: type, detail: detail || '' }, location.origin);
  }
  function deadline(promise, ms, signal, onLate) {
    return new Promise(function (resolve, reject) {
      var done = false;
      function finish(fn, value) {
        if (done) return false;
        done = true;
        clearTimeout(timer);
        if (signal) signal.removeEventListener('abort', abort);
        fn(value);
        return true;
      }
      function abort() { finish(reject, new Error('Map request cancelled')); }
      var timer = setTimeout(function () {
        finish(reject, new Error(words('地图连接超时', 'Map request timed out')));
      }, ms);
      if (signal) {
        signal.addEventListener('abort', abort, { once: true });
        if (signal.aborted) abort();
      }
      Promise.resolve(promise).then(function (value) {
        if (!finish(resolve, value) && onLate) onLate(value);
      }, function (error) { finish(reject, error); });
    });
  }
  function dispose(value) {
    if (value && typeof value.destroy === 'function' && !value.isDestroyed?.()) value.destroy();
  }
  function boundedTiles(provider) {
    var original = provider.requestImage;
    provider.requestImage = function () {
      var result = original.apply(provider, arguments);
      return result === undefined ? undefined : deadline(result, 6500).then(function (image) {
        tileCount++;
        if (document.documentElement) document.documentElement.dataset.globeTiles = String(tileCount);
        return image;
      });
    };
    return provider;
  }

  function cameraFinite(viewer) {
    var p = viewer.camera.positionCartographic;
    return p && Number.isFinite(p.longitude) && Number.isFinite(p.latitude) && Number.isFinite(p.height);
  }
  function overview(viewer, keepCenter) {
    var position = viewer.camera.positionCartographic;
    var safe = cameraFinite(viewer);
    var lon = keepCenter && safe ? C.Math.toDegrees(position.longitude) : 105;
    var lat = keepCenter && safe ? C.Math.toDegrees(position.latitude) : 20;
    if (!Number.isFinite(lon) || Math.abs(lon) > 180) lon = 105;
    if (!Number.isFinite(lat) || Math.abs(lat) > 89) lat = 20;
    viewer.camera.cancelFlight();
    viewer.trackedEntity = undefined;
    viewer.camera.lookAtTransform(C.Matrix4.IDENTITY);
    viewer.camera.setView({
      destination: C.Cartesian3.fromDegrees(lon, lat, overviewHeight),
      orientation: { heading: 0, pitch: -C.Math.PI_OVER_TWO, roll: 0 }
    });
    viewer.scene.requestRender();
  }
  /* 相机守卫**只**负责一件事：把非有限（NaN/Infinity）的相机状态救回来。
   *
   * 早先这里还做了三件事，全部撤掉了 —— 它们为了掩盖「基础地球放大后发糊」
   * 而把导航打残，代价远大于收益：
   *   · maximumMovementRatio = 0.12（Cesium 默认 1.0）：每次滚轮只走到地表距离的
   *     12%，滚轮手感几乎是死的，用户的感受是「滚轮不是前进后退」。
   *   · minimumZoomDistance = 1200：最近只能到 1200 米，永远贴不到地面 ——
   *     而街景视角、驾驶舱、CCTV 地面投影恰恰是这个应用的看点。
   *   · height < 250 就弹回 22000 公里全球视角：任何一次接近地面都会被甩回太空。
   *
   * 「基础地球放大后发糊」是数据本身的性质：本地底图是 Cesium 自带的
   * NaturalEarthII，maximumLevel 只有 2。**糊是诚实的，弹回不是。** 需要细节就在
   * 应用自身的底图菜单里切到高清影像。
   */
  function installCameraGuard(viewer) {
    // 只保留一个上限，防止相机飞到地月之间；下限交给上游自己的设置。
    viewer.scene.screenSpaceCameraController.maximumZoomDistance = 65000000;
    var repairing = false;
    viewer.camera.changed.addEventListener(function () {
      if (repairing || viewer.isDestroyed()) return;
      if (cameraFinite(viewer)) {
        var c = viewer.scene.screenSpaceCameraController;
        if (c.minimumZoomDistance !== LOCAL_FLOOR_M) return;   // 已是真实影像，放开
        var h = viewer.camera.positionCartographic.height;
        /* minimumZoomDistance 在 Cesium 里**只约束用户输入**，不约束程序化的
         * flyTo / setView。应用自带的场景（例如「旧金山金门大桥」街景）会直接
         * 把相机飞到几百米高 —— 那正是用户看到「一片纯绿色球」的由来。
         * 所以这里补一道：本地底图下若相机已落到下限以下，抬回下限并说明原因，
         * 同时试一次高清影像；高清成功后下限解除，场景就能真正飞到街景。
         * 注意这不是之前那个「弹回太空」的守卫 —— 只抬到最低**有效**高度。 */
        if (h < LOCAL_FLOOR_M * 0.98) {
          repairing = true;
          try { liftToFloor(viewer); } finally { setTimeout(function () { repairing = false; }, 0); }
          noticeFloor();
        } else if (h < LOCAL_FLOOR_M * 1.08) {
          noticeFloor();
        }
        return;
      }
      repairing = true;
      try { overview(viewer, false); }
      finally { setTimeout(function () { repairing = false; }, 0); }
    });
  }
  function initialView(viewer) {
    var status = document.querySelector('#loading-screen .loader-status');
    if (status) status.textContent = words('正在显示全球地球…', 'Preparing global view...');
    installCameraGuard(viewer);
    applyZoomFloor(localId, viewer);
    overview(viewer, false);
    return function () { if (!viewer.isDestroyed()) viewer.camera.cancelFlight(); };
  }

  function makeRegistry(registry) {
    var flat = { id: 'ooglex-ellipsoid', create: function () {
      return { provider: new C.EllipsoidTerrainProvider() };
    }};
    var local = {
      descriptor: { id: localId, label: words('基础地球', 'Basic Earth'),
        shortLabel: words('基础', 'BASIC'), kind: 'local-earth', requiresIon: false },
      available: true,
      imagery: function (request) {
        return deadline(C.TileMapServiceImageryProvider.fromUrl(
          base + 'cesium/Assets/Textures/NaturalEarthII',
          { fileExtension: 'jpg', maximumLevel: 2, credit: new C.Credit('Made with Natural Earth', true) }
        ), 9000, request && request.signal, dispose).then(boundedTiles);
      },
      terrain: flat
    };
    registry.defaultId = localId;
    registry.unknownId = localId;
    registry.recoveryId = localId;
    registry.sources.forEach(function (source) {
      if (!source.imagery) return;
      if (!registry.state.hasCesiumIonToken) source.terrain = flat;
      var original = source.imagery;
      source.imagery = function (request) {
        remoteEnabled = true;
        return deadline(Promise.resolve().then(function () { return original(request); }),
          5500, request && request.signal, dispose).then(boundedTiles).finally(function () {
            setTimeout(function () { remoteEnabled = false; }, 500);
          });
      };
      delete source.constructionFallback;
      source.tileFailureFallback = { id: localId, threshold: 2,
        message: words('影像瓦片加载失败，已返回基础地球', 'Imagery tiles unavailable; using Basic Earth') };
    });
    registry.sources.unshift(local);
    return registry;
  }
  /** 取相机控制器。initialView 阶段 scene 还没赋值，所以允许直接传 viewer。 */
  function controllerOf(viewer) {
    var v = viewer || (scene && scene.viewer);
    return v && !v.isDestroyed() ? v.scene.screenSpaceCameraController : null;
  }
  /** 缩放下限跟着底图走：本地底图设 500 km，真实影像恢复上游自己的值。 */
  function applyZoomFloor(id, viewer) {
    var c = controllerOf(viewer);
    if (!c) return;
    if (upstreamFloor === null) upstreamFloor = c.minimumZoomDistance;
    var local = !id || id === localId;
    c.minimumZoomDistance = local ? LOCAL_FLOOR_M : upstreamFloor;
    if (!local) { floorNoticeShown = false; hdAttempted = false; }
  }
  /** 把相机抬到本地底图能显示的最低有效高度，保留当前经纬度与朝向。 */
  function liftToFloor(viewer) {
    var p = viewer.camera.positionCartographic;
    var lon = C.Math.toDegrees(p.longitude), lat = C.Math.toDegrees(p.latitude);
    if (!Number.isFinite(lon) || !Number.isFinite(lat)) { overview(viewer, false); return; }
    viewer.camera.cancelFlight();
    viewer.camera.setView({
      destination: C.Cartesian3.fromDegrees(lon, lat, LOCAL_FLOOR_M),
      orientation: { heading: viewer.camera.heading, pitch: -C.Math.PI_OVER_TWO, roll: 0 }
    });
    viewer.scene.requestRender();
  }
  /** 触到下限时说清原因，并自动试一次高清影像 —— 能连上的网络就不该被限制。 */
  function noticeFloor() {
    if (floorNoticeShown) return;
    floorNoticeShown = true;
    toast(words(
      '基础底图在更低的高度没有细节（本地数据层级上限）。正在尝试切换高清影像…',
      'The basic basemap has no detail below this altitude. Trying high-resolution imagery…'));
    if (hdAttempted || !scene || !scene.mapStackController) return;
    hdAttempted = true;
    remoteEnabled = true;
    scene.mapStackController.setStack('esri-imagery').then(function () {
      toast(words('已切换到高清影像，可以继续放大。', 'High-resolution imagery active; zoom freely.'));
    }).catch(function () {
      remoteEnabled = false;
      toast(words(
        '高清影像当前无法访问，已停在基础底图能显示的最低高度。',
        'High-resolution imagery is unreachable; holding the lowest altitude the basic basemap can show.'));
    });
  }
  /** 极简提示条：这条信息必须在应用内可见，不能只 postMessage 给父页面。 */
  function toast(text) {
    var el = document.getElementById('ooglex-globe-toast');
    if (!el) {
      el = document.createElement('div');
      el.id = 'ooglex-globe-toast';
      document.body.appendChild(el);
    }
    el.textContent = text;
    el.dataset.show = '';
    clearTimeout(toast._t);
    toast._t = setTimeout(function () { delete el.dataset.show; }, 6000);
  }
  function sourceState(state) {
    if (!state || !document.documentElement) return;
    var id = state.activeId;
    /* 回退到本地底图时，只把相机抬到**本地底图能显示的最低有效高度**，
     * 而不是一路拉回 22000 公里全球视角。原先无条件拉回太空，会让「自动试一次
     * 高清、失败后退回」表现成相机被凭空甩走 —— 和之前那个弹回守卫一样刺眼。
     * 已经在有效高度的相机一律不动。 */
    if (scene && id === localId && (previousMap !== localId || state.lastError)) {
      var h = scene.viewer.camera.positionCartographic.height;
      if (!(h >= LOCAL_FLOOR_M)) liftToFloor(scene.viewer);
    }
    previousMap = id;
    applyZoomFloor(id);
    remoteEnabled = id && id !== localId;
    document.documentElement.dataset.globeMap = id || localId;
    report(ready ? 'ready' : 'loading', {
      map: id, switching: state.status === 'switching',
      note: state.lastError || ''
    });
  }
  function fail(message) {
    if (ready) return;
    clearTimeout(bootTimer);
    report('error', message);
    document.getElementById('loading-screen')?.classList.remove('hidden');
    var status = document.querySelector('#loading-screen .loader-status');
    if (status) status.textContent = message;
    var host = document.querySelector('#loading-screen .loader-content');
    if (host && !host.querySelector('[data-globe-retry]')) {
      var retry = document.createElement('button');
      retry.type = 'button';
      retry.dataset.globeRetry = '';
      retry.textContent = words('重新加载', 'Retry');
      retry.addEventListener('click', function () { location.reload(); });
      host.appendChild(retry);
    }
  }
  function start(app) {
    remoteEnabled = false;
    return app.start().then(function (components) {
      scene = components.scene;
      installCameraGuard(scene.viewer);
      if (scene.mapStackController.getState().activeId === localId &&
          scene.viewer.camera.positionCartographic.height < 10000000) overview(scene.viewer, true);
      return new Promise(function (resolve, reject) {
        var timer, renderTick;
        var remove = scene.viewer.scene.postRender.addEventListener(function () {
          var screen = document.getElementById('loading-screen');
          var canvas = scene.viewer.canvas;
          if (!tileCount || !canvas.width || !canvas.height ||
              (screen && !screen.classList.contains('hidden'))) return;
          remove();
          clearTimeout(timer);
          clearInterval(renderTick);
          clearTimeout(bootTimer);
          ready = true;
          sourceState(scene.mapStackController.getState());
          resolve(components);
        });
        timer = setTimeout(function () {
          remove();
          clearInterval(renderTick);
          reject(new Error(words('基础地球加载超时，请重试', 'Basic Earth timed out; please retry')));
        }, 18000);
        renderTick = setInterval(function () { scene.viewer.scene.requestRender(); }, 120);
        scene.viewer.scene.requestRender();
      });
    }).catch(function (error) {
      fail(words('地球未能完成加载，请重试。', 'The globe could not finish loading. Please retry.'));
      throw error;
    });
  }
  window.addEventListener('gev:map-stack-changed', function (event) { sourceState(event.detail); });
  window.addEventListener('message', function (event) {
    if (event.origin !== location.origin || event.source !== window.parent || !scene || !ready) return;
    var data = event.data;
    if (data && data.type === 'ooglex:overview') { overview(scene.viewer, false); return; }
    if (!data || data.type !== 'ooglex:set-map' || ![localId, 'esri-imagery', 'osm'].includes(data.map)) return;
    remoteEnabled = data.map !== localId;
    scene.mapStackController.setStack(data.map).catch(function () {
      remoteEnabled = false;
      sourceState(scene.mapStackController.getState());
    });
  });
  function markIcons() {
    document.querySelectorAll('.material-symbols-outlined').forEach(function (node) {
      var name = node.textContent.trim();
      if (/^right_panel_(open|close)$/.test(name)) {
        if (node.dataset.localIcon !== name) node.dataset.localIcon = name;
      } else if (node.hasAttribute('data-local-icon')) node.removeAttribute('data-local-icon');
    });
  }
  function install() {
    markIcons();
    new MutationObserver(markIcons).observe(document.body, { subtree: true, childList: true, characterData: true });
    report('loading');
    bootTimer = setTimeout(function () {
      fail(words('加载时间过长，请检查网络后重试。', 'Loading is taking too long. Check your connection and retry.'));
    }, 26000);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', install, { once: true });
  else install();
  window.OoglexGlobeNetwork = Object.freeze({ registry: makeRegistry, start: start, initialView: initialView,
    viewState: function () { return scene ? { height: scene.viewer.camera.positionCartographic.height, map: scene.mapStackController.getState().activeId } : null; },
    /* 测试钩子：程序化把相机放到指定位置，等价于应用内场景的 flyTo/setView。
     * 与上面的 viewState 同性质（验证脚本已在用）。需要它是因为
     * minimumZoomDistance 只约束用户输入，不约束程序化移动 —— 而「场景飞到街景
     * 高度、本地底图变成一片纯色」正是这条路造成的，必须能被闸门覆盖。 */
    setView: function (lonDeg, latDeg, heightM) {
      if (!scene || scene.viewer.isDestroyed()) return false;
      scene.viewer.camera.cancelFlight();
      scene.viewer.camera.setView({
        destination: C.Cartesian3.fromDegrees(lonDeg, latDeg, heightM),
        orientation: { heading: 0, pitch: -C.Math.PI_OVER_TWO, roll: 0 }
      });
      scene.viewer.scene.requestRender();
      return true;
    } });
})();
