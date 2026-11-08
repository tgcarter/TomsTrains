// swift-tools-version: 6.0
import PackageDescription

// Portable tests for route and timetable logic. The iPhone app uses the Xcode project.
let package = Package(
    name: "TomsTrainsCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TomsTrainsCore", targets: ["TomsTrainsCore"])],
    targets: [
        .target(name: "TomsTrainsCore", path: "Shared"),
        .testTarget(name: "TomsTrainsCoreTests", dependencies: ["TomsTrainsCore"], path: "TomsTrainsTests")
    ]
)
