import Foundation
@preconcurrency import AVFAudio
import TalkyCore
import TalkyTranscribe

/// Deepgram Nova-3 (prerecorded POST /v1/listen with diarize; live WebSocket wss://api.deepgram.com/v1/listen)
public enum DeepgramSTTPlugin {
    public static func register() {
        TranscriberFactory.register(engine: "deepgram") { provider, options in
            DeepgramTranscriber(provider: provider, options: options)
        }
    }
}

/// TODO(plugin): implement. Streaming when `options.wantsStreaming` and
/// the model supports it; batch (use `BatchFallbackStream` for the mic
/// path) otherwise. Populate `TranscriptSegment.speaker` when diarizing.
public struct DeepgramTranscriber: Transcriber {
    public let id: String
    public let capabilities: TranscriberCapabilities
    let provider: STTProvider
    let options: STTOptions

    public init(provider: STTProvider, options: STTOptions) {
        id = provider.id
        self.provider = provider
        self.options = options
        var caps: TranscriberCapabilities = [.timestamps]
        if provider.supportsStreaming { caps.insert(.streamingPartials) }
        if provider.supportsDiarization { caps.insert(.diarization) }
        capabilities = caps
    }

    public func prepare() async throws {
        guard provider.resolvedAPIKey != nil else {
            throw TalkyError("No API key for '\(provider.id)' (set \(provider.apiKeyEnv ?? "its apiKeyEnv"))")
        }
    }

    public func makeStream(inputFormat: AVAudioFormat) async throws -> TranscriptionStream {
        throw TalkyError("Deepgram streaming is not implemented yet")
    }

    public func transcribeFile(_ url: URL, onSegment: (@Sendable (TranscriptSegment) -> Void)?) async throws -> Transcript {
        throw TalkyError("Deepgram batch transcription is not implemented yet")
    }
}
