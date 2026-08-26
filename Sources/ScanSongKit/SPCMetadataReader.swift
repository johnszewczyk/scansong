import Foundation

/// Reads SPC metadata without starting an emulator or invoking libgme.
///
/// SPC files have two independent metadata areas: the original ID666 fields
/// in the 0x100-byte header and an optional xID6 chunk after the 0x10200-byte
/// SPC image.  Both areas are deliberately parsed here because libgme's
/// inspection API does not expose all of the xID6 timing data.
enum SPCMetadataReader {
    private static let minimumFileSize = 0x10200
    private static let extendedTagOffset = 0x10200
    private static let headerMagic = Array("SNES-SPC700 Sound File Data".utf8)
    private static let maximumID666PlaySeconds = 0x1FFF
    private static let maximumID666FadeMilliseconds = 999_999
    private static let maximumXID6Ticks = 383_999_999

    static func read(fileURL: URL) throws -> ScannerMetadata? {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard data.count >= minimumFileSize,
              data.prefix(headerMagic.count).elementsEqual(headerMagic) else {
            throw ScannerInspectionError.malformedFile(
                "Not an SPC file with a valid header: \(fileURL.lastPathComponent)"
            )
        }

        let legacy = legacyMetadata(in: data)
        let extended = extendedMetadata(in: data)
        guard legacy.hasTag || extended.hasTag else { return nil }

        let introLengthMs = extended.introLengthMs ?? 0
        let loopLengthMs = extended.loopLengthMs ?? 0
        let playLengthMs = legacy.playLengthMs > 0
            ? legacy.playLengthMs
            : effectiveExtendedPlayLength(
                introLengthMs: introLengthMs,
                loopLengthMs: loopLengthMs,
                endLengthMs: extended.endLengthMs,
                loopCount: extended.loopCount
            )

        return ScannerMetadata(
            game: extended.game ?? legacy.game,
            song: extended.song ?? legacy.song,
            system: "Super Nintendo",
            author: extended.author ?? legacy.author,
            comment: extended.comment ?? legacy.comment,
            introLengthMs: introLengthMs,
            loopLengthMs: loopLengthMs,
            playLengthMs: playLengthMs,
            fadeLengthMs: extended.fadeLengthMs ?? legacy.fadeLengthMs
        )
    }

    private static func legacyMetadata(in data: Data) -> SPCLegacyMetadata {
        guard data[0x23] == 0x1A else { return SPCLegacyMetadata() }

        let layout = detectID666Layout(in: data)
        let authorRange = layout == .binary ? 0xB0..<0xD0 : 0xB1..<0xD1
        let playLengthMs: Int
        let fadeLengthMs: Int

        switch layout {
        case .text:
            playLengthMs = (decimal(data[0xA9..<0xAC], maximum: maximumID666PlaySeconds) ?? 0) * 1_000
            fadeLengthMs = decimal(data[0xAC..<0xB1], maximum: maximumID666FadeMilliseconds) ?? 0
        case .binary:
            let seconds = Int(littleEndianUInt16(data, at: 0xA9) ?? 0)
            playLengthMs = seconds <= maximumID666PlaySeconds ? seconds * 1_000 : 0
            fadeLengthMs = min(littleEndianUInt24(data, at: 0xAC) ?? 0, maximumID666FadeMilliseconds)
        }

        return SPCLegacyMetadata(
            hasTag: true,
            game: text(data[0x4E..<0x6E]),
            song: text(data[0x2E..<0x4E]),
            author: text(data[authorRange]),
            comment: text(data[0x7E..<0x9E]),
            playLengthMs: playLengthMs,
            fadeLengthMs: fadeLengthMs
        )
    }

