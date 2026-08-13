# MediaScanner

Shared Swift scanner infrastructure for CocoaSpice, SPCBoy, and future media-player hosts.

Current package products:

- `MediaScannerKit`: versioned scanner types, format-routing policy, incremental inventory selection, cancellation-aware resource scheduling, and dry-run probing.
- `media-scan`: JSONL command-line process boundary used by non-Swift hosts.

## Commands

```bash
swift run media-scan plugins
swift run media-scan probe /path/to/file
swift run media-scan probe --recursive --strict /path/to/folder
```

`probe` never writes a database. Standard output is reserved for versioned JSONL events.

## Build and test

```bash
swift test --disable-sandbox
swift build --disable-sandbox --configuration release --product media-scan
```
