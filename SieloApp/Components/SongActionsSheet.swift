import SwiftUI
import SieloCoreModels
import SieloCoreAudio
import SieloCoreDatabase
import SieloCoreNetwork

/// Mirrors app/ui/components/SongActionsSheet.kt:
/// Play Now, Play Next, Add to Queue, Like/Unlike, Add to Playlist, Offline Download, Go to Artist, Share.
public struct SongActionsSheet: View {
    @EnvironmentObject private var container: SieloContainer
    @Environment(\.dismiss) private var dismiss

    let track: SieloTrack
    let onGoToArtist: (String) -> Void

    @State private var isFavorite = false
    @State private var isCached = false
    @State private var isDownloading = false
    @State private var showPlaylistPicker = false
    @State private var newPlaylistName = ""

    public init(track: SieloTrack, onGoToArtist: @escaping (String) -> Void) {
        self.track = track
        self.onGoToArtist = onGoToArtist
    }

    public var body: some View {
        NavigationStack {
            List {
                // Track Header
                Section {
                    HStack(spacing: 14) {
                        AsyncImage(url: track.thumbnailUrl.flatMap(URL.init)) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                SieloColors.surfaceElevated
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title)
                                .font(SieloTypography.titleMedium)
                                .foregroundColor(SieloColors.cream)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(SieloTypography.bodySmall)
                                .foregroundColor(SieloColors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .listRowBackground(SieloColors.oxfordBlue)
                }

                // Playback Actions
                Section("Playback") {
                    actionRow(icon: "play.fill", title: "Play Now") {
                        container.playerManager.playTrack(track)
                        dismiss()
                    }
                    actionRow(icon: "text.insert", title: "Play Next") {
                        container.playerManager.playNext(track)
                        dismiss()
                    }
                    actionRow(icon: "text.append", title: "Add to Queue") {
                        container.playerManager.appendToQueue(track)
                        dismiss()
                    }
                }

                // Library & Offline
                Section("Library") {
                    actionRow(
                        icon: isFavorite ? "heart.fill" : "heart",
                        title: isFavorite ? "Remove from Liked Songs" : "Like Song",
                        tint: isFavorite ? SieloColors.sand : SieloColors.cream
                    ) {
                        Task {
                            if isFavorite {
                                try? await container.database.favorites.deleteById(track.id)
                            } else {
                                try? await container.database.favorites.insertFavorite(
                                    FavoriteTrackEntity(id: track.id, title: track.title, artist: track.artist, thumbnailUrl: track.thumbnailUrl)
                                )
                            }
                            isFavorite.toggle()
                        }
                    }

                    actionRow(icon: "music.note.list", title: "Add to Playlist") {
                        showPlaylistPicker = true
                    }

                    Button {
                        if isCached {
                            OfflineCacheManager.shared.removeTrack(track.id)
                            isCached = false
                        } else if !isDownloading {
                            isDownloading = true
                            Task {
                                if let stream = await InnerTubeClient.shared.getStreamUrl(videoId: track.id, title: track.title, artist: track.artist) {
                                    let ok = await OfflineCacheManager.shared.downloadFully(track: track, streamURL: stream)
                                    isCached = ok
                                }
                                isDownloading = false
                            }
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: isCached ? "checkmark.circle.fill" : "arrow.down.circle")
                                .foregroundColor(isCached ? SieloColors.sageGreen : SieloColors.cream)
                            Text(isDownloading ? "Downloading..." : (isCached ? "Downloaded Offline (Tap to Remove)" : "Download for Offline Play"))
                                .foregroundColor(SieloColors.cream)
                            Spacer()
                            if isDownloading { ProgressView().tint(SieloColors.sand) }
                        }
                    }
                    .listRowBackground(SieloColors.oxfordBlue)
                }

                // Discover & Share
                Section("Discover") {
                    actionRow(icon: "person.fill", title: "Go to Artist (\(track.artist))") {
                        dismiss()
                        onGoToArtist(track.artist)
                    }

                    if let shareURL = shareURL() {
                        ShareLink(item: shareURL) {
                            HStack(spacing: 14) {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(SieloColors.cream)
                                Text("Share Song")
                                    .foregroundColor(SieloColors.cream)
                            }
                        }
                        .listRowBackground(SieloColors.oxfordBlue)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SieloColors.obsidianBlack)
            .navigationTitle("Track Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPlaylistPicker) {
                playlistPickerSheet
            }
            .task {
                isFavorite = (try? await container.database.favorites.isFavorite(id: track.id)) ?? false
                isCached = OfflineCacheManager.shared.isCached(track.id)
            }
        }
    }

    private func actionRow(icon: String, title: String, tint: Color = SieloColors.cream, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).foregroundColor(tint)
                Text(title).foregroundColor(SieloColors.cream)
            }
        }
        .listRowBackground(SieloColors.oxfordBlue)
    }

    private var playlistPickerSheet: some View {
        NavigationStack {
            List {
                Section("Create New") {
                    HStack {
                        TextField("New playlist name...", text: $newPlaylistName)
                            .foregroundColor(SieloColors.cream)
                        Button("Create") {
                            guard !newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            let created = container.playlistsRepository.createPlaylist(title: newPlaylistName, tracks: [track])
                            _ = created
                            newPlaylistName = ""
                            showPlaylistPicker = false
                            dismiss()
                        }
                        .foregroundColor(SieloColors.sand)
                    }
                    .listRowBackground(SieloColors.oxfordBlue)
                }

                Section("Your Playlists") {
                    ForEach(container.playlistsRepository.customPlaylistsOnly()) { playlist in
                        Button {
                            container.playlistsRepository.addTrack(track, toPlaylistId: playlist.id)
                            showPlaylistPicker = false
                            dismiss()
                        } label: {
                            Text(playlist.title).foregroundColor(SieloColors.cream)
                        }
                        .listRowBackground(SieloColors.oxfordBlue)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SieloColors.obsidianBlack)
            .navigationTitle("Add to Playlist")
        }
    }

    private func shareURL() -> URL? {
        var comps = URLComponents(string: "https://sielo.site/song/\(track.id)")
        comps?.queryItems = [
            URLQueryItem(name: "title", value: track.title),
            URLQueryItem(name: "artist", value: track.artist)
        ]
        return comps?.url
    }
}
