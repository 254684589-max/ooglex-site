/* Financial Sankey page. Live SEC fetch is attempted; browsers are expected to
   fall back to the committed NVDA/MSFT extracts or a local companyfacts file. */
(function () {
  "use strict";

  var model = window.OoglexSankeyModel;
  var sankey = window.OoglexSankey;
  var SNAPSHOTS = { NVDA: "snapshots/nvda.json", MSFT: "snapshots/msft.json" };
  var TABS = ["income", "balance", "cashflow"];

  var state = {
    tickers: null,
    company: null,
    reports: null,
    mode: "",
    period: "annual",
    tab: "income",
    selected: ""
  };

  var els = {};

  document.addEventListener("DOMContentLoaded", function () {
    els.form = document.getElementById("lookup-form");
    els.ticker = document.getElementById("ticker");
    els.generate = document.getElementById("generate");
    els.banner = document.getElementById("banner");
    els.company = document.getElementById("company-line");
    els.meta = document.getElementById("meta-line");
    els.periodBar = document.getElementById("period-bar");
    els.tabs = document.getElementById("statement-tabs");
    els.panel = document.getElementById("statement-panel");
    els.chartScroll = document.getElementById("chart-scroll");
    els.svg = document.getElementById("chart");
    els.detail = document.getElementById("detail");
    els.notes = document.getElementById("statement-notes");
    els.table = document.getElementById("statement-table");
    els.file = document.getElementById("facts-file");
    els.secLink = document.getElementById("sec-link");
    els.factsLink = document.getElementById("facts-link");

    els.form.addEventListener("submit", function (event) {
      event.preventDefault();
      loadTicker(els.ticker.value);
    });
    els.file.addEventListener("change", function () {
      var file = els.file.files && els.file.files[0];
      if (file) readLocalFile(file);
    });
    els.periodBar.addEventListener("click", function (event) {
      var button = event.target.closest("button[data-period]");
      if (!button || button.disabled) return;
      state.period = button.getAttribute("data-period");
      state.selected = "";
      syncPeriodButtons();
      render();
      writeQuery();
    });
    els.tabs.addEventListener("click", function (event) {
      var button = event.target.closest("button[data-tab]");
      if (!button) return;
      state.tab = button.getAttribute("data-tab");
      state.selected = "";
      syncTabs();
      render();
      writeQuery();
    });
    els.tabs.addEventListener("keydown", function (event) {
      if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
      var buttons = Array.prototype.slice.call(els.tabs.querySelectorAll("button[data-tab]"));
      var index = buttons.indexOf(document.activeElement);
      if (index < 0) return;
      event.preventDefault();
      var next = index + (event.key === "ArrowRight" ? 1 : -1);
      if (next < 0) next = buttons.length - 1;
      if (next >= buttons.length) next = 0;
      buttons[next].focus();
      buttons[next].click();
    });
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        state.selected = "";
        sankey.clearHighlight(els.svg);
        renderDetail(null);
        highlightRows("");
      }
    });
    window.addEventListener("resize", debounce(function () {
      if (currentStatement() && currentStatement().nodes.length) drawCurrent();
    }, 150));

    var params = new URLSearchParams(window.location.search);
    var initial = params.get("ticker") || "NVDA";
    var period = params.get("period");
    var tab = params.get("tab");
    if (period === "quarterly" || period === "annual") state.period = period;
    if (TABS.indexOf(tab) >= 0) state.tab = tab;
    els.ticker.value = initial;
    loadTicker(initial);
  });

  function debounce(fn, wait) {
    var timer = 0;
    return function () {
      window.clearTimeout(timer);
      timer = window.setTimeout(fn, wait);
    };
  }

  function setBanner(kind, text) {
    els.banner.className = "banner " + kind;
    els.banner.textContent = text;
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

  async function loadTicker(raw) {
    els.generate.disabled = true;
    setBanner("loading", "正在查找 SEC 公司代码…");
    try {
      if (!state.tickers) state.tickers = await fetchJson("tickers.json");
      var resolved = resolveTicker(state.tickers, raw);
      if (resolved.error === "empty") {
        setBanner("error", "请输入美股代码，例如 NVDA 或 MSFT。");
        return;
      }
      if (resolved.error === "unknown") {
        setBanner("error", "未找到代码 " + resolved.ticker + "。请使用 SEC 公司代码表里的股票代码，例如 BRK-A。");
        els.company.textContent = "";
        els.meta.textContent = "";
        return;
      }
      els.ticker.value = resolved.ticker;
      state.company = resolved;
      showIdentity();
      setSecLinks(resolved.cik);
      setBanner("loading", "正在尝试从 SEC companyfacts 读取 " + resolved.ticker + "…");
      var live = await fetchLive(resolved.cik);
      if (live.ok) {
        applyFacts(live.data, "live", resolved);
        return;
      }
      var snapName = SNAPSHOTS[resolved.ticker];
      if (snapName) {
        setBanner("loading", "浏览器读不到 SEC，改用已核验的公开摘录…");
        var snap = await fetchJson(snapName);
        applyFacts(snap, "snapshot", resolved);
        return;
      }
      setBanner(
        "error",
        "已识别 " + resolved.name + "（CIK " + padCik(resolved.cik) + "），但浏览器不能读取 SEC companyfacts：接口没有开放跨域，网页也不能附上 SEC 要求的 User-Agent。本页只内置了 NVDA 和 MSFT 的摘录。可点「SEC companyfacts」在新页面打开 JSON，再选「打开本地 JSON」。文件只在你的浏览器里解析，不会上传。"
      );
      state.reports = null;
      render();
    } catch (error) {
      setBanner("error", "没有读到数据。" + (error && error.message ? " " + error.message : ""));
    } finally {
      els.generate.disabled = false;
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
      return { ok: false, error: error };
    } finally {
      window.clearTimeout(timer);
    }
  }

  function readLocalFile(file) {
    if (file.size > 30 * 1024 * 1024) {
      setBanner("error", "这个 JSON 超过 30MB，本页不解析。");
      return;
    }
    setBanner("loading", "正在读取本地 companyfacts…");
    var reader = new FileReader();
    reader.onload = function () {
      try {
        var data = JSON.parse(String(reader.result || ""));
        if (!data || typeof data !== "object" || !data.facts) {
          setBanner("error", "这份 JSON 不像 SEC companyfacts（缺少 facts）。");
          return;
        }
        var name = data.entityName ? String(data.entityName) : "本地 JSON";
        var cik = data.cik || (state.company && state.company.cik) || "";
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
      setBanner("error", "没有读到本地文件。");
    };
    reader.readAsText(file);
  }

  function applyFacts(data, mode, company) {
    if (!data.facts || !data.facts["us-gaap"]) {
      setBanner("error", "这份 XBRL 里没有 us-gaap 科目，画不出三张报表。");
      state.reports = null;
      render();
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
      setBanner("error", state.company.name + " 的 XBRL 里没有可用的 10-K / 20-F 年报或 10-Q 季报营业收入，无法定期间。");
      showIdentity();
      render();
      return;
    }
    if (state.period === "quarterly" && !state.reports.quarterly) state.period = "annual";
    if (state.period === "annual" && !state.reports.annual && state.reports.quarterly) state.period = "quarterly";
    state.selected = "";
    showIdentity();
    setSecLinks(state.company.cik);
    if (mode === "live") {
      setBanner("ok", "已直接读到 SEC companyfacts。数字是披露口径，不是行情。");
    } else if (mode === "file") {
      setBanner("ok", "已用你打开的本地 SEC JSON 绘图。文件没有上传。数字是披露口径，不是行情。");
    } else {
      var when = state.company.extract && state.company.extract.extractedAt ? state.company.extract.extractedAt : "";
      setBanner(
        "snapshot",
        "SEC 静态摘录，不是模拟数据。浏览器不能直接调用 data.sec.gov（没有 CORS，也不能设置 SEC 要求的 User-Agent）。" +
        state.company.ticker + " 的数字摘自公开 companyfacts" + (when ? "，摘录时间 " + when + " UTC" : "") +
        "。其他公司请打开 SEC JSON 后用「打开本地 JSON」。实时同源代理还没接。"
      );
    }
    writeQuery();
    syncPeriodButtons();
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
    var url = "?ticker=" + encodeURIComponent(state.company.ticker) + "&period=" + state.period + "&tab=" + state.tab;
    window.history.replaceState(null, "", url);
  }

  function currentReport() {
    if (!state.reports) return null;
    return state.reports[state.period] || null;
  }

  function currentStatement() {
    var report = currentReport();
    if (!report) return null;
    return report.statements[state.tab] || null;
  }

  function syncPeriodButtons() {
    els.periodBar.querySelectorAll("button[data-period]").forEach(function (button) {
      var key = button.getAttribute("data-period");
      var available = !!(state.reports && state.reports[key]);
      button.disabled = !available;
      button.setAttribute("aria-pressed", key === state.period ? "true" : "false");
    });
  }

  function syncTabs() {
    els.tabs.querySelectorAll("button[data-tab]").forEach(function (button) {
      var on = button.getAttribute("data-tab") === state.tab;
      button.setAttribute("aria-selected", on ? "true" : "false");
      button.tabIndex = on ? 0 : -1;
      if (on) els.panel.setAttribute("aria-labelledby", button.id);
    });
  }

  function render() {
    syncPeriodButtons();
    syncTabs();
    var report = currentReport();
    if (!report) {
      els.meta.textContent = state.company ? "这个期间没有可用报表。" : "";
      els.notes.textContent = "";
      els.detail.textContent = "选择图上的色带或下方表格中的一行，查看金额和 SEC 科目。";
      clearTable();
      clearChart("还没有可绘制的报表。");
      return;
    }
    var statement = currentStatement();
    var freq = report.frequency === "annual" ? "年报" : "季报";
    var fyLabel = report.fy ? ("FY" + report.fy + (report.fp && report.fp !== "FY" ? " " + report.fp : "")) : (report.fp || "");
    var bits = [
      freq,
      report.form,
      fyLabel,
      report.start + " 至 " + report.end,
      "申报 " + report.filed,
      "频率 " + (report.frequency === "annual" ? "annual" : "quarterly"),
      "状态 " + statusText(report.status)
    ];
    els.meta.textContent = bits.filter(Boolean).join(" · ");
    if (!statement) return;
    els.notes.textContent = "";
    els.notes.hidden = false;
    statement.notes.forEach(function (note) {
      var line = document.createElement("p");
      line.textContent = note;
      els.notes.appendChild(line);
    });
    if (statement.period && statement.period.start && statement.period.start !== report.start) {
      var extra = document.createElement("p");
      extra.textContent = "本图期间：" + statement.period.start + " 至 " + statement.period.end + " · " + (statement.period.form || "");
      els.notes.appendChild(extra);
    }
    els.notes.hidden = els.notes.childElementCount === 0;
    renderTable(statement);
    if (!statement.nodes.length) {
      clearChart(statement.notes[0] || "这张报表缺少关键科目，没有画出桑基图。");
      renderDetail(null);
      return;
    }
    drawCurrent();
    renderDetail(null);
  }

  function drawCurrent() {
    var statement = currentStatement();
    if (!statement || !statement.nodes.length) return;
    var width = Math.max(760, els.chartScroll.clientWidth || 760);
    var layout = sankey.layoutSankey(statement, width);
    sankey.drawSankey(els.svg, layout, {
      onSelect: function (id) {
        state.selected = id;
        sankey.highlight(els.svg, id);
        var node = statement.nodes.filter(function (item) { return item.id === id; })[0];
        renderDetail(node || null);
        highlightRows(node ? node.label : "");
      }
    });
    els.svg.setAttribute("aria-label", statement.title + "桑基图");
    if (state.selected) sankey.highlight(els.svg, state.selected);
    var empty = els.chartScroll.querySelector(".chart-empty");
    if (empty) empty.remove();
  }

  function clearChart(message) {
    while (els.svg.firstChild) els.svg.removeChild(els.svg.firstChild);
    els.svg.setAttribute("viewBox", "0 0 10 10");
    els.svg.setAttribute("width", "0");
    els.svg.setAttribute("height", "0");
    var note = els.chartScroll.querySelector(".chart-empty");
    if (!note) {
      note = document.createElement("p");
      note.className = "chart-empty";
      els.chartScroll.appendChild(note);
    }
    note.textContent = message;
  }

  function renderDetail(node) {
    els.detail.textContent = "";
    if (!node) {
      els.detail.textContent = "选择图上的色带或下方表格中的一行，查看金额和 SEC 科目。";
      return;
    }
    var title = document.createElement("strong");
    title.textContent = node.label;
    els.detail.appendChild(title);
    var amount = document.createElement("p");
    amount.textContent = formatUSD(node.signed == null ? node.value : node.signed) + "（" + formatExact(node.signed == null ? node.value : node.signed) + "）";
    els.detail.appendChild(amount);
    if (node.concept) {
      var concept = document.createElement("p");
      concept.textContent = "SEC 科目 " + node.concept + (node.en ? " · " + node.en : "");
      els.detail.appendChild(concept);
    }
    if (node.formula) {
      var formula = document.createElement("p");
      formula.textContent = "计算：" + node.formula;
      els.detail.appendChild(formula);
    }
    if (node.plug) {
      var plug = document.createElement("p");
      plug.textContent = "这是轧差，不是公司在报表上单列的科目。";
      els.detail.appendChild(plug);
    }
  }

  function renderTable(statement) {
    var body = els.table.querySelector("tbody");
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
      tr.addEventListener("click", function () { selectByLabel(item.label); });
      tr.addEventListener("keydown", function (event) {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          selectByLabel(item.label);
        }
      });
      body.appendChild(tr);
    });
    var caption = els.table.querySelector("caption");
    caption.textContent = statement.title + " · 单位：美元 · 状态 " + statusText(statement.status);
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

  function clearTable() {
    els.table.querySelector("tbody").textContent = "";
    els.table.querySelector("caption").textContent = "尚未加载报表";
  }

  function selectByLabel(label) {
    var statement = currentStatement();
    if (!statement) return;
    var node = statement.nodes.filter(function (item) { return item.label === label; })[0];
    if (!node) {
      highlightRows(label);
      renderDetail({ label: label, signed: statement.rows.filter(function (item) { return item.label === label; })[0].value });
      return;
    }
    state.selected = node.id;
    sankey.highlight(els.svg, node.id);
    renderDetail(node);
    highlightRows(label);
  }

  function highlightRows(label) {
    els.table.querySelectorAll("tbody tr").forEach(function (row) {
      row.classList.toggle("is-on", !!label && row.dataset.label === label);
    });
  }
})();
