import Foundation
import TalkyCore

/// A model an integration can serve, with default cost rates (USD per
/// million tokens). Rates are editable defaults — override per account.
public struct ModelInfo: Sendable, Equatable {
    public let id: String
    public let inputCostPerMTok: Double?
    public let outputCostPerMTok: Double?
    public let note: String?
    // Speech-to-text models
    public let costPerMinute: Double?
    public let streaming: Bool
    public let diarization: Bool

    public init(_ id: String, input: Double? = nil, output: Double? = nil, note: String? = nil,
                costPerMinute: Double? = nil, streaming: Bool = false, diarization: Bool = false) {
        self.id = id
        self.inputCostPerMTok = input
        self.outputCostPerMTok = output
        self.note = note
        self.costPerMinute = costPerMinute
        self.streaming = streaming
        self.diarization = diarization
    }
}

public enum ProviderKind: String, Sendable {
    case cleanup      // text model (chat completions / messages)
    case stt          // speech-to-text (future: AssemblyAI, Deepgram, ...)
}

/// A pluggable integration definition. Each provider is self-contained:
/// where it lives, how it's called (engine), what auth it needs, and a
/// curated model catalog. Apps can register additional plugins at runtime
/// via `ProviderRegistry.register`.
public struct ProviderPlugin: Sendable {
    public let id: String              // "openai", "anthropic", "ollama", …
    public let name: String            // display name
    public let kind: ProviderKind
    /// Wire protocol handled by CleanerFactory: "openai" (chat/completions),
    /// "anthropic" (Messages API), "apple" (on-device FM), "mlx" (on-device).
    public let engine: String
    public let defaultBaseURL: String
    public let apiKeyRequired: Bool
    /// Conventional env var name for this provider's key.
    public let keyEnvSuggestion: String?
    public let models: [ModelInfo]
    public let available: Bool         // false = catalogued but not yet usable

    public init(id: String, name: String, kind: ProviderKind = .cleanup, engine: String,
                defaultBaseURL: String, apiKeyRequired: Bool, keyEnvSuggestion: String? = nil,
                models: [ModelInfo], available: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.engine = engine
        self.defaultBaseURL = defaultBaseURL
        self.apiKeyRequired = apiKeyRequired
        self.keyEnvSuggestion = keyEnvSuggestion
        self.models = models
        self.available = available
    }

    public func costs(for model: String) -> (input: Double?, output: Double?) {
        let info = models.first { $0.id == model }
        return (info?.inputCostPerMTok, info?.outputCostPerMTok)
    }
}

public enum ProviderRegistry {
    private nonisolated(unsafe) static var custom: [ProviderPlugin] = []
    private static let lock = NSLock()

    public static func register(_ plugin: ProviderPlugin) {
        lock.lock()
        defer { lock.unlock() }
        custom.append(plugin)
    }

    public static var all: [ProviderPlugin] {
        lock.lock()
        defer { lock.unlock() }
        return BuiltinProviders.all + custom
    }

    public static func plugin(id: String) -> ProviderPlugin? {
        all.first { $0.id == id }
    }

    // MARK: - Account resolution

    /// Expands each enabled account into concrete cleanup providers — one
    /// per allowed model (or the plugin's full catalog when the account
    /// doesn't restrict models). These join the static `cleanup.providers`
    /// list everywhere models are selectable.
    public static func accountProviders(_ config: TalkyConfig) -> [CleanupProvider] {
        config.accounts.filter(\.enabled).flatMap { account -> [CleanupProvider] in
            guard let plugin = plugin(id: account.provider), plugin.kind == .cleanup,
                  plugin.available else { return [] }
            let models = account.models.isEmpty ? plugin.models.map(\.id) : account.models
            return models.map { model in
                let costs = plugin.costs(for: model)
                return CleanupProvider(
                    id: "\(account.id)/\(model)",
                    baseURL: account.baseURL ?? plugin.defaultBaseURL,
                    model: model,
                    apiKeyEnv: account.apiKeyEnv ?? plugin.keyEnvSuggestion,
                    apiKey: account.apiKey,
                    engine: plugin.engine,
                    inputCostPerMTok: account.inputCostPerMTok ?? costs.input,
                    outputCostPerMTok: account.outputCostPerMTok ?? costs.output,
                    temperature: account.temperature
                )
            }
        }
    }

    /// Static provider entries + account-derived entries.
    public static func allCleanupProviders(_ config: TalkyConfig) -> [CleanupProvider] {
        config.cleanup.providers + accountProviders(config)
    }

    /// The provider the active id points at, searching both layers.
    public static func activeCleanupProvider(_ config: TalkyConfig) -> CleanupProvider? {
        let all = allCleanupProviders(config)
        return all.first { $0.id == config.cleanup.provider } ?? all.first
    }

    // MARK: - Speech-to-text

    /// Apple on-device plus every enabled STT account's models.
    public static func sttProviders(_ config: TalkyConfig) -> [STTProvider] {
        let remote = config.accounts.filter(\.enabled).flatMap { account -> [STTProvider] in
            guard let plugin = plugin(id: account.provider), plugin.kind == .stt, plugin.available else { return [] }
            let models = account.models.isEmpty ? plugin.models.map(\.id) : account.models
            return models.map { model in
                let info = plugin.models.first { $0.id == model }
                return STTProvider(
                    id: "\(account.id)/\(model)",
                    engine: plugin.engine,
                    baseURL: account.baseURL ?? plugin.defaultBaseURL,
                    model: model,
                    apiKeyEnv: account.apiKeyEnv ?? plugin.keyEnvSuggestion,
                    apiKey: account.apiKey,
                    supportsStreaming: info?.streaming ?? false,
                    supportsDiarization: info?.diarization ?? false,
                    costPerMinute: info?.costPerMinute)
            }
        }
        return [.apple] + remote
    }

    public static func activeSTTProvider(_ config: TalkyConfig) -> STTProvider {
        sttProviders(config).first { $0.id == config.stt.provider } ?? .apple
    }
}
