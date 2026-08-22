# Project Info

## Product

`ScanSong` is the independent Swift package and native scanner app. `MediaScannerKit` owns
discovery, inspection, archive handling, schema-23 catalog creation, resumable staging, and
publication. The product is the sole catalog writer consumed by CocoaSpice and SPCBoy.

## Major Components

- `MediaScannerKit` — host-independent scanning and catalog engine.
- `media-scan` — versioned JSONL command-line boundary.
- `ScanSong` — native catalog-management interface.
- `build-app.sh` and `launch.sh` — fresh packaging and launch boundary.

## Task Routing

- Scanner ownership and protocol: [scanner-contract.md](/Users/john/Downloads/Code/MediaScanner/ai/subsystem-agent/scanner-contract.md)
- Build and plugin packaging: [build-integration.md](/Users/john/Downloads/Code/MediaScanner/ai/subsystem-agent/build-integration.md)
- Command-line behavior: [cli.md](/Users/john/Downloads/Code/MediaScanner/ai/subsystem-human/cli.md)
- Native catalog management: [catalog-management.md](/Users/john/Downloads/Code/MediaScanner/ai/subsystem-human/catalog-management.md)

## Local Rules

- MediaScanner is the sole schema-23 catalog writer.
- Player apps read the catalog; they do not receive scanner write access.
- ScanSong receives inspection executables from VGMBoy and never invokes a player frontend.
- Human notes describe implemented UI behavior; agent notes describe scanner ownership and failure boundaries.

## Human Docs

- `ai/subsystem-human/` contains the current catalog-management and command-line behavior notes.
- `README.md` contains the user-facing build and scanner overview.
