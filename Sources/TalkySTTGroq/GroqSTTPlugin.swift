import Foundation
import TalkyCore
import TalkyTranscribe

/// Groq-hosted Whisper (batch only; OpenAI-compatible transcription API).
public enum GroqSTTPlugin {
    public static func register() {
        TranscriberFactory.register(engine: "groq") { provider, options in
            OpenAICompatBatchTranscriber(provider: provider, options: options)
        }
    }
}
