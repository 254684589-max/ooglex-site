(function () {
  "use strict";

  var grid = document.getElementById("market-grid");
  var pageUpdated = document.getElementById("page-updated");
  var pageSource = document.getElementById("page-source");
  var assetCount = document.getElementById("asset-count");
  var dataStatus = document.getElementById("data-status");
  var SVG_NS = "http://www.w3.org/2000/svg";

  function isNumber(value) {
    return typeof value === "number" && Number.isFinite(value);
  }

  function formatTime(value) {
    var time = new Date(value);
    if (Number.isNaN(time.getTime())) return "演示时间未提供";
    return new Intl.DateTimeFormat("zh-CN", {
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
      timeZone: "Asia/Shanghai"
    }).format(time) + " CST · 演示";
  }

  function formatPrice(asset) {
    if (!isNumber(asset.price)) return "—";
    var decimals = Number.isInteger(asset.decimals) ? asset.decimals : 2;
    var number = asset.price.toLocaleString("en-US", {
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals
    });
    return (asset.prefix || "") + number + (asset.suffix || "");
  }

  function formatChange(value) {
    if (!isNumber(value)) return "—";
    return (value > 0 ? "+" : value < 0 ? "−" : "") + Math.abs(value).toFixed(2) + "%";
  }

  function appendText(parent, tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    node.textContent = text;
    parent.appendChild(node);
    return node;
  }

  function makeSparkline(values, direction) {
    var svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("class", "sparkline");
    svg.setAttribute("viewBox", "0 0 240 42");
    svg.setAttribute("preserveAspectRatio", "none");
    svg.setAttribute("role", "img");
    svg.setAttribute("aria-label", direction === "positive" ? "演示走势向上" : "演示走势向下");

    var base = document.createElementNS(SVG_NS, "line");
    base.setAttribute("class", "base");
    base.setAttribute("x1", "0");
    base.setAttribute("x2", "240");
    base.setAttribute("y1", "34");
    base.setAttribute("y2", "34");
    svg.appendChild(base);

    if (!Array.isArray(values) || values.length < 2) return svg;
    var min = Math.min.apply(Math, values);
    var max = Math.max.apply(Math, values);
    var span = max - min || 1;
    var points = values.map(function (value, index) {
      var x = index * 240 / (values.length - 1);
      var y = 35 - ((value - min) / span) * 28;
      return x.toFixed(1) + "," + y.toFixed(1);
    }).join(" ");

    var line = document.createElementNS(SVG_NS, "polyline");
    line.setAttribute("class", "line");
    line.setAttribute("points", points);
    svg.appendChild(line);
    return svg;
  }

  function makeCard(asset) {
    var direction = asset.changePct >= 0 ? "positive" : "negative";
    var card = document.createElement("article");
    card.className = "asset-card " + direction;
    card.tabIndex = 0;
    card.setAttribute("aria-label", asset.name + "，演示价格" + formatPrice(asset) + "，涨跌幅" + formatChange(asset.changePct));

    var top = document.createElement("div");
    top.className = "card-top";
    var titleBox = document.createElement("div");
    appendText(titleBox, "h3", "asset-name", asset.name);
    appendText(titleBox, "span", "asset-en", asset.nameEn + " · " + asset.category);
    top.appendChild(titleBox);
    appendText(top, "span", "asset-symbol", asset.symbol);
    card.appendChild(top);

    appendText(card, "div", "asset-price", formatPrice(asset));
    var changeRow = document.createElement("div");
    changeRow.className = "change-row";
    appendText(changeRow, "span", "asset-change", formatChange(asset.changePct));
    appendText(changeRow, "span", "change-word", asset.changePct >= 0 ? "▲ 演示上涨" : "▼ 演示下跌");
    card.appendChild(changeRow);
    card.appendChild(makeSparkline(asset.spark, direction));

    var footer = document.createElement("div");
    footer.className = "asset-footer";
    var time = appendText(footer, "time", "", formatTime(asset.updatedAt));
    time.dateTime = asset.updatedAt;
    appendText(footer, "span", "demo-chip", "DEMO");
    card.appendChild(footer);
    return card;
  }

  function render(data) {
    if (!data || data.demo !== true) {
      throw new Error("演示数据标记缺失，已停止展示，避免被误认为真实行情。");
    }
    if (!Array.isArray(data.assets) || data.assets.length !== 8) {
      throw new Error("演示资产数量不完整。");
    }

    grid.textContent = "";
    data.assets.forEach(function (asset) {
      grid.appendChild(makeCard(asset));
    });
    grid.setAttribute("aria-busy", "false");
    pageUpdated.textContent = formatTime(data.updatedAt);
    pageUpdated.dateTime = data.updatedAt;
    pageSource.textContent = data.source || "Ooglex演示数据";
    assetCount.textContent = data.assets.length + "项全球核心资产";
    dataStatus.textContent = "演示模式 · 非真实行情";
  }

  function renderError(error) {
    grid.textContent = "";
    var message = document.createElement("div");
    message.className = "load-error";
    message.textContent = "演示数据加载失败：" + error.message + " 请稍后刷新或返回首页。";
    grid.appendChild(message);
    grid.setAttribute("aria-busy", "false");
    dataStatus.textContent = "演示数据不可用";
  }

  fetch("data.json?t=" + Date.now(), { cache: "no-store" })
    .then(function (response) {
      if (!response.ok) throw new Error("HTTP " + response.status);
      return response.json();
    })
    .then(render)
    .catch(renderError);
})();
