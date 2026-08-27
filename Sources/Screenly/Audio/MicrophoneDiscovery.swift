import AVFoundation
import Foundation

@MainActor
final class MicrophoneDiscovery: ObservableObject {
    @Published private(set) var devices: [AudioInputDevice] = []

    func refresh() {
        let discovered = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        ).devices

        devices = discovered.map(AudioInputDevice.init)
        ScreenlyLogger.capture.info("Loaded \(self.devices.count) microphone devices")
    }
}
