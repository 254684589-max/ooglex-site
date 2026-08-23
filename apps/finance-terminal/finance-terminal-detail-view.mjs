/* 资产详情抽屉：按需加载，展示完整来源口径、可得的真实序列、同币种高影响事件与标题命中的新闻。
   不生成任何新的行情事实：没有序列就如实说明为什么没有，不用相邻标的或推断值顶替。 */

/* 卡片代码 → macro-radar/series.json 中的序列ID。其余标的没有站内长序列。 */
const SERIES_BY_SYMBOL = Object.freeze({ DGS10: "DGS10", DTWEXBGS: "DTWEXBGS", WTI: "RWTC" });

/* 用于筛同币种高影响事件；这是事件自身的币种属性，不是对相关性的推断。 */
const CURRENCY_BY_SYMBOL = Object.freeze({
  DGS10: "USD", DTWEXBGS: "USD", WTI: "USD", SPY: "USD", QQQ: "USD", DIA: "USD", GLD: "USD"
});

const cache = new Map();

async function loadJson(url) {
  if (!cache.has(url)) {
    cache.set(url, fetch(url, { cache: "no-store" })
      .then((response) => (response.ok ? response.json() : null))
      .catch(() => null));
  }
  return cache.get(url);
}

/* 纯函数：把序列点位映射为折线坐标，便于离线断言。 */
export function seriesPath(values, width, height, pad) {
  const points = (values || []).filter((value) => typeof value === "number" && Number.isFinite(value));
  if (points.length < 2) return "";
  const low = Math.min(...points);
  const high = Math.max(...points);
  const span = high - low || 1;
  const inner = height - pad * 2;
  return points.map((value, index) => {
    const x = pad + index / (points.length - 1) * (width - pad * 2);
    const y = pad + (1 - (value - low) / span) * inner;
    return `${index ? "L" : "M"}${x.toFixed(1)} ${y.toFixed(1)}`;
  }).join(" ");
}

/* 纯函数：标题命中判定，返回命中的关键词，供界面如实标注匹配依据。 */
export function matchedKeyword(title, keywords) {
  const text = String(title || "");
  return (keywords || []).find((word) => word && text.includes(word)) || null;
}

function row(document, parent, label, value) {
  if (!value) return;
  const item = document.createElement("div");
  item.className = "detail-row";
  const key = document.createElement("span");
  key.textContent = label;
  const val = document.createElement("b");
  val.textContent = value;
  item.append(key, val);
  parent.appendChild(item);
}

function section(document, parent, title) {
  const box = document.createElement("section");
  box.className = "detail-section";
  const heading = document.createElement("h4");
  heading.textContent = title;
  box.appendChild(heading);
  parent.appendChild(box);
  return box;
}

function note(document, parent, text) {
  const paragraph = document.createElement("p");
  paragraph.className = "detail-note";
  paragraph.textContent = text;
  parent.appendChild(paragraph);
}

function renderChart(document, parent, asset, series) {
  const box = section(document, parent, "历史序列");
  if (asset.externalDisplay) {
    note(document, box, "本卡为 TradingView 免费组件展示的 ETF 代理，"
      + "按其使用条款不得抓取、保存或再分发组件行情，因此站内没有可绘制的历史序列。"
      + "完整历史请前往下方官方来源查看。");
    return;
  }
  const id = SERIES_BY_SYMBOL[asset.symbol];
  const record = id && series && series.series ? series.series[id] : null;
  const values = record && Array.isArray(record.values) ? record.values : null;
  if (!values || values.length < 2) {
    note(document, box, "站内尚未积累到足够的历史点位；日更任务累积后此处会显示完整曲线。"
      + "在此之前不显示推断值。");
    return;
  }
  const width = 520;
  const height = 150;
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("class", "detail-chart");
  svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
  svg.setAttribute("role", "img");
  const first = record.dates[0];
  const last = record.dates[record.dates.length - 1];
  svg.setAttribute("aria-label",
    `${asset.name} 自 ${first} 至 ${last} 共 ${values.length} 个官方观测点的走势`);
  const line = document.createElementNS("http://www.w3.org/2000/svg", "path");
  line.setAttribute("class", "detail-chart-line");
  line.setAttribute("d", seriesPath(values, width, height, 10));
  svg.appendChild(line);
  box.appendChild(svg);
  const low = Math.min(...values);
  const high = Math.max(...values);
  row(document, box, "区间", `${low} — ${high}`);
  row(document, box, "覆盖", `${first} → ${last} · ${values.length} 点`);
  note(document, box, series.note || "");
}

