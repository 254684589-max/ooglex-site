/* 万象智聊 —— 连接国内外大模型的轻量聊天站（BYOK：自带密钥） */
(() => {
'use strict';
const $ = id => document.getElementById(id);

/* ===================== 两个大脑：大聪明（云端）· 小机灵（本机） ===================== */
const MOBILE = /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent);
const PROVIDERS = [
  { id: 'shared', name: '🧠 大聪明（云端 · 免费 · 打开即用）', base: '', model: '',
    help: '本站为你转发的免费云端大模型：<b>无需密钥、打开就能聊，手机也能用</b>。'
      + '每人每天限量，用完自动切到「小机灵」或应急模式。密钥由站长持有，你的对话不经过本站服务器存储。' },
  { id: 'webllm', name: '🤖 小机灵（本机运行 · 免密钥 · 电脑用）', base: '',
    // 手机显存/浏览器多半跑不动：移动端默认小模型，桌面端默认 1.5B
    model: MOBILE ? 'Qwen2.5-0.5B-Instruct-q4f16_1-MLC' : 'Qwen2.5-1.5B-Instruct-q4f16_1-MLC',
    help: '模型直接在你的设备上跑：<b>无需密钥、聊天不出本机、下载后离线可用</b>。'
      + '需要电脑版较新 Chrome / Edge（WebGPU）；<b>手机浏览器多不支持，请改用「大聪明」</b>。'
      + '首次使用下载模型（0.5B 约 300MB / 1.5B 约 900MB），之后走缓存。国内网络请把下方下载源切成镜像。' },
  { id: 'offline', name: '离线小智（断网应急 · 小玩具）', base: '', model: '内置规则引擎',
    help: '不联网、不要密钥的迷你应答机，只会算术、查日期、讲笑话，断网时应急用 😄' },
  { id: 'custom', name: '自定义接口（高级 · 自带密钥）', base: '', model: '',
    help: '给会折腾的用户：填任何 OpenAI 兼容服务的地址、模型名与密钥。例如 '
      + 'DeepSeek（https://api.deepseek.com/v1 · deepseek-chat）、智谱、Kimi、通义、或自建 Ollama。' },
];
const DEFAULT_SYS = '你是 Ooglex「万象智聊」里的 AI 助手，聪明伶俐、博学多才。用中文回答，表达清晰友善，复杂问题分点说明，不确定时诚实说明。';

/* ===================== 配置与历史 ===================== */
// 默认「大聪明」云端通道：新用户打开即聊，零配置
let cfg = { provider: 'shared', base: '', model: '', key: '', sys: DEFAULT_SYS, src: 'hf' };
try { Object.assign(cfg, JSON.parse(localStorage.getItem('aichat_cfg') || '{}')); } catch (e) {}
// 迁移老版本：已下架的品牌服务商（zhipu/deepseek/…）→ 有自填密钥转「自定义」，否则回「大聪明」
if (!PROVIDERS.some(p => p.id === cfg.provider)) {
  cfg.provider = (cfg.key && cfg.base) ? 'custom' : 'shared';
}

/* 大聪明云端配置（部署 workers/ai-proxy 后在 shared-config.json 开通） */
let SHARED = { enabled: false, base: '', model: '' };
fetch('shared-config.json', { cache: 'no-cache' })
  .then(r => (r.ok ? r.json() : null))
  .then(j => { if (j) { SHARED = j; refreshStatus(); } })
  .catch(() => {});
const saveCfg = () => localStorage.setItem('aichat_cfg', JSON.stringify(cfg));

/* ===================== 多会话存储 ===================== */
const newId = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
let convs = [];
try { convs = JSON.parse(localStorage.getItem('aichat_convs') || '[]'); } catch (e) {}
// 老版本的单会话历史迁移成一个会话
try {
  const old = JSON.parse(localStorage.getItem('aichat_hist') || 'null');
  if (Array.isArray(old) && old.length) {
    convs.unshift({ id: newId(), title: '', msgs: old, ts: Date.now() });
  }
  localStorage.removeItem('aichat_hist');
} catch (e) {}
if (!convs.length) convs = [{ id: newId(), title: '', msgs: [], ts: Date.now() }];
let curId = localStorage.getItem('aichat_cur');
if (!convs.some(c => c.id === curId)) curId = convs[0].id;
const cur = () => convs.find(c => c.id === curId);
function saveConvs() {
  convs.sort((a, b) => b.ts - a.ts);
  convs = convs.slice(0, 20);
  convs.forEach(c => { c.msgs = c.msgs.slice(-60); });
  localStorage.setItem('aichat_convs', JSON.stringify(convs));
  localStorage.setItem('aichat_cur', curId);
}
function convTitle(c) {
  if (c.title) return c.title;
  const u = c.msgs.find(m => m.role === 'user');
  return u ? u.content.slice(0, 24) : '新对话';
}

/* ===================== 浏览器本地模型（WebLLM · WebGPU） ===================== */
// 库地址可用 localStorage 键 aichat_webllm_lib 覆盖（自托管或测试用）
const WEBLLM_LIB = localStorage.getItem('aichat_webllm_lib')
  || 'https://cdn.jsdelivr.net/npm/@mlc-ai/web-llm@0.2.84/+esm';
let llm = null, llmModel = '';
function buildAppConfig(mod) {
  if ((cfg.src || 'hf') !== 'mirror') return undefined;
  // 国内镜像：模型权重走 hf-mirror.com（模型 wasm 库仍走原地址）
  const ac = JSON.parse(JSON.stringify(mod.prebuiltAppConfig));
  ac.model_list.forEach(m => { m.model = m.model.replace('https://huggingface.co/', 'https://hf-mirror.com/'); });
  return ac;
}
async function getEngine(model, onProgress) {
  if (llm && llmModel === model) return llm;
  const mod = await import(WEBLLM_LIB);
  if (llm) { try { await llm.unload(); } catch (e) {} llm = null; llmModel = ''; }
  const engine = await mod.CreateMLCEngine(model, {
    initProgressCallback: onProgress,
    appConfig: buildAppConfig(mod),
  });
  llm = engine; llmModel = model;
  return engine;
}

/* ===================== 渲染 ===================== */
function esc(s) { return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

/* Markdown 渲染（零依赖）：整体先转义、代码先占位，再逐行成块，杜绝注入 */
function mdInline(h) {
  h = h.replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>');
  h = h.replace(/(^|[^*])\*(\S(?:[^*\n]*?\S)?)\*(?!\*)/g, '$1<i>$2</i>');
  h = h.replace(/\[([^\]\n]+)\]\((https?:\/\/[^)\s]+)\)/g,
    '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');
  return h;
}
function md(src) {
  const blocks = [], spans = [];
  let s = src.replace(/\r\n?/g, '\n');
  // 围栏代码块：未闭合（流式输出中）也按代码块渲染
  s = s.replace(/```[^\n`]*\n?([\s\S]*?)(?:```|$)/g, (m, body) => {
    blocks.push('<pre><code>' + esc(body.replace(/\n$/, '')) + '</code></pre>');
    return '\uE000' + (blocks.length - 1) + '\uE001';
  });
  s = esc(s);
  s = s.replace(/`([^`\n]+)`/g, (m, c) => {
    spans.push('<code>' + c + '</code>');
    return '\uE002' + (spans.length - 1) + '\uE003';
  });

  const lines = s.split('\n'), out = [], para = [];
  const flush = () => { if (para.length) { out.push('<p>' + para.map(mdInline).join('<br>') + '</p>'); para.length = 0; } };
  const isSep = l => /^\s*\|?\s*:?-{2,}[-|:\s]*$/.test(l) && l.indexOf('-') >= 0;
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    let m;
    if (/^\s*$/.test(l)) { flush(); continue; }
    if (/^\uE000\d+\uE001\s*$/.test(l.trim())) { flush(); out.push(l.trim()); continue; }
    if ((m = l.match(/^(#{1,4})\s+(.*)$/))) { flush(); const n = m[1].length; out.push(`<h${n}>` + mdInline(m[2]) + `</h${n}>`); continue; }
    if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(l)) { flush(); out.push('<hr>'); continue; }
    if ((m = l.match(/^&gt;\s?(.*)$/))) {
      flush(); const q = [m[1]];
      while (i + 1 < lines.length && (m = lines[i + 1].match(/^&gt;\s?(.*)$/))) { q.push(m[1]); i++; }
      out.push('<blockquote>' + q.map(mdInline).join('<br>') + '</blockquote>'); continue;
    }
    if (/^\s*(?:[-*+]|\d+[.)])\s+/.test(l)) {
      flush();
      const ordered = /^\s*\d/.test(l), items = [];
      const re = ordered ? /^\s*\d+[.)]\s+(.*)$/ : /^\s*[-*+]\s+(.*)$/;
      items.push(l.match(re)[1]);
      while (i + 1 < lines.length && re.test(lines[i + 1])) { items.push(lines[i + 1].match(re)[1]); i++; }
      const tag = ordered ? 'ol' : 'ul';
      out.push(`<${tag}>` + items.map(x => '<li>' + mdInline(x) + '</li>').join('') + `</${tag}>`); continue;
    }
    if (l.indexOf('|') >= 0 && i + 1 < lines.length && isSep(lines[i + 1])) {
      flush();
      const row = x => x.replace(/^\s*\|/, '').replace(/\|\s*$/, '').split('|').map(c => mdInline(c.trim()));
      const head = row(l); i++;
      const body = [];
      while (i + 1 < lines.length && lines[i + 1].indexOf('|') >= 0 && !/^\s*$/.test(lines[i + 1])) { body.push(row(lines[i + 1])); i++; }
      out.push('<div class="tbl"><table><thead><tr>' + head.map(c => '<th>' + c + '</th>').join('') + '</tr></thead><tbody>'
        + body.map(r => '<tr>' + r.map(c => '<td>' + c + '</td>').join('') + '</tr>').join('') + '</tbody></table></div>');
      continue;
    }
    para.push(l);
  }
  flush();
  let h = out.join('');
  h = h.replace(/\uE002(\d+)\uE003/g, (m, n) => spans[n]);
  h = h.replace(/\uE000(\d+)\uE001/g, (m, n) => blocks[n]);
  return h;
}
/* 每个大脑的名字（标在头像下，让用户记住） */
function brainName(brain) {
  brain = brain || cfg.provider;
  return brain === 'webllm' ? '小机灵' : brain === 'offline' ? '离线小智' : brain === 'custom' ? '自定义' : '大聪明';
}
/* 像素小怪物头像：大聪明=蓝紫 · 小机灵=橙 · 离线=灰 */
function critterSVG(brain) {
  brain = brain || cfg.provider;
  const c = brain === 'webllm' ? '#e07a4e'
          : brain === 'offline' ? '#8a90a6' : '#7d7bff';
  return '<svg viewBox="0 0 16 16" width="100%" height="100%" shape-rendering="crispEdges" aria-hidden="true">'
    + `<rect x="4" y="3" width="8" height="8" rx="0.6" fill="${c}"/>`
    + `<rect x="2" y="5" width="2" height="3" fill="${c}"/><rect x="12" y="5" width="2" height="3" fill="${c}"/>`
    + `<rect x="5" y="11" width="1.5" height="2.2" fill="${c}"/><rect x="7.25" y="11" width="1.5" height="2.2" fill="${c}"/><rect x="9.5" y="11" width="1.5" height="2.2" fill="${c}"/>`
    + '<rect x="5.9" y="5" width="1.5" height="1.7" fill="#0b0c16"/><rect x="8.6" y="5" width="1.5" height="1.7" fill="#0b0c16"/>'
    + '</svg>';
}
function addMsg(role, text, streaming, brain) {
  const div = document.createElement('div');
  div.className = 'msg ' + (role === 'user' ? 'user' : 'ai');
  // 用户消息按纯文本原样展示，只有 AI 回复走 Markdown
  const body = role === 'user' ? esc(text) : md(text);
  const avatar = role === 'user' ? '🙂' : critterSVG(brain);
  const name = role === 'user' ? '我' : brainName(brain);
  div.innerHTML = `<div class="avc"><div class="av">${avatar}</div><div class="avname">${name}</div></div>
    <div class="grp">
      <div class="bubble${streaming ? ' cursor' : ''}">${body}</div>
      <div class="acts"></div>
    </div>`;
  div._raw = text;
  $('msgs').appendChild(div);
  $('chat').scrollTop = $('chat').scrollHeight;
  return div.querySelector('.bubble');
}

/* ===================== 消息操作：复制 / 重新生成 / 编辑重发 ===================== */
function copyText(t, btn) {
  const done = () => {
    const o = btn.textContent;
    btn.textContent = '已复制 ✓';
    setTimeout(() => { btn.textContent = o; }, 1200);
  };
  const fallback = () => {
    const ta = document.createElement('textarea');
    ta.value = t; ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); done(); } catch (e) {}
    ta.remove();
  };
  if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(t).then(done, fallback);
  else fallback();
}
function refreshActs() {
  const conv = cur();
  const mk = (label, fn) => {
    const b = document.createElement('button');
    b.className = 'act'; b.type = 'button'; b.textContent = label;
    b.addEventListener('click', fn);
    return b;
  };
  const rows = $('msgs').querySelectorAll('.msg');
  rows.forEach(el => {
    const acts = el.querySelector('.acts');
    acts.innerHTML = '';
    acts.appendChild(mk('⧉ 复制', e => copyText(el._raw || '', e.target)));
  });
  // 最后一条 AI 回复可重新生成（欢迎语不入历史，不会命中）
  if (conv.msgs.length && conv.msgs[conv.msgs.length - 1].role === 'assistant') {
    const ai = $('msgs').querySelectorAll('.msg.ai');
    if (ai.length) ai[ai.length - 1].querySelector('.acts').appendChild(mk('↻ 重新生成', regenerate));
  }
  // 最后一条用户消息可编辑重发
  if (conv.msgs.some(m => m.role === 'user')) {
    const us = $('msgs').querySelectorAll('.msg.user');
    if (us.length) us[us.length - 1].querySelector('.acts').appendChild(mk('✎ 编辑重发', editLast));
  }
}
function regenerate() {
  if (busy) return;
  const conv = cur();
  if (!conv.msgs.length || conv.msgs[conv.msgs.length - 1].role !== 'assistant') return;
  conv.msgs.pop();
  const ai = $('msgs').querySelectorAll('.msg.ai');
  if (ai.length) ai[ai.length - 1].remove();
  saveConvs();
  reply(conv);
}
function editLast() {
  if (busy) return;
  const conv = cur();
  const li = conv.msgs.map(m => m.role).lastIndexOf('user');
  if (li < 0) return;
  const text = conv.msgs[li].content;
  conv.msgs.splice(li);          // 该条及其后的回复一并撤下
  saveConvs();
  openConv(conv.id);
  $('inp').value = text; autoSize(); $('inp').focus();
}
function setStatus(t, ok) { $('status').innerHTML = ok ? `<span class="ok">${t}</span>` : t; }
function refreshStatus() {
  if (cfg.provider === 'offline') setStatus('😀 离线小智 · 断网应急', true);
  else if (cfg.provider === 'shared')
    setStatus(SHARED.enabled ? '🧠 大聪明 · 云端免费 · 打开即用' : '大聪明暂未开通 —— 点 ⚙️ 设置换「小机灵」', SHARED.enabled);
  else if (cfg.provider === 'webllm')
    setStatus('🤖 小机灵 · 本机运行' + (llm && llmModel === cfg.model ? ' · 已就绪' : ' · 首次使用需下载'), true);
  else if (cfg.key) setStatus('🔧 自定义接口 · ' + (cfg.model || '未填模型'), true);
  else setStatus('尚未配置 —— 点右上角 ⚙️ 设置');
}

