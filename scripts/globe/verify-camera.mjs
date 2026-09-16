import assert from 'node:assert/strict';

const minimum = 5000000;
const project = { version: 3, scenes: [{ id: 'regression', title: 'Low altitude regression', shots: [
  { id: 'sf', title: 'Golden Gate 626 m', durationSec: 1, holdSec: .2,
    camera: { lon: -122.4783, lat: 37.8199, alt: 626, heading: 20, pitch: -35 },
    visual: { style: 'normal', bloom: { enabled: false }, hud: { visible: false } }, layers: {} },
  { id: 'tokyo', title: 'Tokyo 800 m', durationSec: 1, holdSec: .2,
    camera: { lon: 139.7, lat: 35.7, alt: 800, heading: 0, pitch: -45 },
    visual: { style: 'normal', bloom: { enabled: false }, hud: { visible: false } }, layers: {} }
] }] };

export async function verifyCameraNavigation({ open, verifyVisibleEarth, run }) {
  await run('saved low-altitude shots, scene playback and camera navigation stay visible', async () => {
    const s = await open(1280, 'hang', '/apps/globe/', project);
    try {
      const { frame, page } = s;
      await frame.evaluate(() => {
        const viewer = window.__globeTestViewer;
        window.__cameraEvidence = { min: Infinity, frames: 0 };
        viewer.scene.postRender.addEventListener(() => {
          const record = window.__cameraEvidence;
          record.min = Math.min(record.min, viewer.camera.positionCartographic.height);
          record.frames++;
        });
        const toggle = document.querySelector('[data-collapse-target="scene-panel"]');
        if (toggle?.getAttribute('aria-expanded') === 'false') toggle.click();
      });
      await frame.click('[data-scene-shot-id="sf"] .scene-shot-btn');
      await frame.waitForFunction(() => /Loaded:|已加载/.test(document.getElementById('scene-status').textContent), { timeout: 12000 });
      const shot = await frame.evaluate(() => {
        const c = window.__globeTestViewer.camera.positionCartographic;
        return { lon: Cesium.Math.toDegrees(c.longitude), lat: Cesium.Math.toDegrees(c.latitude), height: c.height };
      });
      assert(Math.abs(shot.lon + 122.4783) < .01 && Math.abs(shot.lat - 37.8199) < .01, 'Keep the requested location');
      assert(shot.height >= minimum - 1 && shot.height < minimum + 100);
      await verifyVisibleEarth(page, frame, 'golden-gate-shot');
      await frame.click('#scene-start-btn');
      await frame.waitForFunction(() => !document.getElementById('scene-stop-btn').disabled);
      await frame.waitForFunction(() => document.getElementById('scene-start-btn').disabled === false &&
        document.getElementById('scene-progress-fill').style.width === '100%', { timeout: 15000 });
      assert.match(await frame.$eval('#scene-status', el => el.textContent), /complete|完成/i);
      await verifyVisibleEarth(page, frame, 'scene-complete');
      assert.equal(await frame.evaluate(() => JSON.parse(localStorage.getItem('godsEyeView.sceneProject.v2')).scenes[0].shots[0].camera.alt), 626, 'Do not rewrite authored shot coordinates');

      const api = await frame.evaluate(async () => {
        const viewer = window.__globeTestViewer, camera = viewer.camera, C = Cesium;
        const destination = C.Cartesian3.fromDegrees(121.5, 31.2, 600);
        camera.setView({ destination, orientation: { heading: 0, pitch: -.5, roll: 0 } });
        const setHeight = camera.positionCartographic.height;
        const originalHeight = C.Cartographic.fromCartesian(destination).height;
        let completed = 0, cancelled = 0;
        await new Promise(resolve => {
          camera.flyTo({ destination: C.Cartesian3.fromDegrees(139.7, 35.7, 800), duration: .3,
            complete() { completed++; resolve(); }, cancel() { cancelled++; resolve(); } });
        });
        camera.flyToBoundingSphere(new C.BoundingSphere(C.Cartesian3.fromDegrees(139.7, 35.7, 0), 50), { duration: 0 });
        const sphereHeight = camera.positionCartographic.height;
        // lookAt bypasses setView/flyTo, as tracked entities and orbits do.
        camera.lookAt(C.Cartesian3.fromDegrees(139.7, 35.7, 0), new C.HeadingPitchRange(0, -1, 626));
        await new Promise(resolve => {
          const remove = viewer.scene.postRender.addEventListener(() => { remove(); resolve(); });
          viewer.scene.requestRender();
        });
        const lookHeight = camera.positionCartographic.height;
        camera.flyTo({ destination, duration: 5, cancel() { cancelled++; } });
        camera.cancelFlight();
        camera.setView({ destination: C.Rectangle.fromDegrees(139.69, 35.69, 139.71, 35.71) });
        return { setHeight, originalHeight, sphereHeight, lookHeight, rectangleHeight: camera.positionCartographic.height, completed, cancelled };
      });
      for (const key of ['setHeight', 'sphereHeight', 'lookHeight', 'rectangleHeight']) assert(api[key] >= minimum - 1, key);
      assert(Math.abs(api.originalHeight - 600) < .01, 'Caller-owned destinations must remain unchanged');
      assert.equal(api.completed, 1, 'Flight completion must fire exactly once');
      assert.equal(api.cancelled, 1, 'Flight cancellation must fire exactly once');
      const canvas = await frame.$('.cesium-widget canvas'), rect = await canvas.boundingBox();
      await page.mouse.move(rect.x + rect.width / 2, rect.y + rect.height / 2);
      for (let i = 0; i < 12; i++) {
        await page.mouse.wheel({ deltaY: -800 });
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      await verifyVisibleEarth(page, frame, 'after-zoom');
      const evidence = await frame.evaluate(() => window.__cameraEvidence);
      assert(evidence.frames > 20 && evidence.min >= minimum - 1, 'No rendered frame may return to street level in Basic Earth: ' + JSON.stringify(evidence));
      console.log('CAMERA NAVIGATION ' + JSON.stringify({ shot, api, evidence }));
      assert.deepEqual(s.errors, []);
    } finally { await s.context.close(); }
  });

  if (process.env.GLOBE_VERIFY_QUICK) return;
  await run('remote maps restore close zoom; failed tiles return to a safe local view', async () => {
    const s = await open(1280);
    try {
      await s.page.evaluate(() => document.querySelector('.stage iframe').contentWindow.postMessage(
        { type: 'ooglex:set-map', map: 'osm' }, location.origin));
      await s.frame.waitForFunction(() => document.documentElement.dataset.globeMap === 'osm');
      const remote = await s.frame.evaluate(() => {
        const viewer = window.__globeTestViewer;
        viewer.camera.setView({ destination: Cesium.Cartesian3.fromDegrees(139.7, 35.7, 626) });
        return { height: viewer.camera.positionCartographic.height, minimum: viewer.scene.screenSpaceCameraController.minimumZoomDistance };
      });
      assert(remote.height < 1000 && remote.minimum < minimum, 'Detailed maps must retain street-level navigation');
      await s.frame.waitForFunction(() => window.__globeTestViewer.scene.globe.tilesLoaded === false);
      // The stalled real tile requests now time out through the production policy.
      await s.frame.waitForFunction(() => document.documentElement.dataset.globeMap === 'local-earth', { timeout: 25000 });
      assert(s.external.length > 0, 'The remote provider must attempt actual tile requests');
      assert((await s.frame.evaluate(() => window.OoglexGlobeNetwork.viewState().height)) > 10000000);
      await verifyVisibleEarth(s.page, s.frame, 'remote-fallback');
      assert.deepEqual(s.errors, []);
    } finally { await s.context.close(); }
  });
}
