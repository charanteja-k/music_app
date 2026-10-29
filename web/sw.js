/* DilSe PWA Service Worker (Zero-Data Offline App Shell & Audio Engine) */
const SHELL_CACHE = 'dilse-shell-v1';
const AUDIO_CACHE = 'dilse-offline-audio-v1';

const PRECACHE_ASSETS = [
  './',
  'index.html',
  'manifest.json',
  'favicon.png',
  'dilse_web_player.js',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/Icon-maskable-192.png',
  'icons/Icon-maskable-512.png'
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(SHELL_CACHE).then((cache) => {
      console.log('[DilSe SW] Pre-caching app shell assets');
      return cache.addAll(PRECACHE_ASSETS).catch((err) => {
        console.warn('[DilSe SW] Pre-cache partial fail (will fetch dynamically):', err);
      });
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

  // 2. Navigation requests: Network-first, fallback to cached index.html
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req).catch(async () => {
        const cache = await caches.open(SHELL_CACHE);
        const cachedIndex = await cache.match('index.html') || await cache.match('./');
        if (cachedIndex) {
          return cachedIndex;
        }
        return new Response('DilSe is offline. Open from Home Screen to play downloaded music.', {
          status: 503,
          headers: { 'Content-Type': 'text/plain' }
        });
      })
    );
    return;
  }

  // 3. Static assets (JS, WASM, CSS, Images, Fonts) -> Stale-while-revalidate / Cache-First
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
        const fetchPromise = fetch(req).then((networkResp) => {
          if (networkResp && networkResp.status === 200) {
            const respClone = networkResp.clone();
            caches.open(SHELL_CACHE).then((cache) => cache.put(req, respClone));
          }
          return networkResp;
        }).catch(() => null);

        return cachedResp || fetchPromise;
      })
    );
    return;
  }

  // Default passthrough for other requests
  event.respondWith(fetch(req));
});
