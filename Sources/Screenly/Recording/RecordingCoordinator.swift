import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

@MainActor
final class RecordingCoordinator: NSObject, ObservableObject {
    private let defaultCountdownSeconds = 5

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var availableSources: [ScreenCaptureSource] = []
    @Published var selectedSourceID: String?
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var lastOutputURL: URL?
    @Published private(set) var lastProjectBundleURL: URL?
    @Published private(set) var countdownRemaining: Int?
    @Published private(set) var microphoneDevices: [AudioInputDevice] = []
    @Published var selectedMicrophoneID: String?
    @Published private(set) var microphoneRMS: Float = 0
    @Published private(set) var microphonePeak: Float = 0
    @Published private(set) var liveRecordingCameraPreview: NSImage?
    @Published private(set) var cameraDevices: [CameraDevice] = []
    @Published var selectedCameraID: String? {
        didSet { syncCameraOverlayToRecorderIfActive() }
    }
    @Published var qualityPreset: QualityPreset = .high
    @Published var cameraBackgroundMode: CameraBackgroundMode = .normal {
        didSet { syncCameraOverlayToRecorderIfActive() }
    }
    @Published var cameraBlurStrength: CameraBlurStrength = .medium {
        didSet { syncCameraOverlayToRecorderIfActive() }
    }
    @Published var cameraShape: CameraShape = .circle {
        didSet { syncCameraOverlayToRecorderIfActive() }
    }
    @Published var cameraMirrorEnabled: Bool = true {
        didSet { syncCameraOverlayToRecorderIfActive() }
    }
    @Published var cameraOverlayLayout: CameraOverlayLayout = .init() {
        didSet { syncCameraOverlayToRecorderIfActive() }
    }
    @Published var cameraReplacementImageURL: URL? {
        didSet { syncCameraOverlayToRecorderIfActive() }
    }
    @Published var isSystemAudioEnabled: Bool = true
    @Published var isMicrophoneMuted: Bool = false
    @Published var isCameraEnabled: Bool = false {
        didSet { syncCameraOverlayToRecorderIfActive() }
    }
    @Published private(set) var diagnostics: RecordingDiagnostics = .init()
    @Published private(set) var diagnosticsDropTrend: [Double] = []
    @Published private(set) var diagnosticsDriftTrend: [Double] = []
    @Published private(set) var diagnosticsWarningMessage: String?
    @Published private(set) var diagnosticsWarningSeverity: DiagnosticsWarningSeverity = .none
    @Published var autoSafeModeEnabled: Bool = true
    @Published private(set) var saveDirectoryPath: String = ""
    @Published var isRegionCaptureEnabled: Bool = false
    @Published var captureRegion: CaptureRegion = .init()

    private let discovery = ScreenCaptureDiscovery()
    private let microphoneDiscovery = MicrophoneDiscovery()
    private let cameraDiscovery = CameraDiscovery()
    private let recorder = ScreenRecorder()
    private let microphoneMeter = MicrophoneMeterEngine()
    private let settingsStore = AppSettingsStore()
    let cameraPreview = CameraPreviewService()
    private var elapsedTimer: Timer?
    private var countdownTask: Task<Void, Never>?
    private var recordingStartedAt: Date?
    private var sessionEvents: [RecordingEvent] = []
    private var criticalWarningSince: Date?
    private var hasAutoAppliedSafeModeForSession = false
    private let diagnosticsTrendLimit = 75
    

    override init() {
        super.init()

        microphoneMeter.onLevelUpdate = { [weak self] rms, peak in
            guard let self else { return }
            if self.isMicrophoneMuted {
                self.microphoneRMS = 0
                self.microphonePeak = 0
            } else {
                self.microphoneRMS = rms
                self.microphonePeak = peak
            }
        }

        recorder.onDiagnosticsUpdate = { [weak self] diagnostics in
            self?.diagnostics = diagnostics
            self?.appendDiagnosticsTrend(diagnostics)
            self?.evaluateDiagnosticsWarning()
        }

        recorder.onCameraPreviewFrame = { [weak self] image in
            self?.liveRecordingCameraPreview = image
        }

        updateSaveDirectoryDisplayPath()

        observeDeviceChanges()
    }

    deinit {
        microphoneMeter.stop()
        NotificationCenter.default.removeObserver(self)
    }

