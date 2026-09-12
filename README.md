# ScanSong

ScanSong is the native Swift catalog writer for CocoaSpice, SPCBoy,
and future app-family frontends. The players browse a selected schema-23 SQLite
catalog through read-only connections; they do not scan into or modify it.

The repository contains:

- `ScanSongKit`, the host-independent scanner, archive, metadata, staging,
  resume, and schema-23 publication implementation.
- `scansong`, a versioned JSONL command-line boundary for Electron and tests.
- `ScanSong`, a small native macOS GUI for managing one catalog file,
  adding roots, scanning, cancelling, resuming, and reading per-path logs.

## Use the native app

```bash
./launch.sh
```

`launch.sh` always removes the prior SwiftPM build and assembled app, performs a
clean release build, ad-hoc signs the new bundle, asks any existing ScanSong
process to close cooperatively, and opens that exact bundle as a new instance
only after the prior process exits. Use
`build-app.sh` alone when a clean build without launch is required.

ScanSong is also registered in `/Users/john/Downloads/Code/LaunchPad/apps.txt`.
Its LaunchPad row runs the same clean `build-app.sh` contract before opening the
new bundle.

Choose an existing schema-23 catalog, use **Use Default**, or choose **Add New**
to create a fresh `Library.sqlite` at a new path. Only one catalog is selected
at a time; Add New never replaces an existing database. Existing attached paths
load from the catalog automatically. **Add Path** adds complete folder roots;
each path can be enabled for **Scan All** or scanned directly.
Every path has Scan, Show Last Scan Log, and Remove controls. **Deep Scan**
forces reinspection of every source and all currently available metadata
adapters; ordinary Scan is the fast path and reuses matching completed sources.
Cancelling retains complete source/archive checkpoints, and the next matching
scan resumes after rediscovery validates them.

**Check Links** verifies every indexed physical source. Missing or moved paths
are marked inactive, so neither player shows them, while their tracks,
metadata, fingerprints, archive identities, and scan inventory remain in the
catalog. If a source returns at the same path, the next check restores it.
**Clean Links** is the explicit destructive operation that permanently purges
only inactive catalog records after confirmation; it never deletes media files.
Removing a scan path only detaches it and retains its records.

Each path shows its last scan time, source count, active track count, and issue
count. Its last-result log uses uniform `status | detail | path` rows. It records
the root summary, actual failure records, and compact ignored/unrecognized diagnostics;
successful archive members are never expanded into a file list, while an
archive-member failure keeps its `archive#member` path. Scanner-owned scratch
prefixes are removed from diagnostic details so the archive member path remains
the useful identifier. Path status is grey before a completed scan, green when
all supported sources completed cleanly, yellow when
failed or inactive sources need attention, and red when a completed scan has no
playable files.

ScanSong publishes a root atomically. A failed refresh retains the last
known-good rows for that source and reports the new failure. Player reads and
playback may continue while ScanSong scans: the app holds an advisory
writer lease only to prevent a second scanner from modifying the same catalog.
No player-state lock is shown. If SQLite reports the catalog busy after its
wait, the scanner leaves the catalog consistent and asks you to retry. Required structural parsers fail
explicitly when their native adapter is unavailable; the scanner does not
invent a single track or invoke a player-owned fallback.

## Command line

```bash
swift run scansong plugins
swift run scansong probe --recursive --strict /path/to/folder
swift run scansong catalog create /path/to/Library.sqlite
swift run scansong catalog validate /path/to/Library.sqlite
swift run scansong catalog roots /path/to/Library.sqlite
swift run scansong scan /path/to/Library.sqlite /path/to/root
swift run scansong scan --new /path/to/Library.sqlite /path/to/root
swift run scansong scan --permits 16 /path/to/Library.sqlite /path/to/root
swift run scansong scan --archive-limit 8 /path/to/Library.sqlite /path/to/root
```

`probe` is always dry-run. `scan` writes only the selected catalog. Standard
output is reserved for ordered, versioned JSONL events; errors and unsupported
required adapters produce a nonzero exit status. SIGINT and SIGTERM cancel
cooperatively after completed checkpoints have been saved.

