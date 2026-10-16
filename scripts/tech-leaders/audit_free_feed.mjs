// 科技领袖公开动态可用性日检。
//
// 直接运行线上同一份 cloudflare/pro-api/worker.js 的 /v1/tech-leaders/free-feed 逻辑
// （内存版 R2、一次性本地会话密钥），逐个检查名录里的本人公开 X 账号能否取到公开动态。
// 不调用线上 Worker，因此不需要任何 Secret，也不会改动线上缓存或会话。
//
// 用法：node scripts/tech-leaders/audit_free_feed.mjs [--out data/tech-leaders/free_feed_health.json]
//        [--concurrency 3] [--limit 0] [--handles a,b,c] [--posts 21]
//   --posts：每个账号请求的帖子数（默认 21；设 100 可检查「加载更多」能取到的历史深度）
//   --backfill-r2：把取到的帖子按 id 与线上 R2 缓存里的历史合并后写回（需要环境变量
//     CLOUDFLARE_API_TOKEN；CLOUDFLARE_ACCOUNT_ID 可选）。线上 Worker 从 Cloudflare 机房向上游翻页
//     常被限流、只拿到十几条；GitHub 机房能稳定取到更深的历史，用它给线上补齐「加载更多」的历史。
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { pathToFileURL } from "node:url";

const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf("--" + name);
  return i >= 0 && args[i + 1] !== undefined ? args[i + 1] : fallback;
};
const OUT = opt("out", "data/tech-leaders/free_feed_health.json");
const CONCURRENCY = Math.max(1, Number(opt("concurrency", "3")) || 3);
const MAX = Math.max(0, Number(opt("limit", "0")) || 0);
const POSTS = Math.max(1, Math.min(100, Number(opt("posts", "21")) || 21));
const BACKFILL = args.includes("--backfill-r2");
// 回填只需要 CLOUDFLARE_API_TOKEN：账号 ID 可省略，wrangler 会按令牌自动识别（与部署流程一致）。
// 启动时就检查，避免巡检跑完十几分钟后才因缺凭据失败。
if (BACKFILL && !process.env.CLOUDFLARE_API_TOKEN) {
  console.error("::error::--backfill-r2 需要环境变量 CLOUDFLARE_API_TOKEN");
  process.exit(1);
}
const R2_BUCKET = "ooglex-pro-data";
const fetchedPosts = new Map();   // handle -> posts（仅回填时保留）
const ONLY = String(opt("handles", "")).split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
const REQUEST_TIMEOUT_MS = 30000;
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");

// worker.js 是 ES 模块，但仓库没有 package.json 的 "type":"module"；复制成 .mjs 再导入。
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "ogx-worker-"));
const workerPath = path.join(tmp, "worker.mjs");
fs.copyFileSync(path.join(ROOT, "cloudflare/pro-api/worker.js"), workerPath);
const worker = (await import(pathToFileURL(workerPath).href)).default;

const store = new Map();
const PRO_DATA = {
  async get(key) {
    if (!store.has(key)) return null;
    const text = store.get(key);
    return { text: async () => text, body: text, httpEtag: "", etag: "", httpMetadata: {} };
  },
  async head(key) { return store.has(key) ? { httpEtag: "", etag: "" } : null; },
  async put(key, value) { store.set(key, typeof value === "string" ? value : String(value)); },
  async delete(key) { store.delete(key); }
};
const SECRET = crypto.randomBytes(24).toString("hex");
const env = {
  PRO_DATA,
  SUPABASE_URL: "https://audit.invalid",
  SUPABASE_PUBLISHABLE_KEY: "audit",
  TECH_LEADERS_SESSION_SECRET: SECRET,
  ALLOWED_ORIGINS: "https://ooglex.com"
};

// 与页面 isConfirmedPersonalX、部署冒烟测试使用同一判定。
const catalog = JSON.parse(fs.readFileSync(path.join(ROOT, "apps/tech-leaders/leaders.json"), "utf8"));
const people = Array.isArray(catalog) ? catalog : (catalog.leaders || catalog.people || []);
let eligible = people.filter((p) =>
  p && p.handle && p.admission_status === "active" && (
    p.x_identity_verified === true ||
    p.verified_personal_x === true ||
    String(p.note || "").includes("个人公开 X 账号")
  ) && p.timeline_mode !== "local_only"
);
if (ONLY.length) eligible = eligible.filter((p) => ONLY.includes(String(p.handle).toLowerCase()));
if (MAX) eligible = eligible.slice(0, MAX);

