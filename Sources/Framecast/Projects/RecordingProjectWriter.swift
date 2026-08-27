import Foundation

struct RecordingProjectWriter {
    static func writeProjectBundle(for outputURL: URL, metadata: RecordingMetadata) throws -> URL {
        let bundleURL = outputURL
            .deletingPathExtension()
            .appendingPathExtension("framecast")

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: bundleURL.path) {
            try fileManager.removeItem(at: bundleURL)
        }

        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let metadataData = try JSONEncoder.prettyPrinted.encode(metadata)
        try metadataData.write(to: bundleURL.appendingPathComponent("project.json"), options: .atomic)

        let eventsData = try JSONEncoder.prettyPrinted.encode(metadata.events)
        try eventsData.write(to: bundleURL.appendingPathComponent("events.json"), options: .atomic)

        let diagnosticsData = try JSONEncoder.prettyPrinted.encode(metadata.diagnostics)
        try diagnosticsData.write(to: bundleURL.appendingPathComponent("diagnostics.json"), options: .atomic)

        let mediaCopyURL = bundleURL.appendingPathComponent("screen\(outputURL.pathExtension.isEmpty ? "" : ".\(outputURL.pathExtension)")")
        try? fileManager.removeItem(at: mediaCopyURL)
        try fileManager.copyItem(at: outputURL, to: mediaCopyURL)

        return bundleURL
    }
}
