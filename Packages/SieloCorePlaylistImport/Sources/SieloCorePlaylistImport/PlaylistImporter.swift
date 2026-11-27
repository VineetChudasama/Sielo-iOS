import Foundation
import SieloCoreModels
import SieloCoreNetwork

public struct ImportedTrackCandidate: Codable, Sendable {
    public let title: String
    public let artistGuess: String
    public let sourcePlatform: String

    public init(title: String, artistGuess: String, sourcePlatform: String) {
        self.title = title
        self.artistGuess = artistGuess
        self.sourcePlatform = sourcePlatform
    }
}

public enum ImportSource: String, Codable, Sendable {
    case youtube = "YOUTUBE"
    case spotifyOAuth = "SPOTIFY_OAUTH"
    case spotifyManualPaste = "SPOTIFY_MANUAL_PASTE"
}

public struct ImportResult: Sendable {
    public let playlistTitle: String
    public let totalCandidates: Int
    public let importedTracks: [SieloTrack]
    public let unimportedTracks: [ImportedTrackCandidate]
}

public enum PlaylistImportError: LocalizedError {
    case unsupportedLink(String)
    case emptyImport

    public var errorDescription: String? {
        switch self {
        case .unsupportedLink(let msg): return msg
        case .emptyImport: return "No tracks could be extracted from the provided link or text."
        }
    }
}

