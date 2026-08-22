# Build Integration

## Scope

Fresh packaging and runtime assembly for ScanSong's native app bundle and its external inspection
executables.

## Ownership

- VGMBoy owns decoder source, compatibility patches, dependency archives, and scanner-plugin builds.
- `MediaScanner/build-app.sh` asks VGMBoy to build the vgmstream CLI and Highly Complete inspector,
  then copies those products into the ScanSong bundle.
- `MediaScanner/launch.sh` packages a fresh app and refuses to open it while an older ScanSong
  process remains.

## Invariants

- ScanSong never reaches into CocoaSpice, SPCBoy, or a frontend-owned helper path.
- The app bundle contains the VGMBoy-built `vgmstream-cli` and
  `vgmboy-highly-complete-inspect` products at the paths expected by the scanner adapters.
- `build-app.sh` removes `.build` before a release build so stale scanner binaries cannot survive
  a fresh packaging run.
- A missing inspection executable is a typed adapter failure; the scanner does not invent a row or
  invoke another application as a fallback.

## Failure Boundaries

- Dependency or plugin build failure stops packaging and leaves the previous installed app intact.
- An unavailable staged inspector is reported by the scanner adapter and does not become a player
  launch or permission request.

## Files

- [build-app.sh](/Users/john/Downloads/Code/MediaScanner/build-app.sh)
- [launch.sh](/Users/john/Downloads/Code/MediaScanner/launch.sh)
- [ScannerInspectors.swift](/Users/john/Downloads/Code/MediaScanner/Sources/MediaScannerKit/ScannerInspectors.swift)
- [VGMBoy build integration](/Users/john/Downloads/Code/VGMBoy/ai/subsystem-agent/build-integration.md)
