import assert from "node:assert/strict";
import test from "node:test";
import {
  LIMITS,
  consumeIp,
  createLimiterState,
  handle,
  originAllowed,
  parseQuery,
  trimTrack,
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

function rawTrack(id, extra) {
  return Object.assign({
    id: String(id),
    name: "Song " + id,
    duration: 201,
    artist_name: "Artist " + id,
    album_name: "Album " + id,
    image: "https://usercontent.jamendo.com?type=album&id=" + id + "&width=200",
    audio: "https://prod-1.storage.jamendo.com/?trackid=" + id + "&format=mp32",
    license_ccurl: "http://creativecommons.org/licenses/by-nc-sa/3.0/",
    shareurl: "https://www.jamendo.com/track/" + id,
  }, extra || {});
}

function upstreamOk(results) {
  return new Response(JSON.stringify({ headers: { status: "success", code: 0, results_count: results.length }, results: results }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

function env(extra) {
  return Object.assign({
    JAMENDO_CLIENT_ID: "test-client",
    CACHE: memoryCache(),
    buckets: createLimiterState(),
    now: () => Date.parse("2026-10-27T08:00:00Z"),
  }, extra || {});
}

function get(path, origin) {
  const headers = { "CF-Connecting-IP": "203.0.113.9" };
  if (origin !== null) headers.Origin = origin || "https://www.ooglex.com";
  return new Request("https://jamendo.example" + path, { headers: headers });
}

test("query params are validated and normalised", () => {
  const ok = (s) => parseQuery(new URLSearchParams(s));
  assert.deepEqual(ok(""), { tag: "", order: "popular", offset: 0, q: "", id: "" });
  assert.deepEqual(ok("tag=jazz&order=new&offset=40&q=%20moon%20"), { tag: "jazz", order: "new", offset: 40, q: "moon", id: "" });
  assert.deepEqual(ok("id=1932670&tag=pop&q=x"), { tag: "", order: "popular", offset: 0, q: "", id: "1932670" });
  [
    "tag=Jazz", "tag=hip-hop", "tag=a", "tag=" + "x".repeat(17),
    "order=random", "order=popularity_week",
    "offset=-20", "offset=7", "offset=1000", "offset=1e2",
    "q=" + "x".repeat(41),
    "id=0", "id=12a", "id=-5", "id=" + "9".repeat(13), "id=1%202",
  ].forEach((s) => assert.equal(ok(s), null, s));
});

test("upstream url carries the secret only server side and fixes page size", () => {
  const single = new URL(upstreamUrl({ tag: "", order: "popular", offset: 0, q: "", id: "77" }, "abc"));
  assert.equal(single.searchParams.get("id"), "77");
  assert.equal(single.searchParams.has("tags"), false);
  const url = new URL(upstreamUrl({ tag: "world", order: "week", offset: 20, q: "" }, "abc"));
  assert.equal(url.origin + url.pathname, "https://api.jamendo.com/v3.0/tracks/");
  assert.equal(url.searchParams.get("client_id"), "abc");
  assert.equal(url.searchParams.get("limit"), String(LIMITS.pageSize));
  assert.equal(url.searchParams.get("order"), "popularity_week");
  assert.equal(url.searchParams.get("tags"), "world");
  assert.equal(url.searchParams.has("search"), false);
});

test("tracks are trimmed; http licence links are upgraded; foreign hosts are dropped", () => {
  const t = trimTrack(rawTrack(7));
  assert.equal(t.license, "https://creativecommons.org/licenses/by-nc-sa/3.0/");
  assert.equal(t.durationSec, 201);
  assert.deepEqual(Object.keys(t).sort(), ["album", "artist", "durationSec", "id", "image", "license", "page", "src", "title"]);
  assert.equal(trimTrack(rawTrack(8, { audio: "https://evil.example/a.mp3" })), null);
  assert.equal(trimTrack(rawTrack(9, { audio: "javascript:alert(1)" })), null);
  assert.equal(trimTrack(rawTrack(10, { license_ccurl: "" })), null);
  assert.equal(trimTrack(rawTrack("x1")), null);
  assert.equal(trimTrack(rawTrack(11, { image: "https://notjamendo.com/x.jpg" })).image, "");
  assert.equal(trimTrack(rawTrack(12, { name: "a\u0000b" })).title, "a b");
});

test("origins: site and localhost only", () => {
  assert.equal(originAllowed("https://www.ooglex.com", {}), true);
  assert.equal(originAllowed("http://127.0.0.1:8765", {}), true);
  assert.equal(originAllowed("https://evil.example", {}), false);
  assert.equal(originAllowed("", {}), true);
});

test("ip limiter blocks after the per-minute budget", () => {
  const state = createLimiterState();
  const now = Date.parse("2026-10-27T08:00:00Z");
  for (let i = 0; i < LIMITS.perIpPerMinute; i++) assert.equal(consumeIp(state, "1.1.1.1", now, LIMITS).ok, true);
  assert.equal(consumeIp(state, "1.1.1.1", now, LIMITS).ok, false);
  assert.equal(consumeIp(state, "1.1.1.1", now + 61000, LIMITS).ok, true);
});

test("successful page is trimmed, cached, and served from cache next time", async () => {
  let calls = 0;
  const e = env({
    fetchImpl: async (url) => {
      calls++;
      assert.match(url, /client_id=test-client/);
      return upstreamOk(Array.from({ length: 20 }, (_, i) => rawTrack(i + 1)));
    },
  });
  const r1 = await handle(get("/tracks?tag=pop"), e);
  assert.equal(r1.status, 200);
  assert.equal(r1.headers.get("Access-Control-Allow-Origin"), "https://www.ooglex.com");
  assert.equal(r1.headers.get("X-Ooglex-Jamendo-Cache"), "miss");
  const b1 = await r1.json();
  assert.equal(b1.status, "ok");
  assert.equal(b1.source, "Jamendo");
  assert.equal(b1.tracks.length, 20);
  assert.equal(b1.hasMore, true);
  assert.equal(JSON.stringify(b1).includes("test-client"), false);
  const r2 = await handle(get("/tracks?tag=pop&order=popular&offset=0"), e);
  assert.equal(r2.headers.get("X-Ooglex-Jamendo-Cache"), "hit");
  assert.equal(calls, 1);
});

test("partial and empty pages are labelled", async () => {
  const partial = await handle(get("/tracks"), env({
    fetchImpl: async () => upstreamOk([rawTrack(1), rawTrack(2, { audio: "" })]),
  }));
  const pb = await partial.json();
  assert.equal(pb.status, "partial");
  assert.equal(pb.tracks.length, 1);
  assert.equal(pb.hasMore, false);
  const empty = await handle(get("/tracks?q=zzzz"), env({ fetchImpl: async () => upstreamOk([]) }));
  assert.equal((await empty.json()).status, "empty");
});

test("errors map to clear states without leaking upstream text or the secret", async () => {
  const notConfigured = await handle(get("/tracks"), env({ JAMENDO_CLIENT_ID: "" }));
  assert.equal(notConfigured.status, 503);
  assert.equal((await notConfigured.json()).error, "not_configured");

  const rejected = await handle(get("/tracks"), env({
    fetchImpl: async () => new Response(JSON.stringify({ headers: { status: "failed", code: 5, error_message: "client_id test-client invalid" }, results: [] }), { status: 200 }),
  }));
  assert.equal(rejected.status, 502);
  const rb = await rejected.text();
  assert.equal(rb.includes("test-client"), false);
  assert.match(rb, /代码 5/);

  const down = await handle(get("/tracks"), env({ fetchImpl: async () => { throw new Error("boom"); } }));
  assert.equal(down.status, 502);
  const slow = await handle(get("/tracks"), env({ fetchImpl: async () => { const e = new Error("t"); e.name = "TimeoutError"; throw e; } }));
  assert.equal((await slow.json()).error, "timeout");
  // 播放器每个地址等 20 秒（player.js API_WAIT_MS）。Worker 必须先结束，页面才不会把还在等的查询中止掉。
  assert.equal(LIMITS.timeoutMs, 15000);
  assert.ok(LIMITS.timeoutMs < 20000);
  const limited = await handle(get("/tracks"), env({ fetchImpl: async () => new Response("", { status: 429 }) }));
  assert.equal(limited.status, 429);
  const bad = await handle(get("/tracks"), env({ fetchImpl: async () => new Response("<html>", { status: 200 }) }));
  assert.equal(bad.status, 502);
});

test("routing, methods and origins are enforced", async () => {
  assert.equal((await handle(get("/tracks?tag=../x"), env())).status, 400);
  assert.equal((await handle(get("/other"), env())).status, 404);
  assert.equal((await handle(get("/tracks", "https://evil.example"), env())).status, 403);
  const post = new Request("https://jamendo.example/tracks", { method: "POST", headers: { Origin: "https://www.ooglex.com" } });
  assert.equal((await handle(post, env())).status, 405);
  const pre = new Request("https://jamendo.example/tracks", { method: "OPTIONS", headers: { Origin: "https://www.ooglex.com" } });
  assert.equal((await handle(pre, env())).status, 204);
  const health = await (await handle(get("/health"), env())).json();
  assert.deepEqual(health, { ok: true, proxy: "jamendo", configured: true });
});

test("an empty tag query retries once with fuzzytags", async () => {
  const seen = [];
  const res = await handle(get("/tracks?tag=hiphop"), env({
    fetchImpl: async (url) => {
      const u = new URL(url);
      seen.push(u.searchParams.has("tags") ? "tags" : u.searchParams.has("fuzzytags") ? "fuzzytags" : "none");
      return upstreamOk(u.searchParams.has("fuzzytags") ? [rawTrack(1), rawTrack(2)] : []);
    },
  }));
  const body = await res.json();
  assert.deepEqual(seen, ["tags", "fuzzytags"]);
  assert.equal(body.status, "ok");
  assert.equal(body.tracks.length, 2);
  assert.equal(body.received, 2);
});

test("a query without a tag does not retry", async () => {
  let calls = 0;
  await handle(get("/tracks?q=zzzz"), env({ fetchImpl: async () => { calls++; return upstreamOk([]); } }));
  assert.equal(calls, 1);
});

test("a failed retry keeps the first (empty) answer instead of erroring", async () => {
  let n = 0;
  const res = await handle(get("/tracks?tag=jazz"), env({
    fetchImpl: async () => (++n === 1 ? upstreamOk([]) : new Response("", { status: 500 })),
  }));
  assert.equal(res.status, 200);
  assert.equal((await res.json()).status, "empty");
});

test("empty results are never cached, so a flaky empty answer does not stick", async () => {
  let n = 0;
  const e = env({ fetchImpl: async () => (++n <= 2 ? upstreamOk([]) : upstreamOk([rawTrack(5)])) });
  const r1 = await handle(get("/tracks?tag=world"), e);
  assert.equal(r1.headers.get("Cache-Control"), "no-store");
  assert.equal((await r1.json()).status, "empty");
  const r2 = await handle(get("/tracks?tag=world"), e);
  assert.equal(r2.headers.get("X-Ooglex-Jamendo-Cache"), "miss");
  assert.equal((await r2.json()).tracks.length, 1);
});

test("received counts what Jamendo sent even when every track is filtered out", async () => {
  const res = await handle(get("/tracks"), env({ fetchImpl: async () => upstreamOk([rawTrack(1, { audio: "" })]) }));
  const body = await res.json();
  assert.equal(body.status, "empty");
  assert.equal(body.received, 1);
});

test("single-track lookup by id is cached separately and does not retry", async () => {
  const seen = [];
  const e = env({ fetchImpl: async (url) => { seen.push(new URL(url).searchParams.get("id")); return upstreamOk([rawTrack(77)]); } });
  const r = await (await handle(get("/tracks?id=77"), e)).json();
  assert.equal(r.tracks.length, 1);
  assert.equal(r.tracks[0].id, "77");
  const r2 = await handle(get("/tracks?id=77"), e);
  assert.equal(r2.headers.get("X-Ooglex-Jamendo-Cache"), "hit");
  const other = await (await handle(get("/tracks"), e)).json();
  assert.equal(other.tracks.length, 1);
  assert.deepEqual(seen, ["77", null]);
});
