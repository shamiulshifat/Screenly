import Foundation

struct RecordingDiagnosticsReport: Codable, Equatable {
    let droppedScreenFrames: Int
    let droppedCameraFrames: Int
    let encoderBackpressureDrops: Int
    let estimatedQueueDepth: Int
    let outputBytes: Int64
    let avSyncOffsetMs: Double
    let warningSeverity: String
    let warningMessage: String?
    let autoSafeModeEnabled: Bool
    let dropTrend: [Double]
    let driftTrend: [Double]
}
