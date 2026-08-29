import AppKit
import Foundation
import ScanSongKit

/// Stores the last complete result for a root outside the canonical catalog.
/// The catalog remains one self-contained SQLite file; these human-readable
/// logs are optional per-source results and never affect a scan.
enum ScannerScanLogStore {
    static let maximumReadBytes = 2 * 1_024 * 1_024
    static let maximumRenderedLines = 2_000

    static func exists(databaseURL: URL, rootID: Int64) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(databaseURL: databaseURL, rootID: rootID).path)
    }

    static func discardAll(databaseURL: URL) {
        try? FileManager.default.removeItem(at: directoryURL(databaseURL: databaseURL))
    }

    static func read(databaseURL: URL, rootID: Int64) -> [String] {
        let url = fileURL(databaseURL: databaseURL, rootID: rootID)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maximumReadBytes),
              let contents = String(data: data, encoding: .utf8) else {
            return ["Unable to read the last scan log."]
        }
        var lines = contents.split(whereSeparator: \.isNewline).map(String.init)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if fileSize > maximumReadBytes {
            lines.append("Log truncated after \(maximumReadBytes / 1_024 / 1_024) MiB to keep this window responsive.")
        }
        if lines.count > maximumRenderedLines {
            lines = Array(lines.prefix(maximumRenderedLines - 1))
            lines.append("Log truncated after \(maximumRenderedLines) lines to keep this window responsive.")
        }
        return lines
    }

    static func writeLastResult(
        databaseURL: URL,
        root: CatalogRoot,
        tally: CatalogScanTally,
        result: CatalogScanResult? = nil,
        terminalMessage: String? = nil
    ) {
        let url = fileURL(databaseURL: databaseURL, rootID: root.id)
        let terminal = terminalMessage ?? root.lastScanError
        let status = terminal == nil ? "complete" : "stopped"
        let resultText: String
        if let terminal, !terminal.isEmpty {
            resultText = terminal
        } else if let result {
            let sourceFailures = result.failures.filter { $0.identity.archiveEntry == nil }.count
            let memberFailures = result.failures.count - sourceFailures
            resultText = "\(result.discoveredSourceCount) discovered, \(result.scannedSourceCount) scanned, \(result.trackCount) tracks, \(result.reusedSourceCount) reused, \(sourceFailures) source failures, \(memberFailures) member failures, \(result.skipped.count) skipped"
        } else {
            resultText = "\(tally.sourceCount) files, \(root.lastScanTrackCount) tracks"
        }
        let lines = ScanLogFormatter.lines(
            status: status,
            summary: resultText,
            rootPath: root.path,
            failures: result?.failures ?? [],
            skipped: result?.skipped ?? []
        )

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bounded = Array(lines.prefix(maximumRenderedLines - 1))
                + (lines.count > maximumRenderedLines ? ["Log truncated after \(maximumRenderedLines) lines."] : [])
            try bounded.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // Logging must never make a successful scan fail.
        }
    }

    static func summary(root: CatalogRoot, tally: CatalogScanTally) -> String {
        let completed = root.lastScanCompletedAt.map {
            DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short)
        } ?? "not completed"
        let duration = root.lastScanStartedAt.flatMap { startedAt in
            root.lastScanCompletedAt.map { completedAt in
                " • \(durationText(completedAt.timeIntervalSince(startedAt)))"
            }
        } ?? ""
        let issues = tally.failedSourceCount + tally.inactiveSourceCount + (root.lastScanError?.isEmpty == false ? 1 : 0)
        return "Last scan \(completed)\(duration) • \(tally.sourceCount) files • \(root.lastScanTrackCount) tracks • \(issues) issue\(issues == 1 ? "" : "s")"
    }

    private static func fileURL(databaseURL: URL, rootID: Int64) -> URL {
        directoryURL(databaseURL: databaseURL)
            .appendingPathComponent("root-\(rootID).log", isDirectory: false)
    }

    private static func directoryURL(databaseURL: URL) -> URL {
        let baseURL = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("ScanSong", isDirectory: true)
            .appendingPathComponent("ScanLogs", isDirectory: true)
            .appendingPathComponent(catalogIdentifier(for: databaseURL), isDirectory: true)
    }

    private static func catalogIdentifier(for databaseURL: URL) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in databaseURL.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private static func durationText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }

}

@MainActor
final class ScannerScanLogWindow {
    private let window: NSWindow
    private let textView = NSTextView()

    init(root: CatalogRoot, summary: String, lines: [String]) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .secondaryLabelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.string = lines.joined(separator: "\n").appending(lines.isEmpty ? "No scan result has been recorded." : "\n")

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.documentView = textView

        let summaryLabel = NSTextField(labelWithString: summary)
        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.maximumNumberOfLines = 1

        let content = NSStackView()
        content.orientation = .vertical
        content.spacing = 0
        content.addArrangedSubview(summaryLabel)
        content.addArrangedSubview(scrollView)
        summaryLabel.heightAnchor.constraint(equalToConstant: 36).isActive = true

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Scan Log — \(URL(fileURLWithPath: root.path).lastPathComponent)"
        window.contentView = content
        window.center()
        window.isReleasedWhenClosed = false
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }
}
