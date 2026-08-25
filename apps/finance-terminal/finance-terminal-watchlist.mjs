/* 自选清单：只存标的代码，只保存在访客本机的 localStorage，不上传、不随请求外发。
   浏览器禁用存储（隐私模式、站点数据被拦）时读写会抛异常，此时降级为本次会话内存态，
   功能仍可用但不跨会话保留；调用方据此提示，不假装已保存。 */
const STORAGE_KEY = "ooglex.finance-terminal.watchlist.v1";
const MAX_ENTRIES = 40;
const SYMBOL_PATTERN = /^[A-Za-z0-9^._=/-]{1,24}$/;

/* 只接受形似标的代码的短字符串，防止把任意内容写进本地存储。 */
export function sanitizeSymbol(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return SYMBOL_PATTERN.test(trimmed) ? trimmed : null;
}

export function normalizeList(values) {
  const seen = [];
  (Array.isArray(values) ? values : []).forEach((value) => {
    const symbol = sanitizeSymbol(value);
    if (symbol && !seen.includes(symbol)) seen.push(symbol);
  });
  return seen.slice(0, MAX_ENTRIES);
}

export function readWatchlist(storage) {
  try {
    return normalizeList(JSON.parse(storage.getItem(STORAGE_KEY) || "[]"));
  } catch {
    return [];
  }
}

/* 返回是否真正落盘；false 表示只在内存生效，调用方需要如实告知。 */
export function writeWatchlist(symbols, storage) {
  try {
    storage.setItem(STORAGE_KEY, JSON.stringify(normalizeList(symbols)));
    return true;
  } catch {
    return false;
  }
}

/* 纯函数：返回切换后的新数组，不修改入参。 */
export function toggleSymbol(symbol, symbols) {
  const target = sanitizeSymbol(symbol);
  const current = normalizeList(symbols);
  if (!target) return current;
  return current.includes(target)
    ? current.filter((item) => item !== target)
    : normalizeList(current.concat(target));
}

/* 纯函数：自选项前置且各自保持原有相对顺序（稳定排序，不打乱同组内次序）。 */
export function orderByWatchlist(items, watched, keyOf) {
  const list = Array.isArray(items) ? items.slice() : [];
  const marked = normalizeList(watched);
  const starred = [];
  const rest = [];
  list.forEach((item) => {
    const key = sanitizeSymbol(keyOf ? keyOf(item) : item);
    (key && marked.includes(key) ? starred : rest).push(item);
  });
  return starred.concat(rest);
}

export function createWatchlistStore(storage) {
  let symbols = storage ? readWatchlist(storage) : [];
  let persisted = Boolean(storage);
  return Object.freeze({
    list: () => symbols.slice(),
    has: (symbol) => symbols.includes(sanitizeSymbol(symbol)),
    size: () => symbols.length,
    /* 存储不可用时仍切换内存态，但把 persisted 置false，供界面如实说明。 */
    toggle(symbol) {
      symbols = toggleSymbol(symbol, symbols);
      if (storage) persisted = writeWatchlist(symbols, storage);
      return symbols.slice();
    },
    persisted: () => persisted
  });
}

/* 整页共用一份自选状态：核心资产与品类行情板读同一个 store，任一处切换都会
   通知另一处重画，避免两份内存副本各自显示不同的星标。 */
let sharedStore = null;
const listeners = new Set();

export function sharedWatchlistStore(view) {
  if (!sharedStore) sharedStore = createWatchlistStore(safeStorage(view));
  return sharedStore;
}

export function subscribeWatchlist(listener) {
  if (typeof listener !== "function") return () => {};
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function notifyWatchlist() {
  listeners.forEach((listener) => {
    try {
      listener();
    } catch {
      /* 单个分区重画失败不影响其他分区 */
    }
  });
}

/* 隐私模式或站点数据被拦时，连访问 window.localStorage 本身都可能抛异常。 */
export function safeStorage(view) {
  try {
    return (view || globalThis).localStorage || null;
  } catch {
    return null;
  }
}

/* 纯函数：由自选数量与存储可用性推导筛选入口的呈现，便于离线断言。 */
export function describeFilter(count, watchOnly, persisted) {
  const active = Boolean(watchOnly) && count > 0;
  return {
    hidden: count === 0,
    pressed: active,
    label: active ? "显示全部" : `只看自选 ${count}`,
    title: persisted
      ? "自选仅保存在本机浏览器，不会上传"
      : "浏览器未允许本地存储，自选仅在本次会话有效"
  };
}

/* 收藏开关：★/☆ 符号 + 无障碍名称双重标识，颜色不作为唯一信号。 */
export function createWatchButton(document, symbol, store, onChange) {
  const button = document.createElement("button");
  const watched = Boolean(store && store.has(symbol));
  button.type = "button";
  button.className = "watch-toggle";
  button.textContent = watched ? "★" : "☆";
  button.setAttribute("data-watch-symbol", symbol);
  button.setAttribute("aria-pressed", watched ? "true" : "false");
  const name = `${watched ? "取消自选" : "加入自选"} ${symbol}`;
  button.setAttribute("aria-label", name);
  button.title = name;
  button.addEventListener("click", () => {
    if (!store) return;
    store.toggle(symbol);
    if (onChange) onChange();
  });
  return button;
}

/* 一次性给出「自选前置的完整顺序」与「当前应展示的子集」，供调用方直接渲染。 */
export function selectAssets(assets, store, watchOnly, keyOf) {
  const key = keyOf || ((asset) => asset && asset.symbol);
  const watched = store ? store.list() : [];
  const ordered = watched.length ? orderByWatchlist(assets, watched, key) : (assets || []);
  const shown = watchOnly && watched.length
    ? ordered.filter((asset) => store.has(key(asset)))
    : ordered;
  return { ordered, shown, count: watched.length };
}

/* 应用筛选入口状态，返回校正后的 watchOnly（自选清空时自动退出筛选）。 */
export function applyFilter(element, count, watchOnly, store) {
  const active = count > 0 && Boolean(watchOnly);
  if (!element) return active;
  const view = describeFilter(count, active, Boolean(store && store.persisted()));
  element.hidden = view.hidden;
  element.setAttribute("aria-pressed", view.pressed ? "true" : "false");
  element.textContent = view.label;
  element.title = view.title;
  return active;
}

/* 一次挂载：共用存储、接管本分区的筛选按钮并持有筛选状态，
   调用方只需 button() 与 select()。filterId 让不同分区各自挂自己的筛选入口。 */
export function mountWatchlist(document, view, onChange, options) {
  const settings = options || {};
  const store = sharedWatchlistStore(view);
  const filter = document.getElementById(settings.filterId || "watch-filter");
  let watchOnly = false;
  if (onChange) subscribeWatchlist(onChange);
  if (filter) {
    filter.addEventListener("click", () => {
      watchOnly = !watchOnly;
      if (onChange) onChange();
    });
  }
  return Object.freeze({
    store,
    button: (symbol) => createWatchButton(document, symbol, store, notifyWatchlist),
    select(assets) {
      const picked = selectAssets(assets, store, watchOnly);
      watchOnly = applyFilter(filter, picked.count, watchOnly, store);
      return picked;
    }
  });
}

export const WATCHLIST_STORAGE_KEY = STORAGE_KEY;
