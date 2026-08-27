import AVFoundation
import CoreVideo
import Foundation

final class CameraFrameProvider: NSObject {
    private let queue = DispatchQueue(label: "com.screenly.camera.frames", qos: .userInitiated)

    private let lock = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?

    private var session: AVCaptureSession?
    private var input: AVCaptureDeviceInput?
    private var output: AVCaptureVideoDataOutput?

    func start(device: AVCaptureDevice) throws {
        stop()

        let session = AVCaptureSession()
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
        output.setSampleBufferDelegate(self, queue: queue)

        session.commitConfiguration()
        session.startRunning()

        self.session = session
        self.input = input
        self.output = output
    }

    func stop() {
        lock.lock()
        latestPixelBuffer = nil
        lock.unlock()

        if let output {
            output.setSampleBufferDelegate(nil, queue: nil)
        }

        session?.stopRunning()
        session = nil
        input = nil
        output = nil
    }

    func currentFrame() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return latestPixelBuffer
    }
}

extension CameraFrameProvider: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        lock.lock()
        latestPixelBuffer = pixelBuffer
        lock.unlock()
    }
}
