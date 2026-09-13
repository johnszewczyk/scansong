import Foundation

/// Reads known Konami and SNK SVAG timing headers without decoding PS-ADPCM.
enum KonamiSNKSVAGMetadataReader {
    private enum HeaderKind {
        case konami
        case snk
    }

    private static let requiredHeaderSize = 0x20
    private static let konamiPaddingCheckSize = 0x404

    static func read(fileURL: URL) throws -> ScannerMetadata {
        let file = try FileHandle(forReadingFrom: fileURL)
        defer { try? file.close() }
        let data = try file.read(upToCount: konamiPaddingCheckSize) ?? Data()
        return try read(data: data, displayName: fileURL.lastPathComponent)
    }

    static func read(data: Data, displayName: String) throws -> ScannerMetadata {
        guard data.count >= requiredHeaderSize,
              let kind = headerKind(data),
              let codecFields = try fields(data, kind: kind) else {
            throw malformed("Missing or truncated Konami/SNK SVAG header.")
        }

        let sampleRate = Int64(codecFields.sampleRate)
        let sampleCount = codecFields.sampleCount
        guard codecFields.channels > 0, codecFields.channels <= 64,
              sampleRate >= 300, sampleRate <= 192_000,
              sampleCount > 0, sampleCount <= 1_000_000_000 else {
            throw malformed("SVAG channel, sample, or rate fields are invalid.")
        }

        var loopStart = codecFields.looping ? codecFields.loopStart : 0
        var loopEnd = codecFields.looping ? codecFields.loopEnd : 0
        if codecFields.looping && (loopStart < 0 || loopEnd <= loopStart || loopEnd > sampleCount) {
            loopStart = 0
            loopEnd = 0
        }

        let loopLength = loopEnd > loopStart ? loopEnd - loopStart : 0
        let playSamples: Int64
        if loopLength > 0 {
            playSamples = loopStart + loopLength * 2 + sampleRate * 10
        } else {
            playSamples = sampleCount
        }

        let title = URL(fileURLWithPath: displayName)
            .deletingPathExtension()
            .lastPathComponent
        return ScannerMetadata(
            game: "",
            song: title,
            system: "",
            author: "",
            comment: codecFields.comment,
            introLengthMs: 0,
            loopLengthMs: Int(loopLength * 1_000 / sampleRate),
            playLengthMs: Int(playSamples * 1_000 / sampleRate),
            fadeLengthMs: 0
        )
    }

    private static func headerKind(_ data: Data) -> HeaderKind? {
        if hasBytes(data, Array("Svag".utf8), at: 0) { return .konami }
        if hasBytes(data, Array("VAGm".utf8), at: 0) { return .snk }
        return nil
    }

    private static func fields(_ data: Data, kind: HeaderKind) throws -> Fields? {
        switch kind {
        case .konami:
            guard let dataSize = uint32LE(data, at: 0x04),
                  let sampleRate = uint32LE(data, at: 0x08),
                  let channels = uint16LE(data, at: 0x0C),
                  let interleaveLoopFlag = uint32LE(data, at: 0x14),
                  let rawLoopStart = uint32LE(data, at: 0x18) else { return nil }

            let paddingMarker = uint32BE(data, at: 0x400) ?? 0
            guard channels <= 1 || paddingMarker == 0
                || paddingMarker == 0x5376_6167 /* Svag */
                || paddingMarker == 0x4465_7369 /* Desi */ else {
                throw malformed("Konami SVAG padding signature is invalid.")
            }

            let channelCount = Int64(channels)
            guard channelCount > 0 else { return nil }
            let sampleCount = Int64(dataSize) / channelCount / 0x10 * 28
            let loopStart = Int64(rawLoopStart) / 0x10 * 28
            return Fields(
                channels: channelCount,
                sampleRate: Int64(sampleRate),
                sampleCount: sampleCount,
                looping: interleaveLoopFlag == 1,
                loopStart: loopStart,
                loopEnd: sampleCount,
                comment: "Konami SVAG header"
            )

        case .snk:
            guard let sampleRate = uint32LE(data, at: 0x08),
                  let channels = uint32LE(data, at: 0x0C),
                  let blockCount = uint32LE(data, at: 0x10),
                  let loopStartBlock = uint32LE(data, at: 0x18),
                  let loopEndBlock = uint32LE(data, at: 0x1C) else { return nil }

            return Fields(
                channels: Int64(channels),
                sampleRate: Int64(sampleRate),
                sampleCount: Int64(blockCount &* 28),
                looping: loopEndBlock > 0,
                loopStart: Int64(loopStartBlock &* 28),
                loopEnd: Int64(loopEndBlock &* 28),
                comment: "SNK SVAG header"
            )
        }
    }

    private struct Fields {
        let channels: Int64
        let sampleRate: Int64
        let sampleCount: Int64
        let looping: Bool
        let loopStart: Int64
        let loopEnd: Int64
        let comment: String
    }

    private static func malformed(_ reason: String) -> ScannerInspectionError {
        .malformedFile("SVAG metadata reader: \(reason)")
    }

    private static func hasBytes(_ data: Data, _ expected: [UInt8], at offset: Int) -> Bool {
        guard offset >= 0, data.count - offset >= expected.count else { return false }
        return data[offset..<(offset + expected.count)].elementsEqual(expected)
    }

    private static func uint16LE(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, data.count - offset >= 2 else { return nil }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func uint32LE(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, data.count - offset >= 4 else { return nil }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func uint32BE(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, data.count - offset >= 4 else { return nil }
        return UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }
}
