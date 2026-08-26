import Foundation
@preconcurrency import AVFoundation
import TalkyCore

/// Captures microphone audio via AVAudioEngine and hands PCM buffers to a
/// callback in the hardware's native format.
public final class MicCapture {
    private let engine = AVAudioEngine()
    private var recordFile: AVAudioFile?

    public init() {}

    /// The format buffers will be delivered in.
    public var inputFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    public static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    /// Starts capture. If `recordTo` is set, audio is also encoded to that
    /// file (AAC .m4a) live, buffer by buffer — so a crash mid-dictation
    /// still leaves the audio on disk.
    public func start(recordTo url: URL? = nil, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw TalkyError("No usable microphone input (format: \(format))")
        }
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        if let url {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            recordFile = try? AVAudioFile(forWriting: url, settings: settings)
        }
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? self?.recordFile?.write(from: buffer)
            onBuffer(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        recordFile = nil // releases (and flushes) the file
    }
}
