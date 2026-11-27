import Foundation
import SieloCoreModels

/// Exact Swift port of core-network/innertube/TrackMatchValidator.kt
public enum TrackMatchValidator {
    private static let noiseWords: Set<String> = [
        "official", "video", "audio", "lyric", "lyrics", "hd", "4k", "mv",
        "feat", "ft", "featuring", "remix", "version", "edit", "explicit", "clean",
        "from", "the", "a", "an", "and", "or", "by", "full", "song", "music"
    ]

    public static func normalize(_ raw: String) -> String {
        let lower = raw.lowercased()
            .replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
        return lower
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    public static func tokenize(_ raw: String) -> [String] {
        normalize(raw)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !noiseWords.contains($0) && $0.count > 1 }
    }

    public static func isStrictArtistMatch(_ candidateArtist: String, _ targetArtist: String) -> Bool {
        let cNorm = normalize(candidateArtist)
        let tNorm = normalize(targetArtist)
        guard !cNorm.isEmpty, !tNorm.isEmpty else { return false }
        if cNorm == tNorm || cNorm.contains(tNorm) || tNorm.contains(cNorm) { return true }

        let cTokens = Set(tokenize(candidateArtist))
        let tTokens = Set(tokenize(targetArtist))
        guard !cTokens.isEmpty, !tTokens.isEmpty else { return false }
        let overlap = cTokens.intersection(tTokens).count
        return Double(overlap) / Double(min(cTokens.count, tTokens.count)) >= 0.6
    }

    public static func isFuzzyMatch(
        candidateTitle: String,
        candidateArtist: String,
        targetTitle: String,
        targetArtist: String
    ) -> Bool {
        guard isStrictArtistMatch(candidateArtist, targetArtist) else { return false }
        let cTokens = Set(tokenize(candidateTitle))
        let tTokens = Set(tokenize(targetTitle))
        guard !cTokens.isEmpty, !tTokens.isEmpty else {
            return normalize(candidateTitle) == normalize(targetTitle)
        }
        let overlap = cTokens.intersection(tTokens).count
        let ratio = Double(overlap) / Double(tTokens.count)
        if tTokens.count <= 2 {
            return overlap == tTokens.count
        }
        return ratio >= 0.6
    }

    public static func isCleanOrCensored(_ title: String) -> Bool {
        let lower = title.lowercased()
        let patterns = [
            "(clean)", "[clean]", "clean version", "clean edit",
            "(censored)", "[censored]", "radio edit", "(edited)", "[edited]"
        ]
        return patterns.contains { lower.contains($0) }
    }

    public static func isCoverOrKaraokeTrack(_ title: String, artist: String = "") -> Bool {
        let combined = "\(title) \(artist)".lowercased()
        let patterns = [
            "karaoke", "instrumental", "cover version", "tribute to",
            "originally performed by", "made famous by", "8d audio",
            "slowed + reverb", "slowed and reverb", "sped up", "nightcore", "8-bit"
        ]
        return patterns.contains { combined.contains($0) }
    }

    public static func isMusicVideoTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower.contains("official video")
            || lower.contains("music video")
            || lower.contains("(mv)")
            || lower.contains("video song")
            || lower.contains("lyrical video")
    }

    public static func isCompilationAlbum(_ title: String) -> Bool {
        let lower = title.lowercased()
        let markers = [
            "greatest hits", "best of", "top hits", "top 10", "top 20", "top 50",
            "collection", "anthology", "essential", "essentials", "non-stop",
            "mashup", "jukebox", "playlist", "party hits", "romantic hits"
        ]
        return markers.contains { lower.contains($0) }
    }

    public static func isSoundtrackRelease(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower.contains("original motion picture")
            || lower.contains("soundtrack")
            || lower.contains("(ost)")
            || lower.contains("from \"")
    }

    public static func isAlbumMadeByArtist(_ albumArtist: String, targetArtist: String) -> Bool {
        let lower = albumArtist.lowercased()
        if lower.contains("various artists") || lower.contains("karaoke") || lower.contains("tribute") {
            return false
        }
        return isStrictArtistMatch(albumArtist, targetArtist)
    }

    public static func isYouTubeChannelId(_ id: String) -> Bool {
        id.hasPrefix("UC") && id.count >= 20
    }

    public static func isSongByOrFeaturingArtist(_ track: SieloTrack, targetArtist: String) -> Bool {
        isStrictArtistMatch(track.artist, targetArtist) ||
            track.title.lowercased().contains(targetArtist.lowercased())
    }

    public static func canonicalTrackKey(_ track: SieloTrack) -> String {
        let titleKey = tokenize(track.title).sorted().joined(separator: "_")
        let primaryArtist = track.artist
            .components(separatedBy: CharacterSet(charactersIn: ",&"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? track.artist
        let artistKey = tokenize(primaryArtist).sorted().joined(separator: "_")
        return "\(titleKey)::\(artistKey)"
    }

    public static func deduplicateTracks(_ tracks: [SieloTrack]) -> [SieloTrack] {
        var bestByKey: [String: SieloTrack] = [:]
        var order: [String] = []

        for track in tracks {
            guard !isCleanOrCensored(track.title) else { continue }
            let key = canonicalTrackKey(track)
            if let existing = bestByKey[key] {
                if scoreTrack(track) > scoreTrack(existing) {
                    bestByKey[key] = track
                }
            } else {
                bestByKey[key] = track
                order.append(key)
            }
        }
        return order.compactMap { bestByKey[$0] }
    }

    private static func scoreTrack(_ track: SieloTrack) -> Int {
        var score = 0
        if !isCoverOrKaraokeTrack(track.title, artist: track.artist) { score += 100 }
        if track.isExplicit { score += 40 }
        if !isCleanOrCensored(track.title) { score += 30 }
        if !isMusicVideoTitle(track.title) { score += 20 }
        if let thumb = track.thumbnailUrl, !thumb.contains("ytimg.com") { score += 10 }
        if let album = track.album, !isCompilationAlbum(album) { score += 10 }
        if track.streamUrl != nil { score += 5 }
        return score
    }
}
