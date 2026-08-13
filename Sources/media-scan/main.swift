import Foundation
import MediaScannerKit

private enum Exit: Error {
    case code(Int32)
}

private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
}()

private func write(_ event: ScannerEvent) throws {
    let data = try encoder.encode(event)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}

private func writeFatal(_ message: String) throws {
    try write(ScannerEvent(
        kind: .diagnostic,
        sequence: 0,
        diagnostic: ScannerDiagnostic(code: "session.fatal", severity: .error, message: message)
    ))
}

private func usage() -> String {
    "Usage: media-scan plugins | probe [--recursive] [--strict] PATH... | catalog validate PATH"
}

do {
    var arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        try writeFatal(usage())
        throw Exit.code(64)
    }
    arguments.removeFirst()

    switch command {
    case "plugins":
        for (index, plugin) in BuiltInScannerPlugins.registry.descriptors.enumerated() {
            try write(ScannerEvent(kind: .plugin, sequence: index, plugin: plugin))
        }
    case "probe":
        let recursive = arguments.contains("--recursive")
        let strict = arguments.contains("--strict")
        let paths = arguments.filter { !$0.hasPrefix("--") }
        guard !paths.isEmpty else {
            try writeFatal("probe requires at least one path")
            throw Exit.code(64)
        }
        let result = try DryRunProbe().run(paths: paths, recursive: recursive, strict: strict)
        for event in result.events { try write(event) }
        if result.hasErrors { throw Exit.code(2) }
    case "catalog":
        guard arguments.count == 2, arguments[0] == "validate" else {
            try writeFatal("catalog requires: validate PATH")
            throw Exit.code(64)
        }
        let summary = try CanonicalCatalog.inspect(databaseURL: URL(fileURLWithPath: arguments[1]))
        try write(ScannerEvent(kind: .catalogValidated, sequence: 0, path: summary.path, catalog: summary))
    default:
        try writeFatal("Unknown command: \(command). \(usage())")
        throw Exit.code(64)
    }
} catch Exit.code(let code) {
    Foundation.exit(code)
} catch {
    try? writeFatal(error.localizedDescription)
    Foundation.exit(1)
}
