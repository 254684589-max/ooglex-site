const DESKTOP_QUERY = "(min-width: 1041px)";
const VIEW_BY_ID = Object.freeze({
  "overview-section": "overview",
  "market-section": "market",
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
desktop.addEventListener("change", () => applyView(viewFromHash(), desktop.matches));
applyView(viewFromHash());
