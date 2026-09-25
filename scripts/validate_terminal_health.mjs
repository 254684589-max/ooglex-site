// Regression coverage for missing status, fallback disclosure and basic-data outages.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const body = { innerHTML: '' };
let missingFundamentals = false;
const ctx = vm.createContext({
  window: {}, document: { querySelector: () => body },
  fetch: async (url) => {
    if (missingFundamentals && url.endsWith('/fundamentals.json')) return { ok:false, status:404 };
    const data = fs.readFileSync(path.join(root, url), 'utf8');
    return { ok:true, json:async () => JSON.parse(data) };
  }
});
for (const name of ['core', 'overview', 'render', 'security']) {
  vm.runInContext(fs.readFileSync(path.join(root, 'assets/terminal', name + '.js'), 'utf8'), ctx);
}
const C = ctx.window.OOGLEX_CORE, R = ctx.window.OOGLEX_RENDER;
const snapshot = { updatedAt:'2026-09-24T12:00:00Z' };
const health = { status:'healthy', publishedSnapshotAt:snapshot.updatedAt };
assert.equal(C.meta('test', snapshot).status, 'unknown');
assert.equal(C.meta('test', snapshot, '', health).status, 'ok');
assert.equal(C.meta('test', snapshot, '', {...health, publishedSnapshotAt:'old'}).status, 'unknown');
assert.equal(C.meta('test', snapshot, '', {...health, __error:'404'}).status, 'unknown');
assert.equal(C.meta('test', {...snapshot, status:'partial'}, '', health).status, 'partial');
assert.equal(C.meta('test', {...snapshot, status:'ok'}, '', {...health, status:'failed'}).status, 'error');
assert.equal(C.meta('test', {__error:'HTTP 404'}).status, 'error');
assert.equal(C.meta('test', {status:'ok', rows:[]}).status, 'empty');
assert.equal(C.meta('test', {status:'ok', demo:true}).status, 'demo');
assert.equal(C.meta('test', {status:'stale'}).status, 'stale');
assert.equal(C.meta('test', {status:'ok', dataQuality:{status:'partial'}}).status, 'partial');
const fallback = C.meta('test', { status:'ok', assets:[{
  symbol:'<img src=x onerror=alert(1)>', dataMeta:{mode:'fallback', asOf:'2026-07-16', note:'<script>bad</script>'}
}] });
assert.equal(fallback.status, 'partial');
assert.equal(fallback.details[0].status, 'stale');
R.sources('#test', {meta:{sources:[fallback, C.meta('unknown', snapshot)]}});
assert.ok(body.innerHTML.includes('2026-07-16'));
assert.ok(body.innerHTML.includes('&lt;script&gt;'));
assert.ok(!body.innerHTML.includes('<img'));
assert.ok(body.innerHTML.includes('状态未核验'));
assert.ok(!body.innerHTML.includes('normal'));

const model = await ctx.window.OOGLEX_OVERVIEW.load();
assert.equal(model.meta.sources.length, 13);
assert.ok(model.fundamentals.rows.some(r => r.available && C.isNum(r.roe)));
assert.ok(C.srcLine(C.meta('unknown', snapshot)).includes('状态未核验'));
assert.ok(C.srcLine(fallback).includes('部分缺失'));
const fund = await ctx.window.OOGLEX_SECURITY.loadFundamentals();
assert.ok(fund.counts.pe > 50 && fund.counts.roe > 50, 'SCRN/RV/FA need real usable ratios');
assert.equal(Object.keys(fund.err).length, 0);
missingFundamentals = true;
const failed = await ctx.window.OOGLEX_OVERVIEW.load();
assert.equal(failed.fundamentals, null);
assert.equal(failed.meta.sources[12].status, 'error');
assert.ok(failed.markets.indices.length > 0, 'One failed source must not blank the market panels');
assert.ok((await ctx.window.OOGLEX_SECURITY.loadFundamentals()).err.fund.includes('404'));
console.log('终端健康回归：28 项通过（真实数据、缺失源、状态、转义、SCRN/RV/FA 模型）');
