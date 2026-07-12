/* 超级投资者持仓 + AAII 情绪 · 前端渲染
 * 读取同目录 data.json（由 scripts/superinvestors/build_superinvestors.py 每周生成），
 * 渲染：投资者 13F 组合卡片（可展开前十大持仓与季度动向）、大佬共识榜、
 * AAII 每周情绪堆叠条（看涨/中性/看跌 + 历史均值对照）。纯原生 JS。 */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };

  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function isNum(v) { return v !== null && v !== undefined && !isNaN(v); }
  function usd(v) {
    if (!isNum(v)) return "—";
    if (v >= 1e12) return "$" + (v / 1e12).toFixed(2) + "T";
    if (v >= 1e9)  return "$" + (v / 1e9).toFixed(v >= 1e11 ? 0 : 1) + "B";
    if (v >= 1e6)  return "$" + (v / 1e6).toFixed(v >= 1e8 ? 0 : 1) + "M";
    return "$" + Math.round(v).toLocaleString("en-US");
  }
  function relTime(iso) {
    if (!iso) return "—";
    var t = Date.parse(iso); if (isNaN(t)) return "—";
    var d = (Date.now() - t) / 1000;
    if (d < 3600) return Math.max(1, Math.floor(d / 60)) + " 分钟前";
    if (d < 86400) return Math.floor(d / 3600) + " 小时前";
    return Math.floor(d / 86400) + " 天前";
  }
  function quarterZh(p) { // "2026-03-31" -> "2026 Q1"
    if (!p || p.length < 7) return esc(p || "—");
    var q = Math.ceil(parseInt(p.slice(5, 7), 10) / 3);
    return p.slice(0, 4) + " Q" + q;
  }

  var HUES = [258, 42, 200, 152, 330, 20, 220, 96, 288, 8, 176, 68, 244, 130, 310, 52];
  function avatar(i, zh, img, ring, logo, alt) {
    var h = HUES[i % HUES.length];
    var cls = "avatar" + (ring ? " ring-" + ring : "") + (logo ? " logo" : "");
    // 图标加载失败时：若有二级源(公司自身 favicon)先切换，再失败则移除露出首字
    var onerr = alt
      ? "if(!this.dataset.f){this.dataset.f=1;this.src=\"" + esc(alt) + "\"}else{this.remove()}"
      : "this.remove()";
    return "<span class='" + cls +
      "' style='background:linear-gradient(145deg,hsl(" + h + ",62%,62%),hsl(" + (h + 26) + ",55%,42%))'>" +
      esc((zh || "?").charAt(0)) +
      (img ? "<img src='" + esc(img) + "' alt='' loading='lazy' referrerpolicy='no-referrer' onerror='" + onerr + "'>" : "") +
      "</span>";
  }
  /* 中英对照：有中文名则「中文 + 英文小字」，否则只显示英文 */
  function bi(zh, en) {
    if (zh && en && zh !== en) return esc(zh) + " <small class='enm'>" + esc(en) + "</small>";
    return esc(zh || en || "—");
  }

  var CHG = { "new": ["c-new", "新建"], add: ["c-add", "加仓"], trim: ["c-trim", "减持"], exit: ["c-exit", "清仓"] };
  function chgChip(chg, pct) {
    if (!chg || !CHG[chg]) return "";
    var t = CHG[chg][1];
    if (isNum(pct)) t += (pct > 0 ? " +" : " ") + pct.toFixed(0) + "%";
    return "<span class='chip " + CHG[chg][0] + "'>" + t + "</span>";
  }

  /* —— 投资者卡片 —— */
  function invCard(inv, i, pfx) {
    pfx = pfx || "inv";
    var h = "<div class='inv glass' id='" + pfx + i + "'>";
    h += "<button class='invhead' data-toggle='" + pfx + i + "' aria-expanded='false'>";
    h += avatar(i, inv.zh, inv.img, null, inv.imgLogo, inv.imgAlt);
    var firmLine = (inv.firmZh && inv.firmZh !== inv.zh ? esc(inv.firmZh) + " " : "") + esc(inv.firm || "");
    var nm = (inv.flag ? inv.flag + " " : "") + esc(inv.zh);
    h += "<span class='who'><span class='nm'>" + nm + "<small>" + esc(inv.en || "") + "</small></span>" +
      "<span class='meta'>" + (inv.countryZh ? esc(inv.countryZh) + " · " : "") + firmLine + "</span>" +
      "<span class='meta'>" + quarterZh(inv.period) + " · " + (inv.stocks || 0) + " 只持仓 · 前十占 " +
      (isNum(inv.top10pct) ? inv.top10pct.toFixed(0) : "—") + "%</span></span>";
    h += "<span class='val'><span class='v'>" + usd(inv.value) + "</span><span class='k'>组合市值</span></span>";
    h += "<span class='chev'>▼</span></button>";

    h += "<div class='invbody'>";
    var hs = inv.holdings || [];
    if (hs.length) {
      var mx = hs[0].pct || 1;
      h += "<div class='sub-h'>前十大持仓 · 占组合比例</div>";
      hs.forEach(function (x) {
        h += "<div class='hrow' title='" + esc((x.zh ? x.zh + " " : "") + x.name) + " · " + usd(x.value) + " · " + x.pct + "%'>" +
          "<span class='hname'>" + (x.ticker ? "<span class='tk'>" + esc(x.ticker) + "</span>" : "") + bi(x.zh, x.name) +
          chgChip(x.chg, x.chgPct) + "</span>" +
          "<span class='hbar'><i style='width:" + Math.max(2, x.pct / mx * 100).toFixed(1) + "%'></i></span>" +
          "<span class='hpct'>" + x.pct.toFixed(1) + "%</span>" +
          "<span class='hval'>" + usd(x.value) + "</span></div>";
      });
    }
    var mv = inv.moves || [];
    if (mv.length) {
      h += "<div class='sub-h'>本季主要动向（vs 上季 13F）</div><div class='moves'>";
      mv.forEach(function (m) {
        var c = CHG[m.type] || ["", m.type];
        h += "<span class='move'><span class='chip " + c[0] + "' style='margin-left:0'>" + c[1] + "</span> <b>" +
          (m.ticker ? esc(m.ticker) + " " : "") + bi(m.zh, m.name) + "</b>" +
          "<span class='d'>" + (isNum(m.delta) ? (m.delta > 0 ? "+" : "") + m.delta.toFixed(0) + "% · " : "") + usd(m.value) + "</span></span>";
      });
      h += "</div>";
    }
    h += "<div class='sub-h' style='margin-bottom:0'>报告期 " + esc(inv.period || "—") + " · 提交于 " + esc(inv.filed || "—") +
      (inv.manual ? " · <span style='opacity:.7'>手动快照·部分近似</span>" : "") +
      " · <a style='color:var(--accent);text-decoration:none' target='_blank' rel='noopener' href='https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK=" +
      esc(inv.cik) + "&type=13F&dateb=&owner=include&count=10'>SEC 原文 ↗</a></div>";
    h += "</div></div>";
    return h;
  }

  /* —— 大佬共识 —— */
  function consensus(top, big) {
    if (!(top || []).length && !(big || []).length) return "";
    var h = "<div class='sec-h' id='consensus'>🤝 大佬共识<small>剔除期权 · 按持有人数与仓位规模</small></div><div class='duo'>";
    if ((top || []).length) {
      var mx = top[0].gurus || 1;
      h += "<div class='glass'><h3>👑 最多大佬共同持有</h3>";
      top.forEach(function (o) {
        h += "<div class='orow'><span class='n'>" + (o.ticker ? "<span class='tk'>" + esc(o.ticker) + "</span>" : "") +
          bi(o.zh, o.name) + "</span><span class='obar'><i style='width:" + (o.gurus / mx * 100).toFixed(0) + "%'></i></span>" +
          "<span class='ocnt'>" + o.gurus + " 位持有</span></div>";
      });
      h += "</div>";
    }
    if ((big || []).length) {
      h += "<div class='glass'><h3>💰 最大单一重仓</h3>";
      big.forEach(function (b) {
        h += "<div class='orow'><span class='n'>" + (b.ticker ? "<span class='tk'>" + esc(b.ticker) + "</span>" : "") +
          bi(b.zh, b.name) + "<small>" + esc(b.investor) + "</small></span>" +
          "<span class='ocnt' style='flex-basis:70px'>" + usd(b.value) + "</span></div>";
      });
      h += "</div>";
    }
    return h + "</div>";
  }

  /* —— 政治人物交易 —— */
  function rangeUSD(lo, hi) {
    function k(v) {
      if (!isNum(v)) return "?";
      if (v >= 1e6) return (v / 1e6).toFixed(v >= 1e7 ? 0 : 1) + "M";
      if (v >= 1e3) return Math.round(v / 1e3) + "K";
      return "" + Math.round(v);
    }
    if (!isNum(lo) && !isNum(hi)) return "—";
    return "$" + k(lo) + "–" + k(hi);
  }
  var TX = { buy: ["c-new", "买入"], sell: ["c-exit", "卖出"], other: ["c-trim", "其他"] };
  function polCard(p, i) {
    var h = "<div class='inv glass pol' id='pol" + i + "'>";
    h += "<button class='invhead' data-toggle='pol" + i + "' aria-expanded='false'>";
    h += avatar(i + 7, p.zh, p.img, p.party === "D" ? "d" : "r");
    h += "<span class='who'><span class='nm'>" + esc(p.zh) + "<small>" + esc(p.en || "") + "</small></span>" +
      "<span class='meta'>" + esc(p.partyZh || "") + " · " + esc(p.roleZh || "") + " · " + esc(p.stateZh || "") + "</span>" +
      "<span class='meta'>近期 " + (p.count || 0) + " 笔披露 · 最近交易 " + esc(p.lastTrade || "—") + "</span></span>";
    h += "<span class='val'><span class='v' style='color:" + (p.party === "D" ? "#7fa8ff" : "#f08a8a") + "'>" +
      usd(p.volume) + "</span><span class='k'>近期规模(估)</span></span>";
    h += "<span class='chev'>▼</span></button>";
    h += "<div class='invbody'><div class='sub-h'>最近披露的交易（按交易日期）</div>";
    (p.trades || []).forEach(function (t) {
      var c = TX[t.type] || TX.other;
      h += "<div class='trow' title='披露于 " + esc(t.filed || "—") + "'>" +
        "<span class='tdate'>" + esc(t.date || "—") + "</span>" +
        "<span class='chip " + c[0] + "' style='margin-left:0'>" + c[1] + "</span>" +
        "<span class='tname'>" + (t.ticker ? "<span class='tk'>" + esc(t.ticker) + "</span>" : "") + bi(t.zh, t.name) + "</span>" +
        "<span class='trange'>" + rangeUSD(t.lo, t.hi) + "</span></div>";
    });
    h += "<div class='sub-h' style='margin-bottom:0'>金额为披露区间估算 · 披露最长滞后 45 天</div>";
    h += "</div></div>";
    return h;
  }
  function polSection(pols) {
    if (!(pols || []).length) return "";
    var h = "<div class='sec-h' id='pols'>🏛 华盛顿 · 政治人物股票交易<small>共 " + pols.length +
      " 位 · 国会 STOCK Act 披露 · 点击展开近期交易</small></div>";
    pols.forEach(function (p, i) { h += polCard(p, i); });
    return h;
  }

  /* —— 主权财富基金 —— */
  function swfSection(swfs, top20) {
    if (!(swfs || []).length && !(top20 || []).length) return "";
    var h = "<div class='sec-h' id='swf'>🌐 主权财富基金 · 前十大持仓<small>向 SEC 提交 13F 的主权基金 · 点击展开</small></div>";
    (swfs || []).forEach(function (s, i) { h += invCard(s, i, "swf"); });

    if ((top20 || []).length) {
      var mx = top20[0].aum || 1;
      var discN = top20.filter(function (t) { return t.disc; }).length;
      h += "<div class='glass' style='padding:13px 14px 11px;margin-top:6px'>" +
        "<h3 style='font-size:0.9rem;margin-bottom:4px'>🏆 全球前 20 大主权财富基金（按规模）</h3>" +
        "<div style='color:var(--dim);font-size:0.76rem;margin-bottom:9px'>✅ 披露 13F 美股持仓（上方可展开） · ⛔ 不披露/经外部管理人持有</div>";
      top20.forEach(function (t) {
        h += "<div class='orow'><span class='n'>" + (t.flag ? t.flag + " " : "") +
          bi(t.zh, t.en) + " <small style='color:" + (t.disc ? "#7ed09b" : "#e8a878") + "'>" +
          (t.disc ? "✅ 有持仓" : "⛔ 不披露") + "</small></span>" +
          "<span class='obar'><i style='width:" + Math.max(4, t.aum / mx * 100).toFixed(0) + "%'></i></span>" +
          "<span class='ocnt' style='flex-basis:64px'>$" + (t.aum >= 1000 ? (t.aum / 1000).toFixed(2) + "T" : t.aum + "B") + "</span></div>";
      });
      h += "<div style='color:var(--dim);font-size:0.74rem;margin-top:8px;line-height:1.6'>规模为近似值（约 " +
        discN + " 家披露 13F）。ADIA、沙特 PIF、中投、科威特、卡塔尔等不向 SEC 申报，免费公开渠道无美股持仓明细。</div></div>";
    }
    return h;
  }

  /* —— AAII 情绪 —— */
  function seg(cls, v, label) {
    var show = v >= 12;
    return "<span class='" + cls + "' style='flex:" + Math.max(v, 0.5).toFixed(1) + "'>" +
      (show ? v.toFixed(1) + "%" : "") + "</span>";
  }
  function weekRow(w, cls, label) {
    var tip = esc((label || w.date) + " · 看涨 " + w.bull + "% · 中性 " + w.neutral + "% · 看跌 " + w.bear + "%");
    return "<div class='wrow " + (cls || "") + "' title='" + tip + "'>" +
      "<span class='dt'>" + esc(label || (w.date || "").slice(2)) + "</span>" +
      "<span class='wbar'>" + seg("b0", w.bull) + seg("b1", w.neutral) + seg("b2", w.bear) + "</span></div>";
  }
  function aaiiSection(a) {
    if (!a || !(a.weeks || []).length) return "";
    var w0 = a.weeks[0], w1 = a.weeks[1];
    function delta(k) {
      if (!w1) return "";
      var d = w0[k] - w1[k];
      return (d >= 0 ? "+" : "−") + Math.abs(d).toFixed(1) + " vs 上周";
    }
    var h = "<div class='sec-h' id='aaii'>🌡 AAII 投资者情绪调查<small>美国个人投资者协会 · 每周四发布 · 未来六个月股市看法</small></div>";
    h += "<div class='tiles'>" +
      "<div class='tile'><div class='k'>看涨 Bullish</div><div class='v' style='color:#7ed09b'>" + w0.bull.toFixed(1) + "%</div><div class='d'>" + delta("bull") + "</div></div>" +
      "<div class='tile'><div class='k'>中性 Neutral</div><div class='v' style='color:#aeb6c6'>" + w0.neutral.toFixed(1) + "%</div><div class='d'>" + delta("neutral") + "</div></div>" +
      "<div class='tile'><div class='k'>看跌 Bearish</div><div class='v' style='color:#e88985'>" + w0.bear.toFixed(1) + "%</div><div class='d'>" + delta("bear") + "</div></div></div>";

    h += "<div class='aaiicard glass'>";
    h += "<div class='legend'><span><i style='background:var(--bull)'></i>看涨</span>" +
      "<span><i style='background:var(--neu)'></i>中性</span>" +
      "<span><i style='background:var(--bear)'></i>看跌</span>" +
      "<span style='margin-left:auto'>近 " + a.weeks.length + " 周 · 新在上</span></div>";
    a.weeks.forEach(function (w) { h += weekRow(w); });
    if (a.avg) {
      h += "<hr class='divider'>";
      h += weekRow({ bull: a.avg.bull, neutral: a.avg.neutral, bear: a.avg.bear, date: "历史平均" }, "avg", "历史平均");
    }
    var notes = [];
    if (isNum(a.spread)) notes.push("本周<b class='" + (a.spread >= 0 ? "bu'>牛熊差 +" : "be'>牛熊差 −") + Math.abs(a.spread).toFixed(1) + "</b> 个百分点");
    if (a.hi52) notes.push("52 周看涨最高 " + a.hi52.bull + "%（" + esc(a.hi52.date) + "）");
    if (a.lo52) notes.push("最低 " + a.lo52.bull + "%（" + esc(a.lo52.date) + "）");
    if (notes.length) h += "<div class='aaiifoot'>" + notes.join(" · ") + "。情绪极端时常被用作反向参考。</div>";
    return h + "</div>";
  }

  /* —— 主渲染 —— */
  function render(d) {
    var st = $("status");
    var fresh = d.updatedAt && (Date.now() - Date.parse(d.updatedAt)) < 9 * 86400e3;
    if (d.updatedAt) {
      st.className = "status " + (fresh ? "live" : "demo");
      st.innerHTML = "<span class='sdot'></span>" + (fresh ? "实时数据 · 更新于 " + relTime(d.updatedAt) : "数据更新于 " + relTime(d.updatedAt));
    } else {
      st.className = "status demo";
      st.innerHTML = "<span class='sdot'></span>等待首次数据更新";
    }

    var h = "";
    var invs = d.investors || [];
    if (invs.length) {
      h += "<div class='sec-h' id='gurus'>🏛 超级投资者组合<small>共 " + invs.length + " 位 · 点击展开前十大持仓与季度动向</small></div>";
      h += "<input id='invSearch' type='search' placeholder='🔍 搜索投资者 / 机构（中英文均可）…' autocomplete='off'>";
      invs.forEach(function (inv, i) { h += invCard(inv, i); });
      h += consensus(d.topOwned, d.biggest);
    }
    h += swfSection(d.swfs, d.swfTop20);
    h += polSection(d.politicians);
    h += aaiiSection(d.aaii);

    if (!invs.length && !(d.swfs || []).length && !(d.politicians || []).length && !(d.aaii && (d.aaii.weeks || []).length)) {
      h = "<div class='glass empty'><div class='big'>⏳</div>数据尚未生成——首次抓取由每周定时任务完成，稍后再来看看。<br>" +
        "数据源：SEC EDGAR 13F · AAII 情绪调查</div>";
    }
    $("main").innerHTML = h;

    document.querySelectorAll(".invhead").forEach(function (b) {
      b.addEventListener("click", function () {
        var card = document.getElementById(b.getAttribute("data-toggle"));
        if (!card) return;
        var open = card.classList.toggle("open");
        b.setAttribute("aria-expanded", open ? "true" : "false");
      });
    });

    var box = $("invSearch");
    if (box) {
      box.addEventListener("input", function () {
        var q = box.value.trim().toLowerCase();
        invs.forEach(function (inv, i) {
          var hay = (inv.zh + " " + (inv.en || "") + " " + (inv.firm || "") + " " + (inv.firmZh || "")).toLowerCase();
          var card = document.getElementById("inv" + i);
          if (card) card.style.display = (!q || hay.indexOf(q) >= 0) ? "" : "none";
        });
      });
    }

    $("foot").innerHTML = "<div class='src'>数据来源：<b>SEC EDGAR 13F-HR</b>（机构与主权基金季度持仓）· " +
      "<b>国会 STOCK Act 披露</b>（议员交易）· <b>AAII Investor Sentiment Survey</b>（每周四发布）</div>" +
      "<div>" + esc(d.note || "") + "</div>";
  }

  fetch("data.json", { cache: "no-store" })
    .then(function (r) { return r.json(); })
    .then(render)
    .catch(function () {
      $("status").className = "status demo";
      $("status").innerHTML = "<span class='sdot'></span>数据加载失败";
      $("main").innerHTML = "<div class='glass empty'><div class='big'>⚠️</div>数据加载失败，请稍后刷新重试。</div>";
    });
})();
