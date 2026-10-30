// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FocusLens",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FocusLens", targets: ["FocusLens"])],
    targets: [
        .target(name: "LensCore"),
        .executableTarget(name: "FocusLens", dependencies: ["LensCore"], swiftSettings: [
            .defaultIsolation(MainActor.self),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault")
        ]),
        .testTarget(name: "LensCoreTests", dependencies: ["LensCore"])
    ]
)
