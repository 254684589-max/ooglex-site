from pathlib import Path
import re

path = Path("assets/theme.js")
text = path.read_text(encoding="utf-8")
pattern = r'  function buildHomepageAccountLink\(\) \{.*?\n  \}\n\n  function build\(\) \{'
replacement = '''  function buildHomepageAccountLink() {
    var p = window.location.pathname || "/";
    if (p !== "/" && p !== "/index.html") return;
    var links = document.querySelector("nav .links");
    if (!links || links.querySelector('a[href="/account/"]')) return;
    var a = document.createElement("a");
    a.href = "/account/";
    a.id = "account-nav-link";

    /* Supabase stores the same-origin login session under this localStorage key.
       The homepage only checks whether a session exists; it never reads passwords or sends extra requests. */
    var AUTH_KEY = "sb-nwthqkpkvbtilafqpjlf-auth-token";
    function signedIn() {
      try {
        var raw = localStorage.getItem(AUTH_KEY);
        return !!raw && raw !== "null" && raw !== "undefined";
      } catch (e) { return false; }
    }
    function syncAccountLabel() {
      var en = isEnglish(), active = signedIn();
      a.textContent = active ? (en ? "Account" : "账户") : (en ? "Sign in / Register" : "登录 / 注册");
      a.setAttribute("aria-label", active ? (en ? "Open account center" : "打开账户中心") : (en ? "Sign in or register" : "登录或注册账户"));
      a.title = active ? (en ? "Ooglex Account" : "Ooglex 账户中心") : (en ? "Sign in / Register" : "登录 / 注册");
    }
    var before = document.getElementById("music-toggle") || document.getElementById("language-toggle");
    links.insertBefore(a, before || null);
    document.addEventListener("ooglex:languagechange", syncAccountLabel);
    window.addEventListener("storage", function (e) { if (e.key === AUTH_KEY) syncAccountLabel(); });
    window.addEventListener("pageshow", syncAccountLabel);
    syncAccountLabel();
  }

  function build() {'''
updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
if count != 1:
    raise SystemExit(f"Expected one homepage account nav function, replaced {count}")
path.write_text(updated, encoding="utf-8")
