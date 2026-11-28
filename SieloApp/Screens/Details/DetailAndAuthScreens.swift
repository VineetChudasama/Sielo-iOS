import SwiftUI
import UIKit
import FirebaseCore
import GoogleSignIn
import SieloCoreModels
import SieloCoreNetwork

// MARK: - ArtistProfileScreen (mirrors ArtistProfileScreen.kt)

public struct ArtistProfileScreen: View {
    @EnvironmentObject private var container: SieloContainer
    let artist: SieloArtist

    @State private var details: ArtistDetails?
    @State private var isLoading = true
    @State private var selectedTab = 0 // 0: Music, 1: About, 2: Similar Artists
    @State private var selectedActionTrack: SieloTrack?
    @State private var isBioExpanded = false

    public init(artist: SieloArtist) {
        self.artist = artist
    }

    public var body: some View {
        let isFollowed = container.userManager.currentUser?.favoriteArtists.contains(where: {
            $0.caseInsensitiveCompare(artist.name) == .orderedSame
        }) ?? false

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero Portrait + Gradient Scrim + Verified Badge
                ZStack(alignment: .bottomLeading) {
                    let heroUrl = (details?.heroImageUrl ?? details?.imageUrl ?? artist.imageUrl).flatMap(URL.init)
                    Group {
                        if let heroUrl {
                            AsyncImage(url: heroUrl) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFill()
                                } else {
                                    SieloColors.oxfordBlue
                                }
                            }
                        } else {
                            SieloColors.oxfordBlue
                        }
                    }
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    LinearGradient(
                        colors: [Color.clear, SieloColors.obsidianBlack.opacity(0.65), SieloColors.obsidianBlack],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 260)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(SieloColors.sand)
                                .font(.caption)
                            Text("VERIFIED ARTIST")
                                .font(SieloTypography.labelSmall)
                                .foregroundColor(SieloColors.sand)
                        }
                        Text(details?.name ?? artist.name)
                            .font(SieloTypography.displayMedium)
                            .foregroundColor(SieloColors.cream)
                    }
                    .padding(16)
                }

                // Primary Action Pills
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
                            .overlay(Capsule().stroke(SieloColors.borderGlass, lineWidth: 1))
                    }

                    if let shareURL = artistShareURL() {
                        ShareLink(item: shareURL) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(SieloColors.cream)
                                .padding(10)
                                .background(SieloColors.oxfordBlue)
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 16)

                // Segmented Tabs (Music / About / Similar)
                Picker("Artist Section", selection: $selectedTab) {
                    Text("Music").tag(0)
                    Text("About").tag(1)
                    Text("Similar").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView().tint(SieloColors.sand)
                        Spacer()
                    }
                    .padding(.top, 24)
                } else {
                    switch selectedTab {
                    case 0:
                        musicTabContent
                    case 1:
                        aboutTabContent
                    default:
                        similarTabContent
                    }
                }
            }
            .padding(.bottom, 160)
        }
        .background(SieloColors.obsidianBlack.ignoresSafeArea())
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedActionTrack) { track in
            SongActionsSheet(track: track) { _ in }
        }
        .task(id: artist.name) {
            isLoading = true
            details = await MusicMetadataRepository.shared.getArtistDetails(artist.name)
            isLoading = false
        }
    }

    @ViewBuilder
    private var musicTabContent: some View {
        let songs = details?.topSongs ?? []
        if songs.isEmpty {
            Text("No tracks found for this artist.")
                .font(SieloTypography.bodyMedium)
                .foregroundColor(SieloColors.textSecondary)
                .padding(.horizontal, 16)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Popular Tracks")
                    .font(SieloTypography.headlineSmall)
                    .foregroundColor(SieloColors.cream)
                    .padding(.horizontal, 16)

                ForEach(songs) { track in
                    Button {
                        container.playerManager.playArtistRadio(
                            artistName: artist.name,
                            tracks: songs,
                            startIndex: songs.firstIndex(where: { $0.id == track.id }) ?? 0
                        )
                    } label: {
                        HStack(spacing: 12) {
                            TrackArtworkView(title: track.title, artist: track.artist, urlString: track.thumbnailUrl, size: 50, cornerRadius: 10)
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
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var aboutTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let bio = details?.bio, !bio.isEmpty {
                Text(bio)
                    .font(SieloTypography.bodyMedium)
                    .foregroundColor(SieloColors.textSecondary)
                    .lineLimit(isBioExpanded ? nil : 6)
                    .onTapGesture { isBioExpanded.toggle() }
            } else {
                Text("No biography available yet.")
                    .font(SieloTypography.bodyMedium)
                    .foregroundColor(SieloColors.textSecondary)
            }

            if let origin = details?.origin, !origin.isEmpty {
                HStack {
                    Text("Origin:").foregroundColor(SieloColors.textMuted)
                    Text(origin).foregroundColor(SieloColors.cream)
                }
                .font(SieloTypography.bodySmall)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SieloColors.oxfordBlue)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var similarTabContent: some View {
        let sim = details?.similarArtists ?? []
        if sim.isEmpty {
            Text("No similar artists available.")
                .font(SieloTypography.bodyMedium)
                .foregroundColor(SieloColors.textSecondary)
                .padding(.horizontal, 16)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(sim) { item in
                    VStack(spacing: 6) {
                        ArtistAvatarView(name: item.name, imageUrl: item.imageUrl, size: 78)
                        Text(item.name)
                            .font(SieloTypography.labelMedium)
                            .foregroundColor(SieloColors.cream)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func artistShareURL() -> URL? {
        var comps = URLComponents(string: "https://sielo.site/artist")
        comps?.queryItems = [URLQueryItem(name: "name", value: artist.name)]
        return comps?.url
    }
}

// MARK: - Genre / Category Detail Screen

public struct GenreOrCategoryDetailScreen: View {
    @EnvironmentObject private var container: SieloContainer
    let title: String
    @State private var tracks: [SieloTrack] = []
    @State private var isLoading = true
    @State private var selectedActionTrack: SieloTrack?

    public init(title: String) { self.title = title }

    public var body: some View {
        List(tracks) { track in
            Button {
                container.playerManager.playTrack(track, queue: tracks)
            } label: {
                HStack(spacing: 12) {
                    TrackArtworkView(title: track.title, artist: track.artist, urlString: track.thumbnailUrl, size: 48, cornerRadius: 10)
                    VStack(alignment: .leading) {
                        Text(track.title).font(SieloTypography.titleSmall).foregroundColor(SieloColors.cream).lineLimit(1)
                        Text(track.artist).font(SieloTypography.bodySmall).foregroundColor(SieloColors.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Button { selectedActionTrack = track } label: {
                        Image(systemName: "ellipsis").foregroundColor(SieloColors.textSecondary).padding(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(SieloColors.oxfordBlue)
        }
        .scrollContentBackground(.hidden)
        .background(SieloColors.obsidianBlack.ignoresSafeArea())
        .navigationTitle(title)
        .sheet(item: $selectedActionTrack) { track in
            SongActionsSheet(track: track) { _ in }
        }
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
    @State private var googleAlertMessage: String?

    public init(userManager: UserManager) { self.userManager = userManager }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Welcome to Sielo")
                    .font(SieloFont.macondo(size: 36))
                    .foregroundColor(SieloColors.cream)

                // Google OAuth Sign-In
                Button {
                    startGoogleSignIn()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "g.circle.fill")
                            .font(.title3)
                        Text("Continue with Google")
                            .font(SieloTypography.titleSmall)
                    }
                    .foregroundColor(SieloColors.obsidianBlack)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(SieloColors.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Divider().overlay(SieloColors.slateBlue)

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
            .alert("Google Sign-In Setup", isPresented: Binding(
                get: { googleAlertMessage != nil },
                set: { if !$0 { googleAlertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(googleAlertMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { userManager.isAuthDialogOpen = false }
                }
            }
        }
    }

    private func startGoogleSignIn() {
        guard FirebaseApp.app() != nil,
              let clientID = FirebaseApp.app()?.options.clientID else {
            googleAlertMessage = "Add GoogleService-Info.plist from your Firebase Console to SieloApp/Resources/ to enable Google Sign-In & Cloud Sync."
            return
        }
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error {
                googleAlertMessage = error.localizedDescription
                return
            }
            guard let user = result?.user,
                  let email = user.profile?.email else { return }
            let name = user.profile?.name ?? "Sielo Listener"
            let photo = user.profile?.imageURL(withDimension: 300)?.absoluteString
            let idToken = user.idToken?.tokenString
            Task {
                try? await userManager.signInWithGoogle(name: name, email: email, photoUrl: photo, idToken: idToken)
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
