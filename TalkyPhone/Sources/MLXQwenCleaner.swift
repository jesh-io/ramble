import Foundation
import TalkyCore
import TalkyClean
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// On-device Qwen cleanup via MLX. The provider's `model` field is an MLX
/// community model id (downloaded once from Hugging Face, then fully local),
/// e.g. "mlx-community/Qwen3-4B-Instruct-2507-4bit".
/// Registered as engine "mlx" — add a provider like:
///   { "id": "mlx-qwen", "engine": "mlx", "baseURL": "on-device",
///     "model": "mlx-community/Qwen3-4B-Instruct-2507-4bit" }
final class MLXQwenCleaner: TextCleaner, @unchecked Sendable {
    let id: String
    private let modelID: String
    private let systemPrompt: String

    // The loaded model is large; keep it cached across dictations.
    private static var cachedContainer: ModelContainer?
    private static var cachedModelID: String?

    init(provider: CleanupProvider, systemPrompt: String) {
        self.id = provider.id
        self.modelID = provider.model
        self.systemPrompt = systemPrompt
    }

    static func register() {
        CleanerFactory.register(engine: "mlx") { provider, systemPrompt, _ in
            MLXQwenCleaner(provider: provider, systemPrompt: systemPrompt)
        }
    }

    func clean(_ text: String) async throws -> String {
        let container: ModelContainer
        if let cached = Self.cachedContainer, Self.cachedModelID == modelID {
            container = cached
        } else {
            container = try await #huggingFaceLoadModelContainer(
                configuration: ModelConfiguration(id: modelID))
            Self.cachedContainer = container
            Self.cachedModelID = modelID
        }

        let prompt = systemPrompt
        let output = try await container.perform { context in
            let input = try await context.processor.prepare(
                input: UserInput(chat: [
                    .system(prompt),
                    .user(text),
                ]))
            var collected = ""
            let params = GenerateParameters(temperature: 0.1)
            let stream = try MLXLMCommon.generate(input: input, parameters: params, context: context)
            for await generation in stream {
                if case .chunk(let chunk) = generation {
                    collected += chunk
                }
            }
            return collected
        }

        let cleaned = OpenAICompatCleaner.postProcess(output)
        guard !cleaned.isEmpty else {
            throw TalkyError("MLX model returned empty text")
        }
        return cleaned
    }
}
