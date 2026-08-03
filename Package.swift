// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PaintCoach",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PaintCoachCore", targets: ["PaintCoachCore"]),
        .library(name: "PaintCoachMetal", targets: ["PaintCoachMetal"]),
        .library(name: "PaintCoachUI", targets: ["PaintCoachUI"]),
        .executable(name: "PaintCoachApp", targets: ["PaintCoachApp"])
    ],
    targets: [
        // Pure, platform-free. Must never import CoreGraphics/UIKit/Metal.
        .target(name: "PaintCoachCore"),
        .testTarget(name: "PaintCoachCoreTests", dependencies: ["PaintCoachCore"]),

        // Metal backend. Separate target so Core stays pure and the device-risk
        // boundary is visible in the package structure.
        .target(
            name: "PaintCoachMetal",
            dependencies: ["PaintCoachCore"],
            resources: [.process("Shaders")]
        ),

        // UIKit/SwiftUI layer. iOS-only in practice; guarded with canImport so
        // the package still builds on macOS for the verification harness.
        .target(
            name: "PaintCoachUI",
            dependencies: ["PaintCoachCore", "PaintCoachMetal"]
        ),

        // Offscreen verification harness. Renders known documents through the
        // real Metal backend and asserts on pixels read back.
        .executableTarget(
            name: "PaintCoachApp",
            dependencies: ["PaintCoachCore", "PaintCoachMetal"]
        )
    ]
)
