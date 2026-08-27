import AppKit
import Combine

@MainActor
final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private weak var coordinator: RecordingCoordinator?

    private var stateCancellable: AnyCancellable?

    func start(with coordinator: RecordingCoordinator) {
        guard statusItem == nil else { return }
        self.coordinator = coordinator

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        stateCancellable = coordinator.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }

        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let statusItem,
              let coordinator else { return }

        updateStatusItemButton(for: coordinator.state)

        let menu = NSMenu()

        let statusItemInfo = NSMenuItem(title: "Status\t\(stateText(for: coordinator.state))", action: nil, keyEquivalent: "")
        statusItemInfo.isEnabled = false
        menu.addItem(statusItemInfo)

        menu.addItem(.separator())

        let newRecordingItem = NSMenuItem(title: "Open Framecast", action: #selector(focusApp), keyEquivalent: "")
        newRecordingItem.target = self
        menu.addItem(newRecordingItem)

        let source = coordinator.availableSources.first(where: { $0.id == coordinator.selectedSourceID })?.name ?? "Not selected"
        let camera = coordinator.cameraDevices.first(where: { $0.id == coordinator.selectedCameraID })?.name ?? "Off"
        let microphone = coordinator.microphoneDevices.first(where: { $0.id == coordinator.selectedMicrophoneID })?.name ?? "Not selected"

        let sourceItem = NSMenuItem(title: "Screen\t\(source)", action: nil, keyEquivalent: "")
        sourceItem.isEnabled = false
        menu.addItem(sourceItem)

        let cameraItem = NSMenuItem(title: "Camera\t\(camera)", action: nil, keyEquivalent: "")
        cameraItem.isEnabled = false
        menu.addItem(cameraItem)

        let microphoneItem = NSMenuItem(title: "Microphone\t\(microphone)", action: nil, keyEquivalent: "")
        microphoneItem.isEnabled = false
        menu.addItem(microphoneItem)

        let systemAudioItem = NSMenuItem(title: "System Audio\t\(coordinator.shouldCaptureSystemAudio ? "On" : "Off")", action: nil, keyEquivalent: "")
        systemAudioItem.isEnabled = false
        menu.addItem(systemAudioItem)

        menu.addItem(.separator())

        let startItem = NSMenuItem(title: "Start Recording", action: #selector(startRecording), keyEquivalent: "r")
        startItem.target = self
        startItem.keyEquivalentModifierMask = [.command, .shift]
        startItem.isEnabled = coordinator.state.canStart
        menu.addItem(startItem)

        let pauseTitle = coordinator.state.canResume ? "Resume" : "Pause"
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(togglePauseResume), keyEquivalent: "p")
        pauseItem.target = self
        pauseItem.keyEquivalentModifierMask = [.command, .shift]
        pauseItem.isEnabled = coordinator.state.canPause || coordinator.state.canResume
        menu.addItem(pauseItem)

        let stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "s")
        stopItem.target = self
        stopItem.keyEquivalentModifierMask = [.command, .shift]
        stopItem.isEnabled = coordinator.state.canStop
        menu.addItem(stopItem)

        menu.addItem(.separator())

        let recordingsItem = NSMenuItem(title: "Show Recordings Folder", action: #selector(openRecordingsFolder), keyEquivalent: "")
        recordingsItem.target = self
        menu.addItem(recordingsItem)

        let diagnosticsItem = NSMenuItem(title: "Open Latest Diagnostics", action: #selector(openDiagnostics), keyEquivalent: "")
        diagnosticsItem.target = self
        diagnosticsItem.isEnabled = coordinator.lastOutputURL != nil
        menu.addItem(diagnosticsItem)

        let projectBundleItem = NSMenuItem(title: "Reveal Project Bundle", action: #selector(showProjectBundle), keyEquivalent: "")
        projectBundleItem.target = self
        projectBundleItem.isEnabled = coordinator.lastProjectBundleURL != nil
        menu.addItem(projectBundleItem)

        if coordinator.lastOutputURL == nil, coordinator.lastProjectBundleURL == nil {
            let noOutputItem = NSMenuItem(title: "No recent outputs yet", action: nil, keyEquivalent: "")
            noOutputItem.isEnabled = false
            menu.addItem(noOutputItem)
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func focusApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func startRecording() {
        guard let coordinator else { return }
        Task { await coordinator.startRecording() }
    }

    @objc private func togglePauseResume() {
        coordinator?.togglePauseResume()
    }

    @objc private func stopRecording() {
        guard let coordinator else { return }
        Task { await coordinator.stopRecording() }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func openRecordingsFolder() {
        if let coordinator,
           let output = coordinator.lastOutputURL {
            NSWorkspace.shared.activateFileViewerSelecting([output.deletingLastPathComponent()])
            return
        }

        if let directory = try? RecordingFileStore.defaultDirectory() {
            NSWorkspace.shared.open(directory)
        }
    }

    @objc private func openDiagnostics() {
        coordinator?.openLastDiagnosticsReport()
    }

    @objc private func showProjectBundle() {
        coordinator?.revealLastProjectBundle()
    }

    private func updateStatusItemButton(for state: RecordingState) {
        guard let button = statusItem?.button else { return }
        button.title = menuBarTitle(for: state)
    }

    private func menuBarTitle(for state: RecordingState) -> String {
        switch state {
        case .recording:
            return "● REC"
        case .paused:
            return "◼︎ Paused"
        case .countdown:
            return "◔ Ready"
        case .preparing, .stopping:
            return "◌ Framecast"
        case .failed:
            return "⚠ Framecast"
        case .idle, .completed:
            return "Framecast"
        }
    }

    private func stateText(for state: RecordingState) -> String {
        switch state {
        case .idle:
            return "Idle"
        case .preparing:
            return "Preparing"
        case .countdown:
            return "Countdown"
        case .recording:
            return "Recording"
        case .paused:
            return "Paused"
        case .stopping:
            return "Stopping"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }
}
