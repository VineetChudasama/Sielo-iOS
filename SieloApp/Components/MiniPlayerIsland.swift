import SwiftUI
import SieloCoreModels

/// Floating Mini-Player Island matching MiniPlayerIsland.kt:
/// 116pt rotating vinyl record on the left + OxfordBlue pill with top progress bar & 5 thumb controls.
public struct MiniPlayerIsland: View {
    let playbackState: PlaybackState
    let onTogglePlay: () -> Void
    let onToggleMute: () -> Void
    let onSkipPrevious: () -> Void
    let onSkipNext: () -> Void
    let onToggleLoop: () -> Void
    let onTap: () -> Void

    @State private var vinylAngle: Double = 0

    public init(
        playbackState: PlaybackState,
        onTogglePlay: @escaping () -> Void,
        onToggleMute: @escaping () -> Void,
        onSkipPrevious: @escaping () -> Void,
        onSkipNext: @escaping () -> Void,
        onToggleLoop: @escaping () -> Void,
        onTap: @escaping () -> Void
    ) {
        self.playbackState = playbackState
        self.onTogglePlay = onTogglePlay
        self.onToggleMute = onToggleMute
        self.onSkipPrevious = onSkipPrevious
        self.onSkipNext = onSkipNext
        self.onToggleLoop = onToggleLoop
        self.onTap = onTap
    }

    public var body: some View {
        let progress: CGFloat = playbackState.durationMs > 0
            ? min(1, max(0, CGFloat(playbackState.currentPositionMs) / CGFloat(playbackState.durationMs)))
            : 0

        ZStack(alignment: .leading) {
            // Right Card Pill
            VStack(spacing: 0) {
                // Top 2.5pt Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(SieloColors.slateBlue.opacity(0.35))
                        Rectangle()
                            .fill(SieloColors.sand)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 2.5)

                HStack(spacing: 10) {
                    Spacer().frame(width: 68)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(playbackState.currentTrack?.title ?? "Not Playing")
                            .font(SieloFont.urbanist(size: 14, weight: .semibold))
                            .foregroundColor(SieloColors.cream)
                            .lineLimit(1)

                        Text(playbackState.currentTrack?.artist ?? "")
                            .font(SieloFont.urbanist(size: 12, weight: .regular))
                            .foregroundColor(SieloColors.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 5 Thumb Controls: Loop, Prev, Play/Pause, Next, Mute
                    HStack(spacing: 8) {
                        Button(action: onToggleLoop) {
                            Image(systemName: playbackState.isLooping ? "repeat.1" : "repeat")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(playbackState.isLooping ? SieloColors.sand : SieloColors.textSecondary)
                        }
                        .buttonStyle(.plain)

                        Button(action: onSkipPrevious) {
                            Image(systemName: "backward.end.fill")
                                .font(.system(size: 15))
                                .foregroundColor(SieloColors.cream)
                        }
                        .buttonStyle(.plain)

                        Button(action: onTogglePlay) {
                            ZStack {
                                Circle()
                                    .fill(SieloColors.sand)
                                    .frame(width: 34, height: 34)
                                if playbackState.isBuffering {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(SieloColors.obsidianBlack)
                                        .scaleEffect(0.75)
                                } else {
                                    Image(systemName: playbackState.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(SieloColors.obsidianBlack)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Button(action: onSkipNext) {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 15))
                                .foregroundColor(SieloColors.cream)
                        }
                        .buttonStyle(.plain)

                        Button(action: onToggleMute) {
                            Image(systemName: playbackState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 14))
                                .foregroundColor(playbackState.isMuted ? SieloColors.sand : SieloColors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 12)
                }
                .padding(.vertical, 10)
            }
            .background(SieloColors.oxfordBlue.opacity(0.97))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(SieloColors.borderGlass, lineWidth: 1)
            )
            .padding(.leading, 42)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            // Left Z-Index 2 Rotating Vinyl Disc
            ZStack {
                Circle()
                    .fill(SieloColors.obsidianBlack)
                    .frame(width: 82, height: 82)
                    .overlay(
                        Circle()
                            .stroke(SieloColors.slateBlue.opacity(0.6), lineWidth: 1.5)
                    )

                if let urlString = playbackState.currentTrack?.thumbnailUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            Circle().fill(SieloColors.surfaceElevated)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(SieloColors.surfaceElevated)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(SieloColors.sand)
                        )
                }

                // Spindle center hole
                Circle()
                    .fill(SieloColors.obsidianBlack)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(SieloColors.sand.opacity(0.7), lineWidth: 1.5))
            }
            .rotationEffect(.degrees(vinylAngle))
            .onTapGesture(perform: onTap)
            .task(id: playbackState.isPlaying) {
                guard playbackState.isPlaying else { return }
                while !Task.isCancelled && playbackState.isPlaying {
                    try? await Task.sleep(nanoseconds: 16_000_000)
                    vinylAngle = (vinylAngle + 0.72).truncatingRemainder(dividingBy: 360)
                }
            }
        }
        .padding(.horizontal, 14)
        .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 6)
    }
}
