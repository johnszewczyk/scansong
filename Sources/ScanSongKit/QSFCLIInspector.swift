import Foundation

/// Scanner-owned QSF structure plugin. The executable validates the QSF
/// payload through the VGMBoy/AOSDK QSound core, including miniQSF libraries.
public struct QSFCLIInspector: ScanFormatHandler {
    public let descriptor: ScannerPluginDescriptor

    public init(descriptor: ScannerPluginDescriptor) { self.descriptor = descriptor }

    public func inspect(fileURL: URL, route: ScannerRoute) async throws -> ScanInspection {
        let executable = try executableURL()
        let data = try await InspectorProcessRunner.run(executable: executable, arguments: [fileURL.path])
        do {
            let metadata = try JSONDecoder().decode(QSFInfo.self, from: data)
            guard metadata.trackCount == 1 else {
                throw ScannerInspectionError.malformedFile(
                    "QSF reported an invalid track count for \(fileURL.lastPathComponent)."
                )
            }
            let decoderMetadata = metadata.metadata(fileURL: fileURL)
            let directTags = try? PSFTagReader.readResult(fileURL: fileURL)
            let resolvedMetadata = directTags?.merged(with: decoderMetadata)
                ?? decoderMetadata
            return ScanInspection(
                route: route,
                tracks: [
                    ScanTrackMetadata(
                        trackIndex: 0,
                        trackCount: 1,
                        metadata: resolvedMetadata
                    )
                ]
            )
        } catch let error as ScannerInspectionError {
            throw error
        } catch {
            throw ScannerInspectionError.library(
                "QSF inspector returned invalid metadata for \(fileURL.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    private func executableURL() throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["SCANSONG_QSF_INSPECT"],
           !configured.isEmpty {
            let url = URL(fileURLWithPath: configured)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw ScannerInspectionError.library("Configured QSF inspector is not executable: \(url.path)")
            }
            return url
        }
        if let bundled = Bundle.main.url(forResource: "vgmboy-qsf-inspect", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        throw ScannerInspectionError.missingRequiredAdapter(
            pluginID: descriptor.pluginID,
            extensionName: descriptor.supportedExtensions.joined(separator: ", ")
        )
    }
}

private struct QSFInfo: Decodable, Sendable {
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
            song: title.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : title,
            system: system,
            author: artist,
            comment: comment,
            introLengthMs: introLengthMs,
            loopLengthMs: loopLengthMs,
            playLengthMs: playLengthMs,
            fadeLengthMs: fadeLengthMs
        )
    }
}
