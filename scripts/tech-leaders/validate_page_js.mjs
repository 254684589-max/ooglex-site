import fs from "node:fs";
import vm from "node:vm";

const htmlPath = "apps/tech-leaders/index.html";
const catalogPath = "apps/tech-leaders/leaders.json";

const html = fs.readFileSync(htmlPath, "utf8");
const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
const leaders = Array.isArray(catalog) ? catalog : (catalog.leaders || catalog.people || []);

if (!Array.isArray(leaders) || leaders.length === 0) {
  throw new Error("Tech Leaders catalog is empty or invalid.");
}

const active = leaders.filter((p) => {
  const status = p.active_status || p.admission_status || "active";
  return status === "active";
});
if (active.length === 0) {
  throw new Error("Tech Leaders catalog has no active profiles.");
}

const heroMatch = html.match(/id=["']hero-account-count["'][^>]*>\s*(\d+)\s+公开账号/);
if (!heroMatch) {
  throw new Error("hero-account-count marker is missing.");
}
const heroCount = Number(heroMatch[1]);
if (heroCount !== active.length) {
  throw new Error(`Hero count ${heroCount} does not match active catalog count ${active.length}.`);
}

const routeStart = html.indexOf('var CATALOG_URL="./leaders.json"');
if (routeStart < 0) {
  throw new Error("Catalog router is missing.");
}
const routeBlock = html.slice(routeStart, routeStart + 1800);
if (routeBlock.includes("\\n")) {
  throw new Error("Catalog router contains a literal \\n token; this breaks inline JavaScript parsing.");
}

const inlineScripts = [];
const scriptRe = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
let match;
while ((match = scriptRe.exec(html))) {
  const attrs = match[1] || "";
  const code = match[2] || "";
  if (/\bsrc\s*=/.test(attrs)) continue;
  const typeMatch = attrs.match(/\btype\s*=\s*["']([^"']+)["']/i);
  const type = typeMatch ? typeMatch[1].toLowerCase() : "";
  if (type && !["text/javascript", "application/javascript", "module"].includes(type)) continue;
  inlineScripts.push(code);
}

if (inlineScripts.length === 0) {
  throw new Error("No inline JavaScript found.");
}

inlineScripts.forEach((code, index) => {
  try {
    new vm.Script(code, { filename: `${htmlPath}#inline-${index + 1}` });
  } catch (error) {
    console.error(`Inline script ${index + 1} failed syntax validation.`);
    throw error;
  }
});

const ids = new Set();
const handles = new Set();
for (const p of active) {
  const id = String(p.id || "").trim();
  if (!id) throw new Error("Active profile missing id.");
  if (ids.has(id)) throw new Error(`Duplicate active id: ${id}`);
  ids.add(id);

  const handle = String(p.handle || "").trim().toLowerCase();
  if (handle) {
    if (handles.has(handle)) throw new Error(`Duplicate active handle: @${handle}`);
    handles.add(handle);
  }
}

console.log(JSON.stringify({
  status: "pass",
  inline_scripts_checked: inlineScripts.length,
  catalog_count: leaders.length,
  active_count: active.length,
  hero_count: heroCount
}, null, 2));
