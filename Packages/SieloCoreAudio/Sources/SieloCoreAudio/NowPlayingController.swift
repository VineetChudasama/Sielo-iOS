import Foundation
import MediaPlayer
import UIKit
import SieloCoreModels

/// Bridges Sielo PlayerManager to iOS Lock Screen & Control Center (replaces MediaSessionService notification).
@MainActor
public final class NowPlayingController {
    public var onPlay: (() -> Void)?
    public var onPause: (() -> Void)?
    public var onTogglePlayPause: (() -> Void)?
    public var onNext: (() -> Void)?
    public var onPrevious: (() -> Void)?
    public var onSeek: ((Int64) -> Void)?
    public var onToggleFavorite: (() -> Void)?
    public var onToggleLoop: (() -> Void)?

    private var cachedArtworkTrackId: String?
    private var cachedArtwork: MPMediaItemArtwork?

    public init() {
        setupRemoteCommands()
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPlay?() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPause?() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onTogglePlayPause?() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onNext?() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPrevious?() }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let ms = Int64(posEvent.positionTime * 1000)
            Task { @MainActor in self?.onSeek?(ms) }
            return .success
        }

        center.likeCommand.isEnabled = true
        center.likeCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onToggleFavorite?() }
            return .success
        }

        center.changeRepeatModeCommand.isEnabled = true
        center.changeRepeatModeCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onToggleLoop?() }
            return .success
        }
    }

    public func updateNowPlaying(state: PlaybackState, isFavorite: Bool, playbackSpeed: Float) {
        guard let track = state.currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album ?? "",
            MPMediaItemPropertyPlaybackDuration: Double(state.durationMs) / 1000.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(state.currentPositionMs) / 1000.0,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? Double(playbackSpeed) : 0.0
        ]

        if let artwork = cachedArtwork, cachedArtworkTrackId == track.id {
            info[MPMediaItemPropertyArtwork] = artwork
        } else if let thumb = track.thumbnailUrl, let url = URL(string: thumb) {
            loadArtwork(for: track.id, url: url)
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPRemoteCommandCenter.shared().likeCommand.isActive = isFavorite
        MPRemoteCommandCenter.shared().changeRepeatModeCommand.currentRepeatType = state.isLooping ? .one : .off
    }

    private func loadArtwork(for trackId: String, url: URL) {
        cachedArtworkTrackId = trackId
        Task.detached(priority: .utility) { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run { [weak self] in
                guard let self, self.cachedArtworkTrackId == trackId else { return }
                self.cachedArtwork = artwork
                var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                current[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = current
            }
        }
    }
}
