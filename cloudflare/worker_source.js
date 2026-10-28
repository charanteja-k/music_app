import CryptoJS from 'crypto-js';

/**
 * DilSe Cloudflare Edge Audio Stream Worker
 * 
 * High-performance edge engine powering DilSe Web/PWA.
 * 
 * Endpoints:
 * 1. /jio/search?q=...&limit=20:
 *    - Searches JioSaavn official catalog.
 *    - Decrypts 320kbps AAC direct audio URLs on the edge.
 *    - Returns high-res 500x500 album artwork and duration.
 *    - Enables instantaneous, error-free playback with native iOS locked screen background play!
 * 2. /jio/suggestions?q=...:
 *    - Live query suggestions for instant autocomplete.
 * 3. /jio?title=...&artist=...:
 *    - Single track resolver with confidence scoring (backwards compatibility).
 * 4. Full CORS & HTTP 206 Partial Content byte ranges.
 */

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, HEAD, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Range, Content-Type, Accept, Authorization, X-User-Id',
  'Access-Control-Expose-Headers': 'Content-Length, Content-Range, Accept-Ranges',
};

const JIO_CIPHER_KEY = '38346591';

const JIO_GEO_HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
  'Cookie':
    'geo=106.51.1.1%2CIN%2CTelangana%2CHyderabad%2C500001; DL=english; L=english; country=IN; CH=G03%2CA07%2CO00%2CL03',
  'X-Forwarded-For': '106.51.1.1',
  'Client-IP': '106.51.1.1',
  'Accept': 'application/json',
};

