import Foundation

struct CameraOverlayConfiguration {
    var isEnabled: Bool
    var selectedCameraID: String?
    var layout: CameraOverlayLayout
    var shape: CameraShape
    var mirror: Bool
    var backgroundMode: CameraBackgroundMode
    var blurStrength: CameraBlurStrength
    var replacementImageURL: URL?
}