ScanSong preserves the catalog's existing durable SQLite journal mode. New
catalogs start in SQLite's default rollback-journal (`DELETE`) mode; existing
WAL catalogs stay in WAL mode so player reads and scanner writes can coexist.
Do not copy a live WAL catalog without its `-wal` and `-shm` companion files.
ScanSong never switches journal mode during a scan or link-maintenance
operation, so an open player does not turn that operation into a catalog-busy
error.

## Implemented intake

- ZIP, 7z, RAR/RSN, TAR.ZST, and TZST archives with bounded complete
  materialization, path/symlink validation, cancellation, and cleanup.
- LHA archives through the same bounded 7zz materialization boundary. Amiga
  members are recognized by the shared UADE prefix manifest as well as by
  ordinary suffixes, and each archive is staged as a complete set so UADE can
  resolve player/sample companions before it publishes real subsong rows.
- Direct NSF/GBS/NSFE header and chunk enumeration, AY relative-pointer
  header/subsong/title/comment/timing extraction, SAP header/subsong/native TIME,
  and HES header/M3U inspection without opening libgme; KSS keeps its 256-slot
  info-only fallback. The SPC route reads ID666/xID6 directly, including the
  libgme-compatible default for valid tagless SPCs; ScanSong's app and CLI no
  longer link or invoke libgme for SPC inspection.
- Direct PSF-style footer tags (including QSF/GSF length and fade tags),
  VGM/VGZ GD3/timing, and Commodore 64 SID PSID/RSID header reads.
- Direct SNDH tag/subtune/timing harvesting through VGMBoy's shared `VGMBoySNDH`
  product. SNDH files are enumerated into their actual Atari ST subtunes; the
  scanner does not start playback just to publish metadata.
- SNDH rows use contiguous zero-based `track_index` values and repeat the
  declared `track_count` on every subtune row, so database/game/file playlist
  activation can select each subtune without reopening the scanner. VGMBoy's
  deterministic 1,024-file corpus sample rendered 2,030 subtunes with zero
  failures, including 4-Mat's eight-subtune Shadow Dancer; this remains decoder
  evidence, not a claim that every file in the 5,897-file Atari ST corpus is
  conventional music or supported.
- MDX modules through the VGMBoy-built `vgmboy-mdx-inspect` adapter. Each MDX
  publishes one logical track with its native duration and title; declared
  sample/data companions are dependency data and are not published as
  standalone rows. The X68000 library commonly stores these as separate
  `name.MDX.zst` and `name.PDX.zst` files. For a compressed MDX, ScanSong reads
  the MDX header, resolves its declared dependency beside the source
  case-insensitively, decompresses it when necessary, and places it beside the
  MDX in disposable scratch before invoking the VGMBoy inspector.
  Extensionless references retain the historical `.pdx` inference, but an
  explicit extension is never rewritten: `NOS.SMP`, `THRICE.PCM`, and
  `KONAMI.MDX` remain those exact logical names. The shared mdxmini boundary
  also decodes inner X68000 LZX 0.32/0.42 MDX bodies and whole-file LZX PDX
  banks; the original `.zst`, MDX, and dependency source bytes are never
  rewritten. Dependency wrappers are therefore not independent scan items;
  an absent declared dependency remains an explicit MDX failure. Some X68000
  libraries keep dependencies in a separate subfolder rather than beside each
  module; names are read using the format's legacy Shift-JIS encoding, and the
  legacy leading `\bos` spelling is normalized to a same-directory basename
  while absolute and traversal spellings remain unsafe. When a scan root is
  supplied, ScanSong builds one root-scoped dependency index for PDX, SMP, PCM,
  and MDX sidecars and resolves the closest matching name deterministically
  (local sibling first, then nearest shared folder, then stable path order). It
  never searches outside the supplied scan root or invents a dependency from
  another scan. Before invoking mdxmini, the inspector verifies that the
  declared dependency was materialized and reports
  `Required MDX dependency is missing: name.` when it was not; missing-
  dependency failures are therefore distinguishable from decoder rejection.
  Failure rows are emitted per declaring module, so repeated missing-name rows
  may refer to one shared dependency rather than distinct missing banks.
