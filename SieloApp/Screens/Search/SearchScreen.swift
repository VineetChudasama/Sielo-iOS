import SwiftUI
import SieloCoreModels
import SieloCoreNetwork
import SieloCoreDatabase

/// Mirrors SearchScreen.kt:
/// Live search with All / Songs / Artists filter chips, Recent Searches, Recently Played, and Browse Categories.
public struct SearchScreen: View {
    @EnvironmentObject private var container: SieloContainer
    @ObservedObject var router: SieloRouter

    @State private var query: String = ""
    @State private var selectedFilter: String = "All"
    @State private var tracks: [SieloTrack] = []
    @State private var artists: [SieloArtist] = []
    @State private var recentQueries: [String] = []
    @State private var selectedActionTrack: SieloTrack?
    @State private var isSearching = false

    private let filters = ["All", "Songs", "Artists"]
    private let categories = ["Bollywood", "Punjabi", "Hip Hop", "Lo-Fi", "Pop", "Romantic", "Workout", "Party"]

    public init(router: SieloRouter) {
        self.router = router
    }

    public var body: some View {
        VStack(spacing: 14) {
            // Search Bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(SieloColors.sand)
                TextField("Search songs, artists, albums...", text: $query)
                    .font(SieloTypography.bodyLarge)
                    .foregroundColor(SieloColors.cream)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await performSearch() }
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                        tracks = []
                        artists = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(SieloColors.textSecondary)
                    }
                }
            }
            .padding(12)
            .background(SieloColors.oxfordBlue)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(SieloColors.borderGlass, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if query.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !recentQueries.isEmpty {
                            HStack {
                                Text("Recent Searches")
                                    .font(SieloTypography.headlineSmall)
                                    .foregroundColor(SieloColors.cream)
                                Spacer()
                                Button("Clear all") {
                                    Task {
                                        try? await container.database.searchHistory.clearAllSearchHistory()
                                        recentQueries = []
                                    }
                                }
                                .font(SieloTypography.labelMedium)
                                .foregroundColor(SieloColors.sand)
                            }

                            FlowLayout(items: recentQueries.prefix(8).map { $0 }) { q in
                                Button {
                                    query = q
                                    Task { await performSearch() }
                                } label: {
                                    Text(q)
                                        .font(SieloTypography.labelMedium)
                                        .foregroundColor(SieloColors.cream)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(SieloColors.oxfordBlue)
                                        .clipShape(Capsule())
                                }
                            }
                        }

                        Text("Browse Categories")
                            .font(SieloTypography.headlineSmall)
                            .foregroundColor(SieloColors.cream)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(Array(categories.enumerated()), id: \.element) { idx, cat in
                                Button {
                                    router.push(.searchCategory(cat))
                                } label: {
                                    ZStack(alignment: .bottomTrailing) {
                                        Text(cat)
                                            .font(SieloTypography.titleSmall)
                                            .foregroundColor(SieloColors.cream)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                            .padding(16)
                                        Image(systemName: "music.quarternote.3")
                                            .font(.title2)
                                            .foregroundColor(SieloColors.cream.opacity(0.25))
                                            .padding(12)
                                    }
                                    .frame(height: 82)
                                    .background(categoryGradient(index: idx))
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 160)
                }
            } else {
                // Filter Chips
                HStack(spacing: 10) {
                    ForEach(filters, id: \.self) { filter in
                        Button {
                            selectedFilter = filter
                        } label: {
                            Text(filter)
                                .font(SieloTypography.labelMedium)
                                .foregroundColor(selectedFilter == filter ? SieloColors.obsidianBlack : SieloColors.cream)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(selectedFilter == filter ? SieloColors.sand : SieloColors.oxfordBlue)
                                .clipShape(Capsule())
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)

                if isSearching {
                    Spacer()
                    ProgressView().tint(SieloColors.sand)
                    Spacer()
                } else {
                    List {
                        if (selectedFilter == "All" || selectedFilter == "Artists") && !artists.isEmpty {
                            Section("Artists") {
                                ForEach(artists.prefix(5)) { artist in
                                    Button {
                                        router.push(.artistProfile(artist))
                                    } label: {
                                        HStack(spacing: 12) {
                                            ArtistAvatarView(name: artist.name, imageUrl: artist.imageUrl, size: 46)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(artist.name)
                                                    .font(SieloTypography.titleSmall)
                                                    .foregroundColor(SieloColors.cream)
                                                Text("Artist")
                                                    .font(SieloTypography.labelSmall)
                                                    .foregroundColor(SieloColors.textSecondary)
                                            }
                                        }
                                    }
                                    .listRowBackground(SieloColors.oxfordBlue)
                                }
                            }
                        }

                        if selectedFilter == "All" || selectedFilter == "Songs" {
                            Section("Songs") {
                                ForEach(tracks) { track in
                                    Button {
                                        container.playerManager.playTrack(track, queue: tracks)
                                    } label: {
                                        HStack(spacing: 12) {
                                            TrackArtworkView(title: track.title, artist: track.artist, urlString: track.thumbnailUrl, size: 50, cornerRadius: 10)
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text(track.title)
                                                        .font(SieloTypography.titleSmall)
                                                        .foregroundColor(SieloColors.cream)
                                                        .lineLimit(1)
                                                    if track.isExplicit {
                                                        Text("E")
                                                            .font(.system(size: 10, weight: .bold))
                                                            .foregroundColor(SieloColors.obsidianBlack)
                                                            .padding(.horizontal, 4)
                                                            .background(SieloColors.textSecondary)
                                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                                    }
                                                }
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
                                    }
                                    .listRowBackground(SieloColors.oxfordBlue)
                                    .contextMenu {
                                        Button { container.playerManager.playNext(track) } label: { Label("Play Next", systemImage: "text.insert") }
                                        Button { container.playerManager.appendToQueue(track) } label: { Label("Add to Queue", systemImage: "text.append") }
                                        Button { selectedActionTrack = track } label: { Label("More Actions", systemImage: "ellipsis.circle") }
                                    }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .background(SieloColors.obsidianBlack.ignoresSafeArea())
        .sheet(item: $selectedActionTrack) { track in
            SongActionsSheet(track: track) { artistName in
                router.push(.artistProfile(SieloArtist(id: artistName.lowercased(), name: artistName)))
            }
        }
        .task {
            if let list = try? await container.database.searchHistory.getAllSearchQueries() {
                recentQueries = list.map(\.query)
            }
        }
    }

    private func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }

        try? await container.database.searchHistory.insertSearchQuery(SearchHistoryEntity(query: trimmed))
        if !recentQueries.contains(trimmed) {
            recentQueries.insert(trimmed, at: 0)
        }

        async let searchRes = InnerTubeClient.shared.search(query: trimmed)
        async let artistRes = InnerTubeClient.shared.searchArtists(query: trimmed)
        tracks = await searchRes.tracks
        artists = await artistRes
    }
    private func categoryGradient(index: Int) -> LinearGradient {
        let palettes: [(Color, Color)] = [
            (Color(hex: 0x3D2645), Color(hex: 0x1B263B)),
            (Color(hex: 0x1F4E5F), Color(hex: 0x0D1B2A)),
            (Color(hex: 0x5C3D2E), Color(hex: 0x1B263B)),
            (Color(hex: 0x2D4059), Color(hex: 0x1B263B)),
            (Color(hex: 0x4A2545), Color(hex: 0x1B263B)),
            (Color(hex: 0x2B580C), Color(hex: 0x0D1B2A)),
            (Color(hex: 0x6B2D5C), Color(hex: 0x1B263B)),
            (Color(hex: 0x3F4E4F), Color(hex: 0x0D1B2A))
        ]
        let pair = palettes[index % palettes.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Reusable Artist Avatar with async Deezer/Wikipedia photo fallback.
public struct ArtistAvatarView: View {
    let name: String
    let imageUrl: String?
    let size: CGFloat

    @State private var resolvedUrl: String?

    public init(name: String, imageUrl: String?, size: CGFloat) {
        self.name = name
        self.imageUrl = imageUrl
        self.size = size
    }

    public var body: some View {
        let activeUrl = (resolvedUrl ?? imageUrl).flatMap(URL.init)
        Group {
            if let activeUrl {
                AsyncImage(url: activeUrl) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        fallbackCircle
                    }
                }
            } else {
                fallbackCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(SieloColors.borderGlass, lineWidth: 1))
        .task(id: name) {
            if imageUrl == nil || imageUrl?.isEmpty == true {
                resolvedUrl = await ArtistMetadataResolver.shared.resolveArtistPhoto(artistName: name)
            }
        }
    }

    private var fallbackCircle: some View {
        Circle()
            .fill(SieloColors.surfaceElevated)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(SieloTypography.titleMedium)
                    .foregroundColor(SieloColors.sand)
            )
    }
}

/// Reusable Track Artwork with JioSaavn/iTunes/Deezer fallback.
public struct TrackArtworkView: View {
    let title: String
    let artist: String
    let urlString: String?
    let size: CGFloat
    let cornerRadius: CGFloat

    @State private var resolvedUrl: String?

    public init(title: String, artist: String, urlString: String?, size: CGFloat, cornerRadius: CGFloat = 10) {
        self.title = title
        self.artist = artist
        self.urlString = urlString
        self.size = size
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let activeUrl = (resolvedUrl ?? urlString).flatMap(URL.init)
        Group {
            if let activeUrl {
                AsyncImage(url: activeUrl) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: "\(title)|\(artist)") {
            if urlString == nil || urlString?.isEmpty == true {
                resolvedUrl = await JioSaavnSongArtworkResolver.shared.resolveArtwork(title: title, artist: artist)
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(SieloColors.surfaceElevated)
            .overlay(Image(systemName: "music.note").foregroundColor(SieloColors.sand.opacity(0.6)))
    }
}

private struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}
