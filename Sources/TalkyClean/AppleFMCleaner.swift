import Foundation
import TalkyCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Cleans transcripts with Apple's on-device foundation model
/// (Apple Intelligence, macOS 26 / iOS 26). No server, no download beyond
/// what the system manages; requires Apple Intelligence to be enabled.
public struct AppleFMCleaner: TextCleaner {
    public let id: String
    private let systemPrompt: String

    public init(id: String, systemPrompt: String) {
        self.id = id
        self.systemPrompt = systemPrompt
    }

    public func clean(_ text: String) async throws -> String {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw TalkyError("Apple on-device model unavailable: \(String(describing: reason)). Is Apple Intelligence enabled?")
        }
        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(
            to: text,
            options: GenerationOptions(temperature: 0.1)
        )
        let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw TalkyError("Apple on-device model returned empty text")
        }
        return cleaned
        #else
        throw TalkyError("FoundationModels framework not available on this OS")
        #endif
    }
}
