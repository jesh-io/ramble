import Foundation
import TalkyCore

/// Cleans transcripts through any OpenAI-compatible chat-completions
/// endpoint — local (Ollama, LM Studio, vLLM, llama.cpp server) or remote
/// (OpenAI, Groq, OpenRouter, Mistral, ...). The provider is pure config;
/// the wire format is identical.
public struct OpenAICompatCleaner: TextCleaner {
    public let id: String
    private let endpoint: URL
    private let model: String
    private let apiKey: String?
    private let systemPrompt: String
    private let timeout: TimeInterval

    public init(provider: CleanupProvider, systemPrompt: String, timeout: TimeInterval = 30) throws {
        guard var url = URL(string: provider.baseURL) else {
            throw TalkyError("Invalid baseURL for provider '\(provider.id)': \(provider.baseURL)")
        }
        url.append(path: "chat/completions")
        self.id = provider.id
        self.endpoint = url
        self.model = provider.model
        self.apiKey = provider.resolvedAPIKey
        self.systemPrompt = systemPrompt
        self.timeout = timeout
    }

    public func clean(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": trimmed],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw TalkyError("Cleanup provider '\(id)' returned HTTP \(status): \(snippet)")
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw TalkyError("Cleanup provider '\(id)' returned an unexpected response shape")
        }

        let cleaned = Self.postProcess(content)
        guard !cleaned.isEmpty else {
            throw TalkyError("Cleanup provider '\(id)' returned empty text")
        }
        return cleaned
    }

    /// Strips reasoning tags, code fences, and wrapping quotes some models
    /// add despite instructions. Shared by other cleaner engines.
    public static func postProcess(_ raw: String) -> String {
        var text = raw

        // Reasoning models: drop <think>...</think> blocks.
        while let open = text.range(of: "<think>"), let close = text.range(of: "</think>") {
            guard open.lowerBound < close.upperBound else { break }
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Unwrap a single full-message code fence.
        if text.hasPrefix("```"), text.hasSuffix("```"), text.count > 6 {
            var lines = text.components(separatedBy: "\n")
            if lines.count >= 2 {
                lines.removeFirst()
                lines.removeLast()
                text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Unwrap full-message quotes.
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count > 2 {
            let inner = String(text.dropFirst().dropLast())
            if !inner.contains("\"") {
                text = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return text
    }
}
