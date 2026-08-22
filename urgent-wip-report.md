# ScanSong plugin ownership

## Current State

- ScanSong is the MediaScanner app and remains the catalog writer.
- The Highly Complete inspection executable is now built from `../VGMBoy` as
  `vgmboy-highly-complete-inspect` and copied into the ScanSong bundle as
  `highly-complete-inspect`.
- ScanSong’s vgmstream CLI is built by
  `../VGMBoy/scripts/build-scanner-plugins.sh` and copied from
  `../VGMBoy/.build/scanner-plugins/vgmstream-cli`.
- The Highly Complete inspection executable is a VGMBoy SwiftPM product.
- VGMBoy still consumes shared upstream static-library inputs produced from
  the existing CocoaSpice vendor checkout; this is a shared-source boundary,
  not a CocoaSpice app/plugin runtime dependency.

## Current Boundary

- Keep scanner plugin assembly in VGMBoy.
- Keep ScanSong limited to bundling the two executable resources it receives
  from VGMBoy; it must not invoke CocoaSpice build or launch paths.
- Treat a future relocation of the shared upstream vendor checkouts as a
  separate migration requiring validation across CocoaSpice, SPCBoy, and VGMBoy.

## Files

- `build-app.sh`
- `../VGMBoy/scripts/build-scanner-plugins.sh`
- `Sources/MediaScannerKit/ScannerInspectors.swift`
- `../VGMBoy/Package.swift`
- `../VGMBoy/build-app.sh`
- `../VGMBoy/Sources/VGMBoyKit/HighlyCompleteInspector.swift`
