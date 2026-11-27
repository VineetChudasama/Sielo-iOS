import Foundation
import SieloCoreModels

/// Mirrors core-lyrics/lrclib/LrcLibClient.kt:
/// 7-strategy search/exact cascade, token-overlap validation, [mm:ss.xx] + [offset:] LRC parser,
/// and -9700ms acoustic trim.
public actor LrcLibClient {
    public static let shared = LrcLibClient()

    private struct LrcLibResponse: Codable {
        let id: Int?
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    public func getLyrics(trackName: String, artistName: String, durationSec: Int = 0) async -> SieloLyrics? {
        let cleanTitle = cleanMetadata(trackName)
        let cleanArtist = cleanMetadata(artistName)
        let primaryArtist = cleanArtist
            .components(separatedBy: CharacterSet(charactersIn: ",&"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? cleanArtist

        let isAcoustic = trackName.lowercased().contains("acoustic") || artistName.lowercased().contains("acoustic")

        var candidates: [LrcLibResponse] = []

        if isAcoustic {
            candidates.append(contentsOf: await fetchSearch(query: "\(cleanTitle) acoustic \(primaryArtist)"))
        }
        if candidates.isEmpty {
            candidates.append(contentsOf: await fetchSearch(query: "\(cleanTitle) \(cleanArtist)"))
        }
        if candidates.isEmpty, primaryArtist != cleanArtist {
            candidates.append(contentsOf: await fetchSearch(query: "\(cleanTitle) \(primaryArtist)"))
        }
        if candidates.isEmpty {
            candidates.append(contentsOf: await fetchSearch(query: cleanTitle))
        }
        if candidates.isEmpty, let exact = await fetchExact(track: cleanTitle, artist: cleanArtist) {
            candidates.append(exact)
        }
        if candidates.isEmpty, primaryArtist != cleanArtist, let exact = await fetchExact(track: cleanTitle, artist: primaryArtist) {
            candidates.append(exact)
        }
        if candidates.isEmpty {
            candidates.append(contentsOf: await fetchSearch(query: "\(trackName) \(artistName)"))
        }

        let valid = candidates.filter { cand in
            isTrackAndArtistMatch(
                candTitle: cand.trackName ?? "",
                candArtist: cand.artistName ?? "",
                targetTitle: cleanTitle,
                targetArtist: cleanArtist
            )
        }

        let sorted = valid.sorted { a, b in
            let aSynced = !(a.syncedLyrics ?? "").isEmpty
            let bSynced = !(b.syncedLyrics ?? "").isEmpty
            if aSynced != bSynced { return aSynced }
            if durationSec > 0 {
                let dA = abs((a.duration ?? 0) - Double(durationSec))
                let dB = abs((b.duration ?? 0) - Double(durationSec))
                return dA < dB
            }
            return false
        }

        guard let best = sorted.first else { return nil }
        var lines = parseLrc(best.syncedLyrics ?? "")

        if isAcoustic, let firstTs = lines.first?.timestampMs, firstTs > 14_000, (1...175).contains(durationSec) {
            lines = lines.map { LyricLine(timestampMs: max(0, $0.timestampMs - 9700), text: $0.text) }
        }

        return SieloLyrics(
            id: best.id.map(String.init) ?? "",
            plainLyrics: best.plainLyrics,
            syncedLyrics: best.syncedLyrics,
            lines: lines
        )
    }

    private func fetchSearch(query: String) async -> [LrcLibResponse] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://lrclib.net/api/search?q=\(encoded)") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Sielo-Music-iOS-App/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: req) else { return [] }
        return (try? JSONDecoder().decode([LrcLibResponse].self, from: data)) ?? []
    }

    private func fetchExact(track: String, artist: String) async -> LrcLibResponse? {
        guard let t = track.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let a = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://lrclib.net/api/get?track_name=\(t)&artist_name=\(a)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Sielo-Music-iOS-App/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: req) else { return nil }
        return try? JSONDecoder().decode(LrcLibResponse.self, from: data)
    }

    public func cleanMetadata(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\([^)]*(official|video|audio|lyric|feat|ft\\.|acoustic|from)[^)]*\\)", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*-\\s*From\\s+\"[^\"]+\"", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isTrackAndArtistMatch(candTitle: String, candArtist: String, targetTitle: String, targetArtist: String) -> Bool {
        let cTitleTokens = Set(candTitle.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let tTitleTokens = Set(targetTitle.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        guard !cTitleTokens.isEmpty, !tTitleTokens.isEmpty else { return false }
        let titleOverlap = Double(cTitleTokens.intersection(tTitleTokens).count) / Double(tTitleTokens.count)
        guard titleOverlap >= 0.5 else { return false }

        let cArtistTokens = Set(candArtist.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let tArtistTokens = Set(targetArtist.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        guard !cArtistTokens.isEmpty, !tArtistTokens.isEmpty else { return true }
        let artistOverlap = Double(cArtistTokens.intersection(tArtistTokens).count) / Double(min(cArtistTokens.count, tArtistTokens.count))
        return artistOverlap >= 0.4
    }

    public func parseLrc(_ lrc: String) -> [LyricLine] {
        guard !lrc.isEmpty else { return [] }
        var offsetMs: Int64 = 0
        var result: [LyricLine] = []

        let tagPattern = try? NSRegularExpression(pattern: "\\[(\\d{1,2}):(\\d{2})(?:[.:](\\d{2,3}))?\\]")
        let offsetPattern = try? NSRegularExpression(pattern: "\\[offset:\\s*(-?\\d+)\\]", options: .caseInsensitive)

        for rawLine in lrc.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if let offsetMatch = offsetPattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(offsetMatch.range(at: 1), in: line),
               let val = Int64(line[range]) {
                offsetMs = val
                continue
            }

            guard let matches = tagPattern?.matches(in: line, range: NSRange(line.startIndex..., in: line)), !matches.isEmpty else {
                continue
            }

            let lastEnd = matches.last!.range.upperBound
            let textStart = line.index(line.startIndex, offsetBy: lastEnd)
            let lyricText = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
            guard !lyricText.isEmpty else { continue }

            for match in matches {
                guard let minR = Range(match.range(at: 1), in: line),
                      let secR = Range(match.range(at: 2), in: line),
                      let mins = Int64(line[minR]),
                      let secs = Int64(line[secR]) else { continue }
                var millis: Int64 = 0
                if let msR = Range(match.range(at: 3), in: line) {
                    let msStr = String(line[msR])
                    millis = (Int64(msStr) ?? 0) * (msStr.count == 2 ? 10 : 1)
                }
                let ts = max(0, (mins * 60_000) + (secs * 1000) + millis + offsetMs)
                result.append(LyricLine(timestampMs: ts, text: lyricText))
            }
        }
        return result.sorted { $0.timestampMs < $1.timestampMs }
    }
}
