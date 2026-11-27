import Foundation
import GRDB

// MARK: - 1. FavoriteTrackDao

public final class FavoriteTrackDao: Sendable {
    private let dbWriter: any DatabaseWriter
    public init(dbWriter: any DatabaseWriter) { self.dbWriter = dbWriter }

    public func observeAllFavorites() -> AsyncThrowingStream<[FavoriteTrackEntity], Error> {
        ValueObservation
            .tracking { db in
                try FavoriteTrackEntity.order(Column("addedAt").desc).fetchAll(db)
            }
            .values(in: dbWriter)
            .eraseToStream()
    }

    public func getAllFavoritesList() async throws -> [FavoriteTrackEntity] {
        try await dbWriter.read { db in
            try FavoriteTrackEntity.order(Column("addedAt").desc).fetchAll(db)
        }
    }

    public func observeIsFavorite(id: String) -> AsyncThrowingStream<Bool, Error> {
        ValueObservation
            .tracking { db in
                try FavoriteTrackEntity.filter(Column("id") == id).fetchCount(db) > 0
            }
            .values(in: dbWriter)
            .eraseToStream()
    }

    public func isFavorite(id: String) async throws -> Bool {
        try await dbWriter.read { db in
            try FavoriteTrackEntity.filter(Column("id") == id).fetchCount(db) > 0
        }
    }

    public func insertFavorite(_ track: FavoriteTrackEntity) async throws {
        try await dbWriter.write { db in
            try track.save(db)
        }
    }

    public func insertFavorites(_ tracks: [FavoriteTrackEntity]) async throws {
        try await dbWriter.write { db in
            for track in tracks {
                try track.save(db)
            }
        }
    }

    public func deleteById(_ id: String) async throws {
        _ = try await dbWriter.write { db in
            try FavoriteTrackEntity.deleteOne(db, key: id)
        }
    }

    public func clearAll() async throws {
        _ = try await dbWriter.write { db in
            try FavoriteTrackEntity.deleteAll(db)
        }
    }
}

// MARK: - 2. ListeningHistoryDao

public final class ListeningHistoryDao: Sendable {
    private let dbWriter: any DatabaseWriter
    public init(dbWriter: any DatabaseWriter) { self.dbWriter = dbWriter }

    @discardableResult
    public func insertEvent(_ event: ListeningEventEntity) async throws -> Int64 {
        try await dbWriter.write { db in
            var copy = event
            try copy.insert(db)
            return copy.eventId ?? 0
        }
    }

    public func insertEvents(_ events: [ListeningEventEntity]) async throws {
        try await dbWriter.write { db in
            for var event in events {
                try event.save(db)
            }
        }
    }

    public func observeRecentHistory(limit: Int = 20) -> AsyncThrowingStream<[ListeningEventEntity], Error> {
        ValueObservation
            .tracking { db in
                try ListeningEventEntity
                    .filter(Column("durationPlayedMs") >= 5000)
                    .order(Column("timestampMs").desc)
                    .limit(limit)
                    .fetchAll(db)
            }
            .values(in: dbWriter)
            .eraseToStream()
    }

    public func observeTotalListeningTime(sinceMs: Int64) -> AsyncThrowingStream<Int64, Error> {
        ValueObservation
            .tracking { db in
                let total: Int64? = try Int64.fetchOne(
                    db,
                    sql: "SELECT SUM(durationPlayedMs) FROM listening_history WHERE timestampMs >= ? AND durationPlayedMs >= 5000",
                    arguments: [sinceMs]
                )
                return total ?? 0
            }
            .values(in: dbWriter)
            .eraseToStream()
    }

