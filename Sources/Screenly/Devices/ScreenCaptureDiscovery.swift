import Foundation
import ScreenCaptureKit

@MainActor
final class ScreenCaptureDiscovery: ObservableObject {
    @Published private(set) var sources: [ScreenCaptureSource] = []
    @Published private(set) var displays: [SCDisplay] = []
    @Published private(set) var windows: [SCWindow] = []
    @Published private(set) var screenlyApplications: [SCRunningApplication] = []
    @Published private(set) var screenlyWindows: [SCWindow] = []

    func refresh() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            displays = content.displays
            windows = content.windows

            let bundleID = Bundle.main.bundleIdentifier
            let currentProcessID = ProcessInfo.processInfo.processIdentifier
            screenlyApplications = content.applications.filter { app in
                if let bundleID {
                    return app.bundleIdentifier == bundleID
                }
                return app.processID == currentProcessID
            }

            let screenlyPIDs = Set(screenlyApplications.map(\.processID))
            screenlyWindows = content.windows.filter { window in
                guard let processID = window.owningApplication?.processID else { return false }
                return screenlyPIDs.contains(processID)
            }

            var discoveredSources: [ScreenCaptureSource] = []
            discoveredSources.append(contentsOf: content.displays.map(ScreenCaptureSource.display))

            let candidateWindows = content.windows.filter { window in
                guard let processID = window.owningApplication?.processID else { return true }
                return !screenlyPIDs.contains(processID)
            }

            let candidateApplications = content.applications.filter { app in
                !screenlyPIDs.contains(app.processID)
            }

            discoveredSources.append(contentsOf: candidateWindows.map(ScreenCaptureSource.window))
            discoveredSources.append(contentsOf: candidateApplications.map(ScreenCaptureSource.application))

            sources = discoveredSources
            ScreenlyLogger.capture.info("Loaded \(self.sources.count) capture sources")
        } catch {
            sources = []
            displays = []
            windows = []
            screenlyApplications = []
            screenlyWindows = []
            ScreenlyLogger.capture.error("Failed to load shareable content: \(error.localizedDescription)")
        }
    }
}
