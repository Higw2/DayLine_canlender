// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DayLine",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DayLineCore", targets: ["DayLineCore"]),
        .executable(name: "DayLine", targets: ["DayLineApp"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "DayLineCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "DayLineApp", dependencies: ["DayLineCore"]),
        .testTarget(name: "DayLineCoreTests", dependencies: ["DayLineCore"])
    ],
    swiftLanguageVersions: [.v5]
)
