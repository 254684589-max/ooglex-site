/* 盘中活更新：把跨资产管道的盘中快照覆盖到已经画出来的行上，并在数值真的变了时闪一下。

   两条铁律：
   1. 闪动只由「取到的新数值与当前显示不同」触发。绝不做定时抖动——那等于伪造实时。
   2. 覆盖只发生在盘中报价确实比页面上那条更新时；盘中文件过期、缺这个标的、
      或者取数失败，就原样保留日更读数，并把状态如实写出来。 */

const DEFAULT_INTERVAL_MS = 20000;      // 页面轮询间隔：快到「看得见在动」，又不至于空转
const MAX_AGE_MINUTES = 90;             // 盘中文件超过这个岁数就不再覆盖，只显示日更值

export function isFiniteNumber(value) {
  return typeof value === "number" && Number.isFinite(value);
}

/* 纯函数：相对时间。刻意只到秒/分/小时，不做「刚刚」这种模糊说法。 */
export function freshnessText(updatedAt, now) {
  const moment = Date.parse(String(updatedAt || ""));
  if (!Number.isFinite(moment)) return "更新时间不可用";
  const seconds = Math.max(0, Math.round((now - moment) / 1000));
  if (seconds < 60) return `更新于 ${seconds} 秒前`;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `更新于 ${minutes} 分钟前`;
  return `更新于 ${Math.round(minutes / 60)} 小时前`;
}

export function ageMinutes(updatedAt, now) {
  const moment = Date.parse(String(updatedAt || ""));
  if (!Number.isFinite(moment)) return Infinity;
  return (now - moment) / 60000;
}

/* 纯函数：这份盘中快照现在还能不能用来覆盖显示。 */
export function usableSnapshot(snapshot, now) {
  if (!snapshot || snapshot.realtime !== false) return false;
  if (!snapshot.quotes || typeof snapshot.quotes !== "object") return false;
  return ageMinutes(snapshot.updatedAt, now) <= MAX_AGE_MINUTES;
}

/* 纯函数：某个标的的盘中报价是否比页面上那条更新。缺时点就按「不更新」处理，
   宁可继续显示日更值，也不拿一条来路不明的报价盖掉它。 */
export function newerThan(quote, currentAsOf) {
  if (!quote || !isFiniteNumber(quote.price)) return false;
  const quoteMoment = Date.parse(String(quote.asOf || ""));
  if (!Number.isFinite(quoteMoment)) return false;
  const currentMoment = Date.parse(String(currentAsOf || ""));
  if (!Number.isFinite(currentMoment)) return true;
  return quoteMoment > currentMoment;
}

/* 纯函数：格式化盘中价，位数跟随该标的原本的显示位数，避免同一行忽然多出两位小数。 */
export function formatLike(sample, value) {
  const text = String(sample || "");
  const dot = text.indexOf(".");
  const decimals = dot === -1 ? 2 : text.length - dot - 1;
  return value.toLocaleString("en-US", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals
  });
}

export function formatChangePct(value) {
  const rounded = Math.round(value * 100) / 100;
  const direction = rounded > 0 ? "up" : (rounded < 0 ? "down" : "flat");
  return {
    direction,
    arrow: direction === "up" ? "▲" : (direction === "down" ? "▼" : "▬"),
    text: `${rounded > 0 ? "+" : ""}${rounded.toFixed(2)}%`
  };
}

/* 闪一下：加类、下一帧移除，靠 CSS 过渡完成。数值没变就什么都不做。 */
function flash(node, direction) {
  if (!node) return;
  node.classList.remove("live-tick-up", "live-tick-down");
  void node.offsetWidth;
  node.classList.add(direction === "down" ? "live-tick-down" : "live-tick-up");
  window.setTimeout(() => { node.classList.remove("live-tick-up", "live-tick-down"); }, 900);
}