async function check(p) {
  const handle = String(p.handle);
  const started = Date.now();
  // limit>20 走 Worker 的完整取数路径：两个公开源都会尝试，失败时返回各自的状态（diagnostic），
  // 便于判断是哪一个源、为什么取不到；limit<=20 的快速路径只给笼统错误。
  const url = `https://pro-api.ooglex.com/v1/tech-leaders/free-feed?handle=${encodeURIComponent(handle)}&limit=${POSTS}`;
  const req = new Request(url, { headers: { Origin: "https://ooglex.com", "x-ooglex-tech-secret": SECRET } });
  let status = 0, body = {};
  try {
    const res = await Promise.race([
      worker.fetch(req, env, { waitUntil() {} }),
      new Promise((_, reject) => setTimeout(() => reject(new Error("audit_timeout")), REQUEST_TIMEOUT_MS))
    ]);
    status = res.status;
    body = await res.json().catch(() => ({}));
  } catch (e) {
    body = { error: e && e.message ? e.message : "audit_exception" };
  }
  const posts = Array.isArray(body.posts) ? body.posts : [];
  if (BACKFILL && status === 200 && posts.length) fetchedPosts.set(handle, posts);
  const times = posts.map((x) => Date.parse(x && x.created_at || "")).filter(Number.isFinite);
  const latest = times.length ? new Date(Math.max(...times)).toISOString() : null;
  const oldest = times.length ? new Date(Math.min(...times)).toISOString() : null;
  return {
    id: p.id,
    name: p.name_zh || p.zh || p.name || p.id,
    handle,
    category: p.primary_category || p.category || (p.categories && p.categories[0]) || "",
    ok: status === 200 && posts.length > 0,
    http_status: status || null,
    post_count: posts.length,
    latest_post_at: latest,
    latest_age_days: latest ? Math.floor((Date.now() - Date.parse(latest)) / 86400000) : null,
    oldest_post_at: oldest,
    requested_posts: POSTS,
    source: body.source || null,
    error: status === 200 && posts.length ? null : (body.error || (status === 200 ? "empty" : `http_${status}`)),
    diagnostic: body.diagnostic || null,
    elapsed_ms: Date.now() - started
  };
}

const rows = new Array(eligible.length);
let next = 0;
async function lane() {
  while (next < eligible.length) {
    const i = next++;
    rows[i] = await check(eligible[i]);
    // 对公开源保持克制：每个工作通道两次请求之间稍作间隔。
    await new Promise((r) => setTimeout(r, 400));
  }
}
await Promise.all(Array.from({ length: Math.min(CONCURRENCY, eligible.length || 1) }, lane));

// 失败的账号歇一会儿后单路再试一次，把偶发失败和持续失败分开。
const firstFailed = rows.map((r, i) => (r.ok ? -1 : i)).filter((i) => i >= 0);
if (firstFailed.length) {
  await new Promise((r) => setTimeout(r, Number(opt("retry-wait-ms", "60000")) || 0));
  for (const i of firstFailed) {
    const again = await check(eligible[i]);
    again.retried = true;
    again.first_error = rows[i].error;
    rows[i] = again;
    await new Promise((r) => setTimeout(r, 1500));
  }
}

