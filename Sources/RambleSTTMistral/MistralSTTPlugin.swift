import Foundation
@preconcurrency import AVFAudio
import RambleCore
import RambleTranscribe

/// Mistral Voxtral: batch via the OpenAI-compatible transcription endpoint,
/// realtime via Mistral's streaming transcription API.
public enum MistralSTTPlugin {
    public static func register() {
        TranscriberFactory.register(engine: "mistral") { provider, options in
            if options.wantsStreaming(engineSupportsStreaming: provider.supportsStreaming) {
                return MistralRealtimeTranscriber(provider: provider, options: options)
            }
            return OpenAICompatBatchTranscriber(provider: provider, options: options)
        }
    }
}

/// TODO(plugin): implement Mistral realtime streaming; falls back to batch.
public struct MistralRealtimeTranscriber: Transcriber {
    public let id: String
    public let capabilities: TranscriberCapabilities = [.timestamps]
    private let batch: OpenAICompatBatchTranscriber

    public init(provider: STTProvider, options: STTOptions) {
        id = provider.id
        batch = OpenAICompatBatchTranscriber(provider: provider, options: options)
    }

    public func prepare() async throws { try await batch.prepare() }
    public func makeStream(inputFormat: AVAudioFormat) async throws -> TranscriptionStream {
        try await batch.makeStream(inputFormat: inputFormat)
    }
    public func transcribeFile(_ url: URL, onSegment: (@Sendable (TranscriptSegment) -> Void)?) async throws -> Transcript {
        try await batch.transcribeFile(url, onSegment: onSegment)
    }
}
