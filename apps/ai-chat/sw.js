/* 万象智聊 · Service Worker
   目标：让应用可安装、可离线启动。
   策略：
     · 安装时只预缓存"外壳"（很小，秒装）；
     · 其余同源静态资源首次用到时再缓存；
     · 跨域请求（大模型 API、广告等）一律直连、绝不拦截/缓存；
     · 只处理 GET，聊天的 POST 请求永远不经过缓存。 */
const VERSION = 'aichat-v10';
const SHELL_CACHE = 'aichat-shell-' + VERSION;
const RUNTIME_CACHE = 'aichat-runtime-' + VERSION;

// 外壳：小而关键，保证秒装 + 离线能起来
const SHELL = [
  './',
  './index.html',
  './app.js',
  './manifest.webmanifest',
  './icons/icon.svg',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './apple-touch-icon.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE)
      // 单个文件失败不拖垮整体安装
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

  // 跨域一律放行（大模型 API / 广告 / 统计），不缓存、不拦截
  if (url.origin !== self.location.origin) return;

  // 只处理本应用作用域内的资源
  if (!url.pathname.startsWith('/apps/ai-chat/')) return;

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

  // 代码与配置（app.js / sw 之外的脚本 / shared-config.json）：网络优先，
  // 保证联网时总能拿到最新版，避免手机卡在旧缓存；断网才回退缓存。
  const netFirst = /\.(js|json|webmanifest)$/.test(url.pathname);
  if (netFirst) {
    event.respondWith(
      fetch(req).then((res) => {
        if (res && res.ok) {
          const copy = res.clone();
          caches.open(RUNTIME_CACHE).then((c) => c.put(req, copy)).catch(() => {});
        }
        return res;
      }).catch(() => caches.match(req, { ignoreSearch: true }))
    );
    return;
  }

  // 其余同源静态资源（图标等）：stale-while-revalidate
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
