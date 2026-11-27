import Foundation
import SieloCoreModels

public enum SongLanguage: String, Sendable {
    case hindi, punjabi, southIndian, english, korean, latin, other
}

public enum SongVibe: String, Sendable {
    case romantic, smoothCalm, lofi, rapHipHop, energeticParty, pop
}

/// Mirrors core-recommendations/autoplay/SongClassifier.kt & CuratedArtistClusters.kt
public enum SongClassifier {
    private static let hindiArtists: Set<String> = [
        "arijit singh", "pritam", "shreya ghoshal", "jubin nautiyal", "atif aslam",
        "armaan malik", "vishal mishra", "sachin-jigar", "sachet-parampara", "darshan raval",
        "amit trivedi", "a.r. rahman", "kk", "sonu nigam", "mohit chauhan", "badshah",
        "raftaar", "divine", "kr$na", "seedhe maut", "king", "anuv jain", "prateek kuhad"
    ]

    private static let punjabiArtists: Set<String> = [
        "diljit dosanjh", "ap dhillon", "karan aujla", "sidhu moose wala", "shubh",
        "ammy virk", "gurdas maan", "harrdy sandhu", "jass manak", "guru randhawa",
        "talwiinder", "arpit bala", "prophec", "navaan sandhu"
    ]

    private static let southArtists: Set<String> = [
        "anirudh ravichander", "yuvan shankar raja", "thaman s", "devi sri prasad",
        "sid sriram", "vijay antony", "ilayaraja", "santhosh narayanan", "gv prakash"
    ]

    public static func detectLanguage(_ track: SieloTrack) -> SongLanguage {
        let combined = "\(track.title) \(track.artist)"
        // Unicode script detection
        for scalar in combined.unicodeScalars {
            let v = scalar.value
            if (0x0A00...0x0A7F).contains(v) { return .punjabi }
            if (0x0900...0x097F).contains(v) || (0x0980...0x09FF).contains(v) || (0x0A80...0x0AFF).contains(v) { return .hindi }
            if (0x0B80...0x0DFF).contains(v) { return .southIndian }
            if (0xAC00...0xD7AF).contains(v) { return .korean }
        }

        let artistLower = track.artist.lowercased()
        if punjabiArtists.contains(where: { artistLower.contains($0) }) { return .punjabi }
        if hindiArtists.contains(where: { artistLower.contains($0) }) { return .hindi }
        if southArtists.contains(where: { artistLower.contains($0) }) { return .southIndian }
        return .english
    }

    public static func detectVibe(_ track: SieloTrack) -> SongVibe {
        let lower = "\(track.title) \(track.artist) \(track.album ?? "")".lowercased()
        if lower.contains("lofi") || lower.contains("lo-fi") || lower.contains("chill") { return .lofi }
        if lower.contains("ishq") || lower.contains("pyaar") || lower.contains("love") || lower.contains("romantic") || lower.contains("tum") { return .romantic }
        if lower.contains("rap") || lower.contains("hip hop") || lower.contains("freestyle") || lower.contains("drill") { return .rapHipHop }
        if lower.contains("party") || lower.contains("club") || lower.contains("dance") || lower.contains("bass") { return .energeticParty }
        if lower.contains("acoustic") || lower.contains("unplugged") || lower.contains("calm") { return .smoothCalm }
        return .pop
    }

    public static func isVibeCompatible(seed: SongVibe, candidate: SongVibe) -> Bool {
        switch seed {
        case .romantic, .smoothCalm, .lofi:
            return candidate != .rapHipHop && candidate != .energeticParty
        case .rapHipHop:
            return candidate == .rapHipHop || candidate == .energeticParty || candidate == .pop
        case .energeticParty:
            return candidate != .lofi
        case .pop:
            return true
        }
    }

    public static func similarArtistsCluster(for artist: String, language: SongLanguage) -> [String] {
        switch language {
        case .hindi:
            return ["Arijit Singh", "Pritam", "Vishal Mishra", "Jubin Nautiyal", "Atif Aslam", "Anuv Jain", "Amit Trivedi"]
        case .punjabi:
            return ["Diljit Dosanjh", "AP Dhillon", "Karan Aujla", "Shubh", "Talwiinder", "Sidhu Moose Wala"]
        case .southIndian:
            return ["Anirudh Ravichander", "Sid Sriram", "Yuvan Shankar Raja", "A.R. Rahman", "Santhosh Narayanan"]
        case .korean:
            return ["BTS", "BLACKPINK", "NewJeans", "Stray Kids", "IU"]
        default:
            return ["The Weeknd", "Drake", "Taylor Swift", "Post Malone", "Billie Eilish", "Coldplay"]
        }
    }
}
