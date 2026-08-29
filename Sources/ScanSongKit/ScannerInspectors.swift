import CGameMusicEmu
import Foundation
import VGMBoySNDH
import zlib

public enum ScannerInspectionError: LocalizedError {
    case unsupportedRoute(String)
    case missingRequiredAdapter(pluginID: String, extensionName: String)
    case library(String)
    case malformedFile(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedRoute(let route):
            return "No scanner inspector is registered for \(route)."
        case .missingRequiredAdapter(let pluginID, let extensionName):
            return "Required \(pluginID) structure adapter is unavailable for .\(extensionName); the source was not flattened into a false single track."
        case .library(let message):
            return message
        case .malformedFile(let message):
            return message
        }
    }
}

public struct BuiltInFormatInspector: ScanFormatHandler {
    public let descriptor: ScannerPluginDescriptor

    public init(descriptor: ScannerPluginDescriptor) {
        self.descriptor = descriptor
    }

    public func inspect(fileURL: URL, route: ScannerRoute) async throws -> ScanInspection {
        switch route.pluginID {
        case "gme", "gme-multitrack":
            return try GMEInspector.inspect(fileURL: fileURL, route: route)
        case "highly-theoretical", "lazyusf", "twosf", "play-psf1", "play-psf2":
            let metadata = try PSFTagReader.read(fileURL: fileURL)
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)])
        case "libvgm":
            // VGM, VGZ, GYM, and S98 containers represent one playable stream.
            // libVGM's playlist-facing enumeration also produces one track.
            let metadata = try VGMTagReader.read(fileURL: fileURL)
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)])
        case "psgplay":
            return try SNDHInspector.inspect(fileURL: fileURL, route: route)
        case "standard-audio":
            let metadata = try StandardAudioInspector.inspect(fileURL: fileURL)
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)])
        case "openmpt", "ffmpeg-audio":
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: nil)])
        case "sid":
            let metadata = try SIDMetadataReader.read(fileURL: fileURL)
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)])
        default:
            if route.structurePolicy != .knownSingle {
                throw ScannerInspectionError.missingRequiredAdapter(
                    pluginID: route.pluginID,
                    extensionName: route.formatExtension
                )
            }
            throw ScannerInspectionError.unsupportedRoute(route.pluginID)
        }
    }
}

private enum SNDHInspector {
    static func inspect(fileURL: URL, route: ScannerRoute) throws -> ScanInspection {
        let source = try SNDHMetadataReader.read(fileURL: fileURL)
        let tracks = source.tracks.map { track in
            let song = track.subtuneName.isEmpty ? source.title : track.subtuneName
            let length = max(0, track.durationMilliseconds)
            let metadata = ScannerMetadata(
                game: "",
                song: song,
                system: "Atari ST",
                author: source.composer,
                comment: source.year,
                introLengthMs: 0,
                loopLengthMs: 0,
                playLengthMs: length,
                fadeLengthMs: 0
            )
            return ScanTrackMetadata(
                trackIndex: track.index,
                trackCount: source.tracks.count,
                metadata: metadata
            )
        }
        return ScanInspection(route: route, tracks: tracks)
    }
}

public enum BuiltInFormatInspectors {
    public static let registry = ScanPluginHandlerRegistry(
            handlers: BuiltInScannerPlugins.registry.descriptors.map { descriptor -> any ScanFormatHandler in
                if descriptor.pluginID == "vgmstream"
                    || descriptor.pluginID == "vgmstream-txtp"
                    || descriptor.pluginID == "vgmstream-hd-bank" {
                    return VGMStreamCLIInspector(descriptor: descriptor)
                }
                if descriptor.pluginID == "highly-complete" {
                    return HighlyCompleteCLIInspector(descriptor: descriptor)
                }
                if descriptor.pluginID == "qsf" || descriptor.pluginID == "qsf-mini" {
                    return QSFCLIInspector(descriptor: descriptor)
                }
                if descriptor.pluginID == "mdx" {
                    return MDXCLIInspector(descriptor: descriptor)
                }
                return BuiltInFormatInspector(descriptor: descriptor)
            }
    )
}

