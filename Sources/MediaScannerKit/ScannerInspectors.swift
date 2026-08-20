import CGameMusicEmu
import Foundation

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
        case "openmpt", "standard-audio", "ffmpeg-audio":
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

public enum BuiltInFormatInspectors {
    public static let registry = ScanPluginHandlerRegistry(
            handlers: BuiltInScannerPlugins.registry.descriptors.map { descriptor -> any ScanFormatHandler in
                if descriptor.pluginID == "vgmstream" {
                    return VGMStreamCLIInspector(descriptor: descriptor)
                }
                if descriptor.pluginID == "highly-complete" {
                    return HighlyCompleteCLIInspector(descriptor: descriptor)
                }
                return BuiltInFormatInspector(descriptor: descriptor)
            }
    )
}

/// Scanner-owned vgmstream structure plugin. It invokes the CLI bundled in
/// the MediaScanner app, never a player process, and emits one typed record
/// for every reported subsong.
public struct VGMStreamCLIInspector: ScanFormatHandler {
    public let descriptor: ScannerPluginDescriptor

    public init(descriptor: ScannerPluginDescriptor) {
        self.descriptor = descriptor
    }

    public func inspect(fileURL: URL, route: ScannerRoute) async throws -> ScanInspection {
        let executable = try Self.executableURL()
        let first = try await Self.readInfo(executable: executable, fileURL: fileURL, subsong: nil)
        let trackCount = max(1, first.streamInfo?.total ?? 0)
        guard trackCount <= 1_000 else {
            throw ScannerInspectionError.malformedFile(
                "vgmstream reported an unsafe subsong count (\(trackCount)) for \(fileURL.lastPathComponent)."
            )
        }
        var tracks: [ScanTrackMetadata] = []
        for index in 0..<trackCount {
            let info = index == 0 ? first : try await Self.readInfo(executable: executable, fileURL: fileURL, subsong: index + 1)
            tracks.append(ScanTrackMetadata(
                trackIndex: index,
                trackCount: trackCount,
                metadata: info.metadata(fileURL: fileURL)
            ))
        }
        return ScanInspection(route: route, tracks: tracks)
    }

    private static func executableURL() throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["MEDIASCANNER_VGMSTREAM_CLI"],
           !configured.isEmpty {
            let url = URL(fileURLWithPath: configured)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw ScannerInspectionError.library("Configured vgmstream plugin is not executable: \(url.path)")
            }
            return url
        }
        if let bundled = Bundle.main.url(forResource: "vgmstream-cli", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        throw ScannerInspectionError.missingRequiredAdapter(pluginID: "vgmstream", extensionName: "plugin")
    }

    private static func readInfo(executable: URL, fileURL: URL, subsong: Int?) async throws -> VGMStreamInfo {
        var arguments = ["-I"]
        if let subsong { arguments += ["-s", String(subsong)] }
        arguments.append(fileURL.path)
        let data = try await VGMStreamCommand.run(executable: executable, arguments: arguments)
        do {
            return try JSONDecoder().decode(VGMStreamInfo.self, from: data)
        } catch {
            throw ScannerInspectionError.library("vgmstream returned invalid metadata for \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

/// Scanner-owned Highly Complete structure plugin. The bundled inspector opens
/// the file through mGBA/PSF, so a miniGSF is only accepted when its required
/// library files are available in the extracted archive materialization.
public struct HighlyCompleteCLIInspector: ScanFormatHandler {
    public let descriptor: ScannerPluginDescriptor

    public init(descriptor: ScannerPluginDescriptor) {
        self.descriptor = descriptor
    }

    public func inspect(fileURL: URL, route: ScannerRoute) async throws -> ScanInspection {
        let executable = try Self.executableURL()
        let data = try await VGMStreamCommand.run(executable: executable, arguments: [fileURL.path])
        let info: HighlyCompleteInfo
        do {
            info = try JSONDecoder().decode(HighlyCompleteInfo.self, from: data)
        } catch {
            throw ScannerInspectionError.library(
                "Highly Complete returned invalid metadata for \(fileURL.lastPathComponent): \(error.localizedDescription)"
            )
        }
        guard info.trackCount == 1 else {
            throw ScannerInspectionError.malformedFile(
                "Highly Complete reported an invalid track count (\(info.trackCount)) for \(fileURL.lastPathComponent)."
            )
        }
        return ScanInspection(
            route: route,
            tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: info.metadata(fileURL: fileURL))]
        )
    }

    private static func executableURL() throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["MEDIASCANNER_HIGHLY_COMPLETE_INSPECT"],
           !configured.isEmpty {
            let url = URL(fileURLWithPath: configured)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw ScannerInspectionError.library("Configured Highly Complete plugin is not executable: \(url.path)")
            }
            return url
        }
        if let bundled = Bundle.main.url(forResource: "highly-complete-inspect", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        throw ScannerInspectionError.missingRequiredAdapter(pluginID: "highly-complete", extensionName: "plugin")
    }
}

