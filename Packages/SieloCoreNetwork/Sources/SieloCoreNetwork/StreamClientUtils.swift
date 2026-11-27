import Foundation

/// Resolves User-Agent, Origin, and Referer headers for YouTube/InnerTube stream URLs (`?c=` param).
public enum StreamClientUtils {
    public static let userAgentWeb = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"
    public static let userAgentAndroid = "com.google.android.youtube/21.10.38 (Linux; U; Android 15; en_US; Pixel 9 Pro; Build/AP4A.250205.002; Cronet/132.0.6834.79) gzip"
    public static let userAgentAndroidMusic = "com.google.android.apps.youtube.music/7.27.52 (Linux; U; Android 15; en_US; Pixel 9 Pro; Build/AP4A.250205.002; Cronet/132.0.6834.79) gzip"
    public static let userAgentIOS = "com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)"

    public static func resolveUserAgent(clientParam: String) -> String {
        let c = clientParam.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if c == "WEB_REMIX" || c == "WEB" || c == "WEB_CREATOR" {
            return userAgentWeb
        } else if c == "TVHTML5" || c == "TVHTML5_SIMPLY_EMBEDDED_PLAYER" || c == "TVHTML5_SIMPLY" {
            return "Mozilla/5.0 (PlayStation; PlayStation 4/12.02) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15"
        } else if c == "IOS_MUSIC" {
            return "com.google.ios.youtubemusic/7.27.0 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)"
        } else if c.hasPrefix("IOS") {
            return userAgentIOS
        } else if c.hasPrefix("ANDROID_VR") {
            return "com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)"
        } else if c == "ANDROID_MUSIC" {
            return userAgentAndroidMusic
        } else {
            return userAgentAndroid
        }
    }

    public static func resolveOriginReferer(clientParam: String) -> (origin: String?, referer: String?) {
        let c = clientParam.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if c == "WEB_REMIX" || c == "WEB" || c == "WEB_CREATOR" {
            return ("https://music.youtube.com", "https://music.youtube.com/")
        } else if c == "TVHTML5" || c == "TVHTML5_SIMPLY_EMBEDDED_PLAYER" || c == "TVHTML5_SIMPLY" {
            return ("https://www.youtube.com", "https://www.youtube.com/tv")
        }
        return (nil, nil)
    }

    public static func headersForStreamURL(_ url: URL) -> [String: String] {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("googlevideo.com") || host.contains("youtube-nocookie.com") || host.contains("ytimg.com") else {
            return [:]
        }
        let cParam = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "c" })?
            .value ?? "ANDROID"
        var headers: [String: String] = ["User-Agent": resolveUserAgent(clientParam: cParam)]
        let (origin, referer) = resolveOriginReferer(clientParam: cParam)
        if let origin { headers["Origin"] = origin }
        if let referer { headers["Referer"] = referer }
        return headers
    }
}
