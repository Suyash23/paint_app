// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PaintCoach",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PaintCoachCore", targets: ["PaintCoachCore"])
    ],
    targets: [
        .target(name: "PaintCoachCore"),
        .testTarget(name: "PaintCoachCoreTests", dependencies: ["PaintCoachCore"])
    ]
)
