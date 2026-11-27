<p align="center">
  <strong>Sielo for iOS</strong>
</p>

<p align="center">
  <strong>A tactile, lossless music streaming app crafted with SwiftUI, AVFoundation &amp; CryptoKit</strong>
</p>

<p align="center">
  🌐 <strong>Official Website</strong>: <a href="https://sielo.site"><strong>sielo.site</strong></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.10-F05138.svg?logo=swift&logoColor=white" alt="Swift" />
  <img src="https://img.shields.io/badge/Platform-iOS%2016%2B-000000.svg?logo=apple&logoColor=white" alt="iOS 16+" />
  <img src="https://img.shields.io/badge/UI-SwiftUI-0A84FF.svg?logo=swift&logoColor=white" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/Audio-AVFoundation%20%2B%20AVAudioEngine-FF6F00.svg" alt="AVFoundation" />
  <img src="https://img.shields.io/badge/Version-v12.0.0-E63946.svg" alt="Version 12.0.0" />
  <a href="https://sielo.site"><img src="https://img.shields.io/badge/Website-sielo.site-0D1B2A.svg?logo=googlechrome&logoColor=white" alt="Website" /></a>
</p>

---

## 🌟 Distinctive & Unique Highlights

**Sielo for iOS** brings 100% feature parity with the Sielo Android edition, tailored with native iOS gestures, interactive backward navigation, and system media controls:

### 1. 👥 End-to-End Encrypted "Listen Together" / Echo (Sub-150ms Sync)
- **Zero-Knowledge P2P Rooms**: Encrypted client-side with **AES-256-GCM** (`CryptoKit`) using `{iv}:{ciphertext+tag}` wire format and `SHA-256` room key derivation, allowing seamless cross-platform rooms between iOS and Android.
- **Clock Drift Compensation**: Periodic `1.0s` host heartbeats and `500ms` guest drift checks (`150ms` soft / `750ms` hard sync) keep playback locked in sync.
- **In-Room Co-Queueing, Live Chat & QR Invites**: Collaborative queue, encrypted chat with swipe-to-reply, `18s` host failover, and `CoreImage` QR code invites.

### 2. 💽 Tactile Vinyl Experience & Native iOS Controls
- **Interactive Vinyl Player**: Spinning vinyl record, 3-page horizontal pager (`Lyrics ↔ Vinyl ↔ Queue`), and smooth vertical **drag-to-dismiss** gesture.
- **Floating Island Mini-Player**: Rotating vinyl disc, live top progress bar, and thumb controls (`Loop`, `Previous`, `Play/Pause`, `Next`, `Mute`).
- **Native iOS Backward Navigation**: Per-tab `NavigationStack`s with interactive **left-edge swipe-back** across Home, Search, Echo, Stats, Profile, Settings, Playlists, and Artist Profiles.
- **Lock Screen & Control Center**: Integrated with `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` (play, pause, seek, skip, like, single-song loop).

### 3. 🧠 Smart Endless Autoplay & Recommendation Engine
- **Hybrid Ranking**: Queries Sielo's `/v1/recommendations` backend and blends with local 3-tier candidate pools (**Pool A ~60% Familiar**, **Pool B ~25% Discovery**, **Pool C ~15% Moderate rotation**).
- **Same-Day Duplicate Shield**: Prevents re-recommending songs already surfaced today (`recommendation_history`).
- **Artist Spacing & Taste Learning**: Enforces `ARTIST_SEPARATION_DISTANCE = 3`, learns from onboarding and `15%` verified plays, and batches listening events to `/v1/events`.

### 4. 📋 Advanced Queue Control & Protected "Play Next"
- **Protected "Play Next" Window**: Manually queued tracks stay in exact order right after the current song even when shuffling.
- **Strict Album & Artist Radio Scopes**: `QueueScope` (`OPEN`, `ALBUM_ONLY`, `ARTIST_ONLY`, `LISTEN_TOGETHER`) preserves album order or replenishes artist radio cleanly.

### 5. 🎚️ Dual-Engine Audio Pipeline & Offline Vault
- **Hybrid Streaming**: Resolves streams from **YouTube / YouTube Music InnerTube** (`ANDROID` + `ANDROID_VR` fallback) and **JioSaavn** (with native `CommonCrypto` DES-ECB-PKCS5 decryption for 320kbps AAC).
- **10-Band Equalizer & Bass Boost**: Powered by `AVAudioUnitEQ` with 11 presets (`Normal`, `Acoustic`, `Bass Boost`, `Classical`, `Dance`, `Electronic`, `Hip Hop`, `Jazz`, `Pop`, `Rock`, `Vocal`).
- **Offline Vault (`Downloaded Cache`)**: Atomic `.tmp` downloads in `Library/Caches/sielo_downloads` with a 512 MB LRU cache and automatic `"Downloaded Cache"` playlist.

