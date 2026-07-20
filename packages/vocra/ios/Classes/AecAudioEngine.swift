import AVFoundation

/// Captures mono 16 kHz PCM16 audio via `AVAudioEngine` with hardware voice
/// processing (echo cancellation) enabled on the input node (spec §9 — iOS
/// side).
///
/// This is part of the *optional* full-duplex native AEC module. It has
/// been written against Apple's documented `AVAudioEngine`/voice-processing
/// APIs but has not been exercised on a physical device as part of this
/// build — unlike the rest of this SDK, runtime echo-cancellation quality
/// can't be verified without one.
final class AecAudioEngine {
    static let sampleRate: Double = 16000

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var onFrame: ((Data) -> Void)?
    private var running = false

    static func isAvailable() -> Bool {
        // AVAudioInputNode.setVoiceProcessingEnabled has been available
        // since iOS 13; the package's deployment target is already 13.0.
        return true
    }

    func start(onFrame: @escaping (Data) -> Void) throws {
        guard !running else { return }
        self.onFrame = onFrame

        let inputNode = engine.inputNode
        try inputNode.setVoiceProcessingEnabled(true)

        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        guard
            let target = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: AecAudioEngine.sampleRate,
                channels: 1,
                interleaved: true
            )
        else {
            throw AecError.formatCreationFailed
        }
        targetFormat = target

        guard let conv = AVAudioConverter(from: hardwareFormat, to: target) else {
            throw AecError.converterCreationFailed
        }
        converter = conv

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) {
            [weak self] buffer, _ in
            self?.convertAndEmit(buffer)
        }

        engine.prepare()
        try engine.start()
        running = true
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        converter = nil
        targetFormat = nil
        onFrame = nil
        running = false
    }

    /// Converts one captured buffer (in the input node's hardware format,
    /// which voice processing may have changed from the device default) to
    /// 16 kHz mono Int16 PCM and hands the raw bytes to [onFrame].
    ///
    /// Runs on AVAudioEngine's real-time audio thread — callers must not do
    /// anything here that could block (no UI work, no locking on the main
    /// thread); [onFrame] is responsible for hopping to the main thread
    /// before touching Flutter's `FlutterEventSink`.
    private func convertAndEmit(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity)
        else { return }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: outBuffer, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, conversionError == nil, outBuffer.frameLength > 0 else { return }
        guard let channelData = outBuffer.int16ChannelData else { return }

        let frameLength = Int(outBuffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Int16>.size)
        onFrame?(data)
    }
}

enum AecError: Error, LocalizedError {
    case formatCreationFailed
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed: return "Failed to create the target 16kHz mono PCM16 audio format."
        case .converterCreationFailed: return "Failed to create the audio format converter."
        }
    }
}
