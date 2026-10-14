/* 全球新闻扫描简报概览：只渲染同目录 data.json。外部文字一律 textContent。 */
(function () {
  "use strict";

  var dateline = document.getElementById("dateline");
  var edition = document.getElementById("edition");
  var lead = document.getElementById("lead");
  var note = document.getElementById("note");
  var banner = document.getElementById("banner");
  var tabs = document.getElementById("category-tabs");
  var toc = document.getElementById("toc");
  var itemsRoot = document.getElementById("items");
  var footMeta = document.getElementById("foot-meta");
  var activeCategory = "全部";
  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  var STATUS = {
    ok: "正常",
    partial: "部分缺失",
    stale: "已过期",
    error: "失败"
  };
  var FREQUENCY = {
    realtime: "实时",
    delayed: "延迟",
    daily: "日频",
    weekly: "周频",
    monthly: "月频",
    quarterly: "季频",
    annual: "年频"
  };

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  function clear(node) {
    while (node.firstChild) node.removeChild(node.firstChild);
  }

  function setBanner(kind, text) {
    banner.className = "banner" + (kind ? " " + kind : "");
    banner.textContent = text || "";
    banner.hidden = !text;
  }

  function safeHttps(url) {
    if (typeof url !== "string") return "";
    var value = url.trim();
    if (!/^https:\/\/[^\s<>"']+$/i.test(value)) return "";
    return value;
  }

  function textOrMissing(value) {
    if (typeof value === "string" && value.trim()) return value.trim();
    return "";
  }

  function formatStamp(value, zoneLabel) {
    if (typeof value !== "string" || !value.trim()) return "—";
    var date = new Date(value);
    if (isNaN(date.getTime())) return value;
    var pad = function (n) { return (n < 10 ? "0" : "") + n; };
    if (zoneLabel === "UTC") {
      return date.getUTCFullYear() + "-" + pad(date.getUTCMonth() + 1) + "-" + pad(date.getUTCDate())
        + " " + pad(date.getUTCHours()) + ":" + pad(date.getUTCMinutes()) + " UTC";
    }
    if (value.indexOf("+08:00") !== -1) {
      var match = value.match(/^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})/);
      if (match) return match[1] + " " + match[2] + "（UTC+8）";
    }
    return value;
  }

  function addChip(label, value) {
    var chip = el("span", "chip");
    chip.appendChild(el("strong", "", label));
    chip.appendChild(document.createTextNode(" " + value));
    edition.appendChild(chip);
  }

  function paragraphs(parent, value) {
    var raw = textOrMissing(value);
    if (!raw) {
      parent.appendChild(el("p", "missing", "（本段未提供）"));
      return;
    }
    raw.split(/\n{2,}/).forEach(function (part) {
      var line = part.trim();
      if (line) parent.appendChild(el("p", "", line));
    });
  }

  function renderTable(table) {
    var wrap = el("div", "table-wrap");
    var grid = document.createElement("table");
    var caption = document.createElement("caption");
    caption.textContent = "关键数据一览。原文没有的对比格为「—」。单位与口径见各行备注，不是实时行情。";
    grid.appendChild(caption);
    var columns = Array.isArray(table.columns) ? table.columns : [];
    var head = document.createElement("thead");
    var headRow = document.createElement("tr");
    columns.forEach(function (column) {
      var th = document.createElement("th");
      th.scope = "col";
      th.textContent = column == null || column === "" ? "—" : String(column);
      headRow.appendChild(th);
    });
    head.appendChild(headRow);
    grid.appendChild(head);
    var body = document.createElement("tbody");
    (Array.isArray(table.rows) ? table.rows : []).forEach(function (row) {
      var tr = document.createElement("tr");
      var cells = Array.isArray(row) ? row : [];
      columns.forEach(function (_, index) {
        var cell = document.createElement(index === 0 ? "th" : "td");
        if (index === 0) cell.scope = "row";
        var value = cells[index];
        cell.textContent = value == null || value === "" ? "—" : String(value);
        tr.appendChild(cell);
      });
      body.appendChild(tr);
    });
    grid.appendChild(body);
    wrap.appendChild(grid);
    return wrap;
  }

  function renderImpact(impact) {
    var section = el("section", "section impact");
    section.appendChild(el("h3", "", "对市场可能产生的影响"));
    var data = impact && typeof impact === "object" ? impact : null;
    if (!data) {
      section.appendChild(el("p", "missing", "（本段未提供）"));
      return section;
    }
    var bullets = Array.isArray(data.bullets) ? data.bullets.filter(function (line) {
      return typeof line === "string" && line.trim();
    }) : [];
    if (!data.hasImpact) {
      section.appendChild(el("p", "impact-none", bullets.length ? bullets.join(" ") : "无"));
      return section;
    }
    if (!bullets.length) {
      section.appendChild(el("p", "missing", "（已标记可能有影响，但未提供要点）"));
      return section;
    }
    var list = document.createElement("ul");
    bullets.forEach(function (line) {
      list.appendChild(el("li", "", line));
    });
    section.appendChild(list);
    return section;
  }

  function renderSources(sources) {
    var section = el("section", "section");
    section.appendChild(el("h3", "", "可核查来源"));
    if (!Array.isArray(sources) || !sources.length) {
      section.appendChild(el("p", "missing", "（未提供来源）"));
      return section;
    }
    var list = el("ul", "sources");
    sources.forEach(function (source) {
      var item = document.createElement("li");
      var label = source && textOrMissing(source.label);
      var href = safeHttps(source && source.url);
      if (href) {
        var link = document.createElement("a");
        link.href = href;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        link.textContent = label || href;
        item.appendChild(link);
      } else {
        item.textContent = label || "（来源未提供可打开链接）";
      }
      list.appendChild(item);
    });
    section.appendChild(list);
    return section;
  }

  function renderItem(item, index) {
    var article = el("article", "item");
    article.id = "item-" + (item.id || String(index + 1));
    article.setAttribute("data-category", item.category || "未分类");
    var panelId = article.id + "-panel";
    var toggle = document.createElement("button");
    toggle.type = "button";
    toggle.className = "item-toggle";
    toggle.setAttribute("aria-expanded", "false");
    toggle.setAttribute("aria-controls", panelId);

    var kicker = el("span", "item-kicker");
    kicker.appendChild(el("span", "", item.id ? String(item.id) : String(index + 1)));
    kicker.appendChild(el("span", "", "·"));
    kicker.appendChild(el("span", "", item.category || "未分类"));
    var verification = textOrMissing(item.verification) || "未标注";
    var badgeClass = "badge" + (verification === "通过" ? " pass" : verification === "有条件通过" ? " cond" : "");
    kicker.appendChild(el("span", badgeClass, "核验：" + verification));
    if (item.candidate) kicker.appendChild(el("span", "", "候选 " + item.candidate));
    toggle.appendChild(kicker);
    toggle.appendChild(el("span", "item-title", item.title || "（无标题）"));
    article.appendChild(toggle);

    var panel = el("div", "item-panel");
    panel.id = panelId;
    panel.hidden = true;
    var sections = item.sections && typeof item.sections === "object" ? item.sections : {};

    if (item.rubric) panel.appendChild(el("p", "note", "栏目：" + item.rubric + (item.audience ? " · 稿件标注：" + item.audience : "")));

    function block(title, value) {
      var section = el("section", "section");
      section.appendChild(el("h3", "", title));
      paragraphs(section, value);
      return section;
    }

    panel.appendChild(block("发生了什么", sections.whatHappened));

    var dataSection = el("section", "section");
    dataSection.appendChild(el("h3", "", "关键数据一览"));
    if (sections.dataTable && Array.isArray(sections.dataTable.columns) && sections.dataTable.columns.length) {
      dataSection.appendChild(renderTable(sections.dataTable));
      if (sections.dataTable.note) dataSection.appendChild(el("p", "table-note", sections.dataTable.note));
    } else {
      dataSection.appendChild(el("p", "", textOrMissing(sections.dataNote) || "本条无关键量化指标。"));
    }
    panel.appendChild(dataSection);
    panel.appendChild(block("起因与背景", sections.background));
    panel.appendChild(block("目前进展", sections.progress));
    panel.appendChild(block("重要性", sections.importance));
    panel.appendChild(renderImpact(sections.marketImpact));
    panel.appendChild(renderSources(sections.sources));
    article.appendChild(panel);

    toggle.addEventListener("click", function () {
      var open = panel.hidden;
      panel.hidden = !open;
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    return article;
  }

  function applyFilter() {
    [toc, itemsRoot].forEach(function (root) {
      Array.prototype.forEach.call(root.querySelectorAll("[data-category]"), function (node) {
        var category = node.getAttribute("data-category");
        node.hidden = activeCategory !== "全部" && category !== activeCategory;
      });
    });
  }

  function renderDirectory(list) {
    clear(toc);
    var groups = [];
    var seen = {};
    list.forEach(function (item) {
      var category = item.category || "未分类";
      if (!seen[category]) {
        seen[category] = [];
        groups.push(category);
      }
      seen[category].push(item);
    });
    groups.forEach(function (category) {
      var group = el("section", "toc-group");
      group.setAttribute("data-category", category);
      group.appendChild(el("h2", "", category));
      var ol = el("ol", "toc-list");
      seen[category].forEach(function (item) {
        var li = document.createElement("li");
        var button = document.createElement("button");
        button.type = "button";
        button.appendChild(el("span", "toc-no", item.id || ""));
        button.appendChild(document.createTextNode(item.title || "（无标题）"));
        button.addEventListener("click", function () {
          var article = document.getElementById("item-" + item.id);
          if (!article) return;
          var toggle = article.querySelector(".item-toggle");
          var panel = article.querySelector(".item-panel");
          if (panel && toggle) {
            panel.hidden = false;
            toggle.setAttribute("aria-expanded", "true");
          }
          article.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" });
          if (toggle) toggle.focus();
        });
        li.appendChild(button);
        ol.appendChild(li);
      });
      group.appendChild(ol);
      toc.appendChild(group);
    });
  }

  function renderTabs(categories) {
    clear(tabs);
    ["全部"].concat(categories).forEach(function (category) {
      var button = document.createElement("button");
      button.type = "button";
      button.textContent = category;
      button.setAttribute("aria-pressed", category === activeCategory ? "true" : "false");
      button.addEventListener("click", function () {
        activeCategory = category;
        Array.prototype.forEach.call(tabs.querySelectorAll("button"), function (node) {
          node.setAttribute("aria-pressed", node.textContent === category ? "true" : "false");
        });
        applyFilter();
      });
      tabs.appendChild(button);
    });
  }

  function showFailure(message) {
    lead.textContent = "本期简报没有载入。";
    note.textContent = "";
    clear(edition);
    clear(toc);
    clear(itemsRoot);
    clear(tabs);
    dateline.textContent = "来源与更新时间暂时不可用";
    setBanner("error", message);
  }

  function render(data) {
    if (!data || typeof data !== "object" || !Array.isArray(data.items)) {
      showFailure("简报数据格式不完整，已停止展示，避免把缺字段当成空行情。");
      return;
    }
    var list = data.items;
    var status = textOrMissing(data.status) || "未标注";
    dateline.textContent = "来源：" + (textOrMissing(data.source) || "未标注")
      + " · 数据时点：" + formatStamp(data.asOf, "local")
      + " · 更新时间：" + formatStamp(data.updatedAt, "UTC")
      + " · 频率：" + (FREQUENCY[data.frequency] || data.frequency || "未标注") + " · 人工编辑（非实时）"
      + " · 状态：" + (STATUS[status] || status);

    clear(edition);
    if (data.edition) addChip("期次", data.edition);
    if (data.version) addChip("版本", data.version);
    if (data.window) addChip("观察窗", data.window);
    var passed = list.filter(function (item) { return item && item.verification === "通过"; }).length;
    var conditional = list.filter(function (item) { return item && item.verification === "有条件通过"; }).length;
    addChip("条目", list.length + " · 通过 " + passed + " · 有条件通过 " + conditional);

    lead.textContent = textOrMissing(data.lead) || "（本期未提供导语）";
    note.textContent = textOrMissing(data.note);

    var categories = Array.isArray(data.categories) && data.categories.length
      ? data.categories.filter(function (category) { return typeof category === "string" && category; })
      : [];
    if (!categories.length) {
      list.forEach(function (item) {
        var category = item && item.category;
        if (category && categories.indexOf(category) === -1) categories.push(category);
      });
    }
    renderTabs(categories);
    renderDirectory(list);
    clear(itemsRoot);
    var missingImpact = 0;
    list.forEach(function (item, index) {
      if (!item || !item.sections || !item.sections.marketImpact) missingImpact += 1;
      itemsRoot.appendChild(renderItem(item || {}, index));
    });

    if (data.demo === true) {
      setBanner("demo", "模拟数据。此页数字不是当前真实行情。");
    } else if (!list.length) {
      setBanner("empty", "本期暂无条目。");
    } else if (status === "error") {
      setBanner("error", "来源状态为失败。下面仍保留文件中的上一份内容，请勿当作最新成功更新。");
    } else if (status === "stale") {
      setBanner("stale", "这份简报已过期。下面仍展示文件中的有效内容，并标明原数据时点。");
    } else if (status === "partial" || missingImpact) {
      setBanner("partial", missingImpact
        ? "部分条目缺少「对市场可能产生的影响」，相关位置会标明未提供。"
        : "数据状态为部分缺失，请对照各条里的空段。");
    } else {
      setBanner("", "");
    }

    footMeta.textContent = (data.edition || "简报")
      + (data.version ? " · " + data.version : "")
      + " · 来源 " + (data.source || "环球新闻情报中心")
      + " · 更新 " + formatStamp(data.updatedAt, "UTC");
    applyFilter();

    if (/^#item-[A-Za-z0-9_-]+$/.test(location.hash)) {
      var target = document.getElementById(location.hash.slice(1));
      if (target && target.classList && target.classList.contains("item")) {
        var toggle = target.querySelector(".item-toggle");
        var panel = target.querySelector(".item-panel");
        if (toggle && panel) {
          panel.hidden = false;
          toggle.setAttribute("aria-expanded", "true");
        }
      }
    } else if (list.length) {
      var firstPanel = itemsRoot.querySelector(".item-panel");
      var firstToggle = itemsRoot.querySelector(".item-toggle");
      if (firstPanel && firstToggle) {
        firstPanel.hidden = false;
        firstToggle.setAttribute("aria-expanded", "true");
      }
    }
  }

  fetch("data.json", { cache: "no-store" })
    .then(function (response) {
      if (!response.ok) throw new Error("status " + response.status);
      return response.json();
    })
    .then(render)
    .catch(function () {
      showFailure("简报暂时无法加载。请稍后重试。自动抓取要闻仍可从「最新消息」查看。");
    });
})();
