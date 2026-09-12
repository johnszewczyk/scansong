import Foundation

/// ScanSong-owned MDX adapter. The executable is built by VGMBoy so the
/// scanner and playback use the same mdxmini implementation without linking
/// ScanSongKit to the playback core.
public struct MDXCLIInspector: ScanFormatHandler {
    public let descriptor: ScannerPluginDescriptor

    public init(descriptor: ScannerPluginDescriptor) {
        self.descriptor = descriptor
    }

    public func inspect(fileURL: URL, route: ScannerRoute) async throws -> ScanInspection {
        let mdxData: Data
        do {
            mdxData = try Data(contentsOf: fileURL)
        } catch {
            throw ScannerInspectionError.library(
                "Could not read MDX payload \(fileURL.lastPathComponent): \(error.localizedDescription)"
            )
        }
        if let dependencyName = MDXDependencyReader.dependencyName(in: mdxData) {
            guard StandaloneArchiveExtractor.isSafeRelativePath(dependencyName) else {
                throw ScannerInspectionError.malformedFile(
                    "MDX declares an unsafe dependency path: \(dependencyName)."
                )
            }
            guard MDXDependencyReader.siblingURL(named: dependencyName, beside: fileURL) != nil else {
                throw ScannerInspectionError.missingDependency(dependencyName)
            }
        }

        let executable = try Self.executableURL(descriptor: descriptor)
        let data = try await InspectorProcessRunner.run(executable: executable, arguments: [fileURL.path])
        let info: MDXInfo
        do {
            info = try JSONDecoder().decode(MDXInfo.self, from: data)
        } catch {
            throw ScannerInspectionError.library(
                "MDX inspector returned invalid metadata for \(fileURL.lastPathComponent): \(error.localizedDescription)"
            )
        }
        guard info.trackCount == 1 else {
            throw ScannerInspectionError.malformedFile(
                "MDX reported an invalid track count (\(info.trackCount)) for \(fileURL.lastPathComponent)."
            )
        }
        let title = info.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = ScannerMetadata(
            game: info.game,
            song: title.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : title,
            system: info.system,
            author: info.artist,
            comment: info.comment,
            introLengthMs: max(0, info.introLengthMs),
            loopLengthMs: max(0, info.loopLengthMs),
            playLengthMs: max(0, info.playLengthMs),
            fadeLengthMs: max(0, info.fadeLengthMs)
        )
        return ScanInspection(route: route, tracks: [
            ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)
        ])
    }

    private static func executableURL(descriptor: ScannerPluginDescriptor) throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["SCANSONG_MDX_INSPECT"], !configured.isEmpty {
            let url = URL(fileURLWithPath: configured)
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw ScannerInspectionError.library("Configured MDX inspector is not executable: \(url.path)")
            }
            return url
        }
        if let bundled = Bundle.main.url(forResource: "vgmboy-mdx-inspect", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        throw ScannerInspectionError.missingRequiredAdapter(
            pluginID: descriptor.pluginID,
            extensionName: descriptor.supportedExtensions.joined(separator: ", ")
        )
    }
}

private struct MDXInfo: Decodable, Sendable {
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
}
