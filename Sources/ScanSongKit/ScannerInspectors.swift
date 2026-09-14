import Foundation
import MetaManCore
import VGMBoyFormatDataCore
import VGMBoySNDH

public enum ScannerInspectionError: LocalizedError {
    case unsupportedRoute(String)
    case missingRequiredAdapter(pluginID: String, extensionName: String)
    case missingDependency(String)
    case library(String)
    case malformedFile(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedRoute(let route):
            return "No scanner inspector is registered for \(route)."
        case .missingRequiredAdapter(let pluginID, let extensionName):
            return "Required \(pluginID) structure adapter is unavailable for .\(extensionName); the source was not flattened into a false single track."
        case .missingDependency(let name):
            return "Required MDX dependency is missing: \(name)."
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
        case "spc-direct":
            return try SPCInspector.inspect(fileURL: fileURL, route: route)
        case "ay-direct":
            return try AYInspector.inspect(fileURL: fileURL, route: route)
        case "sap-direct":
            return try SAPInspector.inspect(fileURL: fileURL, route: route)
        case "hes-direct":
            return try HESInspector.inspect(fileURL: fileURL, route: route)
        case "kss-direct":
            return try KSSInspector.inspect(fileURL: fileURL, route: route)
        case "game-music-direct":
            return try GameMusicDirectInspector.inspect(fileURL: fileURL, route: route)
        case "nsfe-direct":
            return try NSFEDirectInspector.inspect(fileURL: fileURL, route: route)
        case "gsf-direct":
            let metadata = try GSFMetadataReader.read(fileURL: fileURL)
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)])
        case "qsf-direct", "qsf-mini-direct":
            let metadata = try QSFMetadataReader.read(fileURL: fileURL)
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)])
        case "ape-direct":
            let document: MetadataDocument
            do {
                document = try MetaManCore.read(fileURL: fileURL)
            } catch let error as MetadataReadError {
                throw ScannerInspectionError.malformedFile(error.localizedDescription)
            } catch {
                throw ScannerInspectionError.library(
                    "Could not read APE source \(fileURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
            let metadata = ScannerMetadata(
                metadataDocument: document,
                includeDateAndEncodedByInComment: false
            )
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)])
        case "adx-direct":
            let document: MetadataDocument
            do {
                document = try MetaManCore.read(fileURL: fileURL)
            } catch let error as MetadataReadError {
                throw ScannerInspectionError.malformedFile(error.localizedDescription)
            } catch {
                throw ScannerInspectionError.library(
                    "Could not read ADX source \(fileURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
            let metadata = ScannerMetadata(metadataDocument: document, includeDateAndEncodedByInComment: false)
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)])
        case "at3-direct":
            let document: MetadataDocument
            do {
                document = try MetaManCore.read(fileURL: fileURL)
            } catch let error as MetadataReadError {
                throw ScannerInspectionError.malformedFile(error.localizedDescription)
            } catch {
                throw ScannerInspectionError.library(
                    "Could not read RIFF ATRAC3 source \(fileURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
            let metadata = ScannerMetadata(metadataDocument: document, includeDateAndEncodedByInComment: false)
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)])
        case "aus-direct":
            let document: MetadataDocument
            do {
                document = try MetaManCore.read(fileURL: fileURL)
            } catch let error as MetadataReadError {
                throw ScannerInspectionError.malformedFile(error.localizedDescription)
            } catch {
                throw ScannerInspectionError.library(
                    "Could not read Atomic Planet AUS source \(fileURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
            let metadata = ScannerMetadata(metadataDocument: document, includeDateAndEncodedByInComment: false)
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)])
        case "sony-msf-direct":
            let document: MetadataDocument
            do {
                document = try MetaManCore.read(fileURL: fileURL)
            } catch let error as MetadataReadError {
                throw ScannerInspectionError.malformedFile(error.localizedDescription)
            } catch {
                throw ScannerInspectionError.library(
                    "Could not read Sony MSF source \(fileURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
            let metadata = ScannerMetadata(metadataDocument: document, includeDateAndEncodedByInComment: false)
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)])
        case "svag-direct":
            let document: MetadataDocument
            do {
                document = try MetaManCore.read(fileURL: fileURL)
            } catch let error as MetadataReadError {
                throw ScannerInspectionError.malformedFile(error.localizedDescription)
            } catch {
                throw ScannerInspectionError.library(
                    "Could not read SVAG source \(fileURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
            let metadata = ScannerMetadata(metadataDocument: document, includeDateAndEncodedByInComment: false)
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)])
        case "xa-direct":
            let tracks = try XAMetadataReader.read(fileURL: fileURL)
            return ScanInspection(route: route, tracks: tracks)
        case "highly-theoretical", "lazyusf", "twosf", "play-psf1", "play-psf2":
            let metadata: ScannerMetadata?
            do {
                metadata = ScannerMetadata(
                    metadataDocument: try MetaManCore.read(fileURL: fileURL),
                    includeDateAndEncodedByInComment: false
                )
            } catch is MetadataReadError {
                // The previous footer reader admitted the structurally-known
                // source with empty metadata when its PSF signature was absent.
                metadata = nil
            }
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)])
        case "vgm-direct", "s98-direct":
            let document: MetadataDocument
            do {
                document = try MetaManCore.read(fileURL: fileURL)
            } catch let error as MetadataReadError {
                throw ScannerInspectionError.malformedFile(error.localizedDescription)
            }
            let metadata = ScannerMetadata(
                metadataDocument: document,
                includeDateAndEncodedByInComment: route.pluginID == "s98-direct"
            )
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)])
        case "libvgm":
            // GYM remains structure-known without a complete metadata adapter.
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: nil)])
        case "psgplay":
            return try SNDHInspector.inspect(fileURL: fileURL, route: route)
        case "standard-audio":
            let metadata = try StandardAudioInspector.inspect(fileURL: fileURL)
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)])
        case "openmpt":
            return ScanInspection(route: route, tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: nil)])
        case "sid":
            let document: MetadataDocument
            do {
                document = try MetaManCore.read(fileURL: fileURL)
            } catch let error as MetadataReadError {
                throw ScannerInspectionError.malformedFile(error.localizedDescription)
            }
            let metadata = ScannerMetadata(
                metadataDocument: document,
                includeDateAndEncodedByInComment: false
            )
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

