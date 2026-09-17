(function () {
  "use strict";

  var path = location.pathname;
  var isMacro = path.indexOf("/apps/macro-radar/") >= 0;
  var isSupply = path.indexOf("/apps/supply-chain/") >= 0;
  if (!isMacro && !isSupply) return;

  function rootForPage() {
    if (isMacro) return document.querySelector(".wrap");
    return document.querySelector(".page") || document.querySelector(".wrap") || document.querySelector("main");
  }

  function preferredCutoff(root) {
    var target = null;

    if (isMacro) {
      var signals = document.getElementById("signals");
      if (signals && signals.children.length) {
        target = signals;
      }
    } else if (path.indexOf("company.html") >= 0) {
      var smelters = document.querySelector(".smelters");
      if (smelters && smelters.offsetHeight > 40) target = smelters;
      if (!target) {
        var stage = document.querySelector(".stagefig");
        if (stage && stage.offsetHeight > 40) target = stage;
      }
    }

    if (target) {
      var rr = root.getBoundingClientRect();
      var tr = target.getBoundingClientRect();
      var measured = Math.ceil(tr.bottom - rr.top + 28);
      if (measured > 0) return measured;
    }

    var vh = Math.max(window.innerHeight || 0, 720);
    if (isMacro) return Math.max(920, Math.min(1240, Math.round(vh * 1.18)));
    if (path.indexOf("company.html") >= 0) return Math.max(1050, Math.min(1480, Math.round(vh * 1.38)));
    return Math.max(980, Math.min(1380, Math.round(vh * 1.28)));
  }

  function makeFade(root) {
    var old = document.getElementById("ooglex-preview-fade");
    if (old) old.remove();

    var fade = document.createElement("div");
    fade.id = "ooglex-preview-fade";
    fade.setAttribute("aria-hidden", "true");
    fade.style.cssText = [
      "position:absolute","left:0","right:0","bottom:0","height:128px","z-index:9998",
      "pointer-events:none",
      "background:linear-gradient(to bottom,rgba(23,23,23,0),rgba(23,23,23,.96))"
    ].join(";");
    root.appendChild(fade);
  }

  function restyleWall(root) {
    var wall = document.getElementById("ooglex-preview-wall");
    if (!wall) return false;

    wall.setAttribute("data-ooglex-preview-hard-stop", "true");
    wall.style.position = "relative";
    wall.style.left = "auto";
    wall.style.right = "auto";
    wall.style.bottom = "auto";
    wall.style.width = "100%";
    wall.style.zIndex = "9999";
    wall.style.margin = "0";
    wall.style.minHeight = "218px";

    if (root.parentNode) root.parentNode.insertBefore(wall, root.nextSibling);

    var chip = document.getElementById("ooglex-rich-access");
    if (chip) chip.style.bottom = "14px";
    return true;
  }

  function installHardStop(attempt) {
    var wall = document.getElementById("ooglex-preview-wall");
    if (!wall) return false;

    var badge = document.getElementById("ooglex-rich-access");
    if (badge && /(?:OWNER|PRO)\s*·\s*FULL/i.test(badge.textContent || "")) return true;

    var root = rootForPage();
    if (!root) return false;

    // Give the legacy app a short window to finish rendering the visible preview
    // so the cutoff can sit after a meaningful section rather than mid-card.
    if (attempt < 20) {
      if (isMacro) {
        var signals = document.getElementById("signals");
        if (!signals || !signals.children.length) return false;
      }
      if (isSupply && path.indexOf("company.html") >= 0) {
        var stage = document.querySelector(".stagefig");
        if (!stage || stage.offsetHeight < 40) return false;
      }
    }

    if (root.getAttribute("data-ooglex-preview-clipped") === "true") return true;

    var cap = preferredCutoff(root);
    var natural = Math.max(root.scrollHeight || 0, root.offsetHeight || 0);
    if (natural > 0) cap = Math.min(cap, natural);
    cap = Math.max(520, cap);

    var computed = window.getComputedStyle(root);
    if (!computed.position || computed.position === "static") root.style.position = "relative";
    root.style.maxHeight = cap + "px";
    root.style.overflow = "hidden";
    root.setAttribute("data-ooglex-preview-clipped", "true");
    root.setAttribute("data-ooglex-preview-cap", String(cap));

    makeFade(root);
    restyleWall(root);

    // If the browser restored a scroll position from before the gate was applied,
    // snap back to the last legitimate preview position.
    requestAnimationFrame(function () {
      var rootTop = root.getBoundingClientRect().top + window.scrollY;
      var maxScroll = Math.max(0, rootTop + cap - window.innerHeight + 140);
      if (window.scrollY > maxScroll) window.scrollTo({ top: maxScroll, left: 0, behavior: "auto" });
    });

    return true;
  }

  var attempts = 0;
  function tryInstall() {
    attempts += 1;
    if (installHardStop(attempts)) return;
    if (attempts < 50) window.setTimeout(tryInstall, 60);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", tryInstall, { once: true });
  } else {
    tryInstall();
  }

  var observer = new MutationObserver(function () {
    if (document.getElementById("ooglex-preview-wall")) tryInstall();
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });
  window.setTimeout(function () { observer.disconnect(); }, 6000);
})();
