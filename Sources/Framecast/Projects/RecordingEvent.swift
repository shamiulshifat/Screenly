import Foundation

struct RecordingEvent: Codable, Equatable {
    let timestamp: TimeInterval
    let type: String
    let payload: [String: String]?
}