private enum GameMusicDirectInspector {
    static func inspect(fileURL: URL, route: ScannerRoute) throws -> ScanInspection {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let source: GameMusicHeaderFacts
        do {
            guard let result = try GameMusicFormatDataReader.read(
                data: data,
                pathExtension: route.formatExtension,
                displayName: fileURL.lastPathComponent
            ) else {
                throw ScannerInspectionError.malformedFile(
                    "No direct reader is registered for .\(route.formatExtension)."
                )
            }
            source = result
        } catch let error as FormatDataError {
            throw ScannerInspectionError.malformedFile(error.message)
        }

        let metadata = ScannerMetadata(formatMetadata: source.metadata)
        let tracks = (0..<source.trackCount).map { index in
            ScanTrackMetadata(trackIndex: index, trackCount: source.trackCount, metadata: metadata)
        }
        return ScanInspection(route: route, tracks: tracks)
    }
}

private enum NSFEDirectInspector {
    static func inspect(fileURL: URL, route: ScannerRoute) throws -> ScanInspection {
        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let source = try NSFEFormatDataReader.read(
                data: data,
                displayName: fileURL.lastPathComponent
            )
            let visibleTracks = source.orderedTracks
            let tracks = visibleTracks.enumerated().map { visibleIndex, track in
                ScanTrackMetadata(
                    trackIndex: visibleIndex,
                    trackCount: visibleTracks.count,
                    metadata: ScannerMetadata(formatMetadata: track.metadata)
                )
            }
            return ScanInspection(route: route, tracks: tracks)
        } catch let error as FormatDataError {
            throw ScannerInspectionError.malformedFile(error.message)
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
                if descriptor.pluginID == "mdx" {
                    return MDXCLIInspector(descriptor: descriptor)
                }
                if descriptor.pluginID == "amiga-uade" {
                    return AmigaCLIInspector(descriptor: descriptor)
                }
                return BuiltInFormatInspector(descriptor: descriptor)
            }
    )
}

private enum SPCInspector {
    static func inspect(fileURL: URL, route: ScannerRoute) throws -> ScanInspection {
        let document: MetadataDocument
        do {
            document = try MetaManCore.read(fileURL: fileURL)
        } catch let error as MetadataReadError {
            throw ScannerInspectionError.malformedFile(error.localizedDescription)
        }
        let metadata = ScannerMetadata(metadataDocument: document, includeDateAndEncodedByInComment: false)
        return ScanInspection(
            route: route,
            tracks: [ScanTrackMetadata(trackIndex: 0, trackCount: 1, metadata: metadata)]
        )
    }
}

