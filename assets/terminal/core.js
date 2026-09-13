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

  /* ── 转义（外部文本一律先转义再进 innerHTML）──────────────────────── */
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
      return { "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c];
    });
  }

  global.OOGLEX_CORE = {
    BASE: BASE, isNum: isNum, getJSON: getJSON, soft: soft, fmt: fmt, esc: esc,
    meta: meta, srcLine: srcLine, zscore: zscore,
    signalFromPercentile: signalFromPercentile, signalFromZ: signalFromZ,
    MONITOR_METHOD: MONITOR_METHOD, marketStatus: marketStatus,
    UNAVAILABLE: UNAVAILABLE, UNAVAILABLE_NOTE: UNAVAILABLE_NOTE
  };
})(window);
