# ScanSong

ScanSong is the native Swift catalog writer for CocoaSpice, SPCBoy,
and future app-family frontends. The players browse a selected schema-23 SQLite
catalog through read-only connections; they do not scan into or modify it.

The repository contains:

- `MediaScannerKit`, the host-independent scanner, archive, metadata, staging,
  resume, and schema-23 publication implementation.
- `media-scan`, a versioned JSONL command-line boundary for Electron and tests.
- `ScanSong`, a small native macOS GUI for managing one catalog file,
  adding roots, scanning, cancelling, resuming, and reading per-path logs.

## Use the native app

```bash
./launch.sh
```

`launch.sh` always removes the prior SwiftPM build and assembled app, performs a
clean release build, ad-hoc signs the new bundle, stops any existing
ScanSong process, and opens that exact bundle as a new instance. Use
`build-app.sh` alone when a clean build without launch is required.

ScanSong is also registered in `/Users/john/Downloads/Code/LaunchPad/apps.txt`.
Its LaunchPad row runs the same clean `build-app.sh` contract before opening the
new bundle.

Choose an existing schema-23 catalog or create a new `Library.sqlite`. Existing
attached paths load from the catalog automatically. **Add Path** adds complete
folder roots; each path can be enabled for **Scan All** or scanned directly.
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
count. Its last-result log uses `status: result: file` rows, with the variable
file path last. Path status is grey before a
completed scan, green when all supported sources completed cleanly, yellow when
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
swift run media-scan plugins
swift run media-scan probe --recursive --strict /path/to/folder
swift run media-scan catalog create /path/to/Library.sqlite
swift run media-scan catalog validate /path/to/Library.sqlite
swift run media-scan catalog roots /path/to/Library.sqlite
swift run media-scan scan /path/to/Library.sqlite /path/to/root
swift run media-scan scan --new /path/to/Library.sqlite /path/to/root
swift run media-scan scan --permits 16 /path/to/Library.sqlite /path/to/root
swift run media-scan scan --archive-limit 8 /path/to/Library.sqlite /path/to/root
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
- Native libgme enumeration and metadata for NSF, NSFE, GBS, AY, HES, KSS, SAP,
  SPC, and related registered formats.
- Direct bounded SPC ID666/xID6, PSF footer-tag, plain VGM GD3/timing, and
  Commodore 64 SID PSID/RSID header reads.
- Structurally known single rows for standard audio (including OGG Vorbis),
  modules, and registered formats whose optional metadata can remain empty.
- Tracker/module rows (S3M, MOD, IT, XM, MTM, STM, and related) via
  `openmpt123` inspection, one structurally-known row per module.
- A VGMBoy-built vgmstream plugin that ScanSong bundles as `vgmstream-cli`
  (pinned to the r2117 release) to open raw vgmstream formats and enumerate
  real subsongs before publishing rows.
- A VGMBoy-built Highly Complete plugin that ScanSong bundles to open GSF and
  miniGSF through the inspection adapter. A miniGSF is accepted only when its required
  `.gsflib` dependency is present in the extracted source archive; every
  validated file becomes its real single playable row with its authored tags.

ScanSong does not yet embed every playback codec. Each intake plugin owns
its structural and metadata boundary and returns only tracks it actually opens.
Dependency-based vgmstream formats such as HD banks and TXTP, plus formats
without a registered scanner plugin, remain explicit diagnostics rather than
incomplete or invented catalog rows. Playback remains player-owned.

Formats without a scanner adapter (for example SNSF and the WonderSwan/Game
Gear oddball families) are not indexed; those sources report
`No supported playable tracks were found` until an adapter or decoder core is
added. SNSF is a PSF-family format whose decoding requires an SPC700 player
core.

## Verify

```bash
swift test --disable-sandbox
swift build --disable-sandbox --configuration release --product media-scan
swift build --disable-sandbox --configuration release --product ScanSong
```
