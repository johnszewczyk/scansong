// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "MediaScanner",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MediaScannerKit", targets: ["MediaScannerKit"]),
        .executable(name: "media-scan", targets: ["media-scan"])
    ],
    targets: [
        .target(
            name: "MediaScannerKit",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(name: "media-scan", dependencies: ["MediaScannerKit"]),
        .testTarget(name: "MediaScannerKitTests", dependencies: ["MediaScannerKit"])
    ],
    swiftLanguageModes: [.v6]
)
