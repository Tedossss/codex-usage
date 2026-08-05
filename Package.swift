// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tideline",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tideline",
            path: "Sources/Tideline",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TidelineTests",
            dependencies: ["Tideline"],
            path: "Tests/TidelineTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
