function requireDependency(dependencies, name) {
  const value = dependencies && dependencies[name];
  if (value === undefined || value === null) {
    throw new Error(`市场研究视图缺少依赖：${name}`);
  }
  return value;
}

export function createResearchView(dependencies = {}) {
  const document = requireDependency(dependencies, "document");
  const grid = requireDependency(dependencies, "grid");
  const summary = requireDependency(dependencies, "summary");
  const isNumber = requireDependency(dependencies, "isNumber");
  const appendText = requireDependency(dependencies, "appendText");
  const formatSignedPercent = requireDependency(dependencies, "formatSignedPercent");
  const appendQualitySummary = requireDependency(dependencies, "appendQualitySummary");
  const appendSourceHealth = requireDependency(dependencies, "appendSourceHealth");
  const rankCrossAssetPeriod = requireDependency(dependencies, "rankCrossAssetPeriod");
  const periodTabTargetIndex = requireDependency(dependencies, "periodTabTargetIndex");
  const appendResearchFooter = requireDependency(dependencies, "appendResearchFooter");

  function appendRankColumn(parent, title, rows, periodKey, direction) {
    const column = document.createElement("div");
    column.className = "rank-column " + direction;
    appendText(column, "h4", "rank-title", title);
    const list = document.createElement("ol");
    list.className = "rank-list";
    rows.forEach((asset) => {
      const item = document.createElement("li");
      item.className = "rank-row";
      const identity = document.createElement("span");
      identity.className = "rank-identity";
      appendText(identity, "span", "rank-name", asset.name);
      const provenance = document.createElement("span");
      provenance.className = "rank-provenance";
      if (asset.proxy) {
        const proxyBadge = appendText(provenance, "span", "proxy-badge", "PROXY");
        proxyBadge.title = asset.proxy.note;
      }
      appendText(provenance, "span", "rank-symbol",
        asset.symbol + " · " + asset.dataLabel.replace("PROXY · ", ""));
      identity.appendChild(provenance);
      item.appendChild(identity);
      appendText(item, "strong", "rank-value", formatSignedPercent(asset.returns[periodKey]));
      list.appendChild(item);
    });
    column.appendChild(list);
    parent.appendChild(column);
  }

  function makeCrossAssetCard(card) {
    const article = document.createElement("article");
    article.className = "research-card status-" + card.status;
    article.setAttribute("role", "listitem");

    const head = document.createElement("div");
    head.className = "research-card-head";
    const titleBox = document.createElement("div");
    appendText(titleBox, "h3", "research-name", card.name);
    appendText(titleBox, "span", "research-en", card.nameEn);
    head.appendChild(titleBox);
    appendText(head, "span", "research-symbol", card.symbol);
    article.appendChild(head);
    appendQualitySummary(article, card.quality);
    appendSourceHealth(article, card.sourceHealth);

    const controls = document.createElement("div");
    controls.className = "period-tabs";
    controls.setAttribute("role", "tablist");
    controls.setAttribute("aria-label", "跨资产表现周期");
    controls.setAttribute("aria-orientation", "horizontal");
    const body = document.createElement("div");
    body.className = "research-body";
    body.id = card.id + "-period-panel";
    body.setAttribute("role", "tabpanel");
    body.tabIndex = 0;

    function draw(periodKey) {
      const ranking = rankCrossAssetPeriod(card, periodKey);
      controls.querySelectorAll("button").forEach((button) => {
        const active = button.getAttribute("data-period") === ranking.period.key;
        button.classList.toggle("active", active);
        button.setAttribute("aria-selected", active ? "true" : "false");
        button.tabIndex = active ? 0 : -1;
        if (active) body.setAttribute("aria-labelledby", button.id);
      });
      body.textContent = "";
      if (card.status === "error") {
        appendText(body, "div", "research-empty", "数据不可用，未显示排行数值。");
        return;
      }
      if (ranking.paused) {
        appendText(body, "div", "research-empty",
          "数据已过期，“今日”排行暂停；可切换历史周期查看最后有效快照。");
        return;
      }
      const columns = document.createElement("div");
      columns.className = "leader-columns";
      appendRankColumn(columns, "领涨 TOP 3", ranking.leaders, ranking.period.key, "positive");
      appendRankColumn(columns, "领跌 BOTTOM 3", ranking.laggards, ranking.period.key, "negative");
      body.appendChild(columns);
      appendText(body, "p", "coverage-note",
        ranking.coverage + "/" + ranking.total + "项可比 · 已排除过期、可疑或缺失值");
    }

    card.periods.forEach((period) => {
      const button = appendText(controls, "button", "period-tab", period.label);
      button.type = "button";
      button.id = card.id + "-period-" + period.key;
      button.setAttribute("role", "tab");
      button.setAttribute("data-period", period.key);
      button.setAttribute("aria-controls", body.id);
      button.setAttribute("aria-selected", "false");
      button.tabIndex = -1;
      button.addEventListener("click", () => { draw(period.key); });
    });
    controls.addEventListener("keydown", (event) => {
      const buttons = Array.prototype.slice.call(controls.querySelectorAll('[role="tab"]'));
      const currentIndex = buttons.indexOf(document.activeElement);
      if (currentIndex < 0) return;
      const nextIndex = periodTabTargetIndex(currentIndex, event.key, buttons.length);
      if (nextIndex === currentIndex && ["Home", "End"].indexOf(event.key) === -1) return;
      event.preventDefault();
      const nextButton = buttons[nextIndex];
      draw(nextButton.getAttribute("data-period"));
      nextButton.focus();
    });
    article.appendChild(controls);
    article.appendChild(body);
    appendText(article, "p", "research-note", card.note);
    appendResearchFooter(card, article);
    draw(card.defaultPeriod);
    return article;
  }

  function formatMarketCapBillions(value) {
    if (!isNumber(value)) return "—";
    if (value >= 1000) return "$" + (value / 1000).toFixed(value >= 100000 ? 1 : 2) + "T";
    return "$" + value.toFixed(1) + "B";
  }

  function makeAssetRankingCard(card) {
    const article = document.createElement("article");
    article.className = "research-card status-" + card.status;
    article.setAttribute("role", "listitem");

    const head = document.createElement("div");
    head.className = "research-card-head";
    const titleBox = document.createElement("div");
    appendText(titleBox, "h3", "research-name", card.name);
    appendText(titleBox, "span", "research-en", card.nameEn);
    head.appendChild(titleBox);
    appendText(head, "span", "research-symbol", card.symbol);
    article.appendChild(head);
    appendQualitySummary(article, card.quality);
    appendSourceHealth(article, card.sourceHealth);

    const body = document.createElement("div");
    body.className = "research-body marketcap-body";
    if (card.status === "error") {
      appendText(body, "div", "research-empty", "数据不可用，未显示市值或排名。");
    } else {
      const total = document.createElement("div");
      total.className = "research-kpi";
      appendText(total, "strong", "research-kpi-value", formatMarketCapBillions(card.totalMarketCap));
      appendText(total, "span", "research-kpi-label", "榜单样本合计 · " + card.count + "项");
      body.appendChild(total);
      const list = document.createElement("ol");
      list.className = "marketcap-list";
      card.assets.forEach((asset) => {
        const row = document.createElement("li");
        row.className = "marketcap-row" + (asset.stale ? " row-stale" : "");
        appendText(row, "span", "marketcap-rank", String(asset.rank).padStart(2, "0"));
        const identity = document.createElement("span");
        identity.className = "marketcap-identity";
        appendText(identity, "span", "marketcap-name", asset.name);
        appendText(identity, "span", "marketcap-category", asset.categoryLabel + " · " + asset.dataLabel);
        row.appendChild(identity);
        appendText(row, "strong", "marketcap-value", formatMarketCapBillions(asset.marketCap));
        list.appendChild(row);
      });
      body.appendChild(list);
    }
    article.appendChild(body);
    appendText(article, "p", "research-note", card.note);
    appendResearchFooter(card, article);
    return article;
  }

  function makeCompanyLeadersCard(card) {
    const article = document.createElement("article");
    article.className = "research-card status-" + card.status;
    article.setAttribute("role", "listitem");

    const head = document.createElement("div");
    head.className = "research-card-head";
    const titleBox = document.createElement("div");
    appendText(titleBox, "h3", "research-name", card.name);
    appendText(titleBox, "span", "research-en", card.nameEn);
    head.appendChild(titleBox);
    appendText(head, "span", "research-symbol", card.symbol);
    article.appendChild(head);
    appendQualitySummary(article, card.quality);
    appendSourceHealth(article, card.sourceHealth);

    const body = document.createElement("div");
    body.className = "research-body company-body";
    if (card.status === "error") {
      appendText(body, "div", "research-empty", "数据不可用，未显示公司市值或涨跌。");
    } else {
      const total = document.createElement("div");
      total.className = "research-kpi";
      appendText(total, "strong", "research-kpi-value", formatMarketCapBillions(card.listedMarketCap));
      appendText(total, "span", "research-kpi-label",
        card.listedCount + "家上市公司合计 · 排除" + card.privateCount + "家未上市估值");
      body.appendChild(total);

      const topList = document.createElement("ol");
      topList.className = "marketcap-list company-top-list";
      card.topCompanies.forEach((company) => {
        const row = document.createElement("li");
        row.className = "marketcap-row";
        appendText(row, "span", "marketcap-rank", String(company.rank).padStart(2, "0"));
        const identity = document.createElement("span");
        identity.className = "marketcap-identity";
        appendText(identity, "span", "marketcap-name", company.name);
        appendText(identity, "span", "marketcap-category", company.symbol + " · " + company.dataLabel);
        row.appendChild(identity);
        appendText(row, "strong", "marketcap-value", formatMarketCapBillions(company.marketCap));
        topList.appendChild(row);
      });
      body.appendChild(topList);

      const movers = document.createElement("div");
      movers.className = "mover-grid";
      [
        { title: "今日领涨", company: card.gainer, direction: "positive" },
        { title: "今日领跌", company: card.laggard, direction: "negative" }
      ].forEach((item) => {
        const box = document.createElement("div");
        box.className = "mover-box " + item.direction;
        appendText(box, "span", "mover-label", item.title);
        appendText(box, "strong", "mover-name", item.company ? item.company.name : "—");
        appendText(box, "span", "mover-value",
          item.company ? formatSignedPercent(item.company.changePct) : "—");
        appendText(box, "span", "mover-symbol", item.company
          ? item.company.symbol + " · " + item.company.dataLabel
          : "逐条状态待确认");
        movers.appendChild(box);
      });
      body.appendChild(movers);
    }
    article.appendChild(body);
    appendText(article, "p", "research-note", card.note);
    appendResearchFooter(card, article);
    return article;
  }

  function render(cards) {
    grid.textContent = "";
    cards.forEach((card) => {
      if (card.id === "cross-asset") grid.appendChild(makeCrossAssetCard(card));
      if (card.id === "asset-ranking") grid.appendChild(makeAssetRankingCard(card));
      if (card.id === "company-leaders") grid.appendChild(makeCompanyLeadersCard(card));
    });
    grid.setAttribute("aria-busy", "false");
    const ok = cards.filter((card) => card.status === "ok").length;
    const partial = cards.filter((card) => card.status === "partial").length;
    const stale = cards.filter((card) => card.status === "stale").length;
    const errors = cards.filter((card) => card.status === "error").length;
    summary.textContent = `${ok} ACTIVE · ${partial} PARTIAL · ${stale} STALE · ${errors} ERROR`;
  }

  return Object.freeze({ render });
}
