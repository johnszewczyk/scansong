# Command Line

- `scansong plugins` reports registered format routes and policies.
- `scansong probe [--recursive] [--strict] PATH...` examines input without
  writing a catalog.
- `scansong catalog create|validate|roots PATH` creates, checks, or lists a
  canonical catalog.
- `scansong scan [--new] [--permits N] [--archive-limit N] CATALOG ROOT...`
  scans one or more complete roots into the selected catalog. `--permits N`
  bounds concurrent archive-member inspection (default 8) and `--archive-limit
  N` bounds how many sources extract/inspect at once (default 4); tune both on
  large roots. `sessionFinished` reports per-phase millisecond telemetry.
  Console labels are not scanner options; player presentation decides how to
  use path or embedded metadata.
- Output is ordered, versioned JSONL. Scanner failures return nonzero status;
  SIGINT/SIGTERM cancellation returns 130 after retaining checkpoints.
