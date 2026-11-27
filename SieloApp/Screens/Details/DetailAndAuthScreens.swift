import SwiftUI
import SieloCoreModels
import SieloCoreNetwork

// MARK: - ArtistProfileScreen (mirrors ArtistProfileScreen.kt)

public struct ArtistProfileScreen: View {
    @EnvironmentObject private var container: SieloContainer
    let artist: SieloArtist

    @State private var details: ArtistDetails?
    @State private var isLoading = true

    public init(artist: SieloArtist) {
        self.artist = artist
    }

    public var body: some View {
        let isFollowed = container.userManager.currentUser?.favoriteArtists.contains(where: {
            $0.caseInsensitiveCompare(artist.name) == .orderedSame
        }) ?? false

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Hero Header
                VStack(alignment: .leading, spacing: 10) {
                    Text(details?.name ?? artist.name)
                        .font(SieloTypography.displaySmall)
                        .foregroundColor(SieloColors.cream)

                    if let bio = details?.bio, !bio.isEmpty {
                        Text(bio)
                            .font(SieloTypography.bodyMedium)
                            .foregroundColor(SieloColors.textSecondary)
                            .lineLimit(4)
                    }

                    HStack(spacing: 12) {
                        Button {
                            let tracks = details?.topSongs ?? []
                            if !tracks.isEmpty {
                                container.playerManager.playArtistRadio(artistName: artist.name, tracks: tracks)
                            }
                        } label: {
                            Label("Play Radio", systemImage: "play.fill")
                                .font(SieloTypography.titleSmall)
                                .foregroundColor(SieloColors.obsidianBlack)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(SieloColors.sand)
                                .clipShape(Capsule())
                        }

                        Button {
                            container.userManager.toggleFollowArtist(artist.name)
                        } label: {
                            Text(isFollowed ? "Following" : "Follow")
                                .font(SieloTypography.titleSmall)
                                .foregroundColor(SieloColors.cream)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(SieloColors.oxfordBlue)
                                .clipShape(Capsule())
                        }
                    }
                }

                if isLoading {
                    ProgressView().tint(SieloColors.sand)
                } else if let songs = details?.topSongs, !songs.isEmpty {
                    Text("Popular Tracks")
                        .font(SieloTypography.headlineSmall)
                        .foregroundColor(SieloColors.cream)

                    ForEach(songs) { track in
                        Button {
                            container.playerManager.playArtistRadio(
                                artistName: artist.name,
                                tracks: songs,
                                startIndex: songs.firstIndex(where: { $0.id == track.id }) ?? 0
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(track.title).font(SieloTypography.titleSmall).foregroundColor(SieloColors.cream).lineLimit(1)
                                    Text(track.artist).font(SieloTypography.bodySmall).foregroundColor(SieloColors.textSecondary).lineLimit(1)
                                }
                                Spacer()
                                Text(track.formattedDuration).font(SieloTypography.labelSmall).foregroundColor(SieloColors.textMuted)
                            }
                            .padding(12)
                            .background(SieloColors.oxfordBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 160)
        }
        .background(SieloColors.obsidianBlack.ignoresSafeArea())
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            details = await MusicMetadataRepository.shared.getArtistDetails(artist.name)
            isLoading = false
        }
    }
}

// MARK: - Genre / Category Detail Screen

public struct GenreOrCategoryDetailScreen: View {
    @EnvironmentObject private var container: SieloContainer
    let title: String
    @State private var tracks: [SieloTrack] = []
    @State private var isLoading = true

    public init(title: String) { self.title = title }

    public var body: some View {
        List(tracks) { track in
            Button {
                container.playerManager.playTrack(track, queue: tracks)
            } label: {
                VStack(alignment: .leading) {
                    Text(track.title).foregroundColor(SieloColors.cream)
                    Text(track.artist).font(.caption).foregroundColor(SieloColors.textSecondary)
                }
            }
            .listRowBackground(SieloColors.oxfordBlue)
        }
        .scrollContentBackground(.hidden)
        .background(SieloColors.obsidianBlack.ignoresSafeArea())
        .navigationTitle(title)
        .overlay {
            if isLoading { ProgressView().tint(SieloColors.sand) }
        }
        .task {
            tracks = await InnerTubeClient.shared.search(query: "\(title) top hits").tracks
            isLoading = false
        }
    }
}

