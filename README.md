# MediaScanner

Shared Swift scanner infrastructure for CocoaSpice, SPCBoy, and future media-player hosts.

Current package products:

- `MediaScannerKit`: versioned scanner types, host-neutral metadata and result records, format-routing policy, recursive discovery, incremental planning, shared lifecycle/telemetry, archive/decoder plugin protocols, cancellation-aware resource scheduling, and dry-run probing.
- `media-scan`: JSONL command-line process boundary used by non-Swift hosts.
- `MediaScanner`: a small native macOS test application with catalog selection, file/folder intake, live discovery/routing status, diagnostics, and cooperative cancellation.

## Commands

```bash
swift run media-scan plugins
swift run media-scan probe /path/to/file
swift run media-scan probe --recursive --strict /path/to/folder
swift run media-scan catalog validate /path/to/Library.sqlite
```

`probe` never writes a database. `catalog validate` opens the selected SQLite file read-only, requires the canonical CocoaSpice schema version and tables, and reports its root and track counts. Standard output is reserved for versioned JSONL events.

The package is the scanner implementation boundary and canonical catalog owner. The current catalog contract is CocoaSpice schema 23. CocoaSpice and SPCBoy consume the chosen catalog through query-only connections and do not start their legacy scanners or metadata writeback paths. Catalog publication is not implemented in MediaScanner yet, so the safe transitional state has no production writer: the GUI's **Test Scan** performs discovery and routing only and reports that the catalog is unchanged.

## Native app

```bash
./build-app.sh
./launch.sh
```

`build-app.sh` creates an ad-hoc-signed `.build/app/MediaScanner.app`. Choose an existing canonical database to verify the reader contract, add files or folders, then use **Test Scan** to exercise discovery and format routing. Cancel is cooperative during both enumeration and routing.

## Build and test

```bash
swift test --disable-sandbox
swift build --disable-sandbox --configuration release --product media-scan
swift build --disable-sandbox --configuration release --product MediaScanner
```
