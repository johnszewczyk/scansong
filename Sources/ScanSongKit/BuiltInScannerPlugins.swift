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
        .init(pluginID: "gme", displayName: "Game Music Emu", supportedExtensions: ["spc"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "gme-multitrack", displayName: "Game Music Emu", supportedExtensions: ["ay", "gbs", "hes", "kss", "nsf", "nsfe", "sap"], structurePolicy: .enumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "openmpt", displayName: "libopenmpt", supportedExtensions: ["669", "dmf", "far", "it", "mod", "mptm", "mtm", "okt", "ptm", "s3m", "stm", "ult", "xm"], structurePolicy: .knownSingle, metadataPolicy: .optionalDeferred, priority: 10),
        .init(pluginID: "standard-audio", displayName: "Core Audio", supportedExtensions: ["aif", "aiff", "flac", "m4a", "mp3", "ogg", "wav"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "ffmpeg-audio", displayName: "FFmpeg", supportedExtensions: ["ape"], structurePolicy: .knownSingle, metadataPolicy: .optionalDeferred, priority: 10),
        .init(pluginID: "libvgm", displayName: "libVGM", supportedExtensions: ["gym", "s98", "vgm", "vgz"], structurePolicy: .enumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "psgplay", displayName: "PSGPlay", supportedExtensions: ["sndh"], structurePolicy: .enumerate, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "mdx", displayName: "mdxmini", supportedExtensions: ["mdx"], structurePolicy: .knownSingle, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "amiga-uade", displayName: "UADE", supportedExtensions: AmigaFormatManifest.prefixes, supportsMultiTrack: true, structurePolicy: .enumerate, metadataPolicy: .decoder, priority: 20),
        .init(pluginID: "highly-complete", displayName: "Highly Complete", supportedExtensions: ["gsf", "minigsf"], structurePolicy: .dependencyEnumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "highly-theoretical", displayName: "Highly Theoretical", supportedExtensions: ["ssf", "minissf"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "lazyusf", displayName: "LazyUSF", supportedExtensions: ["usf", "miniusf"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "twosf", displayName: "2SF", supportedExtensions: ["2sf", "mini2sf"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "vgmstream-hd-bank", displayName: "vgmstream", supportedExtensions: ["hd", "hbd", "iecs"], structurePolicy: .dependencyEnumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "vgmstream-txtp", displayName: "vgmstream", supportedExtensions: ["txtp"], structurePolicy: .dependencyEnumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "vgmstream", displayName: "vgmstream", supportedExtensions: directVGMStreamExtensions, structurePolicy: .enumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "play-psf1", displayName: "Play! PSF", supportedExtensions: ["psf", "minipsf"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "qsf", displayName: "QSF / QSound", supportedExtensions: ["qsf"], structurePolicy: .knownSingle, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "qsf-mini", displayName: "QSF / QSound", supportedExtensions: ["miniqsf"], structurePolicy: .dependencyEnumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "play-psf2", displayName: "Play! PSF2", supportedExtensions: ["psf2", "minipsf2"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "sid", displayName: "SID", supportedExtensions: ["sid"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10)
    ])

    public static let archiveExtensions: Set<String> = ["7z", "lha", "rar", "rsn", "tar.zst", "tar.zstd", "tzst", "zip", "zst", "zstd"]
}
