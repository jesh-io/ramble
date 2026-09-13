import Foundation
import RambleCore
import RambleTranscribe
import RambleProviders
#if canImport(RambleSTTElevenLabs)
import RambleSTTElevenLabs
#endif
#if canImport(RambleSTTAssemblyAI)
import RambleSTTAssemblyAI
#endif
#if canImport(RambleSTTDeepgram)
import RambleSTTDeepgram
#endif
#if canImport(RambleSTTOpenAI)
import RambleSTTOpenAI
#endif
#if canImport(RambleSTTMistral)
import RambleSTTMistral
#endif
#if canImport(RambleSTTGroq)
import RambleSTTGroq
#endif

/// Registers whichever speech-to-text plugins are compiled in. Each plugin
/// is an optional SPM target; drop it from RambleKit's dependencies to
/// build without it.
public enum STTPlugins {
    private static let once: Void = {
        #if canImport(RambleSTTElevenLabs)
        ElevenLabsSTTPlugin.register()
        #endif
        #if canImport(RambleSTTAssemblyAI)
        AssemblyAISTTPlugin.register()
        #endif
        #if canImport(RambleSTTDeepgram)
        DeepgramSTTPlugin.register()
        #endif
        #if canImport(RambleSTTOpenAI)
        OpenAISTTPlugin.register()
        #endif
        #if canImport(RambleSTTMistral)
        MistralSTTPlugin.register()
        #endif
        #if canImport(RambleSTTGroq)
        GroqSTTPlugin.register()
        #endif
    }()

    public static func registerAll() { _ = once }

    /// STT providers whose engine is actually available in this build.
    public static func availableProviders(_ config: RambleConfig) -> [STTProvider] {
        registerAll()
        let engines = Set(TranscriberFactory.registeredEngines + ["apple"])
        return ProviderRegistry.sttProviders(config).filter { engines.contains($0.engine) }
    }
}
