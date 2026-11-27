import Foundation
import Combine
import SieloCoreModels
import SieloCoreNetwork

/// Mirrors core-audio/OfflineCacheManager.kt:
/// Stores full offline tracks in Library/Caches/sielo_downloads (<id>.m4a, <id>.json, <id>.jpg) with 512 MB LRU cap.
@MainActor
public final class OfflineCacheManager: ObservableObject {
    public static let shared = OfflineCacheManager()

    @Published public private(set) var cacheUpdatedAt: Int64 = 0

    private let maxCacheBytes: Int64 = 512 * 1024 * 1024
    private let downloadsDir: URL
    private let session: URLSession

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.downloadsDir = caches.appendingPathComponent("sielo_downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    private func audioURL(for trackId: String) -> URL {
        downloadsDir.appendingPathComponent("\(trackId).m4a")
    }

    private func metaURL(for trackId: String) -> URL {
        downloadsDir.appendingPathComponent("\(trackId).json")
    }

    private func artURL(for trackId: String) -> URL {
        downloadsDir.appendingPathComponent("\(trackId).jpg")
    }

    public func isCached(_ trackId: String) -> Bool {
        let url = audioURL(for: trackId)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return false
        }
        return size > 1024
    }

    public func getLocalTrackURL(_ trackId: String) -> URL? {
        isCached(trackId) ? audioURL(for: trackId) : nil
    }

    public func getLocalArtworkURL(_ trackId: String) -> URL? {
        let url = artURL(for: trackId)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func autoCacheTrack(_ track: SieloTrack, streamURL: String) {
        guard !isCached(track.id) else { return }
        Task.detached(priority: .utility) { [weak self] in
            await self?.downloadFully(track: track, streamURL: streamURL)
        }
    }

    @discardableResult
    public func downloadFully(track: SieloTrack, streamURL: String) async -> Bool {
        guard let url = URL(string: streamURL) else { return false }
        let targetAudio = audioURL(for: track.id)
        let tmpAudio = downloadsDir.appendingPathComponent("\(track.id).m4a.tmp")

        var req = URLRequest(url: url)
        for (k, v) in StreamClientUtils.headersForStreamURL(url) {
            req.setValue(v, forHTTPHeaderField: k)
        }

        do {
            let (tempFile, response) = try await session.download(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            try? FileManager.default.removeItem(at: tmpAudio)
            try FileManager.default.moveItem(at: tempFile, to: tmpAudio)
            try? FileManager.default.removeItem(at: targetAudio)
            try FileManager.default.moveItem(at: tmpAudio, to: targetAudio)

            // Save track metadata JSON
            if let metaData = try? JSONEncoder().encode(track) {
                try? metaData.write(to: metaURL(for: track.id), options: .atomic)
            }

            // Cache artwork if available
            if let thumbStr = track.thumbnailUrl, let thumbURL = URL(string: thumbStr) {
                if let (artData, _) = try? await session.data(from: thumbURL), !artData.isEmpty {
                    try? artData.write(to: artURL(for: track.id), options: .atomic)
                }
            }

            evictLRUIfNeeded()
            cacheUpdatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmpAudio)
            return false
        }
    }

    public func getCachedTracks() -> [SieloTrack] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: downloadsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let jsonFiles = files
            .filter { $0.pathExtension == "json" }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 > d2
            }

        return jsonFiles.compactMap { fileURL in
            guard let data = try? Data(contentsOf: fileURL),
                  var track = try? JSONDecoder().decode(SieloTrack.self, from: data),
                  isCached(track.id) else {
                return nil
            }
            let localArt = artURL(for: track.id)
            if FileManager.default.fileExists(atPath: localArt.path) {
                track.thumbnailUrl = localArt.absoluteString
            }
            return track
        }
    }

    public func removeTrack(_ trackId: String) {
        try? FileManager.default.removeItem(at: audioURL(for: trackId))
        try? FileManager.default.removeItem(at: metaURL(for: trackId))
        try? FileManager.default.removeItem(at: artURL(for: trackId))
        cacheUpdatedAt = Int64(Date().timeIntervalSince1970 * 1000)
    }

    public func clearCache() {
        if let files = try? FileManager.default.contentsOfDirectory(at: downloadsDir, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
        cacheUpdatedAt = Int64(Date().timeIntervalSince1970 * 1000)
    }

    public func totalCacheSizeBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: downloadsDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }
        return files.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }

    private func evictLRUIfNeeded() {
        var total = totalCacheSizeBytes()
        guard total > maxCacheBytes else { return }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: downloadsDir,
            includingPropertiesForKeys: [.contentAccessDateKey, .fileSizeKey]
        ) else { return }

        let audioFiles = files
            .filter { $0.pathExtension == "m4a" }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? .distantPast
                return d1 < d2
            }

        for file in audioFiles where total > maxCacheBytes {
            let trackId = file.deletingPathExtension().lastPathComponent
            let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            removeTrack(trackId)
            total -= size
        }
    }
}
