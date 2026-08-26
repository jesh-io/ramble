// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Talky",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "TalkyKit", targets: ["TalkyKit"]),
        .library(name: "TalkyCore", targets: ["TalkyCore"]),
        .library(name: "TalkyAudio", targets: ["TalkyAudio"]),
        .library(name: "TalkyTranscribe", targets: ["TalkyTranscribe"]),
        .library(name: "TalkyClean", targets: ["TalkyClean"]),
        .executable(name: "talky", targets: ["TalkyCLI"]),
        .executable(name: "TalkyApp", targets: ["TalkyApp"]),
    ],
    targets: [
        .target(name: "TalkyCore", swiftSettings: swiftSettings),
        .target(name: "TalkyAudio", dependencies: ["TalkyCore"], swiftSettings: swiftSettings),
        .target(name: "TalkyTranscribe", dependencies: ["TalkyCore"], swiftSettings: swiftSettings),
        .target(name: "TalkyClean", dependencies: ["TalkyCore"], swiftSettings: swiftSettings),
        .target(
            name: "TalkyKit",
            dependencies: ["TalkyCore", "TalkyAudio", "TalkyTranscribe", "TalkyClean"],
            swiftSettings: swiftSettings
        ),
        .executableTarget(name: "TalkyCLI", dependencies: ["TalkyKit"], swiftSettings: swiftSettings),
        .executableTarget(name: "TalkyApp", dependencies: ["TalkyKit"], swiftSettings: swiftSettings),
    ]
)
