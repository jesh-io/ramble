// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "RambleAnalytics", platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "RambleAnalytics", targets: ["RambleAnalytics"])],
    targets: [.target(name: "RambleAnalytics"), .testTarget(name: "RambleAnalyticsTests", dependencies: ["RambleAnalytics"])])
