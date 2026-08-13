# Project Info

## Product

- `MediaScanner` is the independent Swift package that owns the scanner contract being consumed by CocoaSpice and staged by SPCBoy.
- `MediaScannerKit` owns routing policy, recursive discovery, archive extraction, metadata inspection, schema-23 catalog creation, resumable staging, atomic publication, host-neutral results, and cancellation-aware scheduling.
- `media-scan` exposes the engine through a versioned JSONL command-line protocol.
- `MediaScanner` is the native macOS scanner app for catalog selection,
  persisted-root intake/status, link testing and explicit dead-link purging,
  scan diagnostics, cancellation, and resume.

## Task Routing

- Scanner ownership and protocol: [scanner-contract.md](/Users/john/Downloads/Code/MediaScanner/ai/subsystem-agent/scanner-contract.md)
- Command-line behavior: [cli.md](/Users/john/Downloads/Code/MediaScanner/ai/subsystem-human/cli.md)
