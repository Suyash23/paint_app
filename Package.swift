// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PaintCoach",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PaintCoachCore", targets: ["PaintCoachCore"]),
        .library(name: "PaintCoachMetal", targets: ["PaintCoachMetal"]),
        .executable(name: "PaintCoachApp", targets: ["PaintCoachApp"])
    ],
    targets: [
        // Pure, platform-free. Must never import CoreGraphics/UIKit/Metal.
        .target(name: "PaintCoachCore"),
        .testTarget(name: "PaintCoachCoreTests", dependencies: ["PaintCoachCore"]),

        // Metal backend. Kept a separate target so Core stays pure and the
        // device-risk boundary is visible in the package structure.
        .target(
            name: "PaintCoachMetal",
            dependencies: ["PaintCoachCore"],
            resources: [.process("Shaders")]
        ),

        // Minimal harness whose only job is to put the Metal backend on screen
        // so the unverified parts of it can be seen to work or fail.
        .executableTarget(
            name: "PaintCoachApp",
            dependencies: ["PaintCoachCore", "PaintCoachMetal"]
        )
    ]
)
