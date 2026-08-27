import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingOverlayPanelManager: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var cameraBubblePanel: NSPanel?
    private var borderPanels: [NSPanel] = []
    private var stateCancellable: AnyCancellable?
    private var layoutCancellable: AnyCancellable?
    private weak var coordinatorRef: RecordingCoordinator?
    private var isApplyingCameraBubbleFrame = false

    func bind(to coordinator: RecordingCoordinator) {
        coordinatorRef = coordinator

        stateCancellable = coordinator.$state
            .combineLatest(coordinator.$isCameraEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] state, isCameraEnabled in
                self?.handle(state: state, isCameraEnabled: isCameraEnabled, coordinator: coordinator)
            }

        layoutCancellable = coordinator.$cameraOverlayLayout
            .combineLatest(coordinator.$state, coordinator.$isCameraEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, state, isCameraEnabled in
                guard let self else { return }
                guard self.isActiveRecording(state), isCameraEnabled else {
                    self.hideCameraBubblePanel()
                    return
                }
                self.showCameraBubblePanel(coordinator: coordinator)
            }
    }

    private func handle(state: RecordingState, isCameraEnabled: Bool, coordinator: RecordingCoordinator) {
        switch state {
        case .recording, .paused:
            showPanel(coordinator: coordinator)
            showRecordingBorders(isPaused: state.canResume)
            if isCameraEnabled {
                showCameraBubblePanel(coordinator: coordinator)
            } else {
                hideCameraBubblePanel()
            }
        default:
            hidePanel()
            hideCameraBubblePanel()
            hideRecordingBorders()
        }
    }

    private func showPanel(coordinator: RecordingCoordinator) {
        let contentView = RecordingOverlayView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: contentView)

        let targetWidth: CGFloat = coordinator.isCameraEnabled ? 520 : 470
        let targetHeight: CGFloat = coordinator.isCameraEnabled ? 104 : 70

        if let panel {
            var frame = panel.frame
            frame.size = NSSize(width: targetWidth, height: targetHeight)
            panel.setFrame(frame, display: true, animate: true)
            panel.contentView = hostingView
            panel.orderFrontRegardless()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 80, y: 90, width: targetWidth, height: targetHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isMovableByWindowBackground = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = hostingView

        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func showCameraBubblePanel(coordinator: RecordingCoordinator) {
        guard let screen = cameraBubblePanel?.screen ?? panel?.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let frame = cameraBubbleFrame(for: coordinator.cameraOverlayLayout, on: screen)
        let contentView = CameraBubbleView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: contentView)

        if let cameraBubblePanel {
            cameraBubblePanel.contentView = hostingView
            applyCameraBubbleFrame(frame, to: cameraBubblePanel)
            cameraBubblePanel.orderFrontRegardless()
            return
        }

        let cameraBubblePanel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        cameraBubblePanel.level = .statusBar
        cameraBubblePanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        cameraBubblePanel.hidesOnDeactivate = false
        cameraBubblePanel.isReleasedWhenClosed = false
        cameraBubblePanel.isOpaque = false
        cameraBubblePanel.backgroundColor = .clear
        cameraBubblePanel.hasShadow = true
        cameraBubblePanel.isMovableByWindowBackground = true
        cameraBubblePanel.contentView = hostingView
        cameraBubblePanel.delegate = self

        self.cameraBubblePanel = cameraBubblePanel
        applyCameraBubbleFrame(frame, to: cameraBubblePanel)
        cameraBubblePanel.orderFrontRegardless()
    }

    private func hideCameraBubblePanel() {
        cameraBubblePanel?.orderOut(nil)
    }

    private func applyCameraBubbleFrame(_ frame: CGRect, to panel: NSPanel) {
        isApplyingCameraBubbleFrame = true
        panel.setFrame(frame, display: true)
        isApplyingCameraBubbleFrame = false
    }

    private func cameraBubbleFrame(for layout: CameraOverlayLayout, on screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        let proposedWidth = screenFrame.width * CGFloat(layout.width)
        let width = min(max(90, proposedWidth), screenFrame.width * 0.45)
        let height = coordinatorRef?.cameraShape == .circle ? width : width * 0.65

        var centerX = screenFrame.minX + screenFrame.width * CGFloat(layout.x)
        var centerY = screenFrame.maxY - screenFrame.height * CGFloat(layout.y)

        centerX = min(max(centerX, screenFrame.minX + width / 2), screenFrame.maxX - width / 2)
        centerY = min(max(centerY, screenFrame.minY + height / 2), screenFrame.maxY - height / 2)

        return CGRect(
            x: centerX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }

    func windowDidMove(_ notification: Notification) {
        guard let movedWindow = notification.object as? NSWindow,
              movedWindow == cameraBubblePanel,
              !isApplyingCameraBubbleFrame,
              let coordinator = coordinatorRef,
              let screen = movedWindow.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let screenFrame = screen.frame
        guard screenFrame.width > 1, screenFrame.height > 1 else {
            return
        }

        let centerX = movedWindow.frame.midX
        let centerY = movedWindow.frame.midY

        var nextLayout = coordinator.cameraOverlayLayout
        nextLayout.x = min(max(Double((centerX - screenFrame.minX) / screenFrame.width), 0.05), 0.95)
        nextLayout.y = min(max(Double((screenFrame.maxY - centerY) / screenFrame.height), 0.05), 0.95)

        if abs(nextLayout.x - coordinator.cameraOverlayLayout.x) > 0.0005 ||
            abs(nextLayout.y - coordinator.cameraOverlayLayout.y) > 0.0005 {
            coordinator.cameraOverlayLayout = nextLayout
        }
    }

    private func isActiveRecording(_ state: RecordingState) -> Bool {
        switch state {
        case .recording, .paused:
            return true
        default:
            return false
        }
    }

    private func showRecordingBorders(isPaused: Bool) {
        let targetScreens = NSScreen.screens

        if borderPanels.count != targetScreens.count {
            hideRecordingBorders()
            borderPanels = targetScreens.map(makeBorderPanel)
        }

        for (panel, screen) in zip(borderPanels, targetScreens) {
            panel.setFrame(screen.frame, display: true)
            if let hosting = panel.contentView as? NSHostingView<RecordingBorderView> {
                hosting.rootView = RecordingBorderView(color: isPaused ? .yellow : .red)
            }
            panel.orderFrontRegardless()
        }
    }

    private func hideRecordingBorders() {
        borderPanels.forEach { $0.orderOut(nil) }
    }

    private func makeBorderPanel(for screen: NSScreen) -> NSPanel {
        let hosting = NSHostingView(rootView: RecordingBorderView(color: .red))
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = hosting
        return panel
    }
}

