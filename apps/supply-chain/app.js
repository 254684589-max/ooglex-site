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
    var cov = d.coverage || {};
    // 副标题照数据写。写死「标普500成分股按价值链环节分层」的那一版，在
    // 外国发行人入池、变成 642 家之后就成了假话——与首页卡片栽的是同一个跟头：
    // 静态文案里的数字不会自己更新，数据一变它就开始说错话且无人报错。
    var sub = $("subtitle");
    if (sub) {
      var sp = cov.poolSp500, fo = cov.poolForeignIssuer;
      setText(sub, (sp && fo
        ? "标普500成分股 " + sp + " 家 + 在美上市外国私人发行人 " + fo + " 家"
        : (cov.nodesTotal || "—") + " 家公司")
        + "，按 12 个价值链环节 × " + (cov.chainsTotal || "—")
        + " 条一级产业链两维定位 · Global Supply Chain");
    }

    var row = $("statusrow");
    row.textContent = "";
    // 专业口径的摘要条：先给量级，再给新鲜度。此前只有四项，读者看不到
    // 「有多少条关系、来自几家申报人」——那才是这个板块的主量级。
    var items = [
      ["公司", (cov.nodesTotal != null ? fmt(cov.nodesTotal) : "—") + " 家"],
      ["关系", (cov.edgesTotal != null ? fmt(cov.edgesTotal) : "—") + " 条"],
      ["申报人", (cov.nodesWithEdges != null ? fmt(cov.nodesWithEdges) : "—") + " 家"],
      ["冶炼厂", (((cov.formSd || {}).uniqueSmelters) != null
                   ? fmt(cov.formSd.uniqueSmelters) : "—") + " 家"],
      ["数据日", d.asOf || "—"],
      ["更新", relTime(d.updatedAt) || "—"]
    ];
    items.forEach(function (pair) {
      var s = el("span", "status");
      s.appendChild(document.createTextNode(pair[0] + " "));
      s.appendChild(el("b", null, pair[1]));
      row.appendChild(s);
    });
    // 「频率 每日」曾经单独占一格，那是误导：**关系数据一年一次**
    // （Form SD 每年 5 月 31 日前申报，抽取器自带申报季闸门），每日刷新的
    // 只有行情。两种频率并在一个词里，读者会以为供应链关系天天在变。
    var freq = el("span", "status freq");
    freq.appendChild(document.createTextNode("频率 "));
    freq.appendChild(el("b", null, "关系一年一次"));
    freq.appendChild(el("s", null, " · 行情每日"));
    freq.title = "Form SD 每年 5 月 31 日前申报，冶炼厂关系一年只变一次；"
      + "市值与涨跌来自站内行情，每日更新。";
    row.appendChild(freq);
  }

  function fmt(n) {
    return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
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

  // 国别栏直接列 30 行，其中 11 行只有 1 家——长尾把版面撑得很长，
  // 却读不出任何东西。并入「其他」，与真实流向图那边 FLOW_TOP_COUNTRIES
  // 同一套口径：**不是省略，是把长尾收拢，合计仍等于全池**。
  var COUNTRY_ROWS = 12;

  function foldTail(rows, keep) {
    if (!rows || rows.length <= keep + 1) return rows || [];
    var head = rows.slice(0, keep);
    var tail = rows.slice(keep);
    var merged = { sector: "其他 " + tail.length + " 个国别／地区", companies: 0,
                   withEdges: 0, filedNoList: 0, resourceExtraction: 0,
                   noFiling: 0, failed: 0, unscanned: 0 };
    tail.forEach(function (r) {
      ["companies", "withEdges", "filedNoList", "resourceExtraction",
       "noFiling", "failed", "unscanned"].forEach(function (k) {
        merged[k] = (merged[k] || 0) + (r[k] || 0);
      });
    });
    head.push(merged);
    return head;
  }

  /* ── 公司查找 ────────────────────────────────────────────────────────
     642 家而页面上零个输入框。匹配代码、中文名与英文名三项，
     **匹配到哪一项就在结果里标出来**——不标的话，搜「台积电」出来一行
     「TSM TAIWAN SEMICONDUCTOR…」，读者不知道是哪个字段命中的。
     结果里同时印这家有没有关系数据，省得点进去才发现是空的。 */
  var QMAX = 12;

  function lookupRows(d, q) {
    var s = String(q || "").trim().toLowerCase();
    if (!s) return [];
    var out = [];
    (d.nodes || []).forEach(function (n) {
      var sym = String(n.symbol || "").toLowerCase();
      var zh = String(n.name || "");
      var en = String(n.nameEn || "").toLowerCase();
      var hit = null, rank = 9;
      if (sym === s) { hit = "代码"; rank = 0; }
      else if (sym.indexOf(s) === 0) { hit = "代码"; rank = 1; }
      else if (zh.indexOf(q.trim()) >= 0) { hit = "中文名"; rank = 2; }
      else if (en.indexOf(s) === 0) { hit = "英文名"; rank = 3; }
      else if (en.indexOf(s) >= 0) { hit = "英文名"; rank = 4; }
      else if (sym.indexOf(s) >= 0) { hit = "代码"; rank = 5; }
      if (hit) out.push({ node: n, hit: hit, rank: rank });
    });
    out.sort(function (a, b) {
      return a.rank - b.rank
        || (b.node.edgeCount || 0) - (a.node.edgeCount || 0)
        || String(a.node.symbol).localeCompare(String(b.node.symbol));
    });
    return out;
  }

  function initLookup(d) {
    var input = $("q"), list = $("qlist");
    if (!input || !list) return;
    var cur = -1, rows = [];

    function close() {
      list.hidden = true; list.textContent = ""; cur = -1; rows = [];
      input.setAttribute("aria-expanded", "false");
    }

    function draw() {
      var all = lookupRows(d, input.value);
      rows = all.slice(0, QMAX);
      list.textContent = "";
      if (!input.value.trim()) { close(); return; }
      if (!rows.length) {
        var none = el("div", "qnone", "没有匹配的公司。本板块收录 "
          + ((d.coverage || {}).nodesTotal || 0) + " 家，不是全市场。");
        list.appendChild(none);
        list.hidden = false;
        input.setAttribute("aria-expanded", "true");
        return;
      }
      rows.forEach(function (r, i) {
        var n = r.node;
        var a = el("a", i === cur ? "on" : null);
        a.href = "company.html?symbol=" + encodeURIComponent(n.symbol || "");
        a.setAttribute("role", "option");
        a.setAttribute("aria-selected", i === cur ? "true" : "false");
        a.appendChild(el("span", "qs", n.symbol || ""));
        a.appendChild(document.createTextNode(n.name || n.nameEn || ""));
        // 命中在哪一项 + 有没有关系数据，都在这一行里说清
        a.appendChild(el("span", "qm", "配" + r.hit
          + " · " + (n.edgeCount ? (n.edgeCount + " 条关系") : "暂无关系数据")));
        list.appendChild(a);
      });
      if (all.length > QMAX) {
        // 截断必须说出来，否则读者会以为只有这几家匹配
        list.appendChild(el("div", "qnone",
          "另有 " + (all.length - QMAX) + " 家匹配未列出，输入更完整的名称可缩小范围"));
      }
      list.hidden = false;
      input.setAttribute("aria-expanded", "true");
    }

    input.addEventListener("input", function () { cur = -1; draw(); });
    input.addEventListener("keydown", function (ev) {
      if (ev.key === "Escape") { input.value = ""; close(); return; }
      if (!rows.length) return;
      if (ev.key === "ArrowDown" || ev.key === "ArrowUp") {
        ev.preventDefault();
        cur += (ev.key === "ArrowDown" ? 1 : -1);
        if (cur < 0) cur = rows.length - 1;
        if (cur >= rows.length) cur = 0;
        draw();
        var on = list.querySelector("a.on");
        if (on && on.scrollIntoView) on.scrollIntoView({ block: "nearest" });
      } else if (ev.key === "Enter") {
        // 没有用方向键选时，回车去第一条——这是终端里的习惯动作
        var pick = rows[cur >= 0 ? cur : 0];
        if (pick) {
          ev.preventDefault();
          location.href = "company.html?symbol="
            + encodeURIComponent(pick.node.symbol || "");
        }
      }
    });
    document.addEventListener("click", function (ev) {
      if (!input.contains(ev.target) && !list.contains(ev.target)) close();
    });
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

    // 折叠头上照实印关键数字。这个面板默认收起，但收起的是**明细**，
    // 不是结论——一眼要能看到「642 家里只有 127 家有关系数据」。
    var cv = d.coverage || {};
    var sum = $("cov-sum");
    if (sum) {
      var withEdges = cv.nodesWithEdges || 0;
      var totalN = cv.nodesTotal || 0;
      sum.textContent = "";
      sum.appendChild(document.createTextNode("全池 "));
      sum.appendChild(el("b", null, String(totalN)));
      sum.appendChild(document.createTextNode(" 家里 "));
      sum.appendChild(el("b", null, String(withEdges)));
      sum.appendChild(document.createTextNode(" 家有出处关系（"
        + (totalN ? Math.round(withEdges / totalN * 100) : 0)
        + "%）· 点开看各板块与国别为什么差这么多"));
    }

    setText($("cov-lead"), anyStatus
      ? "当前唯一的关系数据源是 SEC 的 Form SD 冲突矿产申报，它只适用于产品中含钽锡钨金的发行人。"
        + "因此各板块的覆盖率差别很大，而且有些板块的空白不会随时间填上——银行和 REIT 没有实体产品，"
        + "本来就不需要申报。下面按板块把「有名单」和「为什么没有」分开列出。"
      : "当前唯一的关系数据源是 SEC 的 Form SD 冲突矿产申报，它只适用于产品中含钽锡钨金的发行人。"
        + "本轮尚无逐家申报状态记录，因此只列出各板块有名单的家数，不推断其余公司没有数据的原因。");

    drawCovRows($("cov-rows"), rows);

    // ── 第二个池：外国发行人按国别 ────────────────────────────────────
    // 它们没有站内板块分类。全塞进「未分类」就是一个 147 家的黑箱，
    // 按国别拆至少看得出这批公司来自哪里、哪一档缺得多。
    var byCountry = (d.coverage && d.coverage.byCountry) || [];
    var lead2 = $("cov-country-lead");
    var rows2 = $("cov-country-rows");
    if (rows2) rows2.textContent = "";
    if (lead2) {
      if (!byCountry.length) {
        lead2.hidden = true;
      } else {
        lead2.hidden = false;
        var n2 = byCountry.reduce(function (a, r) { return a + (r.companies || 0); }, 0);
        // 国别取自哪个 SEC 字段，必须照数据写。营业地址回答的是「办公室在哪」，
        // 对在美上市的外国发行人往往是它的美国办公室（爱尔康显示得州、
        // 壳牌显示华盛顿特区）；注册地回答的是「依哪国法律成立」，偏差在
        // 开曼／泽西这类控股架构。两者不是一回事，不能笼统说成「公司在哪国」。
        var basis = (d.coverage && d.coverage.countryBasis) || {};
        var byInc = basis["state-of-incorporation"] || 0;
        var byAddr = (basis["business-address"] || 0) + (basis["mailing-address"] || 0);
        var noBasis = basis.unknown || 0;
        var note = "";
        if (byInc || byAddr || noBasis) {
          note = "国别取自 SEC 备案：其中 " + byInc + " 家按注册地（依哪国法律成立，"
            + "开曼、泽西这类控股架构会记到注册地而不是实际总部）、"
            + byAddr + " 家按备案地址"
            + (noBasis ? "，另有 " + noBasis + " 家 SEC 备案里没有可用的地区字段，列为未归类" : "")
            + "。";
        }
        setText(lead2, "另有在美上市的外国私人发行人 " + n2
          + " 家（报 20-F／40-F 且同时报 Form SD 的那一批）。它们没有站内板块分类，"
          + "下面按国别拆——注意这一栏的口径是国别，不是板块。" + note);
        drawCovRows(rows2, foldTail(byCountry, COUNTRY_ROWS));
      }
    }

    setText($("cov-foot"), anyStatus
      ? "「无申报」不等于「这家公司没有供应链」，只表示它没有提交 Form SD——多数是因为规则对它不适用。"
        + "「有申报未列名单」是规则允许的：Form SD 强制申报、不强制列出冶炼厂名单。"
        + "这两类占多数，所以覆盖率永远到不了 100%，这是披露制度本身的上限。"
      : "「有名单」以外的公司分三种情况：没有申报义务、申报了但正文未列名单、本轮取数失败。"
        + "三者性质完全不同，在拿到逐家记录之前不在这里合并成一个数。");
  }

  /* 画一组覆盖率行。两个池共用——各写一套的话，改了配色或分档，另一处就
     会用旧口径显示，而两栏看着一模一样，没人分得出哪一栏是旧的。 */
  // 逐环节的申报状态分布。分档取自节点自带的 formSdStatus，与页顶那张
  // 总表同源，因此两处的数永远对得上——各算各的迟早会对不上。
  function stageCoverage(d, stageId) {
    var out = { withEdges: 0, listed: 0, filedNoList: 0,
                resourceExtraction: 0, noFiling: 0, unknown: 0 };
    visibleNodes(d).forEach(function (n) {
      if (n.stage !== stageId) return;
      if (n.edgeCount) out.withEdges += 1;
      var k = n.formSdStatus;
      if (k === "listed") out.listed += 1;
      else if (k === "filed-no-list") out.filedNoList += 1;
      else if (k === "resource-extraction") out.resourceExtraction += 1;
      else if (k === "no-filing") out.noFiling += 1;
      else out.unknown += 1;
    });
    return out;
  }

  // 把「为什么这一段是这个数」写成一句话。**不同的 0 要说成不同的 0。**
  function coverWhy(st, total) {
    var bits = [];
    if (st.listed) bits.push("有名单 " + st.listed + " 家");
    if (st.filedNoList) bits.push("有申报但正文未列名单 " + st.filedNoList + " 家");
    if (st.resourceExtraction) {
      bits.push("申报的是 13q-1 资源开采付款 " + st.resourceExtraction
        + " 家（那套披露里没有冶炼厂这个概念）");
    }
    if (st.noFiling) {
      bits.push("无 Form SD 申报 " + st.noFiling
        + " 家（规则只管产品含钽锡钨金的发行人，多数不适用）");
    }
    if (st.unknown) bits.push("尚无逐家申报状态 " + st.unknown + " 家");
    return "本环节 " + total + " 家：" + bits.join("；")
      + "。「无申报」不等于这些公司没有供应链。";
  }

  function drawCovRows(wrap, rows) {
    if (!wrap) return;
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

  /* 链的选择条，按**层次**排：一进页面就看得出谁在上游、谁在下游。
     层次由 77 条上下游连线算出（最长路径），不是手工排的——手排的话改一条连线
     层次就和连线对不上，而且没人看得出对不上。
     链是**分类**，不是边：选中一条链只是把公司筛出来，不声称同一条链上的
     两家公司之间有供应关系。这句话写在条子下面。 */
  function chainChip(d, id, label, count, edges) {
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
  }

  function renderChainPicker(d) {
    var host = $("chainpick");
    if (!host) return;
    host.textContent = "";
    var rows = (d.chains || []).filter(function (c) { return c.count > 0; });
    if (!rows.length) { host.hidden = true; return; }
    host.hidden = false;

    var all = chainChip(d, null, "全部产业链", (d.nodes || []).length,
      (d.coverage && d.coverage.edgesTotal) || 0);
    if (!state.chain) all.classList.add("on");
    var top = el("div", "picktop");
    top.appendChild(all);
    var depth = (d.coverage || {}).chainDepth || 0;
    if (depth) {
      top.appendChild(el("span", "pickhint",
        "下面按上下游层次排：越靠上越上游，共 " + depth
        + " 层，由 " + ((d.coverage || {}).chainLinksTotal || 0)
        + " 条连线算出，不是手工排的"));
    }
    host.appendChild(top);

    // 有 layer 的按层排；没有 layer 的是横跨全链的使能链，单独一行。
    var byLayer = {}, cross = [];
    rows.forEach(function (c) {
      if (typeof c.layer === "number") {
        (byLayer[c.layer] = byLayer[c.layer] || []).push(c);
      } else {
        cross.push(c);
      }
    });
    var levels = Object.keys(byLayer).map(Number).sort(function (a, b) { return a - b; });

    levels.forEach(function (lv, i) {
      var band = el("div", "picklv");
      var tag = el("span", "lv");
      tag.appendChild(document.createTextNode("L" + lv));
      // 首尾给个方向感。中间不硬起名字——名字会随连线漂移，而层号不会。
      if (i === 0) tag.appendChild(el("s", null, "最上游"));
      else if (i === levels.length - 1) tag.appendChild(el("s", null, "最终端"));
      band.appendChild(tag);
      var wrap = el("div", "lvchips");
      byLayer[lv].sort(function (a, b) { return b.count - a.count; })
        .forEach(function (c) {
          wrap.appendChild(chainChip(d, c.id, c.label, c.count, c.edgeCount));
        });
      band.appendChild(wrap);
      host.appendChild(band);
    });

    if (cross.length) {
      var band2 = el("div", "picklv cross");
      var t2 = el("span", "lv");
      t2.appendChild(document.createTextNode("使能"));
      t2.appendChild(el("s", null, "横跨全链"));
      band2.appendChild(t2);
      var w2 = el("div", "lvchips");
      cross.sort(function (a, b) { return b.count - a.count; })
        .forEach(function (c) {
          w2.appendChild(chainChip(d, c.id, c.label, c.count, c.edgeCount));
        });
      band2.appendChild(w2);
      host.appendChild(band2);
    }
  }

  /* 链间上下游。**这一段画的是产业结构框架，不是实测关系**——与那两万条
     指名申报人与冶炼厂、能点开原始申报的边不是一回事，所以它自己有一块区域、
     自己的样式、自己那句说明，不与实测数据放在同一个视觉层里。 */
  function linksOf(d, chainId, dir) {
    var key = dir === "up" ? "to" : "from";
    return (d.chainLinks || []).filter(function (l) { return l[key] === chainId; });
  }

  function linkRow(d, link, dir) {
    var otherId = dir === "up" ? link.from : link.to;
    var meta = chainMeta(d, otherId);
    var back = link.direction === "counterflow";
    var row = el("button", "flowlink" + (back ? " back" : ""));
    row.type = "button";
    row.appendChild(el("span", "ar", dir === "up" ? "←" : "→"));
    row.appendChild(el("span", "nm", meta ? meta.label : otherId));
    row.appendChild(el("span", "fl", link.flow || ""));
    if (back) {
      // 逆向边是实物链本来的形态（回收料返上游、设备与芯片互供），
      // 不标出来的话读者会以为分层排错了。
      var tg = el("span", "bk", "逆向");
      tg.title = link.counterflowWhy || "与所在环的主流向相反";
      row.appendChild(tg);
    }
    row.title = (dir === "up" ? "上游：" : "下游：") + (meta ? meta.label : otherId)
      + " · " + (link.flow || "")
      + (back ? "（逆向：" + (link.counterflowWhy || "") + "）" : "");
    row.addEventListener("click", function () {
      state.chain = otherId;
      state.open = null;
      state.seg = null;
      renderStages(d);
      var host = $("chainpick");
      if (host && host.scrollIntoView) host.scrollIntoView({ block: "start" });
    });
    return row;
  }

  // 沿 77 条框架连线走**多跳**，得到一条链的完整上游谱系与下游触达。
  //
  // 页面此前只画一跳：选中半导体，看得到「化工 → 半导体」，看不到
  // 「石油 → 化工 → 半导体」这条路径本身。而这个板块的横轴价值恰恰在路径上。
  //
  // **逆向边（回收料返上游那六条）不参与推导**：它们是声明过的剪边，
  // 沿着它们走会绕回起点，把「上游」算成一个环。
  //
  // 语义仍然是**框架，不是实测关系**：说的是「按产业结构，这条链的投入
  // 间接来自哪几条链」，不是「这两条链上的公司之间有供货」。
  function chainLineage(d, id, dir) {
    var links = (d.chainLinks || []).filter(function (l) {
      return l.direction !== "counterflow";
    });
    var seen = {}, out = [];
    var frontier = [id];
    seen[id] = true;
    var hops = 0;
    while (frontier.length && hops < 12) {          // 12 > 层数上限，够走到头
      hops += 1;
      var next = [];
      frontier.forEach(function (cur) {
        links.forEach(function (l) {
          var from = dir === "up" ? l.to : l.from;
          var to = dir === "up" ? l.from : l.to;
          if (from !== cur || seen[to]) return;
          seen[to] = true;
          next.push(to);
          out.push({ id: to, via: cur, flow: l.flow, hop: hops });
        });
      });
      frontier = next;
    }
    return out;
  }

  // 把谱系按层号分组。层号是 sic_chains 算出来的，不是这里现编的。
  //
  // **没有层号的使能链不能静默丢掉。** 它们不参与分层是因为横跨所有层，
  // 但「石油 → 物流（运输燃料）」是一条真的入边——把物流从「石油的下游」里
  // 抹掉，路径就少说了一段。单独归到「使能层」一格，不塞进任何一层。
  function byLayer(d, items) {
    var meta = {};
    (d.chains || []).forEach(function (c) { meta[c.id] = c; });
    var buckets = {}, cross = [];
    items.forEach(function (it) {
      var c = meta[it.id];
      if (!c) return;
      var row = { chain: c, hop: it.hop, flow: it.flow };
      if (c.layer == null) cross.push(row);
      else (buckets[c.layer] = buckets[c.layer] || []).push(row);
    });
    var out = Object.keys(buckets).map(Number).sort(function (a, b) { return a - b; })
      .map(function (L) { return { layer: L, items: buckets[L] }; });
    if (cross.length) out.push({ layer: null, items: cross });
    return out;
  }

  function renderLineage(d, host, meta) {
    var up = byLayer(d, chainLineage(d, meta.id, "up"));
    var down = byLayer(d, chainLineage(d, meta.id, "down"));
    if (!up.length && !down.length) return;

    var wrap = el("div", "lineage");
    var cap = el("p", "lncap",
      "按 " + ((d.chainLinks || []).filter(function (l) {
        return l.direction !== "counterflow";
      }).length) + " 条正向框架连线推出的完整路径：这条链的投入间接来自左边几层，"
      + "产出间接流向右边几层。**这是产业结构框架，不是实测的公司间关系**——"
      + "逆向边（回收料返上游那几条）不参与推导，否则「上游」会算成一个环；"
      + "横跨全链的使能链没有层号，单列一格——它们不参与分层，"
      + "但入边是真的（石油给物流的是运输燃料），不能丢。");
    cap.textContent = cap.textContent.replace(/\*\*/g, "");
    wrap.appendChild(cap);

    var strip = el("div", "lnstrip");
    function column(group, cls) {
      var col = el("div", "lncol " + cls + (group.layer == null ? " cross" : ""));
      col.appendChild(el("span", "lv",
        group.layer == null ? "使能层" : ("L" + group.layer)));
      group.items.forEach(function (it) {
        var a = el("a", "lnchip");
        a.href = "?chain=" + encodeURIComponent(it.chain.id);
        a.appendChild(document.createTextNode(it.chain.label));
        a.appendChild(el("s", null, String(it.chain.count) + " 家"));
        a.title = "第 " + it.hop + " 跳可达" + (it.flow ? "：" + it.flow : "");
        col.appendChild(a);
      });
      return col;
    }
    up.forEach(function (g) { strip.appendChild(column(g, "up")); });
    var self = el("div", "lncol self");
    self.appendChild(el("span", "lv", "L" + (meta.layer == null ? "?" : meta.layer)));
    var me = el("span", "lnchip me", meta.label);
    me.appendChild(el("s", null, String(meta.count) + " 家"));
    self.appendChild(me);
    strip.appendChild(self);
    down.forEach(function (g) { strip.appendChild(column(g, "down")); });
    wrap.appendChild(strip);
    host.appendChild(wrap);
  }

  function renderChainFlow(d) {
    var host = $("chainflow");
    if (!host) return;
    host.textContent = "";
    if (!state.chain) { host.hidden = true; return; }
    var meta = chainMeta(d, state.chain);
    if (!meta) { host.hidden = true; return; }
    host.hidden = false;

    var up = linksOf(d, state.chain, "up");
    var down = linksOf(d, state.chain, "down");
    var cross = (d.chainCrossCutting || {})[state.chain];

    var hd = el("div", "cfhd");
    hd.appendChild(el("b", null, meta.label + " 的上下游"));
    hd.appendChild(el("span", "tag", "产业结构框架"));
    host.appendChild(hd);

    // 先给完整路径（多跳），再给直接相邻那一跳的明细。
    renderLineage(d, host, meta);

    if (cross) {
      // 使能链没有连线不是数据缺失，是刻意的。不说明的话页面上就是个断头。
      host.appendChild(el("p", "cfnote", cross + "——" +
        "逐条连会画出上百条线且没有信息量，因此这里不列。"));
    }

    [["up", "上游 · 谁供给它", up], ["down", "下游 · 它供给谁", down]]
      .forEach(function (pair) {
        if (!pair[2].length) return;
        var col = el("div", "cfcol");
        col.appendChild(el("div", "cfcap", pair[1] + "（" + pair[2].length + "）"));
        pair[2].forEach(function (link) { col.appendChild(linkRow(d, link, pair[0])); });
        host.appendChild(col);
      });

    if (!up.length && !down.length && !cross) {
      host.appendChild(el("p", "cfnote", "本链在框架里暂无上下游连线。"));
    }

    // 这句话是这一块的底线，任何时候都要在，且要说清与实测数据的区别
    host.appendChild(el("p", "cfwarn",
      "以上是产业结构框架（谁给谁供料），按行业通识定义，不指名任何公司，"
      + "因此不附出处。它与本页那 "
      + ((d.coverage || {}).edgesTotal || 0)
      + " 条关系不是一回事——那些每一条都指名一家申报人和一家冶炼厂，"
      + "都能点开原始申报。同一条链上的两家公司之间有没有供应关系，只有申报文件说了算。"));
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
      // 市值合计只含有站内报价的公司。外国发行人那批没有报价，如实不计入，
      // 并在这一格的提示里说出来——不说的话「18 家 / 10.98 万亿」看着像
      // 18 家的合计，其实是 15 家的。
      var quoted = visibleNodes(d).filter(function (x) {
        return x.stage === meta.id && isNum(x.marketCap);
      }).length;
      var mcEl = el("span", "mc", cap(capOf(d, meta.id)));
      mcEl.title = total === quoted
        ? "本环节 " + total + " 家的市值合计"
        : "本环节 " + total + " 家里 " + quoted + " 家有站内报价，市值合计只含这 "
          + quoted + " 家；其余是外国私人发行人，站内无报价";
      if (total !== quoted) mcEl.appendChild(el("s", null, "*"));
      hd.appendChild(mcEl);

      // 这一段有多少家带出处关系。**覆盖率要写在读者正在看的地方**——
      // 此前只在页顶那张总表里，读者看到「金融与专业服务 104 家」根本
      // 无从知道它是 0/104；而各段的 0 成因完全不同：资源开采那 65 家里
      // 59 家报的是 13q-1 资源开采付款（那套披露里没有冶炼厂这个概念），
      // 物流与运输 10 家则是全部无申报。两种 0 混成一个空白就是在说假话。
      var st = stageCoverage(d, meta.id);
      var covEl = el("span", "bandcov" + (st.withEdges ? "" : " zero"));
      covEl.appendChild(el("b", null, st.withEdges + "/" + total));
      covEl.appendChild(el("s", null, " 有出处"));
      covEl.title = coverWhy(st, total);
      hd.appendChild(covEl);
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
    renderChainFlow(d);
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
  /* 上游集中度：一家冶炼厂被多少家申报人共同列入。
     这是本板块少见的、完全不需要推断的读数——名单里数出来的。
     但分母是**有名单的那 90 家**，不是 495 家，不写清就是在夸大覆盖。 */
  var _bySym = null;
  function nodeBySymbol(d, sym) {
    if (!_bySym) {
      _bySym = {};
      (d.nodes || []).forEach(function (n) { _bySym[n.symbol] = n; });
    }
    return _bySym[sym];
  }

  /* ── 国别暴露 ──────────────────────────────────────────────────────
     **条数与暴露家数是两个读数，只印一个会把风险读反。**
     印度尼西亚按条数排第 4（6.6%），按暴露家数却排第 1（118 家，高于中国的
     107 家）——几乎每一家有名单的公司都沾到印尼的锡。页面两个都印，
     条的宽度按**暴露家数**画，因为这一屏回答的是「多少家沾到」。 */
  var EXPO_ROWS = 20;

  function renderExposure(d) {
    var sec = $("expsec");
    if (!sec) return;
    var rows = (d.coverage || {}).countryExposure || [];
    if (!rows.length) { sec.hidden = true; return; }
    sec.hidden = false;

    var listed = Object.keys(d.edgeIndex || {}).length;
    var edgesTotal = (d.coverage || {}).edgesTotal || 0;
    var shown = rows.slice(0, EXPO_ROWS);
    setText($("expo-lead"),
      "按冶炼厂所在国别看暴露面：左边是**有多少家申报人的名单里出现过该国的厂**，"
        .replace(/\*\*/g, "")
      + "右边是关系条数。分母是有名单的 " + listed + " 家公司（不是全部 "
      + ((d.coverage || {}).nodesTotal || 0) + " 家）。共 " + rows.length
      + " 个国别，下面列前 " + shown.length + " 个。");

    var host = $("expo-rows");
    host.textContent = "";
    shown.forEach(function (r, i) {
      var line = el("div", "exprow");
      line.appendChild(el("span", "rk", String(i + 1)));
      line.appendChild(el("span", "nm", r.country || "未写明"));
      var bar = el("span", "bar");
      bar.style.flexBasis = Math.max(3, (r.filerShare || 0) * 100) + "%";
      bar.style.flexGrow = "0";
      line.appendChild(bar);
      var n = el("span", "n");
      n.appendChild(document.createTextNode(String(r.filerCount)));
      n.appendChild(el("s", null, " 家 " + Math.round((r.filerShare || 0) * 100) + "%"));
      line.appendChild(n);
      var ed = el("span", "ed", fmt(r.edges) + " 条");
      line.appendChild(ed);
      line.title = (r.country || "未写明") + "：" + r.filerCount + " 家有名单的公司"
        + "（共 " + listed + " 家）的申报名单里出现过该国的冶炼厂，占 "
        + Math.round((r.filerShare || 0) * 100) + "%；"
        + "关系 " + r.edges + " 条，占全部 " + edgesTotal + " 条的 "
        + (edgesTotal ? (r.edges / edgesTotal * 100).toFixed(1) : 0) + "%。"
        + "「出现在名单里」不等于采购关系。";
      host.appendChild(line);
    });

    // 两个读数排名不一致时把它说出来——那正是这一屏存在的理由。
    var byEdges = rows.slice().sort(function (a, b) { return b.edges - a.edges; });
    var note = "";
    if (byEdges.length && rows.length && byEdges[0].country !== rows[0].country) {
      note = "注意两列排名不同：按暴露家数第一的是「" + rows[0].country
        + "」（" + rows[0].filerCount + " 家），按关系条数第一的是「"
        + byEdges[0].country + "」（" + fmt(byEdges[0].edges) + " 条）。"
        + "条数说的是图谱里有多少分量落在那里，家数说的是暴露面有多宽，"
        + "两者不是一回事。";
    }
    setText($("expo-foot"), note
      + "本屏与上游集中度同源，都是从申报名单里数出来的，不含推断。"
      + "「某国的冶炼厂出现在这些公司的名单里」不说明它们与那些冶炼厂之间"
      + "有直接采购关系——冶炼厂在供应链的第三层，申报的原义是"
      + "「出现在本公司供应链中」。");
  }

  function renderConcentration(d) {
    var sec = $("concsec");
    if (!sec) return;
    var rows = d.upstreamConcentration || [];
    if (!rows.length) { sec.hidden = true; return; }
    sec.hidden = false;

    var cov = d.coverage || {};
    var listed = Object.keys(d.edgeIndex || {}).length;
    setText($("conc-lead"),
      "被最多申报人共同列入的 " + rows.length + " 家冶炼厂。分母是有名单的 "
      + listed + " 家公司（不是全部 " + (cov.nodesTotal || 0)
      + " 家）；登记表共 " + (cov.upstreamConcentrationTotal || 0)
      + " 家被两家以上共同申报。");

    var host = $("conc-rows");
    host.textContent = "";
    // 同一家厂可能被拆成两条：一部分申报人给了 RMI 编号、一部分只给名字，
    // 而登记表**刻意不做同义合并**（宁可一家重复出现，不可两家被错并成一家）。
    // 榜单上就会出现两行同名——不解释的话看起来像 bug，所以标出来并写清。
    var seen = {};
    rows.forEach(function (r) {
      var k = (r.name || "").toLowerCase();
      seen[k] = (seen[k] || 0) + 1;
    });
    var splitNames = Object.keys(seen).filter(function (k) { return seen[k] > 1; });

    rows.forEach(function (row, i) {
      var line = el("div", "concrow");
      line.appendChild(el("span", "rk", String(i + 1)));
      var nm = el("span", "nm", row.nameZh || row.name || row.id);
      if (splitNames.indexOf((row.name || "").toLowerCase()) >= 0) {
        var mark = el("s", null, "同名另有一条");
        mark.title = "这家厂在登记表里有两条：一部分申报人给了 RMI 编号、"
          + "一部分只给名字。登记表不做同义合并，所以它的真实共同申报数比这一行更高。";
        nm.appendChild(mark);
      }
      line.appendChild(nm);
      line.appendChild(el("span", "ct", row.country || "—"));
      var bar = el("span", "bar");
      // 分母用**有名单的公司数**而不是榜首：40/90 说得出「四成有名单的公司都列了它」，
      // 而 40/40 只会让前 30 名的条子长得一模一样，什么也没说。
      var ratio = listed ? row.filerCount / listed : 0;
      bar.style.flexBasis = Math.max(3, ratio * 100) + "%";
      bar.style.flexGrow = "0";
      line.appendChild(bar);
      line.appendChild(el("span", "n", row.filerCount + " 家"));
      // 点开看是**哪** N 家。此前只印得出数字，读者看得到「49 家」、
      // 看不到是哪 49 家——而咽喉点的暴露反查正是这份数据最有价值的读法。
      // **语义不变**：仍然只是「这 N 家的申报名单里都有它」，
      // 不是采购关系，展开的那一段里再写一次。
      var names = row.filers || [];
      if (names.length) {
        var more = el("button", "expand");
        more.type = "button";
        more.setAttribute("aria-expanded", "false");
        more.textContent = "看是哪几家";
        var box = el("div", "concfilers");
        box.hidden = true;
        var cap = el("p", "cf-cap",
          "这 " + names.length + " 家申报人的 Form SD 名单里都出现了「"
          + (row.name || row.id) + "」。**只是共同列入，不表示它们与这家冶炼厂"
          + "之间有采购关系，也不表示这几家公司之间有业务往来。**");
        cap.textContent = cap.textContent.replace(/\*\*/g, "");
        box.appendChild(cap);
        var chips = el("div", "cf-chips");
        names.forEach(function (sym) {
          var node = nodeBySymbol(d, sym);
          var a = el("a", "cf-chip");
          a.href = "company.html?symbol=" + encodeURIComponent(sym);
          a.appendChild(document.createTextNode((node && node.name) || sym));
          a.appendChild(el("s", null, sym));
          chips.appendChild(a);
        });
        box.appendChild(chips);
        more.onclick = function () {
          box.hidden = !box.hidden;
          more.setAttribute("aria-expanded", box.hidden ? "false" : "true");
          more.textContent = box.hidden ? "看是哪几家" : "收起";
        };
        line.appendChild(more);
        host.appendChild(line);
        host.appendChild(box);
        return;
      }
      line.title = (row.name || "") + "（" + (row.country || "未标注") + "）"
        + " 出现在 " + row.filerCount + " 家申报人的名单里，占有名单公司的 "
        + Math.round(ratio * 100) + "%"
        + " · 标识：" + (row.identifierType === "rmi-cid"
            ? "RMI 编号 " + row.id : "仅有名字")
        + ((row.minerals || []).length ? " · " + row.minerals.join("、") : "");
      host.appendChild(line);
    });

    setText($("conc-foot"),
      "条的长度是「占有名单公司的比例」，分母 " + listed + " 家。"
      + "「被 N 家共同列入」只说明这 N 家的申报名单里都有它，"
      + "不说明它们与这家冶炼厂之间有直接采购关系——冶炼厂在供应链的第三层，"
      + "申报的原义是「出现在本公司供应链中」。"
      + (splitNames.length
        ? "榜单上有 " + splitNames.length + " 个名字出现两次：同一家厂"
          + "一部分申报人给了 RMI 编号、一部分只给名字，登记表刻意不做同义合并"
          + "（宁可一家重复出现，不可两家被错并成一家），因此这几家的真实共同申报数"
          + "比任一行都高。"
        : "")
      + "整体上这个数只会少算不会多算。");
  }

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
    var cov = d.coverage || {};
    if (cov.poolForeignIssuer) {
      para("公司池：", "两个池。标普 500 成分股 " + cov.poolSp500 + " 家来自站内公司榜，"
        + "有市值与当日涨跌；在美上市的外国私人发行人 " + cov.poolForeignIssuer
        + " 家来自 SEC EDGAR（报 20-F／40-F 且同时报 Form SD 的那一批），"
        + "站内没有它们的报价——市值合计与环节涨跌都不含这批公司，"
        + "带 * 的市值即为此。收这一批而不是全部一千余家外国发行人，是因为报 "
        + "Form SD 才可能带来冶炼厂名单，也就是加进来同时带节点和边；"
        + "只增加孤立节点的扩池没有意义。"
        + "指数商的成分股名单（MSCI ACWI、S&P Global 1200）是专有数据，"
        + "再分发要授权，因此没有采用。");
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

  /* 公司页链到总览页时带 ?chain=<id>。认不出的 id 一律忽略，不硬选一条——
     宁可显示全池，也不要让读者以为自己看的是某条链。 */
  function chainFromUrl(d) {
    var m = /[?&]chain=([^&#]+)/.exec(location.search || "");
    if (!m) return null;
    var want = decodeURIComponent(m[1]);
    var rows = d.chains || [];
    for (var i = 0; i < rows.length; i++) if (rows[i].id === want) return want;
    return null;
  }

  function render(d) {
    state.data = d;
    state.chain = chainFromUrl(d);
    renderStatus(d);
    renderNotice(d);
    renderCoverageBySector(d);
    initLookup(d);
    renderStages(d);
    renderFlow(d);
    renderConcentration(d);
    renderExposure(d);
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
