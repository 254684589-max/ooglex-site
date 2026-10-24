/* Ooglex App 专区登记表：首页 #app-zone 与 /apps/app-zone/ 共用这一份。
   新增 App 只需在数组末尾加一项（见 docs/APP_ZONE.md）：
   id 唯一英文短名；name 中文名（只作无障碍名称与悬停提示，不在图标下显示）；
   icon 方形图标（建议 512×512 SVG，圆角 rx≈112）；href 该 App 的下载/安装页。 */
window.OOGLEX_APPS = [
  { id: "oogle-x", name: "OOGLE X · 科技领袖", en: "OOGLE X · Tech Leaders", icon: "/apps/app-zone/icons/oogle-x.svg", href: "/apps/tech-leaders/app/", platform: "android" },
  { id: "radio",   name: "环球电波",           en: "Global Radio",           icon: "/apps/radio/icons/icon.svg",      href: "/apps/radio/download/",   platform: "android" },
  { id: "tv",      name: "环球TV",             en: "Global TV",              icon: "/apps/tv/icons/icon.svg",         href: "/apps/app-zone/tv/",      platform: "web" },
  { id: "ai-chat", name: "万象智聊",           en: "AI Chat",                icon: "/apps/ai-chat/icons/icon.svg",    href: "/apps/app-zone/ai-chat/", platform: "web" },
  { id: "global-cams", name: "环球实景",       en: "Global Window",          icon: "/apps/global-cams/icons/icon.svg", href: "/apps/global-cams/download/", platform: "android" }
];

/* 把图标渲染进容器：只放图标，名字进 aria-label 与 title。 */
window.ooglexRenderApps = function (box) {
  if (!box) return;
  var en = document.documentElement.getAttribute("data-lang") === "en";
  var frag = document.createDocumentFragment();
  window.OOGLEX_APPS.forEach(function (app) {
    var a = document.createElement("a");
    a.className = "az-app";
    a.href = app.href;
    var label = en ? app.en : app.name;
    a.setAttribute("aria-label", label);
    a.title = label;
    var img = document.createElement("img");
    img.src = app.icon; img.alt = ""; img.width = 128; img.height = 128;
    img.loading = "lazy"; img.decoding = "async";
    a.appendChild(img);
    frag.appendChild(a);
  });
  box.textContent = "";
  box.appendChild(frag);
};
