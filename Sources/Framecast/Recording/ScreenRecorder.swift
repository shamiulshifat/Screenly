import AppKit
import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import ScreenCaptureKit
import Vision

final class ScreenRecorder: NSObject {
    private struct ControlState {
        var isPaused = false
        var awaitingResumeCompensation = false
        var pauseStartPTS: CMTime?
        var totalPausedDuration: CMTime = .zero
        var latestPTS: CMTime?
        var microphoneMuted = false
    }

    private struct MetricsState {
        var droppedScreenFrames = 0
        var droppedCameraFrames = 0
        var encoderBackpressureDrops = 0
        var queueDepthEstimate = 0
        var lastVideoPTS: CMTime?
        var lastAudioPTS: CMTime?
        var lastEmitUptime: TimeInterval = 0
    }

    private let sampleQueue = DispatchQueue(label: "com.framecast.capture.samples", qos: .userInitiated)
    private let controlQueue = DispatchQueue(label: "com.framecast.capture.control", qos: .userInitiated)

    private var controlState = ControlState()
    private var metricsState = MetricsState()

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var videoAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneAudioInput: AVAssetWriterInput?
    private var firstFramePTS: CMTime?

    private(set) var outputURL: URL?
    var onDiagnosticsUpdate: ((RecordingDiagnostics) -> Void)?
    var onCameraPreviewFrame: ((NSImage?) -> Void)?

    private let cameraFrameProvider = CameraFrameProvider()
    private let ciContext = CIContext()
    private let segmentationRequest = VNGeneratePersonSegmentationRequest()

    private var cameraOverlayConfig: CameraOverlayConfiguration?
    private var replacementBackgroundImage: CIImage?
    private var activeCameraDeviceID: String?
    private var frameIndex: Int = 0
    private var cachedPersonMask: CIImage?
    private var lastPreviewFrameEmitUptime: TimeInterval = 0
    private var appendedVideoFrameCount: Int = 0

    override init() {
        super.init()
        segmentationRequest.qualityLevel = .fast
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func start(
        source: ScreenCaptureSource,
        allDisplays: [SCDisplay],
        allWindows: [SCWindow],
        excludingApplications: [SCRunningApplication],
        excludingWindows: [SCWindow],
        selectedMicrophoneID: String?,
        includeSystemAudio: Bool,
        qualityPreset: QualityPreset,
        cameraOverlay: CameraOverlayConfiguration,
        saveDirectoryURL: URL?,
        captureRegion: CaptureRegion?
    ) async throws {
        let outputURL = try RecordingFileStore.nextRecordingURL(fileExtension: "mov", preferredDirectory: saveDirectoryURL)
        let (width, height) = streamSize(for: source, fallbackDisplays: allDisplays)
        let encodedWidth = max(320, width - (width % 2))
        let encodedHeight = max(240, height - (height % 2))

        let configuration = SCStreamConfiguration()
        configuration.width = encodedWidth
        configuration.height = encodedHeight
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(qualityPreset.targetFPS))
        configuration.queueDepth = 8
        configuration.showsCursor = true
        configuration.capturesAudio = includeSystemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        if #available(macOS 15.0, *), let selectedMicrophoneID {
            configuration.captureMicrophone = true
            configuration.microphoneCaptureDeviceID = selectedMicrophoneID
        }

        if let captureRegion,
           case .display(let display) = source.target {
            let normalizedWidth = min(max(captureRegion.width, 0.1), 1.0)
            let normalizedHeight = min(max(captureRegion.height, 0.1), 1.0)
            let centerX = min(max(captureRegion.x, 0.05), 0.95)
            let centerY = min(max(captureRegion.y, 0.05), 0.95)

            let regionWidth = CGFloat(display.width) * normalizedWidth
            let regionHeight = CGFloat(display.height) * normalizedHeight
            let originX = CGFloat(display.width) * CGFloat(centerX) - regionWidth / 2
            let originY = CGFloat(display.height) * CGFloat(centerY) - regionHeight / 2

            configuration.sourceRect = CGRect(
                x: max(0, min(originX, CGFloat(display.width) - regionWidth)),
                y: max(0, min(originY, CGFloat(display.height) - regionHeight)),
                width: regionWidth,
                height: regionHeight
            )
        }

