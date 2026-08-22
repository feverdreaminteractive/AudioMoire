// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioMoire",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AudioMoire",
            resources: [.process("Shaders.metal")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
