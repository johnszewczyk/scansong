import Foundation
import VGMBoyFormatDataCore

/// ScanSong's file adapter for the dependency-free SPC format reader.
enum SPCMetadataReader {
    static func read(fileURL: URL) throws -> ScannerMetadata {
        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let metadata = try SPCFormatDataReader.read(
                data: data,
                displayName: fileURL.lastPathComponent
            )
            return ScannerMetadata(formatMetadata: metadata)
        } catch let error as FormatDataError {
            throw ScannerInspectionError.malformedFile(error.message)
        }
    }
}
