# Catalog Management

## Scope

- The ScanSong app manages a selected schema-23 catalog and its scan paths.

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
- Remove Links permanently removes only inactive catalog entries. It never
  deletes media files.

## Scan Results

- The last-result log has fixed `status | detail | path` columns. Actual
  archive failures retain the `archive#member` path; successful members are
  never listed, and skipped archive members are grouped by archive and
  extension. Scan Status is the only in-window summary.
- Scanner-owned extraction scratch prefixes are removed from diagnostic details;
  the archive/member path remains the stable identifier.
- During Scan, Check Links, or Remove Links, Scan Status shows only sampled
  aggregate progress and failure counts. Operation callbacks are retained as a
  single latest value and sampled by the UI every 250 ms; no callback can pace
  the worker. CLI JSONL diagnostics are separately rate-limited to
  phase changes, phase completion, or at most one event per second; diagnostic
  output must never become the scan's throughput limiter.
- While active, Scan Status presents a bold `Current Scan` heading followed by
  indented monospaced `Items:` and `Fails:` counters. These aggregate readouts
  disappear when the operation finishes; completion is a compact green checkmark
  row with operation duration and finish time.
- Closing the app while a scan or link-maintenance operation is active presents
  a warning. A scan can be cancelled and closes only after completed checkpoints
  are retained; maintenance closes only after its current database operation.

## Options

- The Options window uses the CocoaSpice split-sidebar layout. Its first sidebar
  section is `File Types`.
- File Types shows checkbox controls for documented decoder-absent extensions.
  Checked types are ignored before discovery and archive-member inspection;
  supported formats remain active so malformed files still appear in the scan
  result and last-result log.
- The ignore selection is persisted in ScanSong preferences. Explicitly ignored
  files are recorded in the post-operation scan log. Archive members without a
  scanner route are grouped as `unrecognized` diagnostics unless they are known
  decoder support files, archive documentation, or extensionless material; none
  become playable candidates.

## Files

- `Sources/ScanSongApp/ScanSongApp.swift`
- `Sources/ScanSongApp/ScannerOptionsView.swift`
- `Sources/ScanSongApp/ScannerScanLog.swift`
