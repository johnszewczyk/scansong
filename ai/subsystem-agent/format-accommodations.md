# ScanSong format accommodations

## Scope and reading rules

This document describes the scanner's current behavior for every registered
intake route. It is intentionally more specific than a list of decoder names:
an extension is admitted only according to the route in
[`BuiltInScannerPlugins.swift`](/Users/john/Downloads/Code/VGMMan/ScanSong/Sources/ScanSongKit/BuiltInScannerPlugins.swift), and a row is published only according to that route's structure and metadata handler.

Scanner admission, metadata availability, and playback compatibility are
separate facts. A format may have a useful scanner row while its playback
decoder still needs a dependency set; conversely, a VGMBoy playback format may
be deliberately absent from ScanSong until a safe scanner adapter exists.
Malformed files remain failures. ScanSong never turns a decoder failure into a
fake one-track record merely to make a collection look complete.

## Route summary

| ScanSong route | Registered extensions | Structure published | Metadata source | Dependency or archive rule |
| --- | --- | --- | --- | --- |
| `gme` | `.spc` | One track | Native SPC ID666/xID6 reader | No emulator is started for ordinary metadata inspection. |
| `gme-multitrack` | `.ay`, `.gbs`, `.hes`, `.kss`, `.nsf`, `.nsfe`, `.sap` | One row per libgme track | libgme track enumeration and timing; NSF/GBS headers supplement text | HES may use a same-basename `.m3u`; the playlist is support data. |
| `openmpt` | `.669`, `.dmf`, `.far`, `.it`, `.mod`, `.mptm`, `.mtm`, `.okt`, `.ptm`, `.s3m`, `.stm`, `.ult`, `.xm` | One structurally-known row | Optional/deferred; metadata may be empty | No scanner-side module conversion or archive expansion. |
| `standard-audio` | `.aif`, `.aiff`, `.flac`, `.m4a`, `.mp3`, `.ogg`, `.wav` | One track | Core Audio duration and common tags; FLAC Vorbis comments | Exact decoded duration is preferred. |
| `ffmpeg-audio` | `.ape` | One structurally-known row | Optional/deferred; metadata may be empty | Registered for policy compatibility; no scanner-side transcode. |
| `libvgm` | `.gym`, `.s98`, `.vgm`, `.vgz` | One stream row | Direct VGM/VGZ GD3 and timing; GYM/S98 text may be empty | VGZ is bounded gzip decompression, not a generic archive. |
| `psgplay` | `.sndh` | One row per declared subtune | Shared `VGMBoySNDH` header/timing reader | Never starts PSGPlay during metadata inspection. |
| `mdx` | `.mdx` | One logical sequence row | VGMBoy-built `vgmboy-mdx-inspect` | A declared PDX bank is prepared but never published as a track. |
| `amiga-uade` | UADE replayer prefixes (`mod.*`, `p4x.*`, `med.*`, TFMX, and custom players) | One row per UADE subsong | VGMBoy-built `vgmboy-amiga-inspect` | `.lha` and loose sets are materialized as complete sets; companions remain dependency data. |
| `highly-complete` | `.gsf`, `.minigsf` | One validated row | VGMBoy-built inspector plus PSF-style tags | Complete miniGSF dependency set is required. |
| `highly-theoretical` | `.ssf`, `.minissf` | One structurally-known row | PSF-style footer tags | Scanner tags the PSF container; a native playback route is not implied. |
| `lazyusf` | `.usf`, `.miniusf` | One structurally-known row | PSF-style footer tags | `.usflib` is playback dependency data, never a row. |
| `twosf` | `.2sf`, `.mini2sf` | One structurally-known row | PSF-style footer tags | `.2sflib` is dependency data, never a row. |
| `vgmstream` | Direct raw-stream extensions listed below | One row per reported subsong | VGMBoy-built `vgmstream-cli` | Native `-I` inspection; subsong count is bounded. |
| `vgmstream-txtp` | `.txtp` | One row per resolved subsong | `vgmstream-cli` after dependency preparation | Authored TXTP structure is authoritative. |
| `vgmstream-hd-bank` | `.hd`, `.hbd`, `.iecs` | One row per resolved subsong | `vgmstream-cli` after dependency preparation | Bank/control sidecars are support data; IECS remains a known adapter boundary. |
| `play-psf1` | `.psf`, `.minipsf` | One structurally-known row | PSF-style footer tags | `.psflib` is playback dependency data, never a row. |
| `play-psf2` | `.psf2`, `.minipsf2` | One structurally-known row | PSF-style footer tags | `.psflib` is playback dependency data, never a row. |
| `qsf` | `.qsf` | One validated row | QSF inspector, with PSF-style tags merged | QSound engine validates the source. |
| `qsf-mini` | `.miniqsf` | One validated row | QSF inspector, with PSF-style tags merged | Required `.qsflib` must be available in the extracted set. |
| `sid` | `.sid` | One structurally-known row | PSID/RSID header reader | No finite duration is invented when the header has none. |

