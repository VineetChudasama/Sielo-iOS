import Foundation

// MARK: - Media Models (mirrors core-network/models/Models.kt)

public struct SieloTrack: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public var album: String?
    public var durationText: String?
    public var durationSeconds: Int64
    public var thumbnailUrl: String?
    public var streamUrl: String?
    public var musicBrainzRecordingId: String?
    public var isrc: String?
    public var albumId: String?
    public var viewCount: Int64
    public var isExplicit: Bool

    public init(
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        durationText: String? = nil,
        durationSeconds: Int64 = 0,
        thumbnailUrl: String? = nil,
        streamUrl: String? = nil,
        musicBrainzRecordingId: String? = nil,
        isrc: String? = nil,
        albumId: String? = nil,
        viewCount: Int64 = 0,
        isExplicit: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationText = durationText
        self.durationSeconds = durationSeconds
        self.thumbnailUrl = thumbnailUrl
        self.streamUrl = streamUrl
        self.musicBrainzRecordingId = musicBrainzRecordingId
        self.isrc = isrc
        self.albumId = albumId
        self.viewCount = viewCount
        self.isExplicit = isExplicit
    }

    public var formattedViews: String? {
        guard viewCount > 0 else { return nil }
        switch viewCount {
        case 1_000_000_000...:
            return String(format: "%.1fB views", Double(viewCount) / 1_000_000_000.0)
                .replacingOccurrences(of: ".0B", with: "B")
        case 1_000_000...:
            return String(format: "%.1fM views", Double(viewCount) / 1_000_000.0)
                .replacingOccurrences(of: ".0M", with: "M")
        case 1_000...:
            return String(format: "%.1fK views", Double(viewCount) / 1_000.0)
                .replacingOccurrences(of: ".0K", with: "K")
        default:
            return "\(viewCount) views"
        }
    }

    public var formattedDuration: String {
        if let durationText, !durationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return durationText
        }
        if durationSeconds > 0 {
            let mins = durationSeconds / 60
            let secs = durationSeconds % 60
            return String(format: "%d:%02d", mins, secs)
        }
        let hash = abs((id + title).hashValue)
        let defaultSecs = 175 + (hash % 80)
        return String(format: "%d:%02d", defaultSecs / 60, defaultSecs % 60)
    }
}

public struct SearchResult: Codable, Sendable {
    public var tracks: [SieloTrack]
    public var albums: [SieloAlbum]

    public init(tracks: [SieloTrack] = [], albums: [SieloAlbum] = []) {
        self.tracks = tracks
        self.albums = albums
    }
}

public struct SieloAlbum: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public var year: String?
    public var thumbnailUrl: String?
    public var tracks: [SieloTrack]
    public var songCount: Int
    public var type: String?
    public var description: String?
    public var audioQuality: String?
    public var isFavorite: Bool
    public var releaseDate: String?
    public var musicBrainzId: String?
    public var releaseType: String?

    public init(
        id: String,
        title: String,
        artist: String,
        year: String? = nil,
        thumbnailUrl: String? = nil,
        tracks: [SieloTrack] = [],
        songCount: Int = 0,
        type: String? = "Album",
        description: String? = nil,
        audioQuality: String? = nil,
        isFavorite: Bool = false,
        releaseDate: String? = nil,
        musicBrainzId: String? = nil,
        releaseType: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.year = year
        self.thumbnailUrl = thumbnailUrl
        self.tracks = tracks
        self.songCount = songCount
        self.type = type
        self.description = description
        self.audioQuality = audioQuality
        self.isFavorite = isFavorite
        self.releaseDate = releaseDate
        self.musicBrainzId = musicBrainzId
        self.releaseType = releaseType
    }
}

public struct SieloArtist: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public var imageUrl: String?
    public var role: String?

    public init(id: String, name: String, imageUrl: String? = nil, role: String? = "Artist") {
        self.id = id
        self.name = name
        self.imageUrl = imageUrl
        self.role = role
    }
}

