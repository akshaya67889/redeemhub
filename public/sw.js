const CACHE_NAME = 'redeemhub-shell-v1';
const SHELL = ['/', '/manifest.webmanifest', '/redeemhub-mark.svg'];
self.addEventListener('install', event => { event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(SHELL))); self.skipWaiting(); });
self.addEventListener('activate', event => { event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))))); self.clients.claim(); });
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin || url.pathname.startsWith('/functions/') || url.pathname.startsWith('/rest/')) return;
  event.respondWith(fetch(request).then(response => { if (response.ok && (url.pathname === '/' || url.pathname.startsWith('/assets/') || url.pathname.endsWith('.svg') || url.pathname.endsWith('.webmanifest'))) { const clone = response.clone(); caches.open(CACHE_NAME).then(cache => cache.put(request, clone)); } return response; }).catch(async () => (await caches.match(request)) || (await caches.match('/'))));
});