The route table is deliberately not a claim that every registered source is
playable in every frontend. VGMBoy's playback registry and the scanner's
registry are separate contracts; the [VGMBoy format registry](/Users/john/Downloads/Code/VGMMan/VGMBoy/Sources/VGMBoyKit/FormatRegistry.swift) is the playback source of truth.

## Game Music Emu family

### SPC: direct native timing

`.spc` is registered as `gme` with `knownSingle` structure and direct metadata.
`SPCMetadataReader` maps the fixed ID666 header and optional xID6 extension in
process. It accepts both text and binary ID666 timing layouts, aggregates
segmented xID6 values, bounds all lengths, and ignores unknown xID6 item types
after validating their boundaries. This makes length and fade available without
starting libgme and avoids paying emulator startup cost for every SPC.

The scanner stores `play_length_ms`, `fade_length_ms`, intro, and loop values
as supplied by the native metadata. A missing or invalid native length remains
zero at the scanner boundary; player defaults must not be mistaken for scanner
metadata. A malformed SPC produces an archive-member failure.

### AY, GBS, HES, KSS, NSF, NSFE, and SAP

These formats use `gme-multitrack` and are opened in libgme's information-only
mode. The scanner asks libgme for the track count, reads each track's authored
title/system/author/comment and timing, and emits a contiguous zero-based
track index for every track.

NSF and GBS fixed-header text is read as a supplement where useful, but libgme
remains authoritative for track enumeration and timing. A file with no tracks
or a missing track-info result fails explicitly.

HES needs extra care. If a same-basename `.m3u` is present, ScanSong loads it
before asking libgme for track information; this converts raw address slots
into the rip's authored music and SFX set. Without the playlist, ScanSong still
inspects the file but suppresses unverified HES timing rather than presenting
the raw 256-slot address space as a real album. The `.m3u` itself is support
data and is not a catalog track.

## SNDH / PSGPlay

`.sndh` is a multi-track executable Atari ST music format and receives the
strongest scanner-specific treatment. The route is `psgplay`, with direct
metadata from the shared `VGMBoySNDH` product. ScanSong reads the header and
declared subtune table without starting the PSG emulator. Each declared
subtune becomes one row, with:

- a contiguous zero-based `track_index`;
- the same declared `track_count` on every row;
- the subtune name when present, otherwise the file title;
- the file composer/year fields;
- the subtune's authored duration in `play_length_ms`.

This accommodates SNDH's common complications: default versus selected
subtunes, embedded sound-effect banks, loader/demo files, and files that open
but do not produce conventional music. Scanner publication proves structure
and timing only. VGMBoy separately validates that each declared subtune can
be selected, restarted, and rendered; a file that is valid SNDH but silent or
hardware-specific is not silently converted into a false music claim.

## MDX and PDX

`.mdx` is a one-track logical X68000 sequence. ScanSong invokes the
VGMBoy-built `vgmboy-mdx-inspect` executable, so metadata and duration come
from the same mdxmini implementation used by playback. MDX dependency names
are decoded using the legacy Shift-JIS convention, with UTF-8 fallback for
hand-authored files.

PDX is native X68000 sample-bank data, not an archive and not an alternate MDX
encoding. It is never routed as a playable source. When an MDX declares a PDX,
ScanSong looks for a case-insensitive local sibling first, including
`.pdx.zst`/`.pdx.zstd`, then optionally uses a deterministic root-scoped index:
nearest shared folder, uncompressed before compressed, and lexical path order.
It never searches outside the supplied scan root.

For `name.MDX.zst`, the decompressed MDX is placed in disposable scratch and
the matching PDX is materialized beside it before the inspector starts. A
standalone compressed PDX is suppressed from discovery. For TAR.ZST, the
complete archive is extracted into disposable scratch, the MDX header is read,
and its PDX member is retained as dependency data. A declared but missing PDX
is an explicit MDX failure; it is not a successful metadata row with an
unknown dependency.

The VGMBoy/mdxmini boundary also handles the inner X68000 LZX 0.32/0.42 form.
For MDX, the clear title and dependency header are preserved while only the
compressed sequence body is decoded. For PDX, a whole-file LZX stream is
decoded before the native sample-bank table is parsed. This is a lossless
scratch-layer accommodation: the outer `.zst` and original MDX/PDX payloads
are never rewritten. A legacy leading backslash in a PDX basename is treated
as a same-directory reference; absolute and traversal spellings remain unsafe.

