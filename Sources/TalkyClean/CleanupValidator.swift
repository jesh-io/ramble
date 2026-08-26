import Foundation

/// Guards against cleanup-model hallucination. Cleanup is supposed to be
/// subtractive (remove filler, fix punctuation) with only tiny insertions;
/// if the "cleaned" text invents significant new content — e.g. the model
/// answered a question that appeared in the dictation — we must reject it
/// and fall back to the raw transcript.
public enum CleanupValidator {
    public static func looksFaithful(raw: String, cleaned: String) -> Bool {
        let rawWords = words(raw)
        let cleanedWords = words(cleaned)
        guard !rawWords.isEmpty, !cleanedWords.isEmpty else { return false }

        // Words in the output that never appeared in the input. Legitimate
        // edits (punctuation, a corrected article) barely move this; invented
        // sentences send it soaring.
        let rawSet = Set(rawWords)
        let novel = cleanedWords.filter { !rawSet.contains($0) }.count
        let novelRatio = Double(novel) / Double(cleanedWords.count)

        // Cleanup removes words; it should never grow the text much, nor
        // collapse it toward a summary. Even filler-heavy dictations keep
        // well over half their words (measured ~0.73–0.83 on real sessions);
        // a model that dropped a whole clause landed at 0.36.
        let lengthRatio = Double(cleanedWords.count) / Double(rawWords.count)

        return novelRatio <= 0.20 && lengthRatio <= 1.15 && lengthRatio >= 0.55
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
