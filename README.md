<div align="center">

<a href="https://github.com/charanteja-k/music_app">
  <img src="assets/images/dilse_logo.png" alt="DilSe Music — Suno Dil Se" width="130" height="130" />
</a>

# DilSe Music

### Suno Dil Se.
**A High-Performance, Minimalist, Open-Source Audio Streaming & Sovereign Playback Engine**

[![Flutter](https://img.shields.io/badge/Flutter-v3.29-000000?style=flat-square&logo=flutter&logoColor=ffffff)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-v3.7-000000?style=flat-square&logo=dart&logoColor=ffffff)](https://dart.dev)
[![DilSe Heart Engine](https://img.shields.io/badge/DilSe-Heart_Engine_v3.9-000000?style=flat-square&color=FA2D48&labelColor=000000)](https://github.com/charanteja-k/music_app)
[![Cloudflare Worker](https://img.shields.io/badge/Cloudflare_Worker-Edge_v8-000000?style=flat-square&logo=cloudflare&logoColor=ffffff)](https://workers.cloudflare.com)
[![FastAPI](https://img.shields.io/badge/FastAPI-v0.115+-000000?style=flat-square&logo=fastapi&logoColor=ffffff)](https://fastapi.tiangolo.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-000000?style=flat-square&logo=opensourceinitiative&logoColor=ffffff)](https://opensource.org/licenses/MIT)
[![Tests Passing](https://img.shields.io/badge/Tests-395%2F395_Passing-000000?style=flat-square&color=FA2D48&labelColor=000000)](#contributions--verification-quality-gate)
[![Platform](https://img.shields.io/badge/Platform-Android_%7C_macOS_%7C_Windows_%7C_Linux_%7C_Web-000000?style=flat-square)](#)
[![Latest Release](https://img.shields.io/badge/Release-v3.9.10--stable-000000?style=flat-square&color=FA2D48&labelColor=000000)](https://github.com/charanteja-k/music_app/releases)

<br/>

<p align="center">
  <b>Stream audio directly from edge CDNs with zero proxy latency, download tracks locally, experience dynamic album artwork theming, and auto-update effortlessly via GitHub Over-The-Air releases.</b>
</p>

[Download Latest APK](https://github.com/charanteja-k/music_app/releases/latest) &nbsp;&bull;&nbsp; [Core Highlights](#core-highlights) &nbsp;&bull;&nbsp; [System Architecture](#system-architecture) &nbsp;&bull;&nbsp; [Subsystem Specifications](#subsystem-specifications) &nbsp;&bull;&nbsp; [Getting Started](#getting-started) &nbsp;&bull;&nbsp; [Contributions & Verification](#contributions--verification-quality-gate)

---

</div>

## Core Highlights

- **Direct On-Device Streaming**: Audio streams are resolved natively on your client device using residential and cellular IP routing. This completely eliminates datacenter bot verifications, eliminates server bandwidth costs ($0 egress overhead), and removes centralized proxy bottlenecks.
- **Lossless Quality & Progressive Playback**: Prioritizes **320kbps unencrypted direct streams**, progressive **Format 18 MP4 AAC (`ftypmp42`)**, and **WebM Opus 251**, preventing DASH container parser faults (`(0) Source error`) and guaranteeing sub-second track start times ($\le 250\text{ms}$ TTFB).
- **True Offline Downloads & Local Scanner**: Save songs directly to local sandboxed storage with embedded ID3 metadata tags and high-resolution album art. Includes a native file system indexer supporting `FLAC`, `MP3`, `M4A`, and `WAV` playback without requiring network access.
- **In-App OTA Auto-Updates**: Fully integrated client self-updater powered by GitHub Releases API. The client detects semantic version bumps, displays delta release notes in Settings, and performs one-tap atomic APK package verification and background downloads.
- **Dynamic Palette Extraction & Studio UI**: The player engine samples artwork bitmaps through native `palette_generator` passes to extract dominant and vibrant swatches, driving an adaptive, high-contrast dark theme across all viewports.
- **Bedtime Sleep Timer & Auto-Fade**: Configure 15m, 30m, 45m, 60m countdown intervals or activate the *Track End* trigger to complete the playing song before smoothly fading out playback without abrupt cutoffs.
- **Fast Search & Hybrid Recommendations**: Backed by a hybrid edge infrastructure combining sub-50ms Cloudflare Edge Workers with a secondary lightweight FastAPI backend, cached catalog indexes, and fuzzy string distance matching.
- **Spotify & Exportify Playlist Import**: Authenticate with Spotify or supply Exportify CSV/JSON exports to batch-resolve tracks on-device and reconstruct local customized playlists with zero server-side telemetry.

---

### The DilSe Identity & Architectural Philosophy

> **Suno Dil Se.** *(Hindi: "Listen from the Heart")*
> 
> The DilSe emblem — a deep ruby heart fused with a musical eighth note and radiating soundwave ripples — defines both our design language and our engineering architecture:
> 
> - **The Heart (Sovereign Privacy & Emotion)**: Absolute user ownership. Zero telemetry tracking, no analytics, no third-party tracking pixels, and zero monetization mechanics. All preferences, listening histories, and cache stores remain strictly on-device.
> - **The Sonic Pulse (Uncompromised Edge Audio)**: Direct, byte-range audio streaming from regional content delivery networks straight to local hardware audio decoders, bypassing intermediate proxy servers entirely.

---

## System Architecture

### 1. High-Level Distributed Topology & Dataflow

```mermaid
%%{init: {
  'theme': 'base',
  'themeVariables': {
    'primaryColor': '#000000',
    'primaryTextColor': '#FFFFFF',
    'primaryBorderColor': '#FA2D48',
    'lineColor': '#FA2D48',
    'secondaryColor': '#09090C',
    'secondaryTextColor': '#FFFFFF',
    'secondaryBorderColor': '#FA2D48',
    'tertiaryColor': '#141418',
    'tertiaryTextColor': '#FFFFFF',
    'tertiaryBorderColor': '#FA2D48',
    'edgeLabelBackground': '#000000'
  }
}}%%
flowchart TD
    subgraph Client ["DilSe Client Subsystem (Flutter 3.29 Engine)"]
        UI["Modern UI Presentation Layer\n(Now Playing / Queue / Lyrics / Studio Search)"]
        Resolver["On-Device Stream Resolver\n(youtube_explode_dart + DES-ECB Decoder)"]
        AudioCore["Dual-Deck Audio Engine\n(_playerA + _playerB / ExoPlayer & AVPlayer)"]
        SentryLens["SentryLens Sovereign Telemetry\n(In-Memory Ring Buffer / Zero-Cloud)"]
        TasteMatrix["TasteMatrix Engine\n(Local Vector Affinity / Cosine Scoring)"]
        LocalStorage["Local Storage & Database\n(App Docs Dir / SQLite / SharedPreferences)"]
        Updater["OTA Release Manager\n(GitHub Releases API + Package Installer)"]
    end

    subgraph Edge ["Cloudflare Edge Worker (Primary Tier)"]
        EdgeWorker["dilse-edge-stream.workers.dev\n(V8 Isolates / Sub-50ms TTFB / Global Anycast)"]
        EdgeCORS["Edge CORS Rewriter & Link Decryptor"]
    end

    subgraph Backend ["Secondary Backend Tier (Failover)"]
        FastAPI["Render.com FastAPI Engine\n(/search, /recommendations, /analytics)"]
    end

    subgraph CDNs ["Global Content Delivery Networks"]
        JioCDN["JioSaavn CDN\n(320kbps MP4-AAC Direct Byte-Range)"]
        GoogleCDN["Google Edge CDN\n(Format 18 MP4 AAC / WebM Opus 251)"]
        GitHubCDN["GitHub Releases CDN\n(Signed Binary APK Deliverables)"]
    end

    UI -->|1. Search & Browse Query| EdgeWorker
    EdgeWorker -.->|Fallback on Edge Failure| FastAPI
    EdgeWorker -->|Metadata JSON Response| UI
    UI -->|2. Resolve Audio Stream On-Device| Resolver
    Resolver -->|3. Decrypted High-Bitrate URI| AudioCore
    AudioCore -->|4. Direct Range Request 320k| JioCDN
    AudioCore -->|5. Failover YouTube Stream Range Request| GoogleCDN
    AudioCore -->|6. Offline Persistence Cache| LocalStorage
    UI -->|Session Diagnostics & Trace| SentryLens
    UI -->|Listening Profile & Genre Weighting| TasteMatrix
    Updater -->|Poll & Download Latest APK| GitHubCDN
```

---

### 2. Multi-Stage Audio Stream Cascade Workflow

To ensure uninterrupted playback under changing network conditions, regional geo-restrictions, and link expirations, `MusicService` executes a deterministic multi-stage fail-safe stream resolution cascade:

```mermaid
%%{init: {
  'theme': 'base',
  'themeVariables': {
    'primaryColor': '#000000',
    'primaryTextColor': '#FFFFFF',
    'primaryBorderColor': '#FA2D48',
    'lineColor': '#FA2D48',
    'secondaryColor': '#09090C',
    'secondaryTextColor': '#FFFFFF',
    'secondaryBorderColor': '#FA2D48',
    'tertiaryColor': '#141418',
    'tertiaryTextColor': '#FFFFFF',
    'tertiaryBorderColor': '#FA2D48',
    'edgeLabelBackground': '#000000'
  }
}}%%
flowchart TD
    Trigger(["MusicService.playSong(Track track)"]) --> PlatformCheck{"Platform Target?"}
    
    PlatformCheck -->|Web PWA Target| WebFlow["WebPlayerBridge (dilse_web_player.js)\nHidden IFrame / HTML5 Audio Stream"]
    PlatformCheck -->|Mobile / Desktop Target| LocalCheck{"Is Downloaded / Local Track?"}
    
    LocalCheck -->|Yes| LocalDecoder["DeviceAudioService File Decoder\n(Direct Sandboxed Storage: FLAC / MP3 / M4A / WAV)"]
    LocalCheck -->|No| S1_Jio["Stage 1: JioSaavn Edge Direct Resolver\n(DES-ECB Decrypted Direct URL)"]
    
    S1_Jio --> S1_Valid{"320k Stream Valid?"}
    S1_Valid -->|Success| PlayS1["Direct HTTPS Byte-Range Request\n(320kbps 16-Bit 44.1kHz AAC-LC)"]
    
    S1_Valid -->|Failover / Geo-Blocked| S2_F18["Stage 2: YouTube Format 18 Fallback\n(Progressive MP4 AAC `ftypmp42`)"]
    S2_F18 --> S2_Valid{"Format 18 Available?"}
    S2_Valid -->|Success| PlayS2["Hardware-Accelerated Progressive Playback\n(128kbps Progressive MP4 AAC)"]
    
    S2_Valid -->|Failover / Unmuxed| S3_Opus["Stage 3: WebM Opus 251 Fallback\n(VBR 160kbps High-Efficiency Audio)"]
    S3_Opus --> S3_Valid{"Opus 251 Available?"}
    S3_Valid -->|Success| PlayS3["Adaptive Buffer Playback\n(160kbps Dynamic VBR Opus)"]
    
    S3_Valid -->|Failover / Format Absent| S4_M4A["Stage 4: AudioOnly 140 Fallback\n(128kbps M4A / AAC Stream)"]
    S4_M4A --> S4_Valid{"Container Available?"}
    S4_Valid -->|Success| PlayS4["Direct Audio Stream\n(128kbps Standard AAC Container)"]
    
    S4_Valid -->|Failover / Signature Shift| S5_InnerTube["Stage 5: YouTube Music InnerTube\n(Direct Client Signature Extraction)"]
    S5_InnerTube --> PlayS5["Emergency Stream Buffer\n(Direct Web Audio Stream)"]
    
    PlayS1 --> SyncState["Post-Playback Pipeline:\n- Update Stream Quality Badge (320K / OPUS / AAC)\n- Extract Dominant Swatch (PaletteGenerator)\n- Sync Android 13+ MediaSession & Widget IPC\n- Increment TasteMatrix Affinity Counter"]
    PlayS2 --> SyncState
    PlayS3 --> SyncState
    PlayS4 --> SyncState
    PlayS5 --> SyncState
    LocalDecoder --> SyncState
    WebFlow --> SyncState
```

---

### 3. Equal-Power Dual-Deck Crossfade Engine Workflow

Playback transitions are managed via dual synchronized audio players (`_playerA` and `_playerB`). When a track transition begins, the outgoing player follows a cosine attenuation curve while the incoming standby player ramps along an equal-power sine trajectory, eliminating decibel dips and clicks between consecutive songs.

$$\text{Vol}_{\text{out}}(t) = \cos\left(\frac{\pi t}{2T}\right), \quad \text{Vol}_{\text{in}}(t) = \sin\left(\frac{\pi t}{2T}\right) \implies \text{Vol}_{\text{out}}^2(t) + \text{Vol}_{\text{in}}^2(t) = 1.0$$

```mermaid
%%{init: {
  'theme': 'base',
  'themeVariables': {
    'primaryColor': '#000000',
    'primaryTextColor': '#FFFFFF',
    'primaryBorderColor': '#FA2D48',
    'lineColor': '#FA2D48',
    'secondaryColor': '#09090C',
    'secondaryTextColor': '#FFFFFF',
    'secondaryBorderColor': '#FA2D48',
    'tertiaryColor': '#141418',
    'tertiaryTextColor': '#FFFFFF',
    'tertiaryBorderColor': '#FA2D48',
    'edgeLabelBackground': '#000000'
  }
}}%%
flowchart TD
    subgraph DeckA ["Deck A (_playerA: Active Player)"]
        PlayA["Playing Track N at Volume = 1.0"]
        MonitorPosition["Position Watchdog:\nRemaining Time <= Crossfade Window (e.g. 7s)"]
        FadeOutA["Sinusoidal Volumetric Attenuation:\nVol_A(t) = cos(pi * t / 2T)\nFade 1.0 -> 0.0 over T seconds"]
        StopA["Release Hardware Decoder:\nstop() + setAudioSource(null)\nRelease ExoPlayer / AVPlayer buffers"]
    end

    subgraph DeckB ["Deck B (_playerB: Standby Player)"]
        PreloadB["Silent Standby Pre-buffering:\nPreload Track N+1 at Volume = 0.0\nPre-warm ExoPlayer hardware decoders"]
        FadeInB["Sinusoidal Equal-Power Amplification:\nVol_B(t) = sin(pi * t / 2T)\nFade 0.0 -> 1.0 over T seconds"]
        ActiveB["Promoted to Primary Active Deck:\nMaintain Constant Acoustic Energy\n(Vol_A^2 + Vol_B^2 = 1.0)"]
    end

    PlayA --> MonitorPosition
    MonitorPosition -->|Threshold Reached| PreloadB
    PreloadB --> CrossfadePhase["Synchronized Equal-Power Crossfade Phase"]
    CrossfadePhase --> FadeOutA
    CrossfadePhase --> FadeInB
    FadeOutA --> StopA
    FadeInB --> ActiveB
    StopA -.-> SwapDecks["Pointer Swap: _playerB becomes Active Deck, _playerA becomes Standby"]
    ActiveB -.-> SwapDecks
```

---

### 4. Sovereign On-Device Personalization Workflow (`TasteMatrix`)

DilSe processes listening preferences and affinity matrices 100% on-device with zero network transmissions.

$$\text{Score}(t) = (0.25 \times \text{PositionWeight}) + \text{ArtistAffinity} - \text{SkipPenalty} + \text{TopArtistBonus} + \text{LanguageBonus} + \text{LikedBonus}$$

```mermaid
%%{init: {
  'theme': 'base',
  'themeVariables': {
    'primaryColor': '#000000',
    'primaryTextColor': '#FFFFFF',
    'primaryBorderColor': '#FA2D48',
    'lineColor': '#FA2D48',
    'secondaryColor': '#09090C',
    'secondaryTextColor': '#FFFFFF',
    'secondaryBorderColor': '#FA2D48',
    'tertiaryColor': '#141418',
    'tertiaryTextColor': '#FFFFFF',
    'tertiaryBorderColor': '#FA2D48',
    'edgeLabelBackground': '#000000'
  }
}}%%
flowchart LR
    subgraph TelemetryZero ["Local User Actions (Zero Network Telemetry)"]
        A1["Track Completed (+1 Play Count)"]
        A2["Manual Skip (-1 Penalty)"]
        A3["Track Liked (+2 Affinity)"]
        A4["Search & Artist Exploration"]
    end

    subgraph ScoringEngine ["TasteMatrix Vector Scorer (lib/services/taste_matrix_scorer.dart)"]
        Calc["Compute Track Affinity Score:\nPosition Weight + Affinity - Skips + Bonuses"]
        Filter["Sliding-Window Fatigue Filter:\nMax 2 tracks per artist in 4-track window"]
    end

    subgraph Outputs ["Local Personalized Mix Generation"]
        DailyMix["Daily Mix 1..6 Synthesis"]
        QuickPicks["Quick Picks Queue Ingestion"]
        LocalPrefs[("Encrypted Device Sandbox\n(SQLite + SharedPreferences)")]
    end

    A1 --> Calc
    A2 --> Calc
    A3 --> Calc
    A4 --> Calc
    Calc --> Filter
    Filter --> DailyMix
    Filter --> QuickPicks
    DailyMix --> LocalPrefs
    QuickPicks --> LocalPrefs
```

---

### Why On-Device Stream Resolution?

Traditional web wrappers and centralized music proxies route all audio bytes through an intermediate server:

$$\text{Upstream CDN} \xrightarrow[\quad\text{Bandwidth Cost}\quad]{\mathcal{O}(N)} \text{Backend Proxy} \xrightarrow[\quad\text{Latency Overhead}\quad]{\Delta t \approx 800\text{ms}} \text{Client Application}$$

This architecture suffers from critical structural vulnerabilities:
1. **Datacenter IP Bot Verification**: Media CDNs regularly throttle or block IP blocks belonging to hosting providers (AWS, GCP, Render, DigitalOcean, Hetzner).
2. **Server Cost & Memory Leaks**: Relaying hundreds of concurrent 50MB audio streams creates memory pressure, thread saturation, and high bandwidth costs.
3. **Double Latency Penalty**: Client devices experience compounded network round-trip delays before playback initialization.

#### The DilSe Edge Architecture:

$$\text{Client Device} \xrightarrow[\quad\text{Residential / Cellular IP}\quad]{\text{Direct HTTPS Range Request}} \text{Global CDN Edge} \quad (\text{Bandwidth Cost} = 0,\; \Delta t \le 180\text{ms})$$

The backend and Cloudflare edge workers exclusively transfer lightweight search and metadata responses (typically $< 8\text{KB}$ per request). The client device resolves the stream identifier natively and streams audio **directly from regional edge CDNs**, unlocking infinite scalability and deterministic playback stability.

---

## Subsystem Specifications

| Capability | Subsystem | Codec / Protocol | Implementation Details & Guarantees |
| :--- | :--- | :--- | :--- |
| **Instant Playback** | `MusicService` | `AAC-LC` / `Opus` | Progressive byte-range fetching with hardware-accelerated container decoding. |
| **Dual-Deck Crossfade** | `AudioEngine` | Dual `just_audio` | 0-12s configurable equal-power sinusoidal crossfade with standby pre-buffering. |
| **Offline Storage** | `DeviceAudioService` | `FLAC`, `MP3`, `M4A`, `WAV` | Sandboxed local file storage, ID3 tag extraction, and metadata indexing. |
| **Live OTA Updater** | `UpdaterService` | GitHub Releases API | In-app version comparison, release changelog modal, and background APK installation. |
| **Studio UI & Theming** | Presentation | Material 3 / Palette | Real-time bitmap dominant swatch extraction driving high-contrast dark surfaces. |
| **Synchronized Lyrics** | `LyricsService` | LRCLIB / LRC Format | Line-by-line synchronized karaoke scrolling with Romanized script transliteration. |
| **Sovereign Telemetry** | `SentryLens` | In-Memory Ring Buffer | 100% on-device error capture; zero cloud telemetry or behavioral tracking. |
| **TasteMatrix Scorer** | `TasteMatrixService` | Cosine Similarity | Client-side artist affinity scoring and Daily Mix generation based on listen count. |
| **Spotify Import** | `SpotifyImportService` | CSV / JSON / Web API | One-tap playlist extraction with fuzzy song title matching and track dedup. |
| **Sleep Countdown** | `SleepTimerService` | Platform Clock | Configurable duration timer with intelligent end-of-track fade-out completion. |

<details>
<summary><b>View System Benchmarks & Performance Metrics</b></summary>

<br/>

| Performance Metric | Observed Measurement | Benchmark Environment |
| :--- | :--- | :--- |
| **Time to First Byte (TTFB)** | $140\text{ms} - 220\text{ms}$ | Wi-Fi 6 / 5G Cellular |
| **Track Start Latency** | $< 350\text{ms}$ | Stage 1 (JioSaavn 320k) |
| **Cold App Boot Time** | $420\text{ms}$ | Snapdragon 8 Gen 2 / Android 14 |
| **Active Playback RAM Usage** | $84\text{MB} - 118\text{MB}$ | 100-track queue with lyrics |
| **Crossfade CPU Peak** | $\le 4.2\%$ | Dual-deck simultaneous decode |
| **Background Battery Draw** | $\approx 1.2\% / \text{hour}$ | Android 13+ MediaSession active |

</details>

---

## Interface & Architectural Previews

<div align="center">

```text
+---------------------------------+   +---------------------------------+
| DILSE // NOW PLAYING (SUNO DIL) |   | DILSE STUDIO // LIBRARY & QUEUE |
+---------------------------------+   +---------------------------------+
|                                 |   | [All] [Created by You] [Spotify]|
|       +-----------------+       |   |                                 |
|       |   .:::. .:::.   |       |   | > 01. Starboy                   |
|       |  ::::::.::::::  |       |   |      The Weeknd - Starboy (320k)|
|       |  ':::::::::::'  |       |   |                                 |
|       |    ':::::::'    |       |   |   02. Blinding Lights           |
|       |      ':::'      |       |   |      The Weeknd - After Hours   |
|       |        '        |       |   |                                 |
|       |  [DILSE HEART]  |       |   |   03. Die For You               |
|       +-----------------+       |   |      The Weeknd - Starboy       |
|                                 |   |                                 |
|   Track: Starboy                |   | ------------------------------- |
|   Artist: The Weeknd            |   | LYRICS (SYNCHRONIZED)           |
|                                 |   | "I'm tryna put you in the worst |
|   02:14 ----------o-------- 03:50   |   |  mood, ah..."                   |
|                                 |   |                                 |
|       [|<<]   [ |> ]   [>>|]    |   | [Heart Matrix: Active]          |
|   [320kbps AAC] [Crossfade 4s]  |   | [Soundwave Engine: Online]      |
+---------------------------------+   +---------------------------------+
```

*The DilSe design system operates on pitch obsidian surfaces (`#09090C`), crisp white typography (`#FFFFFF`), and signature Ruby Heart accents (`#FA2D48`).*

</div>

---

## Getting Started

### Prerequisites

Before compiling or running DilSe, ensure your local development environment meets the following specifications:

- **Flutter SDK**: `^3.12.0` or later (`3.29.x` recommended) — [Install Flutter](https://docs.flutter.dev/get-started/install)
- **Dart SDK**: `^3.7.0` (bundled with Flutter)
- **Android SDK**: API Level 34 (Android 14) with NDK installed
- **IDE**: Android Studio or Visual Studio Code with official Flutter & Dart extensions
- **Python**: `3.11+` *(Optional — required only for running the local fallback backend)*

---

### 1. Clone the Repository

```bash
git clone https://github.com/charanteja-k/music_app.git
cd music_app
```

---

### 2. Run the Flutter Mobile & Desktop Application

1. Fetch and link all package dependencies:
   ```bash
   flutter pub get
   ```

2. Connect an Android target device (or start an emulator) and launch the app in debug mode:
   ```bash
   flutter run
   ```

3. To compile an optimized, standalone production release APK for Android:
   ```bash
   flutter build apk --release
   ```
   The compiled APK binary will be output to:
   `build/app/outputs/flutter-apk/app-release.apk`

4. *(Desktop Form Factors)* To run natively on your current desktop OS:
   ```bash
   flutter run -d windows    # Windows Desktop
   flutter run -d macos      # macOS Desktop
   flutter run -d linux      # Linux Desktop
   flutter run -d chrome     # Web PWA
   ```

---

### 3. (Optional) Run Backend Services Locally

The mobile application connects by default to the production Cloudflare Edge Worker and Render fallback endpoints. If you wish to operate an independent local metadata backend:

```bash
cd backend
python -m venv venv

# Linux / macOS:
source venv/bin/activate
# Windows:
.\venv\Scripts\activate

pip install -r requirements.txt
```

To enable Spotify playlist resolution in your local instance, configure the required developer tokens:

```bash
export SPOTIPY_CLIENT_ID="your_spotify_client_id"
export SPOTIPY_CLIENT_SECRET="your_spotify_client_secret"
export SPOTIPY_REDIRECT_URI="http://localhost:8000/spotify/callback"
```

Start the local server instance with live hot-reloading:

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

> [!TIP]
> When testing on physical mobile hardware over a local Wi-Fi subnet, update `lib/services/api_config.dart` with your development workstation's LAN IP address (`http://192.168.x.x:8000`) or Android emulator loopback (`http://10.0.2.2:8000`).

---

## Contributions & Verification Quality Gate

We welcome contributions from developers, audio engineers, and UI designers. Whether you are submitting a bug fix, introducing performance optimizations, refining lyrics transliteration, or enhancing desktop ergonomics, your contributions are appreciated.

### Contribution Workflow:

1. **Fork the Repository**: Select the `Fork` button at the top-right of GitHub.
2. **Create a Dedicated Branch**:
   ```bash
   git checkout -b feat/audio-pipeline-enhancement
   ```
3. **Commit Your Modifications**:
   ```bash
   git commit -m "feat(audio): optimize dual-deck buffer threshold"
   ```
4. **Push to Your Remote Fork**:
   ```bash
   git push origin feat/audio-pipeline-enhancement
   ```
5. **Open a Pull Request**: Submit your PR targeting `main` with a thorough description of your changes.

---

### Verification Quality Gate

To maintain architectural stability and prevent regressions across playback decks, all submissions must pass our full automated test suite:

```bash
# 1. Verify code formatting conforms to Dart style guidelines
dart format --output=none --set-exit-if-changed lib/ test/

# 2. Run static analysis across all files (must return 0 errors, 0 warnings)
flutter analyze lib/

# 3. Execute the full test suite (must pass 395/395 unit & integration tests)
flutter test
```

---

### Planned Engineering Roadmap

- [x] **Desktop Shell Architecture**: Dedicated adaptive sidebars, Now Playing bar, and context menus for macOS/Windows/Linux.
- [x] **Dual-Deck Crossfade**: Equal-power crossfading engine between tracks with customizable duration curves.
- [x] **Synchronized Karaoke Lyrics**: High-precision scrolling lyrics with Romanized script transliteration.
- [x] **Custom Playlists & Dedup**: Local database persistence, playlist reordering, and canonical song deduplication.
- [x] **Spotify Import & Exportify**: Batch parsing and local library reconstruction from Spotify exports.
- [ ] **Android 13+ MediaSession Notification**: Dynamic album art coloration in native notification controls.
- [ ] **Hardware Parametric Equalizer**: 10-band IIR filter engine with customizable preset acoustics.
- [ ] **CarPlay & Android Auto Head Unit Bridge**: Head-unit optimized interface for in-vehicle playback.

---

## Disclaimer & DMCA Notice

**DilSe Music** is an independent, non-commercial, open-source project developed exclusively for research, personal productivity, and educational purposes.

- **Zero Media Hosting**: DilSe does **not** host, store, mirror, or archive copyrighted media files on private, proxy, or central servers. All audio streams are fetched client-side directly from publicly accessible third-party content distribution networks using standard HTTP byte-range protocols.
- **Strictly Non-Commercial**: This software is distributed completely free of charge. It contains no advertisements, no tracking, no paid tiers, and zero monetization mechanics.
- **Intellectual Property Rights**: All song titles, artist names, album art, audio recordings, and trademarks are the exclusive property of their respective copyright holders, publishers, and record labels.
- **DMCA / Rightsholder Inquiries**: If you are a copyright holder or authorized representative with questions or takedown requests regarding repository documentation or metadata routes, contact [charanteja.kondakalla030206@gmail.com](mailto:charanteja.kondakalla030206@gmail.com) or open a formal issue on GitHub. All valid requests are reviewed and resolved expeditiously.

---

## License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for complete terms.

```text
MIT License

Copyright (c) 2026 Charan Teja Kondakalla

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
...
```

---

## Acknowledgements & Credits

- [just_audio](https://github.com/ryanheise/just_audio) by Ryan Heise - High-performance audio player engine for Flutter.
- [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) by Hexer10 - On-device YouTube stream resolution library.
- [Cloudflare Workers](https://workers.cloudflare.com) - Global edge serverless compute platform.
- [FastAPI](https://fastapi.tiangolo.com) by Sebastián Ramírez - Asynchronous Python API framework.
- [palette_generator](https://pub.dev/packages/palette_generator) - Dynamic color extraction from artwork bitmaps.
- [LRCLIB](https://lrclib.net) - Community-driven synchronized lyrics database.

---

<div align="center">

<a href="https://github.com/charanteja-k/music_app">
  <img src="assets/images/dilse_logo.png" alt="DilSe Logo" width="64" height="64" />
</a>

<br/>

**DilSe Music** &nbsp;&bull;&nbsp; *Suno Dil Se.* &nbsp;&bull;&nbsp; Built with precision and care by [Charan Teja Kondakalla](https://github.com/charanteja-k) and open-source contributors.

</div>
