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
./launch.sh
```

`launch.sh` always removes the prior SwiftPM build and assembled app, performs a
clean release build, ad-hoc signs the new bundle, stops any existing
MediaScanner process, and opens that exact bundle as a new instance. Use
`build-app.sh` alone when a clean build without launch is required.

MediaScanner is also registered in `/Users/john/Downloads/Code/LaunchPad/apps.txt`.
Its LaunchPad row runs the same clean `build-app.sh` contract before opening the
new bundle.

Choose an existing schema-23 catalog or create a new `Library.sqlite`. Existing
attached roots load from the catalog automatically. Check the roots to process,
choose whether folder structure supplies console metadata, and press **Scan**.
**Rebuild** forces reinspection of every source and all metadata adapters that
are currently available; ordinary Scan is the fast path and reuses matching
completed sources. Cancelling
retains complete source/archive checkpoints, and the next matching scan resumes
after rediscovery validates them. **Add Files** intentionally adds each file's
containing folder as a complete scan root.

**Test Files** verifies every indexed physical source. Missing sources are
marked inactive but their tracks, metadata, fingerprints, archive identities,
and scan inventory remain in the database. Both players omit inactive sources.
If a source returns at the same path, the next test restores it immediately;
future unique-fingerprint relocation matching remains planned. **Clear Dead
Links** is the explicit destructive operation that purges inactive records after
confirmation. Removing a checked root only detaches it and retains its records.

Root status is grey before a completed scan, green when all supported sources
completed without recorded errors, and yellow when failed or inactive sources
need attention.

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

MediaScanner does not yet embed every CocoaSpice playback codec. It currently
uses libgme plus bounded direct metadata readers and structural policies.
Dependency-enumerated GSF/vgmstream families still require shared native
adapters. Until those adapters are present, affected sources are diagnostics,
not incomplete catalog rows. Playback codecs remain player-owned until each is
extracted behind a scanner-safe metadata/structure adapter.

## Verify

```bash
swift test --disable-sandbox
swift build --disable-sandbox --configuration release --product media-scan
swift build --disable-sandbox --configuration release --product MediaScanner
```
