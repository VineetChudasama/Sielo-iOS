import Foundation
import SieloCoreModels
import SieloCoreDatabase
import SieloCoreNetwork

/// Mirrors core-recommendations/autoplay/AutoplayQueueEngine.kt, CandidatePoolBuilder.kt,
/// RecommendationRepository.kt, and ListeningEventDispatcher.kt.
public actor AutoplayQueueEngine {
    private let database: SieloDatabase
    private let apiClient: RecommendationApiClient
    private let artistSeparationDistance = 3

    public init(database: SieloDatabase, apiClient: RecommendationApiClient = RecommendationApiClient()) {
        self.database = database
        self.apiClient = apiClient
    }

    public func generateBatch(
        seedSong: SieloTrack,
        userId: String?,
        excludedSongIds: Set<String>,
        batchSize: Int = 20
    ) async -> [SieloTrack] {
        let today = Self.todayISO()
        let ineligibleToday = Set((try? await database.recommendationHistory.getIneligibleSongIds(todayDate: today)) ?? [])
        let blockedIds = excludedSongIds.union(ineligibleToday).union([seedSong.id])

        // 1. Try Hybrid Backend (/v1/recommendations)
        let request = RecommendationRequestDto(
            userId: userId,
            seedTrackId: seedSong.id,
            seedArtist: seedSong.artist,
            seedTitle: seedSong.title,
            excludedTrackIds: Array(blockedIds),
            limit: batchSize
        )
        var backendPool: [SieloTrack] = []
        if let response = await apiClient.getRecommendations(request) {
            backendPool = response.recommendations.map { item in
                SieloTrack(
                    id: item.trackId,
                    title: item.title ?? "",
                    artist: item.artist ?? "",
                    album: item.album,
                    thumbnailUrl: item.thumbnailUrl
                )
            }
            .filter { !$0.title.isEmpty && !blockedIds.contains($0.id) }
        }

        // 2. Build local 3-Tier Pools (A: 60% Familiar, B: 25% Discovery, C: 15% Moderate)
        let seedLang = SongClassifier.detectLanguage(seedSong)
        let seedVibe = SongClassifier.detectVibe(seedSong)

        let topArtists = (try? await database.listeningHistory.getTopArtistsSnapshot(
            sinceMs: Self.daysAgoMs(90), limit: 15
        ))?.map(\.artistName) ?? []

        let poolAStats = (try? await database.listeningHistory.getSongsByArtists([seedSong.artist] + topArtists)) ?? []
        var poolA = poolAStats.map {
            SieloTrack(id: $0.songId, title: $0.songTitle, artist: $0.artistName, album: $0.albumName, thumbnailUrl: $0.thumbnailUrl)
        }

        var poolB = backendPool
        if poolB.count < 8 {
            let similarArtists = SongClassifier.similarArtistsCluster(for: seedSong.artist, language: seedLang)
            for artist in similarArtists.prefix(4) {
                let res = await InnerTubeClient.shared.search(query: artist)
                poolB.append(contentsOf: res.tracks.prefix(3))
            }
        }

        let poolCStats = (try? await database.listeningHistory.getSongsByPlayCountRange(
            sinceMs: Self.daysAgoMs(60), minPlays: 2, maxPlays: 5
        )) ?? []
        let poolC = poolCStats.map {
            SieloTrack(id: $0.songId, title: $0.songTitle, artist: $0.artistName, album: $0.albumName, thumbnailUrl: $0.thumbnailUrl)
        }

        func cleanFilter(_ tracks: [SieloTrack]) -> [SieloTrack] {
            tracks.filter { track in
                !blockedIds.contains(track.id) &&
                !TrackMatchValidator.isCleanOrCensored(track.title) &&
                !TrackMatchValidator.isCoverOrKaraokeTrack(track.title, artist: track.artist) &&
                SongClassifier.isVibeCompatible(seed: seedVibe, candidate: SongClassifier.detectVibe(track))
            }
        }

        let cleanA = cleanFilter(poolA)
        let cleanB = cleanFilter(poolB)
        let cleanC = cleanFilter(poolC)

        // 3. Allocate 60% Pool A / 25% Pool B / 15% Pool C
        let countA = Int(Double(batchSize) * 0.60)
        let countB = Int(Double(batchSize) * 0.25)
        let countC = max(0, batchSize - countA - countB)

        var combined: [SieloTrack] = []
        var seen = Set<String>()

        func take(_ source: [SieloTrack], maxCount: Int) {
            var added = 0
            for t in source where added < maxCount {
                if seen.insert(t.id).inserted {
                    combined.append(t)
                    added += 1
                }
            }
        }

        take(cleanA, maxCount: countA)
        take(cleanB, maxCount: countB)
        take(cleanC, maxCount: countC)
        take(cleanB + cleanA, maxCount: max(0, batchSize - combined.count))

        // 4. Interleave with artist separation distance = 3
        let spaced = interleaveWithArtistSpacing(combined, distance: artistSeparationDistance)

        // 5. Mark in same-day duplicate shield
        try? await database.recommendationHistory.markRecommended(songIds: spaced.map(\.id), date: today)
        return spaced
    }

    private func interleaveWithArtistSpacing(_ tracks: [SieloTrack], distance: Int) -> [SieloTrack] {
        var remaining = tracks
        var result: [SieloTrack] = []

        while !remaining.isEmpty {
            let recentArtists = Set(result.suffix(distance).map { $0.artist.lowercased() })
            if let idx = remaining.firstIndex(where: { !recentArtists.contains($0.artist.lowercased()) }) {
                result.append(remaining.remove(at: idx))
            } else {
                result.append(remaining.removeFirst())
            }
        }
        return result
    }

    private static func todayISO() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: Date())
    }

    private static func daysAgoMs(_ days: Int) -> Int64 {
        let date = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return Int64(date.timeIntervalSince1970 * 1000)
    }
}

/// Batches listening events (up to 50) every 30s to POST /v1/events.
public actor ListeningEventDispatcher {
    private let apiClient: RecommendationApiClient
    private var queue: [ClientListeningEvent] = []
    private var isPrivateListening = false
    private var flushTask: Task<Void, Never>?

    public init(apiClient: RecommendationApiClient = RecommendationApiClient()) {
        self.apiClient = apiClient
    }

    public func setPrivateListening(_ enabled: Bool) {
        self.isPrivateListening = enabled
    }

    public func start() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await self?.flush()
            }
        }
    }

    public func dispatch(_ event: ClientListeningEvent) async {
        guard !isPrivateListening else { return }
        queue.append(event)
        if queue.count >= 50 {
            await flush()
        }
    }

    public func flush() async {
        guard !queue.isEmpty else { return }
        let batch = Array(queue.prefix(50))
        queue.removeFirst(batch.count)
        let ok = await apiClient.sendBatchEvents(batch)
        if !ok {
            queue = Array((batch + queue).prefix(200))
        }
    }
}
