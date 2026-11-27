import Foundation
import Combine
import SieloCoreModels
import SieloCoreDatabase
import SieloCoreNetwork
import SieloCoreAudio
import SieloCoreRecommendations

/// Central dependency container wiring all Sielo iOS modules together.
@MainActor
public final class SieloContainer: ObservableObject {
    public let database: SieloDatabase
    public let databaseCleaner: DatabaseCleaner
    public let playerManager: PlayerManager
    public let settingsRepository: SettingsRepository
    public let playlistsRepository: UserPlaylistsRepository
    public let cloudSyncManager: CloudSyncManager
    public let userManager: UserManager
    public let listenTogetherManager: ListenTogetherManager
    public let autoplayEngine: AutoplayQueueEngine
    public let eventDispatcher: ListeningEventDispatcher

    public init() {
        let db = (try? SieloDatabase.openDefault()) ?? (try! SieloDatabase.openInMemory())
        self.database = db
        self.databaseCleaner = DatabaseCleaner(database: db)

        let player = PlayerManager(database: db)
        let settings = SettingsRepository()
        let playlists = UserPlaylistsRepository()
        let sync = CloudSyncManager(
            database: db,
            playlistsRepository: playlists,
            settingsRepository: settings,
            playerManager: player
        )
        let userMgr = UserManager(
            databaseCleaner: DatabaseCleaner(database: db),
            playerManager: player,
            cloudSyncManager: sync,
            playlistsRepository: playlists
        )
        let listenMgr = ListenTogetherManager(playerManager: player)
        let autoplay = AutoplayQueueEngine(database: db)
        let dispatcher = ListeningEventDispatcher()

        self.playerManager = player
        self.settingsRepository = settings
        self.playlistsRepository = playlists
        self.cloudSyncManager = sync
        self.userManager = userMgr
        self.listenTogetherManager = listenMgr
        self.autoplayEngine = autoplay
        self.eventDispatcher = dispatcher

        // Wire cross-module hooks
        player.onTrackPlayedTasteListener = { [weak userMgr] artist, genre in
            userMgr?.recordSongPlayed(artist: artist, genre: genre)
        }
        player.userTasteSeedsProvider = { [weak userMgr] in
            guard let userMgr else { return [] }
            return userMgr.getTopTasteArtists() + (userMgr.currentUser?.favoriteArtists ?? [])
        }
        player.autoplayReplenisher = { [weak autoplay, weak userMgr] seed, excluded in
            let userId = userMgr?.currentUser?.id
            return await autoplay?.generateBatch(seedSong: seed, userId: userId, excludedSongIds: excluded) ?? []
        }
        player.onListeningEvent = { [weak dispatcher, weak userMgr] type, track, posMs, durMs in
            let uid = userMgr?.currentUser?.id ?? "guest"
            let event = ClientListeningEvent(
                userId: uid,
                trackId: track.id,
                eventType: type,
                playbackPositionMs: posMs,
                durationMs: durMs,
                trackTitle: track.title,
                trackArtist: track.artist,
                trackAlbum: track.album
            )
            Task { await dispatcher?.dispatch(event) }
        }

        Task {
            await dispatcher.setPrivateListening(settings.privateListening)
            await dispatcher.start()
        }
    }
}
