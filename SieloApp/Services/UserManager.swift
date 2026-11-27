import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import SieloCoreModels
import SieloCoreDatabase
import SieloCoreAudio

/// Mirrors app/core/auth/UserManager.kt:
/// Firebase Auth, Google/Email/Guest/Spotify profiles, Instagram-style @username validation,
/// taste weight learning, account switching, and full account deletion.
@MainActor
public final class UserManager: ObservableObject {
    @Published public private(set) var currentUser: UserProfile?
    @Published public var isAuthDialogOpen: Bool = false
    @Published public var isOnboardingOpen: Bool = false

    private let prefs = UserDefaults(suiteName: "sielo_auth_prefs") ?? .standard
    private let keyCurrentUser = "current_user_profile"
    private let keyAccountPrefix = "user_account_"

    private let databaseCleaner: DatabaseCleaner
    private let playerManager: PlayerManager
    private let cloudSyncManager: CloudSyncManager
    private let playlistsRepository: UserPlaylistsRepository
    private let firestore = Firestore.firestore()

    public init(
        databaseCleaner: DatabaseCleaner,
        playerManager: PlayerManager,
        cloudSyncManager: CloudSyncManager,
        playlistsRepository: UserPlaylistsRepository
    ) {
        self.databaseCleaner = databaseCleaner
        self.playerManager = playerManager
        self.cloudSyncManager = cloudSyncManager
        self.playlistsRepository = playlistsRepository

        if let data = prefs.data(forKey: keyCurrentUser),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.currentUser = decoded
        }

