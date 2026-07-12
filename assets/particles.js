/* 共享背景动画：粒子星网（与主页同款）。
   任意页面加一行 <script src="…/assets/particles.js"></script> 即可：
   自动注入全屏 canvas（position:fixed · z-index:-1 · 不挡交互），
   随光标轻微聚拢，并尊重系统「减少动态」偏好。 */
(function () {
  function init() {
    if (!document.body || document.getElementById('bg-canvas')) return;
    var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    var c = document.createElement('canvas');
    c.id = 'bg-canvas';
    c.setAttribute('aria-hidden', 'true');
    c.style.cssText = 'position:fixed;inset:0;width:100%;height:100%;z-index:-1;pointer-events:none';
    document.body.insertBefore(c, document.body.firstChild);

    var x = c.getContext('2d'), w, h, dpr, pts, mouse = { x: -9999, y: -9999 };
    function resize() {
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      w = c.width = innerWidth * dpr; h = c.height = innerHeight * dpr;
      c.style.width = innerWidth + 'px'; c.style.height = innerHeight + 'px';
      var n = Math.max(30, Math.min(90, Math.floor(innerWidth * innerHeight / 16000)));
      pts = Array.from({ length: n }, function () {
        return {
          x: Math.random() * w, y: Math.random() * h,
          vx: (Math.random() - 0.5) * 0.22 * dpr, vy: (Math.random() - 0.5) * 0.22 * dpr,
          r: (Math.random() * 1.6 + 0.6) * dpr
        };
      });
    }
    function frame() {
      x.clearRect(0, 0, w, h);
      var link = 130 * dpr, mr = 150 * dpr;
      for (var i = 0; i < pts.length; i++) {
        var p = pts[i], mdx = mouse.x - p.x, mdy = mouse.y - p.y, md = Math.hypot(mdx, mdy);
        if (md < mr && md > 0.1) { p.vx += (mdx / md) * 0.012 * dpr; p.vy += (mdy / md) * 0.012 * dpr; }
        p.vx *= 0.99; p.vy *= 0.99; p.x += p.vx; p.y += p.vy;
        if (p.x < 0 || p.x > w) p.vx *= -1;
        if (p.y < 0 || p.y > h) p.vy *= -1;
      }
      for (var a = 0; a < pts.length; a++) {
        for (var b = a + 1; b < pts.length; b++) {
          var dx = pts[a].x - pts[b].x, dy = pts[a].y - pts[b].y, d = Math.hypot(dx, dy);
          if (d < link) {
            x.strokeStyle = 'rgba(124,150,255,' + (1 - d / link) * 0.45 + ')';
            x.lineWidth = dpr * 0.6;
            x.beginPath(); x.moveTo(pts[a].x, pts[a].y); x.lineTo(pts[b].x, pts[b].y); x.stroke();
          }
        }
      }
      for (var k = 0; k < pts.length; k++) {
        x.fillStyle = 'rgba(157,140,255,0.85)';
        x.beginPath(); x.arc(pts[k].x, pts[k].y, pts[k].r, 0, 6.2832); x.fill();
      }
      if (!reduce) requestAnimationFrame(frame);
    }
    addEventListener('resize', function () { resize(); if (reduce) frame(); }, { passive: true });
    if (!reduce) {
      addEventListener('mousemove', function (e) { mouse.x = e.clientX * dpr; mouse.y = e.clientY * dpr; }, { passive: true });
      addEventListener('mouseout', function () { mouse.x = mouse.y = -9999; }, { passive: true });
    }
    resize();
    frame();
  }
  if (document.body) init();
  else document.addEventListener('DOMContentLoaded', init);
})();
