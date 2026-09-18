/* ===========================================================================
   Ooglex 想法流
   ---------------------------------------------------------------------------
   口径：公开可读，登录可发，发出即公开。

   这个文件里的任何校验都只是「省一次往返」的体验优化，不是防线。
   真正的防线全部在 account/migrations/20260918_add_thoughts.sql 里：
   作者身份、正文长度、发布频率、初始可见性、谁能隐藏、谁能删，都由数据库的
   RLS 策略与触发器决定。浏览器里的这段 JS 被改掉也拿不到多一分权限。

   一条硬规则：用户正文与昵称一律走 textContent，永不进 innerHTML。
   =========================================================================== */
(function () {
  "use strict";

  var CFG = window.OOGLEX_AUTH_CONFIG || {};
  var PAGE_SIZE = 20;
  var MAX_LEN = 500;

  var $ = function (id) { return document.getElementById(id); };

  var el = {
    authLoading: $("auth-loading"),
    authAnon: $("auth-anon"),
    authSuspended: $("auth-suspended"),
    form: $("composer-form"),
    body: $("body"),
    counter: $("counter"),
    submit: $("submit-btn"),
    whoTag: $("who-tag"),
    whoAvatar: $("who-avatar"),
    formMsg: $("form-msg"),
    ownerTools: $("owner-tools"),
    loadReports: $("load-reports"),
    reportsBox: $("reports-box"),
    feed: $("feed"),
    feedState: $("feed-state"),
    loadMore: $("load-more")
  };

  var sb = null;          // Supabase 客户端
  var me = null;          // { id, email }
  var profile = null;     // { display_name, status, role }
  var offset = 0;         // 已加载条数，用于翻页
  var busy = false;

  // --- 小工具 ---------------------------------------------------------------

  function isEnglish() {
    try {
      if (window.OoglexI18n && window.OoglexI18n.getLanguage) {
        return window.OoglexI18n.getLanguage() === "en";
      }
      return localStorage.getItem("ooglex.language") === "en";
    } catch (e) { return false; }
  }

  function t(zh, en) { return isEnglish() ? en : zh; }

  /* 相对时间。超过 7 天直接显示日期，免得「532 天前」这种没用的读数。 */
  function whenText(iso) {
    var then = new Date(iso);
    if (isNaN(then.getTime())) return "";
    var sec = Math.floor((Date.now() - then.getTime()) / 1000);
    if (sec < 0) sec = 0;
    if (sec < 60) return t("刚刚", "just now");
    if (sec < 3600) return t(Math.floor(sec / 60) + " 分钟前", Math.floor(sec / 60) + "m ago");
    if (sec < 86400) return t(Math.floor(sec / 3600) + " 小时前", Math.floor(sec / 3600) + "h ago");
    if (sec < 604800) return t(Math.floor(sec / 86400) + " 天前", Math.floor(sec / 86400) + "d ago");
    var p = function (n) { return n < 10 ? "0" + n : String(n); };
    return then.getFullYear() + "-" + p(then.getMonth() + 1) + "-" + p(then.getDate());
  }

  function show(node, on) { if (node) node.hidden = !on; }

  function say(node, text, kind) {
    if (!node) return;
    node.textContent = text;                       // 一律 textContent
    node.className = "notice" + (kind ? " " + kind : "");
    node.hidden = !text;
  }

  /* Supabase / PostgREST 的错误映射。
     迁移还没在 Supabase 里跑过时，表不存在，PostgREST 回 PGRST205 或 42P01 ——
     这种情况要说「功能还没启用」，不能丢一句通用失败让人以为是自己网络问题。 */
  function explain(error) {
    var code = (error && error.code) || "";
    var msg = (error && error.message) || String(error || "");
    if (code === "PGRST205" || code === "42P01" || /could not find the table|does not exist/i.test(msg)) {
      return t("想法流的数据表还没建好，功能尚未启用。",
               "The thoughts table has not been created yet; this feature is not enabled.");
    }
    if (code === "42501" || /permission denied|row-level security/i.test(msg)) {
      return t("没有权限执行这个操作。", "You do not have permission to do that.");
    }
    if (code === "53400" || /发得太快|已达上限|一模一样/.test(msg)) return msg;   // 限流文案由数据库给出
    if (/thoughts_body_length/.test(msg)) {
      return t("正文需要 1 到 500 字。", "The text must be between 1 and 500 characters.");
    }
    if (/thought_reports_once/.test(msg)) {
      return t("你已经举报过这一条了。", "You have already reported this one.");
    }
    if (/停用|未找到账户资料|请先登录/.test(msg)) return msg;
    if (/Failed to fetch|NetworkError|network/i.test(msg)) {
      return t("网络连不上，稍后再试。", "Network unavailable, please try again later.");
    }
    return msg || t("操作失败。", "The operation failed.");
  }

  // --- 渲染 -----------------------------------------------------------------

  /* 头像：完全由 author_name 推导（首字 + 按名字稳定取色）。
     不读数据库、不存任何文件 —— author_name 是未登录访客本来就能读的列，
     所以这个功能零新增授权、零存储、零审核负担。
     同一个昵称必然得到同一个颜色；换了昵称，数据库的同步触发器会把历史帖子
     的 author_name 一起改掉，头像也就跟着变了。 */
  var AVATAR_COLORS = [
    "#b3471f", "#b03a5b", "#8e3b6e", "#6b3fa0", "#4a4fa8",
    "#1f5f8b", "#116b73", "#136b52", "#4a6b1f", "#8a5a1b"
  ];

  /* 取首个「字」而不是首个码点：emoji 和带变体选择符的字符切一半会变乱码。 */
  function firstGrapheme(str) {
    if (!str) return "";
    try {
      if (typeof Intl !== "undefined" && Intl.Segmenter) {
        var it = new Intl.Segmenter(undefined, { granularity: "grapheme" })
          .segment(str)[Symbol.iterator]().next();
        if (!it.done) return it.value.segment;
      }
    } catch (e) { /* 老浏览器回落到按码点切 */ }
    return Array.from(str)[0] || "";
  }

  function avatarFor(name) {
    var n = (name || "").trim();
    var ch = firstGrapheme(n) || "\u00b7";
    if (/^[a-z]$/.test(ch)) ch = ch.toUpperCase();      // 拉丁小写统一大写显示
    var h = 0;
    for (var i = 0; i < n.length; i++) h = (h * 31 + n.charCodeAt(i)) >>> 0;
    return { text: ch, color: AVATAR_COLORS[h % AVATAR_COLORS.length] };
  }

  function avatarNode(name, small) {
    var a = avatarFor(name);
    var el = document.createElement("span");
    el.className = "avatar" + (small ? " sm" : "");
    el.style.background = a.color;
    el.textContent = a.text;                            // textContent，昵称是用户输入
    // 名字紧跟在头像后面，读屏不需要把首字再念一遍；颜色也不是唯一信息来源
    el.setAttribute("aria-hidden", "true");
    return el;
  }

  function makeButton(label, cls, onClick) {
    var b = document.createElement("button");
    b.type = "button";
    b.textContent = label;
    if (cls) b.className = cls;
    b.addEventListener("click", onClick);
    return b;
  }

  function renderItem(row) {
    var mine = !!(me && row.author_id && row.author_id === me.id);
    var hidden = row.status !== "visible";
    var owner = !!(profile && profile.role === "owner");

    var item = document.createElement("article");
    item.className = "item" + (hidden ? " is-hidden" : "");
    item.appendChild(avatarNode(row.author_name, false));

    var col = document.createElement("div");
    col.className = "col";
    item.appendChild(col);

    var meta = document.createElement("div");
    meta.className = "meta";

    var who = document.createElement("span");
    who.className = "who";
    who.textContent = row.author_name || t("匿名用户", "Anonymous");   // textContent
    meta.appendChild(who);

    var when = document.createElement("span");
    when.textContent = whenText(row.created_at);
    meta.appendChild(when);

    if (mine) {
      var mineTag = document.createElement("span");
      mineTag.className = "tag mine";
      mineTag.textContent = t("我发的", "MINE");
      meta.appendChild(mineTag);
    }
    if (hidden) {
      var hTag = document.createElement("span");
      hTag.className = "tag hidden";
      hTag.textContent = row.status === "hidden"
        ? t("已被隐藏", "HIDDEN") : t("已撤下", "REMOVED");
      meta.appendChild(hTag);
    }
    col.appendChild(meta);

    var body = document.createElement("div");
    body.className = "body";
    body.textContent = row.body || "";                                 // textContent
    col.appendChild(body);

    var acts = document.createElement("div");
    acts.className = "acts";

    if (mine) {
      acts.appendChild(makeButton(t("删除", "Delete"), "", function () {
        if (!window.confirm(t("删除这条想法？删除后无法恢复。",
                              "Delete this thought? This cannot be undone."))) return;
        removeThought(row.id, item);
      }));
    } else if (me) {
      acts.appendChild(makeButton(t("举报", "Report"), "", function () {
        reportThought(row.id, acts);
      }));
    }

    if (owner && !hidden) {
      acts.appendChild(makeButton(t("隐藏（站主）", "Hide (owner)"), "", function () {
        setStatus(row.id, "hidden", item);
      }));
    }
    if (owner && hidden) {
      acts.appendChild(makeButton(t("恢复公开（站主）", "Unhide (owner)"), "", function () {
        setStatus(row.id, "visible", item);
      }));
    }

    if (acts.childNodes.length) col.appendChild(acts);
    return item;
  }

  /* anon 没有 author_id 这一列的 select 权限（迁移里刻意只给了登录用户），
     所以列清单必须按登录态拼，否则未登录访客会整页 permission denied。 */
  function columns() {
    return me
      ? "id, author_id, author_name, body, created_at, status"
      : "id, author_name, body, created_at, status";
  }

  async function loadFeed(append) {
    if (busy) return;
    busy = true;
    if (!append) { offset = 0; el.feed.textContent = ""; }
    el.feedState.textContent = t("加载中…", "Loading…");
    show(el.feedState, true);
    show(el.loadMore, false);

    var res = await sb
      .from("thoughts")
      .select(columns())
      .order("created_at", { ascending: false })
      .range(offset, offset + PAGE_SIZE - 1);

    busy = false;

    if (res.error) {
      el.feedState.textContent = explain(res.error);
      el.feedState.className = "state";
      return;
    }

    var rows = res.data || [];
    rows.forEach(function (row) { el.feed.appendChild(renderItem(row)); });
    offset += rows.length;

    if (!el.feed.childNodes.length) {
      el.feedState.textContent = t("还没有人发布想法，来做第一个。",
                                   "No thoughts yet — be the first.");
      show(el.feedState, true);
    } else {
      show(el.feedState, false);
    }
    show(el.loadMore, rows.length === PAGE_SIZE);
  }

  // --- 写操作 ---------------------------------------------------------------

  async function submitThought(ev) {
    ev.preventDefault();
    var text = (el.body.value || "").trim();
    if (!text) {
      say(el.formMsg, t("先写点什么再发。", "Write something first."), "warn");
      return;
    }
    if (text.length > MAX_LEN) {
      say(el.formMsg, t("最多 500 字。", "500 characters max."), "warn");
      return;
    }

    el.submit.disabled = true;
    say(el.formMsg, t("发布中…", "Posting…"), "");

    // 只送 body 这一列。作者、时间、可见性都由数据库触发器决定。
    var res = await sb.from("thoughts").insert({ body: text }).select(columns());

    el.submit.disabled = false;

    if (res.error) {
      say(el.formMsg, explain(res.error), "err");
      return;
    }

    el.body.value = "";
    updateCounter();
    say(el.formMsg, t("已发布。", "Posted."), "ok");
    var rows = res.data || [];
    if (rows.length) {
      el.feed.insertBefore(renderItem(rows[0]), el.feed.firstChild);
      offset += 1;
      show(el.feedState, false);
    } else {
      loadFeed(false);
    }
    window.setTimeout(function () { show(el.formMsg, false); }, 2500);
  }

  async function removeThought(id, node) {
    var res = await sb.from("thoughts").delete().eq("id", id);
    if (res.error) { window.alert(explain(res.error)); return; }
    if (node && node.parentNode) node.parentNode.removeChild(node);
    if (offset > 0) offset -= 1;
    if (!el.feed.childNodes.length) {
      el.feedState.textContent = t("还没有人发布想法，来做第一个。", "No thoughts yet — be the first.");
      show(el.feedState, true);
    }
  }

  async function setStatus(id, status, node) {
    var res = await sb.from("thoughts").update({ status: status }).eq("id", id).select(columns());
    if (res.error) { window.alert(explain(res.error)); return; }
    var rows = res.data || [];
    if (rows.length && node && node.parentNode) {
      node.parentNode.replaceChild(renderItem(rows[0]), node);
    } else {
      loadFeed(false);
    }
  }

  async function reportThought(id, actsNode) {
    var reason = window.prompt(t("举报原因（可留空，最多 200 字）：",
                                 "Reason (optional, 200 characters max):"), "");
    if (reason === null) return;                       // 用户取消
    reason = String(reason).slice(0, 200);
    var res = await sb.from("thought_reports").insert({ thought_id: id, reason: reason });
    if (res.error) { window.alert(explain(res.error)); return; }
    if (actsNode) {
      var done = document.createElement("span");
      done.className = "tag";
      done.textContent = t("已举报，站主会看到", "Reported");
      actsNode.textContent = "";
      actsNode.appendChild(done);
    }
  }

  async function loadReports() {
    el.loadReports.disabled = true;
    el.reportsBox.textContent = t("加载中…", "Loading…");
    var res = await sb.rpc("reported_thoughts");
    el.loadReports.disabled = false;

    if (res.error) { el.reportsBox.textContent = explain(res.error); return; }

    var rows = res.data || [];
    el.reportsBox.textContent = "";
    if (!rows.length) {
      el.reportsBox.textContent = t("目前没有被举报的想法。", "No reported thoughts right now.");
      return;
    }
    rows.forEach(function (row) {
      var box = document.createElement("div");
      box.className = "item" + (row.status !== "visible" ? " is-hidden" : "");

      box.appendChild(avatarNode(row.author_name, false));
      var rcol = document.createElement("div");
      rcol.className = "col";
      box.appendChild(rcol);

      var meta = document.createElement("div");
      meta.className = "meta";
      var n = document.createElement("span");
      n.className = "tag hidden";
      n.textContent = t("被举报 " + row.report_count + " 次", row.report_count + " report(s)");
      meta.appendChild(n);
      var w = document.createElement("span");
      w.textContent = (row.author_name || "") + " · " + whenText(row.created_at);
      meta.appendChild(w);
      rcol.appendChild(meta);

      var b = document.createElement("div");
      b.className = "body";
      b.textContent = row.body || "";                              // textContent
      rcol.appendChild(b);

      if (row.last_reason) {
        var r = document.createElement("div");
        r.className = "sub";
        r.style.marginTop = "6px";
        r.textContent = t("最近一条理由：", "Latest reason: ") + row.last_reason;   // textContent
        rcol.appendChild(r);
      }

      var acts = document.createElement("div");
      acts.className = "acts";
      if (row.status === "visible") {
        acts.appendChild(makeButton(t("隐藏", "Hide"), "", function () {
          setStatus(row.id, "hidden", null);
          loadReports();
        }));
      } else {
        acts.appendChild(makeButton(t("恢复公开", "Unhide"), "", function () {
          setStatus(row.id, "visible", null);
          loadReports();
        }));
      }
      acts.appendChild(makeButton(t("删除", "Delete"), "", function () {
        if (!window.confirm(t("彻底删除这条想法？", "Permanently delete this thought?"))) return;
        removeThought(row.id, null);
        loadReports();
      }));
      rcol.appendChild(acts);
      el.reportsBox.appendChild(box);
    });
  }

  // --- 登录态 ---------------------------------------------------------------

  function updateCounter() {
    var n = (el.body.value || "").length;
    el.counter.textContent = n + " / " + MAX_LEN;
    el.counter.className = "counter" + (n > MAX_LEN ? " over" : "");
    el.submit.disabled = n === 0 || n > MAX_LEN;
  }

  async function applyAuth(user) {
    me = user ? { id: user.id, email: user.email } : null;
    profile = null;
    show(el.authLoading, false);

    if (!me) {
      show(el.authAnon, true);
      show(el.authSuspended, false);
      show(el.form, false);
      show(el.ownerTools, false);
      return;
    }

    show(el.authAnon, false);

    var res = await sb.from("profiles").select("display_name, status, role").eq("id", me.id).maybeSingle();
    profile = res.error ? null : (res.data || null);

    if (profile && profile.status !== "active") {
      show(el.authSuspended, true);
      show(el.form, false);
      show(el.ownerTools, false);
      return;
    }

    show(el.authSuspended, false);
    show(el.form, true);
    var name = (profile && (profile.display_name || "").trim()) || "";
    var shown = name || "匿名用户";
    el.whoTag.textContent = name
      ? t("以 " + name + " 发布", "as " + name)
      : t("以 匿名用户 发布", "as Anonymous");
    if (el.whoAvatar) {
      el.whoAvatar.textContent = "";
      el.whoAvatar.appendChild(avatarNode(shown, true));
    }
    show(el.ownerTools, !!(profile && profile.role === "owner"));
    updateCounter();
  }

  // --- 启动 -----------------------------------------------------------------

  async function boot() {
    if (!CFG.enabled || !CFG.supabaseUrl || !CFG.supabasePublishableKey) {
      show(el.authLoading, false);
      say(el.authAnon, t("账户服务未配置，暂时无法发布。", "Account service is not configured."), "err");
      show(el.authAnon, true);
      el.feedState.textContent = t("账户服务未配置，无法加载想法流。",
                                   "Account service is not configured; the feed cannot load.");
      return;
    }

    var createClient;
    try {
      createClient = (await import("https://esm.sh/@supabase/supabase-js@2")).createClient;
    } catch (e) {
      show(el.authLoading, false);
      el.feedState.textContent = t("账户组件加载失败，请检查网络后刷新。",
                                   "Failed to load the account library; check your connection and reload.");
      return;
    }

    sb = createClient(CFG.supabaseUrl, CFG.supabasePublishableKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false }
    });

    var userRes = await sb.auth.getUser();
    await applyAuth(userRes && userRes.data ? userRes.data.user : null);
    await loadFeed(false);

    // 在别的标签页登录或退出后，这一页跟着变，列清单也要跟着换（anon 读不到 author_id）
    sb.auth.onAuthStateChange(async function (_evt, session) {
      var next = session && session.user ? session.user.id : null;
      var prev = me ? me.id : null;
      if (next === prev) return;
      await applyAuth(session ? session.user : null);
      await loadFeed(false);
    });

    el.form.addEventListener("submit", submitThought);
    el.body.addEventListener("input", updateCounter);
    el.loadMore.addEventListener("click", function () { loadFeed(true); });
    el.loadReports.addEventListener("click", loadReports);

    // 语言切换后重排一次（时间与按钮文案是脚本生成的，不在 i18n 的文本字典里）
    window.addEventListener("storage", function (e) {
      if (e.key === "ooglex.language") loadFeed(false);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
