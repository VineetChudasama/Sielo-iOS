import Foundation
import Combine
import SieloCoreAudio
import SieloCoreNetwork

/// Mirrors app/core/settings/SettingsRepository.kt with all 28 user preferences + cache & popup state.
@MainActor
public final class SettingsRepository: ObservableObject {
    private let prefs = UserDefaults(suiteName: "sielo_user_settings") ?? .standard

    // 1. Playback & Audio
    @Published public var streamQuality: String { didSet { prefs.set(streamQuality, forKey: "stream_quality"); applyStreamQuality() } }
    @Published public var downloadQuality: String { didSet { prefs.set(downloadQuality, forKey: "download_quality") } }
    @Published public var equalizerEnabled: Bool { didSet { prefs.set(equalizerEnabled, forKey: "equalizer_enabled"); AudioEffectsManager.shared.setEqualizerEnabled(equalizerEnabled) } }
    @Published public var bassBoostEnabled: Bool { didSet { prefs.set(bassBoostEnabled, forKey: "bass_boost_enabled"); AudioEffectsManager.shared.setBassBoostEnabled(bassBoostEnabled) } }
    @Published public var bassStrength: Int { didSet { prefs.set(bassStrength, forKey: "bass_strength"); AudioEffectsManager.shared.setBassStrength(bassStrength) } }
    @Published public var equalizerPreset: String { didSet { prefs.set(equalizerPreset, forKey: "equalizer_preset"); AudioEffectsManager.shared.setEqualizerPreset(equalizerPreset) } }
    @Published public var gaplessPlayback: Bool { didSet { prefs.set(gaplessPlayback, forKey: "gapless_playback") } }
    @Published public var crossfadeSeconds: Int { didSet { prefs.set(crossfadeSeconds, forKey: "crossfade_seconds") } }
    @Published public var playbackSpeed: Float { didSet { prefs.set(playbackSpeed, forKey: "playback_speed") } }
    @Published public var autoplayEnabled: Bool { didSet { prefs.set(autoplayEnabled, forKey: "autoplay_enabled") } }
    @Published public var rememberPosition: Bool { didSet { prefs.set(rememberPosition, forKey: "remember_position") } }

    // 2. Audio Output
    @Published public var pauseOnDisconnect: Bool { didSet { prefs.set(pauseOnDisconnect, forKey: "pause_on_disconnect") } }
    @Published public var bluetoothAutoResume: Bool { didSet { prefs.set(bluetoothAutoResume, forKey: "bluetooth_auto_resume") } }
    @Published public var volumeNormalization: Bool { didSet { prefs.set(volumeNormalization, forKey: "volume_normalization") } }

    // 3. Downloads & Playlist Sync
    @Published public var downloadWifiOnly: Bool { didSet { prefs.set(downloadWifiOnly, forKey: "download_wifi_only") } }
    @Published public var playlistAutoSyncEnabled: Bool { didSet { prefs.set(playlistAutoSyncEnabled, forKey: "playlist_auto_sync_enabled") } }
    @Published public var playlistAutoSyncIntervalHours: Int { didSet { prefs.set(playlistAutoSyncIntervalHours, forKey: "playlist_auto_sync_interval_hours") } }
    @Published public var playlistSyncWifiOnly: Bool { didSet { prefs.set(playlistSyncWifiOnly, forKey: "playlist_sync_wifi_only") } }

    // 4. Appearance
    @Published public var oledDarkTheme: Bool { didSet { prefs.set(oledDarkTheme, forKey: "oled_dark_theme") } }
    @Published public var dynamicArtworkTint: Bool { didSet { prefs.set(dynamicArtworkTint, forKey: "dynamic_artwork_tint") } }
    @Published public var highFpsVisuals: Bool { didSet { prefs.set(highFpsVisuals, forKey: "high_fps_visuals") } }

    // 5. Notifications
    @Published public var notificationsPlayback: Bool { didSet { prefs.set(notificationsPlayback, forKey: "notifications_playback") } }
    @Published public var notificationsListenTogether: Bool { didSet { prefs.set(notificationsListenTogether, forKey: "notifications_listen_together") } }

    // 6. Listen Together
    @Published public var allowRoomInvites: Bool { didSet { prefs.set(allowRoomInvites, forKey: "allow_room_invites") } }
    @Published public var autoRejoinSession: Bool { didSet { prefs.set(autoRejoinSession, forKey: "auto_rejoin_session") } }

