import Foundation
import ScreenCaptureKit

enum CaptureSourceType: String {
    case display
    case window
    case application

    var title: String {
        switch self {
        case .display:
            return "Display"
        case .window:
            return "Window"
        case .application:
            return "Application"
        }
    }
}

enum ScreenCaptureTarget {
    case display(SCDisplay)
    case window(SCWindow)
    case application(SCRunningApplication)
}

struct ScreenCaptureSource: Identifiable {
    let id: String
    let type: CaptureSourceType
    let name: String
    let details: String?
    let width: Int?
    let height: Int?
    let target: ScreenCaptureTarget

    var resolutionDescription: String? {
        guard let width, let height else { return nil }
        return "\(width)x\(height)"
    }

    static func display(_ display: SCDisplay) -> Self {
        return ScreenCaptureSource(
            id: "display-\(display.displayID)",
            type: .display,
            name: "Display \(display.displayID)",
            details: nil,
            width: display.width,
            height: display.height,
            target: .display(display)
        )
    }

    static func window(_ window: SCWindow) -> Self {
        let appName = window.owningApplication?.applicationName
        let title = (window.title?.isEmpty == false ? window.title : nil) ?? "Window \(window.windowID)"
        let width = max(Int(window.frame.width.rounded()), 0)
        let height = max(Int(window.frame.height.rounded()), 0)
        return ScreenCaptureSource(
            id: "window-\(window.windowID)",
            type: .window,
            name: title,
            details: appName,
            width: width > 0 ? width : nil,
            height: height > 0 ? height : nil,
            target: .window(window)
        )
    }

    static func application(_ application: SCRunningApplication) -> Self {
        ScreenCaptureSource(
            id: "app-\(application.processID)",
            type: .application,
            name: application.applicationName,
            details: application.bundleIdentifier,
            width: nil,
            height: nil,
            target: .application(application)
        )
    }
}
