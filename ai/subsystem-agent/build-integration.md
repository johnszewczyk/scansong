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
- `ScanSong/build-app.sh` asks VGMBoy to build the vgmstream CLI, MDX inspector, and UADE-backed Amiga inspector,
  then copies those products into the ScanSong bundle.
- `ScanSong/launch.sh` packages a fresh app, asks the older ScanSong process to
  close through `SIGTERM`, and refuses to open it while that process remains.

## Invariants

- ScanSong never reaches into CocoaSpice, SPCBoy, or a frontend-owned helper path.
- The app bundle contains the VGMBoy-built `vgmstream-cli`,
  `vgmboy-mdx-inspect`,
  `vgmboy-amiga-inspect` product at the paths
  expected by the scanner adapters.
- `build-app.sh` removes `.build` before a release build so stale scanner binaries cannot survive
  a fresh packaging run.
- A missing inspection executable is a typed adapter failure; the scanner does not invent a row or
  invoke another application as a fallback. GSF/miniGSF are read in-process by
  ScanSong, as are QSF/miniQSF; neither requires a bundled Highly Complete or
  QSF inspection executable. APE is also read in-process. The shared VGMBoy
  scanner build currently invokes its broad dependency builder, which still
  prepares playback products including mGBA and the QSF core. This is build-time
  collateral only: the direct GSF/QSF/APE scanner routes do not link or execute
  those playback cores. Isolating scanner-only dependency preparation remains
  separate work.

## Failure Boundaries

- Dependency or plugin build failure stops packaging and leaves the previous installed app intact.
- Retiring a running development app is cooperative: `SIGTERM` enters the
  app's termination delegate, and launch waits for the scan/maintenance close
  boundary instead of replacing a live scanner process.
- An unavailable staged inspector is reported by the scanner adapter and does not become a player
  launch or permission request.
- SNDH metadata is read through the shared `VGMBoySNDH` product; ScanSong owns only
  route registration and catalog projection, while VGMBoy owns the PSGPlay source,
  C bridge, and staged static library.
- MDX metadata is read through the VGMBoy-built `vgmboy-mdx-inspect` process;
  ScanSong owns only route registration and catalog projection.
- Amiga metadata is read through the VGMBoy-built `vgmboy-amiga-inspect` process;
  ScanSong owns only prefix admission, archive materialization, and catalog projection.
- APE metadata is read by ScanSong's direct header/tag reader; FFmpeg remains
  in VGMBoy for playback and is not an APE scanner requirement.
- GSF/miniGSF metadata and structure are read by ScanSong's direct PSF/GSF
  parser; Highly Complete/mGBA remains a VGMBoy playback route, not a scanner
  process or runtime link.
- QSF/miniQSF metadata and structure are read by ScanSong's direct PSF/QSound
  parser; AOSDK remains a VGMBoy playback route, not a scanner process.

## Files

- [build-app.sh](/Users/john/Downloads/Code/VGMMan/ScanSong/build-app.sh)
- [launch.sh](/Users/john/Downloads/Code/VGMMan/ScanSong/launch.sh)
- [ScannerInspectors.swift](/Users/john/Downloads/Code/VGMMan/ScanSong/Sources/ScanSongKit/ScannerInspectors.swift)
- [VGMBoy build integration](/Users/john/Downloads/Code/VGMMan/VGMBoy/ai/subsystem-agent/build-integration.md)
