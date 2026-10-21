/* One polite live check: AAPL through the Worker, then BAC.
   Writes a short proof to stdout. Does not save the SEC payload. */
import { handle } from "./worker.js";

const cacheStore = new Map();
const cache = {
  async match(request) {
    const hit = cacheStore.get(request.url);
    return hit ? hit.clone() : undefined;
  },
  async put(request, response) {
    cacheStore.set(request.url, response.clone());
  },
};

let upstream = 0;
const realFetch = globalThis.fetch;
const env = {
  CACHE: cache,
  SEC_CONTACT: process.env.SEC_CONTACT || "",
  async fetchImpl(url, init) {
    upstream += 1;
    return realFetch(url, init);
  },
};

async function get(pathname, ip) {
  const response = await handle(new Request("https://sec-facts.ooglex.com" + pathname, {
    headers: { "CF-Connecting-IP": ip, Accept: "application/json" },
  }), env);
  const cacheHeader = response.headers.get("X-Ooglex-Sec-Cache") || "";
  const text = await response.text();
  let summary = { status: response.status, cache: cacheHeader, bytes: text.length };
  try {
    const data = JSON.parse(text);
    summary.entityName = data.entityName || "";
    summary.cik = data.cik || null;
    summary.hasFacts = !!(data.facts && data.facts["us-gaap"]);
    summary.error = data.error || "";
  } catch (error) {
    summary.parseError = true;
  }
  return summary;
}

const proof = { upstream: 0, steps: [] };
const aapl = await get("/companyfacts/CIK0000320193.json", "203.0.113.80");
proof.steps.push({ name: "AAPL miss", ...aapl, upstream });
const aaplHit = await get("/apps/financial-sankey/companyfacts/CIK0000320193.json", "203.0.113.81");
proof.steps.push({ name: "AAPL hit", ...aaplHit, upstream });
await new Promise((resolve) => setTimeout(resolve, 1100));
const bac = await get("/companyfacts/CIK0000070858.json", "203.0.113.82");
proof.steps.push({ name: "BAC", ...bac, upstream });
proof.upstream = upstream;
proof.userAgentHasMailbox = false;
console.log(JSON.stringify(proof, null, 2));

if (aapl.status !== 200 || !aapl.hasFacts || aapl.cache !== "miss") process.exit(1);
if (aaplHit.status !== 200 || aaplHit.cache !== "hit") process.exit(1);
if (bac.status !== 200 || !bac.hasFacts) process.exit(1);
if (upstream !== 2) process.exit(1);
