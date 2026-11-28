import Foundation
import Combine

/// Checks Sielo's AltStore/GitHub apps.json for newer iOS releases.
@MainActor
public final class AppUpdateManager: ObservableObject {
    public static let shared = AppUpdateManager()

    @Published public private(set) var availableVersion: String?
    @Published public private(set) var releaseNotes: String?

    private let sourceURL = "https://raw.githubusercontent.com/VineetChudasama/Sielo-iOS/main/apps.json"

    private struct SourcePayload: Codable {
        struct AppItem: Codable {
            let version: String
            let versionDescription: String?
        }
        let apps: [AppItem]
    }

    private init() {}

    public func checkForUpdates() async {
        guard let url = URL(string: "\(sourceURL)?t=\(Int(Date().timeIntervalSince1970))"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = try? JSONDecoder().decode(SourcePayload.self, from: data),
              let latest = decoded.apps.first else {
            return
        }

        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "12.0.0"
        if isVersionNewer(latest.version, than: current) {
            availableVersion = latest.version
            releaseNotes = latest.versionDescription
        } else {
            availableVersion = nil
        }
    }

    private func isVersionNewer(_ remote: String, than local: String) -> Bool {
        let rParts = remote.split(separator: ".").compactMap { Int($0) }
        let lParts = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(rParts.count, lParts.count) {
            let r = i < rParts.count ? rParts[i] : 0
            let l = i < lParts.count ? lParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}
