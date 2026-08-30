import Foundation
import VGMBoyFormatCore

public enum ScanSongContract {
    public static let name = "scansong-jsonl"
    public static let version = 1
}

public enum ScanStructurePolicy: String, Codable, Sendable {
    case knownSingle
    case enumerate
    case dependencyEnumerate
}

public enum ScanMetadataPolicy: String, Codable, Sendable {
    case direct
    case decoder
    case optionalDeferred
}

public struct ScannerPluginDescriptor: Codable, Hashable, Sendable {
    public let pluginID: String
    public let displayName: String
    public let supportedExtensions: Set<String>
    public let structurePolicy: ScanStructurePolicy
    public let metadataPolicy: ScanMetadataPolicy
    public let supportsArchiveMembers: Bool
    public let supportsMultiTrack: Bool
    public let priority: Int

    public init(
        pluginID: String,
        displayName: String,
        supportedExtensions: Set<String>,
        supportsArchiveMembers: Bool = true,
        supportsMultiTrack: Bool = false,
        structurePolicy: ScanStructurePolicy? = nil,
        metadataPolicy: ScanMetadataPolicy = .decoder,
        priority: Int = 0
    ) {
        self.pluginID = pluginID
        self.displayName = displayName
        self.supportedExtensions = Set(supportedExtensions.map(Self.normalize))
        let resolvedStructurePolicy = structurePolicy ?? (supportsMultiTrack ? .enumerate : .knownSingle)
        self.structurePolicy = resolvedStructurePolicy
        self.metadataPolicy = metadataPolicy
        self.supportsArchiveMembers = supportsArchiveMembers
        self.supportsMultiTrack = supportsMultiTrack || resolvedStructurePolicy != .knownSingle
        self.priority = priority
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
    }
}

public struct ScannerRoute: Codable, Hashable, Sendable {
    public let pluginID: String
    public let formatExtension: String
    public let structurePolicy: ScanStructurePolicy
    public let metadataPolicy: ScanMetadataPolicy
    public let supportsArchiveMembers: Bool
    public let supportsMultiTrack: Bool

    public init(
        pluginID: String,
        formatExtension: String,
        supportsArchiveMembers: Bool = true,
        supportsMultiTrack: Bool = false,
        structurePolicy: ScanStructurePolicy? = nil,
        metadataPolicy: ScanMetadataPolicy = .decoder
    ) {
        self.pluginID = pluginID
        self.formatExtension = ScannerPluginDescriptor.normalize(formatExtension)
        let resolvedStructurePolicy = structurePolicy ?? (supportsMultiTrack ? .enumerate : .knownSingle)
        self.structurePolicy = resolvedStructurePolicy
        self.metadataPolicy = metadataPolicy
        self.supportsArchiveMembers = supportsArchiveMembers
        self.supportsMultiTrack = supportsMultiTrack || resolvedStructurePolicy != .knownSingle
    }
}

public struct ScannerPluginRegistry: Sendable {
    public let descriptors: [ScannerPluginDescriptor]

    public init(descriptors: [ScannerPluginDescriptor]) {
        self.descriptors = descriptors.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.pluginID < $1.pluginID
        }
    }

    public var supportedExtensions: Set<String> {
        Set(descriptors.flatMap(\.supportedExtensions))
    }

    public func route(pathExtension: String, archiveMember: Bool = false) -> ScannerRoute? {
        let normalized = ScannerPluginDescriptor.normalize(pathExtension)
        guard let descriptor = descriptors.first(where: {
            // Amiga prefixes are not ordinary suffixes. They are admitted by
            // route(forPath:) so a normal `music.mod` remains OpenMPT.
            $0.pluginID != "amiga-uade"
                && $0.supportedExtensions.contains(normalized)
                && (!archiveMember || $0.supportsArchiveMembers)
        }) else {
            return nil
        }
        return ScannerRoute(
            pluginID: descriptor.pluginID,
            formatExtension: normalized,
            supportsArchiveMembers: descriptor.supportsArchiveMembers,
            supportsMultiTrack: descriptor.supportsMultiTrack,
            structurePolicy: descriptor.structurePolicy,
            metadataPolicy: descriptor.metadataPolicy
        )
    }


    public func route(for pathExtension: String, archiveMember: Bool = false) -> ScannerRoute? {
        route(pathExtension: pathExtension, archiveMember: archiveMember)
    }

    /// Routes ordinary suffixes first, then Amiga's replayer-prefix names
    /// (`p4x.earth`, `mod.xpose-end`, etc.). Prefix routing is path-aware and
    /// is intentionally not folded into the generic extension API.
    public func route(forPath path: String, archiveMember: Bool = false) -> ScannerRoute? {
        if let route = route(
            pathExtension: URL(fileURLWithPath: path).pathExtension,
            archiveMember: archiveMember
        ) {
            return route
        }
        guard let prefix = AmigaFormatManifest.prefix(for: path),
              let descriptor = descriptors.first(where: {
                  $0.pluginID == "amiga-uade"
                      && $0.supportedExtensions.contains(prefix)
                      && (!archiveMember || $0.supportsArchiveMembers)
              }) else { return nil }
        return ScannerRoute(
            pluginID: descriptor.pluginID,
            formatExtension: prefix,
            supportsArchiveMembers: descriptor.supportsArchiveMembers,
            supportsMultiTrack: descriptor.supportsMultiTrack,
            structurePolicy: descriptor.structurePolicy,
            metadataPolicy: descriptor.metadataPolicy
        )
    }
}

