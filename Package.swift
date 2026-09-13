// swift-tools-version: 6.2
import PackageDescription
import Foundation

let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]
let gesturesEnabled = ProcessInfo.processInfo.environment["RAMBLE_ENABLE_GESTURES"] == "1"

let package = Package(
    name: "Ramble",
    platforms: [.macOS(.v26), .iOS(.v26)],
    // OpenMultitouchSupport wraps Apple's private MultitouchSupport
    // framework (trackpad gestures). RambleGestures is an optional add-on:
    // excluded from the app by default. Set RAMBLE_ENABLE_GESTURES=1 to
    // add the target dependency and RAMBLE_GESTURES compilation flag.
    products: [
        .library(name: "RambleKit", targets: ["RambleKit"]),
        .library(name: "RambleCore", targets: ["RambleCore"]),
        .library(name: "RambleAudio", targets: ["RambleAudio"]),
        .library(name: "RambleTranscribe", targets: ["RambleTranscribe"]),
        .library(name: "RambleSTTElevenLabs", targets: ["RambleSTTElevenLabs"]),
        .library(name: "RambleSTTAssemblyAI", targets: ["RambleSTTAssemblyAI"]),
        .library(name: "RambleSTTDeepgram", targets: ["RambleSTTDeepgram"]),
        .library(name: "RambleSTTOpenAI", targets: ["RambleSTTOpenAI"]),
        .library(name: "RambleSTTMistral", targets: ["RambleSTTMistral"]),
        .library(name: "RambleSTTGroq", targets: ["RambleSTTGroq"]),
        .library(name: "RambleClean", targets: ["RambleClean"]),
        .library(name: "RambleProviders", targets: ["RambleProviders"]),
        .library(name: "RambleGestures", targets: ["RambleGestures"]),
        .executable(name: "ramble", targets: ["RambleCLI"]),
        .executable(name: "RambleApp", targets: ["RambleApp"]),
    ],
    dependencies: [
        .package(path: "Packages/RambleAnalytics"),
        .package(url: "https://github.com/Kyome22/OpenMultitouchSupport", from: "4.0.0"),
    ],
    targets: [
        .target(name: "RambleCore", dependencies: [.product(name: "RambleAnalytics", package: "RambleAnalytics")], swiftSettings: swiftSettings),
        .target(name: "RambleAudio", dependencies: ["RambleCore"], swiftSettings: swiftSettings),
        .target(name: "RambleTranscribe", dependencies: ["RambleCore"], swiftSettings: swiftSettings),
        // Speech-to-text plugins: each is optional — remove one from RambleKit's
        // dependencies below to build without it (RambleKit gates on canImport).
        .target(name: "RambleSTTElevenLabs", dependencies: ["RambleCore", "RambleTranscribe"], swiftSettings: swiftSettings),
        .target(name: "RambleSTTAssemblyAI", dependencies: ["RambleCore", "RambleTranscribe"], swiftSettings: swiftSettings),
        .target(name: "RambleSTTDeepgram", dependencies: ["RambleCore", "RambleTranscribe"], swiftSettings: swiftSettings),
        .target(name: "RambleSTTOpenAI", dependencies: ["RambleCore", "RambleTranscribe"], swiftSettings: swiftSettings),
        .target(name: "RambleSTTMistral", dependencies: ["RambleCore", "RambleTranscribe"], swiftSettings: swiftSettings),
        .target(name: "RambleSTTGroq", dependencies: ["RambleCore", "RambleTranscribe"], swiftSettings: swiftSettings),
        .target(name: "RambleClean", dependencies: ["RambleCore"], swiftSettings: swiftSettings),
        .target(name: "RambleProviders", dependencies: ["RambleCore"], swiftSettings: swiftSettings),
        .target(
            name: "RambleGestures",
            dependencies: [
                "RambleCore",
                .product(name: "OpenMultitouchSupport", package: "OpenMultitouchSupport"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "RambleKit",
            dependencies: [
                "RambleCore", "RambleAudio", "RambleTranscribe", "RambleClean", "RambleProviders",
                "RambleSTTElevenLabs", "RambleSTTAssemblyAI", "RambleSTTDeepgram", "RambleSTTOpenAI", "RambleSTTMistral", "RambleSTTGroq",
            ],
            swiftSettings: swiftSettings
        ),
        .executableTarget(name: "RambleCLI", dependencies: ["RambleKit", "RambleProviders"], swiftSettings: swiftSettings),
        .executableTarget(
            name: "RambleApp",
            dependencies: ["RambleKit", "RambleProviders"] + (gesturesEnabled ? ["RambleGestures"] : []),
            swiftSettings: swiftSettings + (gesturesEnabled ? [.define("RAMBLE_GESTURES")] : [])
        ),
        .testTarget(name: "RambleTests", dependencies: ["RambleCore", "RambleClean", "RambleProviders", "RambleSTTElevenLabs"]),
    ]
)
