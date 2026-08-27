import Foundation

enum RecordingState: Equatable {
    case idle
    case preparing
    case countdown
    case recording(startedAt: Date)
    case paused
    case stopping
    case completed(outputURL: URL)
    case failed(message: String)

    var canStart: Bool {
        switch self {
        case .idle, .completed, .failed:
            return true
        default:
            return false
        }
    }

    var canStop: Bool {
        switch self {
        case .preparing, .countdown, .recording, .paused:
            return true
        default:
            return false
        }
    }

    var canPause: Bool {
        if case .recording = self {
            return true
        }
        return false
    }

    var canResume: Bool {
        if case .paused = self {
            return true
        }
        return false
    }
}
