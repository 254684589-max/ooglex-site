/* 万象智聊 —— 连接国内外大模型的轻量聊天站（BYOK：自带密钥） */
(() => {
'use strict';
const $ = id => document.getElementById(id);

/* ===================== 服务商预设（均为 OpenAI 兼容接口） ===================== */
const PROVIDERS = [
  { id: 'zhipu', name: '智谱 GLM（国内 · 有免费模型）', base: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4-flash',
    help: '注册 <a href="https://open.bigmodel.cn" target="_blank">open.bigmodel.cn</a> → 控制台 → API 密钥。glm-4-flash 目前免费。' },
  { id: 'deepseek', name: 'DeepSeek（国内 · 便宜好用）', base: 'https://api.deepseek.com/v1', model: 'deepseek-chat',
    help: '注册 <a href="https://platform.deepseek.com" target="_blank">platform.deepseek.com</a> → API Keys 创建密钥，充值几块钱能用很久。' },
  { id: 'moonshot', name: 'Kimi 月之暗面（国内）', base: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-8k',
    help: '注册 <a href="https://platform.moonshot.cn" target="_blank">platform.moonshot.cn</a> → API Key 管理，新用户送免费额度。' },
  { id: 'qwen', name: '通义千问（国内 · 阿里）', base: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-turbo',
    help: '开通 <a href="https://dashscope.aliyun.com" target="_blank">dashscope.aliyun.com</a> → API-KEY 管理，有免费额度。' },
  { id: 'openai', name: 'OpenAI（海外）', base: 'https://api.openai.com/v1', model: 'gpt-4o-mini',
    help: '需要海外网络与账号：platform.openai.com。' },
  { id: 'custom', name: '自定义（任何兼容接口）', base: '', model: '',
    help: '填入任何 OpenAI 兼容服务的地址与模型名，例如自建的 Ollama（http://localhost:11434/v1）。' },
  { id: 'webllm', name: '浏览器本地模型（免密钥 · 实验）', base: '', model: 'Qwen2.5-1.5B-Instruct-q4f16_1-MLC',
    help: '模型直接在你的设备上运行：<b>无需密钥、聊天内容不出本机、下载后离线可用</b>。首次使用需下载模型文件'
      + '（1.5B 约 900MB，手机可改填 <code>Qwen2.5-0.5B-Instruct-q4f16_1-MLC</code> 约 300MB），之后走本地缓存。'
      + '需要较新的 Chrome / Edge（WebGPU）。国内网络请在下方把模型源切成镜像。' },
  { id: 'offline', name: '离线小智（无需密钥 · 应急玩具）', base: '', model: '内置规则引擎',
    help: '不联网、不要密钥的迷你应答机，只会算术、查日期、讲笑话等小本事，应急解闷用 😄' },
];
const DEFAULT_SYS = '你是「万象智聊」里的AI助手，聪明伶俐、博学多才。用中文回答，表达清晰友善，复杂问题分点说明，不确定时诚实说明。';

/* ===================== 配置与历史 ===================== */
let cfg = { provider: 'zhipu', base: PROVIDERS[0].base, model: PROVIDERS[0].model, key: '', sys: DEFAULT_SYS, src: 'hf' };
try { Object.assign(cfg, JSON.parse(localStorage.getItem('aichat_cfg') || '{}')); } catch (e) {}
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
function addMsg(role, text, streaming) {
  const div = document.createElement('div');
  div.className = 'msg ' + (role === 'user' ? 'user' : 'ai');
  // 用户消息按纯文本原样展示，只有 AI 回复走 Markdown
  const body = role === 'user' ? esc(text) : md(text);
  div.innerHTML = `<div class="av">${role === 'user' ? '🙂' : '✨'}</div>
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
  const p = PROVIDERS.find(x => x.id === cfg.provider) || PROVIDERS[0];
  if (cfg.provider === 'offline') setStatus('🤖 离线小智模式 · 无需密钥', true);
  else if (cfg.provider === 'webllm')
    setStatus('🧠 浏览器本地模型 · ' + cfg.model + (llm && llmModel === cfg.model ? ' · 已就绪' : ' · 首次使用需下载'), true);
  else if (cfg.key) setStatus(`已连接：${p.name.split('（')[0]} · ${cfg.model}`, true);
  else setStatus('尚未配置密钥 —— 点右上角 ⚙️ 设置，几分钟即可接入');
}

/* ===================== 欢迎与会话切换 ===================== */
function welcome() {
  addMsg('ai', '你好呀，我是万象智聊 ✨\n\n我可以接入 DeepSeek、智谱 GLM、Kimi、通义千问 等国内大模型（无需特殊网络，注册就送免费额度），也支持海外模型和自定义接口。\n\n**首次使用**：点右上角 ⚙️ 设置 → 选服务商 → 按提示申请一个免费 API 密钥填入即可。密钥只存在你自己的浏览器里。\n\n没有密钥也可以先选「离线小智」模式逗逗它 😄');
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
  if (c.msgs.length) c.msgs.forEach(m => addMsg(m.role, m.content));
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
  $('srcRow').style.display = pid === 'webllm' ? '' : 'none';
  $('keyRow').style.display = (pid === 'webllm' || pid === 'offline') ? 'none' : '';
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
      if (cur() === conv) addMsg('ai', r);
      conv.msgs.push({ role: 'assistant', content: r });
      saveConvs(); renderConvs();
      if (cur() === conv) refreshActs();
    }, 400);
    return;
  }
  if (!cfg.key || !cfg.base) {
    addMsg('ai', '还没配置密钥哦～点右上角 **⚙️ 设置**，选一个国内服务商（推荐智谱 GLM，有免费模型），按提示申请密钥填入即可。也可以选「浏览器本地模型」，免密钥直接聊。');
    return;
  }

  busy = true; aborter = new AbortController();
  $('sendBtn').textContent = '停止'; $('sendBtn').classList.add('stop');
  const bubble = addMsg('ai', '', true);
  let full = '';
  try {
    const res = await fetch(cfg.base + '/chat/completions', {
      method: 'POST',
      signal: aborter.signal,
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + cfg.key },
      body: JSON.stringify({
        model: cfg.model, stream: true,
        messages: [{ role: 'system', content: cfg.sys }, ...conv.msgs.slice(-16)],
      }),
    });
    if (!res.ok) {
      const t = await res.text();
      throw new Error(`HTTP ${res.status}：${t.slice(0, 200)}`);
    }
    const reader = res.body.getReader();
    const dec = new TextDecoder();
    let buf = '';
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
          if (d && d.content) {
            full += d.content;
            bubble.innerHTML = md(full);
            $('chat').scrollTop = $('chat').scrollHeight;
          }
        } catch (e) {}
      }
    }
    if (!full) full = '（模型没有返回内容，请检查模型名称是否正确）';
  } catch (err) {
    if (err.name === 'AbortError') full += '\n\n（已停止）';
    else if (full === '') {
      full = `❌ 连接失败：${esc(err.message)}\n\n排查建议：\n1. 密钥是否正确、额度是否用完\n2. 模型名称是否拼写正确\n3. 个别服务商不允许网页直连（CORS 限制），可换 DeepSeek / 智谱试试`;
    }
  }
  bubble.classList.remove('cursor');
  bubble.innerHTML = md(full);
  const bubbleMsg = bubble.closest('.msg');
  if (bubbleMsg) bubbleMsg._raw = full;
  conv.msgs.push({ role: 'assistant', content: full });
  conv.ts = Date.now();
  saveConvs(); renderConvs();
  if (cur() === conv) refreshActs();
  busy = false; aborter = null;
  $('sendBtn').textContent = '发送'; $('sendBtn').classList.remove('stop');
}

/* 浏览器本地模型：加载（含下载进度）→ 流式生成 */
async function replyWebLLM(conv) {
  if (!navigator.gpu) {
    addMsg('ai', '你的浏览器不支持 **WebGPU**，跑不动本地模型 😢\n\n建议：\n1. 换最新版 Chrome / Edge 浏览器再试\n2. 或在 ⚙️ 设置里选择其他服务商（如智谱 GLM，有免费模型）');
    return;
  }
  busy = true;
  const stop = { requested: false };
  aborter = { abort: () => { stop.requested = true; if (llm) { try { llm.interruptGenerate(); } catch (e) {} } } };
  $('sendBtn').textContent = '停止'; $('sendBtn').classList.add('stop');
  const bubble = addMsg('ai', '', true);
  let full = '';
  try {
    const engine = await getEngine(cfg.model, p => {
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
    if (full === '') {
      full = `❌ 本地模型加载失败：${esc(String(err && err.message || err)).slice(0, 300)}\n\n排查建议：\n1. 国内网络请在 ⚙️ 设置把「模型下载源」切成镜像\n2. 确认浏览器是最新版 Chrome / Edge（需要 WebGPU）\n3. 内存不足可改用小模型 \`Qwen2.5-0.5B-Instruct-q4f16_1-MLC\`\n4. 或选择其他服务商接入大模型`;
    } else full += '\n\n（生成中断）';
  }
  bubble.classList.remove('cursor');
  bubble.innerHTML = md(full);
  const bubbleMsg = bubble.closest('.msg');
  if (bubbleMsg) bubbleMsg._raw = full;
  conv.msgs.push({ role: 'assistant', content: full });
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
