import Foundation
import TalkyCore
import TalkyTranscribe
import TalkyProviders
#if canImport(TalkySTTElevenLabs)
import TalkySTTElevenLabs
#endif
#if canImport(TalkySTTAssemblyAI)
import TalkySTTAssemblyAI
#endif
#if canImport(TalkySTTDeepgram)
import TalkySTTDeepgram
#endif
#if canImport(TalkySTTOpenAI)
import TalkySTTOpenAI
#endif
#if canImport(TalkySTTMistral)
import TalkySTTMistral
#endif
#if canImport(TalkySTTGroq)
import TalkySTTGroq
#endif

/// Registers whichever speech-to-text plugins are compiled in. Each plugin
/// is an optional SPM target; drop it from TalkyKit's dependencies to
/// build without it.
public enum STTPlugins {
    private static let once: Void = {
        #if canImport(TalkySTTElevenLabs)
        ElevenLabsSTTPlugin.register()
        #endif
        #if canImport(TalkySTTAssemblyAI)
        AssemblyAISTTPlugin.register()
        #endif
        #if canImport(TalkySTTDeepgram)
        DeepgramSTTPlugin.register()
        #endif
        #if canImport(TalkySTTOpenAI)
        OpenAISTTPlugin.register()
        #endif
        #if canImport(TalkySTTMistral)
        MistralSTTPlugin.register()
        #endif
        #if canImport(TalkySTTGroq)
        GroqSTTPlugin.register()
        #endif
    }()

    public static func registerAll() { _ = once }

    /// STT providers whose engine is actually available in this build.
    public static func availableProviders(_ config: TalkyConfig) -> [STTProvider] {
        registerAll()
        let engines = Set(TranscriberFactory.registeredEngines + ["apple"])
        return ProviderRegistry.sttProviders(config).filter { engines.contains($0.engine) }
    }
}