        let filter = try buildFilter(
            source: source,
            allDisplays: allDisplays,
            allWindows: allWindows,
            excludingApplications: excludingApplications,
            excludingWindows: excludingWindows
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: encodedWidth,
            AVVideoHeightKey: encodedHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(
                    Double(estimateBitrate(width: encodedWidth, height: encodedHeight, fps: qualityPreset.targetFPS))
                    * qualityPreset.bitrateMultiplier
                ),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
                AVVideoAllowFrameReorderingKey: false
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw RecordingError.writerInitializationFailed
        }
        writer.add(input)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: encodedWidth,
                kCVPixelBufferHeightKey as String: encodedHeight,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )

        var systemAudioInput: AVAssetWriterInput?
        if includeSystemAudio {
            let systemAudioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 192_000
            ]

            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: systemAudioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                systemAudioInput = input
            }
        }

        var microphoneAudioInput: AVAssetWriterInput?
        if #available(macOS 15.0, *), selectedMicrophoneID != nil {
            let microphoneAudioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 96_000
            ]

            let micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: microphoneAudioSettings)
            micInput.expectsMediaDataInRealTime = true
            if writer.canAdd(micInput) {
                writer.add(micInput)
                microphoneAudioInput = micInput
            }
        }

        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            if includeSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            }
            if #available(macOS 15.0, *), selectedMicrophoneID != nil {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)
            }
        } catch {
            FramecastLogger.capture.error("Failed to add stream output: \(error.localizedDescription)")
            throw RecordingError.streamStartFailed
        }

        guard writer.startWriting() else {
            cleanupOutputArtifact(at: outputURL)
            throw RecordingError.writerStartFailed
        }

        cameraOverlayConfig = cameraOverlay
        updateReplacementImage(for: cameraOverlay)
        try updateCameraProvider(for: cameraOverlay)

        do {
            try await stream.startCapture()
        } catch {
            writer.cancelWriting()
            cameraFrameProvider.stop()
            cleanupOutputArtifact(at: outputURL)
            throw RecordingError.streamStartFailed
        }

        controlQueue.sync {
            controlState = ControlState()
            metricsState = MetricsState()
        }

        firstFramePTS = nil
        self.stream = stream
        self.writer = writer
        videoInput = input
        videoAdaptor = adaptor
        self.systemAudioInput = systemAudioInput
        self.microphoneAudioInput = microphoneAudioInput
        self.outputURL = outputURL
        appendedVideoFrameCount = 0

        FramecastLogger.capture.info("Recording started to \(outputURL.path)")
        emitDiagnostics(force: true)
    }

    func updateCameraOverlay(_ overlay: CameraOverlayConfiguration) {
        cameraOverlayConfig = overlay
        updateReplacementImage(for: overlay)

        do {
            try updateCameraProvider(for: overlay)
        } catch {
            FramecastLogger.capture.error("Unable to update camera overlay: \(error.localizedDescription)")
        }
    }

    func pause() {
        controlQueue.sync {
            guard !controlState.isPaused else { return }
            controlState.isPaused = true
            controlState.pauseStartPTS = controlState.latestPTS ?? firstFramePTS
            controlState.awaitingResumeCompensation = false
        }
    }

    func resume() {
        controlQueue.sync {
            guard controlState.isPaused else { return }
            controlState.isPaused = false
            controlState.awaitingResumeCompensation = true
            if controlState.pauseStartPTS == nil {
                controlState.pauseStartPTS = controlState.latestPTS
            }
        }
    }

    func setMicrophoneMuted(_ muted: Bool) {
        controlQueue.sync {
            controlState.microphoneMuted = muted
        }
    }

    func stop() async throws -> URL {
        guard let stream,
              let writer,
              let videoInput,
              let outputURL else {
            throw RecordingError.streamStopFailed
        }

        do {
            try await stream.stopCapture()
        } catch {
            FramecastLogger.capture.error("Failed stopping SCStream: \(error.localizedDescription)")
            throw RecordingError.streamStopFailed
        }

        videoInput.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneAudioInput?.markAsFinished()

        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        cameraFrameProvider.stop()

        if writer.status == .failed {
            let details = writer.error?.localizedDescription ?? "unknown"
            FramecastLogger.encoder.error("AssetWriter failed: \(details)")
            cleanupOutputArtifact(at: outputURL)
            if let writerError = writer.error {
                throw writerError
            }
            throw RecordingError.recordingWriteFailed
        }

        let finalSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
        if self.appendedVideoFrameCount == 0 || finalSize <= 1024 {
            FramecastLogger.encoder.error("Output appears invalid (frames=\(self.appendedVideoFrameCount), bytes=\(finalSize))")
            self.cleanupOutputArtifact(at: outputURL)
            throw RecordingError.recordingWriteFailed
        }

        let finalizedURL = try await mixAudioTracksIfNeeded(recordingURL: outputURL)

        emitDiagnostics(force: true)

        resetSessionState()
        FramecastLogger.encoder.info("Recording finalized at \(finalizedURL.path)")
        return finalizedURL
    }

    private func adjustedSampleBuffer(_ sampleBuffer: CMSampleBuffer, subtracting timeOffset: CMTime) -> CMSampleBuffer? {
        guard timeOffset > .zero else {
            return sampleBuffer
        }

        var sampleTimingCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &sampleTimingCount
        ) == noErr else {
            return sampleBuffer
        }

        var timingInfo = Array(repeating: CMSampleTimingInfo(), count: sampleTimingCount)
        guard CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: sampleTimingCount,
            arrayToFill: &timingInfo,
            entriesNeededOut: &sampleTimingCount
        ) == noErr else {
            return sampleBuffer
        }

        for index in 0..<timingInfo.count {
            timingInfo[index].presentationTimeStamp = timingInfo[index].presentationTimeStamp - timeOffset
            if timingInfo[index].decodeTimeStamp.isValid {
                timingInfo[index].decodeTimeStamp = timingInfo[index].decodeTimeStamp - timeOffset
            }
        }

        var adjusted: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timingInfo.count,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &adjusted
        )

        return status == noErr ? adjusted : sampleBuffer
    }

    private func compensationState(for sampleBuffer: CMSampleBuffer) -> (drop: Bool, offset: CMTime) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        return controlQueue.sync {
            controlState.latestPTS = pts

            if controlState.isPaused {
                return (true, controlState.totalPausedDuration)
            }

            if controlState.awaitingResumeCompensation,
               let pauseStartPTS = controlState.pauseStartPTS {
                let pausedDuration = pts - pauseStartPTS
                if pausedDuration > .zero {
                    controlState.totalPausedDuration = controlState.totalPausedDuration + pausedDuration
                }
                controlState.awaitingResumeCompensation = false
                controlState.pauseStartPTS = nil
            }

            return (false, controlState.totalPausedDuration)
        }
    }

    private func composeOutputBuffer(from screenBuffer: CVPixelBuffer, at presentationTime: CMTime) -> CVPixelBuffer? {
        guard let adaptor = videoAdaptor,
              let pool = adaptor.pixelBufferPool else {
            return nil
        }

        var maybeOutput: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeOutput)
        guard status == kCVReturnSuccess,
              let outputBuffer = maybeOutput else {
            return nil
        }

        var finalImage = CIImage(cvPixelBuffer: screenBuffer)
        frameIndex += 1

        if let cameraOverlayConfig,
           cameraOverlayConfig.isEnabled,
           let cameraBuffer = cameraFrameProvider.currentFrame(),
           let cameraImage = processedCameraImage(from: cameraBuffer, config: cameraOverlayConfig, on: finalImage.extent) {
            finalImage = cameraImage.composited(over: finalImage)
        } else if cameraOverlayConfig?.isEnabled == true {
            controlQueue.sync {
                metricsState.droppedCameraFrames += 1
            }
        }

        ciContext.render(finalImage, to: outputBuffer)
        return outputBuffer
    }

    private func processedCameraImage(
        from cameraBuffer: CVPixelBuffer,
        config: CameraOverlayConfiguration,
        on screenExtent: CGRect
    ) -> CIImage? {
        var cameraImage = CIImage(cvPixelBuffer: cameraBuffer)

        if config.mirror {
            cameraImage = cameraImage.transformed(
                by: .identity
                    .translatedBy(x: cameraImage.extent.width, y: 0)
                    .scaledBy(x: -1, y: 1)
            )
        }

        cameraImage = applyBackgroundMode(cameraImage, config: config)
        cameraImage = applyShapeMask(cameraImage, shape: config.shape)
        emitCameraPreviewFrame(from: cameraImage)

        let overlayWidth = max(screenExtent.width * config.layout.width, 120)
        let scale = overlayWidth / cameraImage.extent.width
        let overlayHeight = cameraImage.extent.height * scale

        let centerX = screenExtent.width * config.layout.x
        let centerYFromTop = screenExtent.height * config.layout.y
        let originX = centerX - overlayWidth / 2
        let originY = screenExtent.height - centerYFromTop - overlayHeight / 2

        return cameraImage
            .transformed(by: .identity.scaledBy(x: scale, y: scale))
            .transformed(by: .identity.translatedBy(x: originX, y: originY))
    }

    private func applyBackgroundMode(_ cameraImage: CIImage, config: CameraOverlayConfiguration) -> CIImage {
        switch config.backgroundMode {
        case .normal:
            return cameraImage

        case .blur:
            let radius: Double
            switch config.blurStrength {
            case .light: radius = 8
            case .medium: radius = 16
            case .strong: radius = 24
            }

            let blurred = cameraImage
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: cameraImage.extent)

            guard let personMask = currentPersonMask(for: cameraImage) else {
                return blurred
            }

            return cameraImage.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: blurred,
                kCIInputMaskImageKey: personMask
            ])

        case .replace:
            guard let personMask = currentPersonMask(for: cameraImage),
                  let replacement = replacementBackgroundImage else {
                return cameraImage
            }

            let fittedBackground = aspectFill(image: replacement, into: cameraImage.extent)
            return cameraImage.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: fittedBackground,
                kCIInputMaskImageKey: personMask
            ])
        }
    }

    private func applyShapeMask(_ image: CIImage, shape: CameraShape) -> CIImage {
        switch shape {
        case .rectangle:
            return image
        case .roundedRectangle:
            return image
        case .circle:
            let extent = image.extent
            let radius = min(extent.width, extent.height) / 2
            guard let maskImage = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: extent.midX, y: extent.midY),
                "inputRadius0": radius,
                "inputRadius1": radius + 1,
                "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
                "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)
            ])?.outputImage?.cropped(to: extent) else {
                return image
            }

            return image.applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputMaskImageKey: maskImage
            ])
        }
    }

    private func personMask(for image: CIImage) -> CIImage? {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([segmentationRequest])
            guard let observation = segmentationRequest.results?.first else {
                return nil
            }

            let rawMask = CIImage(cvPixelBuffer: observation.pixelBuffer)
            let maskExtent = rawMask.extent

            guard maskExtent.width > 0, maskExtent.height > 0 else {
                return nil
            }

            let scaleX = image.extent.width / maskExtent.width
            let scaleY = image.extent.height / maskExtent.height

            return rawMask
                .transformed(by: .identity.scaledBy(x: scaleX, y: scaleY))
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.5])
                .cropped(to: image.extent)
        } catch {
            FramecastLogger.capture.debug("Segmentation failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func currentPersonMask(for image: CIImage) -> CIImage? {
        if frameIndex % 3 == 0 || cachedPersonMask == nil {
            cachedPersonMask = personMask(for: image)
        }
        return cachedPersonMask
    }

    private func emitCameraPreviewFrame(from image: CIImage) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPreviewFrameEmitUptime >= 0.12 else {
            return
        }
        lastPreviewFrameEmitUptime = now

        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            return
        }

        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        DispatchQueue.main.async { [weak self] in
            self?.onCameraPreviewFrame?(nsImage)
        }
    }

    private func updateReplacementImage(for overlay: CameraOverlayConfiguration) {
        if let replacementURL = overlay.replacementImageURL,
           let image = CIImage(contentsOf: replacementURL) {
            replacementBackgroundImage = image
        } else {
            replacementBackgroundImage = nil
        }
    }

    private func updateCameraProvider(for overlay: CameraOverlayConfiguration) throws {
        guard overlay.isEnabled,
              let selectedCameraID = overlay.selectedCameraID,
              let cameraDevice = AVCaptureDevice(uniqueID: selectedCameraID) else {
            cameraFrameProvider.stop()
            activeCameraDeviceID = nil
            return
        }

        if activeCameraDeviceID == selectedCameraID,
           cameraFrameProvider.currentFrame() != nil {
            return
        }

        try cameraFrameProvider.start(device: cameraDevice)
        activeCameraDeviceID = selectedCameraID
    }

    private func aspectFill(image: CIImage, into destination: CGRect) -> CIImage {
        let scaleX = destination.width / image.extent.width
        let scaleY = destination.height / image.extent.height
        let scale = max(scaleX, scaleY)

        let scaled = image.transformed(by: .identity.scaledBy(x: scale, y: scale))
        let x = destination.midX - scaled.extent.width / 2
        let y = destination.midY - scaled.extent.height / 2
        return scaled.transformed(by: .identity.translatedBy(x: x - scaled.extent.minX, y: y - scaled.extent.minY))
            .cropped(to: destination)
    }

    private func mixAudioTracksIfNeeded(recordingURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: recordingURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard audioTracks.count > 1 else {
            return recordingURL
        }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            return recordingURL
        }

        let composition = AVMutableComposition()

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return recordingURL
        }

        let assetDuration = try await asset.load(.duration)
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: assetDuration),
            of: videoTrack,
            at: .zero
        )

        let audioMix = AVMutableAudioMix()
        var audioParams: [AVMutableAudioMixInputParameters] = []

        for track in audioTracks {
            guard let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                continue
            }

            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: assetDuration),
                of: track,
                at: .zero
            )

            let params = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
            params.setVolume(1.0, at: .zero)
            audioParams.append(params)
        }

        guard !audioParams.isEmpty,
              let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
              ) else {
            return recordingURL
        }

        audioMix.inputParameters = audioParams

        let mixedURL = recordingURL
            .deletingPathExtension()
            .appendingPathExtension("mixed.mov")

        try? FileManager.default.removeItem(at: mixedURL)

        exportSession.outputURL = mixedURL
        exportSession.outputFileType = .mov
        exportSession.audioMix = audioMix
        exportSession.shouldOptimizeForNetworkUse = false

        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }

        guard exportSession.status == .completed else {
            FramecastLogger.encoder.error("Audio mix export failed: \(exportSession.error?.localizedDescription ?? "unknown")")
            return recordingURL
        }

        do {
            try FileManager.default.removeItem(at: recordingURL)
            try FileManager.default.moveItem(at: mixedURL, to: recordingURL)
        } catch {
            FramecastLogger.encoder.error("Failed replacing mixed output: \(error.localizedDescription)")
            return mixedURL
        }

        return recordingURL
    }

    private func buildFilter(
        source: ScreenCaptureSource,
        allDisplays: [SCDisplay],
        allWindows: [SCWindow],
        excludingApplications: [SCRunningApplication],
        excludingWindows: [SCWindow]
    ) throws -> SCContentFilter {
        switch source.target {
        case .display(let display):
            if excludingApplications.isEmpty && excludingWindows.isEmpty {
                return SCContentFilter(display: display, excludingWindows: [])
            }
            return SCContentFilter(
                display: display,
                excludingApplications: excludingApplications,
                exceptingWindows: excludingWindows
            )

        case .window(let window):
            return SCContentFilter(desktopIndependentWindow: window)

        case .application(let application):
            guard let display = preferredDisplay(
                for: application,
                allDisplays: allDisplays,
                allWindows: allWindows
            ) ?? allDisplays.first else {
                throw RecordingError.screenSourceUnavailable
            }
            return SCContentFilter(
                display: display,
                including: [application],
                exceptingWindows: excludingWindows
            )
        }
    }

    private func preferredDisplay(
        for application: SCRunningApplication,
        allDisplays: [SCDisplay],
        allWindows: [SCWindow]
    ) -> SCDisplay? {
        let appWindows = allWindows.filter { window in
            window.owningApplication?.processID == application.processID && window.isOnScreen
        }

        guard !appWindows.isEmpty else {
            return nil
        }

        return allDisplays.max { lhs, rhs in
            overlapArea(display: lhs, windows: appWindows) < overlapArea(display: rhs, windows: appWindows)
        }
    }

    private func overlapArea(display: SCDisplay, windows: [SCWindow]) -> CGFloat {
        windows.reduce(0) { partialResult, window in
            let intersection = display.frame.intersection(window.frame)
            guard !intersection.isNull, !intersection.isEmpty else {
                return partialResult
            }
            return partialResult + intersection.width * intersection.height
        }
    }

    private func streamSize(for source: ScreenCaptureSource, fallbackDisplays: [SCDisplay]) -> (Int, Int) {
        let defaultWidth = fallbackDisplays.first?.width ?? 1920
        let defaultHeight = fallbackDisplays.first?.height ?? 1080
        let width = max(source.width ?? defaultWidth, 320)
        let height = max(source.height ?? defaultHeight, 240)
        return (width, height)
    }

    private func estimateBitrate(width: Int, height: Int, fps: Int) -> Int {
        let pixelsPerSecond = width * height * fps
        let bitsPerPixel: Double = 0.09
        return Int(Double(pixelsPerSecond) * bitsPerPixel)
    }

    private func resetSessionState() {
        stream = nil
        writer = nil
        videoInput = nil
        videoAdaptor = nil
        systemAudioInput = nil
        microphoneAudioInput = nil
        firstFramePTS = nil
        outputURL = nil
        cameraOverlayConfig = nil
        replacementBackgroundImage = nil
        activeCameraDeviceID = nil
        frameIndex = 0
        cachedPersonMask = nil
        lastPreviewFrameEmitUptime = 0
        appendedVideoFrameCount = 0
        DispatchQueue.main.async { [weak self] in
            self?.onCameraPreviewFrame?(nil)
        }
        cameraFrameProvider.stop()

        controlQueue.sync {
            controlState = ControlState()
            metricsState = MetricsState()
        }
    }

    private func emitDiagnostics(force: Bool = false) {
        guard let outputURL else { return }

        let now = ProcessInfo.processInfo.systemUptime

        let snapshot: MetricsState? = controlQueue.sync {
            if !force, now - metricsState.lastEmitUptime < 0.4 {
                return nil
            }
            metricsState.lastEmitUptime = now
            return metricsState
        }

        guard let snapshot else {
            return
        }

        let outputBytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0

        let avOffsetMs: Double = controlQueue.sync {
            guard let videoPTS = metricsState.lastVideoPTS,
                  let audioPTS = metricsState.lastAudioPTS else {
                return 0
            }
            let delta = CMTimeGetSeconds(videoPTS - audioPTS)
            return delta.isFinite ? delta * 1000 : 0
        }

        let diagnostics = RecordingDiagnostics(
            droppedScreenFrames: snapshot.droppedScreenFrames,
            droppedCameraFrames: snapshot.droppedCameraFrames,
            encoderBackpressureDrops: snapshot.encoderBackpressureDrops,
            estimatedQueueDepth: snapshot.queueDepthEstimate,
            outputBytes: outputBytes,
            avSyncOffsetMs: avOffsetMs
        )

        DispatchQueue.main.async { [weak self] in
            self?.onDiagnosticsUpdate?(diagnostics)
        }
    }

    private func cleanupOutputArtifact(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

extension ScreenRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid,
              let writer,
              writer.status != .failed else {
            return
        }

        let compensation = compensationState(for: sampleBuffer)
        if compensation.drop {
            return
        }

        guard let adjustedBuffer = adjustedSampleBuffer(sampleBuffer, subtracting: compensation.offset) else {
            return
        }

        switch outputType {
        case .screen:
            handleScreenSampleBuffer(adjustedBuffer, writer: writer)
        case .audio:
            handleAudioSampleBuffer(adjustedBuffer, input: systemAudioInput)
        case .microphone:
            let isMuted = controlQueue.sync { controlState.microphoneMuted }
            if isMuted { return }
            handleAudioSampleBuffer(adjustedBuffer, input: microphoneAudioInput)
        @unknown default:
            return
        }
    }

    private func handleScreenSampleBuffer(_ sampleBuffer: CMSampleBuffer, writer: AVAssetWriter) {
        guard let videoInput else { return }

        if firstFramePTS == nil {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            firstFramePTS = pts
            writer.startSession(atSourceTime: pts)
        }

        guard videoInput.isReadyForMoreMediaData else {
            FramecastLogger.encoder.debug("Dropping screen frame: writer input backpressure")
            controlQueue.sync {
                metricsState.droppedScreenFrames += 1
                metricsState.encoderBackpressureDrops += 1
                metricsState.queueDepthEstimate = min(metricsState.queueDepthEstimate + 1, 8)
            }
            emitDiagnostics()
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
           let compositedBuffer = composeOutputBuffer(from: imageBuffer, at: presentationTime),
           let adaptor = videoAdaptor {
            if !adaptor.append(compositedBuffer, withPresentationTime: presentationTime) {
                let writerStatus = writer.status.rawValue
                let writerDetails = writer.error?.localizedDescription ?? "none"
                FramecastLogger.encoder.error("Failed to append composited video frame (writerStatus=\(writerStatus), writerError=\(writerDetails))")
                controlQueue.sync {
                    metricsState.droppedScreenFrames += 1
                }
            }
            controlQueue.sync {
                appendedVideoFrameCount += 1
                metricsState.lastVideoPTS = presentationTime
                metricsState.queueDepthEstimate = max(metricsState.queueDepthEstimate - 1, 0)
            }
            emitDiagnostics()
            return
        }

        if !videoInput.append(sampleBuffer) {
            let writerStatus = writer.status.rawValue
            let writerDetails = writer.error?.localizedDescription ?? "none"
            FramecastLogger.encoder.error("Failed to append video sample (writerStatus=\(writerStatus), writerError=\(writerDetails))")
            controlQueue.sync {
                metricsState.droppedScreenFrames += 1
            }
        } else {
            controlQueue.sync {
                appendedVideoFrameCount += 1
                metricsState.lastVideoPTS = presentationTime
                metricsState.queueDepthEstimate = max(metricsState.queueDepthEstimate - 1, 0)
            }
        }

        emitDiagnostics()
    }

    private func handleAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer, input: AVAssetWriterInput?) {
        guard firstFramePTS != nil,
              let input,
              input.isReadyForMoreMediaData else {
            return
        }

        if !input.append(sampleBuffer) {
            let writerStatus = writer?.status.rawValue ?? -1
            let writerDetails = writer?.error?.localizedDescription ?? "none"
            FramecastLogger.encoder.error("Failed to append audio sample (writerStatus=\(writerStatus), writerError=\(writerDetails))")
        } else {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            controlQueue.sync {
                metricsState.lastAudioPTS = pts
            }
        }

        emitDiagnostics()
    }
}
