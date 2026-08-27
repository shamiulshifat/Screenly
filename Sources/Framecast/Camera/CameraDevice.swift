import AVFoundation
import Foundation

struct CameraDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let device: AVCaptureDevice

    init(device: AVCaptureDevice) {
        id = device.uniqueID
        name = device.localizedName
        self.device = device
    }
}
