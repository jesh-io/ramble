import Foundation
@preconcurrency import AVFAudio
import TalkyCore
import TalkyTranscribe

/// AssemblyAI (batch /v2/transcript upload+poll with speaker_labels; Universal-Streaming v3 WebSocket wss://streaming.assemblyai.com/v3/ws)
public enum AssemblyAISTTPlugin {
    public static func register() {
        TranscriberFactory.register(engine: "assemblyai") { provider, options in
            AssemblyAITranscriber(provider: provider, options: options)
        }
    }
}

/// TODO(plugin): implement. Streaming when `options.wantsStreaming` and
/// the model supports it; batch (use `BatchFallbackStream` for the mic
/// path) otherwise. Populate `TranscriptSegment.speaker` when diarizing.
public struct AssemblyAITranscriber: Transcriber {
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
        throw TalkyError("AssemblyAI streaming is not implemented yet")
    }

    public func transcribeFile(_ url: URL, onSegment: (@Sendable (TranscriptSegment) -> Void)?) async throws -> Transcript {
        throw TalkyError("AssemblyAI batch transcription is not implemented yet")
    }
}
