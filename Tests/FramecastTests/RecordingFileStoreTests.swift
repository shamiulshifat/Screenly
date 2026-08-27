import Testing
@testable import Framecast

struct RecordingFileStoreTests {
    @Test
    func filenameHasFramecastPrefix() throws {
        let url = try RecordingFileStore.nextRecordingURL(fileExtension: "mov")
        #expect(url.lastPathComponent.hasPrefix("Framecast "))
        #expect(url.pathExtension == "mov")
    }
}
