// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ScanSong",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MediaScannerKit", targets: ["MediaScannerKit"]),
        .executable(name: "media-scan", targets: ["media-scan"]),
        .executable(name: "ScanSong", targets: ["MediaScannerApp"])
    ],
    targets: [
        .systemLibrary(
            name: "CGameMusicEmu",
            path: "Sources/CGME",
            pkgConfig: "libgme",
            providers: [.brew(["game-music-emu"])]
        ),
        .target(
            name: "MediaScannerKit",
            dependencies: ["CGameMusicEmu"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(name: "media-scan", dependencies: ["MediaScannerKit"]),
        .executableTarget(
            name: "MediaScannerApp",
            dependencies: ["MediaScannerKit"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(name: "MediaScannerKitTests", dependencies: ["MediaScannerKit"])
    ],
    swiftLanguageModes: [.v6]
)