        cloudSyncManager.currentUserProvider = { [weak self] in self?.currentUser }
    }

    // MARK: - Auth Flows

    public func signInWithGoogle(name: String, email: String, photoUrl: String?, idToken: String?) async throws {
        if let idToken {
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: "")
            _ = try await Auth.auth().signIn(with: credential)
        }
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let existing = getUserByEmail(cleanEmail)
        let profile = existing ?? UserProfile(
            id: Auth.auth().currentUser?.uid ?? UUID().uuidString,
            name: name,
            email: cleanEmail,
            photoUrl: photoUrl,
            provider: .google,
            hasCompletedOnboarding: false,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        await switchToAccount(profile)
    }

    public func signInWithEmail(name: String, email: String, isRegister: Bool) async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !isRegister, let existing = getUserByEmail(cleanEmail) {
            await switchToAccount(existing)
            return
        }
        if Auth.auth().currentUser == nil {
            _ = try? await Auth.auth().signInAnonymously()
        }
        let profile = UserProfile(
            id: Auth.auth().currentUser?.uid ?? UUID().uuidString,
            name: name.isEmpty ? cleanEmail.components(separatedBy: "@").first ?? "Listener" : name,
            email: cleanEmail,
            provider: .emailPassword,
            hasCompletedOnboarding: false,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        await switchToAccount(profile)
    }

    public func signInAsGuest() async {
        let suffix = String(UUID().uuidString.prefix(6)).lowercased()
        let profile = UserProfile(
            id: "guest_\(suffix)",
            name: "Guest",
            email: "guest_\(suffix)@sielo.local",
            provider: .guest,
            hasCompletedOnboarding: true,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        await switchToAccount(profile)
    }

    private func switchToAccount(_ profile: UserProfile) async {
        if currentUser?.email.lowercased() != profile.email.lowercased() {
            try? await databaseCleaner.clearAll()
            playlistsRepository.resetToDefault()
        }
        saveUser(profile)
        isAuthDialogOpen = false
        if !profile.hasCompletedOnboarding {
            isOnboardingOpen = true
        }
        await cloudSyncManager.restoreUserData(profile: profile)
    }

    public func signOut() async {
        try? Auth.auth().signOut()
        try? await databaseCleaner.clearAll()
        playlistsRepository.resetToDefault()
        playerManager.resetPlayer()
        prefs.removeObject(forKey: keyCurrentUser)
        currentUser = nil
        isAuthDialogOpen = true
    }

    public func deleteAccount() async {
        if let user = currentUser {
            if let handle = user.username {
                try? await firestore.collection("sielo_usernames").document(handle).delete()
            }
            try? await firestore.collection("sielo_users").document(user.id).delete()
            prefs.removeObject(forKey: "\(keyAccountPrefix)\(user.email.lowercased())")
        }
        try? await Auth.auth().currentUser?.delete()
        await signOut()
    }

    // MARK: - Username Validation & Claim

    public func sanitizeUsername(_ raw: String) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
        return String(lower.unicodeScalars.filter {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "_"
        })
    }

    public func checkUsernameAvailability(_ raw: String) async -> (available: Bool, message: String) {
        let clean = sanitizeUsername(raw)
        if clean.count < 3 { return (false, "Username must be at least 3 characters") }
        if clean.count > 30 { return (false, "Username cannot exceed 30 characters") }
        if clean.hasPrefix(".") || clean.hasSuffix(".") { return (false, "Username cannot start or end with a dot") }
        if clean.contains("..") { return (false, "Username cannot have consecutive dots") }

        if let current = currentUser?.username, sanitizeUsername(current) == clean {
            return (true, "Your current username")
        }

        let doc = try? await firestore.collection("sielo_usernames").document(clean).getDocument()
        if doc?.exists == true {
            return (false, "Username is already taken")
        }
        return (true, "@\(clean) is available")
    }

    public func claimUsername(_ raw: String) async -> Bool {
        let clean = sanitizeUsername(raw)
        let (ok, _) = await checkUsernameAvailability(clean)
        guard ok, var user = currentUser else { return false }
        if let old = user.username, old != clean {
            try? await firestore.collection("sielo_usernames").document(old).delete()
        }
        try? await firestore.collection("sielo_usernames").document(clean).setData([
            "uid": user.id,
            "email": user.email,
            "updatedAt": Int64(Date().timeIntervalSince1970 * 1000)
        ])
        user.username = clean
        saveUser(user)
        await cloudSyncManager.backupAll(profile: user)
        return true
    }

    // MARK: - Taste Learning

    public func completeOnboarding(artists: [String], genres: [String]) {
        guard var user = currentUser else { return }
        user.favoriteArtists = artists
        user.favoriteGenres = genres
        for artist in artists {
            user.artistTasteWeights[artist, default: 0] += 10
        }
        for genre in genres {
            user.genreTasteWeights[genre, default: 0] += 10
        }
        user.hasCompletedOnboarding = true
        saveUser(user)
        isOnboardingOpen = false
        Task { await cloudSyncManager.backupAll(profile: user) }
    }

    public func recordSongPlayed(artist: String, genre: String) {
        guard var user = currentUser else { return }
        if !artist.isEmpty {
            user.artistTasteWeights[artist, default: 0] += 3
        }
        if !genre.isEmpty {
            user.genreTasteWeights[genre, default: 0] += 2
        }
        saveUser(user)
    }

    public func toggleFollowArtist(_ artistName: String) {
        guard var user = currentUser else { return }
        if let idx = user.favoriteArtists.firstIndex(where: { $0.caseInsensitiveCompare(artistName) == .orderedSame }) {
            user.favoriteArtists.remove(at: idx)
        } else {
            user.favoriteArtists.append(artistName)
            user.artistTasteWeights[artistName, default: 0] += 15
        }
        saveUser(user)
        Task { await cloudSyncManager.backupAll(profile: user) }
    }

    public func getTopTasteArtists() -> [String] {
        guard let user = currentUser else { return [] }
        return user.artistTasteWeights.sorted { $0.value > $1.value }.map(\.key)
    }

    private func getUserByEmail(_ email: String) -> UserProfile? {
        guard let data = prefs.data(forKey: "\(keyAccountPrefix)\(email.lowercased())") else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    public func saveUser(_ profile: UserProfile) {
        currentUser = profile
        if let data = try? JSONEncoder().encode(profile) {
            prefs.set(data, forKey: keyCurrentUser)
            prefs.set(data, forKey: "\(keyAccountPrefix)\(profile.email.lowercased())")
        }
    }
}
