import SwiftUI
import UIKit
import CoreImage

/// Tactile interactive Waveform Progress Bar matching WaveformProgressBar.kt.
public struct WaveformProgressBar: View {
    let currentMs: Int64
    let durationMs: Int64
    let isPlaying: Bool
    let accentColor: Color
    let onSeek: (Int64) -> Void

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    private let barCount = 42
    private let amplitudes: [CGFloat] = [
        0.35, 0.55, 0.72, 0.45, 0.88, 0.64, 0.92, 0.50, 0.40, 0.78,
        0.85, 0.58, 0.42, 0.95, 0.70, 0.48, 0.82, 0.62, 0.36, 0.74,
        0.90, 0.52, 0.68, 0.84, 0.44, 0.60, 0.94, 0.76, 0.46, 0.80,
        0.54, 0.70, 0.86, 0.40, 0.66, 0.90, 0.50, 0.75, 0.58, 0.42,
        0.65, 0.38
    ]

    public init(
        currentMs: Int64,
        durationMs: Int64,
        isPlaying: Bool,
        accentColor: Color = SieloColors.sand,
        onSeek: @escaping (Int64) -> Void
    ) {
        self.currentMs = currentMs
        self.durationMs = durationMs
        self.isPlaying = isPlaying
        self.accentColor = accentColor
        self.onSeek = onSeek
    }

    public var body: some View {
        let baseProgress = durationMs > 0 ? min(1.0, max(0.0, Double(currentMs) / Double(durationMs))) : 0.0
        let activeProgress = isDragging ? dragProgress : baseProgress

        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    let threshold = Double(index) / Double(barCount)
                    let isActive = threshold <= activeProgress
                    let heightFactor = amplitudes[index % amplitudes.count]
                    Capsule()
                        .fill(isActive ? accentColor : SieloColors.slateBlue.opacity(0.42))
                        .frame(height: max(5, geo.size.height * heightFactor))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        dragProgress = min(1.0, max(0.0, value.location.x / max(1, geo.size.width)))
                    }
                    .onEnded { value in
                        let finalProgress = min(1.0, max(0.0, value.location.x / max(1, geo.size.width)))
                        isDragging = false
                        if durationMs > 0 {
                            onSeek(Int64(finalProgress * Double(durationMs)))
                        }
                    }
            )
        }
        .frame(height: 36)
    }
}

/// Extracts a rich ambient glow color from an artwork URL using CoreImage CIAreaAverage.
@MainActor
public final class ArtworkGlowLoader: ObservableObject {
    @Published public private(set) var glowColor: Color = SieloColors.sand
    private var lastURL: String?

    public init() {}

    public func update(urlString: String?) {
        guard let urlString, urlString != lastURL, let url = URL(string: urlString) else {
            if urlString == nil { glowColor = SieloColors.sand }
            return
        }
        lastURL = urlString
        Task.detached(priority: .utility) {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let uiImage = UIImage(data: data),
                  let ciImage = CIImage(image: uiImage) else { return }

            let extent = ciImage.extent
            let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: CIVector(cgRect: extent)
            ])
            guard let output = filter?.outputImage else { return }
            var bitmap = [UInt8](repeating: 0, count: 4)
            let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
            context.render(output, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

            let color = Color(
                .sRGB,
                red: Double(bitmap[0]) / 255.0,
                green: Double(bitmap[1]) / 255.0,
                blue: Double(bitmap[2]) / 255.0,
                opacity: 1.0
            )
            await MainActor.run { [weak self] in
                self?.glowColor = color
            }
        }
    }
}
