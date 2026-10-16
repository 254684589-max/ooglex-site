// 科技领袖公开动态可用性日检。
//
// 直接运行线上同一份 cloudflare/pro-api/worker.js 的 /v1/tech-leaders/free-feed 逻辑
// （内存版 R2、一次性本地会话密钥），逐个检查名录里的本人公开 X 账号能否取到公开动态。
// 不调用线上 Worker，因此不需要任何 Secret，也不会改动线上缓存或会话。
//
// 用法：node scripts/tech-leaders/audit_free_feed.mjs [--out data/tech-leaders/free_feed_health.json]
//        [--concurrency 3] [--limit 0] [--handles a,b,c] [--posts 21]
//   --posts：每个账号请求的帖子数（默认 21；设 100 可检查「加载更多」能取到的历史深度）
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
