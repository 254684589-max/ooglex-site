/* 共享背景音乐：用 Web Audio API 现场合成一段免版权的舒缓氛围循环 + 🔇 开关。
   任意页面加一行 <script src="…/assets/ambient.js"></script> 即可：
   若页面已有 #music-toggle（如主页导航里）则接管它，否则在右下角注入一个浮动小钮。
   浏览器禁止带声音自动播放，故默认静音，由访客点击用一次手势启动。 */
(function () {
  function init() {
    if (!document.body) return;
    if (!(window.AudioContext || window.webkitAudioContext)) return;
    if (window.__ambientInit) return; window.__ambientInit = true;

    var btn = document.getElementById('music-toggle');
    if (!btn) {
      var st = document.createElement('style');
      st.textContent =
        '#music-toggle.amb-float{position:fixed;right:18px;bottom:18px;z-index:60;width:42px;height:42px;' +
        'border-radius:50%;border:1px solid rgba(255,255,255,.16);background:rgba(20,24,40,.62);' +
        'backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px);color:#cfd6ea;font-size:18px;line-height:1;' +
        'cursor:pointer;display:flex;align-items:center;justify-content:center;' +
        'transition:transform .2s,border-color .2s,color .2s,box-shadow .2s}' +
        '#music-toggle.amb-float:hover{color:#fff;border-color:rgba(108,140,255,.55);transform:translateY(-2px)}' +
        '#music-toggle.amb-float.playing{color:#b79cff;border-color:rgba(157,108,255,.6);box-shadow:0 0 14px rgba(157,108,255,.35)}';
      document.head.appendChild(st);
      btn = document.createElement('button');
      btn.id = 'music-toggle'; btn.type = 'button'; btn.className = 'amb-float';
      btn.setAttribute('aria-label', '播放背景音乐');
      btn.title = '背景音乐 · 点击播放/静音';
      btn.textContent = '🔇';
      document.body.appendChild(btn);
    }

    var ctx, master, padGain, bellIn, started = false, playing = false, bellTimer;
    var PAD = [110, 164.81, 220, 277.18, 329.63];          // A2 E3 A3 C#4 E4 —— 温暖的 A 大调铺底
    var SHIMMER = [440, 554.37, 659.25, 880, 1108.73];     // A4 C#5 E5 A5 C#6 —— 五声点缀
    function build() {
      ctx = new (window.AudioContext || window.webkitAudioContext)();
      master = ctx.createGain(); master.gain.value = 0; master.connect(ctx.destination);
      var filt = ctx.createBiquadFilter(); filt.type = 'lowpass'; filt.frequency.value = 950; filt.Q.value = 0.5;
      padGain = ctx.createGain(); padGain.gain.value = 0.6;
      filt.connect(padGain); padGain.connect(master);
      PAD.forEach(function (f, i) {
        [-7, 7].forEach(function (det) {
          var o = ctx.createOscillator(); o.type = 'sine'; o.frequency.value = f; o.detune.value = det + i;
          var g = ctx.createGain(); g.gain.value = 0.11 / PAD.length;
          o.connect(g); g.connect(filt); o.start();
        });
      });
      var lfo = ctx.createOscillator(); lfo.frequency.value = 0.06;
      var lg = ctx.createGain(); lg.gain.value = 0.18;
      lfo.connect(lg); lg.connect(padGain.gain); lfo.start();
      var dl = ctx.createDelay(); dl.delayTime.value = 0.42;
      var fb = ctx.createGain(); fb.gain.value = 0.34;
      dl.connect(fb); fb.connect(dl); dl.connect(master);
      bellIn = ctx.createGain(); bellIn.connect(dl); bellIn.connect(master);
      started = true;
    }
    function shimmer() {
      if (!playing) return;
      var f = SHIMMER[Math.floor(Math.random() * SHIMMER.length)];
      var o = ctx.createOscillator(); o.type = 'sine'; o.frequency.value = f;
      var g = ctx.createGain(); g.gain.value = 0.0001;
      o.connect(g); g.connect(bellIn);
      var t = ctx.currentTime;
      g.gain.linearRampToValueAtTime(0.05, t + 0.7);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 4.5);
      o.start(t); o.stop(t + 5);
      bellTimer = setTimeout(shimmer, 5000 + Math.random() * 7000);
    }
    function play() {
      if (!started) build();
      ctx.resume();
      playing = true;
      master.gain.cancelScheduledValues(ctx.currentTime);
      master.gain.setValueAtTime(master.gain.value, ctx.currentTime);
      master.gain.linearRampToValueAtTime(0.14, ctx.currentTime + 2.5);
      btn.textContent = '🔊'; btn.classList.add('playing'); btn.setAttribute('aria-label', '静音背景音乐');
      bellTimer = setTimeout(shimmer, 3500);
    }
    function mute() {
      playing = false; clearTimeout(bellTimer);
      master.gain.cancelScheduledValues(ctx.currentTime);
      master.gain.setValueAtTime(master.gain.value, ctx.currentTime);
      master.gain.linearRampToValueAtTime(0, ctx.currentTime + 1.2);
      setTimeout(function () { if (!playing && ctx) ctx.suspend(); }, 1400);
      btn.textContent = '🔇'; btn.classList.remove('playing'); btn.setAttribute('aria-label', '播放背景音乐');
    }
    btn.addEventListener('click', function () { playing ? mute() : play(); });
  }
  if (document.body) init(); else document.addEventListener('DOMContentLoaded', init);
})();
