/* ===========================================================
   星瞳望远镜 StarPupil Telescope
   纯前端数码望远镜：光学+数码混合变焦、拍照、夜视、瞄准辅助
   =========================================================== */
(() => {
  'use strict';

  // ---------- DOM ----------
  const $ = (id) => document.getElementById(id);
  const welcome = $('welcome');
  const viewer  = $('viewer');
  const video   = $('video');
  const canvas  = $('snapCanvas');
  const startBtn = $('startBtn');
  const closeBtn = $('closeBtn');
  const fsBtn    = $('fsBtn');

  const zoomSlider = $('zoomSlider');
  const zoomInBtn  = $('zoomInBtn');
  const zoomOutBtn = $('zoomOutBtn');
  const zoomReadout = $('zoomReadout');
  const modeReadout = $('modeReadout');
  const quickZoom  = $('quickZoom');

  const shutterBtn = $('shutterBtn');
  const flash = $('flash');
  const toast = $('toast');

  const toolsBtn = $('toolsBtn');
  const toolsPanel = $('toolsPanel');
  const galleryBtn = $('galleryBtn');
  const galleryPanel = $('galleryPanel');
  const galleryClose = $('galleryClose');
  const galleryGrid = $('galleryGrid');
  const galleryEmpty = $('galleryEmpty');
  const lastThumb = $('lastThumb');

  const overlay = { grid: $('grid'), reticle: $('reticle'), level: $('level') };
  const compassEl = $('compass');

  const lightbox = $('lightbox');
  const lightboxImg = $('lightboxImg');
  const lightboxClose = $('lightboxClose');
  const downloadLink = $('downloadLink');
  const deleteShot = $('deleteShot');

  // 画质 sliders
  const fBrightness = $('brightness');
  const fContrast   = $('contrast');
  const fSharpen    = $('sharpen');
  const fWarmth     = $('warmth');

  // ---------- 状态 ----------
  let stream = null;
  let track = null;
  let caps = null;            // 摄像头能力
  let optZoomRange = null;    // {min,max,step} 硬件光学变焦
  let zoom = 1;               // 总倍率（界面显示）
  const MAX_ZOOM = 40;        // 总最大倍率上限
  let videoDevices = [];
  let curDeviceIdx = 0;
  let torchOn = false;
  let photos = [];           // {url, time}
  let activeShot = null;

  // ---------- 工具函数 ----------
  function showToast(msg, ms = 1800){
    toast.textContent = msg;
    toast.classList.remove('hidden');
    clearTimeout(showToast._t);
    showToast._t = setTimeout(() => toast.classList.add('hidden'), ms);
  }

  function vibrate(ms){ if (navigator.vibrate) try { navigator.vibrate(ms); } catch(_){} }

  // ---------- 启动摄像头 ----------
  async function listCameras(){
    try{
      const devices = await navigator.mediaDevices.enumerateDevices();
      videoDevices = devices.filter(d => d.kind === 'videoinput');
    }catch(_){ videoDevices = []; }
  }

  async function startCamera(deviceId){
    stopStream();
    const constraints = {
      audio:false,
      video: deviceId
        ? { deviceId:{ exact:deviceId }, width:{ideal:3840}, height:{ideal:2160} }
        : { facingMode:{ ideal:'environment' }, width:{ideal:3840}, height:{ideal:2160} }
    };
    try{
      stream = await navigator.mediaDevices.getUserMedia(constraints);
    }catch(err){
      // 回退到任意摄像头
      try{ stream = await navigator.mediaDevices.getUserMedia({video:true,audio:false}); }
      catch(e2){ throw err; }
    }
    video.srcObject = stream;
    await video.play().catch(()=>{});
    track = stream.getVideoTracks()[0];
    caps = track.getCapabilities ? track.getCapabilities() : {};
    setupOpticalZoom();
    setupTorchAvailability();
    await listCameras();
  }

  function stopStream(){
    if (stream){ stream.getTracks().forEach(t => t.stop()); stream = null; }
  }

  // ---------- 光学变焦能力 ----------
  function setupOpticalZoom(){
    optZoomRange = null;
    if (caps && 'zoom' in caps && caps.zoom && caps.zoom.max > caps.zoom.min){
      optZoomRange = { min:caps.zoom.min || 1, max:caps.zoom.max, step:caps.zoom.step || 0.1 };
    }
    // 总变焦上限 = 光学上限 ×（数码可再叠加），最高 MAX_ZOOM
    const optMax = optZoomRange ? optZoomRange.max : 1;
    const totalMax = Math.min(MAX_ZOOM, Math.max(optMax * 4, 8));
    zoomSlider.max = totalMax.toFixed(1);
    applyZoom(zoom);
  }

  /* 混合变焦：先用光学变焦顶满，再用 CSS 数码放大补足 */
  function applyZoom(z){
    z = Math.max(1, Math.min(z, parseFloat(zoomSlider.max)));
    zoom = z;
    let digital = z;
    let mode = '数码';

    if (optZoomRange && track){
      // 把界面倍率映射到光学范围内（1 → optMin，optMax → optMax）
      const optTarget = Math.min(optZoomRange.max, Math.max(optZoomRange.min, z));
      track.applyConstraints({ advanced:[{ zoom: optTarget }] }).catch(()=>{});
      // 剩余倍率用数码补
      digital = z / optTarget;
      mode = (optTarget > optZoomRange.min + 0.01)
        ? (digital > 1.02 ? '光学+数码' : '光学') : '数码';
    }

    video.style.transform = `scale(${digital.toFixed(3)})`;
    zoomReadout.textContent = z.toFixed(1) + '×';
    modeReadout.textContent = mode;
    if (zoomSlider.value !== String(z)) zoomSlider.value = z;
    updateQuickZoom(z);
  }

  function updateQuickZoom(z){
    [...quickZoom.children].forEach(b => {
      b.classList.toggle('active', Math.abs(parseFloat(b.dataset.z) - z) < 0.05);
    });
  }

  // ---------- 补光灯 / 手电 ----------
  function setupTorchAvailability(){
    const torchToggle = $('torchToggle');
    const hasTorch = caps && 'torch' in caps;
    torchToggle.classList.toggle('disabled', !hasTorch);
    torchOn = false;
    torchToggle.classList.remove('active');
  }

  async function toggleTorch(){
    const torchToggle = $('torchToggle');
    if (!(caps && 'torch' in caps)){ showToast('当前镜头不支持补光灯'); return; }
    torchOn = !torchOn;
    try{
      await track.applyConstraints({ advanced:[{ torch: torchOn }] });
      torchToggle.classList.toggle('active', torchOn);
    }catch(_){ showToast('补光灯切换失败'); torchOn = false; }
  }

  // ---------- 切换镜头 ----------
  async function switchCamera(){
    await listCameras();
    if (videoDevices.length < 2){ showToast('未检测到其它镜头'); return; }
    curDeviceIdx = (curDeviceIdx + 1) % videoDevices.length;
    try{
      await startCamera(videoDevices[curDeviceIdx].deviceId);
      zoom = 1; applyZoom(1);
      showToast('已切换镜头 ' + (curDeviceIdx + 1) + '/' + videoDevices.length);
    }catch(_){ showToast('切换镜头失败'); }
  }

  // ---------- 画质滤镜 ----------
  function applyFilters(){
    const b = fBrightness.value / 100;
    const c = fContrast.value / 100;
    const warmth = parseInt(fWarmth.value, 10);
    const sharpen = parseInt(fSharpen.value, 10);
    // 用 sepia 近似暖色，hue 微调；锐度用 contrast/saturate 轻微增强近似
    const sepia = warmth > 0 ? warmth / 100 : 0;
    const sat = 1 + (sharpen / 250) - (warmth < 0 ? warmth / 200 : 0);
    let filter = `brightness(${b}) contrast(${c + sharpen/400}) saturate(${sat.toFixed(2)})`;
    if (sepia > 0) filter += ` sepia(${sepia.toFixed(2)}) hue-rotate(-12deg)`;
    if (warmth < 0) filter += ` hue-rotate(${Math.round(warmth/4)}deg)`;
    video.dataset.filter = filter;
    video.style.filter = filter;
  }

  function applyPreset(name){
    const set = (el,v) => { el.value = v; };
    switch(name){
      case 'night':  set(fBrightness,180); set(fContrast,130); set(fSharpen,40); set(fWarmth,-20); break;
      case 'vivid':  set(fBrightness,108); set(fContrast,140); set(fSharpen,55); set(fWarmth,15); break;
      case 'mono':   set(fBrightness,105); set(fContrast,120); set(fSharpen,30); set(fWarmth,0);
                     applyFilters(); video.style.filter = video.dataset.filter + ' grayscale(1)';
                     video.dataset.filter = video.style.filter; return;
      case 'none':
      case 'reset':  set(fBrightness,100); set(fContrast,100); set(fSharpen,0); set(fWarmth,0); break;
    }
    applyFilters();
  }

  // ---------- 拍照 ----------
  function capture(){
    if (!video.videoWidth){ showToast('画面未就绪'); return; }
    shutterBtn.classList.add('busy');
    flash.classList.remove('fire'); void flash.offsetWidth; flash.classList.add('fire');
    vibrate(30);

    // 计算数码裁切区域（模拟变焦后的实际取景）
    const vw = video.videoWidth, vh = video.videoHeight;
    let digital = zoom;
    if (optZoomRange){
      const optTarget = Math.min(optZoomRange.max, Math.max(optZoomRange.min, zoom));
      digital = zoom / optTarget;     // 仅数码部分需要裁切，光学已在传感器层面放大
    }
    digital = Math.max(1, digital);
    const cw = vw / digital, ch = vh / digital;
    const sx = (vw - cw) / 2, sy = (vh - ch) / 2;

    canvas.width = cw; canvas.height = ch;
    const ctx = canvas.getContext('2d');
    ctx.filter = video.dataset.filter || 'none';
    ctx.drawImage(video, sx, sy, cw, ch, 0, 0, cw, ch);

    const url = canvas.toDataURL('image/jpeg', 0.92);
    const shot = { url, time: Date.now() };
    photos.unshift(shot);
    if (photos.length > 60) photos.pop();
    refreshThumb();
    renderGallery();
    setTimeout(() => shutterBtn.classList.remove('busy'), 250);
    showToast('已拍照 · 共 ' + photos.length + ' 张');
  }

  function fileName(t){
    const d = new Date(t);
    const p = n => String(n).padStart(2,'0');
    return `望远镜_${d.getFullYear()}${p(d.getMonth()+1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}.jpg`;
  }

  function refreshThumb(){
    if (photos.length){
      lastThumb.innerHTML = `<img src="${photos[0].url}" alt="最新照片">`;
    } else {
      lastThumb.innerHTML = `<span class="thumb-empty">相册</span>`;
    }
  }

  function renderGallery(){
    galleryGrid.innerHTML = '';
    galleryEmpty.style.display = photos.length ? 'none' : 'block';
    photos.forEach((p, i) => {
      const img = document.createElement('img');
      img.src = p.url; img.loading = 'lazy';
      img.addEventListener('click', () => openLightbox(i));
      galleryGrid.appendChild(img);
    });
  }

  // ---------- 灯箱 ----------
  function openLightbox(i){
    activeShot = i;
    const p = photos[i];
    lightboxImg.src = p.url;
    downloadLink.href = p.url;
    downloadLink.download = fileName(p.time);
    lightbox.classList.remove('hidden');
  }
  function closeLightbox(){ lightbox.classList.add('hidden'); activeShot = null; }
  function deleteCurrent(){
    if (activeShot == null) return;
    photos.splice(activeShot, 1);
    refreshThumb(); renderGallery(); closeLightbox();
    showToast('已删除');
  }

  // ---------- 叠加层开关 ----------
  function toggleTool(name, btn){
    if (name === 'torch'){ toggleTorch(); return; }
    if (name === 'cam'){ switchCamera(); return; }
    if (name === 'compass'){
      const on = compassEl.classList.toggle('hidden') === false;
      btn.classList.toggle('active', on);
      if (on) enableCompass();
      return;
    }
    const el = overlay[name];
    if (!el) return;
    const nowHidden = el.classList.toggle('hidden');
    btn.classList.toggle('active', !nowHidden);
    if (name === 'level' && !nowHidden) enableLevel();
  }

  // ---------- 罗盘 & 水平仪（设备方向）----------
  let orientHandler = null;
  function ensureOrientationPermission(){
    if (typeof DeviceOrientationEvent !== 'undefined' &&
        typeof DeviceOrientationEvent.requestPermission === 'function'){
      DeviceOrientationEvent.requestPermission().catch(()=>{});
    }
  }
  function enableCompass(){ ensureOrientationPermission(); bindOrientation(); }
  function enableLevel(){ ensureOrientationPermission(); bindOrientation(); }

  function bindOrientation(){
    if (orientHandler) return;
    orientHandler = (e) => {
      // 罗盘
      let heading = e.webkitCompassHeading;
      if (heading == null && e.alpha != null) heading = 360 - e.alpha;
      if (heading != null && !compassEl.classList.contains('hidden')){
        compassEl.textContent = '🧭 ' + Math.round(heading) + '° ' + dir(heading);
      }
      // 水平仪（左右倾斜 gamma）
      if (!overlay.level.classList.contains('hidden') && e.gamma != null){
        const g = Math.max(-45, Math.min(45, e.gamma));
        const pct = 50 + (g / 45) * 50;
        const bar = overlay.level.querySelector('i');
        bar.style.left = pct + '%';
        bar.style.background = Math.abs(g) < 3 ? 'var(--cyan)' : 'var(--amber)';
      }
    };
    window.addEventListener('deviceorientation', orientHandler, true);
  }
  function dir(h){
    const dirs = ['北','东北','东','东南','南','西南','西','西北'];
    return dirs[Math.round(h / 45) % 8];
  }

  // ---------- 手势：双指捏合变焦 + 双击 ----------
  function setupGestures(){
    let pinchStart = 0, zoomStart = 1;
    viewer.addEventListener('touchstart', (e) => {
      if (e.touches.length === 2){
        pinchStart = dist(e.touches);
        zoomStart = zoom;
      }
    }, { passive:true });
    viewer.addEventListener('touchmove', (e) => {
      if (e.touches.length === 2 && pinchStart){
        const ratio = dist(e.touches) / pinchStart;
        applyZoom(zoomStart * ratio);
        e.preventDefault();
      }
    }, { passive:false });
    viewer.addEventListener('touchend', () => { pinchStart = 0; });

    // 双击：在 1× 与 5× 之间切换
    let lastTap = 0;
    video.addEventListener('click', () => {
      const now = Date.now();
      if (now - lastTap < 300){ applyZoom(zoom < 3 ? 5 : 1); vibrate(15); }
      lastTap = now;
    });
  }
  function dist(t){
    const dx = t[0].clientX - t[1].clientX, dy = t[0].clientY - t[1].clientY;
    return Math.hypot(dx, dy);
  }

  // ---------- 全屏 ----------
  function toggleFullscreen(){
    if (!document.fullscreenElement){
      (document.documentElement.requestFullscreen || (()=>{})).call(document.documentElement);
    } else {
      document.exitFullscreen && document.exitFullscreen();
    }
  }

  // ---------- 退出 ----------
  function exitViewer(){
    stopStream();
    if (orientHandler){ window.removeEventListener('deviceorientation', orientHandler, true); orientHandler = null; }
    viewer.classList.add('hidden');
    welcome.classList.remove('hidden');
  }

  // ---------- 事件绑定 ----------
  startBtn.addEventListener('click', async () => {
    startBtn.disabled = true;
    startBtn.innerHTML = '<span class="dot"></span> 正在启动…';
    try{
      ensureOrientationPermission();
      await startCamera();
      welcome.classList.add('hidden');
      viewer.classList.remove('hidden');
      applyZoom(1); applyFilters();
      showToast('双指捏合或拖动滑条变焦', 2600);
    }catch(err){
      showToast(cameraError(err), 4200);
    }finally{
      startBtn.disabled = false;
      startBtn.innerHTML = '<span class="dot"></span> 开启望远镜';
    }
  });

  function cameraError(err){
    const n = err && err.name;
    if (n === 'NotAllowedError') return '摄像头权限被拒绝，请在浏览器设置中允许后重试';
    if (n === 'NotFoundError')  return '未找到摄像头设备';
    if (n === 'NotReadableError') return '摄像头被其它应用占用，请关闭后重试';
    if (location.protocol === 'http:' && location.hostname !== 'localhost')
      return '需在 HTTPS 环境下使用摄像头（请用 https:// 打开）';
    return '无法启动摄像头：' + (err && err.message || '未知错误');
  }

  closeBtn.addEventListener('click', exitViewer);
  fsBtn.addEventListener('click', toggleFullscreen);

  zoomSlider.addEventListener('input', () => applyZoom(parseFloat(zoomSlider.value)));
  zoomInBtn.addEventListener('click',  () => { applyZoom(zoom + 0.5); vibrate(10); });
  zoomOutBtn.addEventListener('click', () => { applyZoom(zoom - 0.5); vibrate(10); });
  quickZoom.addEventListener('click', (e) => {
    const b = e.target.closest('button'); if (!b) return;
    applyZoom(parseFloat(b.dataset.z)); vibrate(12);
  });

  shutterBtn.addEventListener('click', capture);

  toolsBtn.addEventListener('click', () => {
    galleryPanel.classList.add('hidden');
    toolsPanel.classList.toggle('hidden');
  });
  toolsPanel.addEventListener('click', (e) => {
    const t = e.target.closest('[data-tool]');
    if (t){ toggleTool(t.dataset.tool, t); return; }
    const p = e.target.closest('[data-preset]');
    if (p){ applyPreset(p.dataset.preset); }
  });
  [fBrightness, fContrast, fSharpen, fWarmth].forEach(s => s.addEventListener('input', applyFilters));

  galleryBtn.addEventListener('click', () => {
    toolsPanel.classList.add('hidden');
    renderGallery();
    galleryPanel.classList.toggle('hidden');
  });
  galleryClose.addEventListener('click', () => galleryPanel.classList.add('hidden'));

  lightboxClose.addEventListener('click', closeLightbox);
  deleteShot.addEventListener('click', deleteCurrent);
  lightbox.addEventListener('click', (e) => { if (e.target === lightbox) closeLightbox(); });

  setupGestures();

  // 点击空白关闭抽屉
  viewer.addEventListener('click', (e) => {
    if (!toolsPanel.classList.contains('hidden') &&
        !toolsPanel.contains(e.target) && !toolsBtn.contains(e.target)){
      toolsPanel.classList.add('hidden');
    }
  });

  // 设备方向变化时保持取景填充
  window.addEventListener('orientationchange', () => setTimeout(()=>applyZoom(zoom), 300));

  // 不支持 getUserMedia 时提示
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia){
    startBtn.addEventListener('click', () =>
      showToast('当前浏览器不支持摄像头，请用 Chrome / Safari 打开', 4000), true);
  }
})();
