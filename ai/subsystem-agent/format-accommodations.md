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

## Dependency-free format data

The fixed-byte metadata readers for AY relative-pointer tables, SPC ID666/xID6,
NSF/GBS/NSFE/SAP headers, HES headers and companion M3U playlists, PSF tags,
VGM/VGZ headers, and SID PSID/RSID headers live in the Foundation-only
`VGMBoyFormatDataCore` product. ScanSong supplies file bytes and bounded VGZ
decompression, then maps the returned facts into `ScannerMetadata`. This
shared product has no playback decoder dependency and is used only where it
provides the complete scanner metadata contract. Decoder-backed enumeration,
timing, dependency validation, and rendering remain on their existing routes.

## CocoaSpice playback metadata interface

Only formats admitted by VGMBoy's
[`FormatRegistry.playbackDescriptors`](/Users/john/Downloads/Code/VGMMan/VGMBoy/Sources/VGMBoyKit/FormatRegistry.swift)
are in scope for decoder-replacement work. This is the CocoaSpice playback
boundary; ScanSong may continue to recognize scanner-only formats, but they
are not extraction targets. The exact route and metadata source for each
scanner intake is detailed in the route summary below.

| CocoaSpice playback family | Playable extensions or names | ScanSong metadata methodology and current boundary |
| --- | --- | --- |
| `libgme` | `.ay`, `.gbs`, `.hes`, `.kss`, `.nsf`, `.nsfe`, `.sap`, `.spc` | Direct format readers handle all eight: native header/chunk/playlist facts are used without starting libgme. |
| `libvgm` | `.vgm`, `.vgz`, `.gym`, `.s98`, `.dro` | `.vgm`/`.vgz` use direct GD3/timing readers and `.s98` uses ScanSong's direct header/event/tag reader. `.gym` remains one structure-known row without metadata; `.dro` has no ScanSong route. |
| `psgplay` | `.sndh` | Shared SNDH header and timing reader; no PSGPlay inspection process. |
| `mdx` | `.mdx` | VGMBoy-built `vgmboy-mdx-inspect` still supplies decoder-derived enumeration and metadata; dependencies are materialized but not published as tracks. |
| `standard-audio` | `.aac`, `.aif`, `.aiff`, `.caf`, `.flac`, `.m4a`, `.mp3`, `.wav`, `.wave` | Core Audio supplies duration/common tags, with FLAC Vorbis comments. `.ogg` is routed through this scanner handler too. `.aac`, `.caf`, and `.wave` do not currently have ScanSong routes. |
| `ffmpeg-audio` | `.ape`, `.mp2`, `.tak` | `.ape` uses ScanSong's direct header/tag reader. `.mp2` and `.tak` do not currently have ScanSong routes. |
| `highly-complete` | `.gsf`, `.minigsf` | ScanSong-owned PSF v0x22/container reader validates payloads and dependency chains without mGBA. |
| `twosf` | `.2sf`, `.mini2sf` | Direct PSF footer-tag reader; it does not start the playback core. |
| `vgmstream` | `.aa3`, `.adp`, `.adx`, `.adpcm`, `.ads`, `.agsc`, `.ahx`, `.aifc`, `.at3`, `.aus`, `.bk2`, `.bik`, `.bika`, `.bnk`, `.dsp`, `.dvi`, `.fsb`, `.genh`, `.h4m`, `.hbd`, `.hd`, `.iecs`, `.int`, `.ldat`, `.logg`, `.mib`, `.msf`, `.mtaf`, `.ogg`, `.ps3`, `.rsf`, `.rws`, `.s14`, `.ss2`, `.stream`, `.strm`, `.svag`, `.swav`, `.thp`, `.txtp`, `.vag`, `.xa`, `.xmd`, `.xvag` | `.adx`, `.at3`, `.aus`, `.msf`, `.svag`, and `.xa` use content-aware direct readers for recognized signatures; nonmatching aliases retain vgmstream. `.txtp` and HD-bank inputs use vgmstream with dependency preparation. Other routed streams use `vgmstream-cli -I`. `.ogg` currently uses the Core Audio scanner route. |
| `lazyusf` | `.usf`, `.miniusf` | Direct PSF footer-tag reader; `.usflib` remains dependency data, not a track. |
| `playpsf` | `.psf`, `.minipsf`, `.psf2`, `.minipsf2` | Direct PSF footer-tag reader; libraries remain dependency data. |
| `qsf` | `.qsf`, `.miniqsf` | ScanSong-owned PSF v0x41/QSound container reader validates payload blocks, tags, and dependencies without the QSound core. |
| `sidplayfp` | `.sid` | Direct PSID/RSID header reader; no duration is invented when the source has none. |
| `openmpt` | `.669`, `.dmf`, `.far`, `.it`, `.mod`, `.mptm`, `.mtm`, `.okt`, `.ptm`, `.s3m`, `.stm`, `.ult`, `.xm` | ScanSong admits one known-structure row, but metadata remains optional/deferred; no playback decoder inspection runs. |
| `amiga-uade` | UADE replayer prefixes such as `mod.*`, `p4x.*`, `med.*`, and TFMX | VGMBoy-built `vgmboy-amiga-inspect` still supplies subsong enumeration and metadata; complete-set dependencies are materialized first. |

