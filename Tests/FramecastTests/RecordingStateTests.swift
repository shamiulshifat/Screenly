import Foundation
import Testing
@testable import Framecast

struct RecordingStateTests {
    @Test
    func idleCanStart() {
        #expect(RecordingState.idle.canStart)
        #expect(!RecordingState.idle.canStop)
    }

    @Test
    func recordingCanStop() {
        #expect(!RecordingState.recording(startedAt: Date()).canStart)
        #expect(RecordingState.recording(startedAt: Date()).canStop)
    }

    @Test
    func failedCanRestart() {
        #expect(RecordingState.failed(message: "err").canStart)
    }
}
