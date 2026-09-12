import Foundation
import zlib

/// Validates QSF PSF containers, QSound data blocks, and sibling QSFLib files
/// without constructing the QSound/Z80 playback core.
enum QSFMetadataReader {
    private static let version: UInt8 = 0x41
    private static let maximumContainerBytes = 64 * 1_024 * 1_024
    private static let maximumInflatedBytes = 32 * 1_024 * 1_024 + 12
    private static let maximumTagBytes = 4 * 1_024 * 1_024
    private static let z80ROMBytes: UInt64 = 512 * 1_024
    private static let qsoundSampleBytes: UInt64 = 8 * 1_024 * 1_024

    private struct Container {
        let tags: [String: String]
        let dependencyNames: [String]
    }

    static func read(fileURL: URL) throws -> ScannerMetadata {
        let sourceURL = fileURL.standardizedFileURL
        let baseURL = sourceURL.deletingLastPathComponent().standardizedFileURL
        let root = try readContainer(at: sourceURL, requireQSFVersion: true)

        // QSF's loader checks _lib, then _lib2 ... _lib9 in order. Libraries
        // are not recursively loaded; their decompressed QSound blocks are
        // merged before the root file's blocks.
        for dependencyName in root.dependencyNames {
            let dependencyURL = try resolve(dependencyName, relativeTo: baseURL)
            _ = try readContainer(at: dependencyURL, requireQSFVersion: false)
        }

        let title = root.tags["title"] ?? ""
        return ScannerMetadata(
            game: root.tags["game"] ?? "",
            song: title.isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : title,
            system: "Capcom QSound",
            author: root.tags["artist"] ?? "",
            comment: root.tags["comment"] ?? "",
            introLengthMs: 0,
            loopLengthMs: 0,
            playLengthMs: timeMilliseconds(root.tags["length"]),
            fadeLengthMs: timeMilliseconds(root.tags["fade"])
        )
    }

    private static func readContainer(at fileURL: URL, requireQSFVersion: Bool) throws -> Container {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            throw malformed("QSF dependency is missing or unreadable: \(fileURL.lastPathComponent)")
        }
        guard data.count >= 16, data.count <= maximumContainerBytes,
              data[0] == 0x50, data[1] == 0x53, data[2] == 0x46,
              !requireQSFVersion || data[3] == version else {
            throw malformed("Not a valid QSF PSF container: \(fileURL.lastPathComponent)")
        }

        let reservedSize = UInt64(littleEndianUInt32(data, offset: 4))
        let compressedSize = UInt64(littleEndianUInt32(data, offset: 8))
        let compressedStart = UInt64(16).addingReportingOverflow(reservedSize)
        let compressedEnd = compressedStart.partialValue.addingReportingOverflow(compressedSize)
        guard !compressedStart.overflow, !compressedEnd.overflow,
              compressedEnd.partialValue <= UInt64(data.count),
              compressedSize <= UInt64(UInt32.max) else {
            throw malformed("Truncated QSF PSF payload: \(fileURL.lastPathComponent)")
        }

        let start = Int(compressedStart.partialValue)
        let end = Int(compressedEnd.partialValue)
        let compressed = data.subdata(in: start..<end)
        if !compressed.isEmpty {
            let expectedCRC = littleEndianUInt32(data, offset: 12)
            let actualCRC = compressed.withUnsafeBytes { bytes -> UInt32 in
                let initial = crc32(0, nil, 0)
                return UInt32(crc32(
                    initial,
                    bytes.bindMemory(to: Bytef.self).baseAddress,
                    uInt(compressed.count)
                ))
            }
            guard actualCRC == expectedCRC else {
                throw malformed("QSF PSF payload CRC mismatch: \(fileURL.lastPathComponent)")
            }
        }

        let program = try inflate(compressed, fileName: fileURL.lastPathComponent)
        try validateQSoundBlocks(program, fileName: fileURL.lastPathComponent)

        var tags: [String: String] = [:]
        if data.count - end >= 5,
           data[end..<(end + 5)] == Data("[TAG]".utf8) {
            let tagBytes = data[(end + 5)...]
            guard tagBytes.count <= maximumTagBytes else {
                throw malformed("QSF tag block exceeds the scanner safety limit: \(fileURL.lastPathComponent)")
            }
            tags = parseTags(tagBytes)
        }

