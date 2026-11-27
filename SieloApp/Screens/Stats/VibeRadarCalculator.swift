import Foundation
import SieloCoreDatabase

public struct VibeRadarMetric: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let value: Float // 0..100
    public let insightSummary: String
}

public struct VibeRadarData: Sendable {
    public let hasData: Bool
    public let energy: VibeRadarMetric
    public let replay: VibeRadarMetric
    public let consistency: VibeRadarMetric
    public let discovery: VibeRadarMetric
    public let mood: VibeRadarMetric
    public let soundDnaSummary: String

    public var metricsList: [VibeRadarMetric] {
        [energy, replay, consistency, discovery, mood]
    }
}

public enum StatsTimeframe: String, CaseIterable, Identifiable {
    case week1 = "1 Week"
    case month1 = "1 Month"
    case year1 = "1 Year"
    case allTime = "All Time"

    public var id: String { rawValue }
    public var days: Int {
        switch self {
        case .week1: return 7
        case .month1: return 30
        case .year1: return 365
        case .allTime: return 36500
        }
    }
}

/// Deterministic AudioFeatureEstimator + VibeRadarCalculator matching Android's VibeRadarCalculator.kt.
public enum VibeRadarCalculator {
    private static let highEnergyWords = ["remix", "dj", "club", "party", "bass", "trap", "rock", "metal", "workout", "fast", "pump"]
    private static let lowEnergyWords = ["lofi", "lo-fi", "acoustic", "unplugged", "chill", "sleep", "ambient", "piano", "rain", "slow"]
    private static let highMoodWords = ["happy", "love", "sun", "dance", "summer", "vibe", "celebrate", "joy", "party", "smile"]
    private static let lowMoodWords = ["sad", "cry", "broken", "heartbreak", "lonely", "pain", "tears", "dark", "miss", "alone"]

    public static func estimateFeatures(title: String, artist: String, durationMs: Int64) -> (energy: Float, mood: Float) {
        let combined = "\(title) \(artist)".lowercased()
        var energy: Float = 0.55
        var mood: Float = 0.52

        for w in highEnergyWords where combined.contains(w) { energy += 0.12 }
        for w in lowEnergyWords where combined.contains(w) { energy -= 0.14 }
        for w in highMoodWords where combined.contains(w) { mood += 0.12 }
        for w in lowMoodWords where combined.contains(w) { mood -= 0.14 }

        let durSec = durationMs / 1000
        if (60...180).contains(durSec) { energy += 0.05 }
        else if durSec > 320 { energy -= 0.06 }

        return (min(0.95, max(0.15, energy)), min(0.94, max(0.12, mood)))
    }

    public static func calculate(
        totalListeningTimeMs: Int64,
        totalUniqueSongs: Int,
        totalUniqueArtists: Int,
        totalStreamCount: Int,
        streamHistory: [ListeningEventEntity],
        timeframe: StatsTimeframe
    ) -> VibeRadarData {
        guard totalStreamCount > 0, totalListeningTimeMs > 0 else {
            return VibeRadarData(
                hasData: false,
                energy: VibeRadarMetric(id: "energy", label: "Energy", value: 0, insightSummary: "Listen to your first tracks to map your musical energy."),
                replay: VibeRadarMetric(id: "replay", label: "Replay", value: 0, insightSummary: "Replaying favorite songs increases this score."),
                consistency: VibeRadarMetric(id: "consistency", label: "Consistency", value: 0, insightSummary: "Listening regularly boosts consistency."),
                discovery: VibeRadarMetric(id: "discovery", label: "Discovery", value: 0, insightSummary: "Exploring new artists expands your discovery horizon."),
                mood: VibeRadarMetric(id: "mood", label: "Mood", value: 0, insightSummary: "Play music to uncover your overall listening vibe."),
                soundDnaSummary: "Your Sound DNA is waiting. Start streaming to reveal your personal music pattern."
            )
        }

        // Energy & Mood weighted average
        var energySum: Float = 0
        var moodSum: Float = 0
        for ev in streamHistory {
            let est = estimateFeatures(title: ev.songTitle, artist: ev.artistName, durationMs: ev.songDurationMs)
            energySum += est.energy
            moodSum += est.mood
        }
        let count = max(1, Float(streamHistory.count))
        let energyScore = min(100, max(0, (energySum / count) * 100))
        let moodScore = min(100, max(0, (moodSum / count) * 100))

        // Replay
        let uniqueRatio = Float(totalUniqueSongs) / Float(max(1, totalStreamCount))
        let replayScore = min(100, max(0, ((1.0 - uniqueRatio) / 0.75) * 100))

        // Consistency
        let cal = Calendar.current
        let activeDays = Set(streamHistory.map {
            cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.timestampMs) / 1000))
        }).count
        let periodDays = min(timeframe.days, 90)
        let consistencyScore = min(100, max(0, (Float(activeDays) / Float(max(1, periodDays))) * 100))

        // Discovery
        let artistVariety = Float(totalUniqueArtists) / Float(max(1, totalUniqueSongs))
        let targetTracks: Float = timeframe == .week1 ? 15 : (timeframe == .month1 ? 45 : (timeframe == .year1 ? 180 : 100))
        let volumeRatio = min(1.0, Float(totalUniqueSongs) / targetTracks)
        let discoveryScore = min(100, max(0, ((artistVariety * 0.45) + (volumeRatio * 0.55)) * 100))

        let dna1 = replayScore > 55 ? "Loyal" : "Progressive"
        let dna2 = discoveryScore > 55 ? "Explorer" : "Specialist"
        let dna3 = consistencyScore > 50 ? "Daily Ritual" : "Spontaneous"

        return VibeRadarData(
            hasData: true,
            energy: VibeRadarMetric(id: "energy", label: "Energy", value: energyScore, insightSummary: "Intensity and dynamic drive across your top plays."),
            replay: VibeRadarMetric(id: "replay", label: "Replay", value: replayScore, insightSummary: "How often you return to your favorite tracks."),
            consistency: VibeRadarMetric(id: "consistency", label: "Consistency", value: consistencyScore, insightSummary: "Active listening days across \(timeframe.rawValue)."),
            discovery: VibeRadarMetric(id: "discovery", label: "Discovery", value: discoveryScore, insightSummary: "Breadth of unique artists & catalog exploration."),
            mood: VibeRadarMetric(id: "mood", label: "Mood", value: moodScore, insightSummary: "Overall tonal brightness and emotional valence."),
            soundDnaSummary: "\(dna1) · \(dna2) · \(dna3)"
        )
    }
}