- Amiga modules through VGMBoy's `vgmboy-amiga-inspect` UADE adapter. Amiga
  names such as `mod.*`, `p4x.*`, `med.*`, `mdat.*`, `smpl.*`, and custom
  EaglePlayer prefixes are routed by content-name convention while ordinary
  `music.mod` remains OpenMPT. UADE's declared subsong range becomes the
  playlist rows; same-archive player/sample companions remain dependency data,
  not duplicate sources. The source bytes are retained and never converted.
- Monkey's Audio (`.ape`) through ScanSong's direct APE header/tag reader. It
  derives one-track duration from sample blocks and rate, reads native APEv2
  tags, and checks the bounded frame/seek structure without starting FFmpeg or
  audio emulation. The source bytes are retained; VGMBoy still uses FFmpeg for
  playback.
- Structurally known single rows for standard audio (including OGG Vorbis),
  modules, and registered formats whose optional metadata can remain empty.
- Tracker/module rows (S3M, MOD, IT, XM, MTM, STM, and related) via
  `openmpt123` inspection, one structurally-known row per module.
- A VGMBoy-built vgmstream plugin that ScanSong bundles as `vgmstream-cli`
  from the VGMBoy-managed source snapshot and compatibility patch to open raw vgmstream formats and enumerate
  real subsongs before publishing rows. TXTP and HD-bank structures are
  materialized and inspected through the same route.
- A ScanSong-owned GSF/miniGSF reader that validates PSF v0x22 headers, CRCs,
  zlib payloads, GBA executable segments and ROM-header signatures, and the
  complete `_lib` dependency chain while extracting authored tags and legacy
  timing semantics. It does not launch or link mGBA; VGMBoy retains Highly
  Complete/mGBA for playback. The shared scanner-plugin script still invokes
  VGMBoy's broad dependency builder, so mGBA is prepared as build-time
  collateral even though it is not a scanner runtime dependency.
- A ScanSong-owned QSF/miniQSF reader that validates PSF v0x41 containers, CRCs,
  bounded zlib data, QSound blocks, and referenced `.qsflib` files without
  starting the playback core. It extracts authored tags and timing directly;
  VGMBoy retains the QSound core for playback.

The complete per-plugin contract—including route policy, native metadata
source, dependency and archive handling, multi-track expansion, playback
boundaries, and retained failure behavior—is maintained in
[`ai/subsystem-agent/format-accommodations.md`](/Users/john/Downloads/Code/VGMMan/ScanSong/ai/subsystem-agent/format-accommodations.md).

Decoder provenance and milestone versions are maintained centrally by VGMBoy
in [`Docs/plugin-versions.json`](/Users/john/Downloads/Code/VGMMan/VGMBoy/Docs/plugin-versions.json).
ScanSong consumes the staged scanner products and does not maintain a second
decoder-version list. Run VGMBoy's read-only audit before a release or after
the documented review interval; adopting a newer decoder still requires
rebuilding the scanner product and running its format-specific fixtures.
The human-readable plugin matrix and dependency notes are in
[`VGMBoy/Docs/plugin-catalog.md`](/Users/john/Downloads/Code/VGMMan/VGMBoy/Docs/plugin-catalog.md).

Standalone Zstandard inputs use the explicit `name.ext.zst` or
`name.ext.zstd` convention: `ext` is the required inner playable format name,
and the scan produces one implicit member. A bare `file.zst` with no inferable
playable suffix is rejected. `*.tar.zst` and `*.tar.zstd` are always treated as
multi-member TAR containers. MDX is the intentional exception to the
single-payload rule: a `name.MDX.zst` may require a separately compressed
`name.PDX.zst` sibling, which is materialized only as MDX dependency data.

ScanSong does not yet embed every playback codec. Each intake plugin owns
its structural and metadata boundary and returns only tracks it actually opens.
Formats without an implementable scanner adapter are documented in
`ai/project-info.md` and are visible under Options > File Types. They are
ignored by default; supported formats are still inspected so corruption remains
an explicit archive-member failure rather than a hidden source.

Formats without a scanner adapter (for example SNSF and the WonderSwan/Game
Gear oddball families) are not indexed; those sources report
`No supported playable tracks were found` until an adapter or decoder core is
added. SNSF is a PSF-family format whose decoding requires an SPC700 player
core.

## Verify

```bash
swift test --disable-sandbox
swift build --disable-sandbox --configuration release --product scansong
swift build --disable-sandbox --configuration release --product ScanSong
```
