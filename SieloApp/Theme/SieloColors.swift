import SwiftUI

/// Exact Sielo color palette matching app/ui/theme/Color.kt
public enum SieloColors {
    // Core Palette
    public static let darkNavy = Color(hex: 0x0D1B2A)       // #0D1B2A - Deep Navy Canvas / Background
    public static let oxfordBlue = Color(hex: 0x1B263B)     // #1B263B - Dark Slate Surface / Cards
    public static let slateBlue = Color(hex: 0x415A77)      // #415A77 - Slate Blue Borders / Muted Accents
    public static let sageGreen = Color(hex: 0x778D7A)      // #778D7A - Sage Green / Secondary Accent
    public static let sand = Color(hex: 0xD4C4A8)           // #D4C4A8 - Warm Sand / Primary Accent & Play Buttons
    public static let cream = Color(hex: 0xF4F1DE)          // #F4F1DE - Eggshell Cream / Primary Typography

    // Semantic UI Mappings
    public static let obsidianBlack = darkNavy
    public static let backgroundDark = darkNavy
    public static let surfaceDark = oxfordBlue
    public static let surfaceElevated = Color(hex: 0x22304A)
    public static let surfaceGlass = Color(hex: 0x1B263B, opacity: 0.92)
    public static let borderGlass = Color(hex: 0x415A77, opacity: 0.24)
    public static let borderSubtle = slateBlue.opacity(0.5)
    public static let borderHighlight = sand.opacity(0.4)

    // Accents
    public static let accentCoral = sand
    public static let accentPeach = sageGreen
    public static let accentRose = sand
    public static let electricCyan = sand
    public static let laserAmber = sageGreen
    public static let neonPurple = slateBlue
    public static let neonPink = sageGreen
    public static let emeraldGlow = sageGreen

    // Typography & State
    public static let textPrimary = cream
    public static let textSecondary = Color(hex: 0xB0BDC9)
    public static let textMuted = slateBlue
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
