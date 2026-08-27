import AppKit
import AVFoundation
import SwiftUI

struct MainDashboardView: View {
    @ObservedObject var coordinator: RecordingCoordinator

    @State private var isShowingSettings = false
    @State private var recordings: [URL] = []
    @State private var pendingDeleteURL: URL?
    @State private var showQuickSettings = true

    var body: some View {
        ZStack {
            texturedBackground

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                if case .countdown = coordinator.state,
                   let remaining = coordinator.countdownRemaining {
                    countdownBanner(remaining: remaining)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)
                }

                if let message = coordinator.errorMessage {
                    errorBanner(message)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)
                }

                actionRow
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)

                quickSettingsSection
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)

                Divider().overlay(Color.white.opacity(0.08))

                recordingsArea
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                Spacer(minLength: 0)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheetView(coordinator: coordinator)
        }
        .task {
            await coordinator.refreshSources()
            reloadRecordings()
        }
        .onReceive(coordinator.$lastOutputURL) { _ in
            reloadRecordings()
        }
        .onReceive(coordinator.$state) { state in
            if case .completed = state {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    reloadRecordings()
                }
            }
        }
        .alert("Delete Recording Permanently?", isPresented: Binding(
            get: { pendingDeleteURL != nil },
            set: { if !$0 { pendingDeleteURL = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDeleteURL {
                    coordinator.deleteRecording(at: pendingDeleteURL)
                    reloadRecordings()
                }
                self.pendingDeleteURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteURL = nil
            }
        } message: {
            Text("This will permanently delete the video and related project files.")
        }
    }

    private func countdownBanner(remaining: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .foregroundStyle(.white)
            Text("Recording starts in \(remaining)…")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.blue.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.blue.opacity(0.4), lineWidth: 1)
        )
    }

    private var texturedBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.96), Color.gray.opacity(0.28), Color.black.opacity(0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.white.opacity(0.06), Color.clear],
                center: .top,
                startRadius: 40,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 7) {
                Circle().fill(Color.red.opacity(0.9)).frame(width: 11, height: 11)
                Circle().fill(Color.orange.opacity(0.9)).frame(width: 11, height: 11)
                Circle().fill(Color.green.opacity(0.9)).frame(width: 11, height: 11)
            }
            .padding(.horizontal, 10)

            Spacer()

            Text("Framecast")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))

            Spacer()

            HStack(spacing: 10) {
                if case .recording = coordinator.state {
                    Label("REC", systemImage: "record.circle.fill")
                        .font(.headline.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.95), in: Capsule())
                        .foregroundStyle(.white)
                } else if case .paused = coordinator.state {
                    Label("PAUSED", systemImage: "pause.circle.fill")
                        .font(.headline.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.yellow.opacity(0.92), in: Capsule())
                        .foregroundStyle(.black)
                }

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            actionTile(icon: "video.fill", title: "Record Screen") {
                Task { await coordinator.startRecording() }
            }

            actionTile(icon: "web.camera.fill", title: "Record Webcam") {
                if !coordinator.isCameraEnabled {
                    coordinator.toggleCameraEnabled()
                }
                Task { await coordinator.startRecording() }
            }

            actionTile(icon: "mic.fill", title: "Record Audio") {
                if coordinator.isCameraEnabled {
                    coordinator.toggleCameraEnabled()
                }
                Task { await coordinator.startRecording() }
            }
        }
    }

    private var quickSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Quick Settings", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                Button(showQuickSettings ? "Hide" : "Show") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showQuickSettings.toggle()
                    }
                }
                .buttonStyle(.bordered)

                Button("Refresh Devices") {
                    Task { await coordinator.refreshSources() }
                }
                .buttonStyle(.bordered)
            }

            if showQuickSettings {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        quickField(title: "Screen") {
                            Picker("Screen", selection: $coordinator.selectedSourceID) {
                                ForEach(coordinator.availableSources) { source in
                                    Text(sourceLabel(source)).tag(Optional(source.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        quickField(title: "Microphone") {
                            Picker("Microphone", selection: selectedMicrophoneBinding) {
                                ForEach(coordinator.microphoneDevices) { microphone in
                                    Text(microphoneLabel(microphone)).tag(Optional(microphone.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        quickField(title: "Camera") {
                            Picker("Camera", selection: selectedCameraBinding) {
                                Text("Off").tag(Optional<String>.none)
                                ForEach(coordinator.cameraDevices) { camera in
                                    Text(camera.name).tag(Optional(camera.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }

                    HStack(spacing: 10) {
                        quickField(title: "Quality") {
                            Picker("Quality", selection: $coordinator.qualityPreset) {
                                ForEach(QualityPreset.allCases) { preset in
                                    Text(preset.title).tag(preset)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        quickField(title: "Toggles") {
                            HStack(spacing: 10) {
                                Toggle("System Audio", isOn: $coordinator.isSystemAudioEnabled)
                                    .toggleStyle(.switch)
                                Toggle("Camera", isOn: cameraEnabledBinding)
                                    .toggleStyle(.switch)
                                Toggle("Mute Mic", isOn: microphoneMutedBinding)
                                    .toggleStyle(.switch)
                            }
                        }
                    }

                    if coordinator.isCameraEnabled {
                        HStack(spacing: 10) {
                            quickField(title: "Background") {
                                Picker("Background", selection: $coordinator.cameraBackgroundMode) {
                                    ForEach(CameraBackgroundMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }

                            if coordinator.cameraBackgroundMode == .blur {
                                quickField(title: "Blur") {
                                    Picker("Blur", selection: $coordinator.cameraBlurStrength) {
                                        ForEach(CameraBlurStrength.allCases) { strength in
                                            Text(strength.title).tag(strength)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .labelsHidden()
                                }
                            }

                            if coordinator.cameraBackgroundMode == .replace {
                                quickField(title: "Replacement") {
                                    HStack(spacing: 8) {
                                        Button("Choose Image") {
                                            coordinator.chooseCameraReplacementImage()
                                        }
                                        .buttonStyle(.bordered)

                                        Text(coordinator.cameraReplacementImageURL?.lastPathComponent ?? "No image")
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func quickField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func actionTile(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Text(title)
                    .font(.system(size: 35, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.94))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 145)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("Recording Issue")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))

                HStack(spacing: 12) {
                    Button("Refresh Sources") {
                        Task { await coordinator.refreshSources() }
                    }
                    .buttonStyle(.bordered)

                    Button("Open Settings") {
                        isShowingSettings = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var recordingsArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            if recordings.isEmpty {
                VStack(spacing: 14) {
                    Spacer(minLength: 70)
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 96, weight: .light))
                        .foregroundStyle(.white.opacity(0.16))
                    Text("No Videos")
                        .font(.system(size: 36, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.36))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(recordings.prefix(6)), id: \.self) { recordingURL in
                        recordingRow(for: recordingURL, isNewest: recordingURL == recordings.first)
                    }
                }
            }
        }
    }

    private func recordingRow(for recordingURL: URL, isNewest: Bool) -> some View {
        HStack(spacing: 14) {
            RecordingThumbnailView(url: recordingURL)
                .frame(width: 180, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if isNewest {
                        Text("NEW")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.95), in: Capsule())
                            .foregroundStyle(.black)
                    }

                    Text(recordingURL.deletingPathExtension().lastPathComponent)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.95))
                }

                Text(recordingMeta(for: recordingURL))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.56))

                HStack(spacing: 12) {
                    rowIconButton("play.fill") { coordinator.openFile(at: recordingURL) }
                    rowIconButton("folder") { coordinator.revealFile(at: recordingURL) }
                    rowIconButton("trash") {
                        pendingDeleteURL = recordingURL
                    }
                    rowIconButton("square.and.arrow.up") {
                        NSWorkspace.shared.activateFileViewerSelecting([recordingURL])
                    }
                }
            }

            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func rowIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sourceLabel(_ source: ScreenCaptureSource) -> String {
        var label = source.name
        if let details = source.details, !details.isEmpty {
            label += " — \(details)"
        }
        if let width = source.width, let height = source.height {
            label += " (\(width)x\(height))"
        }
        return label
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

    private var microphoneMutedBinding: Binding<Bool> {
        Binding {
            coordinator.isMicrophoneMuted
        } set: { newValue in
            if newValue != coordinator.isMicrophoneMuted {
                coordinator.toggleMicrophoneMuted()
            }
        }
    }

    private func recordingMeta(for url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs?[.size] as? Int64 ?? 0
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let sizeString = formatter.string(fromByteCount: size)
        let type = url.pathExtension.uppercased()
        return "\(sizeString) | \(type)"
    }

    private func reloadRecordings() {
        var discovered = coordinator.availableRecordingFiles()

        if let latest = coordinator.lastOutputURL,
           FileManager.default.fileExists(atPath: latest.path),
           !discovered.contains(latest) {
            discovered.append(latest)
        }

        recordings = discovered.sorted(by: { lhs, rhs in
            let leftDate = (try? FileManager.default.attributesOfItem(atPath: lhs.path)[.modificationDate] as? Date) ?? .distantPast
            let rightDate = (try? FileManager.default.attributesOfItem(atPath: rhs.path)[.modificationDate] as? Date) ?? .distantPast
            return leftDate > rightDate
        })
    }
}

private struct RecordingThumbnailView: View {
    let url: URL

    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.07)
                    Image(systemName: "video")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .task(id: url) {
            thumbnail = await generateThumbnail(for: url)
        }
    }

    private func generateThumbnail(for url: URL) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 0.5, preferredTimescale: 600)
                guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: NSImage(cgImage: cgImage, size: .zero))
            }
        }
    }
}
