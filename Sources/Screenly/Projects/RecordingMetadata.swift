import Foundation

struct RecordingMetadata: Codable, Equatable {
    let outputPath: String
    let startedAt: Date
    let endedAt: Date
    let qualityPreset: String
    let sourceID: String?
    let systemAudioEnabled: Bool
    let microphoneID: String?
    let cameraEnabled: Bool
    let cameraID: String?
    let cameraBackgroundMode: String
    let events: [RecordingEvent]
    let diagnostics: RecordingDiagnosticsReport
}
