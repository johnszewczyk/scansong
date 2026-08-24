import Foundation

/// A file type that is known to be unsupported by the current decoder set.
/// These entries are visible in ScanSong so an intentional omission is never
/// confused with a scanner bug.
public struct ScannerFileTypePolicy: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let detail: String

    public init(extensionName: String, displayName: String, detail: String) {
        self.id = Self.normalize(extensionName)
        self.displayName = displayName
        self.detail = detail
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
    }
}

public enum ScannerFormatPolicy {
    /// Keep this list deliberately narrow. A malformed file in a supported
    /// family must remain inspectable and must produce a failure.
    public static let knownUnsupportedFileTypes: [ScannerFileTypePolicy] = [
        .init(
            extensionName: "sgc",
            displayName: "Game Gear SGC",
            detail: "No current Game Gear/SMS music decoder; vgmstream does not open SGC."
        ),
        .init(
            extensionName: "m3u",
            displayName: "Playlist wrappers",
            detail: "Playlist files are not scanner tracks; SGC Game Gear sets use these as wrappers."
        ),
        .init(
            extensionName: "ncsf",
            displayName: "Nintendo DS NCSF",
            detail: "No NCSF decoder is present in VGMBoy or the scanner plugin set."
        ),
        .init(
            extensionName: "minincsf",
            displayName: "Nintendo DS miniNCSF",
            detail: "No NCSF decoder is present in VGMBoy or the scanner plugin set."
        ),
        .init(
            extensionName: "ncsflib",
            displayName: "Nintendo DS NCSF libraries",
            detail: "Dependency libraries for unsupported NCSF tracks; never playable rows."
        ),
        .init(
            extensionName: "mus",
            displayName: "Doom MUS",
            detail: "The current vgmstream build does not open Doom MUS music files."
        )
    ]

    public static let defaultIgnoredExtensions: Set<String> =
        Set(knownUnsupportedFileTypes.map(\.id))

    public static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
    }
}
