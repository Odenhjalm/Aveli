// Intentionally disable Flutter's legacy service worker.
//
// Why this file exists:
// - Older deployments may have registered `flutter_service_worker.js` which can
//   keep serving cached (stale) JS bundles even after new deploys.
// - We no longer register a service worker, but existing registrations can
//   persist until explicitly unregistered/updated.
//
// Keeping this URL and immediately unregistering + clearing caches forces
// clients onto the latest deploy without manual cache clearing.

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      try {
        await self.clients.claim();
      } catch (_) {}

      try {
        const keys = await caches.keys();
        await Promise.all(keys.map((key) => caches.delete(key)));
      } catch (_) {}

      try {
        await self.registration.unregister();
      } catch (_) {}

      try {
        const clients = await self.clients.matchAll({
          type: 'window',
          includeUncontrolled: true,
        });
        await Promise.all(
          clients.map(async (client) => {
            try {
              await client.navigate(client.url);
            } catch (_) {}
          }),
        );
      } catch (_) {}
    })(),
  );
});