    private static func detectID666Layout(in data: Data) -> SPCID666Layout {
        let date = data[0x9E..<0xA9]
        let textPlay = decimal(data[0xA9..<0xAC], maximum: maximumID666PlaySeconds)
        let textFade = decimal(data[0xAC..<0xB1], maximum: maximumID666FadeMilliseconds)
        let binaryPlay = Int(littleEndianUInt16(data, at: 0xA9) ?? 0)
        let binaryFade = littleEndianUInt24(data, at: 0xAC) ?? 0
        let binaryReservedBytesAreClear = data[0xAB] == 0 && data[0xAF] == 0
        let binaryValuesArePlausible = binaryPlay <= maximumID666PlaySeconds
            && binaryFade <= maximumID666FadeMilliseconds

        // A binary date contains raw YYYYMMDD bytes and therefore normally
        // has bytes outside the text date alphabet. This is the strongest
        // discriminator, followed by the reserved bytes and bounded values.
        if date.contains(where: { !isTextDateByte($0) }) {
            return .binary
        }

        let dateHasText = date.contains(where: { (0x30...0x39).contains($0) || $0 == 0x2F })
        if dateHasText {
            return .text
        }

        // Text ID666 places the artist at 0xB1. When the date and timing
        // fields are empty, the NUL at 0xB0 still distinguishes that layout
        // from binary ID666, whose artist starts at 0xB0.
        if data[0xB0] == 0 && !text(data[0xB1..<0xD1]).isEmpty {
            return .text
        }

        // With an empty date, reject the binary interpretation when the
        // binary length would be impossible. This handles text-only tags such
        // as "30\0\0" without relying on a malformed artist-offset guess.
        if binaryReservedBytesAreClear && binaryValuesArePlausible {
            if textPlay == nil && textFade == nil {
                return .binary
            }
            if textFade == nil && binaryPlay > 0 && binaryPlay < 0x100 {
                // A short binary length is commonly mistaken for one ASCII
                // digit followed by NUL; the binary reserved-byte layout wins.
                return .binary
            }
            if textPlay == nil || binaryPlay <= maximumID666PlaySeconds {
                return .binary
            }
        }

        if textPlay != nil || textFade != nil {
            return .text
        }
        return .binary
    }

    private static func extendedMetadata(in data: Data) -> SPCExtendedMetadata {
        guard data.count >= extendedTagOffset + 8,
              data[extendedTagOffset] == Character("x").asciiValue,
              data[extendedTagOffset + 1] == Character("i").asciiValue,
              data[extendedTagOffset + 2] == Character("d").asciiValue,
              data[extendedTagOffset + 3] == Character("6").asciiValue,
              let length = littleEndianUInt32(data, at: extendedTagOffset + 4),
              Int(length) <= data.count - (extendedTagOffset + 8) else {
            return SPCExtendedMetadata()
        }

        let end = extendedTagOffset + 8 + Int(length)
        var metadata = SPCExtendedMetadata(hasTag: true)
        var offset = extendedTagOffset + 8

        while offset < end {
            let remaining = end - offset
            if remaining < 4 {
                // A valid chunk may end with up to three zero padding bytes.
                return data[offset..<end].allSatisfy { $0 == 0 } ? metadata : SPCExtendedMetadata()
            }

            let item = data[offset]
            let type = data[offset + 1]
            let length = Int(littleEndianUInt16(data, at: offset + 2) ?? 0)
            offset += 4

            if type == 0 {
                apply(item: item, type: type, rawValue: UInt32(length), payload: nil, to: &metadata)
                continue
            }

            guard length <= end - offset else { return SPCExtendedMetadata() }
            let payloadEnd = offset + length
            let payload = data[offset..<payloadEnd]
            apply(item: item, type: type, rawValue: nil, payload: payload, to: &metadata)

            let paddedEnd = offset + ((length + 3) & ~3)
            if paddedEnd <= end && data[payloadEnd..<paddedEnd].allSatisfy({ $0 == 0 }) {
                offset = paddedEnd
            } else {
                // Some writers omit alignment padding. Accept that form when
                // the declared payload itself is still inside the chunk.
                offset = payloadEnd
            }
        }

        return metadata
    }

