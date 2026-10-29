# DilSe Music — Lead Architect Instructions & Master Governance

This workspace operates under the **Architectural Immutability + UI Transformation Master Directive** and `DILSE_ARCHITECTURAL_SPECIFICATION.md` (v3.8.0+22 @ commit `e95af07`).

---

## 1. Prime Directive: Presentation Freedom vs. Architectural Immutability

```text
┌────────────────────────────────────────────────────────────────────┐
│ ZONE A — PRESENTATION (FULL AUTHORITY)                             │
│ Flutter widgets, layouts, animations, desktop shell, sidebars,     │
│ panels, cards, navigation, interaction, styling, design tokens.    │
└───────────────────────────────┬────────────────────────────────────┘
                                │ PUBLIC CONTRACTS ONLY
                                ▼
┌────────────────────────────────────────────────────────────────────┐
│ ZONE B — APPLICATION SERVICES (CONTROLLED)                         │
│ Existing service interfaces, state abstractions, navigation models. │
└───────────────────────────────┬────────────────────────────────────┘
                                │
                                ▼
┌────────────────────────────────────────────────────────────────────┐
│ ZONE C — CORE ENGINE (ARCHITECTURALLY IMMUTABLE)                   │
│ MusicService, _playerA, _playerB, dual-deck crossfade, stream      │
│ resolution cascade, queue semantics, persistence, lyrics engine.  │
└───────────────────────────────┬────────────────────────────────────┘
                                │
                                ▼
┌────────────────────────────────────────────────────────────────────┐
│ ZONE D — INFRASTRUCTURE (STRICTLY PROTECTED)                       │
│ Cloudflare Edge Worker, JioSaavn CDN, YouTubeExplode, InnerTube,   │
│ background audio services, platform audio drivers.                 │
└────────────────────────────────────────────────────────────────────┘
```

---

## 2. Eight Absolute Architectural Invariants

1. **Rule #1: Audio Engine Immutability**  
   - Never rewrite `MusicService`, `_playerA`, `_playerB`, active/standby deck swapping, equal-power crossfade mathematics, or stream cascades to make UI code easier.
   - Never introduce UI-driven audio timers, duplicate playback clocks, or direct player backdoors.
   - The UI must *consume* the audio engine; the UI must *never become* the audio engine.

2. **Rule #2: Cloudflare Edge Immutability**  
   - Cloudflare Worker endpoints (`dilse-edge-stream.workers.dev`), DES-ECB stream decryption, and direct CDN streaming are protected infrastructure boundaries.
   - Never introduce a new backend or proxy audio through custom servers.

3. **Rule #3: YouTube Engine Immutability**  
   - YouTube fallback cascade (Format 18 $\to$ Opus 251 $\to$ AudioOnly 140 $\to$ InnerTube) is protected.
   - Never replace `YoutubeExplode` or move YouTube stream resolution into widgets.

4. **Rule #4: Data & Identity Integrity**  
   - `CanonicalSongDedup` is the single source of truth for song identification.
   - Never create secondary song IDs or replace canonical matching with presentation strings.

5. **Rule #5: Single Source of Truth**  
   - Never duplicate playback, queue, position, library, or playlist state. UI state is strictly permitted for presentation concerns only (`sidebarWidth`, `isCollapsed`, `hoverIndex`, `contextTab`).

6. **Rule #6: No Backdoors**  
   - Widgets must interact exclusively through existing public service abstractions.

7. **Rule #7: Sovereign Bootstrap & Recovery Invariant (Zero-Black-Screen Guarantee)**  
   - `main()` must NEVER await unguarded native plugins, audio hardware drivers, or remote network services before calling `runApp()`. The Flutter framework must render its initial frame unconditionally.
   - The Bootstrap & Emergency Recovery layer (Splash, Settings, Updates, Version Rollback, Data Snapshots) must remain completely decoupled and independent from `MusicService`, audio sessions, platform equalizer effects, and remote catalogs.
   - If the core UI or audio engine encounters an unhandled exception or fails to mount, the app must activate a lightweight, engine-independent Safe Mode / Recovery Shell. Users must never be trapped on a dead screen and must always have access to:
     - Version rollback to any prior release (`UpdateService.fetchAllReleases()`).
     - Checking and installing hotfix updates (`UpdateService.checkForUpdate()`).
     - Emergency snapshot backup & restore (`DataSnapshotService`).
     - Resetting corrupt transient caches without wiping offline downloads or custom playlists.

8. **Rule #8: Release Build & ProGuard Verification Gate**  
   - Whenever dependencies in `pubspec.yaml` or `pubspec.lock` are upgraded (especially native plugins like `shared_preferences`, `path_provider`, `just_audio`), or whenever Android/iOS platform configurations are modified, a release compilation (`flutter build apk --release`) is mandatory before creating a git tag or publishing a release.
   - Release APK builds verify that R8 code shrinking, bytecode obfuscation, JNI bindings, and ProGuard keep rules do not silently strip classes required at runtime.

---

## 3. Mandatory Architecture Change Ledger

Every phase and task must maintain the **Architecture Change Ledger**:

```text
ARCHITECTURE CHANGE LEDGER
File:
Change:
Reason:
Layer: (Zone A / Zone B / Zone C / Zone D)
Existing abstraction reused:
Audio impact: NONE
Cloudflare impact: NONE
YouTube impact: NONE
Persistence impact: NONE
Mobile impact:
Web impact:
Lifecycle impact:
Tests affected:
New dependency: NONE
Architectural approval required: NO
```

### Architectural Touch Intercept Protocol:
If a task ever proposes modifying protected files:
- `lib/services/music_service.dart`
- `lib/services/api_config.dart`
- `lib/services/audio_handler.dart`
- `web/dilse_web_player.js`
- `lib/services/canonical_song_dedup.dart`
- `lib/services/data_snapshot_service.dart`

The agent **MUST STOP IMPLEMENTATION**, explain why, prove that a presentation-only solution is impossible, and request explicit user approval before writing any code.

---

## 4. Verification Quality Gate (Mandatory on Every Step)

```bash
dart format lib/ test/       # Must yield 0 changed files
flutter analyze lib/         # Must yield 0 errors, 0 warnings, 0 infos
flutter test                 # Must pass 100% of tests (currently 443/443)
git checkout -- linux/ macos/ windows/ # Clean transient platform files

# Mandatory whenever dependencies or platform build configs are modified:
flutter build apk --release  # Must compile successfully with R8 shrinking
```

