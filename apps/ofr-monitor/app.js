/* 美国金融风险监测 · 渲染 OFR 五大监测（金融压力指数 + 短期融资 + 货币基金 + 对冲基金 + 银行风险）。
   纯原生 JS，读取同目录 data.json（由 scripts/ofr-monitor/build_ofr.py 定时生成）。 */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  function isNum(v) { return v !== null && v !== undefined && v !== "" && !isNaN(v); }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function fnum(v, d) { return isNum(v) ? Number(v).toFixed(d == null ? 2 : d) : "—"; }
  function signed(v, d) { return !isNum(v) ? "—" : (v >= 0 ? "+" : "−") + Math.abs(v).toFixed(d == null ? 2 : d); }
  function relTime(iso) {
    if (!iso) return "";
    var t = Date.parse(iso); if (isNaN(t)) return "";
    var d = (Date.now() - t) / 1000;
    if (d < 3600) return "更新于 " + Math.max(1, Math.floor(d / 60)) + " 分钟前";
    if (d < 86400) return "更新于 " + Math.floor(d / 3600) + " 小时前";
    return "更新于 " + Math.floor(d / 86400) + " 天前";
  }

  // FSI：0=历史平均压力，正值高于平均（红），负值低于平均（绿）
  function fsiColor(v) { return !isNum(v) ? "var(--dim)" : v > 0.5 ? "var(--stress)" : v < -0.5 ? "var(--calm)" : "var(--neutral)"; }
  function fsiLabel(v) { return !isNum(v) ? "—" : v > 0.5 ? "高于平均压力" : v < -0.5 ? "低于平均压力" : "接近平均水平"; }

  // 折线图：把数值序列画成带零基线的 SVG sparkline
  function sparkSVG(vals, w, h) {
    vals = (vals || []).filter(isNum).map(Number);
    if (vals.length < 2) return "";
    var min = Math.min.apply(null, vals), max = Math.max.apply(null, vals);
    if (min === max) { min -= 1; max += 1; }
    var pad = 3;
    var x = function (i) { return pad + i * (w - 2 * pad) / (vals.length - 1); };
    var y = function (v) { return pad + (max - v) * (h - 2 * pad) / (max - min); };
    var pts = vals.map(function (v, i) { return x(i).toFixed(1) + "," + y(v).toFixed(1); }).join(" ");
    var area = "M" + x(0).toFixed(1) + "," + (h - pad).toFixed(1) + " L" +
      vals.map(function (v, i) { return x(i).toFixed(1) + "," + y(v).toFixed(1); }).join(" L") +
      " L" + x(vals.length - 1).toFixed(1) + "," + (h - pad).toFixed(1) + " Z";
    var last = vals[vals.length - 1];
    var col = fsiColor(last);
    var zero = "";
    if (min < 0 && max > 0) {
      var yz = y(0).toFixed(1);
      zero = "<line x1='" + pad + "' y1='" + yz + "' x2='" + (w - pad) + "' y2='" + yz +
        "' stroke='rgba(255,255,255,.18)' stroke-width='1' stroke-dasharray='3 3'/>";
    }
    return "<svg class='spark' viewBox='0 0 " + w + " " + h + "' preserveAspectRatio='none' aria-hidden='true'>" +
      "<defs><linearGradient id='fg' x1='0' y1='0' x2='0' y2='1'>" +
      "<stop offset='0' stop-color='" + col + "' stop-opacity='.28'/>" +
      "<stop offset='1' stop-color='" + col + "' stop-opacity='0'/></linearGradient></defs>" +
      "<path d='" + area + "' fill='url(#fg)'/>" + zero +
      "<polyline points='" + pts + "' fill='none' stroke='" + col + "' stroke-width='2' " +
      "stroke-linejoin='round' stroke-linecap='round'/></svg>";
  }

  // 分项贡献：以 0 为中心的分叉条（正=增压/红，负=减压/绿）
  function decompBars(items) {
    items = (items || []).filter(function (it) { return isNum(it.value); });
    if (!items.length) return "";
    var maxAbs = Math.max.apply(null, items.map(function (it) { return Math.abs(it.value); })) || 1;
    return items.map(function (it) {
      var v = Number(it.value), w = Math.min(50, Math.abs(v) / maxAbs * 50);
      var col = v >= 0 ? "var(--stress)" : "var(--calm)";
      var style = v >= 0 ? "left:50%;width:" + w + "%" : "left:" + (50 - w) + "%;width:" + w + "%";
      return "<div class='bar'><span class='bl'>" + esc(it.name) + "</span>" +
        "<span class='bt'><span class='bf' style='" + style + ";background:" + col + "'></span></span>" +
        "<span class='bv'>" + signed(v) + "</span></div>";
    }).join("");
  }

  function renderHero(d) {
    var f = d.fsi;
    if (!f || !isNum(f.value)) { $("hero").innerHTML = "<div class='empty'>金融压力指数暂无数据</div>"; return; }
    var col = fsiColor(f.value);
    var chgCls = !isNum(f.change) ? "dim" : (f.change > 0 ? "down" : (f.change < 0 ? "up" : "dim"));
    var chg = isNum(f.change) ? "<span class='chg " + chgCls + "'>" +
      (f.change > 0 ? "▲" : f.change < 0 ? "▼" : "•") + " " + signed(f.change) + " 较前值</span>" : "";

    var regions = "";
    if (f.regions) {
      var rmap = [["us", "🇺🇸 美国"], ["oae", "其他发达"], ["em", "新兴市场"]];
      var ri = rmap.filter(function (r) { return isNum(f.regions[r[0]]); })
        .map(function (r) { return { name: r[1], value: f.regions[r[0]] }; });
      if (ri.length) regions = "<div><div class='dc-h'>按地区贡献</div>" + decompBars(ri) + "</div>";
    }
    var cats = "";
    if (f.categories && f.categories.length) cats = "<div><div class='dc-h'>按类别贡献</div>" + decompBars(f.categories) + "</div>";
    var decomp = (regions || cats) ? "<div class='decomp'>" + cats + regions + "</div>" : "";

    $("hero").innerHTML =
      "<div class='cap'><span class='nm'>金融压力指数 <small>OFR FSI · 每日</small></span>" +
      "<a class='more' href='" + esc(f.url || "#") + "' target='_blank' rel='noopener'>OFR 原表 →</a></div>" +
      "<div class='read'><span class='num' style='color:" + col + "'>" + fnum(f.value) + "</span>" +
      "<span class='lab' style='color:" + col + "'>" + fsiLabel(f.value) + "</span>" + chg + "</div>" +
      sparkSVG(f.spark, 300, 56) +
      "<div class='scale'><span>近一年" + (isNum(f.yearAgo) ? " · 一年前 " + fnum(f.yearAgo) : "") +
      "</span><span>0 = 历史平均压力</span></div>" + decomp;
  }

  function monCard(o) {
    var tag = o.tag ? "<span class='tag'>" + esc(o.tag) + "</span>" : "";
    return "<div class='mon glass'><div class='mh'><span class='t'>" + esc(o.title) + "</span>" + tag + "</div>" +
      o.body + "<div class='foot'>" +
      (o.link ? "<a class='go' href='" + esc(o.link) + "' target='_blank' rel='noopener'>前往 OFR →</a>" : "") +
      (o.upd ? "<div class='upd'>" + esc(o.upd) + "</div>" : "") + "</div></div>";
  }

  function renderGrid(d) {
    var cards = [];

    // 短期融资：SOFR 领衔 + EFFR + SOFR 成交量
    var fu = d.funding || {};
    if (fu.sofr && isNum(fu.sofr.value)) {
      var rows = "";
      if (fu.effr && isNum(fu.effr.value)) rows += "<div class='r'><span class='l'>EFFR 联邦基金利率</span><span class='v'>" + fnum(fu.effr.value) + "%</span></div>";
      if (isNum(fu.sofrVol)) rows += "<div class='r'><span class='l'>SOFR 成交量</span><span class='v'>$" + fnum(fu.sofrVol) + "T</span></div>";
      var sc = isNum(fu.sofr.change) ? " <small class='dim'>" + signed(fu.sofr.change) + "</small>" : "";
      cards.push(monCard({
        title: "短期融资监测", tag: "SOFR · 每日", link: fu.url,
        body: "<div class='big'>" + fnum(fu.sofr.value) + "<small>% SOFR" + sc + "</small></div>" +
          "<div class='rows'>" + rows + "</div>",
        upd: fu.asOf ? "截至 " + fu.asOf : ""
      }));
    } else {
      cards.push(monCard({ title: "短期融资监测", tag: "SOFR · 每日", link: fu.url,
        body: "<div class='desc'>隔夜担保融资利率（SOFR）、联邦基金利率与回购成交量。</div>" }));
    }

    // 货币市场基金规模
    var m = d.mmf || {};
    if (isNum(m.total)) {
      var mc = isNum(m.change) ? "<div class='r'><span class='l'>较上月</span><span class='v " +
        (m.change > 0 ? "up" : m.change < 0 ? "down" : "dim") + "'>" + signed(m.change, 3) + " 万亿</span></div>" : "";
      cards.push(monCard({
        title: "货币市场基金", tag: "MMF · 每月", link: m.url,
        body: "<div class='big'>$" + fnum(m.total) + "<small>万亿 · 总规模</small></div><div class='rows'>" + mc + "</div>",
        upd: m.asOf ? "截至 " + m.asOf : ""
      }));
    } else {
      cards.push(monCard({ title: "货币市场基金", tag: "MMF · 每月", link: m.url,
        body: "<div class='desc'>美国货币市场基金总规模及资产结构。</div>" }));
    }

    // 对冲基金监测（季度，来自 Hedge Fund Monitor API 的 Form PF 数据）
    var h = d.hedge || {};
    if (isNum(h.gav) || isNum(h.nav)) {
      var big = isNum(h.gav) ? h.gav : h.nav;
      var bigLab = isNum(h.gav) ? "万亿 · 总资产 GAV" : "万亿 · 净资产 NAV";
      var hrows = "";
      if (isNum(h.gav) && isNum(h.nav)) hrows += "<div class='r'><span class='l'>净资产 NAV</span><span class='v'>$" + fnum(h.nav) + "T</span></div>";
      if (isNum(h.leverage)) hrows += "<div class='r'><span class='l'>平均杠杆</span><span class='v'>" + fnum(h.leverage) + "×</span></div>";
      cards.push(monCard({
        title: "对冲基金监测", tag: "Form PF · " + (h.note || "季度"), link: h.url,
        body: "<div class='big'>$" + fnum(big) + "<small>" + bigLab + "</small></div><div class='rows'>" + hrows + "</div>",
        upd: h.asOf ? "截至 " + h.asOf : "季度更新"
      }));
    } else {
      cards.push(monCard({
        title: "对冲基金监测", tag: (h.note || "季度"), link: h.url,
        body: "<div class='desc'>按规模、杠杆、交易对手、流动性、复杂性与风险管理六大维度跟踪对冲基金（SEC Form PF）。</div>",
        upd: h.asOf ? "截至 " + h.asOf : "季度更新"
      }));
    }

    // 银行系统性风险监测：美国 8 家 G-SIB 系统性资本附加（年度核定）
    var b = d.bank || {};
    if (b.gsibs && b.gsibs.length) {
      var brows = b.gsibs.map(function (g) {
        return "<div class='r'><span class='l'>" + esc(g.zh || g.bank) + "</span><span class='v'>" +
          fnum(g.surcharge, 1) + "%</span></div>";
      }).join("");
      cards.push(monCard({
        title: "银行系统性风险", tag: "G-SIB · 年度", link: b.url,
        body: "<div class='big'>" + b.gsibs.length + "<small>家美国 G-SIB · 系统性资本附加</small></div>" +
          "<div class='rows'>" + brows + "</div>",
        upd: b.effective || (b.asOf ? "适用 " + b.asOf : "年度核定")
      }));
    } else {
      cards.push(monCard({
        title: "银行系统性风险", tag: (b.note || "季度"), link: b.url,
        body: "<div class='desc'>大型银行系统重要性评分、OFR 传染指数等系统性风险关键指标。</div>",
        upd: b.asOf ? "截至 " + b.asOf : "季度更新"
      }));
    }

    $("grid").innerHTML = cards.join("");
  }

  function renderStatus(d) {
    var s = $("status");
    if (d.demo) {
      s.className = "status demo";
      s.innerHTML = "<span class='sdot'></span>示例数据 · 待每日自动更新接入";
    } else {
      s.className = "status live";
      s.innerHTML = "<span class='sdot'></span>" + (relTime(d.updatedAt) || "数据自动更新") +
        (d.asOf ? " · 截至 " + d.asOf : "");
    }
  }

  function boot() {
    fetch("data.json?t=" + Date.now())
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function (d) {
        renderStatus(d);
        renderHero(d);
        renderGrid(d);
        $("foot").innerHTML = "<div class='src'>数据来源：<b>U.S. Office of Financial Research（OFR）</b> · 金融研究办公室，美国财政部下属机构 · 公开数据，仅供参考，不构成投资建议。</div>";
      })
      .catch(function () {
        $("hero").innerHTML = "<div class='empty'>数据暂不可用，请稍后再试。</div>";
        var s = $("status"); s.className = "status demo"; s.innerHTML = "<span class='sdot'></span>数据加载失败";
      });
  }
  boot();
})();
