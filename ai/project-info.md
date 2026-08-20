# Project Info

## Product

- `MediaScanner` is the independent Swift package that owns the scanner contract being consumed by CocoaSpice and staged by SPCBoy.
- `MediaScannerKit` owns routing policy, recursive discovery, archive extraction, metadata inspection, schema-23 catalog creation, resumable staging, atomic publication, host-neutral results, and cancellation-aware scheduling.
- `media-scan` exposes the engine through a versioned JSONL command-line protocol.
- `MediaScanner` is the native macOS scanner app for catalog-file selection,
  persisted-root intake/status, link testing and explicit dead-link purging,
  scan summaries, per-path logs, cancellation, and resume.
- `build-app.sh` packages the native app and installs `app-icon.png` when
  supplied (falling back to the current `app-icon.jpg`) as its runtime icon.
  It also bundles the scanner-owned vgmstream and Highly Complete inspection
  executables; the latter is built from the local GPL-compatible mGBA bridge.

## Task Routing

- Scanner ownership and protocol: [scanner-contract.md](/Users/john/Downloads/Code/MediaScanner/ai/subsystem-agent/scanner-contract.md)
- Command-line behavior: [cli.md](/Users/john/Downloads/Code/MediaScanner/ai/subsystem-human/cli.md)
- Native catalog management: [catalog-management.md](/Users/john/Downloads/Code/MediaScanner/ai/subsystem-human/catalog-management.md)
