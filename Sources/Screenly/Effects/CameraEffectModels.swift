import Foundation

enum CameraBackgroundMode: String, CaseIterable, Identifiable {
    case normal
    case blur
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .blur: return "Blur"
        case .replace: return "Replace"
        }
    }
}

enum CameraBlurStrength: String, CaseIterable, Identifiable {
    case light
    case medium
    case strong

    var id: String { rawValue }

    var title: String { rawValue.capitalized }
}

enum CameraShape: String, CaseIterable, Identifiable {
    case circle
    case roundedRectangle
    case rectangle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .circle: return "Circle"
        case .roundedRectangle: return "Rounded"
        case .rectangle: return "Rectangle"
        }
    }
}

struct CameraOverlayLayout: Codable, Equatable {
    var x: Double = 0.82
    var y: Double = 0.78
    var width: Double = 0.16
}
