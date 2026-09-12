import Foundation
import zlib

/// Reads the scanner-facing GSF contract without constructing a GBA core.
/// Playback remains owned by VGMBoy/Highly Complete.
enum GSFMetadataReader {
    private static let version: UInt8 = 0x22
    private static let maximumDependencyDepth = 10
    private static let maximumInflatedBytes = 64 * 1_024 * 1_024
    private static let maximumROMImageBytes = 64 * 1_024 * 1_024
    private static let maximumTagBytes = 4 * 1_024 * 1_024

    private struct Tag: Sendable {
        var name: String
        var value: String
    }

    private struct Container {
        let compressedRange: Range<Int>
        let tags: [Tag]
        let dependencyNames: [String]
    }

    private struct ExecutableSegment {
        let offset: Int
        let declaredSize: Int
        let payload: Data
    }

    /// Tracks only the bytes mGBA reads while identifying a GBA ROM. The full
    /// image can be tens of MiB, but recognition needs only its first 0xB3.
    private struct ROMHeader {
        private static let inspectedByteCount = 0xB3
        private var bytes = [UInt8](repeating: 0, count: inspectedByteCount)
        private var known = [Bool](repeating: false, count: inspectedByteCount)
        private(set) var imageSize = 0

        mutating func apply(_ segment: ExecutableSegment) {
            let previousImageSize = imageSize
            let requiredSize = segment.offset + segment.declaredSize
            if requiredSize > previousImageSize {
                let zeroStart = min(previousImageSize, Self.inspectedByteCount)
                let zeroEnd = min(requiredSize, Self.inspectedByteCount)
                if zeroStart < zeroEnd {
                    for index in zeroStart..<zeroEnd {
                        bytes[index] = 0
                        known[index] = true
                    }
                }
                imageSize = requiredSize
            }

            guard segment.offset < Self.inspectedByteCount else { return }
            let visibleSize = min(segment.declaredSize, Self.inspectedByteCount - segment.offset)
            let copiedSize = min(visibleSize, segment.payload.count)
            if copiedSize > 0 {
                for index in 0..<copiedSize {
                    bytes[segment.offset + index] = segment.payload[index]
                    known[segment.offset + index] = true
                }
            }
            if copiedSize < visibleSize {
                // The historical bridge copies the declared size, even when
                // fewer decompressed payload bytes are available. Those
                // over-read bytes are not deterministic, so never use them to
                // claim that this image passed the old ROM-recognition gate.
                for index in (segment.offset + copiedSize)..<(segment.offset + visibleSize) {
                    known[index] = false
                }
            }
        }

        func validate(fileName: String) throws {
            guard imageSize >= Self.inspectedByteCount,
                  known.allSatisfy({ $0 }) else {
                throw malformed("GSF dependency chain does not provide a complete GBA ROM header: \(fileName).")
            }

            // These checks mirror mGBA's GBAIsROM fallback for raw cartridge
            // images (GBAIsROM first checks byte 3, then the 0xB2 signature;
            // unfixed ROMs may omit the latter only when bytes 4...0x9F are
            // all zero).
            guard bytes[3] == 0xEA else {
                throw malformed("GSF dependency chain is not recognized as a GBA ROM: \(fileName).")
            }
            if bytes[0xB2] != 0x96 && bytes[4..<0xA0].contains(where: { $0 != 0 }) {
                throw malformed("GSF dependency chain has an invalid GBA ROM header: \(fileName).")
            }

            // mGBA rejects the BIOS image after the cartridge signature check.
            let isBIOS = (0..<7).allSatisfy { vector in
                bytes[vector * 4 + 3] == 0xEA && bytes[vector * 4 + 2] == 0
            }
            guard !isBIOS else {
                throw malformed("GSF dependency chain resolves to a GBA BIOS image, not a game ROM: \(fileName).")
            }
        }
    }