private struct RecordingOverlayView: View {
    @ObservedObject var coordinator: RecordingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(coordinator.state.canResume ? .yellow : .red)
                    .frame(width: 8, height: 8)

                Text(timeText)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .frame(minWidth: 56, alignment: .leading)

                ProgressView(value: Double(coordinator.microphoneRMS), total: 1)
                    .frame(width: 70)

                Text(String(format: "%.0f%%", min(max(Double(coordinator.microphoneRMS) * 100, 0), 100)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Button(coordinator.state.canResume ? "Resume" : "Pause") {
                    coordinator.togglePauseResume()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!(coordinator.state.canPause || coordinator.state.canResume))

                Button(coordinator.isMicrophoneMuted ? "Mic Off" : "Mic On") {
                    coordinator.toggleMicrophoneMuted()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(coordinator.isCameraEnabled ? "Cam Off" : "Cam On") {
                    coordinator.toggleCameraEnabled()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Stop") {
                    Task { await coordinator.stopRecording() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            }

            if coordinator.isCameraEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "hand.draw")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Drag the camera bubble anywhere on screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    Text("Size")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $coordinator.cameraOverlayLayout.width, in: 0.10...0.45)
                        .frame(width: 120)
                    Text(String(format: "%.2f", coordinator.cameraOverlayLayout.width))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var timeText: String {
        let total = Int(coordinator.elapsedSeconds)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct CameraBubbleView: View {
    @ObservedObject var coordinator: RecordingCoordinator

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.22))

            if let image = coordinator.liveRecordingCameraPreview ?? coordinator.cameraPreview.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "video")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(previewShape)
        .overlay {
            previewShape
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    private var previewShape: AnyShape {
        switch coordinator.cameraShape {
        case .circle:
            return AnyShape(Circle())
        case .roundedRectangle:
            return AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .rectangle:
            return AnyShape(Rectangle())
        }
    }
}

private struct RecordingBorderView: View {
    let color: Color

    var body: some View {
        Rectangle()
            .stroke(color.opacity(0.95), lineWidth: 4)
            .ignoresSafeArea()
            .background(Color.clear)
    }
}
