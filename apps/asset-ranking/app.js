/* 全球资产市值排行榜 · 前端渲染
 * 读取同目录 data.json（由 scripts/asset-ranking/build_ranking.py 每日生成），
 * 把房地产/国债/商品/货币/黄金/公司/加密货币放进同一张榜按市值排名并渲染，
 * 支持分类筛选、按市值·今日涨幅·今日跌幅排序、中英名/代码搜索。纯原生 JS。 */
(function () {
  "use strict";

  var DATA = null, MAXC = 1, CATMAP = {};
  var state = { sort: "rank", q: "", cat: "all" };
  var $ = function (id) { return document.getElementById(id); };
  var raf = (typeof requestAnimationFrame !== "undefined")
    ? requestAnimationFrame : function (f) { return setTimeout(f, 16); };

  function isNum(v) { return v !== null && v !== undefined && !isNaN(v); }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  var CURSYM = { USD: "$", EUR: "€", JPY: "¥", HKD: "HK$", KRW: "₩",
    TWD: "NT$", INR: "₹", CHF: "CHF ", SAR: "SAR ", GBP: "£", CNY: "¥" };

  function fmtCap(b) {
    if (!isNum(b)) return "—";
    return b >= 1000 ? "$" + (b / 1000).toFixed(2) + "T" : "$" + b.toFixed(1) + "B";
  }
  function fmtPrice(p, cur) {
    if (!isNum(p)) return null;
    var sym = CURSYM[cur] || "$";
    if (p >= 1000) return sym + p.toLocaleString("en-US", { maximumFractionDigits: 0 });
    if (p >= 1) return sym + p.toFixed(2);
    return sym + p.toPrecision(2);                 // 小额（汇率/低价币）保留有效位
  }
  function fmtQty(v) {
    if (!isNum(v)) return "";
    if (v >= 1e12) return (v / 1e12).toFixed(2) + " 万亿";
    if (v >= 1e8) return (v / 1e8).toFixed(2) + " 亿";
    if (v >= 1e4) return (v / 1e4).toFixed(0) + " 万";
    return String(v);
  }
  function fmtPct(v) { return !isNum(v) ? null : (v >= 0 ? "+" : "−") + Math.abs(v).toFixed(2) + "%"; }
  function pctClass(v) { return !isNum(v) ? "flat" : (v > 0 ? "up" : (v < 0 ? "down" : "flat")); }
  function pctArrow(v) { return !isNum(v) ? "·" : (v > 0 ? "▲" : (v < 0 ? "▼" : "·")); }

  function filtered() {
    var q = state.q.toLowerCase();
    return (DATA.assets || []).filter(function (a) {
      if (state.cat !== "all" && a.category !== state.cat) return false;
      if (!q) return true;
      return (a.name || "").toLowerCase().indexOf(q) >= 0 ||
             (a.nameEn || "").toLowerCase().indexOf(q) >= 0 ||
             (a.symbol || "").toLowerCase().indexOf(q) >= 0;
    });
  }
  function sorted(list) {
    var s = state.sort;
    return list.slice().sort(function (a, b) {
      if (s === "rank") return a.rank - b.rank;
      var ca = isNum(a.changePct) ? a.changePct : (s === "gain" ? -1e9 : 1e9);
      var cb = isNum(b.changePct) ? b.changePct : (s === "gain" ? -1e9 : 1e9);
      return s === "gain" ? cb - ca : ca - cb;
    });
  }

  function logoEl(a) {
    var box = document.createElement("div"); box.className = "logo";
    if (a.logo) {                                  // 公司：本地同源 logo（apps/companies/logos/）
      var img = document.createElement("img");
      img.src = a.logo; img.alt = a.name; img.loading = "lazy"; img.referrerPolicy = "no-referrer";
      var ini = (a.nameEn || a.name || "?").trim().charAt(0).toUpperCase();
      img.onerror = function () { box.innerHTML = '<div class="ini">' + ini + "</div>"; };
      box.appendChild(img);
    } else if (a.emoji) {                           // 大类资产/加密货币：emoji 图标
      box.innerHTML = '<div class="emo">' + a.emoji + "</div>";
    } else {
      box.innerHTML = '<div class="ini">' + (a.name || "?").charAt(0) + "</div>";
    }
    return box;
  }

  function metaOf(a) {
    if (a.category === "company") {
      return [(a.flag || "") + (a.country || ""), a.sector,
        a.private ? (a.lastRound ? "上轮融资 " + a.lastRound : "未上市") : a.symbol].filter(Boolean).join(" · ");
    }
    if (a.category === "crypto") return "加密货币 · " + (a.symbol || "");
    if (isNum(a.qty)) return fmtQty(a.qty) + (a.unit || "");      // 商品/货币：供应/储量
    return a.unit || (a.note ? a.note.split("，")[0] : "");        // 房地产/债券：静态口径
  }

  function catTag(a) {
    var c = CATMAP[a.category];
    if (!c) return "";
    return '<span class="ctag" style="color:' + c.color + '">' + esc(c.label) + "</span>";
  }

  function renderList() {
    var wrap = $("list"); wrap.innerHTML = "";
    var list = sorted(filtered());
    if (!list.length) { wrap.innerHTML = '<div class="empty">没有匹配的资产，换个关键词或分类试试 🙂</div>'; return; }
    var grow = [];
    list.forEach(function (a, i) {
      var card = document.createElement("div"); card.className = "rowcard";
      card.style.animationDelay = Math.min(i * 12, 340) + "ms";

      var rk = document.createElement("div");
      rk.className = "rk" + (a.rank <= 3 ? " top" : ""); rk.textContent = a.rank;

      var info = document.createElement("div"); info.className = "info";
      var nm = document.createElement("div"); nm.className = "nm";
      nm.innerHTML = esc(a.name) +
        (a.nameEn && a.nameEn !== a.name ? '<span class="en">' + esc(a.nameEn) + "</span>" : "") +
        catTag(a) +
        (a.stale ? '<span class="en">· 沿用上次</span>' : "");
      var meta = document.createElement("div"); meta.className = "meta"; meta.textContent = metaOf(a);
      info.appendChild(nm); info.appendChild(meta);

      var money = document.createElement("div"); money.className = "money";
      var cap = document.createElement("div"); cap.className = "cap"; cap.textContent = fmtCap(a.marketCap);
      var px = document.createElement("div"); px.className = "px";
      var pxTxt = fmtPrice(a.price, a.priceCur);
      var ps = fmtPct(a.changePct);
      if (pxTxt || ps) {
        px.innerHTML = (pxTxt ? esc(pxTxt) + " " : "") +
          (ps ? '<span class="chg ' + pctClass(a.changePct) + '">' + pctArrow(a.changePct) + " " + ps + "</span>" : "");
      } else {
        px.innerHTML = '<span class="flat">存量估值</span>';
      }
      money.appendChild(cap); money.appendChild(px);

      var bg = document.createElement("div"); bg.className = "wbarbg";
      var bar = document.createElement("div"); bar.className = "wbar";
      var c = CATMAP[a.category];
      bar.style.background = "linear-gradient(90deg," + ((c && c.color) || "#6c8cff") + ",transparent)";
      grow.push([bar, Math.max(1.5, (a.marketCap / MAXC) * 100)]);

      card.appendChild(rk); card.appendChild(logoEl(a)); card.appendChild(info); card.appendChild(money);
      card.appendChild(bg); card.appendChild(bar);
      wrap.appendChild(card);
    });
    raf(function () { grow.forEach(function (g) { g[0].style.width = g[1] + "%"; }); });
  }

  function renderChips() {
    var cc = DATA.categoryCount || {};
    var chips = [{ key: "all", label: "全部", color: "#9099ad", n: (DATA.assets || []).length }];
    (DATA.categories || []).forEach(function (c) {
      if (cc[c.key]) chips.push({ key: c.key, label: c.label, color: c.color, n: cc[c.key] });
    });
    var box = $("chips"); box.innerHTML = "";
    chips.forEach(function (c) {
      var el = document.createElement("div");
      el.className = "chip" + (state.cat === c.key ? " on" : "");
      el.innerHTML = '<span class="cdot" style="color:' + c.color + '"></span>' + esc(c.label) +
        ' <span style="opacity:.7">' + c.n + "</span>";
      el.onclick = function () {
        state.cat = c.key;
        box.querySelectorAll(".chip").forEach(function (x) { x.classList.remove("on"); });
        el.classList.add("on"); renderList();
      };
      box.appendChild(el);
    });
  }

  function renderSummary() {
    var as = DATA.assets || [], el = $("summary");
    var withChg = as.filter(function (a) { return isNum(a.changePct); });
    var top = withChg.slice().sort(function (a, b) { return b.changePct - a.changePct; })[0];
    var bot = withChg.slice().sort(function (a, b) { return a.changePct - b.changePct; })[0];
    var totalT = isNum(DATA.totalMarketCap) ? "$" + (DATA.totalMarketCap / 1000).toFixed(1) + "T" : "—";
    var html = '<span class="pill-i">📅 ' + esc(DATA.asOf || "—") + "</span>" +
      '<span class="pill-i">前 ' + (DATA.count || as.length) + ' 总市值 <b class="big">' + totalT + "</b></span>";
    if (as[0]) html += '<span class="pill-i">🏆 榜首 <b>' + esc(as[0].name) + "</b> " + fmtCap(as[0].marketCap) + "</span>";
    if (top && top.changePct > 0) html += '<span class="lead up">▲ 今日领涨 ' + esc(top.name) + " " + fmtPct(top.changePct) + "</span>";
    if (bot && bot.changePct < 0) html += '<span class="lead down">▼ 今日领跌 ' + esc(bot.name) + " " + fmtPct(bot.changePct) + "</span>";
    el.innerHTML = html;
  }

  function renderStatus() {
    var live = !!DATA.source && !/示例/.test(DATA.source);
    var el = $("status");
    el.className = "status " + (live ? "live" : "demo");
    el.innerHTML = '<span class="sdot"></span>' + (live ? "实时榜 · 每日自动更新" : "示例数据 · 待每日任务刷新");
  }

  function renderFooter() {
    var upd = DATA.updatedAt ? DATA.updatedAt.replace("T", " ").replace("Z", " UTC") : "—";
    var html = '<div class="src">数据来源 <b>' + esc(DATA.source || "—") + "</b> · 数据日期 <b>" +
      esc(DATA.asOf || "—") + "</b> · 更新于 " + esc(upd) + "</div>";
    if (DATA.note) html += "<div>" + esc(DATA.note) + "</div>";
    $("foot").innerHTML = html;
  }

  function initSorts() {
    $("sorts").querySelectorAll("button").forEach(function (b) {
      b.onclick = function () {
        state.sort = b.getAttribute("data-sort");
        $("sorts").querySelectorAll("button").forEach(function (x) { x.classList.remove("on"); });
        b.classList.add("on"); renderList();
      };
    });
    $("q").oninput = function () { state.q = this.value.trim(); renderList(); };
  }

  function boot(data) {
    DATA = data;
    (DATA.categories || []).forEach(function (c) { CATMAP[c.key] = c; });
    MAXC = Math.max.apply(null, (DATA.assets || [{ marketCap: 1 }]).map(function (a) { return a.marketCap || 0; })) || 1;
    renderStatus(); renderSummary(); renderChips(); initSorts(); renderList(); renderFooter();
  }

  fetch("data.json?t=" + Date.now())
    .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(boot)
    .catch(function (e) {
      $("list").innerHTML = '<div class="empty">数据加载失败：' + esc(e.message) + "<br>请稍后刷新重试。</div>";
    });
})();
