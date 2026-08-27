import AVFoundation
import Foundation

struct AudioInputDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let qualityHint: String?
    let device: AVCaptureDevice

    init(device: AVCaptureDevice) {
        self.id = device.uniqueID
        self.name = device.localizedName
        self.qualityHint = Self.makeQualityHint(for: device.localizedName)
        self.device = device
    }

    private static func makeQualityHint(for name: String) -> String? {
        let lowered = name.lowercased()
        if lowered.contains("airpods") || lowered.contains("bluetooth") {
            return "Bluetooth voice quality"
        }
        return nil
    }
}
