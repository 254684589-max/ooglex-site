function finiteNumber(value) {
  return typeof value === "number" && Number.isFinite(value);
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}

function displayPrice(asset) {
  if (!asset || asset.externalDisplay) return "组件报价";
  if (!finiteNumber(asset.price)) return "数值不可用";
  const decimals = Number.isInteger(asset.decimals) ? clamp(asset.decimals, 0, 6) : 2;
  const value = asset.price.toLocaleString("en-US", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals
  });
  return `${asset.prefix || ""}${value}${asset.suffix || ""}`;
}

function displayChange(asset) {
  if (!asset || asset.externalDisplay) return "时效由提供方标注";
  if (finiteNumber(asset.change) && asset.changeUnit === "bp") {
    const sign = asset.change > 0 ? "+" : asset.change < 0 ? "−" : "";
    return `${sign}${Math.abs(asset.change).toFixed(0)} bp`;
  }
  if (finiteNumber(asset.changePct)) {
    const sign = asset.changePct > 0 ? "+" : asset.changePct < 0 ? "−" : "";
    return `${sign}${Math.abs(asset.changePct).toFixed(2)}%`;
  }
  return asset.status === "error" ? "ERROR" : asset.status === "stale" ? "STALE" : "变化不可用";
}

function directionClass(asset) {
  if (!asset || asset.status === "error") return "status-error";
  if (asset.status === "stale") return "status-stale";
  if (asset.status === "partial") return "status-partial";
  const value = finiteNumber(asset.changePct) ? asset.changePct
    : finiteNumber(asset.change) ? asset.change : null;
  if (value === null || value === 0) return "neutral";
  return value > 0 ? "positive" : "negative";
}

function setText(element, value) {
  if (element) element.textContent = value;
}

export function createTerminalVisuals(dependencies = {}) {
  const document = dependencies.document;
  const window = dependencies.window;
  if (!document || !window) throw new Error("终端视觉层需要浏览器文档环境");

  let clockTimer = null;

  function updateMarketClocks() {
    const now = new Date();
    document.querySelectorAll("[data-market-time]").forEach((element) => {
      const timeZone = element.getAttribute("data-market-time");
      try {
        element.textContent = new Intl.DateTimeFormat("en-GB", {
          timeZone,
          hour: "2-digit",
          minute: "2-digit",
          hour12: false
        }).format(now);
        element.dateTime = now.toISOString();
      } catch {
        element.textContent = "--:--";
        element.removeAttribute("datetime");
      }
    });
  }

  function startMarketClocks() {
    updateMarketClocks();
    if (clockTimer !== null) window.clearInterval(clockTimer);
    clockTimer = window.setInterval(updateMarketClocks, 30000);
  }

  function renderMarketTape(assets) {
    const track = document.getElementById("market-tape");
    if (!track) return;
    track.textContent = "";
    if (!Array.isArray(assets) || assets.length !== 8) {
      const unavailable = document.createElement("span");
      unavailable.className = "market-tape-loading";
      unavailable.textContent = "核心资产状态不可用";
      track.appendChild(unavailable);
      return;
    }
    assets.forEach((asset) => {
      const item = document.createElement("span");
      item.className = `market-tape-item ${directionClass(asset)}`;
      const symbol = document.createElement("b");
      symbol.textContent = asset.symbol || "—";
      const value = document.createElement("span");
      value.textContent = `${displayPrice(asset)} · ${displayChange(asset)}`;
      item.append(symbol, value);
      track.appendChild(item);
    });
  }

  function renderMarketOverview(data) {
    const assets = data && Array.isArray(data.assets) ? data.assets : [];
    renderMarketTape(assets);
    const official = assets.filter((asset) => asset.demo === false && !asset.externalDisplay);
    const proxies = assets.filter((asset) => Boolean(asset.externalDisplay));
    const errors = official.filter((asset) => asset.status === "error");
    const stale = official.filter((asset) => asset.status === "stale");
    const partial = official.filter((asset) => asset.status === "partial");
    const status = document.getElementById("orbit-market-status");
    const note = document.getElementById("orbit-market-note");
    if (errors.length) {
      setText(status, "PARTIAL · 部分来源不可用");
      setText(note, `${errors.map((asset) => asset.symbol).join("、")}未展示无效数值`);
      status?.classList.add("status-error-text");
      return;
    }
    if (stale.length || partial.length) {
      setText(status, "WATCH · 数据状态需注意");
      setText(note, `${stale.length}项过期 · ${partial.length}项明确降级 · ${proxies.length}项免费代理`);
      status?.classList.add("status-watch-text");
      return;
    }
    setText(status, "VERIFIED · 核心契约正常");
    setText(note, `${official.length}项站内行情 · ${proxies.length}项免费代理 · 0项演示`);
    status?.classList.add("status-ok-text");
  }

  function renderCriticalError(message) {
    renderMarketTape([]);
    setText(document.getElementById("orbit-market-status"), "ERROR · 配置不可用");
    setText(document.getElementById("orbit-market-note"), message || "未显示未经校验的数据");
  }

  startMarketClocks();

  return Object.freeze({
    renderCriticalError,
    renderMarketOverview,
    updateMarketClocks
  });
}
