/* 全球产业链 · 渲染标普500成分股的价值链环节分层。
   纯原生 JS，读取同目录 nodes.json（由 scripts/supply-chain/build_chain_nodes.py 生成）。

   两条不可违反的展示规则：
   1. 覆盖率声明必须显著可见，永远不宣称完整供应链；
   2. 阶段判定必须显示依据（SIC 码 + 可点开的申报链接），不得把推断显示成结论。 */
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  function isNum(v) { return v !== null && v !== undefined && v !== "" && !isNaN(v); }

  /* 外部字段一律经 textContent 落地；此函数只在拼接结构化片段时用，
     且只接受本文件自己产出的内容。公司名等外部文本走 setText。 */
  function setText(el, s) { el.textContent = s == null ? "" : String(s); }

  function pct(v) { return isNum(v) ? (v >= 0 ? "+" : "−") + Math.abs(v).toFixed(2) + "%" : "—"; }
  function cls(v) { return !isNum(v) ? "flat" : v > 0 ? "up" : v < 0 ? "down" : "flat"; }
  // 上游 marketCap 以十亿美元计。中文按「亿 / 万亿」显示，单位写在数值里，
  // 避免表头与单元格各说一套（曾经表头写「亿美元」而值输出「十亿」）。
  function cap(v) {
    if (!isNum(v)) return "—";
    var n = Number(v);
    return n >= 1000 ? (n / 1000).toFixed(2) + " 万亿" : (n * 10).toFixed(0) + " 亿";
  }
  function relTime(iso) {
    if (!iso) return "";
    var t = Date.parse(iso); if (isNaN(t)) return "";
    var d = (Date.now() - t) / 1000;
    if (d < 3600) return Math.max(1, Math.floor(d / 60)) + " 分钟前";
    if (d < 86400) return Math.floor(d / 3600) + " 小时前";
    return Math.floor(d / 86400) + " 天前";
  }

  var STAGE_COLOR = {
    // 实物链八段：暖→冷的渐变，顺序本身是信息
    "raw-material": "var(--s1)", "material-processing": "var(--s2)",
    "component": "var(--s3)", "capital-equipment": "var(--s4)",
    "finished-goods": "var(--s5)", "logistics": "var(--s6)",
    "distribution": "var(--s7)", "end-service": "var(--s8)",
    // 使能层四段：低饱和，视觉上退到后面
    "energy-utility": "var(--e1)", "technology": "var(--e2)",
    "financial": "var(--e3)", "circular": "var(--e4)"
  };
  /* 哪些环节在实物流转链条上，由数据里的 chain 字段说了算，不在页面里另写一份
     名单——环节表改了页面就得跟着改，两处各写一份必然有一天对不上。 */
  function chainIds(d, wanted) {
    return (d.stages || []).filter(function (s) { return !!s.chain === wanted; })
      .sort(function (a, b) { return (a.order || 0) - (b.order || 0); })
      .map(function (s) { return s.id; });
  }

  var BASIS_LABEL = {
    "sic-refined": "SEC 官方 SIC 行业码判定",
    "sector-initial": "板块级初步口径",
    "sector-ambiguous": "板块横跨多段，仅给候选",
    "edge-derived": "由真实上下游关系反推",
    "unknown": "未判定"
  };

  var state = { data: null, open: null, seg: null, chain: null };

  function el(tag, className, text) {
    var n = document.createElement(tag);
    if (className) n.className = className;
    if (text != null) n.textContent = String(text);
    return n;
  }

  /* ── 顶部状态：来源、数据日、更新时间必须可见 ── */
  function renderStatus(d) {
    var row = $("statusrow");
    row.textContent = "";
    var items = [
      ["数据日", d.asOf || "—"],
      ["更新", relTime(d.updatedAt) || "—"],
      ["公司", (d.coverage && d.coverage.nodesTotal != null ? d.coverage.nodesTotal : "—") + " 家"],
      ["频率", d.frequency === "daily" ? "每日" : (d.frequency || "—")]
    ];
    items.forEach(function (pair) {
      var s = el("span", "status");
      s.appendChild(document.createTextNode(pair[0] + " "));
      s.appendChild(el("b", null, pair[1]));
      row.appendChild(s);
    });
  }

  /* ── 覆盖率声明：这一段是本页的诚实性底线，不得省略或弱化 ── */
  function renderNotice(d) {
    var cov = d.coverage || {};
    var byBasis = cov.stageByBasis || {};
    var edges = cov.edgesTotal || 0;

    // 这句是页面层面的承诺，固定文案。数据里的 coverage.note 说的是同一件事，
    // 拼在后面会变成「不是完整供应链…不是完整供应链」，因此不再追加。
    var p1 = $("notice-coverage");
    p1.textContent = "";
    p1.appendChild(document.createTextNode("本板块只收录有公开出处的信息，"));
    p1.appendChild(el("b", null, "不是完整供应链"));
    p1.appendChild(document.createTextNode("。每一条信息都能点开核验来源。"));

    // 有边的时候，覆盖率必须连「查过但没有」一起说。Form SD 强制申报、不强制
    // 列名单，把「有申报无名单」并进「无申报」会把披露制度的上限说成抓取失败。
    var sd = cov.formSd || {};
    var withList = sd.companiesWithList;
    var scope = (withList != null && sd.companiesFiledNoList != null)
      ? "（扫了 " + (sd.companiesScanned != null ? sd.companiesScanned : "—") + " 家："
        + withList + " 家有名单、" + sd.companiesFiledNoList + " 家有申报但正文未列名单、"
        + (sd.companiesNoFiling != null ? sd.companiesNoFiling : "—") + " 家无申报）"
      : "";
    setText($("notice-edges"), edges === 0
      ? "当前尚无企业间关系边（0 条）：每条关系都必须挂可核验的原始申报文件，没有出处的关系不会发布。本页展示的是各公司在价值链中的位置，不是公司之间的连线。"
      : "已收录 " + edges + " 条带出处的关系" + scope
        + "，全部来自 Form SD 冲突矿产申报，语义是「该冶炼厂出现在申报人的供应链中」——"
        + "间接、不含份额，不是直接供货关系。一级与二级供应商仍无数据源。"
        + "点公司表里的「冶炼厂」列进入单家视图逐条核验。");

    var parts = Object.keys(byBasis).filter(function (k) { return byBasis[k]; })
      .map(function (k) { return (BASIS_LABEL[k] || k) + " " + byBasis[k] + " 家"; });
    setText($("notice-basis"), parts.length
      ? "阶段判定口径：" + parts.join("；") + "。逐家依据见下方各环节表格的「判定依据」列。"
      : "");
  }

  /* ── 按板块的覆盖情况 ──────────────────────────────────────────────
     用户问「怎么有的公司有数据、有的没有」。这一段的职责是把这个问题按板块
     回答清楚，而且**区分两种 0**：

       金融 0/70、房地产 0/29 —— Form SD 只管产品里含 3TG 的发行人。银行和
                               REIT 没有产品，本来就不申报，这个 0 不会变。
       科技 34/84            —— 同样是缺口，但性质是「这一轮没拿到」。

     两者合成一个覆盖率，等于把披露制度的适用范围说成抓取缺陷。
     没有逐家申报状态时（抽取器还没跑过带 filingStatus 的版本）不猜原因，
     只显示有名单的家数，把未知单列。 */
  var COV_COLOR = {
    withEdges: "#4ea1ff",     // 有名单：真数据
    filedNoList: "#f0cf85",   // 有申报但正文没列名单：制度允许，不是缺陷
    noFiling: "#5a6478",      // 没有申报：多半不适用
    failed: "#e0685f",        // 取数失败：是缺陷，得亮出来
    unknown: "#39414f"        // 没有逐家记录：不猜
  };
  var COV_LABEL = {
    withEdges: "有名单",
    filedNoList: "有申报未列名单",
    noFiling: "无申报",
    resourceExtraction: "申报资源开采付款",
    failed: "取数失败",
    unknown: "无逐家记录"
  };
  var COV_ORDER = ["withEdges", "filedNoList", "resourceExtraction", "noFiling",
                   "failed", "unknown"];

  function covSeg(row) {
    return {
      withEdges: row.withEdges || 0,
      filedNoList: row.filedNoList || 0,
      noFiling: row.noFiling || 0,
      resourceExtraction: row.resourceExtraction || 0,
      failed: row.failed || 0,
      unknown: row.unscanned || 0
    };
  }

  function renderCoverageBySector(d) {
    var box = $("cov");
    if (!box) return;
    var rows = (d.coverage && d.coverage.bySector) || [];
    if (!rows.length) { box.hidden = true; return; }
    box.hidden = false;

    var anyStatus = rows.some(function (r) {
      return (r.filedNoList || 0) + (r.noFiling || 0) + (r.failed || 0) > 0;
    });

    setText($("cov-lead"), anyStatus
      ? "当前唯一的关系数据源是 SEC 的 Form SD 冲突矿产申报，它只适用于产品中含钽锡钨金的发行人。"
        + "因此各板块的覆盖率差别很大，而且有些板块的空白不会随时间填上——银行和 REIT 没有实体产品，"
        + "本来就不需要申报。下面按板块把「有名单」和「为什么没有」分开列出。"
      : "当前唯一的关系数据源是 SEC 的 Form SD 冲突矿产申报，它只适用于产品中含钽锡钨金的发行人。"
        + "本轮尚无逐家申报状态记录，因此只列出各板块有名单的家数，不推断其余公司没有数据的原因。");

    var wrap = $("cov-rows");
    wrap.textContent = "";
    rows.forEach(function (r) {
      var seg = covSeg(r);
      var total = r.companies || 0;
      if (!total) return;
      var line = el("div", "covrow");
      line.appendChild(el("div", "s", r.sector || "未分类"));

      var track = el("div", "t");
      COV_ORDER.forEach(function (k) {
        if (!seg[k]) return;
        var i = el("i");
        i.style.width = (seg[k] / total * 100) + "%";
        i.style.background = COV_COLOR[k];
        i.title = COV_LABEL[k] + " " + seg[k] + " 家";
        track.appendChild(i);
      });
      line.appendChild(track);

      line.appendChild(el("div", "n", seg.withEdges + " / " + total));
      // 屏幕阅读器读到的是完整拆解，不是一条没有含义的进度条。
      track.setAttribute("role", "img");
      track.setAttribute("aria-label", (r.sector || "未分类") + "：共 " + total + " 家，"
        + COV_ORDER.filter(function (k) { return seg[k]; })
            .map(function (k) { return COV_LABEL[k] + " " + seg[k] + " 家"; })
            .join("、"));
      wrap.appendChild(line);
    });

    var key = el("div", "covkey");
    COV_ORDER.forEach(function (k) {
      if (!rows.some(function (r) { return covSeg(r)[k]; })) return;
      var s = el("span");
      var sw = el("i");
      sw.style.background = COV_COLOR[k];
      s.appendChild(sw);
      s.appendChild(document.createTextNode(COV_LABEL[k]));
      key.appendChild(s);
    });
    wrap.appendChild(key);

    setText($("cov-foot"), anyStatus
      ? "「无申报」不等于「这家公司没有供应链」，只表示它没有提交 Form SD——多数是因为规则对它不适用。"
        + "「有申报未列名单」是规则允许的：Form SD 强制申报、不强制列出冶炼厂名单。"
        + "这两类占多数，所以覆盖率永远到不了 100%，这是披露制度本身的上限。"
      : "「有名单」以外的公司分三种情况：没有申报义务、申报了但正文未列名单、本轮取数失败。"
        + "三者性质完全不同，在拿到逐家记录之前不在这里合并成一个数。");
  }

  function perfOf(d, stageId) {
    var rows = (d.stagePerformance && d.stagePerformance.stages) || [];
    for (var i = 0; i < rows.length; i++) if (rows[i].stage === stageId) return rows[i];
    return null;
  }

  /* ── 横轴：一级产业链筛选 ── */
  /* 全页只有这一处决定「哪些公司算数」。家数、市值、细分条、公司表都从它取——
     各处各写一遍过滤条件的话，筛选一开总有一处对不上。 */
  function visibleNodes(d) {
    var all = d.nodes || [];
    if (!state.chain) return all;
    return all.filter(function (n) {
      return (n.chains || []).indexOf(state.chain) >= 0;
    });
  }

  function chainMeta(d, id) {
    var rows = d.chains || [];
    for (var i = 0; i < rows.length; i++) if (rows[i].id === id) return rows[i];
    return null;
  }

  /* 链的选择条。链是**分类**，不是边：选中一条链只是把公司筛出来，
     不声称同一条链上的两家公司之间有供应关系。这句话写在条子下面。 */
  function renderChainPicker(d) {
    var host = $("chainpick");
    if (!host) return;
    host.textContent = "";
    var rows = (d.chains || []).filter(function (c) { return c.count > 0; });
    if (!rows.length) { host.hidden = true; return; }
    host.hidden = false;

    var mk = function (id, label, count, edges) {
      var b = el("button", "chip" + (state.chain === id ? " on" : ""));
      b.type = "button";
      b.setAttribute("aria-pressed", state.chain === id ? "true" : "false");
      b.appendChild(el("span", "cl", label));
      b.appendChild(el("span", "cc", count + " 家"));
      if (edges) b.appendChild(el("span", "ce", edges + " 条关系"));
      b.addEventListener("click", function () {
        state.chain = state.chain === id ? null : id;
        // 换链之后旧的展开位置多半已经空了，一并收起，不留一格空表
        state.open = null;
        state.seg = null;
        renderStages(d);
      });
      return b;
    };

    var allBtn = mk(null, "全部产业链", (d.nodes || []).length,
      (d.coverage && d.coverage.edgesTotal) || 0);
    if (!state.chain) allBtn.classList.add("on");
    host.appendChild(allBtn);
    rows.forEach(function (c) {
      host.appendChild(mk(c.id, c.label, c.count, c.edgeCount));
    });
  }

  /* ── 环节卡片 ── */
  function countIn(d, stageId) {
    var n = 0;
    visibleNodes(d).forEach(function (x) { if (x.stage === stageId) n++; });
    return n;
  }

  /* 环节的市值合计。不在数据里预算，因为它就是节点表的一次求和，
     多一个字段就多一处可能对不上的数。 */
  function capOf(d, stageId) {
    var sum = 0;
    visibleNodes(d).forEach(function (x) {
      if (x.stage === stageId && isNum(x.marketCap)) sum += x.marketCap;
    });
    return sum;
  }

  /* 一个环节 = 一条带：表头（名称／家数／市值／涨跌）+ 始终铺开的细分构成
     + 点开后就地展开的公司表。细分是主体，不藏在点击后面。 */
  function stageBand(d, meta) {
    var p = perfOf(d, meta.id) || {};
    var total = countIn(d, meta.id);
    var band = el("section", "band");
    band.dataset.stage = meta.id;

    var hd = el("button", "bandhd");
    hd.type = "button";
    hd.setAttribute("aria-expanded", "false");
    hd.style.borderLeftColor = STAGE_COLOR[meta.id] || "var(--dim)";
    hd.appendChild(el("span", "nm", meta.label));
    if (meta.labelEn) hd.appendChild(el("span", "en", meta.labelEn));
    hd.appendChild(el("span", "spacer"));

    var n = el("span", "n");
    n.appendChild(document.createTextNode(String(total)));
    n.appendChild(el("s", null, "家"));
    hd.appendChild(n);
    // 空环节不印市值与涨跌：0 亿和一句「涨跌见全部」都是噪音，
    // 这条带子要说的只有一件事——这一段没有公司。
    if (total) {
      hd.appendChild(el("span", "mc", cap(capOf(d, meta.id))));
      // 表头只留等权一个口径，另两个在细分条下面给全——是降级，不是删掉
      if (state.chain) {
        // 环节涨跌是构建时按**整个环节**算好的，筛出一条链之后这个数不再对应
        // 屏幕上这批公司。节点表里没有逐家涨跌，算不出筛后口径——那就不显示，
        // 不拿全环节的数冒充该链的数。
        var na = el("span", "mc", "涨跌见全部");
        na.title = "环节涨跌按整个环节预算，筛选产业链后不对应当前这批公司，故不显示";
        hd.appendChild(na);
      } else if (p.companies == null) {
        hd.appendChild(el("span", "mc", "无表现数据"));
      } else {
        var b = el("span", "pc " + cls(p.equalWeightPct), pct(p.equalWeightPct));
        b.title = "等权涨跌";
        hd.appendChild(b);
      }
    }
    band.appendChild(hd);

    if (state.chain && !total) {
      // 筛出一条链之后，它没覆盖到的环节**照样画出来**并标空。
      // 藏起来会让人以为这条链就是这么短；空着才看得见缺口在哪一段——
      // 「半导体链上游没有公司」正是当前公司池只有标普 500 造成的结果。
      band.classList.add("empty");
      hd.disabled = true;
      band.appendChild(el("div", "banddesc",
        "本池中这条链在该环节没有公司——可能是这条链本就不经过这一段，"
        + "也可能是该段的公司不在当前公司池里。"));
      return band;
    }

    if (meta.description) band.appendChild(el("div", "banddesc", meta.description));

    var list = visibleNodes(d).filter(function (x) { return x.stage === meta.id; })
      .sort(function (a, b2) { return (b2.marketCap || 0) - (a.marketCap || 0); });

    var panel = el("div", "panel");
    panel.hidden = true;
    panel.id = "panel-" + meta.id;

    band.appendChild(renderSegments(d, meta.id, list, function (code) {
      // 同一格再点一次收起；换一格就换内容，表始终在这条带子里面
      var same = state.open === meta.id && state.seg === code;
      state.open = same ? null : meta.id;
      state.seg = same ? null : code;
      renderStages(d);
    }));
    band.appendChild(panel);

    hd.setAttribute("aria-controls", panel.id);
    hd.addEventListener("click", function () {
      var opening = !(state.open === meta.id && !state.seg);
      state.open = opening ? meta.id : null;
      state.seg = null;
      renderStages(d);
    });

    if (state.open === meta.id) {
      band.classList.add("open");
      hd.setAttribute("aria-expanded", "true");
      fillPanel(d, meta, list, panel);
      panel.hidden = false;
    }
    return band;
  }

  /* 环节段数与「同一 SIC 大类跨环节」的说明。段数从数据读，不写死在文案里——
     写死的话调整分类就会留下一句过期的话（上一版就还写着「六个环节」）。 */
  function renderChainNote(d) {
    var chain = chainIds(d, true).length, off = chainIds(d, false).length;
    var sub = $("chain-sub");
    var picked = state.chain ? chainMeta(d, state.chain) : null;
    if (sub) {
      if (picked) {
        // 这条链落在几个环节上，是这个二维模型最有用的一个读数
        var hit = 0;
        (d.stages || []).forEach(function (st) { if (countIn(d, st.id)) hit++; });
        setText(sub, picked.label + "：" + picked.count + " 家，落在 " + hit
          + " / " + (chain + off) + " 个环节上"
          + (picked.edgeCount ? " · 已抽到关系 " + picked.edgeCount + " 条" : "")
          + " · 再点一次取消筛选");
      } else {
        setText(sub, "实物链 " + chain + " 段 + 使能层 " + off
          + " 段，按 SEC 行业码（SIC）展开，宽度即家数 · 点一格只看该组公司");
      }
    }
    if (picked) {
      setText($("chain-note"),
        "产业链归属按公司向 SEC 申报的四位行业码（SIC）判定，规则公开、逐家可核验，"
        + "一家可以同时在多条链上（全池 " + ((d.coverage || {}).chainMulti || 0)
        + " 家如此）。链是分类，不是关系——选中一条链只是把公司筛出来，"
        + "不表示同一条链上的两家公司之间有供应关系——那只能来自申报文件。");
      return;
    }
    // 一个 SIC 大类在几个环节里出现过
    var seen = {};
    (d.nodes || []).forEach(function (n) {
      if (!n.sicMajor) return;
      (seen[n.sicMajor] = seen[n.sicMajor] || {})[n.stage] = 1;
    });
    var spread = Object.keys(seen).filter(function (k) {
      return Object.keys(seen[k]).length > 1;
    }).length;
    setText($("chain-note"), spread
      ? "有 " + spread + " 个 SIC 大类横跨多个环节，因此同一个名字会在不同环节里各出现一次——"
        + "这不是重复：化工里既有工业气体（材料加工）也有成药（整机与品牌），"
        + "四位行业码才分得开，逐家依据见展开后表格的「判定依据」列。"
      : "");
  }

  function renderStages(d) {
    renderChainPicker(d);
    renderChainNote(d);
    var byId = {};
    (d.stages || []).forEach(function (s2) { byId[s2.id] = s2; });
    [["chain", chainIds(d, true)], ["offchain", chainIds(d, false)]]
      .forEach(function (pair) {
      var host = $(pair[0]);
      host.textContent = "";
      pair[1].forEach(function (id, i) {
        if (!byId[id]) return;
        // 实物链四段之间画向下的箭头，表示顺序；链外两段之间不画
        if (i && pair[0] === "chain") host.appendChild(el("div", "link"));
        host.appendChild(stageBand(d, byId[id]));
      });
    });
  }

  /* ── 展开的公司表：逐家显示 SIC 与判定依据 ── */
  var MAX_ROWS = 60;
  // 细分条最多列几格。再多每格就窄到放不下名字了，其余并进长尾说明——
  // 是收拢长尾，不是省略：家数仍然算进合计，并在下面写明有多少家、属几个码。
  var MAX_SEGS = 6;

  /* 按 SIC 两位大类拆分一个环节。分组字段由构建脚本从 SEC 的 SIC 码算出，
     页面只负责显示，不在这里自己编分类。 */
  function segmentsOf(list) {
    var by = {};
    list.forEach(function (n) {
      var code = n.sicMajor;
      // 认不出大类的单独归一档，不硬塞进任何一组
      var key = code || "?";
      if (!by[key]) {
        by[key] = { code: code, label: n.sicMajorLabel || "未归类",
                    labelEn: n.sicMajorLabelEn || "", rows: [] };
      }
      by[key].rows.push(n);
    });
    return Object.keys(by).map(function (k) { return by[k]; })
      .sort(function (a, b) { return b.rows.length - a.rows.length; });
  }

  function tint(hex, a) {
    // STAGE_COLOR 存的是 var(--sN)，取不到字面值就退回一个中性底色，
    // 不猜一个颜色出来。
    var m = /^#([0-9a-f]{6})$/i.exec(hex || "");
    if (!m) return "rgba(255,255,255," + (a * 0.5).toFixed(3) + ")";
    var v = parseInt(m[1], 16);
    return "rgba(" + ((v >> 16) & 255) + "," + ((v >> 8) & 255) + ","
      + (v & 255) + "," + a + ")";
  }

  function renderSegments(d, stageId, list, onPick) {
    var segs = segmentsOf(list);
    var shown = segs.slice(0, MAX_SEGS);
    var rest = segs.slice(MAX_SEGS);
    var restCount = rest.reduce(function (a, g) { return a + g.rows.length; }, 0);

    // 口径只在区块标题里说一次。六条带子各印一遍同样的话，是六份噪音。
    var box = el("div", "segwrap");
    var row = el("div", "segrow");
    var colorVar = STAGE_COLOR[stageId] || "";
    // var(--sN) 拿不到字面色值，从计算样式里读回来再调浓淡
    var probe = document.createElement("span");
    probe.style.color = colorVar;
    document.body.appendChild(probe);
    var rgb = getComputedStyle(probe).color;
    document.body.removeChild(probe);
    var base = /^rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(rgb);

    shown.forEach(function (g, i) {
      var b = el("button", "seg");
      b.type = "button";
      b.dataset.seg = g.code || "?";
      b.setAttribute("aria-pressed", b.dataset.seg === state.seg ? "true" : "false");
      b.style.flex = g.rows.length + " 1 0";
      var a = 0.30 - i * 0.026;
      if (a < 0.07) a = 0.07;
      b.style.background = base
        ? "rgba(" + base[1] + "," + base[2] + "," + base[3] + "," + a + ")"
        : tint(null, a);
      b.style.borderColor = base
        ? "rgba(" + base[1] + "," + base[2] + "," + base[3] + ",0.34)"
        : "transparent";
      b.appendChild(el("span", "sn", g.label));
      b.appendChild(el("span", "sc",
        (g.code ? "SIC " + g.code + " · " : "") + g.rows.length + " 家"));
      b.title = g.label + (g.labelEn ? "（" + g.labelEn + "）" : "")
        + " " + g.rows.length + " 家";
      // 只报「点了哪一格」，要不要收起由调用方判断——两边都做一次切换会互相抵消
      b.addEventListener("click", function (ev) {
        ev.stopPropagation();
        onPick(g.code || "?");
      });
      row.appendChild(b);
    });
    box.appendChild(row);

    if (restCount) {
      box.appendChild(el("div", "rest",
        "另有 " + restCount + " 家分散在 " + rest.length
        + " 个更小的行业码里，未单列。"));
    }

    // 卡片上只留了等权一个口径，另两个在这里给全——是降级，不是删掉
    var p = state.chain ? {} : (perfOf(d, stageId) || {});
    if (p.companies != null) {
      var pf = el("div", "perf2");
      [["等权", p.equalWeightPct], ["市值加权", p.capWeightPct],
       ["中位", p.medianPct]].forEach(function (pair) {
        var one = el("span", null, pair[0]);
        one.appendChild(el("b", cls(pair[1]), pct(pair[1])));
        pf.appendChild(one);
      });
      box.appendChild(pf);
    }
    return box;
  }

  /* 只负责填公司表。细分条由 stageBand 常驻渲染，不在这里重复一份。 */
  function fillPanel(d, meta, all, panel) {
    panel.textContent = "";
    var list = state.seg
      ? all.filter(function (n) { return (n.sicMajor || "?") === state.seg; })
      : all;

    var capBox = el("div", "cap");
    capBox.appendChild(el("b", null, meta.label));
    if (state.seg) {
      var pick = null;
      segmentsOf(all).forEach(function (g) { if ((g.code || "?") === state.seg) pick = g; });
      capBox.appendChild(document.createTextNode(
        " · " + (pick ? pick.label : state.seg) + "（SIC " + state.seg + "）"));
    }
    capBox.appendChild(document.createTextNode(
      " · " + list.length + " 家" + (state.seg ? "（全环节 " + all.length + " 家）" : "")
      + "，按市值排序"
      + (list.length > MAX_ROWS ? "，显示前 " + MAX_ROWS + " 家" : "")));
    panel.appendChild(capBox);

    var wrap = el("div", "tablewrap");
    var table = document.createElement("table");
    var thead = document.createElement("thead");
    var hr = document.createElement("tr");
    // 「冶炼厂」列：这家公司的 Form SD 申报里收录了几家冶炼厂。
    // 有关系数据的公司在总览上就能一眼看出来，不必挨个点进去试。
    ["公司", "代码", "市值(美元)", "SIC", "冶炼厂", "判定依据"].forEach(function (h, i) {
      var th = el("th", (i === 2 || i === 4) ? "num" : null, h);
      hr.appendChild(th);
    });
    thead.appendChild(hr);
    table.appendChild(thead);

    var tbody = document.createElement("tbody");
    list.slice(0, MAX_ROWS).forEach(function (n) {
      var tr = document.createElement("tr");

      var tdName = el("td", "nm");
      var zh = n.name || n.symbol || "—";
      // 公司名做成进入单家供应链视图的入口
      var link = el("a", "colink", zh);
      link.href = "company.html?symbol=" + encodeURIComponent(n.symbol || "");
      tdName.appendChild(link);
      // 中文名缺失时上游会回退成英文名，此时两行内容相同，不重复显示
      if (n.nameEn && n.nameEn !== zh) tdName.appendChild(el("small", null, n.nameEn));
      tr.appendChild(tdName);

      tr.appendChild(el("td", null, n.symbol || "—"));
      tr.appendChild(el("td", "num", cap(n.marketCap)));
      tr.appendChild(el("td", "num", n.sic != null ? String(n.sic) : "—"));

      // 0 与「—」不是一回事：0 表示这家我们查过、申报里没有可解析的名单；
      // 「—」表示这家还没进过抽取器。抽取器扫全表，所以正常情况下都是数字。
      var tdEdges = el("td", "num");
      var count = n.edgeCount;
      if (count) {
        var el2 = el("a", "colink", String(count));
        el2.href = "company.html?symbol=" + encodeURIComponent(n.symbol || "");
        tdEdges.appendChild(el2);
      } else {
        tdEdges.appendChild(document.createTextNode(count === 0 ? "0" : "—"));
        tdEdges.style.color = "var(--faint)";
      }
      tr.appendChild(tdEdges);

      // 判定依据：说明为什么落在这个环节，并给出可核验的申报链接
      var tdBasis = el("td", "basis");
      tdBasis.appendChild(document.createTextNode(n.stageNote || BASIS_LABEL[n.stageBasis] || "—"));
      var ev = n.stageEvidence;
      if (ev && ev.url) {
        tdBasis.appendChild(document.createTextNode(" "));
        var a = el("a", null, "查看申报");
        a.href = ev.url;
        a.target = "_blank";
        a.rel = "noopener noreferrer";
        tdBasis.appendChild(a);
      }
      tr.appendChild(tdBasis);
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    wrap.appendChild(table);
    panel.appendChild(wrap);

    if (list.length > MAX_ROWS) {
      panel.appendChild(el("div", "more",
        "另有 " + (list.length - MAX_ROWS) + " 家未显示。完整清单见站内公司榜。"));
    }
  }

  /* ── 真实流向：环节 → 冶炼厂所在国别 ──────────────────────────────
     全站唯一一处带子宽度有实测含义的图。矩阵由构建脚本预算在 nodes.json 里，
     页面不为一张总览图去下几十个边文件。

     三条守则，都是「空缺要画出来」的具体形态：
       · 一条边都没有的环节照画，画成灰色 0 条的死头，不筛掉
       · 没有名单的公司在图注里点明数目，不能只画有数据的部分让人以为是全貌
       · 语义写「出现在供应链中」，不写「供应商」——后者是我们替申报人下的结论 */
  var FLOW_COUNTRY_COLOR = {
    "中国": "var(--s2)", "日本": "var(--s3)", "美国": "var(--s4)",
    "印度尼西亚": "var(--s1)", "巴西": "var(--s5)", "印度": "#d1785f",
    "德国": "#8f9bb0", "未归类": "#4b5666", "其他": "#3a4553"
  };
  var FLOW_NS = "http://www.w3.org/2000/svg";

  function svgEl(tag, attrs) {
    var n = document.createElementNS(FLOW_NS, tag);
    Object.keys(attrs || {}).forEach(function (k) { n.setAttribute(k, attrs[k]); });
    return n;
  }

  /* 标签避让：小节点只有几像素高，两行标签会压到下一个上去。
     **只推标签，不动条子**——条子的高度是编码，推它等于改数据。 */
  function declash(items, minGap, top, bottom) {
    var out = items.map(function (it) { return { y: it.mid, it: it, mid: it.mid }; });
    out.sort(function (a, b) { return a.mid - b.mid; });
    var i;
    for (i = 1; i < out.length; i++) {
      if (out[i].y - out[i - 1].y < minGap) out[i].y = out[i - 1].y + minGap;
    }
    if (out.length && out[out.length - 1].y > bottom) {
      out[out.length - 1].y = bottom;
      for (i = out.length - 2; i >= 0; i--) {
        if (out[i].y > out[i + 1].y - minGap) out[i].y = out[i + 1].y - minGap;
      }
    }
    if (out.length && out[0].y < top) {
      out[0].y = top;
      for (i = 1; i < out.length; i++) {
        if (out[i].y - out[i - 1].y < minGap) out[i].y = out[i - 1].y + minGap;
      }
    }
    return out;
  }

  function renderFlow(d) {
    var host = $("flowsec");
    if (!host) return;
    var flow = d.flow;
    var chart = $("flow-chart");
    chart.textContent = "";
    if (!flow || !(flow.stages || []).length) { host.hidden = true; return; }
    host.hidden = false;

    var label = {};
    (d.stages || []).forEach(function (s) { label[s.id] = s.label; });

    // 一条边都没有的环节也画进来，画成 0 条的死头
    var left = (flow.stages || []).map(function (r) {
      return { id: r.stage, nm: label[r.stage] || r.stage, total: r.total,
               by: r.byCountry || {} };
    });
    (flow.stagesWithoutEdges || []).forEach(function (id) {
      left.push({ id: id, nm: label[id] || id, total: 0, by: {} });
    });
    // 按价值链顺序排，不按流量大小——这是一条链，顺序本身是信息
    var order = (d.stages || []).map(function (s) { return s.id; });
    left.sort(function (a, b) { return order.indexOf(a.id) - order.indexOf(b.id); });

    var countries = flow.countries || [];
    var ctot = flow.countryTotals || {};
    var total = left.reduce(function (a, r) { return a + r.total; }, 0);
    if (!total) { host.hidden = true; return; }

    var W = 1000, PAD = 6, NODEW = 11, GAP = 27, LX = 150, RX = W - 156;
    var H = 384;
    var k = (H - PAD * Math.max(left.length, countries.length)) / total;

    var y = 0, lp = {};
    left.forEach(function (r) {
      var h = Math.max(r.total * k, 3);
      lp[r.id] = { y0: y, h: h, cur: y };
      y += h + PAD;
    });
    var leftH = y - PAD;
    var ry = 0, rp = {};
    countries.forEach(function (c) {
      var h = Math.max((ctot[c] || 0) * k, 3);
      rp[c] = { y0: ry, h: h, cur: ry };
      ry += h + PAD;
    });
    var rightH = ry - PAD;
    var VH = Math.max(leftH, rightH, left.length * GAP + 24,
                      countries.length * GAP + 24) + 22;
    var loff = (VH - leftH) / 2, roff = (VH - rightH) / 2;

    var svg = svgEl("svg", {
      viewBox: "0 0 " + W + " " + VH, width: "100%", role: "img",
      "aria-label": "各价值链环节的公司与其申报冶炼厂所在国别之间的关系条数流向图，共 "
        + total + " 条"
    });

    // 先按固定次序算好几何，再按面积从大到小绘制，细带才不会被压住
    var geo = {}, ribbons = [];
    left.forEach(function (r) {
      countries.forEach(function (c) {
        var v = r.by[c] || 0;
        if (!v) return;
        var h = v * k;
        geo[r.id + "|" + c] = { y1: loff + lp[r.id].cur, y2: roff + rp[c].cur,
                                h: Math.max(h, 1) };
        lp[r.id].cur += h; rp[c].cur += h;
        ribbons.push({ r: r, c: c, v: v });
      });
    });
    ribbons.sort(function (a, b) { return b.v - a.v; });

    ribbons.forEach(function (rb) {
      var g = geo[rb.r.id + "|" + rb.c];
      var x1 = LX + NODEW, x2 = RX, cx = (x1 + x2) / 2;
      var p = svgEl("path", {
        d: "M" + x1 + "," + g.y1 + " C" + cx + "," + g.y1 + " " + cx + "," + g.y2
           + " " + x2 + "," + g.y2 + " L" + x2 + "," + (g.y2 + g.h)
           + " C" + cx + "," + (g.y2 + g.h) + " " + cx + "," + (g.y1 + g.h)
           + " " + x1 + "," + (g.y1 + g.h) + " Z",
        fill: FLOW_COUNTRY_COLOR[rb.c] || "var(--dim)", "fill-opacity": "0.3"
      });
      var t = svgEl("title", {});
      t.textContent = rb.r.nm + " → " + rb.c + "　" + rb.v + " 条";
      p.appendChild(t);
      svg.appendChild(p);
    });

    function text(x, ty, str, anchor, fill, size, weight) {
      var t = svgEl("text", { x: x, y: ty, "text-anchor": anchor, fill: fill,
        "font-size": size, "font-family": "var(--mono)" });
      if (weight) t.setAttribute("font-weight", weight);
      t.textContent = str;
      return t;
    }
    function leader(x, y1, y2) {
      return svgEl("path", { d: "M" + x + "," + y1 + " L" + x + "," + y2,
        stroke: "var(--line)", "stroke-width": "1", fill: "none" });
    }

    declash(left.map(function (r) {
      return { mid: loff + lp[r.id].y0 + lp[r.id].h / 2, r: r };
    }), GAP, 15, VH - 13).forEach(function (o) {
      var r = o.it.r, box = lp[r.id], y0 = loff + box.y0, dead = !r.total;
      svg.appendChild(svgEl("rect", { x: LX, y: y0, width: NODEW, height: box.h,
        rx: 2, fill: dead ? "#2b3441" : (STAGE_COLOR[r.id] || "var(--dim)") }));
      if (Math.abs(o.y - o.mid) > 2) svg.appendChild(leader(LX - 7, o.mid, o.y - 4));
      svg.appendChild(text(LX - 12, o.y - 3, r.nm, "end",
        dead ? "var(--faint)" : "var(--text)", "12.5", "600"));
      svg.appendChild(text(LX - 12, o.y + 11,
        dead ? "0 条 · 无出处" : r.total + " 条", "end",
        dead ? "var(--faint)" : "var(--dim)", "10.5"));
    });

    declash(countries.map(function (c) {
      return { mid: roff + rp[c].y0 + rp[c].h / 2, c: c };
    }), GAP, 15, VH - 13).forEach(function (o) {
      var c = o.it.c, box = rp[c], y0 = roff + box.y0, tx = RX + NODEW + 12;
      svg.appendChild(svgEl("rect", { x: RX, y: y0, width: NODEW, height: box.h,
        rx: 2, fill: FLOW_COUNTRY_COLOR[c] || "var(--dim)" }));
      if (Math.abs(o.y - o.mid) > 2) {
        svg.appendChild(leader(RX + NODEW + 7, o.mid, o.y - 4));
      }
      svg.appendChild(text(tx, o.y - 3, c, "start", "var(--text)", "12.5", "600"));
      svg.appendChild(text(tx, o.y + 11, String(ctot[c] || 0), "start",
        "var(--dim)", "10.5"));
    });

    chart.appendChild(svg);

    var cov = d.coverage || {};
    var withEdges = cov.nodesWithEdges || 0;
    var without = (cov.nodesTotal || 0) - withEdges;
    setText($("flow-lead"),
      "共 " + total + " 条关系，指向 " + (flow.distinctCountries || 0)
      + " 个国家或地区的冶炼厂。带子宽度是实测条数，不是示意。");
    setText($("flow-sub"), flow.relationLabel
      ? "语义：" + flow.relationLabel + "。"
      : "");

    var key = $("flow-key");
    key.textContent = "";
    var s1 = el("span");
    s1.appendChild(el("i"));
    s1.appendChild(document.createTextNode(
      "灰色 = 无出处。另有 " + without + " 家公司没有冶炼厂名单，未出现在本图中"));
    key.appendChild(s1);
    key.appendChild(el("span", null,
      "列出关系数最多的 " + (countries.length ? countries.length - 1 : 0)
      + " 个国别，长尾并入「其他」，合计仍等于总条数"));
  }

  /* ── 方法与来源 ── */
  function renderMethod(d) {
    var host = $("method");
    host.textContent = "";
    var perf = d.stagePerformance || {};
    var ex = perf.excluded || {};

    function para(strong, rest) {
      var p = document.createElement("p");
      if (strong) p.appendChild(el("b", null, strong));
      p.appendChild(document.createTextNode(rest));
      host.appendChild(p);
      return p;
    }

    para("节点来源：", "标普500成分股清单来自站内公司榜（" + (d.sourceUpstream || "站内管道") +
      "），每日更新，本页不另建取数管道。");
    para("阶段判定：", "由 SEC EDGAR 的官方 SIC 行业码判定。GICS 一级板块粒度不足——" +
      "苹果、英伟达与微软同属「科技」但产业链位置完全不同；SIC 分别为 3571 电子计算机整机、" +
      "3674 半导体、7372 预装软件，可以分开。每家公司的 SIC 与判定依据见各环节表格，" +
      "并附可点开的原始申报链接。");
    if ((d.chains || []).length) {
      para("产业链归属：", "同一套 SIC 码的第二个用途。纵向的 " + (d.stages || []).length
        + " 个环节说的是「在链上的哪一层」，横向的 " + d.chains.length
        + " 条一级产业链说的是「在哪条链上」——只分层不分链的话，半导体设备与农机会"
        + "落在同一格里，看着像邻居，其实一辈子不发生关系。归属由行业码按公开规则映射，"
        + "不按公司名分派；一家可以同时在多条链上（全池 "
        + ((d.coverage || {}).chainMulti || 0) + " 家如此），因为 SIC 3533 油气田机械"
        + "本来就既在油气链也在工业机械链。"
        + "链是分类，不是关系：同一条链上的两家公司之间有没有供应关系，只有申报文件说了算。");
    }
    para("环节涨跌：", perf.method || "");
    para("剔除口径：", "阶段未判定 " + (ex.stageNotResolved || 0) + " 家不摊入任何环节；" +
      "报价过期 " + (ex.staleQuote || 0) + " 家不计入均值；无报价 " + (ex.noQuote || 0) + " 家单独计。");

    var p = document.createElement("p");
    p.appendChild(el("b", null, "阶段划分说明："));
    host.appendChild(p);
    var ul = document.createElement("ul");
    (d.stages || []).forEach(function (s) {
      var li = document.createElement("li");
      li.appendChild(el("b", null, s.label + "："));
      li.appendChild(document.createTextNode(s.description || ""));
      ul.appendChild(li);
    });
    host.appendChild(ul);

    para("局限：", "SIC 是「比板块细」而不是「精确」——SEC 对同类公司的分配本身存在不一致" +
      "（半导体设备厂商有的归 3674 半导体、有的归 3559 专用机械）。因此本页阶段是行业码层面的" +
      "判定，不等于对单家公司业务结构的完整刻画。");
  }

  function fail(message) {
    var s = $("state");
    s.className = "state err";
    setText(s, message);
  }

  function render(d) {
    state.data = d;
    renderStatus(d);
    renderNotice(d);
    renderCoverageBySector(d);
    renderStages(d);
    renderFlow(d);
    renderMethod(d);
    $("state").hidden = true;
  }

  fetch("nodes.json", { cache: "no-cache" })
    .then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    })
    .then(function (d) {
      if (!d || !Array.isArray(d.nodes) || !d.nodes.length) {
        throw new Error("数据文件为空或结构不符");
      }
      render(d);
    })
    .catch(function (err) {
      fail("产业链数据加载失败：" + (err && err.message ? err.message : "未知错误") +
        "。这是加载问题，不代表数据不存在——请稍后重试。");
    });
})();
