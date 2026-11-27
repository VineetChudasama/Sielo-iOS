import SwiftUI

/// 3-Phase Sielo launch reveal matching SieloLaunchReveal.kt:
/// Phase 1 (650ms): Fade/scale in -> Phase 2 (750ms): Hold -> Phase 3 (700ms): Zoom 4.2x on 'e' & fade out.
public struct SieloLaunchReveal: View {
    let onFinish: () -> Void

    @State private var brandAlpha: Double = 0.0
    @State private var brandScale: CGFloat = 0.86
    @State private var backdropAlpha: Double = 1.0
    @State private var finished = false

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        ZStack {
            SieloColors.obsidianBlack
                .opacity(backdropAlpha)
                .ignoresSafeArea()

            Text("Sielo")
                .font(SieloFont.macondo(size: 62))
                .foregroundColor(SieloColors.cream)
                .opacity(brandAlpha)
                .scaleEffect(brandScale, anchor: UnitPoint(x: 0.48, y: 0.52))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            completeReveal()
        }
        .task {
            // Phase 1: Entrance (650ms)
            withAnimation(.easeOut(duration: 0.65)) {
                brandAlpha = 1.0
                brandScale = 1.0
            }
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !finished else { return }

            // Phase 2: Hold (750ms)
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !finished else { return }

            // Phase 3: Zoom into 'e' + Fade (700ms)
            withAnimation(.easeIn(duration: 0.70)) {
                brandScale = 4.2
            }
            withAnimation(.easeOut(duration: 0.52)) {
                brandAlpha = 0.0
            }
            withAnimation(.easeOut(duration: 0.65)) {
                backdropAlpha = 0.0
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            completeReveal()
        }
    }

    private func completeReveal() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
