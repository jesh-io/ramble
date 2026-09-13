import Foundation
@preconcurrency import AVFAudio
import RambleCore
import RambleAudio
import RambleClean
import RambleProviders
import RambleTranscribe
import RambleAnalytics

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
        config: RambleConfig,
        clean: Bool,
        transcriber: Transcriber? = nil,
        onSegment: (@Sendable (TranscriptSegment) -> Void)? = nil
    ) async throws -> Result {
        ProductAnalytics.configure(config)
        let selected = ProviderRegistry.activeSTTProvider(config)
        Analytics.dictationStarted(source: .file, provider: selected.engine, model: selected.model)
        let started = Date()
        var completed = false
        defer {
            if !completed {
                Analytics.operationFailed(stage: .transcription)
                Analytics.dictationCompleted(source: .file, outcome: .failed,
                    durationSeconds: Date().timeIntervalSince(started), characterCount: 0,
                    provider: selected.engine, model: selected.model)
            }
        }
        let engine = transcriber ?? RambleKit.makeTranscriber(config: config, mode: "batch")
        let extracted = try await MediaAudio.audioFile(for: url)
        defer { extracted.cleanUp() }

        let transcript = try await engine.transcribeFile(extracted.url, onSegment: onSegment)
        completed = true
        Analytics.dictationCompleted(source: .file, outcome: .success,
            durationSeconds: Date().timeIntervalSince(started), characterCount: transcript.text.count,
            provider: selected.engine, model: selected.model)

        if let audio = try? AVAudioFile(forReading: extracted.url), audio.fileFormat.sampleRate > 0 {
            UsageLog.record(
                kind: "stt", provider: engine.id, model: engine.id == "apple" ? "SpeechAnalyzer/file" : engine.id,
                seconds: Double(audio.length) / audio.fileFormat.sampleRate)
        }

        guard clean, !transcript.isEmpty, config.cleanup.enabled,
              let provider = ProviderRegistry.activeCleanupProvider(config) else {
            return Result(transcript: transcript, cleaned: nil, warning: nil)
        }
        do {
            let cleanupStart = Date()
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
            Analytics.cleanupCompleted(provider: provider.analyticsProvider, model: provider.model,
                outcome: .success, latencySeconds: Date().timeIntervalSince(cleanupStart), rejected: guarded.rejected)
            if guarded.rejected {
                return Result(
                    transcript: transcript,
                    cleaned: nil,
                    warning: "Cleanup model hallucinated — returning raw transcript")
            }
            return Result(transcript: transcript, cleaned: guarded.text, warning: guarded.note)
        } catch {
            Analytics.operationFailed(stage: .cleanup)
            return Result(
                transcript: transcript,
                cleaned: nil,
                warning: "Cleanup failed (returning raw transcript): \(error.localizedDescription)"
            )
        }
    }
}
