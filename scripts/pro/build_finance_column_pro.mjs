#!/usr/bin/env node
/**
 * Build protected Finance Column payloads.
 *
 * Source stays in the repository for authoring. Production Pages receives only
 * generated ~10% same-schema JS previews; OWNER/PRO full objects are uploaded
 * to private R2 and returned through the entitlement Worker.
 */
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "../..");
const OUT = path.join(ROOT, ".pro-build");
const RICH = path.join(OUT, "rich-preview", "finance-column");
const RATIO = 0.10;

function readDataObject(rel, symbol) {
  const source = fs.readFileSync(path.join(ROOT, rel), "utf8");
  const sandbox = { window: {} };
  vm.createContext(sandbox);
  vm.runInContext(
    source + "\n;globalThis.__OOGLEX_EXPORT__ = " + symbol + ";",
    sandbox,
    { filename: rel, timeout: 2000 }
  );
  return JSON.parse(JSON.stringify(sandbox.__OOGLEX_EXPORT__));
}

function writeJson(rel, obj) {
  const target = path.join(OUT, rel);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, JSON.stringify(obj), "utf8");
  console.log("wrote", path.relative(ROOT, target));
}

function writeText(target, value) {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, value, "utf8");
  console.log("wrote", path.relative(ROOT, target));
}

function countTerms(arch) {
  return (arch.layers || []).reduce(
    (sum, layer) => sum + (layer.modules || []).reduce(
      (m, mod) => m + (mod.terms || []).length, 0
    ), 0
  );
}

function buildArchPreview(full) {
  const source = JSON.parse(JSON.stringify(full));
  const modules = [];
  for (const layer of source.layers || []) {
    for (const mod of layer.modules || []) {
      modules.push(mod);
    }
  }

  const fullTerms = countTerms(source);
  for (const layer of source.layers || []) {
    layer.ooglexFullTerms = (layer.modules || []).reduce(
      (sum, mod) => sum + (mod.terms || []).length, 0
    );
    for (const mod of layer.modules || []) {
      mod.ooglexFullTerms = (mod.terms || []).length;
    }
  }
  const target = Math.max(1, Math.ceil(fullTerms * RATIO));

  // Keep the entire 8-layer / 48-module map visible, but reveal only ~10% of
  // the detailed term rows. Give each module one representative term first,
  // then distribute the remaining preview budget in source order.
  let remaining = target;
  for (const mod of modules) {
    const rows = Array.isArray(mod.terms) ? mod.terms : [];
    const keep = rows.length && remaining > 0 ? 1 : 0;
    mod.__previewSourceTerms = rows;
    mod.terms = rows.slice(0, keep);
    remaining -= keep;
  }
  while (remaining > 0) {
    let progressed = false;
    for (const mod of modules) {
      if (remaining <= 0) break;
      const sourceRows = mod.__previewSourceTerms || [];
      if (mod.terms.length < sourceRows.length) {
        mod.terms.push(sourceRows[mod.terms.length]);
        remaining -= 1;
        progressed = true;
      }
    }
    if (!progressed) break;
  }
  for (const mod of modules) delete mod.__previewSourceTerms;

  const visibleTerms = countTerms(source);
  source.ooglexAccess = {
    mode: "preview",
    ratio: RATIO,
    presentation: "architecture-paywall",
    visibleTerms,
    fullTerms
  };
  return source;
}

function countDiagrams(diagrams) {
  return (diagrams.groups || []).reduce(
    (sum, group) => sum + (group.items || []).length, 0
  );
}

function buildDiagramPreview(full) {
  const source = JSON.parse(JSON.stringify(full));
  const fullDiagrams = countDiagrams(source);
  const target = Math.max(1, Math.ceil(fullDiagrams * RATIO));

  // Select round-robin across groups so the preview is representative rather
  // than exposing the first topic cluster only.
  const groups = source.groups || [];
  const cursors = groups.map(() => 0);
  const selected = groups.map(() => []);
  let remaining = target;

  while (remaining > 0) {
    let progressed = false;
    for (let i = 0; i < groups.length && remaining > 0; i += 1) {
      const items = groups[i].items || [];
      if (cursors[i] < items.length) {
        selected[i].push(items[cursors[i]]);
        cursors[i] += 1;
        remaining -= 1;
        progressed = true;
      }
    }
    if (!progressed) break;
  }

  source.groups = groups
    .map((group, i) => ({ ...group, items: selected[i] }))
    .filter((group) => group.items.length > 0);

  const visibleDiagrams = countDiagrams(source);
  source.ooglexAccess = {
    mode: "preview",
    ratio: RATIO,
    presentation: "diagram-paywall",
    visibleDiagrams,
    fullDiagrams
  };
  return source;
}

function archJs(arch) {
  return [
    "/* Generated safe Finance Column preview. Do not edit directly. */",
    "const ARCH = " + JSON.stringify(arch) + ";",
    "ARCH.findLayer = function (id) { return this.layers.find((l) => l.id === id) || null; };",
    "ARCH.moduleCount = function () { return this.layers.reduce((n, l) => n + l.modules.length, 0); };",
    "ARCH.termCount = function () { return this.layers.reduce((n, l) => n + l.modules.reduce((m, mod) => m + mod.terms.length, 0), 0); };",
    "ARCH.layerTermCount = function (layer) { return layer.modules.reduce((m, mod) => m + mod.terms.length, 0); };",
    "ARCH.flatTerms = function () { const out = []; this.layers.forEach((l) => l.modules.forEach((mod) => mod.terms.forEach((t) => out.push({ cn:t[0], en:t[1], note:t[2]||'', layer:l, module:mod })))); return out; };",
    "if (typeof window !== 'undefined') window.ARCH = ARCH;",
    ""
  ].join("\n");
}

function diagramsJs(diagrams) {
  return [
    "/* Generated safe Finance Column diagram preview. Do not edit directly. */",
    "const DIAGRAMS = " + JSON.stringify(diagrams) + ";",
    "DIAGRAMS.count = function () { return this.groups.reduce((n, g) => n + g.items.length, 0); };",
    "if (typeof window !== 'undefined') window.DIAGRAMS = DIAGRAMS;",
    ""
  ].join("\n");
}

const fullArch = readDataObject("apps/finance-column/arch.js", "ARCH");
const fullDiagrams = readDataObject("apps/finance-column/diagrams.js", "DIAGRAMS");
const previewArch = buildArchPreview(fullArch);
const previewDiagrams = buildDiagramPreview(fullDiagrams);

const preview = {
  schemaVersion: 1,
  product: "finance_column",
  mode: "preview",
  ratio: RATIO,
  arch: previewArch,
  diagrams: previewDiagrams
};
const full = {
  schemaVersion: 1,
  product: "finance_column",
  mode: "full",
  arch: fullArch,
  diagrams: fullDiagrams
};

writeJson("finance-column/preview.json", preview);
writeJson("finance-column/full.json", full);
writeText(path.join(RICH, "arch.js"), archJs(previewArch));
writeText(path.join(RICH, "diagrams.js"), diagramsJs(previewDiagrams));

console.log(
  "Finance Column preview:",
  previewArch.ooglexAccess.visibleTerms + "/" + previewArch.ooglexAccess.fullTerms,
  "terms;",
  previewDiagrams.ooglexAccess.visibleDiagrams + "/" + previewDiagrams.ooglexAccess.fullDiagrams,
  "diagrams"
);
