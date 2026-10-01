// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexPulse",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexPulseCore", targets: ["CodexPulseCore"]),
        .executable(name: "codex-pulse-probe", targets: ["CodexPulseProbe"])
    ],
    targets: [
        .target(name: "CodexPulseCore"),
        .executableTarget(name: "CodexPulseProbe", dependencies: ["CodexPulseCore"]),
        .testTarget(
            name: "CodexPulseCoreTests",
            dependencies: ["CodexPulseCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
