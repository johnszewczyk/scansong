# MediaScanner

MediaScanner is the single native Swift catalog writer for CocoaSpice, SPCBoy,
and future app-family frontends. The players browse a selected schema-23 SQLite
catalog through read-only connections; they do not scan into or modify it.

The repository contains:

- `MediaScannerKit`, the host-independent scanner, archive, metadata, staging,
  resume, and schema-23 publication implementation.
- `media-scan`, a versioned JSONL command-line boundary for Electron and tests.
- `MediaScanner`, a small native macOS GUI for choosing/creating a catalog,
  adding roots, scanning, cancelling, resuming, and reading diagnostics.

## Use the native app

```bash
./build-app.sh
./launch.sh
```

Choose an existing schema-23 catalog or create a new `Library.sqlite`, add scan
folders, choose the console-tag source, and press **Scan**. **Rebuild** forces
reinspection; ordinary Scan reuses matching completed sources. Cancelling
retains complete source/archive checkpoints, and the next matching scan resumes
after rediscovery validates them. **Add Files** intentionally adds each file's
containing folder as a complete scan root.

MediaScanner publishes a root atomically. A failed refresh retains the last
known-good rows for that source and reports the new failure. Required structural
parsers fail explicitly when their native adapter is unavailable; the scanner
does not invent a single track or invoke a player-owned fallback.

## Command line

```bash
swift run media-scan plugins
swift run media-scan probe --recursive --strict /path/to/folder
swift run media-scan catalog create /path/to/Library.sqlite
swift run media-scan catalog validate /path/to/Library.sqlite
swift run media-scan catalog roots /path/to/Library.sqlite
swift run media-scan scan /path/to/Library.sqlite /path/to/root
swift run media-scan scan --new --console-source=metadata /path/to/Library.sqlite /path/to/root
```

`probe` is always dry-run. `scan` writes only the selected catalog. Standard
output is reserved for ordered, versioned JSONL events; errors and unsupported
required adapters produce a nonzero exit status. SIGINT and SIGTERM cancel
cooperatively after completed checkpoints have been saved.

The writer intentionally uses SQLite rollback-journal (`DELETE`) mode so the
catalog remains a self-contained file that CocoaSpice and SPCBoy can open with
OS-level read-only handles. Close player processes before a scan if an older
catalog is still held in WAL mode.

## Implemented intake

- ZIP, 7z, RAR/RSN, TAR.ZST, and TZST archives with bounded complete
  materialization, path/symlink validation, cancellation, and cleanup.
- Native libgme enumeration and metadata for NSF, NSFE, GBS, AY, HES, KSS, SAP,
  SPC, and related registered formats.
- Direct bounded SPC ID666/xID6, PSF footer-tag, and plain VGM GD3/timing reads.
- Structurally known single rows for standard audio, modules, and registered
  VGM-family formats whose optional metadata can remain empty.

Dependency-enumerated GSF/vgmstream families still require shared native
adapters. Until those adapters are present, affected sources are diagnostics,
not incomplete catalog rows.

## Verify

```bash
swift test --disable-sandbox
swift build --disable-sandbox --configuration release --product media-scan
swift build --disable-sandbox --configuration release --product MediaScanner
```