/* ===================== 欢迎与会话切换 ===================== */
function welcome() {
  addMsg('ai', '你好呀，我是万象智聊 ✨\n\n默认用**大聪明**（云端模型）——**打开就能聊，不用配置，手机也能用**。\n\n想更私密？在 ⚙️ 设置里换**小机灵**：模型直接跑在你电脑上，聊天内容不出本机（需要电脑版 Chrome / Edge）。\n\n有什么想聊的，直接说 😄');
}
function renderConvs() {
  $('convList').innerHTML = convs.map(c =>
    `<div class="conv${c.id === curId ? ' cur' : ''}" data-id="${c.id}">
      <span class="t">${esc(convTitle(c))}</span>
      <button class="del" title="删除对话" data-del="${c.id}">✕</button>
    </div>`).join('');
}
function openConv(id) {
  curId = id;
  localStorage.setItem('aichat_cur', curId);
  $('msgs').innerHTML = '';
  const c = cur();
  if (c.msgs.length) c.msgs.forEach(m => addMsg(m.role, m.content, false, m.brain));
  else welcome();
  renderConvs();
  refreshActs();
}
function newConv() {
  const empty = convs.find(c => !c.msgs.length);
  if (empty) { openConv(empty.id); return; }   // 已有空对话就直接用，不堆积
  const c = { id: newId(), title: '', msgs: [], ts: Date.now() };
  convs.unshift(c);
  saveConvs();
  openConv(c.id);
}
function delConv(id) {
  const c = convs.find(x => x.id === id);
  if (!c) return;
  if (c.msgs.length && !confirm('删除对话「' + convTitle(c) + '」？')) return;
  convs = convs.filter(x => x.id !== id);
  if (!convs.length) convs = [{ id: newId(), title: '', msgs: [], ts: Date.now() }];
  if (id === curId) curId = convs[0].id;
  saveConvs();
  openConv(curId);
}
const openDrawer = () => { renderConvs(); $('drawer').classList.add('open'); $('drawerMask').classList.add('show'); };
const closeDrawer = () => { $('drawer').classList.remove('open'); $('drawerMask').classList.remove('show'); };
$('convBtn').addEventListener('click', openDrawer);
$('drawerMask').addEventListener('click', closeDrawer);
$('newConvBtn').addEventListener('click', () => { newConv(); closeDrawer(); });
$('convList').addEventListener('click', e => {
  const del = e.target.closest('[data-del]');
  if (del) { delConv(del.getAttribute('data-del')); return; }
  const item = e.target.closest('.conv');
  if (item) { openConv(item.getAttribute('data-id')); closeDrawer(); }
});
openConv(curId);
refreshStatus();