    private struct MetadataCollector {
        var title = ""
        var game = ""
        var artist = ""
        var comments: [String] = []
        var playLengthMs: Int?
        var decoderLengthMs = 0
        var fadeMs: Int?

        mutating func consume(_ tags: [Tag]) {
            for tag in tags {
                let key = tag.name.lowercased()
                guard !tag.value.isEmpty else { continue }
                let firstLine = tag.value.components(separatedBy: .newlines).first ?? ""
                switch key {
                case "title":
                    if title.isEmpty { title = tag.value }
                case "game", "album":
                    if game.isEmpty { game = tag.value }
                case "artist", "composer":
                    if artist.isEmpty {
                        artist = tag.value
                    }
                case "comment", "copyright":
                    comments.append(tag.value)
                case "length":
                    if playLengthMs == nil { playLengthMs = Self.parseTagTimeMilliseconds(firstLine) }
                    // The previous Highly Complete bridge reads the first
                    // line of each PSF length tag; nested dependency tags then
                    // overwrite it in load order. Mirror that behavior for
                    // intro_length_ms as well as the outer tag's play length.
                    decoderLengthMs = Self.parseDecoderTimeMilliseconds(firstLine)
                case "fade":
                    if fadeMs == nil { fadeMs = Self.parseTagTimeMilliseconds(firstLine) }
                default:
                    break
                }
            }
        }

        private static func parseTagTimeMilliseconds(_ value: String) -> Int {
            let components = value.split(separator: ":", omittingEmptySubsequences: false)
            guard let secondsComponent = components.last,
                  let seconds = Double(secondsComponent.trimmingCharacters(in: .whitespaces)) else { return 0 }
            var total = seconds
            var multiplier = 60.0
            for component in components.dropLast().reversed() {
                let part = Double(component.trimmingCharacters(in: .whitespaces)) ?? 0
                total += part * multiplier
                multiplier *= 60
            }
            total *= 1_000
            guard total.isFinite, total >= 0 else { return 0 }
            let rounded = total.rounded(.toNearestOrAwayFromZero)
            guard rounded < Double(Int.max) else { return Int.max }
            return Int(rounded)
        }

        private static func parseDecoderTimeMilliseconds(_ value: String) -> Int {
            let components = value.split(separator: ":", omittingEmptySubsequences: false)
            guard !components.isEmpty else { return 0 }
            var multiplier = 1_000.0
            var total = 0.0
            for component in components.reversed() {
                let scanner = Scanner(string: component.trimmingCharacters(in: .whitespaces))
                scanner.locale = Locale(identifier: "en_US_POSIX")
                guard let part = scanner.scanDouble() else { return 0 }
                total += part * multiplier
                multiplier *= 60
            }
            guard total.isFinite, total >= 0 else { return 0 }
            let rounded = total.rounded(.toNearestOrAwayFromZero)
            guard rounded < Double(Int.max) else { return Int.max }
            return Int(rounded)
        }
    }

    static func read(fileURL: URL) throws -> ScannerMetadata {
        let baseURL = fileURL.deletingLastPathComponent().standardizedFileURL
        var collector = MetadataCollector()
        var romHeader = ROMHeader()
        try validate(
            fileURL: fileURL.standardizedFileURL,
            baseURL: baseURL,
            depth: 1,
            activePaths: [],
            collector: &collector,
            romHeader: &romHeader
        )
        try romHeader.validate(fileName: fileURL.lastPathComponent)
        let filenameTitle = fileURL.deletingPathExtension().lastPathComponent
        let title = collector.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScannerMetadata(
            game: collector.game,
            song: title.isEmpty ? filenameTitle : title,
            system: "Game Boy Advance",
            author: collector.artist,
            comment: collector.comments.joined(separator: " | "),
            introLengthMs: collector.decoderLengthMs,
            loopLengthMs: 0,
            playLengthMs: collector.playLengthMs ?? collector.decoderLengthMs,
            fadeLengthMs: collector.fadeMs ?? 0
        )
    }

