import Foundation

/// Reads Atomic Planet's AUS header metadata without starting the PS-ADPCM or
/// Xbox IMA decoder used to play its payload.
enum AtomicPlanetAUSMetadataReader {
    private static let headerSize = 0x20
    private static let metadataSource = "Atomic Planet AUS header"

    static func read(fileURL: URL) throws -> ScannerMetadata {
        let file = try FileHandle(forReadingFrom: fileURL)
        defer { try? file.close() }
        let header = try file.read(upToCount: headerSize) ?? Data()
        return try read(data: header, displayName: fileURL.lastPathComponent)
    }

    static func read(data: Data, displayName: String) throws -> ScannerMetadata {
        guard data.count >= headerSize,
              hasBytes(data, Array("AUS ".utf8), at: 0),
              let codec = uint16LE(data, at: 0x06),
              let rawSampleCount = int32LE(data, at: 0x08),
              let rawChannels = uint16LE(data, at: 0x0C),
              let legacyLoopFlag = uint16LE(data, at: 0x0E),
              let sampleRate = int32LE(data, at: 0x10),
              let rawLoopStart = int32LE(data, at: 0x14),
              let rawLoopEnd = int32LE(data, at: 0x18),
              let loopMarker = uint32LE(data, at: 0x1C) else {
            throw malformed("Missing or truncated Atomic Planet AUS header.")
        }

        let sampleCount = Int64(rawSampleCount)
        guard rawChannels > 0, rawChannels <= 64,
              sampleCount > 0, sampleCount <= 1_000_000_000,
              (300...192_000).contains(sampleRate) else {
            throw malformed("Atomic Planet AUS channel, sample, or rate fields are invalid.")
        }

        // vgmstream treats codec 0x02 as Xbox IMA and every other codec value
        // as PS-ADPCM. Codec selection affects decoding only, not header timing.
        _ = codec
        let looping = legacyLoopFlag != 0 || loopMarker == 1
        var loopStart: Int64 = 0
        var loopEnd: Int64 = 0
        if looping {
            loopStart = Int64(rawLoopStart)
            loopEnd = Int64(rawLoopEnd)
            if loopStart < 0 || loopEnd <= loopStart || loopEnd > sampleCount {
                loopStart = 0
                loopEnd = 0
            }
        }

        let loopLength = loopEnd > loopStart ? loopEnd - loopStart : 0
        let playSamples: Int64
        if loopLength > 0 {
            playSamples = loopStart + loopLength * 2 + Int64(sampleRate) * 10
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
            comment: metadataSource,
            introLengthMs: 0,
            loopLengthMs: Int(loopLength * 1_000 / Int64(sampleRate)),
            playLengthMs: Int(playSamples * 1_000 / Int64(sampleRate)),
            fadeLengthMs: 0
        )
    }

    private static func malformed(_ reason: String) -> ScannerInspectionError {
        .malformedFile("Atomic Planet AUS metadata reader: \(reason)")
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

    private static func int32LE(_ data: Data, at offset: Int) -> Int32? {
        uint32LE(data, at: offset).map(Int32.init(bitPattern:))
    }
}
