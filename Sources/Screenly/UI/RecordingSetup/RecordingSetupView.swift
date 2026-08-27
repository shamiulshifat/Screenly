import SwiftUI

struct RecordingSetupView: View {
    private enum SetupTab: String, CaseIterable, Identifiable {
        case capture
        case camera
        case audio
        case output
        case status

        var id: String { rawValue }

        var title: String {
            switch self {
            case .capture: return "Capture"
            case .camera: return "Camera"
            case .audio: return "Audio"
            case .output: return "Output"
            case .status: return "Status"
            }
        }
    }

    @ObservedObject var coordinator: RecordingCoordinator
    @AppStorage("screenly.onboarding.dismissed") private var onboardingChecklistDismissed = false
    @State private var selectedSetupTab: SetupTab = .capture

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.12), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection

                    if shouldShowOnboardingChecklist {
                        onboardingChecklistSection
                    }

                    setupTabPicker
                    tabContent

                    if let errorMessage = coordinator.errorMessage {
                        errorBanner(errorMessage)
                    }
                }
                .padding(20)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: coordinator.state)
        .animation(.easeInOut(duration: 0.2), value: coordinator.isCameraEnabled)
        .animation(.easeInOut(duration: 0.2), value: coordinator.cameraBackgroundMode)
        .task {
            await coordinator.refreshSources()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screenly")
                        .font(.largeTitle.weight(.bold))
                    Text("Fast, reliable screen recording with camera, audio, and diagnostics.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusPill
            }

            LazyVGrid(columns: headerBadgeColumns, alignment: .leading, spacing: 8) {
                statBadge(title: "Source", value: selectedSourceName)
                statBadge(title: "Mic", value: selectedMicrophoneName)
                statBadge(title: "System", value: coordinator.shouldCaptureSystemAudio ? "On" : "Off")
                statBadge(title: "Camera", value: coordinator.isCameraEnabled ? "On" : "Off")
            }
        }
    }

    private var onboardingChecklistSection: some View {
        setupCard(title: "First Recording Checklist", subtitle: "Finish these quick steps for a smooth first capture.", icon: "checklist") {
            checklistRow(
                title: "Choose a capture source",
                description: "Pick a display, window, or application.",
                isComplete: hasSelectedCaptureSource
            )

            checklistRow(
                title: "Pick your microphone",
                description: "Select a preferred input device.",
                isComplete: hasSelectedMicrophone
            )

            checklistRow(
                title: "Set output folder",
                description: "Confirm where recordings are stored.",
                isComplete: !coordinator.saveDirectoryPath.isEmpty
            )

            checklistRow(
                title: "Optional: preview camera",
                description: "Enable camera and verify framing.",
                isComplete: !coordinator.isCameraEnabled || hasSelectedCamera
            )

            HStack {
                Text(checklistProgressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Hide Checklist") {
                    onboardingChecklistDismissed = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var setupTabPicker: some View {
        Picker("Section", selection: $selectedSetupTab) {
            ForEach(SetupTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedSetupTab {
        case .capture:
            actionSection
            sourceSection
            regionSection
            permissionHelpSection
        case .camera:
            cameraSection
        case .audio:
            microphoneSection
            systemAudioSection
        case .output:
            storageSection
        case .status:
            stateSection
            diagnosticsSection
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(stateLabel)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.14), in: Capsule())
    }

    private func statBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var permissionHelpSection: some View {
        setupCard(title: "Permissions", subtitle: "Jump directly to macOS privacy settings.", icon: "hand.raised") {
            Text("Screenly needs Screen Recording and Microphone permissions. Camera permission is optional.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("If capture fails, open System Settings → Privacy & Security from the shortcuts below.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Button("Screen") {
                        coordinator.openScreenRecordingSettings()
                    }
                    .buttonStyle(.link)

                    Button("Microphone") {
                        coordinator.openMicrophoneSettings()
                    }
                    .buttonStyle(.link)

                    Button("Camera") {
                        coordinator.openCameraSettings()
                    }
                    .buttonStyle(.link)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Button("Screen") {
                        coordinator.openScreenRecordingSettings()
                    }
                    .buttonStyle(.link)

                    Button("Microphone") {
                        coordinator.openMicrophoneSettings()
                    }
                    .buttonStyle(.link)

                    Button("Camera") {
                        coordinator.openCameraSettings()
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private var regionSection: some View {
        setupCard(title: "Region Capture", subtitle: "Trim a display area before capture starts.", icon: "rectangle.dashed") {
            Toggle("Enable region capture", isOn: $coordinator.isRegionCaptureEnabled)
                .disabled(!isDisplaySourceSelected)

            if coordinator.isRegionCaptureEnabled {
                regionSlider(title: "X", value: $coordinator.captureRegion.x, range: 0.05...0.95)
                regionSlider(title: "Y", value: $coordinator.captureRegion.y, range: 0.05...0.95)
                regionSlider(title: "W", value: $coordinator.captureRegion.width, range: 0.2...1.0)
                regionSlider(title: "H", value: $coordinator.captureRegion.height, range: 0.2...1.0)
            }
        }
    }

    private var storageSection: some View {
        setupCard(title: "Storage", subtitle: "Set where completed recordings are saved.", icon: "externaldrive") {
            Text(coordinator.saveDirectoryPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack {
                Button("Choose Folder") {
                    coordinator.chooseSaveDirectory()
                }

                Button("Use Default") {
                    coordinator.resetSaveDirectoryToDefault()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private var cameraSection: some View {
        setupCard(title: "Camera", subtitle: "Add a camera overlay and style its appearance.", icon: "camera") {
            Toggle("Enable camera", isOn: cameraEnabledBinding)

            if coordinator.isCameraEnabled && coordinator.cameraDevices.isEmpty {
                emptyStateCard(
                    title: "No camera detected",
                    description: "Connect or enable a camera, then click Refresh Cameras.",
                    icon: "video.slash"
                )
            }

            Picker("Camera", selection: selectedCameraBinding) {
                ForEach(coordinator.cameraDevices) { camera in
                    Text(camera.name)
                        .tag(Optional(camera.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(!coordinator.isCameraEnabled || coordinator.cameraDevices.isEmpty)

            if coordinator.isCameraEnabled {
                CameraPreviewView(service: coordinator.cameraPreview)
                    .frame(maxWidth: 360)
                    .frame(height: 200)
                    .clipShape(cameraPreviewShape)
                    .overlay {
                        cameraPreviewShape
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    }

                Picker("Shape", selection: $coordinator.cameraShape) {
                    ForEach(CameraShape.allCases) { shape in
                        Text(shape.title).tag(shape)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Mirror camera", isOn: $coordinator.cameraMirrorEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Overlay Position")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    CameraOverlayEditorView(layout: $coordinator.cameraOverlayLayout, shape: coordinator.cameraShape)

                    HStack {
                        Text("X")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(value: $coordinator.cameraOverlayLayout.x, in: 0.05...0.95)
                    }

                    HStack {
                        Text("Y")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(value: $coordinator.cameraOverlayLayout.y, in: 0.05...0.95)
                    }

                    HStack {
                        Text("Size")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(value: $coordinator.cameraOverlayLayout.width, in: 0.10...0.35)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Picker("Background", selection: $coordinator.cameraBackgroundMode) {
                    ForEach(CameraBackgroundMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if coordinator.cameraBackgroundMode == .blur {
                    Picker("Blur", selection: $coordinator.cameraBlurStrength) {
                        ForEach(CameraBlurStrength.allCases) { strength in
                            Text(strength.title).tag(strength)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if coordinator.cameraBackgroundMode == .replace {
                    HStack {
                        Button("Choose Background Image") {
                            coordinator.chooseCameraReplacementImage()
                        }
                        .buttonStyle(.bordered)

                        if let url = coordinator.cameraReplacementImageURL {
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Label("No image selected", systemImage: "photo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Button("Refresh Cameras") {
                coordinator.refreshCameras()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private var systemAudioSection: some View {
        setupCard(title: "System Audio", subtitle: "Include Mac speaker/app output in recordings.", icon: "speaker.wave.2") {
            Toggle("Record system audio", isOn: $coordinator.isSystemAudioEnabled)
                .disabled(!coordinator.supportsSystemAudioCapture)

            Text(systemAudioSupportText)
                .font(.caption)
                .foregroundStyle(coordinator.supportsSystemAudioCapture ? Color.secondary : Color.orange)
        }
    }

    private var microphoneSection: some View {
        setupCard(title: "Microphone", subtitle: "Choose an input device and monitor live levels.", icon: "mic") {
            if coordinator.microphoneDevices.isEmpty {
                emptyStateCard(
                    title: "No microphone available",
                    description: "Connect a microphone or allow access, then click Refresh Microphones.",
                    icon: "mic.slash"
                )
            }

            Picker("Microphone", selection: selectedMicrophoneBinding) {
                ForEach(coordinator.microphoneDevices) { microphone in
                    Text(microphoneLabel(microphone))
                        .tag(Optional(microphone.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(coordinator.microphoneDevices.isEmpty)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    ProgressView(value: Double(coordinator.microphoneRMS), total: 1)
                        .progressViewStyle(.linear)
                    Circle()
                        .fill(coordinator.microphonePeak > 0.92 ? .red : .green)
                        .frame(width: 8, height: 8)
                }
                Text("Live input level")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(microphoneRecordingSupportText)
                .font(.caption)
                .foregroundStyle(coordinator.supportsMicrophoneInRecording ? Color.secondary : Color.orange)

            Button("Refresh Microphones") {
                coordinator.refreshMicrophones()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private var sourceSection: some View {
        setupCard(title: "Capture Source", subtitle: "Choose a display, window, or app to capture.", icon: "display") {
            if coordinator.availableSources.isEmpty {
                emptyStateCard(
                    title: "No capture sources yet",
                    description: "Allow Screen Recording in macOS settings, then click Refresh Sources.",
                    icon: "display.slash"
                )
            }

            Picker("Source", selection: $coordinator.selectedSourceID) {
                if !displaySources.isEmpty {
                    Section("Displays") {
                        ForEach(displaySources) { source in
                            Text(sourceLabel(source))
                                .tag(Optional(source.id))
                        }
                    }
                }

                if !windowSources.isEmpty {
                    Section("Windows") {
                        ForEach(windowSources) { source in
                            Text(sourceLabel(source))
                                .tag(Optional(source.id))
                        }
                    }
                }

                if !applicationSources.isEmpty {
                    Section("Applications") {
                        ForEach(applicationSources) { source in
                            Text(sourceLabel(source))
                                .tag(Optional(source.id))
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .disabled(coordinator.availableSources.isEmpty)

            Button("Refresh Sources") {
                Task { await coordinator.refreshSources() }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private func emptyStateCard(title: String, description: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                    .font(.caption.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func checklistRow(title: String, description: String, isComplete: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? Color.green : Color.secondary)
                .font(.caption.weight(.semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stateSection: some View {
        setupCard(title: "Status", subtitle: "Live session state and timing.", icon: "record.circle") {
            Text("Status: \(stateLabel)")
                .font(.headline)

            if case .countdown = coordinator.state,
               let countdownRemaining = coordinator.countdownRemaining {
                Text("Starting in: \(countdownRemaining)")
                    .font(.title2.monospacedDigit())
            }

            if case .recording = coordinator.state {
                Text("Elapsed: \(format(seconds: coordinator.elapsedSeconds))")
                    .font(.title3.monospacedDigit())
            }

            if case .paused = coordinator.state {
                Text("Paused at: \(format(seconds: coordinator.elapsedSeconds))")
                    .font(.title3.monospacedDigit())
            }

            if case .completed(let url) = coordinator.state {
                Label(url.lastPathComponent, systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var diagnosticsSection: some View {
        setupCard(title: "Diagnostics", subtitle: "Performance health and Safe Mode controls.", icon: "waveform.path.ecg") {
            Toggle("Auto Safe Mode", isOn: $coordinator.autoSafeModeEnabled)
                .font(.caption)

            if let warning = coordinator.diagnosticsWarningMessage,
               coordinator.diagnosticsWarningSeverity != .none {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: coordinator.diagnosticsWarningSeverity == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                        .foregroundStyle(coordinator.diagnosticsWarningSeverity == .critical ? Color.red : Color.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(warning)
                            .font(.caption)
                        Button("Apply Safe Mode") {
                            coordinator.applySafePerformanceMode()
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((coordinator.diagnosticsWarningSeverity == .critical ? Color.red : Color.orange).opacity(0.08))
                )
            }

            Text("Dropped screen frames: \(coordinator.diagnostics.droppedScreenFrames)")
                .font(.caption)
            Text("Dropped camera frames: \(coordinator.diagnostics.droppedCameraFrames)")
                .font(.caption)
            Text("Encoder backpressure drops: \(coordinator.diagnostics.encoderBackpressureDrops)")
                .font(.caption)
            Text("Queue depth estimate: \(coordinator.diagnostics.estimatedQueueDepth)")
                .font(.caption)
            Text("Output size: \(formattedBytes(coordinator.diagnostics.outputBytes))")
                .font(.caption)
            Text(String(format: "A/V offset: %.1f ms", coordinator.diagnostics.avSyncOffsetMs))
                .font(.caption)
                .foregroundStyle(abs(coordinator.diagnostics.avSyncOffsetMs) > 120 ? Color.orange : Color.secondary)

            if !coordinator.diagnosticsDropTrend.isEmpty {
                Text("Drop trend: \(sparkline(for: coordinator.diagnosticsDropTrend))")
                    .font(.caption.monospaced())
            }

            if !coordinator.diagnosticsDriftTrend.isEmpty {
                Text("Drift trend: \(sparkline(for: coordinator.diagnosticsDriftTrend.map(abs)))")
                    .font(.caption.monospaced())
            }
        }
    }

    private var actionSection: some View {
        setupCard(title: "Recording Controls", subtitle: "Core capture actions and output shortcuts.", icon: "record.circle") {
            Text(recordingSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Quality", selection: $coordinator.qualityPreset) {
                ForEach(QualityPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.menu)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    startRecordingButton
                    pauseResumeButton
                    stopRecordingButton

                    Spacer(minLength: 0)

                    toggleMicButton
                    toggleCameraButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        startRecordingButton
                        pauseResumeButton
                        stopRecordingButton
                    }
                    HStack(spacing: 10) {
                        toggleMicButton
                        toggleCameraButton
                    }
                }
            }

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    previewRecordingButton
                    revealInFinderButton
                    openDiagnosticsButton
                    revealProjectBundleButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        previewRecordingButton
                        revealInFinderButton
                    }
                    HStack(spacing: 10) {
                        openDiagnosticsButton
                        revealProjectBundleButton
                    }
                }
            }
        }
    }

    private var startRecordingButton: some View {
        Button("Start Recording") {
            Task { await coordinator.startRecording() }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(minWidth: 130)
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(!coordinator.state.canStart || coordinator.availableSources.isEmpty)
    }

    private var pauseResumeButton: some View {
        Button(coordinator.state.canResume ? "Resume" : "Pause") {
            coordinator.togglePauseResume()
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(minWidth: 100)
        .keyboardShortcut("p", modifiers: [.command, .shift])
        .disabled(!(coordinator.state.canPause || coordinator.state.canResume))
    }

    private var stopRecordingButton: some View {
        Button("Stop") {
            Task { await coordinator.stopRecording() }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(minWidth: 100)
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .disabled(!coordinator.state.canStop)
    }

    private var toggleMicButton: some View {
        Button(coordinator.isMicrophoneMuted ? "Unmute Mic" : "Mute Mic") {
            coordinator.toggleMicrophoneMuted()
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .keyboardShortcut("m", modifiers: [.command, .shift])
    }

    private var toggleCameraButton: some View {
        Button(coordinator.isCameraEnabled ? "Camera Off" : "Camera On") {
            coordinator.toggleCameraEnabled()
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .keyboardShortcut("c", modifiers: [.command, .shift])
    }

    private var previewRecordingButton: some View {
        Button("Preview Recording") {
            coordinator.openLastRecording()
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(coordinator.lastOutputURL == nil)
    }

    private var revealInFinderButton: some View {
        Button("Reveal in Finder") {
            coordinator.revealLastRecording()
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(coordinator.lastOutputURL == nil)
    }

    private var openDiagnosticsButton: some View {
        Button("Open Diagnostics") {
            coordinator.openLastDiagnosticsReport()
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(coordinator.lastOutputURL == nil)
    }

    private var revealProjectBundleButton: some View {
        Button("Reveal Project Bundle") {
            coordinator.revealLastProjectBundle()
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(coordinator.lastProjectBundleURL == nil)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recording Issue", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                if coordinator.shouldShowOpenSettingsAction {
                    Button("Open Screen Recording Settings") {
                        coordinator.openScreenRecordingSettings()
                    }
                    .buttonStyle(.link)
                }

                if coordinator.shouldShowOpenMicrophoneSettingsAction {
                    Button("Open Microphone Settings") {
                        coordinator.openMicrophoneSettings()
                    }
                    .buttonStyle(.link)
                }

                if coordinator.shouldShowOpenCameraSettingsAction {
                    Button("Open Camera Settings") {
                        coordinator.openCameraSettings()
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.red.opacity(0.18), lineWidth: 1)
        )
    }

    private func setupCard<Content: View>(title: String, subtitle: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                    .font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func regionSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var stateLabel: String {
        switch coordinator.state {
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

    private func sourceLabel(_ source: ScreenCaptureSource) -> String {
        var label = source.name
        if let details = source.details, !details.isEmpty {
            label += " — \(details)"
        }
        if let resolution = source.resolutionDescription {
            label += " (\(resolution))"
        }
        return label
    }

    private func format(seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let minutes = total / 60
        let remainder = total % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private func microphoneLabel(_ device: AudioInputDevice) -> String {
        if let hint = device.qualityHint {
            return "\(device.name) — \(hint)"
        }
        return device.name
    }

    private var selectedMicrophoneBinding: Binding<String?> {
        Binding {
            coordinator.selectedMicrophoneID
        } set: { newValue in
            coordinator.selectMicrophone(newValue)
        }
    }

    private var selectedCameraBinding: Binding<String?> {
        Binding {
            coordinator.selectedCameraID
        } set: { newValue in
            coordinator.selectCamera(newValue)
        }
    }

    private var cameraEnabledBinding: Binding<Bool> {
        Binding {
            coordinator.isCameraEnabled
        } set: { newValue in
            if newValue != coordinator.isCameraEnabled {
                coordinator.toggleCameraEnabled()
            }
        }
    }

    private var systemAudioSupportText: String {
        if coordinator.supportsSystemAudioCapture {
            return coordinator.isSystemAudioEnabled
                ? "System audio capture is available and currently on."
                : "System audio capture is available and currently off."
        }
        return "System audio capture is unavailable on this macOS version."
    }

    private var microphoneRecordingSupportText: String {
        if coordinator.supportsMicrophoneInRecording {
            return "Microphone recording is supported on this macOS version."
        }
        return "Microphone recording requires macOS 15 or newer."
    }

    private var recordingSummaryText: String {
        let sourceName = coordinator.availableSources
            .first(where: { $0.id == coordinator.selectedSourceID })?
            .name ?? "No source selected"

        let microphoneName = coordinator.microphoneDevices
            .first(where: { $0.id == coordinator.selectedMicrophoneID })?
            .name ?? "No microphone"

        let systemAudio = coordinator.shouldCaptureSystemAudio ? "ON" : "OFF"
        let recordingState = coordinator.state.canResume ? "PAUSED" : "READY"
        return "\(recordingState): Source \(sourceName) • Mic \(microphoneName) • System Audio \(systemAudio)"
    }

    private var statusColor: Color {
        switch coordinator.state {
        case .idle, .completed:
            return .secondary
        case .preparing, .countdown:
            return .orange
        case .recording:
            return .red
        case .paused:
            return .yellow
        case .stopping:
            return .blue
        case .failed:
            return .red
        }
    }

    private var selectedSourceName: String {
        coordinator.availableSources.first(where: { $0.id == coordinator.selectedSourceID })?.name ?? "Not set"
    }

    private var selectedMicrophoneName: String {
        coordinator.microphoneDevices.first(where: { $0.id == coordinator.selectedMicrophoneID })?.name ?? "Not set"
    }

    private var cameraPreviewShape: AnyShape {
        switch coordinator.cameraShape {
        case .circle:
            return AnyShape(Circle())
        case .roundedRectangle:
            return AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .rectangle:
            return AnyShape(Rectangle())
        }
    }

    private var headerBadgeColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 130), spacing: 8)]
    }

    private var shouldShowOnboardingChecklist: Bool {
        !onboardingChecklistDismissed && completedChecklistCount < onboardingChecklistTotalCount
    }

    private var onboardingChecklistTotalCount: Int { 4 }

    private var completedChecklistCount: Int {
        var count = 0
        if hasSelectedCaptureSource { count += 1 }
        if hasSelectedMicrophone { count += 1 }
        if !coordinator.saveDirectoryPath.isEmpty { count += 1 }
        if !coordinator.isCameraEnabled || hasSelectedCamera { count += 1 }
        return count
    }

    private var checklistProgressText: String {
        "Completed \(completedChecklistCount) of \(onboardingChecklistTotalCount)"
    }

    private var hasSelectedCaptureSource: Bool {
        coordinator.selectedSourceID != nil
    }

    private var hasSelectedMicrophone: Bool {
        coordinator.selectedMicrophoneID != nil
    }

    private var hasSelectedCamera: Bool {
        coordinator.selectedCameraID != nil
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func sparkline(for values: [Double]) -> String {
        let bars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        guard let minValue = values.min(), let maxValue = values.max(), maxValue > minValue else {
            return String(repeating: "▁", count: min(values.count, 30))
        }

        let sample = Array(values.suffix(30))
        return sample.map { value in
            let normalized = (value - minValue) / (maxValue - minValue)
            let index = Int((normalized * Double(bars.count - 1)).rounded())
            return bars[max(0, min(index, bars.count - 1))]
        }.joined()
    }

    private var displaySources: [ScreenCaptureSource] {
        coordinator.availableSources.filter { $0.type == .display }
    }

    private var windowSources: [ScreenCaptureSource] {
        coordinator.availableSources.filter { $0.type == .window }
    }

    private var applicationSources: [ScreenCaptureSource] {
        coordinator.availableSources.filter { $0.type == .application }
    }

    private var isDisplaySourceSelected: Bool {
        coordinator.availableSources.first(where: { $0.id == coordinator.selectedSourceID })?.type == .display
    }
}