    // 7. Privacy & Recommendations
    @Published public var privateListening: Bool { didSet { prefs.set(privateListening, forKey: "private_listening") } }
    @Published public var recommendationDiversity: String { didSet { prefs.set(recommendationDiversity, forKey: "recommendation_diversity") } }
    @Published public var prioritizeFollowedArtists: Bool { didSet { prefs.set(prioritizeFollowedArtists, forKey: "prioritize_followed_artists") } }

    @Published public var cacheSizeFormatted: String = "0 MB"

    public init() {
        self.streamQuality = prefs.string(forKey: "stream_quality") ?? "Master (320kbps Opus / FLAC)"
        self.downloadQuality = prefs.string(forKey: "download_quality") ?? "High (320kbps)"
        self.equalizerEnabled = prefs.object(forKey: "equalizer_enabled") as? Bool ?? true
        self.bassBoostEnabled = prefs.object(forKey: "bass_boost_enabled") as? Bool ?? true
        self.bassStrength = prefs.object(forKey: "bass_strength") as? Int ?? 800
        self.equalizerPreset = prefs.string(forKey: "equalizer_preset") ?? "Normal"
        self.gaplessPlayback = prefs.object(forKey: "gapless_playback") as? Bool ?? true
        self.crossfadeSeconds = prefs.object(forKey: "crossfade_seconds") as? Int ?? 4
        self.playbackSpeed = prefs.object(forKey: "playback_speed") as? Float ?? 1.0
        self.autoplayEnabled = prefs.object(forKey: "autoplay_enabled") as? Bool ?? true
        self.rememberPosition = prefs.object(forKey: "remember_position") as? Bool ?? true

        self.pauseOnDisconnect = prefs.object(forKey: "pause_on_disconnect") as? Bool ?? true
        self.bluetoothAutoResume = prefs.object(forKey: "bluetooth_auto_resume") as? Bool ?? false
        self.volumeNormalization = prefs.object(forKey: "volume_normalization") as? Bool ?? true

        self.downloadWifiOnly = prefs.object(forKey: "download_wifi_only") as? Bool ?? true
        self.playlistAutoSyncEnabled = prefs.object(forKey: "playlist_auto_sync_enabled") as? Bool ?? true
        self.playlistAutoSyncIntervalHours = prefs.object(forKey: "playlist_auto_sync_interval_hours") as? Int ?? 12
        self.playlistSyncWifiOnly = prefs.object(forKey: "playlist_sync_wifi_only") as? Bool ?? false

        self.oledDarkTheme = prefs.object(forKey: "oled_dark_theme") as? Bool ?? true
        self.dynamicArtworkTint = prefs.object(forKey: "dynamic_artwork_tint") as? Bool ?? true
        self.highFpsVisuals = prefs.object(forKey: "high_fps_visuals") as? Bool ?? true

        self.notificationsPlayback = prefs.object(forKey: "notifications_playback") as? Bool ?? true
        self.notificationsListenTogether = prefs.object(forKey: "notifications_listen_together") as? Bool ?? true

        self.allowRoomInvites = prefs.object(forKey: "allow_room_invites") as? Bool ?? true
        self.autoRejoinSession = prefs.object(forKey: "auto_rejoin_session") as? Bool ?? false

        self.privateListening = prefs.object(forKey: "private_listening") as? Bool ?? false
        self.recommendationDiversity = prefs.string(forKey: "recommendation_diversity") ?? "Balanced"
        self.prioritizeFollowedArtists = prefs.object(forKey: "prioritize_followed_artists") as? Bool ?? true

        applyStreamQuality()
        refreshCacheSize()
    }

    private func applyStreamQuality() {
        let suffix: String
        if streamQuality.contains("160") { suffix = "_160.mp4" }
        else if streamQuality.contains("96") { suffix = "_96.mp4" }
        else { suffix = "_320.mp4" }
        Task { await InnerTubeClient.shared.setPreferredBitrateSuffix(suffix) }
    }

    public func refreshCacheSize() {
        let bytes = OfflineCacheManager.shared.totalCacheSizeBytes()
        let mb = Double(bytes) / (1024.0 * 1024.0)
        cacheSizeFormatted = String(format: "%.1f MB", mb)
    }

    public func clearCache() {
        OfflineCacheManager.shared.clearCache()
        refreshCacheSize()
    }

