import AVFoundation
import Foundation

@MainActor
final class CameraDiscovery: ObservableObject {
    @Published private(set) var devices: [CameraDevice] = []

    func refresh() {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .externalUnknown]
        if #available(macOS 14.0, *) {
            deviceTypes.append(.continuityCamera)
        }

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )

        devices = session.devices.map(CameraDevice.init)
        FramecastLogger.capture.info("Loaded \(self.devices.count) camera devices")
    }
}
