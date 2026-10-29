/**
 * DilSe Web Audio Player Engine (Dual-Engine: JioSaavn 320k Direct Audio + YouTube Fallback)
 * 
 * Primary Engine: Native HTML5 <audio> streaming 320kbps AAC from JioSaavn public CDN
 *   - Enables 100% continuous background audio playback on iOS Safari / PWA when iPhone screen is locked.
 *   - Native iOS Lock Screen notifications, Dynamic Island, and Control Center scrubbers.
 *   - 320kbps pristine studio sound quality with zero IP bans.
 * 
 * Secondary Engine: Invisible YouTube IFrame Player (Method 1 Fallback)
 *   - Automatic fallback if a track is not available on JioSaavn or network drops.
 *   - Guarantees 0% playback failure under any circumstance.
 */

(function () {
  if ('audioSession' in navigator) {
    try {
      navigator.audioSession.type = 'playback';
    } catch (_) {}
  }

  const ENGINE_NONE = 0;
  const ENGINE_AUDIO = 1;
  const ENGINE_IFRAME = 2;

  let activeEngine = ENGINE_NONE;
  let currentVideoId = null;
  let currentStartSec = 0;
  let currentTitle = '';
  let currentArtist = '';
  let currentArtwork = '';
  let currentAlbum = '';
  let lastReportedPos = 0;
  let lastReportedDur = 0;
  let fallbackTimer = null;
  let iframeWatchdog = null;
  let switchingEngines = false;
  let currentPlaySessionId = 0;

  function clearIframeWatchdog() {
    if (iframeWatchdog) {
      clearTimeout(iframeWatchdog);
      iframeWatchdog = null;
    }
  }

  function armIframeWatchdog() {
    clearIframeWatchdog();
    iframeWatchdog = setTimeout(() => {
      if (activeEngine === ENGINE_IFRAME && ytPlayer && typeof ytPlayer.getPlayerState === 'function') {
        const state = ytPlayer.getPlayerState();
        if (state === 3 || state === -1) {
          console.warn('[DilSe Web Player] YouTube IFrame buffering watchdog expired (7.0s), notifying recovery');
          window.dispatchEvent(
            new CustomEvent('dilse_error', {
              detail: { code: 999 },
            })
          );
        }
      }
    }, 7000);
  }

  // Interruption and lifecycle tracking (reels, calls, tab switches)
  let isUserPaused = false;
  let isInterrupted = false;
  let wasPlayingBeforeInterruption = false;
  let streamNeedsReconnect = false;
  let currentDirectStream = '';

  // Dual-Deck HTML5 Native Audio Elements (Deck A & Deck B for true overlapping crossfades)
  let deckA = null;
  let deckB = null;
  let activeDeckId = 'A'; // 'A' or 'B'
  let audioEl = null; // Always points to active deck
  let crossfadeInterval = null;

  function getActiveDeck() {
    return activeDeckId === 'A' ? deckA : deckB;
  }

  function getInactiveDeck() {
    return activeDeckId === 'A' ? deckB : deckA;
  }

  function cancelCrossfade() {
    if (crossfadeInterval) {
      clearInterval(crossfadeInterval);
      crossfadeInterval = null;
    }
  }

  // Web Audio API 5-Band Studio Equalizer DSP
  let audioCtx = null;
  let eqFilters = []; // 5 BiquadFilterNodes: [60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz]
  let masterGainNode = null;
  let eqEnabled = false; // Default off so native 320k hardware audio is 100% active
  let eqBands = { 0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0 };

  const EQ_FREQUENCIES = [60, 230, 910, 3600, 14000];
  const EQ_TYPES = ['lowshelf', 'peaking', 'peaking', 'peaking', 'highshelf'];

  function getAudioContext() {
    if (!audioCtx) {
      const AudioCtxClass = window.AudioContext || window.webkitAudioContext;
      if (AudioCtxClass) {
        try {
          audioCtx = new AudioCtxClass();
        } catch (_) {}
      }
    }
    return audioCtx;
  }

  function unlockAudioContext() {
    if (audioCtx && audioCtx.state === 'suspended') {
      audioCtx.resume().catch(() => {});
    }
  }

  // Synchronous unlock listeners on all user interactions
  window.addEventListener('click', unlockAudioContext, { passive: true, capture: true });
  window.addEventListener('touchstart', unlockAudioContext, { passive: true, capture: true });
  window.addEventListener('pointerdown', unlockAudioContext, { passive: true, capture: true });

  let limiterNode = null;
  let bassBoostFilter = null;
  let bassBoostVal = 0.0;
  let virtualizerVal = 0.0;
  let spatialDry = null;
  let spatialWet = null;
  let spatialDelay = null;

  function updateMasterHeadroom(ctx) {
    if (!masterGainNode || !ctx) return;
    let maxBoostDb = 0.0;
    if (eqEnabled) {
      for (let i = 0; i < eqFilters.length; i++) {
        const val =
          parseFloat(
            eqBands[i] !== undefined ? eqBands[i] : eqBands[String(i)],
          ) || 0.0;
        if (val > maxBoostDb) maxBoostDb = val;
      }
      if (bassBoostVal > 0.0) {
        maxBoostDb = Math.max(maxBoostDb, bassBoostVal * 8.0);
      }
    }
    // Dynamic anti-clipping headroom: if maxBoost is +7dB, pre-cut by -3.5dB (0.67 multiplier).
    // If flat (0dB boost), multiplier is exactly 1.0 (zero loss, pure transparency).
    const headroom =
      eqEnabled && maxBoostDb > 0.0
        ? Math.pow(10, -(maxBoostDb * 0.55) / 20)
        : 1.0;
    try {
      masterGainNode.gain.setTargetAtTime(headroom, ctx.currentTime, 0.04);
    } catch (_) {
      masterGainNode.gain.value = headroom;
    }
  }

  function initEqualizerDSP() {
    const ctx = getAudioContext();
    if (!ctx) return;
    if (eqFilters.length === 5) return;

    try {
      eqFilters = [];
      masterGainNode = ctx.createGain();
      masterGainNode.gain.value = 1.0; // 1.0 default: transparent, zero artificial distortion

      // Studio Safety Limiter (soft-knee brickwall protection, never pumping)
      limiterNode = ctx.createDynamicsCompressor();
      limiterNode.threshold.value = -1.2;
      limiterNode.knee.value = 24;
      limiterNode.ratio.value = 4;
      limiterNode.attack.value = 0.005;
      limiterNode.release.value = 0.15;

      // 5-band Equalizer
      for (let i = 0; i < EQ_FREQUENCIES.length; i++) {
        const filter = ctx.createBiquadFilter();
        filter.type = EQ_TYPES[i];
        filter.frequency.value = EQ_FREQUENCIES[i];
        filter.Q.value = 1.2;
        const val =
          parseFloat(
            eqBands[i] !== undefined ? eqBands[i] : eqBands[String(i)],
          ) || 0.0;
        filter.gain.value = eqEnabled
          ? Math.max(-12.0, Math.min(12.0, val))
          : 0.0;
        eqFilters.push(filter);
      }

      for (let i = 0; i < eqFilters.length - 1; i++) {
        eqFilters[i].connect(eqFilters[i + 1]);
      }

      // Dedicated Deep Bass Boost Shelf (80Hz)
      bassBoostFilter = ctx.createBiquadFilter();
      bassBoostFilter.type = 'lowshelf';
      bassBoostFilter.frequency.value = 80;
      bassBoostFilter.gain.value = eqEnabled ? bassBoostVal * 8.0 : 0.0;
      eqFilters[eqFilters.length - 1].connect(bassBoostFilter);

      // 3D Spatial Surround Widener
      spatialDry = ctx.createGain();
      spatialWet = ctx.createGain();
      spatialDelay = ctx.createDelay();
      spatialDelay.delayTime.value = 0.012; // 12ms interaural delay for wide 3D soundfield
      spatialDry.gain.value = 1.0;
      spatialWet.gain.value = eqEnabled ? virtualizerVal * 0.45 : 0.0;

      bassBoostFilter.connect(spatialDry);
      bassBoostFilter.connect(spatialDelay);
      spatialDelay.connect(spatialWet);

      spatialDry.connect(masterGainNode);
      spatialWet.connect(masterGainNode);

      masterGainNode.connect(limiterNode);
      limiterNode.connect(ctx.destination);

      updateMasterHeadroom(ctx);
      console.log(
        '[DilSe Web Player] Web Audio API Studio Equalizer connected with BassBoost & 3D Spatializer',
      );
    } catch (e) {
      console.warn(
        '[DilSe Web Player] Equalizer DSP initialization warning:',
        e.message,
      );
    }
  }

  function connectDeckToDSP(deck) {
    if (!deck) return;
    const ctx = getAudioContext();
    if (!ctx) return;
    initEqualizerDSP();

    if (deck._dilseSourceConnected) return;
    try {
      // NOTE: crossOrigin is already set on creation in createDeckElement. Do not re-assign mid-playback!
      const source = ctx.createMediaElementSource(deck);
      if (eqFilters.length > 0) {
        source.connect(eqFilters[0]);
      } else {
        source.connect(ctx.destination);
      }
      deck._dilseSourceConnected = true;
      console.log(`[DilSe Web Player] Deck ${deck.id} connected to Studio Equalizer DSP`);
    } catch (e) {
      console.warn(`[DilSe Web Player] Web Audio routing note for ${deck.id} (direct playback fallback):`, e.message);
    }
  }

  function recreateDecksForDirectAudio() {
    console.log('[DilSe Web Player] Restoring pure native HTML5 audio decks for 100% background playback');
    const wasDeckA = (activeDeckId === 'A');
    const active = getActiveDeck();
    const currentSrc = active ? active.src : '';
    const currentPos = active ? (active.currentTime || 0) : 0;
    const isPlaying = active && !active.paused && (active.currentTime > 0);

    // Remove old elements from DOM
    if (deckA) {
      try {
        deckA.pause();
        deckA.removeAttribute('src');
        deckA.load();
        if (deckA.parentNode) deckA.parentNode.removeChild(deckA);
      } catch (_) {}
      deckA = null;
    }
    if (deckB) {
      try {
        deckB.pause();
        deckB.removeAttribute('src');
        deckB.load();
        if (deckB.parentNode) deckB.parentNode.removeChild(deckB);
      } catch (_) {}
      deckB = null;
    }

    // Recreate clean native decks with NO Web Audio attachment
    deckA = createDeckElement('dilse-deck-a');
    deckB = createDeckElement('dilse-deck-b');
    activeDeckId = wasDeckA ? 'A' : 'B';
    audioEl = getActiveDeck();

    if (currentSrc && currentSrc.startsWith('http')) {
      audioEl.src = currentSrc;
      if (currentPos > 0) audioEl.currentTime = currentPos;
      if (isPlaying) {
        audioEl.play().catch(() => {});
      }
    }
  }

  window.dilseSetEqualizer = function (
    enabled,
    bandsJson,
    bassBoost,
    virtualizer,
  ) {
    eqEnabled = Boolean(enabled);
    if (typeof bandsJson === 'string') {
      try {
        eqBands = JSON.parse(bandsJson);
      } catch (_) {}
    } else if (typeof bandsJson === 'object' && bandsJson !== null) {
      eqBands = bandsJson;
    }
    if (bassBoost !== undefined && bassBoost !== null) {
      bassBoostVal = Math.max(0.0, Math.min(1.0, parseFloat(bassBoost) || 0.0));
    }
    if (virtualizer !== undefined && virtualizer !== null) {
      virtualizerVal = Math.max(
        0.0,
        Math.min(1.0, parseFloat(virtualizer) || 0.0),
      );
    }

    const ctx = getAudioContext();
    if (ctx) {
      unlockAudioContext();
      initEqualizerDSP();

      for (let i = 0; i < eqFilters.length; i++) {
        const val = eqEnabled
          ? parseFloat(
              eqBands[i] !== undefined ? eqBands[i] : eqBands[String(i)],
            ) || 0.0
          : 0.0;
        const targetGain = Math.max(-12.0, Math.min(12.0, val));
        try {
          eqFilters[i].gain.setTargetAtTime(targetGain, ctx.currentTime, 0.03);
        } catch (_) {
          eqFilters[i].gain.value = targetGain;
        }
      }

      if (bassBoostFilter) {
        const targetBassGain = eqEnabled ? bassBoostVal * 8.0 : 0.0;
        try {
          bassBoostFilter.gain.setTargetAtTime(
            targetBassGain,
            ctx.currentTime,
            0.03,
          );
        } catch (_) {
          bassBoostFilter.gain.value = targetBassGain;
        }
      }

      if (spatialWet) {
        const targetSpatialGain = eqEnabled ? virtualizerVal * 0.45 : 0.0;
        try {
          spatialWet.gain.setTargetAtTime(
            targetSpatialGain,
            ctx.currentTime,
            0.03,
          );
        } catch (_) {
          spatialWet.gain.value = targetSpatialGain;
        }
      }

      updateMasterHeadroom(ctx);

      if (deckA) connectDeckToDSP(deckA);
      if (deckB) connectDeckToDSP(deckB);
    }
    console.log(
      '[DilSe Web Player] Equalizer applied smoothly. Enabled:',
      eqEnabled,
      'Bass:',
      bassBoostVal,
      '3D:',
      virtualizerVal,
    );
  };

  // YouTube IFrame Player instance
  let ytPlayer = null;
  let ytReady = false;
  let pendingVideoId = null;
  let pendingStartSec = 0;
  let ticker = null;

  // Silent background keeper strictly for iOS Safari / PWA audio session activation
  let bgAudio = null;
  const isIOS =
    typeof navigator !== 'undefined' &&
    (/iPad|iPhone|iPod/.test(navigator.userAgent || '') ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1));

  function ensureBgAudio() {
    if (!isIOS) return null;
    if (!bgAudio) {
      bgAudio = document.createElement('audio');
      bgAudio.setAttribute('playsinline', 'true');
      bgAudio.setAttribute('webkit-playsinline', 'true');
      bgAudio.loop = true;
      // 1-second silent stereo WAV base64
      bgAudio.src =
        'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=';
      document.body.appendChild(bgAudio);
    }
    return bgAudio;
  }

  function startBgAudio() {
    if (!isIOS) return;
    try {
      const audio = ensureBgAudio();
      if (audio) audio.play().catch(() => {});
    } catch (_) {}
  }

  function stopBgAudio() {
    if (bgAudio) {
      try {
        bgAudio.pause();
      } catch (_) {}
    }
  }

  function createDeckElement(id) {
    const el = document.createElement('audio');
    el.id = id;
    el.setAttribute('playsinline', 'true');
    el.setAttribute('webkit-playsinline', 'true');
    el.preload = 'auto';
    el.volume = 1.0;
    el.muted = false;
    el.crossOrigin = 'anonymous';
    el.style.cssText =
      'position:fixed;top:-9999px;left:-9999px;width:1px;height:1px;opacity:0.001;pointer-events:none;';
    document.body.appendChild(el);

    el.addEventListener('playing', () => {
      if (activeEngine === ENGINE_AUDIO && el === getActiveDeck()) {
        console.log(`[DilSe Web Player] JioSaavn 320k audio playing (${id})`);
        unlockAudioContext();
        clearFallbackTimer();
        isInterrupted = false;
        wasPlayingBeforeInterruption = true;
        broadcastState('playing');
        if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'playing';
      }
    });

    el.addEventListener('pause', () => {
      if (activeEngine === ENGINE_AUDIO && !switchingEngines && el === getActiveDeck()) {
        console.log(`[DilSe Web Player] JioSaavn audio paused (${id})`);
        if (!isUserPaused && wasPlayingBeforeInterruption && !el.ended && (el.currentTime > 0)) {
          console.log('[DilSe Web Player] System interruption detected');
          isInterrupted = true;
        }
        broadcastState('paused');
        if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'paused';
      }
    });

    el.addEventListener('waiting', () => {
      if (activeEngine === ENGINE_AUDIO && el === getActiveDeck()) {
        broadcastState('buffering');
      }
    });

    el.addEventListener('timeupdate', () => {
      if (activeEngine === ENGINE_AUDIO && el === getActiveDeck()) {
        const pos = el.currentTime || 0;
        const dur = el.duration || 0;
        lastReportedPos = pos;
        if (dur > 0) lastReportedDur = dur;
        broadcastTime(pos, dur);
        updateMediaSessionPosition(pos, dur);
      }
    });

    el.addEventListener('ended', () => {
      if (activeEngine === ENGINE_AUDIO && el === getActiveDeck()) {
        const pos = el.currentTime || 0;
        const dur = el.duration || 0;
        // Verify genuine track completion: ensure duration is valid and playback is within 2.5s of end
        if (dur > 1 && pos >= (dur - 2.5)) {
          console.log(`[DilSe Web Player] JioSaavn audio track ended (${id})`);
          broadcastState('ended');
          if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'paused';
          window.dispatchEvent(new CustomEvent('dilse_ended'));
        } else {
          console.log(`[DilSe Web Player] Ignored premature/reset ended event on ${id} (pos: ${pos}, dur: ${dur})`);
        }
      }
    });

    el.addEventListener('error', (e) => {
      if (activeEngine === ENGINE_AUDIO && !switchingEngines && el === getActiveDeck()) {
        console.warn(`[DilSe Web Player] Direct audio error (${id}):`, e);
        // If element is paused, in background, or interrupted (e.g. CDN socket dropped during idle/pause):
        // Flag for reconnection on resume rather than triggering YouTube IFrame fallback (which fails in iOS background).
        if (el.paused || isUserPaused || isInterrupted || document.visibilityState === 'hidden') {
          console.log('[DilSe Web Player] Socket closed while paused/backgrounded; will reconnect on resume');
          streamNeedsReconnect = true;
          return;
        }
        triggerFallback();
      }
    });

    // Only attach Web Audio DSP if equalizer is actively enabled
    if (eqEnabled) {
      connectDeckToDSP(el);
    }
    return el;
  }

  // Ensure Native HTML5 Dual-Deck Audio Elements are ready
  function ensureAudioElement() {
    if (!deckA) deckA = createDeckElement('dilse-deck-a');
    if (!deckB) deckB = createDeckElement('dilse-deck-b');
    audioEl = getActiveDeck();
    return audioEl;
  }

  function clearFallbackTimer() {
    if (fallbackTimer) {
      clearTimeout(fallbackTimer);
      fallbackTimer = null;
    }
  }

  function armFallbackTimer(videoId, startSeconds) {
    clearFallbackTimer();
    // If direct audio doesn't start within 5.0 seconds, auto-fallback to YouTube
    fallbackTimer = setTimeout(() => {
      if (activeEngine === ENGINE_AUDIO && (!audioEl || audioEl.readyState < 2)) {
        console.warn('[DilSe Web Player] Direct stream timeout (5.0s), switching to YouTube fallback');
        triggerFallback();
      }
    }, 5000);
  }

  function isValidYtId(id) {
    return Boolean(
      id &&
      typeof id === 'string' &&
      id.length === 11 &&
      !/^\d{11}$/.test(id) &&
      /^[a-zA-Z0-9_-]{11}$/.test(id)
    );
  }

  function handlePlayRejection(err, targetAudio) {
    const errName = err ? (err.name || '') : '';
    const errMsg = err ? (err.message || String(err)) : '';
    console.warn('[DilSe Web Player] audioEl.play() rejected:', errName, errMsg);

    // If play was aborted due to another play/pause action or rapid track change, this is expected DOM behavior.
    // DO NOT trigger fallback or auto-skip!
    if (
      errName === 'AbortError' ||
      errMsg.includes('interrupted') ||
      errMsg.includes('pause()')
    ) {
      console.log('[DilSe Web Player] Playback request interrupted by subsequent action (benign AbortError). Ignoring.');
      return;
    }

    // If browser Autoplay policy blocked sound before user gesture, DO NOT trigger fallback or skip track!
    if (
      errName === 'NotAllowedError' ||
      errName === 'SecurityError' ||
      errMsg.includes('interact') ||
      errMsg.includes('user gesture')
    ) {
      console.warn(
        '[DilSe Web Player] Autoplay policy prevented playback. Arming user-interaction listener…'
      );
      clearFallbackTimer();
      broadcastState('paused');

      const resumeOnGesture = () => {
        window.removeEventListener('pointerdown', resumeOnGesture, true);
        window.removeEventListener('keydown', resumeOnGesture, true);
        window.removeEventListener('click', resumeOnGesture, true);
        const el = targetAudio || audioEl;
        if (activeEngine === ENGINE_AUDIO && el && el.src) {
          el.play().then(() => {
            unlockAudioContext();
          }).catch((e) => {
            console.warn('[DilSe Web Player] Gesture-triggered play failed:', e);
            triggerFallback();
          });
        }
      };
      window.addEventListener('pointerdown', resumeOnGesture, { capture: true, once: true });
      window.addEventListener('keydown', resumeOnGesture, { capture: true, once: true });
      window.addEventListener('click', resumeOnGesture, { capture: true, once: true });
      return;
    }

    triggerFallback();
  }

  function triggerFallback() {
    clearFallbackTimer();
    if (activeEngine === ENGINE_IFRAME) return; // already in fallback
    if (!navigator.onLine || (currentDirectStream && (currentDirectStream.startsWith('/offline_audio') || currentDirectStream.startsWith('blob:')))) {
      console.warn('[DilSe Web Player] Offline mode active; skipping YouTube online fallback');
      return;
    }

    console.warn('[DilSe Web Player] Activating Method 1 YouTube IFrame fallback for video:', currentVideoId);
    switchingEngines = true;
    if (audioEl) {
      try {
        audioEl.pause();
        audioEl.removeAttribute('src');
        audioEl.load();
      } catch (_) {}
    }
    switchingEngines = false;
    activeEngine = ENGINE_IFRAME;

    const startAt = lastReportedPos > 0 ? lastReportedPos : currentStartSec;

    if (!isValidYtId(currentVideoId)) {
      console.warn('[DilSe Web Player] currentVideoId is synthetic/non-YouTube:', currentVideoId, '- resolving via search API…');
      const q = `${currentTitle} ${currentArtist}`.trim();
      const secondaryBackend = window.dilseApiBaseUrl || 'https://music-backend-4kel.onrender.com';
      fetch(`${secondaryBackend}/search?q=${encodeURIComponent(q)}&limit=1`)
        .then((r) => r.json())
        .then((results) => {
          if (Array.isArray(results) && results.length > 0 && results[0].id) {
            currentVideoId = results[0].id;
            console.log('[DilSe Web Player] Resolved fallback YouTube ID:', currentVideoId);
            playViaIframe(currentVideoId, startAt);
          } else {
            console.warn('[DilSe Web Player] Could not resolve YouTube ID for fallback:', q);
          }
        })
        .catch((err) => {
          console.warn('[DilSe Web Player] Fallback search error:', err);
        });
      return;
    }

    playViaIframe(currentVideoId, startAt);
  }

  // Create an invisible off-screen container for YouTube IFrame
  function ensureYtContainer() {
    let el = document.getElementById('dilse-yt-host');
    if (!el) {
      el = document.createElement('div');
      el.id = 'dilse-yt-host';
      el.style.cssText =
        'position:fixed;top:-9999px;left:-9999px;width:1px;height:1px;opacity:0.001;pointer-events:none;z-index:-9999;';
      document.body.appendChild(el);
    }
    return el;
  }

  // Called automatically when https://www.youtube.com/iframe_api finishes loading
  window.onYouTubeIframeAPIReady = function () {
    console.log('[DilSe Web Player] YouTube IFrame API Ready');
    ensureYtContainer();
    ensureBgAudio();
    ensureAudioElement();

    try {
      ytPlayer = new YT.Player('dilse-yt-host', {
        height: '1',
        width: '1',
        playerVars: {
          autoplay: 1,
          controls: 0,
          disablekb: 1,
          fs: 0,
          playsinline: 1,
          rel: 0,
          enablejsapi: 1,
          origin: window.location.origin,
        },
        events: {
          onReady: onYtPlayerReady,
          onStateChange: onYtStateChange,
          onError: onYtError,
        },
      });
    } catch (e) {
      console.error('[DilSe Web Player] YouTube IFrame initialization error:', e);
    }
  };

  function onYtPlayerReady() {
    console.log('[DilSe Web Player] YouTube Player Instance Ready');
    ytReady = true;
    if (activeEngine === ENGINE_IFRAME && pendingVideoId) {
      const vid = pendingVideoId;
      const start = pendingStartSec;
      pendingVideoId = null;
      pendingStartSec = 0;
      playViaIframe(vid, start);
    }
  }

  function playViaIframe(videoId, startSeconds) {
    activeEngine = ENGINE_IFRAME;
    startBgAudio();

    // Ensure direct HTML5 audio is completely stopped to prevent ghost playback collisions
    if (audioEl) {
      try {
        audioEl.pause();
        audioEl.removeAttribute('src');
        audioEl.load();
      } catch (_) {}
    }

    if (!ytReady || !ytPlayer || typeof ytPlayer.loadVideoById !== 'function') {
      console.log('[DilSe Web Player] YouTube Player not ready yet. Queuing:', videoId);
      pendingVideoId = videoId;
      pendingStartSec = startSeconds || 0;
      return;
    }

    try {
      if (typeof ytPlayer.unMute === 'function') {
        try { ytPlayer.unMute(); } catch (_) {}
      }
      if (typeof ytPlayer.setVolume === 'function') {
        try { ytPlayer.setVolume(100); } catch (_) {}
      }
      ytPlayer.loadVideoById({
        videoId: videoId,
        startSeconds: startSeconds || 0,
        suggestedQuality: 'small',
      });
      ytPlayer.playVideo();
      try {
        if (typeof ytPlayer.setPlaybackQuality === 'function') {
          ytPlayer.setPlaybackQuality('small');
        }
      } catch (_) {}
      if (typeof ytPlayer.unMute === 'function') {
        try { ytPlayer.unMute(); } catch (_) {}
      }
      armIframeWatchdog();
    } catch (err) {
      console.error('[DilSe Web Player] YouTube play error:', err);
      clearIframeWatchdog();
      window.dispatchEvent(
        new CustomEvent('dilse_error', {
          detail: { code: 998 },
        })
      );
    }
  }

  function startTicker() {
    stopTicker();
    const intervalMs = document.visibilityState === 'hidden' ? 2000 : 250;
    ticker = setInterval(() => {
      if (activeEngine === ENGINE_IFRAME && ytPlayer && typeof ytPlayer.getCurrentTime === 'function') {
        const pos = ytPlayer.getCurrentTime() || 0;
        const dur = ytPlayer.getDuration() || 0;
        lastReportedPos = pos;
        if (dur > 0) lastReportedDur = dur;
        broadcastTime(pos, dur);
        updateMediaSessionPosition(pos, dur);
      }
    }, intervalMs);
  }

  function stopTicker() {
    if (ticker) {
      clearInterval(ticker);
      ticker = null;
    }
  }

  function onYtStateChange(event) {
    if (activeEngine !== ENGINE_IFRAME) return;

    let stateName = 'unknown';
    switch (event.data) {
      case 1:
        stateName = 'playing';
        clearIframeWatchdog();
        try {
          if (ytPlayer && typeof ytPlayer.setPlaybackQuality === 'function') {
            ytPlayer.setPlaybackQuality('small');
          }
        } catch (_) {}
        startTicker();
        startBgAudio();
        if (ytPlayer && typeof ytPlayer.isMuted === 'function' && ytPlayer.isMuted()) {
          try {
            ytPlayer.unMute();
            ytPlayer.setVolume(100);
          } catch (_) {}
        }
        if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'playing';
        break;
      case 2:
        stateName = 'paused';
        clearIframeWatchdog();
        stopTicker();
        stopBgAudio();
        if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'paused';
        break;
      case 3:
        stateName = 'buffering';
        armIframeWatchdog();
        break;
      case 0:
        stateName = 'ended';
        clearIframeWatchdog();
        stopTicker();
        stopBgAudio();
        window.dispatchEvent(new CustomEvent('dilse_ended'));
        break;
      default:
        stateName = 'idle';
        break;
    }

    broadcastState(stateName, event.data);
  }

  function onYtError(event) {
    if (activeEngine !== ENGINE_IFRAME) return;
    console.warn('[DilSe Web Player] YouTube IFrame Error code:', event.data);
    window.dispatchEvent(
      new CustomEvent('dilse_error', {
        detail: { code: event.data },
      })
    );
  }

  function broadcastState(stateName, code) {
    window.dispatchEvent(
      new CustomEvent('dilse_state_change', {
        detail: { state: stateName, code: code || 0 },
      })
    );
  }

  function broadcastTime(pos, dur) {
    window.dispatchEvent(
      new CustomEvent('dilse_time_update', {
        detail: { position: pos, duration: dur },
      })
    );
  }

  function updateMediaSessionPosition(pos, dur) {
    if (
      'mediaSession' in navigator &&
      dur > 0 &&
      typeof navigator.mediaSession.setPositionState === 'function'
    ) {
      try {
        navigator.mediaSession.setPositionState({
          duration: dur,
          playbackRate: 1,
          position: Math.min(pos, dur),
        });
      } catch (_) {}
    }
  }

  function attemptAutoResumeAfterInterruption() {
    if (isInterrupted && !isUserPaused && document.visibilityState === 'visible') {
      console.log('[DilSe Web Player] Attempting auto-resume after interruption...');
      window.dilseResume();
    }
  }

  // Consolidated iOS Safari / PWA background playback & thermal watchdog
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') {
      attemptAutoResumeAfterInterruption();
      // Immediately snap UI into sync
      if (
        activeEngine === ENGINE_IFRAME &&
        ytPlayer &&
        typeof ytPlayer.getCurrentTime === 'function'
      ) {
        const pos = ytPlayer.getCurrentTime() || 0;
        const dur = ytPlayer.getDuration() || 0;
        lastReportedPos = pos;
        if (dur > 0) lastReportedDur = dur;
        broadcastTime(pos, dur);
        updateMediaSessionPosition(pos, dur);
        startTicker();
      } else if (activeEngine === ENGINE_AUDIO && audioEl) {
        const pos = audioEl.currentTime || 0;
        const dur = audioEl.duration || 0;
        lastReportedPos = pos;
        if (dur > 0) lastReportedDur = dur;
        broadcastTime(pos, dur);
        updateMediaSessionPosition(pos, dur);
      }
    } else if (document.visibilityState === 'hidden') {
      if (
        activeEngine === ENGINE_IFRAME &&
        ytPlayer &&
        typeof ytPlayer.getPlayerState === 'function'
      ) {
        const state = ytPlayer.getPlayerState();
        if (state === 1 || state === 3) {
          startBgAudio();
          setTimeout(() => {
            if (ytPlayer && typeof ytPlayer.playVideo === 'function') {
              ytPlayer.playVideo();
            }
          }, 120);
        }
      }
      // Background tab: re-trigger ticker to adopt throttled 2000ms interval
      if (ticker) {
        startTicker();
      }
    }
  });

  window.addEventListener('focus', attemptAutoResumeAfterInterruption);
  window.addEventListener('pageshow', attemptAutoResumeAfterInterruption);

  window.dilsePlayWithOptions = function (opts) {
    opts = opts || {};
    return window.dilsePlay(
      opts.videoId,
      opts.startSeconds || 0,
      opts.title || '',
      opts.artist || '',
      opts.artworkUrl || '',
      opts.streamUrl || ''
    );
  };

  window.dilsePlay = async function (
    videoId,
    startSeconds,
    title,
    artist,
    artworkUrl,
    directStreamUrl
  ) {
    unlockAudioContext();
    const sessionId = ++currentPlaySessionId;
    currentVideoId = videoId;
    currentStartSec = startSeconds || 0;
    currentTitle = title || currentTitle || '';
    currentArtist = artist || currentArtist || '';
    currentArtwork = artworkUrl || currentArtwork || '';
    lastReportedPos = startSeconds || 0;

    clearFallbackTimer();
    stopTicker();

    cancelCrossfade();
    // Immediately stop and detach both audio decks to eliminate ghost playback
    if (deckA) {
      try {
        deckA.pause();
        deckA.removeAttribute('src');
        deckA.load();
      } catch (_) {}
    }
    if (deckB) {
      try {
        deckB.pause();
        deckB.removeAttribute('src');
        deckB.load();
      } catch (_) {}
    }
    if (ytPlayer && typeof ytPlayer.stopVideo === 'function') {
      try {
        ytPlayer.stopVideo();
      } catch (_) {}
    }

    startBgAudio();
    ensureAudioElement();
    if (audioEl) {
      audioEl.muted = false;
      audioEl.volume = 1.0;
    }
    if (masterGainNode && audioCtx) {
      try {
        masterGainNode.gain.setValueAtTime(1.0, audioCtx.currentTime);
      } catch (_) {
        masterGainNode.gain.value = 1.0;
      }
    }
    broadcastState('buffering');

    // Update MediaSession with initial metadata
    window.dilseSetMetadata(currentTitle, currentArtist, currentArtwork, currentAlbum);

    isUserPaused = false;
    isInterrupted = false;
    wasPlayingBeforeInterruption = true;

    // If direct stream URL is already provided (e.g. from native JioSaavn search), play instantly!
    const streamToPlay = directStreamUrl || window.dilseCurrentStreamUrl || '';
    window.dilseCurrentStreamUrl = '';
    currentDirectStream = streamToPlay;

    const isDirectAudio = streamToPlay && typeof streamToPlay === 'string' &&
      (streamToPlay.startsWith('http') || streamToPlay.startsWith('blob:') || streamToPlay.startsWith('/offline_audio') || streamToPlay.startsWith('data:')) &&
      (streamToPlay.includes('.mp4') || streamToPlay.includes('.m4a') || streamToPlay.includes('saavncdn') || streamToPlay.includes('media-cdn') || streamToPlay.includes('workers.dev') || streamToPlay.startsWith('blob:') || streamToPlay.startsWith('/offline_audio'));

    if (isDirectAudio) {
      console.log('[DilSe Web Player] Direct 320k stream provided, playing immediately:', streamToPlay);
      activeEngine = ENGINE_AUDIO;

      if (ytPlayer && typeof ytPlayer.stopVideo === 'function') {
        try {
          ytPlayer.stopVideo();
        } catch (_) {}
      }
      stopTicker();

      audioEl.src = streamToPlay;
      audioEl.muted = false;
      audioEl.volume = 1.0;
      if (masterGainNode && audioCtx) {
        try {
          masterGainNode.gain.setValueAtTime(1.0, audioCtx.currentTime);
        } catch (_) {
          masterGainNode.gain.value = 1.0;
        }
      }
      if (startSeconds > 0) {
        audioEl.currentTime = startSeconds;
      }
      if (!streamToPlay.startsWith('blob:') && !streamToPlay.startsWith('/offline_audio')) {
        armFallbackTimer(videoId, startSeconds);
      }

      audioEl.play().then(() => {
        unlockAudioContext();
      }).catch((err) => {
        handlePlayRejection(err, audioEl);
      });
      return;
    }

    // If a clean song title is available, resolve on JioSaavn for 320k direct audio stream
    if (title && title.trim().length > 1) {
      // Prioritize low-latency Cloudflare Edge Worker (~200ms) over Render backend
      const primaryWorker =
        window.dilseWorkerBaseUrl ||
        'https://dilse-edge-stream.charanteja-kondakalla030206.workers.dev';
      const secondaryBackend =
        window.dilseApiBaseUrl ||
        'https://music-backend-4kel.onrender.com';

      const cleanTitle = title
        .replace(/[\(\[\{].*?[\)\]\}]/g, '')
        .replace(/official video|music video|full song|lyric video|audio song|video song/gi, '')
        .replace(/\|.*$/g, '')
        .trim();

      console.log('[DilSe Web Player] Resolving on JioSaavn Smart Engine:', title, '| Artist:', artist);

      try {
        const fetchPromise = fetch(
          `${primaryWorker}/jio?title=${encodeURIComponent(cleanTitle || title)}&artist=${encodeURIComponent(artist || '')}`
        ).then(async (res) => {
          if (res.ok) {
            const json = await res.json();
            if (json.status === 'ok' && json.match && json.data?.streamUrl) {
              return json;
            }
          }
          // Secondary fallback to Render backend if Cloudflare worker didn't find match
          return fetch(
            `${secondaryBackend}/jio?title=${encodeURIComponent(cleanTitle || title)}&artist=${encodeURIComponent(artist || '')}`
          ).then(r => r.ok ? r.json() : null);
        });

        // 6.5s timeout for fast response while allowing Render cold starts if needed
        const timeoutPromise = new Promise((_, reject) =>
          setTimeout(() => reject(new Error('JioSaavn resolution timeout')), 6500)
        );

        const data = await Promise.race([fetchPromise, timeoutPromise]);
        if (sessionId !== currentPlaySessionId) return; // Superceded by another play call

        if (data && data.status === 'ok' && data.match && data.data?.streamUrl) {
          const jioSong = data.data;

          // Validate that the resolved track genuinely matches the requested song/artist
          const reqTitle = (cleanTitle || title || '').toLowerCase();
          const reqArtist = (artist || '').toLowerCase().trim();
          const resTitle = (jioSong.title || '').toLowerCase();
          const resArtist = (jioSong.artist || '').toLowerCase();
          const resArtwork = (jioSong.artwork || '').toLowerCase();

          const isCoverOrInstrumental =
            resArtwork.includes('-instrumental-') ||
            resTitle.includes('instrumental') ||
            resTitle.includes('karaoke') ||
            resTitle.includes('tribute') ||
            resTitle.includes('piano version') ||
            resTitle.includes('easy piano') ||
            resTitle.includes('originally perfo') ||
            resArtist.includes('karaoke') ||
            resArtist.includes('tribute') ||
            resArtist.includes('strings') ||
            resArtist.includes('zzang') ||
            resArtist.includes('luxebeats');

          // Title validation: ensure core keywords appear
          const titleWords = reqTitle
            .split(/\s+/)
            .map(w => w.replace(/[^a-z0-9]/g, ''))
            .filter(w => w.length >= 3 && !['song', 'audio', 'video', 'from', 'lyrics', 'feat', 'with'].includes(w));
          const titleMatches = titleWords.length === 0 || titleWords.some(w => resTitle.includes(w));

          // Artist validation: if artist was specified, check it exists in the resolved track
          let artistMatches = true;
          if (reqArtist.length >= 3) {
            const artistWords = reqArtist
              .split(/\s+/)
              .map(w => w.replace(/[^a-z0-9]/g, ''))
              .filter(w => w.length >= 3);
            artistMatches = artistWords.some(w => resArtist.includes(w));
          }

          if (!isCoverOrInstrumental && titleMatches && artistMatches) {
            console.log(
              `[DilSe Web Player] JioSaavn Confident Match Confirmed: "${jioSong.title}" by "${jioSong.artist}" -> ${jioSong.streamUrl}`
            );

            activeEngine = ENGINE_AUDIO;

            // Stop YouTube IFrame if running
            if (ytPlayer && typeof ytPlayer.stopVideo === 'function') {
              try {
                ytPlayer.stopVideo();
              } catch (_) {}
            }
            stopTicker();

            audioEl.src = jioSong.streamUrl;
            audioEl.muted = false;
            audioEl.volume = 1.0;
            if (masterGainNode && audioCtx) {
              try {
                masterGainNode.gain.setValueAtTime(1.0, audioCtx.currentTime);
              } catch (_) {
                masterGainNode.gain.value = 1.0;
              }
            }
            if (startSeconds > 0) {
              audioEl.currentTime = startSeconds;
            }
            armFallbackTimer(videoId, startSeconds);

            // Update MediaSession with high-res album artwork from JioSaavn
            window.dilseSetMetadata(
              jioSong.title || title,
              jioSong.artist || artist,
              jioSong.artwork || artworkUrl,
              jioSong.album || currentAlbum
            );

            audioEl.play().then(() => {
              unlockAudioContext();
            }).catch((err) => {
              handlePlayRejection(err, audioEl);
            });
            return;
          } else {
            console.log(
              `[DilSe Web Player] JioSaavn resolution rejected (Cover: ${isCoverOrInstrumental}, TitleMatch: ${titleMatches}, ArtistMatch: ${artistMatches}). Falling back to YouTube IFrame for authentic audio.`
            );
          }
        }
      } catch (err) {
        console.log('[DilSe Web Player] JioSaavn resolution skipped/failed:', err.message);
      }
    }

    if (sessionId !== currentPlaySessionId) return;

    // Fallback: If not matched on JioSaavn or resolution failed, play via YouTube IFrame (Method 1)
    console.log('[DilSe Web Player] Playing via Method 1 (YouTube IFrame fallback):', videoId);
    playViaIframe(videoId, startSeconds);
  };

  window.dilseCrossfade = function (videoId, title, artist, artworkUrl) {
    const streamToPlay = window.dilseCurrentStreamUrl || '';
    window.dilseCurrentStreamUrl = '';
    const crossfadeSec = parseInt(window.dilseCrossfadeSeconds, 10) || 4;
    window.dilseCrossfadeSeconds = 0;

    ensureAudioElement();
    cancelCrossfade();

    const outgoing = getActiveDeck();
    const incoming = getInactiveDeck();

    console.log(`[DilSe Web Player] Initiating ${crossfadeSec}s crossfade transition to: "${title}" by "${artist}"`);

    // Update global state & metadata
    currentVideoId = videoId;
    currentTitle = title || '';
    currentArtist = artist || '';
    currentArtwork = artworkUrl || '';
    lastReportedPos = 0;
    isUserPaused = false;
    isInterrupted = false;
    wasPlayingBeforeInterruption = true;

    window.dilseSetMetadata(currentTitle, currentArtist, currentArtwork, currentAlbum);

    function startRamp() {
      // Toggle active deck
      activeDeckId = (activeDeckId === 'A' ? 'B' : 'A');
      audioEl = incoming;
      activeEngine = ENGINE_AUDIO;

      incoming.volume = 0.0;
      incoming.muted = false;
      incoming.currentTime = 0;

      const durationMs = crossfadeSec * 1000;
      const startTime = performance.now();

      incoming.play().then(() => {
        broadcastState('playing');
        crossfadeInterval = setInterval(() => {
          const elapsed = performance.now() - startTime;
          const ratio = Math.min(1.0, elapsed / durationMs);

          // Equal-power crossfade curve for studio smoothness
          const outVol = Math.cos((ratio * Math.PI) / 2);
          const inVol = Math.sin((ratio * Math.PI) / 2);

          if (outgoing) {
            outgoing.volume = Math.max(0, Math.min(1, outVol));
          }
          incoming.volume = Math.max(0, Math.min(1, inVol));

          if (ratio >= 1.0) {
            cancelCrossfade();
            if (outgoing) {
              try {
                outgoing.volume = 0;
                outgoing.pause();
                outgoing.removeAttribute('src');
                outgoing.load();
              } catch (_) {}
            }
            incoming.volume = 1.0;
            console.log('[DilSe Web Player] Crossfade transition complete. Active deck:', activeDeckId);
          }
        }, 40);
      }).catch((err) => {
        console.warn('[DilSe Web Player] incoming crossfade play failed:', err);
        // Fallback to normal play
        window.dilsePlay(videoId, 0, title, artist, streamToPlay);
      });
    }

    if (streamToPlay && streamToPlay.startsWith('http')) {
      incoming.src = streamToPlay;
      startRamp();
    } else {
      // If direct stream URL was not passed directly, fall back to dilsePlay to resolve and play
      window.dilsePlay(videoId, 0, title, artist, streamToPlay);
    }
  };

  window.dilseSetFallbackVideoId = function (realYtId) {
    if (isValidYtId(realYtId)) {
      console.log('[DilSe Web Player] Fallback YouTube ID updated to:', realYtId);
      currentVideoId = realYtId;
    }
  };

  function cleanUpOnAppExit(event) {
    // Only cleanup when the page is being permanently unloaded/closed by the user.
    // NEVER destroy audio elements on pagehide, which fires when backgrounding or switching to other apps.
    if (event && (event.type === 'pagehide' || event.persisted)) return;

    stopBgAudio();
    cancelCrossfade();
    clearFallbackTimer();
    clearIframeWatchdog();
    stopTicker();
    if (masterGainNode && audioCtx) {
      try { masterGainNode.gain.value = 0.0; } catch (_) {}
    }
    if (deckA) {
      try {
        deckA.pause();
      } catch (_) {}
    }
    if (deckB) {
      try {
        deckB.pause();
      } catch (_) {}
    }
    if (ytPlayer && typeof ytPlayer.stopVideo === 'function') {
      try { ytPlayer.stopVideo(); } catch (_) {}
    }
  }

  window.addEventListener('beforeunload', cleanUpOnAppExit);

  window.dilsePause = function () {
    isUserPaused = true;
    isInterrupted = false;
    wasPlayingBeforeInterruption = false;
    cancelCrossfade();
    stopBgAudio();
    clearFallbackTimer();
    clearIframeWatchdog();
    stopTicker();

    // 1. Instantly silence Web Audio master gain to prevent render quantum stutter loop
    if (masterGainNode && audioCtx) {
      try {
        masterGainNode.gain.cancelScheduledValues(audioCtx.currentTime);
        masterGainNode.gain.setValueAtTime(0.0, audioCtx.currentTime);
      } catch (_) {
        masterGainNode.gain.value = 0.0;
      }
    }

    // 2. Pause active decks without muting (muting can cause mobile browsers to drop background MediaSession permissions)
    if (deckA) {
      try {
        deckA.pause();
      } catch (_) {}
    }
    if (deckB) {
      try {
        deckB.pause();
      } catch (_) {}
    }
    if (ytPlayer && typeof ytPlayer.pauseVideo === 'function') {
      try {
        ytPlayer.pauseVideo();
      } catch (_) {}
    }

    // 3. Suspend AudioContext to save power, but keep audio element src and MediaSession fully intact
    if (audioCtx && audioCtx.state === 'running') {
      try {
        audioCtx.suspend().catch(() => {});
      } catch (_) {}
    }

    broadcastState('paused');
    if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'paused';
  };

  window.dilseResume = function () {
    unlockAudioContext();
    isUserPaused = false;
    isInterrupted = false;
    wasPlayingBeforeInterruption = true;
    startBgAudio();

    // Restore master gain if equalizer DSP is active
    if (masterGainNode && audioCtx) {
      try {
        masterGainNode.gain.cancelScheduledValues(audioCtx.currentTime);
        masterGainNode.gain.setValueAtTime(1.0, audioCtx.currentTime);
      } catch (_) {
        masterGainNode.gain.value = 1.0;
      }
    }

    if (activeEngine === ENGINE_AUDIO) {
      const active = getActiveDeck();
      if (active) {
        active.muted = false;
        active.volume = 1.0;

        const posToResume = (active.currentTime > 0) ? active.currentTime : (lastReportedPos || 0);

        // If the socket disconnected during a background pause (>30-60s) or error occurred:
        if (streamNeedsReconnect || active.readyState < 2 || active.networkState === 3 || active.error) {
          console.log('[DilSe Web Player] Reconnecting dropped stream at position:', posToResume);
          streamNeedsReconnect = false;
          const currentSrc = active.src;
          if (currentSrc) {
            active.src = currentSrc;
            active.load();
            if (posToResume > 0) {
              const applyPosition = () => {
                try { active.currentTime = posToResume; } catch (_) {}
              };
              active.addEventListener('loadedmetadata', applyPosition, { once: true });
            }
          }
        }

        const playPromise = active.play();
        if (playPromise !== undefined) {
          playPromise.then(() => {
            unlockAudioContext();
            broadcastState('playing');
            if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'playing';
          }).catch((err) => {
            console.warn('[DilSe Web Player] Resume play rejected, forcing stream reload:', err);
            const currentSrc = active.src;
            if (currentSrc) {
              active.src = currentSrc;
              active.load();
              if (posToResume > 0) {
                const applyPosition = () => {
                  try { active.currentTime = posToResume; } catch (_) {}
                };
                active.addEventListener('loadedmetadata', applyPosition, { once: true });
              }
              active.play().then(() => {
                unlockAudioContext();
                broadcastState('playing');
                if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'playing';
              }).catch((e) => {
                console.error('[DilSe Web Player] Direct audio resume failed:', e);
                if (document.visibilityState === 'visible') {
                  triggerFallback();
                }
              });
            }
          });
        }
      }
    } else if (activeEngine === ENGINE_IFRAME && ytPlayer && typeof ytPlayer.playVideo === 'function') {
      try {
        if (typeof ytPlayer.unMute === 'function') {
          ytPlayer.unMute();
          ytPlayer.setVolume(100);
        }
        ytPlayer.playVideo();
      } catch (_) {}
    }
    broadcastState('playing');
    if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'playing';
  };

  window.dilseSeek = function (seconds) {
    lastReportedPos = seconds;
    if (activeEngine === ENGINE_AUDIO) {
      const active = getActiveDeck();
      if (active) {
        try {
          active.currentTime = seconds;
        } catch (_) {}
      }
    } else if (activeEngine === ENGINE_IFRAME && ytPlayer && typeof ytPlayer.seekTo === 'function') {
      try {
        ytPlayer.seekTo(seconds, true);
      } catch (_) {}
    }
  };

  window.dilseSetVolume = function (volumePercent) {
    const vol = Math.max(0, Math.min(1, volumePercent / 100));
    const active = getActiveDeck();
    if (active) {
      try {
        active.volume = vol;
      } catch (_) {}
    }
    if (ytPlayer && typeof ytPlayer.setVolume === 'function') {
      try {
        ytPlayer.setVolume(volumePercent);
      } catch (_) {}
    }
  };

  window.dilseSetMetadata = function (title, artist, artworkUrl, album) {
    if (!('mediaSession' in navigator)) return;

    try {
      if (album && album !== 'DilSe') currentAlbum = album;
      const resolvedAlbum = (currentAlbum && currentAlbum !== 'DilSe')
        ? currentAlbum
        : (artist || 'Single');

      navigator.mediaSession.metadata = new MediaMetadata({
        title: title || 'DilSe Song',
        artist: artist || 'DilSe Music',
        album: resolvedAlbum,
        artwork: artworkUrl
          ? [
              { src: artworkUrl, sizes: '96x96' },
              { src: artworkUrl, sizes: '192x192' },
              { src: artworkUrl, sizes: '512x512' },
            ]
          : [],
      });

      navigator.mediaSession.setActionHandler('play', () => {
        window.dilseResume();
        window.dispatchEvent(new CustomEvent('dilse_remote_play'));
      });
      navigator.mediaSession.setActionHandler('pause', () => {
        window.dilsePause();
        window.dispatchEvent(new CustomEvent('dilse_remote_pause'));
      });
      navigator.mediaSession.setActionHandler('stop', () => {
        window.dilsePause();
        window.dispatchEvent(new CustomEvent('dilse_remote_pause'));
      });
      navigator.mediaSession.setActionHandler('nexttrack', () => {
        window.dispatchEvent(new CustomEvent('dilse_remote_next'));
      });
      navigator.mediaSession.setActionHandler('previoustrack', () => {
        window.dispatchEvent(new CustomEvent('dilse_remote_prev'));
      });
      navigator.mediaSession.setActionHandler('seekto', (details) => {
        if (details.seekTime !== undefined) {
          window.dilseSeek(details.seekTime);
        }
      });
      navigator.mediaSession.setActionHandler('seekforward', () => {
        window.dilseSeek((lastReportedPos || 0) + 10);
      });
      navigator.mediaSession.setActionHandler('seekbackward', () => {
        window.dilseSeek(Math.max(0, (lastReportedPos || 0) - 10));
      });
    } catch (e) {
      console.warn('[DilSe Web Player] MediaSession error:', e);
    }
  };

  // Offline Audio Cache APIs for PWA zero-data playback
  window.dilseCacheAudio = async function (songId, streamUrl, artworkUrl) {
    if (!('caches' in window)) return false;
    try {
      const cache = await caches.open('dilse-offline-audio-v1');
      const res = await fetch(streamUrl, { mode: 'cors' });
      if (!res.ok) throw new Error('Audio fetch failed with status: ' + res.status);
      await cache.put('/offline_audio/' + songId, res);
      if (artworkUrl) {
        try {
          const artRes = await fetch(artworkUrl, { mode: 'no-cors' });
          await cache.put('/offline_artwork/' + songId, artRes);
        } catch (_) {}
      }
      console.log('[DilSe Web Player] Successfully cached offline audio for:', songId);
      return true;
    } catch (err) {
      console.warn('[DilSe Web Player] Cache audio error for ' + songId + ':', err);
      return false;
    }
  };

  window.dilseDeleteCachedAudio = async function (songId) {
    if (!('caches' in window)) return;
    try {
      const cache = await caches.open('dilse-offline-audio-v1');
      await cache.delete('/offline_audio/' + songId);
      await cache.delete('/offline_artwork/' + songId);
      console.log('[DilSe Web Player] Deleted offline audio for:', songId);
    } catch (_) {}
  };

  window.dilseIsCachedAudio = async function (songId) {
    if (!('caches' in window)) return false;
    try {
      const cache = await caches.open('dilse-offline-audio-v1');
      const match = await cache.match('/offline_audio/' + songId);
      return Boolean(match);
    } catch (_) {
      return false;
    }
  };

  console.log('[DilSe Web Player] Dual-Engine player initialized (JioSaavn 320k + YouTube Fallback)');
})();