private struct HighlyCompleteInfo: Decodable, Sendable {
    let title: String
    let game: String
    let system: String
    let artist: String
    let comment: String
    let introLengthMs: Int
    let loopLengthMs: Int
    let playLengthMs: Int
    let fadeLengthMs: Int
    let trackCount: Int

    func metadata(fileURL: URL) -> ScannerMetadata {
        ScannerMetadata(
            game: game,
            song: title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? fileURL.deletingPathExtension().lastPathComponent,
            system: system,
            author: artist,
            comment: comment,
            introLengthMs: max(0, introLengthMs),
            loopLengthMs: max(0, loopLengthMs),
            playLengthMs: max(0, playLengthMs),
            fadeLengthMs: max(0, fadeLengthMs)
        )
    }
}

private struct VGMStreamInfo: Decodable, Sendable {
    struct StreamInfo: Decodable, Sendable {
        let name: String?
        let total: Int?
    }

    struct LoopingInfo: Decodable, Sendable {
        let start: Int64?
        let end: Int64?
    }

    let sampleRate: Int?
    let numberOfSamples: Int64?
    let playSamples: Int64?
    let metadataSource: String?
    let streamInfo: StreamInfo?
    let loopingInfo: LoopingInfo?

    func metadata(fileURL: URL) -> ScannerMetadata {
        let rate = max(1, sampleRate ?? 0)
        let playFrames = max(0, playSamples ?? numberOfSamples ?? 0)
        let loopFrames = max(0, (loopingInfo?.end ?? 0) - (loopingInfo?.start ?? 0))
        return ScannerMetadata(
            game: "",
            song: streamInfo?.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? fileURL.deletingPathExtension().lastPathComponent,
            system: "",
            author: "",
            comment: metadataSource ?? "",
            introLengthMs: 0,
            loopLengthMs: Int(loopFrames * 1_000 / Int64(rate)),
            playLengthMs: Int(playFrames * 1_000 / Int64(rate)),
            fadeLengthMs: 0
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private enum VGMStreamCommand {
    static func run(executable: URL, arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in continuation.resume() }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw ScannerInspectionError.library(errorText.isEmpty ? "vgmstream could not inspect the file." : errorText)
        }
        return output.fileHandleForReading.readDataToEndOfFile()
    }
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

        let count = Int(gme_track_count(emulator))
        guard count > 0 else {
            throw ScannerInspectionError.malformedFile("Game Music Emu found no tracks in \(fileURL.lastPathComponent).")
        }
        let tracks = try (0..<count).map { index in
            var infoPointer: UnsafeMutablePointer<gme_info_t>?
            try throwIfNeeded(gme_track_info(emulator, &infoPointer, Int32(index)))
            guard let infoPointer else {
                throw ScannerInspectionError.library("Game Music Emu returned no metadata for track \(index + 1).")
            }
            defer { gme_free_info(infoPointer) }
            let info = infoPointer.pointee
            let suppressUnverifiedHESTiming = route.formatExtension == "hes"
            return ScanTrackMetadata(
                trackIndex: index,
                trackCount: count,
                metadata: ScannerMetadata(
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
}

private enum PSFTagReader {
    private static let maximumTagBytes = 1_048_576

    static func read(fileURL: URL) throws -> ScannerMetadata? {
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
        return ScannerMetadata(
            game: tags["game"] ?? "",
            song: tags["title"] ?? fileURL.deletingPathExtension().lastPathComponent,
            system: systemName(for: fileURL.pathExtension.lowercased()),
            author: tags["artist"] ?? "",
            comment: tags["comment"] ?? "",
            introLengthMs: 0,
            loopLengthMs: 0,
            playLengthMs: milliseconds(tags["length"]),
            fadeLengthMs: milliseconds(tags["fade"])
        )
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
        case "psf", "minipsf": return "Sony PlayStation"
        case "psf2", "minipsf2": return "Sony PlayStation 2"
        case "usf", "miniusf": return "Nintendo 64"
        case "2sf", "mini2sf": return "Nintendo DS"
        case "ssf", "minissf": return "Sega Saturn"
        default: return ""
        }
    }

    private static func milliseconds(_ value: String?) -> Int {
        guard let value else { return 0 }
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard let seconds = components.last.flatMap({ Double($0) }) else { return 0 }
        let minutes = components.dropLast().reversed().enumerated().reduce(0.0) {
            $0 + (Double($1.element) ?? 0) * pow(60, Double($1.offset + 1))
        }
        return max(0, Int(((minutes + seconds) * 1_000).rounded()))
    }
}

private enum VGMTagReader {
    static func read(fileURL: URL) throws -> ScannerMetadata? {
        guard fileURL.pathExtension.lowercased() == "vgm" else { return nil }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard data.count >= 0x24, data.prefix(4) == Data("Vgm ".utf8) else { return nil }
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

private enum SPCMetadataReader {
    private static let headerSize = 0x100
    private static let extendedTagOffset = 0x10200
    private static let headerMagic = Array("SNES-SPC700 Sound File Data".utf8)

    static func read(fileURL: URL) throws -> ScannerMetadata? {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard data.count >= headerSize, Array(data.prefix(headerMagic.count)) == headerMagic else {
            throw ScannerInspectionError.malformedFile("Not an SPC file with a valid header: \(fileURL.lastPathComponent)")
        }
        let legacy = legacyMetadata(in: data)
        let extended: ExtendedMetadata
        do { extended = try extendedMetadata(in: data) }
        catch where legacy.hasTag { extended = ExtendedMetadata() }
        guard legacy.hasTag || extended.hasTag else { return nil }
        return ScannerMetadata(
            game: extended.game ?? legacy.game,
            song: extended.song ?? legacy.song,
            system: "Super Nintendo",
            author: extended.author ?? legacy.author,
            comment: extended.comment ?? legacy.comment,
            introLengthMs: extended.introLengthMs ?? 0,
            loopLengthMs: extended.loopLengthMs ?? 0,
            playLengthMs: extended.playLengthMs ?? legacy.playLengthMs,
            fadeLengthMs: extended.fadeLengthMs ?? legacy.fadeLengthMs
        )
    }

    private static func legacyMetadata(in data: Data) -> LegacyMetadata {
        guard data.count >= headerSize, data[0x23] == 0x1A else { return LegacyMetadata() }
        let binary = !containsTextDate(data[0x9E..<0xA9])
            && !containsASCIIDigit(data[0xAC..<0xB1]) && data[0xB0] <= 0x7F
        return LegacyMetadata(
            hasTag: true,
            game: text(data[0x4E..<0x6E]),
            song: text(data[0x2E..<0x4E]),
            author: text(data[(binary ? 0xB0 : 0xB1)..<(binary ? 0xD0 : 0xD1)]),
            comment: text(data[0x7E..<0x9E]),
            playLengthMs: decimal(data[0xA9..<0xAC]) * 1_000,
            fadeLengthMs: binary ? Int(littleEndianUInt32(data, at: 0xAC) ?? 0) : decimal(data[0xAC..<0xB1])
        )
    }

    private static func extendedMetadata(in data: Data) throws -> ExtendedMetadata {
        guard data.count >= extendedTagOffset + 8,
              Array(data[extendedTagOffset..<(extendedTagOffset + 4)]) == Array("xid6".utf8) else {
            return ExtendedMetadata()
        }
        guard let length = littleEndianUInt32(data, at: extendedTagOffset + 4) else {
            throw ScannerInspectionError.malformedFile("Malformed SPC xID6 length.")
        }
        let end = extendedTagOffset + 8 + Int(length)
        guard end <= data.count else { throw ScannerInspectionError.malformedFile("Truncated SPC xID6 tag.") }
        var metadata = ExtendedMetadata(hasTag: true)
        var offset = extendedTagOffset + 8
        while offset < end {
            guard offset + 4 <= end else { throw ScannerInspectionError.malformedFile("Truncated SPC xID6 item.") }
            let item = data[offset]
            let type = data[offset + 1]
            let length = Int(littleEndianUInt16(data, at: offset + 2) ?? 0)
            offset += 4
            let payload: Data.SubSequence
            if type == 0 { payload = data[offset..<offset] }
            else if type == 1 || type == 4 {
                guard offset + length <= end else { throw ScannerInspectionError.malformedFile("Invalid SPC xID6 item length.") }
                payload = data[offset..<(offset + length)]
                offset += (length + 3) & ~3
                guard offset <= end else { throw ScannerInspectionError.malformedFile("Invalid SPC xID6 padding.") }
            } else { throw ScannerInspectionError.malformedFile("Unknown SPC xID6 item type.") }
            switch (item, type) {
            case (0x01, 1): metadata.song = text(payload)
            case (0x02, 1): metadata.game = text(payload)
            case (0x03, 1): metadata.author = text(payload)
            case (0x07, 1): metadata.comment = text(payload)
            case (0x30, 4): metadata.introLengthMs = ticksToMilliseconds(payload)
            case (0x31, 4): metadata.loopLengthMs = ticksToMilliseconds(payload)
            case (0x32, 4): metadata.playLengthMs = ticksToMilliseconds(payload)
            case (0x33, 4): metadata.fadeLengthMs = ticksToMilliseconds(payload)
            default: break
            }
        }
        return metadata
    }

    private static func text(_ bytes: some Collection<UInt8>) -> String {
        let bytes = Data(bytes.prefix { $0 != 0 })
        return (String(data: bytes, encoding: .windowsCP1252) ?? String(decoding: bytes, as: UTF8.self))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func decimal(_ bytes: some Collection<UInt8>) -> Int { Int(text(bytes)) ?? 0 }
    private static func containsTextDate(_ bytes: some Collection<UInt8>) -> Bool {
        bytes.allSatisfy { $0 == 0 || $0 == 0x20 || (0x2F...0x39).contains($0) }
            && bytes.contains { (0x2F...0x39).contains($0) }
    }
    private static func containsASCIIDigit(_ bytes: some Collection<UInt8>) -> Bool {
        bytes.allSatisfy { $0 == 0 || $0 == 0x20 || (0x30...0x39).contains($0) }
            && bytes.contains { (0x30...0x39).contains($0) }
    }
    private static func littleEndianUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }
    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }
    private static func ticksToMilliseconds(_ payload: Data.SubSequence) -> Int? {
        guard payload.count == 4 else { return nil }
        let bytes = Array(payload)
        let ticks = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        return Int(Int64(ticks) * 1_000 / 64_000)
    }
}

private struct LegacyMetadata {
    var hasTag = false
    var game = ""
    var song = ""
    var author = ""
    var comment = ""
    var playLengthMs = 0
    var fadeLengthMs = 0
}

private struct ExtendedMetadata {
    var hasTag = false
    var game: String?
    var song: String?
    var author: String?
    var comment: String?
    var introLengthMs: Int?
    var loopLengthMs: Int?
    var playLengthMs: Int?
    var fadeLengthMs: Int?
}