    private static func validate(
        fileURL: URL,
        baseURL: URL,
        depth: Int,
        activePaths: Set<String>,
        collector: inout MetadataCollector,
        romHeader: inout ROMHeader
    ) throws {
        guard depth <= maximumDependencyDepth else {
            throw malformed("GSF dependency chain exceeds the PSFLib depth limit.")
        }
        let path = fileURL.standardizedFileURL.path
        guard path.hasPrefix(baseURL.path + "/") || fileURL.deletingLastPathComponent().standardizedFileURL == baseURL else {
            throw malformed("GSF dependency escapes its source directory: \(fileURL.lastPathComponent)")
        }
        guard !activePaths.contains(path) else {
            throw malformed("GSF dependency cycle detected at \(fileURL.lastPathComponent).")
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            throw malformed("GSF dependency is missing or unreadable: \(fileURL.lastPathComponent)")
        }
        guard let container = try parse(data: data, fileName: fileURL.lastPathComponent) else {
            throw malformed("Not a valid GSF/miniGSF PSF v0x22 file: \(fileURL.lastPathComponent)")
        }

        collector.consume(container.tags)
        var nextActivePaths = activePaths
        nextActivePaths.insert(path)

        // PSFLib resolves _lib before loading the current executable, then
        // resolves _lib2, _lib3, ... in order, stopping at the first gap.
        if let required = container.dependencyNames.first {
            let dependencyURL = try resolve(required, relativeTo: baseURL)
            try validate(
                fileURL: dependencyURL,
                baseURL: baseURL,
                depth: depth + 1,
                activePaths: nextActivePaths,
                collector: &collector,
                romHeader: &romHeader
            )
        }

        let compressed = data.subdata(in: container.compressedRange)
        let executable = try inflate(compressed, fileName: fileURL.lastPathComponent)
        let segment = try parseGSFExecutable(executable, fileName: fileURL.lastPathComponent)
        romHeader.apply(segment)

        for dependencyName in container.dependencyNames.dropFirst() {
            let dependencyURL = try resolve(dependencyName, relativeTo: baseURL)
            try validate(
                fileURL: dependencyURL,
                baseURL: baseURL,
                depth: depth + 1,
                activePaths: nextActivePaths,
                collector: &collector,
                romHeader: &romHeader
            )
        }
    }

