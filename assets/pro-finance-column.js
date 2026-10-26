(function () {
  "use strict";

  if (location.pathname.indexOf("/apps/finance-column/") < 0 || !window.OoglexPro) return;

  var product = "finance_column";
  // 只有已登录用户会等这一步（访客不发请求）。登录续期 + 会员校验在大陆移动网络下
  // 4 秒常常不够，放宽到 8 秒；超时仍先按预览显示，权限晚到时再自动重新加载一次。
  var ACCESS_GATE_MS = 8000;

  function previewAccess(degraded) {
    var access = { authenticated: false, plan: "free", access_level: "preview" };
    if (degraded) access.degraded = degraded;
    return access;
  }

  function hasSession() {
    try { return !!(window.OoglexPro.getSession && window.OoglexPro.getSession()); }
    catch (_) { return false; }
  }

  function withGate(promise) {
    return new Promise(function (resolve) {
      var done = false;
      var timedOut = false;
      var timer = setTimeout(function () {
        if (done) return;
        done = true;
        timedOut = true;
        resolve(previewAccess("timeout"));
      }, ACCESS_GATE_MS);
      promise.then(function (access) {
        if (done) {
          // 已按预览显示后，完整权限才姗姗来迟：重新加载一次，换成完整数据。
          if (timedOut && access && access.access_level === "full") reloadForLateAccess();
          return;
        }
        done = true;
        clearTimeout(timer);
        resolve(access && access.access_level ? access : previewAccess("empty"));
      });
    });
  }

  // 同一页面 10 分钟内最多自动重新加载一次，网络持续很慢时不会反复刷新。
  function reloadForLateAccess() {
    var key = "ooglex-late-full:" + location.pathname;
    try {
      var last = Number(sessionStorage.getItem(key) || 0);
      if (Date.now() - last < 10 * 60 * 1000) return;
      sessionStorage.setItem(key, String(Date.now()));
    } catch (_) {
      return;
    }
    location.reload();
  }

  // 预览是因为会员服务超时或连不上（不是没有权限）时，后台再试两次；
  // 拿到完整权限就重新加载一次，换成完整数据。
  function retryInBackground() {
    var delays = [2000, 8000];
    (function next(i) {
      if (i >= delays.length) return;
      setTimeout(function () {
        window.OoglexPro.getAccess(product).then(function (access) {
          if (access && access.access_level === "full") reloadForLateAccess();
        }, function () { next(i + 1); });
      }, delays[i]);
    })(0);
  }

  function onReady(fn) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", fn, { once: true });
    } else {
      fn();
    }
  }

  function attachArch(raw) {
    if (!raw || !Array.isArray(raw.layers)) return false;
    raw.findLayer = function (id) {
      return this.layers.find(function (l) { return l.id === id; }) || null;
    };
    raw.moduleCount = function () {
      return this.layers.reduce(function (n, l) { return n + l.modules.length; }, 0);
    };
    raw.termCount = function () {
      return this.layers.reduce(function (n, l) {
        return n + l.modules.reduce(function (m, mod) { return m + mod.terms.length; }, 0);
      }, 0);
    };
    raw.layerTermCount = function (layer) {
      return layer.modules.reduce(function (m, mod) { return m + mod.terms.length; }, 0);
    };
    raw.flatTerms = function () {
      var out = [];
      this.layers.forEach(function (l) {
        l.modules.forEach(function (mod) {
          mod.terms.forEach(function (t) {
            out.push({ cn: t[0], en: t[1], note: t[2] || "", layer: l, module: mod });
          });
        });
      });
      return out;
    };
    window.ARCH = raw;
    return true;
  }

  function attachDiagrams(raw) {
    if (!raw || !Array.isArray(raw.groups)) return false;
    raw.count = function () {
      return this.groups.reduce(function (n, g) { return n + g.items.length; }, 0);
    };
    window.DIAGRAMS = raw;
    return true;
  }

  function installBadge(access) {
    if (document.getElementById("ooglex-rich-access")) return;
    var chip = document.createElement("div");
    chip.id = "ooglex-rich-access";
    chip.textContent = access && access.access_level === "full"
      ? (access.plan === "signed_in" ? "已登录" : String(access.plan || "PRO").toUpperCase()) + " · FULL"
      : "FREE · 10% PREVIEW";
    chip.style.cssText = [
      "position:fixed","right:14px","bottom:14px","z-index:10001",
      "padding:7px 11px","border-radius:999px",
      "font:600 11px/1.2 -apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif",
      "letter-spacing:.4px","color:#dfe7ec","background:rgba(10,14,20,.88)",
      "border:1px solid rgba(255,255,255,.14)","backdrop-filter:blur(8px)",
      "box-shadow:0 8px 24px rgba(0,0,0,.28)"
    ].join(";");
    document.body.appendChild(chip);
  }

  function installWall(access) {
    if (access && access.access_level === "full") return;
    if (document.getElementById("ooglex-preview-wall")) return;

    var page = document.querySelector(".page");
    if (!page || !page.parentNode) return;

    // FREE preview: the base page keeps 80px bottom padding for standalone pages.
    // Once the paywall is appended that padding becomes a visible dead gap, especially
    // on mobile. Compact it only for preview mode so the dark wall follows the footer.
    var isMobile = !!(window.matchMedia && window.matchMedia("(max-width: 560px)").matches);
    page.style.paddingBottom = isMobile ? "12px" : "20px";

    var fade = document.createElement("div");
    fade.id = "ooglex-preview-fade";
    fade.setAttribute("aria-hidden", "true");
    var fadeHeight = 110;
    fade.style.cssText = [
      "height:" + fadeHeight + "px","margin-top:-" + fadeHeight + "px","position:relative","z-index:5","pointer-events:none",
      "background:linear-gradient(to bottom,rgba(15,15,18,0),rgba(23,23,23,.96))"
    ].join(";");

    var wall = document.createElement("section");
    wall.id = "ooglex-preview-wall";
    wall.setAttribute("data-ooglex-preview-hard-stop", "true");
    wall.style.cssText = [
      "position:relative","z-index:6","box-sizing:border-box","width:100%","min-height:218px","padding:24px 20px 22px","text-align:center","background:#171717","color:#f5f5f5",
      "border-top:1px solid rgba(255,255,255,.10)","box-shadow:0 -18px 50px rgba(0,0,0,.30)",
      "font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei',sans-serif"
    ].join(";");

    var title = document.createElement("div");
    title.textContent = "继续查看完整数据";
    title.style.cssText = "font-size:27px;font-weight:760;letter-spacing:-.3px;margin:1px 0 8px";

    var sub = document.createElement("div");
    sub.textContent = access && access.degraded
      ? "会员服务响应较慢或暂时连不上，已先按预览显示。连上后会自动换成完整数据，也可以点「重新加载」。"
      : access && access.authenticated
        ? "你已登录，但账户权限暂时无法确认，当前先显示预览。请刷新或重新登录后再试。"
        : (hasSession() ? "登录状态已失效，请重新登录后查看完整数据。" : "当前展示原版页面预览。登录 / 注册后可查看完整数据。");
    sub.style.cssText = "font-size:14px;line-height:1.7;color:#c8c8c8;margin:0 auto 18px;max-width:760px";

    var button = document.createElement("a");
    button.href = access && access.degraded ? location.href : "/account/";
    button.textContent = access && access.degraded ? "重新加载"
      : access && access.authenticated ? "前往账户"
      : hasSession() ? "重新登录" : "登录 / 注册";
    button.style.cssText = [
      "display:inline-flex","align-items:center","justify-content:center","min-width:270px","height:44px",
      "padding:0 22px","border-radius:4px","background:#fff","color:#111","text-decoration:none",
      "font-size:15px","font-weight:720","box-shadow:none"
    ].join(";");

    var note = document.createElement("div");
    note.textContent = "完整数据不会发送给未登录浏览器；页面下方仅保留受限预览。";
    note.style.cssText = "font-size:11px;color:#8f8f8f;margin-top:14px";

    wall.appendChild(title);
    wall.appendChild(sub);
    wall.appendChild(button);
    wall.appendChild(note);
    page.parentNode.insertBefore(fade, page.nextSibling);
    fade.parentNode.insertBefore(wall, fade.nextSibling);
  }

  var accessPromise = hasSession()
    ? withGate(window.OoglexPro.getAccess(product).catch(function () {
        return previewAccess("unreachable");
      }))
    : Promise.resolve(previewAccess());
  accessPromise.then(function (access) {
    if (access && access.degraded) retryInBackground();
  });

  var fullPromise = accessPromise.then(function (access) {
    if (!access || access.access_level !== "full") return null;
    return window.OoglexPro.getData(product, "full");
  }).catch(function () { return null; });

  accessPromise.then(function (access) {
    onReady(function () {
      installBadge(access);
      if (!access || access.access_level !== "full") {
        installWall(access);
        return;
      }
      fullPromise.then(function (bundle) {
        if (!bundle) return;
        var changed = false;
        if (bundle.arch) changed = attachArch(bundle.arch) || changed;
        if (bundle.diagrams) changed = attachDiagrams(bundle.diagrams) || changed;
        if (changed) {
          window.OoglexFinanceDataVersion = "full";
          window.dispatchEvent(new CustomEvent("ooglex:finance-full-ready"));
        }
      });
    });
  });
})();
