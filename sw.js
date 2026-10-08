// Service Worker mínimo · LiTa Support — Login Único
// Mismo criterio que vitality-control/sw.js y cdjsupport/sw.js: el único objetivo es
// cumplir el criterio de instalabilidad de Chrome/Android para PWA (manifest + service
// worker con evento fetch), sin cachear agresivamente -- esta página resuelve login
// contra dos backends reales, una versión vieja cacheada nunca debe servirse como si
// fuera la actual. Estrategia: network-first con fallback a cache solo si no hay red.
const CACHE = 'lita-login-shell-v3'; // v3 (8 oct 2026): pantalla Eliminar mi cuenta. v2 (2 oct 2026): fuerza purgar el cache viejo potencialmente stale
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
  // Bug real corregido 2 oct 2026: GitHub Pages manda `cache-control:max-age=600` en
  // index.html -- un fetch() normal respeta ese cache HTTP del navegador aunque la
  // ESTRATEGIA del service worker sea "network-first", así que una recarga podía seguir
  // sirviendo una copia de hasta 10 minutos de antigüedad sin tocar la red de verdad
  // (confirmado real en un iPhone: seguía mostrando el comportamiento viejo del login
  // único después de haber corregido y publicado el código). `cache:'reload'` fuerza que
  // esta petición SIEMPRE vaya a la red, ignorando el cache HTTP (no el de este Service
  // Worker, que es el respaldo intencional para cuando sí falla la red, más abajo).
  event.respondWith(
    fetch(event.request, { cache: 'reload' })
      .then((res) => {
        var resClone = res.clone();
        caches.open(CACHE).then((cache) => cache.put(event.request, resClone));
        return res;
      })
      .catch(() => caches.match(event.request))
  );
});
