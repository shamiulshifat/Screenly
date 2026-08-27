import AVFoundation
import CoreMedia
import Foundation

final class MicrophoneMeterEngine: NSObject {
    var onLevelUpdate: ((Float, Float) -> Void)?

    private let queue = DispatchQueue(label: "com.screenly.audio.meter", qos: .userInitiated)
    private var session: AVCaptureSession?

    func start(device: AVCaptureDevice) throws {
        stop()

        let session = AVCaptureSession()
        session.beginConfiguration()

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw RecordingError.microphoneUnavailable
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        guard session.canAddOutput(output) else {
            throw RecordingError.microphoneUnavailable
        }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)

        session.commitConfiguration()
        session.startRunning()

        self.session = session
        ScreenlyLogger.capture.info("Microphone meter started for \(device.localizedName)")
    }

    func stop() {
        guard let session else { return }

        queue.sync {
            session.outputs
                .compactMap { $0 as? AVCaptureAudioDataOutput }
                .forEach { $0.setSampleBufferDelegate(nil, queue: nil) }
        }

        session.stopRunning()
        self.session = nil
    }
}

extension MicrophoneMeterEngine: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return
        }

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList(mNumberBuffers: 0, mBuffers: AudioBuffer())
        var bufferListSizeNeeded: Int = 0

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSizeNeeded,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else { return }

        let channelCount = max(Int(streamDescription.mChannelsPerFrame), 1)
        let bitsPerChannel = Int(streamDescription.mBitsPerChannel)
        let isFloat = (streamDescription.mFormatFlags & kAudioFormatFlagIsFloat) != 0

        let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)

        var sumSquares: Double = 0
        var sampleCount = 0
        var maxMagnitude: Double = 0

        for buffer in buffers {
            guard let data = buffer.mData else { continue }

            if isFloat && bitsPerChannel == 32 {
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = data.bindMemory(to: Float.self, capacity: count)
                for index in 0..<count {
                    let value = Double(abs(samples[index]))
                    sumSquares += value * value
                    maxMagnitude = max(maxMagnitude, value)
                }
                sampleCount += count
            } else {
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
                let samples = data.bindMemory(to: Int16.self, capacity: count)
                for index in 0..<count {
                    let value = Double(abs(Float(samples[index]) / Float(Int16.max)))
                    sumSquares += value * value
                    maxMagnitude = max(maxMagnitude, value)
                }
                sampleCount += count
            }
        }

        guard sampleCount > 0 else { return }

        let normalizedRMS = min(Float(sqrt(sumSquares / Double(sampleCount))), 1)
        let normalizedPeak = min(Float(maxMagnitude), 1)

        DispatchQueue.main.async { [weak self] in
            self?.onLevelUpdate?(normalizedRMS, normalizedPeak)
        }

        _ = channelCount
    }
}
