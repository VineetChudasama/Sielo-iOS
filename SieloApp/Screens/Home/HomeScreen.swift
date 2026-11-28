import SwiftUI
import SieloCoreModels
import SieloCoreNetwork
import SieloCoreAudio
import SieloCoreDatabase

/// Mirrors HomeScreen.kt + HomeViewModel.kt:
/// Sielo Macondo header, Search shortcut, Offline Vault card, Keep Listening, Songs for You,
/// Similar Artists, Curated Mixes & Import, Rediscover Favorites, and 10 Trending Genres.
public struct HomeScreen: View {
    @EnvironmentObject private var container: SieloContainer
    @ObservedObject var router: SieloRouter

    @State private var keepListening: [SieloTrack] = []
    @State private var songsForYou: [SieloTrack] = []
    @State private var rediscoverFavorites: [SieloTrack] = []
    @State private var similarArtists: [SieloArtist] = []
    @State private var selectedActionTrack: SieloTrack?
    @State private var showUpdateAlert = false
    @State private var isLoading = false
    @StateObject private var updateManager = AppUpdateManager.shared
    @Environment(\.openURL) private var openURL

    private let genres = [
        "Bollywood", "Punjabi", "Pop", "Hip Hop", "Lo-Fi",
        "Indie", "R&B", "Rock", "EDM", "Acoustic"
    ]

    public init(router: SieloRouter) {
        self.router = router
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                HStack {
                    Text("Sielo")
                        .font(SieloFont.macondo(size: 34))
                        .foregroundColor(SieloColors.cream)
                    Spacer()
                    if let newVer = updateManager.availableVersion {
                        Button {
                            showUpdateAlert = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("v\(newVer)")
                            }
                            .font(SieloTypography.labelSmall)
                            .foregroundColor(SieloColors.obsidianBlack)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(SieloColors.sand)
                            .clipShape(Capsule())
                        }
                    }
                    Button {
                        router.selectTab(.search)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(SieloColors.cream)
                            .padding(10)
                            .background(SieloColors.oxfordBlue)
                            .clipShape(Circle())
                    }
                }

