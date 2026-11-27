import SwiftUI
import SieloCoreModels
import SieloCoreDatabase
import SieloCoreAudio
import SieloCorePlaylistImport

// MARK: - ProfileScreen (mirrors ProfileScreen.kt)

public struct ProfileScreen: View {
    @EnvironmentObject private var container: SieloContainer
    @ObservedObject var router: SieloRouter

    @State private var favorites: [FavoriteTrackEntity] = []
    @State private var heavyRepeat: [SongStat] = []
    @State private var showLikedSheet = false
    @State private var showHistorySheet = false

    public init(router: SieloRouter) {
        self.router = router
    }

    public var body: some View {
        let user = container.userManager.currentUser

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Profile Header
                HStack(spacing: 14) {
                    Circle()
                        .fill(SieloColors.oxfordBlue)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Text(String((user?.name ?? "S").prefix(1)).uppercased())
                                .font(SieloTypography.headlineLarge)
                                .foregroundColor(SieloColors.sand)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(user?.name ?? "Guest Listener")
                            .font(SieloTypography.headlineMedium)
                            .foregroundColor(SieloColors.cream)
                        if let handle = user?.username, !handle.isEmpty {
                            Text("@\(handle)")
                                .font(SieloTypography.labelMedium)
                                .foregroundColor(SieloColors.sand)
                        } else {
                            Text(user?.email ?? "Not signed in")
                                .font(SieloTypography.bodySmall)
                                .foregroundColor(SieloColors.textSecondary)
                        }
                    }

                    Spacer()

                    Button {
                        if user == nil || user?.provider == .guest {
                            container.userManager.isAuthDialogOpen = true
                        } else {
                            Task { await container.userManager.signOut() }
                        }
                    } label: {
                        Text(user == nil || user?.provider == .guest ? "Sign In" : "Log Out")
                            .font(SieloTypography.labelMedium)
                            .foregroundColor(SieloColors.obsidianBlack)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(SieloColors.sand)
                            .clipShape(Capsule())
                    }
                }
                .padding(16)
                .background(SieloColors.oxfordBlue)
                .clipShape(RoundedRectangle(cornerRadius: 20))

