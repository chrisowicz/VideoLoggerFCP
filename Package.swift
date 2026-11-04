// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VideoLoggerFCP",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VideoLoggerCore", targets: ["VideoLoggerCore"]),
        .executable(name: "videologger", targets: ["VideoLoggerCLI"]),
        .executable(name: "videologger-drag", targets: ["VideoLoggerDragApp"]),
    ],
    targets: [
        .target(name: "VideoLoggerLocalization", resources: [.process("Resources")]),
        .target(name: "VideoLoggerCore", dependencies: ["VideoLoggerLocalization"]),
        .executableTarget(name: "VideoLoggerCLI", dependencies: ["VideoLoggerCore", "VideoLoggerLocalization"]),
        .testTarget(name: "VideoLoggerCoreTests", dependencies: ["VideoLoggerCore", "VideoLoggerTestSupport", "VideoLoggerLocalization"]),
        .testTarget(name: "VideoLoggerCLITests", dependencies: ["VideoLoggerCLI", "VideoLoggerCore", "VideoLoggerLocalization"]),
        .target(name: "VideoLoggerDragDrop", dependencies: ["VideoLoggerCore", "VideoLoggerLocalization"]),
        .executableTarget(name: "VideoLoggerDragApp", dependencies: ["VideoLoggerDragDrop", "VideoLoggerCore", "VideoLoggerLocalization"]),
        .testTarget(name: "VideoLoggerLocalizationTests", dependencies: ["VideoLoggerLocalization", "VideoLoggerCore"]),
        .target(name: "VideoLoggerTestSupport", path: "Tests/Fixtures", resources: [.copy("Projects")]),
        .testTarget(name: "VideoLoggerDragDropTests", dependencies: ["VideoLoggerDragDrop", "VideoLoggerCore", "VideoLoggerTestSupport", "VideoLoggerLocalization"]),
    ]
)
