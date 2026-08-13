# Project Info

## Product

- `MediaScanner` is the independent Swift package that owns the scanner contract being consumed by CocoaSpice and staged by SPCBoy.
- `MediaScannerKit` currently owns routing policy, scan inventory primitives, cancellation-aware resource scheduling, and dry-run probing.
- `media-scan` exposes the engine through a versioned JSONL command-line protocol.

## Task Routing

- Scanner ownership and protocol: [scanner-contract.md](/Users/john/Downloads/Code/MediaScanner/ai/subsystem-agent/scanner-contract.md)
- Command-line behavior: [cli.md](/Users/john/Downloads/Code/MediaScanner/ai/subsystem-human/cli.md)
