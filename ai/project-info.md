# Project Info

## Product

- `ScanSong` is the independent Swift package and native scanner app; it owns the scanner contract consumed by CocoaSpice and staged by SPCBoy.
- `MediaScannerKit` owns routing policy, recursive discovery, archive extraction, metadata inspection, schema-23 catalog creation, resumable staging, atomic publication, host-neutral results, and cancellation-aware scheduling.
- `media-scan` exposes the engine through a versioned JSONL command-line protocol.
- `ScanSong` is the native macOS scanner app for catalog-file selection,
  persisted-root intake/status, link testing and explicit dead-link purging,
  scan summaries, per-path logs, cancellation, and resume.
- `build-app.sh` packages the native app and installs `app-icon.png` when
  supplied (falling back to the current `app-icon.jpg`) as its runtime icon.
  It obtains both required inspection executables from VGMBoy's scanner-plugin
  build boundary; ScanSong does not reach into CocoaSpice's app or old helper
  paths.

## Task Routing

- Scanner ownership and protocol: [scanner-contract.md](/Users/john/Downloads/Code/MediaScanner/ai/subsystem-agent/scanner-contract.md)
- Command-line behavior: [cli.md](/Users/john/Downloads/Code/MediaScanner/ai/subsystem-human/cli.md)
- Native catalog management: [catalog-management.md](/Users/john/Downloads/Code/MediaScanner/ai/subsystem-human/catalog-management.md)
