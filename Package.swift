// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ScanSong",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ScanSongKit", targets: ["ScanSongKit"]),
        .executable(name: "scansong", targets: ["scansong"]),
        .executable(name: "ScanSong", targets: ["ScanSongApp"])
    ],
    dependencies: [
        .package(path: "../VGMBoy")
    ],
    targets: [
        .systemLibrary(
            name: "CGameMusicEmu",
            path: "Sources/CGME",
            pkgConfig: "libgme",
            providers: [.brew(["game-music-emu"])]
        ),
        .target(
            name: "ScanSongKit",
            dependencies: [
                "CGameMusicEmu",
                .product(name: "VGMBoyFormatCore", package: "VGMBoy"),
                .product(name: "VGMBoySNDH", package: "VGMBoy")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("AVFoundation")
            ]
        ),
        .executableTarget(name: "scansong", dependencies: ["ScanSongKit"]),
        .executableTarget(
            name: "ScanSongApp",
            dependencies: ["ScanSongKit"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(name: "ScanSongKitTests", dependencies: ["ScanSongKit"])
    ],
    swiftLanguageModes: [.v6]
)
