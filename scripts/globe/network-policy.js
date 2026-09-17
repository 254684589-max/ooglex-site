/* Ooglex globe: same-origin startup policy. Installed by patch-network.mjs. */
(function () {
  'use strict';
  var script = document.currentScript;
  var base = new URL('./', script.src).href;
  var C = window.Cesium;
  var scene = null, ready = false, bootTimer = null, tileCount = 0;
  var english = new URLSearchParams(location.search).get('lang') === 'en';
  var localId = 'local-earth', previousMap = null;
  var overviewHeight = 22000000;
  // Natural Earth stops at level 2: city/street views have no usable detail.
  var basicMinimumHeight = 5000000, cameraGuard = null;
  function installCameraGuard(viewer) {
    if (cameraGuard) return cameraGuard;
    var camera = viewer.camera, controller = viewer.scene.screenSpaceCameraController;
    var originalMinimum = controller.minimumZoomDistance;
    var originals = { setView: camera.setView, flyTo: camera.flyTo };
    function basic() {
      return (scene ? scene.mapStackController.getState().activeId : previousMap || localId) === localId;
    }
    function safeOptions(options) {
      if (!basic() || viewer.scene.mode !== C.SceneMode.SCENE3D) return options;
      var destination = options && options.destination;
      if (destination && destination.west !== undefined) destination = camera.getRectangleCameraCoordinates(destination);
      var position = C.Cartographic.fromCartesian(destination || camera.positionWC);
      if (!position || position.height >= basicMinimumHeight) return options;
      // Keep the requested place and callbacks, without rewriting saved shots.
      // Cesium destinations are world coordinates, even with an endTransform.
      return Object.assign({}, options, {
        destination: C.Cartesian3.fromRadians(position.longitude, position.latitude, basicMinimumHeight),
        orientation: { heading: options?.orientation?.heading || 0, pitch: -C.Math.PI_OVER_TWO, roll: 0 },
        endTransform: C.Matrix4.IDENTITY
      });
    }
    var wrappers = {};
    Object.keys(originals).forEach(function (method) {
      wrappers[method] = function (options) { return originals[method].call(this, safeOptions(options)); };
      camera[method] = wrappers[method];
    });
    function sync() {
      controller.minimumZoomDistance = basic() ? Math.max(originalMinimum, basicMinimumHeight) : originalMinimum;
    }
    // Wheel/pinch, tracked entities and lookAt can bypass flyTo/setView. Guard
    // before drawing as well; do not cancel flights or lose scene completion.
    var remove = viewer.scene.preRender.addEventListener(function () {
      sync();
      if (!basic() || viewer.scene.mode !== C.SceneMode.SCENE3D ||
          camera.positionCartographic.height >= basicMinimumHeight - 1) return;
      originals.setView.call(camera, safeOptions({ destination: camera.positionWC }));
    });
    sync();
    cameraGuard = { sync: sync, dispose: function () {
      remove();
      Object.keys(originals).forEach(function (method) {
        if (camera[method] === wrappers[method]) camera[method] = originals[method];
      });
      controller.minimumZoomDistance = originalMinimum;
      cameraGuard = null;
    }};
    return cameraGuard;
  }
  function overview(viewer, keepCenter) {
    var position = viewer.camera.positionCartographic;
    var lon = keepCenter ? C.Math.toDegrees(position.longitude) : 105;
    var lat = keepCenter ? C.Math.toDegrees(position.latitude) : 20;
    viewer.camera.cancelFlight();
    viewer.trackedEntity = undefined;
    viewer.camera.lookAtTransform(C.Matrix4.IDENTITY);
    viewer.camera.setView({
      destination: C.Cartesian3.fromDegrees(lon, lat, overviewHeight),
      orientation: { heading: 0, pitch: -C.Math.PI_OVER_TWO, roll: 0 }
    });
    viewer.scene.requestRender();
  }
  function initialView(viewer) {
    var guard = installCameraGuard(viewer);
    var status = document.querySelector('#loading-screen .loader-status');
    if (status) status.textContent = words('正在显示全球地球…', 'Preparing global view...');
    overview(viewer, false);
    return function () {
      guard.dispose();
      if (!viewer.isDestroyed()) viewer.camera.cancelFlight();
    };
  }
  function words(zh, en) { return english ? en : zh; }
  function report(type, detail) {
    if (!document.documentElement) return;
    document.documentElement.dataset.globeState = type;
    if (window.parent !== window) window.parent.postMessage(
      { type: 'ooglex:globe', url: location.href.split('#')[0], state: type, detail: detail || '' }, location.origin);
  }
  // Keep late completions owned by this request; never switch a map from here.
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
      // Cesium returns undefined when its scheduler is saturated: preserve that contract.
      return result === undefined ? undefined : deadline(result, 8000).then(function (image) {
        tileCount++;
        if (document.documentElement) document.documentElement.dataset.globeTiles = String(tileCount);
        return image;
      });
    };
    return provider;
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
        ), 12000, request && request.signal, dispose).then(boundedTiles);
      },
      terrain: flat
    };
    registry.defaultId = localId;
    registry.unknownId = localId;
    registry.recoveryId = localId;
    registry.sources.forEach(function (source) {
      if (!source.imagery) return;
      // No keyless external terrain endpoint participates in startup or map switches.
      if (!registry.state.hasCesiumIonToken) source.terrain = flat;
      var original = source.imagery;
      source.imagery = function (request) {
        return deadline(Promise.resolve().then(function () { return original(request); }),
          6000, request && request.signal, dispose).then(boundedTiles);
      };
      // Controller recoveryId handles construction errors and evicts failed cache entries.
      // A cached constructionFallback would make a later retry reuse the failed resolution.
      delete source.constructionFallback;
      source.tileFailureFallback = { id: localId, threshold: 2,
        message: words('影像瓦片加载失败，已返回基础地球', 'Imagery tiles unavailable; using Basic Earth') };
    });
    registry.sources.unshift(local);
    return registry;
  }
  function sourceState(state) {
    if (!state || !document.documentElement) return;
    var id = state.activeId;
    if (scene && id === localId && (previousMap !== localId || state.lastError) &&
        scene.viewer.camera.positionCartographic.height < 10000000) overview(scene.viewer, true);
    previousMap = id;
    if (cameraGuard) cameraGuard.sync();
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
    return app.start().then(function (components) {
      scene = components.scene;
      installCameraGuard(scene.viewer);
      if (scene.mapStackController.getState().activeId === localId &&
          scene.viewer.camera.positionCartographic.height < 10000000) overview(scene.viewer, true);
      // A defined Cesium global or iframe load event does not prove a rendered globe.
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
        }, 25000);
        renderTick = setInterval(function () { scene.viewer.scene.requestRender(); }, 100);
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
    scene.mapStackController.setStack(data.map).catch(function () {
      sourceState(scene.mapStackController.getState());
    });
  });
  // The two newer Symbols ligatures are rendered by local SVGs; keep their text intact.
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
    }, 35000);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', install, { once: true });
  else install();
  window.OoglexGlobeNetwork = Object.freeze({ registry: makeRegistry, start: start, initialView: initialView,
    viewState: function () { return scene ? { height: scene.viewer.camera.positionCartographic.height, map: scene.mapStackController.getState().activeId } : null; } });
})();
