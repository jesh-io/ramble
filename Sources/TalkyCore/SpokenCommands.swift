import Foundation

/// Deterministic handling of spoken formatting commands. Applied to the raw
/// transcript BEFORE any LLM cleanup, so breaks are guaranteed regardless of
/// how well the cleanup model follows instructions.
public enum SpokenCommands {
    private static let rules: [(pattern: String, replacement: String)] = [
        (#"(?i)[,.!?;]?\s*\bnew paragraph\b[.,!?;]?\s*"#, "\n\n"),
        (#"(?i)[,.!?;]?\s*\bnew line\b[.,!?;]?\s*"#, "\n"),
    ]

    public static func apply(to text: String) -> String {
        var result = text
        for rule in rules {
            result = result.replacingOccurrences(
                of: rule.pattern, with: rule.replacement, options: .regularExpression)
        }
        // Capitalize the first letter after each inserted break so the raw
        // fallback path (cleanup disabled/failed) still reads correctly.
        for separator in ["\n\n", "\n"] {
            result = result
                .components(separatedBy: separator)
                .map { part -> String in
                    guard let first = part.first, first.isLowercase else { return part }
                    return first.uppercased() + part.dropFirst()
                }
                .joined(separator: separator)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