private enum AYInspector {
    static func inspect(fileURL: URL, route: ScannerRoute) throws -> ScanInspection {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let facts: AYFormatFacts
        do {
            facts = try AYFormatDataReader.read(data: data, displayName: fileURL.lastPathComponent)
        } catch let error as FormatDataError {
            throw ScannerInspectionError.malformedFile(error.message)
        }
        let tracks = facts.tracks.map { track in
            ScanTrackMetadata(
                trackIndex: track.sourceTrackIndex,
                trackCount: facts.trackCount,
                metadata: ScannerMetadata(formatMetadata: track.metadata)
            )
        }
        return ScanInspection(route: route, tracks: tracks)
    }
}

private enum SAPInspector {
    static func inspect(fileURL: URL, route: ScannerRoute) throws -> ScanInspection {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let facts: SAPFormatFacts
        do {
            facts = try SAPFormatDataReader.read(data: data, displayName: fileURL.lastPathComponent)
        } catch let error as FormatDataError {
            throw ScannerInspectionError.malformedFile(error.message)
        }
        let tracks = facts.tracks.enumerated().map { index, track in
            ScanTrackMetadata(
                trackIndex: index,
                trackCount: facts.trackCount,
                metadata: ScannerMetadata(formatMetadata: track.metadata)
            )
        }
        return ScanInspection(route: route, tracks: tracks)
    }
}

private enum HESInspector {
    static func inspect(fileURL: URL, route: ScannerRoute) throws -> ScanInspection {
        let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let playlistURL = companionPlaylistURL(for: fileURL)
        let playlistData = try playlistURL.map { try Data(contentsOf: $0, options: .mappedIfSafe) }
        let facts: HESFormatFacts
        do {
            facts = try HESFormatDataReader.read(
                data: fileData,
                playlistData: playlistData,
                displayName: fileURL.lastPathComponent
            )
        } catch let error as FormatDataError {
            throw ScannerInspectionError.malformedFile(error.message)
        }

        let tracks = facts.tracks.enumerated().map { index, track in
            let metadata: ScannerMetadata
            if facts.hasPlaylist {
                metadata = ScannerMetadata(formatMetadata: track.metadata)
            } else {
                metadata = ScannerMetadata(
                    game: track.metadata.game,
                    song: track.metadata.song,
                    system: track.metadata.system,
                    author: track.metadata.author,
                    comment: track.metadata.comment,
                    introLengthMs: 0,
                    loopLengthMs: 0,
                    playLengthMs: 0,
                    fadeLengthMs: 0
                )
            }
            return ScanTrackMetadata(trackIndex: index, trackCount: facts.trackCount, metadata: metadata)
        }
        return ScanInspection(route: route, tracks: tracks)
    }

    private static func companionPlaylistURL(for fileURL: URL) -> URL? {
        let baseURL = fileURL.deletingPathExtension()
        let candidates = [
            baseURL.appendingPathExtension("m3u"),
            baseURL.appendingPathExtension("M3U")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private enum KSSInspector {
    private static let headerSize = 0x10
    private static let trackCount = 256

    static func inspect(fileURL: URL, route: ScannerRoute) throws -> ScanInspection {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard data.count >= headerSize,
              data.starts(with: Data("KSCC".utf8)) || data.starts(with: Data("KSSX".utf8)) else {
            throw ScannerInspectionError.malformedFile(
                "Invalid or truncated KSS header in \(fileURL.lastPathComponent)."
            )
        }

        // libgme's info-only KSS reader exposes a fixed 256-slot address space;
        // it does not infer authored songs from the KSS payload or load M3U here.
        let deviceFlags = data[headerSize - 1]
        var system = "MSX"
        if deviceFlags & 0x02 != 0 {
            system = "Sega Master System"
            if deviceFlags & 0x04 != 0 { system = "Game Gear" }
            if deviceFlags & 0x01 != 0 { system = "Sega Mega Drive" }
        }

        let metadata = ScannerMetadata(
            game: "",
            song: "",
            system: system,
            author: "",
            comment: "",
            introLengthMs: -1,
            loopLengthMs: -1,
            playLengthMs: 150_000,
            fadeLengthMs: -1
        )
        let tracks = (0..<trackCount).map { index in
            ScanTrackMetadata(trackIndex: index, trackCount: trackCount, metadata: metadata)
        }
        return ScanInspection(route: route, tracks: tracks)
    }
}