`metadataPolicy: .direct` means the route does not need a playback-decoder
process; it does not promise facts the source format never stores. `.decoder`
marks routes whose scanner result still depends on a decoder/inspector, while
`.optionalDeferred` admits structure without a complete metadata method. The
`.ssf`/`.minissf` ScanSong route is intentionally absent from this table because
it is not admitted by CocoaSpice's playback registry.

## Route summary

| ScanSong route | Registered extensions | Structure published | Metadata source | Dependency or archive rule |
| --- | --- | --- | --- | --- |
| `spc-direct` | `.spc` | One track | `VGMBoyFormatDataCore` SPC ID666/xID6 reader | All valid files are handled directly, including tagless info-only defaults; no libgme runtime link. |
| `game-music-direct` | `.gbs`, `.nsf` | One row per header-declared track | `VGMBoyFormatDataCore` NSF/GBS header reader | No emulator is started; the formats do not store authored per-track names or timing. |
| `nsfe-direct` | `.nsfe` | One row per NSFE playlist entry | `VGMBoyFormatDataCore` NSFE chunk reader | No emulator is started; source labels/times are mapped through the optional playlist, including duplicates. |
| `kss-direct` | `.kss` | 256 compatibility slots | ScanSong KSS header reader | Header-only; this preserves libgme's info-only fallback, not an authored song count. KSS M3U files are not consumed. |
| `ay-direct` | `.ay` | One row per AY header-declared subtune | `VGMBoyFormatDataCore` ZXAYEMUL reader | No decoder; signed relative pointers expose titles, author/comment, and native 50 Hz track lengths. |
| `sap-direct` | `.sap` | One row per `SONGS` header entry (default one) | `VGMBoyFormatDataCore` SAP header reader | No emulator; native `TIME` facts map finite durations or loop-start intro times. |
| `hes-direct` | `.hes` | One row per sibling-M3U entry, or 256 compatibility slots without one | `VGMBoyFormatDataCore` HES header and M3U reader | No emulator; M3U is support data and supplies the authored track map and timings. |
| `openmpt` | `.669`, `.dmf`, `.far`, `.it`, `.mod`, `.mptm`, `.mtm`, `.okt`, `.ptm`, `.s3m`, `.stm`, `.ult`, `.xm` | One structurally-known row | Optional/deferred; metadata may be empty | No scanner-side module conversion or archive expansion. |
| `standard-audio` | `.aif`, `.aiff`, `.flac`, `.m4a`, `.mp3`, `.ogg`, `.wav` | One track | Core Audio duration and common tags; FLAC Vorbis comments | Exact decoded duration is preferred. |
| `ape-direct` | `.ape` | One validated single row | ScanSong APE header and tag reader | Header-derived duration plus APEv2 and leading ID3 common tags; no decoder startup. |
| `adx-direct` | CRI ADX in `.adx` | One track | ScanSong CRI ADX header reader | Preserves native sample/loop bounds and vgmstream's default two-loop/10-second-fade play window; non-CRI/Monster signatures (including Ogg and RIFF aliases) use vgmstream. |
| `aus-direct` | Atomic Planet AUS in `.aus` | One track | ScanSong Atomic Planet AUS header reader | Preserves native sample rate/count, loop markers, and vgmstream's default play window without starting PS-ADPCM or Xbox IMA decoding; other `.aus` payloads use vgmstream. |
| `sony-msf-direct` | Sony MSF in `.msf` | One track | ScanSong Sony MSF header and frame reader | Reads supported codec timing, native stream name, and loop bounds without audio decoding; TamaSoft `MSF ` and other non-Sony aliases use vgmstream. |
| `svag-direct` | Konami/SNK SVAG in `.svag` | One track | ScanSong Konami/SNK SVAG header reader | Derives PS-ADPCM sample and loop timing without decoding; unknown `.svag` signatures use vgmstream. |
| `xa-direct` | Sony CD-XA in `.xa` | One row per XA file/channel subsong | ScanSong XA sector reader | Preserves interleaved channel enumeration and sector-derived timing; RIFF/CDXA wrappers are accepted. Other `.xa` formats use vgmstream. |
| `vgm-direct` | `.vgm`, `.vgz` | One stream row | `VGMBoyFormatDataCore` VGM/VGZ GD3 and timing | VGZ is bounded gzip decompression, not a generic archive; no decoder is started. |
| `s98-direct` | `.s98` | One stream row | ScanSong S98 v0-v3 header, event-timing, and tag reader | No playback core is started; exact metadata/timing parity is checked against libvgm as a test-only oracle. |
| `libvgm` | `.gym` | One stream row | Structure-known; metadata remains absent | No scanner-side metadata is invented; `.gym` remains decoder-owned. |
| `psgplay` | `.sndh` | One row per declared subtune | Shared `VGMBoySNDH` header/timing reader | Never starts PSGPlay during metadata inspection. |
| `mdx` | `.mdx` | One logical sequence row | VGMBoy-built `vgmboy-mdx-inspect` | A declared PDX bank is prepared but never published as a track. |
| `amiga-uade` | UADE replayer prefixes (`mod.*`, `p4x.*`, `med.*`, TFMX, and custom players) | One row per UADE subsong | VGMBoy-built `vgmboy-amiga-inspect` | `.lha` and loose sets are materialized as complete sets; companions remain dependency data. |
| `gsf-direct` | `.gsf`, `.minigsf` | One validated row | ScanSong PSF v0x22/GSF reader | CRC, zlib payload, GBA segment, and complete miniGSF dependency chain are validated without mGBA. |
| `highly-theoretical` | `.ssf`, `.minissf` | One structurally-known row | `VGMBoyFormatDataCore` PSF footer tags | Scanner tags the PSF container; a native playback route is not implied. |
| `lazyusf` | `.usf`, `.miniusf` | One structurally-known row | `VGMBoyFormatDataCore` PSF footer tags | `.usflib` is playback dependency data, never a row. |
| `twosf` | `.2sf`, `.mini2sf` | One structurally-known row | `VGMBoyFormatDataCore` PSF footer tags | `.2sflib` is dependency data, never a row. |
| `vgmstream` | Remaining raw-stream extensions listed below plus nonmatching `.adx`, `.at3`, `.aus`, `.msf`, `.svag`, and `.xa` aliases | One row per reported subsong | VGMBoy-built `vgmstream-cli` | Native `-I` inspection; subsong count is bounded. Recognized CRI/Monster ADX, RIFF ATRAC3, Atomic Planet AUS, Sony MSF, Konami/SNK SVAG, and Sony XA signatures use ScanSong readers. |
| `vgmstream-txtp` | `.txtp` | One row per resolved subsong | `vgmstream-cli` after dependency preparation | Authored TXTP structure is authoritative. |
| `vgmstream-hd-bank` | `.hd`, `.hbd`, `.iecs` | One row per resolved subsong | `vgmstream-cli` after dependency preparation | Bank/control sidecars are support data; IECS remains a known adapter boundary. |
| `play-psf1` | `.psf`, `.minipsf` | One structurally-known row | `VGMBoyFormatDataCore` PSF footer tags | `.psflib` is playback dependency data, never a row. |
| `play-psf2` | `.psf2`, `.minipsf2` | One structurally-known row | `VGMBoyFormatDataCore` PSF footer tags | `.psflib` is playback dependency data, never a row. |
| `qsf-direct` | `.qsf` | One validated row | ScanSong QSF PSF/data-block reader | CRC, bounded zlib output, QSound block ranges, and any referenced `.qsflib` files are validated without a QSound core. |
| `qsf-mini-direct` | `.miniqsf` | One validated row | ScanSong QSF PSF/data-block reader | Referenced `_lib` through `_lib9` libraries must be available beside the source and pass container/block validation. |
| `sid` | `.sid` | One structurally-known row | `VGMBoyFormatDataCore` PSID/RSID header reader | No finite duration is invented when the header has none. |