public struct ArtistDetails: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public var imageUrl: String?
    public var heroImageUrl: String?
    public var bio: String?
    public var latestAlbum: SieloAlbum?
    public var topSongs: [SieloTrack]
    public var pastAlbums: [SieloAlbum]
    public var originalAlbums: [SieloAlbum]
    public var featuredAlbums: [SieloAlbum]
    public var singles: [SieloAlbum]
    public var similarArtists: [SieloArtist]
    public var monthlyListeners: String?
    public var followerCount: String?
    public var dominantLanguage: String?
    public var dominantType: String?
    public var isVerified: Bool
    public var wikiUrl: String?
    public var genres: [String]
    public var origin: String?
    public var activeYears: String?
    public var recordLabel: String?
    public var description: String?
    public var musicBrainzId: String?

    public init(
        id: String,
        name: String,
        imageUrl: String? = nil,
        heroImageUrl: String? = nil,
        bio: String? = nil,
        latestAlbum: SieloAlbum? = nil,
        topSongs: [SieloTrack] = [],
        pastAlbums: [SieloAlbum] = [],
        originalAlbums: [SieloAlbum] = [],
        featuredAlbums: [SieloAlbum] = [],
        singles: [SieloAlbum] = [],
        similarArtists: [SieloArtist] = [],
        monthlyListeners: String? = nil,
        followerCount: String? = nil,
        dominantLanguage: String? = nil,
        dominantType: String? = nil,
        isVerified: Bool = true,
        wikiUrl: String? = nil,
        genres: [String] = [],
        origin: String? = nil,
        activeYears: String? = nil,
        recordLabel: String? = nil,
        description: String? = nil,
        musicBrainzId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.imageUrl = imageUrl
        self.heroImageUrl = heroImageUrl
        self.bio = bio
        self.latestAlbum = latestAlbum
        self.topSongs = topSongs
        self.pastAlbums = pastAlbums
        self.originalAlbums = originalAlbums
        self.featuredAlbums = featuredAlbums
        self.singles = singles
        self.similarArtists = similarArtists
        self.monthlyListeners = monthlyListeners
        self.followerCount = followerCount
        self.dominantLanguage = dominantLanguage
        self.dominantType = dominantType
        self.isVerified = isVerified
        self.wikiUrl = wikiUrl
        self.genres = genres
        self.origin = origin
        self.activeYears = activeYears
        self.recordLabel = recordLabel
        self.description = description
        self.musicBrainzId = musicBrainzId
    }
}

// MARK: - Playback State (mirrors core-audio/model/PlaybackState.kt)

public enum QueueScope: String, Codable, Sendable {
    case open = "OPEN"
    case albumOnly = "ALBUM_ONLY"
    case artistOnly = "ARTIST_ONLY"
    case listenTogether = "LISTEN_TOGETHER"
}

public struct PlaybackState: Equatable, Sendable {
    public var currentTrack: SieloTrack?
    public var isPlaying: Bool
    public var isBuffering: Bool
    public var isMuted: Bool
    public var currentPositionMs: Int64
    public var durationMs: Int64
    public var queue: [SieloTrack]
    public var queueIndex: Int
    public var isShuffle: Bool
    public var isLooping: Bool
    public var playNextCount: Int

    public init(
        currentTrack: SieloTrack? = nil,
        isPlaying: Bool = false,
        isBuffering: Bool = false,
        isMuted: Bool = false,
        currentPositionMs: Int64 = 0,
        durationMs: Int64 = 0,
        queue: [SieloTrack] = [],
        queueIndex: Int = -1,
        isShuffle: Bool = false,
        isLooping: Bool = false,
        playNextCount: Int = 0
    ) {
        self.currentTrack = currentTrack
        self.isPlaying = isPlaying
        self.isBuffering = isBuffering
        self.isMuted = isMuted
        self.currentPositionMs = currentPositionMs
        self.durationMs = durationMs
        self.queue = queue
        self.queueIndex = queueIndex
        self.isShuffle = isShuffle
        self.isLooping = isLooping
        self.playNextCount = playNextCount
    }
}

