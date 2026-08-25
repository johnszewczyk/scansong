# ScanSong plugin ownership

## Historical State (snapshot from 2026-08-23)

This note records the plugin-boundary state at the time of the snapshot. It is
not the current test count or a release-readiness report; use the live ScanSong
test suite and scanner contract for current verification.

- ScanSong is the ScanSong app and remains the catalog writer.
- The Highly Complete inspection executable is now built from `../VGMBoy` as
  `vgmboy-highly-complete-inspect` and copied into the ScanSong bundle as
  `highly-complete-inspect`.
- ScanSong’s vgmstream CLI is built by
  `../VGMBoy/scripts/build-scanner-plugins.sh` and copied from
  `../VGMBoy/.build/scanner-plugins/vgmstream-cli`.
- The QSF inspection executable is built by the same VGMBoy-owned plugin
  builder and bundled as `vgmboy-qsf-inspect`.
- The Highly Complete inspection executable is a VGMBoy SwiftPM product.
- vgmstream admission is sourced from VGMBoy's database-free
  `VGMBoyFormatCore` product. ScanSong owns routing, native inspection,
  archive materialization, and schema-23 publication.
- VGMBoy consumes the shared upstream source garden and builds the static-library inputs;
  CocoaSpice no longer owns a vendor checkout or plugin runtime dependency.

## Current Boundary

- Keep scanner plugin assembly in VGMBoy.
- Keep ScanSong limited to bundling the three executable resources it receives
  from VGMBoy; it must not invoke CocoaSpice build or launch paths.
- Treat a future relocation of the shared upstream vendor checkouts as a
  separate migration requiring validation across CocoaSpice, SPCBoy, and VGMBoy.

## Files

- `build-app.sh`
- `../VGMBoy/scripts/build-scanner-plugins.sh`
- `Sources/ScanSongKit/InspectorProcessRunner.swift`
- `Sources/ScanSongKit/VGMStreamCLIInspector.swift`
- `Sources/ScanSongKit/QSFCLIInspector.swift`
- `Sources/ScanSongKit/HighlyCompleteCLIInspector.swift`
- `../VGMBoy/Package.swift`
- `../VGMBoy/build-app.sh`
- `../VGMBoy/Sources/VGMBoyFormatCore/VGMStreamFormatManifest.swift`

## Refactor completion and verification (2026-08-23)

- TXTP dependency aliasing and duplicate suppression live in
  `TXTPDependencyResolver`; bounded member accounting lives in
  `ArchiveMemberEnumerator`.
- Native inspectors share a 30-second, bounded-output subprocess runner and
  retain separate decoder-family adapters.
- Catalog schema installation and filesystem link auditing are separated from
  the writer's SQLite transaction orchestration.
- VGMBoy native dependencies and scanner plugins are keyed by source revision,
  dirty diff, build scripts, patches, compiler, and CMake version. A complete
  warm dependency pass reused all seven products and packaged copies in 0.6 s.
- At the time of this snapshot, ScanSong passed 25 tests, including the
  archive-backed GameCube inspector timing fixture. Later scanner repairs and
  regression coverage have changed the live test count; its clean app bundle
  and current verification must be assessed separately.
- VGMBoy's archive-backed GameCube playback test opened every admitted fixture
  and rendered non-silent PCM. The separate AAC export test currently fails in
  AudioToolbox with `fmt?` (`1718449215`); do not treat that unrelated failure
  as GameCube or scanner evidence.

## Game Gear / SGC playback boundary (2026-08-23)

The Game Gear failures are currently an intentional unsupported-format result,
not a scanner-only registration bug.

Representative archives such as Chuck Rock, Clutch Hitter, and Cool Spot
contain one `.sgc` Game Gear/SMS music container plus `.m3u` wrappers for its
individual tracks. ScanSong currently has no `.sgc` or `.m3u` intake route.
VGMBoy's active libgme 0.6.5 path also rejects the actual `.sgc` members with
`Wrong file type for this emulator`. Adding `sgc` to an extension set, or
routing it through vgmstream, would therefore advertise playback that does not
exist.

There is no established Game Gear codec in the current VGMBoy decoder set.
Supporting this family later would require an SGC-capable decoder core, a
VGMBoy decoder/metadata adapter, scanner handling for the M3U-to-SGC wrapper,
and complete archive materialization so the sibling container remains
available during playback. Do not spend more investigation time on this
family unless an approved SGC decoder source is selected for integration.