The route table is deliberately not a claim that every registered source is
playable in every frontend. VGMBoy's playback registry and the scanner's
registry are separate contracts; the [VGMBoy format registry](/Users/john/Downloads/Code/VGMMan/VGMBoy/Sources/VGMBoyKit/FormatRegistry.swift) is the playback source of truth.

## Game Music Emu family

### SPC: complete direct ID666/xID6 route

`.spc` is registered as `spc-direct` with `knownSingle` structure.
`SPCFormatDataReader` in `VGMBoyFormatDataCore` maps the fixed ID666 header and
optional xID6 extension without a playback dependency. It accepts text and
binary ID666 timing layouts, aggregates segmented xID6 values, bounds all
lengths, and ignores unknown xID6 item types after validating their boundaries.
Every valid SPC produces direct metadata: when neither tag format is present,
the reader returns empty authored fields, `Super Nintendo`, unknown intro/loop
(`-1`), the 150-second info-only play default, and zero fade. These are the
values the old libgme fallback published for tagless SPCs.

The reader also keeps authored xID6 intro, loop, end, and fade facts. These can
be richer than libgme's info-only projection: upstream deliberately leaves the
xID6 intro mapping disabled because those values are often wrong. Direct facts
for the F-Zero fixture archives agree with the existing catalog rows; SPC
playback remains VGMBoy's libgme responsibility. Across the two F-Zero archives
and the tagless Super Mario World beta archive, all 57 members route directly;
the 23 tagless records match libgme's defaults, while the other 34 retain
additional native xID6 timing. In the Release parser-only comparison on these
already-extracted bytes, alternating-order medians were 0.0545 ms direct and
0.219208 ms for libgme-info-only; this fixture result excludes archive
decompression and is not a whole-scan performance guarantee. Malformed SPCs
remain archive-member failures.