// MARK: - User & Auth Models (mirrors core/auth/model/UserSession.kt)

public enum AuthProvider: String, Codable, Sendable {
    case google = "GOOGLE"
    case spotify = "SPOTIFY"
    case emailPassword = "EMAIL_PASSWORD"
    case guest = "GUEST"
}

public struct UserProfile: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var email: String
    public var photoUrl: String?
    public var provider: AuthProvider
    public var hasCompletedOnboarding: Bool
    public var favoriteArtists: [String]
    public var favoriteGenres: [String]
    public var artistTasteWeights: [String: Int]
    public var genreTasteWeights: [String: Int]
    public var bio: String?
    public var username: String?
    public var isSpotifyLinked: Bool
    public var spotifyAccountName: String?
    public var createdAt: Int64

    public init(
        id: String,
        name: String,
        email: String,
        photoUrl: String? = nil,
        provider: AuthProvider = .emailPassword,
        hasCompletedOnboarding: Bool = false,
        favoriteArtists: [String] = [],
        favoriteGenres: [String] = [],
        artistTasteWeights: [String: Int] = [:],
        genreTasteWeights: [String: Int] = [:],
        bio: String? = nil,
        username: String? = nil,
        isSpotifyLinked: Bool = false,
        spotifyAccountName: String? = nil,
        createdAt: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.photoUrl = photoUrl
        self.provider = provider
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.favoriteArtists = favoriteArtists
        self.favoriteGenres = favoriteGenres
        self.artistTasteWeights = artistTasteWeights
        self.genreTasteWeights = genreTasteWeights
        self.bio = bio
        self.username = username
        self.isSpotifyLinked = isSpotifyLinked
        self.spotifyAccountName = spotifyAccountName
        self.createdAt = createdAt
    }
}

// MARK: - Playlist Models (mirrors core/playlist/UserPlaylistsRepository.kt)

public struct UserPlaylist: Codable, Identifiable, Hashable, Sendable {
    public static let downloadedCacheId = "sielo_downloaded_cache"

    public let id: String
    public var title: String
    public var description: String
    public var coverUrl: String?
    public var createdAt: Int64
    public var tracks: [SieloTrack]
    public var syncUrl: String?
    public var syncSource: String?
    public var lastSyncedAt: Int64?
    public var autoSyncEnabled: Bool

    public init(
        id: String,
        title: String,
        description: String = "",
        coverUrl: String? = nil,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        tracks: [SieloTrack] = [],
        syncUrl: String? = nil,
        syncSource: String? = nil,
        lastSyncedAt: Int64? = nil,
        autoSyncEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.coverUrl = coverUrl
        self.createdAt = createdAt
        self.tracks = tracks
        self.syncUrl = syncUrl
        self.syncSource = syncSource
        self.lastSyncedAt = lastSyncedAt
        self.autoSyncEnabled = autoSyncEnabled
    }
}

// MARK: - Lyrics Models (mirrors core-lyrics/model/Lyrics.kt)

public struct LyricLine: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(timestampMs)_\(text)" }
    public let timestampMs: Int64
    public let text: String

    public init(timestampMs: Int64, text: String) {
        self.timestampMs = timestampMs
        self.text = text
    }
}

public struct SieloLyrics: Codable, Equatable, Sendable {
    public let id: String
    public let plainLyrics: String?
    public let syncedLyrics: String?
    public let lines: [LyricLine]

    public init(
        id: String = "",
        plainLyrics: String? = nil,
        syncedLyrics: String? = nil,
        lines: [LyricLine] = []
    ) {
        self.id = id
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
        self.lines = lines
    }
}
