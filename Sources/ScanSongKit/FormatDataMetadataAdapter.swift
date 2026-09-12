import VGMBoyFormatDataCore

extension ScannerMetadata {
    init(formatMetadata: FormatMetadata) {
        self.init(
            game: formatMetadata.game,
            song: formatMetadata.song,
            system: formatMetadata.system,
            author: formatMetadata.author,
            comment: formatMetadata.comment,
            introLengthMs: formatMetadata.introLengthMs,
            loopLengthMs: formatMetadata.loopLengthMs,
            playLengthMs: formatMetadata.playLengthMs,
            fadeLengthMs: formatMetadata.fadeLengthMs
        )
    }
}
