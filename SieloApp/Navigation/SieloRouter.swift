import Foundation
import SwiftUI
import SieloCoreModels

public enum SieloTab: Int, CaseIterable, Identifiable {
    case home = 0
    case search = 1
    case echo = 2
    case stats = 3
    case profile = 4

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .echo: return "Echo"
        case .stats: return "Stats"
        case .profile: return "Profile"
        }
    }

    public var selectedSystemImage: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .echo: return "dot.radiowaves.left.and.right"
        case .stats: return "chart.bar.fill"
        case .profile: return "person.fill"
        }
    }

    public var unselectedSystemImage: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .echo: return "dot.radiowaves.left.and.right"
        case .stats: return "chart.bar"
        case .profile: return "person"
        }
    }
}

public enum SieloRoute: Hashable {
    case settings
    case userPlaylists
    case artistProfile(SieloArtist)
    case playlistDetail(id: String, title: String)
    case genreDetail(String)
    case searchCategory(String)
    case albumDetail(SieloAlbum)
}

public enum DeepLinkAction: Equatable {
    case playTrack(id: String, title: String?, artist: String?)
    case openAlbum(id: String, artist: String?)
    case joinRoom(url: String, key: String)
    case openArtist(name: String)
}

/// Manages 5-tab iOS NavigationStack paths (native edge-swipe back), Player modal, and Deep Links.
@MainActor
public final class SieloRouter: ObservableObject {
    @Published public var selectedTab: SieloTab = .home
    @Published public var homePath = NavigationPath()
    @Published public var searchPath = NavigationPath()
    @Published public var echoPath = NavigationPath()
    @Published public var statsPath = NavigationPath()
    @Published public var profilePath = NavigationPath()

    @Published public var isPlayerExpanded: Bool = false
    @Published public var isInsideRoomScreen: Bool = false
    @Published public var isBottomBarHiddenForDetail: Bool = false
    @Published public var pendingDeepLinkAction: DeepLinkAction?

    private var lastHandledDeepLink: String?

    public init() {}

    public var isBottomBarVisible: Bool {
        !isBottomBarHiddenForDetail && !isInsideRoomScreen
    }

    public func selectTab(_ tab: SieloTab) {
        if isPlayerExpanded {
            isPlayerExpanded = false
        }
        if selectedTab == tab {
            // Tapping active tab pops to root (standard iOS convention)
            popToRoot(tab: tab)
        } else {
            selectedTab = tab
        }
    }

    public func push(_ route: SieloRoute, in tab: SieloTab? = nil) {
        let targetTab = tab ?? selectedTab
        if route == .settings || route == .userPlaylists {
            isBottomBarHiddenForDetail = true
        }
        switch targetTab {
        case .home: homePath.append(route)
        case .search: searchPath.append(route)
        case .echo: echoPath.append(route)
        case .stats: statsPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    public func popToRoot(tab: SieloTab) {
        switch tab {
        case .home: homePath = NavigationPath()
        case .search: searchPath = NavigationPath()
        case .echo: echoPath = NavigationPath()
        case .stats: statsPath = NavigationPath()
        case .profile:
            profilePath = NavigationPath()
            isBottomBarHiddenForDetail = false
        }
    }

    /// Mirrors MainActivity.kt deep link routing for sielo:// and https://sielo.site/*
    public func handleDeepLink(_ url: URL) {
        let urlString = url.absoluteString
        guard urlString != lastHandledDeepLink else { return }

        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        let isSieloHost = host == "www.sielo.site" || host == "sielo.site" || host == "sielo-music.vercel.app"
        let isCustomScheme = scheme == "sielo"
        let isLegacyHost = host == "sielo.app" || host == "vineetchudasama.github.io"

        guard isSieloHost || isCustomScheme || isLegacyHost else { return }
        lastHandledDeepLink = urlString

        let pathSegments = url.pathComponents.filter { $0 != "/" }
        let firstSegment = (isCustomScheme ? host : pathSegments.first)?.lowercased() ?? ""
        let secondSegment = isCustomScheme ? pathSegments.first : pathSegments.dropFirst().first
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        func query(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        if firstSegment == "song" || firstSegment == "track" || (query("id") != nil && urlString.contains("track")) {
            if let songId = secondSegment?.nilIfBlank ?? query("id")?.nilIfBlank {
                pendingDeepLinkAction = .playTrack(id: songId, title: query("title"), artist: query("artist"))
            }
        } else if firstSegment == "album" || urlString.contains("album") {
            if let albumId = secondSegment?.nilIfBlank ?? query("id")?.nilIfBlank {
                selectedTab = .home
                pendingDeepLinkAction = .openAlbum(id: albumId, artist: query("artist"))
            }
        } else if ["echo", "listen", "room", "join", "orbit"].contains(firstSegment)
                    || urlString.contains("echo")
                    || urlString.contains("listen")
                    || urlString.contains("room")
                    || urlString.contains("orbit") {
            let key = query("key") ?? ""
            selectedTab = .echo
            pendingDeepLinkAction = .joinRoom(url: urlString, key: key)
        } else if firstSegment == "artist" || urlString.contains("artist") {
            let rawName = query("name")
                ?? secondSegment
                ?? urlString.components(separatedBy: "artist/").last?.components(separatedBy: "?").first
            if let cleanName = rawName?.replacingOccurrences(of: "+", with: " ").nilIfBlank {
                selectedTab = .home
                pendingDeepLinkAction = .openArtist(name: cleanName)
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