    func refreshSources() async {
        errorMessage = nil
        await discovery.refresh()
        availableSources = discovery.sources
        refreshMicrophones()
        refreshCameras()

        validateSelectedSourceDuringSession()

        guard !availableSources.isEmpty else {
            selectedSourceID = nil
            return
        }

        if let selectedSourceID,
           availableSources.contains(where: { $0.id == selectedSourceID }) {
            return
        }

        selectedSourceID = availableSources.first?.id
    }

    func refreshMicrophones() {
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.requestMicrophonePermission()
            guard granted else {
                self.errorMessage = RecordingError.microphonePermissionDenied.localizedDescription
                return
            }
            self.refreshMicrophonesInternal()
        }
    }

    private func refreshMicrophonesInternal() {
        microphoneDiscovery.refresh()
        microphoneDevices = microphoneDiscovery.devices

        if let selectedMicrophoneID,
           microphoneDevices.contains(where: { $0.id == selectedMicrophoneID }) {
            restartMicrophoneMeter()
            return
        }

        selectedMicrophoneID = microphoneDevices.first?.id
        if selectedMicrophoneID == nil {
            isMicrophoneMuted = true
            recorder.setMicrophoneMuted(true)
        }
        restartMicrophoneMeter()
    }

    func selectMicrophone(_ id: String?) {
        guard selectedMicrophoneID != id else { return }
        selectedMicrophoneID = id
        restartMicrophoneMeter()
    }

    func refreshCameras() {
        cameraDiscovery.refresh()
        cameraDevices = cameraDiscovery.devices

        if let selectedCameraID,
           cameraDevices.contains(where: { $0.id == selectedCameraID }) {
            if isCameraEnabled {
                restartCameraPreview()
            }
            return
        }

        selectedCameraID = cameraDevices.first?.id
        if selectedCameraID == nil {
            isCameraEnabled = false
            cameraPreview.stop()
        }
        if isCameraEnabled {
            restartCameraPreview()
        }
    }

    func selectCamera(_ id: String?) {
        guard selectedCameraID != id else { return }
        selectedCameraID = id
        if isCameraEnabled {
            restartCameraPreview()
        }
    }

    func requestScreenPermission() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        ScreenlyLogger.permissions.info("Requesting screen recording permission")
        return CGRequestScreenCaptureAccess()
    }

    func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    func startRecording() async {
        guard state.canStart else { return }
        errorMessage = nil
        state = .preparing

        guard await requestScreenPermission() else {
            state = .failed(message: RecordingError.screenPermissionDenied.localizedDescription)
            errorMessage = RecordingError.screenPermissionDenied.localizedDescription
            return
        }

        guard await requestMicrophonePermission() else {
            state = .failed(message: RecordingError.microphonePermissionDenied.localizedDescription)
            errorMessage = RecordingError.microphonePermissionDenied.localizedDescription
            return
        }

        if isCameraEnabled {
            guard await requestCameraPermission() else {
                state = .failed(message: RecordingError.cameraPermissionDenied.localizedDescription)
                errorMessage = RecordingError.cameraPermissionDenied.localizedDescription
                return
            }
        }

        await refreshSources()

        guard let source = selectedSource() else {
            state = .failed(message: RecordingError.screenSourceUnavailable.localizedDescription)
            errorMessage = RecordingError.screenSourceUnavailable.localizedDescription
            return
        }

        let shouldProceed = await startCountdown(seconds: defaultCountdownSeconds)
        guard shouldProceed else {
            state = .idle
            countdownRemaining = nil
            return
        }

        do {
            try await recorder.start(
                source: source,
                allDisplays: discovery.displays,
                allWindows: discovery.windows,
                excludingApplications: discovery.screenlyApplications,
                excludingWindows: discovery.screenlyWindows,
                selectedMicrophoneID: selectedMicrophoneID,
                includeSystemAudio: shouldCaptureSystemAudio,
                qualityPreset: qualityPreset,
                cameraOverlay: buildCameraOverlayConfiguration(),
                saveDirectoryURL: settingsStore.saveDirectoryURL,
                captureRegion: isRegionCaptureEnabled ? captureRegion : nil
            )
            recorder.setMicrophoneMuted(isMicrophoneMuted)
            diagnostics = .init()
            diagnosticsDropTrend = []
            diagnosticsDriftTrend = []
            diagnosticsWarningMessage = nil
            diagnosticsWarningSeverity = .none
            criticalWarningSince = nil
            hasAutoAppliedSafeModeForSession = false
            recordingStartedAt = Date()
            sessionEvents = []
            startElapsedTimer(reset: true)
            errorMessage = nil
            state = .recording(startedAt: Date())
        } catch {
            let message = userFacingErrorMessage(error)
            errorMessage = message
            state = .failed(message: message)
        }
    }

    func pauseRecording() {
        guard state.canPause else { return }
        recorder.pause()
        stopElapsedTimer()
        recordEvent(type: "pause")
        state = .paused
    }

    func resumeRecording() {
        guard state.canResume else { return }
        recorder.resume()
        startElapsedTimer(reset: false)
        recordEvent(type: "resume")
        state = .recording(startedAt: Date())
    }

    func togglePauseResume() {
        if state.canPause {
            pauseRecording()
        } else if state.canResume {
            resumeRecording()
        }
    }

    func stopRecording() async {
        guard state.canStop else { return }

        if case .preparing = state {
            cancelCountdown()
            state = .idle
            return
        }

        if case .countdown = state {
            cancelCountdown()
            state = .idle
            return
        }

        state = .stopping

        do {
            let outputURL = try await recorder.stop()
            stopElapsedTimer()
            elapsedSeconds = 0
            lastOutputURL = outputURL
            persistMetadata(for: outputURL)
            errorMessage = nil
            state = .completed(outputURL: outputURL)
            liveRecordingCameraPreview = nil
        } catch {
            stopElapsedTimer()
            let message = userFacingErrorMessage(error)
            errorMessage = message
            state = .failed(message: message)
            liveRecordingCameraPreview = nil
        }
    }

    func toggleMicrophoneMuted() {
        isMicrophoneMuted.toggle()
        recorder.setMicrophoneMuted(isMicrophoneMuted)
        recordEvent(type: isMicrophoneMuted ? "microphoneMuted" : "microphoneUnmuted")
    }

    func toggleCameraEnabled() {
        isCameraEnabled.toggle()
        recordEvent(type: isCameraEnabled ? "cameraEnabled" : "cameraDisabled")
        if isCameraEnabled {
            Task {
                let granted = await requestCameraPermission()
                if !granted {
                    isCameraEnabled = false
                    errorMessage = RecordingError.cameraPermissionDenied.localizedDescription
                    return
                }
                restartCameraPreview()
                syncCameraOverlayToRecorderIfActive()
            }
        } else {
            cameraPreview.stop()
            syncCameraOverlayToRecorderIfActive()
            liveRecordingCameraPreview = nil
        }
    }

    func requestCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    func openScreenRecordingSettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }

    func openMicrophoneSettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }

    func openCameraSettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }

    func chooseCameraReplacementImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic]

        if panel.runModal() == .OK {
            cameraReplacementImageURL = panel.url
        }
    }

    private func buildCameraOverlayConfiguration() -> CameraOverlayConfiguration {
        CameraOverlayConfiguration(
            isEnabled: isCameraEnabled,
            selectedCameraID: selectedCameraID,
            layout: cameraOverlayLayout,
            shape: cameraShape,
            mirror: cameraMirrorEnabled,
            backgroundMode: cameraBackgroundMode,
            blurStrength: cameraBlurStrength,
            replacementImageURL: cameraReplacementImageURL
        )
    }

    private func syncCameraOverlayToRecorderIfActive() {
        syncCameraPreviewEffects()

        switch state {
        case .recording, .paused:
            recorder.updateCameraOverlay(buildCameraOverlayConfiguration())
        default:
            break
        }
    }

    func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            settingsStore.saveDirectoryPath = panel.url?.path
            updateSaveDirectoryDisplayPath()
        }
    }

    func resetSaveDirectoryToDefault() {
        settingsStore.saveDirectoryPath = nil
        updateSaveDirectoryDisplayPath()
    }

    var shouldShowOpenSettingsAction: Bool {
        switch state {
        case .failed(let message):
            return message == RecordingError.screenPermissionDenied.localizedDescription
        default:
            return false
        }
    }

    var shouldShowOpenMicrophoneSettingsAction: Bool {
        switch state {
        case .failed(let message):
            return message == RecordingError.microphonePermissionDenied.localizedDescription
        default:
            return false
        }
    }

    var shouldShowOpenCameraSettingsAction: Bool {
        switch state {
        case .failed(let message):
            return message == RecordingError.cameraPermissionDenied.localizedDescription
        default:
            return false
        }
    }

    var supportsMicrophoneInRecording: Bool {
        if #available(macOS 15.0, *) {
            return true
        }
        return false
    }

    var supportsSystemAudioCapture: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    var shouldCaptureSystemAudio: Bool {
        supportsSystemAudioCapture && isSystemAudioEnabled
    }

    func revealLastRecording() {
        guard let lastOutputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastOutputURL])
    }

    func openRecordingsFolder() {
        if let customDirectory = settingsStore.saveDirectoryURL {
            NSWorkspace.shared.open(customDirectory)
            return
        }

        if let defaultDirectory = try? RecordingFileStore.defaultDirectory() {
            NSWorkspace.shared.open(defaultDirectory)
        }
    }

    func openLastRecording() {
        guard let lastOutputURL else { return }
        NSWorkspace.shared.open(lastOutputURL)
    }

    func openFile(at fileURL: URL) {
        NSWorkspace.shared.open(fileURL)
    }

    func revealFile(at fileURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func availableRecordingFiles() -> [URL] {
        let directoryURL: URL
        if let custom = settingsStore.saveDirectoryURL {
            directoryURL = custom
        } else if let fallback = try? RecordingFileStore.defaultDirectory() {
            directoryURL = fallback
        } else {
            return []
        }

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "mov" || ext == "mp4"
        }
    }

    func deleteRecording(at recordingURL: URL) {
        let fileManager = FileManager.default

        try? fileManager.removeItem(at: recordingURL)

        let metadataURL = recordingURL.deletingPathExtension().appendingPathExtension("json")
        if fileManager.fileExists(atPath: metadataURL.path) {
            try? fileManager.removeItem(at: metadataURL)
        }

        let bundleURL = recordingURL.deletingPathExtension().appendingPathExtension("screenly")
        if fileManager.fileExists(atPath: bundleURL.path) {
            try? fileManager.removeItem(at: bundleURL)
        }

        if lastOutputURL == recordingURL {
            lastOutputURL = nil
        }
        if let lastProjectBundleURL,
           lastProjectBundleURL == bundleURL {
            self.lastProjectBundleURL = nil
        }
    }

    func openLastDiagnosticsReport() {
        guard let lastOutputURL else { return }
        let diagnosticsURL = diagnosticsReportURL(for: lastOutputURL)
        guard FileManager.default.fileExists(atPath: diagnosticsURL.path) else { return }
        NSWorkspace.shared.open(diagnosticsURL)
    }

    func revealLastProjectBundle() {
        guard let lastProjectBundleURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastProjectBundleURL])
    }

    private func selectedSource() -> ScreenCaptureSource? {
        guard let selectedSourceID else { return availableSources.first }
        return availableSources.first(where: { $0.id == selectedSourceID })
    }

    private func startElapsedTimer(reset: Bool) {
        if reset {
            elapsedSeconds = 0
        }

        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSeconds += 1
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func restartMicrophoneMeter() {
        microphoneMeter.stop()
        microphoneRMS = 0
        microphonePeak = 0

        guard let selectedMicrophoneID,
              let microphone = microphoneDevices.first(where: { $0.id == selectedMicrophoneID }) else {
            return
        }

        do {
            try microphoneMeter.start(device: microphone.device)
        } catch {
            ScreenlyLogger.capture.error("Unable to start microphone meter: \(error.localizedDescription)")
            errorMessage = RecordingError.microphoneUnavailable.localizedDescription
        }
    }

    private func restartCameraPreview() {
        guard let selectedCameraID,
              let camera = cameraDevices.first(where: { $0.id == selectedCameraID }) else {
            cameraPreview.stop()
            return
        }

        do {
            try cameraPreview.start(device: camera.device)
            syncCameraPreviewEffects()
        } catch {
            ScreenlyLogger.capture.error("Unable to start camera preview: \(error.localizedDescription)")
            errorMessage = RecordingError.cameraUnavailable.localizedDescription
        }
    }

    private func syncCameraPreviewEffects() {
        cameraPreview.updateEffects(
            backgroundMode: cameraBackgroundMode,
            blurStrength: cameraBlurStrength,
            shape: cameraShape,
            mirror: cameraMirrorEnabled,
            replacementImageURL: cameraReplacementImageURL
        )
    }

    private func startCountdown(seconds: Int) async -> Bool {
        cancelCountdown()
        state = .countdown
        countdownRemaining = seconds

        let task = Task { [weak self] in
            guard let self else { return }

            for remaining in stride(from: seconds, through: 1, by: -1) {
                await MainActor.run {
                    self.countdownRemaining = remaining
                }

                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled {
                    return
                }
            }

            await MainActor.run {
                self.countdownRemaining = nil
            }
        }

        countdownTask = task
        await task.value

        let wasCancelled = task.isCancelled
        countdownTask = nil
        return !wasCancelled
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdownRemaining = nil
    }

    private func observeDeviceChanges() {
        let center = NotificationCenter.default

        center.addObserver(self, selector: #selector(handleDeviceDisconnectedNotification(_:)), name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDeviceConnectedNotification(_:)), name: AVCaptureDevice.wasConnectedNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDisplayChangedNotification(_:)), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc
    private func handleDeviceDisconnectedNotification(_ notification: Notification) {
        handleDeviceDisconnect(notification: notification)
    }

    @objc
    private func handleDeviceConnectedNotification(_ notification: Notification) {
        refreshMicrophones()
        refreshCameras()
    }

    @objc
    private func handleDisplayChangedNotification(_ notification: Notification) {
        Task { await refreshSources() }
    }

    private func handleDeviceDisconnect(notification: Notification) {
        guard let device = notification.object as? AVCaptureDevice else { return }

        if device.hasMediaType(.audio), device.uniqueID == selectedMicrophoneID {
            refreshMicrophones()
            errorMessage = "Selected microphone disconnected. Switched to fallback if available."
            recordEvent(type: "microphoneDisconnected", payload: ["device": device.localizedName])
        }

        if device.hasMediaType(.video), device.uniqueID == selectedCameraID {
            refreshCameras()
            errorMessage = "Selected camera disconnected. Switched to fallback if available."
            recordEvent(type: "cameraDisconnected", payload: ["device": device.localizedName])
        }
    }

    private func validateSelectedSourceDuringSession() {
        guard case .recording = state else { return }

        if selectedSource() == nil {
            errorMessage = "Selected capture source became unavailable. Stopping recording."
            recordEvent(type: "captureSourceUnavailable")
            Task { await stopRecording() }
        }
    }

    private func recordEvent(type: String, payload: [String: String]? = nil) {
        sessionEvents.append(
            RecordingEvent(timestamp: elapsedSeconds, type: type, payload: payload)
        )
    }

    private func persistMetadata(for outputURL: URL) {
        guard let startedAt = recordingStartedAt else { return }

        let metadata = RecordingMetadata(
            outputPath: outputURL.path,
            startedAt: startedAt,
            endedAt: Date(),
            qualityPreset: qualityPreset.rawValue,
            sourceID: selectedSourceID,
            systemAudioEnabled: shouldCaptureSystemAudio,
            microphoneID: selectedMicrophoneID,
            cameraEnabled: isCameraEnabled,
            cameraID: selectedCameraID,
            cameraBackgroundMode: cameraBackgroundMode.rawValue,
            events: sessionEvents,
            diagnostics: buildDiagnosticsReport()
        )

        let metadataURL = outputURL.deletingPathExtension().appendingPathExtension("json")

        do {
            let data = try JSONEncoder.prettyPrinted.encode(metadata)
            try data.write(to: metadataURL, options: .atomic)

            let bundleURL = try RecordingProjectWriter.writeProjectBundle(for: outputURL, metadata: metadata)
            lastProjectBundleURL = bundleURL
        } catch {
            ScreenlyLogger.encoder.error("Failed writing metadata: \(error.localizedDescription)")
        }
    }

    private func diagnosticsReportURL(for outputURL: URL) -> URL {
        outputURL.deletingPathExtension().appendingPathExtension("json")
    }

    func applySafePerformanceMode() {
        qualityPreset = .standard

        if isCameraEnabled {
            cameraBackgroundMode = .normal
        }

        diagnosticsWarningMessage = "Safe mode applied: Standard quality and lighter effects."
        diagnosticsWarningSeverity = .warning
        recordEvent(type: "safeModeApplied")
    }

    private func applyAutoSafeModeIfNeeded() {
        guard autoSafeModeEnabled,
              !hasAutoAppliedSafeModeForSession,
              case .recording = state else {
            return
        }

        guard diagnosticsWarningSeverity == .critical else {
            criticalWarningSince = nil
            return
        }

        if criticalWarningSince == nil {
            criticalWarningSince = Date()
            return
        }

        guard let criticalWarningSince,
              Date().timeIntervalSince(criticalWarningSince) >= 3 else {
            return
        }

        hasAutoAppliedSafeModeForSession = true
        applySafePerformanceMode()
        diagnosticsWarningMessage = "Auto safe mode applied after sustained critical load."
        diagnosticsWarningSeverity = .warning
        recordEvent(type: "autoSafeModeApplied")
    }

    private func evaluateDiagnosticsWarning() {
        switch state {
        case .recording, .paused:
            break
        default:
            diagnosticsWarningSeverity = .none
            diagnosticsWarningMessage = nil
            criticalWarningSince = nil
            return
        }

        let recentDropAvg = recentAverage(of: diagnosticsDropTrend, samples: 10)
        let recentDriftAvg = recentAverage(of: diagnosticsDriftTrend.map(abs), samples: 10)

        let highDrift = abs(diagnostics.avSyncOffsetMs) > 180 || recentDriftAvg > 140
        let severeDrops = diagnostics.droppedScreenFrames > 120 || diagnostics.encoderBackpressureDrops > 80 || recentDropAvg > 90
        let moderateDrops = diagnostics.droppedScreenFrames > 40 || diagnostics.encoderBackpressureDrops > 25 || recentDropAvg > 30

        if severeDrops || highDrift {
            diagnosticsWarningSeverity = .critical
            diagnosticsWarningMessage = "Recording under heavy load. Consider safe mode to reduce dropped frames or sync drift."
            applyAutoSafeModeIfNeeded()
            return
        }

        if moderateDrops {
            diagnosticsWarningSeverity = .warning
            diagnosticsWarningMessage = "Performance pressure detected. You may see frame drops."
            criticalWarningSince = nil
            return
        }

        diagnosticsWarningSeverity = .none
        diagnosticsWarningMessage = nil
        criticalWarningSince = nil
    }

    private func updateSaveDirectoryDisplayPath() {
        if let custom = settingsStore.saveDirectoryURL?.path {
            saveDirectoryPath = custom
        } else {
            saveDirectoryPath = (try? RecordingFileStore.defaultDirectory().path) ?? "~/Movies/Screenly"
        }
    }

    private func appendDiagnosticsTrend(_ diagnostics: RecordingDiagnostics) {
        diagnosticsDropTrend.append(Double(diagnostics.droppedScreenFrames + diagnostics.encoderBackpressureDrops))
        diagnosticsDriftTrend.append(diagnostics.avSyncOffsetMs)

        if diagnosticsDropTrend.count > diagnosticsTrendLimit {
            diagnosticsDropTrend.removeFirst(diagnosticsDropTrend.count - diagnosticsTrendLimit)
        }

        if diagnosticsDriftTrend.count > diagnosticsTrendLimit {
            diagnosticsDriftTrend.removeFirst(diagnosticsDriftTrend.count - diagnosticsTrendLimit)
        }
    }

    private func recentAverage(of values: [Double], samples: Int) -> Double {
        guard !values.isEmpty else { return 0 }
        let slice = values.suffix(samples)
        let total = slice.reduce(0, +)
        return total / Double(slice.count)
    }

    private func userFacingErrorMessage(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription,
           !localized.isEmpty,
           localized != "The operation could not be completed." {
            return localized
        }

        let nsError = error as NSError
        if nsError.localizedDescription == "The operation could not be completed." {
            return "Recording failed (\(nsError.domain):\(nsError.code)). Try reducing quality or disabling camera effects."
        }

        return nsError.localizedDescription
    }

    private func buildDiagnosticsReport() -> RecordingDiagnosticsReport {
        let dropTrendSlice = Array(diagnosticsDropTrend.suffix(60))
        let driftTrendSlice = Array(diagnosticsDriftTrend.suffix(60))

        return RecordingDiagnosticsReport(
            droppedScreenFrames: diagnostics.droppedScreenFrames,
            droppedCameraFrames: diagnostics.droppedCameraFrames,
            encoderBackpressureDrops: diagnostics.encoderBackpressureDrops,
            estimatedQueueDepth: diagnostics.estimatedQueueDepth,
            outputBytes: diagnostics.outputBytes,
            avSyncOffsetMs: diagnostics.avSyncOffsetMs,
            warningSeverity: diagnosticsWarningSeverity.rawName,
            warningMessage: diagnosticsWarningMessage,
            autoSafeModeEnabled: autoSafeModeEnabled,
            dropTrend: dropTrendSlice,
            driftTrend: driftTrendSlice
        )
    }
}

enum DiagnosticsWarningSeverity {
    case none
    case warning
    case critical

    var rawName: String {
        switch self {
        case .none:
            return "none"
        case .warning:
            return "warning"
        case .critical:
            return "critical"
        }
    }
}