/* ===================== 设置面板 ===================== */
$('cfgProvider').innerHTML = PROVIDERS.map(p => `<option value="${p.id}">${p.name}</option>`).join('');
function toggleRows(pid) {
  // 大聪明/离线：什么都不用填。小机灵：只显示模型名+下载源。自定义：地址+模型+密钥。
  $('baseRow').style.display = pid === 'custom' ? '' : 'none';
  $('modelRow').style.display = (pid === 'custom' || pid === 'webllm') ? '' : 'none';
  $('srcRow').style.display = pid === 'webllm' ? '' : 'none';
  $('keyRow').style.display = pid === 'custom' ? '' : 'none';
  $('safeNote').style.display = pid === 'custom' ? '' : 'none';
}
function fillPanel() {
  $('cfgProvider').value = cfg.provider;
  $('cfgBase').value = cfg.base; $('cfgModel').value = cfg.model;
  $('cfgKey').value = cfg.key; $('cfgSys').value = cfg.sys;
  $('cfgSrc').value = cfg.src || 'hf';
  $('keyHelp').innerHTML = '💡 ' + (PROVIDERS.find(p => p.id === cfg.provider) || PROVIDERS[0]).help;
  toggleRows(cfg.provider);
}
$('cfgProvider').addEventListener('change', () => {
  const p = PROVIDERS.find(x => x.id === $('cfgProvider').value);
  $('cfgBase').value = p.base; $('cfgModel').value = p.model;
  $('keyHelp').innerHTML = '💡 ' + p.help;
  toggleRows(p.id);
});
$('setBtn').addEventListener('click', () => { fillPanel(); $('mask').classList.add('show'); });
$('cancelBtn').addEventListener('click', () => $('mask').classList.remove('show'));
$('saveBtn').addEventListener('click', () => {
  cfg = { provider: $('cfgProvider').value, base: $('cfgBase').value.trim().replace(/\/+$/, ''),
          model: $('cfgModel').value.trim(), key: $('cfgKey').value.trim(), sys: $('cfgSys').value.trim() || DEFAULT_SYS,
          src: $('cfgSrc').value };
  saveCfg(); refreshStatus();
  $('mask').classList.remove('show');
});

