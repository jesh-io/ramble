import Foundation
@preconcurrency import AVFAudio
import TalkyCore
import TalkyTranscribe

/// OpenAI speech-to-text: batch via `/audio/transcriptions`
/// (gpt-4o-transcribe, gpt-4o-mini-transcribe, whisper-1) and realtime
/// transcription via the Realtime API WebSocket.
public enum OpenAISTTPlugin {
    public static func register() {
        TranscriberFactory.register(engine: "openai") { provider, options in
            if options.wantsStreaming(engineSupportsStreaming: provider.supportsStreaming) {
                return OpenAIRealtimeTranscriber(provider: provider, options: options)
            }
            return OpenAICompatBatchTranscriber(provider: provider, options: options)
        }
    }
}

/// Realtime transcription over OpenAI's Realtime API (WebSocket).
/// TODO(plugin): implement streaming; until then falls back to batch.
public struct OpenAIRealtimeTranscriber: Transcriber {
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
