import Foundation

@MainActor
final class AppRuntimeController {
    private let overlayManager = RecordingOverlayPanelManager()
    private let hotkeys = GlobalShortcutManager()
    private let hud = HUDNotificationManager()
    private let menuBar = MenuBarManager()

    private weak var coordinator: RecordingCoordinator?
    private var isStarted = false

    func start(with coordinator: RecordingCoordinator) {
        guard !isStarted else { return }
        isStarted = true
        self.coordinator = coordinator

        overlayManager.bind(to: coordinator)
        menuBar.start(with: coordinator)
        hotkeys.onAction = { [weak self] action in
            self?.handle(action: action)
        }
        hotkeys.onRegistrationIssue = { [weak self] message in
            self?.hud.show(title: message, shortcut: "Hotkey")
        }
        hotkeys.registerDefaults()
    }

    private func handle(action: GlobalShortcutManager.Action) {
        guard let coordinator else { return }

        switch action {
        case .startRecording:
            if coordinator.state.canStart {
                Task { await coordinator.startRecording() }
                hud.show(title: "Recording Started", shortcut: action.displayShortcut)
            }

        case .pauseResume:
            coordinator.togglePauseResume()
            let title = coordinator.state.canResume ? "Paused" : "Resumed"
            hud.show(title: title, shortcut: action.displayShortcut)

        case .stopRecording:
            if coordinator.state.canStop {
                Task { await coordinator.stopRecording() }
                hud.show(title: "Recording Stopped", shortcut: action.displayShortcut)
            }

        case .toggleCamera:
            coordinator.toggleCameraEnabled()
            let title = coordinator.isCameraEnabled ? "Camera On" : "Camera Off"
            hud.show(title: title, shortcut: action.displayShortcut)

        case .toggleMicrophone:
            coordinator.toggleMicrophoneMuted()
            let title = coordinator.isMicrophoneMuted ? "Microphone Muted" : "Microphone Unmuted"
            hud.show(title: title, shortcut: action.displayShortcut)
        }
    }
}
