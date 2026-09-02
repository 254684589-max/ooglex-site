/* 单家公司的供应链视图 · 读同目录 nodes.json（由 build_chain_nodes.py 生成）。
   入口：company.html?symbol=AAPL

   最外环（冲突矿产冶炼厂）已有真实数据，来自 Form SD 申报，按需从
   edges/<代码>.json 拉取；内两环仍无数据源。因此本页的核心始终是
   **说清楚有什么、没有什么、为什么没有**：
   1. 真实数据与占位结构必须一眼分得开（实线=已核验，虚线=待接入，选中不改线型）；
   2. 每一处空缺都要给出原因，不留无解释的空白；
   3. 绝不把「提到」「同行业」当成供应关系；
   4. 冶炼厂那一层的语义必须照实写：「出现在申报人供应链中」≠「是供应商」。
      条目分两类——带 RMI 编号的可跨公司比对，只有名字的不行，页面必须分开说。 */
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
      body: "来自该公司的 Form SD 冲突矿产申报。语义是「该冶炼厂出现在申报人的供应链中」" +
            "——间接、不含份额、不含层级，不等于直接供货关系。",
      pending: "这家公司提交了 Form SD，但申报正文里没有可解析的冶炼厂名单。" +
               "Form SD 强制申报、不强制列名单，因此这一栏空着是披露本身的形态，" +
               "不是抓取失败。" }
  ];

  var state = { data: null, node: null, view: "tier", tierSel: 2,
                edges: null, edgeError: null };

  /* 这家公司有没有边文件。没有 ≠ 没申报，两者在页面上必须分开说。 */
  function edgeMeta() { return ((state.data || {}).edgeIndex || {})[state.node.symbol] || null; }
  function edgeRows() { return (state.edges && state.edges.edges) || []; }
  function idCounts() {
    var cid = 0, nameOnly = 0;
    edgeRows().forEach(function (e) {
      if (e.identifierType === "rmi-cid") cid++; else nameOnly++;
    });
    return { cid: cid, nameOnly: nameOnly };
  }
  function byCountry() {
    var map = {};
    edgeRows().forEach(function (e) {
      var k = e.country || "未归类";
      map[k] = (map[k] || 0) + 1;
    });
    return Object.keys(map).map(function (k) { return { country: k, count: map[k] }; })
      .sort(function (a, b) { return b.count - a.count || a.country.localeCompare(b.country); });
  }

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
  function renderNotice() {
    var rows = edgeRows();
    var meta = edgeMeta();
    var counts = idCounts();
    $("n-title").textContent = rows.length
      ? "本页收录 " + rows.length + " 家冶炼厂，均带可核验出处"
      : "本页尚未收录任何供应链关系";
    var p = $("n-body");
    p.textContent = "";
    if (rows.length) {
      p.appendChild(document.createTextNode(
        "全部来自该公司的 Form SD 冲突矿产申报，每一条都能点开原始文件核对。"
        + "语义是「该冶炼厂出现在申报人的供应链中」——间接、不含份额、不含层级，"
        + "不是直接供货关系。一级与二级供应商仍无数据源。"
        + (counts.nameOnly
            ? "其中 " + counts.nameOnly + " 条只有名字没有 RMI 编号，无法与其他公司的名单精确比对。"
            : "")));
    } else if (state.edgeError) {
      p.appendChild(document.createTextNode(
        "关系数据加载失败（" + state.edgeError + "）。这是加载问题，不代表数据不存在。"));
    } else if (meta) {
      p.appendChild(document.createTextNode(
        "索引里登记了这家公司的边文件，但内容还没读到。请刷新重试。"));
    } else {
      p.appendChild(document.createTextNode(
        "下方展示的是这家公司在价值链中的位置与同行，均为已核验数据；"
        + "供应链关系边一条都还没有——每条关系都必须挂可点开核验的原始申报，没有出处的不会发布。"));
    }
    var b = el("b", null, "本板块不是完整供应链。");
    b.style.color = "var(--text)";
    p.appendChild(document.createTextNode(" "));
    p.appendChild(b);
  }

  /* ── 视图切换 ── */
  function renderSeg() {
    var seg = $("seg");
    seg.textContent = "";
    var rows = edgeRows();
    var geoHint = rows.length
      ? "按冶炼厂所在国别分布 · " + byCountry().length + " 个国家／地区"
      : "按国别看关系分布——需要关系数据，目前无可定位的条目";
    [["tier", "层级辐射", "离这家公司几层，以及每层有没有数据"],
     ["geo", "地理分布", geoHint]]
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
    $("viewhint").textContent = state.view === "tier"
      ? "离这家公司几层，以及每层有没有数据" : geoHint;
  }

  /* ── 辐射图：中心是公司，外环是层级 ── */
  function radialSVG(n) {
    var stageLabel = (state.data.stages || []).filter(function (s) { return s.id === n.stage; })[0];
    var svgns = "http://www.w3.org/2000/svg";
    var svg = document.createElementNS(svgns, "svg");
    svg.setAttribute("viewBox", "0 0 640 340");
    svg.setAttribute("role", "img");
    var rows = edgeRows();
    svg.setAttribute("aria-label",
      (n.name || n.symbol) + " 的供应链层级示意：内两环无数据源，外环为 "
      + rows.length + " 家冲突矿产冶炼厂");
    svg.style.width = "100%"; svg.style.height = "auto"; svg.style.display = "block";
    function add(tag, attrs, text) {
      var e = document.createElementNS(svgns, tag);
      Object.keys(attrs).forEach(function (k) { e.setAttribute(k, attrs[k]); });
      if (text != null) e.textContent = text;
      svg.appendChild(e);
      return e;
    }
    // 线型是这一页的语言：实线=有已核验数据，虚线=无数据源。选中不改线型。
    // 外环今天有真实名单了，因此从虚线改为实线——这是数据变了，不是样式偏好。
    [[62, "rgba(125,111,209,.30)", "2 4"], [104, "rgba(74,144,217,.26)", "2 4"],
     [150, "rgba(63,174,125,.42)", rows.length ? null : "2 4"]].forEach(function (r) {
      var c = add("circle", { cx: 320, cy: 176, r: r[0], fill: "none",
        stroke: r[1], "stroke-width": 1 });
      if (r[2]) c.setAttribute("stroke-dasharray", r[2]);
    });
    [[108, "#7d6fd1", "一级供应商 · 无数据源"], [66, "#4a90d9", "二级供应商 · 无数据源"],
     [20, "#3fae7d", rows.length
        ? "冶炼厂 · " + rows.length + " 家（Form SD 申报）"
        : "冶炼厂 · 本次申报无名单"]].forEach(function (t) {
      add("text", { x: 320, y: t[0], "text-anchor": "middle", fill: t[1], "font-size": 9,
        "font-family": "-apple-system,'PingFang SC',sans-serif" }, t[2]);
    });
    // 外环上按国别把冶炼厂点出来。点数多于 120 时只画 120 个并在图注里说明——
    // 画满几百个点只会糊成一圈，看不出分布，也不比数字更诚实。
    var drawn = rows.slice(0, 120);
    drawn.forEach(function (e, i) {
      var angle = (i / drawn.length) * Math.PI * 2 - Math.PI / 2;
      add("circle", {
        cx: (320 + 150 * Math.cos(angle)).toFixed(1),
        cy: (176 + 150 * Math.sin(angle)).toFixed(1),
        r: 2.4, fill: e.identifierType === "rmi-cid" ? "#3fae7d" : "#4a90d9",
        opacity: .85
      });
    });
    // 内两环不画任何节点，因为一条都没有
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

  /* ── 地理分布：按冶炼厂所在国别汇总 ──
     不画地图。名单只给国别、不给坐标，画地图等于把「这个国家有 N 家」
     伪装成「这些点在这些位置」。条形表说的正好是数据支持的那句话。 */
  function geoView() {
    var rows = edgeRows();
    var box = el("div", null, null);
    if (!rows.length) {
      box.style.cssText = "padding:40px 20px;text-align:center;";
      var hd = el("div", null, "这家公司没有可定位的关系条目");
      hd.style.cssText = "font-size:.95rem;font-weight:700;margin-bottom:7px;";
      box.appendChild(hd);
      var why = el("div", null, edgeMeta()
        ? "边文件还没读到，请刷新重试。"
        : "它提交了 Form SD，但申报正文里没有可解析的冶炼厂名单——"
          + "Form SD 强制申报、不强制列名单。与其画一张空地图，不如先说清楚。");
      why.style.cssText = "font-size:.8rem;color:var(--dim);max-width:460px;"
        + "margin:0 auto;line-height:1.65;";
      box.appendChild(why);
      return box;
    }

    var list = byCountry();
    var max = list[0].count;
    var head = el("div", null, null);
    head.style.cssText = "display:flex;justify-content:space-between;align-items:baseline;"
      + "gap:10px;margin-bottom:10px;flex-wrap:wrap;";
    var h = el("b", null, list.length + " 个国家／地区 · " + rows.length + " 家冶炼厂");
    h.style.fontSize = ".88rem";
    head.appendChild(h);
    var sub = el("span", null, "按申报里写明的所在国别汇总，未写明的计入「未归类」");
    sub.style.cssText = "font-size:.72rem;color:var(--faint);";
    head.appendChild(sub);
    box.appendChild(head);

    var wrap = el("div", null, null);
    wrap.style.cssText = "max-height:360px;overflow-y:auto;padding-right:4px;";
    list.forEach(function (row) {
      var line = el("div", null, null);
      line.style.cssText = "display:grid;grid-template-columns:110px 1fr 48px;"
        + "align-items:center;gap:9px;padding:3px 0;";
      var name = el("span", null, row.country);
      name.style.cssText = "font-size:.76rem;color:"
        + (row.country === "未归类" ? "var(--faint)" : "var(--text)")
        + ";overflow:hidden;text-overflow:ellipsis;white-space:nowrap;";
      line.appendChild(name);
      var track = el("div", null, null);
      track.style.cssText = "height:9px;border-radius:3px;background:rgba(255,255,255,.05);";
      var bar = el("div", null, null);
      bar.style.cssText = "height:9px;border-radius:3px;background:"
        + (row.country === "未归类" ? "rgba(147,160,178,.5)" : "rgba(63,174,125,.75)")
        + ";width:" + Math.max(2, (row.count / max) * 100).toFixed(1) + "%;";
      track.appendChild(bar);
      line.appendChild(track);
      var num = el("span", null, String(row.count));
      num.style.cssText = "font-family:var(--mono);font-size:.72rem;color:var(--dim);"
        + "text-align:right;";
      line.appendChild(num);
      wrap.appendChild(line);
    });
    box.appendChild(wrap);
    return box;
  }

  function renderFig() {
    var fig = $("fig");
    fig.textContent = "";
    var n = state.node;

    if (state.view === "geo") {
      fig.appendChild(geoView());
      return;
    }

    fig.appendChild(radialSVG(n));

    var picks = el("div", "picks");
    TIERS.forEach(function (t, i) {
      // 线型跟着数据走：有已核验条目才是实线卡片。这一层今天有没有名单是变量，
      // 不能按 TIERS 里写死的 real 画——那会把「有申报无名单」画成已核验。
      var hasData = i === 2 ? edgeRows().length > 0 : false;
      var b = el("button", "pick " + (hasData ? "real" : "demo"));
      b.type = "button";
      b.setAttribute("aria-pressed", state.tierSel === i ? "true" : "false");
      var hd = el("div", "hd");
      var dot = el("span");
      dot.style.cssText = "width:11px;height:11px;border-radius:50%;flex:none;"
        + (t.real ? "background:#3fae7d;" : "border:1px dashed rgba(228,181,61,.65);");
      hd.appendChild(dot);
      hd.appendChild(el("b", null, t.name));
      var count = i === 2 ? edgeRows().length : 0;
      var tag = el("span", count ? "chip ok" : "chip",
        count ? "已核验" : (t.real ? "本次申报无名单" : "无数据源"));
      tag.style.marginLeft = "auto";
      hd.appendChild(tag);
      b.appendChild(hd);
      b.appendChild(el("div", "role", t.role + " · 已收录 " + count + " 条"));
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
    var rowCount = edgeRows().length;
    var text = rowCount
      ? ("内两环无数据源；外环 " + rowCount + " 家已核验"
         + (rowCount > 120 ? "，图上只画前 120 个点" : "")
         + (idCounts().nameOnly ? "，蓝点为无 RMI 编号的条目" : ""))
      : "内两环无数据源；这家公司本次申报未列冶炼厂名单";
    note.appendChild(el("span", rowCount ? "chip ok" : "chip", text));
    fig.appendChild(note);
  }

  /* ── 右栏：出处 + 同行 + 真实数据清单 ── */
  /* ── 冶炼厂清单（主栏）──
     这一页唯一的真实关系数据。厂名即链接，点开就是这条边的原始申报文件。 */
  function renderSmelters() {
    var host = $("smelters");
    host.textContent = "";
    var rows = edgeRows();
    if (!rows.length) return;

    var counts = idCounts();
    var mixed = counts.cid > 0 && counts.nameOnly > 0;
    var box = el("section", "glass smelters");
    box.setAttribute("aria-label", "冶炼厂清单");
    var head = el("div", null, null);
    head.style.cssText = "display:flex;justify-content:space-between;align-items:baseline;"
      + "gap:12px;flex-wrap:wrap;margin-bottom:10px;";
    head.appendChild(el("h3", null, "冶炼厂／精炼厂清单（" + rows.length + " 家）"));
    var sub = el("span", null,
      "出现在该公司 Form SD 申报供应链中 · 不是直接供货关系 · 点厂名看原始申报"
      // 全体同一种标识时在这里说一次就够，不必每行都挂一个标签
      + (mixed ? "" : (counts.cid ? " · 全部带 RMI 编号" : " · 全部只有名字、无 RMI 编号")));
    sub.style.cssText = "font-size:.72rem;color:var(--dim);";
    head.appendChild(sub);
    box.appendChild(head);

    var grid = el("div", "grid");
    rows.slice().sort(function (a, b) {
      return String(a.name || a.from).localeCompare(String(b.name || b.from));
    }).forEach(function (e) {
      var item = el("div", "sm");
      var ev = (e.evidence || [])[0] || {};
      var nm;
      if (ev.url) {
        nm = el("a", "nm sm-nm", e.name || e.from);
        nm.href = ev.url;
        nm.target = "_blank"; nm.rel = "noopener noreferrer";
      } else {
        nm = el("span", "nm", e.name || e.from);
      }
      item.appendChild(nm);
      var bits = [e.country || "国别未写明", (e.minerals || []).join("·") || "矿种未写明"];
      var meta = el("div", "meta", bits.join("  ·  "));
      if (e.cid) {
        meta.appendChild(document.createTextNode("  ·  "));
        meta.appendChild(el("span", "cid", e.cid));
      } else if (mixed) {
        meta.appendChild(document.createTextNode("  ·  "));
        var no = el("span", "cid", "无编号");
        no.style.color = "var(--warn)";
        meta.appendChild(no);
      }
      item.appendChild(meta);
      grid.appendChild(item);
    });
    box.appendChild(grid);
    host.appendChild(box);
  }

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
      var rows = edgeRows();
      var okBox = el("div");
      okBox.style.cssText = "border-top:1px solid var(--line);padding-top:9px;";
      if (rows.length) {
        var f = (state.edges && state.edges.filing) || {};
        var counts = idCounts();
        [["申报日", f.filingDate || "—"],
         ["冶炼厂", rows.length + " 家"],
         ["带 RMI 编号", counts.cid + " 家"],
         ["仅有名字", counts.nameOnly + " 家"]].forEach(function (pair) {
          var kv = el("div", "kv");
          kv.appendChild(el("span", null, pair[0]));
          kv.appendChild(el("b", null, pair[1]));
          okBox.appendChild(kv);
        });
        if (counts.nameOnly) {
          var caveat = el("div", null,
            "「仅有名字」的条目没有 RMI 全球编号，只能按名字比对，"
            + "无法确认与其他公司名单里的同名厂是不是同一家。");
          caveat.style.cssText = "font-size:.7rem;color:var(--warn);line-height:1.6;"
            + "margin-top:7px;";
          okBox.appendChild(caveat);
        }
        if (f.url) {
          var da = el("a", null, "打开原始冲突矿产报告 →");
          da.href = f.url;
          da.target = "_blank"; da.rel = "noopener noreferrer";
          da.style.cssText = "font-size:.78rem;color:var(--accent);text-decoration:none;"
            + "display:block;margin-top:9px;";
          okBox.appendChild(da);
        }
      } else {
        var pend = el("div", null, t.pending);
        pend.style.cssText = "font-size:.73rem;color:var(--dim);margin-bottom:6px;";
        okBox.appendChild(pend);
      }
      if (n.cik != null) {
        var a = el("a", null, "该公司的全部 Form SD 申报 →");
        a.href = edgarUrl(n.cik);
        a.target = "_blank"; a.rel = "noopener noreferrer";
        a.style.cssText = "font-size:.78rem;color:var(--accent);text-decoration:none;"
          + "display:block;margin-top:6px;";
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
    var rows = edgeRows();
    [["身份与市值", "站内公司榜"], ["环节判定", "SEC 官方 SIC 行业码"],
     ["同行业公司", sameSic.length + " 家"], ["同环节公司", sameStage + " 家"],
     ["冶炼厂关系", rows.length + " 条"],
     ["一级／二级供应商", "0 条（无数据源）"]].forEach(function (pair) {
      var kv = el("div", "kv");
      kv.appendChild(el("span", null, pair[0]));
      var v = el("b", null, pair[1]);
      v.style.color = /(^|\D)0 条/.test(pair[1]) ? "var(--warn)" : "var(--text)";
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
      return loadEdges().then(paint);
    })
    .catch(function (err) {
      fail("公司数据加载失败：" + (err && err.message ? err.message : "未知错误")
        + "。这是加载问题，不代表数据不存在——请稍后重试。");
    });

  /* 边按公司分文件，只在这家公司确实有边时才拉——
     总览页 495 家里绝大多数没有边文件，不该为此多发一次请求。
     拉失败不阻断整页：身份、环节、同行都是本地已有的真实数据，
     照常渲染，并在覆盖率声明里说清楚是加载失败而不是没有数据。 */
  function loadEdges() {
    var meta = edgeMeta();
    if (!meta || !meta.file) return Promise.resolve();
    return fetch(meta.file, { cache: "no-cache" })
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (bundle) {
        if (!bundle || !Array.isArray(bundle.edges)) throw new Error("边文件结构不符");
        if (bundle.symbol !== state.node.symbol) {
          throw new Error("边文件属于 " + bundle.symbol + "，与本页不符");
        }
        state.edges = bundle;
      })
      .catch(function (err) {
        state.edges = null;
        state.edgeError = (err && err.message) || "未知错误";
      });
  }

  function paint() {
    renderIdent(state.node); renderNotice(); renderSeg(); renderFig();
    renderSmelters(); renderSide();
    $("state").hidden = true;
    $("body").hidden = false;
  }
})();
