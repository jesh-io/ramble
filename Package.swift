// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Talky",
    platforms: [.macOS(.v26), .iOS(.v26)],
    // OpenMultitouchSupport wraps Apple's private MultitouchSupport
    // framework (trackpad gestures). TalkyGestures is an optional add-on:
    // to publish a build without private-API usage, remove "TalkyGestures"
    // from TalkyApp's dependencies below — the app code gates on
    // canImport(TalkyGestures) and compiles cleanly without it.
    products: [
        .library(name: "TalkyKit", targets: ["TalkyKit"]),
        .library(name: "TalkyCore", targets: ["TalkyCore"]),
        .library(name: "TalkyAudio", targets: ["TalkyAudio"]),
        .library(name: "TalkyTranscribe", targets: ["TalkyTranscribe"]),
        .library(name: "TalkySTTElevenLabs", targets: ["TalkySTTElevenLabs"]),
        .library(name: "TalkySTTAssemblyAI", targets: ["TalkySTTAssemblyAI"]),
        .library(name: "TalkySTTDeepgram", targets: ["TalkySTTDeepgram"]),
        .library(name: "TalkySTTOpenAI", targets: ["TalkySTTOpenAI"]),
        .library(name: "TalkySTTMistral", targets: ["TalkySTTMistral"]),
        .library(name: "TalkySTTGroq", targets: ["TalkySTTGroq"]),
        .library(name: "TalkyClean", targets: ["TalkyClean"]),
        .library(name: "TalkyProviders", targets: ["TalkyProviders"]),
        .library(name: "TalkyGestures", targets: ["TalkyGestures"]),
        .executable(name: "talky", targets: ["TalkyCLI"]),
        .executable(name: "TalkyApp", targets: ["TalkyApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Kyome22/OpenMultitouchSupport", from: "4.0.0"),
    ],
    targets: [
        .target(name: "TalkyCore", swiftSettings: swiftSettings),
        .target(name: "TalkyAudio", dependencies: ["TalkyCore"], swiftSettings: swiftSettings),
        .target(name: "TalkyTranscribe", dependencies: ["TalkyCore"], swiftSettings: swiftSettings),
        // Speech-to-text plugins: each is optional — remove one from TalkyKit's
        // dependencies below to build without it (TalkyKit gates on canImport).
        .target(name: "TalkySTTElevenLabs", dependencies: ["TalkyCore", "TalkyTranscribe"], swiftSettings: swiftSettings),
        .target(name: "TalkySTTAssemblyAI", dependencies: ["TalkyCore", "TalkyTranscribe"], swiftSettings: swiftSettings),
        .target(name: "TalkySTTDeepgram", dependencies: ["TalkyCore", "TalkyTranscribe"], swiftSettings: swiftSettings),
        .target(name: "TalkySTTOpenAI", dependencies: ["TalkyCore", "TalkyTranscribe"], swiftSettings: swiftSettings),
        .target(name: "TalkySTTMistral", dependencies: ["TalkyCore", "TalkyTranscribe"], swiftSettings: swiftSettings),
        .target(name: "TalkySTTGroq", dependencies: ["TalkyCore", "TalkyTranscribe"], swiftSettings: swiftSettings),
        .target(name: "TalkyClean", dependencies: ["TalkyCore"], swiftSettings: swiftSettings),
        .target(name: "TalkyProviders", dependencies: ["TalkyCore"], swiftSettings: swiftSettings),
        .target(
            name: "TalkyGestures",
            dependencies: [
                "TalkyCore",
                .product(name: "OpenMultitouchSupport", package: "OpenMultitouchSupport"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "TalkyKit",
            dependencies: [
                "TalkyCore", "TalkyAudio", "TalkyTranscribe", "TalkyClean", "TalkyProviders",
                "TalkySTTElevenLabs", "TalkySTTAssemblyAI", "TalkySTTDeepgram", "TalkySTTOpenAI", "TalkySTTMistral", "TalkySTTGroq",
            ],
            swiftSettings: swiftSettings
        ),
        .executableTarget(name: "TalkyCLI", dependencies: ["TalkyKit", "TalkyProviders"], swiftSettings: swiftSettings),
        .executableTarget(
            name: "TalkyApp",
            dependencies: ["TalkyKit", "TalkyProviders", "TalkyGestures"],
            swiftSettings: swiftSettings
        ),
    ]
)
