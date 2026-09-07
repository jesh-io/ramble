import Foundation

/// Guards against cleanup-model hallucination. Cleanup is supposed to be
/// subtractive (remove filler, fix punctuation) with only tiny insertions;
/// if the "cleaned" text invents significant new content — e.g. the model
/// answered a question that appeared in the dictation — we must reject it
/// and fall back to the raw transcript.
public enum CleanupValidator {
    public struct GuardResult: Sendable {
        public let text: String
        public let similarity: Double
        public let removedWords: Int
        public let removedRuns: [String]
        /// True when even after repair the output isn't trustworthy.
        public let rejected: Bool
        public var note: String? {
            if rejected { return "cleanup rejected — raw kept (similarity \(Int(similarity * 100))%)" }
            if removedWords > 0 { return "stripped \(removedWords) hallucinated word(s)" }
            return nil
        }
    }

    /// Layered guard:
    /// 1. strip inserted runs longer than `maxInsertedRun` words (prompt/example leakage);
    /// 2. strip sentences no window of the input supports (invented sentences from transcript vocabulary);
    /// 3. reject outright if alignment similarity < `minSimilarity` or the global ratios fail
    ///    (restructuring/paraphrase) — the raw transcript is used instead.
    public static func guardOutput(raw: String, cleaned: String, maxInsertedRun: Int, minSimilarity: Double = 0.75) -> GuardResult {
        let repaired = TranscriptDiff.repair(input: raw, output: cleaned, maxRun: maxInsertedRun)
        let supported = TranscriptDiff.stripUnsupportedSentences(input: raw, output: repaired.text)
        let diff = TranscriptDiff(input: raw, output: supported.text)
        let removedWords = repaired.removedWords + supported.removed.reduce(0) { $0 + $1.split(separator: " ").count }
        let ok = diff.similarity >= minSimilarity && looksFaithful(raw: raw, cleaned: supported.text)
        return GuardResult(
            text: ok ? supported.text : raw,
            similarity: diff.similarity,
            removedWords: removedWords,
            removedRuns: repaired.removedRuns + supported.removed,
            rejected: !ok)
    }

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
