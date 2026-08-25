import Foundation

/// Removes disposable extraction paths from diagnostics before they reach either
/// the database or the human-readable scan log.
public enum ScanDiagnosticSanitizer {
    public static func sanitize(_ message: String) -> String {
        var sanitized = message
        while let scratchMarker = sanitized.range(of: "/ScanSong-ScanScratch/") {
            guard let payloadMarker = sanitized.range(
                of: "/payload/",
                range: scratchMarker.upperBound..<sanitized.endIndex
            ) else { break }

            let beforeScratch = sanitized[..<scratchMarker.lowerBound]
            let pathStart = beforeScratch.lastIndex {
                $0 == " " || $0 == "'" || $0 == "\"" || $0 == "(" || $0 == "["
            }
            let replacementStart = pathStart.map { sanitized.index(after: $0) } ?? scratchMarker.lowerBound
            sanitized.replaceSubrange(replacementStart..<payloadMarker.upperBound, with: "")
        }
        return sanitized
    }
}

/// The compact, human-readable representation used by ScanSong's optional
/// per-root scan log. It deliberately records diagnostics, not archive
/// inventories: successful archive members never become log rows.
public enum ScanLogFormatter {
    public static let header = "status | detail | path"

    public static func lines(
        status: String,
        summary: String,
        rootPath: String,
        failures: [ScanFailure],
        skipped: [ScanSkippedFile]
    ) -> [String] {
        var lines = [
            header,
            render(status: status, detail: summary, path: rootPath)
        ]

        let sortedFailures = failures.sorted {
            let left = identityDescription(for: $0.identity)
            let right = identityDescription(for: $1.identity)
            if left != right { return left.localizedStandardCompare(right) == .orderedAscending }
            if $0.stage.rawValue != $1.stage.rawValue { return $0.stage.rawValue < $1.stage.rawValue }
            return $0.message < $1.message
        }
        lines.append(contentsOf: sortedFailures.map { failure in
            let status: String
            switch failure.stage {
            case .routing:
                status = "unrecognized"
            case .archiveListing, .archiveExtraction:
                status = "archive-error"
            default:
                status = failure.identity.archiveEntry == nil ? "error" : "archive-error"
            }
            return render(
                status: status,
                detail: "\(failure.stage.rawValue): \(ScanDiagnosticSanitizer.sanitize(failure.message))",
                path: identityDescription(for: failure.identity)
            )
        })

        lines.append(contentsOf: skippedLines(skipped))
        return lines
    }

    private struct ArchiveSkipGroup: Hashable {
        let path: String
        let extensionName: String
        let reason: ScanSkipReason
    }

    private static func skippedLines(_ skipped: [ScanSkippedFile]) -> [String] {
        var lines: [String] = []
        var archiveGroups: [ArchiveSkipGroup: Int] = [:]

        for item in skipped {
            if item.identity.archiveEntry != nil {
                let key = ArchiveSkipGroup(
                    path: item.identity.path,
                    extensionName: item.extensionName,
                    reason: item.reason
                )
                archiveGroups[key, default: 0] += 1
                continue
            }
            lines.append(render(
                status: skipStatus(for: item.reason),
                detail: "\(skipDetail(for: item.reason)) (\(extensionLabel(item.extensionName)))",
                path: item.identityDescription
            ))
        }

        let groupedLines = archiveGroups.keys.sorted {
            if $0.path != $1.path { return $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            if $0.extensionName != $1.extensionName { return $0.extensionName < $1.extensionName }
            return $0.reason.rawValue < $1.reason.rawValue
        }.map { group in
            let count = archiveGroups[group, default: 0]
            let noun = count == 1 ? "archive member" : "archive members"
            return render(
                status: skipStatus(for: group.reason),
                detail: "\(skipDetail(for: group.reason)) (\(extensionLabel(group.extensionName)), \(count) \(noun))",
                path: group.path
            )
        }

        lines.append(contentsOf: groupedLines)
        return lines
    }

    private static func skipStatus(for reason: ScanSkipReason) -> String {
        switch reason {
        case .explicitlyIgnored: return "ignored"
        case .unsupportedFormat: return "unrecognized"
        }
    }

    private static func skipDetail(for reason: ScanSkipReason) -> String {
        switch reason {
        case .explicitlyIgnored: return "explicit ignore"
        case .unsupportedFormat: return "unsupported format"
        }
    }

    private static func extensionLabel(_ extensionName: String) -> String {
        extensionName.isEmpty ? "no extension" : ".\(extensionName)"
    }

    private static func identityDescription(for identity: ScanItemIdentity) -> String {
        identity.archiveEntry.map { "\(identity.path)#\($0)" } ?? identity.path
    }

    private static func render(status: String, detail: String, path: String) -> String {
        [status, detail, path].map(columnValue).joined(separator: " | ")
    }

    private static func columnValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
