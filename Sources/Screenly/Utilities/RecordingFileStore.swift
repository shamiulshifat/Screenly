import Foundation

enum RecordingFileStore {
    static func defaultDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let moviesDirectory = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first else {
            throw RecordingError.writerInitializationFailed
        }

        let directory = moviesDirectory.appendingPathComponent("Screenly", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func validatedDirectory(_ preferred: URL?) throws -> URL {
        if let preferred {
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: preferred.path) {
                try fileManager.createDirectory(at: preferred, withIntermediateDirectories: true)
            }
            return preferred
        }

        return try defaultDirectory()
    }

    static func nextRecordingURL(fileExtension: String = "mp4", preferredDirectory: URL? = nil) throws -> URL {
        let directory = try validatedDirectory(preferredDirectory)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"

        let base = "Screenly \(formatter.string(from: Date()))"
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(fileExtension)

        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(base)-\(suffix)")
                .appendingPathExtension(fileExtension)
            suffix += 1
        }

        return candidate
    }
}
