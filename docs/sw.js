const CACHE_NAME = 'dbcheck-v2';
const PRECACHE_URLS = [
    '/',
    '/index.html',
    '/static/index.html',
    '/admin',
    '/static/admin.html'
];

// Install: precache static assets
self.addEventListener('install', function(event) {
    event.waitUntil(
        caches.open(CACHE_NAME).then(function(cache) {
            return Promise.all(PRECACHE_URLS.map(function(url) {
                return cache.add(url).catch(function() {
                    console.warn('Failed to precache:', url);
                });
            }));
        }).then(function() {
            return self.skipWaiting();
        })
    );
});

// Activate: clean old caches
self.addEventListener('activate', function(event) {
    event.waitUntil(
        caches.keys().then(function(names) {
            return Promise.all(
                names.filter(function(name) { return name !== CACHE_NAME; })
                    .map(function(name) { return caches.delete(name); })
            );
        }).then(function() {
            return self.clients.claim();
        })
    );
});

// Fetch: network-first for API, cache-first for static
self.addEventListener('fetch', function(event) {
    var url = new URL(event.request.url);

    // Never cache API calls, admin API, or upload/download
    if (url.pathname.startsWith('/api/') ||
        url.pathname.startsWith('/admin/api/') ||
        event.request.method !== 'GET') {
        return;
    }

    // Cache-first for static assets, network-first for pages
    event.respondWith(
        caches.match(event.request).then(function(cached) {
            var fetched = fetch(event.request).then(function(response) {
                // Update cache with fresh response
                if (response.ok) {
                    var clone = response.clone();
                    caches.open(CACHE_NAME).then(function(cache) {
                        cache.put(event.request, clone);
                    }).catch(function() { /* quota exceeded or other cache error */ });
                }
                return response;
            }).catch(function() {
                // Network failed, return cached or offline fallback
                return cached;
            });
            // Return cached immediately if available (stale-while-revalidate)
            return cached || fetched;
        })
    );
});
