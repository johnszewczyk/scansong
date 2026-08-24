import Foundation

/// Scanner-owned vgmstream structure plugin. It invokes the CLI bundled in
/// ScanSong, never a player process, and emits one typed record per subsong.
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
            let info = index == 0
                ? first
                : try await Self.readInfo(executable: executable, fileURL: fileURL, subsong: index + 1)
            tracks.append(ScanTrackMetadata(
                trackIndex: index,
                trackCount: trackCount,
                metadata: info.metadata(fileURL: fileURL)
            ))
        }
        return ScanInspection(route: route, tracks: tracks)
    }

    private static func executableURL() throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["SCANSONG_VGMSTREAM_CLI"],
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
        let data = try await InspectorProcessRunner.run(executable: executable, arguments: arguments)
        do {
            return try JSONDecoder().decode(VGMStreamInfo.self, from: data)
        } catch {
            throw ScannerInspectionError.library(
                "vgmstream returned invalid metadata for \(fileURL.lastPathComponent): \(error.localizedDescription)"
            )
        }
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
        let streamName = streamInfo?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScannerMetadata(
            game: "",
            song: (streamName?.isEmpty == false ? streamName : nil)
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