/* ===================== 离线小智（规则引擎玩具） ===================== */
function offlineReply(q) {
  const now = new Date();
  if (/几点|时间/.test(q)) return `现在是 ${now.toLocaleTimeString('zh-CN')} ⏰`;
  if (/几号|日期|星期/.test(q)) return `今天是 ${now.toLocaleDateString('zh-CN')}，星期${'日一二三四五六'[now.getDay()]} 📅`;
  const m = q.replace(/[＋﹢加]/g,'+').replace(/[－减]/g,'-').replace(/[×乘]/g,'*').replace(/[÷除以]/g,'/').match(/(-?[\d.]+(?:\s*[+\-*/]\s*-?[\d.]+)+)/);
  if (m && /^[\d+\-*/.()\s]+$/.test(m[1])) {
    try { const r = new Function('return (' + m[1] + ')')(); if (isFinite(r)) return `算出来啦：${m[1].replace(/\s/g,'')} = **${+r.toPrecision(12)}** 🧮`; } catch (e) {}
  }
  if (/笑话|搞笑|开心/.test(q)) {
    const J = ['程序员最讨厌的两件事：1. 写文档；2. 别人不写文档。','为什么程序员分不清万圣节和圣诞节？因为 Oct 31 == Dec 25。','我跟空气吵了一架，最后它赢了——因为它根本不理我。','键盘上最辛苦的键是空格，因为它一直在被人敲打还无名无分。'];
    return J[Math.floor(Math.random() * J.length)] + ' 😆';
  }
  if (/你是谁|你叫什么/.test(q)) return '我是离线小智，一个不联网的迷你应答机 🤖 想体验真正聪明的AI，请在设置里接入大模型～';
  if (/你好|hi|hello|嗨/i.test(q)) return '你好呀！我是离线小智 👋 我会算算术、报时间、讲笑话。想聊更深的，去设置里接个大模型吧！';
  if (/天气/.test(q)) return '我没法联网查天气 🌦 建议看看窗外，或者接入大模型后让它教你接天气接口～';
  if (/谢谢|感谢/.test(q)) return '不客气！能帮上忙我很开心 😊';
  return '这个问题超出我这颗离线小脑袋的能力了 😅 我只会算算术（试试「23*45」）、报时间日期、讲笑话。点右上角 ⚙️ 接入真正的大模型，它什么都能聊！';
}

