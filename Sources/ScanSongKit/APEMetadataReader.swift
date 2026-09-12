import Foundation

/// Reads the scanner-visible APE contract without opening an audio decoder.
/// Playback remains owned by VGMBoy's FFmpeg bridge.
public enum APEMetadataReader {
    public static func read(fileURL: URL) throws -> ScannerMetadata {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            throw ScannerInspectionError.library("Could not read APE source \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }

        do {
            let id3 = try leadingID3Tags(in: data)
            let header = try readHeader(in: data, at: id3.containerOffset)
            let apeTags = readAPEv2Tags(in: data)
            var tags = id3.tags
            for (key, value) in apeTags { tags[key] = value }

            let title = normalized(tags["title"]) ?? fileURL.deletingPathExtension().lastPathComponent
            let album = tags["album"] ?? tags["album_name"] ?? ""
            let artist = tags["artist"] ?? tags["album_artist"] ?? ""
            return ScannerMetadata(
                game: normalized(album) ?? "",
                song: title,
                system: "Standard audio",
                author: normalized(artist) ?? "",
                comment: tags["comment"] ?? "",
                introLengthMs: 0,
                loopLengthMs: 0,
                playLengthMs: header.durationMilliseconds,
                fadeLengthMs: 0
            )
        } catch let error as ScannerInspectionError {
            throw error
        } catch {
            throw ScannerInspectionError.malformedFile(
                "Invalid APE structure in \(fileURL.lastPathComponent): \(error.localizedDescription)"
            )
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private struct ID3Prefix {
        let containerOffset: Int
        let tags: [String: String]
    }

    private struct APEHeader {
        let durationMilliseconds: Int
    }

    private static func leadingID3Tags(in data: Data) throws -> ID3Prefix {
        var offset = 0
        var tags: [String: String] = [:]
        var parsedTagCount = 0

        while hasBytes(data, at: offset, matching: [0x49, 0x44, 0x33]) {
            guard parsedTagCount < 8, offset <= data.count - 10 else {
                throw malformed("Truncated or excessive leading ID3 tags.")
            }
            let major = Int(data[offset + 3])
            let flags = data[offset + 5]
            guard (2...4).contains(major) else { throw malformed("Unsupported leading ID3 version.") }
            let size = try synchsafeSize(data, at: offset + 6)
            let footerSize = major == 4 && flags & 0x10 != 0 ? 10 : 0
            let bodyStart = offset + 10
            let (bodyEnd, bodyOverflow) = bodyStart.addingReportingOverflow(size)
            let (tagEnd, endOverflow) = bodyEnd.addingReportingOverflow(footerSize)
            guard !bodyOverflow, !endOverflow, tagEnd <= data.count else {
                throw malformed("Leading ID3 tag extends past end of file.")
            }

            var body = Array(data[bodyStart..<bodyEnd])
            if flags & 0x80 != 0 { body = removeUnsynchronization(body) }
            let frameTags = parseID3Frames(body, majorVersion: major, flags: flags)
            for (key, value) in frameTags { tags[key] = value }
            offset = tagEnd
            parsedTagCount += 1
        }

        guard hasBytes(data, at: offset, matching: Array("MAC ".utf8)) else {
            throw malformed("APE header signature is missing after any leading ID3 tag.")
        }
        return ID3Prefix(containerOffset: offset, tags: tags)
    }

    private static func parseID3Frames(_ body: [UInt8], majorVersion: Int, flags: UInt8) -> [String: String] {
        var tags: [String: String] = [:]
        var cursor = 0
        if flags & 0x40 != 0 {
            guard body.count >= 4 else { return tags }
            let extendedSize: Int
            if majorVersion == 4 {
                guard let size = synchsafeSize(body, at: 0) else { return tags }
                extendedSize = size
            } else {
                extendedSize = Int(readUInt32BE(body, at: 0) ?? 0) + 4
            }
            guard extendedSize >= 4, extendedSize <= body.count else { return tags }
            cursor = extendedSize
        }

        while cursor < body.count {
            let identifierLength = majorVersion == 2 ? 3 : 4
            let frameHeaderLength = identifierLength + (majorVersion == 2 ? 3 : 6)
            guard cursor <= body.count - frameHeaderLength else { break }
            if body[cursor] == 0 { break }
            let identifierBytes = body[cursor..<(cursor + identifierLength)]
            guard identifierBytes.allSatisfy({ (0x30...0x5A).contains($0) }) else { break }
            let identifier = String(decoding: identifierBytes, as: UTF8.self)
            let sizeOffset = cursor + identifierLength
            let frameSize: Int
            if majorVersion == 2 {
                frameSize = (Int(body[sizeOffset]) << 16) | (Int(body[sizeOffset + 1]) << 8) | Int(body[sizeOffset + 2])
            } else if majorVersion == 4 {
                guard let size = synchsafeSize(body, at: sizeOffset) else { break }
                frameSize = size
            } else {
                guard let size = readUInt32BE(body, at: sizeOffset) else { break }
                frameSize = Int(size)
            }
            let frameFlags = majorVersion == 2 ? 0 : Int(body[sizeOffset + 4]) << 8 | Int(body[sizeOffset + 5])
            let payloadStart = cursor + frameHeaderLength
            let (payloadEnd, overflow) = payloadStart.addingReportingOverflow(frameSize)
            guard !overflow, payloadEnd <= body.count else { break }
            var payload = Array(body[payloadStart..<payloadEnd])
            let unsupportedFrameEncoding = majorVersion == 3
                ? frameFlags & (0x0080 | 0x0040 | 0x0020) != 0
                : frameFlags & (0x0008 | 0x0004 | 0x0040 | 0x0001) != 0
            if !unsupportedFrameEncoding {
                if majorVersion == 4 && frameFlags & 0x0002 != 0 { payload = removeUnsynchronization(payload) }
                if let pair = id3Value(identifier: identifier, payload: payload) { tags[pair.0] = pair.1 }
            }
            cursor = payloadEnd
        }
        return tags
    }

    private static func id3Value(identifier: String, payload: [UInt8]) -> (String, String)? {
        let key: String
        let isComment: Bool
        switch identifier {
        case "TIT2", "TT2": key = "title"; isComment = false
        case "TALB", "TAL": key = "album"; isComment = false
        case "TPE1", "TP1": key = "artist"; isComment = false
        case "TPE2", "TP2": key = "album_artist"; isComment = false
        case "COMM", "COM": key = "comment"; isComment = true
        default: return nil
        }
        guard let encoding = payload.first else { return nil }
        var textBytes = Array(payload.dropFirst())
        if isComment {
            guard textBytes.count >= 3 else { return nil }
            textBytes.removeFirst(3) // language
            let terminatorWidth = encoding == 1 || encoding == 2 ? 2 : 1
            if let separator = textTerminator(in: textBytes, width: terminatorWidth) {
                textBytes = Array(textBytes.dropFirst(separator + terminatorWidth))
            } else {
                return nil
            }
        }
        guard let value = decodeID3Text(textBytes, encoding: encoding) else { return nil }
        return (key, value)
    }

    private static func decodeID3Text(_ bytes: [UInt8], encoding: UInt8) -> String? {
        let width = encoding == 1 || encoding == 2 ? 2 : 1
        let content: [UInt8]
        if let end = textTerminator(in: bytes, width: width) {
            content = Array(bytes.prefix(end))
        } else {
            content = bytes
        }
        let data = Data(content)
        switch encoding {
        case 0: return String(data: data, encoding: .isoLatin1)
        case 1: return String(data: data, encoding: .utf16)
        case 2: return String(data: data, encoding: .utf16BigEndian)
        case 3: return String(data: data, encoding: .utf8)
        default: return nil
        }
    }

    private static func textTerminator(in bytes: [UInt8], width: Int) -> Int? {
        guard width == 1 else {
            guard bytes.count >= 2 else { return nil }
            for index in stride(from: 0, through: bytes.count - 2, by: 2) where bytes[index] == 0 && bytes[index + 1] == 0 {
                return index
            }
            return nil
        }
        return bytes.firstIndex(of: 0)
    }

    private static func removeUnsynchronization(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            result.append(byte)
            index += 1
            if byte == 0xFF, index < bytes.count, bytes[index] == 0 { index += 1 }
        }
        return result
    }

    private static func readHeader(in data: Data, at start: Int) throws -> APEHeader {
        guard data.count >= 6, start >= 0, start <= data.count - 6 else { throw malformed("APE header is truncated.") }
        let version = Int(try uint16LE(data, at: start + 4))
        guard (3_800...3_990).contains(version) else { throw malformed("Unsupported APE version \(version).") }

        var descriptorLength = 0
        var headerLength: Int
        var seekTableLength: Int
        var wavHeaderLength: UInt32
        var wavTailLength: UInt32 = 0
        var audioDataLength: UInt64?
        var headerOffset: Int
        var compressionType: UInt16
        var formatFlags: UInt16
        var channels: UInt16
        var sampleRate: UInt32
        var blocksPerFrame: UInt32
        var finalFrameBlocks: UInt32
        var totalFrames: UInt32
        var bytesPerSample: UInt16

        if version >= 3_980 {
            guard start <= data.count - 52 else { throw malformed("APE descriptor is truncated.") }
            descriptorLength = Int(try uint32LE(data, at: start + 8))
            headerLength = Int(try uint32LE(data, at: start + 12))
            seekTableLength = Int(try uint32LE(data, at: start + 16))
            wavHeaderLength = try uint32LE(data, at: start + 20)
            let audioLow = UInt64(try uint32LE(data, at: start + 24))
            let audioHigh = UInt64(try uint32LE(data, at: start + 28))
            audioDataLength = (audioHigh << 32) | audioLow
            wavTailLength = try uint32LE(data, at: start + 32)
            guard descriptorLength >= 52, headerLength >= 24 else { throw malformed("APE descriptor or header length is invalid.") }
            headerOffset = try checkedAdd(start, descriptorLength, "APE descriptor")
            guard headerOffset <= data.count - 24 else { throw malformed("APE header block is truncated.") }
            compressionType = try uint16LE(data, at: headerOffset)
            formatFlags = try uint16LE(data, at: headerOffset + 2)
            blocksPerFrame = try uint32LE(data, at: headerOffset + 4)
            finalFrameBlocks = try uint32LE(data, at: headerOffset + 8)
            totalFrames = try uint32LE(data, at: headerOffset + 12)
            bytesPerSample = try uint16LE(data, at: headerOffset + 16)
            channels = try uint16LE(data, at: headerOffset + 18)
            sampleRate = try uint32LE(data, at: headerOffset + 20)
        } else {
            headerLength = 32
            guard start <= data.count - headerLength else { throw malformed("Legacy APE header is truncated.") }
            var cursor = start + 6
            compressionType = try uint16LE(data, at: cursor); cursor += 2
            formatFlags = try uint16LE(data, at: cursor); cursor += 2
            channels = try uint16LE(data, at: cursor); cursor += 2
            sampleRate = try uint32LE(data, at: cursor); cursor += 4
            wavHeaderLength = try uint32LE(data, at: cursor); cursor += 4
            wavTailLength = try uint32LE(data, at: cursor); cursor += 4
            totalFrames = try uint32LE(data, at: cursor); cursor += 4
            finalFrameBlocks = try uint32LE(data, at: cursor); cursor += 4
            if formatFlags & 0x0004 != 0 {
                guard cursor <= data.count - 4 else { throw malformed("Legacy APE peak-level field is truncated.") }
                cursor += 4
                headerLength += 4
            }
            if formatFlags & 0x0010 != 0 {
                let seekEntries = try uint32LE(data, at: cursor)
                cursor += 4
                headerLength += 4
                let (tableBytes, overflow) = Int(seekEntries).multipliedReportingOverflow(by: 4)
                guard !overflow else { throw malformed("APE seek table length overflows.") }
                seekTableLength = tableBytes
            } else {
                let (tableBytes, overflow) = Int(totalFrames).multipliedReportingOverflow(by: 4)
                guard !overflow else { throw malformed("APE seek table length overflows.") }
                seekTableLength = tableBytes
            }
            bytesPerSample = formatFlags & 0x0001 != 0 ? 8 : (formatFlags & 0x0008 != 0 ? 24 : 16)
            blocksPerFrame = version >= 3_950 ? 294_912 : (version >= 3_900 || compressionType >= 4_000 ? 73_728 : 9_216)
            headerOffset = start
        }

        guard compressionType > 0,
              totalFrames > 0,
              blocksPerFrame > 0,
              finalFrameBlocks > 0,
              finalFrameBlocks <= blocksPerFrame,
              (1...32).contains(channels),
              (8...32).contains(bytesPerSample),
              (1...768_000).contains(sampleRate) else {
            throw malformed("APE stream parameters are invalid.")
        }
        let (minimumSeekBytes, seekOverflow) = Int(totalFrames).multipliedReportingOverflow(by: 4)
        guard !seekOverflow, seekTableLength >= minimumSeekBytes,
              seekTableLength <= 64 * 1024 * 1024 else {
            throw malformed("APE seek table is missing, truncated, or excessive.")
        }

        let (headerEnd, headerOverflow) = headerOffset.addingReportingOverflow(headerLength)
        let (seekTableEnd, seekOverflow2) = headerEnd.addingReportingOverflow(seekTableLength)
        let (waveEnd, waveOverflow) = seekTableEnd.addingReportingOverflow(Int(wavHeaderLength))
        let bitTableLength = version < 3_810 ? Int(totalFrames) : 0
        let (firstFrame, frameOverflow) = waveEnd.addingReportingOverflow(bitTableLength)
        guard !headerOverflow, !seekOverflow2, !waveOverflow, !frameOverflow,
              firstFrame <= data.count else {
            throw malformed("APE headers or seek table extend past end of file.")
        }

        let tableOffset = headerEnd
        guard tableOffset <= data.count - seekTableLength else { throw malformed("APE seek table is truncated.") }
        let lastTagStart = apeTagStart(in: data) ?? data.count
        let declaredEnd: Int
        if let audioDataLength, audioDataLength > 0 {
            guard audioDataLength <= UInt64(Int.max) else { throw malformed("APE audio data length is excessive.") }
            let (audioEnd, audioOverflow) = firstFrame.addingReportingOverflow(Int(audioDataLength))
            let (withWaveTail, tailOverflow) = audioEnd.addingReportingOverflow(Int(wavTailLength))
            guard !audioOverflow, !tailOverflow, withWaveTail <= lastTagStart else {
                throw malformed("APE audio data range extends past the file payload.")
            }
            declaredEnd = audioEnd
        } else {
            guard Int(wavTailLength) <= lastTagStart else { throw malformed("APE WAV tail length is invalid.") }
            declaredEnd = lastTagStart - Int(wavTailLength)
        }
        guard firstFrame < declaredEnd else { throw malformed("APE audio payload is empty.") }

        var previousFrame = firstFrame
        let frameCount = Int(totalFrames)
        for index in 1..<frameCount {
            let entryOffset = tableOffset + index * 4
            let entry = Int(try uint32LE(data, at: entryOffset))
            let (frameOffset, offsetOverflow) = start.addingReportingOverflow(entry)
            guard !offsetOverflow, frameOffset > previousFrame, frameOffset < declaredEnd else {
                throw malformed("APE seek table contains an invalid frame offset.")
            }
            previousFrame = frameOffset
        }

        let sampleCount = UInt64(totalFrames - 1) * UInt64(blocksPerFrame) + UInt64(finalFrameBlocks)
        let wholeMilliseconds = (sampleCount / UInt64(sampleRate)).multipliedReportingOverflow(by: 1_000)
        let fractionalMilliseconds = (sampleCount % UInt64(sampleRate) * 1_000 + UInt64(sampleRate / 2)) / UInt64(sampleRate)
        let (durationMilliseconds, durationOverflow) = wholeMilliseconds.partialValue.addingReportingOverflow(fractionalMilliseconds)
        guard !wholeMilliseconds.overflow, !durationOverflow, durationMilliseconds <= UInt64(Int.max) else {
            throw malformed("APE duration is outside the scanner's supported range.")
        }
        return APEHeader(durationMilliseconds: Int(durationMilliseconds))
    }

    private static func readAPEv2Tags(in data: Data) -> [String: String] {
        guard data.count >= 32 else { return [:] }
        let footer = data.count - 32
        guard hasBytes(data, at: footer, matching: Array("APETAGEX".utf8)),
              let version = try? uint32LE(data, at: footer + 8), version <= 2_000,
              let tagSizeRaw = try? uint32LE(data, at: footer + 12), tagSizeRaw >= 32,
              let itemCountRaw = try? uint32LE(data, at: footer + 16), itemCountRaw <= 65_536,
              let flags = try? uint32LE(data, at: footer + 20) else { return [:] }
        let tagSize = Int(tagSizeRaw)
        guard tagSize <= 16 * 1024 * 1024 + 32, tagSize <= data.count else { return [:] }
        let fieldsStart = data.count - tagSize
        guard fieldsStart <= footer else { return [:] }
        let itemStart = fieldsStart
        guard itemStart <= footer,
              flags & 0x2000_0000 == 0 else { return [:] } // footer must not claim to be a tag header

        var result: [String: String] = [:]
        var cursor = itemStart
        for _ in 0..<Int(itemCountRaw) {
            guard cursor <= footer - 8,
                  let valueLengthRaw = try? uint32LE(data, at: cursor),
                  let itemFlags = try? uint32LE(data, at: cursor + 4) else { return [:] }
            let valueLength = Int(valueLengthRaw)
            cursor += 8
            let keyStart = cursor
            while cursor < footer, data[cursor] >= 0x20, data[cursor] <= 0x7E { cursor += 1 }
            guard cursor < footer, data[cursor] == 0, cursor > keyStart,
                  cursor - keyStart <= 1_023 else { return [:] }
            let key = String(decoding: data[keyStart..<cursor], as: UTF8.self).lowercased()
            cursor += 1
            let (valueEnd, overflow) = cursor.addingReportingOverflow(valueLength)
            guard !overflow, valueEnd <= footer else { return [:] }
            if itemFlags & 0x0000_0002 == 0 {
                let valueData = Data(data[cursor..<valueEnd])
                let withoutNUL = valueData.prefix { $0 != 0 }
                result[key] = String(data: Data(withoutNUL), encoding: .utf8)
                    ?? String(decoding: withoutNUL, as: UTF8.self)
            }
            cursor = valueEnd
        }
        return result
    }

    private static func apeTagStart(in data: Data) -> Int? {
        guard data.count >= 32 else { return nil }
        let footer = data.count - 32
        guard hasBytes(data, at: footer, matching: Array("APETAGEX".utf8)),
              let tagSize = try? uint32LE(data, at: footer + 12),
              let flags = try? uint32LE(data, at: footer + 20),
              tagSize >= 32 else { return nil }
        let headerSize = flags & 0x8000_0000 != 0 ? 32 : 0
        let (totalSize, overflow) = Int(tagSize).addingReportingOverflow(headerSize)
        guard !overflow, totalSize <= data.count else { return nil }
        return data.count - totalSize
    }

    private static func synchsafeSize(_ data: Data, at offset: Int) throws -> Int {
        guard offset >= 0, offset <= data.count - 4 else { throw malformed("ID3 size field is truncated.") }
        for index in offset..<(offset + 4) where data[index] & 0x80 != 0 {
            throw malformed("ID3 size field is not synchsafe.")
        }
        return (Int(data[offset]) << 21) | (Int(data[offset + 1]) << 14) | (Int(data[offset + 2]) << 7) | Int(data[offset + 3])
    }

    private static func synchsafeSize(_ bytes: [UInt8], at offset: Int) -> Int? {
        guard offset >= 0, offset <= bytes.count - 4,
              bytes[offset] & 0x80 == 0, bytes[offset + 1] & 0x80 == 0,
              bytes[offset + 2] & 0x80 == 0, bytes[offset + 3] & 0x80 == 0 else { return nil }
        return (Int(bytes[offset]) << 21) | (Int(bytes[offset + 1]) << 14) | (Int(bytes[offset + 2]) << 7) | Int(bytes[offset + 3])
    }

    private static func readUInt32BE(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= bytes.count - 4 else { return nil }
        return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }

    private static func uint16LE(_ data: Data, at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset <= data.count - 2 else { throw malformed("APE 16-bit field is truncated.") }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func uint32LE(_ data: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset <= data.count - 4 else { throw malformed("APE 32-bit field is truncated.") }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private static func hasBytes(_ data: Data, at offset: Int, matching bytes: [UInt8]) -> Bool {
        guard offset >= 0, offset <= data.count - bytes.count else { return false }
        return bytes.indices.allSatisfy { data[offset + $0] == bytes[$0] }
    }

    private static func checkedAdd(_ lhs: Int, _ rhs: Int, _ name: String) throws -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw malformed("\(name) length overflows.") }
        return result
    }

    private static func malformed(_ detail: String) -> ScannerInspectionError {
        .malformedFile(detail)
    }
}