    public func getSettingsMap() -> [String: Any] {
        [
            "streamQuality": streamQuality,
            "downloadQuality": downloadQuality,
            "equalizerEnabled": equalizerEnabled,
            "bassBoostEnabled": bassBoostEnabled,
            "bassStrength": bassStrength,
            "equalizerPreset": equalizerPreset,
            "gaplessPlayback": gaplessPlayback,
            "crossfadeSeconds": crossfadeSeconds,
            "playbackSpeed": Double(playbackSpeed),
            "autoplayEnabled": autoplayEnabled,
            "rememberPosition": rememberPosition,
            "pauseOnDisconnect": pauseOnDisconnect,
            "bluetoothAutoResume": bluetoothAutoResume,
            "volumeNormalization": volumeNormalization,
            "downloadWifiOnly": downloadWifiOnly,
            "oledDarkTheme": oledDarkTheme,
            "dynamicArtworkTint": dynamicArtworkTint,
            "highFpsVisuals": highFpsVisuals,
            "notificationsPlayback": notificationsPlayback,
            "notificationsListenTogether": notificationsListenTogether,
            "allowRoomInvites": allowRoomInvites,
            "autoRejoinSession": autoRejoinSession,
            "privateListening": privateListening,
            "recommendationDiversity": recommendationDiversity,
            "prioritizeFollowedArtists": prioritizeFollowedArtists
        ]
    }

    public func applySettingsMap(_ map: [String: Any]) {
        if let v = map["streamQuality"] as? String { streamQuality = v }
        if let v = map["downloadQuality"] as? String { downloadQuality = v }
        if let v = map["equalizerEnabled"] as? Bool { equalizerEnabled = v }
        if let v = map["bassBoostEnabled"] as? Bool { bassBoostEnabled = v }
        if let v = map["bassStrength"] as? Int { bassStrength = v }
        if let v = map["equalizerPreset"] as? String { equalizerPreset = v }
        if let v = map["gaplessPlayback"] as? Bool { gaplessPlayback = v }
        if let v = map["crossfadeSeconds"] as? Int { crossfadeSeconds = v }
        if let v = map["playbackSpeed"] as? Double { playbackSpeed = Float(v) }
        if let v = map["autoplayEnabled"] as? Bool { autoplayEnabled = v }
        if let v = map["rememberPosition"] as? Bool { rememberPosition = v }
        if let v = map["pauseOnDisconnect"] as? Bool { pauseOnDisconnect = v }
        if let v = map["bluetoothAutoResume"] as? Bool { bluetoothAutoResume = v }
        if let v = map["volumeNormalization"] as? Bool { volumeNormalization = v }
        if let v = map["downloadWifiOnly"] as? Bool { downloadWifiOnly = v }
        if let v = map["oledDarkTheme"] as? Bool { oledDarkTheme = v }
        if let v = map["dynamicArtworkTint"] as? Bool { dynamicArtworkTint = v }
        if let v = map["highFpsVisuals"] as? Bool { highFpsVisuals = v }
        if let v = map["notificationsPlayback"] as? Bool { notificationsPlayback = v }
        if let v = map["notificationsListenTogether"] as? Bool { notificationsListenTogether = v }
        if let v = map["allowRoomInvites"] as? Bool { allowRoomInvites = v }
        if let v = map["autoRejoinSession"] as? Bool { autoRejoinSession = v }
        if let v = map["privateListening"] as? Bool { privateListening = v }
        if let v = map["recommendationDiversity"] as? String { recommendationDiversity = v }
        if let v = map["prioritizeFollowedArtists"] as? Bool { prioritizeFollowedArtists = v }
    }

    // Feedback & What's New Popup tracking
    public func shouldShowFeedbackPopup() -> Bool {
        if prefs.bool(forKey: "never_show_feedback_popup") { return false }
        let lastShown = prefs.double(forKey: "last_feedback_popup_time")
        if lastShown == 0 { return true }
        return (Date().timeIntervalSince1970 - lastShown) >= 48 * 3600
    }

    public func recordFeedbackPopupShown(neverAgain: Bool) {
        prefs.set(Date().timeIntervalSince1970, forKey: "last_feedback_popup_time")
        if neverAgain { prefs.set(true, forKey: "never_show_feedback_popup") }
    }

    public func getLastSeenVersion() -> String {
        prefs.string(forKey: "last_seen_whats_new_version") ?? ""
    }

    public func markVersionSeen(_ version: String) {
        prefs.set(version, forKey: "last_seen_whats_new_version")
    }
}
