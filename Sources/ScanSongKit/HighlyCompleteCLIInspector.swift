import Foundation

/// Scanner-owned Highly Complete structure plugin. The bundled inspector opens
/// through mGBA/PSF, including materialized miniGSF library dependencies.
public struct HighlyCompleteCLIInspector: ScanFormatHandler {
    public let descriptor: ScannerPluginDescriptor

    public init(descriptor: ScannerPluginDescriptor) {
        self.descriptor = descriptor
    }

    public func inspect(fileURL: URL, route: ScannerRoute) async throws -> ScanInspection {
        let executable = try Self.executableURL()
        let data = try await InspectorProcessRunner.run(executable: executable, arguments: [fileURL.path])
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
        let decoderMetadata = info.metadata(fileURL: fileURL)
        let directTags = try? PSFTagReader.readResult(fileURL: fileURL)
        let resolvedMetadata = directTags?.merged(with: decoderMetadata)
            ?? decoderMetadata
        return ScanInspection(
            route: route,
            tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: resolvedMetadata)]
        )
    }

    private static func executableURL() throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["SCANSONG_HIGHLY_COMPLETE_INSPECT"],
           !configured.isEmpty {
            let url = URL(fileURLWithPath: configured)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw ScannerInspectionError.library(
                    "Configured Highly Complete plugin is not executable: \(url.path)"
                )
            }
            return url
        }
        if let bundled = Bundle.main.url(forResource: "highly-complete-inspect", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        throw ScannerInspectionError.missingRequiredAdapter(
            pluginID: "highly-complete",
            extensionName: "plugin"
        )
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
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScannerMetadata(
            game: game,
            song: trimmedTitle.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : trimmedTitle,
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