## PSF-family routes

PSF-style footer tags are useful for catalog presentation but do not by
themselves prove that an emulation core can open the source. ScanSong therefore
keeps the following distinctions visible:

### GSF / miniGSF

`highly-complete` is a required external inspector. It creates the parser/core
handle and validates the complete `_lib` chain before returning one track. The
direct `[TAG]` footer is merged for authored title/game/artist/comment and
length/fade, while the inspector remains responsible for accepting the actual
payload. A missing `.gsflib` or invalid ROM chain is a failure.

### QSF / miniQSF

`qsf` and `qsf-mini` use the VGMBoy-built QSF process adapter. A miniQSF is
accepted only when the Audio Overload QSound engine can resolve its required
`.qsflib`; the direct PSF-style tag footer supplements the decoder response.
The scanner exposes one QSound track per source. Because the QSound engine is
process-global, the inspector uses a bounded subprocess rather than sharing a
frontend playback process.

### PSF, PSF2, SSF, and USF

`play-psf1`, `play-psf2`, `highly-theoretical`, and `lazyusf` currently use the
safe PSF-style metadata reader for one structurally-known row. This reader
extracts bounded `[TAG]` fields and maps `length`/`fade` without emulation.
The row may therefore have empty metadata when no footer exists.

Their sidecars are never independent scanner sources. The recognized support
names are `.psflib`, `.2sflib`, `.ssflib`, and `.usflib`; they are omitted from
archive `unrecognized` diagnostics and from standalone `.zst` discovery. The
actual playback materializer must still stage the complete dependency set for
formats whose core requires it. ScanSong does not claim successful playback
solely because a PSF footer was readable.

## libVGM

`.vgm`, `.vgz`, `.gym`, and `.s98` use the `libvgm` route. ScanSong publishes
one stream row per source: these are not treated as multi-track archives even
though the route's decoder policy is shared with other enumerating families.

For VGM and VGZ, the scanner directly validates the VGM header and reads GD3
text, total samples, and loop samples. VGZ decompression is bounded to a fixed
maximum output size. GYM and S98 remain admitted through the libVGM route but
do not receive invented GD3 metadata when their native headers do not expose
it. A libVGM/open failure is retained as a failure record.

## vgmstream raw streams, TXTP, and banks

### Raw direct streams

The direct vgmstream set is owned by VGMBoy's
[`VGMStreamFormatManifest.swift`](/Users/john/Downloads/Code/VGMMan/VGMBoy/Sources/VGMBoyFormatCore/VGMStreamFormatManifest.swift):

```text
.aa3 .adx .ads .ahx .aifc .at3 .aus .bik .bika .bnk .dvi .fsb .genh .int
.mib .msf .mtaf .rws .ss2 .stream .strm .svag .vag .xa .xmd
```

The scanner invokes the bundled `vgmstream-cli -I`. It reads sample rate,
total/play sample counts, loop bounds, source name, and decoder metadata. A
reported subsong count is capped at 1,000; each subsong is inspected with its
one-based `-s` selector and becomes a separate catalog row. A file that the
decoder cannot open remains a visible failure, even when its extension is in
the manifest.

### GameCube primary streams

The GameCube primary set is:

```text
.adp .agsc .dsp .h4m .ldat .logg .rsf .thp .txtp
```

These members are admitted only through the bundled vgmstream inspector. The
archive materializer normalizes underscore-prefixed aliases such as
`_.ldat.txth` to `.ldat.txth` inside scratch storage. `.txth`, `.bd`, `.sbb`,
and other bank/control files are dependencies, not duplicate playlist rows.
The RE2 GameCube archive is the regression fixture for this boundary: primary
`.ldat` members must resolve their TXTH aliases and produce real metadata.

### TXTP and HD-bank structures

`.txtp` is authored mixing/subsong structure, so its resolved dependencies are
prepared before `vgmstream-cli` is invoked. The TXTP row is authoritative;
its underlying stream is retained for decoder access but suppressed as a
separate source row when it is only a dependency.

`.hd`, `.hbd`, and `.iecs` use the required bank-structure adapter. Existing
IECS layouts with `.td` control data and `.msf` payloads may still fail when
they do not match vgmstream's standard `hd_bd` expectation. Those failures are
kept visible until an IECS-specific adapter exists; the scanner does not hide
them or flatten the `.hd` index into a false track.

vgmstream playback-only extensions currently present in VGMBoy but not
admitted by ScanSong are `.adpcm`, `.bk2`, `.ogg`, `.ps3`, `.s14`, `.swav`, and
`.xvag`. They need a scanner route and fixture before they should become
catalog sources.

