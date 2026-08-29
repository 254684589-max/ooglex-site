/* 首页三张工作区预览只镜像已经发布的站内快照：跨资产当日涨跌、宏观读数和经济日历。
   不生成行情、不把资产异动说成事件因果；缺字段、代理、过期或降级条目宁可留空。 */

const EQUITY = "equity";
const IMPACTS = new Set(["high", "medium", "low", "holiday"]);

function isNumber(value) {
  return typeof value === "number" && Number.isFinite(value);
}

function validMarketAsset(asset) {
  return Boolean(asset
    && asset.stale !== true
    && !asset.proxy
    && asset.dataMeta
    && asset.dataMeta.mode === "market"
    && asset.dataMeta.status === "ok"
    && asset.returns
    && isNumber(asset.returns.d1));
}

export function pickIndexRows(tracker, limit = 6) {
  const assets = tracker && Array.isArray(tracker.assets) ? tracker.assets : [];
  return assets.filter((asset) => validMarketAsset(asset) && asset.category === EQUITY)
    .slice(0, limit)
    .map((asset) => ({
      name: String(asset.name || asset.symbol || "").trim(),
      change: asset.returns.d1,
      asOf: String(asset.dataMeta.asOf || "").slice(0, 10),
      source: String(asset.dataMeta.source || "").trim()
    }))
    .filter((row) => row.name && row.asOf && row.source);
}

export function pickMoverRows(tracker, limit = 6) {
  const assets = tracker && Array.isArray(tracker.assets) ? tracker.assets : [];
  return assets.filter(validMarketAsset)
    .map((asset) => ({
      name: String(asset.name || asset.symbol || "").trim(),
      symbol: String(asset.symbol || "").trim(),
      change: asset.returns.d1,
      asOf: String(asset.dataMeta.asOf || "").slice(0, 10),
      source: String(asset.dataMeta.source || "").trim()
    }))
    .filter((row) => row.name && row.asOf && row.source)
    .sort((left, right) => Math.abs(right.change) - Math.abs(left.change))
    .slice(0, limit);
}

export function describeRows(rows) {
  if (!rows.length) return { ready: false, label: "暂无可用指数" };
  const dates = rows.map((row) => row.asOf).sort();
  const oldest = dates[0];
  const newest = dates[dates.length - 1];
  const span = oldest === newest ? newest.slice(5) : `${oldest.slice(5)}~${newest.slice(5)}`;
  return { ready: true, label: `${rows[0].source} · 数据日 ${span}` };
}

export function formatChange(value) {
  const sign = value > 0 ? "+" : value < 0 ? "−" : "";
  return `${sign}${Math.abs(value).toFixed(2)}%`;
}

function macroRows(macro) {
  const groups = macro && Array.isArray(macro.macro) ? macro.macro : [];
  return groups.flatMap((group) => group && Array.isArray(group.rows) ? group.rows : []);
}

function numericReading(row) {
  if (isNumber(row?.price)) return row.price;
  const parsed = Number.parseFloat(String(row?.val || "").replace(/,/g, ""));
  return Number.isFinite(parsed) ? parsed : null;
}

function previousReading(row, current) {
  if (isNumber(row?.previousPrice)) return row.previousPrice;
  if (isNumber(row?.changeBps)) return Number((current - row.changeBps / 100).toFixed(6));
  const match = String(row?.chg || "").match(/([+−-]?\d+(?:\.\d+)?)\s*bp/i);
  if (!match) return current;
  const bps = Number(match[1].replace("−", "-"));
  return Number.isFinite(bps) ? Number((current - bps / 100).toFixed(6)) : current;
}

export function pickMacroSnapshot(macro) {
  const byId = new Map(macroRows(macro).filter((row) => row && row.id)
    .map((row) => [String(row.id), row]));
  const curve = ["DGS2", "DGS10", "DGS30"].map((id) => {
    const row = byId.get(id);
    const current = numericReading(row);
    if (!row || current === null || !String(row.asOf || "")) return null;
    return {
      id,
      label: id.replace("DGS", "") + "Y",
      current,
      previous: previousReading(row, current),
      asOf: String(row.asOf).slice(0, 10)
    };
  }).filter(Boolean);
  const metrics = [
    ["sofr", byId.get("SOFR")],
    ["dgs10", byId.get("DGS10")],
    ["walcl", byId.get("WALCL")]
  ].map(([id, row]) => ({ id, value: row && typeof row.val === "string" ? row.val : "—" }));
  return { ready: curve.length === 3, curve, metrics };
}