export default {
  async fetch(request, env, ctx) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(request.url);

    // Health check endpoint
    if (url.pathname === '/' || url.pathname === '/health') {
      return new Response(
        JSON.stringify({
          status: 'online',
          service: 'dilse-cloudflare-edge',
          engine: 'jiosaavn-native-catalog-320k',
          userStoreAvailable: !!env.DILSE_USER_STORE,
        }),
        { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
      );
    }

    // User Library Sync: GET /user/sync?userId=... & POST /user/sync
    if (url.pathname === '/user/sync') {
      if (request.method === 'GET') {
        const userId = url.searchParams.get('userId');
        if (!userId || userId.trim().length < 3) {
          return new Response(
            JSON.stringify({ status: 'error', message: 'Missing or invalid userId' }),
            { status: 400, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
          );
        }

        if (!env.DILSE_USER_STORE) {
          return new Response(
            JSON.stringify({
              status: 'not_configured',
              message: 'KV namespace DILSE_USER_STORE is not bound on Cloudflare Worker',
              data: null,
            }),
            { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
          );
        }

        const safeKey = `user_lib_${userId.replace(/[^a-zA-Z0-9_-]/g, '_')}`;
        try {
          const raw = await env.DILSE_USER_STORE.get(safeKey);
          if (!raw) {
            return new Response(
              JSON.stringify({ status: 'ok', data: null }),
              { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
            );
          }
          const parsed = JSON.parse(raw);
          return new Response(
            JSON.stringify({ status: 'ok', data: parsed }),
            { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
          );
        } catch (err) {
          return new Response(
            JSON.stringify({ status: 'error', message: err.message || 'KV read error' }),
            { status: 500, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
          );
        }
      }

      if (request.method === 'POST') {
        try {
          const body = await request.json();
          const userId = body.userId;
          if (!userId || userId.trim().length < 3) {
            return new Response(
              JSON.stringify({ status: 'error', message: 'Missing or invalid userId in body' }),
              { status: 400, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
            );
          }

          if (!env.DILSE_USER_STORE) {
            return new Response(
              JSON.stringify({
                status: 'not_configured',
                message: 'KV namespace DILSE_USER_STORE is not bound on Cloudflare Worker',
              }),
              { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
            );
          }

          const safeKey = `user_lib_${userId.replace(/[^a-zA-Z0-9_-]/g, '_')}`;
          const payload = {
            userId: userId,
            email: body.email || '',
            playlists: Array.isArray(body.playlists) ? body.playlists : [],
            likedSongs: Array.isArray(body.likedSongs) ? body.likedSongs : [],
            updatedAt: Date.now(),
          };

          await env.DILSE_USER_STORE.put(safeKey, JSON.stringify(payload));
          return new Response(
            JSON.stringify({ status: 'ok', success: true, updatedAt: payload.updatedAt }),
            { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
          );
        } catch (err) {
          return new Response(
            JSON.stringify({ status: 'error', message: err.message || 'KV write error' }),
            { status: 500, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
          );
        }
      }
    }

    // 1. Native JioSaavn Catalog Search: /jio/search?q=...&limit=20
    if (url.pathname === '/jio/search') {
      const query = url.searchParams.get('q') || '';
      const limit = Math.min(50, Math.max(1, parseInt(url.searchParams.get('limit') || '20')));
      const page = Math.max(1, parseInt(url.searchParams.get('page') || '1'));

      if (!query || query.trim().length < 1) {
        return new Response(
          JSON.stringify([]),
          { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
        );
      }

      try {
        const results = await searchJioSaavn(query.trim(), limit, page);
        return new Response(
          JSON.stringify(results),
          {
            headers: {
              'Content-Type': 'application/json',
              'Cache-Control': 'public, max-age=3600',
              ...CORS_HEADERS,
            },
          }
        );
      } catch (err) {
        return new Response(
          JSON.stringify({ status: 'error', message: err.message || 'Search error' }),
          { status: 500, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
        );
      }
    }

    // 1b. Recommendations: /jio/recommendations?q=...&language=...&limit=20
    if (url.pathname === '/jio/recommendations') {
      const query = url.searchParams.get('q') || '';
      const language = url.searchParams.get('language') || 'telugu';
      const limit = Math.min(50, Math.max(1, parseInt(url.searchParams.get('limit') || '20')));

      try {
        const searchQuery = query.trim() ? `${query.trim()} songs` : `${language} trending songs`;
        const results = await searchJioSaavn(searchQuery, limit);
        return new Response(
          JSON.stringify(results),
          {
            headers: {
              'Content-Type': 'application/json',
              'Cache-Control': 'public, max-age=3600',
              ...CORS_HEADERS,
            },
          }
        );
      } catch (err) {
        return new Response(
          JSON.stringify([]),
          { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
        );
      }
    }

    // 2. Autocomplete Suggestions: /jio/suggestions?q=...&limit=8
    if (url.pathname === '/jio/suggestions') {
      const query = url.searchParams.get('q') || '';
      const limit = Math.min(15, Math.max(1, parseInt(url.searchParams.get('limit') || '8')));

      if (!query || query.trim().length < 1) {
        return new Response(
          JSON.stringify([]),
          { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
        );
      }

      try {
        const suggestions = await getJioSuggestions(query.trim(), limit);
        return new Response(
          JSON.stringify(suggestions),
          {
            headers: {
              'Content-Type': 'application/json',
              'Cache-Control': 'public, max-age=7200',
              ...CORS_HEADERS,
            },
          }
        );
      } catch (err) {
        return new Response(
          JSON.stringify([]),
          { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
        );
      }
    }

    // 3. Single Track Resolver: /jio?title=...&artist=... (or /jio?q=...)
    if (url.pathname === '/jio') {
      const rawTitle = url.searchParams.get('title') || url.searchParams.get('q') || '';
      const rawArtist = url.searchParams.get('artist') || '';

      if (!rawTitle || rawTitle.trim().length < 2) {
        return new Response(
          JSON.stringify({ status: 'error', message: 'Missing title/query (?title=...)' }),
          { status: 400, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
        );
      }

      try {
        const result = await resolveSingleTrack(rawTitle.trim(), rawArtist.trim());
        if (result) {
          return new Response(
            JSON.stringify({ status: 'ok', match: true, data: result }),
            {
              headers: {
                'Content-Type': 'application/json',
                'Cache-Control': 'public, max-age=86400',
                ...CORS_HEADERS,
              },
            }
          );
        } else {
          return new Response(
            JSON.stringify({
              status: 'not_found',
              match: false,
              message: 'No confident match found on JioSaavn; falling back to YouTube',
            }),
            { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
          );
        }
      } catch (err) {
        return new Response(
          JSON.stringify({ status: 'error', message: err.message || 'JioSaavn resolution error' }),
          { status: 500, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
        );
      }
    }

    // 4. Fallback stream endpoint: /stream?v=VIDEO_ID
    if (url.pathname === '/stream') {
      const videoId = url.searchParams.get('v');
      if (!videoId) {
        return new Response('Missing video ID', { status: 400, headers: CORS_HEADERS });
      }
      return new Response(
        JSON.stringify({ status: 'fallback', videoId: videoId }),
        { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
      );
    }

    // 5. Lyrics resolver: /lyrics?title=...&artist=...
    // 5. Lyrics resolver: /lyrics?title=...&artist=...&lang=...&duration=...
    if (url.pathname === '/lyrics') {
      const rawTitle = url.searchParams.get('title') || url.searchParams.get('q') || '';
      const rawArtist = url.searchParams.get('artist') || '';
      const rawLang = url.searchParams.get('lang') || '';
      const rawDuration = parseInt(url.searchParams.get('duration') || '0', 10);
      const rawVideoId = url.searchParams.get('videoId') || url.searchParams.get('v') || '';

      if (!rawTitle || rawTitle.trim().length < 1) {
        return new Response(
          JSON.stringify({ status: 'error', message: 'Missing title (?title=...)' }),
          { status: 400, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
        );
      }

      try {
        const result = await fetchLyricsEdge(
          rawTitle.trim(),
          rawArtist.trim(),
          rawLang.trim(),
          rawDuration,
          rawVideoId.trim()
        );
        if (result && (result.syncedLyrics || result.plainLyrics)) {
          return new Response(
            JSON.stringify({ status: 'ok', match: true, data: result }),
            {
              headers: {
                'Content-Type': 'application/json',
                'Cache-Control': 'public, max-age=86400',
                ...CORS_HEADERS,
              },
            }
          );
        } else {
          return new Response(
            JSON.stringify({ status: 'not_found', match: false, message: 'No lyrics found' }),
            { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
          );
        }
      } catch (err) {
        return new Response(
          JSON.stringify({ status: 'error', message: err.message || 'Lyrics fetch error' }),
          { status: 500, headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } }
        );
      }
    }

    // 6. YouTube Music Radio Automix: /ytm/radio?v=...&limit=40 (and alias /radio?v=...)
    if (url.pathname === '/ytm/radio' || url.pathname === '/radio') {
      const videoId = url.searchParams.get('v') || '';
      const limit = Math.min(50, Math.max(1, parseInt(url.searchParams.get('limit') || '30')));
      const visitorData = url.searchParams.get('visitorData') || '';

      if (!videoId) {
        return new Response(JSON.stringify([]), {
          headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }

      try {
        const results = await fetchYtmRadio(videoId, limit, visitorData);
        return new Response(JSON.stringify(results), {
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'public, max-age=3600',
            ...CORS_HEADERS,
          },
        });
      } catch (err) {
        return new Response(JSON.stringify([]), {
          headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }
    }

    // 7. YouTube Music Studio Search: /ytm/search?q=...&limit=20
    if (url.pathname === '/ytm/search') {
      const query = url.searchParams.get('q') || '';
      const limit = Math.min(50, Math.max(1, parseInt(url.searchParams.get('limit') || '20')));

      if (!query || query.trim().length < 1) {
        return new Response(JSON.stringify([]), {
          headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }

      try {
        const results = await searchYtmSongs(query.trim(), limit);
        return new Response(JSON.stringify(results), {
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'public, max-age=3600',
            ...CORS_HEADERS,
          },
        });
      } catch (err) {
        return new Response(JSON.stringify([]), {
          headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }
    }

    // 8. JioSaavn Album Search: /jio/albums?q=...&limit=10
    if (url.pathname === '/jio/albums') {
      const query = url.searchParams.get('q') || '';
      const limit = Math.min(20, Math.max(1, parseInt(url.searchParams.get('limit') || '10')));

      if (!query || query.trim().length < 1) {
        return new Response(JSON.stringify([]), {
          headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }

      try {
        const results = await searchJioAlbums(query.trim(), limit);
        return new Response(JSON.stringify(results), {
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'public, max-age=7200',
            ...CORS_HEADERS,
          },
        });
      } catch (err) {
        return new Response(JSON.stringify([]), {
          headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }
    }

    // 9. JioSaavn Album Detail (all songs): /jio/album?id=...
    if (url.pathname === '/jio/album') {
      const albumId = url.searchParams.get('id') || '';

      if (!albumId) {
        return new Response(JSON.stringify({ error: 'Missing album id' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }

      try {
        const data = await fetchAlbumDetails(albumId);
        return new Response(JSON.stringify(data), {
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'public, max-age=3600',
            ...CORS_HEADERS,
          },
        });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), {
          status: 500,
          headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }
    }

    // 10. JioSaavn Native Trending Songs: /jio/trending?lang=hindi&limit=30
    if (url.pathname === '/jio/trending') {
      const lang = url.searchParams.get('lang') || 'hindi';
      const limit = Math.min(50, Math.max(1, parseInt(url.searchParams.get('limit') || '30')));

      try {
        const results = await getJioTrendingSongs(lang, limit);
        return new Response(JSON.stringify(results), {
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'public, max-age=1800',
            ...CORS_HEADERS,
          },
        });
      } catch (err) {
        return new Response(JSON.stringify([]), {
          headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }
    }

    // 11. JioSaavn Top Charts: /jio/charts?lang=hindi
    if (url.pathname === '/jio/charts') {
      const lang = url.searchParams.get('lang') || 'hindi';

      try {
        const results = await getJioTopCharts(lang);
        return new Response(JSON.stringify(results), {
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'public, max-age=3600',
            ...CORS_HEADERS,
          },
        });
      } catch (err) {
        return new Response(JSON.stringify([]), {
          headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }
    }

    // 12. JioSaavn Featured & Top Albums: /jio/featured_albums?lang=hindi&limit=20
    if (url.pathname === '/jio/featured_albums') {
      const lang = url.searchParams.get('lang') || 'hindi';
      const limit = Math.min(50, Math.max(1, parseInt(url.searchParams.get('limit') || '20')));

      try {
        const results = await getJioFeaturedAlbums(lang, limit);
        return new Response(JSON.stringify(results), {
          headers: {
            'Content-Type': 'application/json',
            'Cache-Control': 'public, max-age=3600',
            ...CORS_HEADERS,
          },
        });
      } catch (err) {
        return new Response(JSON.stringify([]), {
          headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
        });
      }
    }

    return new Response('Not Found', { status: 404, headers: CORS_HEADERS });
  },
};


/**
 * Helper to extract movie/film name from titles like:
 * 'Samayama (From "Hi Nanna")', 'Ammayi (From "ANIMAL") [Telugu]',
 * 'Devara Thandavam (From "Devara Part 1")'
 */
function extractMovieName(str) {
  if (!str) return null;
  const m = str.match(
    /(?:from\s+["']([^"']+)["']|from\s+([A-Za-z0-9\s]+?)(?:\)|\]|\s+trailer|\s+ost|\s*[-–—]|$))/i
  );
  if (m) {
    const raw = (m[1] || m[2] || '').trim();
    if (raw.length >= 2 && !/^(the|a|an|remix|lofi|official)$/i.test(raw)) {
      return raw;
    }
  }
  return null;
}

/**
 * Searches and synthesizes a complete movie soundtrack album for Indian cinema films.
 * Solves the single-song fragmentation issue where distributor labels publish songs as 1-track singles.
 */
async function fetchMovieSoundtrackTracks(movieName, fallbackArt = '') {
  const url =
    'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&cc=in&api_version=4&ctx=android&n=35&p=1&q=' +
    encodeURIComponent(movieName);

  const res = await fetch(url, {
    headers: {
      'User-Agent': 'SaavnAndroid/9.0.0',
      'Accept': 'application/json',
      ...JIO_GEO_HEADERS,
    },
  });

  if (!res.ok) return null;

  const data = await res.json();
  const results = data.results || [];

  const cleanMovie = movieName.toLowerCase().replace(/[^a-z0-9]/g, '');
  const seenTitles = new Set();
  const songs = [];
  let bestArtwork = fallbackArt ? fallbackArt.replace('http:', 'https:') : '';
  let primaryArtist = '';
  let movieYear = '';
  let movieLang = '';

  const JUNK_SONG_RE =
    /\b(slowed|reverb|speed\s*up|sped\s*up|nightcore|karaoke|originally\s+performed|in\s+the\s+style\s+of|tribute|parody|spoof)\b/i;

  for (const r of results) {
    if (!r || !r.id) continue;
    const mi = r.more_info || {};
    const rawTitle = (r.title || r.song || '')
      .replace(/&quot;/g, '"')
      .replace(/&#039;/g, "'")
      .replace(/&amp;/g, '&')
      .trim();

    if (JUNK_SONG_RE.test(rawTitle)) continue;

    const rawAlbum = (mi.album || r.album || '')
      .replace(/&quot;/g, '"')
      .replace(/&#039;/g, "'")
      .replace(/&amp;/g, '&')
      .trim();

    const cTitle = rawTitle.toLowerCase().replace(/[^a-z0-9]/g, '');
    const cAlbum = rawAlbum.toLowerCase().replace(/[^a-z0-9]/g, '');

    const isFromMovie =
      new RegExp('from.*?[\\s"\'(]' + cleanMovie, 'i').test(rawTitle) ||
      cAlbum === cleanMovie ||
      cAlbum.includes(cleanMovie);

    if (isFromMovie) {
      const baseTitle = rawTitle
        .replace(/\s*\(from.*?\)/i, '')
        .replace(/\s*\[from.*?\]/i, '')
        .trim();
      const normBase = baseTitle.toLowerCase().replace(/[^a-z0-9]/g, '');

      if (!seenTitles.has(normBase) && normBase.length > 0) {
        seenTitles.add(normBase);

        let thumb = (r.image || '').replace('150x150', '500x500');
        if (thumb.startsWith('http:')) thumb = thumb.replace('http:', 'https:');
        if (!bestArtwork && thumb && !thumb.includes('default_')) {
          bestArtwork = thumb;
        }

        const artist =
          (mi.artistMap?.primary_artists || []).map((a) => a.name).join(', ') ||
          r.subtitle ||
          'Various Artists';

        if (!primaryArtist && artist) primaryArtist = artist;
        if (!movieYear && (mi.year || r.year)) movieYear = mi.year || r.year;
        if (!movieLang && (mi.language || r.language)) movieLang = mi.language || r.language;

        const encMedia = mi.encrypted_media_url || r.encrypted_media_url || '';
        const streamUrl = decryptMediaUrl(encMedia);

        songs.push({
          id: String(r.id),
          title: baseTitle,
          author: artist,
          album: movieName,
          duration: parseInt(mi.duration || r.duration || '0', 10) || 0,
          thumbnail: thumb || bestArtwork,
          streamUrl: streamUrl,
          trackNumber: songs.length + 1,
          source: 'jiosaavn',
          bitrate: '320kbps',
        });
      }
    }
  }

  if (songs.length === 0) return null;

  return {
    id: 'movie_' + encodeURIComponent(movieName),
    title: `${movieName} (Soundtrack)`,
    artist: primaryArtist || 'Original Motion Picture Soundtrack',
    artwork: bestArtwork,
    year: String(movieYear || new Date().getFullYear()),
    language: (movieLang || 'telugu').toLowerCase(),
    songCount: songs.length,
    type: 'album',
    songs: songs,
  };
}

/**
 * Searches JioSaavn album catalog and returns album metadata.
 * Consolidates fragmented movie singles into unified movie soundtrack albums
 * and prioritizes multi-track full albums.
 * Used by /jio/albums endpoint.
 */
async function searchJioAlbums(query, limit = 12) {
  const url =
    'https://www.jiosaavn.com/api.php?__call=search.getAlbumResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&n=35&p=1&q=' +
    encodeURIComponent(query);

  const res = await fetch(url, {
    headers: {
      'User-Agent': 'SaavnAndroid/9.0.0',
      'Accept': 'application/json',
      ...JIO_GEO_HEADERS,
    },
  });

  if (!res.ok) return [];

  const data = await res.json();
  const results = data.results || [];

  const JUNK_ALBUM_RE =
    /\b(slowed|reverb|speed\s*up|sped\s*up|nightcore|karaoke|originally\s+performed|in\s+the\s+style\s+of|tribute\s+to|instrumental\s+cover|parody|spoof)\b/i;

  const fullAlbums = [];
  const singles = [];

  for (const r of results) {
    if (!r || !r.id) continue;
    const mi = r.more_info || {};
    const title = (r.title || '')
      .replace(/&quot;/g, '"')
      .replace(/&#039;/g, "'")
      .replace(/&amp;/g, '&')
      .trim();

    if (JUNK_ALBUM_RE.test(title)) continue;

    let artwork = (r.image || '').replace('150x150', '500x500');
    if (artwork.startsWith('http:')) artwork = artwork.replace('http:', 'https:');
    if (
      artwork.includes('default_') ||
      artwork.includes('album-default') ||
      !artwork.startsWith('http')
    ) {
      artwork = '';
    }

    const artistStr = (mi.music || r.subtitle || '')
      .replace(/&quot;/g, '"')
      .replace(/&#039;/g, "'")
      .replace(/&amp;/g, '&')
      .trim();
    const year = mi.year || r.year || '';
    const songCount = parseInt(mi.song_count || '0', 10) || 0;
    const language = (mi.language || r.language || '').toLowerCase();
    const isDialogue = /\b(dialogue|dialogues|bgm\s+only)\b/i.test(title);

    const albumObj = {
      id: String(r.id),
      title: title || 'Unknown Album',
      artist: artistStr || 'Various Artists',
      artwork: artwork,
      year: String(year),
      songCount: songCount,
      language: language,
      type: songCount > 1 ? 'album' : 'single',
      isDialogue: isDialogue,
    };

    if (songCount >= 2) {
      fullAlbums.push(albumObj);
    } else {
      singles.push(albumObj);
    }
  }

  // Group fragmented movie singles (e.g. Samayama, Odiyamma, Gaaju Bomma from Hi Nanna)
  const movieGroups = new Map();
  for (const s of singles) {
    const movie = extractMovieName(s.title);
    if (movie) {
      const key = movie.toLowerCase();
      if (!movieGroups.has(key)) {
        movieGroups.set(key, {
          movie,
          count: 0,
          bestArtwork: s.artwork,
          artist: s.artist,
          year: s.year,
          language: s.language,
        });
      }
      const g = movieGroups.get(key);
      g.count++;
      if (!g.bestArtwork && s.artwork) g.bestArtwork = s.artwork;
    }
  }

  // Create consolidated Movie Soundtrack Albums for grouped singles
  const syntheticMovieSoundtracks = [];
  for (const g of movieGroups.values()) {
    // Only synthesize if there isn't already a full album with this movie title
    const exists = fullAlbums.some(
      (fa) =>
        fa.title.toLowerCase().includes(g.movie.toLowerCase()) ||
        g.movie.toLowerCase().includes(fa.title.toLowerCase())
    );
    if (!exists) {
      syntheticMovieSoundtracks.push({
        id: 'movie_' + encodeURIComponent(g.movie),
        title: `${g.movie} (Original Soundtrack)`,
        artist: g.artist || 'Original Motion Picture Soundtrack',
        artwork: g.bestArtwork,
        year: g.year,
        songCount: Math.max(g.count, 5),
        language: g.language,
        type: 'album',
        isDialogue: false,
      });
    }
  }

  // Sort full albums: non-dialogue first, then highest song count
  fullAlbums.sort((a, b) => {
    if (a.isDialogue !== b.isDialogue) return a.isDialogue ? 1 : -1;
    return (b.songCount || 0) - (a.songCount || 0);
  });

  // Prioritize synthetic movie soundtracks + full albums
  const combined = [...syntheticMovieSoundtracks, ...fullAlbums];

  // Only append non-grouped singles if we have fewer results than requested limit
  if (combined.length < limit) {
    const remainingSingles = singles.filter((s) => !extractMovieName(s.title));
    combined.push(...remainingSingles);
  }

  return combined.slice(0, limit);
}

/**
 * Fetches all songs for a JioSaavn album by albumId.
 * Returns album metadata + decrypted 320k song list.
 * Includes movie soundtrack expansion, multi-key detection, and YouTube Music fallback.
 */
async function fetchAlbumDetails(albumId) {
  // 1. Synthetic movie soundtrack album
  if (albumId.startsWith('movie_')) {
    const movie = decodeURIComponent(albumId.replace('movie_', ''));
    const soundtrack = await fetchMovieSoundtrackTracks(movie);
    if (soundtrack) return soundtrack;
  }

  // 2. Standard JioSaavn album lookup
  const url =
    'https://www.jiosaavn.com/api.php?__call=content.getAlbumDetails&_format=json&_marker=0&api_version=4&ctx=web6dot0&albumid=' +
    encodeURIComponent(albumId);

  const res = await fetch(url, {
    headers: {
      'User-Agent': 'SaavnAndroid/9.0.0',
      'Accept': 'application/json',
      ...JIO_GEO_HEADERS,
    },
  });

  if (!res.ok) throw new Error(`JioSaavn album fetch failed: ${res.status}`);

  const data = await res.json();

  const albumTitle = (data.title || data.name || 'Unknown Album')
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&amp;/g, '&')
    .trim();

  let cleanArtwork = (data.image || '').replace('150x150', '500x500');
  if (cleanArtwork.startsWith('http:')) cleanArtwork = cleanArtwork.replace('http:', 'https:');
  if (
    cleanArtwork.includes('default_') ||
    cleanArtwork.includes('album-default') ||
    !cleanArtwork.startsWith('http')
  ) {
    cleanArtwork = '';
  }

  const artistStr = (data.primary_artists || data.music || data.subtitle || '')
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&amp;/g, '&')
    .trim();
  const year = data.year || (data.more_info || {}).year || '';
  const language = (
    data.language || (data.more_info || {}).language || ''
  ).toLowerCase();

  // Inspect data.list, data.songs, or modules for songs
  let rawSongs = [];
  if (Array.isArray(data.list) && data.list.length > 0) {
    rawSongs = data.list;
  } else if (Array.isArray(data.songs) && data.songs.length > 0) {
    rawSongs = data.songs;
  } else if (Array.isArray(data.modules?.songs?.data)) {
    rawSongs = data.modules.songs.data;
  }

  // 3. Movie Single Expansion: If album only has 1 song and is from a movie, enrich to full soundtrack!
  const movieFromTitle =
    extractMovieName(albumTitle) ||
    (rawSongs[0] ? extractMovieName(rawSongs[0].title || rawSongs[0].song || '') : null);

  if (rawSongs.length <= 1 && movieFromTitle) {
    try {
      const enrichedMovie = await fetchMovieSoundtrackTracks(movieFromTitle, cleanArtwork);
      if (enrichedMovie && enrichedMovie.songs.length > rawSongs.length) {
        return enrichedMovie;
      }
    } catch (_) {}
  }

  // 4. Fallback: If album details API returned 0 songs, search catalog with fuzzy matching
  if (rawSongs.length === 0 && albumTitle && albumTitle !== 'Unknown Album') {
    try {
      const cleanSearchTitle = albumTitle
        .replace(/\s*\(.*?\)/g, '')
        .replace(/\s*\[.*?\]/g, '')
        .replace(/[-–—]\s*(Original Soundtrack|OST|Telugu|Tamil|Hindi|Kannada|Malayalam).*/i, '')
        .trim();

      const fallbackTracks = await searchJioSaavn(cleanSearchTitle || albumTitle, 30);
      const cleanLower = (cleanSearchTitle || albumTitle).toLowerCase();

      const matching = fallbackTracks.filter(
        (t) =>
          (t.album && t.album.toLowerCase().includes(cleanLower)) ||
          t.title.toLowerCase().includes(cleanLower) ||
          cleanLower.includes(t.album.toLowerCase())
      );

      if (matching.length > 0) {
        return {
          id: String(albumId),
          title: albumTitle,
          artist: artistStr || matching[0].author || 'Various Artists',
          artwork: cleanArtwork || matching[0].thumbnail || '',
          year: String(year),
          language: language,
          songCount: matching.length,
          type: 'album',
          songs: matching.map((m, idx) => ({
            id: String(m.id),
            title: m.title,
            author: m.author,
            album: albumTitle,
            duration: m.duration,
            thumbnail: m.thumbnail || cleanArtwork,
            streamUrl: m.streamUrl,
            trackNumber: idx + 1,
            source: 'jiosaavn',
            bitrate: '320kbps',
          })),
        };
      }

      // If JioSaavn search yielded nothing, fall back to YouTube Music tracks
      const ytmFallback = await searchYtmSongs(albumTitle);
      if (ytmFallback && ytmFallback.length > 0) {
        return {
          id: String(albumId),
          title: albumTitle,
          artist: artistStr || ytmFallback[0].author || 'Various Artists',
          artwork: cleanArtwork || ytmFallback[0].thumbnail || '',
          year: String(year),
          language: language,
          songCount: ytmFallback.length,
          type: 'album',
          songs: ytmFallback.map((y, idx) => ({
            id: String(y.id),
            title: y.title,
            author: y.author,
            album: albumTitle,
            duration: y.duration,
            thumbnail: y.thumbnail || cleanArtwork,
            streamUrl: y.streamUrl || '',
            trackNumber: idx + 1,
            source: 'youtube',
            bitrate: '160kbps',
          })),
        };
      }
    } catch (_) {}
  }

  const songs = rawSongs
    .filter((s) => s && s.id)
    .map((s) => {
      const mi = s.more_info || {};
      const encMedia = mi.encrypted_media_url || s.encrypted_media_url || '';
      const streamUrl = decryptMediaUrl(encMedia);
      let thumb = (s.image || '').replace('150x150', '500x500');
      if (thumb.startsWith('http:')) thumb = thumb.replace('http:', 'https:');
      if (
        thumb.includes('default_') ||
        thumb.includes('album-default') ||
        !thumb.startsWith('http')
      ) {
        thumb = cleanArtwork;
      }

      const title = (s.title || s.song || '')
        .replace(/&quot;/g, '"')
        .replace(/&#039;/g, "'")
        .replace(/&amp;/g, '&');
      const primaryArtists = (mi.artistMap?.primary_artists || [])
        .map((a) => a.name)
        .join(', ');
      const artist = (
        primaryArtists ||
        s.subtitle ||
        s.primary_artists ||
        mi.music ||
        ''
      )
        .replace(/&quot;/g, '"')
        .replace(/&#039;/g, "'")
        .replace(/&amp;/g, '&');
      const duration = parseInt(mi.duration || s.duration || '0', 10) || 0;
      const trackNum = parseInt(mi.track_number || s.track_number || '0', 10) || 0;

      return {
        id: String(s.id),
        title: title || 'Unknown Title',
        author: artist || artistStr || 'Various Artists',
        album: albumTitle,
        duration: duration,
        thumbnail: thumb || cleanArtwork,
        streamUrl: streamUrl,
        trackNumber: trackNum,
        source: 'jiosaavn',
        bitrate: '320kbps',
      };
    })
    .sort((a, b) => (a.trackNumber || 999) - (b.trackNumber || 999));

  // If album artwork is missing, fallback to the first song's thumbnail
  if (!cleanArtwork && songs.length > 0 && songs[0].thumbnail) {
    cleanArtwork = songs[0].thumbnail;
  }

  return {
    id: String(albumId),
    title: albumTitle,
    artist: artistStr || 'Various Artists',
    artwork: cleanArtwork,
    year: String(year),
    language: language,
    songCount: songs.length,
    type: songs.length > 1 ? 'album' : 'single',
    songs: songs,
  };
}

const UNICODE_SCRIPTS = {
  telugu: [0x0C00, 0x0C7F],
  tamil: [0x0B80, 0x0BFF],
  hindi: [0x0900, 0x097F],
  kannada: [0x0C80, 0x0CFF],
  malayalam: [0x0D00, 0x0D7F],
  punjabi: [0x0A00, 0x0A7F],
  bengali: [0x0980, 0x09FF],
  gujarati: [0x0A80, 0x0AFF],
};

const ALL_LANGUAGES = ['telugu', 'tamil', 'hindi', 'kannada', 'malayalam', 'punjabi', 'bengali', 'gujarati', 'marathi', 'english'];

function detectLyricsScript(text) {
  if (!text) return null;
  const clean = text.replace(/\[\d+:\d+\.?\d*\]/g, '');
  const counts = {};
  for (const lang of Object.keys(UNICODE_SCRIPTS)) counts[lang] = 0;
  for (let i = 0; i < clean.length; i++) {
    const cp = clean.charCodeAt(i);
    for (const [lang, [start, end]] of Object.entries(UNICODE_SCRIPTS)) {
      if (cp >= start && cp <= end) {
        counts[lang]++;
      }
    }
  }
  let best = null;
  let maxCount = 0;
  for (const [lang, count] of Object.entries(counts)) {
    if (count > maxCount) {
      maxCount = count;
      best = lang;
    }
  }
  return maxCount >= 8 ? best : null;
}

function detectMetaLanguage(text) {
  if (!text) return null;
  const lower = text.toLowerCase();
  for (const l of ALL_LANGUAGES) {
    const reg = new RegExp(`\\b${l}\\b`, 'i');
    if (reg.test(lower)) return l;
  }
  return null;
}

function scoreLyricsCandidate(cand, targetTitle, targetArtist, targetLang, targetDuration) {
  const lyrics = (cand.syncedLyrics || cand.plainLyrics || '').trim();
  if (!lyrics) return -9999;

  const script = detectLyricsScript(lyrics);
  const album = (cand.albumName || '').toLowerCase();
  const track = (cand.trackName || '').toLowerCase();
  const metaLang = detectMetaLanguage(`${album} ${track}`);

  let score = 0;

  // 1. Script checks (Strict non-Latin script matching)
  if (targetLang) {
    if (script) {
      if (script !== targetLang) {
        // Severe script contradiction (e.g. Malayalam or Tamil lyrics for Telugu song)
        return -9999;
      } else {
        score += 500;
      }
    } else if (targetLang === 'english' && script !== null) {
      return -9999;
    }
  }

  // 2. Metadata language tag conflict in album/track title
  if (targetLang && metaLang) {
    if (metaLang !== targetLang) {
      // e.g. candidate says [Hindi] or (Tamil) when target is Telugu
      return -9999;
    } else {
      score += 300;
    }
  }

  // 3. Title match
  const cTitle = (cand.trackName || '').replace(/[\(\[\{].*?[\)\]\}]/g, '').toLowerCase().trim();
  const tTitle = targetTitle.replace(/[\(\[\{].*?[\)\]\}]/g, '').toLowerCase().trim();
  if (cTitle === tTitle) {
    score += 250;
  } else if (cTitle.includes(tTitle) || tTitle.includes(cTitle)) {
    score += 150;
  } else {
    score -= 100;
  }

  // 4. Artist match
  if (targetArtist && cand.artistName) {
    const tTokens = targetArtist.toLowerCase().split(/[\s,;&]+/).filter((w) => w.length > 2);
    const cTokens = cand.artistName.toLowerCase().split(/[\s,;&]+/).filter((w) => w.length > 2);
    const hasOverlap = tTokens.some((t) => cTokens.includes(t));
    if (hasOverlap) {
      score += 150;
    } else if (tTokens.length > 0) {
      score -= 150;
    }
  }

  // 5. Duration match
  const cDur = cand.duration || 0;
  if (targetDuration > 0 && cDur > 0) {
    const diff = Math.abs(cDur - targetDuration);
    if (diff <= 5) {
      score += 100;
    } else if (diff <= 12) {
      score += 50;
    } else if (diff > 35) {
      score -= 200;
    }
  }

  // 6. Synced lyrics preference (large bonus to prioritize synced LRC over plain text)
  if (cand.syncedLyrics && cand.syncedLyrics.trim().length > 0) {
    score += 350;
  }

  return score;
}

/**
 * 3-Stage Lyric Pipeline:
 * Stage 1: JioSaavn Official Lyrics (Direct Indic catalog lyrics with highest accuracy)
 * Stage 2: YouTube Music InnerTube Lyrics (Massive global catalog coverage)
 * Stage 3: LRCLIB (Global crowdsourced synchronized LRC lyrics)
 */
async function fetchLyricsEdge(title, artist, lang, duration, videoId) {
  const cleanTitle = title
    .replace(/[\(\[\{].*?[\)\]\}]/g, '')
    .replace(/official video|music video|full song|lyric video|audio song|video song|lyrics/gi, '')
    .trim();
  const cleanArtist = artist.replace(/[\(\[\{].*?[\)\]\}]/g, '').trim();

  // STAGE 1: JioSaavn Official Lyrics
  try {
    const jioResult = await fetchJioLyrics(cleanTitle, cleanArtist);
    if (jioResult && (jioResult.plainLyrics || jioResult.syncedLyrics)) {
      return jioResult;
    }
  } catch (err) {
    console.error('JioLyrics error:', err);
  }

  // STAGE 2: YouTube Music InnerTube Lyrics
  try {
    let targetVid = videoId;
    if (!targetVid) {
      const ytmMatches = await searchYtmSongs(`${cleanTitle} ${cleanArtist}`.trim(), 2);
      if (ytmMatches && ytmMatches.length > 0 && ytmMatches[0].id) {
        targetVid = ytmMatches[0].id;
      }
    }
    if (targetVid) {
      const ytmResult = await fetchYtmLyrics(targetVid, cleanTitle, cleanArtist);
      if (ytmResult && (ytmResult.plainLyrics || ytmResult.syncedLyrics)) {
        return ytmResult;
      }
    }
  } catch (err) {
    console.error('YtmLyrics error:', err);
  }

  // STAGE 3: LRCLIB (Crowdsourced Synced & Plain)
  try {
    const lrcResult = await fetchLrcLibLyrics(cleanTitle, cleanArtist, lang, duration);
    if (lrcResult && (lrcResult.syncedLyrics || lrcResult.plainLyrics)) {
      return lrcResult;
    }
  } catch (err) {
    console.error('LrcLib error:', err);
  }

  return null;
}

/**
 * Stage 1: JioSaavn Official Lyrics Resolver
 */
async function fetchJioLyrics(cleanTitle, cleanArtist) {
  const query = `${cleanTitle} ${cleanArtist}`.trim();
  const searchUrl =
    'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&cc=in&api_version=4&ctx=android&n=5&p=1&q=' +
    encodeURIComponent(query);

  const res = await fetch(searchUrl, {
    headers: {
      'User-Agent': 'SaavnAndroid/9.0.0',
      'Accept': 'application/json',
      ...JIO_GEO_HEADERS,
    },
  });

  if (!res.ok) return null;
  const data = await res.json();
  const results = data.results || [];

  for (const r of results) {
    if (!r || !r.id) continue;
    const lUrl =
      `https://www.jiosaavn.com/api.php?__call=lyrics.getLyrics&lyrics_id=${r.id}&ctx=web6dot0&api_version=4&_format=json`;
    try {
      const lRes = await fetch(lUrl, {
        headers: {
          'User-Agent': 'SaavnAndroid/9.0.0',
          'Accept': 'application/json',
          ...JIO_GEO_HEADERS,
        },
      });
      if (lRes.ok) {
        const lData = await lRes.json();
        const rawLyrics = lData.lyrics;
        if (rawLyrics && typeof rawLyrics === 'string' && rawLyrics.trim().length > 10) {
          const clean = rawLyrics
            .replace(/<br\s*[\/]?>/gi, '\n')
            .replace(/&quot;/g, '"')
            .replace(/&#039;/g, "'")
            .replace(/&amp;/g, '&')
            .replace(/<[^>]+>/g, '')
            .trim();

          const songTitle = (r.title || r.song || cleanTitle)
            .replace(/&quot;/g, '"')
            .replace(/&#039;/g, "'")
            .replace(/&amp;/g, '&')
            .trim();

          const songArtist =
            (r.more_info?.artistMap?.primary_artists || []).map((a) => a.name).join(', ') ||
            r.subtitle ||
            cleanArtist;

          return {
            id: 'jio_' + r.id,
            trackName: songTitle,
            artistName: songArtist,
            albumName: r.more_info?.album || r.album || '',
            plainLyrics: clean,
            syncedLyrics: null,
            source: 'jiosaavn_official',
          };
        }
      }
    } catch (_) {}
  }

  return null;
}

/**
 * Stage 2: YouTube Music InnerTube Lyrics Resolver
 */
async function fetchYtmLyrics(videoId, cleanTitle, cleanArtist) {
  if (!videoId) return null;

  const nextUrl = 'https://www.youtube.com/youtubei/v1/next';
  const nextBody = {
    videoId: videoId,
    context: YTM_CONTEXT,
  };

  const nextRes = await fetch(nextUrl, {
    method: 'POST',
    headers: YTM_HEADERS,
    body: JSON.stringify(nextBody),
  });

  if (!nextRes.ok) return null;
  const nextData = await nextRes.json();

  const tabs =
    nextData.contents?.singleColumnMusicWatchNextResultsRenderer?.tabbedRenderer
      ?.watchNextTabbedResultsRenderer?.tabs || [];

  let lyricsBrowseId = null;
  for (const t of tabs) {
    const tab = t.tabRenderer;
    if (tab && (tab.title || '').toLowerCase().includes('lyric')) {
      lyricsBrowseId = tab.endpoint?.browseEndpoint?.browseId;
      break;
    }
  }

  if (!lyricsBrowseId) return null;

  const browseUrl = 'https://www.youtube.com/youtubei/v1/browse';
  const browseBody = {
    browseId: lyricsBrowseId,
    context: YTM_CONTEXT,
  };

  const browseRes = await fetch(browseUrl, {
    method: 'POST',
    headers: YTM_HEADERS,
    body: JSON.stringify(browseBody),
  });

  if (!browseRes.ok) return null;
  const browseData = await browseRes.json();

  const section =
    browseData.contents?.sectionListRenderer?.contents?.[0]
      ?.musicDescriptionShelfRenderer;
  const runs = section?.description?.runs || [];
  const text = runs.map((r) => r.text || '').join('').trim();

  if (text && text.length > 10) {
    return {
      id: 'ytm_' + videoId,
      trackName: cleanTitle,
      artistName: cleanArtist,
      plainLyrics: text,
      syncedLyrics: null,
      source: 'youtube_music_official',
    };
  }

  return null;
}

/**
 * Stage 3: LRCLIB Synced and Plain Lyrics Resolver
 */
async function fetchLrcLibLyrics(cleanTitle, cleanArtist, lang, duration) {
  // If lang not explicitly provided, attempt detection from title or artist
  let targetLang = (lang || '').toLowerCase().trim();
  if (!targetLang) {
    targetLang = detectLyricsScript(cleanTitle) || detectMetaLanguage(`${cleanTitle} ${cleanArtist}`) || '';
  }

  const searchHeaders = {
    'User-Agent': 'DilSeMusicApp/1.0 (https://dilse.app; contact@dilse.app)',
    'Accept': 'application/json',
  };

  const queries = [];
  if (cleanTitle && targetLang) {
    queries.push(`https://lrclib.net/api/search?q=${encodeURIComponent(`${cleanTitle} ${targetLang}`)}`);
  }
  if (cleanTitle && cleanArtist) {
    queries.push(`https://lrclib.net/api/search?track_name=${encodeURIComponent(cleanTitle)}&artist_name=${encodeURIComponent(cleanArtist)}`);
    queries.push(`https://lrclib.net/api/search?q=${encodeURIComponent(`${cleanTitle} ${cleanArtist}`)}`);
  }
  if (cleanTitle) {
    queries.push(`https://lrclib.net/api/search?track_name=${encodeURIComponent(cleanTitle)}`);
    queries.push(`https://lrclib.net/api/search?q=${encodeURIComponent(cleanTitle)}`);
  }

  // Exact match endpoint
  if (cleanTitle && cleanArtist && duration > 0) {
    try {
      const getUrl = `https://lrclib.net/api/get?track_name=${encodeURIComponent(cleanTitle)}&artist_name=${encodeURIComponent(cleanArtist)}&duration=${Math.round(duration)}`;
      const res = await fetch(getUrl, { headers: searchHeaders });
      if (res.ok) {
        const item = await res.json();
        if (item && (item.syncedLyrics || item.plainLyrics)) {
          const s = scoreLyricsCandidate(item, cleanTitle, cleanArtist, targetLang, duration);
          if (s >= 100) return item;
        }
      }
    } catch (_) {}
  }

  const seenIds = new Set();
  let bestCandidate = null;
  let bestScore = 99;

  for (const url of queries) {
    try {
      const res = await fetch(url, { headers: searchHeaders });
      if (res.ok) {
        const list = await res.json();
        if (Array.isArray(list)) {
          for (const item of list) {
            if (!item || seenIds.has(item.id)) continue;
            seenIds.add(item.id);
            const score = scoreLyricsCandidate(item, cleanTitle, cleanArtist, targetLang, duration);
            if (score > bestScore) {
              bestScore = score;
              bestCandidate = item;
            }
          }
          if (bestCandidate && bestScore >= 400) {
            return bestCandidate;
          }
        }
      }
    } catch (_) {}
  }

  return bestCandidate;
}

/**
 * Decrypts JioSaavn encrypted_media_url into 320kbps direct CDN MP4 stream URL.
 */
function decryptMediaUrl(encryptedUrl) {
  if (!encryptedUrl) return '';
  try {
    const key = CryptoJS.enc.Utf8.parse(JIO_CIPHER_KEY);
    const decrypted = CryptoJS.DES.decrypt(
      { ciphertext: CryptoJS.enc.Base64.parse(encryptedUrl) },
      key,
      { mode: CryptoJS.mode.ECB, padding: CryptoJS.pad.Pkcs7 }
    );
    const rawUrl = decrypted.toString(CryptoJS.enc.Utf8);
    if (!rawUrl || !rawUrl.startsWith('http')) return '';
    return rawUrl.replace('_96.mp4', '_320.mp4').replace('_160.mp4', '_320.mp4');
  } catch (_) {
    return '';
  }
}

/**
 * Searches JioSaavn official catalog and returns direct 320k stream URLs and metadata.
 */
async function searchJioSaavn(query, limit = 20, page = 1) {
  const url =
    'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&cc=in&api_version=4&ctx=android&n=' +
    limit +
    '&p=' +
    page +
    '&q=' +
    encodeURIComponent(query);

  const res = await fetch(url, {
    headers: {
      'User-Agent': 'SaavnAndroid/9.0.0',
      'Accept': 'application/json',
      ...JIO_GEO_HEADERS,
    },
  });

  if (!res.ok) return [];

  const data = await res.json();
  const results = data.results || [];

  const formatted = results.map((r) => {
    const mi = r.more_info || {};
    const encMedia = mi.encrypted_media_url || r.encrypted_media_url || '';
    const streamUrl = decryptMediaUrl(encMedia);
    const artwork = (r.image || '').replace('150x150', '500x500');
    const title = (r.title || r.song || '')
      .replace(/&quot;/g, '"')
      .replace(/&#039;/g, "'")
      .replace(/&amp;/g, '&');
    const primaryArtists = (mi.artistMap?.primary_artists || []).map((a) => a.name).join(', ');
    const artist = (primaryArtists || r.subtitle || r.primary_artists || mi.music || r.singers || '')
      .replace(/&quot;/g, '"')
      .replace(/&#039;/g, "'")
      .replace(/&amp;/g, '&');
    const album = (mi.album || r.album || '')
      .replace(/&quot;/g, '"')
      .replace(/&#039;/g, "'")
      .replace(/&amp;/g, '&');
    const duration = parseInt(mi.duration || r.duration || '0') || 0;

    return {
      id: r.id,
      title: title || 'Unknown Title',
      author: artist || 'DilSe Music',
      album: album,
      duration: duration,
      thumbnail: artwork,
      streamUrl: streamUrl,
      source: 'jiosaavn',
      bitrate: '320kbps',
    };
  });

  const COMPILATION_REGEX = /\b(?:best of|top hits|greatest hits|party mix|mashup|compilation|collection|all time hits|vol\b|volume\b|anniversary|super hits|jukebox|blockbuster)\b/i;
  formatted.sort((a, b) => {
    const isAComp = COMPILATION_REGEX.test(a.album || '') ? 1 : 0;
    const isBComp = COMPILATION_REGEX.test(b.album || '') ? 1 : 0;
    return isAComp - isBComp;
  });

  return formatted;
}

/**
 * Fetches autocomplete search suggestions from JioSaavn.
 */
async function getJioSuggestions(query, limit = 8) {
  const url =
    'https://www.jiosaavn.com/api.php?__call=autocomplete.get&query=' +
    encodeURIComponent(query) +
    '&_format=json&_marker=0&ctx=web6dot0';

  const res = await fetch(url, {
    headers: JIO_GEO_HEADERS,
  });

  if (!res.ok) return [];

  const data = await res.json();
  const suggestions = [];

  if (data.topquery?.data) {
    for (const item of data.topquery.data) {
      if (item.title && !suggestions.includes(item.title)) {
        suggestions.push(item.title.replace(/&quot;/g, '"').replace(/&#039;/g, "'"));
      }
    }
  }

  if (data.songs?.data) {
    for (const item of data.songs.data) {
      if (item.title && !suggestions.includes(item.title)) {
        suggestions.push(item.title.replace(/&quot;/g, '"').replace(/&#039;/g, "'"));
      }
    }
  }

  return suggestions.slice(0, limit);
}

/**
 * Single track fuzzy resolver for backwards compatibility.
 */
async function resolveSingleTrack(rawTitle, rawArtist) {
  const songs = await searchJioSaavn(rawTitle + (rawArtist ? ' ' + rawArtist : ''), 5);
  for (const s of songs) {
    if (!s.streamUrl) continue;
    if (rawArtist) {
      const artWords = rawArtist.toLowerCase().split(/\s+/).filter((w) => w.length >= 3);
      if (artWords.length > 0 && !artWords.some((w) => s.author.toLowerCase().includes(w))) {
        continue;
      }
    }
    return {
      title: s.title,
      artist: s.author,
      album: s.album,
      artwork: s.thumbnail,
      streamUrl: s.streamUrl,
      bitrate: '320kbps',
    };
  }
  return null;
}

/**
 * YouTube Music InnerTube Edge Bridge
 */
const YTM_HEADERS = {
  'Content-Type': 'application/json',
  'User-Agent':
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
  'Origin': 'https://music.youtube.com',
  'Referer': 'https://music.youtube.com/',
};

const YTM_CONTEXT = {
  client: {
    clientName: 'WEB_REMIX',
    clientVersion: '1.20240101.01.00',
    hl: 'en',
    gl: 'IN',
  },
};

// ── Non-music noise patterns (mirrors canonical_song_dedup.dart) ──────────────
const NON_MUSIC_TITLE_RE = /\b(speech|press\s+meet|launch\s+event|interview|talk\s+show|podcast|reaction|reacting|dance\s+cover|dance\s+video|stage\s+performance|performance\s+video|full\s+movie|movie\s+scene|comedy\s+scene|ringtone|bgm\s+only|#?shorts|reels?|tiktok|troll|parody|spoof|jukebox|all\s+songs|audio\s+jukebox|mega\s+jukebox|full\s+album|slowed[\s+]*(?:and|\+)?[\s+]*reverb|speed\s*up|sped\s*up|nightcore|8d\s+audio|bass\s+boosted|acoustic\s+cover|guitar\s+cover|piano\s+cover|violin\s+cover|cover\s+song|cover\s+version|cover\s+classics|female\s+cover|male\s+cover|karaoke|originally\s+performed|in\s+the\s+style\s+of|tribute\s+to|tribute\s+version|instrumental|tabata|power\s+music|workout|fitness\s+beats|gym\s+(?:music|mix|workout)|carnatic\s+mix|lo-?fi\s+mix|varmala|vidhi|ceremony|wedding\s+music|shaadi|mehendi|sangeet|dj\s+mix|dj\s+remix|mashup|mash\s+up|club\s+mix|oye\s+lalii|boostereo|shadow\s+tower|party\s+hits\s+band|the\s+hit\s+crew|the\s+covers|making\s+video|bloopers|teaser|trailer|glimpse|promo)\b/i;
const NON_MUSIC_AUTHOR_RE = /\b(media|news|tv|filmnagar|events|buzz|sports|daily|vlogs?|cricket|gaming|memes?|dj\s+\w+|remix\s+hub|wedding|ceremony|oye\s+lalii|cover\s+classics|the\s+covers|the\s+hit\s+crew|party\s+hits\s+band|tabata|power\s+music|fitness\s+beats|workout|luxebeats|zzang|sweet\s+strings|boostereo|shadow\s+tower)\b/i;

function isGenuineTrack(title, author, durationSec) {
  if (!title) return false;
  if (NON_MUSIC_TITLE_RE.test(title)) return false;
  if (NON_MUSIC_AUTHOR_RE.test(author || '')) return false;
  if (durationSec && (durationSec < 60 || durationSec > 600)) return false;
  return true;
}

function parseDurationSec(str) {
  if (!str || typeof str !== 'string') return 0;
  const parts = str.split(':').map((p) => parseInt(p, 10));
  if (parts.some((n) => isNaN(n))) return 0;
  if (parts.length === 2) {
    return parts[0] * 60 + parts[1];
  } else if (parts.length === 3) {
    return parts[0] * 3600 + parts[1] * 60 + parts[2];
  }
  return 0;
}

async function fetchYtmRadio(videoId, limit = 40, visitorData = '') {
  try {
    const headers = { ...YTM_HEADERS };
    if (visitorData) {
      headers['X-Goog-Visitor-Id'] = visitorData;
    }
    const context = JSON.parse(JSON.stringify(YTM_CONTEXT));
    if (visitorData) {
      context.client.visitorData = visitorData;
    }
    const resp = await fetch('https://music.youtube.com/youtubei/v1/next', {
      method: 'POST',
      headers: headers,
      body: JSON.stringify({
        context: context,
        videoId: videoId,
        playlistId: `RDAMVM${videoId}`,
      }),
    });

    if (!resp.ok) return [];

    const data = await resp.json();
    const tabs =
      data?.contents?.singleColumnMusicWatchNextResultsRenderer?.tabbedRenderer
        ?.watchNextTabbedResultsRenderer?.tabs || [];
    if (!tabs.length) return [];

    const items =
      tabs[0]?.tabRenderer?.content?.musicQueueRenderer?.content
        ?.playlistPanelRenderer?.contents || [];
    const results = [];

    for (const it of items) {
      const r = it?.playlistPanelVideoRenderer;
      if (!r) continue;
      const vid = r.videoId;
      if (!vid || vid === videoId) continue;

      const titleRuns = r.title?.runs || [];
      const title = titleRuns[0]?.text || 'Unknown Title';

      const bylineRuns = r.longBylineText?.runs || [];
      const author = bylineRuns[0]?.text || 'Unknown Artist';

      const lengthText = r.lengthText?.runs?.[0]?.text || '';
      const duration = parseDurationSec(lengthText) || 210;

      // Filter out non-music content (covers, karaoke, workout, remixes, etc.)
      if (!isGenuineTrack(title, author, duration)) continue;

      results.push({
        id: vid,
        title: title,
        author: author,
        duration: duration,
      });

      if (results.length >= limit) break;
    }

    return results;
  } catch (e) {
    return [];
  }
}

async function searchYtmSongs(query, limit = 20) {
  try {
    const resp = await fetch('https://music.youtube.com/youtubei/v1/search', {
      method: 'POST',
      headers: YTM_HEADERS,
      body: JSON.stringify({
        context: YTM_CONTEXT,
        query: query.trim(),
      }),
    });

    if (!resp.ok) return [];

    const data = await resp.json();
    const contents =
      data?.contents?.tabbedSearchResultsRenderer?.tabs?.[0]?.tabRenderer
        ?.content?.sectionListRenderer?.contents || [];
    const songs = [];

    // 1. Top Result Card (if it is an official studio Song)
    const card = contents[0]?.musicCardShelfRenderer;
    if (card) {
      const subtitle = (card.subtitle?.runs?.map((r) => r.text).join('') || '').toLowerCase();
      const vid = card.onTap?.watchEndpoint?.videoId;
      const title = card.title?.runs?.[0]?.text || '';
      const artistRun = card.subtitle?.runs?.find((r) =>
        r.navigationEndpoint?.browseEndpoint?.browseId?.startsWith('UC')
      );
      const author = artistRun?.text || 'Various Artists';
      if (
        vid &&
        title &&
        !subtitle.includes('video') &&
        !subtitle.includes('episode') &&
        !subtitle.includes('podcast')
      ) {
        if (isGenuineTrack(title, author, 210)) {
          songs.push({ id: vid, title, author, duration: 210 });
        }
      }
    }

    // 2. Scan sections for official studio songs only
    for (let i = 0; i < contents.length; i++) {
      const section = contents[i];
      const items =
        section?.itemSectionRenderer?.contents ||
        section?.musicShelfRenderer?.contents ||
        [];
      for (const item of items) {
        const renderer = item?.musicResponsiveListItemRenderer;
        if (!renderer) continue;

        const flexColumns = renderer.flexColumns || [];
        if (flexColumns.length < 2) continue;

        // Subruns check: MUST be tagged as 'Song' by YouTube Music
        const subRuns =
          flexColumns[1]?.musicResponsiveListItemFlexColumnRenderer?.text?.runs ||
          [];
        const itemType = (subRuns[0]?.text || '').toLowerCase();
        if (itemType !== 'song') continue;

        const titleRuns =
          flexColumns[0]?.musicResponsiveListItemFlexColumnRenderer?.text?.runs ||
          [];
        const title = titleRuns[0]?.text || 'Unknown Title';

        let videoId =
          renderer.overlay?.musicItemThumbnailOverlayRenderer?.content
            ?.musicPlayButtonRenderer?.playNavigationEndpoint?.watchEndpoint
            ?.videoId ||
          renderer.onTap?.watchEndpoint?.videoId ||
          titleRuns[0]?.navigationEndpoint?.watchEndpoint?.videoId;

        if (!videoId) continue;

        // Author & Duration
        const artistRun =
          subRuns.find(
            (r) =>
              r.navigationEndpoint?.browseEndpoint
                ?.browseEndpointContextSupportedConfigs
                ?.browseEndpointContextMusicConfig?.pageType ===
              'MUSIC_PAGE_TYPE_ARTIST'
          ) || subRuns[2];
        const author = artistRun?.text || 'Various Artists';

        let duration = 210;
        if (subRuns.length > 2) {
          const lastText = subRuns[subRuns.length - 1]?.text || '';
          const parsed = parseDurationSec(lastText);
          if (parsed) duration = parsed;
        }

        // Filter out non-music content (covers, karaoke, workout, remixes, etc.)
        if (!isGenuineTrack(title, author, duration)) continue;

        songs.push({
          id: videoId,
          title: title,
          author: author,
          duration: duration,
        });

        if (songs.length >= limit) break;
      }
      if (songs.length >= limit) break;
    }

    return songs;
  } catch (e) {
    return [];
  }
}

const SPAM_AND_JUNK_FILTER =
  /\b(trending(\s+version)?|1\s*min(\s*mix)?|reels?(\s*version)?|viral(\s*version)?|(speed|sped)(\s*up)?|slowed(\s*\+\s*reverb)?|classic.*soundtrack|vol(ume)?\.?\s*\d+|greatest\s+hits|best\s+of|party\s+mix|jukebox|compilation|golden\s+era|archive)\b/i;

function cleanString(str) {
  if (!str) return '';
  return str
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&amp;/g, '&')
    .trim();
}

/**
 * Romanizes or extracts clean Romanized title if raw title is in native Indic Unicode script.
 */
function romanizeIndicTitle(title, item) {
  if (!title) return '';
  if (/[\u0900-\u0D7F]/.test(title)) {
    const miAlbum = cleanString(item?.more_info?.album || item?.album || '');
    if (miAlbum && !/[\u0900-\u0D7F]/.test(miAlbum)) {
      return miAlbum;
    }
    if (item?.perma_url) {
      const match = item.perma_url.match(/\/(?:album|song)\/([^\/]+)\//);
      if (match && match[1]) {
        return match[1].split('-').map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
      }
    }
    if (item?.image) {
      const imgMatch = item.image.match(/\/([A-Za-z0-9\-]+)-(Hindi|Telugu|Tamil|Kannada|Malayalam|Punjabi|Bengali|Bhojpuri|Gujarati|Marathi)-\d{4}-/i);
      if (imgMatch && imgMatch[1]) {
        return imgMatch[1].split('-').map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
      }
    }
  }
  return title;
}

/**
 * Fetches authentic JioSaavn trending songs using native chart/trending modules
 * without any keyword search stuffing.
 */
async function getJioTrendingSongs(lang = 'hindi', limit = 30) {
  const language = lang.toLowerCase().trim();
  const geoHeaders = {
    ...JIO_GEO_HEADERS,
    Cookie: `country=IN; CH=G03%2CA07%2CO00%2CL03; language=${language}`,
  };

  const songs = [];
  const seenIds = new Set();

  function addSong(r) {
    if (!r || !r.id || seenIds.has(String(r.id))) return;
    const mi = r.more_info || {};
    let title = cleanString(r.title || r.song);
    title = romanizeIndicTitle(title, r);
    let album = cleanString(mi.album || r.album);
    album = romanizeIndicTitle(album, r);

    const primaryArtists = (mi.artistMap?.primary_artists || []).map((a) => a.name).filter(Boolean);
    const musicOnly = (mi.artistMap?.artists || [])
      .filter((a) => a.role !== 'starring')
      .map((a) => a.name)
      .filter(Boolean);
    const artistPool = primaryArtists.length > 0
      ? primaryArtists
      : (musicOnly.length > 0 ? musicOnly : [r.subtitle, r.primary_artists, mi.music, r.singers]);
    const cleanArtists = [...new Set(artistPool.filter(Boolean))].slice(0, 3).join(', ');
    const artist = cleanString(cleanArtists || 'DilSe Music');

    // Strict spam, 1-min reel cut, and compilation filter
    if (SPAM_AND_JUNK_FILTER.test(title) || SPAM_AND_JUNK_FILTER.test(album) || SPAM_AND_JUNK_FILTER.test(artist)) {
      return;
    }

    const encMedia = mi.encrypted_media_url || r.encrypted_media_url || '';
    const streamUrl = decryptMediaUrl(encMedia);
    let artwork = (r.image || '').replace('150x150', '500x500');
    if (artwork.startsWith('http:')) artwork = artwork.replace('http:', 'https:');
    if (artwork.includes('default_') || !artwork.startsWith('http')) artwork = '';

    const duration = parseInt(mi.duration || r.duration || '0', 10) || 0;

    seenIds.add(String(r.id));
    songs.push({
      id: String(r.id),
      title: title || 'Unknown Title',
      author: artist,
      album: album,
      duration: duration,
      thumbnail: artwork,
      streamUrl: streamUrl,
      source: 'jiosaavn',
      bitrate: '320kbps',
    });
  }

  // 1. Fetch content.getTrending
  try {
    const url = `https://www.jiosaavn.com/api.php?__call=content.getTrending&api_version=4&_format=json&ctx=web6dot0&languages=${encodeURIComponent(language)}`;
    const res = await fetch(url, { headers: geoHeaders });
    if (res.ok) {
      let text = await res.text();
      text = text.replace(/^\uFEFF/, '').trim();
      const list = JSON.parse(text);
      if (Array.isArray(list)) {
        for (const item of list) {
          if (item.type === 'song') {
            addSong(item);
          }
        }
      }
    }
  } catch (_) {}

  // 2. Fetch content.getBrowseModules (new_trending and new_albums)
  if (songs.length < limit) {
    try {
      const url = `https://www.jiosaavn.com/api.php?__call=content.getBrowseModules&api_version=4&_format=json&ctx=web6dot0&languages=${encodeURIComponent(language)}`;
      const res = await fetch(url, { headers: geoHeaders });
      if (res.ok) {
        let text = await res.text();
        text = text.replace(/^\uFEFF/, '').trim();
        const data = JSON.parse(text);
        const candidates = [...(data.new_trending || []), ...(data.new_albums || [])];
        for (const item of candidates) {
          if (item.type === 'song') {
            addSong(item);
            if (songs.length >= limit) break;
          }
        }
      }
    } catch (_) {}
  }

  // 3. Fallback to official top charts playlist if still low
  if (songs.length < 15) {
    try {
      const chartUrl = `https://www.jiosaavn.com/api.php?__call=content.getCharts&api_version=4&_format=json&ctx=web6dot0&languages=${encodeURIComponent(language)}`;
      const chartRes = await fetch(chartUrl, { headers: geoHeaders });
      if (chartRes.ok) {
        let chartText = await chartRes.text();
        chartText = chartText.replace(/^\uFEFF/, '').trim();
        const chartList = JSON.parse(chartText);
        if (Array.isArray(chartList) && chartList.length > 0) {
          const matchedChart = chartList.find(c => (c.title || '').toLowerCase().includes(language)) || chartList[0];
          if (matchedChart && matchedChart.id) {
            const detailUrl = `https://www.jiosaavn.com/api.php?__call=playlist.getDetails&api_version=4&_format=json&ctx=web6dot0&listid=${matchedChart.id}`;
            const detailRes = await fetch(detailUrl, { headers: geoHeaders });
            if (detailRes.ok) {
              let detailText = await detailRes.text();
              detailText = detailText.replace(/^\uFEFF/, '').trim();
              const detailData = JSON.parse(detailText);
              for (const song of detailData.list || []) {
                addSong(song);
                if (songs.length >= limit) break;
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  return songs.slice(0, limit);
}

/**
 * Fetches JioSaavn Top Charts playlists metadata.
 */
async function getJioTopCharts(lang = 'hindi') {
  const language = lang.toLowerCase().trim();
  const geoHeaders = {
    ...JIO_GEO_HEADERS,
    Cookie: `country=IN; CH=G03%2CA07%2CO00%2CL03; language=${language}`,
  };

  try {
    const url = `https://www.jiosaavn.com/api.php?__call=content.getCharts&api_version=4&_format=json&ctx=web6dot0&languages=${encodeURIComponent(language)}`;
    const res = await fetch(url, { headers: geoHeaders });
    if (!res.ok) return [];
    let text = await res.text();
    text = text.replace(/^\uFEFF/, '').trim();
    const data = JSON.parse(text);
    if (!Array.isArray(data)) return [];

    return data.map(c => {
      let img = (c.image || '').replace('150x150', '500x500');
      if (img.startsWith('http:')) img = img.replace('http:', 'https:');
      return {
        id: String(c.id),
        title: cleanString(c.title || 'Top Chart'),
        image: img,
        count: parseInt(c.count || '50', 10) || 50,
      };
    });
  } catch (_) {
    return [];
  }
}

/**
 * Fetches JioSaavn Top & Featured Albums for a specific language
 * with strict spam and modern release year (>= 2018) enforcement.
 */
async function getJioFeaturedAlbums(lang = 'hindi', limit = 20) {
  const language = lang.toLowerCase().trim();
  const geoHeaders = {
    ...JIO_GEO_HEADERS,
    Cookie: `country=IN; CH=G03%2CA07%2CO00%2CL03; language=${language}`,
  };

  const albums = [];
  const seenIds = new Set();

  function addAlbum(r) {
    if (!r || !r.id || seenIds.has(String(r.id))) return;
    const mi = r.more_info || {};
    let title = cleanString(r.title);
    title = romanizeIndicTitle(title, r);

    const primaryArtists = (mi.artistMap?.primary_artists || []).map((a) => a.name).filter(Boolean);
    const musicOnly = (mi.artistMap?.artists || [])
      .filter((a) => a.role !== 'starring')
      .map((a) => a.name)
      .filter(Boolean);
    const artistPool = primaryArtists.length > 0
      ? primaryArtists
      : (musicOnly.length > 0 ? musicOnly : [mi.music, r.subtitle]);
    const cleanArtistNames = [...new Set(artistPool.filter(Boolean))].slice(0, 3).join(', ');
    const artist = cleanString(cleanArtistNames || 'Soundtrack Album');

    // Strict spam and compilation filter
    if (SPAM_AND_JUNK_FILTER.test(title) || SPAM_AND_JUNK_FILTER.test(artist)) {
      return;
    }

    // Modern release year verification (year >= 2018)
    const rawDate = String(mi.release_date || r.year || mi.year || '');
    let yearNum = 0;
    const yearMatch = rawDate.match(/\b(19\d{2}|20\d{2})\b/);
    if (yearMatch) {
      yearNum = parseInt(yearMatch[1], 10);
      if (yearNum < 2018) return; // Drop retro compilations
    }

    let artwork = (r.image || '').replace('150x150', '500x500');
    if (artwork.startsWith('http:')) artwork = artwork.replace('http:', 'https:');
    if (artwork.includes('default_') || artwork.includes('album-default') || !artwork.startsWith('http')) {
      artwork = '';
    }

    const songCount = parseInt(mi.song_count || r.song_count || '8', 10) || 8;
    const itemLang = (r.language || mi.language || language).toLowerCase();

    seenIds.add(String(r.id));
    albums.push({
      id: String(r.id),
      title: title || 'Unknown Album',
      artist: artist,
      artwork: artwork,
      year: yearNum > 0 ? String(yearNum) : (rawDate.slice(0, 4) || '2026'),
      songCount: songCount,
      language: itemLang,
      type: 'album',
    });
  }

  // 1. Fetch from content.getBrowseModules
  try {
    const url = `https://www.jiosaavn.com/api.php?__call=content.getBrowseModules&api_version=4&_format=json&ctx=web6dot0&languages=${encodeURIComponent(language)}`;
    const res = await fetch(url, { headers: geoHeaders });
    if (res.ok) {
      let text = await res.text();
      text = text.replace(/^\uFEFF/, '').trim();
      const data = JSON.parse(text);
      const candidates = [...(data.new_albums || []), ...(data.new_trending || [])];
      for (const item of candidates) {
        if (item.type === 'album') {
          addAlbum(item);
          if (albums.length >= limit) break;
        }
      }
    }
  } catch (_) {}

  // 2. Fetch from content.getTrending
  if (albums.length < limit) {
    try {
      const url = `https://www.jiosaavn.com/api.php?__call=content.getTrending&api_version=4&_format=json&ctx=web6dot0&languages=${encodeURIComponent(language)}`;
      const res = await fetch(url, { headers: geoHeaders });
      if (res.ok) {
        let text = await res.text();
        text = text.replace(/^\uFEFF/, '').trim();
        const data = JSON.parse(text);
        if (Array.isArray(data)) {
          for (const item of data) {
            if (item.type === 'album') {
              addAlbum(item);
              if (albums.length >= limit) break;
            }
          }
        }
      }
    } catch (_) {}
  }

  return albums.slice(0, limit);
}
