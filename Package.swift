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
        .package(path: "../VGMBoy"),
        .package(path: "../MetaMan")
    ],
    targets: [
        // Test-only decoder oracles for reader parity; production scanner targets do not depend on these cores.
        .systemLibrary(
            name: "CGameMusicEmu",
            path: "Sources/CGME",
            pkgConfig: "libgme",
            providers: [.brew(["game-music-emu"])]
        ),
        .target(
            name: "ScanSongKit",
            dependencies: [
                .product(name: "VGMBoyFormatCore", package: "VGMBoy"),
                .product(name: "VGMBoyFormatDataCore", package: "VGMBoy"),
                .product(name: "VGMBoySNDH", package: "VGMBoy"),
                .product(name: "MetaManCore", package: "MetaMan")
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
        .testTarget(
            name: "ScanSongKitTests",
            dependencies: [
                "ScanSongKit",
                "CGameMusicEmu",
                .product(name: "MetaManCore", package: "MetaMan"),
                .product(name: "VGMBoyFormatDataCore", package: "VGMBoy"),
                .product(name: "VGMBoyKit", package: "VGMBoy")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
