import SwiftUI
import SieloCoreModels
import SieloCoreAudio
import SieloCoreLyrics

/// Mirrors PlayerScreen.kt + QueueScreen.kt:
/// 3-page Horizontal Pager (Page 0 = Lyrics, Page 1 = Vinyl Now Playing, Page 2 = Queue)
/// with vertical drag-to-dismiss back gesture.
public struct PlayerScreen: View {
    @ObservedObject var playerManager: PlayerManager
    @Binding var dragOffset: CGFloat
    let onClose: () -> Void

    @State private var selectedPage: Int = 1
    @State private var lyrics: SieloLyrics?
    @State private var lyricOffsetMs: Int64 = 0
    @State private var showTransliterated: Bool = false
    @State private var vinylAngle: Double = 0
    @StateObject private var glowLoader = ArtworkGlowLoader()

    public init(playerManager: PlayerManager, dragOffset: Binding<CGFloat>, onClose: @escaping () -> Void) {
        self.playerManager = playerManager
        self._dragOffset = dragOffset
        self.onClose = onClose
    }

    public var body: some View {
        let state = playerManager.playbackState

        VStack(spacing: 0) {
            // Top Handle + Page Indicator + Close
            HStack {
                Button {
                    if selectedPage != 1 {
                        withAnimation { selectedPage = 1 }
                    } else {
                        onClose()
                    }
                } label: {
                    Image(systemName: selectedPage != 1 ? "chevron.left" : "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(SieloColors.cream)
                        .padding(10)
                }

                Spacer()

                // Page switcher pills
                HStack(spacing: 14) {
                    pagePill("Lyrics", index: 0)
                    pagePill("Player", index: 1)
                    pagePill("Queue", index: 2)
                }

                Spacer()

                Button {
                    Task { await playerManager.toggleCurrentTrackFavorite() }
                } label: {
                    Image(systemName: playerManager.isCurrentTrackFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18))
                        .foregroundColor(playerManager.isCurrentTrackFavorite ? SieloColors.sand : SieloColors.cream)
                        .padding(10)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            TabView(selection: $selectedPage) {
                lyricsPageView(state: state).tag(0)
                nowPlayingPageView(state: state).tag(1)
                queuePageView(state: state).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(
            ZStack {
                SieloColors.obsidianBlack
                RadialGradient(
                    colors: [glowLoader.glowColor.opacity(0.28), Color.clear],
                    center: .top,
                    startRadius: 20,
                    endRadius: 460
                )
            }
            .ignoresSafeArea()
        )
        .onChange(of: state.currentTrack?.thumbnailUrl) { newUrl in
            glowLoader.update(urlString: newUrl)
        }
        .onAppear {
            glowLoader.update(urlString: state.currentTrack?.thumbnailUrl)
        }
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 20 && abs(value.translation.height) > abs(value.translation.width) {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 140 || value.predictedEndTranslation.height > 260 {
                        onClose()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .task(id: state.currentTrack?.id) {
            guard let track = state.currentTrack else { lyrics = nil; return }
            lyrics = await LrcLibClient.shared.getLyrics(
                trackName: track.title,
                artistName: track.artist,
                durationSec: Int(track.durationSeconds)
            )
        }
    }

    private func pagePill(_ title: String, index: Int) -> some View {
        Button {
            withAnimation { selectedPage = index }
        } label: {
            Text(title)
                .font(SieloTypography.labelMedium)
                .foregroundColor(selectedPage == index ? SieloColors.obsidianBlack : SieloColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(selectedPage == index ? SieloColors.sand : Color.clear)
                .clipShape(Capsule())
        }
    }

    // MARK: - Page 1: Vinyl Now Playing

    private func nowPlayingPageView(state: PlaybackState) -> some View {
        VStack(spacing: 24) {
            Spacer()

            // Rotating Vinyl Disc
            ZStack {
                Circle()
                    .fill(SieloColors.oxfordBlue)
                    .frame(width: 270, height: 270)
                    .overlay(Circle().stroke(SieloColors.slateBlue.opacity(0.5), lineWidth: 2))

                if let urlStr = state.currentTrack?.thumbnailUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            Circle().fill(SieloColors.surfaceElevated)
                        }
                    }
                    .frame(width: 220, height: 220)
                    .clipShape(Circle())
                }

                Circle()
                    .fill(SieloColors.obsidianBlack)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(SieloColors.sand, lineWidth: 2))
            }
            .rotationEffect(.degrees(vinylAngle))
            .task(id: state.isPlaying) {
                guard state.isPlaying else { return }
                while !Task.isCancelled && state.isPlaying {
                    try? await Task.sleep(nanoseconds: 16_000_000)
                    vinylAngle = (vinylAngle + 0.5).truncatingRemainder(dividingBy: 360)
                }
            }

            // Track Info
            VStack(spacing: 6) {
                Text(state.currentTrack?.title ?? "Not Playing")
                    .font(SieloTypography.headlineMedium)
                    .foregroundColor(SieloColors.cream)
                    .lineLimit(1)
                Text(state.currentTrack?.artist ?? "")
                    .font(SieloTypography.bodyLarge)
                    .foregroundColor(SieloColors.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 24)

            // Waveform Scrubber
            VStack(spacing: 6) {
                WaveformProgressBar(
                    currentMs: state.currentPositionMs,
                    durationMs: state.durationMs,
                    isPlaying: state.isPlaying,
                    accentColor: glowLoader.glowColor,
                    onSeek: { playerManager.seekTo($0) }
                )

                HStack {
                    Text(formatMs(state.currentPositionMs))
                    Spacer()
                    Text(formatMs(state.durationMs))
                }
                .font(SieloTypography.labelSmall)
                .foregroundColor(SieloColors.textSecondary)
            }
            .padding(.horizontal, 28)

            // Controls: Shuffle, Prev, Play/Pause, Next, Loop
            HStack(spacing: 28) {
                Button { playerManager.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 18))
                        .foregroundColor(state.isShuffle ? SieloColors.sand : SieloColors.textSecondary)
                }
                Button { playerManager.skipPrevious() } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 26))
                        .foregroundColor(SieloColors.cream)
                }
                Button { playerManager.togglePlayPause() } label: {
                    ZStack {
                        Circle().fill(SieloColors.sand).frame(width: 68, height: 68)
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(SieloColors.obsidianBlack)
                    }
                }
                Button { playerManager.skipNext() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 26))
                        .foregroundColor(SieloColors.cream)
                }
                Button { playerManager.toggleLoop() } label: {
                    Image(systemName: state.isLooping ? "repeat.1" : "repeat")
                        .font(.system(size: 18))
                        .foregroundColor(state.isLooping ? SieloColors.sand : SieloColors.textSecondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Page 0: Synced Lyrics

    private func lyricsPageView(state: PlaybackState) -> some View {
        VStack(spacing: 12) {
            HStack {
                Button("-0.5s") { lyricOffsetMs -= 500 }
                Button("Reset") { lyricOffsetMs = 0 }
                Button("+0.5s") { lyricOffsetMs += 500 }
                Spacer()
                Button(showTransliterated ? "Original" : "Romanize") {
                    showTransliterated.toggle()
                }
            }
            .font(SieloTypography.labelMedium)
            .foregroundColor(SieloColors.sand)
            .padding(.horizontal, 20)

            if let lines = lyrics?.lines, !lines.isEmpty {
                let effectivePos = state.currentPositionMs + lyricOffsetMs
                let activeIdx = lines.lastIndex(where: { $0.timestampMs <= effectivePos }) ?? 0

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                            let text = showTransliterated ? HomophonicTransliterator.transliterate(line.text) : line.text
                            Button {
                                playerManager.seekTo(max(0, line.timestampMs - lyricOffsetMs))
                            } label: {
                                Text(text)
                                    .font(SieloFont.urbanist(size: idx == activeIdx ? 22 : 17, weight: idx == activeIdx ? .bold : .medium))
                                    .foregroundColor(idx == activeIdx ? SieloColors.cream : SieloColors.textSecondary.opacity(0.65))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(24)
                }
            } else if let plain = lyrics?.plainLyrics, !plain.isEmpty {
                ScrollView {
                    Text(showTransliterated ? HomophonicTransliterator.transliterate(plain) : plain)
                        .font(SieloTypography.bodyLarge)
                        .foregroundColor(SieloColors.cream)
                        .padding(24)
                }
            } else {
                Spacer()
                Text("No lyrics available for this track.")
                    .font(SieloTypography.bodyMedium)
                    .foregroundColor(SieloColors.textSecondary)
                Spacer()
            }
        }
    }

    // MARK: - Page 2: Queue

    private func queuePageView(state: PlaybackState) -> some View {
        let upcomingStart = min(state.queue.count, max(0, state.queueIndex + 1))
        let upcoming = Array(state.queue[upcomingStart...])

        return List {
            if let cur = state.currentTrack {
                Section("NOW PLAYING") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(cur.title).font(SieloTypography.titleSmall).foregroundColor(SieloColors.sand)
                            Text(cur.artist).font(SieloTypography.bodySmall).foregroundColor(SieloColors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "waveform").foregroundColor(SieloColors.sand)
                    }
                    .listRowBackground(SieloColors.oxfordBlue)
                }
            }

            Section("UP NEXT (\(upcoming.count))") {
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { offset, track in
                    Button {
                        playerManager.playTrack(track, queue: state.queue, resetScope: false)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(track.title).font(SieloTypography.bodyLarge).foregroundColor(SieloColors.cream)
                            Text(track.artist).font(SieloTypography.bodySmall).foregroundColor(SieloColors.textSecondary)
                        }
                    }
                    .listRowBackground(SieloColors.oxfordBlue)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            playerManager.removeTrackFromQueue(at: upcomingStart + offset)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                .onMove { from, to in
                    if let first = from.first {
                        playerManager.reorderUpcomingTracks(fromOffset: first, toOffset: to)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(SieloColors.obsidianBlack)
    }

    private func formatMs(_ ms: Int64) -> String {
        let totalSec = max(0, ms / 1000)
        return String(format: "%d:%02d", totalSec / 60, totalSec % 60)
    }
}
