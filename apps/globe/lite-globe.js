/* Dependency-free Natural Earth globe. A usable map while the full viewer loads.
   Texture: the same public-domain NaturalEarthII tiles shipped with Cesium. */
(function () {
  'use strict';
  var canvas = document.getElementById('lite-canvas');
  var host = document.getElementById('lite-earth');
  var status = document.getElementById('lite-status');
  var ctx = canvas.getContext('2d', { alpha: false });
  var lon = 105 * Math.PI / 180, lat = 20 * Math.PI / 180, zoom = 1;
  var texture, frame = 0, dragging = null, visible = true, loading = false;
  var width = 0, height = 0, rays = [], pixels;
  var base = new URL('./app/cesium/Assets/Textures/NaturalEarthII/0/', document.currentScript.src);
  function words(zh, en) { return document.documentElement.lang.indexOf('en') === 0 ? en : zh; }
  function notify(state) {
    host.dataset.state = state;
    window.dispatchEvent(new CustomEvent('ooglex:lite-state', { detail: state }));
  }
  function schedule() { if (visible && !frame) frame = requestAnimationFrame(draw); }
  function resize() {
    var box = canvas.getBoundingClientRect();
    if (!box.width || !box.height) return;
    // Bound CPU work on phones and high-DPI screens; no idle animation loop.
    var scale = Math.min(1, (dragging ? 260 : 420) / Math.min(box.width, box.height));
    var w = Math.max(1, Math.round(box.width * scale)), h = Math.max(1, Math.round(box.height * scale));
    if (w === width && h === height && pixels) return;
    width = canvas.width = w; height = canvas.height = h;
    pixels = ctx.createImageData(w, h);
    rays = [];
    var radius = Math.min(w, h) * .43 * zoom;
    for (var y = 0; y < h; y++) for (var x = 0; x < w; x++) {
      var i = (y * w + x) * 4, nx = (x - w / 2) / radius, ny = (h / 2 - y) / radius;
      pixels.data[i] = 8; pixels.data[i + 1] = 11; pixels.data[i + 2] = 16; pixels.data[i + 3] = 255;
      if (nx * nx + ny * ny <= 1) rays.push([i, nx, ny, Math.sqrt(Math.max(0, 1 - nx * nx - ny * ny))]);
    }
  }
  function draw() {
    frame = 0;
    if (!ctx || !visible) return;
    resize();
    if (!texture || !pixels) return;
    var sin = Math.sin(lat), cos = Math.cos(lat), data = pixels.data;
    for (var n = 0; n < rays.length; n++) {
      var r = rays[n], phi = Math.asin(Math.max(-1, Math.min(1, r[2] * cos + r[3] * sin)));
      var lambda = lon + Math.atan2(r[1], r[3] * cos - r[2] * sin);
      var u = ((lambda / (2 * Math.PI) + .5) % 1 + 1) % 1;
      var v = Math.max(0, Math.min(.999999, .5 - phi / Math.PI));
      var j = (Math.floor(v * texture.height) * texture.width + Math.floor(u * texture.width)) * 4;
      var light = .64 + .36 * r[3];
      data[r[0]] = texture.data[j] * light;
      data[r[0] + 1] = texture.data[j + 1] * light;
      data[r[0] + 2] = texture.data[j + 2] * light;
    }
    ctx.putImageData(pixels, 0, 0);
    canvas.dataset.longitude = String(Math.round(lon * 180 / Math.PI));
    canvas.dataset.zoom = String(zoom);
    if (host.dataset.state !== 'ready') {
      status.textContent = words('拖动旋转 · 滚轮或按钮缩放', 'Drag to rotate · Scroll or use the zoom buttons');
      notify('ready');
    }
  }
  function imageAt(path) {
    return new Promise(function (resolve, reject) {
      var img = new Image(), timer = setTimeout(function () { img.onload = img.onerror = null; reject(new Error('tile timeout')); }, 20000);
      img.onload = function () { clearTimeout(timer); resolve(img); };
      img.onerror = function () { clearTimeout(timer); reject(new Error('tile unavailable')); };
      img.src = new URL(path, base).href;
    });
  }
  function load() {
    if (loading || texture) return;
    if (!ctx) { status.textContent = words('浏览器无法绘制地图，请尝试完整三维。', 'Canvas is unavailable. Try the full viewer.'); notify('error'); return; }
    loading = true; notify('loading');
    Promise.all([imageAt('0/0.jpg'), imageAt('1/0.jpg')]).then(function (images) {
      var atlas = document.createElement('canvas'); atlas.width = 512; atlas.height = 256;
      var painter = atlas.getContext('2d');
      images.forEach(function (img, i) { painter.drawImage(img, i * 256, 0, 256, 256); });
      texture = painter.getImageData(0, 0, 512, 256); schedule();
    }).catch(function () {
      status.textContent = words('基础底图未能下载，请点击重试。', 'The base map could not download. Please retry.');
      document.getElementById('lite-retry').hidden = false; notify('error');
    }).finally(function () { loading = false; });
  }
  function zoomBy(amount) { zoom = Math.max(.7, Math.min(2.5, zoom * amount)); pixels = null; schedule(); }
  function home() { lon = 105 * Math.PI / 180; lat = 20 * Math.PI / 180; zoom = 1; pixels = null; schedule(); }
  canvas.addEventListener('pointerdown', function (e) {
    if (dragging || e.button > 0) return;
    dragging = { id: e.pointerId, x: e.clientX, y: e.clientY };
    canvas.setPointerCapture(e.pointerId); canvas.focus({ preventScroll: true }); schedule();
  });
  canvas.addEventListener('pointermove', function (e) {
    if (!dragging || e.pointerId !== dragging.id) return;
    lon -= (e.clientX - dragging.x) * .007 / zoom;
    lon = (lon + Math.PI * 3) % (Math.PI * 2) - Math.PI;
    lat = Math.max(-1.45, Math.min(1.45, lat + (e.clientY - dragging.y) * .007 / zoom));
    dragging.x = e.clientX; dragging.y = e.clientY; schedule();
  });
  function release(e) { if (dragging && dragging.id === e.pointerId) { dragging = null; schedule(); } }
  canvas.addEventListener('pointerup', release);
  canvas.addEventListener('pointercancel', release);
  canvas.addEventListener('lostpointercapture', release);
  canvas.addEventListener('wheel', function (e) { e.preventDefault(); zoomBy(Math.exp(-Math.max(-100, Math.min(100, e.deltaY)) * .0015)); }, { passive: false });
  canvas.addEventListener('keydown', function (e) {
    if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', '+', '=', '-', 'Home'].includes(e.key)) return;
    e.preventDefault();
    if (e.key === 'Home') home();
    else if (e.key === '+' || e.key === '=') zoomBy(1.15);
    else if (e.key === '-') zoomBy(1 / 1.15);
    else { lon += e.key === 'ArrowLeft' ? -.12 : e.key === 'ArrowRight' ? .12 : 0;
      lat = Math.max(-1.45, Math.min(1.45, lat + (e.key === 'ArrowUp' ? .12 : e.key === 'ArrowDown' ? -.12 : 0))); schedule(); }
  });
  document.getElementById('lite-in').addEventListener('click', function () { zoomBy(1.2); });
  document.getElementById('lite-out').addEventListener('click', function () { zoomBy(1 / 1.2); });
  document.getElementById('lite-retry').addEventListener('click', function () { this.hidden = true; load(); });
  window.addEventListener('resize', schedule);
  document.addEventListener('visibilitychange', function () { visible = !document.hidden && !host.hidden; if (visible) schedule(); });
  window.OoglexLiteGlobe = Object.freeze({ home: home, setVisible: function (value) {
    host.hidden = !value; visible = value && !document.hidden; if (visible) schedule();
  }});
  load();
})();