### 6. 🎙️ Millisecond-Accurate Lyrics & Transliteration
- **LRCLIB Integration**: 7-strategy search/exact cascade, `[mm:ss.xx]` + `[offset:]` LRC parsing, tap-to-seek, `±0.5s` sync calibration, and `-9700ms` acoustic trim.
- **Script Transliteration**: Automatic Romanization via `CFStringTransform` for Gurmukhi, Devanagari, Hangul, Japanese, Cyrillic, and more.

### 7. 🌌 Listening Universe Stats & Vibe Radar
- **5-Axis Interactive Pentagon Radar**: Measures **Energy**, **Replay**, **Consistency**, **Discovery**, and **Mood** across `1 Week`, `1 Month`, `1 Year`, and `All Time`.
- **On Heavy Repeat & Top Artists**: Powered by local `GRDB` SQLite analytics (`listening_history`).

### 8. ☁️ Cross-Device Cloud Sync & Universal Playlist Importer
- **Firestore Sync**: Syncs `profile`, `library`, `playlists`, `history`, `stats`, `search_history`, `playback` (`activeDeviceId = "ios"`), and `settings` under `sielo_users/{uid}/data/*`.
- **Universal Importer**: Import playlists from **YouTube / YouTube Music**, **Spotify** links, or manual track lists (`Title - Artist`).

---

## 📦 Project Structure

```text
Sielo-iOS/
├── .github/workflows/
│   └── build-ios.yml                # Automated macOS CI build -> Sielo-iOS.ipa
├── project.yml                      # XcodeGen project specification (iOS 16+)
├── Packages/
│   ├── SieloCoreModels/             # Shared Codable models (SieloTrack, PlaybackState, UserProfile, etc.)
│   ├── SieloCoreDatabase/           # GRDB SQLite database (7 tables, DAOs, DatabaseCleaner)
│   ├── SieloCoreNetwork/            # InnerTube, JioSaavn DES crypto, TrackMatchValidator, MusicBrainz, API client
│   ├── SieloCoreAudio/              # PlayerManager (AVPlayer), OfflineCacheManager, AudioEffectsManager, NowPlaying
│   ├── SieloCoreLyrics/             # LrcLibClient + HomophonicTransliterator
│   ├── SieloCoreRecommendations/    # SongClassifier, AutoplayQueueEngine, ListeningEventDispatcher
│   └── SieloCorePlaylistImport/     # YouTube, Spotify & manual paste playlist importer
└── SieloApp/
    ├── App/                         # SieloAppMain, SieloContainer, SieloRootView
    ├── Components/                  # SieloBottomBar, MiniPlayerIsland
    ├── Navigation/                  # SieloRouter (5-tab NavigationStacks + Deep Links)
    ├── Resources/Fonts/             # Macondo, Sora, Urbanist (.ttf)
    ├── Room/                        # ListenTogetherManager, RoomCrypto (AES-256-GCM), Models
    ├── Screens/                     # Home, Search, ListenTogether, Player/Lyrics/Queue, Stats/VibeRadar, Profile, Settings, Playlists, Artist, Auth
    ├── Services/                    # UserManager, CloudSyncManager, SettingsRepository, UserPlaylistsRepository
    └── Theme/                       # SieloColors, SieloTypography, SieloLaunchReveal
```

---

## 🛠️ Tech Stack

- **Language**: Swift 5.10 (`async/await`, `Actor` concurrency, `Combine`)
- **UI**: SwiftUI (`NavigationStack`, `TabView`, `Canvas`)
- **Audio & Media**: `AVFoundation` (`AVPlayer`, `AVAudioSession`, `AVAudioUnitEQ`), `MediaPlayer` (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`)
- **Local Database**: `GRDB.swift` (SQLite)
- **Cloud & Auth**: Firebase Auth, Cloud Firestore, Google Sign-In
- **Real-Time P2P**: `CocoaMQTT` + `CryptoKit` (`AES.GCM`)
- **Typography**: `Sora`, `Urbanist`, `Macondo`

---

## 🚀 Building & Installing on iPhone

### Option A: Automated Build via GitHub Actions (No Mac Required)
1. Push changes to `main` (or trigger **Actions → Build Sielo iOS (.ipa) → Run workflow**).
2. Download the **Sielo-iOS-IPA** artifact and unzip `Sielo-iOS.ipa`.
3. Sideload `Sielo-iOS.ipa` onto your iPhone from Windows using **Sideloadly** or **AltStore**.
4. On iPhone: **Settings → General → VPN & Device Management → Trust** (and enable **Developer Mode** under Privacy & Security).

### Option B: Local Build on macOS
```bash
brew install xcodegen
xcodegen generate
open Sielo.xcodeproj
```
Add your Firebase `GoogleService-Info.plist` to `SieloApp/Resources/`, select your Signing Team in Xcode, and run on your iPhone.