/* ===================== 站内数据工具（OpenAI function calling） ===================== */
async function fetchJSON(path) {
  const r = await fetch(path, { cache: 'no-cache' });
  if (!r.ok) throw new Error('HTTP ' + r.status);
  return r.json();
}
const TOOLS = [
  {
    label: '今日要闻',
    def: { type: 'function', function: {
      name: 'get_latest_news',
      description: '获取今日全球要闻（本站每日更新的权威新闻聚合，含市场/科技/世界等分类）。用户询问新闻、时事、行情消息、"今天发生了什么"时调用。',
      parameters: { type: 'object', properties: {}, required: [] },
    } },
    run: async () => {
      const d = await fetchJSON('../whats-latest/data.json');
      return JSON.stringify({
        更新时间: d.asOf || d.updatedAt, 数据来源: d.source,
        头条: d.highlight ? { 标题: d.highlight.title, 来源: d.highlight.source, 分类: d.highlight.category } : null,
        分类要闻: (d.categories || []).map(c => ({
          分类: c.name,
          条目: (c.items || []).slice(0, 4).map(it => ({ 标题: it.title, 来源: it.source })),
        })),
      });
    },
  },
  {
    label: '市场情绪',
    def: { type: 'function', function: {
      name: 'get_market_sentiment',
      description: '获取当前市场情绪：CNN 恐惧与贪婪指数（0-100，本站每日更新），含与昨收/一周前/一月前/一年前的对比。用户问市场情绪、恐慌贪婪指数、行情冷热时调用。',
      parameters: { type: 'object', properties: {}, required: [] },
    } },
    run: async () => {
      const d = await fetchJSON('../fear-greed/data.json');
      const f = r => (r ? { 分数: r.score, 评级: r.ratingZh || r.rating } : null);
      return JSON.stringify({
        更新时间: d.asOf || d.updatedAt, 数据来源: d.source,
        当前: { 分数: d.score, 评级: d.ratingZh || d.rating },
        对比: { 昨收: f(d.refs && d.refs.close), 一周前: f(d.refs && d.refs.week),
                一月前: f(d.refs && d.refs.month), 一年前: f(d.refs && d.refs.year) },
      });
    },
  },
];
const TOOL_SYS = '\n\n你可以调用工具获取 Ooglex 站内每日更新的实时数据。涉及新闻、市场情绪等话题时优先调用工具拿到真实数据再回答，注明数据更新时间，不要编造数据。';
async function runTool(tc) {
  const t = TOOLS.find(x => x.def.function.name === (tc.function && tc.function.name));
  if (!t) return '{"error":"未知工具"}';
  try {
    let args = {};
    try { args = JSON.parse(tc.function.arguments || '{}'); } catch (e) {}
    return String(await t.run(args)).slice(0, 6000);
  } catch (e) {
    return JSON.stringify({ error: '工具执行失败：' + String((e && e.message) || e) });
  }
}

