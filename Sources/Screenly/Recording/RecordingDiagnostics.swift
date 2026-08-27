import Foundation

struct RecordingDiagnostics: Codable, Equatable {
    var droppedScreenFrames: Int = 0
    var droppedCameraFrames: Int = 0
    var encoderBackpressureDrops: Int = 0
    var estimatedQueueDepth: Int = 0
    var outputBytes: Int64 = 0
    var avSyncOffsetMs: Double = 0
}