/* 把一条盘中报价写到一行上；返回是否真的改动了显示。 */
export function applyQuoteToRow(row, quote) {
  const priceCell = row.querySelector(".board-cell-price");
  const changeCell = row.querySelector(".board-cell-change");
  if (!priceCell || !changeCell) return false;
  const nextPrice = formatLike(row.dataset.livePrice || priceCell.textContent, quote.price);
  const nextChange = formatChangePct(quote.changePct);
  const currentPrice = (row.dataset.livePrice || priceCell.textContent || "").trim();
  if (currentPrice === nextPrice) return false;
  const rising = !currentPrice || Number(String(nextPrice).replace(/,/g, ""))
    >= Number(String(currentPrice).replace(/,/g, ""));

  const currency = priceCell.querySelector(".board-cell-currency");
  priceCell.textContent = nextPrice;
  if (currency) priceCell.appendChild(currency);
  row.dataset.livePrice = nextPrice;

  const arrow = changeCell.querySelector(".board-arrow");
  const body = changeCell.querySelector("b");
  if (arrow) arrow.textContent = nextChange.arrow;
  if (body) body.textContent = nextChange.text;
  row.classList.remove("board-change-up", "board-change-down", "board-change-flat", "board-change-unknown");
  row.classList.add(`board-change-${nextChange.direction}`);
  row.dataset.liveApplied = "1";
  flash(priceCell, rising ? "up" : "down");
  return true;
}

/* 把整份快照覆盖到当前 DOM 上，返回本次真正改动了多少行。 */
export function applySnapshot(root, snapshot, now) {
  if (!usableSnapshot(snapshot, now)) return { applied: 0, covered: 0, usable: false };
  const rows = Array.from(root.querySelectorAll(".board-row[data-live-symbol]"));
  let applied = 0;
  let covered = 0;
  rows.forEach((row) => {
    const quote = snapshot.quotes[row.dataset.liveSymbol];
    if (!quote || !newerThan(quote, row.dataset.liveAsof)) return;
    covered += 1;
    if (applyQuoteToRow(row, quote)) applied += 1;
  });
  return { applied, covered, usable: true };
}

/* 状态条：把「这份盘中快照有多新、覆盖了多少行、能不能用」如实写出来。
   它是页面上唯一声称「盘中」的地方，措辞固定为非实时。 */
export function paintLiveState(host, state) {
  if (!host) return;
  if (!state || state.error) {
    host.hidden = false;
    host.dataset.liveState = "error";
    host.textContent = "";
    host.appendChild(host.ownerDocument.createElement("i"));
    host.appendChild(host.ownerDocument.createTextNode("盘中快照读取失败 · 显示日更收盘值"));
    return;
  }
  const snapshot = state.snapshot;
  if (!state.usable || !snapshot) {
    host.hidden = false;
    host.dataset.liveState = "stale";
    host.textContent = "";
    host.appendChild(host.ownerDocument.createElement("i"));
    host.appendChild(host.ownerDocument.createTextNode("盘中快照已过期 · 显示日更收盘值"));
    return;
  }
  const cadence = Number.isInteger(snapshot.cadenceMinutes) ? snapshot.cadenceMinutes : null;
  host.hidden = false;
  host.dataset.liveState = "live";
  host.textContent = "";
  host.appendChild(host.ownerDocument.createElement("i"));
  host.appendChild(host.ownerDocument.createTextNode(
    `盘中 ${state.covered} 项 · ${freshnessText(snapshot.updatedAt, state.now)}`
    + (cadence ? ` · 约${cadence}分钟一刷，非实时` : " · 非实时")));
  host.title = String(snapshot.note || "");
}

/* 轮询：只重取盘中那一份小文件（约几KB），不重取整套日更快照。
   页面不可见时不轮询——后台标签页没有必要一直发请求。 */
export function startLive(options = {}) {
  const path = options.path || "../asset-tracker/intraday.json";
  const interval = options.intervalMs || DEFAULT_INTERVAL_MS;
  const root = options.root || document;
  const onState = typeof options.onState === "function" ? options.onState : () => {};
  let timer = null;
  let stopped = false;

  async function tick() {
    if (stopped) return;
    try {
      const response = await fetch(path, { cache: "no-store" });
      if (!response || response.ok !== true) throw new Error(`HTTP ${response && response.status}`);
      const snapshot = await response.json();
      const now = Date.now();
      const result = applySnapshot(root, snapshot, now);
      onState({ snapshot, now, ...result, error: null });
    } catch (error) {
      onState({ snapshot: null, now: Date.now(), applied: 0, covered: 0, usable: false, error });
    }
  }

  function schedule() {
    window.clearTimeout(timer);
    timer = window.setTimeout(async () => {
      if (document.visibilityState === "visible") await tick();
      schedule();
    }, interval);
  }

  tick();
  schedule();
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") tick();
  });
  return { stop() { stopped = true; window.clearTimeout(timer); } };
}