// ---- 回填线上 R2 历史 ----
// 缓存键与 worker.js 的 freeTechLeaderCacheKey 一致：从源码读取版本号，避免两处各写一份。
const workerSource = fs.readFileSync(path.join(ROOT, "cloudflare/pro-api/worker.js"), "utf8");
const keyMatch = workerSource.match(/const version = normalized === "elonmusk" \? "([^"]+)" : "([^"]+)";/);
function liveCacheKey(handle) {
  const normalized = String(handle || "").replace(/^@/, "").toLowerCase();
  if (!keyMatch) throw new Error("cache_key_version_not_found_in_worker");
  return `tech-leaders/free-feed/${normalized === "elonmusk" ? keyMatch[1] : keyMatch[2]}/${normalized}.json`;
}
function mergePosts(fresh, history) {
  const byId = new Map();
  for (const p of history || []) if (p && p.id) byId.set(String(p.id), p);
  for (const p of fresh || []) if (p && p.id) byId.set(String(p.id), p);
  return Array.from(byId.values()).sort((a, b) => {
    const ta = Date.parse(a.created_at || "") || 0, tb = Date.parse(b.created_at || "") || 0;
    if (ta !== tb) return tb - ta;
    return String(b.id || "").localeCompare(String(a.id || ""));
  }).slice(0, 100);
}
const backfill = { attempted: 0, written: 0, failed: 0, grew: 0, unchanged: 0, errors: [] };
if (BACKFILL && fetchedPosts.size) {
  // 用与部署流程相同的 wrangler r2 object get/put 读写线上 R2（凭据来自环境变量，不写入日志）。
  const { execFile } = await import("node:child_process");
  const run = (argv) => new Promise((resolve) => {
    execFile("npx", ["--yes", "wrangler@4", ...argv], { maxBuffer: 1 << 26, timeout: 120000 }, (err, stdout, stderr) => {
      resolve({ ok: !err, stdout: String(stdout || ""), stderr: String(stderr || "") });
    });
  });
  const work = fs.mkdtempSync(path.join(os.tmpdir(), "ogx-backfill-"));
  const entries = Array.from(fetchedPosts.entries());
  let cursor = 0;
  async function backfillLane(lane) {
    while (cursor < entries.length) {
      const [handle, posts] = entries[cursor++];
      const key = liveCacheKey(handle);
      const file = path.join(work, `${lane}.json`);
      backfill.attempted += 1;
      try {
        try { fs.rmSync(file, { force: true }); } catch {}
        const got = await run(["r2", "object", "get", `${R2_BUCKET}/${key}`, "--file", file, "--remote"]);
        let current = null;
        if (got.ok && fs.existsSync(file)) { try { current = JSON.parse(fs.readFileSync(file, "utf8")); } catch {} }
        else if (!/does not exist|NoSuchKey|not found|404/i.test(got.stderr + got.stdout)) throw new Error("r2_get_failed");
        const history = current && Array.isArray(current.posts) ? current.posts : [];
        const merged = mergePosts(posts, history);
        if (merged.length > history.length) backfill.grew += 1; else backfill.unchanged += 1;
        // 线上 Worker 10 分钟内刚刷新过就沿用它的时间，否则记为现在（回填的数据本身就是刚取的）。
        const fetchedAt = current && current.fetched_at && Date.parse(current.fetched_at) > Date.now() - 10 * 60 * 1000
          ? current.fetched_at : new Date().toISOString();
        const next = {
          ...(current || {}),
          schema_version: (current && current.schema_version) || 6,
          uses_x_api: false,
          handle: (current && current.handle) || handle,
          fetched_at: fetchedAt,
          posts: merged,
          requested_limit: merged.length,
          requested_target: Math.max(100, Number(current && current.requested_target) || 0),
          history_backfill: { source: "github_actions_public_sources", at: new Date().toISOString(), fetched: posts.length }
        };
        fs.writeFileSync(file, JSON.stringify(next));
        const put = await run(["r2", "object", "put", `${R2_BUCKET}/${key}`, "--file", file, "--content-type", "application/json; charset=utf-8", "--remote"]);
        if (!put.ok) throw new Error("r2_put_failed");
        backfill.written += 1;
      } catch (e) {
        backfill.failed += 1;
        if (backfill.errors.length < 10) backfill.errors.push(`${handle}: ${e && e.message ? e.message : e}`);
      }
    }
  }
  await Promise.all(Array.from({ length: 6 }, (_, i) => backfillLane(i)));
  fs.rmSync(work, { recursive: true, force: true });
  console.log(`BACKFILL ${JSON.stringify(backfill)}`);
  if (backfill.attempted && backfill.failed / backfill.attempted > 0.2) {
    console.error(`::error::回填线上历史失败过多（${backfill.failed}/${backfill.attempted}）：${backfill.errors.join("；")}`);
    process.exitCode = 1;
  }
}

const ok = rows.filter((r) => r.ok);
const failed = rows.filter((r) => !r.ok);
const stale = ok.filter((r) => r.latest_age_days !== null && r.latest_age_days > 180);
const errorCounts = {};
for (const r of failed) errorCounts[r.error] = (errorCounts[r.error] || 0) + 1;

const report = {
  schema_version: 1,
  generated_at: new Date().toISOString(),
  source: "cloudflare/pro-api/worker.js free-feed 逻辑在 GitHub Actions 中本地运行（不经过线上 Worker、不使用线上缓存）",
  note: "ok=取到至少一条公开动态。失败多为上游公开源（X syndication / fxtwitter）对该账号无返回或限流；GitHub 机房网络与 Cloudflare 边缘可能略有差异。",
  eligible_accounts: rows.length,
  ok_count: ok.length,
  failed_count: failed.length,
  ok_but_older_than_180d: stale.length,
  error_counts: errorCounts,
  recovered_on_retry: rows.filter((r) => r.ok && r.retried).length,
  failed: failed.map(({ id, name, handle, category, http_status, error, diagnostic }) => ({ id, name, handle, category, http_status, error, diagnostic })),
  rows
};
const outPath = path.resolve(ROOT, OUT);
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(report, null, 2) + "\n");

const lines = [
  `## 科技领袖公开动态日检`,
  ``,
  `- 检查账号：${rows.length}`,
  `- 可取到动态：${ok.length}`,
  `- 取不到：${failed.length}（首轮失败后重试成功 ${rows.filter((r) => r.ok && r.retried).length} 个）`,
  `- 能取到但最新一条超过 180 天：${stale.length}`,
  ``
];
if (failed.length) {
  const why = (d) => d ? `X 官方源 ${d.official_source || "-"}${d.official_status ? " " + d.official_status : ""}；fxtwitter ${d.fallback_source || "-"}${d.fallback_status ? " " + d.fallback_status : ""}` : "";
  lines.push(`### 取不到动态的账号（已重试一次）`, ``, `| 人物 | 账号 | 分类 | 原因 |`, `|---|---|---|---|`);
  for (const r of failed) lines.push(`| ${r.name} | @${r.handle} | ${r.category} | ${why(r.diagnostic) || r.error} |`);
}
const summary = lines.join("\n") + "\n";
if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
console.log(summary);
console.log(JSON.stringify({ eligible: rows.length, ok: ok.length, failed: failed.length, errors: errorCounts }));

fs.rmSync(tmp, { recursive: true, force: true });
// 大面积失败通常是运行环境网络问题而不是账号问题：标红提醒，但仍保留已写出的报告。
if (rows.length && failed.length / rows.length > 0.5) {
  console.error(`::warning::超过一半账号取不到动态（${failed.length}/${rows.length}），可能是运行环境网络或上游整体故障。`);
}