    public func observeTotalUniqueSongs(sinceMs: Int64) -> AsyncThrowingStream<Int, Error> {
        ValueObservation
            .tracking { db in
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(DISTINCT songId) FROM listening_history WHERE timestampMs >= ? AND durationPlayedMs >= 5000",
                    arguments: [sinceMs]
                ) ?? 0
            }
            .values(in: dbWriter)
            .eraseToStream()
    }

    public func observeTotalUniqueArtists(sinceMs: Int64) -> AsyncThrowingStream<Int, Error> {
        ValueObservation
            .tracking { db in
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(DISTINCT artistName) FROM listening_history WHERE timestampMs >= ? AND durationPlayedMs >= 5000",
                    arguments: [sinceMs]
                ) ?? 0
            }
            .values(in: dbWriter)
            .eraseToStream()
    }

    public func observeTopArtists(sinceMs: Int64, limit: Int = 5) -> AsyncThrowingStream<[ArtistStat], Error> {
        ValueObservation
            .tracking { db in
                try ArtistStat.fetchAll(
                    db,
                    sql: """
                        SELECT artistName, COUNT(*) as playCount, SUM(durationPlayedMs) as totalDurationMs, MAX(thumbnailUrl) as thumbnailUrl
                        FROM listening_history
                        WHERE timestampMs >= ? AND durationPlayedMs >= 5000
                        GROUP BY artistName
                        ORDER BY playCount DESC
                        LIMIT ?
                    """,
                    arguments: [sinceMs, limit]
                )
            }
            .values(in: dbWriter)
            .eraseToStream()
    }

    public func observeTopSongs(sinceMs: Int64, limit: Int = 10) -> AsyncThrowingStream<[SongStat], Error> {
        ValueObservation
            .tracking { db in
                try SongStat.fetchAll(
                    db,
                    sql: """
                        SELECT songId, songTitle, artistName, COUNT(*) as playCount, SUM(durationPlayedMs) as totalDurationMs, MAX(thumbnailUrl) as thumbnailUrl
                        FROM listening_history
                        WHERE timestampMs >= ? AND durationPlayedMs >= 5000
                        GROUP BY songId
                        ORDER BY playCount DESC
                        LIMIT ?
                    """,
                    arguments: [sinceMs, limit]
                )
            }
            .values(in: dbWriter)
            .eraseToStream()
    }

    public func observeHourlyDistribution(sinceMs: Int64) -> AsyncThrowingStream<[HourCount], Error> {
        ValueObservation
            .tracking { db in
                try HourCount.fetchAll(
                    db,
                    sql: "SELECT hourOfDay, COUNT(*) as count, SUM(durationPlayedMs) as totalDurationMs FROM listening_history WHERE timestampMs >= ? AND durationPlayedMs >= 5000 GROUP BY hourOfDay",
                    arguments: [sinceMs]
                )
            }
            .values(in: dbWriter)
            .eraseToStream()
    }

    public func observeStreamHistory(sinceMs: Int64, limit: Int = 100) -> AsyncThrowingStream<[ListeningEventEntity], Error> {
        ValueObservation
            .tracking { db in
                try ListeningEventEntity.fetchAll(
                    db,
                    sql: "SELECT * FROM listening_history WHERE timestampMs >= ? AND durationPlayedMs >= 5000 ORDER BY timestampMs DESC LIMIT ?",
                    arguments: [sinceMs, limit]
                )
            }
            .values(in: dbWriter)
            .eraseToStream()
    }

    public func observeTotalStreamCount(sinceMs: Int64) -> AsyncThrowingStream<Int, Error> {
        ValueObservation
            .tracking { db in
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM listening_history WHERE timestampMs >= ? AND durationPlayedMs >= 5000",
                    arguments: [sinceMs]
                ) ?? 0
            }
            .values(in: dbWriter)
            .eraseToStream()
    }

    public func observeRecentUniquePlayedSongs(limit: Int = 10) -> AsyncThrowingStream<[ListeningEventEntity], Error> {
        ValueObservation
            .tracking { db in
                try ListeningEventEntity.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM listening_history
                        WHERE durationPlayedMs >= 5000
                          AND eventId IN (
                            SELECT MAX(eventId) FROM listening_history WHERE durationPlayedMs >= 5000 GROUP BY songId
                          )
                        ORDER BY timestampMs DESC
                        LIMIT ?
                    """,
                    arguments: [limit]
                )
            }
            .values(in: dbWriter)
            .eraseToStream()
    }

    public func updateDurationPlayed(eventId: Int64, durationMs: Int64) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: "UPDATE listening_history SET durationPlayedMs = ? WHERE eventId = ?",
                arguments: [durationMs, eventId]
            )
        }
    }

    public func updateSongDuration(eventId: Int64, songDurationMs: Int64) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: "UPDATE listening_history SET songDurationMs = ? WHERE eventId = ? AND (songDurationMs = 0 OR songDurationMs IS NULL)",
                arguments: [songDurationMs, eventId]
            )
        }
    }

    public func updateSongDurationBySongId(songId: String, songDurationMs: Int64) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: "UPDATE listening_history SET songDurationMs = ? WHERE songId = ? AND (songDurationMs = 0 OR songDurationMs IS NULL)",
                arguments: [songDurationMs, songId]
            )
        }
    }

    public func sanitizeLegacyRecords() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: """
                UPDATE listening_history
                SET durationPlayedMs = CASE
                    WHEN songDurationMs > 0 AND durationPlayedMs > songDurationMs THEN songDurationMs
                    WHEN durationPlayedMs > 14400000 THEN 14400000
                    ELSE durationPlayedMs
                END
                WHERE (songDurationMs > 0 AND durationPlayedMs > songDurationMs) OR durationPlayedMs > 14400000
            """)
        }
    }

    public func purgeSubThresholdRecords() async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM listening_history WHERE durationPlayedMs < 5000")
        }
    }

    public func getSongsByArtists(_ artistNames: [String]) async throws -> [CandidateSongStat] {
        guard !artistNames.isEmpty else { return [] }
        return try await dbWriter.read { db in
            let placeholders = Array(repeating: "?", count: artistNames.count).joined(separator: ",")
            return try CandidateSongStat.fetchAll(
                db,
                sql: """
                    SELECT songId, songTitle, artistName, albumName, thumbnailUrl, COUNT(*) as playCount, MAX(timestampMs) as lastPlayedMs
                    FROM listening_history
                    WHERE artistName IN (\(placeholders)) AND durationPlayedMs >= 5000
                    GROUP BY songId
                    ORDER BY playCount DESC
                """,
                arguments: StatementArguments(artistNames)
            )
        }
    }

    public func getSongsByPlayCountRange(sinceMs: Int64, minPlays: Int = 2, maxPlays: Int = 5) async throws -> [CandidateSongStat] {
        try await dbWriter.read { db in
            try CandidateSongStat.fetchAll(
                db,
                sql: """
                    SELECT songId, songTitle, artistName, albumName, thumbnailUrl, COUNT(*) as playCount, MAX(timestampMs) as lastPlayedMs
                    FROM listening_history
                    WHERE timestampMs >= ? AND durationPlayedMs >= 5000
                    GROUP BY songId
                    HAVING COUNT(*) >= ? AND COUNT(*) <= ?
                    ORDER BY lastPlayedMs DESC
                """,
                arguments: [sinceMs, minPlays, maxPlays]
            )
        }
    }

    public func getTopArtistsSnapshot(sinceMs: Int64, limit: Int = 10) async throws -> [ArtistStat] {
        try await dbWriter.read { db in
            try ArtistStat.fetchAll(
                db,
                sql: """
                    SELECT artistName, COUNT(*) as playCount, SUM(durationPlayedMs) as totalDurationMs, MAX(thumbnailUrl) as thumbnailUrl
                    FROM listening_history
                    WHERE timestampMs >= ? AND durationPlayedMs >= 5000
                    GROUP BY artistName
                    ORDER BY playCount DESC
                    LIMIT ?
                """,
                arguments: [sinceMs, limit]
            )
        }
    }

    public func getSongIdsPlayedSince(_ sinceMs: Int64) async throws -> [String] {
        try await dbWriter.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT DISTINCT songId FROM listening_history WHERE timestampMs >= ?",
                arguments: [sinceMs]
            )
        }
    }

    public func getTopSongsSnapshot(sinceMs: Int64, limit: Int = 30) async throws -> [SongStat] {
        try await dbWriter.read { db in
            try SongStat.fetchAll(
                db,
                sql: """
                    SELECT songId, songTitle, artistName, COUNT(*) as playCount, SUM(durationPlayedMs) as totalDurationMs, MAX(thumbnailUrl) as thumbnailUrl
                    FROM listening_history
                    WHERE timestampMs >= ? AND durationPlayedMs >= 5000
                    GROUP BY songId
                    ORDER BY playCount DESC
                    LIMIT ?
                """,
                arguments: [sinceMs, limit]
            )
        }
    }

    public func getAllHistoryList(limit: Int = 1500) async throws -> [ListeningEventEntity] {
        try await dbWriter.read { db in
            try ListeningEventEntity
                .order(Column("timestampMs").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func clearAll() async throws {
        _ = try await dbWriter.write { db in
            try ListeningEventEntity.deleteAll(db)
        }
    }
}

// MARK: - 3. SearchHistoryDao

public final class SearchHistoryDao: Sendable {
    private let dbWriter: any DatabaseWriter
    public init(dbWriter: any DatabaseWriter) { self.dbWriter = dbWriter }

    public func insertSearchQuery(_ item: SearchHistoryEntity) async throws {
        try await dbWriter.write { db in try item.save(db) }
    }

    public func insertSearchQueries(_ items: [SearchHistoryEntity]) async throws {
        try await dbWriter.write { db in
            for item in items { try item.save(db) }
        }
    }

    public func observeRecentSearchQueries(limit: Int = 15) -> AsyncThrowingStream<[SearchHistoryEntity], Error> {
        ValueObservation
            .tracking { db in
                try SearchHistoryEntity.order(Column("timestampMs").desc).limit(limit).fetchAll(db)
            }
            .values(in: dbWriter)
            .eraseToStream()
    }

    public func getAllSearchQueries() async throws -> [SearchHistoryEntity] {
        try await dbWriter.read { db in
            try SearchHistoryEntity.order(Column("timestampMs").desc).fetchAll(db)
        }
    }

    public func deleteSearchQuery(_ query: String) async throws {
        _ = try await dbWriter.write { db in
            try SearchHistoryEntity.deleteOne(db, key: query)
        }
    }

    public func clearAllSearchHistory() async throws {
        _ = try await dbWriter.write { db in
            try SearchHistoryEntity.deleteAll(db)
        }
    }
}

// MARK: - 4. SearchPlayHistoryDao

public final class SearchPlayHistoryDao: Sendable {
    private let dbWriter: any DatabaseWriter
    public init(dbWriter: any DatabaseWriter) { self.dbWriter = dbWriter }

    public func insertSearchPlay(_ item: SearchPlayHistoryEntity) async throws {
        try await dbWriter.write { db in
            var copy = item
            try copy.insert(db)
        }
    }

    public func observeRecentSearchPlays(limit: Int = 15) -> AsyncThrowingStream<[SearchPlayHistoryEntity], Error> {
        ValueObservation
            .tracking { db in
                try SearchPlayHistoryEntity.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM search_play_history
                        WHERE id IN (SELECT MAX(id) FROM search_play_history GROUP BY songId)
                        ORDER BY playedAtMs DESC
                        LIMIT ?
                    """,
                    arguments: [limit]
                )
            }
            .values(in: dbWriter)
            .eraseToStream()
    }

    public func clearSearchPlays() async throws {
        _ = try await dbWriter.write { db in
            try SearchPlayHistoryEntity.deleteAll(db)
        }
    }
}

