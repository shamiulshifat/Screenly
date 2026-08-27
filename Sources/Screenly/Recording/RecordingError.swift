import Foundation

enum RecordingError: Error, LocalizedError {
    case screenPermissionDenied
    case cameraPermissionDenied
    case microphonePermissionDenied
    case screenSourceUnavailable
    case microphoneUnavailable
    case cameraUnavailable
    case writerInitializationFailed
    case writerStartFailed
    case recordingWriteFailed
    case streamStartFailed
    case streamStopFailed

    var errorDescription: String? {
        switch self {
        case .screenPermissionDenied:
            return "Screen Recording permission is required."
        case .cameraPermissionDenied:
            return "Camera permission is required."
        case .microphonePermissionDenied:
            return "Microphone permission is required."
        case .screenSourceUnavailable:
            return "No screen source is currently available."
        case .microphoneUnavailable:
            return "The selected microphone is unavailable."
        case .cameraUnavailable:
            return "The selected camera is unavailable."
        case .writerInitializationFailed:
            return "Could not initialize video writer."
        case .writerStartFailed:
            return "Could not start writing the recording file."
        case .recordingWriteFailed:
            return "Failed while writing recording samples."
        case .streamStartFailed:
            return "Could not start screen capture stream."
        case .streamStopFailed:
            return "Could not stop screen capture stream cleanly."
        }
    }
}
