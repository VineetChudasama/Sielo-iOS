import Foundation
import AVFoundation
import Combine
import MediaPlayer
import SieloCoreModels
import SieloCoreNetwork
import SieloCoreDatabase

/// Mirrors core-audio/PlayerManager.kt with AVPlayer, AVAudioSession, QueueScope,
/// protected Play Next, smart shuffle, 15% play threshold, and Lock Screen controls.
@MainActor
public final class PlayerManager: ObservableObject {
    @Published public private(set) var playbackState = PlaybackState()
    @Published public private(set) var isCurrentTrackFavorite = false
    @Published public private(set) var queueScope: QueueScope = .open

    public var scopeArtistName: String?
    public var playbackSpeed: Float = 1.0
    public var pauseOnDisconnect: Bool = true
    public var rememberPosition: Bool = true
    public var autoplayEnabled: Bool = true

    // Callbacks wired by App / Recommendations
    public var onTrackPlayedTasteListener: ((_ artist: String, _ genre: String) -> Void)?
    public var onListeningEvent: ((_ eventType: String, _ track: SieloTrack, _ positionMs: Int64, _ durationMs: Int64) -> Void)?
    public var userTasteSeedsProvider: (() -> [String])?
    public var autoplayReplenisher: ((_ seed: SieloTrack, _ excludedIds: Set<String>) async -> [SieloTrack])?

    private let database: SieloDatabase
    private let offlineCache = OfflineCacheManager.shared
    private let nowPlaying = NowPlayingController()
    private let prefs = UserDefaults(suiteName: "sielo_player_state") ?? .standard

    private var player = AVPlayer()
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var progressTask: Task<Void, Never>?
    private var favoriteTask: Task<Void, Never>?

    private var playbackGeneration: Int64 = 0
    private var retryAttemptedForCurrentTrack = false
    private var originalQueue: [SieloTrack] = []
    private var currentTrackEventId: Int64?
    private var hasRegisteredPlayForCurrentTrack = false
    private var lastPersistedProgressMs: Int64 = 0
    private var penalizedSongIds: Set<String> = []
    private var favoredSongIds: Set<String> = []

    public init(database: SieloDatabase) {
        self.database = database
        configureAudioSession()
        configureNowPlayingCallbacks()
        observeAudioNotifications()
        restorePersistedState()
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeChangeObserver { NotificationCenter.default.removeObserver(routeChangeObserver) }
    }