        var dependencies: [String] = []
        if requireQSFVersion {
            for index in 1...9 {
                let key = index == 1 ? "_lib" : "_lib\(index)"
                if let value = tags[key] { dependencies.append(value) }
            }
        }
        return Container(tags: tags, dependencyNames: dependencies)
    }

    private static func validateQSoundBlocks(_ data: Data, fileName: String) throws {
        var cursor = 0
        while cursor < data.count {
            guard data.count - cursor >= 11 else {
                throw malformed("Truncated QSF data-block header: \(fileName)")
            }
            let kind = data[cursor]
            let offset = UInt64(littleEndianUInt32(data, offset: cursor + 3))
            let length = UInt64(littleEndianUInt32(data, offset: cursor + 7))
            let payloadStart = cursor + 11
            guard length <= UInt64(data.count - payloadStart) else {
                throw malformed("Truncated QSF data block: \(fileName)")
            }

            let end = offset.addingReportingOverflow(length)
            guard !end.overflow else {
                throw malformed("QSF data-block range overflows: \(fileName)")
            }
            switch kind {
            case 0x5A: // Z80 program ROM
                guard end.partialValue <= z80ROMBytes else {
                    throw malformed("QSF Z80 block exceeds the supported ROM size: \(fileName)")
                }
            case 0x53: // QSound sample ROM
                guard end.partialValue <= qsoundSampleBytes else {
                    throw malformed("QSF sample block exceeds the supported ROM size: \(fileName)")
                }
            case 0x4B: // Kabuki decryption keys
                guard length >= 11 else {
                    throw malformed("QSF Kabuki key block is shorter than 11 bytes: \(fileName)")
                }
            default:
                // The legacy QSF loader ignores unknown block kinds.
                break
            }

            cursor = payloadStart + Int(length)
        }
    }

    private static func parseTags(_ bytes: Data.SubSequence) -> [String: String] {
        let visibleBytes = bytes.prefix(while: { $0 != 0 })
        let text = String(decoding: visibleBytes, as: UTF8.self)
        var tags: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let name = line[..<equals].drop(while: isTagWhitespace).lowercased()
            let rawValue = line[line.index(after: equals)...].drop(while: isTagWhitespace)
            guard !name.isEmpty, !rawValue.isEmpty else { continue }
            // Corlett's case-insensitive tag table is last-value-wins and
            // preserves trailing value bytes (including CR in CRLF files).
            tags[name] = String(rawValue)
        }
        return tags
    }

    private static func isTagWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t" || character == "\r" || character == "\n"
    }

    private static func timeMilliseconds(_ value: String?) -> Int {
        guard let value, !value.isEmpty else { return 0 }
        let locale = Locale(identifier: "en_US_POSIX")
        var seconds: Double?

        // Match VGMBoy's QSF playback bridge: first try scanf("%d:%lf"),
        // then atof-style numeric-prefix parsing.
        let clockScanner = Scanner(string: value)
        clockScanner.locale = locale
        if let minutes = clockScanner.scanInt() {
            clockScanner.charactersToBeSkipped = []
            if clockScanner.scanString(":") != nil,
               let partSeconds = clockScanner.scanDouble() {
                seconds = Double(minutes) * 60 + partSeconds
            }
        }
        if seconds == nil {
            let numericScanner = Scanner(string: value)
            numericScanner.locale = locale
            seconds = numericScanner.scanDouble()
        }

        guard let seconds, seconds.isFinite, seconds > 0 else { return 0 }
        let frames = seconds * 44_100
        guard frames < Double(Int64.max) else { return Int.max }
        let frameCount = Int64(frames)
        guard frameCount <= Int64.max / 1_000 else { return Int.max }
        return Int(frameCount * 1_000 / 44_100)
    }

    private static func inflate(_ compressed: Data, fileName: String) throws -> Data {
        guard !compressed.isEmpty else { return Data() }
        var capacity = min(maximumInflatedBytes, max(1_024, compressed.count * 3))
        while true {
            var output = [UInt8](repeating: 0, count: capacity)
            var outputSize = uLongf(capacity)
            let status = compressed.withUnsafeBytes { input in
                output.withUnsafeMutableBufferPointer { destination in
                    uncompress(
                        destination.baseAddress,
                        &outputSize,
                        input.bindMemory(to: Bytef.self).baseAddress,
                        uLong(compressed.count)
                    )
                }
            }
            if status == Z_OK {
                return Data(output.prefix(Int(outputSize)))
            }
            guard status == Z_BUF_ERROR, capacity < maximumInflatedBytes else {
                throw malformed("Could not inflate QSF program payload: \(fileName) (zlib \(status))")
            }
            capacity = min(maximumInflatedBytes, capacity * 2)
        }
    }

    private static func resolve(_ dependencyName: String, relativeTo baseURL: URL) throws -> URL {
        let components = dependencyName.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        guard !dependencyName.isEmpty,
              !dependencyName.contains("\0"),
              !dependencyName.hasPrefix("/") && !dependencyName.hasPrefix("\\"),
              !components.contains("..") else {
            throw malformed("Unsafe QSF dependency path: \(dependencyName)")
        }
        let url = URL(fileURLWithPath: dependencyName, relativeTo: baseURL).standardizedFileURL
        guard url.path.hasPrefix(baseURL.path + "/") else {
            throw malformed("QSF dependency escapes its source directory: \(dependencyName)")
        }
        return url
    }

    private static func littleEndianUInt32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func malformed(_ message: String) -> ScannerInspectionError {
        .malformedFile(message)
    }
}
