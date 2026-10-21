/* Financial Sankey page. Live SEC fetch is attempted; browsers are expected to
   fall back to the committed NVDA/MSFT extracts or a local companyfacts file. */
(function () {
  "use strict";

  var model = window.OoglexSankeyModel;
  var sankey = window.OoglexSankey;
  var SNAPSHOTS = { NVDA: "snapshots/nvda.json", MSFT: "snapshots/msft.json" };
  var SECTIONS = ["income", "balance", "cashflow"];

  var state = {
    tickers: null,
    company: null,
    reports: null,
    mode: "",
    period: "annual",
    selected: {}
  };
  var busy = false;
  var els = {};

  document.addEventListener("DOMContentLoaded", function () {
    els.form = document.getElementById("lookup-form");
    els.ticker = document.getElementById("ticker");
    els.generate = document.getElementById("generate");
    els.retry = document.getElementById("retry");
    els.banner = document.getElementById("banner");
    els.results = document.getElementById("results");
    els.company = document.getElementById("company-line");
    els.source = document.getElementById("source-line");
    els.meta = document.getElementById("meta-line");
    els.periodBar = document.getElementById("period-bar");
    els.tabs = document.getElementById("statement-tabs");
    els.file = document.getElementById("facts-file");
    els.secLink = document.getElementById("sec-link");
    els.factsLink = document.getElementById("facts-link");

    els.form.addEventListener("submit", function (event) {
      event.preventDefault();
      loadTicker(els.ticker.value);
    });
    els.retry.addEventListener("click", function () {
      loadTicker(els.ticker.value);
    });
    els.file.addEventListener("change", function () {
      var file = els.file.files && els.file.files[0];
      if (file) readLocalFile(file);
    });
    els.periodBar.addEventListener("click", function (event) {
      var button = event.target.closest("button[data-period]");
      if (!button || button.disabled || busy) return;
      state.period = button.getAttribute("data-period");
      state.selected = {};
      syncPeriodButtons();
      render();
      writeQuery();
    });
    els.tabs.addEventListener("click", function () {
      window.setTimeout(syncNav, 0);
    });
    window.addEventListener("hashchange", syncNav);
    document.addEventListener("keydown", function (event) {
      if (event.key !== "Escape") return;
      state.selected = {};
      SECTIONS.forEach(function (id) {
        var section = sectionEl(id);
        sankey.clearHighlight(section.querySelector("svg"));
        renderDetail(section, null);
        highlightRows(section, "");
      });
    });
    window.addEventListener("resize", debounce(function () {
      if (!state.reports || els.results.hidden) return;
      SECTIONS.forEach(function (id) {
        drawSection(sectionEl(id), statementOf(id));
      });
    }, 150));

    var params = new URLSearchParams(window.location.search);
    var initial = params.get("ticker");
    var period = params.get("period");
    if (period === "quarterly" || period === "annual") state.period = period;
    if (initial && normalizeTicker(initial)) {
      els.ticker.value = normalizeTicker(initial);
      loadTicker(initial);
    }
  });

  function debounce(fn, wait) {
    var timer = 0;
    return function () {
      window.clearTimeout(timer);
      timer = window.setTimeout(fn, wait);
    };
  }

  function sectionEl(id) {
    return document.getElementById("panel-" + id);
  }

  function setBanner(kind, text) {
    els.banner.className = "banner " + kind;
    els.banner.textContent = text;
  }

  function setBusy(on) {
    els.banner.setAttribute("aria-busy", on ? "true" : "false");
    els.generate.disabled = !!on;
    els.retry.disabled = !!on;
  }

  function showRetry(on) {
    els.retry.hidden = !on;
  }

  function hideResults() {
    state.reports = null;
    state.company = null;
    state.mode = "";
    state.selected = {};
    els.results.hidden = true;
    els.company.textContent = "";
    els.source.textContent = "";
    els.meta.textContent = "";
  }

  function padCik(value) {
    return String(value == null ? "" : value).replace(/\D/g, "").padStart(10, "0");
  }

  function normalizeTicker(value) {
    return String(value || "").trim().toUpperCase().replace(/\s+/g, "");
  }

  function formatUSD(value) {
    if (value == null || !isFinite(value)) return "—";
    var sign = value < 0 ? "−" : "";
    var abs = Math.abs(value);
    if (abs >= 1e8) {
      return sign + (abs / 1e8).toLocaleString("zh-CN", { minimumFractionDigits: 1, maximumFractionDigits: 1 }) + " 亿美元";
    }
    if (abs >= 1e4) {
      return sign + Math.round(abs / 1e4).toLocaleString("zh-CN") + " 万美元";
    }
    return sign + Math.round(abs).toLocaleString("zh-CN") + " 美元";
  }

  function formatExact(value) {
    if (value == null || !isFinite(value)) return "—";
    var sign = value < 0 ? "−" : "";
    return sign + Math.abs(Math.round(value)).toLocaleString("zh-CN") + " 美元";
  }

  function statusText(status) {
    if (status === "ok") return "正常";
    if (status === "partial") return "部分科目";
    if (status === "error") return "无法绘制";
    return status || "—";
  }

  function frequencyText(frequency) {
    return frequency === "annual" ? "年度" : "季度";
  }

  async function loadTicker(raw) {
    if (busy) return;
    var ticker = normalizeTicker(raw);
    if (!ticker) {
      hideResults();
      setBanner("error", "请输入美股代码，例如 NVDA 或 MSFT。");
      showRetry(false);
      return;
    }
    busy = true;
    setBusy(true);
    showRetry(false);
    els.results.hidden = true;
    setBanner("loading", "正在查找代码…");
    try {
      if (!state.tickers) state.tickers = await fetchJson("tickers.json");
      var resolved = resolveTicker(state.tickers, ticker);
      if (resolved.error === "unknown") {
        hideResults();
        setBanner("error", "未找到代码 " + resolved.ticker + "。请核对美股代码，例如 NVDA 或 MSFT。");
        showRetry(false);
        return;
      }
      els.ticker.value = resolved.ticker;
      setSecLinks(resolved.cik);
      setBanner("loading", "正在从 SEC 读取报表…");
      var live = await fetchLive(resolved.cik);
      if (live.ok) {
        applyFacts(live.data, "live", resolved);
        return;
      }
      var snapName = SNAPSHOTS[resolved.ticker];
      if (snapName) {
        setBanner("loading", "正在加载内置摘录…");
        var snap = await fetchJson(snapName);
        applyFacts(snap, "snapshot", resolved);
        return;
      }
      hideResults();
      setBanner(
        "error",
        "已识别 " + resolved.name + "（CIK " + padCik(resolved.cik) + "），但没有从 SEC 读到报表。请稍后再点「重试」，或用「打开本地 JSON」打开从 SEC companyfacts 下载的文件。文件只在本机解析，不会上传。"
      );
      showRetry(true);
    } catch (error) {
      hideResults();
      setBanner("error", "网络或 SEC 暂时没有响应。请稍后再点「重试」。");
      showRetry(true);
    } finally {
      busy = false;
      setBusy(false);
    }
  }

  function resolveTicker(map, raw) {
    var ticker = normalizeTicker(raw);
    if (!ticker) return { error: "empty" };
    if (/^\d{1,10}$/.test(ticker)) {
      var cik = parseInt(ticker, 10);
      var match = null;
      Object.keys(map).some(function (key) {
        if (map[key][0] === cik) {
          match = { ticker: key, cik: cik, name: map[key][1] };
          return true;
        }
        return false;
      });
      return match || { ticker: padCik(cik), cik: cik, name: "CIK " + padCik(cik) };
    }
    if (map[ticker]) return { ticker: ticker, cik: map[ticker][0], name: map[ticker][1] };
    var dashed = ticker.replace(/\./g, "-");
    if (map[dashed]) return { ticker: dashed, cik: map[dashed][0], name: map[dashed][1] };
    return { error: "unknown", ticker: ticker };
  }

  async function fetchJson(url) {
    var response = await fetch(url, { headers: { Accept: "application/json" } });
    if (!response.ok) throw new Error("HTTP " + response.status);
    return response.json();
  }

  async function fetchLive(cik) {
    var url = "https://data.sec.gov/api/xbrl/companyfacts/CIK" + padCik(cik) + ".json";
    var controller = new AbortController();
    var timer = window.setTimeout(function () { controller.abort(); }, 8000);
    try {
      var response = await fetch(url, {
        signal: controller.signal,
        headers: { Accept: "application/json" },
        referrerPolicy: "origin"
      });
      if (!response.ok) return { ok: false, status: response.status };
      return { ok: true, data: await response.json() };
    } catch (error) {
      return { ok: false };
    } finally {
      window.clearTimeout(timer);
    }
  }

  function readLocalFile(file) {
    if (file.size > 30 * 1024 * 1024) {
      setBanner("error", "这个 JSON 超过 30MB，本页不解析。");
      showRetry(false);
      return;
    }
    setBanner("loading", "正在读取本地 companyfacts…");
    setBusy(true);
    var reader = new FileReader();
    reader.onload = function () {
      setBusy(false);
      try {
        var data = JSON.parse(String(reader.result || ""));
        if (!data || typeof data !== "object" || !data.facts) {
          setBanner("error", "这份 JSON 不像 SEC companyfacts（缺少 facts）。");
          return;
        }
        var name = data.entityName ? String(data.entityName) : "本地 JSON";
        var cik = data.cik || "";
        applyFacts(data, "file", {
          ticker: els.ticker.value ? normalizeTicker(els.ticker.value) : "LOCAL",
          name: name,
          cik: cik
        });
      } catch (error) {
        setBanner("error", "JSON 无法解析。请选择从 SEC 下载的 companyfacts 文件。");
      }
    };
    reader.onerror = function () {
      setBusy(false);
      setBanner("error", "没有读到本地文件。请再选一次。");
    };
    reader.readAsText(file);
  }

  function applyFacts(data, mode, company) {
    if (!data.facts || !data.facts["us-gaap"]) {
      hideResults();
      setBanner("error", "这份 XBRL 里没有 us-gaap 科目，画不出三张报表。可点「重试」。");
      showRetry(mode !== "file");
      return;
    }
    state.mode = mode;
    state.company = {
      ticker: company.ticker,
      name: data.entityName ? String(data.entityName) : company.name,
      cik: data.cik || company.cik,
      extract: data.extract || null,
      sourceUrl: (data.extract && data.extract.sourceUrl) || ("https://data.sec.gov/api/xbrl/companyfacts/CIK" + padCik(data.cik || company.cik) + ".json")
    };
    state.reports = model.buildReports(data);
    if (!state.reports.annual && !state.reports.quarterly) {
      hideResults();
      setBanner("error", (data.entityName ? String(data.entityName) : company.name) + " 的 XBRL 里没有可用的年报或季报营业收入，无法确定报告期。");
      showRetry(mode !== "file");
      return;
    }
    if (state.period === "quarterly" && !state.reports.quarterly) state.period = "annual";
    if (state.period === "annual" && !state.reports.annual && state.reports.quarterly) state.period = "quarterly";
    state.selected = {};
    setSecLinks(state.company.cik);
    if (mode === "live") {
      setBanner("ok", "已直接读到 SEC companyfacts。数字是披露口径，不是行情。");
      showRetry(false);
    } else if (mode === "file") {
      setBanner("ok", "已用你打开的本地 SEC JSON 绘图。文件没有上传。数字是披露口径，不是行情。");
      showRetry(false);
    } else {
      var when = state.company.extract && state.company.extract.extractedAt ? state.company.extract.extractedAt : "";
      setBanner(
        "snapshot",
        "没有从 SEC 直接读到最新文件（浏览器跨域限制）。已改用本站保存的公开摘录，数值来自 SEC companyfacts。" +
        (when ? "摘录时间 " + when + " UTC。" : "") +
        "可点「重试」再试一次。"
      );
      showRetry(true);
    }
    writeQuery();
    render();
  }

  function showIdentity() {
    var company = state.company;
    if (!company) return;
    els.company.textContent = company.name + " · " + company.ticker + " · CIK " + padCik(company.cik);
  }

  function setSecLinks(cik) {
    var padded = padCik(cik);
    els.secLink.href = "https://www.sec.gov/edgar/browse/?CIK=" + padded;
    els.factsLink.href = "https://data.sec.gov/api/xbrl/companyfacts/CIK" + padded + ".json";
  }

  function writeQuery() {
    if (!state.company || !state.company.ticker || state.mode === "file") return;
    var url = "?ticker=" + encodeURIComponent(state.company.ticker) + "&period=" + state.period;
    if (window.location.hash) url += window.location.hash;
    window.history.replaceState(null, "", url);
  }

  function currentReport() {
    if (!state.reports) return null;
    return state.reports[state.period] || null;
  }

  function statementOf(id) {
    var report = currentReport();
    if (!report || !report.statements) return null;
    return report.statements[id] || null;
  }

  function syncPeriodButtons() {
    els.periodBar.querySelectorAll("button[data-period]").forEach(function (button) {
      var key = button.getAttribute("data-period");
      var available = !!(state.reports && state.reports[key]);
      button.disabled = !available;
      button.setAttribute("aria-pressed", key === state.period ? "true" : "false");
    });
  }

  function syncNav() {
    var hash = window.location.hash;
    els.tabs.querySelectorAll("a").forEach(function (link) {
      if (link.getAttribute("href") === hash) link.setAttribute("aria-current", "true");
      else link.removeAttribute("aria-current");
    });
  }

  function render() {
    syncPeriodButtons();
    syncNav();
    var report = currentReport();
    if (!report) {
      els.results.hidden = true;
      return;
    }
    els.results.hidden = false;
    showIdentity();
    els.source.textContent = "来源：SEC EDGAR companyfacts（公开 XBRL，US-GAAP） · 报告期：" +
      report.start + " 至 " + report.end + " · " + (report.form || "") + " · " + frequencyText(report.frequency);
    var freq = report.frequency === "annual" ? "年报" : "季报";
    var fyLabel = report.fy ? ("FY" + report.fy + (report.fp && report.fp !== "FY" ? " " + report.fp : "")) : (report.fp || "");
    els.meta.textContent = [
      freq,
      report.form,
      fyLabel,
      report.start + " 至 " + report.end,
      "申报 " + report.filed,
      "频率 " + frequencyText(report.frequency),
      "状态 " + statusText(report.status)
    ].filter(Boolean).join(" · ");
    SECTIONS.forEach(function (id) {
      renderSection(sectionEl(id), statementOf(id), report);
    });
  }

  function renderSection(section, statement, report) {
    var notes = section.querySelector(".notes");
    notes.textContent = "";
    if (!statement) {
      clearChart(section, "这张报表缺少关键科目，没有画出桑基图。");
      renderDetail(section, null);
      clearTable(section, "尚未加载报表");
      return;
    }
    statement.notes.forEach(function (note) {
      var line = document.createElement("p");
      line.textContent = note;
      notes.appendChild(line);
    });
    if (statement.period && statement.period.start && statement.period.start !== report.start) {
      var extra = document.createElement("p");
      extra.textContent = "本图期间：" + statement.period.start + " 至 " + statement.period.end + " · " + (statement.period.form || "") + "。季报现金流量经常是年初至今，不能和单季利润直接比较。";
      notes.appendChild(extra);
    }
    notes.hidden = notes.childElementCount === 0;
    renderTable(section, statement);
    renderDetail(section, null);
    if (!statement.nodes.length) {
      clearChart(section, statement.notes[0] || "这张报表缺少关键科目，没有画出桑基图。");
      return;
    }
    drawSection(section, statement);
  }

  function drawSection(section, statement) {
    if (!section || !statement || !statement.nodes.length) return;
    var scroll = section.querySelector(".chart-scroll");
    var svg = section.querySelector("svg");
    var empty = section.querySelector(".chart-empty");
    var width = Math.max(760, scroll.clientWidth || 760);
    var layout = sankey.layoutSankey(statement, width);
    sankey.drawSankey(svg, layout, {
      onSelect: function (id) {
        state.selected[section.getAttribute("data-statement")] = id;
        sankey.highlight(svg, id);
        var node = statement.nodes.filter(function (item) { return item.id === id; })[0];
        renderDetail(section, node || null);
        highlightRows(section, node ? node.label : "");
      }
    });
    svg.hidden = false;
    if (empty) empty.hidden = true;
    var picked = state.selected[section.getAttribute("data-statement")];
    if (picked) sankey.highlight(svg, picked);
  }

  function clearChart(section, message) {
    var svg = section.querySelector("svg");
    var empty = section.querySelector(".chart-empty");
    while (svg.firstChild) svg.removeChild(svg.firstChild);
    svg.setAttribute("viewBox", "0 0 10 10");
    svg.setAttribute("width", "0");
    svg.setAttribute("height", "0");
    svg.hidden = true;
    empty.hidden = false;
    empty.textContent = message;
  }

  function renderDetail(section, node) {
    var detail = section.querySelector(".detail");
    detail.textContent = "";
    if (!node) {
      detail.textContent = "选择图上的色带或下方表格中的一行，查看金额和 SEC 科目。";
      return;
    }
    var title = document.createElement("strong");
    title.textContent = node.label;
    detail.appendChild(title);
    var amount = document.createElement("p");
    var signed = node.signed == null ? node.value : node.signed;
    amount.textContent = formatUSD(signed) + "（" + formatExact(signed) + "）";
    detail.appendChild(amount);
    if (node.concept) {
      var concept = document.createElement("p");
      concept.textContent = "SEC 科目 " + node.concept + (node.en ? " · " + node.en : "");
      detail.appendChild(concept);
    }
    if (node.formula) {
      var formula = document.createElement("p");
      formula.textContent = "计算：" + node.formula;
      detail.appendChild(formula);
    }
    if (node.plug) {
      var plug = document.createElement("p");
      plug.textContent = "这是轧差，不是公司在报表上单列的科目。";
      detail.appendChild(plug);
    }
  }

  function renderTable(section, statement) {
    var table = section.querySelector("table");
    var body = table.querySelector("tbody");
    body.textContent = "";
    statement.rows.forEach(function (item) {
      var tr = document.createElement("tr");
      tr.tabIndex = 0;
      tr.dataset.label = item.label;
      if (item.role === "plug") tr.classList.add("is-plug");
      appendCell(tr, item.label);
      appendCell(tr, item.en || "—");
      appendCell(tr, item.concept || (item.role === "plug" ? "轧差" : "—"));
      appendCell(tr, formatExact(item.value));
      appendCell(tr, item.formula || roleText(item.role));
      tr.addEventListener("click", function () { selectByLabel(section, item.label); });
      tr.addEventListener("keydown", function (event) {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          selectByLabel(section, item.label);
        }
      });
      body.appendChild(tr);
    });
    table.querySelector("caption").textContent = statement.title + " · 单位：美元 · 状态 " + statusText(statement.status);
  }

  function appendCell(tr, text) {
    var td = document.createElement("td");
    td.textContent = text;
    tr.appendChild(td);
  }

  function roleText(role) {
    if (role === "plug") return "轧差";
    if (role === "subtotal") return "小计";
    return "SEC 原值";
  }

  function clearTable(section, caption) {
    var table = section.querySelector("table");
    table.querySelector("tbody").textContent = "";
    table.querySelector("caption").textContent = caption;
  }

  function selectByLabel(section, label) {
    var statement = statementOf(section.getAttribute("data-statement"));
    if (!statement) return;
    var node = statement.nodes.filter(function (item) { return item.label === label; })[0];
    var svg = section.querySelector("svg");
    if (!node) {
      highlightRows(section, label);
      var row = statement.rows.filter(function (item) { return item.label === label; })[0];
      renderDetail(section, row ? { label: label, signed: row.value, concept: row.concept, en: row.en, formula: row.formula, plug: row.role === "plug" } : null);
      return;
    }
    state.selected[section.getAttribute("data-statement")] = node.id;
    sankey.highlight(svg, node.id);
    renderDetail(section, node);
    highlightRows(section, label);
  }

  function highlightRows(section, label) {
    section.querySelectorAll("tbody tr").forEach(function (row) {
      row.classList.toggle("is-on", !!label && row.dataset.label === label);
    });
  }
})();
