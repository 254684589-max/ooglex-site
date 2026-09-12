/* ===========================================================================
   Ooglex 主题选择器 —— 全站共享
   ---------------------------------------------------------------------------
   · 主题写在 localStorage["ooglex.theme"]，同源下所有子页面自动沿用。
   · 首屏防闪：各页 <head> 里有一小段同步内联脚本先把 data-theme 打到 <html> 上，
     本文件只负责控件、切换与跨标签同步。
   · <html data-theme-lock="dark"> 的页面（3D 地球、游戏、仿真等由 canvas 主导的
     画面）固定深色显示，但主题选择照样记住并对其余页面生效。
   · 纯静态，无依赖，无网络请求。
   =========================================================================== */
(function () {
  "use strict";

  var KEY = "ooglex.theme";
  var DEFAULT = "dark";
  var THEMES = [
    { id: "dark",  zh: "深色",     en: "Dark",  sw: "ogx-sw-dark" },
    { id: "ft",    zh: "FT 纸色",  en: "Paper (FT)", sw: "ogx-sw-ft" },
    { id: "paper", zh: "亮白",     en: "Light", sw: "ogx-sw-paper" }
  ];
  var root = document.documentElement;
  var lock = root.getAttribute("data-theme-lock") || "";

  function valid(t) {
    for (var i = 0; i < THEMES.length; i++) if (THEMES[i].id === t) return t;
    return null;
  }
  function read() {
    try { return valid(localStorage.getItem(KEY)) || DEFAULT; } catch (e) { return DEFAULT; }
  }
  function write(t) {
    try { localStorage.setItem(KEY, t); } catch (e) {}
  }
  function meta(t) {
    for (var i = 0; i < THEMES.length; i++) if (THEMES[i].id === t) return THEMES[i];
    return THEMES[0];
  }
  /* 本页实际渲染用的主题：被锁定的页面永远按锁定值渲染 */
  function applied(chosen) { return lock ? lock : chosen; }

  function paint(chosen) {
    root.setAttribute("data-theme", applied(chosen));
    root.setAttribute("data-theme-choice", chosen);
    var bar = document.querySelector('meta[name="theme-color"]');
    var bgs = { dark: "#0b0e13", ft: "#fff1e5", paper: "#ffffff" };
    if (bar) bar.setAttribute("content", bgs[applied(chosen)] || bgs.dark);
    try {
      document.dispatchEvent(new CustomEvent("ooglex:themechange", {
        detail: { theme: applied(chosen), choice: chosen, locked: !!lock }
      }));
    } catch (e) {}
  }

  /* ═══ 浅色主题：站内脚本写进 inline style / SVG 属性的亮色值需要同相压暗 ═══
     这些颜色是页面脚本按深色配色算出来的（机制分档、涨跌、恐慌贪婪、迷你走势线），
     CSS 覆盖不到。**颜色本身是数据编码**，所以只压亮度、保留色相，红绿分档不变。 */
  var PAPER = [255, 241, 229];        // 纸色底：浅色主题里对比度最紧的一档
  var origin = new WeakMap();         // 元素 → 原始取值，切回深色时还原
  var ATTRS = ["fill", "stroke", "stop-color"];

  function parseColor(v) {
    if (!v) return null;
    v = String(v).trim().toLowerCase();
    if (v === "none" || v === "transparent" || v === "currentcolor" || v === "inherit") return null;
    var m;
    if (v.charAt(0) === "#") {
      var h = v.slice(1);
      if (h.length === 3) return [parseInt(h[0] + h[0], 16), parseInt(h[1] + h[1], 16), parseInt(h[2] + h[2], 16), 1];
      if (h.length === 6) return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16), 1];
      return null;
    }
    m = v.match(/^rgba?\(([^)]+)\)$/);
    if (!m) return null;
    var p = m[1].split(/[,/\s]+/).filter(Boolean).map(Number);
    if (p.length < 3 || p.slice(0, 3).some(isNaN)) return null;
    return [p[0], p[1], p[2], p.length > 3 && !isNaN(p[3]) ? p[3] : 1];
  }
  function lum(c) {
    function f(x) { x /= 255; return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4); }
    return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]);
  }
  function contrastOnPaper(c) {
    var a = lum(c), b = lum(PAPER);
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
  }
  function rgbToHsl(c) {
    var r = c[0] / 255, g = c[1] / 255, b = c[2] / 255;
    var mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn, h = 0, l = (mx + mn) / 2;
    var s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
    if (d !== 0) {
      if (mx === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
      else if (mx === g) h = ((b - r) / d + 2) / 6;
      else h = ((r - g) / d + 4) / 6;
    }
    return [h, s, l];
  }
  function hslToRgb(h, s, l) {
    function f(n) {
      var k = (n + h * 12) % 12, a = s * Math.min(l, 1 - l);
      return Math.round(255 * (l - a * Math.max(-1, Math.min(k - 3, Math.min(9 - k, 1)))));
    }
    return [f(0), f(8), f(4)];
  }
  function hex(c) {
    return "#" + c.map(function (x) {
      var v = Math.max(0, Math.min(255, Math.round(x))).toString(16);
      return v.length < 2 ? "0" + v : v;
    }).join("");
  }
  /* 保留色相与饱和度，把亮度压到刚好满足 target 对比度 */
  function darken(c, target) {
    var hsl = rgbToHsl(c), h = hsl[0];
    // 近白/近黑的饱和度会虚高，压暗时会凭空长出彩色 —— 用绝对彩度约束
    var chroma = Math.max(c[0], c[1], c[2]) - Math.min(c[0], c[1], c[2]);
    var s = Math.min(hsl[1], 0.8, Math.max(chroma / 140, 0.02));
    var lo = 0, hi = Math.max(hsl[2], 0.02);
    for (var i = 0; i < 20; i++) {
      var mid = (lo + hi) / 2;
      if (contrastOnPaper(hslToRgb(h, s, mid)) >= target) lo = mid; else hi = mid;
    }
    var out = hslToRgb(h, s, lo);
    if (c[3] < 0.95) return "rgba(" + out[0] + "," + out[1] + "," + out[2] + "," + c[3] + ")";
    return hex(out);
  }
  /* 站内多页把 OOGLEX 字标写成六个内联色的彩虹字。浅色主题下应当是一个纯墨色字标，
     而不是六个压暗后的彩色字母 —— 这里单独拦掉（CSS 规则会被运行时改写的 style
     属性甩开，所以必须在这里处理）。 */
  /* 注意比的是解析后的 RGB：读 el.style.color 拿到的是 "rgb(34, 211, 238)"，不是原始 hex */
  var BRAND = {
    "34,211,238": 1,   // #22d3ee
    "74,168,255": 1,   // #4aa8ff
    "108,140,255": 1,  // #6c8cff
    "157,108,255": 1,  // #9d6cff
    "200,108,255": 1,  // #c86cff
    "244,114,182": 1   // #f472b6
  };
  function inkColor() { return applied(current) === "ft" ? "#1a1613" : "#111214"; }

  function shadeText(v, target) {
    var c = parseColor(v);
    if (c && BRAND[Math.round(c[0]) + "," + Math.round(c[1]) + "," + Math.round(c[2])]) return inkColor();
    if (!c || c[3] < 0.25) return null;
    if (contrastOnPaper(c) >= target) return null;
    return darken(c, target + 0.1);
  }
  /* 注意：这里**不碰** inline 背景色。页面脚本写进 style 的背景基本都是数据色
     （热力图瓦片、持仓条、迷你走势填充），翻转会破坏数据编码；界面外壳的背景
     来自 CSS，已由 scripts/theme/light_overrides.py 生成的规则接管。 */

  function shadeOne(el) {
    var st = el.style, saved = origin.get(el), rec = saved || {};
    var touched = false;
    if (st && st.color) {
      var nc = shadeText(st.color, 4.0);
      if (nc) { if (!("color" in rec)) rec.color = st.color; st.color = nc; touched = true; }
    }
    /* 页面脚本常把「本条目的强调色」写成 inline 自定义属性（如 --mc），
       这些值同时用于文字与描边，按文字标准压暗。 */
    if (st && st.length) {
      for (var k = 0; k < st.length; k++) {
        var pn = st[k];
        if (pn.slice(0, 2) !== "--") continue;
        var pv = st.getPropertyValue(pn);
        var np = shadeText(pv, 4.0);
        if (!np) continue;
        if (!(pn in rec)) rec[pn] = pv;
        st.setProperty(pn, np);
        touched = true;
      }
    }
    for (var i = 0; i < ATTRS.length; i++) {
      var a = ATTRS[i], av = el.getAttribute && el.getAttribute(a);
      if (!av) continue;
      var na = shadeText(av, 3.0);           // 图形元素按 3:1 走
      if (na) { if (!(a in rec)) rec[a] = av; el.setAttribute(a, na); touched = true; }
    }
    if (touched) origin.set(el, rec);
  }

  function restoreOne(el) {
    var rec = origin.get(el);
    if (!rec) return;
    if ("color" in rec) el.style.color = rec.color;
    for (var k in rec) if (k.slice(0, 2) === "--") el.style.setProperty(k, rec[k]);
    for (var i = 0; i < ATTRS.length; i++) if (ATTRS[i] in rec) el.setAttribute(ATTRS[i], rec[ATTRS[i]]);
    origin.delete(el);
  }

  var SEL = '[style*="color"],[style*="--"],[fill],[stroke],[stop-color]';
  /* 着色是幂等的：已经达标的颜色不会再动，所以自己的写入触发的重扫会立刻收敛，
     不需要互斥标志（早先的互斥反而会漏掉正好在那一帧渲染出来的元素）。 */
  function sweep(light, root) {
    var scope = root && root.querySelectorAll ? root : document;
    var list = scope.querySelectorAll(SEL);
    for (var i = 0; i < list.length; i++) (light ? shadeOne : restoreOne)(list[i]);
    if (scope !== document && scope.matches && scope.matches(SEL)) (light ? shadeOne : restoreOne)(scope);
  }

  var pending = null, observer = null, sweeps = 0, sweepWindow = 0;
  function isLight() { var t = applied(current); return t === "ft" || t === "paper"; }
  function flush() {
    pending = null;
    if (!isLight()) return;
    /* 兜底上限：万一页面脚本与着色互相触发，1 秒内最多扫 60 次就停手 */
    var now = Date.now();
    if (now - sweepWindow > 1000) { sweepWindow = now; sweeps = 0; }
    if (++sweeps > 60) return;
    sweep(true, document);
  }
  function watch() {
    if (observer || typeof MutationObserver === "undefined") return;
    observer = new MutationObserver(function (recs) {
      if (pending) return;
      for (var i = 0; i < recs.length; i++) {
        if (recs[i].type === "childList" ? recs[i].addedNodes.length : true) {
          pending = requestAnimationFrame(flush);
          return;
        }
      }
    });
    observer.observe(document.documentElement, {
      subtree: true, childList: true, attributes: true,
      attributeFilter: ["style", "fill", "stroke", "stop-color"]
    });
  }
  function applyShading() {
    if (isLight()) {
      sweep(true, document);
      watch();
      /* 页面首屏数据多是异步渲染的，补两次延迟扫描，接住 observer 之外的落点 */
      setTimeout(flush, 250);
      setTimeout(flush, 1200);
    }
    else { if (observer) { observer.disconnect(); observer = null; } sweep(false, document); }
  }

  var current = read();
  paint(current);
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", applyShading);
  } else {
    applyShading();
  }

  /* ── 控件 ───────────────────────────────────────────────────────────────── */
  /* 各页顶栏结构不一，按优先级找一个能放的容器；都找不到就固定在右上角。 */
  var SLOTS = [
    "[data-theme-slot]", "nav .links", "nav.topbar", ".topbar", ".bar",
    ".head .tools", ".page > .head", "header nav", "body > header"
  ];
  function findSlot() {
    for (var i = 0; i < SLOTS.length; i++) {
      var el = document.querySelector(SLOTS[i]);
      if (el) return el;
    }
    return null;
  }

  function isEnglish() {
    try { return !!(window.OoglexI18n && window.OoglexI18n.getLanguage() === "en"); } catch (e) { return false; }
  }
  function label(m) { return isEnglish() ? m.en : m.zh; }

  function build() {
    var slot = findSlot();
    var box = document.createElement("div");
    box.className = "ogx-theme" + (slot ? "" : " is-float");

    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "ogx-theme__btn";
    btn.setAttribute("aria-haspopup", "true");
    btn.setAttribute("aria-expanded", "false");
    var sw = document.createElement("span");
    sw.className = "ogx-theme__swatch " + meta(current).sw;
    var txt = document.createElement("span");
    txt.className = "ogx-theme__label";
    btn.appendChild(sw);
    btn.appendChild(txt);

    var menu = document.createElement("div");
    menu.className = "ogx-theme__menu";
    menu.setAttribute("role", "radiogroup");
    menu.dataset.open = "0";

    var opts = THEMES.map(function (m) {
      var o = document.createElement("button");
      o.type = "button";
      o.className = "ogx-theme__opt";
      o.setAttribute("role", "radio");
      o.dataset.theme = m.id;
      var s = document.createElement("span");
      s.className = "ogx-theme__swatch " + m.sw;
      var t = document.createElement("span");
      t.className = "ogx-theme__optlabel";
      o.appendChild(s);
      o.appendChild(t);
      o.addEventListener("click", function () { choose(m.id); close(); btn.focus(); });
      menu.appendChild(o);
      return o;
    });

    var note = document.createElement("p");
    note.className = "ogx-theme__note";
    if (lock) menu.appendChild(note);

    box.appendChild(btn);
    box.appendChild(menu);

    function sync() {
      var m = meta(current);
      sw.className = "ogx-theme__swatch " + m.sw;
      txt.textContent = label(m);
      btn.setAttribute("aria-label", isEnglish() ? "Theme: " + m.en : "主题配色：" + m.zh);
      btn.title = isEnglish() ? "Site theme — applies to every page" : "全站主题配色 · 所有子页面通用";
      opts.forEach(function (o) {
        var om = meta(o.dataset.theme);
        o.setAttribute("aria-checked", o.dataset.theme === current ? "true" : "false");
        o.querySelector(".ogx-theme__optlabel").textContent = label(om);
      });
      if (lock) {
        note.textContent = isEnglish()
          ? "This page stays dark (full-screen canvas); your choice still applies site-wide."
          : "本页画面固定深色（整屏 canvas），所选主题仍对其他页面生效。";
      }
    }

    function open() {
      menu.dataset.open = "1";
      btn.setAttribute("aria-expanded", "true");
      document.addEventListener("click", outside, true);
      document.addEventListener("keydown", onKey, true);
    }
    function close() {
      menu.dataset.open = "0";
      btn.setAttribute("aria-expanded", "false");
      document.removeEventListener("click", outside, true);
      document.removeEventListener("keydown", onKey, true);
    }
    function outside(e) { if (!box.contains(e.target)) close(); }
    function onKey(e) {
      if (e.key === "Escape") { close(); btn.focus(); return; }
      if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
      var list = opts, i = list.indexOf(document.activeElement);
      e.preventDefault();
      i = i < 0 ? 0 : i + (e.key === "ArrowDown" ? 1 : -1);
      list[(i + list.length) % list.length].focus();
    }
    function choose(t) {
      current = valid(t) || DEFAULT;
      write(current);
      paint(current);
      applyShading();
      sync();
    }

    btn.addEventListener("click", function () {
      if (menu.dataset.open === "1") { close(); } else { open(); opts[0].focus(); }
    });

    /* 跨标签页同步 */
    window.addEventListener("storage", function (e) {
      if (e.key !== KEY) return;
      current = read();
      paint(current);
      applyShading();
      sync();
    });
    /* 跟随站内中英切换 */
    document.addEventListener("ooglex:languagechange", sync);

    sync();
    if (slot) slot.appendChild(box); else document.body.appendChild(box);

    /* 有些页面的顶栏默认隐藏（望远镜的 .topbar 藏在启动页后面），
       落位后量一次实际尺寸，量不到就改成右上角浮动。 */
    requestAnimationFrame(function () {
      var r = btn.getBoundingClientRect();
      if (r.width > 10 && r.height > 10) return;
      box.classList.add("is-float");
      document.body.appendChild(box);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", build);
  } else {
    build();
  }
})();
