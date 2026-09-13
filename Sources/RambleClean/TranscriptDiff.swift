import Foundation
import RambleCore

/// Word-level alignment between the raw transcript and the model's output.
///
/// Cleanup is supposed to be *subtractive* with tiny local insertions
/// (punctuation, an article, a corrected word). Long runs of words that
/// never appeared in the input are hallucinations — typically the model
/// echoing its own instructions/examples. A global novel-word ratio can't
/// see a 12-word insertion inside a 300-word dictation; an alignment can.
public struct TranscriptDiff: Sendable {
    public struct Insertion: Sendable, Equatable {
        public let text: String
        public let wordCount: Int
    }

    /// Similarity in [0, 1]: aligned words / max(input, output) words.
    public let similarity: Double
    public let insertedRuns: [Insertion]
    public let deletedWords: Int
    public let inputWords: Int
    public let outputWords: Int

    // MARK: - Analysis

    private struct Token {
        let text: String       // as written, with leading whitespace
        let key: String        // normalized for matching ("" = punctuation-only)
    }

    private static func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var leading = ""
        func flush() {
            if !current.isEmpty {
                tokens.append(Token(text: leading + current, key: normalize(current)))
                current = ""
                leading = ""
            }
        }
        for ch in s {
            if ch.isWhitespace {
                flush()
                leading.append(ch)
            } else {
                current.append(ch)
            }
        }
        flush()
        return tokens
    }

    private static func normalize(_ word: String) -> String {
        word.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    /// Aligns `output` against `input`; `matched[i]` tells whether output
    /// token i is anchored to an input word.
    private static func align(input: [Token], output: [Token]) -> [Bool] {
        let a = input.map(\.key).filter { !$0.isEmpty }
        // Map output word tokens (non-empty keys) to indices for LCS.
        let bIndices = output.indices.filter { !output[$0].key.isEmpty }
        let b = bIndices.map { output[$0].key }
        let n = a.count, m = b.count
        var matched = Array(repeating: false, count: output.count)
        guard n > 0, m > 0 else { return matched }

        // LCS table (n+1 x m+1). Dictations are a few hundred words.
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] {
                matched[bIndices[j]] = true
                i += 1; j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return matched
    }

    public init(input: String, output: String) {
        let inTokens = Self.tokenize(input)
        let outTokens = Self.tokenize(output)
        let matched = Self.align(input: inTokens, output: outTokens)

        var runs: [Insertion] = []
        var run: [Token] = []
        func flushRun() {
            let words = run.filter { !$0.key.isEmpty }.count
            if words > 0 {
                runs.append(Insertion(
                    text: run.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines),
                    wordCount: words))
            }
            run = []
        }
        for (idx, token) in outTokens.enumerated() {
            if token.key.isEmpty { continue }              // punctuation never breaks/forms a run
            if matched[idx] { flushRun() } else { run.append(token) }
        }
        flushRun()

        let inWords = inTokens.filter { !$0.key.isEmpty }.count
        let outWords = outTokens.filter { !$0.key.isEmpty }.count
        let aligned = matched.filter { $0 }.count
        insertedRuns = runs
        inputWords = inWords
        outputWords = outWords
        deletedWords = max(0, inWords - aligned)
        similarity = max(inWords, outWords) == 0 ? 1 : Double(aligned) / Double(max(inWords, outWords))
    }

    // MARK: - Sentence support

    /// Strips output sentences that no contiguous window of the input
    /// supports (ordered word overlap below `minCoverage`). Catches
    /// invented sentences assembled from vocabulary that appears elsewhere
    /// in the transcript, which run-length detection can't see.
    public static func stripUnsupportedSentences(input: String, output: String, minCoverage: Double = 0.6) -> (text: String, removed: [String]) {
        let inputKeys = tokenize(input).map(\.key).filter { !$0.isEmpty }
        guard !inputKeys.isEmpty else { return (output, []) }
        // Split output into sentences, preserving separators.
        var sentences: [String] = []
        var current = ""
        for ch in output {
            current.append(ch)
            if ch == "." || ch == "?" || ch == "!" || ch == "\n" {
                sentences.append(current)
                current = ""
            }
        }
        if !current.isEmpty { sentences.append(current) }

        var kept: [String] = []
        var removed: [String] = []
        for sentence in sentences {
            let keys = tokenize(sentence).map(\.key).filter { !$0.isEmpty }
            guard keys.count >= 3 else { kept.append(sentence); continue }
            let window = min(inputKeys.count, keys.count * 2 + 2)
            var best = 0
            var start = 0
            while start + min(window, inputKeys.count - start) <= inputKeys.count, start < inputKeys.count {
                let slice = Array(inputKeys[start..<min(start + window, inputKeys.count)])
                best = max(best, lcsLength(keys, slice))
                if best == keys.count { break }
                start += max(1, keys.count / 2)
            }
            if Double(best) / Double(keys.count) >= minCoverage {
                kept.append(sentence)
            } else {
                removed.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        var text = kept.joined()
        text = text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), removed)
    }

    private static func lcsLength(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var prev = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            var row = Array(repeating: 0, count: b.count + 1)
            for j in 1...b.count {
                row[j] = a[i - 1] == b[j - 1] ? prev[j - 1] + 1 : max(prev[j], row[j - 1])
            }
            prev = row
        }
        return prev[b.count]
    }

    // MARK: - Repair

    /// Removes inserted runs longer than `maxRun` words from `output`,
    /// keeping everything else (including short legitimate insertions such
    /// as corrected words). Returns the repaired text and the words removed.
    public static func repair(input: String, output: String, maxRun: Int) -> (text: String, removedWords: Int, removedRuns: [String]) {
        let inTokens = tokenize(input)
        let outTokens = tokenize(output)
        let matched = align(input: inTokens, output: outTokens)

        // Group output tokens into runs of consecutive unmatched words
        // (punctuation-only tokens ride along with the run they sit in).
        var keep = Array(repeating: true, count: outTokens.count)
        var removedWords = 0
        var removedRuns: [String] = []
        var runStart: Int? = nil
        var runWords = 0
        func closeRun(endExclusive: Int) {
            if let start = runStart, runWords > maxRun {
                for k in start..<endExclusive { keep[k] = false }
                removedWords += runWords
                removedRuns.append(outTokens[start..<endExclusive].map(\.text).joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines))
            }
            runStart = nil
            runWords = 0
        }
        for idx in outTokens.indices {
            let isWord = !outTokens[idx].key.isEmpty
            if isWord && matched[idx] {
                closeRun(endExclusive: idx)
            } else if isWord {
                if runStart == nil { runStart = idx }
                runWords += 1
            } else if runStart == nil {
                // punctuation outside a run: keep
            }
        }
        closeRun(endExclusive: outTokens.count)

        var text = ""
        for idx in outTokens.indices where keep[idx] {
            text += outTokens[idx].text
        }
        // Collapse whitespace artifacts left by removals (3+ newlines, double spaces).
        text = text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), removedWords, removedRuns)
    }
}
