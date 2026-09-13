import Foundation

/// Reads the RIFF ATRAC3/ATRAC3+ facts vgmstream reports without initializing
/// FFmpeg. The metadata projection intentionally matches vgmstream's normal
/// two-loop, ten-second-fade inspection window.
enum AT3MetadataReader {
    private static let atrac3PlusGUID = Data([
        0xBF, 0xAA, 0x23, 0xE9, 0x58, 0xCB, 0x71, 0x44,
        0xA1, 0x19, 0xFF, 0xFA, 0x01, 0xE4, 0xCE, 0x62
    ])

    static func supports(fileURL: URL) -> Bool {
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let fileSize = try handle.seekToEnd()
            guard fileSize >= 20 else { return false }
            try handle.seek(toOffset: 0)
            guard let header = try handle.read(upToCount: 12),
                  header.count == 12,
                  header.prefix(4) == Data("RIFF".utf8),
                  header.subdata(in: 8..<12) == Data("WAVE".utf8),
                  UInt64(uint32LE(header, at: 4) ?? 0) + 8 == fileSize else {
                return false
            }

            var offset: UInt64 = 12
            var chunksRead = 0
            while offset + 8 <= fileSize, chunksRead < 256 {
                try handle.seek(toOffset: offset)
                guard let chunkHeader = try handle.read(upToCount: 8), chunkHeader.count == 8,
                      let rawSize = uint32LE(chunkHeader, at: 4) else { return false }
                let chunkSize = UInt64(rawSize)
                let payloadOffset = offset + 8
                let chunkEnd = payloadOffset + chunkSize
                guard chunkEnd <= fileSize else { return false }

                if chunkHeader.prefix(4) == Data("fmt ".utf8) {
                    guard chunkSize >= 16, chunkSize <= 1_024 else { return false }
                    try handle.seek(toOffset: payloadOffset)
                    let amount = Int(min(chunkSize, 40))
                    guard let format = try handle.read(upToCount: amount), format.count == amount else {
                        return false
                    }
                    return isSupportedFormat(format)
                }

                offset = chunkEnd + (chunkSize & 1)
                chunksRead += 1
            }
        } catch {
            return false
        }
        return false
    }

    static func read(fileURL: URL) throws -> ScannerMetadata {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        return try read(data: data, displayName: fileURL.lastPathComponent)
    }

    static func read(data: Data, displayName: String) throws -> ScannerMetadata {
        guard data.count >= 12,
              fourCC(data, at: 0) == "RIFF",
              fourCC(data, at: 8) == "WAVE",
              let riffSize = uint32LE(data, at: 4),
              UInt64(riffSize) + 8 == UInt64(data.count) else {
            throw malformed("Invalid RIFF/WAVE boundary.")
        }

        var offset = 12
        var format: Data?
        var sampleCount: Int64 = 0
        var sampleSkip: Int64 = 0
        var smplLoopStart: Int64 = 0
        var smplLoopEnd: Int64 = 0
        var hasSMPLLoop = false
        var wsmpLoopStart: Int64 = 0
        var wsmpLoopEnd: Int64 = 0
        var hasWSMPLoop = false
        var hasData = false

        while offset < data.count {
            guard data.count - offset >= 8,
                  let rawSize = uint32LE(data, at: offset + 4) else {
                throw malformed("Truncated RIFF chunk header.")
            }
            let size = Int(rawSize)
            let payloadOffset = offset + 8
            guard size <= data.count - payloadOffset else {
                throw malformed("RIFF chunk extends beyond the file.")
            }
            let payloadEnd = payloadOffset + size

            switch fourCC(data, at: offset) {
            case "fmt ":
                guard format == nil else { throw malformed("Duplicate RIFF fmt chunk.") }
                let bytes = data.subdata(in: payloadOffset..<payloadEnd)
                guard isSupportedFormat(bytes) else {
                    throw malformed("RIFF codec is not ATRAC3 or ATRAC3+.")
                }
                format = bytes

            case "fact":
                if size == 4, let value = int32LE(data, at: payloadOffset) {
                    sampleCount = Int64(value)
                } else if let format, isATRAC3Format(format), size == 8 || size == 12 {
                    guard let count = int32LE(data, at: payloadOffset),
                          let skip = int32LE(data, at: payloadOffset + 4) else {
                        throw malformed("Truncated ATRAC3 fact chunk.")
                    }
                    sampleCount = Int64(count)
                    sampleSkip = Int64(skip)
                }

            case "smpl":
                // vgmstream accepts exactly one forward loop point.
                if size >= 0x3C,
                   uint32LE(data, at: payloadOffset + 0x1C) == 1,
                   uint32LE(data, at: payloadOffset + 0x28) == 0,
                   let start = int32LE(data, at: payloadOffset + 0x2C),
                   let end = int32LE(data, at: payloadOffset + 0x30) {
                    smplLoopStart = Int64(start)
                    smplLoopEnd = Int64(end)
                    hasSMPLLoop = true
                }

            case "wsmp":
                if size >= 0x24,
                   uint32LE(data, at: payloadOffset) == 0x14,
                   (int32LE(data, at: payloadOffset + 0x10) ?? 0) > 0,
                   uint32LE(data, at: payloadOffset + 0x14) == 0x10,
                   uint32LE(data, at: payloadOffset + 0x18) == 0,
                   let start = int32LE(data, at: payloadOffset + 0x1C),
                   let length = int32LE(data, at: payloadOffset + 0x20) {
                    wsmpLoopStart = Int64(start)
                    wsmpLoopEnd = Int64(start) + Int64(length)
                    hasWSMPLoop = true
                }

            case "data":
                guard !hasData else { throw malformed("Duplicate RIFF data chunk.") }
                hasData = true

            default:
                break
            }

            let paddedEnd = payloadEnd + (size & 1)
            guard paddedEnd <= data.count else { throw malformed("Missing RIFF chunk padding.") }
            offset = paddedEnd
        }

        guard let format, isSupportedFormat(format), hasData else {
            throw malformed("Missing ATRAC3 fmt or data chunk.")
        }
        guard let sampleRate = uint32LE(format, at: 4) else {
            throw malformed("Truncated ATRAC3 fmt chunk.")
        }

        let hasLoop = hasSMPLLoop || hasWSMPLoop
        if hasLoop {
            // vgmstream adjusts the smpl points by the encoder skip. RIFF
            // wsmp loop points are already represented as start/length and
            // are left unchanged by that decoder path.
            smplLoopStart -= sampleSkip
            smplLoopEnd -= sampleSkip
            // vgmstream uses the loop end as a fallback sample count only when
            // the ATRAC3 fact chunk did not provide one.
            if sampleCount == 0 {
                sampleCount = smplLoopEnd + 1
            }
        }

        let activeLoop = if hasSMPLLoop {
            (start: smplLoopStart, end: smplLoopEnd + 1, smpl: true)
        } else if hasWSMPLoop {
            (start: wsmpLoopStart, end: wsmpLoopEnd, smpl: false)
        } else {
            (start: Int64(0), end: Int64(0), smpl: false)
        }
        let loopEndExclusive = activeLoop.smpl && activeLoop.end - 1 == sampleCount
            ? activeLoop.end - 1
            : activeLoop.end
        let loopFrames = hasLoop ? max(0, loopEndExclusive - activeLoop.start) : 0
        let rate = Int64(max(1, sampleRate))
        let playFrames: Int64
        if hasLoop {
            playFrames = max(0, activeLoop.start + loopFrames * 2 + Int64(sampleRate) * 10)
        } else {
            playFrames = max(0, sampleCount)
        }
        let title = URL(fileURLWithPath: displayName)
            .deletingPathExtension()
            .lastPathComponent

        return ScannerMetadata(
            game: "",
            song: title,
            system: "",
            author: "",
            comment: hasSMPLLoop
                ? "RIFF WAVE header (smpl looping)"
                : (hasWSMPLoop ? "RIFF WAVE header (wsmp looping)" : "RIFF WAVE header"),
            introLengthMs: 0,
            loopLengthMs: Int(loopFrames * 1_000 / rate),
            playLengthMs: Int(playFrames * 1_000 / rate),
            fadeLengthMs: 0
        )
    }

    private static func isSupportedFormat(_ data: Data) -> Bool {
        guard data.count >= 16,
              let codec = uint16LE(data, at: 0) else { return false }
        if codec == 0x0270 { return true }
        guard codec == 0xFFFE,
              data.count >= 40,
              uint16LE(data, at: 16).map({ $0 >= 0x16 }) == true else { return false }
        return data.subdata(in: 24..<40) == atrac3PlusGUID
    }

    private static func isATRAC3Format(_ data: Data) -> Bool {
        guard let codec = uint16LE(data, at: 0) else { return false }
        return codec == 0x0270 || codec == 0xFFFE && isSupportedFormat(data)
    }

    private static func malformed(_ reason: String) -> ScannerInspectionError {
        .malformedFile("AT3 metadata reader: \(reason)")
    }

    private static func fourCC(_ data: Data, at offset: Int) -> String? {
        guard offset >= 0, data.count - offset >= 4 else { return nil }
        return String(data: data[offset..<(offset + 4)], encoding: .ascii)
    }

    private static func uint16LE(_ data: Data, at offset: Int) -> UInt16? {
        guard let first = byte(data, at: offset), let second = byte(data, at: offset + 1) else { return nil }
        return UInt16(second) << 8 | UInt16(first)
    }

    private static func uint32LE(_ data: Data, at offset: Int) -> UInt32? {
        guard let first = byte(data, at: offset), let second = byte(data, at: offset + 1),
              let third = byte(data, at: offset + 2), let fourth = byte(data, at: offset + 3) else { return nil }
        return UInt32(fourth) << 24 | UInt32(third) << 16 | UInt32(second) << 8 | UInt32(first)
    }

    private static func int32LE(_ data: Data, at offset: Int) -> Int32? {
        uint32LE(data, at: offset).map(Int32.init(bitPattern:))
    }

    private static func byte(_ data: Data, at offset: Int) -> UInt8? {
        guard offset >= 0, offset < data.count else { return nil }
        return data[offset]
    }
}
