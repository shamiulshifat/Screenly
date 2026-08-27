import SwiftUI

@main
struct FramecastApp: App {
    @StateObject private var coordinator = RecordingCoordinator()
    @State private var runtime = AppRuntimeController()

    var body: some Scene {
        WindowGroup("Framecast") {
            MainDashboardView(coordinator: coordinator)
            .frame(minWidth: 980, minHeight: 760)
            .onAppear {
                runtime.start(with: coordinator)
                Task { await coordinator.refreshSources() }
            }
        }
    }
}
