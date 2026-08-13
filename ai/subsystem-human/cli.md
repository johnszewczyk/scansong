# Scanner Interfaces

## Native App

- New and Browse choose the schema-23 catalog MediaScanner alone may modify.
- Add Folders adds complete scan roots. Add Files adds each selected file's
  containing folder as a complete root.
- Scan reuses validated completed work; Rebuild forces source reinspection.
- Console Tags selects folder-first or embedded-metadata-first grouping.
- Status shows the active phase, source path, counts, and diagnostics.
- Cancel retains completed source/archive checkpoints for the next Scan.

## Command Line

- `media-scan plugins` reports registered format routes and policies.
- `media-scan probe [--recursive] [--strict] PATH...` examines input without
  writing a catalog.
- `media-scan catalog create|validate|roots PATH` creates, checks, or lists a
  canonical catalog.
- `media-scan scan [--new] [--console-source=folders|metadata] CATALOG ROOT...`
  scans one or more complete roots into the selected catalog.
- Output is ordered, versioned JSONL. Scanner failures return nonzero status;
  SIGINT/SIGTERM cancellation returns 130 after retaining checkpoints.
