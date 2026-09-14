/* ===========================================================================
   OOGLEX 终端公共层 · Terminal Core
   ---------------------------------------------------------------------------
   两个数据模型（overview.js 横向总览 / security.js 纵向单标的）共用的口径。
   合并前 ds/feed.js 与 chrome/data.js 各写了一遍 soft / fmt / isNum /
   statusZh / UNAVAILABLE —— 当时两边输出恰好一致，但那是巧合不是设计，
   两份拷贝迟早漂移。现在只有这一份。

   口径规则（改这里就等于改全终端）
   -------------------------------
   · 单源失败只影响对应区块：失败的源返回 {__error}，页面各自显示失败态，
     绝不以零值或占位数字静默覆盖。
   · 盘中快照自带 realtime:false，只标「快照 30M」，绝不标「实时」。
   · 站内没有的字段在 UNAVAILABLE 里统一声明，页面据此写「无来源·不显示」。
   · 派生值（利差、Z-Score、分位、信号判定）一律标注算法与窗口，可由原始字段复现。
   =========================================================================== */
(function (global) {
  "use strict";

  var BASE = global.OOGLEX_TERMINAL_BASE || "/apps/";

  function isNum(x) { return typeof x === "number" && isFinite(x); }

  function getJSON(p) {
    return fetch(BASE + p).then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status + " " + p);
      return r.json();
    });
  }
  /* 单源失败不拖垮整页 */
  function soft(p) {
    return getJSON(p).catch(function (e) { return { __error: String(e.message || e) }; });
  }

  /* 纯函数：按片号改写历史文件路径。公司完整历史按市值名次每 100 家一片，
     第 1 片沿用原文件名，其余加 -N，与 apps/finance-terminal 的行情页和采集管道一致。
     片号缺失或不是大于 1 的整数就退回第 1 片：宁可多取一片取不到，也不要拼出乱路径。 */
  function shardPath(path, shard) {
    var i = Number(shard);
    if (!isFinite(i) || Math.floor(i) !== i || i <= 1) return path;
    return path.replace(/\.json$/, "-" + i + ".json");
  }

  /* ── 格式化（原来两边各一份，现在合成一份超集）────────────────────── */
  var fmt = {
    px: function (x) {
      if (!isNum(x)) return "—";
      var a = Math.abs(x);
      return a >= 10000 ? x.toLocaleString("en-US", { maximumFractionDigits: 0 })
           : a >= 1000  ? x.toLocaleString("en-US", { maximumFractionDigits: 1 })
           : a >= 100   ? x.toFixed(2) : a >= 10 ? x.toFixed(3) : x.toFixed(4);
    },
    chg: function (x) {
      if (!isNum(x)) return "—";
      return (x >= 0 ? "+" : "−") + Math.abs(x).toFixed(Math.abs(x) >= 100 ? 1 : 2);
    },
    pct: function (x, dp) {
      if (!isNum(x)) return "—";
      return (x >= 0 ? "+" : "−") + Math.abs(x).toFixed(isNum(dp) ? dp : 2) + "%";
    },
    bp: function (x) {
      if (!isNum(x)) return "—";
      return (x >= 0 ? "+" : "−") + Math.abs(Math.round(x)) + "bp";
    },
    z: function (x) { return !isNum(x) ? "—" : (x >= 0 ? "+" : "−") + Math.abs(x).toFixed(2); },
    cap: function (x) {
      if (!isNum(x)) return "—";
      return x >= 1000 ? (x / 1000).toFixed(2) + "T" : x.toFixed(1) + "B";
    },
    arrow: function (x) { return !isNum(x) || x === 0 ? "" : x > 0 ? "▲" : "▼"; },
    /* 涨跌类名：全终端一套（合并前外壳给 up/dn/fl、数据区给 t-up/t-dn/t-flat） */
    cls: function (x) { return !isNum(x) ? "t-flat" : x > 0 ? "t-up" : x < 0 ? "t-dn" : "t-flat"; },
    utc: function (s) { return String(s || "—").replace("T", " ").replace(/\.\d+Z?$/, "Z"); },
    hm: function (iso) {
      if (!iso) return "—";
      var d = new Date(iso);
      if (isNaN(d)) return "—";
      return p2(d.getUTCHours()) + ":" + p2(d.getUTCMinutes()) + "Z";
    },
    statusZh: function (s) {
      return { ok:"正常", partial:"部分缺失", stale:"数据过期", error:"读取失败",
               degraded:"降级", provider:"由提供方标注" }[s] || (s || "—");
    }
  };
  function p2(n) { return n < 10 ? "0" + n : "" + n; }

  /* ── 站内没有的字段：统一声明，页面据此渲染说明而不是占位数字 ──────── */
  var UNAVAILABLE = [
    { k:"BID / ASK / 买卖价差", why:"无免费公开的层级报价来源" },
    { k:"VOL 成交量 / 成交额",  why:"无免费公开来源" },
    { k:"日内最高 / 最低",       why:"盘中快照只给单点价格，不含区间" },
    { k:"财务报表字段（PE / PB / ROE / 营收）", why:"站内公司数据只到价格、市值与收益率" },
    { k:"信用评级 / 券级现金流",  why:"站内债券数据是主权收益率序列，无券级要素" },
    { k:"ISIN / FIGI / CUSIP",   why:"站内只有交易所代码（symbol），无付费标识符库" },
    { k:"持仓 / 组合",           why:"站内无任何账户或持仓来源" }
  ];
  var UNAVAILABLE_NOTE = "本终端不显示 BID / ASK / VOL / 日内高低 / 财务报表 / 评级 / 券级现金流 / 持仓：" +
    "站内没有这些来源，也不用占位数字冒充。";

  /* ── 出处行：金融数据规范要求的 source / asOf / 频率 / 状态 ────────── */
  function meta(label, d, cadence) {
    if (!d || d.__error) return { label: label, error: (d && d.__error) || "未加载", cadence: cadence };
    return { label: label, source: d.source, asOf: d.asOf, updatedAt: d.updatedAt,
             frequency: d.frequency, status: d.status, cadence: cadence, note: d.note,
             count: d.count, realtime: d.realtime === true };
  }
  function srcLine(s, extra) {
    if (!s) return "来源 —";
    if (s.error) return "读取失败：" + s.error;
    return "来源 " + (s.source || "—") + " · AS OF " + (s.asOf || "—") + " · " +
      (s.cadence || s.frequency || "—") + " · 状态 " + fmt.statusZh(s.status) +
      (extra ? " · " + extra : "");
  }

  /* ── 多标的比较：先按日期对齐，再求共同窗口 ───────────────────────────
     两条管道的日期轴并不相同：公司榜 2025-11-11→2026-09-11，跨资产
     2025-11-14→2026-09-12，交集 257 天。所以绝不能按下标对齐 —— 按下标
     叠出来的线整体错位几天，图是假的。这里按日期字符串对齐到并集轴上，
     某条在某天没有观测就留 null，折线在那里断开，不插值也不前向填充。 */
  function alignSeries(list) {
    var axis = {}, items = (list || []).filter(function (x) { return x && x.dates && x.values; });
    items.forEach(function (it) {
      it.dates.forEach(function (d) { if (d) axis[d] = 1; });
    });
    var all = Object.keys(axis).sort();
    var at0 = {};
    all.forEach(function (d, i) { at0[d] = i; });
    /* 先把每条摊到并集轴上，再把「这几条都没有观测」的那些天整列去掉。
       公司榜的轴里含 41 个周日（股票那天本来就不开盘），留着的话每条股票线
       每周断一次、看上去像虚线。去掉空列不是补数据：某天 A 有 B 没有时，
       B 在那一天依然留空、依然断开。去掉了几列由 dropped 返回，页面要如实写出。 */
    var raw = items.map(function (it) {
      var out = new Array(all.length);
      for (var i = 0; i < all.length; i++) out[i] = null;
      for (var j = 0; j < it.dates.length; j++) {
        var k = at0[it.dates[j]];
        if (k !== undefined && isNum(it.values[j])) out[k] = it.values[j];
      }
      return out;
    });
    var keep = [];
    for (var c = 0; c < all.length; c++) {
      for (var s2 = 0; s2 < raw.length; s2++) {
        if (isNum(raw[s2][c])) { keep.push(c); break; }
      }
    }
    var dates = keep.map(function (c) { return all[c]; });
    var at = {};
    dates.forEach(function (d, i) { at[d] = i; });
    return {
      dates: dates,
      dropped: all.length - dates.length,
      axisFull: all.length,
      items: items.map(function (it, idx) {
        return { tk: it.tk, name: it.name, cur: it.cur, note: it.note,
                 values: keep.map(function (c) { return raw[idx][c]; }) };
      }),
    };
  }

  /* ── 多标的比较：共同窗口与归一化 ─────────────────────────────────────
     几条序列的有效覆盖不一样（站内典型 209/260，个别只有 27/260）。
     各自按自己的起点归一化再画在一起，比出来的是假的 —— 所以先求共同窗口：
       起点 = 各序列「首个有效点」里最晚的那个
       终点 = 各序列「最后有效点」里最早的那个
     再把每条按自己在窗口内的第一个有效值重基到 100。缺口一律留空，不插值。
     各条的实际基期可能差几天（休市日不同），逐条返回 baseDate 供页面如实写出。 */
  function compareWindow(list) {
    var items = (list || []).filter(function (x) { return x && x.values && x.values.length; });
    if (items.length < 2) return { ok:false, reason:"至少要两条序列才能比较" };
    var firsts = [], lasts = [];
    items.forEach(function (it) {
      var f = -1, l = -1;
      for (var i = 0; i < it.values.length; i++) if (isNum(it.values[i])) { if (f < 0) f = i; l = i; }
      firsts.push(f); lasts.push(l);
    });
    if (firsts.some(function (f) { return f < 0; }))
      return { ok:false, reason:"有序列一个有效点都没有" };
    var start = Math.max.apply(null, firsts);
    var end = Math.min.apply(null, lasts);
    if (end - start < 5) return { ok:false, reason:"几条序列的共同窗口不足 6 个交易日，不做比较" };
    return { ok:true, start:start, end:end };
  }

  /* 把一条序列在 [start,end] 窗口内重基到 100。base 取窗口内第一个有效值。 */
  function rebase(values, start, end) {
    var base = null, baseAt = -1, out = [];
    for (var i = start; i <= end; i++) {
      if (base === null && isNum(values[i])) { base = values[i]; baseAt = i; }
      out.push(base !== null && isNum(values[i]) ? values[i] / base * 100 : null);
    }
    if (base === null) return null;
    var valid = out.filter(isNum).length;
    var lastVal = null;
    for (var j = out.length - 1; j >= 0; j--) if (isNum(out[j])) { lastVal = out[j]; break; }
    return { values:out, base:base, baseAt:baseAt, valid:valid, n:out.length, last:lastVal };
  }

  /* ── 日收益率：只在「相邻两个交易日都有收盘」时才算 ───────────────────
     返回的数组与输入同长、同下标（out[i] = 第 i 天相对第 i−1 天的收益），
     这样多条序列做两两统计时直接按下标取交集就行。
     某天缺收盘，它前后那两个收益都不算 —— 跨着缺口算出来的不是「日」收益。 */
  function dailyReturns(values) {
    var out = [];
    for (var i = 0; i < (values || []).length; i++) out.push(null);
    for (var j = 1; j < (values || []).length; j++) {
      var a0 = values[j - 1], a1 = values[j];
      if (isNum(a0) && isNum(a1) && a0 !== 0) out[j] = a1 / a0 - 1;
    }
    return out;
  }

  /* 两条收益序列的皮尔逊相关。只取两边同一天都有收益的样本；
     样本不足就返回 r:null 并带上 n —— 三十天的相关系数是噪声，不该给数。 */
  var MIN_PAIRS = 60;
  function pairCorr(ra, rb, minN) {
    var need = minN || MIN_PAIRS, xs = [], ys = [];
    var len = Math.min((ra || []).length, (rb || []).length);
    for (var i = 0; i < len; i++) {
      if (isNum(ra[i]) && isNum(rb[i])) { xs.push(ra[i]); ys.push(rb[i]); }
    }
    var n = xs.length;
    if (n < need) return { r: null, n: n, need: need };
    var mx = 0, my = 0, i2;
    for (i2 = 0; i2 < n; i2++) { mx += xs[i2]; my += ys[i2]; }
    mx /= n; my /= n;
    var sxy = 0, sxx = 0, syy = 0;
    for (i2 = 0; i2 < n; i2++) {
      var dx = xs[i2] - mx, dy = ys[i2] - my;
      sxy += dx * dy; sxx += dx * dx; syy += dy * dy;
    }
    if (sxx <= 0 || syy <= 0) return { r: null, n: n, need: need, flat: true };
    return { r: sxy / Math.sqrt(sxx * syy), n: n, need: need };
  }

  /* 对基准的最小二乘回归：y = alpha + beta·x（都是日简单收益）。
     alpha 按 252 个交易日折年，但没有扣无风险利率 —— 站内没有这条序列，
     所以它是「相对 beta·基准的超额」，不是 Jensen alpha，页面必须这么写。 */
  function regress(ry, rx, minN) {
    var need = minN || MIN_PAIRS, xs = [], ys = [];
    var len = Math.min((ry || []).length, (rx || []).length);
    for (var i = 0; i < len; i++) {
      if (isNum(ry[i]) && isNum(rx[i])) { xs.push(rx[i]); ys.push(ry[i]); }
    }
    var n = xs.length;
    if (n < need) return { beta: null, n: n, need: need };
    var mx = 0, my = 0, k;
    for (k = 0; k < n; k++) { mx += xs[k]; my += ys[k]; }
    mx /= n; my /= n;
    var sxy = 0, sxx = 0, syy = 0;
    for (k = 0; k < n; k++) {
      var dx = xs[k] - mx, dy = ys[k] - my;
      sxy += dx * dy; sxx += dx * dx; syy += dy * dy;
    }
    if (sxx <= 0) return { beta: null, n: n, need: need, flat: true };
    var beta = sxy / sxx;
    var alpha = my - beta * mx;
    var r2 = syy > 0 ? (sxy * sxy) / (sxx * syy) : null;
    return { beta: beta, alphaDaily: alpha, alphaAnn: alpha * 252 * 100,
             r2: r2, n: n, need: need };
  }

  /* ── 月线：{start:"1999-02", closes:[…]} 展开成显式月份标签 ─────────────
     月线文件的自述里写了一件要命的事：「数据源对超长区间会自行降采样，部分公司
     的早年只有季度末观测，缺月一律留空」。所以**不能把相邻两个有值的观测当成
     相邻两个月**——跨着降采样区间算出来的不是月收益，是季收益。
     monthOverMonth 因此只在「日历上真正相邻的两个月都有收盘」时才算。 */
  function monthLabels(start, n) {
    var out = [], m = /^(\d{4})-(\d{2})$/.exec(String(start || ""));
    if (!m) return out;
    var y = +m[1], mo = +m[2];
    for (var i = 0; i < n; i++) {
      out.push(y + "-" + (mo < 10 ? "0" + mo : mo));
      mo++; if (mo > 12) { mo = 1; y++; }
    }
    return out;
  }
  function monthlySeries(entry) {
    if (!entry || !entry.closes) return { months: [], closes: [] };
    return { months: monthLabels(entry.start, entry.closes.length), closes: entry.closes };
  }
  /* 月度环比收益，与 closes 同下标；只有日历上相邻的两个月都有值才给数 */
  function monthOverMonth(months, closes) {
    var out = [];
    for (var i = 0; i < closes.length; i++) out.push(null);
    for (var j = 1; j < closes.length; j++) {
      if (!isNum(closes[j]) || !isNum(closes[j - 1]) || closes[j - 1] === 0) continue;
      var a0 = months[j - 1], a1 = months[j];
      if (!a0 || !a1) continue;
      var y0 = +a0.slice(0, 4), m0 = +a0.slice(5), y1 = +a1.slice(0, 4), m1 = +a1.slice(5);
      if ((y1 - y0) * 12 + (m1 - m0) !== 1) continue;     /* 不是相邻月，不算 */
      out[j] = closes[j] / closes[j - 1] - 1;
    }
    return out;
  }
  /* 覆盖面自述：整条序列跨多久、有多少观测、其中多少是真正相邻的月，
     以及「逐月观测」从哪个月开始。实测 MMM 从 1962-01 起共 339 个观测，
     但其中 219 个间隔是 3 个月（季度末），逐月只从 2016-10 开始、119 对。
     所以页面必须把「跨 64 年」和「月度样本只有 10 年」分开讲，否则读的人
     会以为那个季节性是六十年的证据。 */
  function monthlyCoverage(months, closes) {
    var obs = [], i;
    for (i = 0; i < closes.length; i++) if (isNum(closes[i]) && months[i]) obs.push(months[i]);
    if (!obs.length) return { obs: 0, from: null, to: null, mom: 0, momFrom: null, quarterly: 0 };
    var mom = 0, quarterly = 0, momFrom = null;
    for (i = 1; i < obs.length; i++) {
      var a0 = obs[i - 1], a1 = obs[i];
      var d = (+a1.slice(0, 4) - +a0.slice(0, 4)) * 12 + (+a1.slice(5) - +a0.slice(5));
      if (d === 1) { mom++; if (!momFrom) momFrom = a0; }
      else if (d >= 2) quarterly++;
    }
    return { obs: obs.length, from: obs[0], to: obs[obs.length - 1],
             mom: mom, momFrom: momFrom, quarterly: quarterly };
  }

  /* 按日历月汇总：每个月的平均/中位环比、正收益占比、样本年数。
     样本不足 minN 年就不给数 —— 五个观测的「季节性」是巧合不是规律。 */
  var MIN_SEASON_YEARS = 8;
  function seasonality(months, rets, minN) {
    var need = minN || MIN_SEASON_YEARS, buckets = [];
    for (var m = 0; m < 12; m++) buckets.push([]);
    for (var i = 0; i < rets.length; i++) {
      if (!isNum(rets[i]) || !months[i]) continue;
      buckets[+months[i].slice(5) - 1].push(rets[i]);
    }
    return buckets.map(function (v, idx) {
      var n = v.length;
      if (n < need) return { month: idx + 1, n: n, need: need, mean: null, median: null, pos: null };
      var sorted = v.slice().sort(function (a, b) { return a - b; });
      var mid = sorted.length % 2
        ? sorted[(sorted.length - 1) / 2]
        : (sorted[sorted.length / 2 - 1] + sorted[sorted.length / 2]) / 2;
      return {
        month: idx + 1, n: n, need: need,
        mean: v.reduce(function (a, b) { return a + b; }, 0) / n * 100,
        median: mid * 100,
        pos: v.filter(function (x) { return x > 0; }).length / n * 100
      };
    });
  }

  /* ── 自定义篮子指数 ────────────────────────────────────────────────────
     输入是已经重基到 100 的成分序列 + 一组权重，输出还是一条重基到 100 的序列。
     两条必须说清的口径：
       1) **固定权重、不再平衡** —— 权重在基期一次性施加，之后各成分自行涨跌。
          这等于「基期按这些权重买入后一直持有」，与「每日/每月再平衡」结果不同。
       2) **只在全部成分当天都有值时才给点** —— 少一个成分就留空、折线断开。
          缺成分时按剩下的权重重新归一化会悄悄改变篮子构成，那是另一只篮子。 */
  function basketIndex(items, weights) {
    var live = (items || []).filter(function (it) { return it && it.values && it.values.length; });
    if (live.length < 2) return { values: [], reason: "至少要两个成分" };
    var n = Math.max.apply(null, live.map(function (it) { return it.values.length; }));
    var w = live.map(function (it, i) {
      var x = weights && isNum(weights[i]) ? weights[i] : 0;
      return x > 0 ? x : 0;
    });
    var sum = w.reduce(function (a, b) { return a + b; }, 0);
    if (sum <= 0) return { values: [], reason: "权重合计必须大于 0" };
    w = w.map(function (x) { return x / sum; });
    var out = [], full = 0, partial = 0;
    for (var t = 0; t < n; t++) {
      var ok = true, v = 0;
      for (var k = 0; k < live.length; k++) {
        var x2 = live[k].values[t];
        if (!isNum(x2)) { ok = false; break; }
        v += w[k] * x2;
      }
      if (ok) { out.push(v); full++; } else { out.push(null); partial++; }
    }
    /* 再重基一次：第一个有效点归到 100，篮子和成分才同起点可比 */
    var base = null;
    for (var j = 0; j < out.length; j++) if (isNum(out[j])) { base = out[j]; break; }
    if (base === null || base === 0) return { values: [], reason: "没有全部成分都有值的日子" };
    var last = null;
    var idx = out.map(function (x3) { return isNum(x3) ? x3 / base * 100 : null; });
    for (var q = idx.length - 1; q >= 0; q--) if (isNum(idx[q])) { last = idx[q]; break; }
    return { values: idx, weights: w, full: full, skipped: partial, n: n, last: last,
             valid: idx.filter(isNum).length };
  }

  /* ── 统计：Z-Score 与分位（需要足够样本才给数）────────────────────── */
  function zscore(values, win) {
    var v = (values || []).filter(isNum);
    if (v.length < 30) return null;
    var w = Math.min(win || 504, v.length);
    var s = v.slice(-w);
    var mu = s.reduce(function (a, b) { return a + b; }, 0) / s.length;
    var sd = Math.sqrt(s.reduce(function (a, b) { return a + (b - mu) * (b - mu); }, 0) / (s.length - 1));
    if (!sd) return null;
    return { last: v[v.length - 1], mean: mu, sd: sd, z: (v[v.length - 1] - mu) / sd, n: s.length, win: w };
  }
  /* 判定阈值集中在这里，页面上必须把它原样写出来 */
  function signalFromPercentile(p) {
    if (!isNum(p)) return { k:"na", label:"—" };
    if (p < 35) return { k:"stress", label:"STRESS" };
    if (p < 48) return { k:"risk",   label:"RISK" };
    if (p < 58) return { k:"watch",  label:"WATCH" };
    return { k:"normal", label:"NORMAL" };
  }
  function signalFromZ(z) {
    if (!isNum(z)) return { k:"na", label:"—" };
    var a = Math.abs(z);
    if (a >= 2)   return { k:"stress", label:"STRESS" };
    if (a >= 1.5) return { k:"risk",   label:"RISK" };
    if (a >= 1)   return { k:"watch",  label:"WATCH" };
    return { k:"normal", label:"NORMAL" };
  }
  var MONITOR_METHOD = "判定阈值：分位 <35 STRESS / <48 RISK / <58 WATCH / ≥58 NORMAL；" +
    "Z-Score |z|≥2 STRESS / ≥1.5 RISK / ≥1 WATCH（Z 由站内原始日序列现算，窗口见括号）";

  /* ── 交易时段：按真实夏令时与午休规则算，不写死 ──────────────────── */
  function nthWeekdayUTC(year, month, weekday, nth) {
    var d = new Date(Date.UTC(year, month, 1));
    var shift = (weekday - d.getUTCDay() + 7) % 7;
    return new Date(Date.UTC(year, month, 1 + shift + (nth - 1) * 7));
  }
  function lastWeekdayUTC(year, month, weekday) {
    var d = new Date(Date.UTC(year, month + 1, 0));
    var shift = (d.getUTCDay() - weekday + 7) % 7;
    return new Date(Date.UTC(year, month + 1, 0 - shift));
  }
  /* 美国：3 月第二个周日 02:00 本地 → 11 月第一个周日 */
  function usDST(now) {
    var y = now.getUTCFullYear();
    var start = nthWeekdayUTC(y, 2, 0, 2), end = nthWeekdayUTC(y, 10, 0, 1);
    start.setUTCHours(7); end.setUTCHours(6);
    return now >= start && now < end;
  }
  /* 英国：3 月最后一个周日 01:00 UTC → 10 月最后一个周日 */
  function ukDST(now) {
    var y = now.getUTCFullYear();
    var start = lastWeekdayUTC(y, 2, 0), end = lastWeekdayUTC(y, 9, 0);
    start.setUTCHours(1); end.setUTCHours(1);
    return now >= start && now < end;
  }
  function shift(now, hours) { return new Date(now.getTime() + hours * 3600000); }
  function parts(d) { return { h: d.getUTCHours(), m: d.getUTCMinutes(), dow: d.getUTCDay() }; }
  function within(p, a, b) { var t = p.h * 60 + p.m; return t >= a && t < b; }
  function weekday(p) { return p.dow >= 1 && p.dow <= 5; }

  function marketStatus(now) {
    now = now || new Date();
    var nyOff = usDST(now) ? -4 : -5;
    var ldOff = ukDST(now) ? 1 : 0;
    var ny = parts(shift(now, nyOff));
    var ld = parts(shift(now, ldOff));
    var tk = parts(shift(now, 9));
    var sh = parts(shift(now, 8));
    var out = [];
    /* 纽约 09:30–16:00；纳斯达克同时段 */
    var nyOpen = weekday(ny) && within(ny, 9 * 60 + 30, 16 * 60);
    out.push({ id:"NYSE",   city:"NEW YORK", parts:ny, open:nyOpen });
    out.push({ id:"NASDAQ", city:"NEW YORK", parts:ny, open:nyOpen });
    /* 伦敦 08:00–16:30 */
    out.push({ id:"LSE", city:"LONDON", parts:ld, open: weekday(ld) && within(ld, 8 * 60, 16 * 60 + 30) });
    /* 东京 09:00–11:30、12:30–15:00 */
    out.push({ id:"TSE", city:"TOKYO", parts:tk,
      open: weekday(tk) && (within(tk, 9 * 60, 11 * 60 + 30) || within(tk, 12 * 60 + 30, 15 * 60)) });
    /* 上海 09:30–11:30、13:00–15:00 */
    out.push({ id:"SSE", city:"SHANGHAI", parts:sh,
      open: weekday(sh) && (within(sh, 9 * 60 + 30, 11 * 60 + 30) || within(sh, 13 * 60, 15 * 60)) });
    return out;
  }

  /* ── 详情页地址 ───────────────────────────────────────────────────────
     站内的行情详情页 quote.html 支持七种 kind，各自的 symbol 键格式不同：

       tracker   asset-tracker 的 symbol（^GSPC / BZ=F / DX-Y.NYB…）
       company   companies 的 symbol（NVDA）
       crypto    BTC / ETH
       curve     美债期限的 id（DGS10 / DGS2…）
       macro     macro-radar referenceSeries 的键，站内只有 DTWEXBGS 与 RWTC
       commodity / bond   对应两个纯数据目录

     个股例外：站内另有证券描述页，信息更全（发行人、标识、同业、收盘走势），
     所以个股的行点进去走 security.html，那一页再链向 quote.html 看全区间。

     拿不到 kind 或 symbol 时返回 null —— 宁可这一行不可点，也不给死链。 */
  var QUOTE_KINDS = { tracker:1, company:1, crypto:1, curve:1, macro:1, commodity:1, bond:1 };

  function quoteHref(kind, symbol) {
    if (!QUOTE_KINDS[kind] || !symbol) return null;
    return "/apps/finance-terminal/quote.html?kind=" + encodeURIComponent(kind) +
           "&symbol=" + encodeURIComponent(symbol);
  }
  function securityHref(symbol) {
    if (!symbol) return null;
    return "/apps/finance-terminal/security.html?sym=" + encodeURIComponent(symbol);
  }
  /* 一行 → 它的详情页。detail 由模型层附上（模型才知道这一行是什么）。 */
  function detailHref(detail) {
    if (!detail || !detail.kind || !detail.symbol) return null;
    if (detail.kind === "company") return securityHref(detail.symbol);
    return quoteHref(detail.kind, detail.symbol);
  }

  /* ── 转义（外部文本一律先转义再进 innerHTML）──────────────────────── */
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c];
    });
  }

  global.OOGLEX_CORE = {
    BASE: BASE, isNum: isNum, getJSON: getJSON, soft: soft, fmt: fmt, esc: esc,
    shardPath: shardPath, alignSeries: alignSeries,
    dailyReturns: dailyReturns, pairCorr: pairCorr, regress: regress, MIN_PAIRS: MIN_PAIRS,
    monthLabels: monthLabels, monthlySeries: monthlySeries, monthOverMonth: monthOverMonth,
    seasonality: seasonality, monthlyCoverage: monthlyCoverage, MIN_SEASON_YEARS: MIN_SEASON_YEARS,
    compareWindow: compareWindow, rebase: rebase, basketIndex: basketIndex,
    meta: meta, srcLine: srcLine, zscore: zscore,
    quoteHref: quoteHref, securityHref: securityHref, detailHref: detailHref,
    QUOTE_KINDS: QUOTE_KINDS,
    signalFromPercentile: signalFromPercentile, signalFromZ: signalFromZ,
    MONITOR_METHOD: MONITOR_METHOD, marketStatus: marketStatus,
    UNAVAILABLE: UNAVAILABLE, UNAVAILABLE_NOTE: UNAVAILABLE_NOTE
  };
})(window);