    private static func parse(data: Data, fileName: String) throws -> Container? {
        guard data.count >= 16,
              data[0] == 0x50, data[1] == 0x53, data[2] == 0x46,
              data[3] == version else { return nil }
        let reservedSize = UInt64(littleEndianUInt32(data, offset: 4))
        let compressedSize = UInt64(littleEndianUInt32(data, offset: 8))
        let start = UInt64(16).addingReportingOverflow(reservedSize)
        let end = start.partialValue.addingReportingOverflow(compressedSize)
        guard !start.overflow, !end.overflow, end.partialValue <= UInt64(data.count),
              compressedSize <= UInt64(UInt32.max) else {
            throw malformed("Truncated PSF payload in \(fileName).")
        }

        let compressedStart = Int(start.partialValue)
        let compressedEnd = Int(end.partialValue)
        let expectedCRC = littleEndianUInt32(data, offset: 12)
        if compressedSize > 0 {
            let actualCRC = data[compressedStart..<compressedEnd].withUnsafeBytes { bytes -> UInt32 in
                let initial = crc32(0, nil, 0)
                return UInt32(crc32(
                    initial,
                    bytes.bindMemory(to: Bytef.self).baseAddress,
                    uInt(compressedSize)
                ))
            }
            guard actualCRC == expectedCRC else {
                throw malformed("GSF executable CRC mismatch in \(fileName) (stored \(String(expectedCRC, radix: 16)), computed \(String(actualCRC, radix: 16))).")
            }
        }

        var tags: [Tag] = []
        if UInt64(data.count) >= end.partialValue + 5 {
            let tagStart = compressedEnd
            if data[tagStart..<(tagStart + 5)] == Data("[TAG]".utf8) {
                let tagBytes = data[(tagStart + 5)...]
                guard tagBytes.count <= maximumTagBytes else {
                    throw malformed("PSF tag block exceeds the scanner safety limit in \(fileName).")
                }
                tags = parseTags(tagBytes)
            }
        }

        var dependencyNames: [String] = []
        let tagValues = Dictionary(tags.map { ($0.name.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        if let primary = tagValues["_lib"] { dependencyNames.append(primary) }
        var libraryIndex = 2
        while let dependency = tagValues["_lib\(libraryIndex)"] {
            dependencyNames.append(dependency)
            libraryIndex += 1
        }
        return Container(
            compressedRange: compressedStart..<compressedEnd,
            tags: tags,
            dependencyNames: dependencyNames
        )
    }

    private static func parseTags(_ bytes: Data.SubSequence) -> [Tag] {
        let nulTerminated = bytes.prefix { $0 != 0 }
        let text = String(decoding: nulTerminated, as: UTF8.self)
        var ordered: [Tag] = []
        var indexes: [String: Int] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let name = String(line[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty else { continue }
            let key = name.lowercased()
            if let index = indexes[key] {
                if !key.hasPrefix("_") {
                    ordered[index].value += "\n\(value)"
                }
            } else {
                indexes[key] = ordered.count
                ordered.append(Tag(name: name, value: value))
            }
        }
        return ordered
    }

    private static func resolve(_ dependencyName: String, relativeTo baseURL: URL) throws -> URL {
        let components = dependencyName.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        guard !dependencyName.isEmpty,
              !dependencyName.hasPrefix("/") && !dependencyName.hasPrefix("\\"),
              !components.contains("..") else {
            throw malformed("Unsafe GSF dependency path: \(dependencyName)")
        }
        let url = URL(fileURLWithPath: dependencyName, relativeTo: baseURL).standardizedFileURL
        guard url.path.hasPrefix(baseURL.path + "/") else {
            throw malformed("GSF dependency escapes its source directory: \(dependencyName)")
        }
        return url
    }

    private static func inflate(_ compressed: Data, fileName: String) throws -> Data {
        guard !compressed.isEmpty else { return Data() }
        guard compressed.count <= Int(UInt32.max) else {
            throw malformed("GSF compressed payload is too large in \(fileName).")
        }
        let triple = compressed.count <= maximumInflatedBytes / 3
            ? compressed.count * 3
            : maximumInflatedBytes
        var capacity = min(maximumInflatedBytes, max(1_024, triple))
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
                throw malformed("Could not inflate GSF executable payload in \(fileName) (zlib \(status)).")
            }
            capacity = min(maximumInflatedBytes, capacity * 2)
        }
    }

    private static func parseGSFExecutable(_ data: Data, fileName: String) throws -> ExecutableSegment {
        guard data.count >= 12 else {
            throw malformed("GSF executable segment is shorter than its 12-byte header in \(fileName).")
        }
        let offset = UInt64(littleEndianUInt32(data, offset: 4) & 0x01FF_FFFF)
        let imageSize = UInt64(littleEndianUInt32(data, offset: 8))
        guard imageSize >= UInt64(data.count - 12) else {
            throw malformed("GSF executable segment declares less data than it contains in \(fileName).")
        }
        let required = offset.addingReportingOverflow(imageSize)
        guard !required.overflow, required.partialValue <= UInt64(maximumROMImageBytes) else {
            throw malformed("GSF executable segment exceeds the supported GBA ROM image size in \(fileName).")
        }
        return ExecutableSegment(
            offset: Int(offset),
            declaredSize: Int(imageSize),
            payload: data.subdata(in: 12..<data.count)
        )
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