export function curveGeometry(curve) {
  if (!Array.isArray(curve) || curve.length !== 3) return null;
  const values = curve.flatMap((point) => [point.current, point.previous]);
  const low = Math.min(...values);
  const high = Math.max(...values);
  const span = Math.max(high - low, 0.1);
  const xs = [24, 128, 232];
  const y = (value) => Number((74 - ((value - low) / span) * 58).toFixed(2));
  const current = curve.map((point, index) => [xs[index], y(point.current)]);
  const previous = curve.map((point, index) => [xs[index], y(point.previous)]);
  const path = (points) => points.map(([x, pointY], index) => `${index ? "L" : "M"}${x} ${pointY}`).join("");
  return {
    current,
    previous,
    currentPath: path(current),
    previousPath: path(previous),
    axis: [high, low + span / 2, low].map((value) => `${value.toFixed(2)}%`)
  };
}

export function pickCalendarRows(calendar, now = new Date(), limit = 5) {
  if (!calendar || !String(calendar.source || "").includes("Forex Factory")
    || !Array.isArray(calendar.events)) return [];
  const nowTime = now instanceof Date && !Number.isNaN(now.getTime()) ? now.getTime() : Date.now();
  const rows = calendar.events.map((event) => {
    const timestamp = new Date(event?.ts || "").getTime();
    if (!Number.isFinite(timestamp) || !IMPACTS.has(event?.impact)
      || typeof event?.title !== "string" || !event.title.trim()) return null;
    return {
      ts: new Date(timestamp).toISOString(),
      timestamp,
      title: event.title.trim(),
      country: String(event.country || "").trim(),
      ccy: String(event.ccy || "").trim(),
      impact: event.impact
    };
  }).filter(Boolean).sort((left, right) => left.timestamp - right.timestamp);
  const important = rows.filter((row) => row.impact === "high" || row.impact === "medium");
  const upcoming = important.filter((row) => row.timestamp >= nowTime).slice(0, limit);
  const seen = new Set(upcoming.map((row) => row.ts + row.title));
  const recent = important.filter((row) => row.timestamp < nowTime).reverse()
    .filter((row) => !seen.has(row.ts + row.title));
  const selected = upcoming.concat(recent).slice(0, limit);
  selected.forEach((row) => seen.add(row.ts + row.title));
  if (selected.length < limit) {
    rows.slice().sort((left, right) => Math.abs(left.timestamp - nowTime) - Math.abs(right.timestamp - nowTime))
      .forEach((row) => {
        const key = row.ts + row.title;
        if (selected.length < limit && !seen.has(key)) {
          seen.add(key);
          selected.push(row);
        }
      });
  }
  return selected;
}

function directionClass(value) {
  return value > 0 ? "is-up" : value < 0 ? "is-down" : "is-flat";
}

function renderQuoteTable(document, tracker, error) {
  const table = document?.getElementById("gateway-index-table");
  if (!table) return { rendered: 0, ready: false };
  const meta = table.querySelector(".preview-head em");
  const rows = Array.from(table.querySelectorAll(".preview-quote-row"));
  const picked = error ? [] : pickIndexRows(tracker, rows.length);
  const described = describeRows(picked);
  if (meta) meta.textContent = error ? "跨资产管道不可用" : described.label;
  rows.forEach((row, index) => {
    const name = row.querySelector("b");
    const change = row.querySelector("em");
    const entry = picked[index];
    if (name) name.textContent = entry?.name || "—";
    if (change) {
      change.textContent = entry ? formatChange(entry.change) : "—";
      change.className = `preview-quote-change${entry ? ` ${directionClass(entry.change)}` : ""}`;
    }
    if (entry) row.title = `${entry.name} 当日涨跌 ${formatChange(entry.change)} · ${entry.source} · 数据日 ${entry.asOf}`;
    else row.removeAttribute("title");
  });
  table.setAttribute("aria-busy", "false");
  return { rendered: picked.length, ready: described.ready };
}

function renderMovers(document, tracker, error) {
  const picked = error ? [] : pickMoverRows(tracker, 6);
  const maximum = Math.max(...picked.map((row) => Math.abs(row.change)), 0.01);
  const table = document?.getElementById("gateway-mover-table");
  const rows = table ? Array.from(table.querySelectorAll(".preview-flow-row")) : [];
  rows.forEach((row, index) => {
    const entry = picked[index];
    row.querySelector("b").textContent = entry?.name || "—";
    const change = row.querySelector("em");
    change.textContent = entry ? formatChange(entry.change) : "—";
    change.className = entry ? directionClass(entry.change) : "";
    row.style.setProperty("--strength", entry ? `${Math.max(18, Math.round(Math.abs(entry.change) / maximum * 100))}%` : "0%");
  });
  if (table) table.setAttribute("aria-busy", "false");

  const impact = document?.getElementById("gateway-impact-table");
  const impactRows = impact ? Array.from(impact.querySelectorAll(".preview-impact-row:not(.preview-impact-legend)")) : [];
  impactRows.forEach((row, index) => {
    const entry = picked[index];
    row.querySelector("b").textContent = entry?.name || "—";
    const arrow = row.querySelector("em");
    arrow.textContent = entry ? (entry.change > 0 ? "↑" : entry.change < 0 ? "↓" : "→") : "·";
    arrow.className = entry ? directionClass(entry.change) : "";
    row.style.setProperty("--strength", entry ? `${Math.max(18, Math.round(Math.abs(entry.change) / maximum * 100))}%` : "0%");
    if (entry) row.title = `${entry.name} 当日涨跌 ${formatChange(entry.change)}；这里只显示同日异动，不表示事件因果关系。`;
    else row.removeAttribute("title");
  });
  if (impact) impact.setAttribute("aria-busy", "false");
  return picked.length;
}

