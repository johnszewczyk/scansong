# MediaScanner

Shared Swift scanner infrastructure for CocoaSpice, SPCBoy, and future media-player hosts.

Current package products:

- `MediaScannerKit`: versioned scanner types, host-neutral metadata and result records, format-routing policy, recursive discovery, incremental planning, shared lifecycle/telemetry, archive/decoder plugin protocols, cancellation-aware resource scheduling, and dry-run probing.
- `media-scan`: JSONL command-line process boundary used by non-Swift hosts.

## Commands

```bash
swift run media-scan plugins
swift run media-scan probe /path/to/file
swift run media-scan probe --recursive --strict /path/to/folder
```

`probe` never writes a database. Standard output is reserved for versioned JSONL events.

The package is the scanner implementation boundary. Player hosts adapt its typed results into their own databases; scanner plugins do not know about CocoaSpice, Electron, playlists, or UI state. The executable is not yet the production SPCBoy catalog path because archive materialization and decoder plugin packaging must move behind this boundary before cutover.

## Build and test

```bash
swift test --disable-sandbox
swift build --disable-sandbox --configuration release --product media-scan
```