/* ===================== 发送与流式接收 ===================== */
let busy = false, aborter = null;
async function send() {
  if (busy) { aborter && aborter.abort(); return; }
  const q = $('inp').value.trim();
  if (!q) return;
  $('inp').value = ''; autoSize();
  // 锁定当前会话对象：流式回复期间即使切换会话，答案也落回原会话
  const conv = cur();
  addMsg('user', q);
  conv.msgs.push({ role: 'user', content: q });
  conv.ts = Date.now();
  saveConvs(); renderConvs(); refreshActs();
  reply(conv);
}

/* 基于会话现有历史请求一条 AI 回复（send 与「重新生成」共用） */
async function reply(conv) {
  const lastUser = conv.msgs.filter(m => m.role === 'user').pop();
  const q = lastUser ? lastUser.content : '';

  if (cfg.provider === 'webllm') { replyWebLLM(conv); return; }

  if (cfg.provider === 'offline') {
    const r = offlineReply(q);
    setTimeout(() => {
      if (cur() === conv) addMsg('ai', r, false, 'offline');
      conv.msgs.push({ role: 'assistant', content: r, brain: 'offline' });
      saveConvs(); renderConvs();
      if (cur() === conv) refreshActs();
    }, 400);
    return;
  }

  const shared = cfg.provider === 'shared';
  if (shared && !(SHARED.enabled && SHARED.base)) { degrade(conv, '大聪明当前不可用'); return; }
  // 没配密钥也不已读不回：走降级链给出应急回答 + 引导，并存入历史
  if (!shared && (!cfg.key || !cfg.base)) { degrade(conv, '还没配置 AI 服务'); return; }
  const base = shared ? SHARED.base.replace(/\/+$/, '') : cfg.base;
  const model = shared ? SHARED.model : cfg.model;
  const headers = { 'Content-Type': 'application/json' };
  if (!shared) headers.Authorization = 'Bearer ' + cfg.key;

  busy = true; aborter = new AbortController();
  $('sendBtn').textContent = '停止'; $('sendBtn').classList.add('stop');
  const bubble = addMsg('ai', '', true, cfg.provider);
  let full = '';
  try {
    const msgs = [{ role: 'system', content: cfg.sys + TOOL_SYS }, ...conv.msgs.slice(-16)];
    let useTools = true;
    // 工具循环：模型要求调用工具 → 本地执行 → 结果回传 → 再生成，最多 3 轮
    for (let round = 0; round < 4; round++) {
      const res = await fetch(base + '/chat/completions', {
        method: 'POST',
        signal: aborter.signal,
        headers,
        body: JSON.stringify(Object.assign(
          { model, stream: true, messages: msgs },
          useTools ? { tools: TOOLS.map(t => t.def) } : {}
        )),
      });
      if (!res.ok) {
        const t = await res.text();
        // 个别服务商不认 tools 字段：去掉工具重试，保证基础聊天不受影响
        if (useTools && res.status === 400 && round === 0) { useTools = false; round--; continue; }
        throw new Error(`HTTP ${res.status}：${t.slice(0, 200)}`);
      }
      const r = await readStream(res, bubble);
      if (useTools && r.toolCalls.length && round < 3) {
        msgs.push({ role: 'assistant', content: r.content || null, tool_calls: r.toolCalls });
        for (const tc of r.toolCalls) {
          const t = TOOLS.find(x => x.def.function.name === tc.function.name);
          bubble.innerHTML = md('🔎 正在查询站内数据：**' + (t ? t.label : tc.function.name) + '** …');
          $('chat').scrollTop = $('chat').scrollHeight;
          msgs.push({ role: 'tool', tool_call_id: tc.id, content: await runTool(tc) });
        }
        continue;
      }
      full = r.content;
      break;
    }
    if (!full) full = '（模型没有返回内容，请检查模型名称是否正确）';
  } catch (err) {
    if (err.name === 'AbortError') full += '\n\n（已停止）';
    else if (full === '') {
      // 共享通道失败：撤下气泡走三大脑降级，不打错误脸
      if (shared) {
        const m = bubble.closest('.msg'); if (m) m.remove();
        busy = false; aborter = null;
        $('sendBtn').textContent = '发送'; $('sendBtn').classList.remove('stop');
        degrade(conv, /429/.test(err.message) ? '大聪明今日额度已用完' : '大聪明暂时连不上（网络受限时可能这样）');
        return;
      }
      full = `❌ 连接失败：${esc(err.message)}\n\n排查建议：\n1. 密钥是否正确、额度是否用完\n2. 模型名称是否拼写正确\n3. 部分接口不允许网页直连（CORS 限制）`;
    }
  }
  bubble.classList.remove('cursor');
  bubble.innerHTML = md(full);
  const bubbleMsg = bubble.closest('.msg');
  if (bubbleMsg) bubbleMsg._raw = full;
  conv.msgs.push({ role: 'assistant', content: full, brain: cfg.provider });
  conv.ts = Date.now();
  saveConvs(); renderConvs();
  if (cur() === conv) refreshActs();
  busy = false; aborter = null;
  $('sendBtn').textContent = '发送'; $('sendBtn').classList.remove('stop');
}

