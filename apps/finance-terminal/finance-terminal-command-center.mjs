import { initMarketGlobe } from "./finance-terminal-globe.mjs";

const DESKTOP_QUERY = "(min-width: 1041px)";
const VIEW_BY_ID = Object.freeze({
  "overview-section": "overview",
  "market-section": "market",
  "board-section": "board",
  "risk-section": "risk",
  "research-section": "research",
  "information-section": "information",
  "operations-section": "operations",
  "method-section": "method"
});

const body = document.body;
const desktop = window.matchMedia(DESKTOP_QUERY);
const navigation = Array.from(document.querySelectorAll(".section-nav a, .terminal-rail a"));

function viewFromHash(hash = window.location.hash) {
  return VIEW_BY_ID[String(hash).replace(/^#/, "")] || "overview";
}

function updateCurrentLinks(view) {
  navigation.forEach((link) => {
    const current = viewFromHash(link.hash) === view;
    if (current) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  });
}

function applyView(view, shouldScroll = false) {
  const next = Object.values(VIEW_BY_ID).includes(view) ? view : "overview";
  body.dataset.terminalView = next;
  updateCurrentLinks(next);
  if (!desktop.matches || !shouldScroll) return;
  window.requestAnimationFrame(() => {
    if (next === "overview") {
      window.scrollTo({ top: 0, behavior: "auto" });
      return;
    }
    const targetId = Object.keys(VIEW_BY_ID).find((id) => VIEW_BY_ID[id] === next);
    document.getElementById(targetId)?.scrollIntoView({ block: "start", behavior: "auto" });
  });
}

navigation.forEach((link) => {
  link.addEventListener("click", (event) => {
    if (!desktop.matches) return;
    const view = viewFromHash(link.hash);
    event.preventDefault();
    if (window.location.hash !== link.hash) window.history.pushState(null, "", link.hash);
    applyView(view, true);
  });
});

window.addEventListener("popstate", () => applyView(viewFromHash(), true));
/* 面板入口用 hash 跳转。点击 hash 链接只触发 hashchange 而不触发 popstate，
   少了这一条，导航栏以外的入口点下去地址变了、视图却不动。 */
window.addEventListener("hashchange", () => applyView(viewFromHash(), true));
desktop.addEventListener("change", () => applyView(viewFromHash(), desktop.matches));
applyView(viewFromHash());
initMarketGlobe({ document, window });
