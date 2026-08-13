# Scanner Interfaces

## Native App

- `launch.sh` always clean-builds and signs a new app bundle, stops an existing
  MediaScanner process, and opens the exact new bundle.
- New and Browse choose the schema-23 catalog MediaScanner alone may modify;
  persisted attached roots load immediately.
- Add Folders adds complete scan roots. Add Files adds each selected file's
  containing folder as a complete root.
- The leading toolbar checkbox checks or unchecks every root. Remove detaches
  checked roots after confirmation without purging their indexed records.
- Scan reuses validated completed work; Rebuild forces source reinspection and
  every currently available metadata adapter.
- Folders as Metadata selects folder-first console grouping; unchecked uses
  embedded metadata first and still falls back to folders.
- Test Files marks missing physical sources inactive without deleting their
  rows. Clear Dead Links explicitly purges inactive rows after confirmation.
- Grey roots are unscanned, green roots completed cleanly, and yellow roots
  contain failed or inactive sources.
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