/* 解析一次 SSE 流：正文增量实时渲染，tool_calls 分片按 index 拼装 */
async function readStream(res, bubble) {
  const reader = res.body.getReader();
  const dec = new TextDecoder();
  let buf = '', content = '';
  const calls = [];
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    const lines = buf.split('\n');
    buf = lines.pop();
    for (const line of lines) {
      const s = line.trim();
      if (!s.startsWith('data:')) continue;
      const data = s.slice(5).trim();
      if (data === '[DONE]') continue;
      try {
        const j = JSON.parse(data);
        const d = j.choices && j.choices[0] && j.choices[0].delta;
        if (!d) continue;
        if (d.content) {
          content += d.content;
          bubble.innerHTML = md(content);
          $('chat').scrollTop = $('chat').scrollHeight;
        }
        if (d.tool_calls) {
          for (const tc of d.tool_calls) {
            const i = tc.index || 0;
            if (!calls[i]) calls[i] = { id: tc.id || ('call_' + i), type: 'function', function: { name: '', arguments: '' } };
            if (tc.id) calls[i].id = tc.id;
            if (tc.function && tc.function.name) calls[i].function.name = tc.function.name;
            if (tc.function && tc.function.arguments) calls[i].function.arguments += tc.function.arguments;
          }
        }
      } catch (e) {}
    }
  }
  return { content, toolCalls: calls.filter(Boolean) };
}

/* 三大脑自动降级：共享通道不可用 → 本地模型（已就绪才接手，不擅自下载几百 MB）→ 离线小智 */
function degrade(conv, reason) {
  if (navigator.gpu && llm && llmModel) {
    addMsg('ai', '⚠️ ' + reason + '，已切到**小机灵**（本机模型）继续 👇');
    replyWebLLM(conv);
    return;
  }
  const lastUser = conv.msgs.filter(m => m.role === 'user').pop();
  const r = '⚠️ ' + reason + '，先由离线小智应急——\n\n' + offlineReply(lastUser ? lastUser.content : '')
    + '\n\n> 想要聪明回答：稍后再试**大聪明**（云端·免费），或在电脑上用**小机灵**（本机模型）。';
  addMsg('ai', r, false, 'offline');
  conv.msgs.push({ role: 'assistant', content: r, brain: 'offline' });
  conv.ts = Date.now();
  saveConvs(); renderConvs();
  if (cur() === conv) refreshActs();
}

