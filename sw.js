// Service Worker mínimo · LiTa Support — Login Único
// Mismo criterio que vitality-control/sw.js y cdjsupport/sw.js: el único objetivo es
// cumplir el criterio de instalabilidad de Chrome/Android para PWA (manifest + service
// worker con evento fetch), sin cachear agresivamente -- esta página resuelve login
// contra dos backends reales, una versión vieja cacheada nunca debe servirse como si
// fuera la actual. Estrategia: network-first con fallback a cache solo si no hay red.
const CACHE = 'lita-login-shell-v1';
const SHELL = ['./index.html', './manifest.json', './icons/icon-192.png', './icons/icon-512.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  event.respondWith(
    fetch(event.request)
      .then((res) => {
        var resClone = res.clone();
        caches.open(CACHE).then((cache) => cache.put(event.request, resClone));
        return res;
      })
      .catch(() => caches.match(event.request))
  );
});
