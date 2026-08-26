import Foundation

/// Deterministic vocabulary correction. Entries shaped
/// `Term (misheard: a, b)` get their listed mishearings replaced with the
/// exact term in code — guaranteed, regardless of the cleanup model.
/// Ambiguous mishearings (words that are often legitimate, like "cash")
/// should NOT use the "(misheard: ...)" form; describe them in prose
/// instead and the LLM pass will handle them contextually.
public enum Vocabulary {
    public static func applyKnownMishearings(to text: String, vocabulary: [String]) -> String {
        var result = text
        for entry in vocabulary {
            guard let open = entry.range(of: "(misheard:"),
                  let close = entry.range(of: ")", range: open.upperBound..<entry.endIndex)
            else { continue }
            let term = entry[..<open.lowerBound].trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty else { continue }
            let hints = entry[open.upperBound..<close.lowerBound]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for hint in hints {
                let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: hint) + "\\b"
                result = result.replacingOccurrences(
                    of: pattern, with: term, options: .regularExpression)
            }
        }
        return result
    }
}
