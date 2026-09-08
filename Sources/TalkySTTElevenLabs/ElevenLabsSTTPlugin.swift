import Foundation
@preconcurrency import AVFAudio
import TalkyCore
import TalkyTranscribe

/// ElevenLabs Scribe v2 (batch /v1/speech-to-text with diarization; realtime WebSocket /v1/speech-to-text/realtime)
public enum ElevenLabsSTTPlugin {
    public static func register() {
        TranscriberFactory.register(engine: "elevenlabs") { provider, options in
            ElevenLabsTranscriber(provider: provider, options: options)
        }
    }
}

/// TODO(plugin): implement. Streaming when `options.wantsStreaming` and
/// the model supports it; batch (use `BatchFallbackStream` for the mic
/// path) otherwise. Populate `TranscriptSegment.speaker` when diarizing.
public struct ElevenLabsTranscriber: Transcriber {
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
        throw TalkyError("ElevenLabs streaming is not implemented yet")
    }

    public func transcribeFile(_ url: URL, onSegment: (@Sendable (TranscriptSegment) -> Void)?) async throws -> Transcript {
        throw TalkyError("ElevenLabs batch transcription is not implemented yet")
    }
}
