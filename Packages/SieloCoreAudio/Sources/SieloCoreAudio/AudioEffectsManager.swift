import Foundation
import AVFoundation

/// Mirrors core-audio/AudioEffectsManager.kt using AVAudioUnitEQ presets & bass shelf.
@MainActor
public final class AudioEffectsManager: ObservableObject {
    public static let shared = AudioEffectsManager()

    @Published public var isEqualizerEnabled: Bool = true
    @Published public var isBassBoostEnabled: Bool = true
    @Published public var bassStrength: Int = 800 // 0..1000
    @Published public var selectedPreset: String = "Normal"

    public let availablePresets: [String] = [
        "Normal", "Acoustic", "Bass Boost", "Classical", "Dance",
        "Electronic", "Hip Hop", "Jazz", "Pop", "Rock", "Vocal"
    ]

    public let eqUnit = AVAudioUnitEQ(numberOfBands: 10)
    private let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    private init() {
        for (idx, band) in eqUnit.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = frequencies[idx]
            band.bandwidth = 1.0
            band.bypass = false
            band.gain = 0
        }
        applyCurrentEffects()
    }

    public func setEqualizerEnabled(_ enabled: Bool) {
        isEqualizerEnabled = enabled
        applyCurrentEffects()
    }

    public func setBassBoostEnabled(_ enabled: Bool) {
        isBassBoostEnabled = enabled
        applyCurrentEffects()
    }

    public func setBassStrength(_ strength: Int) {
        bassStrength = min(1000, max(0, strength))
        applyCurrentEffects()
    }

    public func setEqualizerPreset(_ preset: String) {
        selectedPreset = preset
        applyCurrentEffects()
    }

    public func applyCurrentEffects() {
        eqUnit.bypass = !isEqualizerEnabled && !isBassBoostEnabled
        let baseGains = gainsForPreset(selectedPreset)
        let bassBoostDb: Float = isBassBoostEnabled ? (Float(bassStrength) / 1000.0) * 8.0 : 0.0

        for (idx, band) in eqUnit.bands.enumerated() {
            var gain = isEqualizerEnabled ? baseGains[idx] : 0.0
            if idx <= 1 {
                gain += bassBoostDb * (idx == 0 ? 1.0 : 0.65)
            }
            band.gain = min(12.0, max(-12.0, gain))
        }
    }

    private func gainsForPreset(_ preset: String) -> [Float] {
        switch preset {
        case "Acoustic":   return [2, 2, 1, 0, 1, 1, 2, 3, 2, 1]
        case "Bass Boost": return [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]
        case "Classical":  return [3, 2, 1, 0, -1, -1, 0, 2, 3, 3]
        case "Dance":      return [4, 5, 3, 0, 1, 2, 3, 2, 2, 1]
        case "Electronic": return [4, 4, 2, 0, -1, 1, 2, 3, 4, 4]
        case "Hip Hop":    return [5, 4, 3, 1, -1, -1, 1, 2, 2, 3]
        case "Jazz":       return [2, 2, 1, 2, -1, -1, 0, 1, 2, 2]
        case "Pop":        return [-1, 1, 3, 3, 2, 0, -1, -1, 1, 2]
        case "Rock":       return [4, 3, 2, 1, -1, -1, 1, 2, 3, 3]
        case "Vocal":      return [-2, -1, 0, 2, 4, 4, 3, 2, 1, 0]
        default:           return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        }
    }
}
