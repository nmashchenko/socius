// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Socius",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Socius", targets: ["Socius"])],
    targets: [
        .target(name: "CyclopTools", path: "Vendor/Cyclop/Sources", swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "Socius", dependencies: ["CyclopTools"], swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
        .testTarget(name: "SociusTests", dependencies: ["Socius"]),
        .testTarget(name: "CyclopToolsTests", dependencies: ["CyclopTools"])
    ]
)
