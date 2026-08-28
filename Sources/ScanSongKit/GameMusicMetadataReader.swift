import Foundation

/// Reads the fixed textual headers shared by the simple Game Music Emu
/// families. These fields are independent of emulation; libgme remains the
/// authority for per-track timing and track enumeration.
enum GameMusicMetadataReader {
    struct Result {
        let trackCount: Int
        let metadata: ScannerMetadata

        func merged(with fallback: ScannerMetadata) -> ScannerMetadata {
            ScannerMetadata(
                game: metadata.game.isEmpty ? fallback.game : metadata.game,
                song: fallback.song,
                system: metadata.system.isEmpty ? fallback.system : metadata.system,
                author: metadata.author.isEmpty ? fallback.author : metadata.author,
                comment: metadata.comment.isEmpty ? fallback.comment : metadata.comment,
                introLengthMs: fallback.introLengthMs,
                loopLengthMs: fallback.loopLengthMs,
                playLengthMs: fallback.playLengthMs,
                fadeLengthMs: fallback.fadeLengthMs
            )
        }
    }

    static func read(fileURL: URL) throws -> Result? {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        switch fileURL.pathExtension.lowercased() {
        case "nsf": return readNSF(data)
        case "gbs": return readGBS(data)
        default: return nil
        }
    }

    private static func readNSF(_ data: Data) -> Result? {
        guard data.count >= 128,
              data.prefix(5) == Data([0x4E, 0x45, 0x53, 0x4D, 0x1A]) else { return nil }
        let trackCount = Int(data[0x06])
        guard trackCount > 0 else { return nil }
        return Result(
            trackCount: trackCount,
            metadata: ScannerMetadata(
                game: text(data[0x0E..<0x2E]),
                song: "",
                system: "Nintendo Entertainment System",
                author: text(data[0x2E..<0x4E]),
                comment: text(data[0x4E..<0x6E]),
                introLengthMs: 0,
                loopLengthMs: 0,
                playLengthMs: 0,
                fadeLengthMs: 0
            )
        )
    }

    private static func readGBS(_ data: Data) -> Result? {
        guard data.count >= 0x70,
              data.prefix(3) == Data("GBS".utf8) else { return nil }
        let trackCount = Int(data[0x04])
        guard trackCount > 0 else { return nil }
        return Result(
            trackCount: trackCount,
            metadata: ScannerMetadata(
                game: text(data[0x10..<0x30]),
                song: "",
                system: "Nintendo Game Boy",
                author: text(data[0x30..<0x50]),
                comment: text(data[0x50..<0x70]),
                introLengthMs: 0,
                loopLengthMs: 0,
                playLengthMs: 0,
                fadeLengthMs: 0
            )
        )
    }

    private static func text(_ bytes: Data.SubSequence) -> String {
        let bytes = Data(bytes.prefix { $0 != 0 })
        return (String(data: bytes, encoding: .windowsCP1252) ?? String(decoding: bytes, as: UTF8.self))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
