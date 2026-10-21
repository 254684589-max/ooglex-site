import assert from "node:assert/strict";
import test from "node:test";
import {
  LIMITS,
  consumeIp,
  consumeUpstream,
  createLimiterState,
  handle,
  matchCik,
  originAllowed,
  resetLimiter,
  secUserAgent,
  upstreamUrl,
} from "./worker.js";

function memoryCache() {
  const store = new Map();
  return {
    async match(request) {
      const hit = store.get(request.url);
      return hit ? hit.clone() : undefined;
    },
    async put(request, response) {
      store.set(request.url, response.clone());
    },
  };
}

function jsonFacts(cik) {
  return new Response(JSON.stringify({ cik: Number(cik), entityName: "Example", facts: { "us-gaap": {} } }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

test("only the 10-digit companyfacts path matches", () => {
  assert.equal(matchCik("/companyfacts/CIK0000320193.json"), "0000320193");
  assert.equal(matchCik("/apps/financial-sankey/companyfacts/CIK0000070858.json"), "0000070858");
  [
    "/companyfacts/CIK320193.json",
    "/companyfacts/CIK00003201930.json",
    "/companyfacts/CIK0000320193.JSON",
    "/companyfacts/CIK0000320193.json.txt",
    "/companyfacts/CIK0000320193.json/extra",
    "/api/xbrl/companyfacts/CIK0000320193.json",
    "/submissions/CIK0000320193.json",
    "/companyfacts/%2e%2e/CIK0000320193.json",
    "/?url=https://data.sec.gov/api/xbrl/companyfacts/CIK0000320193.json",
  ].forEach((path) => assert.equal(matchCik(path), null, path));
});

test("upstream URL is the single SEC companyfacts address", () => {
  assert.equal(
    upstreamUrl("0000320193"),
    "https://data.sec.gov/api/xbrl/companyfacts/CIK0000320193.json"
  );
});

test("user agent names the site and does not embed a mailbox", () => {
  const fallback = secUserAgent({});
  assert.match(fallback, /Ooglex financial-sankey/);
  assert.match(fallback, /https:\/\/www\.ooglex\.com\/apps\/financial-sankey\//);
  assert.equal(fallback.includes("@"), false);
  const custom = secUserAgent({ SEC_CONTACT: "desk@example.invalid\r\nX-Injected: 1" });
  assert.match(custom, /desk@example\.invalid/);
  assert.equal(custom.includes("\n"), false);
  assert.equal(custom.includes("\r"), false);
});

test("origin allow list is the site plus local dev", () => {
  assert.equal(originAllowed("", {}), true);
  assert.equal(originAllowed("https://www.ooglex.com", {}), true);
  assert.equal(originAllowed("https://ooglex.com", {}), true);
  assert.equal(originAllowed("http://127.0.0.1:8765", {}), true);
  assert.equal(originAllowed("http://localhost:4173", {}), true);
  assert.equal(originAllowed("https://evil.example", {}), false);
});

test("per-IP and upstream limits trip", () => {
  const state = createLimiterState();
  const t0 = Date.parse("2026-10-21T00:00:00Z");
  for (let i = 0; i < LIMITS.perIpPerMinute; i += 1) {
    assert.equal(consumeIp(state, "203.0.113.8", t0 + i, LIMITS).ok, true);
  }
  assert.equal(consumeIp(state, "203.0.113.8", t0 + 50, LIMITS).ok, false);
  assert.equal(consumeIp(state, "203.0.113.9", t0 + 50, LIMITS).ok, true);

  const upstream = createLimiterState();
  assert.equal(consumeUpstream(upstream, t0, LIMITS).ok, true);
  const blocked = consumeUpstream(upstream, t0 + 10, LIMITS);
  assert.equal(blocked.ok, false);
  assert.equal(blocked.scope, "upstream_gap");
  assert.equal(consumeUpstream(upstream, t0 + LIMITS.upstreamGapMs, LIMITS).ok, true);
});

test("daily cap is independent of the minute window", () => {
  const state = createLimiterState();
  const start = Date.parse("2026-10-21T12:00:00Z");
  state.ips.set("203.0.113.10", {
    day: "2026-10-21",
    dayCount: LIMITS.perIpPerDay,
    minute: [],
  });
  const denied = consumeIp(state, "203.0.113.10", start, LIMITS);
  assert.equal(denied.ok, false);
  assert.equal(denied.scope, "ip_day");
});

test("handler forwards only companyfacts and caches the SEC body", async () => {
  resetLimiter();
  const calls = [];
  const cache = memoryCache();
  const env = {
    CACHE: cache,
    buckets: createLimiterState(),
    now: () => Date.parse("2026-10-21T12:00:00Z"),
    fetchImpl(url, init) {
      calls.push({ url: String(url), init });
      assert.equal(init.redirect, "manual");
      assert.match(init.headers["User-Agent"], /Ooglex financial-sankey/);
      assert.equal(init.headers["User-Agent"].includes("@"), false);
      return jsonFacts("0000320193");
    },
  };
  const first = await handle(new Request("https://sec-facts.ooglex.com/companyfacts/CIK0000320193.json", {
    headers: { Origin: "https://www.ooglex.com", "CF-Connecting-IP": "203.0.113.20" },
  }), env);
  assert.equal(first.status, 200);
  assert.equal(first.headers.get("Access-Control-Allow-Origin"), "https://www.ooglex.com");
  assert.equal(first.headers.get("X-Ooglex-Sec-Cache"), "miss");
  const body = await first.json();
  assert.equal(body.entityName, "Example");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://data.sec.gov/api/xbrl/companyfacts/CIK0000320193.json");

  env.now = () => Date.parse("2026-10-21T12:00:02Z");
  const second = await handle(new Request("https://www.ooglex.com/apps/financial-sankey/companyfacts/CIK0000320193.json", {
    headers: { Origin: "https://www.ooglex.com", "CF-Connecting-IP": "203.0.113.21" },
  }), env);
  assert.equal(second.status, 200);
  assert.equal(second.headers.get("X-Ooglex-Sec-Cache"), "hit");
  assert.equal(calls.length, 1);
  await second.json();
});

test("rejected paths and origins never call SEC", async () => {
  resetLimiter();
  let called = 0;
  const env = {
    buckets: createLimiterState(),
    now: () => Date.parse("2026-10-21T12:00:00Z"),
    fetchImpl() {
      called += 1;
      return jsonFacts("0000320193");
    },
  };
  const bad = await handle(new Request("https://sec-facts.ooglex.com/?url=https://data.sec.gov/api/xbrl/companyfacts/CIK0000320193.json"), env);
  assert.equal(bad.status, 404);
  const foreign = await handle(new Request("https://sec-facts.ooglex.com/companyfacts/CIK0000320193.json", {
    headers: { Origin: "https://evil.example" },
  }), env);
  assert.equal(foreign.status, 403);
  const post = await handle(new Request("https://sec-facts.ooglex.com/companyfacts/CIK0000320193.json", { method: "POST" }), env);
  assert.equal(post.status, 405);
  const health = await handle(new Request("https://sec-facts.ooglex.com/health"));
  assert.equal(health.status, 200);
  assert.equal(called, 0);
});

test("redirects and non-JSON upstreams are not passed through", async () => {
  resetLimiter();
  const env = {
    CACHE: memoryCache(),
    buckets: createLimiterState(),
    now: () => Date.parse("2026-10-21T12:00:00Z"),
    fetchImpl() {
      return new Response(null, { status: 302, headers: { Location: "https://evil.example/x" } });
    },
  };
  const redirected = await handle(new Request("https://sec-facts.ooglex.com/companyfacts/CIK0000320193.json", {
    headers: { "CF-Connecting-IP": "203.0.113.30" },
  }), env);
  assert.equal(redirected.status, 502);

  resetLimiter();
  env.buckets = createLimiterState();
  env.now = () => Date.parse("2026-10-21T12:10:00Z");
  env.fetchImpl = () => new Response("<html></html>", { status: 200, headers: { "Content-Type": "text/html" } });
  const html = await handle(new Request("https://sec-facts.ooglex.com/companyfacts/CIK0000320193.json", {
    headers: { "CF-Connecting-IP": "203.0.113.31" },
  }), env);
  assert.equal(html.status, 502);
});

test("upstream gap returns 429 without a second SEC request", async () => {
  resetLimiter();
  let called = 0;
  const env = {
    CACHE: memoryCache(),
    buckets: createLimiterState(),
    now: () => Date.parse("2026-10-21T13:00:00Z"),
    fetchImpl() {
      called += 1;
      const cik = called === 1 ? "0000320193" : "0000070858";
      return jsonFacts(cik);
    },
  };
  const first = await handle(new Request("https://sec-facts.ooglex.com/companyfacts/CIK0000320193.json", {
    headers: { "CF-Connecting-IP": "203.0.113.40" },
  }), env);
  assert.equal(first.status, 200);
  await first.json();
  const second = await handle(new Request("https://sec-facts.ooglex.com/companyfacts/CIK0000070858.json", {
    headers: { "CF-Connecting-IP": "203.0.113.41" },
  }), env);
  assert.equal(second.status, 429);
  assert.equal(called, 1);
  const payload = await second.json();
  assert.match(payload.message, /请稍后再试/);
});