    private static func apply(
        item: UInt8,
        type: UInt8,
        rawValue: UInt32?,
        payload: Data.SubSequence?,
        to metadata: inout SPCExtendedMetadata
    ) {
        switch (item, type) {
        case (0x01, 1): metadata.song = nonEmptyText(payload)
        case (0x02, 1): metadata.game = nonEmptyText(payload)
        case (0x03, 1): metadata.author = nonEmptyText(payload)
        case (0x07, 1): metadata.comment = nonEmptyText(payload)
        case (0x30, 4): metadata.introLengthMs = ticksToMilliseconds(payload)
        case (0x31, 4): metadata.loopLengthMs = ticksToMilliseconds(payload)
        case (0x32, 4): metadata.endLengthMs = ticksToMilliseconds(payload)
        case (0x33, 4): metadata.fadeLengthMs = ticksToMilliseconds(payload)
        case (0x35, 0): metadata.loopCount = Int(rawValue ?? 0) & 0xFF
        default: break
        }
    }

    private static func effectiveExtendedPlayLength(
        introLengthMs: Int,
        loopLengthMs: Int,
        endLengthMs: Int?,
        loopCount: Int?
    ) -> Int {
        let end = max(0, endLengthMs ?? 0)
        guard introLengthMs > 0 || loopLengthMs > 0 || end > 0 else { return 0 }

        // xID6 describes the intro, loop, and end as separate segments. If a
        // loop count is absent, one loop is the same conservative natural
        // duration used by both playback clients. A present count is the
        // number of loop-section repetitions; zero therefore means no loop.
        let repetitions = max(0, loopCount ?? 1)
        return introLengthMs + loopLengthMs * repetitions + end
    }

    private static func ticksToMilliseconds(_ payload: Data.SubSequence?) -> Int? {
        guard let payload, payload.count == 4 else { return nil }
        guard let raw = littleEndianUInt32(payload) else { return nil }
        let ticks = Int64(Int32(bitPattern: raw))
        guard ticks >= 0, ticks <= Int64(maximumXID6Ticks) else { return nil }
        return Int(ticks * 1_000 / 64_000)
    }

    private static func nonEmptyText(_ payload: Data.SubSequence?) -> String? {
        guard let payload else { return nil }
        let value = text(payload)
        return value.isEmpty ? nil : value
    }

    private static func text(_ bytes: some Collection<UInt8>) -> String {
        let bytes = Data(bytes.prefix { $0 != 0 })
        return (String(data: bytes, encoding: .windowsCP1252) ?? String(decoding: bytes, as: UTF8.self))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decimal(_ bytes: some Collection<UInt8>, maximum: Int) -> Int? {
        var value = 0
        var sawDigit = false
        for byte in bytes {
            if byte == 0 { break }
            if byte == 0x20 || byte == 0x09 { continue }
            guard (0x30...0x39).contains(byte) else { return nil }
            sawDigit = true
            value = value * 10 + Int(byte - 0x30)
            if value > maximum { return nil }
        }
        return sawDigit ? value : nil
    }

    private static func isTextDateByte(_ byte: UInt8) -> Bool {
        byte == 0 || byte == 0x20 || byte == 0x2F || (0x30...0x39).contains(byte)
    }

    private static func littleEndianUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func littleEndianUInt24(_ data: Data, at offset: Int) -> Int? {
        guard offset + 3 <= data.count else { return nil }
        return Int(data[offset]) | Int(data[offset + 1]) << 8 | Int(data[offset + 2]) << 16
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private static func littleEndianUInt32(_ bytes: Data.SubSequence) -> UInt32? {
        guard bytes.count == 4 else { return nil }
        let values = Array(bytes)
        return UInt32(values[0]) | UInt32(values[1]) << 8
            | UInt32(values[2]) << 16 | UInt32(values[3]) << 24
    }
}

private enum SPCID666Layout {
    case text
    case binary
}

struct SPCLegacyMetadata {
    var hasTag = false
    var game = ""
    var song = ""
    var author = ""
    var comment = ""
    var playLengthMs = 0
    var fadeLengthMs = 0
}

struct SPCExtendedMetadata {
    var hasTag = false
    var game: String?
    var song: String?
    var author: String?
    var comment: String?
    var introLengthMs: Int?
    var loopLengthMs: Int?
    var endLengthMs: Int?
    var fadeLengthMs: Int?
    var loopCount: Int?
}
