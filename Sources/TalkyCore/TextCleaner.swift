import Foundation

/// Post-processes a raw transcript into clean written text (removing filler
/// words, fixing punctuation, applying formatting). Implementations may be
/// local or remote LLMs — the pipeline doesn't care.
public protocol TextCleaner: Sendable {
    var id: String { get }
    func clean(_ text: String) async throws -> String
}
