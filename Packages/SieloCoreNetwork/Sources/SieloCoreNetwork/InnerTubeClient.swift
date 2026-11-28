import Foundation
import SieloCoreModels

/// Dual-engine InnerTube (YouTube / YouTube Music) + JioSaavn client.
/// Mirrors core-network/innertube/InnerTubeClient.kt
public actor InnerTubeClient {
    public static let shared = InnerTubeClient()

    public var preferredBitrateSuffix: String = "_320.mp4"

    private struct CachedStream {
        let url: String
        let expiresAt: TimeInterval
    }

    private var streamCache: [String: CachedStream] = [:]
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
    }

    public func setPreferredBitrateSuffix(_ suffix: String) {
        self.preferredBitrateSuffix = suffix
    }

    // MARK: - Search

    public func search(query: String) async -> SearchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchResult() }

        async let saavnTracks = searchJioSaavn(query: trimmed)
        async let ytTracks = searchYouTubeMusic(query: trimmed)

        let combined = await saavnTracks + ytTracks
        let filtered = combined.filter { isPureMusicTrack($0) }
        let deduped = TrackMatchValidator.deduplicateTracks(filtered)
        return SearchResult(tracks: deduped, albums: [])
    }

    public func searchArtists(query: String) async -> [SieloArtist] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://www.jiosaavn.com/api.php?__call=search.getArtistResults&q=\(encoded)&api_version=4&_format=json&_marker=0&n=10") else {
            return []
        }
        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                return []
            }
            return results.compactMap { item in
                guard let id = item["id"] as? String,
                      let name = item["name"] as? String else { return nil }
                let image = (item["image"] as? String)?
                    .replacingOccurrences(of: "150x150", with: "500x500")
                    .replacingOccurrences(of: "50x50", with: "500x500")
                    .replacingOccurrences(of: "http://", with: "https://")
                return SieloArtist(id: id, name: name, imageUrl: image, role: "Artist")
            }
        } catch {
            return []
        }
    }

    // MARK: - Stream Resolution

    public func getStreamUrl(videoId: String, title: String = "", artist: String = "") async -> String? {
        let cacheKey = "\(videoId)|\(title.lowercased())|\(artist.lowercased())"
        if let cached = streamCache[cacheKey], Date().timeIntervalSince1970 < cached.expiresAt - 60 {
            return cached.url
        }

        var resolvedUrl: String?

        // 1. YouTube 11-char ID -> ANDROID (v21.10.38) -> ANDROID_VR fallback
        if isYouTubeVideoId(videoId) {
            if let ytUrl = await resolveYouTubeStream(videoId: videoId) {
                resolvedUrl = ytUrl
            }
        }

        // 2. JioSaavn direct or search resolution (320 -> 160 -> 96 kbps)
        if resolvedUrl == nil {
            if let saavnUrl = await resolveJioSaavnStream(trackId: videoId, title: title, artist: artist) {
                resolvedUrl = saavnUrl
            }
        }

        // 3. YouTube Music search fallback if ID wasn't a YT ID
        if resolvedUrl == nil, !title.isEmpty {
            let q = artist.isEmpty ? title : "\(title) \(artist)"
            let ytResults = await searchYouTubeMusic(query: q)
            if let match = ytResults.first(where: { isYouTubeVideoId($0.id) }) {
                resolvedUrl = await resolveYouTubeStream(videoId: match.id)
            }
        }

        if let resolvedUrl {
            let expiry = parseExpiry(from: resolvedUrl) ?? (Date().timeIntervalSince1970 + 3600)
            streamCache[cacheKey] = CachedStream(url: resolvedUrl, expiresAt: expiry)
        }
        return resolvedUrl
    }

    public func resolveTrackById(_ songId: String) async -> SieloTrack? {
        if isYouTubeVideoId(songId) {
            let body: [String: Any] = [
                "context": androidContext(),
                "videoId": songId
            ]
            if let json = await postInnerTube(endpoint: "player", body: body, userAgent: StreamClientUtils.userAgentAndroid),
               let details = json["videoDetails"] as? [String: Any],
               let title = details["title"] as? String,
               let author = details["author"] as? String {
                let lengthSec = Int64((details["lengthSeconds"] as? String) ?? "0") ?? 0
                let thumb = ((details["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
                return SieloTrack(
                    id: songId,
                    title: title,
                    artist: author,
                    durationSeconds: lengthSec,
                    thumbnailUrl: thumb
                )
            }
        }
        return await fetchJioSaavnSongById(songId)
    }

    public func getAlbumSongs(_ albumId: String) async -> [SieloTrack] {
        // JioSaavn album or YT browse fallback
        if let saavnAlbumUrl = URL(string: "https://www.jiosaavn.com/api.php?__call=content.getAlbumDetails&albumid=\(albumId)&api_version=4&_format=json&_marker=0") {
            if let (data, _) = try? await session.data(from: saavnAlbumUrl),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let list = json["list"] as? [[String: Any]], !list.isEmpty {
                return list.compactMap(parseJioSaavnTrack)
            }
        }
        return []
    }

    public func getYouTubePlaylistSongs(_ playlistId: String) async -> [SieloTrack] {
        let browseId = playlistId.hasPrefix("VL") ? playlistId : "VL\(playlistId)"
        let body: [String: Any] = [
            "context": webRemixContext(),
            "browseId": browseId
        ]
        guard let json = await postInnerTube(
            endpoint: "browse",
            body: body,
            baseUrl: "https://music.youtube.com/youtubei/v1",
            userAgent: StreamClientUtils.userAgentWeb
        ) else {
            return []
        }
        return extractTracksFromBrowseJSON(json)
    }

    public func getArtistDetails(_ artistName: String) async -> ArtistDetails? {
        let artists = await searchArtists(query: artistName)
        guard let primary = artists.first(where: { TrackMatchValidator.isStrictArtistMatch($0.name, artistName) }) ?? artists.first else {
            return nil
        }
        let searchRes = await search(query: primary.name)
        let topSongs = searchRes.tracks.filter { TrackMatchValidator.isSongByOrFeaturingArtist($0, targetArtist: primary.name) }
        return ArtistDetails(
            id: primary.id,
            name: primary.name,
            imageUrl: primary.imageUrl,
            topSongs: Array(topSongs.prefix(25))
        )
    }

    public func getSimilarArtistNames(_ artistName: String) async -> [String] {
        let res = await searchArtists(query: artistName)
        return res.map(\.name).filter { $0.caseInsensitiveCompare(artistName) != .orderedSame }
    }

    // MARK: - Private Helpers

    private func isYouTubeVideoId(_ id: String) -> Bool {
        let pattern = "^[A-Za-z0-9_-]{11}$"
        return id.range(of: pattern, options: .regularExpression) != nil
    }

    private func isPureMusicTrack(_ track: SieloTrack) -> Bool {
        let lower = track.title.lowercased()
        let blocked = ["full album", "jukebox", "mashup", "podcast", "audiobook"]
        if blocked.contains(where: { lower.contains($0) }) { return false }
        if track.durationSeconds > 660 { return false }
        if (1...25).contains(track.durationSeconds) { return false }
        return true
    }

    private func searchJioSaavn(query: String) async -> [SieloTrack] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://www.jiosaavn.com/api.php?__call=search.getResults&q=\(encoded)&api_version=4&_format=json&_marker=0&n=20") else {
            return []
        }
        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                return []
            }
            return results.compactMap(parseJioSaavnTrack)
        } catch {
            return []
        }
    }

    private func fetchJioSaavnSongById(_ songId: String) async -> SieloTrack? {
        guard let url = URL(string: "https://www.jiosaavn.com/api.php?__call=song.getDetails&pids=\(songId)&api_version=4&_format=json&_marker=0") else {
            return nil
        }
        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let songs = json["songs"] as? [[String: Any]],
                  let first = songs.first else {
                return nil
            }
            return parseJioSaavnTrack(first)
        } catch {
            return nil
        }
    }

    private func parseJioSaavnTrack(_ dict: [String: Any]) -> SieloTrack? {
        guard let id = dict["id"] as? String,
              let rawTitle = dict["title"] as? String else { return nil }
        let title = decodeHTML(rawTitle)
        let moreInfo = dict["more_info"] as? [String: Any]
        let artistMap = moreInfo?["artistMap"] as? [String: Any]
        let primaryArtists = (artistMap?["primary_artists"] as? [[String: Any]])?
            .compactMap { $0["name"] as? String }
            .joined(separator: ", ")
        let artist = decodeHTML(primaryArtists ?? (dict["subtitle"] as? String) ?? "Unknown Artist")
        let durationSec = Int64((moreInfo?["duration"] as? String) ?? "0") ?? 0
        let image = (dict["image"] as? String)?
            .replacingOccurrences(of: "150x150", with: "500x500")
            .replacingOccurrences(of: "http://", with: "https://")
        let album = (moreInfo?["album"] as? String).map(decodeHTML)
        let explicit = (dict["explicit_content"] as? String) == "1"

        return SieloTrack(
            id: id,
            title: title,
            artist: artist,
            album: album,
            durationSeconds: durationSec,
            thumbnailUrl: image,
            albumId: moreInfo?["album_id"] as? String,
            isExplicit: explicit
        )
    }

    private func resolveJioSaavnStream(trackId: String, title: String, artist: String) async -> String? {
        if let url = URL(string: "https://www.jiosaavn.com/api.php?__call=song.getDetails&pids=\(trackId)&api_version=4&_format=json&_marker=0"),
           let (data, _) = try? await session.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let songs = json["songs"] as? [[String: Any]],
           let first = songs.first,
           let moreInfo = first["more_info"] as? [String: Any],
           let encrypted = moreInfo["encrypted_media_url"] as? String,
           let baseUrl = JioSaavnCrypto.decryptMediaURL(encrypted) {
            return await probeBestSaavnBitrate(baseUrl: baseUrl)
        }

        guard !title.isEmpty else { return nil }
        let q = artist.isEmpty ? title : "\(title) \(artist)"
        let results = await searchJioSaavn(query: q)
        if let best = results.first(where: {
            TrackMatchValidator.isFuzzyMatch(candidateTitle: $0.title, candidateArtist: $0.artist, targetTitle: title, targetArtist: artist)
        }) {
            return await resolveJioSaavnStream(trackId: best.id, title: "", artist: "")
        }
        return nil
    }

    private func probeBestSaavnBitrate(baseUrl: String) async -> String {
        let suffixes = [preferredBitrateSuffix, "_320.mp4", "_160.mp4", "_96.mp4"]
        for suffix in suffixes {
            let candidate = baseUrl
                .replacingOccurrences(of: "_96.mp4", with: suffix)
                .replacingOccurrences(of: "_160.mp4", with: suffix)
                .replacingOccurrences(of: "_320.mp4", with: suffix)
            if let url = URL(string: candidate) {
                var headReq = URLRequest(url: url)
                headReq.httpMethod = "HEAD"
                if let (_, resp) = try? await session.data(for: headReq),
                   let http = resp as? HTTPURLResponse,
                   (200..<400).contains(http.statusCode) {
                    return candidate
                }
            }
        }
        return baseUrl
    }

    private func searchYouTubeMusic(query: String) async -> [SieloTrack] {
        let body: [String: Any] = [
            "context": webRemixContext(),
            "query": query,
            "params": "EgWKAQIIAWoKEAMQBBAJEAoQBQ=="
        ]
        guard let json = await postInnerTube(
            endpoint: "search",
            body: body,
            baseUrl: "https://music.youtube.com/youtubei/v1",
            userAgent: StreamClientUtils.userAgentWeb
        ) else {
            return []
        }
        return extractTracksFromBrowseJSON(json)
    }

    private func resolveYouTubeStream(videoId: String) async -> String? {
        // Primary: ANDROID client, Fallback: ANDROID_VR Quest 3
        let clients: [([String: Any], String)] = [
            (androidContext(), StreamClientUtils.userAgentAndroid),
            (androidVRContext(), StreamClientUtils.resolveUserAgent(clientParam: "ANDROID_VR"))
        ]

        for (ctx, ua) in clients {
            let body: [String: Any] = [
                "context": ctx,
                "videoId": videoId,
                "contentCheckOk": true,
                "racyCheckOk": true
            ]
            guard let json = await postInnerTube(endpoint: "player", body: body, userAgent: ua),
                  let streamingData = json["streamingData"] as? [String: Any] else {
                continue
            }
            let adaptive = (streamingData["adaptiveFormats"] as? [[String: Any]]) ?? []
            let audioFormats = adaptive
                .filter { ($0["mimeType"] as? String)?.hasPrefix("audio/") == true }
                .sorted { ($0["bitrate"] as? Int ?? 0) > ($1["bitrate"] as? Int ?? 0) }
            if let bestUrl = audioFormats.first?["url"] as? String {
                return bestUrl
            }
            let formats = (streamingData["formats"] as? [[String: Any]]) ?? []
            if let progUrl = formats.first?["url"] as? String {
                return progUrl
            }
        }
        return nil
    }

    private func postInnerTube(
        endpoint: String,
        body: [String: Any],
        baseUrl: String = "https://www.youtube.com/youtubei/v1",
        userAgent: String
    ) async -> [String: Any]? {
        guard let url = URL(string: "\(baseUrl)/\(endpoint)?prettyPrint=false") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if baseUrl.contains("music.youtube.com") {
            req.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
            req.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await session.data(for: req)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private func extractTracksFromBrowseJSON(_ json: [String: Any]) -> [SieloTrack] {
        var found: [SieloTrack] = []
        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                if let renderer = dict["musicResponsiveListItemRenderer"] as? [String: Any],
                   let track = parseMusicResponsiveRenderer(renderer) {
                    found.append(track)
                }
                for value in dict.values { walk(value) }
            } else if let arr = node as? [Any] {
                for item in arr { walk(item) }
            }
        }
        walk(json)
        return found
    }

    private func parseMusicResponsiveRenderer(_ r: [String: Any]) -> SieloTrack? {
        guard let videoId = (r["playlistItemData"] as? [String: Any])?["videoId"] as? String else { return nil }
        let flexColumns = (r["flexColumns"] as? [[String: Any]]) ?? []
        let titleRuns = ((flexColumns.first?["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"] as? [String: Any])?["runs"] as? [[String: Any]]
        let title = titleRuns?.compactMap { $0["text"] as? String }.joined() ?? ""
        guard !title.isEmpty else { return nil }

        let subRuns = ((flexColumns.dropFirst().first?["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"] as? [String: Any])?["runs"] as? [[String: Any]]
        let artist = subRuns?.first?["text"] as? String ?? "Unknown Artist"
        let thumb = (((r["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        let rawThumbUrl = thumb?.last?["url"] as? String
        let thumbUrl = rawThumbUrl.map { url -> String in
            if url.contains("lh3.googleusercontent.com") || url.contains("yt3.ggpht.com") {
                return url.replacingOccurrences(of: "=w\\d+-h\\d+[^\"&]*", with: "=w544-h544-l90-rj", options: .regularExpression)
            }
            return url
        }

        return SieloTrack(id: videoId, title: title, artist: artist, thumbnailUrl: thumbUrl)
    }

    private func parseExpiry(from urlString: String) -> TimeInterval? {
        guard let url = URL(string: urlString),
              let expStr = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "expire" })?.value,
              let exp = TimeInterval(expStr) else {
            return nil
        }
        return exp
    }

    private func decodeHTML(_ str: String) -> String {
        str.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private func webRemixContext() -> [String: Any] {
        ["client": ["clientName": "WEB_REMIX", "clientVersion": "1.20241120.01.00", "hl": "en", "gl": "IN"]]
    }

    private func androidContext() -> [String: Any] {
        ["client": ["clientName": "ANDROID", "clientVersion": "21.10.38", "androidSdkVersion": 35, "hl": "en", "gl": "IN"]]
    }

    private func androidVRContext() -> [String: Any] {
        ["client": ["clientName": "ANDROID_VR", "clientVersion": "1.61.48", "deviceMake": "Oculus", "deviceModel": "Quest 3", "hl": "en", "gl": "IN"]]
    }
}