### AY: complete relative-pointer metadata route

`.ay` uses `ay-direct` and `AYFormatDataReader` in the Foundation-only
`VGMBoyFormatDataCore`; ScanSong does not open libgme or execute the embedded
Z80 player. The reader validates the `ZXAYEMUL` header and complete track-pointer
table, follows bounded signed big-endian relative pointers, and extracts each
subtune title plus file-level author/comment. It retains the header's version,
player id, and first-track byte as source facts while publishing the same
zero-based `0..<max_track+1` order used by [libgme's AY info reader](https://github.com/libgme/game-music-emu/blob/master/gme/Ay_Emu.cpp).

Per-track duration is stored in 50 Hz frames. The reader maps a positive frame
count to milliseconds (`frames * 20`); absent or zero length retains libgme's
150-second play-length fallback. Intro, loop, and fade remain unknown, matching
the info-only contract. The Project AY corpus comparison covers all 1,175 AY
files: every acceptance decision, subtune count/order, metadata field, and
timing value matches libgme. In the optimized Release corpus run the medians
were 0.049 ms direct and 0.059 ms libgme per file; the direct reader was about
17% faster while preserving the info-only contract.

### SAP: direct header, track, and timing facts

`.sap` uses `sap-direct` and `SAPFormatDataReader` in the Foundation-only
`VGMBoyFormatDataCore`; ScanSong does not open libgme or start the Atari CPU and
POKEY playback core. The reader validates the SAP signature, header lines,
binary-data marker, any present player type (B/C only), optional `SONGS` count,
and bounded numeric fields. `SONGS` defaults to one as it does in libgme's
information-only reader. `NAME` and `AUTHOR` become game and author; the system
is `Atari XL`. SAP `DATE` remains available as a source fact, matching the old
scanner projection that did not map copyright into the catalog comment.

The reader retains one `TIME` hint per corresponding subsong. The [SAP format
specification](https://asap.sourceforge.net/sap-format.html) defines a plain
`TIME` as finite duration and `TIME … LOOP` as the point where looping begins.
ScanSong therefore maps plain time to `play_length_ms`, loop-start time to
`intro_length_ms`, leaves unknown loop length and fade at -1, and keeps the
150-second playback fallback for loop-marked or missing timing. This adds
header-authored timing that the previous libgme info-only route did not expose;
it does not infer loop length or a finite end for an indefinitely looping song.

Corpus parity covers all 6,335 SAP sources under the local ASMA fixture tree:
5,577 are accepted and 758 rejected by both readers. Track counts, ordering,
and all prior scanner metadata fields match; the only intentional differences
are the verified SAP `TIME` enrichments. No SAP rows exist in the inspected
CocoaSpice catalog for live-row comparison.

### HES: complete header and M3U route

`.hes` uses `hes-direct` and `HESFormatDataReader` in the Foundation-only
`VGMBoyFormatDataCore`; it does not open libgme or start the PC Engine emulator.
The reader validates the HES information header and extracts its game/author
tags. A same-basename `.m3u` supplies the authored address-slot mapping,
per-track titles, and intro/loop/play/fade times. The playlist remains support
data, not a catalog track. Without a playlist the route preserves the previous
256-slot compatibility listing and suppresses unverified timing. The adapter is
covered by a real Bloody Wolf fixture comparison against libgme and a
read-only comparison of all HES rows in the CocoaSpice catalog.

### KSS: complete info-only header route

`.kss` is registered independently as `kss-direct`. The reader validates the
16-byte `KSCC`/`KSSX` header and applies libgme's device-flag system mapping;
there is no title, author, comment, or authored timing in this inspection
contract. It emits the same fixed 256 slots and empty/default metadata as
libgme's info-only KSS reader, including the 150-second play-length fallback.
Those slots are a compatibility address space, not evidence that the file
contains 256 real songs. ScanSong does not load KSS M3U playlists today, so the
direct route deliberately preserves that behavior rather than partially
applying playlist-derived structure or metadata. No emulation core is started
for KSS metadata inspection.

### NSFE: complete chunk route

NSFE uses the Foundation-only `NSFEFormatDataReader` in
`VGMBoyFormatDataCore`. The reader validates the mandatory INFO, DATA, and
NEND chunks, then harvests AUTH, TLBL, TAUT, TIME, FADE, PLST, PSFX, TEXT,
RATE, BANK, NSF2, VRC7, and region facts without executing the embedded NSF
payload.
Unknown optional chunks are retained as raw facts; unknown mandatory chunks
fail instead of being silently ignored.

The NSFE `time` and `fade` arrays are in source-track order, while `PLST`
defines the visible order and may omit or duplicate source tracks. ScanSong
publishes one row per visible playlist entry and keeps each row's source facts
in the shared reader. A positive authored TIME becomes the row length; zero or
negative/default TIME retains libgme's documented 150-second play-length
fallback, while the raw signed value remains available to callers. Explicit
FADE values are retained, including zero. This preserves both the old scanner
contract and the authored NSFE timing data.

### NSF and GBS: complete header route

NSF and GBS use `game-music-direct`, a dependency-free reader in
`VGMBoyFormatDataCore`. The headers contain the complete file identity fields,
format facts, and track count, so ScanSong enumerates one row for every
header-declared track without opening libgme. The reader also preserves the
format-specific addresses, playback flags/timer fields, banking, and version
for future catalog projections.

Neither format stores authored per-track names or finite timing. The direct
scanner therefore publishes the header game/author/comment and leaves song
empty. It preserves libgme's unknown intro/loop/fade values and its documented
150-second play-length fallback without running timed emulation. Playback
remains a separate libgme concern.

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

## MDX dependencies

`.mdx` is a one-track logical X68000 sequence. ScanSong invokes the
VGMBoy-built `vgmboy-mdx-inspect` executable, so metadata and duration come
from the same mdxmini implementation used by playback. MDX dependency names
are decoded using the legacy Shift-JIS convention, with UTF-8 fallback for
hand-authored files.

PDX is native X68000 sample-bank data, not an archive and not an alternate MDX
encoding. SMP and PCM companions, plus an explicitly referenced MDX sidecar,
are dependency data in this path rather than automatically being new scan
sources. When an MDX declares a dependency, ScanSong looks for a
case-insensitive local sibling first, including compressed `.zst`/`.zstd`
forms, then optionally uses a deterministic root-scoped index for `.pdx`,
`.smp`, `.pcm`, and `.mdx`: nearest shared folder, uncompressed before
compressed, and lexical path order. It never searches outside the supplied
scan root.

The dependency reader infers `.pdx` only when the MDX reference is
extensionless. Explicit alternate references such as `NOS.SMP`, `THRICE.PCM`,
or `KONAMI.MDX` are preserved verbatim (apart from case-insensitive filesystem
matching), so they are not turned into false names such as `NOS.SMP.PDX`.

For `name.MDX.zst`, the decompressed MDX is placed in disposable scratch and
the matching dependency is materialized beside it before the inspector starts.
Standalone compressed PDX, SMP, and PCM companions are suppressed from
discovery. For TAR.ZST, the complete archive is extracted into disposable
scratch, the MDX header is read, and its declared dependency remains data for
that MDX rather than an independent track. A declared but missing dependency
is an explicit MDX failure. The inspector checks the materialized scratch
directory before launching mdxmini and includes the declared name in the
failure (`Required MDX dependency is missing: name.`); it is not a successful
metadata row with an unknown dependency. Failures are recorded per declaring
module, so issue reports must deduplicate dependency names before treating their
counts as a bank inventory; several modules may legitimately share one bank.

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

`gsf-direct` reads the PSF v0x22 container without starting mGBA. It checks the
compressed-payload CRC and zlib stream, validates every GSF executable segment,
and resolves `_lib`, then sequential `_lib2`, `_lib3`, etc. dependencies to the
PSFLib depth limit. It checks the assembled GBA header bytes in PSFLib load
order against mGBA's ROM signature/fallback and BIOS rejection rules; it does
not construct or execute a GBA core. Missing dependencies, unsafe paths,
malformed segments, CRC failures, broken zlib streams, and unrecognized ROM
images remain explicit failures. Outer-file tags win for authored metadata and
`play_length_ms`; dependency tags fill missing values, while legacy
`intro_length_ms` follows the old inspector's final nested `length` callback.
Both time interpretations are parsed directly from tags, including the legacy
C numeric-prefix behavior. Fallback song names use the source filename. Each
valid GSF/miniGSF file contributes one track. VGMBoy continues to use Highly
Complete/mGBA for actual GSF playback. ScanSong no longer bundles or invokes a
Highly Complete inspector, and its GSF runtime route does not link mGBA. The
scanner-plugin build no longer calls VGMBoy's broad playback dependency builder,
so it does not prepare mGBA as scanner build-time collateral.

### QSF / miniQSF

`qsf-direct` and `qsf-mini-direct` parse QSF's PSF v0x41 container in ScanSong.
They verify compressed-payload CRCs and bounded zlib streams, validate each
QSound data block against the legacy ROM bounds, and resolve `_lib` through
`_lib9` sibling dependencies without starting the Z80/QSound playback core.
Root tags provide title, game, artist, comment, length, and fade; length/fade
are converted to milliseconds using the playback bridge's parsing semantics.
The scanner publishes one QSound track per source. VGMBoy retains its QSF core
for playback.

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

`.vgm` and `.vgz` use `vgm-direct`, `.s98` uses `s98-direct`, and `.gym` stays
on the `libvgm` route. These formats publish at most one stream row per
source; they are not treated as multi-track archives.

For VGM and VGZ, the direct reader validates the VGM header and reads GD3 text,
total samples, and loop samples. VGZ decompression is bounded to a fixed
maximum output size, and a declared-but-invalid GD3 block is a malformed-file
failure rather than a partial metadata row. GYM remains admitted through the
libVGM route as a structure-known row without invented metadata.

### S98: complete direct metadata and timing route

`s98-direct` reads S98 versions 0–3 without creating a libvgm player or sound
device. It validates the version-specific header/device table, walks the event
stream for total ticks and loop timing, and reads legacy title text or the v3
`[S98]` tag block. Legacy text uses CP932 conversion with libvgm-compatible
fallback behavior; v3 UTF-8 BOM tags and the scanner's mapped title, game,
system, artist, comment, and date fields are projected into `ScannerMetadata`.

The compatibility target is the metadata exposed by ScanSong's former libvgm
inspection path, including its quirks: the bridge reports loop duration in
both intro and loop fields, maps `YEAR` to date while raw `DATE` is not
reliably exposed, and can fall back to raw bytes for some long CP932 strings.
The direct reader preserves those observable results rather than substituting
different S98 interpretations. A test-only libvgm oracle compares the complete
metadata and row structure against all 5,081 S98 rows in the inspected
CocoaSpice catalog (exact parity). In the optimized corpus test, direct
inspection measured 0.109 ms median / 0.374 ms p95 versus libvgm at 0.142 ms /
0.492 ms; the direct route does not link or invoke the decoder in production.

## vgmstream and direct raw streams, TXTP, and banks

### Sony CD-XA

Recognized raw Sony XA sectors and RIFF/CDXA-wrapped sectors use ScanSong's
in-process sector reader. It mirrors vgmstream's audio-sector test, first
three-audio-sector frame-header validation, 128 per-channel state slots,
interleaved file/channel subsong ordering, end-of-file resets, stream labels,
and sample-rate/form/bit-depth timing calculation. It does not decode ADPCM or
start `vgmstream-cli`. For sparse raw files, vgmstream's 32-bit probe offset
can wrap and revisit data after EOF; the direct reader folds those duplicate
probes while retaining the decoder's initial 32-sector search limit. Other
`.xa` signatures, including Maxis XA, XA30, 04SW, and AIFC aliases, remain on
vgmstream. The decoder also accepts a 100-byte raw prefix when its first XA
header/frame is valid: out-of-range frame reads are zero-filled. The direct
reader deliberately preserves this legacy boundary rather than tightening it.

The read-only live-catalog comparison matched all 867 saved rows against both
the direct reader and vgmstream (827 files across 18 archives), including
multi-subsong indexes. In that run, mean inspection time was 8.961 ms/file for
the direct reader and 70.581 ms/file for the CLI inspector. Sparse one-sector,
two-sector, audio-plus-non-audio, and 100-byte-prefix probes also matched the
legacy inspector; those decoder probes took 1.0–2.3 seconds each due to its
offset wrap. Archive extraction is serialized, with one archive payload at a
time.

### CRI ADX

CRI ADX files route to ScanSong's in-process metadata reader rather than
`vgmstream-cli`. It recognizes type-03, type-04 (including encrypted version
markers), and type-05 headers, plus the distinct Monster Games ADX layout. The
reader preserves the decoder's source label, sample-derived loop length, and
default play timing (two loop iterations followed by a ten-second fade). The
live-catalog test compares all saved ADX fields against both this reader and
`vgmstream-cli`. Only recognized CRI/Monster headers use this reader; other
payloads named `.adx` (including Ogg and RIFF aliases) remain on vgmstream, so
extension alone does not classify content as CRI ADX.

### Atomic Planet AUS

Recognized `AUS ` signatures use ScanSong's in-process header reader. It reads
the native signed sample count, rate, loop points, channel count, and both loop
signals; codec selection (`0x02` Xbox IMA versus PS-ADPCM fallback) is not
needed to derive metadata. No payload decoding or `vgmstream-cli` startup is
required. Valid loops preserve the CLI's two iterations plus ten-second fade;
invalid loop bounds are cleared using vgmstream's preparation rules. Titles
remain the source filename without `.aus`, and the metadata source remains
`Atomic Planet AUS header`. Non-`AUS ` files with the same extension retain
vgmstream fallback routing.

The read-only live-catalog differential matched all 440 rows against both the
saved catalog and vgmstream in the Mega Man Anniversary Collection archive.
Mean metadata inspection time was 0.162 ms/file for the direct reader versus
164.076 ms/file for the vgmstream CLI (including its per-file process startup).

### Sony MSF

Recognized Sony MSF signatures use ScanSong's in-process reader. It parses the
container header and stream name, then derives sample and loop bounds for PCM,
PSX ADPCM, ATRAC3 variants, or MPEG by counting frame headers; it never decodes
audio or starts `vgmstream-cli`. ATRAC encoder delay and vgmstream's invalid-loop
cleanup are preserved. Play length retains the CLI default of two loop
iterations plus a ten-second fade. Content routing leaves TamaSoft's `MSF `
signature and other non-Sony `.msf` aliases on vgmstream.

The read-only live-catalog differential matched all 799 rows against both the
saved catalog and vgmstream across 799 files in four archives. The corpus
covered codecs 0, 4, 5, and 7; focused fixtures also cover codecs 1, 3, and 6,
MPEG CBR/VBR, TamaSoft fallback, and invalid loops. Mean metadata inspection
time was 2.566 ms/file for the direct reader versus 239.738 ms/file for the
vgmstream CLI (including its per-file process startup).

### Konami and SNK SVAG

Known `.svag` variants use ScanSong's header reader: `Svag` selects the Konami
layout with interleaved PS-ADPCM data, sample-byte loop start, and the optional
`Svag`/`Desi` padding marker; `VAGm` selects SNK's block-count loop layout.
Both variants preserve vgmstream's sample-rate/channel/sample limits, invalid
loop cleanup, filename title, format comment, and default two-loop plus
ten-second-fade play projection. No ADPCM data is decoded. Other `.svag`
signatures retain the vgmstream fallback.

The read-only live-catalog differential matched all 284 rows against both the
saved catalog and vgmstream across eight archives; every live row used the
Konami header. Synthetic fixtures also cover the SNK variant, both loop
conventions, invalid loops, and the Konami padding check. Mean metadata
inspection time was 0.128 ms/file for the direct reader versus 185.562 ms/file
for the vgmstream CLI (including its per-file process startup).

### RIFF ATRAC3/ATRAC3+: complete direct metadata route

Recognized `.at3` RIFF/WAVE sources use ScanSong's bounds-checked RIFF reader.
It accepts WAVE ATRAC3 (`0x0270`) and the ATRAC3+ extensible GUID, reads `fact`
sample count/encoder skip and forward `smpl` or `wsmp` loops, and preserves
their different inclusive/exclusive loop-end rules. It reproduces vgmstream's
loop adjustment and default two-loop/ten-second-fade play window. The row title
remains the filename stem, and the comment follows the RIFF WAVE metadata type.
No FFmpeg/ATRAC decoder is initialized; nonmatching `.at3` payloads retain the
vgmstream route.

The read-only live-catalog differential matched all 177 rows in the
Castlevania: The Dracula X Chronicles and Silent Hill: Origins archives against
both the saved catalog and vgmstream, including every metadata field and track
index. Mean direct inspection was 0.405 ms/file versus 1,157.322 ms/file for
`vgmstream-cli -I`; the decoder timing includes per-file process startup.

### Raw stream suffixes

The vgmstream extension set is owned by VGMBoy's
[`VGMStreamFormatManifest.swift`](/Users/john/Downloads/Code/VGMMan/VGMBoy/Sources/VGMBoyFormatCore/VGMStreamFormatManifest.swift):

```text
.aa3 .ads .ahx .aifc .at3 .aus .bik .bika .bnk .dvi .fsb .genh .int
.mib .msf .mtaf .rws .ss2 .stream .strm .svag .vag .xmd
```

Although `.adx`, `.at3`, `.aus`, `.msf`, `.svag`, and `.xa` remain in VGMBoy's
upstream manifest, ScanSong removes them from generic extension-only routing.
Recognized CRI/Monster ADX, RIFF ATRAC3, Atomic Planet AUS, Sony MSF,
Konami/SNK SVAG, and Sony XA signatures use their direct readers; other aliases
retain the vgmstream fallback. For the remaining raw-stream formats, the
scanner invokes the bundled `vgmstream-cli -I`. It reads sample rate,
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

vgmstream's playback-only extension set is `.adpcm`, `.bk2`, `.ogg`, `.ps3`,
`.s14`, `.swav`, and `.xvag`. ScanSong already admits `.ogg` through its
standard-audio route; the other six have no scanner route and need a fixture
before they should become catalog sources.

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

### APE / Monkey's Audio

`.ape` is a native lossless audio container, not an archive and not a
multi-track module. ScanSong's direct reader validates the APE descriptor,
stream parameters, seek-table extent, frame offsets, and payload bounds. It
derives duration from the container's sample-block count and rate, reads APEv2
common tags plus leading ID3v2 common tags, and falls back to the source stem
for an absent title. It never starts FFmpeg or an audio decoder. VGMBoy keeps
its independent `CFFmpeg` bridge for APE playback; ScanSong no longer builds
or bundles an FFmpeg inspection helper. The original APE bytes remain the
catalog source; no transcode is performed.

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
