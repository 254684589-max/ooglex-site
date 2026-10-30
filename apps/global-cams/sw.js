/* 环球实景 · Service Worker
   目标：让应用可安装、可离线启动外壳。
   策略：
     · 安装时只预缓存"外壳"（很小，秒装）；
     · 地球纹理与 globe.gl（与环球电波共用 /apps/radio/vendor/）首次用到时再缓存；
     · 备用清单 windows.json 网络优先：始终取最新，离线才回退缓存；
     · 跨域请求（WINDOW 视频库、R2/CDN 视频、Wikimedia 素材）一律直连、绝不拦截/缓存。 */
const VERSION = 'gc-v5';
const SHELL_CACHE = 'gc-shell-' + VERSION;
const RUNTIME_CACHE = 'gc-runtime-' + VERSION;

const SHELL = [
  './',
  './index.html',
  './app.js?v=18',
  './config.js',
  './manifest.webmanifest',
  './icons/icon.svg',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './apple-touch-icon.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE)
      .then((cache) => Promise.allSettled(SHELL.map((u) => cache.add(u))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((k) => k.startsWith('gc-') && k !== SHELL_CACHE && k !== RUNTIME_CACHE)
            .map((k) => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // 跨域一律放行（视频库清单、视频文件、素材来源），不缓存、不拦截
  if (url.origin !== self.location.origin) return;

  // 只处理本应用与共用的地球资源
  const own = url.pathname.startsWith('/apps/global-cams/');
  const vendor = url.pathname.startsWith('/apps/radio/vendor/');
  if (!own && !vendor) return;

  // 下载页和 APK 不进缓存。导航若被写进外壳 index.html，离线会打开下载页而不是地球；
  // APK 也不走 stale-while-revalidate，避免整包占缓存。
  if (own && (/\/global-cams\/download(\/|$)/.test(url.pathname) || url.pathname.endsWith('.apk'))) {
    return;
  }

  // 备用清单：网络优先，离线才回退
  if (own && /\/windows\.json$/.test(url.pathname)) {
    const key = url.origin + url.pathname;
    event.respondWith(
      fetch(req).then((res) => {
        if (res && res.ok) {
          const copy = res.clone();
          caches.open(RUNTIME_CACHE).then((c) => c.put(key, copy)).catch(() => {});
        }
        return res;
      }).catch(() => caches.match(key))
    );
    return;
  }

  // 页面导航：网络优先，断网回退到缓存的外壳
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          if (res && res.ok) {
            const copy = res.clone();
            caches.open(SHELL_CACHE).then((c) => c.put('./index.html', copy)).catch(() => {});
          }
          return res;
        })
        .catch(() => caches.match(req, { ignoreSearch: true })
          .then((hit) => hit || caches.match('./index.html')))
    );
    return;
  }

  // 其余同源静态资源：stale-while-revalidate
  event.respondWith(
    caches.match(req).then((cached) => {
      const network = fetch(req).then((res) => {
        if (res && res.ok) {
          const copy = res.clone();
          caches.open(RUNTIME_CACHE).then((c) => c.put(req, copy)).catch(() => {});
        }
        return res;
      }).catch(() => cached);
      return cached || network;
    })
  );
});
