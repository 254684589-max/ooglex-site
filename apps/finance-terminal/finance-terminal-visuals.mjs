import { renderRiskRadar } from "./finance-terminal-risk-radar.mjs";
import { renderWorldHeatmap } from "./finance-terminal-worldmap.mjs";
import { renderSessions } from "./finance-terminal-sessions.mjs";

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

const REGION_SPECS = Object.freeze([
  { id: "north-america", label: "北美", symbols: ["^GSPC"] },
  { id: "south-america", label: "南美", symbols: ["^BVSP"] },
  { id: "europe", label: "欧洲", symbols: ["^STOXX", "^FTSE", "^GDAXI", "^FCHI"] },
  { id: "greater-china", label: "大中华", symbols: ["510300.SS", "^HSI"] },
  { id: "japan", label: "日本", symbols: ["^N225"] },
  { id: "south-asia", label: "南亚", symbols: ["^BSESN"] },
  { id: "oceania", label: "大洋洲", symbols: ["^AXJO", "^NZ50"] }
]);

function signedPercent(value) {
  if (!finiteNumber(value)) return "—";
  const sign = value > 0 ? "+" : value < 0 ? "−" : "";
  return `${sign}${Math.abs(value).toFixed(2)}%`;
}

function regionSnapshot(card, spec) {
  const sourceAssets = Array.isArray(card?.assets) ? card.assets : [];
  const assets = spec.symbols.map((symbol) => sourceAssets.find((asset) => asset.symbol === symbol))
    .filter((asset) => asset && !asset.stale && !asset.suspect && finiteNumber(asset.returns?.d1));
  if (!assets.length) return { ...spec, value: null, assets: [] };
  const value = assets.reduce((sum, asset) => sum + asset.returns.d1, 0) / assets.length;
  return { ...spec, value, assets };
}

function pressureClass(value) {
  if (!finiteNumber(value)) return "region-no-data";
  if (value <= -1) return "region-pressure-high";
  if (value < -0.25) return "region-pressure-watch";
  if (value <= 0.25) return "region-pressure-neutral";
  return "region-pressure-positive";
}

export function deriveRegionalHeatmap(card) {
  if (!card || card.status === "error" || !Array.isArray(card.assets)) return [];
  return REGION_SPECS.map((spec) => regionSnapshot(card, spec));
}

