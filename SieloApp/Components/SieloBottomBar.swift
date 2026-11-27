import SwiftUI

/// Floating curved-notch bottom bar matching SieloBottomBar.kt
public struct SieloBottomBar: View {
    @Binding var selectedTab: SieloTab
    let onTabSelected: (SieloTab) -> Void

    public init(selectedTab: Binding<SieloTab>, onTabSelected: @escaping (SieloTab) -> Void) {
        self._selectedTab = selectedTab
        self.onTabSelected = onTabSelected
    }

    public var body: some View {
        let tabs = SieloTab.allCases
        let selectedIndex = CGFloat(selectedTab.rawValue)

        ZStack {
            // Outer SlateBlue glass border + OxfordBlue curved-notch pill
            GeometryReader { geo in
                let width = min(geo.size.width, 420)
                let height: CGFloat = 62
                let itemWidth = width / CGFloat(tabs.count)
                let centerX = (selectedIndex + 0.5) * itemWidth
                let effectStrength = effectStrengthFor(index: selectedTab.rawValue)

                ZStack {
                    RoundedRectangle(cornerRadius: 24 + 10 * effectStrength, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    SieloColors.slateBlue.opacity(0.65),
                                    SieloColors.oxfordBlue.opacity(0.95)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: width, height: height)

                    RoundedRectangle(cornerRadius: 23 + 9 * effectStrength, style: .continuous)
                        .fill(SieloColors.oxfordBlue.opacity(0.96))
                        .frame(width: width - 2, height: height - 2)

                    // Active glass orb indicator
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    SieloColors.sand.opacity(0.32),
                                    SieloColors.slateBlue.opacity(0.18),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 2,
                                endRadius: 28
                            )
                        )
                        .frame(width: 48, height: 48)
                        .position(x: centerX, y: height / 2)
                        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: selectedTab)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 62)

            // Tab Buttons
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    let isSelected = (tab == selectedTab)
                    Button {
                        onTabSelected(tab)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: isSelected ? tab.selectedSystemImage : tab.unselectedSystemImage)
                                .font(.system(size: tab == .echo ? 20 : 19, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(isSelected ? SieloColors.cream : SieloColors.sageGreen)
                                .scaleEffect(isSelected ? 1.1 : 1.0)
                                .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)

                            Text(tab.title)
                                .font(SieloFont.urbanist(size: 10, weight: isSelected ? .semibold : .medium))
                                .foregroundColor(isSelected ? SieloColors.cream : SieloColors.sageGreen.opacity(0.85))
                        }
                        .frame(maxWidth: .infinity, maxHeight: 62)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 420)
        }
        .frame(height: 76)
        .padding(.horizontal, 14)
        .shadow(color: Color.black.opacity(0.45), radius: 16, x: 0, y: 8)
    }

    private func effectStrengthFor(index: Int) -> CGFloat {
        switch index {
        case 2: return 1.0
        case 1, 3: return 0.65
        default: return 0.0
        }
    }
}