                // Your Music Bento Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    bentoCard(title: "Liked Songs", subtitle: "\(favorites.count) tracks", icon: "heart.fill") {
                        showLikedSheet = true
                    }
                    bentoCard(title: "Playlists", subtitle: "\(container.playlistsRepository.playlists.count) lists", icon: "music.note.list") {
                        router.push(.userPlaylists, in: .profile)
                    }
                    bentoCard(title: "History", subtitle: "Recently played", icon: "clock.arrow.circlepath") {
                        showHistorySheet = true
                    }
                    bentoCard(title: "Downloads", subtitle: "\(OfflineCacheManager.shared.getCachedTracks().count) cached", icon: "arrow.down.circle.fill") {
                        router.push(.playlistDetail(id: UserPlaylist.downloadedCacheId, title: "Downloaded Cache"), in: .profile)
                    }
                }

                // Favorite Artists
                if let favArtists = user?.favoriteArtists, !favArtists.isEmpty {
                    Text("Favorite Artists")
                        .font(SieloTypography.headlineSmall)
                        .foregroundColor(SieloColors.cream)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(favArtists, id: \.self) { name in
                                Button {
                                    router.push(.artistProfile(SieloArtist(id: name.lowercased(), name: name)), in: .profile)
                                } label: {
                                    Text(name)
                                        .font(SieloTypography.labelMedium)
                                        .foregroundColor(SieloColors.cream)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(SieloColors.oxfordBlue)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                // On Heavy Repeat
                if !heavyRepeat.isEmpty {
                    Text("On Heavy Repeat")
                        .font(SieloTypography.headlineSmall)
                        .foregroundColor(SieloColors.cream)

                    ForEach(Array(heavyRepeat.prefix(10).enumerated()), id: \.offset) { idx, song in
                        Button {
                            let tracks = heavyRepeat.map {
                                SieloTrack(id: $0.songId, title: $0.songTitle, artist: $0.artistName, thumbnailUrl: $0.thumbnailUrl)
                            }
                            container.playerManager.playTrack(tracks[idx], queue: tracks)
                        } label: {
                            HStack {
                                Text("#\(idx + 1)")
                                    .font(SieloTypography.titleSmall)
                                    .foregroundColor(SieloColors.sand)
                                    .frame(width: 28, alignment: .leading)
                                VStack(alignment: .leading) {
                                    Text(song.songTitle).font(SieloTypography.titleSmall).foregroundColor(SieloColors.cream).lineLimit(1)
                                    Text(song.artistName).font(SieloTypography.bodySmall).foregroundColor(SieloColors.textSecondary).lineLimit(1)
                                }
                                Spacer()
                                Text("\(song.playCount)x").font(SieloTypography.labelSmall).foregroundColor(SieloColors.sageGreen)
                            }
                            .padding(12)
                            .background(SieloColors.oxfordBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
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
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { router.push(.userPlaylists, in: .profile) } label: {
                    Image(systemName: "music.note.list").foregroundColor(SieloColors.cream)
                }
                Button { router.push(.settings, in: .profile) } label: {
                    Image(systemName: "gearshape.fill").foregroundColor(SieloColors.cream)
                }
            }
        }
        .sheet(isPresented: $showLikedSheet) {
            NavigationStack {
                List(favorites) { fav in
                    Button {
                        let tracks = favorites.map { SieloTrack(id: $0.id, title: $0.title, artist: $0.artist, thumbnailUrl: $0.thumbnailUrl) }
                        if let match = tracks.first(where: { $0.id == fav.id }) {
                            container.playerManager.playTrack(match, queue: tracks)
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(fav.title).foregroundColor(SieloColors.cream)
                            Text(fav.artist).font(.caption).foregroundColor(SieloColors.textSecondary)
                        }
                    }
                    .listRowBackground(SieloColors.oxfordBlue)
                }
                .scrollContentBackground(.hidden)
                .background(SieloColors.obsidianBlack)
                .navigationTitle("Liked Songs")
            }
        }
        .sheet(isPresented: $showHistorySheet) {
            NavigationStack {
                HistorySheetView(database: container.database, playerManager: container.playerManager)
            }
        }
        .task {
            favorites = (try? await container.database.favorites.getAllFavoritesList()) ?? []
            heavyRepeat = (try? await container.database.listeningHistory.getTopSongsSnapshot(sinceMs: 0, limit: 10)) ?? []
        }
    }

    private func bentoCard(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).foregroundColor(SieloColors.sand).font(.title3)
                Text(title).font(SieloTypography.titleMedium).foregroundColor(SieloColors.cream)
                Text(subtitle).font(SieloTypography.bodySmall).foregroundColor(SieloColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(SieloColors.oxfordBlue)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(SieloColors.borderGlass, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct HistorySheetView: View {
    let database: SieloDatabase
    let playerManager: PlayerManager
    @State private var events: [ListeningEventEntity] = []

    var body: some View {
        List(events) { ev in
            Button {
                let track = SieloTrack(id: ev.songId, title: ev.songTitle, artist: ev.artistName, album: ev.albumName, thumbnailUrl: ev.thumbnailUrl)
                playerManager.playTrack(track)
            } label: {
                VStack(alignment: .leading) {
                    Text(ev.songTitle).foregroundColor(SieloColors.cream)
                    Text(ev.artistName).font(.caption).foregroundColor(SieloColors.textSecondary)
                }
            }
            .listRowBackground(SieloColors.oxfordBlue)
        }
        .scrollContentBackground(.hidden)
        .background(SieloColors.obsidianBlack)
        .navigationTitle("Listening History")
        .task {
            events = (try? await database.listeningHistory.getAllHistoryList(limit: 100)) ?? []
        }
    }
}

// MARK: - SettingsScreen (12 Subscreens with native iOS NavigationLink swipe-back)

public struct SettingsScreen: View {
    @EnvironmentObject private var container: SieloContainer
    @ObservedObject var router: SieloRouter

    public init(router: SieloRouter) {
        self.router = router
    }

    public var body: some View {
        let settings = container.settingsRepository

        List {
            Section("Account") {
                NavigationLink("Account & @Username") {
                    AccountSettingsSubscreen(userManager: container.userManager)
                }
                NavigationLink("Connected Services") {
                    Text("Google & Sielo Cloud Sync Active").foregroundColor(SieloColors.cream)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(SieloColors.obsidianBlack)
                }
            }

            Section("Audio & Playback") {
                NavigationLink("Audio Quality & Equalizer") {
                    AudioPlaybackSettingsView(settings: settings)
                }
                NavigationLink("Player Behavior") {
                    PlayerBehaviorSettingsView(settings: settings)
                }
                NavigationLink("Audio Output") {
                    Form {
                        Toggle("Pause on Disconnect", isOn: Binding(
                            get: { settings.pauseOnDisconnect },
                            set: { settings.pauseOnDisconnect = $0; container.playerManager.pauseOnDisconnect = $0 }
                        ))
                        Toggle("Bluetooth Auto-Resume", isOn: Binding(get: { settings.bluetoothAutoResume }, set: { settings.bluetoothAutoResume = $0 }))
                        Toggle("Volume Normalization", isOn: Binding(get: { settings.volumeNormalization }, set: { settings.volumeNormalization = $0 }))
                    }
                    .scrollContentBackground(.hidden).background(SieloColors.obsidianBlack)
                    .navigationTitle("Audio Output")
                }
            }

            Section("Storage, Appearance & Privacy") {
                NavigationLink("Downloads & Storage (\(settings.cacheSizeFormatted))") {
                    Form {
                        Toggle("Download on Wi-Fi Only", isOn: Binding(get: { settings.downloadWifiOnly }, set: { settings.downloadWifiOnly = $0 }))
                        Toggle("Auto-Sync Imported Playlists", isOn: Binding(get: { settings.playlistAutoSyncEnabled }, set: { settings.playlistAutoSyncEnabled = $0 }))
                        Button("Clear Offline Cache", role: .destructive) { settings.clearCache() }
                    }
                    .scrollContentBackground(.hidden).background(SieloColors.obsidianBlack)
                    .navigationTitle("Downloads & Storage")
                }
                NavigationLink("Appearance") {
                    Form {
                        Toggle("OLED Dark Theme", isOn: Binding(get: { settings.oledDarkTheme }, set: { settings.oledDarkTheme = $0 }))
                        Toggle("Dynamic Artwork Tint", isOn: Binding(get: { settings.dynamicArtworkTint }, set: { settings.dynamicArtworkTint = $0 }))
                    }
                    .scrollContentBackground(.hidden).background(SieloColors.obsidianBlack)
                    .navigationTitle("Appearance")
                }
                NavigationLink("Privacy & Recommendations") {
                    Form {
                        Toggle("Private Listening", isOn: Binding(
                            get: { settings.privateListening },
                            set: { val in
                                settings.privateListening = val
                                Task { await container.eventDispatcher.setPrivateListening(val) }
                            }
                        ))
                        Toggle("Prioritize Followed Artists", isOn: Binding(get: { settings.prioritizeFollowedArtists }, set: { settings.prioritizeFollowedArtists = $0 }))
                    }
                    .scrollContentBackground(.hidden).background(SieloColors.obsidianBlack)
                    .navigationTitle("Privacy & Recommendations")
                }
            }

            Section("Info") {
                NavigationLink("About Sielo") {
                    VStack(spacing: 12) {
                        Text("Sielo Music").font(SieloFont.macondo(size: 36)).foregroundColor(SieloColors.cream)
                        Text("iOS Edition • v12.0.0").font(SieloTypography.bodyMedium).foregroundColor(SieloColors.sand)
                        Link("Official Website (sielo.site)", destination: URL(string: "https://sielo.site")!)
                            .foregroundColor(SieloColors.sageGreen)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SieloColors.obsidianBlack)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(SieloColors.obsidianBlack.ignoresSafeArea())
        .navigationTitle("Settings")
        .onDisappear { router.isBottomBarHiddenForDetail = false }
    }
}

private struct AccountSettingsSubscreen: View {
    @ObservedObject var userManager: UserManager
    @State private var usernameInput = ""
    @State private var statusMessage = ""

    var body: some View {
        Form {
            Section("Username") {
                TextField("@username", text: $usernameInput)
                if !statusMessage.isEmpty {
                    Text(statusMessage).font(.caption).foregroundColor(SieloColors.sand)
                }
                Button("Check & Claim Username") {
                    Task {
                        let (_, msg) = await userManager.checkUsernameAvailability(usernameInput)
                        statusMessage = msg
                        _ = await userManager.claimUsername(usernameInput)
                    }
                }
            }
            Section {
                Button("Delete Account Permanently", role: .destructive) {
                    Task { await userManager.deleteAccount() }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(SieloColors.obsidianBlack)
        .navigationTitle("Account")
        .onAppear { usernameInput = userManager.currentUser?.username ?? "" }
    }
}

private struct AudioPlaybackSettingsView: View {
    @ObservedObject var settings: SettingsRepository

    var body: some View {
        Form {
            Picker("Stream Quality", selection: $settings.streamQuality) {
                Text("Master (320kbps Opus / FLAC)").tag("Master (320kbps Opus / FLAC)")
                Text("High (160kbps)").tag("High (160kbps)")
                Text("Data Saver (96kbps)").tag("Data Saver (96kbps)")
            }
            Toggle("Equalizer", isOn: $settings.equalizerEnabled)
            Picker("EQ Preset", selection: $settings.equalizerPreset) {
                ForEach(AudioEffectsManager.shared.availablePresets, id: \.self) { preset in
                    Text(preset).tag(preset)
                }
            }
            Toggle("Bass Boost", isOn: $settings.bassBoostEnabled)
            Slider(value: Binding(get: { Double(settings.bassStrength) }, set: { settings.bassStrength = Int($0) }), in: 0...1000)
        }
        .scrollContentBackground(.hidden)
        .background(SieloColors.obsidianBlack)
        .navigationTitle("Audio & EQ")
    }
}

private struct PlayerBehaviorSettingsView: View {
    @ObservedObject var settings: SettingsRepository

    var body: some View {
        Form {
            Toggle("Autoplay Recommendations", isOn: $settings.autoplayEnabled)
            Toggle("Remember Playback Position", isOn: $settings.rememberPosition)
            Toggle("Gapless Playback", isOn: $settings.gaplessPlayback)
            Stepper("Crossfade: \(settings.crossfadeSeconds)s", value: $settings.crossfadeSeconds, in: 0...12)
        }
        .scrollContentBackground(.hidden)
        .background(SieloColors.obsidianBlack)
        .navigationTitle("Player Behavior")
    }
}

// MARK: - UserPlaylistsScreen & PlaylistDetailScreen

public struct UserPlaylistsScreen: View {
    @EnvironmentObject private var container: SieloContainer
    @ObservedObject var router: SieloRouter

    @State private var showCreate = false
    @State private var newTitle = ""
    @State private var showImport = false
    @State private var importInput = ""
    @State private var importStatus = ""

    public init(router: SieloRouter) { self.router = router }

    public var body: some View {
        List {
            ForEach(container.playlistsRepository.playlists) { playlist in
                Button {
                    router.push(.playlistDetail(id: playlist.id, title: playlist.title), in: .profile)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(playlist.title).font(SieloTypography.titleMedium).foregroundColor(SieloColors.cream)
                        Text("\(playlist.tracks.count) tracks • \(playlist.description)")
                            .font(SieloTypography.bodySmall).foregroundColor(SieloColors.textSecondary).lineLimit(1)
                    }
                }
                .listRowBackground(SieloColors.oxfordBlue)
            }
        }
        .scrollContentBackground(.hidden)
        .background(SieloColors.obsidianBlack.ignoresSafeArea())
        .navigationTitle("Your Playlists")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showImport = true } label: { Image(systemName: "square.and.arrow.down") }
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .alert("New Playlist", isPresented: $showCreate) {
            TextField("Playlist title", text: $newTitle)
            Button("Create") {
                if !newTitle.isEmpty {
                    _ = container.playlistsRepository.createPlaylist(title: newTitle)
                    newTitle = ""
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showImport) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Paste Spotify / YouTube Playlist Link or Track List")
                        .font(SieloTypography.titleSmall)
                        .foregroundColor(SieloColors.cream)
                    TextEditor(text: $importInput)
                        .frame(height: 150)
                        .scrollContentBackground(.hidden)
                        .background(SieloColors.oxfordBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    if !importStatus.isEmpty {
                        Text(importStatus).font(SieloTypography.bodySmall).foregroundColor(SieloColors.sand)
                    }
                    Button("Import Playlist") {
                        Task {
                            importStatus = "Importing..."
                            do {
                                let res = try await PlaylistImportRepository.shared.importFromInput(importInput)
                                _ = container.playlistsRepository.createPlaylist(
                                    title: res.playlistTitle,
                                    tracks: res.importedTracks,
                                    syncUrl: importInput.hasPrefix("http") ? importInput : nil
                                )
                                importStatus = "Imported \(res.importedTracks.count)/\(res.totalCandidates) tracks!"
                            } catch {
                                importStatus = error.localizedDescription
                            }
                        }
                    }
                    .padding()
                    .background(SieloColors.sand)
                    .foregroundColor(SieloColors.obsidianBlack)
                    .clipShape(Capsule())
                    Spacer()
                }
                .padding()
                .background(SieloColors.obsidianBlack)
                .navigationTitle("Universal Importer")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showImport = false }
                    }
                }
            }
        }
        .onDisappear { router.isBottomBarHiddenForDetail = false }
    }
}

public struct PlaylistDetailScreen: View {
    @EnvironmentObject private var container: SieloContainer
    let playlistId: String
    let title: String

    public init(playlistId: String, title: String) {
        self.playlistId = playlistId
        self.title = title
    }

    public var body: some View {
        let playlist = container.playlistsRepository.playlists.first(where: { $0.id == playlistId })
        let tracks = playlist?.tracks ?? []

        List {
            if !tracks.isEmpty {
                Section {
                    Button {
                        container.playerManager.playAlbum(tracks: tracks)
                    } label: {
                        Label("PLAY ALL (\(tracks.count))", systemImage: "play.fill")
                            .font(SieloTypography.titleSmall)
                            .foregroundColor(SieloColors.obsidianBlack)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(SieloColors.sand)
                            .clipShape(Capsule())
                    }
                    .listRowBackground(Color.clear)
                }
            }

            ForEach(tracks) { track in
                Button {
                    container.playerManager.playAlbum(tracks: tracks, startIndex: tracks.firstIndex(where: { $0.id == track.id }) ?? 0)
                } label: {
                    VStack(alignment: .leading) {
                        Text(track.title).foregroundColor(SieloColors.cream)
                        Text(track.artist).font(.caption).foregroundColor(SieloColors.textSecondary)
                    }
                }
                .listRowBackground(SieloColors.oxfordBlue)
            }
            .onMove { from, to in
                container.playlistsRepository.reorderTracks(inPlaylistId: playlistId, fromOffsets: from, toOffset: to)
            }
        }
        .scrollContentBackground(.hidden)
        .background(SieloColors.obsidianBlack.ignoresSafeArea())
        .navigationTitle(title)
    }
}
