import Foundation
import VGMBoyFormatCore

public enum BuiltInScannerPlugins {
    /// Directly catalogued GameCube members. TXTP is part of the shared
    /// GameCube manifest but takes the dependency-enumeration route below.
    public static let gameCubeVGMStreamExtensions = Set(
        VGMStreamFormatManifest.formats.lazy
            .filter { $0.isGameCubePrimary && $0.scannerAdmission == .direct }
            .map(\.pathExtension)
    )

    public static let directVGMStreamExtensions = VGMStreamFormatManifest.directScannerExtensions

    public static let registry = ScannerPluginRegistry(descriptors: [
        .init(pluginID: "spc-direct", displayName: "SPC ID666/xID6 reader", supportedExtensions: ["spc"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 20),
        .init(pluginID: "game-music-direct", displayName: "NSF/GBS header reader", supportedExtensions: ["gbs", "nsf"], structurePolicy: .enumerate, metadataPolicy: .direct, priority: 20),
        .init(pluginID: "nsfe-direct", displayName: "NSFE chunk reader", supportedExtensions: ["nsfe"], structurePolicy: .enumerate, metadataPolicy: .direct, priority: 20),
        .init(pluginID: "kss-direct", displayName: "KSS header reader", supportedExtensions: ["kss"], structurePolicy: .enumerate, metadataPolicy: .direct, priority: 20),
        .init(pluginID: "ay-direct", displayName: "AY metadata reader", supportedExtensions: ["ay"], structurePolicy: .enumerate, metadataPolicy: .direct, priority: 20),
        .init(pluginID: "sap-direct", displayName: "SAP header reader", supportedExtensions: ["sap"], structurePolicy: .enumerate, metadataPolicy: .direct, priority: 20),
        .init(pluginID: "hes-direct", displayName: "HES header and M3U reader", supportedExtensions: ["hes"], structurePolicy: .enumerate, metadataPolicy: .direct, priority: 20),
        .init(pluginID: "openmpt", displayName: "libopenmpt", supportedExtensions: ["669", "dmf", "far", "it", "mod", "mptm", "mtm", "okt", "ptm", "s3m", "stm", "ult", "xm"], structurePolicy: .knownSingle, metadataPolicy: .optionalDeferred, priority: 10),
        .init(pluginID: "standard-audio", displayName: "Core Audio", supportedExtensions: ["aif", "aiff", "flac", "m4a", "mp3", "ogg", "wav"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "ape-direct", displayName: "APE header and tag reader", supportedExtensions: ["ape"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "vgm-direct", displayName: "VGM/VGZ header reader", supportedExtensions: ["vgm", "vgz"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 20),
        .init(pluginID: "libvgm", displayName: "libVGM", supportedExtensions: ["gym", "s98"], structurePolicy: .knownSingle, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "psgplay", displayName: "PSGPlay", supportedExtensions: ["sndh"], structurePolicy: .enumerate, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "mdx", displayName: "mdxmini", supportedExtensions: ["mdx"], structurePolicy: .knownSingle, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "amiga-uade", displayName: "UADE", supportedExtensions: AmigaFormatManifest.prefixes, supportsMultiTrack: true, structurePolicy: .enumerate, metadataPolicy: .decoder, priority: 20),
        .init(pluginID: "gsf-direct", displayName: "GSF PSF container reader", supportedExtensions: ["gsf", "minigsf"], structurePolicy: .dependencyEnumerate, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "highly-theoretical", displayName: "Highly Theoretical", supportedExtensions: ["ssf", "minissf"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "lazyusf", displayName: "LazyUSF", supportedExtensions: ["usf", "miniusf"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "twosf", displayName: "2SF", supportedExtensions: ["2sf", "mini2sf"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "vgmstream-hd-bank", displayName: "vgmstream", supportedExtensions: ["hd", "hbd", "iecs"], structurePolicy: .dependencyEnumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "vgmstream-txtp", displayName: "vgmstream", supportedExtensions: ["txtp"], structurePolicy: .dependencyEnumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "vgmstream", displayName: "vgmstream", supportedExtensions: directVGMStreamExtensions, structurePolicy: .enumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "play-psf1", displayName: "Play! PSF", supportedExtensions: ["psf", "minipsf"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "qsf-direct", displayName: "QSF PSF container reader", supportedExtensions: ["qsf"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "qsf-mini-direct", displayName: "miniQSF PSF container reader", supportedExtensions: ["miniqsf"], structurePolicy: .dependencyEnumerate, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "play-psf2", displayName: "Play! PSF2", supportedExtensions: ["psf2", "minipsf2"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "sid", displayName: "SID", supportedExtensions: ["sid"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10)
    ])

    public static let archiveExtensions: Set<String> = ["7z", "lha", "rar", "rsn", "tar.zst", "tar.zstd", "tzst", "zip", "zst", "zstd"]
}