    // MARK: - Audio Session & Remote Controls

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            // Audio session activation may fail in background/simulator
        }
    }

    private func configureNowPlayingCallbacks() {
        nowPlaying.onPlay = { [weak self] in self?.play() }
        nowPlaying.onPause = { [weak self] in self?.pause() }
        nowPlaying.onTogglePlayPause = { [weak self] in self?.togglePlayPause() }
        nowPlaying.onNext = { [weak self] in self?.skipNext() }
        nowPlaying.onPrevious = { [weak self] in self?.skipPrevious() }
        nowPlaying.onSeek = { [weak self] ms in self?.seekTo(ms) }
        nowPlaying.onToggleFavorite = { [weak self] in
            Task { await self?.toggleCurrentTrackFavorite() }
        }
        nowPlaying.onToggleLoop = { [weak self] in self?.toggleLoop() }
    }

    private func observeAudioNotifications() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }
            Task { @MainActor [weak self] in
                if type == .began {
                    self?.pause()
                } else if type == .ended,
                          let optVal = info[AVAudioSessionInterruptionOptionKey] as? UInt,
                          AVAudioSession.InterruptionOptions(rawValue: optVal).contains(.shouldResume) {
                    self?.play()
                }
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let info = note.userInfo,
                  let reasonVal = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonVal) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.pauseOnDisconnect, reason == .oldDeviceUnavailable else { return }
                self.pause()
            }
        }
    }

    // MARK: - Playback API

    public func playTrack(
        _ track: SieloTrack,
        queue: [SieloTrack]? = nil,
        seekToMs: Int64 = 0,
        autoPlay: Bool = true,
        resetScope: Bool = true
    ) {
        if resetScope && queueScope != .listenTogether {
            queueScope = .open
            scopeArtistName = nil
        }

        let activeQueue = (queue?.isEmpty == false) ? queue! : [track]
        let idx = activeQueue.firstIndex(where: { $0.id == track.id }) ?? 0

        if playbackState.currentTrack?.id != track.id {
            evaluateSkipPenaltyIfNeeded()
        }

        playbackGeneration += 1
        let gen = playbackGeneration
        retryAttemptedForCurrentTrack = false
        currentTrackEventId = nil
        hasRegisteredPlayForCurrentTrack = false
        lastPersistedProgressMs = 0

        playbackState.currentTrack = track
        playbackState.queue = activeQueue
        playbackState.queueIndex = idx
        playbackState.currentPositionMs = seekToMs
        playbackState.durationMs = track.durationSeconds * 1000
        playbackState.isBuffering = true
        playbackState.isPlaying = autoPlay

        observeFavoriteState(for: track.id)
        persistState()
        updateNowPlaying()

        Task { [weak self] in
            await self?.loadAndStart(track: track, seekToMs: seekToMs, autoPlay: autoPlay, generation: gen)
        }
    }

    public func playAlbum(tracks: [SieloTrack], startIndex: Int = 0) {
        guard !tracks.isEmpty else { return }
        let safeIdx = min(max(0, startIndex), tracks.count - 1)
        queueScope = .albumOnly
        playTrack(tracks[safeIdx], queue: tracks, resetScope: false)
    }

    public func playArtistRadio(artistName: String, tracks: [SieloTrack], startIndex: Int = 0) {
        guard !tracks.isEmpty else { return }
        let safeIdx = min(max(0, startIndex), tracks.count - 1)
        queueScope = .artistOnly
        scopeArtistName = artistName
        playTrack(tracks[safeIdx], queue: tracks, resetScope: false)
    }

    public func playListenTogether(track: SieloTrack, queue: [SieloTrack], seekToMs: Int64 = 0, autoPlay: Bool = true) {
        queueScope = .listenTogether
        playTrack(track, queue: queue, seekToMs: seekToMs, autoPlay: autoPlay, resetScope: false)
    }

    public func updateListenTogetherQueue(_ queue: [SieloTrack]) {
        guard queueScope == .listenTogether else { return }
        playbackState.queue = queue
        if let cur = playbackState.currentTrack,
           let idx = queue.firstIndex(where: { $0.id == cur.id }) {
            playbackState.queueIndex = idx
        }
    }

    public func clearListenTogetherScope() {
        if queueScope == .listenTogether {
            queueScope = .open
        }
    }

    private func loadAndStart(track: SieloTrack, seekToMs: Int64, autoPlay: Bool, generation: Int64) async {
        var assetURL: URL?
        var headers: [String: String] = [:]

        if let local = offlineCache.getLocalTrackURL(track.id) {
            assetURL = local
        } else if NetworkHelper.shared.isOnline {
            if let streamStr = await InnerTubeClient.shared.getStreamUrl(
                videoId: track.id,
                title: track.title,
                artist: track.artist
            ), let remoteURL = URL(string: streamStr) {
                assetURL = remoteURL
                headers = StreamClientUtils.headersForStreamURL(remoteURL)
                offlineCache.autoCacheTrack(track, streamURL: streamStr)
            }
        }

        guard generation == playbackGeneration else { return }

        guard let resolvedURL = assetURL else {
            playbackState.isBuffering = false
            playbackState.isPlaying = false
            return
        }

        let options: [String: Any] = headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: resolvedURL, options: options)
        let item = AVPlayerItem(asset: asset)

        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTrackEnded()
            }
        }

        player.replaceCurrentItem(with: item)
        player.isMuted = playbackState.isMuted

        if seekToMs > 0 {
            let cmTime = CMTime(value: seekToMs, timescale: 1000)
            await player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        if autoPlay {
            player.playImmediately(atRate: playbackSpeed)
            if let currentTrack = playbackState.currentTrack {
                onListeningEvent?("play_started", currentTrack, seekToMs, playbackState.durationMs)
            }
        } else {
            player.pause()
        }

        playbackState.isBuffering = false
        startProgressTicker()
        updateNowPlaying()
        maybeReplenishAutoplay()
    }

    // MARK: - Transport Controls

    public func togglePlayPause() {
        playbackState.isPlaying ? pause() : play()
    }

    public func play() {
        configureAudioSession()
        player.playImmediately(atRate: playbackSpeed)
        playbackState.isPlaying = true
        updateNowPlaying()
    }

    public func pause() {
        player.pause()
        playbackState.isPlaying = false
        updateNowPlaying()
        saveCurrentPlaybackPosition()
    }

    public func seekTo(_ ms: Int64) {
        let clamped = max(0, ms)
        let cmTime = CMTime(value: clamped, timescale: 1000)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        playbackState.currentPositionMs = clamped
        updateNowPlaying()
    }

    public func toggleMute() {
        playbackState.isMuted.toggle()
        player.isMuted = playbackState.isMuted
    }

    public func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = min(2.0, max(0.5, speed))
        if playbackState.isPlaying {
            player.rate = playbackSpeed
        }
        updateNowPlaying()
    }

    public func toggleLoop() {
        playbackState.isLooping.toggle()
        updateNowPlaying()
    }

    public func skipNext() {
        let queue = playbackState.queue
        guard !queue.isEmpty else { return }
        let nextIdx = playbackState.queueIndex + 1
        if nextIdx < queue.count {
            if playbackState.playNextCount > 0 {
                playbackState.playNextCount -= 1
            }
            playTrack(queue[nextIdx], queue: queue, resetScope: false)
        } else if queueScope == .albumOnly {
            playTrack(queue[0], queue: queue, resetScope: false)
        }
    }

    public func skipPrevious() {
        if playbackState.currentPositionMs > 3000 {
            seekTo(0)
            return
        }
        let queue = playbackState.queue
        let prevIdx = playbackState.queueIndex - 1
        if prevIdx >= 0, prevIdx < queue.count {
            playTrack(queue[prevIdx], queue: queue, resetScope: false)
        } else {
            seekTo(0)
        }
    }

    // MARK: - Queue & Protected Play Next

    public func playNext(_ track: SieloTrack) {
        var queue = playbackState.queue
        guard !queue.isEmpty, playbackState.queueIndex >= 0 else {
            playTrack(track)
            return
        }
        let insertIndex = min(queue.count, playbackState.queueIndex + 1 + playbackState.playNextCount)
        queue.insert(track, at: insertIndex)
        playbackState.queue = queue
        playbackState.playNextCount += 1
        if !originalQueue.isEmpty {
            originalQueue.append(track)
        }
        persistState()
    }

    public func appendToQueue(_ track: SieloTrack) {
        playbackState.queue.append(track)
        if !originalQueue.isEmpty {
            originalQueue.append(track)
        }
        persistState()
    }

    public func removeTrackFromQueue(at index: Int) {
        guard index >= 0, index < playbackState.queue.count, index != playbackState.queueIndex else { return }
        playbackState.queue.remove(at: index)
        if index < playbackState.queueIndex {
            playbackState.queueIndex -= 1
        } else if index <= playbackState.queueIndex + playbackState.playNextCount && playbackState.playNextCount > 0 {
            playbackState.playNextCount -= 1
        }
        persistState()
    }

    public func reorderUpcomingTracks(fromOffset: Int, toOffset: Int) {
        let base = playbackState.queueIndex + 1
        let fromIdx = base + fromOffset
        let toIdx = base + toOffset
        guard fromIdx >= base, toIdx >= base,
              fromIdx < playbackState.queue.count, toIdx < playbackState.queue.count else { return }
        let moved = playbackState.queue.remove(at: fromIdx)
        playbackState.queue.insert(moved, at: toIdx)
        persistState()
    }

    public func toggleShuffle() {
        let curIdx = playbackState.queueIndex
        let queue = playbackState.queue
        guard curIdx >= 0, curIdx < queue.count else {
            playbackState.isShuffle.toggle()
            return
        }

        if !playbackState.isShuffle {
            originalQueue = queue
            let past = Array(queue[0...curIdx])
            let protectedEnd = min(queue.count, curIdx + 1 + playbackState.playNextCount)
            let protectedWindow = Array(queue[(curIdx + 1)..<protectedEnd])
            let dynamicTail = Array(queue[protectedEnd...]).shuffled()
            playbackState.queue = past + protectedWindow + dynamicTail
            playbackState.isShuffle = true
        } else {
            if !originalQueue.isEmpty, let curTrack = playbackState.currentTrack {
                let newIdx = originalQueue.firstIndex(where: { $0.id == curTrack.id }) ?? curIdx
                playbackState.queue = originalQueue
                playbackState.queueIndex = newIdx
            }
            originalQueue = []
            playbackState.isShuffle = false
        }
        persistState()
    }

    public func resetPlayer() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        progressTask?.cancel()
        playbackState = PlaybackState()
        queueScope = .open
        originalQueue = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Progress, 15% Threshold & Autoplay

    private func handleTrackEnded() {
        if let cur = playbackState.currentTrack {
            favoredSongIds.insert(cur.id)
            onListeningEvent?("play_completed", cur, playbackState.durationMs, playbackState.durationMs)
        }
        if playbackState.isLooping {
            seekTo(0)
            play()
            return
        }
        skipNext()
    }

    private func evaluateSkipPenaltyIfNeeded() {
        guard let cur = playbackState.currentTrack else { return }
        if playbackState.currentPositionMs > 0 && playbackState.currentPositionMs < 25_000 {
            penalizedSongIds.insert(cur.id)
            onListeningEvent?("skipped", cur, playbackState.currentPositionMs, playbackState.durationMs)
        }
    }

    private func startProgressTicker() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                guard let self else { return }
                await self.tickProgress()
            }
        }
    }

    private func tickProgress() async {
        guard let item = player.currentItem else { return }
        let posSec = CMTimeGetSeconds(player.currentTime())
        let durSec = CMTimeGetSeconds(item.duration)

        if posSec.isFinite && posSec >= 0 {
            playbackState.currentPositionMs = Int64(posSec * 1000)
        }
        if durSec.isFinite && durSec > 0 {
            playbackState.durationMs = Int64(durSec * 1000)
        }

        // 15% Play Threshold (min 5s, fallback 20s)
        let thresholdMs: Int64 = playbackState.durationMs > 0
            ? max(5_000, Int64(Double(playbackState.durationMs) * 0.15))
            : 20_000

        if playbackState.isPlaying,
           !hasRegisteredPlayForCurrentTrack,
           playbackState.currentPositionMs >= thresholdMs,
           let track = playbackState.currentTrack {
            hasRegisteredPlayForCurrentTrack = true
            await registerListeningEvent(for: track)
        }

        // Flush durationPlayedMs every 2 seconds
        if playbackState.isPlaying,
           let eventId = currentTrackEventId,
           abs(playbackState.currentPositionMs - lastPersistedProgressMs) >= 2000 {
            lastPersistedProgressMs = playbackState.currentPositionMs
            try? await database.listeningHistory.updateDurationPlayed(
                eventId: eventId,
                durationMs: playbackState.currentPositionMs
            )
        }
    }

    private func registerListeningEvent(for track: SieloTrack) async {
        let now = Date()
        let cal = Calendar.current
        let event = ListeningEventEntity(
            songId: track.id,
            songTitle: track.title,
            artistName: track.artist,
            albumName: track.album,
            thumbnailUrl: track.thumbnailUrl,
            timestampMs: Int64(now.timeIntervalSince1970 * 1000),
            durationPlayedMs: max(5000, playbackState.currentPositionMs),
            songDurationMs: playbackState.durationMs,
            hourOfDay: cal.component(.hour, from: now),
            dayOfWeek: cal.component(.weekday, from: now),
            month: cal.component(.month, from: now),
            year: cal.component(.year, from: now),
            completed: false
        )
        currentTrackEventId = try? await database.listeningHistory.insertEvent(event)
        onTrackPlayedTasteListener?(track.artist, "")
        onListeningEvent?("playback_progress", track, playbackState.currentPositionMs, playbackState.durationMs)
    }

    private func maybeReplenishAutoplay() {
        guard autoplayEnabled,
              queueScope == .open || queueScope == .artistOnly,
              let cur = playbackState.currentTrack,
              let replenisher = autoplayReplenisher else { return }

        let remaining = playbackState.queue.count - (playbackState.queueIndex + 1)
        guard remaining <= 3 else { return }

        let excluded = Set(playbackState.queue.map(\.id)).union(penalizedSongIds)
        Task { [weak self] in
            let batch = await replenisher(cur, excluded)
            guard let self, !batch.isEmpty else { return }
            let existingIds = Set(self.playbackState.queue.map(\.id))
            let fresh = batch.filter { !existingIds.contains($0.id) }
            self.playbackState.queue.append(contentsOf: fresh)
            self.persistState()
        }
    }

    // MARK: - Favorites & Persistence

    private func observeFavoriteState(for trackId: String) {
        favoriteTask?.cancel()
        favoriteTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await fav in self.database.favorites.observeIsFavorite(id: trackId) {
                    if Task.isCancelled { break }
                    self.isCurrentTrackFavorite = fav
                    self.updateNowPlaying()
                }
            } catch {}
        }
    }

    public func toggleCurrentTrackFavorite() async {
        guard let track = playbackState.currentTrack else { return }
        let currentlyFav = (try? await database.favorites.isFavorite(id: track.id)) ?? false
        if currentlyFav {
            try? await database.favorites.deleteById(track.id)
            onListeningEvent?("unliked", track, playbackState.currentPositionMs, playbackState.durationMs)
        } else {
            let entity = FavoriteTrackEntity(
                id: track.id,
                title: track.title,
                artist: track.artist,
                thumbnailUrl: track.thumbnailUrl
            )
            try? await database.favorites.insertFavorite(entity)
            onListeningEvent?("liked", track, playbackState.currentPositionMs, playbackState.durationMs)
        }
    }

    public func saveCurrentPlaybackPosition() {
        persistState()
    }

    private func persistState() {
        if let track = playbackState.currentTrack,
           let data = try? JSONEncoder().encode(track) {
            prefs.set(data, forKey: "last_track")
        }
        if let queueData = try? JSONEncoder().encode(playbackState.queue) {
            prefs.set(queueData, forKey: "last_queue")
        }
        prefs.set(playbackState.queueIndex, forKey: "last_queue_index")
        prefs.set(playbackState.currentPositionMs, forKey: "last_position_ms")
        prefs.set(playbackState.durationMs, forKey: "last_duration_ms")
        prefs.set(playbackState.isShuffle, forKey: "last_shuffle")
    }

    private func restorePersistedState() {
        guard let trackData = prefs.data(forKey: "last_track"),
              let track = try? JSONDecoder().decode(SieloTrack.self, from: trackData) else { return }
        let queue: [SieloTrack] = (prefs.data(forKey: "last_queue").flatMap {
            try? JSONDecoder().decode([SieloTrack].self, from: $0)
        }) ?? [track]
        let idx = prefs.integer(forKey: "last_queue_index")
        let pos = Int64(prefs.integer(forKey: "last_position_ms"))
        let dur = Int64(prefs.integer(forKey: "last_duration_ms"))
        let shuffle = prefs.bool(forKey: "last_shuffle")

        playbackState = PlaybackState(
            currentTrack: track,
            isPlaying: false,
            currentPositionMs: rememberPosition ? pos : 0,
            durationMs: dur,
            queue: queue,
            queueIndex: min(max(0, idx), max(0, queue.count - 1)),
            isShuffle: shuffle
        )
        observeFavoriteState(for: track.id)
    }

    private func updateNowPlaying() {
        nowPlaying.updateNowPlaying(
            state: playbackState,
            isFavorite: isCurrentTrackFavorite,
            playbackSpeed: playbackSpeed
        )
    }
}
