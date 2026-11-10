const CACHE_PREFIX = 'redeemhub-shell-';
const CACHE_NAME = `${CACHE_PREFIX}v1`;

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const scope = self.registration.scope;
    const shell = [scope, new URL('manifest.webmanifest', scope).href, new URL('redeemhub-mark.svg', scope).href];
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(shell);
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys
      .filter(key => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
      .map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  const scope = self.registration.scope;
  if (request.method !== 'GET' || url.origin !== self.location.origin || !url.href.startsWith(scope)) return;

  event.respondWith(fetch(request).then(response => {
    if (response.ok && (url.href === scope || url.pathname.startsWith(new URL('assets/', scope).pathname) || url.pathname.endsWith('.svg') || url.pathname.endsWith('.webmanifest'))) {
      const clone = response.clone();
      void caches.open(CACHE_NAME).then(cache => cache.put(request, clone));
    }
    return response;
  }).catch(async () => (await caches.match(request)) || (await caches.match(scope))));
});