                // Offline Vault Card
                if !NetworkHelper.shared.isOnline || !OfflineCacheManager.shared.getCachedTracks().isEmpty {
                    Button {
                        router.push(.playlistDetail(id: UserPlaylist.downloadedCacheId, title: "Downloaded Cache"))
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(SieloColors.sand)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Downloaded Cache")
                                    .font(SieloTypography.titleMedium)
                                    .foregroundColor(SieloColors.cream)
                                Text("\(OfflineCacheManager.shared.getCachedTracks().count) tracks ready offline")
                                    .font(SieloTypography.bodySmall)
                                    .foregroundColor(SieloColors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(SieloColors.textSecondary)
                        }
                        .padding(14)
                        .background(SieloColors.oxfordBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SieloColors.borderGlass, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                // Keep Listening
                if !keepListening.isEmpty {
                    sectionHeader("Keep listening")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(keepListening) { track in
                                trackCard(track, queue: keepListening)
                            }
                        }
                    }
                }

                // Songs for You
                if !songsForYou.isEmpty {
                    sectionHeader("Songs for you")
                    VStack(spacing: 10) {
                        ForEach(songsForYou.prefix(10)) { track in
                            trackRow(track, queue: songsForYou)
                        }
                    }
                }

                // Similar Artists
                if !similarArtists.isEmpty {
                    sectionHeader("Artists you might like")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(similarArtists) { artist in
                                Button {
                                    router.push(.artistProfile(artist))
                                } label: {
                                    VStack(spacing: 8) {
                                        Circle()
                                            .fill(SieloColors.oxfordBlue)
                                            .frame(width: 86, height: 86)
                                            .overlay(
                                                Text(String(artist.name.prefix(1)))
                                                    .font(SieloTypography.headlineMedium)
                                                    .foregroundColor(SieloColors.sand)
                                            )
                                        Text(artist.name)
                                            .font(SieloTypography.labelMedium)
                                            .foregroundColor(SieloColors.cream)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 90)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Your Playlists Carousel
                if !container.playlistsRepository.playlists.isEmpty {
                    sectionHeader("Your playlists")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(container.playlistsRepository.playlists) { playlist in
                                Button {
                                    router.push(.playlistDetail(id: playlist.id, title: playlist.title))
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(SieloColors.oxfordBlue)
                                            .frame(width: 124, height: 124)
                                            .overlay(
                                                Image(systemName: playlist.id == UserPlaylist.downloadedCacheId ? "arrow.down.circle.fill" : "music.note.list")
                                                    .font(.title)
                                                    .foregroundColor(SieloColors.sand)
                                            )
                                        Text(playlist.title)
                                            .font(SieloTypography.titleSmall)
                                            .foregroundColor(SieloColors.cream)
                                            .lineLimit(1)
                                        Text("\(playlist.tracks.count) tracks")
                                            .font(SieloTypography.bodySmall)
                                            .foregroundColor(SieloColors.textSecondary)
                                    }
                                    .frame(width: 124)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Rediscover Your Favorites
                if !rediscoverFavorites.isEmpty {
                    sectionHeader("Rediscover Your Favorites")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(rediscoverFavorites) { track in
                                trackCard(track, queue: rediscoverFavorites)
                            }
                        }
                    }
                }

                // Trending Music Genres
                sectionHeader("Trending Music Genres")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(genres, id: \.self) { genre in
                        Button {
                            router.push(.genreDetail(genre))
                        } label: {
                            HStack {
                                Text(genre)
                                    .font(SieloTypography.titleSmall)
                                    .foregroundColor(SieloColors.cream)
                                Spacer()
                                Image(systemName: "waveform")
                                    .foregroundColor(SieloColors.sand.opacity(0.8))
                            }
                            .padding(16)
                            .background(SieloColors.oxfordBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(SieloColors.borderGlass, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 160)
        }
        .background(SieloColors.obsidianBlack.ignoresSafeArea())
        .refreshable {
            await refreshHome()
        }
        .sheet(item: $selectedActionTrack) { track in
            SongActionsSheet(track: track) { artistName in
                router.push(.artistProfile(SieloArtist(id: artistName.lowercased(), name: artistName)))
            }
        }
        .alert("Update Available (v\(updateManager.availableVersion ?? ""))", isPresented: $showUpdateAlert) {
            Button("Update in AltStore") {
                if let url = URL(string: "altstore://") { openURL(url) }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text(updateManager.releaseNotes ?? "A newer build of Sielo iOS is ready.")
        }
        .task {
            await updateManager.checkForUpdates()
            if songsForYou.isEmpty {
                await refreshHome()
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(SieloTypography.headlineMedium)
            .foregroundColor(SieloColors.cream)
    }

    private func trackCard(_ track: SieloTrack, queue: [SieloTrack]) -> some View {
        Button {
            container.playerManager.playTrack(track, queue: queue)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                AsyncImage(url: track.thumbnailUrl.flatMap(URL.init)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        SieloColors.oxfordBlue
                    }
                }
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(track.title)
                    .font(SieloTypography.titleSmall)
                    .foregroundColor(SieloColors.cream)
                    .lineLimit(1)
                Text(track.artist)
                    .font(SieloTypography.bodySmall)
                    .foregroundColor(SieloColors.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 132)
        }
        .buttonStyle(.plain)
    }

    private func trackRow(_ track: SieloTrack, queue: [SieloTrack]) -> some View {
        Button {
            container.playerManager.playTrack(track, queue: queue)
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: track.thumbnailUrl.flatMap(URL.init)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        SieloColors.surfaceElevated
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(SieloTypography.titleSmall)
                        .foregroundColor(SieloColors.cream)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(SieloTypography.bodySmall)
                        .foregroundColor(SieloColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(track.formattedDuration)
                    .font(SieloTypography.labelSmall)
                    .foregroundColor(SieloColors.textMuted)
                Button {
                    selectedActionTrack = track
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(SieloColors.textSecondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(SieloColors.oxfordBlue)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { container.playerManager.playNext(track) } label: { Label("Play Next", systemImage: "text.insert") }
            Button { container.playerManager.appendToQueue(track) } label: { Label("Add to Queue", systemImage: "text.append") }
            Button { selectedActionTrack = track } label: { Label("More Actions", systemImage: "ellipsis.circle") }
        }
    }

    private func refreshHome() async {
        isLoading = true
        defer { isLoading = false }

        // Keep listening from local DB
        if let recent = try? await container.database.listeningHistory.getAllHistoryList(limit: 20) {
            var seen = Set<String>()
            keepListening = recent.compactMap { ev in
                guard seen.insert(ev.songId).inserted else { return nil }
                return SieloTrack(id: ev.songId, title: ev.songTitle, artist: ev.artistName, album: ev.albumName, thumbnailUrl: ev.thumbnailUrl)
            }.prefix(5).map { $0 }
        }

        // Rediscover Favorites (>48h unplayed)
        if let favs = try? await container.database.favorites.getAllFavoritesList() {
            let twoDaysAgoMs = Int64((Date().timeIntervalSince1970 - 48 * 3600) * 1000)
            let recentIds = Set((try? await container.database.listeningHistory.getSongIdsPlayedSince(twoDaysAgoMs)) ?? [])
            rediscoverFavorites = favs
                .filter { !recentIds.contains($0.id) }
                .prefix(8)
                .map { SieloTrack(id: $0.id, title: $0.title, artist: $0.artist, thumbnailUrl: $0.thumbnailUrl) }
        }

        let seedArtists = container.userManager.getTopTasteArtists() + (container.userManager.currentUser?.favoriteArtists ?? [])
        let seedQuery = seedArtists.first ?? "Arijit Singh"
        let searchRes = await InnerTubeClient.shared.search(query: seedQuery)
        songsForYou = searchRes.tracks

        let artists = await InnerTubeClient.shared.searchArtists(query: seedQuery)
        similarArtists = Array(artists.prefix(8))
    }
}
