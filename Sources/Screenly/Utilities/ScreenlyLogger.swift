import OSLog

enum ScreenlyLogger {
    static let capture = Logger(subsystem: "com.screenly.app", category: "capture")
    static let encoder = Logger(subsystem: "com.screenly.app", category: "encoder")
    static let permissions = Logger(subsystem: "com.screenly.app", category: "permissions")
    static let ui = Logger(subsystem: "com.screenly.app", category: "ui")
}
