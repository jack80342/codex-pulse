// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexPulse",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexPulseCore", targets: ["CodexPulseCore"]),
        .executable(name: "codex-pulse-probe", targets: ["CodexPulseProbe"]),
        .executable(name: "codex-pulse", targets: ["CodexPulseCLI"]),
        .executable(name: "CodexPulseApp", targets: ["CodexPulseApp"])
    ],
    targets: [
        .target(name: "CodexPulseCore"),
        .target(name: "CodexPulseUI", dependencies: ["CodexPulseCore"]),
        .executableTarget(name: "CodexPulseApp", dependencies: ["CodexPulseUI"]),
        .executableTarget(name: "CodexPulseProbe", dependencies: ["CodexPulseCore"]),
        .executableTarget(name: "CodexPulseCLI", dependencies: ["CodexPulseCore"]),
        .testTarget(
            name: "CodexPulseCoreTests",
            dependencies: ["CodexPulseCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "CodexPulseUITests", dependencies: ["CodexPulseUI", "CodexPulseCore"])
    ]
)
