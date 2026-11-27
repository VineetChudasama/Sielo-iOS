import SwiftUI
import SieloCoreModels
import SieloCoreNetwork
import SieloCoreAudio

/// Root iOS shell mirroring MainActivity.kt with all 5 tabs, native iOS NavigationStack swipe-back,
/// MiniPlayerIsland, drag-to-dismiss PlayerScreen, Deep Links, Auth & Onboarding sheets.
public struct SieloRootView: View {
    @EnvironmentObject private var container: SieloContainer
    @StateObject private var router = SieloRouter()

    @State private var showLaunchReveal = true
    @State private var playerDragOffset: CGFloat = 0

    public init() {}

    public var body: some View {
        let playbackState = container.playerManager.playbackState

        ZStack(alignment: .bottom) {
            SieloColors.obsidianBlack.ignoresSafeArea()

            // Per-tab NavigationStacks for native iOS interactive edge-swipe back
            TabView(selection: $router.selectedTab) {
                NavigationStack(path: $router.homePath) {
                    HomeScreen(router: router)
                        .navigationDestination(for: SieloRoute.self) { routeDestination($0) }
                }
                .tag(SieloTab.home)

                NavigationStack(path: $router.searchPath) {
                    SearchScreen(router: router)
                        .navigationDestination(for: SieloRoute.self) { routeDestination($0) }
                }
                .tag(SieloTab.search)

                NavigationStack(path: $router.echoPath) {
                    ListenTogetherScreen(router: router)
                        .navigationDestination(for: SieloRoute.self) { routeDestination($0) }
                }
                .tag(SieloTab.echo)

                NavigationStack(path: $router.statsPath) {
                    StatsScreen()
                        .navigationDestination(for: SieloRoute.self) { routeDestination($0) }
                }
                .tag(SieloTab.stats)

                NavigationStack(path: $router.profilePath) {
                    ProfileScreen(router: router)
                        .navigationDestination(for: SieloRoute.self) { routeDestination($0) }
                }
                .tag(SieloTab.profile)
            }
            .toolbar(.hidden, for: .tabBar)

            // Floating Mini-Player Island + Floating Bottom Bar
            VStack(spacing: 8) {
                if playbackState.currentTrack != nil && !router.isPlayerExpanded && !router.isInsideRoomScreen {
                    MiniPlayerIsland(
                        playbackState: playbackState,
                        onTogglePlay: { container.playerManager.togglePlayPause() },
                        onToggleMute: { container.playerManager.toggleMute() },
                        onSkipPrevious: { container.playerManager.skipPrevious() },
                        onSkipNext: { container.playerManager.skipNext() },
                        onToggleLoop: { container.playerManager.toggleLoop() },
                        onTap: {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                                router.isPlayerExpanded = true
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if router.isBottomBarVisible {
                    SieloBottomBar(selectedTab: $router.selectedTab) { tab in
                        router.selectTab(tab)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.bottom, 4)

            // Full-Screen Vinyl, Lyrics & Queue Player with vertical drag-to-dismiss
            if router.isPlayerExpanded {
                PlayerScreen(
                    playerManager: container.playerManager,
                    dragOffset: $playerDragOffset,
                    onClose: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            router.isPlayerExpanded = false
                            playerDragOffset = 0
                        }
                    }
                )
                .transition(.move(edge: .bottom))
                .zIndex(10)
            }

            if showLaunchReveal {
                SieloLaunchReveal {
                    showLaunchReveal = false
                }
                .zIndex(20)
            }
        }
        .sheet(isPresented: Binding(
            get: { container.userManager.isAuthDialogOpen && !showLaunchReveal },
            set: { container.userManager.isAuthDialogOpen = $0 }
        )) {
            AuthDialogView(userManager: container.userManager)
        }
        .fullScreenCover(isPresented: Binding(
            get: { container.userManager.isOnboardingOpen && !showLaunchReveal },
            set: { container.userManager.isOnboardingOpen = $0 }
        )) {
            NewUserOnboardingScreen(userManager: container.userManager)
        }
        .onOpenURL { url in
            router.handleDeepLink(url)
        }
        .onChange(of: router.pendingDeepLinkAction) { action in
            guard let action else { return }
            router.pendingDeepLinkAction = nil
            Task { await executeDeepLink(action) }
        }
        .onAppear {
            if container.userManager.currentUser == nil && !container.userManager.isOnboardingOpen {
                container.userManager.isAuthDialogOpen = true
            }
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: SieloRoute) -> some View {
        switch route {
        case .settings:
            SettingsScreen(router: router)
        case .userPlaylists:
            UserPlaylistsScreen(router: router)
        case .artistProfile(let artist):
            ArtistProfileScreen(artist: artist)
        case .playlistDetail(let id, let title):
            PlaylistDetailScreen(playlistId: id, title: title)
        case .genreDetail(let genre):
            GenreOrCategoryDetailScreen(title: genre)
        case .searchCategory(let category):
            GenreOrCategoryDetailScreen(title: category)
        case .albumDetail(let album):
            GenreOrCategoryDetailScreen(title: album.title)
        }
    }

    private func executeDeepLink(_ action: DeepLinkAction) async {
        switch action {
        case .playTrack(let id, let title, let artist):
            if let title, let artist {
                let placeholder = SieloTrack(id: id, title: title, artist: artist)
                container.playerManager.playTrack(placeholder)
            }
            if let resolved = await InnerTubeClient.shared.resolveTrackById(id) {
                container.playerManager.playTrack(resolved)
            }
        case .openAlbum(let id, let artist):
            if let artist {
                router.push(.artistProfile(SieloArtist(id: artist.lowercased(), name: artist)), in: .home)
            } else {
                let tracks = await InnerTubeClient.shared.getAlbumSongs(id)
                if let first = tracks.first {
                    container.playerManager.playAlbum(tracks: tracks)
                    _ = first
                }
            }
        case .joinRoom(let url, let key):
            let name = container.userManager.currentUser?.name ?? "Listener"
            _ = container.listenTogetherManager.joinRoom(rawInput: url, keyOverride: key, userName: name)
        case .openArtist(let name):
            router.push(.artistProfile(SieloArtist(id: name.lowercased(), name: name)), in: .home)
        }
    }
}
