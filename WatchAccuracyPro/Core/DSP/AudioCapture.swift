import AVFoundation
import Foundation

/// 디바이스 마이크에서 오디오를 캡처해 100ms 청크 단위로 콜백한다.
/// AVAudioSession은 `.measurement` 카테고리로 설정해 이득 자동조절을 최소화한다.
final class AudioCapture: AudioSource {
    let sampleRate: Double = 48_000

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var onBuffer: (([Float]) -> Void)?
    private let chunkFrames: AVAudioFrameCount = 4_800 // 100ms @ 48kHz

    func start(onBuffer: @escaping ([Float]) -> Void) throws {
        try configureSession()
        self.onBuffer = onBuffer

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioSourceError.sessionConfigurationFailed(
                underlying: NSError(domain: "AudioCapture", code: -1)
            )
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: chunkFrames, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
            guard let outBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * self.sampleRate / inputFormat.sampleRate)
            ) else { return }
            var error: NSError?
            converter.convert(to: outBuffer, error: &error) { _, status in
                status.pointee = .haveData
                return buffer
            }
            if error != nil { return }
            guard let channel = outBuffer.floatChannelData?[0] else { return }
            let count = Int(outBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channel, count: count))
            self.onBuffer?(samples)
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioSourceError.engineStartFailed(underlying: error)
        }
    }

    func stop() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        onBuffer = nil
    }

    private func configureSession() throws {
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true, options: [])
        } catch {
            throw AudioSourceError.sessionConfigurationFailed(underlying: error)
        }
        #endif
    }
}
