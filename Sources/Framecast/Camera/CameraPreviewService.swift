import AppKit
import AVFoundation
import CoreImage
import Foundation
import Vision

final class CameraPreviewService: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var previewImage: NSImage?

    private var currentInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let outputQueue = DispatchQueue(label: "com.framecast.camera.preview.output", qos: .userInitiated)
    private let configQueue = DispatchQueue(label: "com.framecast.camera.preview.config", qos: .userInitiated)

    private let ciContext = CIContext()
    private let segmentationRequest = VNGeneratePersonSegmentationRequest()

    private struct EffectConfig {
        var backgroundMode: CameraBackgroundMode = .normal
        var blurStrength: CameraBlurStrength = .medium
        var shape: CameraShape = .circle
        var mirror = true
        var replacementImageURL: URL?
        var replacementImage: CIImage?
    }

    private var effectConfig = EffectConfig()
    private var frameIndex = 0
    private var cachedMask: CIImage?
    private var maskUpdateInterval = 3

    override init() {
        super.init()
        segmentationRequest.qualityLevel = .balanced
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func updateEffects(
        backgroundMode: CameraBackgroundMode,
        blurStrength: CameraBlurStrength,
        shape: CameraShape,
        mirror: Bool,
        replacementImageURL: URL?
    ) {
        configQueue.async { [weak self] in
            guard let self else { return }

            self.effectConfig.backgroundMode = backgroundMode
            self.effectConfig.blurStrength = blurStrength
            self.effectConfig.shape = shape
            self.effectConfig.mirror = mirror

            if self.effectConfig.replacementImageURL != replacementImageURL {
                self.effectConfig.replacementImageURL = replacementImageURL
                if let replacementImageURL,
                   let image = CIImage(contentsOf: replacementImageURL) {
                    self.effectConfig.replacementImage = image
                } else {
                    self.effectConfig.replacementImage = nil
                }
            }
        }
    }

    func start(device: AVCaptureDevice) throws {
        stop()

        session.beginConfiguration()
        session.sessionPreset = .high

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw RecordingError.cameraUnavailable
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.alwaysDiscardsLateVideoFrames = true

        guard session.canAddOutput(output) else {
            throw RecordingError.cameraUnavailable
        }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: outputQueue)

        currentInput = input
        videoOutput = output

        frameIndex = 0
        cachedMask = nil
        maskUpdateInterval = 3

        session.commitConfiguration()
        session.startRunning()
    }

    func stop() {
        session.beginConfiguration()

        if let output = videoOutput {
            output.setSampleBufferDelegate(nil, queue: nil)
            session.removeOutput(output)
            videoOutput = nil
        }

        if let input = currentInput {
            session.removeInput(input)
            currentInput = nil
        }

        session.commitConfiguration()

        if session.isRunning {
            session.stopRunning()
        }

        frameIndex = 0
        cachedMask = nil

        DispatchQueue.main.async { [weak self] in
            self?.previewImage = nil
        }
    }
}

extension CameraPreviewService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let start = CFAbsoluteTimeGetCurrent()

        let config: EffectConfig = configQueue.sync { effectConfig }

        frameIndex += 1
        if frameIndex % 2 != 0 {
            return
        }

        var image = CIImage(cvPixelBuffer: pixelBuffer)

        if config.mirror {
            image = image.transformed(
                by: .identity
                    .translatedBy(x: image.extent.width, y: 0)
                    .scaledBy(x: -1, y: 1)
            )
        }

        image = applyBackgroundMode(image, config: config)
        image = applyShapeMask(image, shape: config.shape)

        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            return
        }

        let outputImage = NSImage(cgImage: cgImage, size: .zero)

        DispatchQueue.main.async { [weak self] in
            self?.previewImage = outputImage
        }

        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if elapsedMs > 20 {
            maskUpdateInterval = min(maskUpdateInterval + 1, 6)
        } else if elapsedMs < 10 {
            maskUpdateInterval = max(maskUpdateInterval - 1, 2)
        }
    }

    private func applyBackgroundMode(_ image: CIImage, config: EffectConfig) -> CIImage {
        switch config.backgroundMode {
        case .normal:
            return image

        case .blur:
            let radius: Double
            switch config.blurStrength {
            case .light: radius = 8
            case .medium: radius = 14
            case .strong: radius = 22
            }

            let blurred = image
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: image.extent)

            guard let mask = currentMask(for: image) else {
                return image
            }

            return image.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: blurred,
                kCIInputMaskImageKey: mask
            ])

        case .replace:
            guard let mask = currentMask(for: image),
                  let replacementImage = config.replacementImage else {
                return image
            }

            let background = aspectFill(image: replacementImage, into: image.extent)
            return image.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: background,
                kCIInputMaskImageKey: mask
            ])
        }
    }

    private func applyShapeMask(_ image: CIImage, shape: CameraShape) -> CIImage {
        let extent = image.extent

        switch shape {
        case .rectangle:
            return image

        case .roundedRectangle:
            let inset = min(extent.width, extent.height) * 0.02
            let rect = extent.insetBy(dx: inset, dy: inset)
            let radius = min(rect.width, rect.height) * 0.12

            guard let mask = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
                "inputExtent": CIVector(cgRect: rect),
                "inputRadius": radius,
                "inputColor": CIColor(red: 1, green: 1, blue: 1, alpha: 1)
            ])?.outputImage?.cropped(to: extent) else {
                return image
            }

            return image.applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputMaskImageKey: mask
            ])

        case .circle:
            let radius = min(extent.width, extent.height) / 2
            guard let mask = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: extent.midX, y: extent.midY),
                "inputRadius0": radius,
                "inputRadius1": radius + 1,
                "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
                "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)
            ])?.outputImage?.cropped(to: extent) else {
                return image
            }

            return image.applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputMaskImageKey: mask
            ])
        }
    }

    private func currentMask(for image: CIImage) -> CIImage? {
        if frameIndex % maskUpdateInterval == 0 || cachedMask == nil {
            cachedMask = personMask(for: image)
        }
        return cachedMask
    }

    private func personMask(for image: CIImage) -> CIImage? {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        do {
            try handler.perform([segmentationRequest])
            guard let observation = segmentationRequest.results?.first else {
                return nil
            }

            let rawMask = CIImage(cvPixelBuffer: observation.pixelBuffer)
            let extent = rawMask.extent
            guard extent.width > 0, extent.height > 0 else {
                return nil
            }

            let scaleX = image.extent.width / extent.width
            let scaleY = image.extent.height / extent.height

            return rawMask
                .transformed(by: .identity.scaledBy(x: scaleX, y: scaleY))
                .applyingFilter("CIMedianFilter")
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2.0])
                .cropped(to: image.extent)
        } catch {
            return nil
        }
    }

    private func aspectFill(image: CIImage, into destination: CGRect) -> CIImage {
        let scaleX = destination.width / image.extent.width
        let scaleY = destination.height / image.extent.height
        let scale = max(scaleX, scaleY)

        let scaled = image.transformed(by: .identity.scaledBy(x: scale, y: scale))
        let x = destination.midX - scaled.extent.width / 2
        let y = destination.midY - scaled.extent.height / 2

        return scaled
            .transformed(by: .identity.translatedBy(x: x - scaled.extent.minX, y: y - scaled.extent.minY))
            .cropped(to: destination)
    }
}
