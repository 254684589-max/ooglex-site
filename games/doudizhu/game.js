/* 欢乐斗地主 · 单机版（纯前端）
 * 完整规则引擎（单/对/三/三带/顺子/连对/飞机/四带二/炸弹/王炸）+ 抢地主 + 两个 AI 对手
 * + 精美牌桌 UI + Web Audio 背景音乐与音效。点牌选中，出牌/不出/提示。 */
(function () {
  "use strict";
  var $ = function (s) { return document.querySelector(s); };
  function setText(id, t) { var e = document.getElementById(id); if (e) e.textContent = t; }
  function show(id, on) { var e = document.getElementById(id); if (e) e.style.display = on ? "" : "none"; }

  var RTXT = { 3: "3", 4: "4", 5: "5", 6: "6", 7: "7", 8: "8", 9: "9", 10: "10", 11: "J", 12: "Q", 13: "K", 14: "A", 15: "2", 16: "小", 17: "大" };
  var SUITORD = { "♠": 0, "♥": 1, "♣": 2, "♦": 3 };
  function cmpCard(a, b) { return a.r - b.r || ((SUITORD[a.suit] || 0) - (SUITORD[b.suit] || 0)); }

  /* ----------------------------------------------------------------- 音频引擎 */
  var Audio0 = (function () {
    var ac = null, master = null, bgmOn = false, bgmTimer = null, step = 0;
    function ensure() {
      if (ac) return;
      ac = new (window.AudioContext || window.webkitAudioContext)();
      master = ac.createGain(); master.gain.value = 0.9; master.connect(ac.destination);
    }
    function tone(freq, dur, type, vol, when, glide) {
      ensure(); var t = ac.currentTime + (when || 0);
      var o = ac.createOscillator(), g = ac.createGain();
      o.type = type || "sine"; o.frequency.setValueAtTime(freq, t);
      if (glide) o.frequency.exponentialRampToValueAtTime(glide, t + dur);
      g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(vol || 0.2, t + 0.012);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(g); g.connect(master); o.start(t); o.stop(t + dur + 0.03);
    }
    function noise(dur, vol, when) {
      ensure(); var t = ac.currentTime + (when || 0);
      var n = ac.createBufferSource(), b = ac.createBuffer(1, ac.sampleRate * dur, ac.sampleRate), d = b.getChannelData(0);
      for (var i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
      n.buffer = b; var g = ac.createGain(); g.gain.setValueAtTime(vol || 0.3, t); g.gain.exponentialRampToValueAtTime(0.001, t + dur);
      var f = ac.createBiquadFilter(); f.type = "lowpass"; f.frequency.setValueAtTime(1400, t); f.frequency.exponentialRampToValueAtTime(180, t + dur);
      n.connect(f); f.connect(g); g.connect(master); n.start(t); n.stop(t + dur);
    }
    var sfx = {
      deal: function () { for (var i = 0; i < 4; i++) tone(680 + i * 80, 0.05, "triangle", 0.10, i * 0.045); },
      select: function () { tone(900, 0.05, "sine", 0.10); },
      play: function () { tone(520, 0.08, "triangle", 0.18); tone(800, 0.06, "sine", 0.09, 0.02); },
      pass: function () { tone(320, 0.13, "sine", 0.13, 0, 210); },
      grab: function () { tone(440, 0.10, "sawtooth", 0.18); tone(660, 0.10, "sawtooth", 0.18, 0.09); tone(880, 0.18, "sawtooth", 0.20, 0.18); },
      bomb: function () { noise(0.45, 0.5); tone(110, 0.45, "square", 0.25, 0, 45); },
      rocket: function () { noise(0.65, 0.42); tone(180, 0.55, "sawtooth", 0.22, 0, 1100); },
      win: function () {[523, 659, 784, 1047].forEach(function (f, i) { tone(f, 0.22, "triangle", 0.2, i * 0.12); }); },
      lose: function () {[440, 370, 294].forEach(function (f, i) { tone(f, 0.3, "sine", 0.18, i * 0.16); }); },
      landlord: function () { tone(330, 0.12, "sawtooth", 0.16); tone(494, 0.2, "sawtooth", 0.18, 0.1); tone(660, 0.22, "sawtooth", 0.16, 0.22); }
    };
    var MEL = [[523, 1], [587, 1], [659, 2], [587, 1], [523, 1], [440, 2], [392, 1], [440, 1], [523, 2], [659, 1], [784, 1], [659, 2], [587, 2]];
    function tick() {
      if (!bgmOn) return;
      var nt = MEL[step % MEL.length], dur = nt[1] * 0.27;
      tone(nt[0], dur * 0.92, "triangle", 0.05); tone(nt[0] / 2, dur * 0.92, "sine", 0.045);
      step++; bgmTimer = setTimeout(tick, dur * 1000);
    }
    return {
      start: function () { ensure(); if (ac.state === "suspended") ac.resume(); },
      sfx: sfx,
      bgm: function (on) { bgmOn = on; if (on) { if (!bgmTimer) tick(); } else if (bgmTimer) { clearTimeout(bgmTimer); bgmTimer = null; } }
    };
  })();
  var sfx = Audio0.sfx;

  /* ----------------------------------------------------------------- 牌型引擎 */
  function byRank(hand) { var m = {}; hand.forEach(function (c) { (m[c.r] = m[c.r] || []).push(c); }); return m; }
  function isConsec(a) { for (var i = 1; i < a.length; i++) if (a[i] !== a[i - 1] + 1) return false; return true; }

  // 解析一组牌 → {type, rank, len}；非法返回 null
  function getCombo(cards) {
    if (!cards || !cards.length) return null;
    var n = cards.length, cnt = {}, r;
    cards.forEach(function (c) { cnt[c.r] = (cnt[c.r] || 0) + 1; });
    var ranks = Object.keys(cnt).map(Number).sort(function (a, b) { return a - b; });
    var has = function (k) { return ranks.filter(function (r) { return cnt[r] === k; }); };
    if (n === 2 && cnt[16] && cnt[17]) return { type: "rocket", rank: 100, len: 1 };
    if (n === 4 && ranks.length === 1) return { type: "bomb", rank: ranks[0], len: 1 };
    if (n === 1) return { type: "single", rank: ranks[0], len: 1 };
    if (n === 2 && ranks.length === 1) return { type: "pair", rank: ranks[0], len: 1 };
    if (n === 3 && ranks.length === 1) return { type: "triple", rank: ranks[0], len: 1 };
    if (n === 4) { var t = has(3); if (t.length === 1) return { type: "triple1", rank: t[0], len: 1 }; }
    if (n === 5) { var t3 = has(3), p2 = has(2); if (t3.length === 1 && p2.length === 1) return { type: "triple2", rank: t3[0], len: 1 }; }
    if (n >= 5 && ranks.length === n && isConsec(ranks) && ranks[n - 1] <= 14) return { type: "straight", rank: ranks[0], len: n };
    if (n >= 6 && n % 2 === 0 && ranks.every(function (r) { return cnt[r] === 2; }) && isConsec(ranks) && ranks[ranks.length - 1] <= 14)
      return { type: "straight2", rank: ranks[0], len: ranks.length };
    var trips = has(3).sort(function (a, b) { return a - b; });
    if (trips.length >= 2 && isConsec(trips) && trips[trips.length - 1] <= 14) {
      var m = trips.length;
      if (n === 3 * m) return { type: "plane", rank: trips[0], len: m };
      if (n === 4 * m) return { type: "plane1", rank: trips[0], len: m };           // 飞机带单
      if (n === 5 * m) {
        var others = ranks.filter(function (r) { return trips.indexOf(r) < 0; });
        if (others.length === m && others.every(function (r) { return cnt[r] === 2; })) return { type: "plane2", rank: trips[0], len: m };
      }
    }
    var fours = has(4);
    if (fours.length === 1) {
      if (n === 6) return { type: "four2", rank: fours[0], len: 1 };                 // 四带二单
      if (n === 8) { var o2 = ranks.filter(function (r) { return r !== fours[0]; }); if (o2.length === 2 && o2.every(function (r) { return cnt[r] === 2; })) return { type: "four22", rank: fours[0], len: 1 }; }
    }
    return null;
  }

  function beats(a, b) {
    if (!a) return false;
    if (!b) return true;
    if (a.type === "rocket") return true;
    if (b.type === "rocket") return false;
    if (a.type === "bomb" && b.type !== "bomb") return true;
    if (a.type === "bomb" && b.type === "bomb") return a.rank > b.rank;
    if (b.type === "bomb") return false;
    return a.type === b.type && a.len === b.len && a.rank > b.rank;
  }

  // 选配角牌（带牌）：每组 size 张、共 count 组，优先不拆炸弹/大牌
  function kickVal(m, r) { var v = r; var L = m[r].length; if (L === 4) v += 100; if (r >= 16) v += 60; if (L === 3) v += 20; if (L === 2) v += 8; return v; }
  function pickKickers(m, exclude, size, count) {
    var cand = Object.keys(m).map(Number).filter(function (r) { return exclude.indexOf(r) < 0 && m[r].length >= size; })
      .sort(function (a, b) { return kickVal(m, a) - kickVal(m, b); });
    var out = [];
    for (var i = 0; i < cand.length && out.length < size * count; i++) out = out.concat(m[cand[i]].slice(0, size));
    return out.length >= size * count ? out.slice(0, size * count) : null;
  }
  function genStraights(m, len, minStart) {
    var out = []; for (var s = Math.max(3, minStart + 1); s + len - 1 <= 14; s++) {
      var ok = true, mv = []; for (var r = s; r < s + len; r++) { if (!m[r] || m[r].length < 1) { ok = false; break; } mv.push(m[r][0]); }
      if (ok) out.push(mv);
    } return out;
  }
  function genStraight2(m, len, minStart) {
    var out = []; for (var s = Math.max(3, minStart + 1); s + len - 1 <= 14; s++) {
      var ok = true, mv = []; for (var r = s; r < s + len; r++) { if (!m[r] || m[r].length < 2) { ok = false; break; } mv = mv.concat(m[r].slice(0, 2)); }
      if (ok) out.push(mv);
    } return out;
  }
  function genPlanes(m, last) {
    var k = last.len, out = [];
    for (var s = last.rank + 1; s + k - 1 <= 14; s++) {
      var ok = true, base = [], ex = [], r;
      for (r = s; r < s + k; r++) { if (!m[r] || m[r].length < 3) { ok = false; break; } base = base.concat(m[r].slice(0, 3)); ex.push(r); }
      if (!ok) continue;
      if (last.type === "plane") out.push(base);
      else if (last.type === "plane1") { var w = pickKickers(m, ex, 1, k); if (w) out.push(base.concat(w)); }
      else if (last.type === "plane2") { var w2 = pickKickers(m, ex, 2, k); if (w2) out.push(base.concat(w2)); }
    } return out;
  }
  function genFourTwo(m, last) {
    var out = [];
    Object.keys(m).map(Number).filter(function (r) { return m[r].length === 4 && r > last.rank; }).sort(function (a, b) { return a - b; }).forEach(function (r) {
      var base = m[r].slice(0, 4), w = last.type === "four2" ? pickKickers(m, [r], 1, 2) : pickKickers(m, [r], 2, 2);
      if (w) out.push(base.concat(w));
    }); return out;
  }
  // 所有能压过 last 的走法；last 为 null 时返回领出建议
  function genBeats(hand, last) {
    var m = byRank(hand), res = [], ranks = Object.keys(m).map(Number).sort(function (a, b) { return a - b; });
    if (!last) return [chooseLead(hand)];
    if (last.type === "rocket") return [];
    switch (last.type) {
      case "single": ranks.forEach(function (r) { if (r > last.rank) res.push([m[r][0]]); }); break;
      case "pair": ranks.forEach(function (r) { if (r > last.rank && m[r].length >= 2) res.push(m[r].slice(0, 2)); }); break;
      case "triple": ranks.forEach(function (r) { if (r > last.rank && m[r].length >= 3) res.push(m[r].slice(0, 3)); }); break;
      case "triple1": ranks.forEach(function (r) { if (r > last.rank && m[r].length >= 3) { var w = pickKickers(m, [r], 1, 1); if (w) res.push(m[r].slice(0, 3).concat(w)); } }); break;
      case "triple2": ranks.forEach(function (r) { if (r > last.rank && m[r].length >= 3) { var w = pickKickers(m, [r], 2, 1); if (w) res.push(m[r].slice(0, 3).concat(w)); } }); break;
      case "straight": genStraights(m, last.len, last.rank).forEach(function (x) { res.push(x); }); break;
      case "straight2": genStraight2(m, last.len, last.rank).forEach(function (x) { res.push(x); }); break;
      case "plane": case "plane1": case "plane2": genPlanes(m, last).forEach(function (x) { res.push(x); }); break;
      case "four2": case "four22": genFourTwo(m, last).forEach(function (x) { res.push(x); }); break;
    }
    ranks.forEach(function (r) { if (m[r].length === 4 && (last.type !== "bomb" || r > last.rank)) res.push(m[r].slice(0, 4)); }); // 炸弹
    if (m[16] && m[17]) res.push([m[16][0], m[17][0]]); // 王炸
    return res;
  }
  // 领出建议（AI/提示用）
  function chooseLead(hand) {
    var m = byRank(hand), ranks = Object.keys(m).map(Number).sort(function (a, b) { return a - b; });
    if (getCombo(hand)) return hand.slice();                       // 能一手出完
    for (var len = Math.min(8, ranks.length); len >= 5; len--) {   // 低顺子
      var s = genStraights(m, len, 2); if (s.length && s[0][0].r <= 9) return s[0];
    }
    var cand = ranks.filter(function (r) { return r < 15; }); if (!cand.length) cand = ranks;
    var pure = cand.filter(function (r) { return m[r].length === 1; });
    var pick = pure.length ? pure[0] : cand[0];
    return m[pick].slice(0, 1);
  }

  /* ----------------------------------------------------------------- 游戏状态 */
  var G = {
    hands: [[], [], []], bottom: [], landlord: null, turn: 0, lastPlayer: null, lastCombo: null,
    phase: "idle", multiplier: 1, beans: 1000, passStreak: 0, plays: [0, 0, 0],
    selected: new Set(), hint: [], hintIdx: 0, revealBottom: false, bidStart: 0, order: [], bi: 0, lastGrabber: null, grabCount: 0
  };
  var NAMES = ["你", "大聪明", "小机灵"]; // index 0 me, 1 right, 2 left
  function seatName(p) { return NAMES[p]; }
  function isLandlord(p) { return p === G.landlord; }
  function sameSide(a, b) { return (a === G.landlord) === (b === G.landlord); }
  function zoneOf(p) { return p === 0 ? "#zMe" : (p === 1 ? "#zR" : "#zL"); }

  function deal() {
    var deck = [], id = 0, suits = ["♠", "♥", "♣", "♦"], r, s;
    for (r = 3; r <= 15; r++) for (s = 0; s < 4; s++) deck.push({ id: id++, r: r, suit: suits[s] });
    deck.push({ id: id++, r: 16, suit: "" }); deck.push({ id: id++, r: 17, suit: "" });
    for (var i = deck.length - 1; i > 0; i--) { var j = Math.floor(Math.random() * (i + 1)); var t = deck[i]; deck[i] = deck[j]; deck[j] = t; }
    G.hands = [deck.slice(0, 17), deck.slice(17, 34), deck.slice(34, 51)]; G.bottom = deck.slice(51, 54);
    G.hands.forEach(function (h) { h.sort(cmpCard); }); G.bottom.sort(cmpCard);
  }

  /* ----------------------------------------------------------------- 渲染 */
  function cardHTML(c, opt) {
    opt = opt || {}; var sm = opt.small ? " small" : "", sel = opt.sel ? " sel" : "";
    var style = opt.ml != null ? ' style="margin-left:' + opt.ml + 'px"' : "";
    if (c.r >= 16) { var red = c.r === 17; return '<div class="c jok ' + (red ? "red" : "blk") + sm + sel + '" data-id="' + c.id + '"' + style + '><div class="r">' + (red ? "大" : "小") + '</div><div class="big">王</div></div>'; }
    var rd = (c.suit === "♥" || c.suit === "♦");
    return '<div class="c ' + (rd ? "red" : "blk") + sm + sel + '" data-id="' + c.id + '"' + style + '><div class="r">' + RTXT[c.r] + '</div><div class="s">' + c.suit + '</div><div class="big">' + c.suit + '</div></div>';
  }
  function back(small) { return '<div class="c' + (small ? " small" : "") + '" style="background:repeating-linear-gradient(45deg,#b23a2e 0 6px,#9c2f25 6px 12px);border-color:rgba(0,0,0,.3)"></div>'; }

  function renderHand() {
    var hand = G.hands[0].slice().sort(cmpCard), el = $("#hand");
    var W = Math.min(el.clientWidth || 520, 540) - 10, cw = 46, n = hand.length, ov = 24;
    if (n > 1) { var need = (n * cw - W) / (n - 1); ov = Math.max(16, Math.min(34, need)); }
    el.innerHTML = hand.map(function (c, i) { return cardHTML(c, { sel: G.selected.has(c.id), ml: i === 0 ? 0 : -ov }); }).join("");
  }
  function renderBottom() {
    var el = $("#zBottom"); if (G.phase === "idle") { el.innerHTML = ""; return; }
    var lbl = '<span class="lbl">底牌</span>';
    el.innerHTML = lbl + (G.revealBottom ? G.bottom.map(function (c) { return cardHTML(c, { small: true }); }).join("")
      : G.bottom.map(function () { return back(true); }).join(""));
  }
  function renderMini() {
    [["L", 2], ["R", 1]].forEach(function (x) {
      var n = G.hands[x[1]].length, k = Math.max(0, Math.min(8, n));
      document.getElementById("mini" + x[0]).innerHTML = new Array(k).fill('<i></i>').join("");
    });
  }
  function updateUI() {
    setText("cntMe", G.hands[0].length); setText("cntR", G.hands[1].length); setText("cntL", G.hands[2].length);
    show("crMe", G.landlord === 0); show("crR", G.landlord === 1); show("crL", G.landlord === 2);
    setText("meRole", G.landlord == null ? "—" : (G.landlord === 0 ? "地主" : "农民"));
    $("#seatR").classList.toggle("turn", G.turn === 1 && G.phase !== "over");
    $("#seatL").classList.toggle("turn", G.turn === 2 && G.phase !== "over");
    setText("multi", "底分 1 · 倍数 " + G.multiplier); setText("beanv", G.beans);
    renderBottom(); renderMini(); renderHand();
  }
  function showPlayed(p, mv) { $(zoneOf(p)).innerHTML = mv.slice().sort(cmpCard).map(function (c, i) { return cardHTML(c, { small: true, ml: i === 0 ? 0 : -26 }); }).join(""); }
  function clearPlayed(p) { $(zoneOf(p)).innerHTML = ""; }
  function clearAllPlayed() {[0, 1, 2].forEach(clearPlayed); }
  var bubTimers = {};
  function bubble(p, text, cls) {
    if (p === 0) { $("#zMe").innerHTML = '<span class="bubble show ' + (cls || "") + '">' + text + "</span>"; return; }
    var el = document.getElementById(p === 1 ? "bubR" : "bubL");
    el.className = "bubble show " + (cls || ""); el.textContent = text;
    clearTimeout(bubTimers[p]); bubTimers[p] = setTimeout(function () { el.className = "bubble"; }, 1300);
  }
  function flash(text) { $("#msg").innerHTML = "<span>" + text + "</span>"; setTimeout(function () { var m = $("#msg"); if (m.firstChild) m.innerHTML = ""; }, 950); }

  /* ----------------------------------------------------------------- 控制条 */
  function btn(label, cls, fn) { var b = document.createElement("button"); b.className = "btn " + (cls || ""); b.textContent = label; b.onclick = fn; return b; }
  function renderControls(mode) {
    var c = $("#controls"); c.innerHTML = "";
    if (mode === "bid") {
      c.appendChild(btn(G.lastGrabber === null ? "叫地主" : "抢地主", "gold", function () { renderControls("wait"); humanBid(true); }));
      c.appendChild(btn("不抢", "gray", function () { renderControls("wait"); humanBid(false); }));
    } else if (mode === "play") {
      var pb = btn("出牌", "", humanPlay); pb.id = "btnPlay"; c.appendChild(pb);
      if (G.lastCombo) c.appendChild(btn("不出", "gray", function () { clearSel(); doPass(0); }));
      c.appendChild(btn("提示", "gray", humanHint));
      updatePlayBtn();
    }
  }
  function selCards() { var ids = G.selected; return G.hands[0].filter(function (c) { return ids.has(c.id); }); }
  function clearSel() { G.selected.clear(); G.hint = []; }
  function updatePlayBtn() {
    var b = document.getElementById("btnPlay"); if (!b) return;
    var combo = getCombo(selCards());
    b.disabled = !(combo && (G.lastCombo === null || beats(combo, G.lastCombo)));
  }

  /* ----------------------------------------------------------------- 人类操作 */
  function onHandClick(e) {
    if (G.phase !== "play" || G.turn !== 0) return;
    var card = e.target.closest(".c"); if (!card) return;
    var id = +card.getAttribute("data-id");
    if (G.selected.has(id)) G.selected.delete(id); else { G.selected.add(id); sfx.select(); }
    G.hint = []; renderHand(); updatePlayBtn();
  }
  function humanPlay() {
    var mv = selCards(), combo = getCombo(mv);
    if (!combo) { flash("牌型不对"); return; }
    if (G.lastCombo && !beats(combo, G.lastCombo)) { flash("管不上"); return; }
    clearSel(); doPlay(0, mv);
  }
  function humanHint() {
    var cand = G.lastCombo ? genBeats(G.hands[0], G.lastCombo) : [chooseLead(G.hands[0])];
    cand = cand.filter(Boolean);
    if (!cand.length) { flash(G.lastCombo ? "要不起" : "无牌可出"); return; }
    cand.sort(function (a, b) { var ca = getCombo(a), cb = getCombo(b); var ba = (ca.type === "bomb" || ca.type === "rocket") ? 1 : 0, bb = (cb.type === "bomb" || cb.type === "rocket") ? 1 : 0; return ba - bb || a.length - b.length || ca.rank - cb.rank; });
    var mv = cand[G.hintIdx % cand.length]; G.hintIdx++;
    G.selected = new Set(mv.map(function (c) { return c.id; })); renderHand(); updatePlayBtn();
  }

  /* ----------------------------------------------------------------- AI */
  function smallest(moves) {
    return moves.slice().sort(function (a, b) {
      var ca = getCombo(a), cb = getCombo(b);
      var ba = (ca.type === "bomb" || ca.type === "rocket") ? 1 : 0, bb = (cb.type === "bomb" || cb.type === "rocket") ? 1 : 0;
      return ba - bb || ca.rank - cb.rank || a.length - b.length;
    })[0];
  }
  function aiTurn(p) {
    var hand = G.hands[p];
    if (G.lastCombo === null) return chooseLead(hand);
    var arr = genBeats(hand, G.lastCombo);
    var fin = arr.filter(function (mv) { return mv.length === hand.length; });
    if (fin.length) return smallest(fin);
    if (sameSide(p, G.lastPlayer)) return null;            // 队友占着，过
    if (!arr.length) return null;
    var nb = arr.filter(function (mv) { var t = getCombo(mv).type; return t !== "bomb" && t !== "rocket"; });
    if (nb.length) {
      var oppMin = Math.min.apply(null, [0, 1, 2].filter(function (x) { return x !== p && !sameSide(p, x); }).map(function (x) { return G.hands[x].length; }));
      // 对手快走完时，倾向用大牌压；否则出最小能压的
      return (oppMin <= 2 && hand.length <= 10) ? nb[nb.length - 1] : smallest(nb);
    }
    var oppLow = Math.min.apply(null, [0, 1, 2].filter(function (x) { return x !== p && !sameSide(p, x); }).map(function (x) { return G.hands[x].length; }));
    if (oppLow <= 2 || hand.length <= 5) return smallest(arr); // 只剩炸弹，关键时刻才炸
    return null;
  }

  /* ----------------------------------------------------------------- 出牌 / 过 */
  function comboName(c) {
    return { single: "单", pair: "对子", triple: "三条", triple1: "三带一", triple2: "三带二", straight: "顺子", straight2: "连对", plane: "飞机", plane1: "飞机带单", plane2: "飞机带对", four2: "四带二", four22: "四带两对", bomb: "炸弹", rocket: "王炸" }[c.type] || "";
  }
  function doPlay(p, mv) {
    var combo = getCombo(mv);
    var ids = {}; mv.forEach(function (c) { ids[c.id] = 1; });
    G.hands[p] = G.hands[p].filter(function (c) { return !ids[c.id]; });
    G.lastPlayer = p; G.lastCombo = combo; G.passStreak = 0; G.plays[p]++;
    if (combo.type === "bomb") { G.multiplier *= 2; sfx.bomb(); flash("💥 炸弹"); }
    else if (combo.type === "rocket") { G.multiplier *= 2; sfx.rocket(); flash("🚀 王炸"); }
    else sfx.play();
    showPlayed(p, mv); if (p !== 0) bubble(p, comboName(combo));
    updateUI();
    if (G.hands[p].length === 0) { return endGame(p); }
    G.turn = (p + 1) % 3; step();
  }
  function doPass(p) {
    sfx.pass(); bubble(p, "不出", "pass");
    G.passStreak++;
    if (G.passStreak >= 2) { G.turn = G.lastPlayer; G.lastCombo = null; G.passStreak = 0; setTimeout(clearAllPlayed, 350); }
    else G.turn = (p + 1) % 3;
    updateUI(); step();
  }
  function step() {
    if (G.phase !== "play") return;
    updateUI();
    if (G.turn === 0) { renderControls("play"); }
    else { renderControls("wait"); setTimeout(function () { if (G.phase !== "play") return; var mv = aiTurn(G.turn); if (mv && mv.length) doPlay(G.turn, mv); else doPass(G.turn); }, 750); }
  }

  /* ----------------------------------------------------------------- 抢地主 */
  function handStrength(hand) {
    var m = byRank(hand), s = 0; if (m[17]) s += 7; if (m[16]) s += 5;
    s += (m[15] ? m[15].length : 0) * 2; s += (m[14] ? m[14].length : 0);
    Object.keys(m).forEach(function (r) { if (m[r].length === 4) s += 8; });
    return s;
  }
  function aiBid(hand) { var s = handStrength(hand); return s >= 8 || (s >= 5 && Math.random() < 0.45); }
  function startBidding() {
    G.phase = "bid"; G.order = [G.bidStart, (G.bidStart + 1) % 3, (G.bidStart + 2) % 3]; G.bi = 0; G.lastGrabber = null; G.grabCount = 0;
    flash("抢 地 主"); updateUI(); setTimeout(bidStep, 950);
  }
  function bidStep() {
    if (G.bi >= 3) return finishBid();
    var p = G.order[G.bi]; G.turn = p; updateUI();
    if (p === 0) renderControls("bid");
    else { renderControls("wait"); setTimeout(function () { applyBid(p, aiBid(G.hands[p])); }, 850); }
  }
  function humanBid(grab) { applyBid(0, grab); }
  function applyBid(p, grab) {
    if (grab) { sfx.grab(); bubble(p, G.lastGrabber === null ? "叫地主" : "抢地主", "rob"); G.lastGrabber = p; G.grabCount++; }
    else { sfx.pass(); bubble(p, "不抢", "pass"); }
    G.bi++; setTimeout(bidStep, 750);
  }
  function finishBid() {
    if (G.lastGrabber === null) { flash("都不抢 · 重发"); setTimeout(function () { newGame(true); }, 1200); return; }
    G.landlord = G.lastGrabber; G.multiplier = Math.max(1, Math.pow(2, G.grabCount - 1));
    G.hands[G.landlord] = G.hands[G.landlord].concat(G.bottom); G.hands[G.landlord].sort(cmpCard);
    G.revealBottom = true; sfx.landlord();
    G.phase = "play"; G.turn = G.landlord; G.lastPlayer = null; G.lastCombo = null; G.passStreak = 0; G.plays = [0, 0, 0];
    flash((G.landlord === 0 ? "你" : seatName(G.landlord)) + " 当地主");
    updateUI(); setTimeout(step, 1150);
  }

  /* ----------------------------------------------------------------- 结算 */
  function endGame(winner) {
    G.phase = "over"; $("#controls").innerHTML = "";
    var llWon = (winner === G.landlord), farmers = [0, 1, 2].filter(function (x) { return x !== G.landlord; });
    var spring = 1;
    if (llWon && G.plays[farmers[0]] === 0 && G.plays[farmers[1]] === 0) spring = 2;       // 春天
    if (!llWon && G.plays[G.landlord] <= 1) spring = 2;                                     // 反春天
    G.multiplier *= spring;
    var delta = G.multiplier, mine;
    if (G.landlord === 0) mine = llWon ? 2 * delta : -2 * delta; else mine = llWon ? -delta : delta;
    G.beans = Math.max(0, G.beans + mine); saveBeans();
    updateUI(); G.revealBottom = true;
    var meWon = mine > 0; sfx[meWon ? "win" : "lose"]();
    showResult('<div class="res">' + (meWon ? "🎉" : "😵") + '</div><h1>' + (llWon ? "地主 胜！" : "农民 胜！") + "</h1>"
      + '<div class="sub">' + (spring > 1 ? "🌸 春天 ×2　" : "") + "倍数 ×" + G.multiplier + "<br>你"
      + (mine >= 0 ? "赢得 " : "输掉 ") + '<b style="color:var(--gold)">' + Math.abs(mine) + "</b> 🫘（剩余 " + G.beans + "）</div>"
      + '<button class="btn big gold" id="btnAgain">🔄 再来一局</button>');
    document.getElementById("btnAgain").onclick = function () { hideOverlay(); newGame(false); };
  }

  /* ----------------------------------------------------------------- 局面控制 */
  function newGame(redeal) {
    clearSel(); clearAllPlayed(); ["bubL", "bubR"].forEach(function (id) { document.getElementById(id).className = "bubble"; });
    G.landlord = null; G.lastPlayer = null; G.lastCombo = null; G.revealBottom = false; G.multiplier = 1; G.plays = [0, 0, 0]; G.hintIdx = 0;
    if (!redeal) G.bidStart = (G.bidStart + 1) % 3;
    deal(); sfx.deal(); G.phase = "deal"; updateUI(); startBidding();
  }
  function showResult(html) { var o = $("#ov"); o.innerHTML = html; o.classList.remove("hide"); }
  function hideOverlay() { $("#ov").classList.add("hide"); }
  function loadBeans() { try { var v = +localStorage.getItem("ddz_beans"); if (v > 0) G.beans = v; } catch (e) {} }
  function saveBeans() { try { localStorage.setItem("ddz_beans", G.beans); } catch (e) {} }

  /* ----------------------------------------------------------------- 启动 */
  function init() {
    loadBeans();
    $("#hand").addEventListener("click", onHandClick);
    var musicOn = true;
    document.getElementById("btnMusic").onclick = function () {
      musicOn = !musicOn; this.classList.toggle("on", musicOn); Audio0.bgm(musicOn);
    };
    document.getElementById("btnStart").onclick = function () {
      Audio0.start(); Audio0.bgm(true); hideOverlay(); newGame(false);
    };
    updateUI();
  }
  if (typeof document !== "undefined") {
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init); else init();
  }
  // 引擎导出（供无界面环境做规则自检；浏览器中仅在 window 上挂一份调试句柄，无副作用）
  if (typeof globalThis !== "undefined") globalThis.DDZ = { getCombo: getCombo, beats: beats, genBeats: genBeats, byRank: byRank, chooseLead: chooseLead };
})();