## Standard audio and modules

### Core Audio

`.aif`, `.aiff`, `.flac`, `.m4a`, `.mp3`, `.ogg`, and `.wav` are one-track
standard audio. ScanSong prefers `AVAudioFile`'s exact decoded frame count and
sample rate for duration, then falls back to `AVURLAsset`. Common tags are
mapped to the catalog; FLAC Vorbis comments are read directly for album,
title, artist, album artist, composer, and comment. No game-music timing model
is invented for ordinary audio.

### OpenMPT modules

The registered tracker extensions use one structurally-known row and optional
metadata. ScanSong does not render or convert a module during intake; an empty
metadata object means the module was admitted as a known single source, not
that a title was fabricated. Playback compatibility and module-specific
duration remain the libopenmpt/VGMBoy boundary.

### Amiga modules through UADE

Amiga music is a special route because many historical files identify the
EaglePlayer from a leading filename token rather than a conventional suffix.
ScanSong admits known UADE prefixes such as `mod.*`, `p4x.*`, `med.*`,
`mdat.*`, `smpl.*`, TFMX, and custom-player names through the shared
`AmigaFormatManifest`; an ordinary `music.mod` remains an OpenMPT module.
Loose files and members inside `.lha` archives use the same path-aware route.

The scanner extracts `.lha` with the existing bounded 7zz archive boundary,
then materializes the complete extracted Amiga set before invoking the
VGMBoy-built `vgmboy-amiga-inspect` adapter. This is required because an
Amiga set may contain a module, player companion, or sample bank in the same
archive. Companion data is available to UADE but is not published as a second
track source. UADE reports the actual subsong range, so ScanSong publishes one
row per declared subsong with the same zero-based contiguous track indexes used
by VGMBoy playback. The original module and companion bytes are preserved;
ScanSong does not convert them to WAV or flatten them into a new container.

The current shareable runtime is Homebrew UADE 3.05. UADE is GPL-2.0-only (not
GPL-2.0-or-later), so distribution must keep its license obligations and the
runtime data directory in view. A valid UADE open establishes format support;
native duration may remain zero for EaglePlayers that do not expose a finite
length, in which case VGMBoy's normal natural-end or bounded playback policy
applies. Decode/open failures remain visible `archive-error` records and are
never replaced with a fabricated one-track success.

### APE policy route

`.ape` is retained as a known single optional-metadata route for compatibility
with the scanner policy. ScanSong does not transcode or expand it and may
publish an empty-metadata row. It must not be described as a newly verified
playback path until an explicit scanner/playback fixture exists.

## SID

`.sid` uses the direct PSID/RSID header reader and publishes one row. The
reader maps title, author, released information, load/init/play addresses, and
the song count where the catalog model can represent them. SID has no reliable
universal finite end, so missing timing remains missing; the player applies its
bounded playback policy rather than ScanSong inventing a length.

## Deliberately not admitted

The following are visible file-type policy entries, not failed attempts at
scanner support:

- `.sgc` and `.m3u` for the current SGC/playlist boundary;
- `.ncsf`, `.minincsf`, and `.ncsflib` for the unimplemented NCSF dependency
  family;
- `.mus` for Doom MUS, which the current vgmstream path does not open.

Changing the ignore policy does not create a decoder. If a format has a route,
it is inspected and malformed data produces a failure. If it has no route,
archive members use compact `unrecognized` diagnostics unless they are known
support files. Sidecars and dependency files are silent support data, never
fake playable records.

## Archive and progress guarantees shared by every route

- A loose file or physical archive is one source-level progress item. Archive
  members update detail/current path but never advance the source denominator.
- Archive extraction is bounded and disposable. TAR.ZST streams `zstd -dc`
  into `tar`; it does not create a second full temporary TAR.
- Required external inspectors run through one bounded process runner with
  cancellation, concurrent stdout/stderr draining, a 30-second deadline, and
  output limits.
- ScanSong's native UI samples the latest aggregate progress; worker callbacks
  cannot pace the scan. CLI JSONL is rate-limited independently.
- A failed member is retained for diagnosis and retry while valid siblings are
  published. A completed source summary counts physical sources; the result
  log separately reports member failures.
- Diagnostic paths are relative to the supplied scanner root. Archive errors
  use `archive#member`, and redundant member names or disposable scratch paths
  are removed from the detail column.

## Maintenance rule

When a plugin or route changes, update this document and the corresponding
route/fixture tests in the same change. A new extension is not complete until
its structure policy, metadata source, dependency behavior, archive behavior,
and failure boundary are stated here and exercised by at least one fixture or
an explicit skipped test hook.