// MARK: - AuthDialogView & NewUserOnboardingScreen

public struct AuthDialogView: View {
    @ObservedObject var userManager: UserManager

    @State private var email = ""
    @State private var name = ""
    @State private var isRegister = false

    public init(userManager: UserManager) { self.userManager = userManager }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Welcome to Sielo")
                    .font(SieloFont.macondo(size: 36))
                    .foregroundColor(SieloColors.cream)

                Picker("Mode", selection: $isRegister) {
                    Text("Sign In").tag(false)
                    Text("Sign Up").tag(true)
                }
                .pickerStyle(.segmented)

                if isRegister {
                    TextField("Your Name", text: $name)
                        .padding(12).background(SieloColors.oxfordBlue).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                TextField("Email Address", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .padding(12).background(SieloColors.oxfordBlue).clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    Task { await userManager.signInWithEmail(name: name, email: email, isRegister: isRegister) }
                } label: {
                    Text(isRegister ? "Create Account" : "Sign In")
                        .font(SieloTypography.titleSmall)
                        .foregroundColor(SieloColors.obsidianBlack)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SieloColors.sand)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button("Continue as Guest") {
                    Task { await userManager.signInAsGuest() }
                }
                .foregroundColor(SieloColors.textSecondary)

                Spacer()
            }
            .padding(24)
            .background(SieloColors.obsidianBlack)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { userManager.isAuthDialogOpen = false }
                }
            }
        }
    }
}

public struct NewUserOnboardingScreen: View {
    @ObservedObject var userManager: UserManager

    @State private var selectedArtists: Set<String> = []
    @State private var selectedGenres: Set<String> = []

    private let seededArtists = [
        "Arijit Singh", "The Weeknd", "Diljit Dosanjh", "AP Dhillon", "Taylor Swift",
        "Drake", "Pritam", "Karan Aujla", "Anirudh Ravichander", "Billie Eilish",
        "Atif Aslam", "Shubh", "Coldplay", "A.R. Rahman", "Post Malone"
    ]
    private let genres = ["Bollywood", "Punjabi", "Pop", "Hip Hop", "Lo-Fi", "Indie", "R&B", "Rock", "EDM", "Acoustic"]

    public init(userManager: UserManager) { self.userManager = userManager }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Pick 5+ Artists You Love")
                        .font(SieloTypography.headlineMedium)
                        .foregroundColor(SieloColors.cream)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 10) {
                        ForEach(seededArtists, id: \.self) { artist in
                            let selected = selectedArtists.contains(artist)
                            Button {
                                if selected { selectedArtists.remove(artist) } else { selectedArtists.insert(artist) }
                            } label: {
                                Text(artist)
                                    .font(SieloTypography.labelMedium)
                                    .foregroundColor(selected ? SieloColors.obsidianBlack : SieloColors.cream)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(selected ? SieloColors.sand : SieloColors.oxfordBlue)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    Text("Pick Your Vibes")
                        .font(SieloTypography.headlineMedium)
                        .foregroundColor(SieloColors.cream)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 95))], spacing: 10) {
                        ForEach(genres, id: \.self) { genre in
                            let selected = selectedGenres.contains(genre)
                            Button {
                                if selected { selectedGenres.remove(genre) } else { selectedGenres.insert(genre) }
                            } label: {
                                Text(genre)
                                    .font(SieloTypography.labelMedium)
                                    .foregroundColor(selected ? SieloColors.obsidianBlack : SieloColors.cream)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(selected ? SieloColors.sageGreen : SieloColors.oxfordBlue)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    Button {
                        userManager.completeOnboarding(artists: Array(selectedArtists), genres: Array(selectedGenres))
                    } label: {
                        Text("Finish Setup")
                            .font(SieloTypography.titleSmall)
                            .foregroundColor(SieloColors.obsidianBlack)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedArtists.count >= 5 ? SieloColors.sand : SieloColors.slateBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(selectedArtists.count < 5)
                }
                .padding(20)
            }
            .background(SieloColors.obsidianBlack)
            .navigationTitle("Personalize Sielo")
        }
    }
}
