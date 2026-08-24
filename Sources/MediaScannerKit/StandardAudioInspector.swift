import AVFoundation
import Foundation

/// Reads the metadata that Core Audio exposes for ordinary audio files.
/// Standard audio has no game-music timing tags, so its natural play window
/// is the exact decoded file length and its common tags are mapped into the
/// catalog's existing title/game/author/comment fields.
enum StandardAudioInspector {
    static func inspect(fileURL: URL) throws -> ScannerMetadata {
        let durationMilliseconds = try durationMilliseconds(for: fileURL)
        let asset = AVURLAsset(url: fileURL)
        let values: [String: String] = asset.commonMetadata.reduce(into: [:]) { values, item in
            guard let key = item.commonKey?.rawValue,
                  let value = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return }
            values[key] = value
        }
        let flacValues = fileURL.pathExtension.caseInsensitiveCompare("flac") == .orderedSame
            ? (try? flacVorbisComments(fileURL: fileURL)) ?? [:]
            : [:]

        return ScannerMetadata(
            game: flacValues["ALBUM"] ?? values[AVMetadataKey.commonKeyAlbumName.rawValue] ?? "",
            song: flacValues["TITLE"] ?? values[AVMetadataKey.commonKeyTitle.rawValue] ?? "",
            system: "Standard audio",
            author: flacValues["ARTIST"] ?? flacValues["ALBUMARTIST"]
                ?? flacValues["COMPOSER"] ?? values[AVMetadataKey.commonKeyArtist.rawValue]
                ?? values[AVMetadataKey.commonKeyAuthor.rawValue]
                ?? "",
            comment: flacValues["COMMENT"] ?? values[AVMetadataKey.commonKeyDescription.rawValue] ?? "",
            introLengthMs: 0,
            loopLengthMs: 0,
            playLengthMs: durationMilliseconds,
            fadeLengthMs: 0
        )
    }

    private static func durationMilliseconds(for fileURL: URL) throws -> Int {
        if let file = try? AVAudioFile(forReading: fileURL),
           file.processingFormat.sampleRate > 0,
           file.length >= 0 {
            return max(0, Int((Double(file.length) / file.processingFormat.sampleRate * 1_000).rounded()))
        }

        let duration = AVURLAsset(url: fileURL).duration.seconds
        guard duration.isFinite, duration >= 0 else {
            throw ScannerInspectionError.malformedFile(
                "Core Audio could not determine the duration of (fileURL.lastPathComponent)."
            )
        }
        return max(0, Int((duration * 1_000).rounded()))
    }

    private static func flacVorbisComments(fileURL: URL) throws -> [String: String] {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data("fLaC".utf8) else { return [:] }

        while true {
            guard let header = try handle.read(upToCount: 4), header.count == 4 else { break }
            let isLast = (header[0] & 0x80) != 0
            let blockType = header[0] & 0x7F
            let blockLength = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            guard let block = try handle.read(upToCount: blockLength), block.count == blockLength else { break }

            if blockType == 4 {
                return parseVorbisCommentBlock(block)
            }
            if isLast { break }
        }
        return [:]
    }

    private static func parseVorbisCommentBlock(_ block: Data) -> [String: String] {
        var offset = 0
        guard let vendorLength = littleEndianUInt32(block, offset: &offset),
              offset + Int(vendorLength) <= block.count else { return [:] }
        offset += Int(vendorLength)
        guard let commentCount = littleEndianUInt32(block, offset: &offset) else { return [:] }

        var values: [String: String] = [:]
        for _ in 0..<commentCount {
            guard let length = littleEndianUInt32(block, offset: &offset),
                  offset + Int(length) <= block.count else { break }
            let comment = String(decoding: block[offset..<(offset + Int(length))], as: UTF8.self)
            offset += Int(length)
            guard let separator = comment.firstIndex(of: "=") else { continue }
            let key = String(comment[..<separator]).uppercased()
            let value = String(comment[comment.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty { values[key] = value }
        }
        return values
    }

    private static func littleEndianUInt32(_ data: Data, offset: inout Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        let value = UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
        offset += 4
        return value
    }
}