private enum GMEInspector {
    static func inspect(fileURL: URL, route: ScannerRoute) throws -> ScanInspection {
        if route.formatExtension == "spc", let direct = try SPCMetadataReader.read(fileURL: fileURL) {
            return ScanInspection(
                route: route,
                tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: direct)]
            )
        }

        var emulator: OpaquePointer?
        try throwIfNeeded(gme_open_file(fileURL.path, &emulator, Int32(gme_info_only)))
        guard let emulator else {
            throw ScannerInspectionError.library("Game Music Emu did not return an inspector for \(fileURL.lastPathComponent).")
        }
        defer { gme_delete(emulator) }

        let companionPlaylistURL = route.formatExtension == "hes"
            ? companionHESPlaylistURL(for: fileURL)
            : nil
        if let playlistURL = companionPlaylistURL {
            try throwIfNeeded(playlistURL.path.withCString { gme_load_m3u(emulator, $0) })
        }

        let count = Int(gme_track_count(emulator))
        guard count > 0 else {
            throw ScannerInspectionError.malformedFile("Game Music Emu found no tracks in \(fileURL.lastPathComponent).")
        }
        let directHeader = try? GameMusicMetadataReader.read(fileURL: fileURL)
        let tracks = try (0..<count).map { index in
            var infoPointer: UnsafeMutablePointer<gme_info_t>?
            try throwIfNeeded(gme_track_info(emulator, &infoPointer, Int32(index)))
            guard let infoPointer else {
                throw ScannerInspectionError.library("Game Music Emu returned no metadata for track \(index + 1).")
            }
            defer { gme_free_info(infoPointer) }
            let info = infoPointer.pointee
            let suppressUnverifiedHESTiming = route.formatExtension == "hes" && companionPlaylistURL == nil
            let decoderMetadata = ScannerMetadata(
                game: string(info.game),
                song: string(info.song),
                system: string(info.system),
                author: string(info.author),
                comment: string(info.comment),
                introLengthMs: suppressUnverifiedHESTiming ? 0 : Int(info.intro_length),
                loopLengthMs: suppressUnverifiedHESTiming ? 0 : Int(info.loop_length),
                playLengthMs: suppressUnverifiedHESTiming ? 0 : Int(info.play_length),
                fadeLengthMs: suppressUnverifiedHESTiming ? 0 : Int(info.fade_length)
            )
            return ScanTrackMetadata(
                trackIndex: index,
                trackCount: count,
                metadata: directHeader?.merged(with: decoderMetadata) ?? decoderMetadata
            )
        }
        return ScanInspection(route: route, tracks: tracks)
    }

    private static func throwIfNeeded(_ error: gme_err_t?) throws {
        if let error { throw ScannerInspectionError.library(String(cString: error)) }
    }

    private static func string(_ pointer: UnsafePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        let value = String(cString: pointer)
        return value == "?" ? "" : value
    }

    private static func companionHESPlaylistURL(for fileURL: URL) -> URL? {
        let baseURL = fileURL.deletingPathExtension()
        let candidates = [
            baseURL.appendingPathExtension("m3u"),
            baseURL.appendingPathExtension("M3U")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

enum PSFTagReader {
    private static let maximumTagBytes = 1_048_576

    struct Result {
        let metadata: ScannerMetadata
        let tags: [String: String]

        func merged(with fallback: ScannerMetadata) -> ScannerMetadata {
            ScannerMetadata(
                game: tags["game"] ?? fallback.game,
                song: tags["title"] ?? fallback.song,
                system: fallback.system,
                author: tags["artist"] ?? fallback.author,
                comment: tags["comment"] ?? fallback.comment,
                introLengthMs: fallback.introLengthMs,
                loopLengthMs: fallback.loopLengthMs,
                playLengthMs: tags["length"].map(PSFTagReader.milliseconds) ?? fallback.playLengthMs,
                fadeLengthMs: tags["fade"].map(PSFTagReader.milliseconds) ?? fallback.fadeLengthMs
            )
        }
    }

    static func read(fileURL: URL) throws -> ScannerMetadata? {
        try readResult(fileURL: fileURL)?.metadata
    }

    static func readResult(fileURL: URL) throws -> Result? {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 16), header.count == 16,
              header.prefix(3) == Data("PSF".utf8) else { return nil }
        let tagOffset = 16 + UInt64(littleEndianUInt32(header, offset: 4))
            + UInt64(littleEndianUInt32(header, offset: 8))
        let fileSize = UInt64((try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        var tags: [String: String] = [:]
        if tagOffset + 5 <= fileSize {
            try handle.seek(toOffset: tagOffset)
            let length = min(UInt64(maximumTagBytes), fileSize - tagOffset)
            if let footer = try handle.read(upToCount: Int(length)), footer.starts(with: Data("[TAG]".utf8)) {
                tags = parseTags(footer.dropFirst(5))
            }
        }
        let metadata = ScannerMetadata(
            game: tags["game"] ?? "",
            song: tags["title"] ?? fileURL.deletingPathExtension().lastPathComponent,
            system: systemName(for: fileURL.pathExtension.lowercased()),
            author: tags["artist"] ?? "",
            comment: tags["comment"] ?? "",
            introLengthMs: 0,
            loopLengthMs: 0,
            playLengthMs: tags["length"].map { milliseconds($0) } ?? 0,
            fadeLengthMs: tags["fade"].map { milliseconds($0) } ?? 0
        )
        return Result(metadata: metadata, tags: tags)
    }

    private static func littleEndianUInt32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private static func parseTags(_ bytes: Data.SubSequence) -> [String: String] {
        String(decoding: bytes, as: UTF8.self).split(whereSeparator: \.isNewline).reduce(into: [:]) { result, line in
            guard let equals = line.firstIndex(of: "=") else { return }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, !value.isEmpty, result[key] == nil { result[key] = value }
        }
    }

    private static func systemName(for extensionName: String) -> String {
        switch extensionName {
        case "gsf", "minigsf": return "Game Boy Advance"
        case "qsf", "miniqsf": return "Capcom QSound"
        case "psf", "minipsf": return "Sony PlayStation"
        case "psf2", "minipsf2": return "Sony PlayStation 2"
        case "usf", "miniusf": return "Nintendo 64"
        case "2sf", "mini2sf": return "Nintendo DS"
        case "ssf", "minissf": return "Sega Saturn"
        default: return ""
        }
    }

    static func milliseconds(_ value: String) -> Int {
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard let seconds = components.last.flatMap({ Double($0) }) else { return 0 }
        let minutes = components.dropLast().reversed().enumerated().reduce(0.0) {
            $0 + (Double($1.element) ?? 0) * pow(60, Double($1.offset + 1))
        }
        return max(0, Int(((minutes + seconds) * 1_000).rounded()))
    }
}

private enum VGMTagReader {
    private static let maximumCompressedOutputBytes = 256 * 1_024 * 1_024

    static func read(fileURL: URL) throws -> ScannerMetadata? {
        let extensionName = fileURL.pathExtension.lowercased()
        guard extensionName == "vgm" || extensionName == "vgz" else { return nil }
        let data = try readData(fileURL: fileURL, isCompressed: extensionName == "vgz")
        guard data.count >= 0x40, data.prefix(4) == Data("Vgm ".utf8) else {
            throw ScannerInspectionError.malformedFile(
                "Not a VGM file with a valid header: \(fileURL.lastPathComponent)"
            )
        }
        let gd3Relative = Int(littleEndianUInt32(data, at: 0x14))
        let totalSamples = Int(littleEndianUInt32(data, at: 0x18))
        let loopSamples = Int(littleEndianUInt32(data, at: 0x20))
        let totalMs = milliseconds(samples: totalSamples)
        let loopMs = milliseconds(samples: loopSamples)
        guard gd3Relative > 0 else {
            return ScannerMetadata(
                game: "", song: fileURL.deletingPathExtension().lastPathComponent,
                system: "", author: "", comment: "",
                introLengthMs: max(0, totalMs - loopMs), loopLengthMs: loopMs,
                playLengthMs: totalMs, fadeLengthMs: 0
            )
        }
        let gd3 = 0x14 + gd3Relative
        guard gd3 + 12 <= data.count, data[gd3..<(gd3 + 4)] == Data("Gd3 ".utf8) else { return nil }
        let byteCount = Int(littleEndianUInt32(data, at: gd3 + 8))
        guard byteCount >= 0, gd3 + 12 + byteCount <= data.count else { return nil }
        let strings = decodeUTF16Strings(Data(data[(gd3 + 12)..<(gd3 + 12 + byteCount)]))
        func first(_ index: Int, alternate: Int? = nil) -> String {
            if strings.indices.contains(index), !strings[index].isEmpty { return strings[index] }
            if let alternate, strings.indices.contains(alternate) { return strings[alternate] }
            return ""
        }
        return ScannerMetadata(
            game: first(2, alternate: 3),
            song: first(0, alternate: 1),
            system: first(4, alternate: 5),
            author: first(6, alternate: 7),
            comment: first(10),
            introLengthMs: max(0, totalMs - loopMs),
            loopLengthMs: loopMs,
            playLengthMs: totalMs,
            fadeLengthMs: 0
        )
    }

    private static func readData(fileURL: URL, isCompressed: Bool) throws -> Data {
        guard isCompressed else {
            return try Data(contentsOf: fileURL, options: .mappedIfSafe)
        }

        guard let handle = gzopen(fileURL.path, "rb") else {
            throw ScannerInspectionError.malformedFile(
                "Could not open compressed VGM: \(fileURL.lastPathComponent)"
            )
        }
        defer { _ = gzclose(handle) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = gzread(handle, &buffer, UInt32(buffer.count))
            if count < 0 {
                throw ScannerInspectionError.malformedFile(
                    "Could not decompress VGM: \(fileURL.lastPathComponent)"
                )
            }
            if count == 0 { break }
            guard data.count <= maximumCompressedOutputBytes - Int(count) else {
                throw ScannerInspectionError.malformedFile(
                    "Compressed VGM exceeds the scanner safety limit: \(fileURL.lastPathComponent)"
                )
            }
            data.append(contentsOf: buffer.prefix(Int(count)))
        }
        return data
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private static func milliseconds(samples: Int) -> Int {
        samples > 0 ? Int((Double(samples) / 44_100.0 * 1_000.0).rounded()) : 0
    }

    private static func decodeUTF16Strings(_ data: Data) -> [String] {
        var values: [String] = []
        var units: [UInt16] = []
        var offset = 0
        while offset + 1 < data.count {
            let unit = UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
            offset += 2
            if unit == 0 {
                values.append(String(decoding: units, as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines))
                units.removeAll(keepingCapacity: true)
            } else {
                units.append(unit)
            }
        }
        if !units.isEmpty { values.append(String(decoding: units, as: UTF16.self)) }
        return values
    }
}

private enum SIDMetadataReader {
    private static let nameOffset = 0x16
    private static let nameLength = 32
    private static let authorOffset = 0x2E
    private static let authorLength = 32
    private static let copyrightOffset = 0x46
    private static let copyrightLength = 32
    private static let palPlayLengthOffset = 0x76
    private static let ntscPlayLengthOffset = 0x78

    static func read(fileURL: URL) throws -> ScannerMetadata? {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard data.count >= 0x7A, let magic = String(data: data.prefix(4), encoding: .ascii),
              magic == "PSID" || magic == "RSID" else {
            throw ScannerInspectionError.malformedFile("Not a SID file with a valid PSID/RSID header: \(fileURL.lastPathComponent)")
        }
        let version = Int(bigEndianUInt16(data, at: 0x04) ?? 0)
        var playLengthMs = 0
        if version >= 2 {
            let palSeconds = Int(bigEndianUInt16(data, at: palPlayLengthOffset) ?? 0)
            let ntscSeconds = Int(bigEndianUInt16(data, at: ntscPlayLengthOffset) ?? 0)
            playLengthMs = max(palSeconds, ntscSeconds) * 1_000
        }
        let name = text(data[nameOffset..<(nameOffset + nameLength)])
        let author = text(data[authorOffset..<(authorOffset + authorLength)])
        let copyright = text(data[copyrightOffset..<(copyrightOffset + copyrightLength)])
        return ScannerMetadata(
            game: name,
            song: name.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : name,
            system: "Commodore 64",
            author: author,
            comment: copyright,
            introLengthMs: 0,
            loopLengthMs: 0,
            playLengthMs: playLengthMs,
            fadeLengthMs: 0
        )
    }

    private static func bigEndianUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func text(_ bytes: some Collection<UInt8>) -> String {
        let bytes = Data(bytes.prefix { $0 != 0 })
        return (String(data: bytes, encoding: .windowsCP1252) ?? String(decoding: bytes, as: UTF8.self))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
