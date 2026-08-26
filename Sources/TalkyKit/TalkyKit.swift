import Foundation
import TalkyCore
import TalkyClean
import TalkyTranscribe

/// Convenience entry points for SDK consumers.
public enum TalkyKit {
    /// The default local speech engine for the configured locale.
    public static func makeDefaultTranscriber(config: TalkyConfig) -> Transcriber {
        AppleTranscriber(locale: Locale(identifier: config.locale), vocabulary: config.vocabulary)
    }

    /// Cleans text with the active cleanup provider from config.
    public static func cleanText(_ text: String, config: TalkyConfig) async throws -> String {
        guard let provider = config.cleanup.activeProvider else {
            throw TalkyError("No cleanup provider configured")
        }
        let cleaner = try CleanerFactory.make(
            provider: provider,
            systemPrompt: config.effectiveCleanupPrompt,
            timeout: config.cleanup.timeoutSeconds
        )
        let input = Vocabulary.applyKnownMishearings(
            to: SpokenCommands.apply(to: text), vocabulary: config.vocabulary)
        let cleaned = try await cleaner.clean(input)
        guard CleanupValidator.looksFaithful(raw: input, cleaned: cleaned) else {
            throw TalkyError("Cleanup model hallucinated (output diverges too far from input); raw kept")
        }
        return cleaned
    }
}
