import Foundation
import TalkyCore

/// Builds the right `TextCleaner` for a provider's `engine`. Apps can
/// register additional engines (e.g. the iOS app registers "mlx" for
/// on-device Qwen) without the core package depending on them.
public enum CleanerFactory {
    public typealias Builder = (CleanupProvider, _ systemPrompt: String, _ timeout: TimeInterval) throws -> any TextCleaner

    private static var custom: [String: Builder] = [:]

    public static func register(engine: String, _ builder: @escaping Builder) {
        custom[engine] = builder
    }

    public static func make(
        provider: CleanupProvider,
        systemPrompt: String,
        timeout: TimeInterval
    ) throws -> any TextCleaner {
        let engine = provider.engine ?? "openai"
        switch engine {
        case "openai":
            return try OpenAICompatCleaner(provider: provider, systemPrompt: systemPrompt, timeout: timeout)
        case "apple":
            return AppleFMCleaner(id: provider.id, systemPrompt: systemPrompt)
        default:
            if let builder = custom[engine] {
                return try builder(provider, systemPrompt, timeout)
            }
            throw TalkyError("Unknown cleanup engine '\(engine)' for provider '\(provider.id)'")
        }
    }
}
