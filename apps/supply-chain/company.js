/* 单家公司的供应链视图 · 读同目录 nodes.json（由 build_chain_nodes.py 生成）。
   入口：company.html?symbol=AAPL

   这一版能填的真实数据只有身份、环节判定与同行——关系边一条都还没有。
   因此本页的核心不是「展示关系」，而是**说清楚有什么、没有什么、为什么没有**：
   1. 真实数据与占位结构必须一眼分得开（实线=已核验，虚线=待接入，选中不改线型）；
   2. 每一处空缺都要给出原因，不留无解释的空白；
   3. 绝不把「提到」「同行业」当成供应关系。 */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = String(text);
    return n;
  }
  function isNum(v) { return v !== null && v !== undefined && v !== "" && !isNaN(v); }
  function cap(v) {
    if (!isNum(v)) return "—";
    var n = Number(v);
    return n >= 1000 ? (n / 1000).toFixed(2) + " 万亿" : (n * 10).toFixed(0) + " 亿";
  }
  function param(name) {
    var m = new RegExp("[?&]" + name + "=([^&#]*)").exec(location.search);
    return m ? decodeURIComponent(m[1]).toUpperCase() : "";
  }
  function edgarUrl(cik) {
    return "https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK=" +
      String(cik).padStart(10, "0") + "&type=SD&dateb=&owner=include&count=40";
  }

  var STAGE_COLOR = {
    "upstream-resource": "var(--s1)", "intermediate-manufacturing": "var(--s2)",
    "brand-integration": "var(--s3)", "distribution-service": "var(--s4)",
    "platform-service": "var(--s5)", "supporting": "var(--s6)"
  };

  /* 供应链层级。real 表示该层今天是否已有可核验的数据来源。
     gap 是这一层为什么空——每处空缺都要有原因，不留无解释的空白。 */
  var TIERS = [
    { id: "t1", name: "一级供应商", role: "直接供货", real: false,
      body: "直接向该公司供货的企业。",
      gap: "没有免费数据源。两条路线已实测否决：客户集中度披露（ASC 280）要求披露占比但不要求写客户名；" +
           "EDGAR 全文反查按词频排序，提及某公司最多的往往是起诉它的人，不是供应它的人。" },
    { id: "t2", name: "二级供应商", role: "供应商的供应商", real: false,
      body: "更上游一层。",
      gap: "一级都拿不到，二级更无从谈起。" },
    { id: "t3", name: "冶炼厂／精炼厂", role: "锡 · 钽 · 钨 · 金", real: true,
      body: "来自 Form SD 冲突矿产申报，按 RMI 全球统一编号规范化。" +
            "语义是「该冶炼厂出现在申报人的供应链中」——间接、不含份额、不含层级，" +
            "不等于直接供货关系。",
      pending: "抽取器尚未落地：来源已实测可得（6 家样本中 3 家有名单，合计 519 个 RMI 编号），" +
               "但本页目前收录 0 条。" }
  ];

  var state = { data: null, node: null, view: "tier", tierSel: 2 };

  /* ── 身份条：全部真实字段 ── */
  function renderIdent(n) {
    $("c-zh").textContent = n.name || n.symbol;
    $("c-en").textContent = [n.nameEn, n.symbol].filter(Boolean).join(" · ");
    var facts = $("c-facts");
    facts.textContent = "";
    function add(label, value, color) {
      var f = el("span", "fact");
      f.appendChild(document.createTextNode(label + " "));
      var b = el("b", null, value);
      if (color) b.style.color = color;
      f.appendChild(b);
      facts.appendChild(f);
    }
    if (n.sic != null) add("SIC", String(n.sic));
    var stageLabel = (state.data.stages || []).filter(function (s) { return s.id === n.stage; })[0];
    if (stageLabel) add("环节", stageLabel.label, STAGE_COLOR[n.stage]);
    if (n.cik != null) add("CIK", String(n.cik));
    if (isNum(n.marketCap)) add("市值", cap(n.marketCap));
  }

  /* ── 覆盖率声明：本页最重要的一段 ── */
  function renderNotice(n) {
    var edges = ((state.data.coverage || {}).edgesTotal) || 0;
    $("n-title").textContent = edges === 0
      ? "本页尚未收录任何供应链关系"
      : "本页已收录 " + edges + " 条有出处的关系";
    var p = $("n-body");
    p.textContent = "";
    p.appendChild(document.createTextNode(
      edges === 0
        ? "下方展示的是这家公司在价值链中的位置与同行，均为已核验数据；"
          + "供应链关系边一条都还没有——每条关系都必须挂可点开核验的原始申报，没有出处的不会发布。"
        : "每条关系均可点开核验。"));
    var b = el("b", null, "本板块不是完整供应链。");
    b.style.color = "var(--text)";
    p.appendChild(document.createTextNode(" "));
    p.appendChild(b);
  }

  /* ── 视图切换 ── */
  function renderSeg() {
    var seg = $("seg");
    seg.textContent = "";
    [["tier", "层级辐射", "离这家公司几层，以及每层有没有数据"],
     ["geo", "地理分布", "按国别看关系分布——需要关系数据，目前无可定位的条目"]]
      .forEach(function (v) {
        var b = el("button", null, null);
        b.type = "button";
        b.setAttribute("aria-pressed", state.view === v[0] ? "true" : "false");
        b.dataset.view = v[0];
        b.appendChild(el("span", null, v[1]));
        b.addEventListener("click", function () {
          state.view = v[0];
          renderSeg();
          renderFig();
        });
        seg.appendChild(b);
      });
    var active = state.view === "tier" ? 0 : 1;
    $("viewhint").textContent = [
      "离这家公司几层，以及每层有没有数据",
      "按国别看关系分布——需要关系数据，目前无可定位的条目"
    ][active];
  }

  /* ── 辐射图：中心是公司，外环是层级 ── */
  function radialSVG(n) {
    var stageLabel = (state.data.stages || []).filter(function (s) { return s.id === n.stage; })[0];
    var svgns = "http://www.w3.org/2000/svg";
    var svg = document.createElementNS(svgns, "svg");
    svg.setAttribute("viewBox", "0 0 640 340");
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label",
      (n.name || n.symbol) + " 的供应链层级示意：内两环为待接入，外环为冲突矿产冶炼厂");
    svg.style.width = "100%"; svg.style.height = "auto"; svg.style.display = "block";
    function add(tag, attrs, text) {
      var e = document.createElementNS(svgns, tag);
      Object.keys(attrs).forEach(function (k) { e.setAttribute(k, attrs[k]); });
      if (text != null) e.textContent = text;
      svg.appendChild(e);
      return e;
    }
    [[62, "rgba(125,111,209,.30)", null], [104, "rgba(74,144,217,.26)", null],
     [150, "rgba(63,174,125,.32)", "2 4"]].forEach(function (r) {
      var c = add("circle", { cx: 320, cy: 176, r: r[0], fill: "none",
        stroke: r[1], "stroke-width": 1 });
      if (r[2]) c.setAttribute("stroke-dasharray", r[2]);
    });
    [[108, "#7d6fd1", "一级供应商 · 待接入"], [66, "#4a90d9", "二级供应商 · 待接入"],
     [20, "#3fae7d", "冶炼厂 · 来源已实测可得"]].forEach(function (t) {
      add("text", { x: 320, y: t[0], "text-anchor": "middle", fill: t[1], "font-size": 9,
        "font-family": "-apple-system,'PingFang SC',sans-serif" }, t[2]);
    });
    // 内两环空着：不画任何节点，因为一条都没有
    add("circle", { cx: 320, cy: 176, r: 30, fill: "#141922",
      stroke: STAGE_COLOR[n.stage] || "#4a90d9", "stroke-width": 1.5 });
    add("text", { x: 320, y: 173, "text-anchor": "middle", fill: "#eaf0f3",
      "font-size": 12, "font-weight": 700,
      "font-family": "-apple-system,'PingFang SC',sans-serif" }, n.name || n.symbol);
    add("text", { x: 320, y: 187, "text-anchor": "middle", fill: "#93a0b2", "font-size": 7.5,
      "font-family": "-apple-system,'PingFang SC',sans-serif" },
      stageLabel ? stageLabel.label : "");
    return svg;
  }

  function renderFig() {
    var fig = $("fig");
    fig.textContent = "";
    var n = state.node;

    if (state.view === "geo") {
      var box = el("div", null, null);
      box.style.cssText = "padding:40px 20px;text-align:center;";
      box.appendChild(el("div", null, "地理分布视图需要关系数据"))
        .style.cssText = "font-size:.95rem;font-weight:700;margin-bottom:7px;";
      var why = el("div", null,
        "这个视图按对手方所在国别把关系标到地图上。目前本页收录 0 条关系，"
        + "没有可定位的条目——与其画一张空地图，不如先说清楚。");
      why.style.cssText = "font-size:.8rem;color:var(--dim);max-width:460px;margin:0 auto;line-height:1.65;";
      box.appendChild(why);
      var next = el("div", null,
        "Form SD 冶炼厂清单带国别字段，抽取器落地后这个视图即可启用。");
      next.style.cssText = "font-size:.76rem;color:var(--faint);margin-top:10px;";
      box.appendChild(next);
      fig.appendChild(box);
      return;
    }

    fig.appendChild(radialSVG(n));

    var picks = el("div", "picks");
    TIERS.forEach(function (t, i) {
      var b = el("button", "pick " + (t.real ? "real" : "demo"));
      b.type = "button";
      b.setAttribute("aria-pressed", state.tierSel === i ? "true" : "false");
      var hd = el("div", "hd");
      var dot = el("span");
      dot.style.cssText = "width:11px;height:11px;border-radius:50%;flex:none;"
        + (t.real ? "background:#3fae7d;" : "border:1px dashed rgba(228,181,61,.65);");
      hd.appendChild(dot);
      hd.appendChild(el("b", null, t.name));
      var tag = el("span", t.real ? "chip ok" : "chip", t.real ? "来源可得" : "无数据源");
      tag.style.marginLeft = "auto";
      hd.appendChild(tag);
      b.appendChild(hd);
      b.appendChild(el("div", "role", t.role + " · 已收录 0 条"));
      b.addEventListener("click", function () {
        state.tierSel = i;
        // 只改选中状态，不重建这批按钮——重建会销毁当前被聚焦的元素，
        // 键盘用户按回车后焦点就丢了。
        Array.prototype.forEach.call(picks.children, function (other, j) {
          other.setAttribute("aria-pressed", j === i ? "true" : "false");
        });
        renderSide();
      });
      picks.appendChild(b);
    });
    fig.appendChild(picks);

    var note = el("div", "fignote");
    note.appendChild(el("span", "chip", "内两环无数据源，外环来源可得但抽取器待落地"));
    fig.appendChild(note);
  }

  /* ── 右栏：出处 + 同行 + 真实数据清单 ── */
  function renderSide() {
    var side = $("side");
    side.textContent = "";
    var n = state.node;
    var d = state.data;

    // 出处栏
    var t = TIERS[state.tierSel] || TIERS[0];
    var src = el("div", "glass");
    src.style.cssText = "padding:13px 15px;";
    src.appendChild(el("h3", null, "出处 · " + t.name));
    var body = el("div", null, t.body);
    body.style.cssText = "font-size:.75rem;color:var(--dim);margin-bottom:10px;";
    src.appendChild(body);
    if (t.real) {
      var okBox = el("div");
      okBox.style.cssText = "border-top:1px solid var(--line);padding-top:9px;";
      var pend = el("div", null, t.pending);
      pend.style.cssText = "font-size:.73rem;color:var(--dim);margin-bottom:6px;";
      okBox.appendChild(pend);
      if (n.cik != null) {
        var a = el("a", null, "该公司的 Form SD 申报 →");
        a.href = edgarUrl(n.cik);
        a.target = "_blank"; a.rel = "noopener noreferrer";
        a.style.cssText = "font-size:.78rem;color:var(--accent);text-decoration:none;";
        okBox.appendChild(a);
      }
      src.appendChild(okBox);
    } else {
      var gapBox = el("div");
      gapBox.style.cssText = "border-top:1px dashed rgba(228,181,61,.35);padding-top:9px;";
      var g = el("div", null, t.gap);
      g.style.cssText = "font-size:.73rem;color:var(--warn);line-height:1.6;";
      gapBox.appendChild(g);
      src.appendChild(gapBox);
    }
    side.appendChild(src);

    // 环节判定依据（真实）
    var basis = el("div", "glass");
    basis.style.cssText = "padding:13px 15px;border-color:rgba(63,174,125,.28);";
    basis.appendChild(el("h3", null, "环节判定依据"));
    var bn = el("div", null, n.stageNote || "—");
    bn.style.cssText = "font-size:.75rem;color:var(--dim);margin-bottom:8px;";
    basis.appendChild(bn);
    if (n.stageEvidence && n.stageEvidence.url) {
      var ea = el("a", null, "SEC 申报索引 →");
      ea.href = n.stageEvidence.url;
      ea.target = "_blank"; ea.rel = "noopener noreferrer";
      ea.style.cssText = "font-size:.78rem;color:var(--accent);text-decoration:none;";
      basis.appendChild(ea);
    }
    side.appendChild(basis);

    // 同 SIC 同行（真实且有用）
    var sameSic = (d.nodes || []).filter(function (x) {
      return x.sic != null && x.sic === n.sic && x.symbol !== n.symbol;
    }).sort(function (a, b) { return (b.marketCap || 0) - (a.marketCap || 0); });
    var peers = el("div", "glass");
    peers.style.cssText = "padding:13px 15px;";
    peers.appendChild(el("h3", null, "同行业（SIC " + (n.sic != null ? n.sic : "—") + "）"));
    if (sameSic.length) {
      sameSic.slice(0, 8).forEach(function (p) {
        var row = el("div", "peer");
        var a = el("a", null, p.name || p.symbol);
        a.href = "company.html?symbol=" + encodeURIComponent(p.symbol);
        row.appendChild(a);
        row.appendChild(el("span", "sym", p.symbol));
        peers.appendChild(row);
      });
      if (sameSic.length > 8) {
        var more = el("div", null, "另有 " + (sameSic.length - 8) + " 家");
        more.style.cssText = "font-size:.73rem;color:var(--faint);padding-top:7px;";
        peers.appendChild(more);
      }
    } else {
      var none = el("div", null, "标普500里没有同 SIC 的其他公司。");
      none.style.cssText = "font-size:.75rem;color:var(--dim);";
      peers.appendChild(none);
    }
    side.appendChild(peers);

    // 本页真实数据清单
    var real = el("div", "glass");
    real.style.cssText = "padding:13px 15px;";
    real.appendChild(el("h3", null, "本页哪些是真实数据"));
    var sameStage = (d.nodes || []).filter(function (x) { return x.stage === n.stage; }).length;
    [["身份与市值", "站内公司榜"], ["环节判定", "SEC 官方 SIC 行业码"],
     ["同行业公司", sameSic.length + " 家"], ["同环节公司", sameStage + " 家"],
     ["供应链关系", "0 条"]].forEach(function (pair) {
      var kv = el("div", "kv");
      kv.appendChild(el("span", null, pair[0]));
      var v = el("b", null, pair[1]);
      v.style.color = pair[1] === "0 条" ? "var(--warn)" : "var(--text)";
      v.style.fontWeight = "600";
      kv.appendChild(v);
      real.appendChild(kv);
    });
    side.appendChild(real);
  }

  function fail(msg) {
    var s = $("state");
    s.className = "state err";
    s.textContent = msg;
    s.hidden = false;
  }

  fetch("nodes.json", { cache: "no-cache" })
    .then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    })
    .then(function (d) {
      if (!d || !Array.isArray(d.nodes) || !d.nodes.length) throw new Error("数据文件为空或结构不符");
      var symbol = param("symbol");
      if (!symbol) { fail("网址里没有指定公司代码。请从产业链页面的公司表进入。"); return; }
      var node = d.nodes.filter(function (x) { return (x.symbol || "").toUpperCase() === symbol; })[0];
      if (!node) { fail("产业链节点表里没有 " + symbol + "。本板块目前只收录标普500成分股。"); return; }
      state.data = d; state.node = node;
      document.title = (node.name || symbol) + " 供应链视图 · 全球产业链";
      renderIdent(node); renderNotice(node); renderSeg(); renderFig(); renderSide();
      $("state").hidden = true;
      $("body").hidden = false;
    })
    .catch(function (err) {
      fail("公司数据加载失败：" + (err && err.message ? err.message : "未知错误")
        + "。这是加载问题，不代表数据不存在——请稍后重试。");
    });
})();
