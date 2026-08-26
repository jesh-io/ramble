import Foundation

/// Built-in integrations, one definition per provider. Model catalogs are
/// curated starting points with default cost rates (USD/M tokens) — edit
/// per account or in config; local providers cost 0.
enum BuiltinProviders {
    static let all: [ProviderPlugin] = [
        // MARK: Local (free, private)
        ProviderPlugin(
            id: "ollama", name: "Ollama", engine: "openai",
            defaultBaseURL: "http://localhost:11434/v1", apiKeyRequired: false,
            models: [
                ModelInfo("qwen3:4b-instruct", note: "best local cleanup tested"),
                ModelInfo("qwen3:8b"),
                ModelInfo("gemma3:4b"),
                ModelInfo("llama3.2:3b"),
            ]),
        ProviderPlugin(
            id: "lmstudio", name: "LM Studio", engine: "openai",
            defaultBaseURL: "http://localhost:1234/v1", apiKeyRequired: false,
            models: [ModelInfo("local-model", note: "whatever is loaded in LM Studio")]),
        ProviderPlugin(
            id: "vllm", name: "vLLM", engine: "openai",
            defaultBaseURL: "http://localhost:8000/v1", apiKeyRequired: false,
            models: []),
        ProviderPlugin(
            id: "apple", name: "Apple Intelligence", engine: "apple",
            defaultBaseURL: "on-device", apiKeyRequired: false,
            models: [ModelInfo("apple-foundation", note: "built-in on-device model")]),
        ProviderPlugin(
            id: "mlx", name: "MLX (on-device)", engine: "mlx",
            defaultBaseURL: "on-device", apiKeyRequired: false,
            models: [ModelInfo("mlx-community/Qwen3-4B-Instruct-2507-4bit", note: "iOS app only")]),

        // MARK: Remote — text
        ProviderPlugin(
            id: "anthropic", name: "Anthropic", engine: "anthropic",
            defaultBaseURL: "https://api.anthropic.com", apiKeyRequired: true,
            keyEnvSuggestion: "ANTHROPIC_API_KEY",
            models: [
                ModelInfo("claude-opus-5", input: 5, output: 25),
                ModelInfo("claude-sonnet-5", input: 2, output: 10),
                ModelInfo("claude-haiku-4-5", input: 1, output: 5, note: "fast + cheap, great for cleanup"),
            ]),
        ProviderPlugin(
            id: "openai", name: "OpenAI", engine: "openai",
            defaultBaseURL: "https://api.openai.com/v1", apiKeyRequired: true,
            keyEnvSuggestion: "OPENAI_API_KEY",
            models: [
                ModelInfo("gpt-5", input: 1.25, output: 10),
                ModelInfo("gpt-5-mini", input: 0.25, output: 2),
                ModelInfo("gpt-5-nano", input: 0.05, output: 0.4),
            ]),
        ProviderPlugin(
            id: "groq", name: "Groq", engine: "openai",
            defaultBaseURL: "https://api.groq.com/openai/v1", apiKeyRequired: true,
            keyEnvSuggestion: "GROQ_API_KEY",
            models: [
                ModelInfo("llama-3.3-70b-versatile", input: 0.59, output: 0.79),
                ModelInfo("llama-3.1-8b-instant", input: 0.05, output: 0.08),
            ]),
        ProviderPlugin(
            id: "openrouter", name: "OpenRouter", engine: "openai",
            defaultBaseURL: "https://openrouter.ai/api/v1", apiKeyRequired: true,
            keyEnvSuggestion: "OPENROUTER_API_KEY",
            models: [ModelInfo("auto", note: "any OpenRouter model id works")]),
        ProviderPlugin(
            id: "mistral", name: "Mistral", engine: "openai",
            defaultBaseURL: "https://api.mistral.ai/v1", apiKeyRequired: true,
            keyEnvSuggestion: "MISTRAL_API_KEY",
            models: [ModelInfo("mistral-small-latest", input: 0.1, output: 0.3)]),
        ProviderPlugin(
            id: "together", name: "Together AI", engine: "openai",
            defaultBaseURL: "https://api.together.xyz/v1", apiKeyRequired: true,
            keyEnvSuggestion: "TOGETHER_API_KEY",
            models: []),
        ProviderPlugin(
            id: "deepseek", name: "DeepSeek", engine: "openai",
            defaultBaseURL: "https://api.deepseek.com/v1", apiKeyRequired: true,
            keyEnvSuggestion: "DEEPSEEK_API_KEY",
            models: [ModelInfo("deepseek-chat", input: 0.27, output: 1.1)]),
        ProviderPlugin(
            id: "xai", name: "xAI", engine: "openai",
            defaultBaseURL: "https://api.x.ai/v1", apiKeyRequired: true,
            keyEnvSuggestion: "XAI_API_KEY",
            models: [ModelInfo("grok-4-fast", input: 0.2, output: 0.5)]),

        // MARK: Remote — speech-to-text (catalogued; engines land with the
        // remote-STT phase. Per-second billing is already supported by the
        // usage ledger.)
        ProviderPlugin(
            id: "assemblyai", name: "AssemblyAI", kind: .stt, engine: "stt-remote",
            defaultBaseURL: "https://api.assemblyai.com", apiKeyRequired: true,
            keyEnvSuggestion: "ASSEMBLYAI_API_KEY",
            models: [ModelInfo("universal", note: "incl. diarization")], available: false),
        ProviderPlugin(
            id: "deepgram", name: "Deepgram", kind: .stt, engine: "stt-remote",
            defaultBaseURL: "https://api.deepgram.com", apiKeyRequired: true,
            keyEnvSuggestion: "DEEPGRAM_API_KEY",
            models: [ModelInfo("nova-3", note: "incl. diarization")], available: false),
    ]
}