// MARK: - 5. RecommendationHistoryDao (Same-Day Duplicate Shield)

public final class RecommendationHistoryDao: Sendable {
    private let dbWriter: any DatabaseWriter
    public init(dbWriter: any DatabaseWriter) { self.dbWriter = dbWriter }

    public func getIneligibleSongIds(todayDate: String) async throws -> [String] {
        try await dbWriter.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT songId FROM recommendation_history WHERE lastRecommendedDate = ?",
                arguments: [todayDate]
            )
        }
    }

    public func markRecommended(songIds: [String], date: String) async throws {
        try await dbWriter.write { db in
            for songId in songIds {
                try RecommendationHistoryEntity(songId: songId, lastRecommendedDate: date).save(db)
            }
        }
    }

    public func clearAll() async throws {
        _ = try await dbWriter.write { db in
            try RecommendationHistoryEntity.deleteAll(db)
        }
    }
}

// MARK: - 6. SimilarArtistCacheDao

public final class SimilarArtistCacheDao: Sendable {
    private let dbWriter: any DatabaseWriter
    public init(dbWriter: any DatabaseWriter) { self.dbWriter = dbWriter }

    public func getCache(seedArtistId: String) async throws -> SimilarArtistCacheEntity? {
        try await dbWriter.read { db in
            try SimilarArtistCacheEntity.fetchOne(db, key: seedArtistId)
        }
    }

    public func insertCache(_ entry: SimilarArtistCacheEntity) async throws {
        try await dbWriter.write { db in try entry.save(db) }
    }

    public func deleteExpired(cutoffMs: Int64) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM similar_artist_cache WHERE cachedAt < ?", arguments: [cutoffMs])
        }
    }
}

// MARK: - 7. ArtistCountryCacheDao

public final class ArtistCountryCacheDao: Sendable {
    private let dbWriter: any DatabaseWriter
    public init(dbWriter: any DatabaseWriter) { self.dbWriter = dbWriter }

    public func getCountry(artistName: String) async throws -> ArtistCountryCacheEntity? {
        try await dbWriter.read { db in
            try ArtistCountryCacheEntity.fetchOne(db, key: artistName)
        }
    }

    public func insertCountry(_ entry: ArtistCountryCacheEntity) async throws {
        try await dbWriter.write { db in try entry.save(db) }
    }

    public func deleteExpired(cutoffMs: Int64) async throws {
        try await dbWriter.write { db in
            try db.execute(sql: "DELETE FROM artist_country_cache WHERE cachedAt < ?", arguments: [cutoffMs])
        }
    }
}

// MARK: - AsyncStream Helper

private extension AsyncSequence {
    func eraseToStream() -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in self {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
