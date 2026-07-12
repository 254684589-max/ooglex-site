/* 全球经济图谱 · 前端
 * 读取 data.json（由 scripts/world-economy/build_economy.py 每日生成），用世界地图（jsVectorMap）
 * 渲染各国经济指标 choropleth，支持指标切换 / 榜单 / 提示框，并提供 Web Audio 生成的背景音乐。
 * 地图库从 CDN 加载；若不可用则自动降级为榜单表格。纯原生 JS。 */
(function () {
  "use strict";
  var DATA = null, KEY = null, mapObj = null;
  var $ = function (id) { return document.getElementById(id); };

  // ISO2 → 中文国名（覆盖主要经济体，未命中回退地图英文名 / 代码）
  var ZH = {
    US: "美国", CN: "中国", JP: "日本", DE: "德国", GB: "英国", IN: "印度", FR: "法国", IT: "意大利",
    BR: "巴西", CA: "加拿大", RU: "俄罗斯", KR: "韩国", AU: "澳大利亚", ES: "西班牙", MX: "墨西哥",
    ID: "印度尼西亚", NL: "荷兰", SA: "沙特阿拉伯", CH: "瑞士", TR: "土耳其", TW: "台湾", SE: "瑞典",
    PL: "波兰", BE: "比利时", AR: "阿根廷", NO: "挪威", AT: "奥地利", AE: "阿联酋", TH: "泰国",
    ZA: "南非", DK: "丹麦", FI: "芬兰", IE: "爱尔兰", IL: "以色列", SG: "新加坡", HK: "香港",
    MY: "马来西亚", PH: "菲律宾", VN: "越南", PK: "巴基斯坦", BD: "孟加拉国", EG: "埃及", NG: "尼日利亚",
    CL: "智利", CO: "哥伦比亚", PE: "秘鲁", CZ: "捷克", RO: "罗马尼亚", PT: "葡萄牙", GR: "希腊",
    HU: "匈牙利", NZ: "新西兰", UA: "乌克兰", KZ: "哈萨克斯坦", QA: "卡塔尔", KW: "科威特", IR: "伊朗",
    IQ: "伊拉克", DZ: "阿尔及利亚", MA: "摩洛哥", AO: "安哥拉", KE: "肯尼亚", ET: "埃塞俄比亚",
    GH: "加纳", TZ: "坦桑尼亚", SK: "斯洛伐克", SI: "斯洛文尼亚", LT: "立陶宛", LV: "拉脱维亚",
    EE: "爱沙尼亚", LU: "卢森堡", HR: "克罗地亚", BG: "保加利亚", RS: "塞尔维亚", IS: "冰岛",
    CY: "塞浦路斯", MT: "马耳他", LK: "斯里兰卡", MM: "缅甸", KH: "柬埔寨", LA: "老挝", NP: "尼泊尔",
    UZ: "乌兹别克斯坦", AZ: "阿塞拜疆", GE: "格鲁吉亚", BY: "白俄罗斯", VE: "委内瑞拉", EC: "厄瓜多尔",
    BO: "玻利维亚", PY: "巴拉圭", UY: "乌拉圭", DO: "多米尼加", GT: "危地马拉", CR: "哥斯达黎加",
    PA: "巴拿马", OM: "阿曼", JO: "约旦", LB: "黎巴嫩", TN: "突尼斯", CI: "科特迪瓦", SN: "塞内加尔",
    CM: "喀麦隆", ZM: "赞比亚", ZW: "津巴布韦", UG: "乌干达", MZ: "莫桑比克", BW: "博茨瓦纳", MN: "蒙古"
  };

  function isNum(v) { return v !== null && v !== undefined && !isNaN(v); }
  function cur() { return (DATA.indicators || []).filter(function (i) { return i.key === KEY; })[0]; }

  function flag(iso2) {
    if (!iso2 || iso2.length !== 2) return "🌐";
    try {
      return String.fromCodePoint.apply(null, iso2.toUpperCase().split("").map(function (c) {
        return 0x1F1E6 + c.charCodeAt(0) - 65;
      }));
    } catch (e) { return "🌐"; }
  }
  function name(code) { return ZH[code] || code; }

  function fmt(v, unit) {
    if (!isNum(v)) return "—";
    if (unit === "美元") return "$" + Math.round(v).toLocaleString("en-US");
    var s = Math.abs(v) >= 100 ? v.toFixed(0) : v.toFixed(2);
    return s + (unit || "");
  }

  function hex(c) { c = c.replace("#", ""); return [parseInt(c.slice(0, 2), 16), parseInt(c.slice(2, 4), 16), parseInt(c.slice(4, 6), 16)]; }
  function lerp(a, b, t) {
    var x = hex(a), y = hex(b);
    return "rgb(" + x.map(function (v, i) { return Math.round(v + (y[i] - v) * t); }).join(",") + ")";
  }
  function range(ind) {
    var vs = Object.keys(ind.values).map(function (k) { return ind.values[k]; }).filter(isNum);
    return vs.length ? [Math.min.apply(null, vs), Math.max.apply(null, vs)] : [0, 1];
  }
  function colorFor(ind, v, rg) {
    if (!isNum(v)) return "#222734";
    var t = rg[1] === rg[0] ? 0.5 : (v - rg[0]) / (rg[1] - rg[0]);
    return lerp(ind.scale[0], ind.scale[1], Math.max(0, Math.min(1, t)));
  }

  /* —— 地图 —— */
  function mapReady() {
    var JVM = window.jsVectorMap || window.JsVectorMap;
    return JVM && JVM.maps && JVM.maps.world ? JVM : null;
  }
  function renderMap() {
    var JVM = mapReady();
    if (!JVM) { forceTable(); return; }
    var ind = cur();
    if (mapObj) { try { mapObj.destroy(); } catch (e) {} mapObj = null; }
    $("map").innerHTML = "";
    try {
      mapObj = new JVM({
        selector: "#map", map: "world", backgroundColor: "transparent",
        zoomOnScroll: true, zoomButtons: true,
        regionStyle: { initial: { fill: "#222734", stroke: "#06080d", strokeWidth: 0.4 }, hover: { fillOpacity: 0.82 } },
        series: { regions: [{ attribute: "fill", scale: [ind.scale[0], ind.scale[1]], normalizeFunction: "polynomial", values: ind.values }] },
        onRegionTooltipShow: function (event, tooltip, code) {
          var v = ind.values[code];
          var nm = ZH[code] || tooltip.text();
          tooltip.text(nm + "：" + (isNum(v) ? fmt(v, ind.unit) : "暂无数据"), true);
        }
      });
    } catch (e) { console.log("map render fail", e); forceTable(); }
  }
  function forceTable() {
    $("mapwrap").style.display = "none";
    $("legend").style.display = "none";
    $("tableBox").style.display = "block";
  }

  /* —— 顶部 / 副标题 / 图例 / 榜单 —— */
  function renderTabs() {
    var box = $("tabs"); box.innerHTML = "";
    (DATA.indicators || []).forEach(function (ind) {
      var b = document.createElement("button");
      b.textContent = ind.name;
      if (ind.key === KEY) { b.className = "on"; b.style.background = ind.scale[1]; b.style.color = "#0b0a07"; }
      b.onclick = function () { KEY = ind.key; render(); };
      box.appendChild(b);
    });
  }
  function renderSubhead() {
    var ind = cur();
    $("indName").textContent = ind.name + (ind.nameEn ? " · " + ind.nameEn : "");
    $("indDesc").textContent = ind.desc || "";
    $("indYear").textContent = (ind.year ? "数据：" + ind.year : "") + (ind.unit ? " · 单位 " + ind.unit : "");
  }
  function renderTop() {
    var ind = cur(), rg = range(ind);
    var rows = Object.keys(ind.values).map(function (k) { return [k, ind.values[k]]; })
      .filter(function (r) { return isNum(r[1]); }).sort(function (a, b) { return b[1] - a[1]; }).slice(0, 6);
    $("top").innerHTML = rows.map(function (r, i) {
      return "<div class='t'><div class='c'>" + flag(r[0]) + " " + name(r[0]) + "</div>" +
        "<div class='v' style='color:" + colorFor(ind, r[1], rg) + "'>" + fmt(r[1], ind.unit) + "</div>" +
        "<div class='r'>第 " + (i + 1) + " 高</div></div>";
    }).join("");
  }
  function renderLegend() {
    var ind = cur(), rg = range(ind);
    $("legend").style.display = "";
    var mid = (rg[0] + rg[1]) / 2;
    $("legend").innerHTML = "<span class='lab'>" + fmt(rg[0], ind.unit) + "</span>" +
      "<div class='bar' style='background:linear-gradient(90deg," + ind.scale[0] + "," + ind.scale[1] + ")'></div>" +
      "<span class='lab'>" + fmt(mid, ind.unit) + "</span>" +
      "<div class='bar' style='background:linear-gradient(90deg," + lerp(ind.scale[0], ind.scale[1], 0.5) + "," + ind.scale[1] + ")'></div>" +
      "<span class='lab'>" + fmt(rg[1], ind.unit) + "</span>";
  }
  var sortDir = -1;
  function renderTable() {
    var ind = cur(), rg = range(ind);
    var rows = Object.keys(ind.values).map(function (k) { return [k, ind.values[k]]; })
      .filter(function (r) { return isNum(r[1]); }).sort(function (a, b) { return (a[1] - b[1]) * sortDir; });
    $("tableCnt").textContent = rows.length + " 个国家/地区";
    var html = "<table><thead><tr><th>国家 / 地区</th><th id='vh'>" + ind.name + "（" + (ind.unit || "") + "）" + (sortDir < 0 ? " ↓" : " ↑") + "</th></tr></thead><tbody>";
    rows.forEach(function (r) {
      html += "<tr><td>" + flag(r[0]) + " " + name(r[0]) + " <span style='color:var(--dim)'>" + r[0] + "</span></td>" +
        "<td><span class='dot' style='background:" + colorFor(ind, r[1], rg) + "'></span>" + fmt(r[1], ind.unit) + "</td></tr>";
    });
    $("tableBox").innerHTML = html + "</tbody></table>";
    var vh = document.getElementById("vh");
    if (vh) vh.onclick = function () { sortDir *= -1; renderTable(); };
  }

  function renderStatus() {
    var live = !DATA.demo;
    $("foot").innerHTML = "<span class='status " + (live ? "live" : "demo") + "'><span class='sdot'></span>" +
      (live ? "实时聚合 · 每日更新" : "示例数据 · 待刷新") + "</span><br>数据来源 <b>" +
      (DATA.sources || []).join(" · ") + "</b> · 更新于 " + (DATA.updatedAt || "").replace("T", " ").replace("Z", " UTC") +
      "<br>" + (DATA.note || "");
  }

  function render() {
    renderTabs(); renderSubhead(); renderTop(); renderLegend(); renderMap(); renderTable();
  }

  /* —— 视图切换：榜单展开/收起 —— */
  function toggleTable() {
    var box = $("tableBox");
    box.style.display = (box.style.display === "none" || !box.style.display) ? "block" : "none";
  }

  /* —— Web Audio 生成的环境背景音乐 —— */
  var actx = null, voice = null, chordTimer = null;
  var CHORDS = [[110, 164.81, 220, 277.18], [98, 146.83, 196, 246.94], [123.47, 185, 246.94, 311.13], [87.31, 130.81, 174.61, 220]];
  function startMusic() {
    actx = actx || new (window.AudioContext || window.webkitAudioContext)();
    if (actx.state === "suspended") actx.resume();
    var master = actx.createGain(); master.gain.value = 0; master.connect(actx.destination);
    master.gain.linearRampToValueAtTime(0.075, actx.currentTime + 3);
    var filter = actx.createBiquadFilter(); filter.type = "lowpass"; filter.frequency.value = 650; filter.connect(master);
    var flfo = actx.createOscillator(); flfo.frequency.value = 0.03; var fg = actx.createGain(); fg.gain.value = 320;
    flfo.connect(fg); fg.connect(filter.frequency); flfo.start();
    var oscs = CHORDS[0].map(function (f, i) {
      var o = actx.createOscillator(); o.type = i % 2 ? "sine" : "triangle"; o.frequency.value = f;
      var g = actx.createGain(); g.gain.value = 0.22 / (i + 1); o.connect(g); g.connect(filter); o.start();
      var lfo = actx.createOscillator(); lfo.frequency.value = 0.05 + i * 0.013; var lg = actx.createGain(); lg.gain.value = 2.2;
      lfo.connect(lg); lg.connect(o.detune); lfo.start();
      return o;
    });
    voice = { master: master, oscs: oscs, extra: [flfo] };
    var ci = 0;
    chordTimer = setInterval(function () {                       // 缓慢和弦演进
      ci = (ci + 1) % CHORDS.length;
      oscs.forEach(function (o, i) { o.frequency.linearRampToValueAtTime(CHORDS[ci][i], actx.currentTime + 5); });
    }, 11000);
    $("music").classList.add("on");
  }
  function stopMusic() {
    if (chordTimer) { clearInterval(chordTimer); chordTimer = null; }
    if (voice && actx) {
      voice.master.gain.cancelScheduledValues(actx.currentTime);
      voice.master.gain.linearRampToValueAtTime(0, actx.currentTime + 1.2);
      var v = voice; voice = null;
      setTimeout(function () { try { v.oscs.concat(v.extra).forEach(function (o) { o.stop(); }); } catch (e) {} }, 1500);
    }
    $("music").classList.remove("on");
  }
  function toggleMusic() { if (voice) stopMusic(); else { try { startMusic(); } catch (e) { console.log("music fail", e); } } }

  function boot(data) {
    DATA = data;
    KEY = data.defaultKey || (data.indicators[0] && data.indicators[0].key);
    render(); renderStatus();
    $("music").onclick = toggleMusic;
    $("viewtoggle").onclick = toggleTable;
    $("tableHead").onclick = toggleTable;
  }

  fetch("data.json?t=" + Date.now())
    .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(boot)
    .catch(function (e) {
      $("top").innerHTML = "<div style='color:var(--dim);padding:20px'>数据加载失败：" + e.message + "</div>";
    });
})();
