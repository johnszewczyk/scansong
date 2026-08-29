# Build Integration

## Scope

Fresh packaging and runtime assembly for ScanSong's native app bundle and its external inspection
executables.

## Ownership

- VGMBoy owns decoder source, compatibility patches, dependency archives, and scanner-plugin builds.
- VGMBoy's [plugin milestone manifest](/Users/john/Downloads/Code/VGMMan/VGMBoy/Docs/plugin-versions.json)
  and [read-only audit script](/Users/john/Downloads/Code/VGMMan/VGMBoy/scripts/audit-plugin-versions.sh)
  are the source of truth for upstream revision review; ScanSong does not keep a second version list.
- ScanSong depends on VGMBoy's lightweight `VGMBoyFormatCore` and `VGMBoySNDH` products
  for typed format admission; it does not link VGMBoyKit or native decoders.
- `ScanSong/build-app.sh` asks VGMBoy to build the vgmstream CLI, Highly Complete inspector, and MDX inspector,
  then copies those products into the ScanSong bundle.
- `ScanSong/launch.sh` packages a fresh app and refuses to open it while an older ScanSong
  process remains.

## Invariants

- ScanSong never reaches into CocoaSpice, SPCBoy, or a frontend-owned helper path.
- The app bundle contains the VGMBoy-built `vgmstream-cli` and
  `vgmboy-highly-complete-inspect` and `vgmboy-mdx-inspect` products at the paths expected by the scanner adapters.
- `build-app.sh` removes `.build` before a release build so stale scanner binaries cannot survive
  a fresh packaging run.
- A missing inspection executable is a typed adapter failure; the scanner does not invent a row or
  invoke another application as a fallback.

## Failure Boundaries

- Dependency or plugin build failure stops packaging and leaves the previous installed app intact.
- An unavailable staged inspector is reported by the scanner adapter and does not become a player
  launch or permission request.
- SNDH metadata is read through the shared `VGMBoySNDH` product; ScanSong owns only
  route registration and catalog projection, while VGMBoy owns the PSGPlay source,
  C bridge, and staged static library.
- MDX metadata is read through the VGMBoy-built `vgmboy-mdx-inspect` process;
  ScanSong owns only route registration and catalog projection.

## Files

- [build-app.sh](/Users/john/Downloads/Code/VGMMan/ScanSong/build-app.sh)
- [launch.sh](/Users/john/Downloads/Code/VGMMan/ScanSong/launch.sh)
- [ScannerInspectors.swift](/Users/john/Downloads/Code/VGMMan/ScanSong/Sources/ScanSongKit/ScannerInspectors.swift)
- [VGMBoy build integration](/Users/john/Downloads/Code/VGMMan/VGMBoy/ai/subsystem-agent/build-integration.md)
