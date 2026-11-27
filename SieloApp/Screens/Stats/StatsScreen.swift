import SwiftUI
import SieloCoreDatabase

/// Mirrors StatsScreen.kt + VibeRadarSection.kt:
/// Timeframe selector, Planetary Universe metrics, 5-axis interactive Pentagon Vibe Radar, Circadian Flow, and Top Artists/Tracks.
public struct StatsScreen: View {
    @EnvironmentObject private var container: SieloContainer

    @State private var timeframe: StatsTimeframe = .month1
    @State private var totalTimeMs: Int64 = 0
    @State private var uniqueSongs: Int = 0
    @State private var uniqueArtists: Int = 0
    @State private var streamCount: Int = 0
    @State private var topArtists: [ArtistStat] = []
    @State private var topSongs: [SongStat] = []
    @State private var streamHistory: [ListeningEventEntity] = []
    @State private var selectedMetricId: String? = nil

    public init() {}

    public var body: some View {
        let radar = VibeRadarCalculator.calculate(
            totalListeningTimeMs: totalTimeMs,
            totalUniqueSongs: uniqueSongs,
            totalUniqueArtists: uniqueArtists,
            totalStreamCount: streamCount,
            streamHistory: streamHistory,
            timeframe: timeframe
        )

        ScrollView {
            VStack(spacing: 20) {
                // Header & Timeframe Picker
                HStack {
                    Text("Listening Universe")
                        .font(SieloTypography.headlineLarge)
                        .foregroundColor(SieloColors.cream)
                    Spacer()
                    Menu {
                        ForEach(StatsTimeframe.allCases) { tf in
                            Button(tf.rawValue) { timeframe = tf }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(timeframe.rawValue)
                                .font(SieloTypography.labelLarge)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .foregroundColor(SieloColors.sand)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(SieloColors.oxfordBlue)
                        .clipShape(Capsule())
                    }
                }

                // 4 Planetary Stat Cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statCard(title: "Listening Time", value: formatDuration(totalTimeMs), icon: "clock.fill")
                    statCard(title: "Unique Tracks", value: "\(uniqueSongs)", icon: "music.note")
                    statCard(title: "Artists", value: "\(uniqueArtists)", icon: "person.2.fill")
                    statCard(title: "Total Plays", value: "\(streamCount)", icon: "play.circle.fill")
                }

                // Vibe Radar Pentagon Section
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Vibe Radar")
                            .font(SieloTypography.headlineMedium)
                            .foregroundColor(SieloColors.cream)
                        Spacer()
                        Text(radar.soundDnaSummary)
                            .font(SieloTypography.labelMedium)
                            .foregroundColor(SieloColors.sand)
                    }

                    VibeRadarPentagonView(metrics: radar.metricsList, selectedId: $selectedMetricId)
                        .frame(height: 240)

                    if let selId = selectedMetricId,
                       let metric = radar.metricsList.first(where: { $0.id == selId }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(metric.label): \(Int(metric.value))%")
                                .font(SieloTypography.titleSmall)
                                .foregroundColor(SieloColors.sand)
                            Text(metric.insightSummary)
                                .font(SieloTypography.bodySmall)
                                .foregroundColor(SieloColors.textSecondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SieloColors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(16)
                .background(SieloColors.oxfordBlue)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(SieloColors.borderGlass, lineWidth: 1))

                // Top Artists
                if !topArtists.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top Artists")
                            .font(SieloTypography.headlineSmall)
                            .foregroundColor(SieloColors.cream)
                        ForEach(Array(topArtists.enumerated()), id: \.offset) { idx, artist in
                            HStack {
                                Text("#\(idx + 1)")
                                    .font(SieloTypography.titleSmall)
                                    .foregroundColor(SieloColors.sand)
                                    .frame(width: 28, alignment: .leading)
                                Text(artist.artistName)
                                    .font(SieloTypography.bodyLarge)
                                    .foregroundColor(SieloColors.cream)
                                Spacer()
                                Text("\(artist.playCount) plays")
                                    .font(SieloTypography.labelMedium)
                                    .foregroundColor(SieloColors.textSecondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(16)
                    .background(SieloColors.oxfordBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }

                // Top Songs
                if !topSongs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("On Heavy Repeat")
                            .font(SieloTypography.headlineSmall)
                            .foregroundColor(SieloColors.cream)
                        ForEach(Array(topSongs.prefix(10).enumerated()), id: \.offset) { idx, song in
                            HStack {
                                Text("#\(idx + 1)")
                                    .font(SieloTypography.titleSmall)
                                    .foregroundColor(SieloColors.sand)
                                    .frame(width: 28, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.songTitle)
                                        .font(SieloTypography.bodyLarge)
                                        .foregroundColor(SieloColors.cream)
                                        .lineLimit(1)
                                    Text(song.artistName)
                                        .font(SieloTypography.bodySmall)
                                        .foregroundColor(SieloColors.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("\(song.playCount)x")
                                    .font(SieloTypography.labelMedium)
                                    .foregroundColor(SieloColors.sageGreen)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(16)
                    .background(SieloColors.oxfordBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 160)
        }
        .background(SieloColors.obsidianBlack.ignoresSafeArea())
        .task(id: timeframe) {
            await loadStats()
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(SieloColors.sand)
            Text(value)
                .font(SieloTypography.headlineMedium)
                .foregroundColor(SieloColors.cream)
            Text(title)
                .font(SieloTypography.labelMedium)
                .foregroundColor(SieloColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(SieloColors.oxfordBlue)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SieloColors.borderGlass, lineWidth: 1))
    }

    private func formatDuration(_ ms: Int64) -> String {
        let mins = ms / 60_000
        if mins >= 60 { return "\(mins / 60)h \(mins % 60)m" }
        return "\(mins)m"
    }

    private func loadStats() async {
        let sinceDate = Calendar.current.date(byAdding: .day, value: -timeframe.days, to: Date()) ?? Date()
        let sinceMs = Int64(sinceDate.timeIntervalSince1970 * 1000)
        let dao = container.database.listeningHistory

        async let artists = (try? await dao.getTopArtistsSnapshot(sinceMs: sinceMs, limit: 5)) ?? []
        async let songs = (try? await dao.getTopSongsSnapshot(sinceMs: sinceMs, limit: 10)) ?? []
        async let history = (try? await dao.getAllHistoryList(limit: 500)) ?? []

        let hist = (await history).filter { $0.timestampMs >= sinceMs && $0.durationPlayedMs >= 5000 }
        self.topArtists = await artists
        self.topSongs = await songs
        self.streamHistory = hist
        self.streamCount = hist.count
        self.totalTimeMs = hist.reduce(0) { $0 + $1.durationPlayedMs }
        self.uniqueSongs = Set(hist.map(\.songId)).count
        self.uniqueArtists = Set(hist.map(\.artistName)).count
    }
}

private struct VibeRadarPentagonView: View {
    let metrics: [VibeRadarMetric]
    @Binding var selectedId: String?

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) * 0.36

            ZStack {
                Canvas { context, _ in
                    // Concentric pentagons (25%, 50%, 75%, 100%)
                    for ring in [CGFloat(0.25), CGFloat(0.5), CGFloat(0.75), CGFloat(1.0)] {
                        var path = Path()
                        for i in 0..<5 {
                            let angle = (-90.0 + Double(i) * 72.0) * .pi / 180.0
                            let pt = CGPoint(
                                x: center.x + CGFloat(cos(angle)) * radius * ring,
                                y: center.y + CGFloat(sin(angle)) * radius * ring
                            )
                            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                        path.closeSubpath()
                        context.stroke(path, with: .color(SieloColors.slateBlue.opacity(0.45)), lineWidth: 1)
                    }

                    // Data polygon
                    var dataPath = Path()
                    for (i, m) in metrics.enumerated() {
                        let angle = (-90.0 + Double(i) * 72.0) * .pi / 180.0
                        let r = radius * CGFloat(max(Float(0.08), m.value / 100.0))
                        let pt = CGPoint(x: center.x + CGFloat(cos(angle)) * r, y: center.y + CGFloat(sin(angle)) * r)
                        if i == 0 { dataPath.move(to: pt) } else { dataPath.addLine(to: pt) }
                    }
                    dataPath.closeSubpath()
                    context.fill(dataPath, with: .color(SieloColors.sand.opacity(0.28)))
                    context.stroke(dataPath, with: .color(SieloColors.sand), lineWidth: 2)
                }

                // Tappable Labels
                ForEach(Array(metrics.enumerated()), id: \.element.id) { i, metric in
                    let angle = (-90.0 + Double(i) * 72.0) * .pi / 180.0
                    let labelR = radius + 24
                    let pt = CGPoint(x: center.x + CGFloat(cos(angle)) * labelR, y: center.y + CGFloat(sin(angle)) * labelR)
                    Button {
                        selectedId = (selectedId == metric.id) ? nil : metric.id
                    } label: {
                        Text(metric.label)
                            .font(SieloTypography.labelMedium)
                            .foregroundColor(selectedId == metric.id ? SieloColors.sand : SieloColors.cream)
                    }
                    .position(pt)
                }
            }
        }
    }
}
