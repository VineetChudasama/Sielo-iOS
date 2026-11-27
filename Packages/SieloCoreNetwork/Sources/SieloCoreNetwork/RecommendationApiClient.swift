import Foundation

// MARK: - DTOs (mirrors core-network/recommendations/RecommendationModels.kt)

public struct ClientListeningEvent: Codable, Sendable {
    public let eventId: String
    public let userId: String
    public let trackId: String
    public let eventType: String
    public let timestampMs: Int64
    public var playbackPositionMs: Int64
    public var durationMs: Int64
    public var trackTitle: String?
    public var trackArtist: String?
    public var trackAlbum: String?
    public var source: String?
    public var sessionId: String?

    public init(
        eventId: String = UUID().uuidString,
        userId: String,
        trackId: String,
        eventType: String,
        timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        playbackPositionMs: Int64 = 0,
        durationMs: Int64 = 0,
        trackTitle: String? = nil,
        trackArtist: String? = nil,
        trackAlbum: String? = nil,
        source: String? = "autoplay",
        sessionId: String? = nil
    ) {
        self.eventId = eventId
        self.userId = userId
        self.trackId = trackId
        self.eventType = eventType
        self.timestampMs = timestampMs
        self.playbackPositionMs = playbackPositionMs
        self.durationMs = durationMs
        self.trackTitle = trackTitle
        self.trackArtist = trackArtist
        self.trackAlbum = trackAlbum
        self.source = source
        self.sessionId = sessionId
    }
}

public struct BatchEventsRequestDto: Codable, Sendable {
    public let events: [ClientListeningEvent]
    public init(events: [ClientListeningEvent]) { self.events = events }
}

public struct BatchEventsResponseDto: Codable, Sendable {
    public let accepted: Int
    public let duplicatesIgnored: Int
    public let errors: Int
    public let message: String
}

public struct RecommendationRequestDto: Codable, Sendable {
    public let userId: String?
    public let seedTrackId: String?
    public let seedArtist: String?
    public let seedTitle: String?
    public let excludedTrackIds: [String]
    public let limit: Int
    public let diversityFactor: Float

    public init(
        userId: String? = nil,
        seedTrackId: String? = nil,
        seedArtist: String? = nil,
        seedTitle: String? = nil,
        excludedTrackIds: [String] = [],
        limit: Int = 20,
        diversityFactor: Float = 0.3
    ) {
        self.userId = userId
        self.seedTrackId = seedTrackId
        self.seedArtist = seedArtist
        self.seedTitle = seedTitle
        self.excludedTrackIds = excludedTrackIds
        self.limit = limit
        self.diversityFactor = diversityFactor
    }
}

public struct RecommendationItemDto: Codable, Sendable {
    public let trackId: String
    public let title: String?
    public let artist: String?
    public let album: String?
    public let thumbnailUrl: String?
    public let score: Float
    public let reason: String
    public let source: String
}

public struct RecommendationResponseDto: Codable, Sendable {
    public let modelVersion: String
    public let isFallback: Bool
    public let generatedAtMs: Int64
    public let recommendations: [RecommendationItemDto]
    public let metadata: [String: String]
}

public struct TrendingTrackDto: Codable, Sendable {
    public let trackId: String?
    public let title: String
    public let artist: String
    public let normalizedTitle: String
    public let normalizedArtist: String
    public let trendScore: Float
    public let momentumScore: Float
    public let source: String
    public let rank: Int
    public let confidence: Float
    public let updatedAt: String
    public let thumbnailUrl: String?
}

public struct TrendingBatchDto: Codable, Sendable {
    public let market: String
    public let source: String
    public let generatedAt: String
    public let isStale: Bool
    public let confidence: Float
    public let tracks: [TrendingTrackDto]
}

// MARK: - API Client

public final class RecommendationApiClient: Sendable {
    public let baseUrl: String
    private let tokenProvider: @Sendable () async -> String?
    private let session: URLSession

    public init(
        baseUrl: String = "https://sielo.onrender.com",
        tokenProvider: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.baseUrl = baseUrl
        self.tokenProvider = tokenProvider
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 6.0
        self.session = URLSession(configuration: config)
    }

    private func authHeader() async -> String {
        if let token = await tokenProvider(), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Bearer \(token)"
        }
        return "Bearer dev_token"
    }

    public func getRecommendations(_ request: RecommendationRequestDto) async -> RecommendationResponseDto? {
        guard let url = URL(string: "\(baseUrl)/v1/recommendations") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(await authHeader(), forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONEncoder().encode(request)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return try JSONDecoder().decode(RecommendationResponseDto.self, from: data)
        } catch {
            return nil
        }
    }

    public func sendBatchEvents(_ events: [ClientListeningEvent]) async -> Bool {
        guard !events.isEmpty, let url = URL(string: "\(baseUrl)/v1/events") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(await authHeader(), forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONEncoder().encode(BatchEventsRequestDto(events: events))

        do {
            let (_, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    public func getTrending(market: String = "IN") async -> TrendingBatchDto? {
        guard let url = URL(string: "\(baseUrl)/v1/trending?market=\(market)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(await authHeader(), forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return try JSONDecoder().decode(TrendingBatchDto.self, from: data)
        } catch {
            return nil
        }
    }
}
