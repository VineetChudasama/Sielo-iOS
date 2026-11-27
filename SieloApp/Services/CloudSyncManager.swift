import Foundation
import FirebaseAuth
import FirebaseFirestore
import SieloCoreModels
import SieloCoreDatabase
import SieloCoreAudio

/// Mirrors app/core/sync/CloudSyncManager.kt:
/// Syncs 9 sub-documents under sielo_users/{userKey}/data/* and listens for remote desktop playback.
@MainActor
public final class CloudSyncManager: ObservableObject {
    @Published public private(set) var isRestoring: Bool = false

    private let database: SieloDatabase
    private let playlistsRepository: UserPlaylistsRepository
    private let settingsRepository: SettingsRepository
    private let playerManager: PlayerManager
    private let firestore = Firestore.firestore()

    public var currentUserProvider: (() -> UserProfile?)?
    public var onProfileRestored: ((UserProfile) -> Void)?

    private var syncTask: Task<Void, Never>?
    private var telemetryTask: Task<Void, Never>?
    private var playbackListener: ListenerRegistration?

    public init(
        database: SieloDatabase,
        playlistsRepository: UserPlaylistsRepository,
        settingsRepository: SettingsRepository,
        playerManager: PlayerManager
    ) {
        self.database = database
        self.playlistsRepository = playlistsRepository
        self.settingsRepository = settingsRepository
        self.playerManager = playerManager
        startPeriodicLoops()
    }

    deinit {
        playbackListener?.remove()
        syncTask?.cancel()
        telemetryTask?.cancel()
    }