/* 浏览器本地模型：加载（含下载进度）→ 流式生成 */
async function replyWebLLM(conv) {
  if (!navigator.gpu) {
    addMsg('ai', '😢 你的浏览器不支持 **WebGPU**，跑不了「小机灵」本机模型（手机浏览器基本都不支持）。\n\n**最省事**：点 ⚙️ 设置换成 **大聪明**（云端 · 免费 · 手机也能用），打开就能聊。\n\n想用小机灵请在电脑上换最新版 Chrome / Edge。');
    return;
  }
  busy = true;
  const stop = { requested: false };
  aborter = { abort: () => { stop.requested = true; if (llm) { try { llm.interruptGenerate(); } catch (e) {} } } };
  $('sendBtn').textContent = '停止'; $('sendBtn').classList.add('stop');
  const bubble = addMsg('ai', '', true, 'webllm');
  let full = '';
  // 本地模型模式用配置的模型；从其他模式降级接手时 cfg.model 不是 WebLLM
  // 模型名，必须用已加载引擎的模型（llmModel），兜底用服务商默认值
  const wllmDefault = PROVIDERS.find(p => p.id === 'webllm').model;
  const useModel = (cfg.provider === 'webllm' ? cfg.model : llmModel) || wllmDefault;
  try {
    const engine = await getEngine(useModel, p => {
      // 下载/编译进度：直接写在气泡里，完成后被正文覆盖
      const pct = p && p.progress ? Math.round(p.progress * 100) + '%' : '';
      bubble.innerHTML = md('⏳ **正在准备本地模型** ' + pct + '\n\n' + (p && p.text ? '`' + p.text.slice(0, 120) + '`' : '')
        + '\n\n首次使用需下载模型文件，之后有缓存秒开。可以先去别的标签页逛逛～');
      $('chat').scrollTop = $('chat').scrollHeight;
    });
    refreshStatus();
    if (!stop.requested) {
      bubble.innerHTML = '';
      const chunks = await engine.chat.completions.create({
        stream: true,
        messages: [{ role: 'system', content: cfg.sys }, ...conv.msgs.slice(-16)],
      });
      for await (const c of chunks) {
        const d = c.choices && c.choices[0] && c.choices[0].delta;
        if (d && d.content) {
          full += d.content;
          bubble.innerHTML = md(full);
          $('chat').scrollTop = $('chat').scrollHeight;
        }
      }
    }
    if (stop.requested) full += (full ? '\n\n' : '') + '（已停止）';
    else if (!full) full = '（模型没有返回内容，请重试）';
  } catch (err) {
    const emsg = String((err && err.message) || err);
    // GPU 崩溃/显存不足（常见于手机跑大模型）：引擎已废，重置以便重试时干净重建
    const gpuDied = /mapAsync|GPUBuffer|device.*lost|out of memory|OOM|Instance dropped/i.test(emsg);
    if (gpuDied && llm) { try { llm.unload(); } catch (e) {} llm = null; llmModel = ''; refreshStatus(); }
    if (full === '') {
      full = gpuDied
        ? `❌ 你的设备带不动「小机灵」本机模型（GPU 报错，手机浏览器基本都会这样）\n\n**最省事**：点 ⚙️ 设置换成 **大聪明**（云端 · 免费 · 手机也能用），打开就能聊。\n\n想继续用小机灵：在电脑上把模型名改成 \`Qwen2.5-0.5B-Instruct-q4f16_1-MLC\`（约 300MB）再点「重新生成」。`
        : `❌ 小机灵出错：${esc(emsg).slice(0, 200)}\n\n换 **大聪明**（云端 · 免费）最省事；想用小机灵请确认电脑浏览器支持 WebGPU，国内网络把下载源切成镜像。`;
    } else full += '\n\n（生成中断）';
  }
  bubble.classList.remove('cursor');
  bubble.innerHTML = md(full);
  const bubbleMsg = bubble.closest('.msg');
  if (bubbleMsg) bubbleMsg._raw = full;
  conv.msgs.push({ role: 'assistant', content: full, brain: 'webllm' });
  conv.ts = Date.now();
  saveConvs(); renderConvs();
  if (cur() === conv) refreshActs();
  busy = false; aborter = null;
  $('sendBtn').textContent = '发送'; $('sendBtn').classList.remove('stop');
}
$('sendBtn').addEventListener('click', send);
$('inp').addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); }
});
function autoSize() {
  const i = $('inp');
  i.style.height = 'auto';
  i.style.height = Math.min(120, i.scrollHeight) + 'px';
}
$('inp').addEventListener('input', autoSize);

/* ===================== 移动端细节 ===================== */
// 窄屏用短占位文案，避免挤压
if (matchMedia('(max-width:480px)').matches) $('inp').placeholder = '输入你的问题…';
// 键盘弹起（视口缩小）时保持聊天贴底，不让最新消息被挡住
if (window.visualViewport) {
  window.visualViewport.addEventListener('resize', () => {
    $('chat').scrollTop = $('chat').scrollHeight;
  });
}
})();
