/* 「全球市场行情」独立页：与金融终端「专业模式」里的品类行情共用同一份数据层与视图，
   只是换了个自己的页面外壳与统计条。行情事实一条也不在这里重算——六大品类仍然只读
   站内每日运行的公开管道快照，缺什么就如实说缺什么。 */

import { buildBoard } from "../finance-terminal/finance-terminal-board-data.mjs";
import { createBoardView } from "../finance-terminal/finance-terminal-board-view.mjs";
import { paintLiveState, startLive } from "../finance-terminal/finance-terminal-live.mjs";

/* 与金融终端 board 资源组同一份清单：同样的六份文件、同样的相对路径深度。 */
const SOURCES = Object.freeze({
  assetTracker: "../asset-tracker/data.json",
  assetRanking: "../asset-ranking/data.json",
  assetRankingCrypto: "../asset-ranking/crypto.json",
  companies: "../companies/data.json",
  macro: "../macro-radar/data.json",
  macroCurve: "../macro-radar/curve.json",
  commodities: "../commodities/data.json"
});

/* 可选文件缺失不算管线故障：加密快照首次生成前就属于这种情况。 */
const OPTIONAL = Object.freeze(["assetRankingCrypto", "commodities"]);

function loadOne(key, path) {
  return fetch(path, { cache: "no-store" }).then((response) => {
    if (!response || response.ok !== true) throw new Error(`HTTP ${response && response.status}`);
    return response.json();
  }).then((data) => [key, { data, error: null }])
    .catch((error) => [key, OPTIONAL.includes(key) ? null : { data: null, error }]);
}

function text(id, value) {
  const node = document.getElementById(id);
  if (node) node.textContent = value;
}

/* 统计条只汇总本页已经画出来的行，不引入第二套口径。 */
function paintStats(board) {
  text("stat-total", String(board.total));
  text("stat-categories", String(board.categories.filter((category) => category.rows.length).length));
  /* 二级分组目前只有商品这一类有；统计的是「今天真的有行的组」，不是登记了几组。 */
  const grouped = board.categories.filter((category) => (category.groups || []).length);
  const groups = grouped.reduce((sum, category) => sum + category.groups.length, 0);
  text("stat-groups", groups ? `${groups} 组` : "不可用");
  const rows = board.categories.flatMap((category) => category.rows);
  const dates = rows.map((row) => row.asOf).filter(Boolean).sort();
  const oldest = dates[0] || "";
  const newest = dates[dates.length - 1] || "";
  text("stat-asof", newest ? (oldest === newest ? newest : `${oldest} ~ ${newest}`) : "不可用");
  const up = rows.filter((row) => row.change.direction === "up").length;
  const down = rows.filter((row) => row.change.direction === "down").length;
  text("stat-breadth", `▲${up} ▼${down}`);
  const sources = rows.map((row) => row.sourceName).filter(Boolean)
    .filter((name, index, list) => list.indexOf(name) === index);
  text("stat-sources", sources.length ? String(sources.length) + " 家" : "不可用");
  const box = document.getElementById("markets-stats");
  if (box) box.title = sources.join(" · ");
}

async function start() {
  const entries = await Promise.all(Object.keys(SOURCES).map((key) => loadOne(key, SOURCES[key])));
  const group = {};
  entries.forEach(([key, value]) => { if (value) group[key] = value; });
  const board = buildBoard(group);
  createBoardView(document, window).render(board);
  paintStats(board);
  /* 盘中快照只覆盖跨资产管道的行，且必须比行上显示的数据日更新才会生效；
     取不到或过期就原样保留日更读数，并在状态条里说明。 */
  const live = document.getElementById("board-live");
  startLive({
    path: "../asset-tracker/intraday.json",
    onState: (state) => { paintLiveState(live, state); }
  });
}

start().catch((error) => {
  const panel = document.getElementById("board-panel");
  if (!panel) return;
  panel.setAttribute("aria-busy", "false");
  panel.textContent = "";
  const note = document.createElement("p");
  note.className = "board-empty";
  note.textContent = `暂时读不到站内行情快照：${error && error.message ? error.message : "未知错误"}。`
    + "页面不会用旧值或演示值顶替，管道恢复后刷新即可。";
  panel.appendChild(note);
});
