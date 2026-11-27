import Foundation
import SieloCoreModels

// MARK: - ArtistProfileCache

public actor ArtistProfileCache {
    public static let shared = ArtistProfileCache()
    private var cache: [String: ArtistDetails] = [:]

    public func get(_ artistName: String) -> ArtistDetails? {
        cache[artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    public func put(_ artistName: String, details: ArtistDetails) {
        cache[artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = details
    }

    public func clear() {
        cache.removeAll()
    }
}

// MARK: - JioSaavnSongArtworkResolver

public actor JioSaavnSongArtworkResolver {
    public static let shared = JioSaavnSongArtworkResolver()
    private var cache: [String: String] = [:]
    private let session = URLSession.shared

    public func resolveArtwork(title: String, artist: String) async -> String? {
        let key = "\(title.lowercased())::\(artist.lowercased())"
        if let cached = cache[key] { return cached }

        // 1. JioSaavn
        let q = "\(title) \(artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        if let url = URL(string: "https://www.jiosaavn.com/api.php?__call=search.getResults&q=\(q)&api_version=4&_format=json&_marker=0&n=5"),
           let (data, _) = try? await session.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = json["results"] as? [[String: Any]],
           let img = (results.first?["image"] as? String)?
            .replacingOccurrences(of: "150x150", with: "500x500")
            .replacingOccurrences(of: "http://", with: "https://") {
            cache[key] = img
            return img
        }

        // 2. iTunes Search API (600x600)
        if let itunesUrl = URL(string: "https://itunes.apple.com/search?term=\(q)&entity=song&limit=3"),
           let (data, _) = try? await session.data(from: itunesUrl),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = json["results"] as? [[String: Any]],
           let art = (results.first?["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100", with: "600x600") {
            cache[key] = art
            return art
        }

        // 3. Deezer
        if let dzUrl = URL(string: "https://api.deezer.com/search?q=\(q)&limit=3"),
           let (data, _) = try? await session.data(from: dzUrl),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataArr = json["data"] as? [[String: Any]],
           let album = dataArr.first?["album"] as? [String: Any],
           let cover = (album["cover_xl"] as? String) ?? (album["cover_big"] as? String) {
            cache[key] = cover
            return cover
        }

        return nil
    }
}

// MARK: - ArtistMetadataResolver & YouTubeArtistImageResolver

public actor ArtistMetadataResolver {
    public static let shared = ArtistMetadataResolver()
    private var bioCache: [String: String] = [:]
    private var photoCache: [String: String] = [:]
    private let session = URLSession.shared

    public func fetchWikipediaBio(artistName: String) async -> String? {
        let key = artistName.lowercased()
        if let cached = bioCache[key] { return cached }

        let suffixes = ["", "_(singer)", "_(musician)", "_(band)"]
        for suffix in suffixes {
            let slug = (artistName.replacingOccurrences(of: " ", with: "_") + suffix)
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? artistName
            guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(slug)") else { continue }
            if let (data, resp) = try? await session.data(from: url),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let extract = json["extract"] as? String, !extract.isEmpty {
                let lower = extract.lowercased()
                if lower.contains("singer") || lower.contains("musician") || lower.contains("rapper")
                    || lower.contains("band") || lower.contains("artist") || lower.contains("composer") {
                    bioCache[key] = extract
                    return extract
                }
            }
        }
        return nil
    }

    public func resolveArtistPhoto(artistName: String) async -> String? {
        let key = artistName.lowercased()
        if let cached = photoCache[key] { return cached }

        let encoded = artistName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? artistName
        if let url = URL(string: "https://api.deezer.com/search/artist?q=\(encoded)&limit=3"),
           let (data, _) = try? await session.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let list = json["data"] as? [[String: Any]],
           let match = list.first(where: {
               TrackMatchValidator.isStrictArtistMatch(($0["name"] as? String) ?? "", artistName)
           }) ?? list.first,
           let pic = (match["picture_xl"] as? String) ?? (match["picture_big"] as? String) {
            photoCache[key] = pic
            return pic
        }
        return nil
    }
}

// MARK: - MusicBrainzClient (950ms rate limit) & CoverArtArchiveClient

public actor MusicBrainzClient {
    public static let shared = MusicBrainzClient()
    private var lastRequestTime: Date = .distantPast
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        self.session = URLSession(configuration: config)
    }

    private func throttle() async {
        let elapsed = Date().timeIntervalSince(lastRequestTime)
        if elapsed < 0.95 {
            try? await Task.sleep(nanoseconds: UInt64((0.95 - elapsed) * 1_000_000_000))
        }
        lastRequestTime = Date()
    }

    public func searchArtist(name: String) async -> (id: String, name: String, country: String?)? {
        await throttle()
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        guard let url = URL(string: "https://musicbrainz.org/ws/2/artist/?query=artist:\(encoded)&fmt=json&limit=3") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Sielo/12.0.0 (ios@sielo.site)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let artists = json["artists"] as? [[String: Any]],
              let first = artists.first,
              let id = first["id"] as? String,
              let mbName = first["name"] as? String else {
            return nil
        }
        return (id, mbName, first["country"] as? String)
    }
}

public actor MusicMetadataRepository {
    public static let shared = MusicMetadataRepository()

    public func getArtistDetails(_ artistName: String) async -> ArtistDetails? {
        if let cached = await ArtistProfileCache.shared.get(artistName) {
            return cached
        }

        async let ytDetails = InnerTubeClient.shared.getArtistDetails(artistName)
        async let wikiBio = ArtistMetadataResolver.shared.fetchWikipediaBio(artistName: artistName)
        async let photo = ArtistMetadataResolver.shared.resolveArtistPhoto(artistName: artistName)
        async let mbArtist = MusicBrainzClient.shared.searchArtist(name: artistName)

        let base = await ytDetails ?? ArtistDetails(id: artistName.lowercased(), name: artistName)
        let bio = await wikiBio
        let resolvedPhoto = await photo
        let mb = await mbArtist

        let merged = ArtistDetails(
            id: base.id,
            name: base.name,
            imageUrl: resolvedPhoto ?? base.imageUrl,
            heroImageUrl: resolvedPhoto ?? base.heroImageUrl ?? base.imageUrl,
            bio: bio ?? base.bio,
            latestAlbum: base.latestAlbum,
            topSongs: base.topSongs,
            pastAlbums: base.pastAlbums,
            originalAlbums: base.originalAlbums,
            featuredAlbums: base.featuredAlbums,
            singles: base.singles,
            similarArtists: base.similarArtists,
            monthlyListeners: base.monthlyListeners,
            followerCount: base.followerCount,
            dominantLanguage: base.dominantLanguage,
            dominantType: base.dominantType,
            isVerified: true,
            origin: mb?.country,
            musicBrainzId: mb?.id
        )

        await ArtistProfileCache.shared.put(artistName, details: merged)
        return merged
    }
}
