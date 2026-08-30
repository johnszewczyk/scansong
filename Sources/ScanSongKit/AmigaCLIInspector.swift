import Foundation

/// ScanSong's process boundary for the shared VGMBoy UADE adapter. Keeping
/// this as a small executable protocol means the scanner does not link the
/// playback engine into its worker process, while both applications still
/// inspect the same UADE implementation.
public struct AmigaCLIInspector: ScanFormatHandler {
    public let descriptor: ScannerPluginDescriptor

    public init(descriptor: ScannerPluginDescriptor) {
        self.descriptor = descriptor
    }

    public func inspect(fileURL: URL, route: ScannerRoute) async throws -> ScanInspection {
        let executable = try Self.executableURL(descriptor: descriptor)
        let data = try await InspectorProcessRunner.run(executable: executable, arguments: [fileURL.path])
        let info: AmigaInfo
        do {
            info = try JSONDecoder().decode(AmigaInfo.self, from: data)
        } catch {
            throw ScannerInspectionError.library(
                "UADE inspector returned invalid metadata for \(fileURL.lastPathComponent): \(error.localizedDescription)"
            )
        }

        guard info.trackCount > 0, info.tracks.count == info.trackCount else {
            throw ScannerInspectionError.malformedFile(
                "UADE reported an invalid track count (\(info.trackCount)) for \(fileURL.lastPathComponent)."
            )
        }

        let tracks = info.tracks.map { track in
            let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
            var detail: [String] = []
            if !track.player.isEmpty { detail.append("player: \(track.player)") }
            if !track.format.isEmpty { detail.append("format: \(track.format)") }
            let metadata = ScannerMetadata(
                game: "",
                song: title.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : title,
                system: track.system,
                author: "",
                comment: detail.joined(separator: "; "),
                introLengthMs: 0,
                loopLengthMs: 0,
                playLengthMs: max(0, track.lengthMs),
                fadeLengthMs: 0
            )
            return ScanTrackMetadata(
                trackIndex: track.index,
                trackCount: info.trackCount,
                metadata: metadata
            )
        }
        return ScanInspection(route: route, tracks: tracks)
    }

    private static func executableURL(descriptor: ScannerPluginDescriptor) throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["SCANSONG_AMIGA_INSPECT"], !configured.isEmpty {
            let url = URL(fileURLWithPath: configured)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw ScannerInspectionError.library("Configured Amiga inspector is not executable: \(url.path)")
            }
            return url
        }
        if let bundled = Bundle.main.url(forResource: "vgmboy-amiga-inspect", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        throw ScannerInspectionError.missingRequiredAdapter(
            pluginID: descriptor.pluginID,
            extensionName: "Amiga replayer prefixes"
        )
    }
}

private struct AmigaInfo: Decodable, Sendable {
    let trackCount: Int
    let tracks: [AmigaTrackInfo]
}

private struct AmigaTrackInfo: Decodable, Sendable {
    let index: Int
    let title: String
    let system: String
    let player: String
    let format: String
    let lengthMs: Int
}
