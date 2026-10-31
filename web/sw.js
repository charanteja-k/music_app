/* DilSe PWA Service Worker (Zero-Data Offline App Shell & Audio Engine) */
const SHELL_CACHE = 'dilse-shell-v4';
const AUDIO_CACHE = 'dilse-offline-audio-v1';

const PRECACHE_ASSETS = [
  '/',
  'index.html',
  'manifest.json',
  'favicon.png',
  'dilse_web_player.js',
  'flutter_bootstrap.js',
  'main.dart.js',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/Icon-maskable-192.png',
  'icons/Icon-maskable-512.png'
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(SHELL_CACHE).then(async (cache) => {
      console.log('[DilSe SW] Pre-caching app shell assets (v4)');

      // Fetch root HTML document and store clean, non-redirected copies for all root navigation paths.
      // Critical for Safari iOS WebKit: Vercel clean URLs redirect /index.html -> / (HTTP 308).
      // Storing an unredirected Response ensures response.redirected === false on offline launch.
      try {
        const rootResp = await fetch('/', { cache: 'reload' });
        if (rootResp && rootResp.ok) {
          const blob = await rootResp.blob();
          const headers = new Headers(rootResp.headers);
          headers.set('Content-Type', 'text/html; charset=utf-8');

          await cache.put('/', new Response(blob, { status: 200, statusText: 'OK', headers }));
          await cache.put('./', new Response(blob, { status: 200, statusText: 'OK', headers }));
          await cache.put('index.html', new Response(blob, { status: 200, statusText: 'OK', headers }));
        }
      } catch (err) {
        console.warn('[DilSe SW] Root index precache error:', err);
      }

      // Pre-cache secondary static assets with Promise.allSettled so one miss never fails the cache
      const precacheJobs = PRECACHE_ASSETS.filter((p) => p !== '/' && p !== 'index.html').map(async (path) => {
        try {
          const resp = await fetch(path);
          if (resp && (resp.ok || resp.type === 'opaque')) {
            await cache.put(path, resp);
          }
        } catch (e) {
          // Non-critical optional asset on cold start
        }
      });
      await Promise.allSettled(precacheJobs);
    })
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== SHELL_CACHE && key !== AUDIO_CACHE) {
            console.log('[DilSe SW] Cleaning obsolete cache:', key);
            return caches.delete(key);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

// Safari iOS requires HTTP 206 Partial Content for HTML5 Audio playback from Cache
async function handleAudioRangeRequest(request) {
  const cache = await caches.open(AUDIO_CACHE);
  const url = new URL(request.url);
  const key = url.pathname;

  let response = await cache.match(key);
  if (!response) {
    response = await cache.match(request);
  }

  if (!response) {
    // If not in cache, pass to network
    return fetch(request);
  }

  const rangeHeader = request.headers.get('range');
  if (!rangeHeader) {
    return response;
  }

  const arrayBuffer = await response.arrayBuffer();
  const totalLength = arrayBuffer.byteLength;
  const matches = rangeHeader.match(/bytes=(\d+)-(\d*)/);

  if (!matches) {
    return response;
  }

  const start = parseInt(matches[1], 10);
  const end = matches[2] ? parseInt(matches[2], 10) : totalLength - 1;

  if (start >= totalLength || end >= totalLength) {
    return new Response(null, {
      status: 416,
      statusText: 'Range Not Satisfiable',
      headers: {
        'Content-Range': `bytes */${totalLength}`
      }
    });
  }

  const sliced = arrayBuffer.slice(start, end + 1);
  return new Response(sliced, {
    status: 206,
    statusText: 'Partial Content',
    headers: {
      'Content-Range': `bytes ${start}-${end}/${totalLength}`,
      'Content-Length': String(sliced.byteLength),
      'Content-Type': response.headers.get('Content-Type') || 'audio/mp4',
      'Accept-Ranges': 'bytes',
      'Cache-Control': 'public, max-age=31536000'
    }
  });
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = new URL(req.url);

  // 1. Offline audio requests (local offline audio endpoints)
  if (url.pathname.startsWith('/offline_audio/') || req.headers.get('accept')?.includes('audio/')) {
    event.respondWith(handleAudioRangeRequest(req));
    return;
  }

  // 2. Navigation requests: Network-first, fallback to clean cached index.html
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then(async (networkResp) => {
          if (networkResp && networkResp.status === 200) {
            const cache = await caches.open(SHELL_CACHE);
            // If Vercel or hosting redirected the request (e.g. trailing slash / clean URL),
            // clean it before storing so offline navigation never receives redirected: true
            if (networkResp.redirected) {
              const blob = await networkResp.clone().blob();
              const headers = new Headers(networkResp.headers);
              headers.set('Content-Type', 'text/html; charset=utf-8');
              const cleanResp = new Response(blob, {
                status: 200,
                statusText: 'OK',
                headers
              });
              await cache.put(req, cleanResp);
            } else {
              await cache.put(req, networkResp.clone());
            }
          }
          return networkResp;
        })
        .catch(async () => {
          const cache = await caches.open(SHELL_CACHE);
          const cachedIndex =
            (await cache.match('/')) ||
            (await cache.match('./')) ||
            (await cache.match('index.html'));

          if (cachedIndex) {
            // CRITICAL FOR SAFARI / WEBKIT (Zero-Black-Screen PWA Invariant):
            // Safari throws "Response served by service worker has redirections"
            // if a response returned to respondWith() has redirected === true or opaqueredirect type.
            // Creating a new Response from blob() strips the redirected flag completely.
            const blob = await cachedIndex.blob();
            const headers = new Headers(cachedIndex.headers);
            headers.set('Content-Type', 'text/html; charset=utf-8');
            return new Response(blob, {
              status: 200,
              statusText: 'OK',
              headers
            });
          }

          return new Response(
            '<!DOCTYPE html><html><head><meta charset="utf-8"><title>DilSe Offline</title>' +
            '<meta name="viewport" content="width=device-width, initial-scale=1.0">' +
            '<style>body{background:#000;color:#fff;font-family:sans-serif;display:flex;' +
            'align-items:center;justify-content:center;height:100vh;margin:0;padding:20px;' +
            'text-align:center;box-sizing:border-box;}</style></head><body>' +
            '<div><h2>DilSe is Offline</h2><p>Please open DilSe once while connected to the internet to initialize the offline player.</p></div>' +
            '</body></html>',
            {
              status: 200,
              headers: { 'Content-Type': 'text/html; charset=utf-8' }
            }
          );
        })
    );
    return;
  }

  // 3. Static assets (JS, WASM, CSS, Images, Fonts) -> Cache-first with background revalidation
  const isStaticAsset =
    url.pathname.endsWith('.js') ||
    url.pathname.endsWith('.wasm') ||
    url.pathname.endsWith('.css') ||
    url.pathname.endsWith('.png') ||
    url.pathname.endsWith('.jpg') ||
    url.pathname.endsWith('.ttf') ||
    url.pathname.endsWith('.woff2') ||
    url.pathname.endsWith('.json') ||
    url.origin === self.location.origin;

  if (isStaticAsset) {
    event.respondWith(
      caches.match(req).then((cachedResp) => {
        if (cachedResp) {
          // Return cache immediately (0ms instant startup) and revalidate in background if online
          fetch(req).then((networkResp) => {
            if (networkResp && networkResp.status === 200) {
              caches.open(SHELL_CACHE).then((cache) => cache.put(req, networkResp));
            }
          }).catch(() => {});
          return cachedResp;
        }

        // If not in cache, fetch from network and populate cache
        return fetch(req).then((networkResp) => {
          if (networkResp && networkResp.status === 200) {
            const respClone = networkResp.clone();
            caches.open(SHELL_CACHE).then((cache) => cache.put(req, respClone));
          }
          return networkResp;
        });
      })
    );
    return;
  }

  // Default passthrough for other requests
  event.respondWith(fetch(req));
});