function renderMacro(document, macro, error) {
  const snapshot = error ? { ready: false, curve: [], metrics: [] } : pickMacroSnapshot(macro);
  const geometry = curveGeometry(snapshot.curve);
  const current = document?.getElementById("gateway-yield-current");
  const previous = document?.getElementById("gateway-yield-previous");
  if (geometry && current && previous) {
    current.setAttribute("d", geometry.currentPath);
    previous.setAttribute("d", geometry.previousPath);
    const nodes = Array.from(document.querySelectorAll("#gateway-yield-nodes circle"));
    nodes.forEach((node, index) => {
      node.setAttribute("cx", String(geometry.current[index][0]));
      node.setAttribute("cy", String(geometry.current[index][1]));
    });
    ["high", "mid", "low"].forEach((name, index) => {
      const label = document.getElementById(`gateway-yield-axis-${name}`);
      if (label) label.textContent = geometry.axis[index];
    });
  }
  const meta = document?.getElementById("gateway-yield-meta");
  if (meta) {
    const dates = snapshot.curve.map((point) => point.asOf).sort();
    meta.textContent = error ? "宏观管道不可用" : snapshot.ready ? `FRED · 数据日 ${dates[0].slice(5)}~${dates[dates.length - 1].slice(5)}` : "收益率读数不完整";
  }
  snapshot.metrics.forEach((metric) => {
    const target = document?.getElementById(`gateway-metric-${metric.id}`);
    if (target) target.textContent = metric.value;
  });
  return snapshot.ready;
}

function renderEvents(document, calendar, error) {
  const list = document?.getElementById("gateway-event-list");
  if (!list) return 0;
  const rows = Array.from(list.querySelectorAll(".preview-event-row"));
  const picked = error ? [] : pickCalendarRows(calendar, new Date(), rows.length);
  const formatter = new Intl.DateTimeFormat("zh-CN", {
    month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false
  });
  const labels = { high: "高", medium: "中", low: "低", holiday: "休" };
  rows.forEach((row, index) => {
    const entry = picked[index];
    row.querySelector("time").textContent = entry ? formatter.format(new Date(entry.ts)).replace(/\//g, "-") : "--:--";
    row.querySelector("b").textContent = entry?.title || (index ? "—" : error ? "经济日历不可用" : "暂无可用重要事件");
    const grade = row.querySelector(".event-grade");
    grade.textContent = entry ? labels[entry.impact] : "—";
    grade.className = `event-grade${entry ? ` grade-${entry.impact}` : ""}`;
    if (entry) row.title = `${entry.title} · ${entry.country} ${entry.ccy} · ${entry.impact} · Forex Factory`;
    else row.removeAttribute("title");
  });
  const meta = document.getElementById("gateway-event-meta");
  const updatedAt = new Date(calendar?.updatedAt || "").getTime();
  const stale = !Number.isFinite(updatedAt) || Date.now() - updatedAt > 36 * 60 * 60 * 1000;
  if (meta) meta.textContent = error ? "Forex Factory · 不可用"
    : picked.length ? `Forex Factory · 数据日 ${String(calendar.asOf || "").slice(5)}${stale ? " · 已过期" : ""}`
      : "Forex Factory · 暂无事件";
  list.dataset.status = error ? "error" : stale ? "stale" : picked.length ? "ok" : "empty";
  list.setAttribute("aria-busy", "false");
  return picked.length;
}

export function renderGatewayPreview(options = {}) {
  const document = options.document || globalThis.document;
  if (!document) return null;
  const trackerError = options.trackerError || options.error || null;
  const quote = renderQuoteTable(document, options.tracker, trackerError);
  const movers = renderMovers(document, options.tracker, trackerError);
  const macro = renderMacro(document, options.macro, options.macroError || null);
  const events = renderEvents(document, options.calendar, options.calendarError || null);
  return { quote, movers, macro, events };
}
