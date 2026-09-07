import Foundation
@preconcurrency import AVFAudio
import TalkyCore
import TalkyAudio
import TalkyClean
import TalkyProviders
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

        if let audio = try? AVAudioFile(forReading: extracted.url), audio.fileFormat.sampleRate > 0 {
            UsageLog.record(
                kind: "stt", provider: engine.id, model: "SpeechAnalyzer/file",
                seconds: Double(audio.length) / audio.fileFormat.sampleRate)
        }

        guard clean, !transcript.isEmpty, config.cleanup.enabled,
              let provider = ProviderRegistry.activeCleanupProvider(config) else {
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
            let guarded = CleanupValidator.guardOutput(
                raw: input, cleaned: cleaned, maxInsertedRun: config.cleanup.maxInsertedRun, minSimilarity: config.cleanup.minSimilarity)
            if guarded.rejected {
                return Result(
                    transcript: transcript,
                    cleaned: nil,
                    warning: "Cleanup model hallucinated — returning raw transcript")
            }
            return Result(transcript: transcript, cleaned: guarded.text, warning: guarded.note)
        } catch {
            return Result(
                transcript: transcript,
                cleaned: nil,
                warning: "Cleanup failed (returning raw transcript): \(error.localizedDescription)"
            )
        }
    }
}
