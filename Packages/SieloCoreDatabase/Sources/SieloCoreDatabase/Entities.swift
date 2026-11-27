import Foundation
import GRDB

// MARK: - 1. FavoriteTrackEntity (table: favorites)

public struct FavoriteTrackEntity: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "favorites"

    public let id: String
    public var title: String
    public var artist: String
    public var thumbnailUrl: String?
    public var addedAt: Int64

    public init(
        id: String,
        title: String,
        artist: String,
        thumbnailUrl: String? = nil,
        addedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.thumbnailUrl = thumbnailUrl
        self.addedAt = addedAt
    }
}

// MARK: - 2. ListeningEventEntity (table: listening_history)

public struct ListeningEventEntity: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "listening_history"

    public var id: Int64? { eventId }
    public var eventId: Int64?
    public var songId: String
    public var songTitle: String
    public var artistName: String
    public var albumName: String?
    public var thumbnailUrl: String?
    public var timestampMs: Int64
    public var durationPlayedMs: Int64
    public var songDurationMs: Int64
    public var hourOfDay: Int
    public var dayOfWeek: Int
    public var month: Int
    public var year: Int
    public var completed: Bool

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        eventId = inserted.rowID
    }

    public init(
        eventId: Int64? = nil,
        songId: String,
        songTitle: String,
        artistName: String,
        albumName: String? = nil,
        thumbnailUrl: String? = nil,
        timestampMs: Int64,
        durationPlayedMs: Int64,
        songDurationMs: Int64 = 0,
        hourOfDay: Int,
        dayOfWeek: Int,
        month: Int,
        year: Int,
        completed: Bool = false
    ) {
        self.eventId = eventId
        self.songId = songId
        self.songTitle = songTitle
        self.artistName = artistName
        self.albumName = albumName
        self.thumbnailUrl = thumbnailUrl
        self.timestampMs = timestampMs
        self.durationPlayedMs = durationPlayedMs
        self.songDurationMs = songDurationMs
        self.hourOfDay = hourOfDay
        self.dayOfWeek = dayOfWeek
        self.month = month
        self.year = year
        self.completed = completed
    }
}

// MARK: - 3. SearchHistoryEntity (table: search_history)

public struct SearchHistoryEntity: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "search_history"
    public var id: String { query }

    public let query: String
    public var timestampMs: Int64

    public init(query: String, timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.query = query
        self.timestampMs = timestampMs
    }
}

// MARK: - 4. SearchPlayHistoryEntity (table: search_play_history)

public struct SearchPlayHistoryEntity: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "search_play_history"

    public var id: Int64?
    public var songId: String
    public var songTitle: String
    public var artistName: String
    public var albumName: String?
    public var thumbnailUrl: String?
    public var playedAtMs: Int64

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(
        id: Int64? = nil,
        songId: String,
        songTitle: String,
        artistName: String,
        albumName: String? = nil,
        thumbnailUrl: String? = nil,
        playedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.songId = songId
        self.songTitle = songTitle
        self.artistName = artistName
        self.albumName = albumName
        self.thumbnailUrl = thumbnailUrl
        self.playedAtMs = playedAtMs
    }
}

// MARK: - 5. RecommendationHistoryEntity (table: recommendation_history)

public struct RecommendationHistoryEntity: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "recommendation_history"
    public var id: String { songId }

    public let songId: String
    public var lastRecommendedDate: String // ISO yyyy-MM-dd

    public init(songId: String, lastRecommendedDate: String) {
        self.songId = songId
        self.lastRecommendedDate = lastRecommendedDate
    }
}

// MARK: - 6. SimilarArtistCacheEntity (table: similar_artist_cache)

public struct SimilarArtistCacheEntity: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "similar_artist_cache"
    public var id: String { seedArtistId }

    public let seedArtistId: String
    public var resultsJson: String
    public var cachedAt: Int64

    public init(seedArtistId: String, resultsJson: String, cachedAt: Int64) {
        self.seedArtistId = seedArtistId
        self.resultsJson = resultsJson
        self.cachedAt = cachedAt
    }
}

// MARK: - 7. ArtistCountryCacheEntity (table: artist_country_cache)

public struct ArtistCountryCacheEntity: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "artist_country_cache"
    public var id: String { artistName }

    public let artistName: String
    public var country: String?
    public var cachedAt: Int64

    public init(artistName: String, country: String?, cachedAt: Int64) {
        self.artistName = artistName
        self.country = country
        self.cachedAt = cachedAt
    }
}

// MARK: - Aggregated Stat Projections

public struct ArtistStat: Codable, FetchableRecord, Hashable, Sendable {
    public let artistName: String
    public let playCount: Int
    public let totalDurationMs: Int64
    public let thumbnailUrl: String?
}

public struct SongStat: Codable, FetchableRecord, Hashable, Sendable {
    public let songId: String
    public let songTitle: String
    public let artistName: String
    public let playCount: Int
    public let totalDurationMs: Int64
    public let thumbnailUrl: String?
}

public struct CandidateSongStat: Codable, FetchableRecord, Hashable, Sendable {
    public let songId: String
    public let songTitle: String
    public let artistName: String
    public let albumName: String?
    public let thumbnailUrl: String?
    public let playCount: Int
    public let lastPlayedMs: Int64
}

public struct HourCount: Codable, FetchableRecord, Hashable, Sendable {
    public let hourOfDay: Int
    public let count: Int
    public let totalDurationMs: Int64
}
