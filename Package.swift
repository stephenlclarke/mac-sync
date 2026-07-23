// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "mac-sync",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "mac-sync", targets: ["MacSyncCLI"]),
        .executable(name: "mac-spinner", targets: ["MacSyncSpinner"]),
        .executable(name: "MacSync", targets: ["MacSyncApp"]),
        .library(name: "MacSyncCore", targets: ["MacSyncCore"]),
    ],
    targets: [
        .target(
            name: "MacSyncCore",
            path: "Sources/MacSyncCore",
        ),
        .executableTarget(
            name: "MacSyncCLI",
            dependencies: ["MacSyncCore"],
            path: "Sources/MacSyncCLI",
        ),
        .executableTarget(
            name: "MacSyncSpinner",
            path: "Sources/MacSyncSpinner",
        ),
        .executableTarget(
            name: "MacSyncApp",
            dependencies: ["MacSyncCore"],
            path: "Sources/MacSyncApp",
            exclude: ["Resources"],
        ),
        .testTarget(
            name: "MacSyncCoreTests",
            dependencies: ["MacSyncCore"],
            path: "tests/MacSyncCoreTests",
        ),
        .testTarget(
            name: "MacSyncAppTests",
            dependencies: ["MacSyncApp"],
            path: "tests/MacSyncAppTests",
        ),
    ],
)
