import Foundation
import Darwin

/// Reads the S98 facts exposed by libvgm's information path without creating
/// the playback decoder or any sound devices.
enum S98MetadataReader {
    private struct Header {
        let version: UInt8
        let tickMultiplier: UInt32
        let tickDivisor: UInt32
        let tagOffset: Int
        let dataOffset: Int
        let loopOffset: Int
    }

    static func read(fileURL: URL) throws -> ScannerMetadata {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        return try read(data: data)
    }

    static func read(data: Data) throws -> ScannerMetadata {
        try data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return try read(bytes: bytes)
        }
    }

    private static func read(bytes: UnsafeBufferPointer<UInt8>) throws -> ScannerMetadata {
        let header = try readHeader(bytes)
        let (totalTicks, loopTick) = try readTiming(bytes, header: header)

        var loopOffset = header.loopOffset
        if loopOffset < header.dataOffset || loopOffset >= bytes.count {
            loopOffset = 0
        } else if loopOffset != 0, loopTick == totalTicks {
            // libvgm disables a loop that has no samples in its loop section.
            loopOffset = 0
        }

        let loopTicks = loopOffset == 0 ? 0 : totalTicks &- loopTick
        let tags = readTags(bytes, header: header)
        // S98Player::GetSongInfo() stores GetLoopTicks() in PLR_SONG_INFO's
        // loopTick field. The libvgm bridge treats that value as the intro
        // endpoint, so its published intro is the loop duration, not the
        // command stream's actual loop-start tick.
        let introLengthMs = loopTicks > 0
            ? milliseconds(ticks: loopTicks, multiplier: header.tickMultiplier, divisor: header.tickDivisor)
            : 0
        let loopLengthMs = loopTicks > 0
            ? milliseconds(ticks: loopTicks, multiplier: header.tickMultiplier, divisor: header.tickDivisor)
            : 0

        return ScannerMetadata(
            game: tags["GAME"] ?? "",
            song: tags["TITLE"] ?? "",
            system: nonempty(tags["SYSTEM"]) ?? String(format: "S98 v%X.00", header.version),
            author: tags["ARTIST"] ?? "",
            comment: combinedComment(
                comment: tags["COMMENT"],
                // Only YEAR is a decoder-recognized S98 date key. A raw DATE
                // tag survives libvgm's map as an unmapped pointer and is not
                // reliably visible to the C bridge.
                date: nonempty(tags["YEAR"]),
                encodedBy: nonempty(tags["S98BY"])
            ),
            introLengthMs: introLengthMs,
            loopLengthMs: loopLengthMs,
            playLengthMs: milliseconds(
                ticks: totalTicks,
                multiplier: header.tickMultiplier,
                divisor: header.tickDivisor
            ),
            fadeLengthMs: 0
        )
    }

    private static func readHeader(_ bytes: UnsafeBufferPointer<UInt8>) throws -> Header {
        guard bytes.count >= 0x20,
              bytes[0] == 0x53, bytes[1] == 0x39, bytes[2] == 0x38,
              (0x30...0x33).contains(bytes[3]) else {
            throw malformed("Invalid or unsupported S98 header.")
        }

        let version = bytes[3] - 0x30
        guard var tickMultiplier = uint32LE(bytes, at: 0x04),
              var tickDivisor = uint32LE(bytes, at: 0x08),
              let tagOffsetValue = uint32LE(bytes, at: 0x10),
              let dataOffsetValue = uint32LE(bytes, at: 0x14),
              let loopOffsetValue = uint32LE(bytes, at: 0x18) else {
            throw malformed("Truncated S98 header fields.")
        }

        if version == 0 { tickMultiplier = 0 }
        if version <= 1 { tickDivisor = 0 }
        if tickMultiplier == 0 { tickMultiplier = 10 }
        if tickDivisor == 0 { tickDivisor = 1_000 }

        var minimumDataOffset = 0x20
        switch version {
        case 0, 1:
            break
        case 2:
            var deviceOffset = 0x20
            var foundTerminator = false
            while deviceOffset <= bytes.count - 4 {
                guard let deviceType = uint32LE(bytes, at: deviceOffset) else { break }
                if deviceType == 0 {
                    let (end, overflow) = deviceOffset.addingReportingOverflow(0x10)
                    guard !overflow else { throw malformed("S98 device table is too large.") }
                    minimumDataOffset = end
                    foundTerminator = true
                    break
                }
                let (next, overflow) = deviceOffset.addingReportingOverflow(0x10)
                guard !overflow else { throw malformed("S98 device table is too large.") }
                deviceOffset = next
            }
            guard foundTerminator else { throw malformed("S98 v2 device table has no terminator.") }
        case 3:
            guard let deviceCount = uint32LE(bytes, at: 0x1C) else {
                throw malformed("Invalid S98 v3 device count.")
            }
            let (deviceBytes, multiplicationOverflow) = Int(deviceCount).multipliedReportingOverflow(by: 0x10)
            let (end, additionOverflow) = 0x20.addingReportingOverflow(deviceBytes)
            guard !multiplicationOverflow, !additionOverflow, end <= bytes.count else {
                throw malformed("S98 v3 device table extends beyond the file.")
            }
            minimumDataOffset = end
        default:
            throw malformed("Unsupported S98 version.")
        }

        let dataOffset = Int(dataOffsetValue)
        guard dataOffset >= minimumDataOffset, dataOffset <= bytes.count else {
            throw malformed("S98 data offset is outside the command stream.")
        }

        return Header(
            version: version,
            tickMultiplier: tickMultiplier,
            tickDivisor: tickDivisor,
            tagOffset: Int(tagOffsetValue),
            dataOffset: dataOffset,
            loopOffset: Int(loopOffsetValue)
        )
    }

    private static func readTiming(_ bytes: UnsafeBufferPointer<UInt8>, header: Header) throws -> (UInt32, UInt32) {
        var position = header.dataOffset
        var totalTicks: UInt32 = 0
        var loopTick: UInt32 = 0

        while position < bytes.count {
            if position == header.loopOffset {
                loopTick = totalTicks
            }

            let command = bytes[position]
            position += 1
            switch command {
            case 0xFF:
                totalTicks &+= 1
            case 0xFE:
                let delta = try readVariableInteger(bytes, position: &position)
                totalTicks &+= 2 &+ delta
            case 0xFD:
                return (totalTicks, loopTick)
            default:
                // libvgm's length pass only advances over the two write
                // operands; it does not dereference them. Preserve acceptance
                // of a short final write while keeping all actual reads bound.
                position += 2
            }
        }

        return (totalTicks, loopTick)
    }

    private static func readVariableInteger(_ bytes: UnsafeBufferPointer<UInt8>, position: inout Int) throws -> UInt32 {
        var value: UInt32 = 0
        for byteIndex in 0..<5 {
            guard position < bytes.count else {
                throw malformed("Truncated S98 variable-length tick value.")
            }
            let byte = bytes[position]
            position += 1
            value |= UInt32(byte & 0x7F) &<< (byteIndex * 7)
            if byte & 0x80 == 0 { return value }
        }
        throw malformed("S98 variable-length tick value exceeds 32 bits.")
    }

    private static func readTags(_ bytes: UnsafeBufferPointer<UInt8>, header: Header) -> [String: String] {
        guard header.tagOffset > 0,
              header.tagOffset < bytes.count else { return [:] }

        var end = header.tagOffset
        while end < bytes.count, bytes[end] != 0 { end += 1 }
        let tagBytes = UnsafeBufferPointer(start: bytes.baseAddress?.advanced(by: header.tagOffset), count: end - header.tagOffset)
        var tagData = Data(tagBytes)

        if header.version < 3 {
            let title = decodeLegacyText(tagData)
            return title.isEmpty ? [:] : ["TITLE": title]
        }

        guard tagData.count >= 5,
              tagData.prefix(5) == Data("[S98]".utf8) else { return [:] }
        tagData.removeFirst(5)

        let decoded: String
        if tagData.starts(with: [0xEF, 0xBB, 0xBF]) {
            tagData.removeFirst(3)
            decoded = String(decoding: tagData, as: UTF8.self)
        } else {
            decoded = decodeLegacyText(tagData)
        }

        var rawTags: [String: String] = [:]
        for line in decoded.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = trimPSFTagWhitespace(String(line[..<separator])).uppercased()
            guard !key.isEmpty else { continue }
            let valueStart = line.index(after: separator)
            let value = trimPSFTagWhitespace(String(line[valueStart...]))
            if let existing = rawTags[key] {
                rawTags[key] = existing + "\n" + value
            } else {
                rawTags[key] = value
            }
        }
        return rawTags
    }

    private static func decodeLegacyText(_ data: Data) -> String {
        let fallback = String(decoding: data, as: UTF8.self)
        guard let converter = iconv_open("UTF-8", "CP932") else { return fallback }
        defer { iconv_close(converter) }

        let (scaledCount, scaleOverflow) = data.count.multipliedReportingOverflow(by: 3)
        guard !scaleOverflow else { return fallback }
        var output = [UInt8](repeating: 0, count: scaledCount / 2)
        var inputRemaining = data.count
        var outputWritten = 0
        var previousOutputWritten: Int?

        let converted = data.withUnsafeBytes { inputBytes -> String? in
            guard let inputBase = inputBytes.baseAddress else { return "" }
            var inputCursor: UnsafeMutablePointer<CChar>? = UnsafeMutablePointer(
                mutating: inputBase.assumingMemoryBound(to: CChar.self)
            )

            while true {
                var outputRemaining = output.count - outputWritten
                let status = output.withUnsafeMutableBufferPointer { outputBytes -> size_t in
                    guard let outputBase = outputBytes.baseAddress else { return -1 }
                    var outputCursor: UnsafeMutablePointer<CChar>? = UnsafeMutableRawPointer(
                        outputBase.advanced(by: outputWritten)
                    ).assumingMemoryBound(to: CChar.self)
                    return Darwin.iconv(
                        converter,
                        &inputCursor,
                        &inputRemaining,
                        &outputCursor,
                        &outputRemaining
                    )
                }
                outputWritten = output.count - outputRemaining
                if status != -1 {
                    return String(decoding: output[..<outputWritten], as: UTF8.self)
                }

                switch Darwin.errno {
                case EILSEQ:
                    return nil
                case EINVAL:
                    // libvgm treats a single trailing byte as a truncated
                    // character and returns the converted prefix; longer
                    // incomplete input falls back to its original bytes.
                    return inputRemaining <= 1
                        ? String(decoding: output[..<outputWritten], as: UTF8.self)
                        : nil
                case E2BIG:
                    if previousOutputWritten == outputWritten { return nil }
                    previousOutputWritten = outputWritten
                    let (growth, growthOverflow) = inputRemaining.multipliedReportingOverflow(by: 2)
                    let (_, capacityOverflow) = output.count.addingReportingOverflow(growth)
                    guard !growthOverflow, !capacityOverflow else { return nil }
                    output.append(contentsOf: repeatElement(0, count: growth))
                default:
                    return nil
                }
            }
        }
        return converted ?? fallback
    }

    private static func trimPSFTagWhitespace(_ string: String) -> String {
        let bytes = Array(string.utf8)
        var start = 0
        var end = bytes.count
        while start < end, bytes[start] <= 0x20 { start += 1 }
        while end > start, bytes[end - 1] <= 0x20 { end -= 1 }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    private static func combinedComment(comment: String?, date: String?, encodedBy: String?) -> String {
        var result = nonempty(comment) ?? ""
        if let date = nonempty(date) {
            if !result.isEmpty { result += " | " }
            result += "Date: " + date
        }
        if let encodedBy = nonempty(encodedBy) {
            if !result.isEmpty { result += " | " }
            result += "Encoded By: " + encodedBy
        }
        return result
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func milliseconds(ticks: UInt32, multiplier: UInt32, divisor: UInt32) -> Int {
        // Match S98Player::Tick2Second's UInt32 product followed by the
        // bridge's double-to-int32 millisecond projection.
        let wrappedNumerator = Int64(ticks &* multiplier)
        let value = Double(wrappedNumerator) / Double(divisor) * 1_000
        return Int(Int32(truncatingIfNeeded: Int64(value)))
    }

    private static func uint32LE(_ bytes: UnsafeBufferPointer<UInt8>, at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= bytes.count - 4, let base = bytes.baseAddress else { return nil }
        return UInt32(base[offset])
            | UInt32(base[offset + 1]) << 8
            | UInt32(base[offset + 2]) << 16
            | UInt32(base[offset + 3]) << 24
    }

    private static func malformed(_ message: String) -> ScannerInspectionError {
        .malformedFile(message)
    }
}