    private func resolveUserKey(for profile: UserProfile?) -> String? {
        if let uid = Auth.auth().currentUser?.uid, !uid.isEmpty { return uid }
        if let id = profile?.id, !id.isEmpty { return id }
        return profile?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func dataCollection(for userKey: String) -> CollectionReference {
        firestore.collection("sielo_users").document(userKey).collection("data")
    }

    // MARK: - Full Backup & Restore

    public func backupAll(profile: UserProfile) async {
        guard profile.provider != .guest, !isRestoring, let key = resolveUserKey(for: profile) else { return }
        let col = dataCollection(for: key)

        // 1. data/profile
        let favs = (try? await database.favorites.getAllFavoritesList()) ?? []
        let history = (try? await database.listeningHistory.getAllHistoryList(limit: 1500)) ?? []
        let totalTime = history.reduce(0) { $0 + $1.durationPlayedMs }

        let profileData: [String: Any] = [
            "id": profile.id,
            "name": profile.name,
            "email": profile.email,
            "photoUrl": profile.photoUrl as Any,
            "bio": profile.bio as Any,
            "username": profile.username as Any,
            "provider": profile.provider.rawValue,
            "hasCompletedOnboarding": profile.hasCompletedOnboarding,
            "favoriteArtists": profile.favoriteArtists,
            "favoriteGenres": profile.favoriteGenres,
            "artistTasteWeights": profile.artistTasteWeights,
            "genreTasteWeights": profile.genreTasteWeights,
            "totalStreams": history.count,
            "streamCount": history.count,
            "likedCount": favs.count,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "12.0.0",
            "deviceModel": "iPhone",
            "createdAt": profile.createdAt,
            "lastSyncedAt": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        try? await col.document("profile").setData(profileData, merge: true)

        // 2. data/library
        let favMaps = favs.map {
            [
                "id": $0.id,
                "title": $0.title,
                "artist": $0.artist,
                "thumbnailUrl": $0.thumbnailUrl as Any,
                "addedAt": $0.addedAt
            ] as [String: Any]
        }
        try? await col.document("library").setData(["favorites": favMaps], merge: true)

        // 3. data/playlists
        if let playlistData = try? JSONEncoder().encode(playlistsRepository.customPlaylistsOnly()),
           let playlistJSON = String(data: playlistData, encoding: .utf8) {
            try? await col.document("playlists").setData(["playlistsJson": playlistJSON], merge: true)
        }

        // 4. data/history & data/stats
        if let historyData = try? JSONEncoder().encode(history),
           let historyJSON = String(data: historyData, encoding: .utf8) {
            try? await col.document("history").setData(["eventsJson": historyJSON], merge: true)
        }
        try? await col.document("stats").setData([
            "totalListeningTimeMs": totalTime,
            "totalStreams": history.count
        ], merge: true)

        // 5. data/search_history
        let searches = (try? await database.searchHistory.getAllSearchQueries()) ?? []
        let searchMaps = searches.prefix(30).map { ["query": $0.query, "timestampMs": $0.timestampMs] as [String: Any] }
        try? await col.document("search_history").setData(["queries": searchMaps], merge: true)

        // 6. data/settings
        try? await col.document("settings").setData(settingsRepository.getSettingsMap(), merge: true)

        // 7. data/playback
        await backupPlayback(userKey: key)
    }

    public func restoreUserData(profile: UserProfile) async {
        guard profile.provider != .guest, let key = resolveUserKey(for: profile) else { return }
        isRestoring = true
        defer { isRestoring = false }

        let col = dataCollection(for: key)

        // Restore library favorites
        if let doc = try? await col.document("library").getDocument(),
           let favs = doc.data()?["favorites"] as? [[String: Any]] {
            let entities = favs.compactMap { item -> FavoriteTrackEntity? in
                guard let id = item["id"] as? String,
                      let title = item["title"] as? String,
                      let artist = item["artist"] as? String else { return nil }
                return FavoriteTrackEntity(
                    id: id,
                    title: title,
                    artist: artist,
                    thumbnailUrl: item["thumbnailUrl"] as? String,
                    addedAt: (item["addedAt"] as? Int64) ?? Int64(Date().timeIntervalSince1970 * 1000)
                )
            }
            try? await database.favorites.insertFavorites(entities)
        }

        // Restore custom playlists
        if let doc = try? await col.document("playlists").getDocument(),
           let jsonStr = doc.data()?["playlistsJson"] as? String,
           let data = jsonStr.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([UserPlaylist].self, from: data) {
            playlistsRepository.replaceSyncedPlaylists(decoded)
        }

        // Restore settings
        if let doc = try? await col.document("settings").getDocument(),
           let settingsMap = doc.data() {
            settingsRepository.applySettingsMap(settingsMap)
        }

        startRemotePlaybackListener(userKey: key)
    }

    private func backupPlayback(userKey: String) async {
        let state = playerManager.playbackState
        var payload: [String: Any] = [
            "activeDeviceId": "ios",
            "isPlaying": state.isPlaying,
            "positionMs": state.currentPositionMs,
            "updatedAt": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let track = state.currentTrack,
           let data = try? JSONEncoder().encode(track),
           let str = String(data: data, encoding: .utf8) {
            payload["currentTrackJson"] = str
        }
        try? await dataCollection(for: userKey).document("playback").setData(payload, merge: true)
    }

    private func startRemotePlaybackListener(userKey: String) {
        playbackListener?.remove()
        playbackListener = dataCollection(for: userKey).document("playback")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let data = snapshot?.data(),
                      let activeDevice = data["activeDeviceId"] as? String,
                      let isPlaying = data["isPlaying"] as? Bool,
                      activeDevice != "ios", isPlaying else { return }
                Task { @MainActor [weak self] in
                    if self?.playerManager.playbackState.isPlaying == true {
                        self?.playerManager.pause()
                    }
                }
            }
    }

    private func startPeriodicLoops() {
        // 3-minute periodic backup
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 180_000_000_000)
                guard let self, let user = self.currentUserProvider?() else { continue }
                await self.backupAll(profile: user)
            }
        }

        // 30-second admin telemetry heartbeat
        telemetryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, let user = self.currentUserProvider?(), user.provider != .guest else { continue }
                await self.sendAdminTelemetry(for: user)
            }
        }
    }

    private func sendAdminTelemetry(for user: UserProfile) async {
        guard let url = URL(string: "https://sielo.site/api/admin/users") else { return }
        let state = playerManager.playbackState
        let payload: [String: Any] = [
            "id": user.id,
            "email": user.email,
            "name": user.name,
            "username": user.username ?? "",
            "isPlaying": state.isPlaying,
            "currentTrack": state.currentTrack?.title ?? "",
            "currentArtist": state.currentTrack?.artist ?? "",
            "platform": "ios"
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: req)
    }
}
