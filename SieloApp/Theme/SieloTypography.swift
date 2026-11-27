import SwiftUI

/// Exact Sielo typography matching app/ui/theme/Type.kt (Sora, Urbanist, Macondo)
public enum SieloFont {
    public static func macondo(size: CGFloat) -> Font {
        .custom("Macondo-Regular", size: size)
    }

    public static func sora(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black:
            name = "Sora-Bold"
        case .semibold, .medium:
            name = "Sora-SemiBold"
        default:
            name = "Sora-Regular"
        }
        return .custom(name, size: size)
    }

    public static func urbanist(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black:
            name = "Urbanist-Bold"
        case .semibold:
            name = "Urbanist-SemiBold"
        case .medium:
            name = "Urbanist-Medium"
        default:
            name = "Urbanist-Regular"
        }
        return .custom(name, size: size)
    }
}

public enum SieloTypography {
    public static let displayLarge = SieloFont.sora(size: 36, weight: .bold)
    public static let displayMedium = SieloFont.sora(size: 30, weight: .semibold)
    public static let displaySmall = SieloFont.sora(size: 26, weight: .semibold)
    public static let headlineLarge = SieloFont.sora(size: 24, weight: .bold)
    public static let headlineMedium = SieloFont.sora(size: 20, weight: .semibold)
    public static let headlineSmall = SieloFont.sora(size: 18, weight: .semibold)

    public static let titleLarge = SieloFont.urbanist(size: 22, weight: .semibold)
    public static let titleMedium = SieloFont.urbanist(size: 17, weight: .semibold)
    public static let titleSmall = SieloFont.urbanist(size: 15, weight: .semibold)

    public static let bodyLarge = SieloFont.urbanist(size: 16, weight: .regular)
    public static let bodyMedium = SieloFont.urbanist(size: 14, weight: .regular)
    public static let bodySmall = SieloFont.urbanist(size: 12, weight: .regular)
    public static let labelLarge = SieloFont.urbanist(size: 14, weight: .medium)
    public static let labelMedium = SieloFont.urbanist(size: 12, weight: .medium)
    public static let labelSmall = SieloFont.urbanist(size: 11, weight: .medium)
}
