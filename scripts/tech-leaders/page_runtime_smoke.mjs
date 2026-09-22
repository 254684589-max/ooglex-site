import fs from "node:fs";
import { JSDOM } from "jsdom";

const htmlPath = "apps/tech-leaders/index.html";
const catalogPath = "apps/tech-leaders/leaders.json";

const html = fs.readFileSync(htmlPath, "utf8");
const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
const leaders = Array.isArray(catalog) ? catalog : (catalog.leaders || catalog.people || []);
if (!leaders.length) throw new Error("Catalog is empty.");

const preferred = leaders.find((p) =>
  String(p.handle || "").toLowerCase() === "elonmusk" &&
  (p.admission_status || p.active_status || "active") === "active"
) || leaders.find((p) =>
  p.handle &&
  (p.admission_status || p.active_status || "active") === "active" &&
  (p.x_identity_verified === true || p.verified_personal_x === true || String(p.note || "").includes("个人公开 X 账号"))
) || leaders[0];

const url = new URL("https://www.ooglex.com/apps/tech-leaders/");
url.searchParams.set("leader", preferred.id || "");
url.searchParams.set("sharev", "smoke");

const dom = new JSDOM(html, {
  url: url.toString(),
  runScripts: "outside-only",
  pretendToBeVisual: true
});
const { window } = dom;

const errors = [];
window.addEventListener("error", (event) => {
  errors.push(event.error || event.message || "window_error");
});
window.addEventListener("unhandledrejection", (event) => {
  errors.push(event.reason || "unhandled_rejection");
});

window.requestAnimationFrame = window.requestAnimationFrame || ((cb) => setTimeout(() => cb(Date.now()), 0));
window.cancelAnimationFrame = window.cancelAnimationFrame || ((id) => clearTimeout(id));
window.scrollTo = () => {};
window.HTMLElement.prototype.scrollIntoView = function () {};
window.HTMLElement.prototype.setPointerCapture = function () {};
window.HTMLElement.prototype.releasePointerCapture = function () {};
if (!window.matchMedia) {
  window.matchMedia = () => ({
    matches: false,
    media: "",
    onchange: null,
    addListener() {},
    removeListener() {},
    addEventListener() {},
    removeEventListener() {},
    dispatchEvent() { return false; }
  });
}

const fakePost = {
  id: "9999999999999999999",
  text: "Tech Leaders runtime smoke test",
  created_at: new Date().toISOString(),
  url: "https://x.com/ooglex/status/9999999999999999999",
  post_type: "post",
  metrics: { reply_count: 0, repost_count: 0, like_count: 0 },
  entities: { urls: [] },
  media: []
};

window.fetch = async (input) => {
  const value = String(input && input.url ? input.url : input);
  if (value.includes("leaders.json")) {
    return {
      ok: true,
      status: 200,
      json: async () => catalog,
      text: async () => JSON.stringify(catalog)
    };
  }
  if (value.includes("/v1/tech-leaders/free-feed")) {
    return {
      ok: true,
      status: 200,
      json: async () => ({
        uses_x_api: false,
        posts: [fakePost],
        requested_limit: 10
      }),
      text: async () => JSON.stringify({ uses_x_api: false, posts: [fakePost] })
    };
  }
  if (value.includes("/v1/tech-leaders/profile")) {
    return {
      ok: true,
      status: 200,
      json: async () => ({
        profile: {
          followers_count: 1,
          following_count: 1,
          created_at: "2009-06-01T00:00:00Z"
        }
      }),
      text: async () => "{}"
    };
  }
  return {
    ok: false,
    status: 404,
    json: async () => ({}),
    text: async () => ""
  };
};

const scripts = [...window.document.querySelectorAll("script:not([src])")];
const mainScript = scripts.map((node) => node.textContent || "").find((code) => code.includes('var API_BASE="https://pro-api.ooglex.com"'));
if (!mainScript) throw new Error("Main Tech Leaders inline script not found.");

window.eval(mainScript);

await new Promise((resolve) => setTimeout(resolve, 250));

if (errors.length) {
  throw new Error("Runtime errors: " + errors.map(String).join(" | "));
}

const cards = window.document.querySelectorAll("#leaders .leader");
if (cards.length === 0) {
  throw new Error("Leader rail did not render.");
}

const profile = window.document.querySelector(".profile");
const preferredName = preferred.name_zh || preferred.zh || preferred.name_en || preferred.name || "";
if (!profile || (preferredName && !profile.textContent.includes(preferredName))) {
  throw new Error("Selected leader profile did not render.");
}

const timeline = window.document.getElementById("timeline");
if (!timeline) throw new Error("Timeline mount is missing.");
if (!timeline.querySelector(".post-card") && timeline.getAttribute("data-state") !== "ready") {
  throw new Error("Timeline did not reach a rendered/ready state.");
}

const hero = window.document.getElementById("hero-account-count");
const activeCount = leaders.filter((p) => (p.active_status || p.admission_status || "active") === "active").length;
if (!hero || !hero.textContent.includes(String(activeCount))) {
  throw new Error("Hero account count did not synchronize with catalog.");
}

console.log(JSON.stringify({
  status: "pass",
  selected_id: preferred.id,
  selected_handle: preferred.handle,
  rendered_leader_cards: cards.length,
  timeline_state: timeline.getAttribute("data-state"),
  post_cards: timeline.querySelectorAll(".post-card").length,
  active_count: activeCount
}, null, 2));

dom.window.close();