/// Mirrors core-playlist-import (SpotifyPlaylistFetcher, ManualPasteParser, PlaylistImportRepository).
public actor PlaylistImportRepository {
    public static let shared = PlaylistImportRepository()
    private let session = URLSession.shared

    public func importFromInput(
        _ rawInput: String,
        customTitle: String? = nil,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> ImportResult {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. YouTube / YouTube Music Playlist URL
        if let ytPlaylistId = extractYouTubePlaylistId(from: trimmed) {
            let tracks = await InnerTubeClient.shared.getYouTubePlaylistSongs(ytPlaylistId)
            return ImportResult(
                playlistTitle: customTitle ?? "Imported YouTube Playlist",
                totalCandidates: tracks.count,
                importedTracks: tracks,
                unimportedTracks: []
            )
        }

        // 2. Reject private Spotify blend / short app links
        if trimmed.contains("/blend/invite") || trimmed.contains("spotify.app.link") {
            throw PlaylistImportError.unsupportedLink("Private Spotify Blend or short app.link URLs cannot be imported directly. Please copy the full playlist URL.")
        }

        // 3. Extract candidates from Spotify URL or Manual Paste
        let (title, candidates) = try await extractCandidates(from: trimmed)
        guard !candidates.isEmpty else { throw PlaylistImportError.emptyImport }

        // 4. Resolve candidates concurrently (max 5 in-flight)
        var resolved: [SieloTrack] = []
        var unimported: [ImportedTrackCandidate] = []
        let total = candidates.count

        await withTaskGroup(of: (Int, SieloTrack?, ImportedTrackCandidate).self) { group in
            var nextIdx = 0
            for _ in 0..<min(5, total) {
                let idx = nextIdx
                nextIdx += 1
                let cand = candidates[idx]
                group.addTask {
                    let match = await self.resolveCandidate(cand)
                    return (idx, match, cand)
                }
            }

            var completed = 0
            var indexedResults: [(Int, SieloTrack?, ImportedTrackCandidate)] = []
            while let item = await group.next() {
                indexedResults.append(item)
                completed += 1
                onProgress?(completed, total)

                if nextIdx < total {
                    let idx = nextIdx
                    nextIdx += 1
                    let cand = candidates[idx]
                    group.addTask {
                        let match = await self.resolveCandidate(cand)
                        return (idx, match, cand)
                    }
                }
            }

            for (_, track, cand) in indexedResults.sorted(by: { $0.0 < $1.0 }) {
                if let track {
                    resolved.append(track)
                } else {
                    unimported.append(cand)
                }
            }
        }

        return ImportResult(
            playlistTitle: customTitle ?? title,
            totalCandidates: total,
            importedTracks: resolved,
            unimportedTracks: unimported
        )
    }

    private func resolveCandidate(_ cand: ImportedTrackCandidate) async -> SieloTrack? {
        let query = cand.artistGuess.isEmpty ? cand.title : "\(cand.title) \(cand.artistGuess)"
        let search = await InnerTubeClient.shared.search(query: query)
        return search.tracks.first(where: {
            !TrackMatchValidator.isCoverOrKaraokeTrack($0.title, artist: $0.artist) &&
            TrackMatchValidator.isFuzzyMatch(
                candidateTitle: $0.title,
                candidateArtist: $0.artist,
                targetTitle: cand.title,
                targetArtist: cand.artistGuess.isEmpty ? $0.artist : cand.artistGuess
            )
        }) ?? search.tracks.first
    }

    private func extractYouTubePlaylistId(from input: String) -> String? {
        guard input.contains("youtube.com") || input.contains("youtu.be") || input.contains("music.youtube.com"),
              let url = URL(string: input),
              let list = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "list" })?.value,
              !list.isEmpty else {
            return nil
        }
        return list
    }

    private func extractCandidates(from input: String) async throws -> (String, [ImportedTrackCandidate]) {
        if let spotifyInfo = extractSpotifyResource(from: input) {
            if let embedTracks = await fetchSpotifyEmbed(type: spotifyInfo.type, id: spotifyInfo.id), !embedTracks.tracks.isEmpty {
                return (embedTracks.title, embedTracks.tracks)
            }
            if let oembed = await fetchSpotifyOEmbed(url: input) {
                return (oembed.title, [oembed])
            }
            return ("Imported Spotify Playlist", [])
        }

        // Multiline manual paste ("Title - Artist" or "Title by Artist")
        let lines = input.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let candidates = lines.map { line -> ImportedTrackCandidate in
            let cleaned = line.replacingOccurrences(of: "^\\d+[.)]\\s*", with: "", options: .regularExpression)
            if let range = cleaned.range(of: " - ") {
                return ImportedTrackCandidate(
                    title: String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                    artistGuess: String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespaces),
                    sourcePlatform: "Manual"
                )
            } else if let range = cleaned.range(of: " by ", options: .caseInsensitive) {
                return ImportedTrackCandidate(
                    title: String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                    artistGuess: String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespaces),
                    sourcePlatform: "Manual"
                )
            }
            return ImportedTrackCandidate(title: cleaned, artistGuess: "", sourcePlatform: "Manual")
        }
        return ("Imported Playlist", candidates)
    }

    private func extractSpotifyResource(from input: String) -> (type: String, id: String)? {
        let pattern = "open\\.spotify\\.com/(playlist|album|track)/([A-Za-z0-9]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let typeR = Range(match.range(at: 1), in: input),
              let idR = Range(match.range(at: 2), in: input) else {
            return nil
        }
        return (String(input[typeR]), String(input[idR]))
    }

    private func fetchSpotifyEmbed(type: String, id: String) async -> (title: String, tracks: [ImportedTrackCandidate])? {
        guard let url = URL(string: "https://open.spotify.com/embed/\(type)/\(id)") else { return nil }
        guard let (data, _) = try? await session.data(from: url),
              let html = String(data: data, encoding: .utf8) else { return nil }

        // Extract __NEXT_DATA__ JSON
        guard let startRange = html.range(of: "<script id=\"__NEXT_DATA__\" type=\"application/json\">"),
              let endRange = html.range(of: "</script>", range: startRange.upperBound..<html.endIndex) else {
            return nil
        }
        let jsonStr = String(html[startRange.upperBound..<endRange.lowerBound])
        guard let jsonData = jsonStr.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let props = root["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let state = pageProps["state"] as? [String: Any],
              let dataObj = state["data"] as? [String: Any],
              let entity = dataObj["entity"] as? [String: Any] else {
            return nil
        }

        let title = (entity["name"] as? String) ?? "Imported Spotify Playlist"
        let trackList = (entity["trackList"] as? [[String: Any]]) ?? []
        let candidates = trackList.compactMap { item -> ImportedTrackCandidate? in
            guard let t = item["title"] as? String else { return nil }
            let artist = (item["subtitle"] as? String) ?? ""
            return ImportedTrackCandidate(title: t, artistGuess: artist, sourcePlatform: "Spotify")
        }
        return (title, candidates)
    }

    private func fetchSpotifyOEmbed(url rawUrl: String) async -> ImportedTrackCandidate? {
        guard let encoded = rawUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://open.spotify.com/oembed?url=\(encoded)"),
              let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String else {
            return nil
        }
        return ImportedTrackCandidate(title: title, artistGuess: "", sourcePlatform: "Spotify")
    }
}
