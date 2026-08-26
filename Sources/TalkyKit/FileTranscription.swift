import Foundation
import TalkyCore
import TalkyAudio
import TalkyClean
import TalkyTranscribe

/// One-shot transcription of an audio or video file.
public enum FileTranscription {
    public struct Result: Sendable {
        public let transcript: Transcript
        /// Cleaned text, if cleanup ran successfully.
        public let cleaned: String?
        /// Non-fatal warning (e.g. cleanup failed and raw text was kept).
        public let warning: String?

        public var bestText: String {
            cleaned ?? (transcript.hasSpeakers ? transcript.formattedText : transcript.text)
        }
    }

    public static func transcribe(
        url: URL,
        config: TalkyConfig,
        clean: Bool,
        transcriber: Transcriber? = nil,
        onSegment: (@Sendable (TranscriptSegment) -> Void)? = nil
    ) async throws -> Result {
        let engine = transcriber
            ?? AppleTranscriber(locale: Locale(identifier: config.locale), vocabulary: config.vocabulary)
        let extracted = try await MediaAudio.audioFile(for: url)
        defer { extracted.cleanUp() }

        let transcript = try await engine.transcribeFile(extracted.url, onSegment: onSegment)

        guard clean, !transcript.isEmpty, config.cleanup.enabled,
              let provider = config.cleanup.activeProvider else {
            return Result(transcript: transcript, cleaned: nil, warning: nil)
        }
        do {
            let cleaner = try CleanerFactory.make(
                provider: provider,
                systemPrompt: config.effectiveCleanupPrompt,
                timeout: max(config.cleanup.timeoutSeconds, 120)
            )
            let input = Vocabulary.applyKnownMishearings(
                to: SpokenCommands.apply(to: transcript.text), vocabulary: config.vocabulary)
            let cleaned = try await cleaner.clean(input)
            guard CleanupValidator.looksFaithful(raw: input, cleaned: cleaned) else {
                return Result(
                    transcript: transcript,
                    cleaned: nil,
                    warning: "Cleanup model hallucinated — returning raw transcript")
            }
            return Result(transcript: transcript, cleaned: cleaned, warning: nil)
        } catch {
            return Result(
                transcript: transcript,
                cleaned: nil,
                warning: "Cleanup failed (returning raw transcript): \(error.localizedDescription)"
            )
        }
    }
}
