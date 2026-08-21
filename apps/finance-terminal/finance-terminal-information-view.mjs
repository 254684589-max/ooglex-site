function requireDependency(dependencies, name) {
  const value = dependencies && dependencies[name];
  if (value === undefined || value === null) {
    throw new Error(`事件资讯视图缺少依赖：${name}`);
  }
  return value;
}

export function createInformationView(dependencies = {}) {
  const document = requireDependency(dependencies, "document");
  const grid = requireDependency(dependencies, "grid");
  const summary = requireDependency(dependencies, "summary");
  const appendText = requireDependency(dependencies, "appendText");
  const formatDate = requireDependency(dependencies, "formatDate");
  const appendSource = requireDependency(dependencies, "appendSource");
  const formatTimestamp = requireDependency(dependencies, "formatTimestamp");
  const isSafeHref = requireDependency(dependencies, "isSafeHref");
  const appendSupportingHealth = requireDependency(dependencies, "appendSupportingHealth");

  function informationStatusLabel(card) {
    if (card.status === "stale") return { className: "stale-chip", text: "STALE" };
    if (card.status === "error") return { className: "error-chip", text: "ERROR" };
    if (card.status === "partial") return { className: "partial-chip", text: "PARTIAL" };
    return { className: "official-chip", text: "ACTIVE" };
  }

  function appendInformationFooter(card, parent) {
    const meta = document.createElement("div");
    meta.className = "information-meta";
    appendText(meta, "span", "", "数据日 · " + formatDate(card.asOf, false));
    appendText(meta, "span", "", card.frequency || "频率未提供");
    parent.appendChild(meta);

    const footer = document.createElement("div");
    footer.className = "information-footer";
    const sourceBox = document.createElement("div");
    sourceBox.className = "information-source";
    appendSource(sourceBox, card);
    footer.appendChild(sourceBox);
    const time = appendText(footer, "time", "", "更新 · " + formatTimestamp(card.updatedAt, false));
    if (card.updatedAt) time.dateTime = card.updatedAt;
    const chip = informationStatusLabel(card);
    appendText(footer, "span", "status-chip " + chip.className, chip.text);
    if (isSafeHref(card.detailUrl)) {
      const detail = appendText(footer, "a", "detail-link", "查看完整页面 →");
      detail.href = card.detailUrl;
    }
    parent.appendChild(footer);
  }

  function formatEventTime(value) {
    const time = new Date(value);
    if (Number.isNaN(time.getTime())) return "时间不可用";
    return new Intl.DateTimeFormat("zh-CN", {
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false
    }).format(time) + " 本地";
  }

  function eventImpactLabel(value) {
    if (value === "high") return "高影响";
    if (value === "medium") return "中影响";
    if (value === "holiday") return "假日";
    return "低影响";
  }

  function makeEconomicCalendarCard(card) {
    const article = document.createElement("article");
    article.className = "information-card calendar-card status-" + card.status;
    article.setAttribute("role", "listitem");

    const head = document.createElement("div");
    head.className = "information-card-head";
    const titleBox = document.createElement("div");
    appendText(titleBox, "h3", "information-name", card.name);
    appendText(titleBox, "span", "information-en", card.nameEn);
    head.appendChild(titleBox);
    appendText(head, "span", "information-symbol", card.symbol);
    article.appendChild(head);

    const overview = document.createElement("div");
    overview.className = "information-overview";
    appendText(overview, "strong", "information-kpi", card.highCount + "项高影响");
    appendText(overview, "span", "information-context",
      card.selectionLabel + " · 本周共" + card.count + "项");
    article.appendChild(overview);

    const body = document.createElement("div");
    body.className = "information-body";
    if (card.status === "error" || !card.events.length) {
      appendText(body, "div", "information-empty", "经济日历不可用，未显示事件或默认值。");
    } else {
      const list = document.createElement("ol");
      list.className = "event-list";
      card.events.forEach((event) => {
        const row = document.createElement("li");
        row.className = "event-row impact-" + event.impact;
        const marker = appendText(row, "span", "event-impact", eventImpactLabel(event.impact));
        marker.setAttribute("aria-label", eventImpactLabel(event.impact));
        const time = appendText(row, "time", "event-time", formatEventTime(event.ts));
        time.dateTime = event.ts;
        const identity = document.createElement("span");
        identity.className = "event-identity";
        appendText(identity, "strong", "event-title", event.title);
        appendText(identity, "span", "event-country",
          (event.flag || "🌐") + " " + event.country + " · " + event.ccy);
        row.appendChild(identity);
        const values = document.createElement("span");
        values.className = "event-values";
        appendText(values, "span", event.actual ? "actual" : "", "实际 " + (event.actual || "—"));
        appendText(values, "span", "", "预测 " + (event.forecast || "—"));
        appendText(values, "span", "", "前值 " + (event.previous || "—"));
        row.appendChild(values);
        list.appendChild(row);
      });
      body.appendChild(list);
    }
    article.appendChild(body);
    appendText(article, "p", "information-note", card.note);
    if (card.sourceHealth) appendSupportingHealth(article, card.sourceHealth);
    appendInformationFooter(card, article);
    return article;
  }

  function formatNewsTime(value) {
    const time = new Date(value);
    if (Number.isNaN(time.getTime())) return "时间不可用";
    return new Intl.DateTimeFormat("zh-CN", {
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false
    }).format(time) + " 本地";
  }

  function makeFinanceNewsCard(card) {
    const article = document.createElement("article");
    article.className = "information-card news-card status-" + card.status;
    article.setAttribute("role", "listitem");

    const head = document.createElement("div");
    head.className = "information-card-head";
    const titleBox = document.createElement("div");
    appendText(titleBox, "h3", "information-name", card.name);
    appendText(titleBox, "span", "information-en", card.nameEn);
    head.appendChild(titleBox);
    appendText(head, "span", "information-symbol", card.symbol);
    article.appendChild(head);

    const overview = document.createElement("div");
    overview.className = "information-overview";
    appendText(overview, "strong", "information-kpi", card.articles.length + "条最新市场新闻");
    appendText(overview, "span", "information-context",
      "有效市场板块共" + card.count + "条 · 按发布时间排序");
    article.appendChild(overview);

    const body = document.createElement("div");
    body.className = "information-body";
    if (card.status === "error" || !card.articles.length) {
      appendText(body, "div", "information-empty", "财经新闻不可用，未显示标题或默认内容。");
    } else {
      const list = document.createElement("ol");
      list.className = "news-list";
      card.articles.forEach((item) => {
        const row = document.createElement("li");
        row.className = "news-row";
        const link = document.createElement("a");
        link.className = "news-link";
        link.href = item.link;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        link.setAttribute("aria-label",
          item.title + "（" + item.sourceName + "，在新窗口打开）");
        appendText(link, "strong", "news-title", item.title);
        const meta = document.createElement("span");
        meta.className = "news-meta";
        appendText(meta, "span", "news-source-name", item.sourceName);
        const time = appendText(meta, "time", "", formatNewsTime(item.publishedAt));
        time.dateTime = item.publishedAt;
        link.appendChild(meta);
        row.appendChild(link);
        list.appendChild(row);
      });
      body.appendChild(list);
    }
    article.appendChild(body);
    appendText(article, "p", "information-note", card.note);
    if (card.sourceHealth) appendSupportingHealth(article, card.sourceHealth);
    appendInformationFooter(card, article);
    return article;
  }

  function render(cards) {
    grid.textContent = "";
    cards.forEach((card) => {
      if (card.id === "economic-calendar") grid.appendChild(makeEconomicCalendarCard(card));
      if (card.id === "finance-news") grid.appendChild(makeFinanceNewsCard(card));
    });
    grid.classList.toggle("single", cards.length === 1);
    grid.setAttribute("aria-busy", "false");
    const ok = cards.filter((card) => card.status === "ok").length;
    const partial = cards.filter((card) => card.status === "partial").length;
    const stale = cards.filter((card) => card.status === "stale").length;
    const errors = cards.filter((card) => card.status === "error").length;
    summary.textContent = `${ok} ACTIVE · ${partial} PARTIAL · ${stale} STALE · ${errors} ERROR`;
  }

  return Object.freeze({ render });
}
