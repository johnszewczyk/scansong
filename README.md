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
swift run media-scan catalog validate /path/to/Library.sqlite
```

`probe` never writes a database. `catalog validate` opens the selected SQLite file read-only, requires the canonical CocoaSpice schema version and tables, and reports its root and track counts. Standard output is reserved for versioned JSONL events.

The package is the scanner implementation boundary and the canonical catalog owner. The current catalog contract is CocoaSpice schema 23. SPCBoy already consumes that catalog through a query-only adapter; CocoaSpice still has its in-process writer while catalog mutations, archive materialization, and decoder plugin packaging move behind this boundary. Do not claim the sole-writer cutover is complete until CocoaSpice's writer and the dormant SPCBoy JavaScript scanner are removed from production paths.

## Build and test

```bash
swift test --disable-sandbox
swift build --disable-sandbox --configuration release --product media-scan
```
