/* 环球TV · Service Worker
   目标：让应用可安装、可离线启动。
   策略：
     · 安装时只预缓存"外壳"（很小，秒装）；
     · 大文件（地球纹理、globe.gl、hls.js、channels.json）首次用到时再缓存（离线可用）；
     · 跨域请求（电视直播流、外站台标）一律直连、绝不拦截/缓存。 */
const VERSION = 'tv-v1';
const SHELL_CACHE = 'tv-shell-' + VERSION;
const RUNTIME_CACHE = 'tv-runtime-' + VERSION;

// 外壳：小而关键，保证秒装 + 离线能起来
const SHELL = [
  './',
  './index.html',
  './app.js?v=1',
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
        keys.filter((k) => k !== SHELL_CACHE && k !== RUNTIME_CACHE)
            .map((k) => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('message', (event) => {
  if (event.data === 'skipWaiting') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // 跨域一律放行（电视直播流 / 外站台标），不缓存、不拦截
  if (url.origin !== self.location.origin) return;

  // 只处理本应用作用域内的资源
  if (!url.pathname.startsWith('/apps/tv/')) return;

  // 页面导航：网络优先，断网回退到缓存的外壳，保证离线也能打开
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(SHELL_CACHE).then((c) => c.put('./index.html', copy)).catch(() => {});
          return res;
        })
        .catch(() => caches.match(req, { ignoreSearch: true })
          .then((hit) => hit || caches.match('./index.html')))
    );
    return;
  }

  // 其余同源静态资源：stale-while-revalidate（忽略查询串，兼容 channels.json?t=… 的缓存穿透）
  event.respondWith(
    caches.match(req, { ignoreSearch: true }).then((cached) => {
      const network = fetch(req).then((res) => {
        if (res && (res.ok || res.type === 'opaque')) {
          const copy = res.clone();
          caches.open(RUNTIME_CACHE).then((c) => c.put(req, copy)).catch(() => {});
        }
        return res;
      }).catch(() => cached);
      return cached || network;
    })
  );
});