function renderEvents(document, parent, asset, calendar) {
  const currency = CURRENCY_BY_SYMBOL[asset.symbol];
  if (!currency || !calendar || !Array.isArray(calendar.events)) return;
  const events = calendar.events
    .filter((event) => event && event.currency === currency && event.impact === "high")
    .slice(0, 4);
  if (!events.length) return;
  const box = section(document, parent, `同币种高影响事件 · ${currency}`);
  events.forEach((event) => {
    row(document, box, event.title || event.name || "—", event.date || event.time || "");
  });
  note(document, box, "按事件自身的币种与影响级别筛选，不代表其与本标的存在因果关系。");
}

function renderNews(document, parent, asset, news) {
  const keywords = [asset.name, asset.nameEn, asset.symbol].filter(Boolean);
  const sections = news && Array.isArray(news.sections) ? news.sections : [];
  const hits = [];
  sections.forEach((group) => {
    (group.items || []).forEach((item) => {
      const word = matchedKeyword(item && item.title, keywords);
      if (word && hits.length < 4) hits.push({ item, word });
    });
  });
  if (!hits.length) return;
  const box = section(document, parent, "标题命中的最新条目");
  hits.forEach((hit) => {
    const link = document.createElement("a");
    link.className = "detail-news";
    link.href = hit.item.url || "#";
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.textContent = hit.item.title;
    box.appendChild(link);
    row(document, box, "命中关键词", hit.word);
  });
  note(document, box, "仅按标题字面命中，未做语义判断，命中不等于与本标的相关。");
}

/* 只有抽屉自身的样式随模块按需注入；触发按钮的样式必须留在首屏CSS，
   否则它在模块加载前会短暂小于44px触控目标。 */
const STYLE_ID = "finance-terminal-detail-style";
const STYLE_TEXT = `
.detail-close:focus-visible{outline:2px solid var(--vision-cyan);outline-offset:2px}
.detail-overlay{position:fixed;z-index:60;display:flex;align-items:center;justify-content:center;padding:20px;background:rgba(1,6,12,.78);inset:0}
.detail-panel{width:min(640px,100%);max-height:86vh;padding:18px;overflow-y:auto;border:1px solid var(--vision-line-strong);border-radius:6px;background:linear-gradient(160deg,rgba(8,24,38,.99),rgba(3,12,21,.99));box-shadow:0 24px 60px rgba(0,0,0,.55)}
.detail-head{display:flex;align-items:flex-start;justify-content:space-between;gap:14px;padding-bottom:12px;border-bottom:1px solid var(--vision-line)}
.detail-head h3{margin:0;font-size:16px}
.detail-head span{color:var(--faint);font:9px var(--mono)}
.detail-close{min-width:44px;min-height:44px;border:1px solid var(--vision-line-strong);border-radius:3px;color:var(--muted);background:none;font-size:13px;cursor:pointer}
.detail-section{margin-top:16px}
.detail-section h4{margin:0 0 8px;color:var(--vision-cyan);font:9px var(--mono);letter-spacing:.1em}
.detail-row{display:flex;justify-content:space-between;gap:12px;padding:5px 0;border-bottom:1px solid rgba(69,212,255,.08);font-size:10px}
.detail-row span{color:var(--faint)}
.detail-row b{color:var(--muted);font-weight:600;text-align:right}
.detail-chart{display:block;width:100%;height:auto;margin-bottom:8px}
.detail-chart-line{fill:none;stroke:var(--vision-cyan);stroke-width:1.6}
.detail-note{margin:8px 0 0;color:var(--faint);font-size:9px;line-height:1.7}
.detail-news{display:block;margin-top:8px;color:var(--vision-cyan);font-size:10px;line-height:1.5}
`;

