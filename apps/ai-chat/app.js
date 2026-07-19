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
  { id: 'offline', name: '离线小智（无需密钥 · 应急玩具）', base: '', model: '内置规则引擎',
    help: '不联网、不要密钥的迷你应答机，只会算术、查日期、讲笑话等小本事，应急解闷用 😄' },
];
const DEFAULT_SYS = '你是「万象智聊」里的AI助手，聪明伶俐、博学多才。用中文回答，表达清晰友善，复杂问题分点说明，不确定时诚实说明。';

/* ===================== 配置与历史 ===================== */
let cfg = { provider: 'zhipu', base: PROVIDERS[0].base, model: PROVIDERS[0].model, key: '', sys: DEFAULT_SYS };
try { Object.assign(cfg, JSON.parse(localStorage.getItem('aichat_cfg') || '{}')); } catch (e) {}
let hist = [];
try { hist = JSON.parse(localStorage.getItem('aichat_hist') || '[]'); } catch (e) {}
const saveCfg = () => localStorage.setItem('aichat_cfg', JSON.stringify(cfg));
const saveHist = () => localStorage.setItem('aichat_hist', JSON.stringify(hist.slice(-40)));

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
    <div class="bubble${streaming ? ' cursor' : ''}">${body}</div>`;
  $('msgs').appendChild(div);
  $('chat').scrollTop = $('chat').scrollHeight;
  return div.querySelector('.bubble');
}
function setStatus(t, ok) { $('status').innerHTML = ok ? `<span class="ok">${t}</span>` : t; }
function refreshStatus() {
  const p = PROVIDERS.find(x => x.id === cfg.provider) || PROVIDERS[0];
  if (cfg.provider === 'offline') setStatus('🤖 离线小智模式 · 无需密钥', true);
  else if (cfg.key) setStatus(`已连接：${p.name.split('（')[0]} · ${cfg.model}`, true);
  else setStatus('尚未配置密钥 —— 点右上角 ⚙️ 设置，几分钟即可接入');
}

/* ===================== 欢迎与历史回放 ===================== */
function welcome() {
  addMsg('ai', '你好呀，我是万象智聊 ✨\n\n我可以接入 DeepSeek、智谱 GLM、Kimi、通义千问 等国内大模型（无需特殊网络，注册就送免费额度），也支持海外模型和自定义接口。\n\n**首次使用**：点右上角 ⚙️ 设置 → 选服务商 → 按提示申请一个免费 API 密钥填入即可。密钥只存在你自己的浏览器里。\n\n没有密钥也可以先选「离线小智」模式逗逗它 😄');
}
if (hist.length) hist.forEach(m => addMsg(m.role, m.content));
else welcome();
refreshStatus();

/* ===================== 设置面板 ===================== */
$('cfgProvider').innerHTML = PROVIDERS.map(p => `<option value="${p.id}">${p.name}</option>`).join('');
function fillPanel() {
  $('cfgProvider').value = cfg.provider;
  $('cfgBase').value = cfg.base; $('cfgModel').value = cfg.model;
  $('cfgKey').value = cfg.key; $('cfgSys').value = cfg.sys;
  $('keyHelp').innerHTML = '💡 ' + (PROVIDERS.find(p => p.id === cfg.provider) || PROVIDERS[0]).help;
}
$('cfgProvider').addEventListener('change', () => {
  const p = PROVIDERS.find(x => x.id === $('cfgProvider').value);
  $('cfgBase').value = p.base; $('cfgModel').value = p.model;
  $('keyHelp').innerHTML = '💡 ' + p.help;
});
$('setBtn').addEventListener('click', () => { fillPanel(); $('mask').classList.add('show'); });
$('cancelBtn').addEventListener('click', () => $('mask').classList.remove('show'));
$('saveBtn').addEventListener('click', () => {
  cfg = { provider: $('cfgProvider').value, base: $('cfgBase').value.trim().replace(/\/+$/, ''),
          model: $('cfgModel').value.trim(), key: $('cfgKey').value.trim(), sys: $('cfgSys').value.trim() || DEFAULT_SYS };
  saveCfg(); refreshStatus();
  $('mask').classList.remove('show');
});
$('clearBtn').addEventListener('click', () => {
  hist = []; saveHist(); $('msgs').innerHTML = ''; welcome();
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
  addMsg('user', q);
  hist.push({ role: 'user', content: q });

  if (cfg.provider === 'offline') {
    const r = offlineReply(q);
    setTimeout(() => { addMsg('ai', r); hist.push({ role: 'assistant', content: r }); saveHist(); }, 400);
    saveHist(); return;
  }
  if (!cfg.key || !cfg.base) {
    addMsg('ai', '还没配置密钥哦～点右上角 **⚙️ 设置**，选一个国内服务商（推荐智谱 GLM，有免费模型），按提示申请密钥填入即可。');
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
        messages: [{ role: 'system', content: cfg.sys }, ...hist.slice(-16)],
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
  hist.push({ role: 'assistant', content: full });
  saveHist();
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
