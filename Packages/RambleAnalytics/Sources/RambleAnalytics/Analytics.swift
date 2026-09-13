import Foundation
import OSLog

public struct AnalyticsEvent: Sendable, Codable, Equatable {
    public let schemaVersion: Int
    public let name: String
    public let properties: [String: String]
}

/// Called serially by Analytics. Reset discards queued events on opt-out.
public protocol AnalyticsAdapter: Sendable {
    func send(_ event: AnalyticsEvent)
    func reset()
    func setEnabled(_ enabled: Bool)
}
public extension AnalyticsAdapter {
    func setEnabled(_ enabled: Bool) {}
}

public struct LoggingAnalyticsAdapter: AnalyticsAdapter {
    private let logger = Logger(subsystem: "io.ramble.analytics", category: "events")
    public init() {}
    public func send(_ event: AnalyticsEvent) {
        guard let data = try? JSONEncoder().encode(event), let json = String(data: data, encoding: .utf8) else { return }
        logger.info("\(json, privacy: .public)")
    }
    public func reset() {}
}

/// Typed calls check consent centrally. No pre-consent buffering or user ID.
public enum Analytics {
    public enum Source: String, Sendable { case microphone, file, text }
    public enum Outcome: String, Sendable { case success, failed, cancelled }
    public enum Stage: String, Sendable { case permission, capture, transcription, cleanup }
    public enum Feature: String, Sendable { case launchAtLogin, recordings, history, cleanup, gestures }
    private final class State: @unchecked Sendable {
        let lock = NSRecursiveLock()
        var enabled = false
        var adapter: any AnalyticsAdapter = LoggingAnalyticsAdapter()
        var previousStart: Date?
    }
    private static let state = State()

    public static func configure(enabled: Bool, adapter: (any AnalyticsAdapter)? = nil) {
        state.lock.lock(); defer { state.lock.unlock() }
        if let adapter { state.adapter.reset(); state.adapter = adapter }
        if !enabled { state.adapter.reset(); state.previousStart = nil }
        state.adapter.setEnabled(enabled)
        state.enabled = enabled
    }
    private static func emit(_ name: String, _ properties: [String: String]) {
        state.lock.lock(); defer { state.lock.unlock() }
        guard state.enabled else { return }
        state.adapter.send(AnalyticsEvent(schemaVersion: 1, name: name, properties: properties))
    }
    public static func appOpened() { emit("app_opened", [:]) }
    public static func featureChanged(_ feature: Feature, enabled: Bool) {
        emit("feature_changed", ["feature": feature.rawValue, "enabled": String(enabled)])
    }
    public static func dictationStarted(source: Source, provider: String, model: String, now: Date = Date()) {
        state.lock.lock(); defer { state.lock.unlock() }
        guard state.enabled else { return }
        let hour = Calendar.current.component(.hour, from: now)
        let interval = state.previousStart.map { bucket(now.timeIntervalSince($0), [60, 300, 1800, 7200, 86400]) } ?? "first_in_process"
        state.previousStart = now
        emit("dictation_started", ["source": source.rawValue, "provider": safeProvider(provider), "model": safeModel(model),
            "local_daypart": ["night", "morning", "afternoon", "evening"][hour / 6], "interval_seconds_bucket": interval])
    }
    public static func dictationCompleted(source: Source, outcome: Outcome, durationSeconds: Double, characterCount: Int,
                                         provider: String = "custom", model: String = "custom") {
        emit("dictation_completed", ["source": source.rawValue, "outcome": outcome.rawValue,
            "provider": safeProvider(provider), "model": safeModel(model),
            "duration_seconds_bucket": bucket(durationSeconds, [5, 15, 30, 60, 180, 600]),
            "character_count_bucket": bucket(Double(characterCount), [50, 200, 500, 1000, 5000])])
    }
    public static func cleanupCompleted(provider: String, model: String, outcome: Outcome, latencySeconds: Double, rejected: Bool) {
        emit("cleanup_completed", ["provider": safeProvider(provider), "model": safeModel(model), "outcome": outcome.rawValue,
            "latency_seconds_bucket": bucket(latencySeconds, [1, 3, 10, 30, 60]), "guard_rejected": String(rejected)])
    }
    public static func cleanupSkipped() { emit("cleanup_skipped", [:]) }
    public static func operationFailed(stage: Stage) { emit("operation_failed", ["stage": stage.rawValue]) }
    private static func bucket(_ value: Double, _ boundaries: [Double]) -> String {
        guard value.isFinite, value >= 0 else { return "unknown" }
        for boundary in boundaries where value < boundary { return "lt_\(Int(boundary))" }
        return "gte_\(Int(boundaries.last!))"
    }
    private static func safeProvider(_ value: String) -> String {
        let allowed: Set<String> = ["apple", "openai", "anthropic", "groq", "mistral", "elevenlabs", "assemblyai", "deepgram", "mlx", "ollama", "lmstudio", "vllm"]
        return allowed.contains(value) ? value : "custom"
    }
    private static func safeModel(_ value: String) -> String {
        let allowed: Set<String> = ["SpeechAnalyzer", "apple-foundation", "qwen3:4b-instruct", "qwen3:8b", "gemma3:1b", "gemma3:4b", "gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1", "whisper-large-v3", "whisper-large-v3-turbo", "voxtral-mini-transcribe-2", "scribe_v2", "scribe_v2_realtime", "claude-haiku-4-5"]
        return allowed.contains(value) ? value : "custom"
    }
}