public enum ScanMode: String, CaseIterable, Codable, Sendable {
    case incremental
    case newScan
}

public enum ScanItemState: String, Codable, Sendable {
    case discovered
    case queued
    case scanning
    case successful
    case failed
    case unsupported
    case cancelled
}

public struct ScanItemIdentity: Codable, Hashable, Sendable {
    public let rootID: Int64
    public let path: String
    public let archiveEntry: String?

    public init(rootID: Int64, path: String, archiveEntry: String?) {
        self.rootID = rootID
        self.path = path
        self.archiveEntry = archiveEntry
    }
}

public struct ScanFingerprint: Codable, Hashable, Sendable {
    public let fileSize: Int64
    public let modifiedAt: Date
    public let contentSignature: String?

    public init(fileSize: Int64, modifiedAt: Date, contentSignature: String? = nil) {
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.contentSignature = contentSignature
    }

    public func matches(_ current: ScanFingerprint) -> Bool {
        if let contentSignature, let currentSignature = current.contentSignature {
            return contentSignature == currentSignature
        }
        // Compare the persisted epoch double, not the internal Date value.
        // `Date(timeIntervalSince1970:)` can land one double-ULP off the
        // Foundation contentModificationDate for the same filesystem instant,
        // so `Date ==` would silently reject unchanged sources.
        if fileSize == current.fileSize, modifiedAt.timeIntervalSince1970 == current.modifiedAt.timeIntervalSince1970 {
            return true
        }
        return contentSignature != nil && contentSignature == current.contentSignature
    }
}

public struct ScanInventoryItem: Codable, Sendable {
    public let identity: ScanItemIdentity
    public let fingerprint: ScanFingerprint
    public let state: ScanItemState
    public let route: ScannerRoute?

    public init(identity: ScanItemIdentity, fingerprint: ScanFingerprint, state: ScanItemState, route: ScannerRoute?) {
        self.identity = identity
        self.fingerprint = fingerprint
        self.state = state
        self.route = route
    }
}

public enum ScannerEventKind: String, Codable, Sendable {
    case sessionStarted
    case sourceDiscovered
    case sourceRouted
    case diagnostic
    case sessionFinished
    case plugin
    case catalogValidated
}

public enum ScannerDiagnosticSeverity: String, Codable, Sendable {
    case warning
    case error
}

public struct ScannerDiagnostic: Codable, Hashable, Sendable {
    public let code: String
    public let severity: ScannerDiagnosticSeverity
    public let message: String

    public init(code: String, severity: ScannerDiagnosticSeverity, message: String) {
        self.code = code
        self.severity = severity
        self.message = message
    }
}

public struct ScannerEvent: Codable, Sendable {
    public let contract: String
    public let version: Int
    public let kind: ScannerEventKind
    public let sequence: Int
    public let path: String?
    public let route: ScannerRoute?
    public let diagnostic: ScannerDiagnostic?
    public let plugin: ScannerPluginDescriptor?
    public let discovered: Int?
    public let accepted: Int?
    public let failed: Int?
    public let unsupported: Int?
    public let catalog: CanonicalCatalogSummary?
    public let telemetry: ScanPhaseTelemetry?

    public init(
        kind: ScannerEventKind,
        sequence: Int,
        path: String? = nil,
        route: ScannerRoute? = nil,
        diagnostic: ScannerDiagnostic? = nil,
        plugin: ScannerPluginDescriptor? = nil,
        discovered: Int? = nil,
        accepted: Int? = nil,
        failed: Int? = nil,
        unsupported: Int? = nil,
        catalog: CanonicalCatalogSummary? = nil,
        telemetry: ScanPhaseTelemetry? = nil
    ) {
        self.contract = ScanSongContract.name
        self.version = ScanSongContract.version
        self.kind = kind
        self.sequence = sequence
        self.path = path
        self.route = route
        self.diagnostic = diagnostic
        self.plugin = plugin
        self.discovered = discovered
        self.accepted = accepted
        self.failed = failed
        self.unsupported = unsupported
        self.catalog = catalog
        self.telemetry = telemetry
    }
}
