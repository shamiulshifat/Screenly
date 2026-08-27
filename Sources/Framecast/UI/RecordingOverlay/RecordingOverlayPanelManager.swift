import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingOverlayPanelManager {
    private var panel: NSPanel?
    private var borderPanels: [NSPanel] = []
    private var stateCancellable: AnyCancellable?

    func bind(to coordinator: RecordingCoordinator) {
        stateCancellable = coordinator.$state
            .combineLatest(coordinator.$isCameraEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] state, _ in
                self?.handle(state: state, coordinator: coordinator)
            }
    }

    private func handle(state: RecordingState, coordinator: RecordingCoordinator) {
        switch state {
        case .recording, .paused:
            showPanel(coordinator: coordinator)
            showRecordingBorders(isPaused: state.canResume)
        default:
            hidePanel()
            hideRecordingBorders()
        }
    }

    private func showPanel(coordinator: RecordingCoordinator) {
        let contentView = RecordingOverlayView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: contentView)

        let targetWidth: CGFloat = 640
        let targetHeight: CGFloat = coordinator.isCameraEnabled ? 430 : 92

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

    @State private var dragStartLayout: CameraOverlayLayout?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(coordinator.state.canResume ? .yellow : .red)
                    .frame(width: 10, height: 10)

                Text(timeText)
                    .font(.system(.headline, design: .monospaced))
                    .frame(minWidth: 64, alignment: .leading)

                ProgressView(value: Double(coordinator.microphoneRMS), total: 1)
                    .frame(width: 90)

                Text(String(format: "%.0f%%", min(max(Double(coordinator.microphoneRMS) * 100, 0), 100)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Button(coordinator.state.canResume ? "Resume" : "Pause") {
                    coordinator.togglePauseResume()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!(coordinator.state.canPause || coordinator.state.canResume))

                Button(coordinator.isMicrophoneMuted ? "Mic Off" : "Mic On") {
                    coordinator.toggleMicrophoneMuted()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(coordinator.isCameraEnabled ? "Cam Off" : "Cam On") {
                    coordinator.toggleCameraEnabled()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("Stop") {
                    Task { await coordinator.stopRecording() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.red)
            }

            if coordinator.isCameraEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Live Camera Overlay (drag to move)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    GeometryReader { proxy in
                        let width = max(proxy.size.width * coordinator.cameraOverlayLayout.width, 90)
                        let height = coordinator.cameraShape == .circle ? width : width * 0.65

                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black.opacity(0.2))

                            CameraPreviewView(service: coordinator.cameraPreview)
                                .opacity(coordinator.liveRecordingCameraPreview == nil ? 1 : 0)
                                .overlay {
                                    if let image = coordinator.liveRecordingCameraPreview {
                                        Image(nsImage: image)
                                            .resizable()
                                            .scaledToFill()
                                    }
                                }
                                .frame(width: width, height: height)
                                .clipShape(previewShape)
                                .overlay {
                                    previewShape
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                }
                                .position(
                                    x: proxy.size.width * coordinator.cameraOverlayLayout.x,
                                    y: proxy.size.height * coordinator.cameraOverlayLayout.y
                                )
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            if dragStartLayout == nil {
                                                dragStartLayout = coordinator.cameraOverlayLayout
                                            }
                                            guard let start = dragStartLayout else { return }
                                            let nx = start.x + Double(value.translation.width / max(proxy.size.width, 1))
                                            let ny = start.y + Double(value.translation.height / max(proxy.size.height, 1))
                                            coordinator.cameraOverlayLayout.x = min(max(nx, 0.05), 0.95)
                                            coordinator.cameraOverlayLayout.y = min(max(ny, 0.05), 0.95)
                                        }
                                        .onEnded { _ in
                                            dragStartLayout = nil
                                        }
                                )
                        }
                    }
                    .frame(height: 120)

                    HStack {
                        Text("Size")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(value: $coordinator.cameraOverlayLayout.width, in: 0.10...0.45)
                    }

                    HStack {
                        Text("X")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(value: $coordinator.cameraOverlayLayout.x, in: 0.05...0.95)
                        Text(String(format: "%.2f", coordinator.cameraOverlayLayout.x))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }

                    HStack {
                        Text("Y")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(value: $coordinator.cameraOverlayLayout.y, in: 0.05...0.95)
                        Text(String(format: "%.2f", coordinator.cameraOverlayLayout.y))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }

                    HStack(spacing: 8) {
                        Text("Shape")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Picker("Shape", selection: $coordinator.cameraShape) {
                            ForEach(CameraShape.allCases) { shape in
                                Text(shape.title).tag(shape)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack(spacing: 8) {
                        Text("Background")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Picker("Background", selection: $coordinator.cameraBackgroundMode) {
                            ForEach(CameraBackgroundMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if coordinator.cameraBackgroundMode == .blur {
                        HStack(spacing: 8) {
                            Text("Blur")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Picker("Blur", selection: $coordinator.cameraBlurStrength) {
                                ForEach(CameraBlurStrength.allCases) { strength in
                                    Text(strength.title).tag(strength)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    if coordinator.cameraBackgroundMode == .replace {
                        HStack(spacing: 8) {
                            Button("Choose Background") {
                                coordinator.chooseCameraReplacementImage()
                            }
                            .buttonStyle(.bordered)

                            if let replacementURL = coordinator.cameraReplacementImageURL {
                                Text(replacementURL.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("No image selected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
