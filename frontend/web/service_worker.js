const CACHE_NAME = 'aveliclient-cache-v1';

self.addEventListener('install', (event) => {
  // Activate immediately on install to reduce risk of stale assets.
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key !== CACHE_NAME)
            .map((key) => caches.delete(key)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;

  if (request.method !== 'GET') {
    return;
  }

  // Ignore browser extension and devtool requests.
  if (request.url.startsWith('chrome-extension') || request.url.includes('browser-sync')) {
    return;
  }

  event.respondWith(
    caches.open(CACHE_NAME).then((cache) =>
      fetch(request)
        .then((response) => {
          if (response && response.ok && response.type === 'basic') {
            cache.put(request, response.clone());
          }
          return response;
        })
        .catch(() => cache.match(request)),
    ),
  );
});
