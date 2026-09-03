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
    "upstream-resource": "var(--s1)", "intermediate-manufacturing": "var(--s2)",
    "brand-integration": "var(--s3)", "distribution-service": "var(--s4)",
    "platform-service": "var(--s5)", "supporting": "var(--s6)"
  };
  // 实物链四段按顺序展示；平台服务与支持性行业不在实物流转链条上，单独一组。
  var CHAIN = ["upstream-resource", "intermediate-manufacturing",
               "brand-integration", "distribution-service"];
  var OFFCHAIN = ["platform-service", "supporting"];

  var BASIS_LABEL = {
    "sic-refined": "SEC 官方 SIC 行业码判定",
    "sector-initial": "板块级初步口径",
    "sector-ambiguous": "板块横跨多段，仅给候选",
    "edge-derived": "由真实上下游关系反推",
    "unknown": "未判定"
  };

  var state = { data: null, open: null };

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
    failed: "取数失败",
    unknown: "无逐家记录"
  };
  var COV_ORDER = ["withEdges", "filedNoList", "noFiling", "failed", "unknown"];

  function covSeg(row) {
    return {
      withEdges: row.withEdges || 0,
      filedNoList: row.filedNoList || 0,
      noFiling: row.noFiling || 0,
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

  /* ── 环节卡片 ── */
  function countIn(d, stageId) {
    var n = 0;
    (d.nodes || []).forEach(function (x) { if (x.stage === stageId) n++; });
    return n;
  }

  function stageCard(d, meta) {
    var p = perfOf(d, meta.id) || {};
    var total = countIn(d, meta.id);
    var btn = el("button", "stage");
    btn.type = "button";
    btn.setAttribute("aria-expanded", "false");
    btn.setAttribute("aria-controls", "panel");
    btn.dataset.stage = meta.id;

    var bar = el("div", "bar");
    bar.style.background = STAGE_COLOR[meta.id] || "var(--dim)";
    btn.appendChild(bar);

    var nm = el("div", "nm");
    nm.appendChild(document.createTextNode(meta.label));
    nm.appendChild(el("small", null, meta.labelEn || ""));
    btn.appendChild(nm);

    btn.appendChild(el("div", "cnt", total + " 家 · " + (meta.description || "")));

    var perf = el("div", "perf");
    if (p.companies == null) {
      // 没有表现数据时如实说明，不显示成「0%」或「持平」——没算出来不等于没变化
      perf.appendChild(el("div", "none", "本次未生成环节表现数据"));
    } else {
      [["等权", p.equalWeightPct], ["市值加权", p.capWeightPct], ["中位", p.medianPct]]
        .forEach(function (pair) {
          var box = el("div", null, pair[0]);
          box.appendChild(el("b", cls(pair[1]), pct(pair[1])));
          perf.appendChild(box);
        });
      // 参与统计的公司少于该环节公司数时点明差额，避免读者以为涨跌覆盖全部
      if (p.companies < total) {
        perf.appendChild(el("div", "none",
          "（涨跌按 " + p.companies + " 家有效报价计，另 " + (total - p.companies) + " 家无有效报价）"));
      }
    }
    btn.appendChild(perf);

    btn.addEventListener("click", function () { toggle(meta.id); });
    return btn;
  }

  function renderStages(d) {
    var byId = {};
    (d.stages || []).forEach(function (s) { byId[s.id] = s; });
    [["chain", CHAIN], ["offchain", OFFCHAIN]].forEach(function (pair) {
      var host = $(pair[0]);
      host.textContent = "";
      pair[1].forEach(function (id) {
        if (byId[id]) host.appendChild(stageCard(d, byId[id]));
      });
    });
  }

  /* ── 展开的公司表：逐家显示 SIC 与判定依据 ── */
  var MAX_ROWS = 60;

  function renderPanel(d, stageId) {
    var panel = $("panel");
    panel.textContent = "";
    var meta = null;
    (d.stages || []).forEach(function (s) { if (s.id === stageId) meta = s; });
    if (!meta) { panel.hidden = true; return; }

    var list = (d.nodes || []).filter(function (n) { return n.stage === stageId; })
      .sort(function (a, b) { return (b.marketCap || 0) - (a.marketCap || 0); });

    var capBox = el("div", "cap");
    capBox.appendChild(el("b", null, meta.label));
    capBox.appendChild(document.createTextNode(
      " · " + list.length + " 家，按市值排序" +
      (list.length > MAX_ROWS ? "，显示前 " + MAX_ROWS + " 家" : "")));
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
    panel.hidden = false;
  }

  function toggle(stageId) {
    var opening = state.open !== stageId;
    state.open = opening ? stageId : null;
    Array.prototype.forEach.call(document.querySelectorAll(".stage"), function (b) {
      b.setAttribute("aria-expanded", b.dataset.stage === state.open ? "true" : "false");
    });
    if (state.open) {
      renderPanel(state.data, state.open);
      $("panel").scrollIntoView({ block: "nearest",
        behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
    } else {
      $("panel").hidden = true;
    }
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
