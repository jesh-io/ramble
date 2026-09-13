import Foundation
import RambleCore
import RambleClean
import RambleProviders
import RambleTranscribe

/// Convenience entry points for SDK consumers.
public enum RambleKit {
    /// The default local speech engine for the configured locale.
    public static func makeDefaultTranscriber(config: RambleConfig) -> Transcriber {
        AppleTranscriber(locale: Locale(identifier: config.locale), vocabulary: config.vocabulary)
    }

    /// The configured speech engine (Apple on-device or a remote plugin).
    /// Falls back to Apple if the chosen engine isn't available.
    public static func makeTranscriber(config: RambleConfig, mode: String? = nil) -> Transcriber {
        STTPlugins.registerAll()
        let provider = ProviderRegistry.activeSTTProvider(config)
        let options = STTOptions(
            locale: Locale(identifier: config.locale),
            vocabulary: config.vocabulary.map { $0.components(separatedBy: "(")[0].components(separatedBy: " —")[0].trimmingCharacters(in: .whitespaces) },
            mode: mode ?? config.stt.mode,
            diarize: config.stt.diarize)
        do {
            return try TranscriberFactory.make(provider: provider, options: options)
        } catch {
            return makeDefaultTranscriber(config: config)
        }
    }

    /// Cleans text with the active cleanup provider from config.
    public static func cleanText(_ text: String, config: RambleConfig) async throws -> String {
        guard let provider = ProviderRegistry.activeCleanupProvider(config) else {
            throw RambleError("No cleanup provider configured")
        }
        let cleaner = try CleanerFactory.make(
            provider: provider,
            systemPrompt: config.effectiveCleanupPrompt,
            timeout: config.cleanup.timeoutSeconds
        )
        let input = Vocabulary.applyKnownMishearings(
            to: SpokenCommands.apply(to: text), vocabulary: config.vocabulary)
        let cleaned = try await cleaner.clean(input)
        let guarded = CleanupValidator.guardOutput(
            raw: input, cleaned: cleaned, maxInsertedRun: config.cleanup.maxInsertedRun, minSimilarity: config.cleanup.minSimilarity)
        if guarded.rejected {
            throw RambleError("Cleanup model hallucinated (\(guarded.note ?? "rejected")); raw kept")
        }
        if guarded.removedWords > 0 {
            fputs("guard: \(guarded.note ?? "") — removed: \(guarded.removedRuns.joined(separator: " | "))\n", stderr)
        }
        return guarded.text
    }

    /// Diffs a transcript against the user's hand-corrected version and
    /// extracts vocabulary entries worth remembering ("Term (misheard: ...)").
    public static func extractVocabulary(
        original: String, corrected: String, config: RambleConfig
    ) async throws -> [String] {
        guard let provider = ProviderRegistry.activeCleanupProvider(config) else {
            throw RambleError("No cleanup provider configured")
        }
        let prompt = """
            Compare the ORIGINAL speech transcript with the user's CORRECTED version. \
            Find words or phrases the user changed because the speech engine misheard a name or term.

            Output ONLY lines of this exact form, one per correction:
            CorrectTerm = mishearing1, mishearing2

            Rules: CorrectTerm is the corrected spelling; mishearings are what the ORIGINAL had. \
            Only include proper nouns, product names, jargon, or unusual terms worth remembering. \
            Ignore punctuation, grammar, and wording-preference changes. \
            If there are no such corrections, output exactly: NONE
            """
        let cleaner = try CleanerFactory.make(
            provider: provider, systemPrompt: prompt, timeout: config.cleanup.timeoutSeconds)
        let output = try await cleaner.clean("ORIGINAL:\n\(original)\n\nCORRECTED:\n\(corrected)")
        return output
            .split(separator: "\n")
            .compactMap { line -> String? in
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                let term = parts[0].trimmingCharacters(in: .whitespaces)
                let misheard = parts[1].trimmingCharacters(in: .whitespaces)
                guard !term.isEmpty, !misheard.isEmpty,
                      term.uppercased() != "NONE",
                      term != "CorrectTerm", // template echo
                      term.count < 60, misheard.count < 120,
                      term.lowercased() != misheard.lowercased()
                else { return nil }
                return "\(term) (misheard: \(misheard))"
            }
    }
}
