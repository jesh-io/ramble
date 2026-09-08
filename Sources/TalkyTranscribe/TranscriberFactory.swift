import Foundation
import TalkyCore

/// Options every STT engine receives.
public struct STTOptions: Sendable {
    public var locale: Locale
    /// Personal vocabulary terms (bare spellings) for recognizer biasing /
    /// keyword boosting where the API supports it.
    public var vocabulary: [String]
    /// "auto" | "streaming" | "batch" — see `STTConfig.mode`.
    public var mode: String
    /// Request speaker labels when the engine supports diarization.
    public var diarize: Bool

    public init(locale: Locale, vocabulary: [String] = [], mode: String = "auto", diarize: Bool = false) {
        self.locale = locale
        self.vocabulary = vocabulary
        self.mode = mode
        self.diarize = diarize
    }

    /// True when the caller wants live partials and the engine can stream.
    public func wantsStreaming(engineSupportsStreaming: Bool) -> Bool {
        mode != "batch" && engineSupportsStreaming
    }
}

/// Registry of speech-to-text engines. Plugin modules register a builder
/// for their `engine` id at startup; `make` resolves the config's choice.
public enum TranscriberFactory {
    public typealias Builder = @Sendable (STTProvider, STTOptions) throws -> any Transcriber

    private static let lock = NSLock()
    private nonisolated(unsafe) static var builders: [String: Builder] = [:]

    public static func register(engine: String, _ builder: @escaping Builder) {
        lock.withLock { builders[engine] = builder }
    }

    public static var registeredEngines: [String] {
        lock.withLock { Array(builders.keys).sorted() }
    }

    public static func make(provider: STTProvider, options: STTOptions) throws -> any Transcriber {
        if provider.engine == "apple" {
            return AppleTranscriber(locale: options.locale, vocabulary: options.vocabulary)
        }
        guard let builder = lock.withLock({ builders[provider.engine] }) else {
            throw TalkyError("Speech engine '\(provider.engine)' is not available in this build (provider '\(provider.id)')")
        }
        return try builder(provider, options)
    }
}