export function derivePipelineSummary(cards) {
  const rows = Array.isArray(cards) ? cards : [];
  const cycles = rows.map((card) => card?.readiness?.consecutiveSuccessfulCycles)
    .filter((value) => Number.isInteger(value) && value >= 0 && value <= 7);
  return Object.freeze({
    minimumCycle: cycles.length === 4 ? Math.min(...cycles) : null,
    evidenceStale: rows.some((card) => card?.readiness?.reportStale === true),
    healthy: rows.filter((card) => card.status === "healthy").length,
    degraded: rows.filter((card) => card.status === "degraded" || card.status === "stale").length,
    failed: rows.filter((card) => card.status === "failed" || card.status === "unknown").length
  });
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
      const zone = document.querySelector(`[data-market-zone="${timeZone}"]`);
      try {
        /* <time> 只放机器可读的 HH:MM；时区缩写写进相邻元素，
           这样时间本身可被程序解析，缩写仍照常显示。 */
        const parts = new Intl.DateTimeFormat(timeZone.startsWith("America/") ? "en-US" : "en-GB", {
          timeZone,
          hour: "2-digit",
          minute: "2-digit",
          hour12: false,
          timeZoneName: "short"
        }).formatToParts(now);
        const pick = (type) => parts.find((part) => part.type === type)?.value || "";
        element.textContent = `${pick("hour")}:${pick("minute")}`;
        element.dateTime = now.toISOString();
        /* 按时区选locale才能得到正确缩写（伦敦BST需en-GB、纽约EDT需en-US）；
           其余时区回退为准确的GMT偏移，不硬编码会随夏令时改变的缩写。 */
        if (zone) zone.textContent = pick("timeZoneName");
      } catch {
        element.textContent = "--:--";
        element.removeAttribute("datetime");
        if (zone) zone.textContent = "";
      }
    });
    renderSessions(document, now);
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
      value.textContent = asset.externalDisplay
        ? "组件报价"
        : `${displayPrice(asset)} · ${displayChange(asset)}`;
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
    status?.classList.remove("status-error-text", "status-watch-text", "status-ok-text");
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

  function renderGlobalRiskHeatmap(cards) {
    const panel = document.getElementById("global-risk-map");
    const status = document.getElementById("global-risk-map-status");
    const list = document.getElementById("risk-region-list");
    if (!panel || !status || !list) return;
    const card = Array.isArray(cards) ? cards.find((item) => item.id === "cross-asset") : null;
    list.textContent = "";
    panel.className = "global-risk-map";
    if (!card || card.status === "error" || !Array.isArray(card.assets)) {
      panel.classList.add("status-error");
      status.className = "status-chip error-chip";
      status.textContent = "ERROR";
      const error = document.createElement("p");
      error.textContent = "区域代表指数不可用，热力图未显示推断值。";
      list.appendChild(error);
      panel.querySelectorAll("[data-risk-region]").forEach((region) => {
        region.className.baseVal = "risk-region region-no-data";
      });
      panel.setAttribute("aria-busy", "false");
      return;
    }

    const regions = deriveRegionalHeatmap(card);
    /* 点阵大陆按同一组回报值着色；画布不可用时保留下方SVG区块作为降级。 */
    renderWorldHeatmap(document.getElementById("risk-map-canvas"), regions, { document, window });
    regions.forEach((region) => {
      const shape = panel.querySelector(`[data-risk-region="${region.id}"]`);
      if (shape) shape.setAttribute("class", `risk-region ${pressureClass(region.value)}`);
      const row = document.createElement("div");
      row.className = `risk-region-row ${pressureClass(region.value)}`;
      const identity = document.createElement("span");
      const name = document.createElement("b");
      name.textContent = region.label;
      const symbols = document.createElement("small");
      symbols.textContent = region.assets.length
        ? region.assets.map((asset) => asset.symbol + (asset.proxy ? " PROXY" : "")).join(" · ")
        : "无可比代表指数";
      identity.append(name, symbols);
      const value = document.createElement("strong");
      value.textContent = signedPercent(region.value);
      value.setAttribute("aria-label", finiteNumber(region.value)
        ? `${region.label}代表指数当日平均回报${signedPercent(region.value)}`
        : `${region.label}代表指数数据不可用`);
      row.append(identity, value);
      list.appendChild(row);
    });

    const source = document.createElement("p");
    source.className = "risk-map-source";
    source.textContent = `来源 · Yahoo Finance · 数据日 ${card.asOf || "不可用"} · `
      + `更新 ${card.updatedAt ? new Intl.DateTimeFormat("zh-CN", {
        timeZone: "Asia/Shanghai", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false
      }).format(new Date(card.updatedAt)) + " UTC+8" : "不可用"}`;
    list.appendChild(source);

    const unavailable = regions.filter((region) => !finiteNumber(region.value)).length;
    panel.classList.add(`status-${card.status}`);
    status.className = `status-chip ${card.status === "stale" ? "stale-chip"
      : card.status === "partial" || unavailable ? "partial-chip" : "official-chip"}`;
    status.textContent = card.status === "stale" ? "STALE"
      : card.status === "partial" || unavailable ? "PARTIAL" : "ACTIVE";
    panel.setAttribute("aria-busy", "false");
  }

  function renderPipelineOverview(cards) {
    const command = document.getElementById("pipeline-command");
    const ring = document.getElementById("stable-v1-ring");
    const ringValue = document.getElementById("stable-v1-ring-value");
    const ringState = document.getElementById("stable-v1-ring-state");
    const topChip = document.getElementById("stable-v1-chip");
    const title = document.getElementById("pipeline-command-title");
    const note = document.getElementById("pipeline-command-note");
    if (!command || !ring || !ringValue || !ringState || !topChip || !title || !note) return;
    const rows = Array.isArray(cards) ? cards : [];
    command.querySelectorAll("[data-pipeline-node]").forEach((node) => {
      node.className = "pipeline-node-unknown";
      const state = node.querySelector("i");
      if (state) state.textContent = "UNKNOWN";
    });
    const summary = derivePipelineSummary(rows);
    const minimum = summary.minimumCycle;
    const evidenceStale = summary.evidenceStale;

    command.setAttribute("aria-busy", "false");
    ring.className = "stable-v1-ring";
    topChip.className = "stable-v1-chip";
    if (minimum === null) {
      ring.classList.add("status-error");
      topChip.classList.add("status-error");
      ringValue.textContent = "— / 7";
      ringState.textContent = "UNKNOWN";
      topChip.textContent = "STABLE V1 · — / 7";
      topChip.setAttribute("aria-label", "稳定V1资格证据不可用");
      ring.setAttribute("aria-valuenow", "0");
      ring.style.setProperty("--stable-progress", "0deg");
    } else {
      const ready = minimum >= 7 && !evidenceStale;
      ring.classList.add(ready ? "status-ready" : evidenceStale ? "status-stale" : "status-progress");
      topChip.classList.add(ready ? "status-ready" : evidenceStale ? "status-stale" : "status-progress");
      ringValue.textContent = `${minimum} / 7`;
      ringState.textContent = ready ? "READY" : evidenceStale ? "EVIDENCE STALE" : "IN PROGRESS";
      topChip.textContent = `STABLE V1 · ${minimum} / 7`;
      topChip.setAttribute("aria-label", `稳定V1资格${minimum}/7${evidenceStale ? "，证据快照已过期" : ""}`);
      ring.setAttribute("aria-valuenow", String(minimum));
      ring.style.setProperty("--stable-progress", `${minimum / 7 * 360}deg`);
    }

    title.textContent = `${summary.healthy}/4 HEALTHY · ${summary.degraded} DEGRADED · ${summary.failed} FAILED/UNKNOWN`;
    note.textContent = evidenceStale
      ? "现有周期记录完整保留，但资格快照已超过72小时；请以远端门禁为准，不重新计算已有记录。"
      : "资格证据与更新健康分别校验；视觉改版不会清空、补造或重复累计已有周期。";
    rows.forEach((card) => {
      const node = command.querySelector(`[data-pipeline-node="${card.id}"]`);
      if (!node) return;
      node.className = `pipeline-node-${card.status}`;
      const state = node.querySelector("i");
      if (state) state.textContent = String(card.status || "unknown").toUpperCase();
    });
  }

  function renderCriticalError(message) {
    renderMarketTape([]);
    setText(document.getElementById("orbit-market-status"), "ERROR · 配置不可用");
    setText(document.getElementById("orbit-market-note"), message || "未显示未经校验的数据");
  }

  startMarketClocks();

  return Object.freeze({
    renderCriticalError,
    renderGlobalRiskHeatmap,
    renderMarketOverview,
    renderPipelineOverview,
    renderRiskRadar: (cards) => renderRiskRadar(document, cards),
    updateMarketClocks
  });
}