function ensureStyle(document) {
  if (document.getElementById(STYLE_ID)) return;
  const style = document.createElement("style");
  style.id = STYLE_ID;
  style.textContent = STYLE_TEXT;
  document.head.appendChild(style);
}

let instance = null;

/* 模块内单例：调用方无需自行持有实例。 */
export function openAsset(document, view, asset) {
  instance = instance || createDetailView(document, view);
  return instance.open(asset);
}

export function createDetailView(document, window) {
  let overlay = null;
  let lastFocus = null;

  function close() {
    if (!overlay) return;
    overlay.remove();
    overlay = null;
    document.removeEventListener("keydown", onKey);
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  }

  function onKey(event) {
    if (event.key === "Escape") close();
  }

  async function open(asset) {
    ensureStyle(document);
    close();
    lastFocus = document.activeElement;
    overlay = document.createElement("div");
    overlay.className = "detail-overlay";
    const panel = document.createElement("div");
    panel.className = "detail-panel";
    panel.setAttribute("role", "dialog");
    panel.setAttribute("aria-modal", "true");
    panel.setAttribute("aria-label", `${asset.name} 数据详情`);

    const head = document.createElement("div");
    head.className = "detail-head";
    const titleBox = document.createElement("div");
    const title = document.createElement("h3");
    title.textContent = asset.name;
    const sub = document.createElement("span");
    sub.textContent = `${asset.nameEn || ""} · ${asset.symbol}`;
    titleBox.append(title, sub);
    const dismiss = document.createElement("button");
    dismiss.type = "button";
    dismiss.className = "detail-close";
    dismiss.textContent = "✕";
    dismiss.setAttribute("aria-label", "关闭详情");
    dismiss.addEventListener("click", close);
    head.append(titleBox, dismiss);
    panel.appendChild(head);

    const meta = section(document, panel, "来源与口径");
    row(document, meta, "来源", (asset.source && asset.source.name) || "不可用");
    row(document, meta, "数据日", asset.asOf || "不可用");
    row(document, meta, "更新时间", asset.updatedAt || "不可用");
    row(document, meta, "频率", asset.delayLabel || asset.frequency || "不可用");
    row(document, meta, "状态", asset.status || "不可用");
    if (asset.proxyFor) row(document, meta, "代理原标的", asset.proxyFor.symbol);
    if (asset.source && asset.source.url) {
      const link = document.createElement("a");
      link.className = "detail-news";
      link.href = asset.source.url;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      link.textContent = "前往官方来源查看";
      meta.appendChild(link);
    }

    const body = document.createElement("div");
    body.className = "detail-body";
    panel.appendChild(body);
    overlay.appendChild(panel);
    overlay.addEventListener("click", (event) => { if (event.target === overlay) close(); });
    document.body.appendChild(overlay);
    document.addEventListener("keydown", onKey);
    dismiss.focus();

    const [series, calendar, news] = await Promise.all([
      SERIES_BY_SYMBOL[asset.symbol] ? loadJson("../macro-radar/series.json") : null,
      loadJson("../econ-calendar/data.json"),
      loadJson("../whats-latest/data.json")
    ]);
    if (!overlay) return;
    renderChart(document, body, asset, series);
    renderEvents(document, body, asset, calendar);
    renderNews(document, body, asset, news);
  }

  return Object.freeze({ open, close });
}
