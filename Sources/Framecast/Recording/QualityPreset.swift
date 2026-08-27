import Foundation

enum QualityPreset: String, CaseIterable, Identifiable {
    case standard
    case high
    case maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .high: return "High"
        case .maximum: return "Maximum"
        }
    }

    var targetFPS: Int {
        switch self {
        case .standard: return 30
        case .high, .maximum: return 60
        }
    }

    var bitrateMultiplier: Double {
        switch self {
        case .standard: return 0.8
        case .high: return 1.0
        case .maximum: return 1.4
        }
    }
}
