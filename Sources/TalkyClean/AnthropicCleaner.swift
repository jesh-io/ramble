import Foundation
import TalkyCore

/// Cleans transcripts with Claude via the Anthropic Messages API
/// (`POST /v1/messages` — Anthropic's native wire format, not an
/// OpenAI-compatible shim).
public struct AnthropicCleaner: TextCleaner {
    public let id: String
    private let endpoint: URL
    private let model: String
    private let apiKey: String?
    private let systemPrompt: String
    private let temperature: Double?
    private let timeout: TimeInterval

    public init(provider: CleanupProvider, systemPrompt: String, timeout: TimeInterval = 30) throws {
        guard var url = URL(string: provider.baseURL) else {
            throw TalkyError("Invalid baseURL for provider '\(provider.id)': \(provider.baseURL)")
        }
        url.append(path: "v1/messages")
        self.id = provider.id
        self.endpoint = url
        self.model = provider.model
        self.apiKey = provider.resolvedAPIKey
        self.systemPrompt = systemPrompt
        self.temperature = provider.temperature
        self.timeout = timeout
    }

    public func clean(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard let apiKey else {
            throw TalkyError("Anthropic account '\(id)' has no API key (set its apiKeyEnv variable)")
        }

        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": systemPrompt,
            "messages": [["role": "user", "content": trimmed]],
        ]
        // Current Claude models (Opus/Sonnet 5+) reject `temperature`; only
        // pass an explicit account-level override.
        if let temperature {
            body["temperature"] = temperature
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw TalkyError("Anthropic '\(id)' returned HTTP \(status): \(snippet)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TalkyError("Anthropic '\(id)' returned an unexpected response shape")
        }

        if let usage = json["usage"] as? [String: Any] {
            UsageLog.record(
                kind: "cleanup", provider: id, model: model,
                tokensIn: usage["input_tokens"] as? Int,
                tokensOut: usage["output_tokens"] as? Int)
        }

        if let stopReason = json["stop_reason"] as? String, stopReason == "refusal" {
            throw TalkyError("Anthropic '\(id)' declined the request (stop_reason: refusal)")
        }
        let textBlocks = (json["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
        let cleaned = OpenAICompatCleaner.postProcess(textBlocks.joined())
        guard !cleaned.isEmpty else {
            throw TalkyError("Anthropic '\(id)' returned empty text")
        }
        return cleaned
    }
}
