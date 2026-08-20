# Catalog Management

## Scope

- The MediaScanner app manages a selected schema-23 catalog and its scan paths.

## Catalog

- Database File always shows one selected catalog-file row, or `(None)` when
  that file no longer exists. Its controls open an existing catalog, reset its
  contents with the circular x icon, or permanently delete the file after confirmation. Use Default
  remains below the row.
- Reset empties the catalog, including scan paths, indexed tracks, metadata,
  and scan history; Delete removes the SQLite file. Neither action deletes
  media files.

## Scan Paths

- Each scan path can be enabled or disabled without removing it.
- Every path has Scan, Show Last Scan Log, and Remove controls.
- A path shows its last scan time, physical file count, active playable-track
  count, and issue count.
- Scan All scans enabled paths. An individual path can be scanned without
  enabling it.

## Link Maintenance

- Check Links marks missing or moved sources inactive and removes them from
  the player-visible catalog without deleting their retained records.
- Clean Links permanently removes only inactive catalog entries. It never
  deletes media files.

## Scan Results

- The last-result log has a fixed `status: result: file` layout; the variable
  path is always last. Scan Status is the only in-window summary.
- During a scan, the displayed progress and Current Activity/File Path/File Name
  fields coalesce scanner updates every 250 ms. The scanner itself keeps its
  full-resolution progress callbacks; only SwiftUI presentation is throttled.
- Closing the app while a scan or link-maintenance operation is active presents
  a warning. A scan can be cancelled and closes only after completed checkpoints
  are retained; maintenance closes only after its current database operation.

## Files

- `Sources/MediaScannerApp/MediaScannerApp.swift`
- `Sources/MediaScannerApp/ScannerScanLog.swift`
