import Foundation
import Combine
import SieloCoreModels
import SieloCoreAudio

/// Mirrors app/core/playlist/UserPlaylistsRepository.kt with dynamic Downloaded Cache playlist.
@MainActor
public final class UserPlaylistsRepository: ObservableObject {
    @Published public private(set) var playlists: [UserPlaylist] = []

    private let prefs = UserDefaults(suiteName: "sielo_user_playlists") ?? .standard
    private let keyPlaylists = "user_playlists_json"
    private var rawPlaylists: [UserPlaylist] = []
    private var cancellable: AnyCancellable?

    public init() {
        rawPlaylists = loadPlaylists()
        rebuildCombinedPlaylists()

        cancellable = OfflineCacheManager.shared.$cacheUpdatedAt
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildCombinedPlaylists()
            }
    }

    public func customPlaylistsOnly() -> [UserPlaylist] {
        rawPlaylists.filter { !$0.id.hasPrefix("sielo_starter_") && $0.id != UserPlaylist.downloadedCacheId }
    }

    public func createPlaylist(
        title: String,
        description: String = "",
        tracks: [SieloTrack] = [],
        syncUrl: String? = nil,
        syncSource: String? = nil
    ) -> UserPlaylist {
        let playlist = UserPlaylist(
            id: UUID().uuidString,
            title: title,
            description: description,
            coverUrl: tracks.first?.thumbnailUrl,
            tracks: tracks,
            syncUrl: syncUrl,
            syncSource: syncSource,
            lastSyncedAt: syncUrl != nil ? Int64(Date().timeIntervalSince1970 * 1000) : nil
        )
        rawPlaylists.insert(playlist, at: 0)
        savePlaylists()
        rebuildCombinedPlaylists()
        return playlist
    }

    public func renamePlaylist(id: String, newTitle: String) {
        guard let idx = rawPlaylists.firstIndex(where: { $0.id == id }) else { return }
        rawPlaylists[idx].title = newTitle
        savePlaylists()
        rebuildCombinedPlaylists()
    }

    public func deletePlaylist(id: String) {
        rawPlaylists.removeAll { $0.id == id }
        savePlaylists()
        rebuildCombinedPlaylists()
    }

    public func addTrack(_ track: SieloTrack, toPlaylistId id: String) {
        guard let idx = rawPlaylists.firstIndex(where: { $0.id == id }) else { return }
        guard !rawPlaylists[idx].tracks.contains(where: { $0.id == track.id }) else { return }
        rawPlaylists[idx].tracks.append(track)
        if rawPlaylists[idx].coverUrl == nil {
            rawPlaylists[idx].coverUrl = track.thumbnailUrl
        }
        savePlaylists()
        rebuildCombinedPlaylists()
    }

    public func removeTrack(trackId: String, fromPlaylistId id: String) {
        guard let idx = rawPlaylists.firstIndex(where: { $0.id == id }) else { return }
        rawPlaylists[idx].tracks.removeAll { $0.id == trackId }
        savePlaylists()
        rebuildCombinedPlaylists()
    }

    public func reorderTracks(inPlaylistId id: String, fromOffsets: IndexSet, toOffset: Int) {
        guard let idx = rawPlaylists.firstIndex(where: { $0.id == id }) else { return }
        var items = rawPlaylists[idx].tracks
        let moving = fromOffsets.sorted().map { items[$0] }
        for offset in fromOffsets.sorted(by: >) {
            items.remove(at: offset)
        }
        let adjustedTarget = toOffset - fromOffsets.filter { $0 < toOffset }.count
        items.insert(contentsOf: moving, at: max(0, min(adjustedTarget, items.count)))
        rawPlaylists[idx].tracks = items
        savePlaylists()
        rebuildCombinedPlaylists()
    }

    public func replaceSyncedPlaylists(_ incoming: [UserPlaylist]) {
        let existingIds = Set(rawPlaylists.map(\.id))
        for item in incoming where !existingIds.contains(item.id) {
            rawPlaylists.append(item)
        }
        savePlaylists()
        rebuildCombinedPlaylists()
    }

    public func resetToDefault() {
        rawPlaylists = Self.starterPlaylists()
        savePlaylists()
        rebuildCombinedPlaylists()
    }

    private func rebuildCombinedPlaylists() {
        let cached = OfflineCacheManager.shared.getCachedTracks()
        let dynamicVault = UserPlaylist(
            id: UserPlaylist.downloadedCacheId,
            title: "Downloaded Cache",
            description: cached.isEmpty
                ? "Offline Vault • Songs you play are cached here for offline replay"
                : "Offline Vault • \(cached.count) songs ready for offline replay",
            coverUrl: cached.first?.thumbnailUrl
                ?? "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&auto=format&fit=crop&q=80",
            createdAt: Int64.max,
            tracks: cached
        )
        playlists = [dynamicVault] + rawPlaylists.filter { $0.id != UserPlaylist.downloadedCacheId }
    }

    private func loadPlaylists() -> [UserPlaylist] {
        guard let data = prefs.data(forKey: keyPlaylists),
              let decoded = try? JSONDecoder().decode([UserPlaylist].self, from: data),
              !decoded.isEmpty else {
            return Self.starterPlaylists()
        }
        return decoded
    }

    private func savePlaylists() {
        if let data = try? JSONEncoder().encode(rawPlaylists) {
            prefs.set(data, forKey: keyPlaylists)
        }
    }

    private static func starterPlaylists() -> [UserPlaylist] {
        [
            UserPlaylist(id: "sielo_starter_1", title: "Late Night Drive", description: "Atmospheric night mixes"),
            UserPlaylist(id: "sielo_starter_2", title: "Acoustic Unplugged", description: "Stripped-down studio sessions"),
            UserPlaylist(id: "sielo_starter_3", title: "Focus Flow", description: "Deep concentration instrumentals")
        ]
    }
}
