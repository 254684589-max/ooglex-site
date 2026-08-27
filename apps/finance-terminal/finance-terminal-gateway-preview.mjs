/* 「专业终端」入口卡的预览表。
   它只镜像跨资产管道（asset-tracker）里已经校验过的当日涨跌，与品类行情板同源，
   不新增请求也不另算口径：该资源在 risk 组里已经在取，加载器按资源键去重。
   逐行只取 dataMeta.mode=market 且 status=ok、未过期、当日涨跌可用的标的；
   任一条件不满足就不进表，宁可少几行也不推算补齐。
   带 proxy 的标的（如以ETF代理原指数）不进这张表：这里没有位置写清代理关系，
   而未加说明地展示代理值会把代理当成原标的。它们在品类行情板里有完整披露。 */

const EQUITY = "equity";

function isNumber(value) {
  return typeof value === "number" && Number.isFinite(value);
}

export function pickIndexRows(tracker, limit = 6) {
  const assets = tracker && Array.isArray(tracker.assets) ? tracker.assets : [];
  return assets.filter((asset) => asset
    && asset.category === EQUITY
    && asset.stale !== true
    && !asset.proxy
    && asset.dataMeta
    && asset.dataMeta.mode === "market"
    && asset.dataMeta.status === "ok"
    && asset.returns
    && isNumber(asset.returns.d1))
    .slice(0, limit)
    .map((asset) => ({
      name: String(asset.name || asset.symbol || "").trim(),
      change: asset.returns.d1,
      asOf: String(asset.dataMeta.asOf || "").slice(0, 10),
      source: String(asset.dataMeta.source || "").trim()
    }))
    .filter((row) => row.name && row.asOf && row.source);
}

/* 表头右侧那一行是披露位：来源 + 数据日。各行数据日不一致时给出区间，
   只写最新的一天会把整张表说得比实际更新。 */
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

export function renderGatewayPreview(options = {}) {
  const { document = globalThis.document, tracker = null, error = null } = options;
  const table = document?.getElementById("gateway-index-table");
  if (!table) return null;
  const head = table.querySelector(".preview-head");
  const meta = head ? head.querySelector("em") : null;
  const rows = Array.from(table.querySelectorAll(".preview-quote-row"));
  if (!rows.length) return null;

  const picked = error ? [] : pickIndexRows(tracker, rows.length);
  const described = describeRows(picked);
  if (meta) meta.textContent = error ? "跨资产管道不可用" : described.label;

  rows.forEach((row, index) => {
    const name = row.querySelector("b");
    const change = row.querySelector("em");
    const entry = picked[index];
    if (!entry) {
      if (name) name.textContent = "—";
      if (change) {
        change.textContent = "—";
        change.className = "preview-quote-change";
      }
      row.removeAttribute("title");
      return;
    }
    if (name) name.textContent = entry.name;
    if (change) {
      change.textContent = formatChange(entry.change);
      change.className = "preview-quote-change "
        + (entry.change > 0 ? "is-up" : entry.change < 0 ? "is-down" : "is-flat");
    }
    row.title = `${entry.name} 当日涨跌 ${formatChange(entry.change)} · ${entry.source} · 数据日 ${entry.asOf}`;
  });

  table.setAttribute("aria-busy", "false");
  return { rendered: picked.length, ready: described.ready };
}
