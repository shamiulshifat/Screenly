import OSLog

enum FramecastLogger {
    static let capture = Logger(subsystem: "com.framecast.app", category: "capture")
    static let encoder = Logger(subsystem: "com.framecast.app", category: "encoder")
    static let permissions = Logger(subsystem: "com.framecast.app", category: "permissions")
    static let ui = Logger(subsystem: "com.framecast.app", category: "ui")
}
