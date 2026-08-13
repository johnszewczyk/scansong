import Foundation

public enum BuiltInScannerPlugins {
    public static let registry = ScannerPluginRegistry(descriptors: [
        .init(pluginID: "gme", displayName: "Game Music Emu", supportedExtensions: ["spc"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "gme-multitrack", displayName: "Game Music Emu", supportedExtensions: ["ay", "gbs", "hes", "kss", "nsf", "nsfe", "sap"], structurePolicy: .enumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "openmpt", displayName: "libopenmpt", supportedExtensions: ["xm"], structurePolicy: .knownSingle, metadataPolicy: .optionalDeferred, priority: 10),
        .init(pluginID: "standard-audio", displayName: "Core Audio", supportedExtensions: ["aif", "aiff", "flac", "m4a", "mp3", "wav"], structurePolicy: .knownSingle, metadataPolicy: .optionalDeferred, priority: 10),
        .init(pluginID: "ffmpeg-audio", displayName: "FFmpeg", supportedExtensions: ["ape"], structurePolicy: .knownSingle, metadataPolicy: .optionalDeferred, priority: 10),
        .init(pluginID: "libvgm", displayName: "libVGM", supportedExtensions: ["gym", "s98", "vgm", "vgz"], structurePolicy: .enumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "highly-complete", displayName: "Highly Complete", supportedExtensions: ["gsf", "minigsf"], structurePolicy: .dependencyEnumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "highly-theoretical", displayName: "Highly Theoretical", supportedExtensions: ["ssf", "minissf"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "lazyusf", displayName: "LazyUSF", supportedExtensions: ["usf", "miniusf"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "twosf", displayName: "2SF", supportedExtensions: ["2sf", "mini2sf"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "vgmstream-hd-bank", displayName: "vgmstream", supportedExtensions: ["hd", "hbd", "iecs"], structurePolicy: .dependencyEnumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "vgmstream-txtp", displayName: "vgmstream", supportedExtensions: ["txtp"], structurePolicy: .dependencyEnumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "vgmstream", displayName: "vgmstream", supportedExtensions: ["aa3", "adx", "ads", "aifc", "at3", "aus", "bnk", "dvi", "fsb", "genh", "int", "mib", "msf", "mtaf", "ogg", "rws", "ss2", "stream", "svag", "vag", "xa"], structurePolicy: .enumerate, metadataPolicy: .decoder, priority: 10),
        .init(pluginID: "play-psf1", displayName: "Play! PSF", supportedExtensions: ["psf", "minipsf"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10),
        .init(pluginID: "play-psf2", displayName: "Play! PSF2", supportedExtensions: ["psf2", "minipsf2"], structurePolicy: .knownSingle, metadataPolicy: .direct, priority: 10)
    ])

    public static let archiveExtensions: Set<String> = ["7z", "rar", "rsn", "tar.zst", "tar.zstd", "tzst", "zip"]
}
