import Foundation
import GRDB

public final class SieloDatabase: Sendable {
    public let dbWriter: any DatabaseWriter

    public let favorites: FavoriteTrackDao
    public let listeningHistory: ListeningHistoryDao
    public let searchHistory: SearchHistoryDao
    public let searchPlayHistory: SearchPlayHistoryDao
    public let recommendationHistory: RecommendationHistoryDao
    public let similarArtistCache: SimilarArtistCacheDao
    public let artistCountryCache: ArtistCountryCacheDao

    public static func openDefault() throws -> SieloDatabase {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbURL = appSupport.appendingPathComponent("sielo_music.db")
        let pool = try DatabasePool(path: dbURL.path)
        return try SieloDatabase(dbWriter: pool)
    }

    public static func openInMemory() throws -> SieloDatabase {
        let queue = try DatabaseQueue()
        return try SieloDatabase(dbWriter: queue)
    }

    public init(dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try Self.migrator.migrate(dbWriter)
        self.favorites = FavoriteTrackDao(dbWriter: dbWriter)
        self.listeningHistory = ListeningHistoryDao(dbWriter: dbWriter)
        self.searchHistory = SearchHistoryDao(dbWriter: dbWriter)
        self.searchPlayHistory = SearchPlayHistoryDao(dbWriter: dbWriter)
        self.recommendationHistory = RecommendationHistoryDao(dbWriter: dbWriter)
        self.similarArtistCache = SimilarArtistCacheDao(dbWriter: dbWriter)
        self.artistCountryCache = ArtistCountryCacheDao(dbWriter: dbWriter)
    }

    public func clearAllTables() async throws {
        try await dbWriter.write { db in
            try FavoriteTrackEntity.deleteAll(db)
            try ListeningEventEntity.deleteAll(db)
            try SearchHistoryEntity.deleteAll(db)
            try SearchPlayHistoryEntity.deleteAll(db)
            try RecommendationHistoryEntity.deleteAll(db)
            try SimilarArtistCacheEntity.deleteAll(db)
            try ArtistCountryCacheEntity.deleteAll(db)
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_sielo_schema") { db in
            try db.create(table: "favorites") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("thumbnailUrl", .text)
                t.column("addedAt", .integer).notNull()
            }

            try db.create(table: "listening_history") { t in
                t.autoIncrementedPrimaryKey("eventId")
                t.column("songId", .text).notNull()
                t.column("songTitle", .text).notNull()
                t.column("artistName", .text).notNull()
                t.column("albumName", .text)
                t.column("thumbnailUrl", .text)
                t.column("timestampMs", .integer).notNull()
                t.column("durationPlayedMs", .integer).notNull()
                t.column("songDurationMs", .integer).notNull().defaults(to: 0)
                t.column("hourOfDay", .integer).notNull()
                t.column("dayOfWeek", .integer).notNull()
                t.column("month", .integer).notNull()
                t.column("year", .integer).notNull()
                t.column("completed", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "idx_listening_songId", on: "listening_history", columns: ["songId"])
            try db.create(index: "idx_listening_timestamp", on: "listening_history", columns: ["timestampMs"])
            try db.create(index: "idx_listening_artist", on: "listening_history", columns: ["artistName"])

            try db.create(table: "search_history") { t in
                t.column("query", .text).primaryKey()
                t.column("timestampMs", .integer).notNull()
            }

            try db.create(table: "search_play_history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("songId", .text).notNull()
                t.column("songTitle", .text).notNull()
                t.column("artistName", .text).notNull()
                t.column("albumName", .text)
                t.column("thumbnailUrl", .text)
                t.column("playedAtMs", .integer).notNull()
            }

            try db.create(table: "recommendation_history") { t in
                t.column("songId", .text).primaryKey()
                t.column("lastRecommendedDate", .text).notNull()
            }

            try db.create(table: "similar_artist_cache") { t in
                t.column("seedArtistId", .text).primaryKey()
                t.column("resultsJson", .text).notNull()
                t.column("cachedAt", .integer).notNull()
            }

            try db.create(table: "artist_country_cache") { t in
                t.column("artistName", .text).primaryKey()
                t.column("country", .text)
                t.column("cachedAt", .integer).notNull()
            }
        }

        return migrator
    }
}

public final class DatabaseCleaner: Sendable {
    private let database: SieloDatabase

    public init(database: SieloDatabase) {
        self.database = database
    }

    public func clearAll() async throws {
        try await database.clearAllTables()
    }
}
