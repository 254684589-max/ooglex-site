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
                edges: null, edgeError: null, zh: null, peers: null };

  /* 冶炼厂中文译名。查不到就显示英文原文——申报里写的就是英文，
     半译出来的名字比纯英文更糟。译名表独立发布，拉不到不影响其它内容。 */
  function zhKey(name) {
    return String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "");
  }
  function zhName(name) {
    var table = (state.zh && state.zh.names) || null;
    return table ? (table[zhKey(name)] || null) : null;
  }

  /* 这家公司有没有边文件。没有 ≠ 没申报，两者在页面上必须分开说。 */
  function edgeMeta() { return ((state.data || {}).edgeIndex || {})[state.node.symbol] || null; }
  function edgeRows() { return (state.edges && state.edges.edges) || []; }
  function idCounts() {
    var cid = 0, nameOnly = 0;
    edgeRows().forEach(function (e) {
      if (e.idType === "rmi-cid") cid++; else nameOnly++;
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
    var zh = n.name || n.symbol;
    $("c-zh").textContent = zh;
    // 中文名缺失时上游会回退成英文名，此时主副标题内容相同，不重复显示
    // （总览表早就这么处理了，这里漏了——Skyworks 的标题显示成
    //  「Skyworks Solutions Skyworks Solutions · SWKS」）
    $("c-en").textContent = [n.nameEn !== zh ? n.nameEn : null, n.symbol]
      .filter(Boolean).join(" · ");
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
    // 外国私人发行人这一池：没有站内行情、没有站内板块分类，
    // 什么都不显示会让读者以为是数据缺失。如实说明它属于哪一池、
    // 国别取自哪个字段——「注册地」和「总部在哪」不是一回事。
    if (n.pool === "sec-foreign-issuer") {
      // **经营地在前，注册地在后。**
      //
      // 总览页的地理汇总用的是经营地（开曼 340 家折回中国 236、新加坡 79…），
      // 而这里此前只印注册地——422 家注册地≠经营地的公司，读者在总览页看到
      // 「中国 236 家」，点进来却写着「国别 开曼群岛」。**两个页面对同一家
      // 公司说了不同的话**，比两处都印注册地更糟。
      //
      // 注册地不删：它是 SEC 备案里的事实，而且「注册在开曼」本身是信息
      // （控股架构）。两个都印、各自标清是什么，读者才能自己判断。
      var offshore = n.offshoreIncorporation && n.geoCountry
        && n.geoCountry !== n.country;
      if (offshore) {
        add("经营地", n.geoCountry + (n.operatingRegion ? "（" + n.operatingRegion + "）" : ""));
        add("注册地", n.country);
      } else if (n.country) {
        add("国别", n.country + (n.region ? "（" + n.region + "）" : ""));
      }
      if (n.exchange) add("上市地", n.exchange);
      var why = offshore
        ? "这家注册在" + n.country + "——开曼、英属维尔京、马绍尔、百慕大这类法域"
          + "只做登记，注册地回答不了「在哪做生意」，所以按 SEC 备案的营业地址"
          + "记为经营地；总览页的国别汇总用的也是经营地，两处一致"
        : (n.countryBasis === "state-of-incorporation"
            ? "国别取自 SEC 备案的注册地（依哪国法律成立），不等于总部所在地"
            : (n.countryBasis ? "国别取自 SEC 备案地址" : "SEC 备案里没有可用的地区字段"));
      var tip = $("c-pool");
      if (tip) {
        tip.hidden = false;
        tip.textContent = "在美上市的外国私人发行人（报 20-F／40-F）。"
          + "站内公司榜只收标普500成分股，因此这一家没有市值与板块分类——"
          + "是口径如此，不是取数失败。" + why + "。";
      }
    } else if ($("c-pool")) {
      $("c-pool").hidden = true;
    }
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
        r: 2.4, fill: e.idType === "rmi-cid" ? "#3fae7d" : "#4a90d9",
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
  // 清单筛选：矿种（3TG）× 国别。两个维度都已在边数据里，不需要新取数。
  // **筛选只是取子集，不改变任何一条边的语义**——每条仍然是「该冶炼厂出现在
  // 申报人的供应链中」，仍然点得开原始申报。
  var filt = { mineral: "", country: "" };

  function matchFilter(e) {
    if (filt.mineral && (e.minerals || []).indexOf(filt.mineral) < 0) return false;
    if (filt.country && (e.country || "未写明") !== filt.country) return false;
    return true;
  }

  // 某一维的取值分布。计数用的是**另一维已筛之后**的集合，
  // 这样按钮上的数就是「点下去会得到几条」，不是一个对不上的总数。
  function facet(rows, key, other) {
    var map = {};
    rows.forEach(function (e) {
      if (!other(e)) return;
      var vals = key === "mineral"
        ? (e.minerals && e.minerals.length ? e.minerals : ["未写明"])
        : [e.country || "未写明"];
      vals.forEach(function (v) { map[v] = (map[v] || 0) + 1; });
    });
    return Object.keys(map).map(function (k) { return { k: k, n: map[k] }; })
      .sort(function (a, b) { return b.n - a.n || a.k.localeCompare(b.k); });
  }

  function filterBar(rows, onChange) {
    var bar = el("div", "smfilt");
    function group(label, key, items, cap) {
      if (items.length < 2) return;              // 只有一类就不必给筛选
      var g = el("div", "fg");
      g.appendChild(el("span", "lb", label));
      var all = el("button", "fb" + (filt[key] ? "" : " on"));
      all.type = "button";
      all.textContent = "全部";
      all.setAttribute("aria-pressed", filt[key] ? "false" : "true");
      all.onclick = function () { filt[key] = ""; shownCount = PAGE; onChange(); };
      g.appendChild(all);
      items.slice(0, cap).forEach(function (it) {
        var b = el("button", "fb" + (filt[key] === it.k ? " on" : ""));
        b.type = "button";
        b.setAttribute("aria-pressed", filt[key] === it.k ? "true" : "false");
        b.appendChild(document.createTextNode(it.k));
        b.appendChild(el("s", null, String(it.n)));
        b.onclick = function () {
          filt[key] = (filt[key] === it.k) ? "" : it.k;
          shownCount = PAGE;          // 换了筛选就回到第一批，否则会停在上一次的位置
          onChange();
        };
        g.appendChild(b);
      });
      if (items.length > cap) {
        var rest = items.slice(cap).reduce(function (a, x) { return a + x.n; }, 0);
        // **不说「其余」两个字就成了截断**：读者会以为这就是全部取值。
        g.appendChild(el("span", "more",
          "另有 " + (items.length - cap) + " 个未单列（" + rest + " 条）"));
      }
      bar.appendChild(g);
    }
    group("矿种", "mineral",
      facet(rows, "mineral", function (e) {
        return !filt.country || (e.country || "未写明") === filt.country;
      }), 6);
    group("国别", "country",
      facet(rows, "country", function (e) {
        return !filt.mineral || (e.minerals || []).indexOf(filt.mineral) >= 0;
      }), 10);
    return bar;
  }

  // 一次画多少条。349 条在桌面是三列 8,802px，**在手机上是一列 22,201px**
  // ——65 屏。那不是设计决定，是没想过手机的结果。
  // 分批展开，但**总数永远印在标题里、按钮上写清还剩多少**：
  // 这个板块的规矩是不静默截断，渐进展开与截断的差别就在于说不说得出剩下多少。
  var PAGE = 60;
  var shownCount = PAGE;

  function renderSmelters() {
    var host = $("smelters");
    host.textContent = "";
    var all = edgeRows();
    if (!all.length) return;
    var rows = all.filter(matchFilter);

    var counts = idCounts();
    var mixed = counts.cid > 0 && counts.nameOnly > 0;
    var docUrl = ((state.edges || {}).evidence || {}).url || "";
    var box = el("section", "glass smelters");
    box.setAttribute("aria-label", "冶炼厂清单");
    var head = el("div", null, null);
    head.style.cssText = "display:flex;justify-content:space-between;align-items:baseline;"
      + "gap:12px;flex-wrap:wrap;margin-bottom:10px;";
    // 标题永远同时印「筛出多少」与「共多少」。只印筛出的那个数，读者一眼
    // 看过去会以为这家公司就这么几条——筛选不能把总量说小。
    head.appendChild(el("h3", null, rows.length === all.length
      ? "冶炼厂／精炼厂清单（" + all.length + " 家）"
      : "冶炼厂／精炼厂清单（筛出 " + rows.length + " 家 / 共 " + all.length + " 家）"));
    var translated = rows.filter(function (e) { return zhName(e.name); }).length;
    var sub = el("span", null,
      "出现在该公司 Form SD 申报供应链中 · 不是直接供货关系 · 点厂名看原始申报"
      + (translated
          ? " · " + translated + " 家有中文译名（以英文原文为准）"
          : "")
      // 全体同一种标识时在这里说一次就够，不必每行都挂一个标签
      + (mixed ? "" : (counts.cid ? " · 全部带 RMI 编号" : " · 全部只有名字、无 RMI 编号")));
    sub.style.cssText = "font-size:.72rem;color:var(--dim);";
    head.appendChild(sub);
    box.appendChild(head);
    box.appendChild(filterBar(all, function () { renderSmelters(); }));
    if (rows.length !== all.length) {
      var back = el("p", "smclear",
        "已筛选：" + [filt.mineral && ("矿种 " + filt.mineral),
                      filt.country && ("国别 " + filt.country)]
          .filter(Boolean).join(" · ")
        + "。隐藏了 " + (all.length - rows.length) + " 家，它们仍在这份申报里。");
      box.appendChild(back);
    }

    var grid = el("div", "grid");
    var ordered = rows.slice().sort(function (a, b) {
      return String(a.name || a.from).localeCompare(String(b.name || b.from));
    });
    var visible = ordered.slice(0, shownCount);
    visible.forEach(function (e) {
      var item = el("div", "sm");
      var english = e.name || e.from;
      var chinese = zhName(e.name);
      var nm;
      if (docUrl) {
        nm = el("a", "nm sm-nm", chinese || english);
        nm.href = docUrl;
        nm.target = "_blank"; nm.rel = "noopener noreferrer";
        // 行号写进 title，核验时知道去原文第几行找
        if (e.row) nm.title = "原始申报第 " + e.row + " 行";
      } else {
        nm = el("span", "nm", chinese || english);
      }
      item.appendChild(nm);
      // 有中文名时英文原文仍然显示——中文是译名，核对以申报原文为准
      if (chinese) {
        var en = el("div", "en", english);
        item.appendChild(en);
      }
      // **国别这一格的依据要写出来。** 丰田、飞利浦那几份申报的国别列没被
      // 抽取器认出来，98% 的条目原本是空的；现在按 RMI CID 从冶炼厂登记表
      // 补上了——CID 是设施的全球唯一编号，别家申报人写的国别说的就是同一
      // 座厂。但那毕竟不是**本份申报**写的，不标出来读者会以为是。
      var bits = [e.country || "国别未写明", (e.minerals || []).join("·") || "矿种未写明"];
      var meta = el("div", "meta", bits.join("  ·  "));
      if (e.countryBasis === "rmi-registry") {
        meta.appendChild(document.createTextNode("  ·  "));
        var rb = el("span", "cid", "国别据登记表");
        rb.title = "本份申报未写明该厂国别；此处按 RMI 冶炼厂编号（"
          + (e.cid || "CID") + "）从登记表取，即其他申报人对同一座厂的登记。"
          + "登记表内写法不一致的一律留空，不取多数。";
        meta.appendChild(rb);
      }
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

    // 「还有 N 家」。**写清还剩多少才叫渐进展开，不写就是截断。**
    if (ordered.length > visible.length) {
      var left = ordered.length - visible.length;
      var more = el("button", "smmore");
      more.type = "button";
      more.textContent = "再显示 " + Math.min(PAGE, left) + " 家（还有 " + left + " 家）";
      more.onclick = function () { shownCount += PAGE; renderSmelters(); };
      box.appendChild(more);
      var allBtn = el("button", "smmore alt");
      allBtn.type = "button";
      allBtn.textContent = "一次全部展开（" + ordered.length + " 家）";
      allBtn.onclick = function () { shownCount = ordered.length; renderSmelters(); };
      box.appendChild(allBtn);
    } else if (ordered.length > PAGE) {
      var fold = el("button", "smmore alt");
      fold.type = "button";
      fold.textContent = "收起（只看前 " + PAGE + " 家）";
      fold.onclick = function () { shownCount = PAGE; renderSmelters(); };
      box.appendChild(fold);
    }
    host.appendChild(box);
  }

  function renderSide() {
    var side = $("side");
    side.textContent = "";
    var n = state.node;
    var d = state.data;
    var rows = edgeRows();

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
      if (rows.length) {
        // 出处在文件级：本文件每条边共用同一份申报，因此这里只需读一次。
        var f = (state.edges && state.edges.evidence) || {};
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
        var dropped = ((state.edges || {}).parse || {}).droppedNoCid || 0;
        if (dropped) {
          var dr = el("div", "kv");
          dr.appendChild(el("span", null, "未收录的行"));
          var db = el("b", null, dropped + " 行");
          db.style.color = "var(--warn)";
          dr.appendChild(db);
          okBox.appendChild(dr);
          var why = el("div", null,
            "这些行看着像冶炼厂（有厂名有国别）但缺矿种，无法确认，因此不收录。"
            + "这一栏不为零就说明本页只是该申报名单的一部分。");
          why.style.cssText = "font-size:.7rem;color:var(--dim);line-height:1.6;margin-top:6px;";
          okBox.appendChild(why);
        }
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
    // ── 上游冶炼厂重叠 ────────────────────────────────────────────────
    // 这是本页唯一一条公司 ↔ 公司的关系，而且它是**两份原始申报的交集**：
    // 甲的名单里有 X、乙的名单里也有 X。没有一个字是推断出来的。
    // 但语义只到这里为止：共同暴露，不是业务往来。这句话必须写在块里。
    var pv = state.peers && (state.peers.companies || {})[n.symbol];
    if (pv && (pv.peers || []).length) {
      var nameOf = {};
      (d.nodes || []).forEach(function (x) { nameOf[x.symbol] = x.name || x.symbol; });

      var pbox = el("div", "glass peerbox");
      pbox.style.cssText = "padding:13px 15px;";
      pbox.appendChild(el("h3", null, "上游冶炼厂重叠"));
      pbox.appendChild(el("p", "pcap",
        "本公司名单 " + pv.total + " 家；与 " + pv.peerCount
        + " 家申报人有重叠，下面按重叠数排前 "
        + Math.min((pv.peers || []).length, pv.peerCount) + " 名。"));

      (pv.peers || []).forEach(function (row) {
        var a = el("a", "peer");
        a.href = "company.html?symbol=" + encodeURIComponent(row.symbol);
        a.appendChild(el("span", "nm", nameOf[row.symbol] || row.symbol));
        a.appendChild(el("span", "sym", row.symbol));
        a.appendChild(el("span", "sh", row.shared + " 家"));
        // 只给「重叠 236 家」看不出这是多是少，得知道对方名单有多大
        a.appendChild(el("span", "of", "/ 对方 " + row.peerTotal + " 家"));
        a.title = (nameOf[row.symbol] || row.symbol) + "：两家名单里有 "
          + row.shared + " 家相同的冶炼厂（本公司 " + pv.total
          + " 家 · 对方 " + row.peerTotal + " 家）";
        pbox.appendChild(a);
      });

      if ((pv.topShared || []).length) {
        pbox.appendChild(el("div", "pcap2", "本公司名单里被最多同行共同申报的"));
        pv.topShared.forEach(function (row) {
          var line = el("div", "pshare");
          line.appendChild(el("span", "nm", zhName(row.name) || row.name || row.id));
          if (row.country) line.appendChild(el("span", "ct", row.country));
          line.appendChild(el("span", "sh", row.filerCount + " 家共同申报"));
          pbox.appendChild(line);
        });
      }

      pbox.appendChild(el("p", "pwarn",
        "重叠来自两份可点开的原始申报的交集，不含推断。但它只表示两家的上游"
        + "冶炼环节有共同暴露，不表示两家之间有业务往来、供货或合作。"
        + "另外：只有名字的冶炼厂按规范化名字合并，同一家厂写法不同会被算成两条，"
        + "所以这个数只会少算不会多算。"));
      side.appendChild(pbox);
    }

    // ── 所属产业链与它的上下游 ────────────────────────────────────────
    // 「点开一家公司能看到它在链条上的位置」——这一块回答的就是这句话。
    // 但要分清两层：**这家公司在哪条链上**是按它申报的 SIC 码判的分类；
    // **链与链之间的上下游**是产业结构框架。两层都不是「这家公司供货给谁」，
    // 那种话只能来自申报文件，本页目前只有冶炼厂那一条真关系。
    var myChains = n.chains || [];
    if (myChains.length && (d.chainLinks || []).length) {
      var chainOf = {};
      (d.chains || []).forEach(function (c) { chainOf[c.id] = c; });

      var box = el("div", "glass chainbox");
      box.style.cssText = "padding:13px 15px;";
      var h = el("h3", null, "所属产业链");
      box.appendChild(h);

      var mine = el("div", "mychains");
      myChains.forEach(function (cid) {
        var c = chainOf[cid];
        var a = el("a", "cpill", c ? c.label : cid);
        a.href = "./?chain=" + encodeURIComponent(cid);
        a.title = (c ? c.label : cid) + "：在总览页查看这条链";
        mine.appendChild(a);
      });
      box.appendChild(mine);
      if (myChains.length > 1) {
        box.appendChild(el("p", "cnote",
          "同时在 " + myChains.length + " 条链上——申报的行业码本身就横跨多条链，"
          + "不是重复。"));
      }

      // 上下游按这家公司所在的**全部**链合并，去掉它自己已在的链
      var seen = {}, up = [], down = [];
      (d.chainLinks || []).forEach(function (l) {
        if (myChains.indexOf(l.to) >= 0 && myChains.indexOf(l.from) < 0) {
          if (!seen["u" + l.from]) { seen["u" + l.from] = 1; up.push(l); }
        }
        if (myChains.indexOf(l.from) >= 0 && myChains.indexOf(l.to) < 0) {
          if (!seen["d" + l.to]) { seen["d" + l.to] = 1; down.push(l); }
        }
      });

      [["上游 · 谁供给这些链", up, "from", "←"],
       ["下游 · 这些链供给谁", down, "to", "→"]].forEach(function (pair) {
        if (!pair[1].length) return;
        box.appendChild(el("div", "ccap", pair[0] + "（" + pair[1].length + "）"));
        pair[1].forEach(function (l) {
          var otherId = l[pair[2]];
          var c = chainOf[otherId];
          var a = el("a", "clink");
          a.href = "./?chain=" + encodeURIComponent(otherId);
          a.appendChild(el("span", "ar", pair[3]));
          a.appendChild(el("span", "nm", c ? c.label : otherId));
          a.appendChild(el("span", "fl", l.flow || ""));
          box.appendChild(a);
        });
      });

      var cross = (d.chainCrossCutting || {});
      var crossHit = myChains.filter(function (c) { return cross[c]; });
      if (crossHit.length) {
        box.appendChild(el("p", "cnote", cross[crossHit[0]] + "。"));
      }

      box.appendChild(el("p", "cwarn",
        "产业链归属按本公司申报的 SIC 行业码判定；链与链之间的上下游是产业结构框架，"
        + "按行业通识定义。两者都不表示这家公司与上下游企业之间有供应关系——"
        + "那只能来自申报文件，本页目前只有冶炼厂那一类。"));
      side.appendChild(box);
    }

    var real = el("div", "glass");
    real.style.cssText = "padding:13px 15px;";
    real.appendChild(el("h3", null, "本页哪些是真实数据"));
    var sameStage = (d.nodes || []).filter(function (x) { return x.stage === n.stage; }).length;
    [["身份与市值", "站内公司榜"], ["环节判定", "SEC 官方 SIC 行业码"],
     ["同行业公司", sameSic.length + " 家"], ["同环节公司", sameStage + " 家"],
     ["冶炼厂关系", rows.length + " 条"],
     ["上游重叠", pv ? (pv.peerCount + " 家申报人") : "0 家"],
     ["产业链归属", (n.chains || []).length + " 条链（按 SIC 分类）"],
     ["链间上下游", "产业结构框架，非实测"],
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
      if (!node) {
        // 收录范围随池扩张，写死「只收标普500」会在扩池后变成假话。
        // 照数据报当前实际收了多少家。
        fail("产业链节点表里没有 " + symbol + "。本板块目前收录 " + d.nodes.length
             + " 家公司：标普500成分股，以及在美上市、同时申报 Form SD 的外国私人发行人。");
        return;
      }
      state.data = d; state.node = node;
      document.title = (node.name || symbol) + " 供应链视图 · 全球产业链";
      return Promise.all([loadEdges(), loadNamesZh(), loadPeers()]).then(paint);
    })
    .catch(function (err) {
      fail("公司数据加载失败：" + (err && err.message ? err.message : "未知错误")
        + "。这是加载问题，不代表数据不存在——请稍后重试。");
    });

  /* 边按公司分文件，只在这家公司确实有边时才拉——
     总览页 495 家里绝大多数没有边文件，不该为此多发一次请求。
     拉失败不阻断整页：身份、环节、同行都是本地已有的真实数据，
     照常渲染，并在覆盖率声明里说清楚是加载失败而不是没有数据。 */
  /* 上游重叠。只在这家公司确实有名单时才拉——没有名单就不可能有重叠，
     为它多发一次请求是白发。拉不到不阻断整页：这一块不显示，其余照常。 */
  function loadPeers() {
    var idx = ((state.data || {}).edgeIndex || {})[state.node.symbol];
    if (!idx) return Promise.resolve();
    return fetch("peers.json", { cache: "no-cache" })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (d) { if (d && d.companies) state.peers = d; })
      .catch(function () { /* 这一块不显示即可，不影响其它内容 */ });
  }

  /* 译名表是显示层的补充，拉不到就显示英文原文，不算失败。 */
  function loadNamesZh() {
    return fetch("names-zh.json", { cache: "no-cache" })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (d) { if (d && d.names) state.zh = d; })
      .catch(function () { /* 显示英文原文即可 */ });
  }

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
