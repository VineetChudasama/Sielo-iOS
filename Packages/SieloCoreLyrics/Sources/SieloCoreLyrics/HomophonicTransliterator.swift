import Foundation

/// Mirrors core-lyrics/lrclib/HomophonicTransliterator.kt:
/// Detects non-Latin scripts (>25% non-Latin letters) and transliterates via CoreFoundation Any-Latin + Latin-ASCII.
public enum HomophonicTransliterator {
    public static func isNonLatin(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let nonLatinCount = letters.filter { $0.value > 0x024F }.count
        return Double(nonLatinCount) / Double(letters.count) > 0.25
    }

    public static func transliterate(_ text: String) -> String {
        guard isNonLatin(text) else { return text }
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return (mutable as String)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
